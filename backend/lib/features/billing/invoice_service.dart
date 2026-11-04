import 'package:api_contracts/api_contracts.dart';
import 'package:common_models/common_models.dart';
import 'package:shelf/shelf.dart';

import '../../core/data/document_store.dart';
import '../../core/errors/api_exception.dart';
import '../../core/ids.dart';
import '../clinic/common/tenant_context.dart';
import '../platform/common/body_reader.dart';
import '../platform/common/paging.dart';
import '../scheduling/time_support.dart';
import 'billing_math.dart';
import 'billing_support.dart';
import 'catalogue_service.dart';

const int maxInvoiceLines = 50;

const List<String> invoiceStatuses = [
  'draft',
  'finalized',
  'partially_paid',
  'paid',
  'overdue',
  'cancelled',
  'partially_refunded',
  'refunded',
];

/// Invoices: drafts, finalization with a snapshot of prices and tax, balances,
/// cancellation and credit/debit adjustments. Finalized invoices are never
/// edited; corrections are adjustment records.
class InvoiceService {
  InvoiceService(this._s, this._cat);

  final BillingSupport _s;
  final CatalogueService _cat;

  static const String collection = 'invoices';

  // ------------------------------------------------------------ loading

  Future<DocData> load(TenantContext t, String id, {TxContext? tx}) async {
    final p = _s.path(t, collection, id);
    final inv = tx == null ? await _s.d.store.get(p) : await tx.get(p);
    if (inv == null || !t.scope.allows('${inv['branchId']}')) {
      throw const ApiException.notFound('Invoice not found.');
    }
    return inv;
  }

  /// Wire form with the derived "overdue" display status.
  Future<Map<String, Object?>> present(
    TenantContext t,
    DocData inv, {
    String? today,
  }) async {
    final day = today ?? (await _s.zone(t)).localDate(_s.d.now);
    return presentWith(inv, day);
  }

  static Map<String, Object?> presentWith(DocData inv, String today) {
    final out = BillingSupport.present(inv);
    final open =
        inv['status'] == 'finalized' || inv['status'] == 'partially_paid';
    final due = inv['dueDate'] as String?;
    final overdue =
        open &&
        due != null &&
        ((inv['outstanding'] as int?) ?? 0) > 0 &&
        due.compareTo(today) < 0;
    out['overdue'] = overdue;
    out['displayStatus'] = overdue ? 'overdue' : inv['status'];
    return out;
  }

  // ----------------------------------------------------------- balances

  /// Fields to write after money moved on a finalized invoice.
  Map<String, Object?> balancePatch(
    DocData inv, {
    int paid = 0,
    int refunded = 0,
    int debits = 0,
    int credits = 0,
  }) {
    final p = ((inv['amountPaid'] as int?) ?? 0) + paid;
    final rf = ((inv['amountRefunded'] as int?) ?? 0) + refunded;
    final db = ((inv['adjustmentDebits'] as int?) ?? 0) + debits;
    final cr = ((inv['adjustmentCredits'] as int?) ?? 0) + credits;
    final b = balanceOf(
      grandTotal: inv['grandTotal']! as int,
      debits: db,
      credits: cr,
      paid: p,
      refunded: rf,
    );
    return {
      'amountPaid': p,
      'amountRefunded': rf,
      'adjustmentDebits': db,
      'adjustmentCredits': cr,
      'adjustedTotal': b.adjustedTotal,
      'outstanding': b.outstanding,
      'status': b.status,
      'updatedAt': _s.d.now,
      'rev': ((inv['rev'] as int?) ?? 1) + 1,
    };
  }

  /// Whether money can be allocated to the invoice.
  static bool acceptsPayment(DocData inv) =>
      const {
        'finalized',
        'partially_paid',
        'partially_refunded',
        'paid',
        'refunded',
      }.contains(inv['status']) &&
      ((inv['outstanding'] as int?) ?? 0) > 0;

  // -------------------------------------------------------------- lines

