# Architecture and Data Model

## Layers
`PaymentProvider` (adapter; knows the provider) → `GatewayService` (rules; knows EazyClinic) → `PaymentService` / `RefundService` (existing money records). The service never contains provider-specific code; adapters never touch Firestore.

## Collections
Platform: `payment_eligibility/{countryCode}` — `providers[{provider, name, currencies[], modes[], status candidate|approved|disabled, liveApproved, note}], version, updatedAt/By`.
Per clinic (`tenants/{t}/…`):
* `gateway_config/main` — `provider, mode (test|live), credentialRef, previousCredentialRef, credentialVersion, enabled, updatedAt/By`. **No secrets.**
* `gateway_transactions/{gtx_…}` — `invoiceId, invoiceNumber, patientId, branchId, provider, mode, amountMinor, currency, currencyExponent, status, providerRef, paymentId, receiptNumber, refundedTotal, settlement{currency, amountMinor, feeMinor, fxRate, settledAt, recordedAt}, history[], createdAt/By, capturedAt`. The checkout token is returned to the caller once and **not stored**.
* `gateway_events/{hash}` — claim record per `provider:eventId` (`received → processed`, outcome). The unique document is the replay guard.
* `gateway_exceptions/{ex_<event>_<type>}` — `type, transactionId, eventKey, status open|resolved, resolvedBy/At/Note`.
* Existing `payments` gain `source: gateway`, `gatewayProvider`, `gatewayTransactionId`.

## Lifecycle
`intent → pending → authorized → captured → partially_refunded → refunded`; `disputed` from captured/partially refunded and back; `failed`/`cancelled` from open states. Final: failed, cancelled, refunded. Capability flags declare what a provider supports (separate capture, partial refunds, inquiry, disputes).

## Webhook processing
1. Resolve tenant config from the URL; resolve credentials by reference (current, then previous during rotation); the **provider adapter** verifies the signature over the raw bytes. Any failure → the same generic 401.
2. Claim the event (`gateway_events`, create-if-absent). Already `processed` → `{duplicate:true}` and stop. `received` (an interrupted earlier attempt) → resume.
3. Find the transaction **in that clinic** by provider reference. None → exception.
4. Apply by type, always through the transition table: capture requires equal amount and currency and an open transaction; otherwise an exception and **no payment**.
5. Capture records the payment via `PaymentService.create(gateway: …)` with the idempotency key `gw_<transactionId>` (so a redelivery or a second event for the same capture cannot create a second payment), allocating to the invoice up to what is outstanding and keeping the rest as an advance.
6. Mark the event `processed`. If recording the payment fails, an exception is opened and the error is returned (5xx) so the provider redelivers; the event stays `received`.

## Settlement and currency
Every transaction carries `currency` + `currencyExponent`. Settlement currency/amount/fee/FX-rate evidence arrive from the provider and are stored in `settlement`, never mixed with the invoice amount and never calculated. `AED` joined the currency list (exponent 2); the settings UI still offers INR only (TD-127).

## Refund flow
Request/approve as before → `POST /billing/refunds/{id}/gateway` → provider refund (key = refund id) → the outcome is written through `RefundService.complete(viaGateway: true)` (method `online`) → transaction `refundedTotal` and status updated once (skipped on replay). A `processing` outcome completes later through a `refund.processed` webhook matched by refund reference. Unmatched refund events become exceptions.

## Credentials
Secrets live only in server configuration: `PAYMENT_CRED_<REF>_KEY|_SECRET|_WEBHOOK`. Clinics store the reference name. `ProviderCredentials.toString()` is redacted. Rotation: new reference becomes current, the old one verifies webhooks until `retirePrevious`.
