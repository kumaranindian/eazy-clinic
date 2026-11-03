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

/// Scheduling on the real Firestore REST store: reservation documents as the
/// double-booking guard, idempotency keys, range + equality + `in` queries,
/// leave flagging, check-in, token counter and queue transitions, tenant
/// isolation. Sequential (the emulator serializes transactions).
void main() {
  final host = Platform.environment['FIRESTORE_EMULATOR_HOST'];

  group(
    'scheduling on the Firestore emulator',
    () {
      test(
        'availability, booking, double booking, leave, check-in and queue',
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
                'features': {'multiple_branches': true, 'appointments': true},
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
          final deps = depsAt(() => start);
          final patients = PatientModule(deps, MemoryObjectStorage());
          final sched = SchedulingModule(deps, patients.support);
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
          // overlapping schedules are refused by the real store too
          await expectLater(
            sched.availability.createSchedule(owner, doc, {
              'branchId': br,
              'weeklyHours': weekly(),
              'effectiveFrom': '2026-02-01',
            }),
            throwsA(isA<Object>()),
          );

          // a date two days ahead, whatever the weekday
          final day = start.add(const Duration(days: 2));
          final date =
              '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
          Future<String> patient(int i) async =>
              (await patients.patients.create(
                    owner,
                    patientBody(
                      br,
                      name: 'Emu Patient$i',
                      dob: '19${50 + i}-01-01',
                      phone: '98765002${i.toString().padLeft(2, '0')}',
                    ),
                  ))['patientId']!
                  as String;
          final p1 = await patient(1);
          final p2 = await patient(2);
          final p3 = await patient(3);
          Map<String, Object?> body(String p, String time) => {
            'patientId': p,
            'doctorId': doc,
            'branchId': br,
            'typeId': type,
            'date': date,
            'startTime': time,
          };

          final slots = await sched.slots.availableSlots(
            owner,
            branchId: br,
            doctorId: doc,
            date: date,
            typeId: type,
          );
          expect((slots['slots']! as List).first['startTime'], '09:00');

          final a1 = await sched.appointments.book(
            owner,
            body(p1, '09:00'),
            idempotencyKey: 'emu-key-$suffix-1',
          );
          expect(a1['status'], 'confirmed');
          // the same slot is refused (reservation documents already exist)
          await expectLater(
            sched.appointments.book(
              owner,
              body(p2, '09:00'),
              idempotencyKey: 'emu-key-$suffix-2',
            ),
            throwsA(isA<Object>()),
          );
          // idempotent replay
          final replay = await sched.appointments.book(
            owner,
            body(p1, '09:00'),
            idempotencyKey: 'emu-key-$suffix-1',
          );
          expect(replay['appointmentId'], a1['appointmentId']);
          final a2 = await sched.appointments.book(
            owner,
            body(p2, '09:30'),
            idempotencyKey: 'emu-key-$suffix-3',
          );
          final a3 = await sched.appointments.book(
            owner,
            body(p3, '10:00'),
            idempotencyKey: 'emu-key-$suffix-4',
          );
          final reservations = await store.query(
            DocQuery(
              'tenants/$tidA/appointment_slot_reservations',
              filters: [
                QueryFilter('doctorId', FilterOp.eq, doc),
                QueryFilter('localDate', FilterOp.eq, date),
              ],
            ),
          );
          expect(reservations, hasLength(18));

          // list queries: range + equality, and scoped `in`
          Request req(String q) =>
              Request('GET', Uri.parse('http://x/api/v1/appointments?$q'));
          final listed = await sched.appointments.list(
            owner,
            req(''),
            from: date,
            to: date,
            doctorId: doc,
            branchId: br,
            status: 'confirmed',
          );
          expect(listed.docs, hasLength(3));
          final scoped = TenantContext(
            tenantId: tidA,
            uid: 'east$suffix',
            role: ClinicRole.receptionist,
            scope: BranchScope(allBranches: false, branchIds: {br}),
            entitlements: owner.entitlements,
          );
          expect(
            (await sched.appointments.list(scoped, req(''), date: date)).docs,
            hasLength(3),
          );
          final otherScope = TenantContext(
            tenantId: tidA,
            uid: 'x$suffix',
            role: ClinicRole.receptionist,
            scope: const BranchScope(
              allBranches: false,
              branchIds: {'br_elsewhere'},
            ),
            entitlements: owner.entitlements,
          );
          expect(
            (await sched.appointments.list(
              otherScope,
              req(''),
              date: date,
            )).docs,
            isEmpty,
          );

          // leave over booked appointments: flagged, not cancelled
          final leave = await sched.availability.createException(owner, {
            'branchId': br,
            'type': 'doctor_leave',
            'startDate': date,
            'reason': 'Conference',
          }, doctorId: doc);
          expect(leave['affectedAppointments'], hasLength(3));
          final flagged = await sched.appointments.detail(
            owner,
            a1['appointmentId']! as String,
          );
          expect(flagged['status'], 'confirmed');
          expect(flagged['needsAttention'], true);
          await expectLater(
            sched.appointments.book(
              owner,
              body(p1, '11:00'),
              idempotencyKey: 'emu-key-$suffix-5',
            ),
            throwsA(isA<Object>()),
          );
          await sched.availability.cancelException(
            owner,
            doc,
            leave['exceptionId']! as String,
          );
          expect(
            (await sched.appointments.detail(
              owner,
              a1['appointmentId']! as String,
            ))['needsAttention'],
            false,
          );

          // cancel frees the slot for someone else
          await sched.appointments.cancel(
            owner,
            a3['appointmentId']! as String,
            {'reason': 'Patient called'},
          );
          final p4 = await patient(4);
          await sched.appointments.book(
            owner,
            body(p4, '10:00'),
            idempotencyKey: 'emu-key-$suffix-6',
          );

          // another clinic sees none of it
          await expectLater(
            sched.appointments.detail(ownerB, a1['appointmentId']! as String),
            throwsA(isA<Object>()),
          );
          expect(
            (await sched.appointments.list(ownerB, req(''), date: date)).docs,
            isEmpty,
          );

          // check-in on the day: two tokens, then the queue flow
          final dayStart = DateTime.parse(
            '${date}T03:30:00Z',
          ).add(const Duration(hours: 1)); // 10:00 IST
          final later = depsAt(() => dayStart);
          final laterPatients = PatientModule(later, MemoryObjectStorage());
          final laterSched = SchedulingModule(later, laterPatients.support);
          final recep = await ctx(
            tidA,
            ClinicRole.receptionist,
            uid: 'recep',
            d: later,
          );
          final t1 = await laterSched.appointments.checkIn(
            recep,
            a1['appointmentId']! as String,
          );
          final t2 = await laterSched.appointments.checkIn(
            recep,
            a2['appointmentId']! as String,
          );
          expect(t1['tokenDisplay'], 'A001');
          expect(t2['tokenDisplay'], 'A002');
          await expectLater(
            laterSched.appointments.checkIn(
              recep,
              a1['appointmentId']! as String,
            ),
            throwsA(isA<Object>()),
          );
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
          final docCtx = await ctx(
            tidA,
            ClinicRole.doctor,
            uid: 'doc',
            d: later,
          );
          final cur = await laterSched.queue.current(
            recep,
            branchId: br,
            doctorId: doc,
            date: date,
          );
          expect(cur['waiting'], 2);
          final called = await laterSched.queue.callNext(
            recep,
            '${cur['queueId']}',
          );
          expect(called['displayToken'], 'A001');
          await laterSched.appointments.consult(
            docCtx,
            a1['appointmentId']! as String,
            'start',
          );
          await laterSched.appointments.consult(
            docCtx,
            a1['appointmentId']! as String,
            'complete',
          );
          final done = await laterSched.queue.current(
            recep,
            branchId: br,
            doctorId: doc,
            date: date,
          );
          expect(done['completed'], 1);
          expect(done['waiting'], 1);
          final tokens = await store.query(
            DocQuery('tenants/$tidA/queue_tokens'),
          );
          expect(tokens, hasLength(2));
        },
      );
    },
    skip: host == null ? 'FIRESTORE_EMULATOR_HOST not set' : null,
  );
}
