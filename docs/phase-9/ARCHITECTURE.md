# Laboratory architecture

## Shape
The laboratory is a module of the existing backend (`LabModule`, wired in `ClinicModule`); it adds no service, queue or database. It reuses tenant resolution (`TenantContext`), RBAC (`ClinicPermission`), plan gating (`FeatureKey.laboratory`), the document store with transactions, `ObjectStorage`, `PortalNotifier` and the Phase 6 consultation checks (`ClinicalSupport`).

```
LabModule
 ├─ LabSupport        scope filters, numbering, history, audit, transitions
 ├─ LabCatalogueService   tests, parameters, ranges, external labs
 ├─ LabOrderService       orders, samples, dashboard
 └─ LabResultService      results, verification, publication, reports, audit list
PortalLabService (portal module) -> patient-facing allow-listed reads
```

## Decisions (ADR 066-073)
| # | Decision | Reason |
|---|---|---|
| 066 | One `lab_orders` document holds its items as bounded snapshots (max 30) of the test definitions at order time. Later catalogue edits never change an existing order or its result flags. | Reports must be reproducible; avoids a join on every read. |
| 067 | A doctor's catalogue request creates the lab order **and** a linked Phase 6 `investigation_requests` record (`processing: laboratory`, `labOrderId`). The free-text Phase 6 endpoint is unchanged. | One request store, no duplicates, backward compatible. |
| 068 | Reference ranges exist only as clinic configuration with a mandatory `source` and unit. Without an applicable range, or with a different unit, the flag is `not_assessed` / `unit_mismatch`. | Never invent medical values (CLAUDE.md section 8, rule 17). |
| 069 | The order lifecycle is a transition table (`orderTransitions`); every move writes a history event and an audit record in the same transaction. | Auditable, concurrency-safe. |
| 070 | Separation of duty: the verifier must differ from whoever entered or amended the result. No setting turns this off yet. | Lab quality practice; see TD-75. |
| 071 | Reports are PDF bytes written by an in-repo text writer, stored in private object storage, versioned, and streamed through authenticated endpoints with `Cache-Control: private, no-store`. | No dependency; no public URL. |
| 072 | External reports are uploaded files, stored the same way, labelled "External laboratory report", and marked `verifiedByClinic` only after a second person reviews them. | Do not imply EazyClinic verified an outside result. |
| 073 | Counters plus uniqueness-key documents (`lab_order_numbers`, `lab_sample_numbers`, `lab_report_numbers`) written in the same transaction; sample identifiers are unique per clinic (`lab_sample_ids`). | Concurrency-safe numbering and identifiers. |

## Order lifecycle
```
requested -> accepted -> sample_pending -> sample_collected -> processing
          -> result_entered -> verification_pending -> verified -> published
side exits: rejected (from requested), cancelled (before results),
            recollection_required (sample rejected; back to sample_pending)
backwards:  verification_pending -> processing (returned for correction)
            verified|published -> verification_pending (amendment)
```
`result_entered -> verification_pending` happens in the same write as submission, so the order is never left in a state nobody works on.

## Concurrency
Everything that changes state runs in one document-store transaction that re-reads the order. Races covered: two samples claiming one identifier (one wins), double accept, double verify/publish (idempotent replay), duplicate request per consultation and test (key document), idempotent order creation (`Idempotency-Key` + body fingerprint). The Firestore emulator test exercises the identifier race on real transactions.

## What is deliberately not here
Instrument integration, AI interpretation, prescriptions/pharmacy, radiology, insurance, ABDM, a new payment gateway, new patient authentication, a separate service. Billing of lab charges is not automatic (TD-79).
