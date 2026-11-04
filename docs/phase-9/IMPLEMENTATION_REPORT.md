# Phase 9 implementation report

Status: **implemented and tested at API, emulator and widget level; not release-ready; not pushed.** Branch `feature/phase-9-laboratory` (from `develop` at `6b92ee0`).

## Definition of done
| Requirement | State |
|---|---|
| Lab catalogue with categories, sample type, fasting, turnaround, units, price, branch availability, in-house/external | Done (categories fixed list, TD-71) |
| Clinic-configured reference ranges by age/sex/unit with source; none hardcoded | Done |
| Doctor investigation requests integrated with Phase 6 without duplication | Done |
| Order lifecycle with validated transitions and history | Done |
| Sample collection with identity check, collector/time, unique identifier, rejection, recollection | Done (typed labels, TD-74) |
| Structured result entry (numeric, text, qualitative), drafts, flags | Done |
| Verification, return, controlled amendment with preserved history | Done |
| PDF report in secure storage, versioned, authenticated access | Done; plain layout (TD-73); live GCS unverified (TD-80) |
| Patient app access (published only, dependents via family permission) | Done; structured view, no PDF viewer |
| Doctor workspace integration | Done |
| External lab directory and report upload, clearly labelled | Done (TD-76) |
| Lab dashboard from real data | Done (TD-77) |
| Audit trail | Done (TD-81) |
| Security, functional, concurrency tests | Done |
| Documentation | Done |
| Android build / real device | **Not verified** (no SDK) |
| Phases 0-8 still green | Yes (full suite) |

## Commits (branch `feature/phase-9-laboratory`)
`d7246ed` backend · `6d3a670` patient portal lab reports · `a2c7d19` indexes, rules tests, emulator test, search fix · `8b2ecd8` Clinic Web · `cb406c7` Doctor Workspace · `615ec2a` doctor history · `c4930fd` patient app · docs commit.

## Files, APIs, data
See `README.md` (map), `API_SPECIFICATION.md`, `DATABASE_SCHEMA.md`. Shared docs updated: progress, roadmap, technical debt (TD-68 updated, TD-71 to TD-82 added), architecture ADRs 066-073, schema, RBAC, API standards, testing strategy.

## Deviations and decisions to confirm
- A dedicated branch was used instead of `feature/phase-0-foundation`, as in Phases 7 and 8.
- The doctor's old free-text investigation endpoint is kept; the consultation now shows catalogue orders and marks old free-text entries as "recorded as a note".
- The administrator cannot read results or reports (clinical permission set).
- Verifier must differ from enterer, with no setting to change it (TD-75). A single-technician clinic therefore needs a doctor or the owner to verify.
- Doctors see only their own orders and reports (TD-82).

## Known issues and remaining work
TD-71 to TD-82. In particular: critical-value call-back is absent (TD-78), lab charges are not billed (TD-79), indexes are undeployed (TD-80), push delivery depends on Phase 10 (TD-67), and other medical documents are still not shared with patients (TD-68).

## Recommended next step
Approve pushing and merging Phase 9, then Phase 10 (reports and notifications), which would also make report availability and critical results reach people promptly.
