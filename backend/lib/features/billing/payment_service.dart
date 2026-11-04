import 'package:common_models/common_models.dart';
import 'package:shelf/shelf.dart';

import '../../core/data/document_store.dart';
import '../../core/errors/api_exception.dart';
import '../../core/ids.dart';
import '../clinic/common/tenant_context.dart';
import '../platform/common/body_reader.dart';
import '../platform/common/paging.dart';
import '../scheduling/time_support.dart';
import 'billing_support.dart';
import 'invoice_service.dart';

/// Methods that need the transaction reference (UTR, approval code, cheque
/// number) so the payment can be reconciled against a statement.
const Set<String> _referenceRequired = {
  'upi',
  'card',
  'bank_transfer',
  'cheque',
};

/// Payment collection, allocation to invoices, the patient credit ledger and
/// receipts.
///
/// Payments recorded here are **offline**: staff record money they actually
/// received. A client-reported result is never proof of payment, and no gateway
/// payment can be created until a gateway is configured and approved (see
/// `gateway.dart`).
class PaymentService {
  PaymentService(this._s, this._invoices);

  final BillingSupport _s;
  final InvoiceService _invoices;

  static const String collection = 'payments';

  // ------------------------------------------------------------ helpers

  Future<DocData> loadPayment(
    TenantContext t,
    String id, {
    TxContext? tx,
  }) async {
    final p = _s.path(t, collection, id);
    final pay = tx == null ? await _s.d.store.get(p) : await tx.get(p);
    if (pay == null || !t.scope.allows('${pay['branchId']}')) {
      throw const ApiException.notFound('Payment not found.');
    }
    return pay;
  }

  List<({String invoiceId, int amount})> _allocations(
    BodyReader r,
    Object? raw,
  ) {
    if (raw == null) return const [];
    if (raw is! List || raw.length > 20) {
      r.addIssue('allocations', 'invalid_value', 'Give up to 20 allocations.');
      return const [];
    }
    final out = <({String invoiceId, int amount})>[];
    final seen = <String>{};
    for (var i = 0; i < raw.length; i++) {
      final item = raw[i];
      if (item is! Map) {
        r.addIssue('allocations[$i]', 'invalid_type', 'Must be an object.');
        continue;
      }
      final c = BodyReader(item.cast<String, Object?>())
        ..rejectUnknown({'invoiceId', 'amountMinor'});
      final id = c.str('invoiceId', max: 40);
      final amt = c.integer('amountMinor', min: 1, max: 100000000000);
      for (final x in c.issues) {
        r.addIssue('allocations[$i].${x.field}', x.code, x.message);
      }
      if (id == null || amt == null) continue;
      if (!seen.add(id)) {
        r.addIssue(
          'allocations[$i].invoiceId',
          'duplicate',
          'Each invoice can appear once.',
        );
        continue;
      }
      out.add((invoiceId: id, amount: amt));
    }
    return out;
  }

  // ------------------------------------------------------ credit ledger

  String _balancePath(TenantContext t, String patientId) =>
      _s.path(t, 'patient_credit_balances', patientId);

  WriteOp _setBalance(
    TenantContext t,
    String patientId,
    String branchId,
    bool exists,
    int balance,
  ) {
    final fields = {'balance': balance, 'updatedAt': _s.d.now};
    return exists
        ? UpdateOp(_balancePath(t, patientId), fields)
        : CreateOp(_balancePath(t, patientId), {
            'patientId': patientId,
            'branchId': branchId,
            'tenantId': t.tenantId,
            ...fields,
          });
  }

  /// What is left of a credit source (an "in" ledger entry).
  Future<int> remainingOf(TxContext tx, TenantContext t, DocData source) async {
    final outs = await tx.query(
      DocQuery(
        _s.path(t, 'patient_credit_ledger'),
        filters: [QueryFilter('creditId', FilterOp.eq, source['entryId'])],
        limit: 500,
      ),
    );
    final used = outs.fold<int>(0, (a, e) => a + (e.data['amount']! as int));
    return (source['amount']! as int) - used;
  }

