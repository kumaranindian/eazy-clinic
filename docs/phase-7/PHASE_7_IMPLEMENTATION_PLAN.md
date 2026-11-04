# Phase 7 Implementation Plan

| Step | Work | Result |
|---|---|---|
| 1 | Assessment | `PHASE_7_ASSESSMENT.md` |
| 2 | Architecture and data model | `FINANCIAL_ARCHITECTURE.md`, `FINANCIAL_DATA_SCHEMA.md`; integer-paise math with 17 unit tests |
| 3 | Service catalogue, tax rules, billing settings | `catalogue_service.dart` |
| 4 | Invoice lifecycle (draft, finalize, cancel, credit/debit notes) | `invoice_service.dart` |
| 5 | Payments, allocations, idempotency, concurrency-safe numbering | `payment_service.dart` |
| 6 | Advance payments and the credit ledger | `payment_service.dart` |
| 7 | Receipts | issued with the payment, re-read without side effects |
| 8 | Refunds | `refund_service.dart` |
| 9 | Expenses and categories | `expense_service.dart` |
| 10 | Dashboard and reports, CSV | `report_service.dart` |
| 11 | Clinic Web screens | `apps/clinic_web/lib/features/finance/` |
| 12 | Security and concurrency tests | 114 backend billing tests (17 arithmetic), 7 permission-policy tests, 25 Clinic Web tests, emulator suite |
| 13 | Documentation | this folder |

Test-first for the arithmetic (`billing_math_test.dart`); every service shipped with HTTP-level tests including cross-tenant, cross-branch, permission and race cases. A real authorization gap (clinic-wide expense creation by a branch-scoped user) and a refund-eligibility gap (failed refunds not holding their amount) were found by those tests and fixed.
