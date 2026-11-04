@Tags(['emulator'])
library;

import 'dart:io';

import 'package:backend/core/data/document_store.dart';
import 'package:backend/core/data/firestore_document_store.dart';
import 'package:backend/features/clinic/branches/branch_service.dart';
import 'package:backend/features/clinic/common/clinic_deps.dart';
import 'package:backend/features/clinic/common/seat_service.dart';
import 'package:backend/features/clinic/common/tenant_context.dart';
import 'package:backend/features/clinic/doctors/doctor_service.dart';
import 'package:backend/features/clinical/clinical_module.dart';
import 'package:backend/features/patients/patient_module.dart';
import 'package:backend/features/platform/audit/audit_service.dart';
import 'package:backend/features/platform/entitlements/entitlement_service.dart';
import 'package:backend/features/scheduling/scheduling_module.dart';
import 'package:common_models/common_models.dart';
import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import '../support/patient_fixtures.dart' show patientBody;
import '../support/platform_http_fixtures.dart'
    show MemoryObjectStorage, branchBody;
import '../support/scheduling_fixtures.dart' show weekly;

class _Client extends http.BaseClient {
  _Client(this._inner);
  final http.Client _inner;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers['authorization'] = 'Bearer owner';
    return _inner.send(request);
  }
}

