import '../../core/data/document_store.dart';
import '../../core/errors/api_exception.dart';
import '../auth/domain/auth_context.dart';
import '../billing/invoice_service.dart';
import '../scheduling/time_support.dart';
import 'portal_support.dart';

/// Read-only view of a patient's own bills, payments, receipts and refunds.
///
/// Built from allow-lists; staff identities, internal notes, expenses and
/// reports are never included, and a patient cannot reach another patient's
/// money by changing an id (every document is matched to the linked record).
/// Online payment is not offered: no gateway is configured, so the app shows
/// what is owed and how the clinic accepts payment, and never reports a
/// payment it did not receive.
class PortalBillingService {
  PortalBillingService(this._s);

  final PortalSupport _s;

  static const List<String> _invoiceFields = [
    'invoiceId',
    'invoiceNumber',
    'status',
    'invoiceDate',
    'dueDate',
    'currency',
    'branchName',
    'subtotal',
    'discountTotal',
    'taxTotal',
    'grandTotal',
    'adjustedTotal',
    'amountPaid',
    'amountRefunded',
    'outstanding',
  ];

  Future<List<DocData>> _rows(
    ClinicLink link,
    String collection, {
    int limit = 100,
  }) async {
    final rows = await _s.store.query(
      DocQuery(
        _s.path(link.tenantId, collection),
        filters: [QueryFilter('patientId', FilterOp.eq, link.patientId)],
        limit: limit,
      ),
    );
    return [for (final r in rows) r.data];
  }

  Future<Map<String, Object?>> _invoice(
    ClinicLink link,
    DocData inv,
    String today, {
    bool lines = false,
  }) async {
    final shown = InvoiceService.presentWith(inv, today);
    final out = {
      ...PortalSupport.pick(inv, _invoiceFields),
      'displayStatus': shown['displayStatus'],
      'clinicId': link.tenantId,
      'clinicName': link.clinicName,
    };
    if (lines) {
      out['lines'] = [
        for (final l in (inv['lines'] as List? ?? const []))
          PortalSupport.pick((l as Map).cast<String, Object?>(), [
            'description',
            'quantity',
            'unitMinor',
            'lineDiscount',
            'tax',
            'total',
          ]),
      ];
    }
    return out;
  }

  Future<String> _today(ClinicLink link) async {
    final s = await _s.store.get(
      _s.path(link.tenantId, 'clinic_settings', 'operations'),
    );
    return ClinicZone.resolve(s?['timezone'] as String?).localDate(_s.d.now);
  }

  Future<List<Map<String, Object?>>> invoices(
    AuthContext ctx, {
    String? accountId,
    String? clinicId,
  }) async {
    final subject = await _s.subject(
      ctx,
      accountId,
      PortalSupport.scopeRecords,
    );
    final out = <Map<String, Object?>>[];
    for (final link in await _s.links(subject, clinicId: clinicId)) {
      final today = await _today(link);
      for (final inv in await _rows(link, 'invoices')) {
        if (inv['status'] == 'draft') continue;
        out.add(await _invoice(link, inv, today));
      }
    }
    out.sort((a, b) => '${b['invoiceDate']}'.compareTo('${a['invoiceDate']}'));
    return out;
  }

  Future<Map<String, Object?>> invoice(
    AuthContext ctx,
    String clinicId,
    String invoiceId, {
    String? accountId,
  }) async {
    final subject = await _s.subject(
      ctx,
      accountId,
      PortalSupport.scopeRecords,
    );
    final link = await _s.requireLink(subject, clinicId);
    final inv = await _s.store.get(_s.path(clinicId, 'invoices', invoiceId));
    if (inv == null ||
        inv['patientId'] != link.patientId ||
        inv['status'] == 'draft') {
      throw const ApiException.notFound('Invoice not found.');
    }
    final pays = await _s.store.query(
      DocQuery(
        _s.path(clinicId, 'payment_allocations'),
        filters: [QueryFilter('invoiceId', FilterOp.eq, invoiceId)],
        limit: 100,
      ),
    );
    return {
      ...await _invoice(link, inv, await _today(link), lines: true),
      'payments': [
        for (final a in pays)
          PortalSupport.pick(a.data, [
            'paymentId',
            'amount',
            'source',
            'createdAt',
          ]),
      ],
      'onlinePayment': {
        'available': false,
        'note': 'Pay at the clinic. Online payment is not available yet.',
      },
    };
  }