  Map<String, Object?> _ledgerEntry(
    TenantContext t, {
    required String id,
    required String patientId,
    required String branchId,
    required String type,
    required int amount,
    required int balanceAfter,
    required String currency,
    String? creditId,
    String? paymentId,
    String? invoiceId,
    String? allocationId,
    String? reason,
  }) => {
    'entryId': id,
    'tenantId': t.tenantId,
    'patientId': patientId,
    'branchId': branchId,
    'type': type,
    'direction': type.endsWith('_in') ? 'in' : 'out',
    'amount': amount,
    'balanceAfter': balanceAfter,
    'currency': currency,
    'creditId': creditId,
    'sourcePaymentId': paymentId,
    'invoiceId': invoiceId,
    'allocationId': allocationId,
    'reason': reason,
    'createdAt': _s.d.now,
    'createdBy': t.uid,
  }..removeWhere((k, v) => v == null);

  // ------------------------------------------------------------ create

  static const Set<String> _createFields = {
    'patientId',
    'branchId',
    'amountMinor',
    'method',
    'reference',
    'receivedAt',
    'notes',
    'allocations',
    'advance',
  };

  Future<Map<String, Object?>> create(
    TenantContext t,
    Map<String, Object?> body, {
    required String? idempotencyKey,
    String? requestId,
    bool advanceOnly = false,
  }) async {
    t.require(
      advanceOnly
          ? ClinicPermission.paymentRecordAdvance
          : ClinicPermission.paymentCollect,
    );
    final idem = _s.idem(
      t,
      advanceOnly ? 'credit' : 'payment',
      idempotencyKey,
      body,
    );
    final r = BodyReader(body)..rejectUnknown(_createFields);
    final patientId = r.str('patientId', max: 40);
    final branchId = r.str('branchId', max: 40);
    final amount = _s.amount(r, 'amountMinor');
    final methods = await _s.allowedMethods(t);
    final method = r.str('method', max: 30);
    if (method != null && !methods.contains(method)) {
      r.addIssue(
        'method',
        'unsupported',
        'Use one of: ${methods.join(', ')}. Online payments are not available yet.',
      );
    }
    final reference = r.str('reference', max: 100, required: false);
    if (method != null &&
        _referenceRequired.contains(method) &&
        reference == null) {
      r.addIssue('reference', 'required', 'Enter the transaction reference.');
    }
    final notes = r.str('notes', max: 500, required: false);
    final advance = r.boolean('advance') ?? advanceOnly;
    final allocations = advanceOnly
        ? const <({String invoiceId, int amount})>[]
        : _allocations(r, r.body['allocations']);
    if (advanceOnly && r.has('allocations')) {
      r.addIssue(
        'allocations',
        'not_allowed',
        'An advance has no allocations.',
      );
    }
    final now = _s.d.now;
    DateTime receivedAt = now;
    if (r.has('receivedAt')) {
      final v = r.body['receivedAt'] is String
          ? DateTime.tryParse(r.body['receivedAt']! as String)
          : null;
      if (v == null ||
          v.toUtc().isAfter(now.add(const Duration(minutes: 5))) ||
          v.toUtc().isBefore(now.subtract(const Duration(days: 31)))) {
        r.addIssue(
          'receivedAt',
          'invalid_date',
          'Give a time within the last 31 days, not in the future.',
        );
      } else {
        receivedAt = v.toUtc();
      }
    }
    final allocated = allocations.fold<int>(0, (a, b) => a + b.amount);
    if (allocated > amount) {
      r.addIssue(
        'allocations',
        'exceeds_payment',
        'Allocations are more than the amount received.',
      );
    }
    final remainder = amount - allocated;
    if (remainder > 0 && !advance) {
      r.addIssue(
        'allocations',
        'unallocated',
        'Allocate the full amount to invoices or mark the remainder as an advance.',
      );
    }
    r.throwIfInvalid();
    if (allocations.isNotEmpty) t.require(ClinicPermission.paymentAllocate);
    if (remainder > 0) t.require(ClinicPermission.paymentRecordAdvance);

    final patient = await _s.patients.load(t, patientId!);
    if (patient['status'] != 'active') {
      throw const ApiException.conflict('The patient record is not active.');
    }
    final branch = await _s.branch(t, branchId!);
    final currency = await _s.currency(t);
    final payId = 'pay_${newId(length: 14)}';
    final recId = 'rct_${newId(length: 14)}';
    final clinic = await _clinicSnapshot(t, branch);

    return _s.d.store.transaction((tx) async {
      final prior = await _s.priorIn(tx, idem);
      if (prior != null) {
        return {
          ...await detail(t, '${prior['resourceId']}'),
          'idempotentReplay': true,
        };
      }
      final ops = <WriteOp>[];
      final receiptLines = <Map<String, Object?>>[];
      final allocDocs = <Map<String, Object?>>[];
      for (final a in allocations) {
        final inv = await _invoices.load(t, a.invoiceId, tx: tx);
        if (inv['patientId'] != patientId) {
          throw const ApiException.notFound('Invoice not found.');
        }
        if (!InvoiceService.acceptsPayment(inv)) {
          throw ApiException.conflict(
            'Invoice ${inv['invoiceNumber'] ?? a.invoiceId} has nothing outstanding or cannot take payments.',
          );
        }
        final due = inv['outstanding']! as int;
        if (a.amount > due) {
          throw ApiException.conflict(
            'Invoice ${inv['invoiceNumber']} has only $due outstanding; '
            'the extra must be an advance.',
          );
        }
        final patch = _invoices.balancePatch(inv, paid: a.amount)
          ..['updatedBy'] = t.uid;
        final allocId = '${payId}_${a.invoiceId}';
        final doc = <String, Object?>{
          'allocationId': allocId,
          'tenantId': t.tenantId,
          'branchId': inv['branchId'],
          'paymentId': payId,
          'invoiceId': a.invoiceId,
          'invoiceNumber': inv['invoiceNumber'],
          'patientId': patientId,
          'amount': a.amount,
          'currency': currency,
          'source': 'payment',
          'createdAt': now,
          'createdBy': t.uid,
        };
        allocDocs.add(doc);
        ops
          ..add(CreateOp(_s.path(t, 'payment_allocations', allocId), doc))
          ..add(
            UpdateOp(_s.path(t, InvoiceService.collection, a.invoiceId), patch),
          );
        receiptLines.add({
          'invoiceId': a.invoiceId,
          'invoiceNumber': inv['invoiceNumber'],
          'amount': a.amount,
          'outstandingAfter': patch['outstanding'],
        });
      }

      String? creditId;
      if (remainder > 0) {
        final balDoc = await tx.get(_balancePath(t, patientId));
        final bal = (balDoc?['balance'] as int?) ?? 0;
        creditId = 'cr_$payId';
        ops
          ..add(
            CreateOp(
              _s.path(t, 'patient_credit_ledger', creditId),
              _ledgerEntry(
                t,
                id: creditId,
                patientId: patientId,
                branchId: branchId,
                type: 'advance_in',
                amount: remainder,
                balanceAfter: bal + remainder,
                currency: currency,
                paymentId: payId,
              ),
            ),
          )
          ..add(
            _setBalance(
              t,
              patientId,
              branchId,
              balDoc != null,
              bal + remainder,
            ),
          );
      }

      final number = await _s.nextNumber(
        tx,
        t,
        ops,
        counter: 'receipt_number',
        prefix: 'RCT',
        keys: 'receipt_numbers',
        ownerId: recId,
        ownerField: 'receiptId',
      );
      final receipt = <String, Object?>{
        'receiptId': recId,
        'tenantId': t.tenantId,
        'branchId': branchId,
        'receiptNumber': number,
        'paymentId': payId,
        'patientId': patientId,
        'patientName': patient['fullName'],
        'patientMrn': patient['mrn'],
        'amount': amount,
        'currency': currency,
        'method': method,
        'reference': reference,
        'receivedAt': receivedAt,
        'receivedBy': t.uid,
        'receivedByRole': t.actorLabel,
        'invoices': receiptLines,
        'advanceAmount': remainder,
        'clinic': clinic,
        'issuedAt': now,
      };
      final payment = <String, Object?>{
        'paymentId': payId,
        'tenantId': t.tenantId,
        'branchId': branchId,
        'patientId': patientId,
        'patientName': patient['fullName'],
        'patientMrn': patient['mrn'],
        'amount': amount,
        'currency': currency,
        'method': method,
        'reference': reference,
        'receivedAt': receivedAt,
        'receivedBy': t.uid,
        'receivedByRole': t.actorLabel,
        'status': 'completed',
        'source': 'offline',
        'allocatedTotal': allocated,
        'advanceAmount': remainder,
        'creditId': creditId,
        'receiptId': recId,
        'receiptNumber': number,
        'refundedTotal': 0,
        'notes': notes,
        'createdAt': now,
        'createdBy': t.uid,
      }..removeWhere((k, v) => v == null);
      ops
        ..add(CreateOp(_s.path(t, collection, payId), payment))
        ..add(CreateOp(_s.path(t, 'receipts', recId), receipt))
        ..add(_s.record(idem, 'payment', payId))
        ..add(
          _s.audit(
            t,
            action: remainder > 0 && allocated == 0
                ? 'payment.advance_recorded'
                : 'payment.collected',
            resourceType: 'payment',
            resourceId: payId,
            branchId: branchId,
            patientId: patientId,
            amount: amount,
            requestId: requestId,
            after: {
              'method': method,
              'allocated': allocated,
              'advance': remainder,
              'receipt': number,
            },
          ),
        );
      tx.write(ops);
      return {
        ...BillingSupport.present(payment),
        'receipt': BillingSupport.present(receipt),
        'allocations': [for (final a in allocDocs) BillingSupport.present(a)],
      };
    });
  }

