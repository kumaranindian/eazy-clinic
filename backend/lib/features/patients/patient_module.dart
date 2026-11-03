import 'dart:typed_data';

import 'package:api_contracts/api_contracts.dart';
import 'package:common_models/common_models.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../../core/data/document_store.dart';
import '../../core/responses/responses.dart';
import '../../core/security/rate_limiter.dart';
import '../../core/validation/request_validator.dart';
import '../auth/domain/auth_context.dart';
import '../clinic/clinic_module.dart';
import '../clinic/common/clinic_deps.dart';
import '../clinic/common/object_storage.dart';
import '../clinic/common/tenant_context.dart';
import '../platform/common/paging.dart';
import 'clinical_records.dart';
import 'consent_service.dart';
import 'document_service.dart';
import 'family_service.dart';
import 'identity_service.dart';
import 'patient_service.dart';
import 'patient_support.dart';

/// Services of the patient foundation (Phase 4).
class PatientModule {
  PatientModule(ClinicDeps deps, ObjectStorage storage)
    : support = PatientSupport(deps) {
    consents = ConsentService(support);
    patients = PatientService(support, consents);
    specs = RecordSpecs(() => deps.now);
    records = ClinicalRecordService(support);
    documents = PatientDocumentService(support, storage);
    accounts = PatientAccountService(support);
    identity = PatientIdentityService(support, accounts, consents);
  }

  final PatientSupport support;
  late final ConsentService consents;
  late final PatientService patients;
  late final RecordSpecs specs;
  late final ClinicalRecordService records;
  late final PatientDocumentService documents;
  late final PatientAccountService accounts;
  late final PatientIdentityService identity;

  /// Patient audit trail (tenant scoped, newest first).
  Future<Paged> auditLogs(
    TenantContext t,
    String patientId,
    Request req,
  ) async {
    t.require(ClinicPermission.patientAuditView);
    await support.load(t, patientId);
    return runPaged(
      support.d.store,
      DocQuery(
        support.d.path(t, 'patient_audit_logs'),
        filters: [QueryFilter('patientId', FilterOp.eq, patientId)],
        orderBy: const OrderBy('timestamp', descending: true),
      ),
      req,
    );
  }
}

const String _v1 = apiV1Prefix;

