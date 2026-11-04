import 'package:api_contracts/api_contracts.dart';

import '../../core/errors/api_exception.dart';

/// Result of creating a payment order at the gateway.
class GatewayOrder {
  const GatewayOrder({
    required this.orderId,
    required this.amountMinor,
    required this.currency,
  });
  final String orderId;
  final int amountMinor;
  final String currency;
}

/// A verified gateway notification (never trusted before verification).
class GatewayEvent {
  const GatewayEvent({
    required this.eventId,
    required this.type,
    required this.orderId,
    required this.paymentId,
    required this.amountMinor,
    required this.currency,
  });
  final String eventId;
  final String type;
  final String orderId;
  final String? paymentId;
  final int amountMinor;
  final String currency;
}

/// Server-side boundary for an online payment gateway (Razorpay is the
/// planned provider, CLAUDE.md §3).
///
/// **Not implemented.** No gateway has been approved or configured for this
/// project, so only this interface and [NotConfiguredGateway] exist. Nothing
/// simulates a successful payment. When a gateway is approved, an
/// implementation must:
///
/// 1. create orders on the backend, with the amount taken from the invoice
///    outstanding (never from the client) and the secret held only in backend
///    environment configuration;
/// 2. verify the payment signature on the backend before a payment is
///    recorded, and verify the amount and currency against the order;
/// 3. verify webhook signatures over the raw body and de-duplicate events by
///    event id so a replay cannot create a second payment;
/// 4. record the payment through the same transaction as offline payments
///    (allocation, receipt, audit), idempotently;
/// 5. reconcile orders without a payment event and surface failures.
abstract interface class PaymentGateway {
  bool get configured;

  Future<GatewayOrder> createOrder({
    required String tenantId,
    required int amountMinor,
    required String currency,
    required String receipt,
  });

  /// Verifies the checkout signature; throws when invalid.
  Future<void> verifyPayment({
    required String orderId,
    required String paymentId,
    required String signature,
  });

  /// Verifies a webhook over the raw request body.
  GatewayEvent verifyWebhook({
    required List<int> rawBody,
    required String signature,
  });
}

class NotConfiguredGateway implements PaymentGateway {
  const NotConfiguredGateway();

  @override
  bool get configured => false;

  Never _unavailable() => throw const ApiException(
    ApiErrorCode.unavailable,
    'Online payments are not available. No payment gateway is configured.',
  );

  @override
  Future<GatewayOrder> createOrder({
    required String tenantId,
    required int amountMinor,
    required String currency,
    required String receipt,
  }) async => _unavailable();

  @override
  Future<void> verifyPayment({
    required String orderId,
    required String paymentId,
    required String signature,
  }) async => _unavailable();

  @override
  GatewayEvent verifyWebhook({
    required List<int> rawBody,
    required String signature,
  }) => _unavailable();
}