  Discount? _discount(BodyReader r, Object? raw, String field) {
    if (raw == null) return null;
    if (raw is! Map) {
      r.addIssue(field, 'invalid_type', 'Must be an object.');
      return null;
    }
    final c = BodyReader(raw.cast<String, Object?>())
      ..rejectUnknown({'type', 'value'});
    final type = c.enumOf<String>('type', const ['fixed', 'percent'], (v) => v);
    final value = c.integer(
      'value',
      min: 1,
      max: type == 'percent' ? 10000 : 1000000000,
    );
    for (final x in c.issues) {
      r.addIssue('$field.${x.field}', x.code, x.message);
    }
    if (type == null || value == null) return null;
    return type == 'fixed' ? Discount.fixed(value) : Discount.percent(value);
  }

  /// Validates and snapshots the lines of a draft. Prices and taxes of
  /// catalogue services are resolved here, on the server; the client sends
  /// neither.
  Future<List<Map<String, Object?>>> _snapshotLines(
    TenantContext t,
    BodyReader r,
    String branchId,
    String? invoiceDoctorId,
    Object? raw,
  ) async {
    if (raw is! List || raw.length > maxInvoiceLines) {
      r.addIssue(
        'lines',
        'invalid_value',
        'Give up to $maxInvoiceLines lines.',
      );
      return const [];
    }
    final out = <Map<String, Object?>>[];
    for (var i = 0; i < raw.length; i++) {
      final item = raw[i];
      if (item is! Map) {
        r.addIssue('lines[$i]', 'invalid_type', 'Must be an object.');
        continue;
      }
      final c = BodyReader(item.cast<String, Object?>())
        ..rejectUnknown({
          'serviceId',
          'description',
          'category',
          'unitMinor',
          'quantity',
          'discount',
          'taxExempt',
          'taxExemptReason',
          'taxRuleId',
          'doctorId',
        });
      final serviceId = c.str('serviceId', max: 40, required: false);
      final qty = c.integer('quantity', min: 1, max: 1000);
      final disc = _discount(c, c.body['discount'], 'discount');
      final exempt = c.boolean('taxExempt') ?? false;
      final exemptReason = c.str(
        'taxExemptReason',
        min: 5,
        max: 200,
        required: false,
      );
      if (exempt && exemptReason == null) {
        c.addIssue(
          'taxExemptReason',
          'required',
          'Give the reason for the exemption.',
        );
      }
      final doctorId =
          c.str('doctorId', max: 40, required: false) ?? invoiceDoctorId;
      String description;
      String category;
      int unit;
      String? ruleId;
      int? serviceVersion;
      if (serviceId != null) {
        // price, category and tax come from the catalogue only
        for (final k in ['unitMinor', 'category', 'taxRuleId']) {
          if (c.has(k)) {
            c.addIssue(
              k,
              'not_allowed',
              'This comes from the service catalogue.',
            );
          }
        }
        if (c.issues.isNotEmpty) {
          for (final x in c.issues) {
            r.addIssue('lines[$i].${x.field}', x.code, x.message);
          }
          continue;
        }
        final svc = await _cat.usable(t, serviceId, branchId, doctorId);
        description =
            c.str('description', max: 200, required: false) ?? '${svc['name']}';
        category = '${svc['category']}';
        unit = CatalogueService.priceFor(svc, branchId, doctorId);
        ruleId = svc['taxRuleId'] as String?;
        serviceVersion = svc['version'] as int?;
      } else {
        description = c.str('description', min: 2, max: 200) ?? '';
        category =
            c.enumOf<String>(
              'category',
              serviceCategories,
              (v) => v,
              required: false,
            ) ??
            'custom';
        unit = c.integer('unitMinor', min: 0, max: 1000000000) ?? 0;
        ruleId = c.str('taxRuleId', max: 40, required: false);
      }
      for (final x in c.issues) {
        r.addIssue('lines[$i].${x.field}', x.code, x.message);
      }
      if (c.issues.isNotEmpty) continue;
      final rule = await _cat.taxRule(t, ruleId);
      out.add({
        'lineId': 'l${i + 1}',
        'serviceId': serviceId,
        'serviceVersion': serviceVersion,
        'description': description,
        'category': category,
        'quantity': qty,
        'unitMinor': unit,
        'discountType': disc == null
            ? null
            : (disc.amount != null ? 'fixed' : 'percent'),
        'discountValue': disc?.amount ?? disc?.bps,
        'taxRuleId': rule?.id,
        'taxRuleName': rule?.name,
        'taxInclusive': rule?.inclusive,
        'taxComponents': rule == null
            ? null
            : [
                for (final k in rule.components)
                  {'name': k.name, 'rateBps': k.rateBps},
              ],
        'taxExempt': exempt,
        'taxExemptReason': exemptReason,
        'doctorId': doctorId,
      });
    }
    return out;
  }

