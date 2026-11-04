# Phase 9: Laboratory Management, Investigation Requests and Test Reports

Branch: `feature/phase-9-laboratory` (created from `develop` at `6b92ee0`). The Phase 9 prompt asked to continue on `feature/phase-0-foundation`; as in Phases 7 and 8 a dedicated branch was used so the phase can be reviewed and merged on its own. Nothing is pushed or merged. No production Firebase change, deployment or secret was involved.

## What exists
| Area | Where |
|---|---|
| Test catalogue, categories, clinic-configured reference ranges, external laboratory directory | `backend/lib/features/laboratory/lab_catalogue.dart` |
| Orders (doctor request and desk order), samples, dashboard | `lab_orders.dart` |
| Result entry, submit, verify, return, amend, publish, reports, external report upload, audit list | `lab_results.dart` |
| Flag logic (normal / low / high / critical / not assessed) from configured ranges only | `lab_evaluation.dart` |
| Report PDF writer (no dependency) | `lab_pdf.dart` |
| Routes | `lab_module.dart` (`/api/v1/laboratory/...`, `/api/v1/consultations/{id}/lab-orders`) |
| Patient-app endpoints | `backend/lib/features/portal/portal_lab.dart` |
| Clinic Web screens | `apps/clinic_web/lib/features/laboratory/lab_pages.dart` |
| Doctor Workspace | `apps/doctor_mobile/.../lab_section.dart` |
| Patient app "Lab reports" tab | `apps/patient_mobile/.../lab_reports.dart` |

## Documents
`ARCHITECTURE.md` · `DATABASE_SCHEMA.md` · `API_SPECIFICATION.md` · `WORKFLOWS.md` · `SECURITY.md` · `TESTING.md` · `IMPLEMENTATION_REPORT.md`

## Key rules in one place
1. The product ships **no** reference ranges. A flag exists only when the clinic configured a range (with its source and unit) that applies to the patient's sex and age; otherwise the value is `not_assessed`.
2. A result is verified by someone other than the person who entered (or amended) it. This is enforced by the backend.
3. A report is published only from a verified order, is stored in private object storage and is served only through authenticated endpoints. There is no public or permanent link.
4. An amendment keeps the previous values and produces a new report version; the earlier version is marked `superseded`.
5. Patients see only the current published report of themselves (or of a dependent they may see records for), and never unverified values, internal comments or who handled the sample.
6. The doctor's Phase 6 free-text investigation endpoint is kept for compatibility; new catalogue-linked requests create a lab order and a linked `investigation_requests` record rather than a duplicate request store.

See `IMPLEMENTATION_REPORT.md` for status, test results and known limitations.
