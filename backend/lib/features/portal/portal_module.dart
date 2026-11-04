import 'package:api_contracts/api_contracts.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../../core/responses/responses.dart';
import '../../core/security/rate_limiter.dart';
import '../auth/domain/auth_context.dart';
import '../clinic/clinic_module.dart';
import '../clinic/common/clinic_deps.dart';
import '../clinic/common/object_storage.dart';
import '../patients/patient_module.dart';
import '../scheduling/scheduling_module.dart';
import 'portal_account.dart';
import 'portal_appointments.dart';
import 'portal_billing.dart';
import 'portal_discovery.dart';
import 'portal_lab.dart';
import 'portal_notifier.dart';
import 'portal_records.dart';
import 'portal_support.dart';

/// Phase 8: the patient-facing API (`/patient/...`).
///
/// A thin layer over the existing modules. It adds no second identity system,
/// no second appointment engine and no second notification system: it resolves
/// the caller to a patient account, applies patient authorization (own record,
/// verified relationship, existing clinic link), then reuses the shared
/// services and returns allow-listed projections.
class PortalModule {
  PortalModule(
    ClinicDeps deps,
    PatientModule patients,
    SchedulingModule sched,
    ObjectStorage storage,
  ) : support = PortalSupport(
        deps,
        patients.accounts,
        patients.support,
        sched.support,
      ),
      notifier = PortalNotifier(deps) {
    discovery = PortalDiscoveryService(support, sched.slots);
    appointments = PortalAppointmentService(
      support,
      sched.appointments,
      sched.queue,
      notifier,
    );
    records = PortalRecordsService(support);
    lab = PortalLabService(support, storage);
    billing = PortalBillingService(support);
    notifications = PortalNotificationService(support);
    account = PortalAccountService(support, patients.consents);
  }

  final PortalSupport support;
  final PortalNotifier notifier;
  late final PortalDiscoveryService discovery;
  late final PortalAppointmentService appointments;
  late final PortalRecordsService records;
  late final PortalLabService lab;
  late final PortalBillingService billing;
  late final PortalNotificationService notifications;
  late final PortalAccountService account;

  /// Generous: the app reads many small lists. Abuse of linking and booking is
  /// limited by their own rules (codes, idempotency, policy).
  final RateLimiter limiter = RateLimiter(
    maxRequests: 600,
    window: const Duration(minutes: 1),
  );
}

const String _v1 = apiV1Prefix;

