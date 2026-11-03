# CLAUDE.md – EazyClinic Development Instructions

## 1. Project Identity

**Product Name:** EazyClinic  
**Company:** Avail404 (OPC) Private Limited  
**Tagline:** You Care. We Manage.  
**Product Type:** Multi-tenant Healthcare / Clinic Management SaaS  
**Initial Market:** India  
**Primary Goal:** Help doctors focus on patient care while EazyClinic manages clinic administration and operational workflows.

EazyClinic is a configurable clinic management platform designed for:

- Individual doctors and single-doctor clinics
- Multi-doctor clinics
- Multi-specialty clinics
- Multi-branch healthcare organizations
- General practitioners and specialist doctors

This is a commercial SaaS product. All implementation decisions must prioritize security, maintainability, scalability, usability, and production readiness.

---

## 2. Core Development Objective

Build a complete clinic management ecosystem consisting of three connected applications.

### Application 1: Clinic Management Web

Primary users:
- Platform administrators
- Clinic owners
- Clinic administrators
- Receptionists
- Nurses
- Accountants
- Laboratory technicians

Responsibilities:
- Clinic configuration
- Branch management
- Doctor and staff management
- Patient registration
- Appointment scheduling
- Queue management
- Billing and payment collection
- Expenses
- Reports
- Notifications
- Subscription management

### Application 2: Doctor Workspace

Platforms:
- Flutter Web
- Flutter Android

Primary responsibilities:
- Daily appointment management
- Patient medical history
- Consultation management
- Clinical observations and vitals
- Diagnosis
- Prescription creation
- Laboratory requests
- Follow-up scheduling
- Medical document management

### Application 3: Patient Android Application

Primary responsibilities:
- Patient registration and authentication
- Clinic discovery and connection
- Doctor discovery
- Appointment booking
- Appointment history
- Queue status
- Prescription access
- Laboratory report access
- Medical history access
- Notifications
- Family and dependent profiles

All three applications must use the same backend APIs, business rules, and data model.

Do not duplicate business logic across applications.

---

## 3. Mandatory Technology Stack

Use the following technologies unless an architectural decision is formally documented.

| Layer | Technology |
|---|---|
| Frontend | Flutter |
| Web | Flutter Web |
| Mobile | Flutter Android |
| Backend | Dart |
| REST Framework | Shelf |
| Database | Firebase Firestore |
| Authentication | Firebase Authentication |
| File Storage | Firebase Storage |
| Notifications | Firebase Cloud Messaging |
| Payments | Razorpay |
| State Management | Riverpod |
| Navigation | GoRouter |
| Charts | FL Chart |
| API Communication | Dio or an established project HTTP client |
| Serialization | JSON serialization with generated models |
| Testing | Flutter Test, Dart Test, integration tests |

### Important rules

1. Use Dart for backend development.
2. Use Shelf for REST APIs.
3. Use Firebase Admin SDK for privileged backend operations.
4. Never expose Firebase Admin credentials in Flutter applications.
5. Never put Razorpay secret keys in client applications.
6. All financial transactions must be verified by the backend.
7. Use Firestore indexes for complex queries.
8. Use environment-specific Firebase configurations.
9. Keep development, staging/UAT, and production environments isolated.
10. Do not introduce additional frameworks without documenting the reason.

---

## 4. Product Architecture

Use a modular, multi-tenant SaaS architecture.

The platform must support:

- Multiple clinics
- Multiple branches per clinic
- Multiple doctors per clinic
- Multiple staff members
- Multiple patients
- Different subscription plans
- Clinic-specific settings
- Clinic-specific consultation templates
- Clinic-specific billing configurations
- Specialty-specific workflows

### Tenant isolation

Every clinic must have isolated data.

The backend must derive the authenticated user's tenant membership from trusted server-side records.

Never trust a tenant ID, branch ID, role, or permission supplied directly by the client.

Every sensitive API must validate:

1. Firebase authentication.
2. Tenant membership.
3. Branch access.
4. Role permissions.
5. Resource ownership or relationship.
6. Patient consent and access authorization where applicable.

A user from Clinic A must never access Clinic B's data without explicit authorization.

---

## 5. User Roles and Permissions

Implement role-based access control (RBAC).

### Platform-level roles

- Super Admin
- Platform Support Admin

### Clinic-level roles

- Clinic Owner
- Clinic Admin
- Doctor
- Receptionist
- Nurse
- Accountant
- Lab Technician
- Pharmacist (optional)