  Future<List<Map<String, Object?>>> payments(
    AuthContext ctx, {
    String? accountId,
    String? clinicId,
  }) async {
    final subject = await _s.subject(
      ctx,
      accountId,
      PortalSupport.scopeRecords,
    );
    final out = <Map<String, Object?>>[];
    for (final link in await _s.links(subject, clinicId: clinicId)) {
      for (final p in await _rows(link, 'payments')) {
        out.add({
          ...PortalSupport.pick(p, [
            'paymentId',
            'receiptId',
            'receiptNumber',
            'amount',
            'currency',
            'method',
            'reference',
            'receivedAt',
            'status',
            'refundedTotal',
            'advanceAmount',
          ]),
          'clinicId': link.tenantId,
          'clinicName': link.clinicName,
        });
      }
    }
    out.sort((a, b) => '${b['receivedAt']}'.compareTo('${a['receivedAt']}'));
    return out;
  }

  Future<Map<String, Object?>> receipt(
    AuthContext ctx,
    String clinicId,
    String receiptId, {
    String? accountId,
  }) async {
    final subject = await _s.subject(
      ctx,
      accountId,
      PortalSupport.scopeRecords,
    );
    final link = await _s.requireLink(subject, clinicId);
    final rc = await _s.store.get(_s.path(clinicId, 'receipts', receiptId));
    if (rc == null || rc['patientId'] != link.patientId) {
      throw const ApiException.notFound('Receipt not found.');
    }
    return {
      ...PortalSupport.pick(rc, [
        'receiptId',
        'receiptNumber',
        'paymentId',
        'amount',
        'currency',
        'method',
        'reference',
        'receivedAt',
        'invoices',
        'advanceAmount',
        'clinic',
        'patientName',
        'patientMrn',
      ]),
      'clinicId': clinicId,
    };
  }

  Future<List<Map<String, Object?>>> refunds(
    AuthContext ctx, {
    String? accountId,
    String? clinicId,
  }) async {
    final subject = await _s.subject(
      ctx,
      accountId,
      PortalSupport.scopeRecords,
    );
    final out = <Map<String, Object?>>[];
    for (final link in await _s.links(subject, clinicId: clinicId)) {
      for (final f in await _rows(link, 'refunds')) {
        out.add({
          ...PortalSupport.pick(f, [
            'refundId',
            'paymentReceipt',
            'invoiceNumber',
            'amount',
            'currency',
            'status',
            'method',
            'requestedAt',
            'completedAt',
          ]),
          'clinicId': link.tenantId,
          'clinicName': link.clinicName,
        });
      }
    }
    out.sort((a, b) => '${b['requestedAt']}'.compareTo('${a['requestedAt']}'));
    return out;
  }

  /// What is owed and the advance credit, per clinic.
  Future<List<Map<String, Object?>>> summary(
    AuthContext ctx, {
    String? accountId,
  }) async {
    final subject = await _s.subject(
      ctx,
      accountId,
      PortalSupport.scopeRecords,
    );
    final out = <Map<String, Object?>>[];
    for (final link in await _s.links(subject)) {
      var owed = 0;
      for (final inv in await _rows(link, 'invoices')) {
        if (inv['status'] == 'draft' || inv['status'] == 'cancelled') continue;
        owed += (inv['outstanding'] as int?) ?? 0;
      }
      final credit = await _s.store.get(
        _s.path(link.tenantId, 'patient_credit_balances', link.patientId),
      );
      out.add({
        'clinicId': link.tenantId,
        'clinicName': link.clinicName,
        'outstanding': owed,
        'creditBalance': (credit?['balance'] as int?) ?? 0,
      });
    }
    return out;
  }
}
