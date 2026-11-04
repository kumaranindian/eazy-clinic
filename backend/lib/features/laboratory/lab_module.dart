import 'package:api_contracts/api_contracts.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../../core/responses/responses.dart';
import '../clinic/clinic_module.dart';
import '../clinic/common/clinic_deps.dart';
import '../clinic/common/object_storage.dart';
import '../clinic/common/tenant_context.dart';
import '../clinical/clinical_support.dart';
import '../patients/patient_support.dart';
import '../scheduling/scheduling_support.dart';
import 'lab_catalogue.dart';
import 'lab_orders.dart';
import 'lab_results.dart';
import 'lab_support.dart';

/// Phase 9: laboratory catalogue, orders, samples, results, verification,
/// publication, external reports and the laboratory dashboard.
class LabModule {
  LabModule(
    ClinicDeps deps,
    PatientSupport patients,
    SchedulingSupport scheduling,
    ClinicalSupport clinical,
    ObjectStorage storage,
  ) : support = LabSupport(deps, patients, scheduling, storage) {
    catalogue = LabCatalogueService(support);
    orders = LabOrderService(support, catalogue, clinical);
    results = LabResultService(support, orders);
  }

  final LabSupport support;
  late final LabCatalogueService catalogue;
  late final LabOrderService orders;
  late final LabResultService results;
}

const String _v1 = apiV1Prefix;