### Patient-level role

- Patient
- Authorized Family Member / Caregiver

Permissions must be configurable.

Do not hardcode all permissions inside UI widgets.

Create centralized permission definitions and backend authorization policies.

Examples:

| Feature | Doctor | Receptionist | Accountant |
|---|---|---|---|
| Patient registration | Yes | Yes | Limited |
| View medical history | Authorized | Restricted | No |
| Consultation | Yes | No | No |
| Prescription | Yes | No | No |
| Appointment management | Yes | Yes | No |
| Invoice generation | Optional | Yes | Yes |
| Payment collection | Optional | Yes | Yes |
| Financial reports | Restricted | No | Yes |

The actual permissions must be configurable by the clinic owner.

---

## 6. Functional Modules

Implement the following modules in a modular architecture.

### Module 1: SaaS Platform Management

- Platform dashboard
- Clinic registration
- Clinic approval
- Tenant management
- Subscription plans
- Subscription lifecycle
- Trial management
- Payment status
- Platform-level audit logs

### Module 2: Clinic Setup

- Clinic profile
- Clinic logo
- Contact details
- Address
- Working hours
- Holidays
- Consultation fees
- Clinic configuration
- Specialty configuration
- Appointment policies
- Invoice configuration

### Module 3: Branch Management

- Add branch
- Edit branch
- Branch-specific working hours
- Branch-specific doctors
- Branch-specific staff
- Branch-specific appointments
- Branch-level reports

### Module 4: Doctor Management

- Doctor profile
- Qualification
- Registration information
- Specialization
- Consultation fees
- Availability
- Appointment slots
- Branch assignments
- Signature configuration

### Module 5: Staff Management

- Staff registration
- Role assignment
- Permission management
- Branch assignment
- Account activation/deactivation
- Invitation workflow

### Module 6: Patient Management

- Patient registration
- Unique patient ID
- Contact information
- Demographic details
- Medical history
- Allergies
- Chronic conditions
- Previous visits
- Patient documents
- Patient search

### Module 7: Family and Dependent Management

- Family profiles
- Dependent registration
- Guardian relationships
- Authorized caregiver access
- Consent management
- Access revocation

### Module 8: Appointment Management

- Appointment booking
- Doctor selection
- Branch selection
- Availability
- Slot management
- Rescheduling
- Cancellation
- Appointment reminders
- Appointment status

### Module 9: Queue and Token Management

- Daily token generation
- Doctor-wise queue
- Waiting status
- In consultation
- Completed
- Cancelled
- No-show
- Queue display
- Real-time queue updates

### Module 10: Consultation Management

- Consultation creation
- Chief complaint
- Symptoms
- Vitals
- Examination notes
- Clinical observations
- Diagnosis
- Treatment plan
- Doctor notes
- Follow-up recommendations
- Consultation finalization

### Module 11: Prescription Management

- Medicine catalogue
- Medicine search
- Dosage
- Frequency
- Duration
- Route
- Instructions
- Prescription preview
- PDF generation
- Prescription history
- Doctor authorization

### Module 12: Clinical Templates

Provide configurable templates for:

- General Medicine
- Paediatrics
- Dentistry
- Dermatology
- Gynaecology
- Physiotherapy

Templates should support configurable fields and specialty-specific workflows.

Do not create separate applications for different specialties.

### Module 13: Billing and Invoicing

- Consultation charges
- Medicine charges
- Laboratory charges
- Additional service charges
- Discounts
- Tax configuration
- Invoice generation
- Invoice PDF
- Payment status
- Outstanding balances
- Refund management

### Module 14: Payment Management

- Cash
- UPI
- Card
- Online payment
- Razorpay integration
- Payment verification
- Payment receipts
- Refunds
- Payment reconciliation

### Module 15: Expense Management

- Expense categories
- Expense entries
- Vendor details
- Payment methods
- Expense reports
- Monthly summaries

### Module 16: Laboratory Management

- Test catalogue
- Laboratory orders
- Test status
- Result entry
- Report uploads
- Doctor review
- Patient report access

Full laboratory equipment integration is not part of the initial MVP.

### Module 17: Medical Documents

- Patient documents
- Consultation documents
- Prescription PDFs
- Laboratory reports
- Medical certificates
- Upload and download
- Secure document access

### Module 18: Follow-up Management

- Follow-up date
- Doctor assignment
- Follow-up reminders
- Previous consultation reference
- Follow-up status