  Future<Map<String, Object?>> _clinicSnapshot(
    TenantContext t,
    DocData branch,
  ) async {
    final tenant = await _s.d.store.get('tenants/${t.tenantId}');
    final profile = await _s.d.store.get(
      _s.path(t, 'clinic_settings', 'profile'),
    );
    return {
      'name': profile?['name'] ?? tenant?['clinicName'],
      'address': branch['address'] ?? profile?['address'],
      'phone': branch['phone'] ?? profile?['phone'],
      'email': profile?['email'],
      'branchName': branch['name'],
    };
  }

  // ------------------------------------------------------------- reads

  Future<Map<String, Object?>> detail(TenantContext t, String id) async {
    t.require(ClinicPermission.paymentView);
    final pay = await loadPayment(t, id);
    final alloc = await _s.d.store.query(
      DocQuery(
        _s.path(t, 'payment_allocations'),
        filters: [QueryFilter('paymentId', FilterOp.eq, id)],
        limit: 200,
      ),
    );
    final refunds = await _s.d.store.query(
      DocQuery(
        _s.path(t, 'refunds'),
        filters: [QueryFilter('paymentId', FilterOp.eq, id)],
        limit: 100,
      ),
    );
    return {
      ...BillingSupport.present(pay),
      'allocations': [for (final a in alloc) BillingSupport.present(a.data)],
      'refunds': [
        for (final f in refunds)
          {
            'refundId': f.data['refundId'],
            'amount': f.data['amount'],
            'status': f.data['status'],
          },
      ],
    };
  }

