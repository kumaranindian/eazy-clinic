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
import 'payment_service.dart';

const List<String> refundStatuses = [
  'requested',
  'approved',
  'rejected',
  'processing',
  'completed',
  'failed',
];

/// Statuses that hold part of the payment (so it cannot be refunded twice). A
/// failed refund keeps holding its amount because it can be retried; rejecting
/// it abandons it and releases the amount.
const Set<String> _holding = {
  'requested',
  'approved',
  'processing',
  'failed',
  'completed',
};

/// Refunds reference a completed payment and never change it. Money moves only
/// at `completed`; every decision is audited and failed attempts are kept.
class RefundService {
  RefundService(this._s, this._invoices, this._payments);

  final BillingSupport _s;
  final InvoiceService _invoices;
  final PaymentService _payments;

  static const String collection = 'refunds';

  Future<DocData> load(TenantContext t, String id, {TxContext? tx}) async {
    final p = _s.path(t, collection, id);
    final f = tx == null ? await _s.d.store.get(p) : await tx.get(p);
    if (f == null || !t.scope.allows('${f['branchId']}')) {
      throw const ApiException.notFound('Refund not found.');
    }
    return f;
  }

  Map<String, Object?> _event(TenantContext t, String status, {String? note}) =>
      {
        'status': status,
        'by': t.uid,
        'role': t.actorLabel,
        'at': _s.d.now,
        'note': note,
      }..removeWhere((k, v) => v == null);

  List<Object?> _history(DocData f, Map<String, Object?> e) => [
    ...((f['history'] as List?) ?? const []),
    e,
  ];

  // ------------------------------------------------------------ request

  Future<Map<String, Object?>> request(
    TenantContext t,
    Map<String, Object?> body, {
    required String? idempotencyKey,
    String? requestId,
  }) async {
    t.require(ClinicPermission.refundRequest);
    final idem = _s.idem(t, 'refund', idempotencyKey, body);
    final r = BodyReader(body)
      ..rejectUnknown({'paymentId', 'invoiceId', 'amountMinor', 'reason'});
    final paymentId = r.str('paymentId', max: 40);
    final invoiceId = r.str('invoiceId', max: 40, required: false);
    final amount = _s.amount(r, 'amountMinor');
    final reason = r.str('reason', min: 5, max: 300);
    r.throwIfInvalid();
    final id = 'rf_${newId(length: 14)}';
    final now = _s.d.now;
    return _s.d.store.transaction((tx) async {
      final prior = await _s.priorIn(tx, idem);
      if (prior != null) {
        return {
          ...BillingSupport.present(await load(t, '${prior['resourceId']}')),
          'idempotentReplay': true,
        };
      }
      final pay = await _payments.loadPayment(t, paymentId!, tx: tx);
      if (pay['status'] != 'completed') {
        throw const ApiException.conflict(
          'Only a completed payment can be refunded.',
        );
      }
      if (pay['source'] != 'offline' && pay['source'] != 'gateway') {
        throw const ApiException.conflict('This payment cannot be refunded.');
      }
      final existing = await tx.query(
        DocQuery(
          _s.path(t, collection),
          filters: [QueryFilter('paymentId', FilterOp.eq, paymentId)],
          limit: 200,
        ),
      );
      int held(String? inv) => existing
          .where(
            (f) =>
                _holding.contains(f.data['status']) &&
                f.data['invoiceId'] == inv,
          )
          .fold<int>(0, (a, f) => a + (f.data['amount']! as int));
      int eligible;
      String? invoiceNumber;
      if (invoiceId != null) {
        final allocs = await tx.query(
          DocQuery(
            _s.path(t, 'payment_allocations'),
            filters: [
              QueryFilter('paymentId', FilterOp.eq, paymentId),
              QueryFilter('invoiceId', FilterOp.eq, invoiceId),
            ],
            limit: 200,
          ),
        );
        if (allocs.isEmpty) {
          throw const ApiException.notFound(
            'That payment was not applied to this invoice.',
          );
        }
        invoiceNumber = allocs.first.data['invoiceNumber'] as String?;
        final applied = allocs.fold<int>(
          0,
          (a, f) => a + (f.data['amount']! as int),
        );
        eligible = applied - held(invoiceId);
      } else {
        final creditId = pay['creditId'] as String?;
        if (creditId == null) {
          throw const ApiException.conflict(
            'This payment has no unapplied advance. Name the invoice to refund.',
          );
        }
        final src = await tx.get(_s.path(t, 'patient_credit_ledger', creditId));
        eligible = (await _payments.remainingOf(tx, t, src!)) - held(null);
      }
      if (amount > eligible) {
        throw ApiException.conflict(
          eligible <= 0
              ? 'Nothing is left to refund on this payment.'
              : 'Only $eligible can still be refunded on this payment.',
        );
      }
      final doc = <String, Object?>{
        'refundId': id,
        'tenantId': t.tenantId,
        'branchId': pay['branchId'],
        'paymentId': paymentId,
        'paymentReceipt': pay['receiptNumber'],
        'invoiceId': invoiceId,
        'invoiceNumber': invoiceNumber,
        'patientId': pay['patientId'],
        'patientName': pay['patientName'],
        'amount': amount,
        'currency': pay['currency'],
        'reason': reason,
        'status': 'requested',
        'attempts': 0,
        'requestedBy': t.uid,
        'requestedByRole': t.actorLabel,
        'requestedAt': now,
        'history': [_event(t, 'requested')],
        'updatedAt': now,
      }..removeWhere((k, v) => v == null);
      tx.write([
        CreateOp(_s.path(t, collection, id), doc),
        _s.record(idem, 'refund', id),
        _s.audit(
          t,
          action: 'refund.requested',
          resourceType: 'refund',
          resourceId: id,
          branchId: '${pay['branchId']}',
          patientId: '${pay['patientId']}',
          invoiceId: invoiceId,
          amount: amount,
          reason: reason,
          requestId: requestId,
          after: {'paymentId': paymentId},
        ),
      ]);
      return BillingSupport.present(doc);
    });
  }