/// Registers the patient routes on [r]. Authentication, tenant resolution,
/// rate limiting and subscription gating come from [m]'s `secured` wrapper;
/// permission, branch and consent checks happen in the services.
void registerPatientRoutes(
  ClinicModule m,
  PatientModule p,
  Router r, {
  required RateLimiter identityLimiter,
  required RateLimiter familyLimiter,
}) {
  // ------------------------------------------------------------ directory
  r.get(
    '$_v1/patients',
    m.secured((Request req, TenantContext t) async {
      final page = await p.patients.list(
        t,
        req,
        q: m.query(req, 'q'),
        status: m.query(req, 'status'),
        branchId: m.query(req, 'branchId'),
        gender: m.query(req, 'gender'),
        from: m.query(req, 'from'),
        to: m.query(req, 'to'),
      );
      return m.list(req, page, (d) => p.patients.listItem(d.data));
    }),
  );
  r.post(
    '$_v1/patients',
    m.secured(
      (Request req, TenantContext t) async => ok(
        req,
        await p.patients.create(t, await m.body(req), requestId: m.rid(req)),
        status: 201,
      ),
      write: true,
    ),
  );
  r.post(
    '$_v1/patients/duplicate-check',
    m.secured(
      (Request req, TenantContext t) async =>
          ok(req, await p.patients.duplicateCheck(t, await m.body(req))),
      write: true,
    ),
  );
  r.get(
    '$_v1/patients/<pid>',
    m.secured(
      (Request req, TenantContext t, String pid) async =>
          ok(req, await p.patients.detail(t, m.id(pid), requestId: m.rid(req))),
    ),
  );
  r.patch(
    '$_v1/patients/<pid>',
    m.secured(
      (Request req, TenantContext t, String pid) async => ok(
        req,
        await p.patients.update(
          t,
          m.id(pid),
          await m.body(req),
          requestId: m.rid(req),
        ),
      ),
      write: true,
    ),
  );
  for (final (path, to) in [
    ('activate', 'active'),
    ('deactivate', 'inactive'),
    ('archive', 'archived'),
  ]) {
    r.post(
      '$_v1/patients/<pid>/$path',
      m.secured((Request req, TenantContext t, String pid) async {
        final body = await m.optionalBody(req);
        final reason = body['reason'];
        return ok(
          req,
          await p.patients.setStatus(
            t,
            m.id(pid),
            to,
            reason: reason is String ? reason : null,
            requestId: m.rid(req),
          ),
        );
      }, write: true),
    );
  }
  r.get(
    '$_v1/patients/<pid>/possible-duplicates',
    m.secured(
      (Request req, TenantContext t, String pid) async =>
          ok(req, await p.patients.possibleDuplicates(t, m.id(pid))),
    ),
  );

  // ------------------------------------------------- identity (clinic side)
  r.post(
    '$_v1/patients/<pid>/link-account',
    m.secured(
      (Request req, TenantContext t, String pid) async => ok(
        req,
        await p.identity.createLinkCode(
          t,
          m.id(pid),
          await m.body(req),
          requestId: m.rid(req),
        ),
        status: 201,
      ),
      write: true,
      limiter: identityLimiter,
    ),
  );
  r.post(
    '$_v1/patients/<pid>/unlink-account',
    m.secured(
      (Request req, TenantContext t, String pid) async => ok(
        req,
        await p.identity.unlinkByClinic(
          t,
          m.id(pid),
          await m.body(req),
          requestId: m.rid(req),
        ),
      ),
      write: true,
      limiter: identityLimiter,
    ),
  );

  // --------------------------------------------- clinical record families
  void records(String path, RecordSpec Function() spec, String idParam) {
    r.get(
      '$_v1/patients/<pid>/$path',
      m.secured((Request req, TenantContext t, String pid) async {
        final page = await p.records.list(
          t,
          spec(),
          m.id(pid),
          req,
          requestId: m.rid(req),
        );
        return m.list(req, page, (d) => ClinicalRecordService.present(d.data));
      }),
    );
    r.post(
      '$_v1/patients/<pid>/$path',
      m.secured(
        (Request req, TenantContext t, String pid) async => ok(
          req,
          await p.records.create(
            t,
            spec(),
            m.id(pid),
            await m.body(req),
            requestId: m.rid(req),
          ),
          status: 201,
        ),
        write: true,
      ),
    );
    r.patch(
      '$_v1/patients/<pid>/$path/<rid>',
      m.secured(
        (Request req, TenantContext t, String pid, String rid) async => ok(
          req,
          await p.records.update(
            t,
            spec(),
            m.id(pid),
            m.id(rid),
            await m.body(req),
            requestId: m.rid(req),
          ),
        ),
        write: true,
      ),
    );
  }

  records('medical-history', () => p.specs.history, 'entryId');
  records('allergies', () => p.specs.allergy, 'allergyId');
  records('medications', () => p.specs.medication, 'medicationId');
  records('alerts', () => p.specs.alert, 'alertId');

  r.get(
    '$_v1/patients/<pid>/emergency-contacts',
    m.secured(
      (Request req, TenantContext t, String pid) async =>
          ok(req, await p.records.getContacts(t, m.id(pid))),
    ),
  );
  r.put(
    '$_v1/patients/<pid>/emergency-contacts',
    m.secured(
      (Request req, TenantContext t, String pid) async => ok(
        req,
        await p.records.putContacts(
          t,
          m.id(pid),
          await m.body(req),
          requestId: m.rid(req),
        ),
      ),
      write: true,
    ),
  );

  // -------------------------------------------------------------- consent
  r.get(
    '$_v1/consent-catalog',
    m.secured(
      (Request req, TenantContext t) async => ok(req, p.consents.catalog()),
    ),
  );
  r.get(
    '$_v1/patients/<pid>/consents',
    m.secured((Request req, TenantContext t, String pid) async {
      final page = await p.consents.list(t, m.id(pid), req);
      return m.list(req, page, (d) => ConsentService.present(d.data));
    }),
  );
  r.post(
    '$_v1/patients/<pid>/consents',
    m.secured(
      (Request req, TenantContext t, String pid) async => ok(
        req,
        await p.consents.record(
          t,
          m.id(pid),
          await m.body(req),
          requestId: m.rid(req),
        ),
        status: 201,
      ),
      write: true,
    ),
  );
  r.post(
    '$_v1/patients/<pid>/consents/<cid>/revoke',
    m.secured(
      (Request req, TenantContext t, String pid, String cid) async => ok(
        req,
        await p.consents.revoke(
          t,
          m.id(pid),
          m.id(cid),
          await m.body(req),
          requestId: m.rid(req),
        ),
      ),
      write: true,
    ),
  );

  // ----------------------------------------------------------- documents
  r.get(
    '$_v1/patients/<pid>/documents',
    m.secured((Request req, TenantContext t, String pid) async {
      final page = await p.documents.list(
        t,
        m.id(pid),
        req,
        category: m.query(req, 'category'),
      );
      return m.list(req, page, (d) => PatientDocumentService.present(d.data));
    }),
  );
  r.post(
    '$_v1/patients/<pid>/documents',
    m.secured((Request req, TenantContext t, String pid) async {
      // base64 of up to 3 MB plus JSON framing
      final payload = await readJsonObject(req, maxBytes: 5 * 1024 * 1024);
      return ok(
        req,
        await p.documents.upload(t, m.id(pid), payload, requestId: m.rid(req)),
        status: 201,
      );
    }, write: true),
  );
  r.get(
    '$_v1/patients/<pid>/documents/<did>',
    m.secured(
      (Request req, TenantContext t, String pid, String did) async =>
          ok(req, await p.documents.detail(t, m.id(pid), m.id(did))),
    ),
  );
  r.get(
    '$_v1/patients/<pid>/documents/<did>/content',
    m.secured((Request req, TenantContext t, String pid, String did) async {
      final (bytes, type, _) = await p.documents.content(
        t,
        m.id(pid),
        m.id(did),
        requestId: m.rid(req),
      );
      return Response.ok(
        Uint8List.fromList(bytes),
        headers: {
          'content-type': type,
          'cache-control': 'private, no-store',
          'x-content-type-options': 'nosniff',
          'content-disposition': 'attachment',
        },
      );
    }),
  );
  r.delete(
    '$_v1/patients/<pid>/documents/<did>',
    m.secured(
      (Request req, TenantContext t, String pid, String did) async => ok(
        req,
        await p.documents.remove(
          t,
          m.id(pid),
          m.id(did),
          m.query(req, 'reason', max: 300),
          requestId: m.rid(req),
        ),
      ),
      write: true,
    ),
  );

  // --------------------------------------------------------------- audit
  r.get(
    '$_v1/patients/<pid>/audit-logs',
    m.secured((Request req, TenantContext t, String pid) async {
      final page = await p.auditLogs(t, m.id(pid), req);
      return m.list(
        req,
        page,
        (d) => jsonSafe(d.data)! as Map<String, Object?>,
      );
    }),
  );

  // ------------------------------------- global patient identity (patient)
  r.post(
    '$_v1/patient-accounts',
    m.userSecured(
      (Request req, AuthContext ctx) async =>
          ok(req, await p.accounts.create(ctx, await m.body(req)), status: 201),
      limiter: familyLimiter,
    ),
  );
  r.get(
    '$_v1/patient-accounts/me',
    m.userSecured(
      (Request req, AuthContext ctx) async =>
          ok(req, await p.accounts.mine(ctx)),
      limiter: familyLimiter,
    ),
  );
  r.get(
    '$_v1/patient-accounts/me/clinic-links',
    m.userSecured(
      (Request req, AuthContext ctx) async => ok(
        req,
        await p.accounts.clinicLinks(
          ctx,
          forAccountId: m.query(req, 'accountId', max: 40),
        ),
      ),
      limiter: familyLimiter,
    ),
  );
  r.post(
    '$_v1/patient-accounts/me/link-clinic-record',
    m.userSecured(
      (Request req, AuthContext ctx) async => ok(
        req,
        await p.identity.claim(ctx, await m.body(req), requestId: m.rid(req)),
        status: 201,
      ),
      limiter: identityLimiter,
    ),
  );
  r.post(
    '$_v1/patient-accounts/me/clinic-links/<lid>/unlink',
    m.userSecured(
      (Request req, AuthContext ctx) async => ok(
        req,
        await p.identity.unlinkByPatient(
          ctx,
          req.params['lid']!,
          await m.optionalBody(req),
          requestId: m.rid(req),
        ),
      ),
      limiter: identityLimiter,
    ),
  );

  // -------------------------------------------------------------- family
  r.get(
    '$_v1/patient-accounts/me/family',
    m.userSecured(
      (Request req, AuthContext ctx) async =>
          ok(req, await p.accounts.listMine(ctx)),
      limiter: familyLimiter,
    ),
  );
  r.post(
    '$_v1/patient-accounts/me/family',
    m.userSecured(
      (Request req, AuthContext ctx) async => ok(
        req,
        await p.accounts.createRelationship(ctx, await m.body(req)),
        status: 201,
      ),
      limiter: familyLimiter,
    ),
  );
  r.get(
    '$_v1/family-relationships/<fid>',
    m.userSecured(
      (Request req, AuthContext ctx) async => ok(
        req,
        await p.accounts.getRelationship(ctx, m.id(req.params['fid']!)),
      ),
      limiter: familyLimiter,
    ),
  );
  r.patch(
    '$_v1/family-relationships/<fid>',
    m.userSecured(
      (Request req, AuthContext ctx) async => ok(
        req,
        await p.accounts.update(
          ctx,
          m.id(req.params['fid']!),
          await m.body(req),
        ),
      ),
      limiter: familyLimiter,
    ),
  );
  r.post(
    '$_v1/family-relationships/<fid>/verify',
    m.userSecured(
      (Request req, AuthContext ctx) async => ok(
        req,
        await p.accounts.verify(
          ctx,
          m.id(req.params['fid']!),
          await m.body(req),
        ),
      ),
      limiter: identityLimiter,
    ),
  );
  r.post(
    '$_v1/family-relationships/<fid>/revoke',
    m.userSecured(
      (Request req, AuthContext ctx) async => ok(
        req,
        await p.accounts.revoke(
          ctx,
          m.id(req.params['fid']!),
          await m.optionalBody(req),
        ),
      ),
      limiter: familyLimiter,
    ),
  );
}
