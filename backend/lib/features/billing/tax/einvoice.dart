import 'dart:convert';

import 'package:common_models/common_models.dart';
import 'package:crypto/crypto.dart';

import '../../../core/data/document_store.dart';
import '../../../core/errors/api_exception.dart';
import '../../clinic/common/tenant_context.dart';
import '../billing_support.dart';

/// Phase 15: provider-neutral e-invoicing contract.
///
/// **No live provider exists.** [NotConfiguredEInvoiceProvider] is the only
/// implementation shipped; it reports e-invoicing as disabled for every
/// country, so nothing is ever transmitted. A real provider may be added only
/// after the country's requirements, the provider contract, credentials,
/// certification and sandbox testing are approved (see
/// `docs/phase-15/KNOWN_GAPS_AND_NEXT_PHASE.md`).
const List<String> eInvoiceStatuses = [
  'queued',
  'submitted',
  'accepted',
  'rejected',
  'failed',
  'cancelled',
];

const int maxEInvoiceAttempts = 5;

/// Allowed state changes. `accepted`, `rejected` and `cancelled` are final:
/// a rejected document is corrected with a credit/debit note, never resent.
const Map<String, Set<String>> eInvoiceTransitions = {
  'queued': {'submitted', 'accepted', 'rejected', 'failed', 'cancelled'},
  'submitted': {'accepted', 'rejected', 'failed'},
  'failed': {'queued', 'cancelled'},
  'accepted': {},
  'rejected': {},
  'cancelled': {},
};

bool canMoveEInvoice(String from, String to) =>
    eInvoiceTransitions[from]?.contains(to) ?? false;

/// What a provider receives: references and a digest, built by the provider
/// adapter from the immutable invoice. The core never logs or stores the
/// payload, only its SHA-256.
class EInvoiceRequest {
  const EInvoiceRequest({
    required this.tenantId,
    required this.invoiceId,
    required this.invoiceNumber,
    required this.countryCode,
    required this.idempotencyKey,
    required this.payloadSha256,
    required this.invoice,
  });

  final String tenantId;
  final String invoiceId;
  final String invoiceNumber;
  final String countryCode;
  final String idempotencyKey;
  final String payloadSha256;

  /// The immutable invoice. Providers must not log it.
  final Map<String, Object?> invoice;
}

class EInvoiceResponse {
  const EInvoiceResponse({
    required this.outcome,
    this.providerReference,
    this.errorCode,
  });

  /// `submitted`, `accepted`, `rejected` or `failed`.
  final String outcome;
  final String? providerReference;

  /// A short code, never a message that echoes invoice content.
  final String? errorCode;
}

abstract class EInvoiceProvider {
  /// Whether live submission is enabled for [countryCode].
  bool enabledFor(String countryCode);

  Future<EInvoiceResponse> submit(EInvoiceRequest request);
}

class NotConfiguredEInvoiceProvider implements EInvoiceProvider {
  const NotConfiguredEInvoiceProvider();

  @override
  bool enabledFor(String countryCode) => false;

  @override
  Future<EInvoiceResponse> submit(EInvoiceRequest request) =>
      throw StateError('E-invoicing is not configured.');
}

/// Submission record per invoice (`tenants/{t}/einvoice_submissions/{invoiceId}`):
/// status, attempt log (time, outcome, provider reference, error code, payload
/// digest) and the idempotency key. No payload and no credentials.
class EInvoiceService {
  EInvoiceService(this._s, this.provider);

  final BillingSupport _s;
  final EInvoiceProvider provider;

  static const String collection = 'einvoice_submissions';

  Future<Map<String, Object?>?> status(
    TenantContext t,
    String invoiceId,
  ) async {
    t.require(ClinicPermission.billingView);
    final inv = await _s.d.store.get(_s.path(t, 'invoices', invoiceId));
    if (inv == null || !t.scope.allows('${inv['branchId']}')) {
      throw const ApiException.notFound('Invoice not found.');
    }
    final d = await _s.d.store.get(_s.path(t, collection, invoiceId));
    return d == null ? null : BillingSupport.present(d);
  }

