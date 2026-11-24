import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// Phase 16: provider-neutral online payment contract.
///
/// Candidate providers (Razorpay, Cashfree, PayU for India; Telr, Network
/// International, Checkout.com for the UAE) are **candidates subject to
/// commercial and technical validation**. None has an adapter here. The only
/// shipped adapter is [SandboxProvider], a deterministic, in-process stand-in
/// used for contract tests and sandbox rehearsals; it can never move money.

/// Payment transaction states (the subset a provider supports is declared in
/// [ProviderCapabilities]).
const List<String> gatewayStatuses = [
  'intent',
  'pending',
  'authorized',
  'captured',
  'failed',
  'cancelled',
  'partially_refunded',
  'refunded',
  'disputed',
];

/// Allowed status changes. `failed`, `cancelled` and `refunded` are final.
const Map<String, Set<String>> gatewayTransitions = {
  'intent': {'pending', 'failed', 'cancelled'},
  'pending': {'authorized', 'captured', 'failed', 'cancelled'},
  'authorized': {'captured', 'failed', 'cancelled'},
  'captured': {'partially_refunded', 'refunded', 'disputed'},
  'partially_refunded': {'partially_refunded', 'refunded', 'disputed'},
  'disputed': {'captured', 'refunded', 'partially_refunded'},
  'failed': {},
  'cancelled': {},
  'refunded': {},
};

bool canMoveGateway(String from, String to) =>
    gatewayTransitions[from]?.contains(to) ?? false;

/// Statuses where the payer may still complete the payment.
const Set<String> openGatewayStatuses = {'intent', 'pending', 'authorized'};

const List<String> providerEventTypes = [
  'payment.authorized',
  'payment.captured',
  'payment.failed',
  'payment.cancelled',
  'refund.processed',
  'refund.failed',
  'dispute.opened',
  'dispute.closed',
  'settlement.updated',
];

class ProviderCapabilities {
  const ProviderCapabilities({
    this.separateCapture = false,
    this.refunds = true,
    this.partialRefunds = true,
    this.inquiry = true,
    this.disputes = false,
  });

  final bool separateCapture;
  final bool refunds;
  final bool partialRefunds;
  final bool inquiry;
  final bool disputes;

  Map<String, Object?> toJson() => {
    'separateCapture': separateCapture,
    'refunds': refunds,
    'partialRefunds': partialRefunds,
    'inquiry': inquiry,
    'disputes': disputes,
  };
}

/// Secrets for one provider account. Resolved on the server from the
/// environment / secret manager at call time; never stored in the database,
/// never returned by an API, never logged.
class ProviderCredentials {
  const ProviderCredentials({
    required this.apiKey,
    required this.apiSecret,
    required this.webhookSecret,
  });

  final String apiKey;
  final String apiSecret;
  final String webhookSecret;

  @override
  String toString() => 'ProviderCredentials(***)';
}

abstract interface class CredentialResolver {
  /// Credentials for a reference such as `ACME_TEST_1`, or null.
  ProviderCredentials? resolve(String ref);
}

/// Reads `PAYMENT_CRED_<REF>_KEY`, `_SECRET` and `_WEBHOOK` from the
/// environment. The database only ever holds the *reference*.
class EnvCredentialResolver implements CredentialResolver {
  EnvCredentialResolver([Map<String, String>? env])
    : _env = env ?? Platform.environment;

  final Map<String, String> _env;

  @override
  ProviderCredentials? resolve(String ref) {
    if (!RegExp(r'^[A-Z0-9_]{3,40}$').hasMatch(ref)) return null;
    final k = _env['PAYMENT_CRED_${ref}_KEY'];
    final s = _env['PAYMENT_CRED_${ref}_SECRET'];
    final w = _env['PAYMENT_CRED_${ref}_WEBHOOK'];
    if (k == null || s == null || w == null) return null;
    return ProviderCredentials(apiKey: k, apiSecret: s, webhookSecret: w);
  }
}

class MapCredentialResolver implements CredentialResolver {
  MapCredentialResolver(this.byRef);

  final Map<String, ProviderCredentials> byRef;