  /// Runs the deterministic calculation over stored line snapshots.
  ({List<Map<String, Object?>> lines, Map<String, Object?> totals}) _compute(
    List<Map<String, Object?>> snaps,
    Map<String, Object?>? invDiscount,
  ) {
    final inputs = [
      for (final l in snaps)
        LineInput(
          quantity: l['quantity']! as int,
          unitMinor: l['unitMinor']! as int,
          discount: l['discountType'] == null
              ? null
              : l['discountType'] == 'fixed'
              ? Discount.fixed(l['discountValue']! as int)
              : Discount.percent(l['discountValue']! as int),
          taxExempt: l['taxExempt'] == true,
          taxRule: l['taxComponents'] == null
              ? null
              : TaxRule(
                  id: '${l['taxRuleId']}',
                  name: '${l['taxRuleName']}',
                  inclusive: l['taxInclusive'] == true,
                  components: [
                    for (final c in (l['taxComponents'] as List))
                      TaxComponent(
                        '${(c as Map)['name']}',
                        c['rateBps'] as int,
                      ),
                  ],
                ),
        ),
    ];
    Discount? inv;
    if (invDiscount != null) {
      inv = invDiscount['type'] == 'fixed'
          ? Discount.fixed(invDiscount['value']! as int)
          : Discount.percent(invDiscount['value']! as int);
    }
    final res = calculateInvoice(inputs, invoiceDiscount: inv);
    final lines = <Map<String, Object?>>[
      for (var i = 0; i < snaps.length; i++)
        {
          ...snaps[i],
          'gross': res.lines[i].gross,
          'lineDiscount': res.lines[i].lineDiscount,
          'invoiceDiscountShare': res.lines[i].invoiceDiscountShare,
          'taxableBase': res.lines[i].taxableBase,
          'taxParts': [for (final p in res.lines[i].taxParts) p.toJson()],
          'tax': res.lines[i].tax,
          'total': res.lines[i].total,
        },
    ];
    return (
      lines: lines,
      totals: {
        'subtotal': res.subtotal,
        'lineDiscountTotal': res.lineDiscountTotal,
        'invoiceDiscount': res.invoiceDiscount,
        'discountTotal': res.discountTotal,
        'taxTotal': res.taxTotal,
        'grandTotal': res.grandTotal,
      },
    );
  }

  /// A discount needs the permission and must stay within the role's limit.
  Future<void> _checkDiscount(
    TenantContext t,
    Map<String, Object?> totals,
  ) async {
    final total = totals['discountTotal']! as int;
    if (total == 0) return;
    t.require(ClinicPermission.billingApplyDiscount);
    final s = await _s.settings(t);
    final limits = (s['discountLimitsBps'] as Map?) ?? const {};
    final limit = (limits[t.actorLabel] as int?) ?? 0;
    final subtotal = totals['subtotal']! as int;
    final bps = subtotal == 0
        ? 0
        : ((total * 10000) + subtotal - 1) ~/ subtotal;
    if (bps > limit) {
      throw ApiException.forbidden(
        'This discount exceeds your limit of ${limit / 100}%.',
      );
    }
  }

  // ------------------------------------------------------------- create

  static const Set<String> _createFields = {
    'patientId',
    'branchId',
    'appointmentId',
    'consultationId',
    'doctorId',
    'dueDate',
    'notes',
    'lines',
    'discount',
  };