  Future<Paged> list(
    TenantContext t,
    Request req, {
    String? patientId,
    String? branchId,
    String? method,
    String? from,
    String? to,
  }) async {
    t.require(ClinicPermission.paymentView);
    final zone = await _s.zone(t);
    DateTime? lo;
    DateTime? hi;
    if (from != null) {
      if (!Dates.valid(from)) {
        throw const ApiException.badRequest('from must be YYYY-MM-DD.');
      }
      lo = zone.toUtc(from, 0);
    }
    if (to != null) {
      if (!Dates.valid(to)) {
        throw const ApiException.badRequest('to must be YYYY-MM-DD.');
      }
      hi = zone.toUtc(Dates.addDays(to, 1), 0);
    }
    return runPaged(
      _s.d.store,
      DocQuery(
        _s.path(t, collection),
        filters: [
          ..._s.scopeFilters(t, branchId),
          if (patientId != null)
            QueryFilter('patientId', FilterOp.eq, patientId),
          if (method != null) QueryFilter('method', FilterOp.eq, method),
          if (lo != null) QueryFilter('receivedAt', FilterOp.gte, lo),
          if (hi != null) QueryFilter('receivedAt', FilterOp.lt, hi),
        ],
        orderBy: const OrderBy('receivedAt', descending: true),
      ),
      req,
    );
  }

  // --------------------------------------------------- credit endpoints

