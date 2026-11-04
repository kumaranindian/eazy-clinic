import 'package:api_contracts/api_contracts.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../../core/responses/responses.dart';
import '../../core/security/rate_limiter.dart';
import '../clinic/clinic_module.dart';
import '../clinic/common/tenant_context.dart';
import 'export_service.dart';
import 'report_service.dart';

const String _v1 = apiV1Prefix;

/// Phase 10: operational dashboard, reports and exports.
void registerReportRoutes(
  ClinicModule m,
  ReportService reports,
  ExportService exports,
  Router r,
) {
  final exportLimiter = RateLimiter(
    maxRequests: 20,
    window: const Duration(hours: 1),
  );

  Map<String, String> filters(Request req) => {
    for (final k in const ['from', 'to', 'branchId', 'doctorId'])
      if (m.query(req, k) != null) k: m.query(req, k)!,
  };

  r.get(
    '$_v1/reports/dashboard',
    m.secured(
      (Request req, TenantContext t) async =>
          ok(req, await reports.dashboard(t, filters(req))),
    ),
  );
  for (final kind in reportKinds) {
    r.get(
      '$_v1/reports/$kind',
      m.secured(
        (Request req, TenantContext t) async =>
            ok(req, (await reports.run(t, kind, filters(req))).toJson()),
      ),
    );
  }
  r.post(
    '$_v1/reports/exports',
    m.secured(
      (Request req, TenantContext t) async => ok(
        req,
        await exports.create(t, await m.body(req), requestId: m.rid(req)),
        status: 201,
      ),
      limiter: exportLimiter,
    ),
  );
  r.get(
    '$_v1/reports/exports',
    m.secured((Request req, TenantContext t) async {
      final page = await exports.history(t, req);
      return m.list(req, page, (d) => exports.present(d.data));
    }),
  );
  r.get(
    '$_v1/reports/exports/<id>',
    m.secured(
      (Request req, TenantContext t, String id) async =>
          ok(req, await exports.detail(t, m.id(id))),
    ),
  );
  r.get(
    '$_v1/reports/exports/<id>/download',
    m.secured(
      (Request req, TenantContext t, String id) =>
          exports.download(t, m.id(id), requestId: m.rid(req)),
    ),
  );
}