### Module 19: Notifications

- Appointment confirmation
- Appointment reminders
- Queue updates
- Prescription availability
- Laboratory report availability
- Payment notifications
- Follow-up reminders

Support push notifications first. Keep SMS and WhatsApp integration configurable for future expansion.

### Module 20: Dashboard and Reports

Provide dashboards for:

- Clinic owner
- Clinic admin
- Doctor
- Receptionist
- Accountant

Reports should include:

- Total appointments
- Daily patient visits
- New patients
- Returning patients
- Doctor performance
- Consultation statistics
- Revenue
- Collections
- Outstanding payments
- Expenses
- Monthly trends

### Module 21: Security and Audit

- User login history
- Role changes
- Patient record access logs
- Consultation modification logs
- Prescription history
- Payment logs
- Document access logs
- Consent history
- Security event tracking

---

## 7. Patient Identity and Medical Record Rules

This is a critical architectural requirement.

A patient may visit multiple clinics.

Therefore:

1. Patient identity must be separate from clinic-specific patient records.
2. A patient can have one patient account and multiple clinic relationships.
3. Each clinic controls its own medical records.
4. A clinic must not automatically access another clinic's consultation history.
5. Phone number alone must never authorize access to an existing medical record.
6. Account linking must require identity verification and appropriate clinic authorization.
7. Family/dependent access must have an explicit authorized relationship.
8. Consent and authorization must be recorded and revocable.
9. Patient data access must be audited.

Use separate entities for global patient accounts and clinic-specific patient records.

---

## 8. Clinical Workflow Rules

Follow this consultation lifecycle:

Draft → In Progress → Finalized → Amended

Rules:

- Doctors can edit draft consultations.
- Doctors can finalize completed consultations.
- Finalized records must not be silently overwritten.
- Amendments must preserve the original record and record the reason, author, and timestamp.
- Prescriptions must be authorized by the responsible doctor.
- Clinical data must never be fabricated or automatically filled with unverified medical information.
- AI features, if introduced later, must not independently diagnose or prescribe.

Clinical decisions remain the responsibility of qualified healthcare professionals.

---

## 9. Firestore Database Architecture

Use logical collections with clear tenant boundaries.

### Platform-level collections

- `platform_users`
- `tenants`
- `subscription_plans`
- `platform_subscriptions`
- `platform_audit_logs`
- `clinic_invites`

### Tenant-level collections

- `clinic_settings`
- `branches`
- `members`
- `roles`
- `doctors`
- `staff`
- `patients`
- `patient_accounts`
- `patient_links`
- `family_relationships`
- `appointments`
- `appointment_slots`
- `queue_entries`
- `consultations`
- `diagnoses`
- `prescriptions`
- `medicine_catalogue`
- `clinical_templates`
- `medical_histories`
- `vitals`
- `lab_orders`
- `lab_results`
- `documents`
- `invoices`
- `payments`
- `refunds`
- `expenses`
- `followups`
- `notifications`
- `consents`
- `audit_logs`

### Database design rules

1. Use stable document IDs.
2. Include timestamps for important records.
3. Use explicit status fields.
4. Include createdBy and updatedBy where appropriate.
5. Include tenant and branch references where applicable.
6. Avoid uncontrolled duplication of patient information.
7. Design indexes before implementing complex queries.
8. Use transactions or batched writes when required for data consistency.
9. Use backend-controlled writes for sensitive workflows.
10. Document every collection and important field.

Do not put all application data into one large collection.

---

## 10. Backend API Architecture

Use versioned REST APIs.

Base path:

`/api/v1`

Organize endpoints by domain:

- `/auth`
- `/platform`
- `/clinics`
- `/branches`
- `/members`
- `/doctors`
- `/patients`
- `/patient-accounts`
- `/appointments`
- `/queues`
- `/consultations`
- `/diagnoses`
- `/prescriptions`
- `/clinical-templates`
- `/invoices`
- `/payments`
- `/refunds`
- `/expenses`
- `/labs`
- `/documents`
- `/followups`
- `/notifications`
- `/reports`
- `/consents`
- `/audit`

### API rules

- Use standard HTTP methods.
- Use consistent response formats.
- Validate every request.
- Return meaningful HTTP status codes.
- Implement centralized exception handling.
- Implement pagination and filtering.
- Use idempotency for payment and booking operations where appropriate.
- Never expose internal stack traces to clients.
- Maintain API documentation.
- Verify Firebase ID tokens on protected endpoints.