  /// Advance collection (`kind: advance`) or a reasoned ledger adjustment
  /// (`kind: adjustment`).
  Future<Map<String, Object?>> createCredit(
    TenantContext t,
    Map<String, Object?> body, {
    required String? idempotencyKey,
    String? requestId,
  }) async {
    final kind = body['kind'];
    final rest = {...body}..remove('kind');
    if (kind == 'adjustment') {
      return _adjustCredit(
        t,
        rest,
        idempotencyKey: idempotencyKey,
        requestId: requestId,
      );
    }
    if (kind != 'advance') {
      throw ApiException.validation([
        billingIssue(
          'kind',
          'invalid_value',
          'kind must be advance or adjustment.',
        ),
      ]);
    }
    return create(
      t,
      {...rest, 'advance': true},
      idempotencyKey: idempotencyKey,
      requestId: requestId,
      advanceOnly: true,
    );
  }

  Future<Map<String, Object?>> _adjustCredit(
    TenantContext t,
    Map<String, Object?> body, {
    required String? idempotencyKey,
    String? requestId,
  }) async {
    t.require(ClinicPermission.billingAdjust);
    final idem = _s.idem(t, 'credit_adjust', idempotencyKey, body);
    final r = BodyReader(body)
      ..rejectUnknown({
        'patientId',
        'branchId',
        'direction',
        'amountMinor',
        'reason',
        'creditId',
      });
    final patientId = r.str('patientId', max: 40);
    final branchId = r.str('branchId', max: 40);
    final dir = r.enumOf<String>('direction', const ['in', 'out'], (v) => v);
    final amount = _s.amount(r, 'amountMinor');
    final reason = r.str('reason', min: 5, max: 300);
    final creditId = r.str('creditId', max: 60, required: false);
    if (dir == 'out' && creditId == null) {
      r.addIssue('creditId', 'required', 'Name the credit to reduce.');
    }
    r.throwIfInvalid();
    await _s.patients.load(t, patientId!);
    await _s.branch(t, branchId!);
    final currency = await _s.currency(t);
    final id = 'le_${newId(length: 14)}';
    return _s.d.store.transaction((tx) async {
      final prior = await _s.priorIn(tx, idem);
      if (prior != null) {
        return {'entryId': prior['resourceId'], 'idempotentReplay': true};
      }
      final balDoc = await tx.get(_balancePath(t, patientId));
      final bal = (balDoc?['balance'] as int?) ?? 0;
      if (dir == 'out') {
        final src = await tx.get(
          _s.path(t, 'patient_credit_ledger', creditId!),
        );
        if (src == null ||
            src['patientId'] != patientId ||
            src['direction'] != 'in') {
          throw const ApiException.notFound('Credit not found.');
        }
        if (amount > await remainingOf(tx, t, src)) {
          throw const ApiException.conflict(
            'That is more than the credit has left.',
          );
        }
      }
      final next = dir == 'in' ? bal + amount : bal - amount;
      if (next < 0) {
        throw const ApiException.conflict(
          'The credit balance cannot go below zero.',
        );
      }
      final entry = _ledgerEntry(
        t,
        id: id,
        patientId: patientId,
        branchId: branchId,
        type: dir == 'in' ? 'adjustment_in' : 'adjustment_out',
        amount: amount,
        balanceAfter: next,
        currency: currency,
        creditId: dir == 'out' ? creditId : null,
        reason: reason,
      );
      tx.write([
        CreateOp(_s.path(t, 'patient_credit_ledger', id), entry),
        _setBalance(t, patientId, branchId, balDoc != null, next),
        _s.record(idem, 'credit_entry', id),
        _s.audit(
          t,
          action: 'credit.adjusted',
          resourceType: 'credit',
          resourceId: id,
          branchId: branchId,
          patientId: patientId,
          amount: amount,
          reason: reason,
          requestId: requestId,
          after: {'direction': dir, 'balanceAfter': next},
        ),
      ]);
      return BillingSupport.present(entry);
    });
  }