/// The clinical workflow on the real Firestore REST store: appointment and
/// queue integration, consultation lifecycle with versions and amendments,
/// prescription numbering and amendment chain, vitals, follow-up range queries
/// and tenant isolation. Sequential (the emulator serializes transactions).
void main() {
  final host = Platform.environment['FIRESTORE_EMULATOR_HOST'];

  group(
    'clinical workflow on the Firestore emulator',
    () {
      test(
        'visit, consultation, prescription, amendment, follow-up and isolation',
        () async {
          final store = FirestoreDocumentStore(
            projectId: 'demo-eazyclinic',
            host: 'http://$host',
            client: _Client(http.Client()),
          );
          final suffix = DateTime.now().microsecondsSinceEpoch.toString();
          final start = DateTime.now().toUtc();
          Future<String> tenant(String tag) async {
            final tid = 'ten_$tag$suffix';
            await store.commit([
              CreateOp('tenants/$tid', {
                'tenantId': tid,
                'clinicName': 'Emu $tag',
                'status': 'active',
                'subscriptionId': 'sub_$tag$suffix',
                'createdAt': start,
              }),
              CreateOp('platform_subscriptions/sub_$tag$suffix', {
                'subscriptionId': 'sub_$tag$suffix',
                'tenantId': tid,
                'status': 'active',
                'name': 'P',
                'planId': 'p',
                'limits': {
                  'max_branches': 2,
                  'max_doctors': 3,
                  'max_staff': 3,
                  'max_patients': null,
                },
                'features': {
                  'multiple_branches': true,
                  'appointments': true,
                  'doctor_workspace': true,
                },
                'startDate': start,
                'endDate': start.add(const Duration(days: 60)),
                'overrides': <String, Object?>{},
              }),
            ]);
            return tid;
          }

          ClinicDeps depsAt(DateTime Function() clock) => ClinicDeps(
            store: store,
            audit: AuditService(store, clock: clock),
            seats: SeatService(store, clock: clock),
            entitlements: EntitlementService(store, clock: clock),
            clock: clock,
          );
          ClinicalModule clinicalAt(ClinicDeps d) {
            final patients = PatientModule(d, MemoryObjectStorage());
            final sched = SchedulingModule(d, patients.support);
            return ClinicalModule(d, patients.support, sched);
          }

          final deps = depsAt(() => start);
          final patients = PatientModule(deps, MemoryObjectStorage());
          final sched = SchedulingModule(deps, patients.support);
          final clin = ClinicalModule(deps, patients.support, sched);
          final branches = BranchService(deps);
          final doctors = DoctorService(deps, branches);
          final tidA = await tenant('a');
          final tidB = await tenant('b');

          Future<TenantContext> ctx(
            String tid,
            ClinicRole role, {
            String uid = 'staff',
            ClinicDeps? d,
          }) async => TenantContext(
            tenantId: tid,
            uid: '$uid$suffix',
            role: role,
            scope: const BranchScope(allBranches: true, branchIds: {}),
            entitlements: await (d ?? deps).entitlements.forTenant(tid),
          );

          final owner = await ctx(tidA, ClinicRole.clinicOwner, uid: 'owner');
          final ownerB = await ctx(tidB, ClinicRole.clinicOwner, uid: 'ownerB');
          final br =
              (await branches.create(
                    owner,
                    branchBody(code: 'EMU'),
                  ))['branchId']!
                  as String;
          await branches.create(ownerB, branchBody(code: 'EMUB'));
          final doc =
              (await doctors.create(owner, {
                    'fullName': 'Dr Emu Test',
                    'email': 'dr$suffix@example.test',
                    'phone': '9876543211',
                    'registrationNumber': 'EMU/$suffix',
                    'branchIds': [br],
                  }))['doctorId']!
                  as String;
          final type =
              (await sched.types.create(owner, {
                    'name': 'General',
                    'durationMinutes': 30,
                  }))['typeId']!
                  as String;
          await sched.availability.createSchedule(owner, doc, {
            'branchId': br,
            'weeklyHours': weekly(days: [1, 2, 3, 4, 5, 6, 7]),
            'effectiveFrom': '2026-01-01',
          });
          await store.commit([
            CreateOp('tenants/$tidA/members/doc$suffix', {
              'uid': 'doc$suffix',
              'role': 'doctor',
              'status': 'active',
              'doctorId': doc,
              'allBranches': true,
              'branchIds': <String>[],
            }),
          ]);
          final patient =
              (await patients.patients.create(
                    owner,
                    patientBody(br),
                  ))['patientId']!
                  as String;

          // book a visit two days ahead, then act on the day
          final day = start.add(const Duration(days: 2));
          final date =
              '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
          final appt = await sched.appointments.book(owner, {
            'patientId': patient,
            'doctorId': doc,
            'branchId': br,
            'typeId': type,
            'date': date,
            'startTime': '09:00',
          }, idempotencyKey: 'emu-clin-$suffix');
          final dayClock = DateTime.parse(
            '${date}T03:30:00Z',
          ).add(const Duration(hours: 1)); // 10:00 IST
          final later = depsAt(() => dayClock);
          final laterClin = clinicalAt(later);
          final recep = await ctx(
            tidA,
            ClinicRole.receptionist,
            uid: 'recep',
            d: later,
          );
          final docCtx = await ctx(
            tidA,
            ClinicRole.doctor,
            uid: 'doc',
            d: later,
          );
          await laterClin.scheduling.appointments.checkIn(
            recep,
            appt['appointmentId']! as String,
          );

          // the doctor's workspace sees the waiting patient
          final dash = await laterClin.workspace.dashboard(docCtx);
          expect((dash['counts']! as Map)['checkedIn'], 1);
          expect((dash['counts']! as Map)['waiting'], 1);

          // consultation from the appointment
          final con = await laterClin.consultations.create(docCtx, {
            'patientId': patient,
            'appointmentId': appt['appointmentId'],
            'chiefComplaint': {'reason': 'Fever for three days'},
          });
          final cid = con['consultationId']! as String;
          await expectLater(
            laterClin.consultations.create(docCtx, {
              'patientId': patient,
              'appointmentId': appt['appointmentId'],
            }),
            throwsA(isA<Object>()),
            reason: 'one consultation per appointment (uniqueness key)',
          );
          await laterClin.consultations.start(docCtx, cid);
          expect(
            (await store.get(
              'tenants/$tidA/appointments/${appt['appointmentId']}',
            ))!['status'],
            'in_progress',
          );
          await laterClin.vitals.record(docCtx, patient, {
            'consultationId': cid,
            'height': {'value': 175, 'unit': 'cm'},
            'weight': {'value': 70, 'unit': 'kg'},
          });
          await laterClin.consultations.addDiagnosis(docCtx, cid, {
            'kind': 'primary',
            'certainty': 'provisional',
            'label': 'Viral fever',
          });
          final rx = await laterClin.prescriptions.create(docCtx, cid, {
            'medicines': [
              {
                'name': 'Paracetamol',
                'dosage': '1 tablet',
                'frequency': 'three times a day',
                'durationValue': 5,
                'durationUnit': 'days',
              },
            ],
          });
          final rxId = rx['prescriptionId']! as String;
          final fin = await laterClin.prescriptions.finalize(docCtx, rxId);
          expect(fin['number'], 'RX-000001');
          expect(
            (await laterClin.prescriptions.finalize(
              docCtx,
              rxId,
            ))['idempotentReplay'],
            true,
          );
          final rep = await laterClin.prescriptions.amend(docCtx, rxId, {
            'reason': 'Dose corrected',
          });
          await laterClin.prescriptions.finalize(
            docCtx,
            rep['prescriptionId']! as String,
          );
          expect(
            (await store.get('tenants/$tidA/prescriptions/$rxId'))!['status'],
            'amended',
          );

          // finalize completes the visit; the record is locked; an amendment keeps version 0
          final done = await laterClin.consultations.finalize(docCtx, cid);
          expect(done['status'], 'finalized');
          expect(
            (await store.get(
              'tenants/$tidA/appointments/${appt['appointmentId']}',
            ))!['status'],
            'completed',
          );
          await expectLater(
            laterClin.consultations.update(docCtx, cid, {
              'assessment': {'notes': 'silent'},
            }),
            throwsA(isA<Object>()),
          );
          await laterClin.consultations.amend(docCtx, cid, {
            'reason': 'Add the assessment',
            'assessment': {'notes': 'Viral'},
          });
          final am = await laterClin.consultations.amendments(
            docCtx,
            cid,
            Request('GET', Uri.parse('http://x/a')),
          );
          expect((am['versions']! as List), hasLength(2));
          expect(((am['versions']! as List).first as Map)['revision'], 0);

          // follow-up queries: equality + range + order on the real store
          final fu = await laterClin.followups.create(docCtx, cid, {
            'recommendedDate': date,
            'reason': 'Review',
          });
          final page = await laterClin.followups.list(
            docCtx,
            Request('GET', Uri.parse('http://x/f')),
            upcoming: true,
          );
          expect(page.docs.map((d) => d.id), contains(fu['followupId']));
          final history = await laterClin.workspace.history(
            docCtx,
            patient,
            Request('GET', Uri.parse('http://x/h')),
          );
          expect((history.$1['consultations']! as List), hasLength(1));
          final vitals = await laterClin.vitals.list(
            docCtx,
            patient,
            Request('GET', Uri.parse('http://x/v')),
          );
          expect(vitals.docs, hasLength(1));

          // another clinic reaches nothing
          await expectLater(
            clin.consultations.detail(ownerB, cid),
            throwsA(isA<Object>()),
          );
          await expectLater(
            clin.prescriptions.detail(ownerB, rxId),
            throwsA(isA<Object>()),
          );
          await expectLater(
            clin.workspace.overview(ownerB, patient),
            throwsA(isA<Object>()),
          );
          final audit = await store.query(
            DocQuery(
              'tenants/$tidA/clinical_audit_logs',
              filters: [QueryFilter('consultationId', FilterOp.eq, cid)],
            ),
          );
          expect(
            audit.map((a) => a.data['action']),
            containsAll([
              'consultation.created',
              'consultation.started',
              'consultation.finalized',
              'consultation.amended',
              'prescription.finalized',
              'prescription.amended',
            ]),
          );
        },
      );
    },
    skip: host == null ? 'FIRESTORE_EMULATOR_HOST not set' : null,
  );
}
