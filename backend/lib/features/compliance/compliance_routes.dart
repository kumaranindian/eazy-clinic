import 'dart:typed_data';

import 'package:api_contracts/api_contracts.dart';
import 'package:common_models/common_models.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../../core/responses/responses.dart';
import '../../core/validation/request_validator.dart';
import '../clinic/clinic_module.dart';
import '../clinic/common/tenant_context.dart';
import 'tenant_compliance_service.dart';

const String _v1 = apiV1Prefix;

/// 3 MB of file as base64 plus framing.
const int _uploadBodyBytes = 5 * 1024 * 1024;

/// Phase 14: a clinic's compliance checklist, evidence and credentials.
/// Viewing needs `compliance.view`; uploading and editing need
/// `compliance.manage`. Approving evidence is a platform reviewer action.
void registerComplianceRoutes(
  ClinicModule m,
  TenantComplianceService s,
  Router r,
) {
  r.get(
    '$_v1/compliance/dashboard',
    m.secured((Request req, TenantContext t) async {
      t.require(ClinicPermission.complianceView);
      return ok(req, await s.dashboard(t.tenantId));
    }),
  );
  r.get(
    '$_v1/compliance/history',
    m.secured((Request req, TenantContext t) async {
      t.require(ClinicPermission.complianceView);
      return ok(req, {'items': await s.history(t.tenantId)});
    }),
  );
  r.get(
    '$_v1/compliance/evidence',
    m.secured((Request req, TenantContext t) async {
      t.require(ClinicPermission.complianceView);
      return ok(req, {'items': await s.listEvidence(t.tenantId)});
    }),
  );
  r.post(
    '$_v1/compliance/evidence',
    m.secured((Request req, TenantContext t) async {
      t.require(ClinicPermission.complianceManage);
      final body = await readJsonObject(req, maxBytes: _uploadBodyBytes);
      return ok(
        req,
        await s.uploadEvidence(
          t.tenantId,
          body,
          m.actor(t),
          requestId: m.rid(req),
        ),
        status: 201,
      );
    }, write: true),
  );
  r.get(
    '$_v1/compliance/evidence/<id>/file',
    m.secured((Request req, TenantContext t, String id) async {
      t.require(ClinicPermission.complianceView);
      final f = await s.downloadEvidence(
        t.tenantId,
        m.id(id),
        m.actor(t),
        requestId: m.rid(req),
      );
      return fileResponse(f.bytes, f.mime, f.filename);
    }),
  );
  r.get(
    '$_v1/compliance/credentials',
    m.secured((Request req, TenantContext t) async {
      t.require(ClinicPermission.complianceView);
      return ok(req, {'items': await s.listCredentials(t.tenantId)});
    }),
  );
  r.post(
    '$_v1/compliance/credentials',
    m.secured((Request req, TenantContext t) async {
      t.require(ClinicPermission.complianceManage);
      return ok(
        req,
        await s.createCredential(
          t.tenantId,
          await m.body(req),
          m.actor(t),
          requestId: m.rid(req),
        ),
        status: 201,
      );
    }, write: true),
  );
  r.patch(
    '$_v1/compliance/credentials/<id>',
    m.secured((Request req, TenantContext t, String id) async {
      t.require(ClinicPermission.complianceManage);
      return ok(
        req,
        await s.updateCredential(
          t.tenantId,
          m.id(id),
          await m.body(req),
          m.actor(t),
          requestId: m.rid(req),
        ),
      );
    }, write: true),
  );
  r.post(
    '$_v1/compliance/credentials/<id>/archive',
    m.secured((Request req, TenantContext t, String id) async {
      t.require(ClinicPermission.complianceManage);
      return ok(
        req,
        await s.archiveCredential(
          t.tenantId,
          m.id(id),
          m.actor(t),
          requestId: m.rid(req),
        ),
      );
    }, write: true),
  );
  r.post(
    '$_v1/compliance/credentials/<id>/document',
    m.secured((Request req, TenantContext t, String id) async {
      t.require(ClinicPermission.complianceManage);
      final body = await readJsonObject(req, maxBytes: _uploadBodyBytes);
      return ok(
        req,
        await s.attachCredentialEvidence(
          t.tenantId,
          m.id(id),
          body,
          m.actor(t),
          requestId: m.rid(req),
        ),
      );
    }, write: true),
  );
}

/// An authenticated file download: never cached, never sniffed, with a
/// generic file name.
Response fileResponse(Uint8List bytes, String mime, String filename) =>
    Response.ok(
      bytes,
      headers: {
        'content-type': mime,
        'content-disposition': 'attachment; filename="$filename"',
        'cache-control': 'private, no-store',
        'x-content-type-options': 'nosniff',
      },
    );