void registerPortalRoutes(ClinicModule m, PortalModule p, Router r) {
  Handler secured(Future<Response> Function(Request, AuthContext) h) =>
      m.userSecured(h, limiter: p.limiter);

  String? q(Request req, String name) => m.query(req, name);
  String pid(Request req, String name) => m.id(req.params[name]!);
  String? key(Request req) => req.headers['idempotency-key'];

  // ------------------------------------------------------------- profile
  r.get(
    '$_v1/patient/profile',
    secured((req, c) async => ok(req, await p.account.profile(c))),
  );
  r.patch(
    '$_v1/patient/profile',
    secured(
      (req, c) async =>
          ok(req, await p.account.updateProfile(c, await m.body(req))),
    ),
  );
  r.post(
    '$_v1/patient/account/deletion-request',
    secured(
      (req, c) async => ok(
        req,
        await p.account.requestDeletion(c, await m.optionalBody(req)),
        status: 201,
      ),
    ),
  );

  // ----------------------------------------------------------- discovery
  r.get(
    '$_v1/patient/clinics',
    secured(
      (req, c) async => ok(
        req,
        await p.discovery.clinics(c, q: q(req, 'q'), city: q(req, 'city')),
      ),
    ),
  );
  r.get(
    '$_v1/patient/clinics/<cid>',
    secured(
      (req, c) async => ok(req, await p.discovery.clinic(c, pid(req, 'cid'))),
    ),
  );
  r.get(
    '$_v1/patient/clinics/<cid>/doctors',
    secured(
      (req, c) async => ok(
        req,
        await p.discovery.doctors(
          c,
          pid(req, 'cid'),
          branchId: q(req, 'branchId'),
          q: q(req, 'q'),
          speciality: q(req, 'speciality'),
        ),
      ),
    ),
  );
  r.get(
    '$_v1/patient/clinics/<cid>/doctors/<did>',
    secured(
      (req, c) async => ok(
        req,
        await p.discovery.doctor(c, pid(req, 'cid'), pid(req, 'did')),
      ),
    ),
  );
  r.get(
    '$_v1/patient/clinics/<cid>/specialities',
    secured(
      (req, c) async =>
          ok(req, await p.discovery.specialities(c, pid(req, 'cid'))),
    ),
  );
  r.get(
    '$_v1/patient/clinics/<cid>/availability',
    secured(
      (req, c) async => ok(
        req,
        await p.discovery.availability(
          c,
          pid(req, 'cid'),
          branchId: q(req, 'branchId') ?? '',
          doctorId: q(req, 'doctorId') ?? '',
          date: q(req, 'date') ?? '',
          typeId: q(req, 'typeId'),
        ),
      ),
    ),
  );

  // -------------------------------------------------------- appointments
  r.get(
    '$_v1/patient/appointments',
    secured(
      (req, c) async => ok(
        req,
        await p.appointments.list(
          c,
          accountId: q(req, 'accountId'),
          clinicId: q(req, 'clinicId'),
          filter: q(req, 'filter'),
        ),
      ),
    ),
  );
  r.post(
    '$_v1/patient/appointments',
    secured(
      (req, c) async => ok(
        req,
        await p.appointments.book(
          c,
          await m.body(req),
          idempotencyKey: key(req),
          requestId: m.rid(req),
        ),
        status: 201,
      ),
    ),
  );
  r.get(
    '$_v1/patient/clinics/<cid>/appointments/<aid>',
    secured(
      (req, c) async => ok(
        req,
        await p.appointments.detail(
          c,
          pid(req, 'cid'),
          pid(req, 'aid'),
          accountId: q(req, 'accountId'),
        ),
      ),
    ),
  );
  r.post(
    '$_v1/patient/clinics/<cid>/appointments/<aid>/cancel',
    secured(
      (req, c) async => ok(
        req,
        await p.appointments.cancel(
          c,
          pid(req, 'cid'),
          pid(req, 'aid'),
          await m.optionalBody(req),
          requestId: m.rid(req),
        ),
      ),
    ),
  );
  r.post(
    '$_v1/patient/clinics/<cid>/appointments/<aid>/reschedule',
    secured(
      (req, c) async => ok(
        req,
        await p.appointments.reschedule(
          c,
          pid(req, 'cid'),
          pid(req, 'aid'),
          await m.body(req),
          requestId: m.rid(req),
        ),
      ),
    ),
  );
  r.post(
    '$_v1/patient/clinics/<cid>/appointments/<aid>/check-in',
    secured(
      (req, c) async => ok(
        req,
        await p.appointments.checkIn(
          c,
          pid(req, 'cid'),
          pid(req, 'aid'),
          await m.optionalBody(req),
          requestId: m.rid(req),
        ),
      ),
    ),
  );
  r.get(
    '$_v1/patient/clinics/<cid>/appointments/<aid>/queue',
    secured(
      (req, c) async => ok(
        req,
        await p.appointments.queue(
          c,
          pid(req, 'cid'),
          pid(req, 'aid'),
          accountId: q(req, 'accountId'),
        ),
      ),
    ),
  );

  // ------------------------------------------------------------- records
  Future<Response> records(
    Request req,
    AuthContext c,
    Future<List<Map<String, Object?>>> Function(
      String? accountId,
      String? clinicId,
    )
    f,
  ) async => ok(req, await f(q(req, 'accountId'), q(req, 'clinicId')));

  r.get(
    '$_v1/patient/medical-records',
    secured(
      (req, c) => records(
        req,
        c,
        (a, k) => p.records.overview(c, accountId: a, clinicId: k),
      ),
    ),
  );
  r.get(
    '$_v1/patient/consultations',
    secured(
      (req, c) => records(
        req,
        c,
        (a, k) => p.records.consultations(c, accountId: a, clinicId: k),
      ),
    ),
  );
  r.get(
    '$_v1/patient/prescriptions',
    secured(
      (req, c) => records(
        req,
        c,
        (a, k) => p.records.prescriptions(c, accountId: a, clinicId: k),
      ),
    ),
  );
  r.get(
    '$_v1/patient/documents',
    secured((req, c) async => ok(req, p.records.documents())),
  );
  r.get(
    '$_v1/patient/reports',
    secured(
      (req, c) async => ok(
        req,
        await p.lab.list(
          c,
          accountId: q(req, 'accountId'),
          clinicId: q(req, 'clinicId'),
        ),
      ),
    ),
  );
  r.get(
    '$_v1/patient/lab-reports',
    secured(
      (req, c) async => ok(
        req,
        await p.lab.list(
          c,
          accountId: q(req, 'accountId'),
          clinicId: q(req, 'clinicId'),
        ),
      ),
    ),
  );
  r.get(
    '$_v1/patient/clinics/<cid>/lab-reports/<rid>',
    secured(
      (req, c) async => ok(
        req,
        await p.lab.detail(
          c,
          pid(req, 'cid'),
          pid(req, 'rid'),
          accountId: q(req, 'accountId'),
        ),
      ),
    ),
  );
  r.get(
    '$_v1/patient/clinics/<cid>/lab-reports/<rid>/download',
    secured(
      (req, c) => p.lab.download(
        c,
        pid(req, 'cid'),
        pid(req, 'rid'),
        accountId: q(req, 'accountId'),
      ),
    ),
  );

  // ------------------------------------------------------------- billing
  r.get(
    '$_v1/patient/invoices',
    secured(
      (req, c) => records(
        req,
        c,
        (a, k) => p.billing.invoices(c, accountId: a, clinicId: k),
      ),
    ),
  );
  r.get(
    '$_v1/patient/clinics/<cid>/invoices/<iid>',
    secured(
      (req, c) async => ok(
        req,
        await p.billing.invoice(
          c,
          pid(req, 'cid'),
          pid(req, 'iid'),
          accountId: q(req, 'accountId'),
        ),
      ),
    ),
  );
  r.get(
    '$_v1/patient/payments',
    secured(
      (req, c) => records(
        req,
        c,
        (a, k) => p.billing.payments(c, accountId: a, clinicId: k),
      ),
    ),
  );
  r.get(
    '$_v1/patient/clinics/<cid>/receipts/<rid>',
    secured(
      (req, c) async => ok(
        req,
        await p.billing.receipt(
          c,
          pid(req, 'cid'),
          pid(req, 'rid'),
          accountId: q(req, 'accountId'),
        ),
      ),
    ),
  );
  r.get(
    '$_v1/patient/refunds',
    secured(
      (req, c) => records(
        req,
        c,
        (a, k) => p.billing.refunds(c, accountId: a, clinicId: k),
      ),
    ),
  );
  r.get(
    '$_v1/patient/billing-summary',
    secured(
      (req, c) async =>
          ok(req, await p.billing.summary(c, accountId: q(req, 'accountId'))),
    ),
  );

  // ------------------------------------------------------- notifications
  r.post(
    '$_v1/patient/devices',
    secured(
      (req, c) async => ok(
        req,
        await p.notifications.registerDevice(c, await m.body(req)),
        status: 201,
      ),
    ),
  );
  r.delete(
    '$_v1/patient/devices/<did>',
    secured(
      (req, c) async => ok(
        req,
        await p.notifications.unregisterDevice(c, req.params['did']!),
      ),
    ),
  );
  r.get(
    '$_v1/patient/notifications/preferences',
    secured((req, c) async => ok(req, await p.notifications.preferences(c))),
  );
  r.put(
    '$_v1/patient/notifications/preferences',
    secured(
      (req, c) async =>
          ok(req, await p.notifications.setPreferences(c, await m.body(req))),
    ),
  );
  r.get(
    '$_v1/patient/notifications',
    secured((req, c) async => ok(req, await p.notifications.inbox(c))),
  );
  r.post(
    '$_v1/patient/notifications/read-all',
    secured((req, c) async => ok(req, await p.notifications.markAllRead(c))),
  );
  r.post(
    '$_v1/patient/notifications/<nid>/archive',
    secured(
      (req, c) async =>
          ok(req, await p.notifications.archive(c, req.params['nid']!)),
    ),
  );
  r.post(
    '$_v1/patient/notifications/<nid>/read',
    secured(
      (req, c) async =>
          ok(req, await p.notifications.markRead(c, req.params['nid']!)),
    ),
  );

  r.get(
    '$_v1/patient/family',
    secured((req, c) async => ok(req, await p.account.family(c))),
  );

  // ------------------------------------------------------------- consent
  r.get(
    '$_v1/patient/consent-catalog',
    secured((req, c) async => ok(req, p.account.catalog())),
  );
  r.get(
    '$_v1/patient/clinics/<cid>/consents',
    secured(
      (req, c) async => ok(req, await p.account.consents(c, pid(req, 'cid'))),
    ),
  );
  r.post(
    '$_v1/patient/consents',
    secured(
      (req, c) async => ok(
        req,
        await p.account.decide(c, await m.body(req), requestId: m.rid(req)),
        status: 201,
      ),
    ),
  );
  r.post(
    '$_v1/patient/clinics/<cid>/consents/<kid>/revoke',
    secured(
      (req, c) async => ok(
        req,
        await p.account.withdraw(
          c,
          pid(req, 'cid'),
          pid(req, 'kid'),
          await m.optionalBody(req),
          requestId: m.rid(req),
        ),
      ),
    ),
  );
}