  Future<Map<String, Object?>> create(
    TenantContext t,
    Map<String, Object?> body, {
    String? requestId,
  }) async {
    t.require(ClinicPermission.billingCreate);
    final r = BodyReader(body)..rejectUnknown(_createFields);
    final patientId = r.str('patientId', max: 40);
    final branchId = r.str('branchId', max: 40);
    final appointmentId = r.str('appointmentId', max: 40, required: false);
    final consultationId = r.str('consultationId', max: 40, required: false);
    var doctorId = r.str('doctorId', max: 40, required: false);
    final notes = r.str('notes', max: 500, required: false);
    if (r.has('dueDate') && !Dates.valid(r.body['dueDate'])) {
      r.addIssue('dueDate', 'invalid_date', 'Use YYYY-MM-DD.');
    }
    r.throwIfInvalid();

    final patient = await _s.patients.load(t, patientId!);
    if (patient['status'] != 'active') {
      throw const ApiException.conflict('The patient record is not active.');
    }
    final branch = await _s.branch(t, branchId!);
    final zone = await _s.zone(t);
    final now = _s.d.now;
    final today = zone.localDate(now);
    final settings = await _s.settings(t);

    String? sourceKey;
    if (appointmentId != null) {
      final a = await _s.d.store.get(_s.path(t, 'appointments', appointmentId));
      if (a == null ||
          a['patientId'] != patientId ||
          a['branchId'] != branchId) {
        throw const ApiException.notFound('Appointment not found.');
      }
      doctorId ??= a['doctorId'] as String?;
      sourceKey = 'appointment_$appointmentId';
    }
    if (consultationId != null) {
      // Only ids are compared; no clinical content is read or returned.
      final c = await _s.d.store.get(
        _s.path(t, 'consultations', consultationId),
      );
      if (c == null ||
          c['patientId'] != patientId ||
          c['branchId'] != branchId) {
        throw const ApiException.notFound('Consultation not found.');
      }
      doctorId ??= c['doctorId'] as String?;
      sourceKey = 'consultation_$consultationId';
    }
    if (doctorId != null) await _s.sched.assignedDoctor(t, doctorId, branchId);

    var lines = <Map<String, Object?>>[];
    if (r.has('lines')) {
      lines = await _snapshotLines(t, r, branchId, doctorId, r.body['lines']);
    }
    Map<String, Object?>? discount;
    if (r.has('discount') && r.body['discount'] != null) {
      final dsc = _discount(r, r.body['discount'], 'discount');
      if (dsc != null) {
        discount = {
          'type': dsc.amount != null ? 'fixed' : 'percent',
          'value': dsc.amount ?? dsc.bps,
        };
      }
    }
    r.throwIfInvalid();
    final calc = _compute(lines, discount);
    await _checkDiscount(t, calc.totals);

    final dueDate =
        r.body['dueDate'] as String? ??
        Dates.addDays(today, (settings['invoiceDueDays'] as int?) ?? 7);
    final id = 'inv_${newId(length: 14)}';
    final doc = <String, Object?>{
      'invoiceId': id,
      'tenantId': t.tenantId,
      'branchId': branchId,
      'branchName': branch['name'],
      'patientId': patientId,
      'patientName': patient['fullName'],
      'patientMrn': patient['mrn'],
      'appointmentId': appointmentId,
      'consultationId': consultationId,
      'doctorId': doctorId,
      'invoiceNumber': null,
      'status': 'draft',
      'currency': await _s.currency(t),
      'invoiceDate': today,
      'dueDate': dueDate,
      'lines': calc.lines,
      'discount': discount,
      ...calc.totals,
      'adjustmentDebits': 0,
      'adjustmentCredits': 0,
      'adjustedTotal': calc.totals['grandTotal'],
      'amountPaid': 0,
      'amountRefunded': 0,
      'outstanding': 0,
      'notes': notes,
      'rev': 1,
      'createdAt': now,
      'createdBy': t.uid,
      'updatedAt': now,
      'updatedBy': t.uid,
    };
    final ops = <WriteOp>[
      CreateOp(_s.path(t, collection, id), doc),
      _s.audit(
        t,
        action: 'invoice.created',
        resourceType: 'invoice',
        resourceId: id,
        branchId: branchId,
        patientId: patientId,
        invoiceId: id,
        requestId: requestId,
        after: {
          'appointmentId': appointmentId,
          'consultationId': consultationId,
        },
      ),
    ];
    if (sourceKey != null) {
      // one open invoice per appointment/consultation
      final kp = _s.path(t, 'invoice_sources', sourceKey);
      final prior = await _s.d.store.get(kp);
      if (prior != null && prior['active'] == true) {
        throw ApiException.conflict(
          'An invoice already exists for this visit (${prior['invoiceId']}).',
        );
      }
      ops.add(
        prior == null
            ? CreateOp(kp, {'invoiceId': id, 'active': true, 'createdAt': now})
            : UpdateOp(kp, {'invoiceId': id, 'active': true}),
      );
    }
    try {
      await _s.d.store.commit(ops);
    } on AlreadyExistsException {
      throw const ApiException.conflict(
        'An invoice already exists for this visit.',
      );
    }
    return present(t, doc, today: today);
  }