  @override
  ProviderCredentials? resolve(String ref) => byRef[ref];
}

class IntentRequest {
  const IntentRequest({
    required this.tenantId,
    required this.transactionId,
    required this.amountMinor,
    required this.currency,
    required this.idempotencyKey,
    required this.reference,
  });

  final String tenantId;
  final String transactionId;
  final int amountMinor;
  final String currency;
  final String idempotencyKey;

  /// Opaque reference printed on the provider side (an invoice number, never
  /// patient details).
  final String reference;
}

class ProviderIntent {
  const ProviderIntent({required this.providerRef, this.checkoutToken});

  final String providerRef;

  /// What the payer's device needs to complete the payment (provider
  /// specific). Never a secret.
  final String? checkoutToken;
}

class ProviderStatus {
  const ProviderStatus({
    required this.status,
    this.amountMinor,
    this.currency,
    this.settlement,
  });

  /// One of [gatewayStatuses] as the provider reports it now.
  final String status;
  final int? amountMinor;
  final String? currency;
  final ProviderSettlement? settlement;
}

/// Settlement facts reported by the provider. EazyClinic never computes FX:
/// [fxRate] is evidence as given (a decimal string), or null.
class ProviderSettlement {
  const ProviderSettlement({
    required this.currency,
    required this.amountMinor,
    this.feeMinor,
    this.fxRate,
    this.settledAt,
  });

  final String currency;
  final int amountMinor;
  final int? feeMinor;
  final String? fxRate;
  final DateTime? settledAt;
}

class ProviderRefundRequest {
  const ProviderRefundRequest({
    required this.providerRef,
    required this.amountMinor,
    required this.currency,
    required this.idempotencyKey,
  });

  final String providerRef;
  final int amountMinor;
  final String currency;
  final String idempotencyKey;
}

class ProviderRefundResult {
  const ProviderRefundResult({
    required this.outcome,
    this.refundRef,
    this.errorCode,
  });

  /// `completed`, `processing` or `failed`.
  final String outcome;
  final String? refundRef;
  final String? errorCode;
}

/// A webhook after signature verification. Nothing in it is trusted until the
/// service has matched it to a transaction and checked amount and currency.
class ProviderEvent {
  const ProviderEvent({
    required this.eventId,
    required this.type,
    required this.providerRef,
    this.amountMinor,
    this.currency,
    this.refundRef,
    this.settlement,
  });

  final String eventId;
  final String type;
  final String providerRef;
  final int? amountMinor;
  final String? currency;
  final String? refundRef;
  final ProviderSettlement? settlement;
}

/// Thrown when a webhook is not authentic or not understood.
class InvalidWebhook implements Exception {
  const InvalidWebhook(this.reason);
  final String reason;

  @override
  String toString() => 'InvalidWebhook($reason)';
}

abstract interface class PaymentProvider {
  String get id;

  /// Modes this adapter may run in. A sandbox adapter only has `test`.
  Set<String> get modes;

  ProviderCapabilities get capabilities;

  Future<ProviderIntent> createIntent(
    IntentRequest request,
    ProviderCredentials credentials,
  );

  Future<ProviderStatus> inquire(
    String providerRef,
    ProviderCredentials credentials,
  );

  Future<ProviderRefundResult> refund(
    ProviderRefundRequest request,
    ProviderCredentials credentials,
  );

  /// Verifies authenticity over the **raw** body and parses the event.
  /// Throws [InvalidWebhook] on any problem.
  ProviderEvent verifyWebhook(
    List<int> rawBody,
    Map<String, String> headers,
    ProviderCredentials credentials,
  );
}

/// Constant-time comparison of two hex signatures.
bool signaturesEqual(String a, String b) {
  final x = utf8.encode(a.toLowerCase());
  final y = utf8.encode(b.toLowerCase());
  var diff = x.length ^ y.length;
  for (var i = 0; i < x.length && i < y.length; i++) {
    diff |= x[i] ^ y[i];
  }
  return diff == 0;
}

String hmacHex(String secret, List<int> body) =>
    Hmac(sha256, utf8.encode(secret)).convert(body).toString();

