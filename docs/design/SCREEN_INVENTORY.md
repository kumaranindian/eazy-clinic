# Screen Inventory

Status: **Planned.** No screen beyond the Phase 0 placeholder shell is implemented. Source: CLAUDE.md §2, §6, the app-flow mockup (screen numbers `M#`
refer to it) and workflow completeness. Phase numbers follow CLAUDE.md §18. "API domain" refers to `/api/v1/<domain>`.

Apps: **CW** = EazyClinic Clinic Web (Flutter Web) · **DW** = EazyClinic Doctor (Flutter Web + Android) · **PA** = EazyClinic Patient (Flutter Android).
Roles abbreviations: Owner, Admin, Doc, Rec (receptionist), Nurse, Acct (accountant), Lab, Plat (platform admin), Pat (patient), Care (caregiver).

## 1. Phase 0 (implemented)

| Screen | App | Purpose |
|---|---|---|
| Foundation page | CW, DW, PA | Proves shell, theme, routing, config; shows environment; links to gallery in non-production |
| Design-system gallery (`/design-system`) | CW, DW, PA | Developer showcase, not in production |
| Configuration error screen | CW, DW, PA | Shown when build-time config is invalid |

## 2. Clinic Management Web (CW)

| Screen | Role | Purpose | Entry point | Main actions | Data dependencies | API domain | Phase |
|---|---|---|---|---|---|---|---|
| Login (M5) | All clinic staff | Authenticate | App start | Email/password, MFA, forgot password | users, memberships | auth | 1 |
| Forgot / reset password | All | Recover account | Login | Request link, set password | users | auth | 1 |
| MFA enrol / verify | Owner, Admin, Acct | Second factor | Login / security settings | Enrol, verify, recovery codes | users | auth | 1 |
| Clinic owner sign-up (M6, adjusted per D-1) | Prospective owner | Apply for a clinic account | Login | Submit applicant + terms | tenants (pending) | clinics | 2 |
| Accept invitation | Invited staff/doctor | Join a clinic | Email link | Set password, accept | clinic_invites, members | auth, members | 3 |
| Tenant / branch switcher | Multi-membership users | Choose clinic and branch context | Top bar | Switch | members, branches | auth, clinics | 2 |
| Clinic setup wizard (M7) | Owner | First-time configuration | After approval / settings | Profile, logo, address, specialties | clinic_settings | clinics | 2 |
| Dashboard (M8 adapted) | Owner, Admin, Rec, Acct | Today's overview | Home | KPIs, quick actions, today's queue | appointments, queue, invoices | reports | 10 (shell with placeholder in 2) |
| Clinic settings (hours, holidays, policies, invoice, tax) | Owner, Admin | Configure clinic | Settings | Edit sections | clinic_settings | clinics | 2 |
| Subscription & plan | Owner | View plan, trial, billing status | Settings | View/upgrade | platform_subscriptions | clinics | 2 |
| Branches list / branch form | Owner, Admin | Manage branches | Settings | Add/edit, hours, deactivate | branches | branches | 2 |
| Doctors list / doctor profile form | Owner, Admin | Manage doctors | Staff menu | Add, qualifications, fees, availability, signature, branch assignment | doctors | doctors | 3 |
| Staff list / staff form / invite | Owner, Admin | Manage staff | Staff menu | Invite, role, branches, deactivate | staff, members, roles | members | 3 |
| Roles & permissions | Owner | Configure permissions | Settings | Edit role permission sets | roles | members | 3 |
| Patients list (M14) | Rec, Admin, Doc, Nurse | Find patients | Patients menu | Search, filter, open, register | patients | patients | 4 |
| Patient registration form | Rec, Admin, Doc, Nurse | Register patient | Patients / appointment flow | Create, duplicate check | patients | patients | 4 |
| Patient details (M11) | Rec, Admin, Doc, Nurse | Overview, history, prescriptions, billing tabs | Patient list | View/edit demographics, history, documents | patients, medical_histories, vitals | patients | 4 |
| Patient linking / invitation | Rec, Admin | Link to patient account | Patient details | Generate code, verify, record consent | patient_links, consents | patients, consents | 4 |
| Appointments (calendar & list, M9) | Rec, Admin, Doc | View/manage | Appointments menu | Filter day/week/doctor/branch, reschedule, cancel | appointments, slots | appointments | 5 |
| New appointment (M10) | Rec, Admin | Book | FAB / patient details | Patient, doctor, branch, slot, type | appointments, slots, doctors | appointments | 5 |
| Availability & slots | Admin, Doc | Configure | Doctor profile | Weekly rules, blocks | doctors, slots | doctors, appointments | 5 |
| Queue board / check-in | Rec, Nurse | Token and live queue | Queue menu | Check-in, issue token, call, skip, no-show | queue_entries | queues | 5 |
| Queue display (public screen mode) | Rec | Waiting-room display | Queue menu | Fullscreen display (no PHI beyond token/first name) | queue_entries | queues | 5 |
| Billing: generate bill (M15) | Rec, Acct | Create invoice | Patient / consultation | Add lines, discount, tax, finalize | invoices | invoices | 7 |
| Invoice list / detail / preview (M16) | Rec, Acct, Admin | Review, print, share | Billing menu | View, PDF, void/credit note | invoices | invoices | 7 |
| Payment collection / receipt | Rec, Acct | Take payment | Invoice | Cash/UPI/card/online, receipt | payments | payments | 7 |
| Refunds | Acct, Admin | Process refunds | Invoice/payment | Initiate, approve | refunds | refunds | 7 |
| Expenses & categories | Acct, Admin | Track expenses | Finance menu | Add, categorise, vendor, attach | expenses | expenses | 7 |
| Lab orders & results | Lab, Nurse | Manage lab flow | Lab menu | Receive orders, enter results, upload report | lab_orders, lab_results | labs | 9 |
| Documents | Rec, Nurse, Admin | Patient documents | Patient details | Upload/download | documents | documents | 9 |
| Follow-up list | Rec, Doc | Manage follow-ups | Follow-ups menu | Remind, book, mark | followups | followups | 6 / 10 |
| Reports (M17) | Owner, Admin, Acct | Operational & financial reports | Reports menu | Filters, charts, export | aggregates | reports | 10 |
| Notification settings & templates | Owner, Admin | Configure | Settings | Channels, templates | clinic_settings, notifications | notifications | 10 |
| Audit log viewer | Owner, Admin | Review activity | Settings | Filter, export | audit_logs | audit | 11 (basic in 3) |
| Profile & security (M18) | All | Account | Top bar | Edit profile, password, MFA, sessions, logout | users | auth | 1 |