  // -------------------------------------------------------------- edit

  Future<Map<String, Object?>> update(
    TenantContext t,
    String id,
    Map<String, Object?> body, {
    String? requestId,
  }) async {
    t.require(ClinicPermission.billingEditDraft);
    final r = BodyReader(body, partial: true)
      ..rejectUnknown({'dueDate', 'notes', 'lines', 'discount', 'expectedRev'});
    final notes = r.str('notes', max: 500, required: false);
    final expected = r.integer(
      'expectedRev',
      min: 1,
      max: 1000000,
      required: false,
    );
    if (r.has('dueDate') && !Dates.valid(r.body['dueDate'])) {
      r.addIssue('dueDate', 'invalid_date', 'Use YYYY-MM-DD.');
    }
    final head = await load(t, id);
    if (head['status'] != 'draft') {
      throw const ApiException.conflict(
        'A finalized invoice cannot be edited. Use an adjustment.',
      );
    }
    List<Map<String, Object?>>? lines;
    if (r.has('lines')) {
      lines = await _snapshotLines(
        t,
        r,
        '${head['branchId']}',
        head['doctorId'] as String?,
        r.body['lines'],
      );
    }
    Map<String, Object?>? discount = head['discount'] as Map<String, Object?>?;
    var discountChanged = false;
    if (r.has('discount')) {
      discountChanged = true;
      if (r.body['discount'] == null) {
        discount = null;
      } else {
        final dsc = _discount(r, r.body['discount'], 'discount');
        discount = dsc == null
            ? discount
            : {
                'type': dsc.amount != null ? 'fixed' : 'percent',
                'value': dsc.amount ?? dsc.bps,
              };
      }
    }
    r.throwIfInvalid();
    final now = _s.d.now;
    return _s.d.store.transaction((tx) async {
      final cur = await load(t, id, tx: tx);
      if (cur['status'] != 'draft') {
        throw const ApiException.conflict(
          'A finalized invoice cannot be edited. Use an adjustment.',
        );
      }
      if (expected != null && expected != cur['rev']) {
        throw const ApiException.conflict(
          'This invoice changed since you opened it. Reload and try again.',
        );
      }
      final snaps =
          lines ??
          [
            for (final l in (cur['lines'] as List? ?? const []))
              (l as Map).cast<String, Object?>(),
          ];
      final calc = _compute(snaps, discount);
      if (lines != null || discountChanged) {
        await _checkDiscount(t, calc.totals);
      }
      final patch = <String, Object?>{
        'lines': calc.lines,
        'discount': discount,
        ...calc.totals,
        'adjustedTotal': calc.totals['grandTotal'],
        if (notes != null) 'notes': notes,
        if (r.has('dueDate')) 'dueDate': r.body['dueDate'],
        'rev': ((cur['rev'] as int?) ?? 1) + 1,
        'updatedAt': now,
        'updatedBy': t.uid,
      };
      tx.write([
        UpdateOp(_s.path(t, collection, id), patch),
        _s.audit(
          t,
          action: 'invoice.draft_updated',
          resourceType: 'invoice',
          resourceId: id,
          branchId: '${cur['branchId']}',
          patientId: '${cur['patientId']}',
          invoiceId: id,
          requestId: requestId,
          amount: calc.totals['grandTotal'] as int,
        ),
      ]);
      return present(t, {...cur, ...patch});
    });
  }

