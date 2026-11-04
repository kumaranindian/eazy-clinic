# Laboratory data (under `tenants/{tenantId}/`)

All writes are backend-only; Firestore rules deny every client read and write (rules tests cover each collection).

| Collection | Id | Purpose / key fields |
|---|---|---|
| `lab_tests` | `lt_...` | Catalogue entry: `code`, `name`, `nameLower`, `category`, `sampleType`, `container`, `fastingRequired`, `fastingHours`, `turnaroundHours`, `priceMinor`, `branchIds` (empty = all), `designation` (`in_house`/`external`), `externalLabId`, `parameters[]`, `version`, `status` |
| `lab_tests.parameters[]` | | `code`, `name`, `valueType` (`numeric`/`text`/`qualitative`), `unit`, `qualitativeOptions[{value, abnormal?, critical?}]`, `referenceRanges[{sex, ageMinYears, ageMaxYears, low, high, criticalLow, criticalHigh, unit, source (required), note}]` |
| `lab_test_codes` | lowercase code | Uniqueness key for test codes |
| `external_laboratories` | `el_...` | Name and contact of an outside laboratory, `status` |
| `lab_orders` | `lo_...` | `orderNumber` (LAB-000001), patient/branch/doctor/consultation references and name snapshots, `priority`, `status`, `source` (`doctor`/`laboratory`), `external`, `items[]` (snapshot of each test incl. `parameters`), `history[]`, `reportId`, `externalReportId`, `amendmentPending` |
| `lab_order_numbers` | `LAB-000001` | Uniqueness key; `ownerId` |
| `lab_order_keys` | `{consultationId}_{testId}` | One active request per consultation and test (`active`, `orderId`, `orderNumber`) |
| `lab_samples` | `ls_...` | `sampleNumber` (SMP-), `orderId`, `itemIds`, `sampleType`, `status` (`pending`/`collected`/`rejected`/`cancelled`), `identifier`, `identityVerified`, `collectedBy/At`, `condition`, `rejectReason`, `recollectOf`, `recollectedAs`, `history[]` |
| `lab_sample_numbers`, `lab_sample_ids` | number / UPPERCASE identifier | Uniqueness keys |
| `lab_results` | `{orderId}__{itemId}` | One per ordered test: `status` (`draft`/`submitted`/`returned`/`verified`), `observations[{code, name, valueType, value, unit, flag, range{...,source}, comment}]`, `internalComment`, `revision`, `revisions[]` (previous values, amender, reason, time), `enteredBy`, `submittedBy`, `verifiedBy`, `history[]` |
| `lab_reports` | `lr_...` | `reportNumber` (RPT-), `orderId`, `version`, `status` (`uploaded`/`published`/`superseded`), `current`, `external`, `source`, `label`, `verifiedByClinic`, `storagePath`, `contentType`, `sizeBytes`, `sha256`, `publishedBy/At` |
| `lab_report_numbers` | `RPT-000001` | Uniqueness key |
| `lab_idempotency` | hash of uid and key | Order-creation replay record with body fingerprint |
| `counters` | `lab_order_number`, `lab_sample_number`, `lab_report_number` | Next-number counters (shared collection) |
| `lab_audit_logs` | auto | `action`, `resourceType/Id`, `orderId`, `patientId`, `branchId`, `actorUid`, `actorRole`, `reason`, `requestId`, `before`, `after`, `timestamp`. **No test names or values.** |

Changes to existing collections: `investigation_requests` gains `testId`, `code`, `labOrderId`, `labOrderNumber`, `processing: laboratory`, and a status that follows the order (`ordered`, then `rejected`/`cancelled`).

## Object storage
`{tenantId}/lab_reports/{reportId}.pdf` (generated) and `{tenantId}/lab_reports/{reportId}` (external uploads, content-sniffed to PDF/PNG/JPEG/WebP). Private; never exposed as a URL.

## Indexes
21 composite indexes added to `firebase/firestore.indexes.json` for `lab_tests`, `lab_orders`, `lab_samples`, `lab_reports`, `lab_audit_logs`. **Not deployed** (no production change was made).
