# Security and Privacy (Phase 16)

| Topic | Control | Evidence |
|---|---|---|
| Never trust the client | Payments are recorded only from a verified provider event or an inquiry; the intent amount comes from the invoice outstanding | intents and manual-online tests |
| Signature | Verified over the raw bytes with constant-time comparison; any failure → identical 401; unauthentic events are not stored | "invalid signatures…" |
| Replay / duplicates | Each event claimed once (unique document); concurrent deliveries and a second event id for the same capture create no second payment (idempotency key per transaction) | duplicate, concurrent tests |
| Amount / currency | Mismatch never records money; exception queue | mismatch tests |
| Tenant isolation | Tenant from the URL selects that clinic's configuration and secrets; the transaction is looked up in that clinic only; clinic B cannot reach clinic A's transactions; secrets differ per clinic | cross-clinic tests |
| Secrets | Environment references only; never stored, returned, or logged; redacted `toString`; stored documents contain no secret | configuration test |
| Live mode | Hard-disabled (deployment switch + per-provider approval); candidates cannot be approved without an adapter | eligibility test |
| Separation of duties | Configuration: owner/admin (`gateway.manage`); reconciliation: owner/admin/accountant; refunds: `refund.process`; platform eligibility: manage vs read | permission tests |
| Card data | None is received, stored or logged; the provider hosts the payment page | design |
| PII to providers | Only an opaque reference (invoice number) is sent; no patient name or clinical data | design |
| Logging | Webhook bodies are not logged; exceptions hold codes only | code |
| Abuse | Body size cap 64 KB; unknown routes/tenants give the generic 401 | tests |
| Residual | The webhook endpoint has no per-IP rate limit (TD-128); no provider IP allow-list; sandbox signature scheme is not any real provider's; MFA for platform roles still open (TD-94) | |
