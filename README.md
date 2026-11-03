# EazyClinic

**You Care. We Manage.**

EazyClinic is a product of **Avail404 (OPC) Private Limited**.

> **Development status: Project initialization.** Nothing described below as a feature has been implemented yet. This README describes the planned product; see [Development Status](#development-status).

## Overview

EazyClinic is a configurable, multi-tenant clinic management SaaS, initially for the Indian market. It supports single-doctor clinics, multi-doctor and multi-specialty clinics, and multi-branch healthcare organizations, so that doctors can focus on patient care while the platform handles administration and operations.

### Vision

A complete healthcare operations platform, not a collection of disconnected CRUD screens: patient registration, appointments, queue, consultation, prescription, billing and follow-up working together end to end.

### Mission

Take clinic administration off doctors' hands with a secure, easy-to-use, commercially deployable platform that protects patient data and keeps each clinic's records isolated.

## Target Users

- Platform administrators (Super Admin, Platform Support Admin)
- Clinic owners and clinic administrators
- Doctors
- Receptionists, nurses, accountants, laboratory technicians (and optionally pharmacists)
- Patients, and their authorized family members / caregivers

## Applications

| Application | Platform | Purpose |
|---|---|---|
| **EazyClinic** – Clinic Management Web | Flutter Web | Clinic setup, branches, staff, patients, appointments, queue, billing, expenses, reports, subscriptions |
| **EazyClinic Doctor** – Doctor Workspace | Flutter Web, Flutter Android | Appointments, patient history, consultations, prescriptions, lab requests, follow-ups |
| **EazyClinic Patient** – Patient Android App | Flutter Android | Registration, clinic and doctor discovery, booking, queue status, prescriptions, reports, family profiles |

All three applications use the same backend APIs, business rules and data model.

## Technology Stack

| Layer | Technology |
|---|---|
| Frontend | Flutter (Web and Android) |
| Backend | Dart with Shelf (REST, `/api/v1`) |
| Authentication | Firebase Authentication |
| Database | Cloud Firestore |
| File storage | Firebase Storage |
| Notifications | Firebase Cloud Messaging |
| Payments | Razorpay |
| State management | Riverpod |
| Navigation | GoRouter |

Further choices (charts, HTTP client, serialization, testing) are defined in [CLAUDE.md](CLAUDE.md).

## Planned Functional Modules

SaaS platform management · clinic setup · branches · doctors · staff · patients · family and dependents · appointments · queue and tokens · consultations · prescriptions · clinical templates · billing and invoicing · payments · expenses · laboratory · medical documents · follow-ups · notifications · dashboards and reports · security and audit.

The detailed module list is in [CLAUDE.md](CLAUDE.md), section 6.

## High-Level Architecture

- Multi-tenant: every clinic's data is isolated. The backend derives tenant membership, branch access and role permissions from trusted server-side records, never from client-supplied values.
- Flutter clients call the Shelf REST API; privileged operations use the Firebase Admin SDK on the backend only.
- Patient identity (global patient account) is separate from clinic-specific patient records. Each clinic controls its own medical records, and access is consent-based and audited.
- Payments are verified on the backend (Razorpay signatures and webhooks).

## Repository Structure

```
eazy-clinic/
├── CLAUDE.md, README.md
├── apps/
│   ├── clinic_web/      # EazyClinic – Clinic Management (Flutter Web)
│   ├── doctor_mobile/   # EazyClinic Doctor (Flutter Web + Android)
│   └── patient_mobile/  # EazyClinic Patient (Flutter Android)
├── backend/             # Dart + Shelf REST API (/api/v1)
├── packages/            # common_models, api_contracts, validation, utilities, design_system
├── assets/              # brand (original logo preserved), fonts, icons
├── firebase/            # deny-all rules and index definitions (nothing deployed)
├── environments/        # dev / staging / production templates (placeholders only)
├── docs/                # architecture, database, api, security, design, development, testing, deployment
└── scripts/             # check_all.sh, run_backend.sh, sync_brand_assets.sh
```

Details: [docs/architecture/REPOSITORY_STRUCTURE.md](docs/architecture/REPOSITORY_STRUCTURE.md).

## Development Phases

0. Repository inspection and architecture
1. Foundation and authentication
2. Multi-tenant and clinic setup
3. Users, doctors and staff
4. Patient management
5. Appointments and queue
6. Clinical operations
7. Billing and payments
8. Patient Android application
9. Laboratory and documents
10. Reports and notifications
11. Production readiness

## Environments

Three isolated environments, each with its own Firebase configuration:

- **dev** – local and development work
- **staging** – UAT and pre-release verification
- **production** – live; changes require explicit approval

## Getting Started

Prerequisites: Flutter 3.32+ (Dart 3.8+), Android SDK for the Android apps, Chrome for web.

```bash
scripts/check_all.sh          # format, analyze and test every project
scripts/run_backend.sh dev    # backend on :8080 → GET /health
```

Running the apps and environment configuration: [docs/development/DEVELOPMENT_SETUP.md](docs/development/DEVELOPMENT_SETUP.md).
Documentation index: [docs/IMPLEMENTATION_ROADMAP.md](docs/IMPLEMENTATION_ROADMAP.md) · [docs/IMPLEMENTATION_PROGRESS.md](docs/IMPLEMENTATION_PROGRESS.md).

## Development Status

**Phase 0 (foundation) implemented, awaiting review.** Available: monorepo, three Flutter app shells, Shelf backend with `GET /health`, shared packages,
the EazyClinic design system, and the architecture/database/API/security documentation.
**No business functionality exists yet** (no authentication, clinics, patients, appointments, consultations, billing or Firebase integration). See [docs/IMPLEMENTATION_PROGRESS.md](docs/IMPLEMENTATION_PROGRESS.md).

## License and Ownership

© Avail404 (OPC) Private Limited. All rights reserved.