void registerLabRoutes(ClinicModule m, LabModule l, Router r) {
  // Every handler checks the plan first.
  Function g0(Future<Response> Function(Request, TenantContext) f) =>
      (Request req, TenantContext t) {
        l.support.requireFeature(t);
        return f(req, t);
      };
  Function g1(Future<Response> Function(Request, TenantContext, String) f) =>
      (Request req, TenantContext t, String a) {
        l.support.requireFeature(t);
        return f(req, t, m.id(a));
      };
  Function g2(
    Future<Response> Function(Request, TenantContext, String, String) f,
  ) => (Request req, TenantContext t, String a, String b) {
    l.support.requireFeature(t);
    return f(req, t, m.id(a), m.id(b));
  };

  String? q(Request req, String name) => m.query(req, name);
  String? key(Request req) => req.headers['idempotency-key'];

  // -------------------------------------------------------------- catalogue
  r.get(
    '$_v1/laboratory/categories',
    m.secured(
      g0(
        (req, t) async => ok(req, {
          'categories': l.catalogue.categories(),
          'sampleTypes': sampleTypes,
          'priorities': labPriorities,
        }),
      ),
    ),
  );
  r.get(
    '$_v1/laboratory/tests',
    m.secured(
      g0((req, t) async {
        final page = await l.catalogue.list(
          t,
          req,
          q: q(req, 'q'),
          category: q(req, 'category'),
          status: q(req, 'status'),
          branchId: q(req, 'branchId'),
        );
        return m.list(req, page, (d) => LabSupport.present(d.data));
      }),
    ),
  );
  r.post(
    '$_v1/laboratory/tests',
    m.secured(
      g0(
        (req, t) async => ok(
          req,
          await l.catalogue.create(t, await m.body(req), requestId: m.rid(req)),
          status: 201,
        ),
      ),
      write: true,
    ),
  );
  r.get(
    '$_v1/laboratory/tests/<id>',
    m.secured(
      g1((req, t, id) async => ok(req, await l.catalogue.detail(t, id))),
    ),
  );
  r.patch(
    '$_v1/laboratory/tests/<id>',
    m.secured(
      g1(
        (req, t, id) async => ok(
          req,
          await l.catalogue.update(
            t,
            id,
            await m.body(req),
            requestId: m.rid(req),
          ),
        ),
      ),
      write: true,
    ),
  );

  // ----------------------------------------------------------------- orders
  r.get(
    '$_v1/laboratory/orders',
    m.secured(
      g0((req, t) async {
        final page = await l.orders.list(
          t,
          req,
          status: q(req, 'status'),
          priority: q(req, 'priority'),
          doctorId: q(req, 'doctorId'),
          patientId: q(req, 'patientId'),
          branchId: q(req, 'branchId'),
          from: q(req, 'from'),
          to: q(req, 'to'),
          q: q(req, 'q'),
        );
        return m.list(req, page, (d) => PortalLike.summary(d.data));
      }),
    ),
  );
  r.post(
    '$_v1/laboratory/orders',
    m.secured(
      g0(
        (req, t) async => ok(
          req,
          await l.orders.createManual(
            t,
            await m.body(req),
            idempotencyKey: key(req),
            requestId: m.rid(req),
          ),
          status: 201,
        ),
      ),
      write: true,
    ),
  );
  r.get(
    '$_v1/laboratory/orders/<id>',
    m.secured(g1((req, t, id) async => ok(req, await l.orders.detail(t, id)))),
  );
  r.get(
    '$_v1/consultations/<cid>/lab-orders',
    m.secured(
      g1(
        (req, t, cid) async => ok(req, await l.orders.forConsultation(t, cid)),
      ),
    ),
  );
  r.post(
    '$_v1/consultations/<cid>/lab-orders',
    m.secured(
      g1(
        (req, t, cid) async => ok(
          req,
          await l.orders.createForConsultation(
            t,
            cid,
            await m.body(req),
            requestId: m.rid(req),
          ),
          status: 201,
        ),
      ),
      write: true,
    ),
  );

  Future<Response> act(
    Request req,
    TenantContext t,
    String id,
    Future<Map<String, Object?>> Function(Map<String, Object?> body) f,
  ) async => ok(req, await f(await m.optionalBody(req)));

  r.post(
    '$_v1/laboratory/orders/<id>/accept',
    m.secured(
      g1(
        (req, t, id) => act(
          req,
          t,
          id,
          (b) => l.orders.accept(t, id, b, requestId: m.rid(req)),
        ),
      ),
      write: true,
    ),
  );
  r.post(
    '$_v1/laboratory/orders/<id>/reject',
    m.secured(
      g1(
        (req, t, id) async => ok(
          req,
          await l.orders.reject(
            t,
            id,
            await m.body(req),
            requestId: m.rid(req),
          ),
        ),
      ),
      write: true,
    ),
  );
  r.post(
    '$_v1/laboratory/orders/<id>/cancel',
    m.secured(
      g1(
        (req, t, id) async => ok(
          req,
          await l.orders.cancel(
            t,
            id,
            await m.body(req),
            requestId: m.rid(req),
          ),
        ),
      ),
      write: true,
    ),
  );

  // ---------------------------------------------------------------- samples
  r.get(
    '$_v1/laboratory/samples',
    m.secured(
      g0((req, t) async {
        final page = await l.orders.listSamples(
          t,
          req,
          status: q(req, 'status'),
          branchId: q(req, 'branchId'),
          orderId: q(req, 'orderId'),
        );
        return m.list(req, page, (d) => LabSupport.present(d.data));
      }),
    ),
  );
  r.post(
    '$_v1/laboratory/orders/<id>/samples',
    m.secured(
      g1(
        (req, t, id) async => ok(
          req,
          await l.orders.createSample(
            t,
            id,
            await m.optionalBody(req),
            requestId: m.rid(req),
          ),
          status: 201,
        ),
      ),
      write: true,
    ),
  );
  r.post(
    '$_v1/laboratory/samples/<id>/collect',
    m.secured(
      g1(
        (req, t, id) async => ok(
          req,
          await l.orders.collect(
            t,
            id,
            await m.body(req),
            requestId: m.rid(req),
          ),
        ),
      ),
      write: true,
    ),
  );
  r.post(
    '$_v1/laboratory/samples/<id>/reject',
    m.secured(
      g1(
        (req, t, id) async => ok(
          req,
          await l.orders.rejectSample(
            t,
            id,
            await m.body(req),
            requestId: m.rid(req),
          ),
        ),
      ),
      write: true,
    ),
  );
  r.post(
    '$_v1/laboratory/samples/<id>/recollect',
    m.secured(
      g1(
        (req, t, id) async => ok(
          req,
          await l.orders.recollect(t, id, requestId: m.rid(req)),
          status: 201,
        ),
      ),
      write: true,
    ),
  );

  // ---------------------------------------------------------------- results
  r.get(
    '$_v1/laboratory/orders/<id>/results',
    m.secured(
      g1((req, t, id) async => ok(req, await l.results.forOrder(t, id))),
    ),
  );
  r.put(
    '$_v1/laboratory/orders/<id>/results/<item>',
    m.secured(
      g2(
        (req, t, id, item) async => ok(
          req,
          await l.results.save(
            t,
            id,
            item,
            await m.body(req),
            requestId: m.rid(req),
          ),
        ),
      ),
      write: true,
    ),
  );
  r.post(
    '$_v1/laboratory/orders/<id>/submit-verification',
    m.secured(
      g1(
        (req, t, id) async =>
            ok(req, await l.results.submit(t, id, requestId: m.rid(req))),
      ),
      write: true,
    ),
  );
  r.post(
    '$_v1/laboratory/orders/<id>/verify',
    m.secured(
      g1(
        (req, t, id) async =>
            ok(req, await l.results.verify(t, id, requestId: m.rid(req))),
      ),
      write: true,
    ),
  );
  r.post(
    '$_v1/laboratory/orders/<id>/return',
    m.secured(
      g1(
        (req, t, id) async => ok(
          req,
          await l.results.returnForCorrection(
            t,
            id,
            await m.body(req),
            requestId: m.rid(req),
          ),
        ),
      ),
      write: true,
    ),
  );
  r.post(
    '$_v1/laboratory/orders/<id>/results/<item>/amend',
    m.secured(
      g2(
        (req, t, id, item) async => ok(
          req,
          await l.results.amend(
            t,
            id,
            item,
            await m.body(req),
            requestId: m.rid(req),
          ),
          status: 201,
        ),
      ),
      write: true,
    ),
  );
  r.post(
    '$_v1/laboratory/orders/<id>/publish',
    m.secured(
      g1(
        (req, t, id) async =>
            ok(req, await l.results.publish(t, id, requestId: m.rid(req))),
      ),
      write: true,
    ),
  );
  r.post(
    '$_v1/laboratory/orders/<id>/external-report',
    m.secured(
      g1(
        (req, t, id) async => ok(
          req,
          await l.results.uploadExternal(
            t,
            id,
            await m.body(req),
            requestId: m.rid(req),
          ),
          status: 201,
        ),
      ),
      write: true,
    ),
  );

  // ---------------------------------------------------------------- reports
  r.get(
    '$_v1/laboratory/reports',
    m.secured(
      g0((req, t) async {
        final page = await l.results.listReports(
          t,
          req,
          orderId: q(req, 'orderId'),
          patientId: q(req, 'patientId'),
          branchId: q(req, 'branchId'),
          status: q(req, 'status'),
        );
        return m.list(
          req,
          page,
          (d) => LabSupport.present(d.data)..remove('storagePath'),
        );
      }),
    ),
  );
  r.get(
    '$_v1/laboratory/reports/<id>',
    m.secured(
      g1(
        (req, t, id) async =>
            ok(req, await l.results.reportDetail(t, id, requestId: m.rid(req))),
      ),
    ),
  );
  r.get(
    '$_v1/laboratory/reports/<id>/download',
    m.secured(
      g1((req, t, id) => l.results.download(t, id, requestId: m.rid(req))),
    ),
  );

  // ---------------------------------------------- external labs, dashboard
  r.get(
    '$_v1/laboratory/external-labs',
    m.secured(g0((req, t) async => ok(req, await l.catalogue.externalLabs(t)))),
  );
  r.post(
    '$_v1/laboratory/external-labs',
    m.secured(
      g0(
        (req, t) async => ok(
          req,
          await l.catalogue.createExternalLab(
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
    '$_v1/laboratory/dashboard',
    m.secured(g0((req, t) async => ok(req, await l.orders.dashboard(t, req)))),
  );
  r.get(
    '$_v1/laboratory/audit',
    m.secured(
      g0((req, t) async {
        final page = await l.results.auditLogs(
          t,
          req,
          orderId: q(req, 'orderId'),
          patientId: q(req, 'patientId'),
          action: q(req, 'action'),
        );
        return m.list(req, page, (d) => LabSupport.present(d.data));
      }),
    ),
  );
}