  /// Sends a finalized invoice. Idempotent: repeating the call for an invoice
  /// that is queued, submitted or final returns the existing record; only a
  /// `failed` record is retried (up to [maxEInvoiceAttempts]).
  Future<Map<String, Object?>> submit(
    TenantContext t,
    String invoiceId, {
    String? requestId,
  }) async {
    t.require(ClinicPermission.billingFinalize);
    final p = _s.path(t, 'invoices', invoiceId);
    final inv = await _s.d.store.get(p);
    if (inv == null || !t.scope.allows('${inv['branchId']}')) {
      throw const ApiException.notFound('Invoice not found.');
    }
    if (inv['invoiceNumber'] == null || inv['status'] == 'cancelled') {
      throw const ApiException.conflict(
        'Only an issued, not cancelled, invoice can be e-invoiced.',
      );
    }
    final country =
        (await _s.d.store.get('tenants/${t.tenantId}'))?['countryCode']
            as String?;
    if (country == null || !provider.enabledFor(country)) {
      throw const ApiException.conflict(
        'E-invoicing is not enabled for this clinic\'s country.',
      );
    }
    final sp = _s.path(t, collection, invoiceId);
    final prior = await _s.d.store.get(sp);
    if (prior != null && prior['status'] != 'failed') {
      return BillingSupport.present(prior);
    }
    final attempts = ((prior?['attempts'] as List?) ?? const []);
    if (attempts.length >= maxEInvoiceAttempts) {
      throw const ApiException.conflict(
        'The retry limit was reached. Contact support.',
      );
    }
    final digest = sha256
        .convert(utf8.encode(jsonEncode(BillingSupport.present(inv))))
        .toString();
    final key =
        (prior?['idempotencyKey'] as String?) ??
        'ei_${invoiceId}_$digest'.substring(0, 60);
    EInvoiceResponse res;
    try {
      res = await provider.submit(
        EInvoiceRequest(
          tenantId: t.tenantId,
          invoiceId: invoiceId,
          invoiceNumber: '${inv['invoiceNumber']}',
          countryCode: country,
          idempotencyKey: key,
          payloadSha256: digest,
          invoice: BillingSupport.present(inv),
        ),
      );
    } on Object {
      res = const EInvoiceResponse(
        outcome: 'failed',
        errorCode: 'provider_error',
      );
    }
    final outcome =
        const {'submitted', 'accepted', 'rejected'}.contains(res.outcome)
        ? res.outcome
        : 'failed';
    final now = _s.d.now;
    final from = prior == null ? 'queued' : 'failed';
    final status = canMoveEInvoice('queued', outcome) ? outcome : 'failed';
    final doc = {
      'invoiceId': invoiceId,
      'invoiceNumber': inv['invoiceNumber'],
      'branchId': inv['branchId'],
      'tenantId': t.tenantId,
      'status': status,
      'idempotencyKey': key,
      'attempts': [
        ...attempts,
        {
          'at': now,
          'from': from,
          'outcome': status,
          'providerReference': res.providerReference,
          'errorCode': res.errorCode,
          'payloadSha256': digest,
        },
      ],
      'updatedAt': now,
      'updatedBy': t.uid,
    };
    await _s.d.store.commit([
      prior == null
          ? CreateOp(sp, {...doc, 'createdAt': now, 'createdBy': t.uid})
          : UpdateOp(sp, doc),
      _s.audit(
        t,
        action: 'invoice.einvoice_$status',
        resourceType: 'invoice',
        resourceId: invoiceId,
        branchId: '${inv['branchId']}',
        invoiceId: invoiceId,
        requestId: requestId,
        after: {'status': status, 'attempt': attempts.length + 1},
      ),
    ]);
    return BillingSupport.present({...?prior, ...doc});
  }
}
