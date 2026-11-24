# Migration and Rollback

## Data
Additive only. Existing invoices, tax rules, adjustments and counters are untouched. **Existing finalized invoices have no `issueSnapshot`** and no policy fields; readers must treat both as optional (the code does). No back-fill is performed (a back-fill would invent seller details that were not captured at issue time).

Clinic-defined `tax_rules` keep working exactly as before (half-up rounding). Nothing is migrated to policies; clinics opt in per line when a verified policy exists.

## Rollout (when approved)
1. Deploy index `invoice_adjustments(branchId, createdAt)`; deploy backend.
2. Super admin seeds the baseline shells.
3. A tax specialist supplies rates, thresholds, exemptions and invoice requirements per country; a verifier records the verification.
4. Clinics set `legalName` and `taxRegistrationNumber`.

## Rollback
Redeploy the previous backend: policy fields and `issueSnapshot` are ignored; invoices remain valid. Retire a policy (`status: retired`) to stop new use; issued invoices are unaffected. No destructive step exists.

## Production tax migration
Explicitly out of scope.