All sensitive business logic must be executed on the backend.

---

## 11. UI/UX and Branding Instructions

The entire application must follow the approved EazyClinic brand identity.

### Brand identity

Product: EazyClinic  
Tagline: You Care. We Manage.

### Brand colours

| Purpose | Colour | Hex |
|---|---|---|
| Primary Navy | Deep Medical Navy | #103B64 |
| Brand Red | Healthcare Red | #E92335 |
| Accent Blue | Medical Blue | #087FAF |
| Background | Light Grey | #F8FAFC |
| Surface | White | #FFFFFF |
| Primary Text | Dark Grey | #1F2937 |
| Secondary Text | Grey | #6B7280 |
| Border | Light Grey | #E5E7EB |
| Success | Green | #16A34A |
| Warning | Amber | #D97706 |
| Error | Red | #DC2626 |

### Design rules

1. Use the approved EazyClinic logo.
2. Use Inter as the primary font.
3. Use a clean, modern healthcare design.
4. Use white surfaces and light backgrounds.
5. Use navy for navigation and structural elements.
6. Use red for primary actions and important brand highlights.
7. Use blue for secondary actions and informational elements.
8. Avoid excessive red backgrounds.
9. Use consistent spacing, typography, cards, icons, and buttons.
10. Make the web interface responsive.
11. Design mobile screens for practical one-handed usage.
12. Support loading, empty, error, success, and disabled states.
13. Include proper form validation and clear error messages.
14. Avoid unnecessary animations.
15. Do not use generic or outdated admin dashboard templates.

### UI quality expectations

Every screen must be designed as a production application screen, not a prototype.

Provide:
- Clear page hierarchy
- Consistent navigation
- Search and filtering
- Useful data tables
- Confirmation dialogs for destructive actions
- Appropriate loading indicators
- Empty-state illustrations or guidance
- Responsive layouts
- Accessible contrast and readable text

Before implementing a new module, review its complete workflow and required screens.

---

## 12. Flutter Development Standards

Use a feature-first folder structure.

Example:

`lib/`
- `core/`
  - `config/`
  - `constants/`
  - `errors/`
  - `network/`
  - `routing/`
  - `security/`
  - `theme/`
  - `utils/`
- `shared/`
  - `widgets/`
  - `models/`
  - `services/`
- `features/`
  - `authentication/`
  - `dashboard/`
  - `clinics/`
  - `branches/`
  - `doctors/`
  - `staff/`
  - `patients/`
  - `appointments/`
  - `queue/`
  - `consultations/`
  - `prescriptions/`
  - `billing/`
  - `payments/`
  - `laboratory/`
  - `documents/`
  - `reports/`
  - `settings/`

Each feature should contain appropriate layers:

- data
- domain
- presentation

Use Riverpod for state management.

Use GoRouter for navigation.

Separate UI, business logic, API services, and data models.

Avoid:
- Large monolithic widgets
- Business logic inside UI widgets
- Duplicate API calls
- Hardcoded IDs
- Hardcoded tenant information
- Direct Firestore access for privileged operations
- Unnecessary dependencies
- Unstructured global state

---

## 13. Security and Privacy Requirements

Healthcare information is sensitive.

Security must be treated as a core product requirement.

Implement:

1. Firebase Authentication.
2. Backend token verification.
3. Role-based authorization.
4. Tenant and branch isolation.
5. Patient relationship validation.
6. Patient consent management.
7. Firestore security rules.
8. Storage security rules.
9. Audit logs.
10. Secure document access.
11. Session revocation.
12. Rate limiting for sensitive endpoints.
13. Input validation and sanitization.
14. Payment verification.
15. Backup and recovery procedures.
16. Secure handling of secrets.
17. MFA for privileged users where supported.

Never assume that hiding a UI button is sufficient security.

Every sensitive action must be authorized on the backend.

Design for applicable Indian data protection requirements, including the Digital Personal Data Protection Act and relevant rules.

Keep future ABDM/ABHA integration in mind, but do not claim ABDM compliance or connectivity until the relevant integration and verification work is completed.

---

## 14. Payment and Financial Rules

Financial workflows must be reliable and auditable.

- Never trust payment success reported by the client.
- Verify Razorpay payment signatures on the backend.
- Verify webhook events.
- Implement idempotency.
- Prevent duplicate payment records.
- Preserve payment history.
- Record refunds separately.
- Keep invoices immutable after finalization; use proper credit or adjustment records.
- Maintain accurate outstanding balances.
- Record who performed each financial action.

