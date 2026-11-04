import 'package:api_contracts/api_contracts.dart';
import 'package:common_models/common_models.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../../core/data/document_store.dart';
import '../../core/errors/api_exception.dart';
import '../../core/responses/responses.dart';
import '../clinic/clinic_module.dart';
import '../clinic/common/clinic_deps.dart';
import '../clinic/common/tenant_context.dart';
import '../patients/patient_support.dart';
import '../platform/common/paging.dart';
import '../scheduling/scheduling_module.dart';
import 'clinical_support.dart';
import 'consultation_service.dart';
import 'prescription_service.dart';
import 'templates_and_followups.dart';
import 'vitals_and_catalogues.dart';
import 'workspace_service.dart';

/// Services of Phase 6: doctor workspace, consultations, diagnoses,
/// prescriptions, vitals, templates, follow-ups and investigation requests.
class ClinicalModule {
  ClinicalModule(ClinicDeps deps, PatientSupport patients, this.scheduling)
    : support = ClinicalSupport(deps, patients, scheduling.support) {
    consultations = ConsultationService(support, scheduling.queue);
    prescriptions = PrescriptionService(support);
    vitals = VitalsService(support);
    catalogues = CatalogueService(support);
    templates = TemplateService(support);
    followups = FollowupService(support, scheduling.appointments);
    workspace = WorkspaceService(support, scheduling.queue);
  }

  final ClinicalSupport support;
  late final ConsultationService consultations;
  late final PrescriptionService prescriptions;
  late final VitalsService vitals;
  late final CatalogueService catalogues;
  late final TemplateService templates;
  late final FollowupService followups;
  late final WorkspaceService workspace;
  final SchedulingModule scheduling;

  /// The plan must include the doctor workspace.
  void requireFeature(TenantContext t) {
    if (t.entitlements.features[FeatureKey.doctorWorkspace] != true) {
      throw const ApiException.forbidden(
        'Your subscription does not include the doctor workspace.',
      );
    }
  }
}

const String _v1 = apiV1Prefix;