  /// Applies credit to invoices. [creditId] is the "in" ledger entry.
  Future<Map<String, Object?>> allocateCredit(
    TenantContext t,
    String creditId,
    Map<String, Object?> body, {
    required String? idempotencyKey,
    String? requestId,
  }) async {
    t.require(ClinicPermission.paymentAllocate);
    final idem = _s.idem(t, 'credit_apply:$creditId', idempotencyKey, body);
    final r = BodyReader(body)..rejectUnknown({'allocations'});
    final allocations = _allocations(r, r.body['allocations']);
    if (allocations.isEmpty) {
      r.addIssue('allocations', 'required', 'Give at least one invoice.');
    }
    r.throwIfInvalid();
    final now = _s.d.now;
    final currency = await _s.currency(t);
    return _s.d.store.transaction((tx) async {
      final prior = await _s.priorIn(tx, idem);
      if (prior != null) {
        return {'creditId': creditId, 'idempotentReplay': true};
      }
      final src = await tx.get(_s.path(t, 'patient_credit_ledger', creditId));
      if (src == null ||
          src['direction'] != 'in' ||
          !t.scope.allows('${src['branchId']}')) {
        throw const ApiException.notFound('Credit not found.');
      }
      final patientId = '${src['patientId']}';
      final remaining = await remainingOf(tx, t, src);
      final total = allocations.fold<int>(0, (a, b) => a + b.amount);
      if (total > remaining) {
        throw ApiException.conflict('This credit has only $remaining left.');
      }
      final balDoc = await tx.get(_balancePath(t, patientId));
      var bal = (balDoc?['balance'] as int?) ?? 0;
      final ops = <WriteOp>[];
      final applied = <Map<String, Object?>>[];
      for (final a in allocations) {
        final inv = await _invoices.load(t, a.invoiceId, tx: tx);
        if (inv['patientId'] != patientId) {
          throw const ApiException.notFound('Invoice not found.');
        }
        if (!InvoiceService.acceptsPayment(inv)) {
          throw ApiException.conflict(
            'Invoice ${inv['invoiceNumber'] ?? a.invoiceId} has nothing outstanding or cannot take payments.',
          );
        }
        if (a.amount > (inv['outstanding']! as int)) {
          throw ApiException.conflict(
            'Invoice ${inv['invoiceNumber']} has only ${inv['outstanding']} outstanding.',
          );
        }
        bal -= a.amount;
        final allocId = 'al_${newId(length: 14)}';
        final entryId = 'le_${newId(length: 14)}';
        final doc = <String, Object?>{
          'allocationId': allocId,
          'tenantId': t.tenantId,
          'branchId': inv['branchId'],
          'paymentId': src['sourcePaymentId'],
          'creditId': creditId,
          'invoiceId': a.invoiceId,
          'invoiceNumber': inv['invoiceNumber'],
          'patientId': patientId,
          'amount': a.amount,
          'currency': currency,
          'source': 'credit',
          'createdAt': now,
          'createdBy': t.uid,
        }..removeWhere((k, v) => v == null);
        final patch = _invoices.balancePatch(inv, paid: a.amount)
          ..['updatedBy'] = t.uid;
        ops
          ..add(CreateOp(_s.path(t, 'payment_allocations', allocId), doc))
          ..add(
            UpdateOp(_s.path(t, InvoiceService.collection, a.invoiceId), patch),
          )
          ..add(
            CreateOp(
              _s.path(t, 'patient_credit_ledger', entryId),
              _ledgerEntry(
                t,
                id: entryId,
                patientId: patientId,
                branchId: '${src['branchId']}',
                type: 'applied',
                amount: a.amount,
                balanceAfter: bal,
                currency: currency,
                creditId: creditId,
                paymentId: src['sourcePaymentId'] as String?,
                invoiceId: a.invoiceId,
                allocationId: allocId,
              ),
            ),
          );
        applied.add(BillingSupport.present(doc));
      }
      ops
        ..add(
          _setBalance(t, patientId, '${src['branchId']}', balDoc != null, bal),
        )
        ..add(_s.record(idem, 'credit_apply', creditId))
        ..add(
          _s.audit(
            t,
            action: 'credit.applied',
            resourceType: 'credit',
            resourceId: creditId,
            branchId: '${src['branchId']}',
            patientId: patientId,
            amount: total,
            requestId: requestId,
            after: {'invoices': allocations.length, 'balanceAfter': bal},
          ),
        );
      tx.write(ops);
      return {
        'creditId': creditId,
        'applied': applied,
        'remaining': remaining - total,
        'balance': bal,
      };
    });
  }

