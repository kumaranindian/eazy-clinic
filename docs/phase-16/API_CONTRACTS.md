# API Contracts (Phase 16)

## Platform (`/api/v1/platform`)
| Method & path | Permission | Notes |
|---|---|---|
| `POST /payments/eligibility/seed-baseline` | `platform.payments.manage` | create-if-absent IN/AE; providers other than `sandbox` are candidates |
| `GET /payments/eligibility` | `platform.payments.read` | |
| `PATCH /payments/eligibility/{country}/{provider}` | manage | `expectedVersion, reason` + `status, currencies, modes, liveApproved, note`. `409`: no adapter, live disabled, not approved with modes, stale |
| `GET /payments/health` | read | per provider: clinics configured/enabled/live, transaction counts by status, open exceptions; no payer data |

## Clinic (`/api/v1`)
| Method & path | Permission | Notes |
|---|---|---|
| `GET /billing/gateway/config` | `payment.view` | provider, mode, enabled, version; `credentialRef` and eligible providers only for `gateway.manage` |
| `PUT /billing/gateway/config` | `gateway.manage` | `{provider, mode, credentialRef, enabled?}`; `409` not eligible/live off; `422` unknown credential |
| `POST /billing/gateway/config/rotate` | `gateway.manage` | `{credentialRef}` or `{retirePrevious:true}` |
| `POST /billing/gateway/intents` | `payment.collect` + `Idempotency-Key` | `{invoiceId, amountMinor?}` (≤ outstanding); `201` with `transactionId, providerRef, checkoutToken, status`; `409` not enabled / nothing due / already open; replay returns the same transaction |
| `GET /billing/gateway/transactions[?invoiceId&status]`, `GET …/{id}` | `payment.view` | branch scoped |
| `POST /billing/gateway/transactions/{id}/sync` | `gateway.reconcile` | provider inquiry applied through the webhook rules |
| `POST /billing/refunds/{id}/gateway` | `refund.process` | executes an approved refund of an online payment at the provider; replay-safe |
| `GET /billing/gateway/reconciliation` | `gateway.reconcile` | `{exceptions, staleTransactions, counts, definitions}` |
| `POST /billing/gateway/exceptions/{id}/resolve` | `gateway.reconcile` | `{note}` (≥ 5 chars) |
| `POST /webhooks/payments/{provider}/{tenantId}` | **public** (signature) | raw JSON ≤ 64 KB; `200 {duplicate, outcome}`; `401` for anything not authentic (no detail); `413` oversized |

Changed behaviour: `POST /billing/payments` with `method: online` stays refused; `POST /billing/refunds/{id}/complete` on an online payment is refused (`409`), and `…/gateway` on a cash payment is refused.

Sandbox webhook shape (adapter-specific; real providers define their own): `{id, type, ref, amountMinor?, currency?, refundRef?, settlement?{currency, amountMinor, feeMinor?, fxRate?, settledAt?}}`, header `x-signature` = hex HMAC-SHA256 of the raw body.