void registerClinicalRoutes(ClinicModule m, ClinicalModule c, Router r) {
  // Handlers that check the plan before anything else.
  Function g0(Future<Response> Function(Request, TenantContext) f) =>
      (Request req, TenantContext t) {
        c.requireFeature(t);
        return f(req, t);
      };
  Function g1(Future<Response> Function(Request, TenantContext, String) f) =>
      (Request req, TenantContext t, String a) {
        c.requireFeature(t);
        return f(req, t, a);
      };
  Function g2(
    Future<Response> Function(Request, TenantContext, String, String) f,
  ) => (Request req, TenantContext t, String a, String b) {
    c.requireFeature(t);
    return f(req, t, a, b);
  };

  // ----------------------------------------------------- doctor workspace
  r.get(
    '$_v1/doctor/dashboard',
    m.secured(
      g0(
        (req, t) async => ok(
          req,
          await c.workspace.dashboard(t, branchId: m.query(req, 'branchId')),
        ),
      ),
    ),
  );
  r.get(
    '$_v1/doctor/appointments/today',
    m.secured(
      g0(
        (req, t) async => ok(
          req,
          await c.workspace.todayAppointments(
            t,
            branchId: m.query(req, 'branchId'),
          ),
        ),
      ),
    ),
  );
  r.get(
    '$_v1/doctor/queue',
    m.secured(
      g0(
        (req, t) async => ok(
          req,
          await c.workspace.queue(t, branchId: m.query(req, 'branchId')),
        ),
      ),
    ),
  );
  r.post(
    '$_v1/doctor/queue/<eid>/call',
    m.secured(
      g1((req, t, eid) async {
        await c.support.requireDoctorSelf(t);
        return ok(
          req,
          await c.scheduling.queue.transition(
            t,
            m.id(eid),
            'called',
            action: 'call',
            permission: ClinicPermission.queueOperate,
            requestId: m.rid(req),
          ),
        );
      }),
      write: true,
    ),
  );
  r.get(
    '$_v1/doctor/followups',
    m.secured(
      g0((req, t) async {
        final today = await c.followups.today(t);
        final page = await c.followups.list(
          t,
          req,
          status: m.query(req, 'status'),
          branchId: m.query(req, 'branchId'),
          from: m.query(req, 'from'),
          to: m.query(req, 'to'),
          overdue: m.query(req, 'overdue') == 'true',
          upcoming: m.query(req, 'upcoming') == 'true',
        );
        return m.list(req, page, (d) => c.followups.present(t, d.data, today));
      }),
    ),
  );

  // ------------------------------------------------ clinical patient views
  r.get(
    '$_v1/clinical/patients/<pid>/overview',
    m.secured(
      g1(
        (req, t, pid) async => ok(
          req,
          await c.workspace.overview(t, m.id(pid), requestId: m.rid(req)),
        ),
      ),
    ),
  );
  r.get(
    '$_v1/clinical/patients/<pid>/history',
    m.secured(
      g1((req, t, pid) async {
        final (data, meta) = await c.workspace.history(t, m.id(pid), req);
        return ok(req, data, page: meta);
      }),
    ),
  );
  r.get(
    '$_v1/clinical/patients/<pid>/vitals',
    m.secured(
      g1((req, t, pid) async {
        final p = await c.vitals.list(t, m.id(pid), req);
        return m.list(req, p, (d) => ClinicalSupport.present(d.data));
      }),
    ),
  );
  r.post(
    '$_v1/clinical/patients/<pid>/vitals',
    m.secured(
      g1(
        (req, t, pid) async => ok(
          req,
          await c.vitals.record(
            t,
            m.id(pid),
            await m.body(req),
            requestId: m.rid(req),
          ),
          status: 201,
        ),
      ),
      write: true,
    ),
  );

  // -------------------------------------------------------- consultations
  r.post(
    '$_v1/consultations',
    m.secured(
      g0(
        (req, t) async => ok(
          req,
          await c.consultations.create(
            t,
            await m.body(req),
            requestId: m.rid(req),
          ),
          status: 201,
        ),
      ),
      write: true,
    ),
  );
  r.get(
    '$_v1/consultations/<cid>',
    m.secured(
      g1(
        (req, t, cid) async => ok(
          req,
          await c.consultations.detail(t, m.id(cid), requestId: m.rid(req)),
        ),
      ),
    ),
  );
  r.patch(
    '$_v1/consultations/<cid>',
    m.secured(
      g1(
        (req, t, cid) async => ok(
          req,
          await c.consultations.update(
            t,
            m.id(cid),
            await m.body(req),
            requestId: m.rid(req),
          ),
        ),
      ),
      write: true,
    ),
  );
  r.post(
    '$_v1/consultations/<cid>/start',
    m.secured(
      g1(
        (req, t, cid) async => ok(
          req,
          await c.consultations.start(t, m.id(cid), requestId: m.rid(req)),
        ),
      ),
      write: true,
    ),
  );
  r.post(
    '$_v1/consultations/<cid>/finalize',
    m.secured(
      g1(
        (req, t, cid) async => ok(
          req,
          await c.consultations.finalize(t, m.id(cid), requestId: m.rid(req)),
        ),
      ),
      write: true,
    ),
  );
  r.post(
    '$_v1/consultations/<cid>/amend',
    m.secured(
      g1(
        (req, t, cid) async => ok(
          req,
          await c.consultations.amend(
            t,
            m.id(cid),
            await m.body(req),
            requestId: m.rid(req),
          ),
        ),
      ),
      write: true,
    ),
  );
  for (final release in [true, false]) {
    r.post(
      '$_v1/consultations/<cid>/${release ? 'release' : 'unrelease'}',
      m.secured(
        g1((req, t, cid) async {
          final res = await c.consultations.release(
            t,
            m.id(cid),
            release: release,
            requestId: m.rid(req),
          );
          if (release && res['idempotentReplay'] != true) {
            await c.support.notifier?.publishForPatient(
              t.tenantId,
              '${res['patientId']}',
              category: 'summary_available',
              title: 'Visit summary available',
              body:
                  'Your doctor shared a summary of your visit. Open the app to read it.',
              dedupeKey: 'summary:${res['consultationId']}',
              resourceType: 'consultation',
              resourceId: '${res['consultationId']}',
            );
          }
          return ok(req, res);
        }),
        write: true,
      ),
    );
  }
  r.get(
    '$_v1/consultations/<cid>/amendments',
    m.secured(
      g1(
        (req, t, cid) async =>
            ok(req, await c.consultations.amendments(t, m.id(cid), req)),
      ),
    ),
  );
  r.get(
    '$_v1/consultations/<cid>/audit-logs',
    m.secured(
      g1((req, t, cid) async {
        t.require(ClinicPermission.clinicalAuditView);
        await c.support.consultation(t, m.id(cid));
        final p = await runPaged(
          c.support.d.store,
          DocQuery(
            c.support.path(t, 'clinical_audit_logs'),
            filters: [QueryFilter('consultationId', FilterOp.eq, m.id(cid))],
            orderBy: const OrderBy('timestamp', descending: true),
          ),
          req,
        );
        return m.list(req, p, (d) => ClinicalSupport.present(d.data));
      }),
    ),
  );

  // ------------------------------------------------------------ diagnoses
  r.get(
    '$_v1/diagnoses/catalogue',
    m.secured(
      g0((req, t) async {
        final p = await c.catalogues.search(
          t,
          req,
          'diagnosis_catalogue',
          permission: ClinicPermission.consultationsManage,
          q: m.query(req, 'q'),
          status: m.query(req, 'status'),
        );
        return m.list(req, p, (d) => CatalogueService.present(d.data));
      }),
    ),
  );
  r.post(
    '$_v1/diagnoses/catalogue',
    m.secured(
      g0(
        (req, t) async => ok(
          req,
          CatalogueService.present(
            await c.catalogues.createDiagnosis(
              t,
              await m.body(req),
              requestId: m.rid(req),
            ),
          ),
          status: 201,
        ),
      ),
      write: true,
    ),
  );
  r.patch(
    '$_v1/diagnoses/catalogue/<id>',
    m.secured(
      g1(
        (req, t, id) async => ok(
          req,
          await c.catalogues.update(
            t,
            'diagnosis_catalogue',
            m.id(id),
            await m.body(req),
            {'name', 'code', 'codeSystem', 'description'},
            requestId: m.rid(req),
          ),
        ),
      ),
      write: true,
    ),
  );
  r.post(
    '$_v1/consultations/<cid>/diagnoses',
    m.secured(
      g1(
        (req, t, cid) async => ok(
          req,
          await c.consultations.addDiagnosis(
            t,
            m.id(cid),
            await m.body(req),
            requestId: m.rid(req),
          ),
          status: 201,
        ),
      ),
      write: true,
    ),
  );
  r.patch(
    '$_v1/consultations/<cid>/diagnoses/<did>',
    m.secured(
      g2(
        (req, t, cid, did) async => ok(
          req,
          await c.consultations.updateDiagnosis(
            t,
            m.id(cid),
            m.id(did),
            await m.body(req),
            requestId: m.rid(req),
          ),
        ),
      ),
      write: true,
    ),
  );

  // -------------------------------------------------------- prescriptions
  r.get(
    '$_v1/medicines/catalogue',
    m.secured(
      g0((req, t) async {
        final p = await c.catalogues.search(
          t,
          req,
          'medicine_catalogue',
          permission: ClinicPermission.prescriptionsManage,
          q: m.query(req, 'q'),
          status: m.query(req, 'status'),
        );
        return m.list(req, p, (d) => CatalogueService.present(d.data));
      }),
    ),
  );
  r.post(
    '$_v1/medicines/catalogue',
    m.secured(
      g0(
        (req, t) async => ok(
          req,
          await c.catalogues.createMedicine(
            t,
            await m.body(req),
            requestId: m.rid(req),
          ),
          status: 201,
        ),
      ),
      write: true,
    ),
  );
  r.patch(
    '$_v1/medicines/catalogue/<id>',
    m.secured(
      g1(
        (req, t, id) async => ok(
          req,
          await c.catalogues.update(
            t,
            'medicine_catalogue',
            m.id(id),
            await m.body(req),
            {
              'name',
              'genericName',
              'brandName',
              'strength',
              'form',
              'description',
            },
            requestId: m.rid(req),
          ),
        ),
      ),
      write: true,
    ),
  );
  r.post(
    '$_v1/consultations/<cid>/prescriptions',
    m.secured(
      g1(
        (req, t, cid) async => ok(
          req,
          await c.prescriptions.create(
            t,
            m.id(cid),
            await m.body(req),
            requestId: m.rid(req),
          ),
          status: 201,
        ),
      ),
      write: true,
    ),
  );
  r.get(
    '$_v1/prescriptions/<rid>',
    m.secured(
      g1(
        (req, t, rid) async => ok(
          req,
          await c.prescriptions.detail(t, m.id(rid), requestId: m.rid(req)),
        ),
      ),
    ),
  );
  r.patch(
    '$_v1/prescriptions/<rid>',
    m.secured(
      g1(
        (req, t, rid) async => ok(
          req,
          await c.prescriptions.update(
            t,
            m.id(rid),
            await m.body(req),
            requestId: m.rid(req),
          ),
        ),
      ),
      write: true,
    ),
  );
  r.post(
    '$_v1/prescriptions/<rid>/finalize',
    m.secured(
      g1((req, t, rid) async {
        final res = await c.prescriptions.finalize(
          t,
          m.id(rid),
          requestId: m.rid(req),
        );
        if (res['idempotentReplay'] != true) {
          await c.support.notifier?.publishForPatient(
            t.tenantId,
            '${res['patientId']}',
            category: 'prescription_available',
            title: 'Prescription available',
            body: 'Your doctor issued a prescription. Open the app to view it.',
            dedupeKey: 'rx:${res['prescriptionId']}',
            resourceType: 'prescription',
            resourceId: '${res['prescriptionId']}',
          );
        }
        return ok(req, res);
      }),
      write: true,
    ),
  );
  r.post(
    '$_v1/prescriptions/<rid>/amend',
    m.secured(
      g1(
        (req, t, rid) async => ok(
          req,
          await c.prescriptions.amend(
            t,
            m.id(rid),
            await m.body(req),
            requestId: m.rid(req),
          ),
          status: 201,
        ),
      ),
      write: true,
    ),
  );

  // ------------------------------------------------------------ templates
  r.get(
    '$_v1/clinical/templates',
    m.secured(
      g0(
        (req, t) async =>
            ok(req, await c.templates.list(t, status: m.query(req, 'status'))),
      ),
    ),
  );
  r.post(
    '$_v1/clinical/templates',
    m.secured(
      g0(
        (req, t) async => ok(
          req,
          await c.templates.create(t, await m.body(req), requestId: m.rid(req)),
          status: 201,
        ),
      ),
      write: true,
    ),
  );
  r.patch(
    '$_v1/clinical/templates/<tid>',
    m.secured(
      g1(
        (req, t, tid) async => ok(
          req,
          await c.templates.update(
            t,
            m.id(tid),
            await m.body(req),
            requestId: m.rid(req),
          ),
        ),
      ),
      write: true,
    ),
  );

  // ------------------------------------------------- follow-ups, requests
  r.post(
    '$_v1/consultations/<cid>/followups',
    m.secured(
      g1(
        (req, t, cid) async => ok(
          req,
          await _followupCreated(
            c,
            t,
            await c.followups.create(
              t,
              m.id(cid),
              await m.body(req),
              requestId: m.rid(req),
            ),
          ),
          status: 201,
        ),
      ),
      write: true,
    ),
  );
  r.patch(
    '$_v1/followups/<fid>',
    m.secured(
      g1(
        (req, t, fid) async => ok(
          req,
          await c.followups.update(
            t,
            m.id(fid),
            await m.body(req),
            requestId: m.rid(req),
          ),
        ),
      ),
      write: true,
    ),
  );
  r.post(
    '$_v1/followups/<fid>/appointment',
    m.secured(
      g1((req, t, fid) async {
        final out = await c.followups.bookAppointment(
          t,
          m.id(fid),
          await m.body(req),
          idempotencyKey: req.headers['idempotency-key'],
          requestId: m.rid(req),
        );
        return ok(req, out, status: 201);
      }),
      write: true,
    ),
  );
  r.post(
    '$_v1/consultations/<cid>/investigations',
    m.secured(
      g1(
        (req, t, cid) async => ok(
          req,
          await c.consultations.requestInvestigation(
            t,
            m.id(cid),
            await m.body(req),
            requestId: m.rid(req),
          ),
          status: 201,
        ),
      ),
      write: true,
    ),
  );
  r.get(
    '$_v1/consultations/<cid>/investigations',
    m.secured(
      g1(
        (req, t, cid) async =>
            ok(req, await c.consultations.investigations(t, m.id(cid))),
      ),
    ),
  );
}

/// Tells the patient a follow-up was recommended (generic text; the reason and
/// instructions stay in the clinic record).
Future<Map<String, Object?>> _followupCreated(
  ClinicalModule c,
  TenantContext t,
  Map<String, Object?> f,
) async {
  try {
    final pid = f['patientId'];
    if (pid != null) {
      await c.support.notifier?.publishForPatient(
        t.tenantId,
        '$pid',
        category: 'followup_reminder',
        title: 'Follow-up recommended',
        body:
            'Your doctor recommended a follow-up visit. Open the app for details.',
        dedupeKey: 'followup_created:${f['followupId']}',
        resourceType: 'followup',
        resourceId: '${f['followupId']}',
      );
    }
  } on Object {
    // best effort
  }
  return f;
}
