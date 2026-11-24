# Phase 16 – International Payments: Implementation Plan

Branch `feature/phase-16-international-payments` (stacked on 15 → 14 → 13 → 12). Date: 2026-11-05. Spec: `EazyClinic_Phase_16_Implementation_Prompt.docx`.

> **No live gateway, no real provider.** Razorpay, Cashfree, PayU (India) and Telr, Network International, Checkout.com (UAE) are recorded as **candidates subject to commercial and technical validation**. No adapter exists for any of them, none can be enabled, and live mode is hard-disabled. The only adapter is a deterministic **sandbox** that moves no money. No card data is handled or stored.

## 1. Pre-flight findings
| Area | Finding |
|---|---|
| Existing gateway code | `gateway.dart` (Phase 7): an interface and `NotConfiguredGateway`; nothing used it |
| Payments | `PaymentService.create` records payments with allocation to invoices, advances, receipts, audit and idempotency; manual methods (cash, UPI, card, bank transfer, cheque, custom) |
| Refunds | request → approve → complete workflow; completion refused for non-offline payments |
| Currency | INR only (`currencyExponent`); clinic currency from settings |
| Notifications/workers | not needed here |

## 2. Delivered
* **Provider contract** (`gateway/provider.dart`): intent, inquiry, refund, webhook verification over the raw body, capabilities, status lifecycle with a transition table, credential resolver (environment references only), `SandboxProvider`.
* **Eligibility** (platform, `payment_eligibility/{country}`): country × currency × provider × mode with status candidate/approved/disabled. A provider can be approved only when an adapter exists; live needs the deployment switch **and** per-provider approval (both off).
* **Clinic configuration**: provider, mode, credential *reference* (secrets stay in server configuration), enable/disable, **rotation** with a grace period for in-flight webhooks.
* **Transactions** (`gateway_transactions`): amount taken from the invoice, ISO currency and exponent on every record, one open intent per invoice, idempotent creation, history.
* **Webhooks** (`POST /api/v1/webhooks/payments/{provider}/{tenantId}`, public by design): signature over the raw body, replay protection by claiming each event once, amount/currency verification, never trusts the client, exceptions instead of guesses.
* **Payments** recorded through the existing code path (`source: gateway`, method `online`): allocation to the invoice, advance for any excess, receipt, audit.
* **Settlement** facts stored separately (currency, amount, fee, FX rate **as reported**, timestamps); no FX is computed.
* **Refunds** through the provider using the existing approval workflow; refund id is the provider idempotency key; manual completion of an online payment is refused.
* **Reconciliation:** exception queue (amount/currency mismatch, late capture, state conflict, unknown transaction, unmatched refund, dispute, record failure), stale-payment list, status counts, provider inquiry (`sync`), resolution with a note; **platform health** per provider.
* Permissions, indexes, rules-test paths, ADRs 106–110, TD-124…TD-131, runbook.

## 3. Exclusions (per prompt)
Live activation; storing card data; unapproved providers; FX conversion/trading; subscription gateway changes. Also not delivered: any real provider adapter (TD-124) and Clinic Web / patient app screens for online payment (TD-126).

## 4. Test plan
State machine and signature primitives; platform eligibility; configuration; intents; webhooks (valid, duplicate, concurrent, invalid, oversized, mismatch, late, partial, advance, settlement, disputes, cross-tenant); refunds; reconciliation, inquiry, rotation, health; manual collection unchanged. Results: `TEST_REPORT.md`.
