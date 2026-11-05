# Test Report (Phase 16)

Date: 2026-11-05 · Flutter 3.32.8 / Dart 3.8.1.

| Command | Result |
|---|---|
| `scripts/check_all.sh` | **exit 0** |

Backend 1048 passed (+34 in `gateway_test.dart`), 29 skipped (emulator). Other packages unchanged and passing (common_models 21, api_contracts 7, validation 5, utilities 8, country_config 20, design_system 19, app_core 102, clinic_web 184, doctor 23, patient 40). Apps were not rebuilt (no app code changed).

## What `gateway_test.dart` proves (34)
* **Primitives:** transition table (final states never move); constant-time signature compare; environment credentials need all parts and a valid reference; redacted `toString`.
* **Eligibility/config:** platform permission split; candidates cannot be approved (no adapter); live and `liveApproved` refused; bad status/currency/provider; stale version; owner-only configuration; unknown credential; non-eligible provider and live refused; only managers see the credential reference; no secret appears in responses or stored documents; a clinic billing in INR cannot use the AED entry.
* **Intents:** amount from invoice; replay returns the same transaction and calls the provider once; same key + different body = conflict; key required; one open intent per invoice; cannot exceed what is due; draft/unknown/foreign invoices refused; nurse refused; not configured creates nothing; provider failure marks the transaction failed and allows a retry.
* **Webhooks:** valid capture records exactly one payment (source gateway, method online, receipt, audit) and pays the invoice; **duplicate and concurrent deliveries and a second event id create no second payment**; bad signature, other clinic's secret, unknown provider/tenant, tampered bytes, non-JSON, malformed, unknown type are refused with no effect and nothing stored; oversized refused; amount/currency/missing-amount mismatch → exception, no payment; unknown transaction → exception; capture after failure → late-capture exception; authorized→captured then failure → state conflict; partial payment leaves a balance and excess becomes an advance; settlement stored apart, never computed; disputes; **clinic B cannot affect or read clinic A's transaction**.
* **Refunds:** full refund through the provider completes refund and transaction, key = refund id, replay safe; partial refunds accumulate and cap; provider decline leaves the transaction untouched and is retryable; processing refunds complete from the provider's confirmation, repeats change nothing, unmatched refund → exception; manual completion of an online payment and gateway refund of a cash payment are refused while cash refunds still work; permission checks.
* **Operations:** inquiry applies status through the same checks (and a later webhook is not a second payment); inquiry mismatch → exception; reconciliation lists exceptions and stale payments after 31 minutes, resolution needs a note and the right role; credential rotation (both secrets work, then only the new one); platform health counts without payer data; **manual collection unchanged** and `method: online` stays refused.

## Not run / not verified
Real providers (none exist) and their webhook formats; the Firestore emulator and real transaction concurrency (in-memory store serialises); rules tests; Clinic Web and patient app screens (none built); load/rate-limit behaviour of the public endpoint; settlement-report reconciliation (not built).
