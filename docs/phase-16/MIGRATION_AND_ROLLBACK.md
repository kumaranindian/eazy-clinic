# Migration and Rollback

## Data
Additive. Existing payments are `source: offline` and unchanged. `AED` is accepted as a clinic currency (stored value only; billing UI remains INR). Refund eligibility rule changed from "offline only" to "offline or gateway".

## Rollout (when approved; sandbox only in this phase)
1. Deploy index `gateway_exceptions(status, createdAt)` (collection group) and the backend.
2. Super admin seeds payment eligibility (candidates + sandbox).
3. For a **sandbox rehearsal only**: set `PAYMENT_CRED_<REF>_KEY|_SECRET|_WEBHOOK` in the backend environment; the clinic owner configures provider `sandbox`, mode `test`, that reference.
4. Real providers: see `OPERATIONS_RUNBOOK.md` — requires an approved adapter, contract, credentials, certification and sandbox testing; none exists.

## Rollback
Redeploy the previous backend; gateway documents are ignored. Disable a clinic's gateway with `enabled:false` (webhooks for existing transactions are still honoured so money already taken is not lost). Set a provider `disabled` platform-wide. No destructive step exists; transaction history is never rewritten.