Do not store card details or sensitive payment credentials.

---

## 15. Testing Requirements

Every module must include appropriate tests.

### Unit testing
- Business logic
- Validation
- Calculations
- Permission policies
- Status transitions

### API testing
- Authentication
- Authorization
- Request validation
- Response formats
- Tenant isolation
- Error handling

### Integration testing
- Firebase integration
- Firestore operations
- Payment workflows
- Notifications
- Document uploads

### UI testing
- Login
- Registration
- Navigation
- Forms
- Search
- Appointment booking
- Consultation
- Billing

### Security testing
- Unauthorized access
- Cross-tenant access
- Role escalation
- Patient record access
- Document access
- Payment manipulation
- Invalid tokens

Never mark a feature complete merely because the screen renders.

---

## 16. Development Workflow – Mandatory

Follow this process for every module.

### Step 1: Inspect

Before coding:
- Inspect the current repository.
- Understand the existing architecture.
- Review relevant files.
- Identify reusable components.
- Check dependencies.
- Identify incomplete or broken functionality.

Never assume that a feature does not exist without checking.

### Step 2: Plan

Create a module implementation plan covering:
- Functional requirements
- User roles
- Screen list
- User workflows
- Database collections
- API endpoints
- Permission requirements
- Validation rules
- Error scenarios
- Test cases

Update the relevant documentation.

### Step 3: Design

Design the required screens using the approved EazyClinic design system.

Ensure all screens support their intended user workflows.

### Step 4: Implement

Implement:
- Models
- Validation
- Backend APIs
- Database operations
- Permissions
- State management
- UI screens
- Navigation
- Error handling

Follow existing architectural conventions.

### Step 5: Test

Run:
- Formatting
- Static analysis
- Unit tests
- API tests
- Integration tests where applicable
- Build verification

Fix issues before moving to the next module.

### Step 6: Document

Update:
- Feature implementation status
- API documentation
- Database documentation
- User workflows
- Technical decisions
- Known limitations

### Step 7: Report

At the end of each implementation task, provide:

1. What was implemented.
2. Files created or modified.
3. APIs added or modified.
4. Database changes.
5. Tests executed and results.
6. Known issues.
7. Remaining work.
8. Recommended next step.

---

## 17. Project Documentation

Maintain the following documentation (layout established in Phase 0; it supersedes the earlier flat list):

`docs/`
- `REPOSITORY_ASSESSMENT.md`, `IMPLEMENTATION_ROADMAP.md`, `IMPLEMENTATION_PROGRESS.md`, `TECHNICAL_DEBT.md`
- `architecture/` – `MASTER_ARCHITECTURE.md` (includes ADRs), `REPOSITORY_STRUCTURE.md`, `MULTI_TENANT_ARCHITECTURE.md`
- `database/` – `DATABASE_SCHEMA.md`, `DATABASE_RELATIONSHIPS.md`
- `api/` – `API_STANDARDS.md`
- `security/` – `SECURITY_ARCHITECTURE.md`, `RBAC_PERMISSION_MATRIX.md`
- `design/` – `DESIGN_SYSTEM.md`, `UI_UX_REFERENCE_ANALYSIS.md`, `SCREEN_INVENTORY.md`
- `development/` – `DEVELOPMENT_SETUP.md`, `CODING_STANDARDS.md`
- `testing/` – `TESTING_STRATEGY.md`
- `deployment/` – `ENVIRONMENT_STRATEGY.md`
- Added in later phases: patient data privacy (Phase 4), user workflows (per module), production readiness checklist (Phase 11).

Update documentation whenever a significant implementation decision or feature changes.

Do not allow documentation to contradict the actual code.

---

## 17a. Repository Layout and Standing Decisions (added in Phase 0)