  // ---------------------------------------------------------- finalize

  Future<Map<String, Object?>> finalize(
    TenantContext t,
    String id, {
    String? requestId,
  }) async {
    t.require(ClinicPermission.billingFinalize);
    final head = await load(t, id);
    if (head['status'] != 'draft') {
      return {...await present(t, head), 'idempotentReplay': true};
    }
    final now = _s.d.now;
    return _s.d.store.transaction((tx) async {
      final inv = await load(t, id, tx: tx);
      if (inv['status'] != 'draft') {
        return {...await present(t, inv), 'idempotentReplay': true};
      }
      final snaps = [
        for (final l in (inv['lines'] as List? ?? const []))
          (l as Map).cast<String, Object?>(),
      ];
      if (snaps.isEmpty) {
        throw ApiException.validation([
          billingIssue(
            'lines',
            'required',
            'Add at least one line before finalizing.',
          ),
        ]);
      }
      // Recalculate from the stored snapshots: what is finalized is exactly
      // what the server computed, never a client figure.
      final calc = _compute(snaps, inv['discount'] as Map<String, Object?>?);
      final ops = <WriteOp>[];
      final number = await _s.nextNumber(
        tx,
        t,
        ops,
        counter: 'invoice_number',
        prefix: 'INV',
        keys: 'invoice_numbers',
        ownerId: id,
        ownerField: 'invoiceId',
      );
      final merged = {
        ...inv,
        'lines': calc.lines,
        ...calc.totals,
        'adjustmentDebits': 0,
        'adjustmentCredits': 0,
        'amountPaid': 0,
        'amountRefunded': 0,
      };
      final patch = {
        ...balancePatch(merged),
        'lines': calc.lines,
        ...calc.totals,
        'invoiceNumber': number,
        'finalizedAt': now,
        'finalizedBy': t.uid,
        'updatedBy': t.uid,
      };
      ops.add(UpdateOp(_s.path(t, collection, id), patch));
      ops.add(
        _s.audit(
          t,
          action: 'invoice.finalized',
          resourceType: 'invoice',
          resourceId: id,
          branchId: '${inv['branchId']}',
          patientId: '${inv['patientId']}',
          invoiceId: id,
          requestId: requestId,
          amount: calc.totals['grandTotal'] as int,
          after: {'invoiceNumber': number},
        ),
      );
      tx.write(ops);
      return present(t, {...inv, ...patch});
    });
  }

  // ------------------------------------------------------------ cancel

  Future<Map<String, Object?>> cancel(
    TenantContext t,
    String id,
    Map<String, Object?> body, {
    String? requestId,
  }) async {
    t.require(ClinicPermission.billingCancel);
    final r = BodyReader(body)..rejectUnknown({'reason'});
    final reason = r.str('reason', min: 5, max: 300);
    r.throwIfInvalid();
    final head = await load(t, id);
    if (head['status'] == 'cancelled') {
      return {...await present(t, head), 'idempotentReplay': true};
    }
    final now = _s.d.now;
    return _s.d.store.transaction((tx) async {
      final inv = await load(t, id, tx: tx);
      if (inv['status'] == 'cancelled') {
        return {...await present(t, inv), 'idempotentReplay': true};
      }
      if (((inv['amountPaid'] as int?) ?? 0) > 0) {
        throw const ApiException.conflict(
          'This invoice has payments. Refund them first; a paid invoice cannot be cancelled.',
        );
      }
      final patch = {
        'status': 'cancelled',
        'outstanding': 0,
        'cancelledAt': now,
        'cancelledBy': t.uid,
        'cancelReason': reason,
        'rev': ((inv['rev'] as int?) ?? 1) + 1,
        'updatedAt': now,
        'updatedBy': t.uid,
      };
      final ops = <WriteOp>[
        UpdateOp(_s.path(t, collection, id), patch),
        _s.audit(
          t,
          action: 'invoice.cancelled',
          resourceType: 'invoice',
          resourceId: id,
          branchId: '${inv['branchId']}',
          patientId: '${inv['patientId']}',
          invoiceId: id,
          requestId: requestId,
          reason: reason,
          before: {'status': inv['status']},
        ),
      ];
      for (final k in ['appointmentId', 'consultationId']) {
        final v = inv[k] as String?;
        if (v != null) {
          final kp = _s.path(
            t,
            'invoice_sources',
            '${k == 'appointmentId' ? 'appointment' : 'consultation'}_$v',
          );
          if (await tx.get(kp) != null) {
            ops.add(UpdateOp(kp, {'active': false}));
          }
        }
      }
      tx.write(ops);
      return present(t, {...inv, ...patch});
    });
  }