  // ----------------------------------------------------------- decisions

  Future<Map<String, Object?>> approve(
    TenantContext t,
    String id,
    Map<String, Object?> body, {
    String? requestId,
  }) async {
    t.require(ClinicPermission.refundApprove);
    final r = BodyReader(body)..rejectUnknown({'notes'});
    final notes = r.str('notes', max: 300, required: false);
    r.throwIfInvalid();
    final settings = await _s.settings(t);
    return _s.d.store.transaction((tx) async {
      final f = await load(t, id, tx: tx);
      if (f['status'] == 'approved') {
        return {...BillingSupport.present(f), 'idempotentReplay': true};
      }
      if (f['status'] != 'requested') {
        throw ApiException.conflict(
          'A ${f['status']} refund cannot be approved.',
        );
      }
      if (f['requestedBy'] == t.uid && settings['allowSelfApproval'] != true) {
        throw const ApiException.forbidden(
          'You cannot approve a refund you requested.',
        );
      }
      final patch = {
        'status': 'approved',
        'approvedBy': t.uid,
        'approvedAt': _s.d.now,
        'history': _history(f, _event(t, 'approved', note: notes)),
        'updatedAt': _s.d.now,
      };
      tx.write([
        UpdateOp(_s.path(t, collection, id), patch),
        _s.audit(
          t,
          action: 'refund.approved',
          resourceType: 'refund',
          resourceId: id,
          branchId: '${f['branchId']}',
          patientId: '${f['patientId']}',
          amount: f['amount'] as int,
          requestId: requestId,
        ),
      ]);
      return BillingSupport.present({...f, ...patch});
    });
  }