/// Deterministic stand-in provider (`test` mode only). Webhooks are signed
/// with HMAC-SHA256 over the raw body in `x-signature`.
class SandboxProvider implements PaymentProvider {
  SandboxProvider();

  /// Test hook: what [inquire] reports for a reference.
  final Map<String, ProviderStatus> simulated = {};

  /// Test hook: make refunds fail / stay processing.
  String refundOutcome = 'completed';

  /// Test hook: make intent creation fail.
  bool failIntents = false;

  /// Test hook: calls made, to prove idempotency keys are passed.
  final List<String> intentKeys = [];
  final List<String> refundKeys = [];

  @override
  String get id => 'sandbox';

  @override
  Set<String> get modes => const {'test'};

  @override
  ProviderCapabilities get capabilities =>
      const ProviderCapabilities(separateCapture: true, disputes: true);

  @override
  Future<ProviderIntent> createIntent(
    IntentRequest request,
    ProviderCredentials credentials,
  ) async {
    intentKeys.add(request.idempotencyKey);
    if (failIntents) throw StateError('provider down');
    return ProviderIntent(
      providerRef: 'sbx_${request.transactionId}',
      checkoutToken: 'tok_${request.transactionId}',
    );
  }

  @override
  Future<ProviderStatus> inquire(
    String providerRef,
    ProviderCredentials credentials,
  ) async => simulated[providerRef] ?? const ProviderStatus(status: 'pending');

  @override
  Future<ProviderRefundResult> refund(
    ProviderRefundRequest request,
    ProviderCredentials credentials,
  ) async {
    refundKeys.add(request.idempotencyKey);
    return ProviderRefundResult(
      outcome: refundOutcome,
      refundRef: refundOutcome == 'failed'
          ? null
          : 'sbxr_${request.idempotencyKey}',
      errorCode: refundOutcome == 'failed' ? 'sandbox_declined' : null,
    );
  }

  @override
  ProviderEvent verifyWebhook(
    List<int> rawBody,
    Map<String, String> headers,
    ProviderCredentials credentials,
  ) {
    final sig = headers['x-signature'];
    if (sig == null ||
        !signaturesEqual(sig, hmacHex(credentials.webhookSecret, rawBody))) {
      throw const InvalidWebhook('signature');
    }
    final Object? j;
    try {
      j = jsonDecode(utf8.decode(rawBody));
    } on FormatException {
      throw const InvalidWebhook('body');
    }
    if (j is! Map) throw const InvalidWebhook('body');
    final type = j['type'];
    final id = j['id'];
    final ref = j['ref'];
    if (type is! String ||
        !providerEventTypes.contains(type) ||
        id is! String ||
        id.isEmpty ||
        id.length > 80 ||
        ref is! String ||
        ref.isEmpty ||
        ref.length > 80) {
      throw const InvalidWebhook('shape');
    }
    final amount = j['amountMinor'];
    final cur = j['currency'];
    if ((amount != null && (amount is! int || amount < 0)) ||
        (cur != null && (cur is! String || cur.length != 3))) {
      throw const InvalidWebhook('shape');
    }
    ProviderSettlement? settlement;
    final s = j['settlement'];
    if (s is Map) {
      final sa = s['amountMinor'];
      final sc = s['currency'];
      if (sa is! int || sa < 0 || sc is! String || sc.length != 3) {
        throw const InvalidWebhook('shape');
      }
      final fee = s['feeMinor'];
      final fx = s['fxRate'];
      settlement = ProviderSettlement(
        currency: sc,
        amountMinor: sa,
        feeMinor: fee is int ? fee : null,
        fxRate: fx is String ? fx : null,
        settledAt: s['settledAt'] is String
            ? DateTime.tryParse(s['settledAt']! as String)?.toUtc()
            : null,
      );
    }
    return ProviderEvent(
      eventId: id,
      type: type,
      providerRef: ref,
      amountMinor: amount as int?,
      currency: cur as String?,
      refundRef: j['refundRef'] is String ? j['refundRef']! as String : null,
      settlement: settlement,
    );
  }
}
