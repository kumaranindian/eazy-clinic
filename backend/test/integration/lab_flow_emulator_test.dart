@Tags(['emulator'])
library;

import 'dart:io';

import 'package:backend/core/data/document_store.dart';
import 'package:backend/core/data/firestore_document_store.dart';
import 'package:backend/features/clinic/branches/branch_service.dart';
import 'package:backend/features/clinic/common/clinic_deps.dart';
import 'package:backend/features/clinic/common/seat_service.dart';
import 'package:backend/features/clinic/common/tenant_context.dart';
import 'package:backend/features/clinical/clinical_module.dart';
import 'package:backend/features/laboratory/lab_module.dart';
import 'package:backend/features/patients/patient_module.dart';
import 'package:backend/features/platform/audit/audit_service.dart';
import 'package:backend/features/platform/entitlements/entitlement_service.dart';
import 'package:backend/features/scheduling/scheduling_module.dart';
import 'package:common_models/common_models.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

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

/// Laboratory workflow on the real Firestore REST store: catalogue, order,
/// sample identity, result entry, separation of duty, publication into private
/// storage, and a real transactional race on a sample identifier.
void main() {
  final host = Platform.environment['FIRESTORE_EMULATOR_HOST'];

  test(
    'laboratory order to published report on the Firestore emulator',
    () async {
      final store = FirestoreDocumentStore(
        projectId: 'demo-eazyclinic',
        host: 'http://$host',
        client: _Client(http.Client()),
      );
      final suffix = DateTime.now().microsecondsSinceEpoch.toString();
      final start = DateTime.now().toUtc();
      final tid = 'ten_lab$suffix';
      await store.commit([
        CreateOp('tenants/$tid', {
          'tenantId': tid,
          'clinicName': 'Emu Lab',
          'status': 'active',
          'subscriptionId': 'sub_lab$suffix',
          'createdAt': start,
        }),
        CreateOp('platform_subscriptions/sub_lab$suffix', {
          'subscriptionId': 'sub_lab$suffix',
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
            'laboratory': true,
          },
          'startDate': start,
          'endDate': start.add(const Duration(days: 60)),
          'overrides': <String, Object?>{},
        }),
      ]);
      DateTime clock() => start;
      final deps = ClinicDeps(
        store: store,
        audit: AuditService(store, clock: clock),
        seats: SeatService(store, clock: clock),
        entitlements: EntitlementService(store, clock: clock),
        clock: clock,
      );
      final storage = MemoryObjectStorage();
      final patients = PatientModule(deps, storage);
      final sched = SchedulingModule(deps, patients.support);
      final clin = ClinicalModule(deps, patients.support, sched);
      final lab = LabModule(
        deps,
        patients.support,
        sched.support,
        clin.support,
        storage,
      );
      final ent = await deps.entitlements.forTenant(tid);
      TenantContext ctx(ClinicRole role, String uid) => TenantContext(
        tenantId: tid,
        uid: '$uid$suffix',
        role: role,
        scope: const BranchScope(allBranches: true, branchIds: {}),
        entitlements: ent,
      );
      final owner = ctx(ClinicRole.clinicOwner, 'owner');
      final tech1 = ctx(ClinicRole.labTechnician, 'lt1');
      final tech2 = ctx(ClinicRole.labTechnician, 'lt2');
      final nurse = ctx(ClinicRole.nurse, 'nurse');
      final br =
          (await BranchService(
                deps,
              ).create(owner, branchBody(code: 'LAB')))['branchId']!
              as String;
      final patient = await patients.patients.create(owner, patientBody(br));
      final test = await lab.catalogue.create(owner, {
        'code': 'HB',
        'name': 'Haemoglobin',
        'category': 'hematology',
        'sampleType': 'blood',
        'turnaroundHours': 6,
        'parameters': [
          {
            'code': 'HGB',
            'name': 'Haemoglobin',
            'valueType': 'numeric',
            'unit': 'g/dL',
            'referenceRanges': [
              {'low': 12, 'high': 15, 'unit': 'g/dL', 'source': 'Clinic SOP'},
            ],
          },
        ],
      });

      Future<Map<String, Object?>> newOrder(String key) =>
          lab.orders.createManual(tech1, {
            'patientId': patient['patientId'],
            'branchId': br,
            'tests': [
              {'testId': test['testId']},
            ],
          }, idempotencyKey: key);

      final o = await newOrder('emu-lab-key-$suffix');
      final id = o['orderId']! as String;
      expect(o['orderNumber'], 'LAB-000001');
      final again = await newOrder('emu-lab-key-$suffix');
      expect(again['orderId'], id, reason: 'idempotent create');

      await lab.orders.accept(tech1, id, {});
      final s = await lab.orders.createSample(nurse, id, {});
      await lab.orders.collect(nurse, s['sampleId']! as String, {
        'identifier': 'EMU-$suffix',
        'confirmedMrn': patient['mrn'],
      });
      final item = ((o['items']! as List).first as Map)['itemId']! as String;
      final saved = await lab.results.save(tech1, id, item, {
        'observations': [
          {'code': 'HGB', 'value': 10.5},
        ],
      });
      expect(((saved['observations']! as List).first as Map)['flag'], 'low');
      await lab.results.submit(tech1, id);
      await expectLater(
        lab.results.verify(tech1, id),
        throwsA(isA<Object>()),
        reason: 'the person who entered cannot verify',
      );
      await lab.results.verify(tech2, id);
      final rep = await lab.results.publish(tech2, id);
      expect(rep['version'], 1);
      final stored = await storage.get('${rep['storagePath']}');
      expect(stored, isNotNull);
      expect(String.fromCharCodes(stored!.$1.sublist(0, 5)), '%PDF-');
      final replay = await lab.results.publish(tech2, id);
      expect(replay['reportId'], rep['reportId']);

      // a real transactional race on one identifier
      final ids = <String>[];
      for (var i = 0; i < 2; i++) {
        final x = await newOrder('emu-lab-race-$i-$suffix');
        await lab.orders.accept(tech1, x['orderId']! as String, {});
        ids.add(
          (await lab.orders.createSample(
                nurse,
                x['orderId']! as String,
                {},
              ))['sampleId']!
              as String,
        );
      }
      final outcomes = await Future.wait([
        for (final sid in ids)
          lab.orders
              .collect(nurse, sid, {
                'identifier': 'RACE-$suffix',
                'confirmedMrn': patient['mrn'],
              })
              .then<bool>((_) => true, onError: (Object _) => false),
      ]);
      expect(outcomes.where((b) => b).length, 1);

      // another clinic's staff never reach this data
      final tidB = 'ten_labb$suffix';
      final foreign = TenantContext(
        tenantId: tidB,
        uid: 'x$suffix',
        role: ClinicRole.labTechnician,
        scope: const BranchScope(allBranches: true, branchIds: {}),
        entitlements: ent,
      );
      await expectLater(lab.orders.detail(foreign, id), throwsA(isA<Object>()));
    },
    skip: host == null ? 'FIRESTORE_EMULATOR_HOST not set' : false,
  );
}
