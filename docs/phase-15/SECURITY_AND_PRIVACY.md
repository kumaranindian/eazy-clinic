# Security and Privacy (Phase 15)

| Topic | Control |
|---|---|
| No guessed tax | Resolution throws on unverified/retired/wrong-country/missing-rate policies; no default rate exists anywhere; baseline shells are empty |
| Separation of duties | `manage` (edit) and `verify` are distinct platform permissions; Support Admin is read-only; clinic roles have none; a stale verification is refused |
| Verification voiding | Material edits clear the verification and say why; metadata edits keep it |
| Tenant isolation | Clinic reads use the caller's tenant; country comes from the trusted tenant record, never the client; `x-tenant-id` is only a selector |
| Historical integrity | Rates, policy version, rounding and seller/customer/numbering are frozen on the invoice; a finalized draft re-checks the policy version; adjustments are the only correction path |
| Mass assignment | Strict allow-lists on policy updates, verification, line fields, note fields, settings |
| Input safety | Tax registration number pattern-checked (no markup); dates strictly validated; rates integers |
| E-invoice | No live provider; payload never stored or logged, only a digest; attempt log holds codes, not messages; idempotency key per invoice; retry cap |
| Export | Tax CSV needs the export permission, is audited, and uses the existing formula-injection neutralisation |
| Financial data | Tax figures are visible to billing/finance roles only; nurses/receptionists are refused the report |
| Residual | Tax registration numbers are business identifiers visible to billing users; verification relies on a human specialist; no MFA on platform roles (TD-94) |