  // ------------------------------------------------------- adjustments

  Future<Map<String, Object?>> adjust(
    TenantContext t,
    String id,
    Map<String, Object?> body, {
    String? requestId,
  }) async {
    t.require(ClinicPermission.billingAdjust);
    final r = BodyReader(body)
      ..rejectUnknown({'type', 'amountMinor', 'reason', 'description'});
    final type = r.enumOf<String>('type', const ['credit', 'debit'], (v) => v);
    final amount = _s.amount(r, 'amountMinor', max: 1000000000);
    final reason = r.str('reason', min: 5, max: 300);
    final description = r.str('description', max: 300, required: false);
    r.throwIfInvalid();
    final adjId = 'adj_${newId(length: 14)}';
    final now = _s.d.now;
    return _s.d.store.transaction((tx) async {
      final inv = await load(t, id, tx: tx);
      if (inv['status'] == 'draft' || inv['status'] == 'cancelled') {
        throw const ApiException.conflict(
          'Adjustments apply to finalized invoices only.',
        );
      }
      if (type == 'credit' && amount > ((inv['outstanding'] as int?) ?? 0)) {
        throw const ApiException.conflict(
          'A credit note cannot exceed the outstanding balance. '
          'Refund money that was already paid instead.',
        );
      }
      final ops = <WriteOp>[];
      final number = await _s.nextNumber(
        tx,
        t,
        ops,
        counter: type == 'credit' ? 'credit_note_number' : 'debit_note_number',
        prefix: type == 'credit' ? 'CN' : 'DN',
        keys: type == 'credit' ? 'credit_note_numbers' : 'debit_note_numbers',
        ownerId: adjId,
      );
      final patch = balancePatch(
        inv,
        debits: type == 'debit' ? amount : 0,
        credits: type == 'credit' ? amount : 0,
      )..['updatedBy'] = t.uid;
      final doc = <String, Object?>{
        'adjustmentId': adjId,
        'tenantId': t.tenantId,
        'branchId': inv['branchId'],
        'invoiceId': id,
        'invoiceNumber': inv['invoiceNumber'],
        'patientId': inv['patientId'],
        'type': type,
        'number': number,
        'amount': amount,
        'currency': inv['currency'],
        'reason': reason,
        'description': description,
        'createdAt': now,
        'createdBy': t.uid,
      };
      ops
        ..add(CreateOp(_s.path(t, 'invoice_adjustments', adjId), doc))
        ..add(UpdateOp(_s.path(t, collection, id), patch))
        ..add(
          _s.audit(
            t,
            action: 'invoice.${type}_note',
            resourceType: 'invoice',
            resourceId: id,
            branchId: '${inv['branchId']}',
            patientId: '${inv['patientId']}',
            invoiceId: id,
            requestId: requestId,
            amount: amount,
            reason: reason,
            before: {
              'outstanding': inv['outstanding'],
              'status': inv['status'],
            },
            after: {
              'outstanding': patch['outstanding'],
              'status': patch['status'],
            },
          ),
        );
      tx.write(ops);
      return {
        'adjustment': BillingSupport.present(doc),
        'invoice': await present(t, {...inv, ...patch}),
      };
    });
  }

  // -------------------------------------------------------------- read