  Future<Map<String, Object?>> reject(
    TenantContext t,
    String id,
    Map<String, Object?> body, {
    String? requestId,
  }) async {
    t.require(ClinicPermission.refundApprove);
    final r = BodyReader(body)..rejectUnknown({'reason'});
    final reason = r.str('reason', min: 5, max: 300);
    r.throwIfInvalid();
    return _s.d.store.transaction((tx) async {
      final f = await load(t, id, tx: tx);
      if (f['status'] == 'rejected') {
        return {...BillingSupport.present(f), 'idempotentReplay': true};
      }
      if (!const {'requested', 'approved', 'failed'}.contains(f['status'])) {
        throw ApiException.conflict(
          'A ${f['status']} refund cannot be rejected.',
        );
      }
      final patch = {
        'status': 'rejected',
        'rejectedBy': t.uid,
        'rejectedAt': _s.d.now,
        'rejectReason': reason,
        'history': _history(f, _event(t, 'rejected', note: reason)),
        'updatedAt': _s.d.now,
      };
      tx.write([
        UpdateOp(_s.path(t, collection, id), patch),
        _s.audit(
          t,
          action: 'refund.rejected',
          resourceType: 'refund',
          resourceId: id,
          branchId: '${f['branchId']}',
          patientId: '${f['patientId']}',
          amount: f['amount'] as int,
          reason: reason,
          requestId: requestId,
        ),
      ]);
      return BillingSupport.present({...f, ...patch});
    });
  }

  /// Records what happened when the money was actually paid back.
  Future<Map<String, Object?>> complete(
    TenantContext t,
    String id,
    Map<String, Object?> body, {
    String? requestId,

    /// Set by the gateway service when the provider executed the refund.
    bool viaGateway = false,
  }) async {
    t.require(ClinicPermission.refundProcess);
    final r = BodyReader(body)
      ..rejectUnknown({
        'outcome',
        'method',
        'reference',
        'notes',
        'failureReason',
      });
    final outcome = r.enumOf<String>('outcome', const [
      'completed',
      'processing',
      'failed',
    ], (v) => v);
    final methods = await _s.allowedMethods(t);
    final method = r.str('method', max: 30, required: outcome != 'failed');
    if (viaGateway) {
      if (method != 'online') {
        r.addIssue('method', 'unsupported', 'Gateway refunds are online.');
      }
    } else if (method != null && !methods.contains(method)) {
      r.addIssue('method', 'unsupported', 'Use one of: ${methods.join(', ')}.');
    }
    final reference = r.str('reference', max: 100, required: false);
    if (outcome == 'completed' &&
        method != null &&
        method != 'cash' &&
        reference == null) {
      r.addIssue('reference', 'required', 'Enter the transaction reference.');
    }
    final notes = r.str('notes', max: 300, required: false);
    final failure = r.str(
      'failureReason',
      min: 3,
      max: 300,
      required: outcome == 'failed',
    );
    r.throwIfInvalid();
    final now = _s.d.now;
    return _s.d.store.transaction((tx) async {
      final f = await load(t, id, tx: tx);
      final status = '${f['status']}';
      if (status == 'completed') {
        if (outcome == 'completed' &&
            f['method'] == method &&
            f['reference'] == reference) {
          return {...BillingSupport.present(f), 'idempotentReplay': true};
        }
        throw const ApiException.conflict('This refund is already completed.');
      }
      if (!const {'approved', 'processing', 'failed'}.contains(status)) {
        throw ApiException.conflict('A $status refund cannot be processed.');
      }
      final srcPay = await tx.get(_s.path(t, 'payments', '${f['paymentId']}'));
      final gatewayPay = srcPay?['source'] == 'gateway';
      if (gatewayPay != viaGateway) {
        throw ApiException.conflict(
          gatewayPay
              ? 'This payment was made online. Refund it through the payment gateway.'
              : 'This payment was not made online.',
        );
      }
      final amount = f['amount']! as int;
      final base = <String, Object?>{
        'status': outcome,
        'method': method,
        'reference': reference,
        'processedBy': t.uid,
        'processedByRole': t.actorLabel,
        'processedAt': now,
        'attempts': ((f['attempts'] as int?) ?? 0) + 1,
        'failureReason': outcome == 'failed' ? failure : null,
        'history': _history(
          f,
          _event(t, outcome!, note: outcome == 'failed' ? failure : notes),
        ),
        'updatedAt': now,
      }..removeWhere((k, v) => v == null && k != 'failureReason');
      final ops = <WriteOp>[];
      Map<String, Object?>? invoicePatch;
      if (outcome == 'completed') {
        base['completedAt'] = now;
        final pay = await _payments.loadPayment(t, '${f['paymentId']}', tx: tx);
        ops.add(
          UpdateOp(_s.path(t, PaymentService.collection, '${f['paymentId']}'), {
            'refundedTotal': ((pay['refundedTotal'] as int?) ?? 0) + amount,
          }),
        );
        final invoiceId = f['invoiceId'] as String?;
        if (invoiceId != null) {
          final inv = await _invoices.load(t, invoiceId, tx: tx);
          if (((inv['amountPaid'] as int?) ?? 0) -
                  ((inv['amountRefunded'] as int?) ?? 0) <
              amount) {
            throw const ApiException.conflict(
              'The invoice has less paid than this refund.',
            );
          }
          invoicePatch = _invoices.balancePatch(inv, refunded: amount)
            ..['updatedBy'] = t.uid;
          ops.add(
            UpdateOp(
              _s.path(t, InvoiceService.collection, invoiceId),
              invoicePatch,
            ),
          );
        } else {
          // refund of an unapplied advance: it leaves the credit ledger
          final creditId = pay['creditId']! as String;
          final src = await tx.get(
            _s.path(t, 'patient_credit_ledger', creditId),
          );
          if (amount > await _payments.remainingOf(tx, t, src!)) {
            throw const ApiException.conflict(
              'The advance has less left than this refund.',
            );
          }
          final patientId = '${f['patientId']}';
          final balPath = _s.path(t, 'patient_credit_balances', patientId);
          final balDoc = await tx.get(balPath);
          final bal = ((balDoc?['balance'] as int?) ?? 0) - amount;
          if (bal < 0) {
            throw const ApiException.conflict(
              'The credit balance cannot go below zero.',
            );
          }
          final entryId = 'le_${newId(length: 14)}';
          ops
            ..add(
              CreateOp(_s.path(t, 'patient_credit_ledger', entryId), {
                'entryId': entryId,
                'tenantId': t.tenantId,
                'patientId': patientId,
                'branchId': f['branchId'],
                'type': 'refund_out',
                'direction': 'out',
                'amount': amount,
                'balanceAfter': bal,
                'currency': f['currency'],
                'creditId': creditId,
                'sourcePaymentId': f['paymentId'],
                'reason': 'Refund ${f['refundId']}',
                'createdAt': now,
                'createdBy': t.uid,
              }),
            )
            ..add(UpdateOp(balPath, {'balance': bal, 'updatedAt': now}));
        }
      }
      ops
        ..add(UpdateOp(_s.path(t, collection, id), base))
        ..add(
          _s.audit(
            t,
            action: 'refund.$outcome',
            resourceType: 'refund',
            resourceId: id,
            branchId: '${f['branchId']}',
            patientId: '${f['patientId']}',
            invoiceId: f['invoiceId'] as String?,
            amount: amount,
            reason: failure,
            requestId: requestId,
            after: {'method': method, 'attempt': base['attempts']},
          ),
        );
      tx.write(ops);
      return BillingSupport.present({...f, ...base});
    });
  }