## 3. Doctor Workspace (DW)

| Screen | Role | Purpose | Entry | Main actions | Data | API domain | Phase |
|---|---|---|---|---|---|---|---|
| Login, forgot password, MFA | Doc | Authenticate | Start | As CW | users | auth | 1 |
| Accept invitation | Doc | Join clinic | Email | As CW | invites | auth | 3 |
| Clinic/branch switcher | Doc | Context | Top bar | Switch | members | auth | 3 |
| Dashboard (M8) | Doc | Today's schedule | Home | Stats, quick actions, next patient | appointments, queue | reports, appointments | 5 (stats 10) |
| Appointments list (M9) | Doc | Day/week schedule | Nav | Filter, open, start consultation | appointments | appointments | 5 |
| Queue (own) | Doc | Call next patient | Dashboard | Call, skip, complete | queue_entries | queues | 5 |
| Patient details / history (M11) | Doc | Clinical overview | Appointment | History, vitals, allergies, documents, prior consultations | patients, histories | patients | 4 / 6 |
| Consultation (M12) | Doc | Document the visit | Appointment | Complaint, symptoms, vitals, exam, diagnosis, plan; draft → in progress → finalize | consultations, templates | consultations, diagnoses | 6 |
| Consultation amendment | Doc | Amend finalized record | Consultation | Reason + changes, preserved original | consultations | consultations | 6 |
| Prescription (M13) | Doc | Prescribe | Consultation | Medicine search, dose, frequency, duration, route, preview, issue, PDF | prescriptions, medicine_catalogue | prescriptions | 6 |
| Lab request & results review | Doc | Order/review tests | Consultation | Order, view/acknowledge results | lab_orders, lab_results | labs | 6 / 9 |
| Follow-ups | Doc | Schedule/see follow-ups | Consultation / nav | Set date, reminders | followups | followups | 6 |
| Medical history / documents | Doc | Longitudinal view, files | Patient details | View, upload | documents | documents | 6 / 9 |
| Templates (choose/preview) | Doc | Specialty templates | Consultation | Select template | clinical_templates | clinical-templates | 6 |
| Own schedule & availability | Doc | Manage availability | Profile | Edit weekly rules, leave | doctors | doctors | 5 |
| Profile & settings (M18) | Doc | Account, signature, notification prefs | Nav | Edit, logout | doctors, users | doctors, auth | 3 |

## 4. Patient Android (PA)

