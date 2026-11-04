@Tags(['emulator'])
library;

import 'dart:io';

import 'package:backend/core/data/document_store.dart';
import 'package:backend/core/data/firestore_document_store.dart';
import 'package:backend/features/clinic/branches/branch_service.dart';
import 'package:backend/features/clinic/common/clinic_deps.dart';
import 'package:backend/features/clinic/common/seat_service.dart';
import 'package:backend/features/clinic/common/tenant_context.dart';
import 'package:backend/features/notifications/notification_core.dart';
import 'package:backend/features/notifications/notification_hub.dart';
import 'package:backend/features/patients/patient_module.dart';
import 'package:backend/features/platform/audit/audit_service.dart';
import 'package:backend/features/platform/entitlements/entitlement_service.dart';
import 'package:backend/features/reports/report_service.dart';
import 'package:backend/features/scheduling/scheduling_module.dart';
import 'package:common_models/common_models.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import '../support/notification_fixtures.dart';
import '../support/patient_fixtures.dart' show patientBody;
import '../support/platform_http_fixtures.dart'
    show MemoryObjectStorage, branchBody;

class _Client extends http.BaseClient {
  _Client(this._inner);
  final http.Client _inner;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers['authorization'] = 'Bearer owner';
    return _inner.send(request);
  }
}

/// The notification pipeline and the reports on the real Firestore REST store:
/// outbox, deterministic ids, queries with ranges and `in` filters, retries
/// and concurrent workers.
void main() {
  final host = Platform.environment['FIRESTORE_EMULATOR_HOST'];

  test(
    'events, deliveries, retries, reminders and reports on the Firestore emulator',
    () async {
      final store = FirestoreDocumentStore(
        projectId: 'demo-eazyclinic',
        host: 'http://$host',
        client: _Client(http.Client()),
      );
      final suffix = DateTime.now().microsecondsSinceEpoch.toString();
      var now = DateTime.now().toUtc();
      DateTime clock() => now;
      final tid = 'ten_not$suffix';
      await store.commit([
        CreateOp('tenants/$tid', {
          'tenantId': tid,
          'clinicName': 'Emu Notify',
          'status': 'active',
          'subscriptionId': 'sub_not$suffix',
          'createdAt': now,
        }),
        CreateOp('platform_subscriptions/sub_not$suffix', {
          'subscriptionId': 'sub_not$suffix',
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
            'reports': true,
          },
          'startDate': now,
          'endDate': now.add(const Duration(days: 60)),
          'overrides': <String, Object?>{},
        }),
      ]);
      final deps = ClinicDeps(
        store: store,
        audit: AuditService(store, clock: clock),
        seats: SeatService(store, clock: clock),
        entitlements: EntitlementService(store, clock: clock),
        clock: clock,
      );
      final fcm = MockFcm();
      final hub = NotificationHub(deps, fcm: fcm);
      final patients = PatientModule(deps, MemoryObjectStorage());
      final sched = SchedulingModule(deps, patients.support);
      final ent = await deps.entitlements.forTenant(tid);
      final owner = TenantContext(
        tenantId: tid,
        uid: 'owner$suffix',
        role: ClinicRole.clinicOwner,
        scope: const BranchScope(allBranches: true, branchIds: {}),
        entitlements: ent,
      );
      final br =
          (await BranchService(
                deps,
              ).create(owner, branchBody(code: 'NOT')))['branchId']!
              as String;
      final patient = await patients.patients.create(owner, patientBody(br));
      final pid = patient['patientId']! as String;
      final account = 'pa_$suffix';
      await store.commit([
        UpdateOp('tenants/$tid/patients/$pid', {'patientAccountId': account}),
        CreateOp('patient_devices/dev_$suffix', {
          'accountId': account,
          'uid': 'u$suffix',
          'token': 'tok-emulator-aaaaaaaaaaaaaaaa',
          'active': true,
        }),
      ]);

      // outbox: same key twice is one event; concurrent workers make one inbox entry
      final id = await hub.emit(
        tenantId: tid,
        type: 'payment_received',
        dedupeKey: 'emu-1',
        accountId: account,
        fallbackTitle: 'Payment received',
        fallbackBody: 'Open the app.',
      );
      expect(
        await hub.emit(
          tenantId: tid,
          type: 'payment_received',
          dedupeKey: 'emu-1',
          accountId: account,
        ),
        id,
      );
      await Future.wait([
        for (var i = 0; i < 3; i++)
          hub.processEvent(tid, id).then<void>((_) {}, onError: (Object _) {}),
      ]);
      final inbox = await store.query(
        DocQuery(
          'patient_notifications',
          filters: [QueryFilter('accountId', FilterOp.eq, account)],
          limit: 10,
        ),
      );
      expect(inbox, hasLength(1));

      // dispatch with a transient failure, then success after the backoff
      fcm.script = [
        const ProviderResult('transient', error: 'http_503'),
        const ProviderResult('accepted', messageId: 'ok'),
      ];
      await hub.dispatchDue(tid);
      var pushes = await store.query(
        DocQuery(
          'tenants/$tid/notification_deliveries',
          filters: [const QueryFilter('channel', FilterOp.eq, 'push')],
          limit: 10,
        ),
      );
      expect(pushes.single.data['status'], 'retry_scheduled');
      await hub.dispatchDue(tid);
      expect(fcm.sent, hasLength(1), reason: 'not due yet');
      now = now.add(const Duration(minutes: 5));
      await hub.dispatchDue(tid);
      pushes = await store.query(
        DocQuery(
          'tenants/$tid/notification_deliveries',
          filters: [const QueryFilter('channel', FilterOp.eq, 'push')],
          limit: 10,
        ),
      );
      expect(pushes.single.data['status'], 'sent');
      expect(pushes.single.data['providerMessageId'], 'ok');

      // report queries run against the real store (ranges, branch filters)
      final reports = ReportService(deps, sched.support);
      final r = await reports.run(owner, 'patients', {});
      expect(r.kind, 'patients');
      expect(r.summary['registrations'], 1);
      expect(r.summary['activePatients'], 1);
      // range and in-list queries over appointments, queues and consultations
      for (final k in ['appointments', 'queues', 'consultations']) {
        expect((await reports.run(owner, k, {})).truncated, isFalse, reason: k);
      }
      // reminders: nothing is due, and scanning twice creates nothing
      expect(await hub.scanReminders(tid), 0);
    },
    skip: host == null ? 'FIRESTORE_EMULATOR_HOST not set' : false,
  );
}