  // -------------------------------------------------------------- reads

  Future<Map<String, Object?>> detail(TenantContext t, String id) async {
    _requireAny(t);
    return BillingSupport.present(await load(t, id));
  }

  void _requireAny(TenantContext t) {
    if (!t.can(ClinicPermission.refundRequest) &&
        !t.can(ClinicPermission.refundApprove) &&
        !t.can(ClinicPermission.refundProcess) &&
        !t.can(ClinicPermission.paymentView)) {
      throw const ApiException.forbidden();
    }
  }

  Future<Paged> list(
    TenantContext t,
    Request req, {
    String? status,
    String? patientId,
    String? branchId,
    String? paymentId,
    String? from,
    String? to,
  }) async {
    _requireAny(t);
    if (status != null && !refundStatuses.contains(status)) {
      throw const ApiException.badRequest('status has an unsupported value.');
    }
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
          if (status != null) QueryFilter('status', FilterOp.eq, status),
          if (patientId != null)
            QueryFilter('patientId', FilterOp.eq, patientId),
          if (paymentId != null)
            QueryFilter('paymentId', FilterOp.eq, paymentId),
          if (lo != null) QueryFilter('requestedAt', FilterOp.gte, lo),
          if (hi != null) QueryFilter('requestedAt', FilterOp.lt, hi),
        ],
        orderBy: const OrderBy('requestedAt', descending: true),
      ),
      req,
    );
  }
}