| Screen | Role | Purpose | Entry | Main actions | Data | API domain | Phase |
|---|---|---|---|---|---|---|---|
| Splash (M1) | Pat | Branding / session check | Launch | – | – | – | 8 |
| Onboarding ×3 (M2-4) | Pat | Intro | First launch | Next/Skip/Get started | – | – | 8 |
| Registration | Pat | Create account | Onboarding | Phone verification (OTP), name, consent to terms/privacy | patient_accounts | patient-accounts, auth | 8 |
| Login (M19) | Pat, Care | Sign in | Launch | OTP / (decision D-3), biometric unlock | patient_accounts | auth | 8 |
| Patient profile | Pat | Own details | Profile tab | View/edit | patient_accounts | patient-accounts | 8 |
| Family profiles & dependents | Pat | Add dependents, caregivers | Profile | Add, relationship, scope, revoke | family_relationships, consents | patient-accounts, consents | 8 |
| Home (M20) | Pat | Entry point | After login | Quick actions, upcoming appointment | appointments | appointments | 8 |
| Clinic discovery & connection | Pat | Find and connect to a clinic | Home | Search, view, connect (code/QR), consent | tenants (public profile), patient_links | clinics, patient-accounts | 8 |
| Doctor discovery | Pat | Browse doctors | Clinic | Filter by specialty/branch, view availability | doctors | doctors | 8 |
| Appointment booking | Pat | Book | Doctor | Choose patient (self/dependent), slot, confirm | slots, appointments | appointments | 8 |
| Appointment confirmation | Pat | Confirmation and next steps | Booking | Add to calendar, view | appointments | appointments | 8 |
| Appointment history / details | Pat | History, cancel/reschedule | Appointments tab | View, cancel | appointments | appointments | 8 |
| Queue status | Pat | Live token | Appointment | View position, estimated time | queue_entries | queues | 8 |
| Prescriptions list / detail | Pat | Access Rx | Home | View, download PDF | prescriptions | prescriptions | 8 |
| Laboratory reports | Pat | Access results | Reports tab | View, download | lab_results, documents | labs, documents | 9 |
| Medical history / documents | Pat | Records from linked clinics | Reports tab | View, upload own docs | histories, documents | patients, documents | 8 / 9 |
| Invoices & payments | Pat | Pay online, receipts | Home | Pay (Razorpay), receipt | invoices, payments | invoices, payments | 8 (needs Phase 7) |
| Notifications | Pat | Inbox, preferences | Bell | View, mark read | notifications | notifications | 8 / 10 |
| Consent & privacy centre | Pat | Review/revoke access | Settings | Grant/revoke, access log | consents, audit | consents | 8 |
| Settings | Pat | App settings, language, logout, delete account | Profile | – | patient_accounts | patient-accounts | 8 |

## 5. Missing screens required for complete workflows (not in the mockup)

| Screen | App | Why needed | Phase |
|---|---|---|---|
| Forgot/reset password, email verification, MFA enrol/verify, session/device list | CW, DW | Account security (CLAUDE.md §13) | 1 |
| Platform admin console: tenant approval queue, tenant detail, plans, subscription status, platform audit | Separate platform area in CW (role-gated) | Module 1 | 2 |
| Accept-invitation, branch/clinic switcher, role & permission editor | CW, DW | Modules 3, 5 | 2-3 |
| Patient duplicate-check/merge-request, patient link/consent screens | CW | Patient identity rules (§7) | 4 |
| Check-in, queue display, walk-in registration | CW | Modules 8-9 | 5 |
| Consultation amendment history view | DW | §8 clinical rules | 6 |
| Prescription PDF preview/share, medicine catalogue admin | DW, CW | Module 11 | 6 |
| Invoice credit note/void, payment receipt, refund approval, reconciliation | CW | Modules 13-14 | 7 |
| Expense categories/vendors | CW | Module 15 | 7 |
| Lab catalogue, sample tracking | CW | Module 16 | 9 |
| Document viewer (secure) | All | Module 17 | 9 |
| Notification centre and preferences | All | Module 19 | 10 |
| Error pages (403, 404, offline, maintenance, force-update), session-expired dialog, empty states | All | UX quality bar | 1 (generic), then per feature |
| Data export / privacy request (access, correction, erasure) | PA, CW | DPDP rights | 4-11 |
| Terms, privacy policy, about, help & support | All | Compliance | 1 |
| Onboarding checklist (first-run guidance for new clinics) | CW | Activation | 2 |

## 6. Phase mapping summary

| Phase | Screens |
|---|---|
| 1 | Login, reset, MFA, profile/security, error/offline pages (CW, DW) |
| 2 | Owner sign-up, clinic setup, settings, branches, subscription, platform console, switcher |
| 3 | Doctors, staff, invitations, roles, DW profile |
| 4 | Patients (list, form, details, linking, family/consent on CW side) |
| 5 | Appointments, availability, queue, check-in, DW dashboard & schedule |
| 6 | Consultation, amendment, prescription, templates, lab request, follow-ups |
| 7 | Billing, payments, refunds, expenses |
| 8 | Entire PA core (auth, discovery, booking, queue, Rx, consent) |
| 9 | Lab, documents, reports in PA |
| 10 | Dashboards/reports, notification centre/settings |
| 11 | Audit viewer completion, accessibility/perf fixes |
