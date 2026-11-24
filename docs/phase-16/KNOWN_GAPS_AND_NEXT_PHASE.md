# Known Gaps and Next Phase

| ID | Gap | Plan |
|---|---|---|
| TD-124 | **No real provider adapter.** The named providers are candidates only; the sandbox signature scheme is ours. Each real adapter needs the provider contract, API/webhook spec review, credentials, certification and sandbox contract tests (webhook fixtures per provider) | Provider selection decision first |
| TD-125 | Live mode hard-disabled (deployment switch + per-provider approval); no activation workflow, checklist enforcement or approver record | Design with the first real provider |
| TD-126 | No Clinic Web / doctor / patient screens for gateway configuration, "pay online", transactions or reconciliation; the patient app cannot start an intent | UI pass; patient flow needs client SDK or hosted page per provider |
| TD-127 | Clinic currency is still chosen as INR in the UI; AED accepted in the backend only; amount precision map has two currencies | With Phase 19/22 country packs |
| TD-128 | Webhook endpoint has no per-IP rate limit or provider IP allow-list | Edge/WAF + limiter |
| TD-129 | No settlement-report import or automatic settlement matching; the reconciliation queue is event-driven plus manual `sync`; no scheduled sweep of stale payments | Worker hook (as in Phase 14) |
| TD-130 | Refund amounts are per refund, tax parts are not computed for gateway refunds (see TD-120) | |
| TD-131 | Subscription payments are unchanged and do not use this gateway (out of scope) | |
| – | Deposits/advances: captured excess becomes an advance; no "deposit before visit" flow; multiple tenders in one invoice work through separate transactions/payments | |
| – | Dispute evidence submission is not built | |
| – | Index `gateway_exceptions(status, createdAt)`, rules tests not deployed/run; some list filters (`branchId in` + `status`) may need composite indexes (TD-95) | |

## Release risks
Do not tell clinics online payments are available. Do not enable any provider until an adapter is built and certified. Treat `platform.payments.manage` and `gateway.manage` as highly privileged.

## Next phase
**Phase 17 – Healthcare Integrations & National Health Ecosystems.** It can reuse the provider/adapter + disabled-by-default pattern, the credential-reference approach, the compliance registers (Phase 14) and the event/exception queue pattern. Prerequisites: which national integrations (ABDM, UAE exchanges) are in scope, access agreements and sandbox availability.