  /// `POST /payments/{id}/allocations`: applies what is left of this payment's
  /// advance to invoices.
  Future<Map<String, Object?>> allocatePayment(
    TenantContext t,
    String paymentId,
    Map<String, Object?> body, {
    required String? idempotencyKey,
    String? requestId,
  }) async {
    t.require(ClinicPermission.paymentAllocate);
    final pay = await loadPayment(t, paymentId);
    final creditId = pay['creditId'] as String?;
    if (creditId == null) {
      throw const ApiException.conflict(
        'This payment has no unallocated amount left to apply.',
      );
    }
    return allocateCredit(
      t,
      creditId,
      body,
      idempotencyKey: idempotencyKey,
      requestId: requestId,
    );
  }

  Future<Map<String, Object?>> credits(
    TenantContext t,
    String patientId,
  ) async {
    t.require(ClinicPermission.paymentView);
    await _s.patients.load(t, patientId);
    final bal = await _s.d.store.get(
      _s.path(t, 'patient_credit_balances', patientId),
    );
    final rows = await _s.d.store.query(
      DocQuery(
        _s.path(t, 'patient_credit_ledger'),
        filters: [QueryFilter('patientId', FilterOp.eq, patientId)],
        limit: 500,
      ),
    );
    final entries = [for (final r in rows) r.data]
      ..sort(
        (a, b) => (b['createdAt']! as DateTime).compareTo(
          a['createdAt']! as DateTime,
        ),
      );
    final used = <String, int>{};
    for (final e in entries) {
      final c = e['creditId'] as String?;
      if (c != null) used[c] = (used[c] ?? 0) + (e['amount']! as int);
    }
    return {
      'patientId': patientId,
      'currency': await _s.currency(t),
      'balance': (bal?['balance'] as int?) ?? 0,
      'sources': [
        for (final e in entries)
          if (e['direction'] == 'in' &&
              (e['amount']! as int) - (used['${e['entryId']}'] ?? 0) > 0)
            {
              ...BillingSupport.present(e),
              'remaining':
                  (e['amount']! as int) - (used['${e['entryId']}'] ?? 0),
            },
      ],
      'ledger': [for (final e in entries) BillingSupport.present(e)],
    };
  }

  // ---------------------------------------------------------- receipts

  Future<Map<String, Object?>> receipt(
    TenantContext t,
    String receiptId, {
    String? requestId,
  }) async {
    t.require(ClinicPermission.paymentView);
    final rc = await _s.d.store.get(_s.path(t, 'receipts', receiptId));
    if (rc == null || !t.scope.allows('${rc['branchId']}')) {
      throw const ApiException.notFound('Receipt not found.');
    }
    return _presentReceipt(t, rc, requestId);
  }

  Future<Map<String, Object?>> receiptOfPayment(
    TenantContext t,
    String paymentId, {
    String? requestId,
  }) async {
    t.require(ClinicPermission.paymentView);
    final pay = await loadPayment(t, paymentId);
    final rc = await _s.d.store.get(
      _s.path(t, 'receipts', '${pay['receiptId']}'),
    );
    if (rc == null) throw const ApiException.notFound('Receipt not found.');
    return _presentReceipt(t, rc, requestId);
  }

  /// Reading a receipt never creates or changes a payment; the read is
  /// audited so re-downloads are traceable.
  Future<Map<String, Object?>> _presentReceipt(
    TenantContext t,
    DocData rc,
    String? requestId,
  ) async {
    // The balance printed on the receipt is the patient's current total due.
    final due = await _outstandingOf(t, '${rc['patientId']}', rc);
    await _s.d.store.commit([
      _s.audit(
        t,
        action: 'receipt.viewed',
        resourceType: 'receipt',
        resourceId: '${rc['receiptId']}',
        branchId: '${rc['branchId']}',
        patientId: '${rc['patientId']}',
        requestId: requestId,
      ),
    ]);
    return {...BillingSupport.present(rc), 'patientOutstandingNow': due};
  }

  Future<int> _outstandingOf(
    TenantContext t,
    String patientId,
    DocData rc,
  ) async {
    final rows = await _s.d.store.query(
      DocQuery(
        _s.path(t, InvoiceService.collection),
        filters: [QueryFilter('patientId', FilterOp.eq, patientId)],
        limit: 500,
      ),
    );
    return rows.fold<int>(
      0,
      (a, r) =>
          a +
          (r.data['status'] == 'cancelled' || r.data['status'] == 'draft'
              ? 0
              : (r.data['outstanding'] as int?) ?? 0),
    );
  }
}
