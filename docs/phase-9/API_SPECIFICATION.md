# Laboratory API (`/api/v1`)

Standard envelope, errors and pagination (`docs/api/API_STANDARDS.md`). Every route needs authentication, tenant membership, branch scope and the permission shown; the plan must include the `laboratory` feature (403 otherwise). Request bodies reject unknown fields. Lifecycle changes are action endpoints; no endpoint accepts a status, flag, report number or tenant.

## Catalogue
| Method / path | Permission | Notes |
|---|---|---|
| `GET /laboratory/categories` | `lab.tests.view` | categories, sample types, priorities |
| `GET /laboratory/tests?q&category&status&branchId` | `lab.tests.view` | `q` is a name prefix |
| `POST /laboratory/tests` | `lab.tests.manage` | `code`, `name`, `category`, `sampleType`, `turnaroundHours`, optional `priceMinor`, `fastingRequired`, `branchIds`, `designation`+`externalLabId`, required `parameters[]`; ranges need `source` |
| `GET /laboratory/tests/{id}` | `lab.tests.view` | |
| `PATCH /laboratory/tests/{id}` | `lab.tests.manage` | bumps `version`; existing orders keep their snapshot |
| `GET/POST /laboratory/external-labs` | view / `lab.external.manage` | |

## Orders
| Method / path | Permission | Notes |
|---|---|---|
| `GET /laboratory/orders?status&priority&doctorId&patientId&branchId&from&to&q` | `lab.orders.view` | `q` = exact order number. A doctor without lab-desk rights sees only their own orders |
| `POST /laboratory/orders` | `lab.orders.manage` | **`Idempotency-Key` required**; `patientId`, `branchId`, `tests[{testId, indication?, instructions?}]`, `priority` |
| `POST /consultations/{cid}/lab-orders` | `investigations.request` | the consultation's own doctor, consultation open; one active request per test |
| `GET /consultations/{cid}/lab-orders` | `lab.orders.view` | order summaries for the consultation |
| `GET /laboratory/orders/{id}` | `lab.orders.view` | order, items, samples, history |
| `POST /laboratory/orders/{id}/accept` | `lab.orders.manage` | optional `assignedTo` |
| `POST /laboratory/orders/{id}/reject` | `lab.orders.manage` | `reason` (5+ chars) |
| `POST /laboratory/orders/{id}/cancel` | manage, or the requesting doctor | `reason`; refused once results exist |

## Samples
| Method / path | Permission | Notes |
|---|---|---|
| `GET /laboratory/samples?status&branchId&orderId` | `lab.samples.manage` or results entry | |
| `POST /laboratory/orders/{id}/samples` | `lab.samples.manage` | order accepted; optional `sampleType`, `itemIds`, `container`, `notes` |
| `POST /laboratory/samples/{id}/collect` | `lab.samples.manage` | `identifier` (unique), **`confirmedMrn` must match the patient**, optional `condition` (`acceptable`, `hemolyzed`, `lipemic`, `clotted`, `insufficient`, `other`) |
| `POST /laboratory/samples/{id}/reject` | `lab.samples.manage` | `reason`; order becomes `recollection_required` |
| `POST /laboratory/samples/{id}/recollect` | `lab.samples.manage` | new pending sample linked by `recollectOf` |

## Results, verification, publication
| Method / path | Permission | Notes |
|---|---|---|
| `GET /laboratory/orders/{id}/results` | `lab.results.view` | non-lab staff (doctors) receive results only when the order is `verified`/`published`; no `internalComment`, `enteredBy`, `revisions`, `history` |
| `PUT /laboratory/orders/{id}/results/{itemId}` | `lab.results.enter` | draft save; body `observations[{code, value, unit?, comment?}]`, `internalComment?`; first save moves the order to `processing`; flags computed server-side |
| `POST /laboratory/orders/{id}/submit-verification` | `lab.results.enter` | every parameter of every test needs a value |
| `POST /laboratory/orders/{id}/verify` | `lab.results.verify` | verifier differs from the enterer; idempotent |
| `POST /laboratory/orders/{id}/return` | `lab.results.verify` | `reason`; back to `processing`, results `returned` |
| `POST /laboratory/orders/{id}/results/{itemId}/amend` | `lab.results.enter` | verified/published only; `reason`, `observations`; keeps previous values; order returns to `verification_pending` (201) |
| `POST /laboratory/orders/{id}/publish` | `lab.reports.publish` | verified orders; renders the PDF, stores it privately, supersedes older versions, notifies the patient; idempotent |
| `POST /laboratory/orders/{id}/external-report` | `lab.external.manage` | external orders; `fileName`, `contentBase64` (up to 8 MB; PDF/PNG/JPEG/WebP by content); `externalReference?` (201) |

## Reports and audit
| Method / path | Permission | Notes |
|---|---|---|
| `GET /laboratory/reports?orderId&patientId&branchId&status` | `lab.reports.view` | `storagePath` is never returned |
| `GET /laboratory/reports/{id}` | `lab.reports.view` | audited |
| `GET /laboratory/reports/{id}/download` | `lab.reports.view` | bytes, `Cache-Control: private, no-store`, `nosniff`; audited |
| `GET /laboratory/dashboard?from&to&branchId&status&priority` | `lab.dashboard.view` | counts with definitions; range up to 92 days; `truncated` flag at the 5,000-order scan cap |
| `GET /laboratory/audit?orderId&patientId&action` | `lab.audit.view` | owner only by default |

## Patient app (`/patient`, account-scoped, allow-listed)
| Method / path | Notes |
|---|---|
| `GET /patient/lab-reports?accountId&clinicId` (alias `GET /patient/reports`) | current published reports of the selected person |
| `GET /patient/clinics/{cid}/lab-reports/{rid}` | tests, values, flags, ranges, disclaimer |
| `GET /patient/clinics/{cid}/lab-reports/{rid}/download` | the stored file, authenticated, audited |

Dependents need the relationship scope `view_records`. `GET /patient/documents` still reports documents as unavailable (TD-68).
