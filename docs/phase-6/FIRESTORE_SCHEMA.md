# Phase 6 Firestore Schema (under `tenants/{tenantId}/`)

| Collection | Key | Purpose |
|---|---|---|
| `consultations` | `con_…` | consultation, status, sections, `version`, `revision`, `amendmentCount` |
| `consultation_appointments` | appointmentId | uniqueness key: one consultation per appointment |
| `consultation_versions` | `{consultationId}_r{n}` | full snapshot at finalization (r0) and each amendment |
| `consultation_amendments` | | reason, author, time, changed sections/diagnoses |
| `diagnoses` | `dx_…` | per consultation; `status` active/removed |
| `prescriptions` | `rx_…` | draft/finalized/amended, `rev`, `version`, `supersedesId`, `rootId`, `number` |
| `counters/prescription_number`, `prescription_numbers/{RX-000001}` | | gap-tolerant numbering with uniqueness keys |
| `vitals` | `vt_…` | append-only |
| `investigation_requests` | `inv_…` | requests only |
| `followups` | `fu_…` | follow-ups |
| `clinical_templates`, `diagnosis_catalogue`, `medicine_catalogue` | | clinic-managed, start empty |
| `clinical_audit_logs` | | append-only; ids, actions, changed field names — no clinical text |

Clients have no Firestore access (rules deny all; tested). 14 composite indexes added (92 total in `firebase/firestore.indexes.json`), undeployed (TD-54).
