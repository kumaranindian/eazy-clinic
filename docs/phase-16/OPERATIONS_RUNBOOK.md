# Payments Operations Runbook (draft)

**Scope:** sandbox only. Production activation is disabled and needs explicit approval, an approved provider adapter, a signed provider contract, credentials, certification and sandbox contract testing.

## Daily
1. Platform admin: `GET /platform/payments/health` — look for rising `openExceptions`, many `pending`, or an unexpected `liveClinics` (must be 0).
2. Clinic accountant/owner: `GET /billing/gateway/reconciliation` — work every open exception and every stale payment.

## Exceptions
| Type | Meaning | Action |
|---|---|---|
| `amount_mismatch` / `currency_mismatch` | the provider says it captured a different amount/currency | **no payment was recorded**; check the provider dashboard; if money was taken, refund at the provider or collect the difference manually; resolve with a note |
| `late_capture` | capture arrived for a failed/cancelled transaction | money may have moved; verify at the provider; refund or record manually |
| `state_conflict` | an event contradicted the current state | verify with the provider (`sync`) |
| `unknown_transaction` | an authentic event we cannot match | check provider reference, clinic and environment |
| `external_refund` | refund event with no matching refund here | a refund was made outside EazyClinic; record it manually |
| `dispute_opened` | chargeback/dispute | follow the provider's dispute process; evidence is outside this phase |
| `payment_record_failed` | money confirmed but recording failed | the provider redelivers; if it persists, escalate to engineering |

## Stuck payments
`POST …/transactions/{id}/sync` asks the provider for the current state and applies it through the same checks.

## Credential rotation
1. Add the new `PAYMENT_CRED_<NEW>_*` variables and redeploy. 2. Owner: `POST /billing/gateway/config/rotate {credentialRef:<NEW>}`. 3. Switch the provider to the new secret. 4. After in-flight events settle: `{retirePrevious:true}`. 5. Remove the old variables.

## Incident: suspected leaked webhook secret
Rotate immediately and retire the previous reference; review `gateway_events`/`gateway_exceptions` and the financial audit log for the period; reconcile against the provider's settlement report.

## Open items before any go-live
Provider selection and contract; real adapter and certification; webhook IP allow-listing and rate limiting (TD-128); settlement-report import (TD-129); finance review of exception handling; legal/tax review of fees and receipts for each country.