- Monorepo: `apps/{clinic_web,doctor_mobile,patient_mobile}`, `backend/`, `packages/{common_models,api_contracts,validation,utilities,design_system}`, `assets/`, `firebase/`, `environments/`, `docs/`, `scripts/`. Path dependencies, no workspace tool.
- Official brand references: `assets/branding/original/EazyClinic Caring Healthcare Logo.png` (never modify; use `EcBrandLogo`) and `docs/design/reference/EazyClinic Healthcare App Flow Mockup (1).png` (visual direction only, not a functional spec).
- All UI uses `packages/design_system` tokens and components. No hex colours, font sizes or one-off buttons in feature code.
- Every API response uses the `api_contracts` envelope; errors use `ApiErrorCode`.
- Firestore/Storage rules are deny-all for clients; the backend is the only data path. Tenant data lives under `tenants/{tenantId}/` (see `docs/database/DATABASE_SCHEMA.md`).
- Configuration: backend via environment variables, apps via `--dart-define-from-file`; both validated at startup. Only `*.example.*` templates are committed.
- Run `scripts/check_all.sh` before every commit that changes code.
- Git: `master` ← `develop` ← `feature/*`; never push, merge or deploy without explicit approval.
- Open decision before Phase 1: how the Dart backend accesses Firebase (Admin SDK options) - see `docs/TECHNICAL_DEBT.md` TD-01.

---

## 18. Implementation Phases

Do not attempt to build the entire system in one operation.

Implement in the following sequence.

### Phase 0 – Repository Inspection and Architecture
- Repository inspection
- Architecture validation
- Project structure
- Environment configuration
- Coding conventions
- Documentation

### Phase 1 – Foundation and Authentication
- Flutter foundation
- Backend foundation
- Firebase initialization
- Authentication
- API client
- Error handling
- Logging

### Phase 2 – Multi-Tenant and Clinic Setup
- Tenant management
- Clinic registration
- Branch management
- Clinic settings
- Subscription foundation

### Phase 3 – Users, Doctors and Staff
- Doctor profiles
- Staff management
- Roles and permissions
- Invitations
- Branch assignments

### Phase 4 – Patient Management
- Patient registry
- Patient accounts
- Patient linking
- Family profiles
- Medical history
- Vitals
- Consent

### Phase 5 – Appointments and Queue
- Doctor availability
- Appointment slots
- Booking
- Rescheduling
- Cancellation
- Token generation
- Queue management

### Phase 6 – Clinical Operations
- Consultation
- Examination
- Diagnosis
- Clinical templates
- Prescription
- Follow-up

### Phase 7 – Billing and Payments
- Invoice
- Payment collection
- Razorpay
- Receipts
- Refunds
- Expenses

### Phase 8 – Patient Android Application
- Patient authentication
- Clinic connection
- Clinic and doctor discovery
- Appointment booking
- Appointment history
- Queue status
- Prescriptions
- Reports
- Notifications

### Phase 9 – Laboratory and Documents
- Lab catalogue
- Lab orders
- Results
- Report uploads
- Medical documents

### Phase 10 – Reports and Notifications
- Dashboards
- Reports
- FCM
- Reminders
- Notification preferences

### Phase 11 – Production Readiness
- Security audit
- Tenant-isolation testing
- Performance testing
- Backup validation
- Error monitoring
- Deployment
- Production verification

---

## 19. Rules Claude Code Must Never Violate

1. Never rewrite existing working modules without a valid reason.
2. Never delete existing functionality to make a new feature easier.
3. Never make production Firebase changes without explicit approval.
4. Never deploy to production without explicit approval.
5. Never delete production data.
6. Never expose secrets or credentials.
7. Never bypass authentication or authorization for convenience.
8. Never use mock data in production workflows.
9. Never report a feature as complete without testing it.
10. Never silently change the agreed architecture.
11. Never introduce an unnecessary dependency.
12. Never create duplicate models, services, or widgets when reusable implementations already exist.
13. Never make clinical or financial records editable without appropriate audit controls.
14. Never assume that patient phone-number ownership grants access to existing medical records.
15. Never trust client-supplied tenant IDs or permissions.
16. Never store sensitive clinical information in application logs.
17. Never make unverified medical claims in generated content.

If an architectural change is necessary, explain the reason and document it before implementation.

---

## 20. Final Product Quality Standard

EazyClinic must be developed as a commercially deployable SaaS product.

The application must be:

- Secure
- Scalable
- Multi-tenant
- Responsive
- Reliable
- Maintainable
- Easy to use
- Well documented
- Thoroughly tested
- Production ready

Prioritize complete end-to-end workflows over isolated screens.

For example, appointment management is not complete until a patient can be registered, an appointment can be booked, a queue token can be generated, the doctor can complete a consultation, and the appointment status can be updated correctly.

**Final development principle:**

Build EazyClinic as a complete healthcare operations platform, not as a collection of disconnected CRUD screens.

**EazyClinic – You Care. We Manage.**
