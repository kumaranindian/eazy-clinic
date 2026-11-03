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

Current:

```
eazy-clinic/
├── CLAUDE.md   # Development rules and architecture requirements
└── README.md
```

The application and backend structure will be defined during Phase 0 and documented in `docs/`.

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

There is no runnable code yet. Once Phase 0 and Phase 1 are complete, setup instructions (Flutter and Dart SDK versions, Firebase environment configuration, running the backend and apps) will be added here.

For now, read [CLAUDE.md](CLAUDE.md) for the project's development rules.

## Development Status

**Project initialization.** The repository contains documentation only. No phases have been implemented.

## License and Ownership

© Avail404 (OPC) Private Limited. All rights reserved.