  Future<Map<String, Object?>> detail(
    TenantContext t,
    String id, {
    String? requestId,
  }) async {
    t.require(ClinicPermission.billingView);
    final inv = await load(t, id);
    final adj = await _s.d.store.query(
      DocQuery(
        _s.path(t, 'invoice_adjustments'),
        filters: [QueryFilter('invoiceId', FilterOp.eq, id)],
        limit: 100,
      ),
    );
    final alloc = await _s.d.store.query(
      DocQuery(
        _s.path(t, 'payment_allocations'),
        filters: [QueryFilter('invoiceId', FilterOp.eq, id)],
        limit: 200,
      ),
    );
    return {
      ...await present(t, inv),
      'adjustments': [for (final a in adj) BillingSupport.present(a.data)],
      'allocations': [for (final a in alloc) BillingSupport.present(a.data)],
    };
  }

  Future<Paged> list(
    TenantContext t,
    Request req, {
    String? status,
    String? patientId,
    String? branchId,
    String? from,
    String? to,
    String? q,
  }) async {
    t.require(ClinicPermission.billingView);
    final zone = await _s.zone(t);
    final today = zone.localDate(_s.d.now);
    final overdueOnly = status == 'overdue';
    if (status != null && !invoiceStatuses.contains(status)) {
      throw const ApiException.badRequest('status has an unsupported value.');
    }
    for (final v in [from, to]) {
      if (v != null && !Dates.valid(v)) {
        throw const ApiException.badRequest('from/to must be YYYY-MM-DD.');
      }
    }
    final filters = <QueryFilter>[
      ..._s.scopeFilters(t, branchId),
      if (patientId != null) QueryFilter('patientId', FilterOp.eq, patientId),
      if (status != null && !overdueOnly)
        QueryFilter('status', FilterOp.eq, status),
      if (from != null) QueryFilter('invoiceDate', FilterOp.gte, from),
      if (to != null) QueryFilter('invoiceDate', FilterOp.lte, to),
    ];
    // An exact invoice number is a single lookup.
    final term = q?.trim().toUpperCase();
    if (term != null && term.isNotEmpty) {
      final key = await _s.d.store.get(_s.path(t, 'invoice_numbers', term));
      final inv = key == null
          ? null
          : await _s.d.store.get(_s.path(t, collection, '${key['invoiceId']}'));
      final rows = inv != null && t.scope.allows('${inv['branchId']}')
          ? [inv]
          : const <DocData>[];
      return Paged([
        for (final d in rows)
          StoredDoc(_s.path(t, collection, '${d['invoiceId']}'), d),
      ], const PageMeta(limit: 1, hasMore: false));
    }
    final page = await runPaged(
      _s.d.store,
      DocQuery(
        _s.path(t, collection),
        filters: filters,
        orderBy: const OrderBy('createdAt', descending: true),
      ),
      req,
    );
    if (!overdueOnly) return page;
    final due = [
      for (final d in page.docs)
        if (presentWith(d.data, today)['overdue'] == true) d,
    ];
    return Paged(due, page.meta);
  }

  /// Wire form of one list row.
  Map<String, Object?> listItem(StoredDoc d, String today) {
    final p = presentWith(d.data, today);
    p.remove('lines');
    return p;
  }

  /// Payments applied to one invoice.
  Future<Map<String, Object?>> payments(TenantContext t, String id) async {
    t.require(ClinicPermission.paymentView);
    await load(t, id);
    final alloc = await _s.d.store.query(
      DocQuery(
        _s.path(t, 'payment_allocations'),
        filters: [QueryFilter('invoiceId', FilterOp.eq, id)],
        limit: 200,
      ),
    );
    final out = <Map<String, Object?>>[];
    final seen = <String>{};
    for (final a in alloc) {
      final pid = '${a.data['paymentId']}';
      if (!seen.add(pid)) continue;
      final pay = await _s.d.store.get(_s.path(t, 'payments', pid));
      if (pay != null) out.add(BillingSupport.present(pay));
    }
    return {
      'invoiceId': id,
      'payments': out,
      'allocations': [for (final a in alloc) BillingSupport.present(a.data)],
    };
  }
}
