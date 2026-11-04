import 'package:api_contracts/api_contracts.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../../core/responses/responses.dart';
import '../clinic/clinic_module.dart';
import '../clinic/common/clinic_deps.dart';
import '../clinic/common/tenant_context.dart';
import '../patients/patient_support.dart';
import '../scheduling/scheduling_support.dart';
import 'billing_support.dart';
import 'catalogue_service.dart';
import 'expense_service.dart';
import 'gateway.dart';
import 'invoice_service.dart';
import 'payment_service.dart';
import 'refund_service.dart';
import 'report_service.dart';

/// Phase 7: billing, payments, patient credit, refunds, expenses and finance
/// reports.
class BillingModule {
  BillingModule(
    ClinicDeps deps,
    PatientSupport patients,
    SchedulingSupport scheduling, {
    this.gateway = const NotConfiguredGateway(),
  }) : support = BillingSupport(deps, patients, scheduling) {
    catalogue = CatalogueService(support);
    invoices = InvoiceService(support, catalogue);
    payments = PaymentService(support, invoices);
    refunds = RefundService(support, invoices, payments);
    expenses = ExpenseService(support);
    reports = ReportService(support);
  }

  final BillingSupport support;
  final PaymentGateway gateway;
  late final CatalogueService catalogue;
  late final InvoiceService invoices;
  late final PaymentService payments;
  late final RefundService refunds;
  late final ExpenseService expenses;
  late final ReportService reports;
}

const String _v1 = apiV1Prefix;

void registerBillingRoutes(ClinicModule m, BillingModule b, Router r) {
  // Every handler checks the plan first.
  Function g0(Future<Response> Function(Request, TenantContext) f) =>
      (Request req, TenantContext t) {
        b.support.requireFeature(t);
        return f(req, t);
      };
  Function g1(Future<Response> Function(Request, TenantContext, String) f) =>
      (Request req, TenantContext t, String a) {
        b.support.requireFeature(t);
        return f(req, t, m.id(a));
      };

  String? key(Request req) => req.headers['idempotency-key'];

  // ---------------------------------------------------------- settings
  r.get(
    '$_v1/billing/settings',
    m.secured(g0((req, t) async => ok(req, await b.catalogue.getSettings(t)))),
  );
  r.put(
    '$_v1/billing/settings',
    m.secured(
      g0(
        (req, t) async => ok(
          req,
          await b.catalogue.updateSettings(
            t,
            await m.body(req),
            requestId: m.rid(req),
          ),
        ),
      ),
      write: true,
    ),
  );
  r.get(
    '$_v1/billing/gateway',
    m.secured(
      g0(
        (req, t) async => ok(req, {
          'configured': b.gateway.configured,
          'methods': await b.support.allowedMethods(t),
          'note': b.gateway.configured
              ? null
              : 'Online payments are not available. Payments are recorded by staff.',
        }),
      ),
    ),
  );

  // ---------------------------------------------------------- tax rules
  r.get(
    '$_v1/billing/tax-rules',
    m.secured(g0((req, t) async => ok(req, await b.catalogue.listTaxRules(t)))),
  );
  r.post(
    '$_v1/billing/tax-rules',
    m.secured(
      g0(
        (req, t) async => ok(
          req,
          await b.catalogue.createTaxRule(
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
    '$_v1/billing/tax-rules/<id>',
    m.secured(
      g1(
        (req, t, id) async => ok(
          req,
          await b.catalogue.updateTaxRule(
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

  // ----------------------------------------------------------- services
  r.get(
    '$_v1/billing/services',
    m.secured(
      g0((req, t) async {
        final page = await b.catalogue.list(
          t,
          req,
          q: m.query(req, 'q'),
          category: m.query(req, 'category'),
          status: m.query(req, 'status'),
        );
        return m.list(req, page, (d) => BillingSupport.present(d.data));
      }),
    ),
  );
  r.post(
    '$_v1/billing/services',
    m.secured(
      g0(
        (req, t) async => ok(
          req,
          await b.catalogue.create(t, await m.body(req), requestId: m.rid(req)),
          status: 201,
        ),
      ),
      write: true,
    ),
  );
  r.patch(
    '$_v1/billing/services/<sid>',
    m.secured(
      g1(
        (req, t, id) async => ok(
          req,
          await b.catalogue.update(
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
  r.get(
    '$_v1/billing/services/<sid>/price-history',
    m.secured(
      g1((req, t, id) async => ok(req, await b.catalogue.priceHistory(t, id))),
    ),
  );

  // ----------------------------------------------------------- invoices
  r.post(
    '$_v1/billing/invoices',
    m.secured(
      g0(
        (req, t) async => ok(
          req,
          await b.invoices.create(t, await m.body(req), requestId: m.rid(req)),
          status: 201,
        ),
      ),
      write: true,
    ),
  );
  r.get(
    '$_v1/billing/invoices',
    m.secured(
      g0((req, t) async {
        final today = (await b.support.zone(t)).localDate(b.support.d.now);
        final page = await b.invoices.list(
          t,
          req,
          status: m.query(req, 'status'),
          patientId: m.query(req, 'patientId'),
          branchId: m.query(req, 'branchId'),
          from: m.query(req, 'from'),
          to: m.query(req, 'to'),
          q: m.query(req, 'q'),
        );
        return m.list(req, page, (d) => b.invoices.listItem(d, today));
      }),
    ),
  );
  r.get(
    '$_v1/billing/invoices/<id>',
    m.secured(
      g1(
        (req, t, id) async =>
            ok(req, await b.invoices.detail(t, id, requestId: m.rid(req))),
      ),
    ),
  );
  r.patch(
    '$_v1/billing/invoices/<id>',
    m.secured(
      g1(
        (req, t, id) async => ok(
          req,
          await b.invoices.update(
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
    '$_v1/billing/invoices/<id>/finalize',
    m.secured(
      g1(
        (req, t, id) async =>
            ok(req, await b.invoices.finalize(t, id, requestId: m.rid(req))),
      ),
      write: true,
    ),
  );
  r.post(
    '$_v1/billing/invoices/<id>/cancel',
    m.secured(
      g1(
        (req, t, id) async => ok(
          req,
          await b.invoices.cancel(
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
    '$_v1/billing/invoices/<id>/adjustments',
    m.secured(
      g1(
        (req, t, id) async => ok(
          req,
          await b.invoices.adjust(
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
  r.get(
    '$_v1/billing/invoices/<id>/payments',
    m.secured(
      g1((req, t, id) async => ok(req, await b.invoices.payments(t, id))),
    ),
  );

  // ----------------------------------------------------------- payments
  r.post(
    '$_v1/billing/payments',
    m.secured(
      g0(
        (req, t) async => ok(
          req,
          await b.payments.create(
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
    '$_v1/billing/payments',
    m.secured(
      g0((req, t) async {
        final page = await b.payments.list(
          t,
          req,
          patientId: m.query(req, 'patientId'),
          branchId: m.query(req, 'branchId'),
          method: m.query(req, 'method'),
          from: m.query(req, 'from'),
          to: m.query(req, 'to'),
        );
        return m.list(req, page, (d) => BillingSupport.present(d.data));
      }),
    ),
  );
  r.get(
    '$_v1/billing/payments/<pid>',
    m.secured(
      g1((req, t, id) async => ok(req, await b.payments.detail(t, id))),
    ),
  );
  r.post(
    '$_v1/billing/payments/<pid>/allocations',
    m.secured(
      g1(
        (req, t, id) async => ok(
          req,
          await b.payments.allocatePayment(
            t,
            id,
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
    '$_v1/billing/payments/<pid>/receipt',
    m.secured(
      g1(
        (req, t, id) async => ok(
          req,
          await b.payments.receiptOfPayment(t, id, requestId: m.rid(req)),
        ),
      ),
    ),
  );
  r.get(
    '$_v1/billing/receipts/<rid>',
    m.secured(
      g1(
        (req, t, id) async =>
            ok(req, await b.payments.receipt(t, id, requestId: m.rid(req))),
      ),
    ),
  );

  // ------------------------------------------------------ patient credit
  r.post(
    '$_v1/billing/patient-credits',
    m.secured(
      g0(
        (req, t) async => ok(
          req,
          await b.payments.createCredit(
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
    '$_v1/billing/patients/<pid>/credits',
    m.secured(
      g1((req, t, id) async => ok(req, await b.payments.credits(t, id))),
    ),
  );
  r.post(
    '$_v1/billing/patient-credits/<cid>/allocations',
    m.secured((Request req, TenantContext t, String cid) async {
      b.support.requireFeature(t);
      return ok(
        req,
        await b.payments.allocateCredit(
          t,
          cid,
          await m.body(req),
          idempotencyKey: key(req),
          requestId: m.rid(req),
        ),
        status: 201,
      );
    }, write: true),
  );

  // ------------------------------------------------------------ refunds
  r.post(
    '$_v1/billing/refunds',
    m.secured(
      g0(
        (req, t) async => ok(
          req,
          await b.refunds.request(
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
    '$_v1/billing/refunds',
    m.secured(
      g0((req, t) async {
        final page = await b.refunds.list(
          t,
          req,
          status: m.query(req, 'status'),
          patientId: m.query(req, 'patientId'),
          branchId: m.query(req, 'branchId'),
          paymentId: m.query(req, 'paymentId'),
          from: m.query(req, 'from'),
          to: m.query(req, 'to'),
        );
        return m.list(req, page, (d) => BillingSupport.present(d.data));
      }),
    ),
  );
  r.get(
    '$_v1/billing/refunds/<id>',
    m.secured(g1((req, t, id) async => ok(req, await b.refunds.detail(t, id)))),
  );
  for (final action in ['approve', 'reject', 'complete']) {
    r.post(
      '$_v1/billing/refunds/<id>/$action',
      m.secured(
        g1((req, t, id) async {
          final body = await m.optionalBody(req);
          final rid = m.rid(req);
          return ok(req, switch (action) {
            'approve' => await b.refunds.approve(t, id, body, requestId: rid),
            'reject' => await b.refunds.reject(t, id, body, requestId: rid),
            _ => await b.refunds.complete(t, id, body, requestId: rid),
          });
        }),
        write: true,
      ),
    );
  }

  // ----------------------------------------------------------- expenses
  r.get(
    '$_v1/expenses/categories',
    m.secured(g0((req, t) async => ok(req, await b.expenses.categories(t)))),
  );
  r.post(
    '$_v1/expenses/categories',
    m.secured(
      g0(
        (req, t) async => ok(
          req,
          await b.expenses.createCategory(
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
    '$_v1/expenses/categories/<id>',
    m.secured(
      g1(
        (req, t, id) async => ok(
          req,
          await b.expenses.updateCategory(
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
  r.get(
    '$_v1/expenses',
    m.secured(
      g0((req, t) async {
        final page = await b.expenses.list(
          t,
          req,
          status: m.query(req, 'status'),
          categoryId: m.query(req, 'categoryId'),
          branchId: m.query(req, 'branchId'),
          from: m.query(req, 'from'),
          to: m.query(req, 'to'),
        );
        return m.list(req, page, (d) => BillingSupport.present(d.data));
      }),
    ),
  );
  r.post(
    '$_v1/expenses',
    m.secured(
      g0(
        (req, t) async => ok(
          req,
          await b.expenses.create(t, await m.body(req), requestId: m.rid(req)),
          status: 201,
        ),
      ),
      write: true,
    ),
  );
  r.get(
    '$_v1/expenses/<id>',
    m.secured(
      g1((req, t, id) async => ok(req, await b.expenses.detail(t, id))),
    ),
  );
  r.patch(
    '$_v1/expenses/<id>',
    m.secured(
      g1(
        (req, t, id) async => ok(
          req,
          await b.expenses.update(
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
    '$_v1/expenses/<id>/submit',
    m.secured(
      g1(
        (req, t, id) async =>
            ok(req, await b.expenses.submit(t, id, requestId: m.rid(req))),
      ),
      write: true,
    ),
  );
  for (final action in ['approve', 'reject', 'pay']) {
    r.post(
      '$_v1/expenses/<id>/$action',
      m.secured(
        g1((req, t, id) async {
          final body = await m.optionalBody(req);
          final rid = m.rid(req);
          return ok(req, switch (action) {
            'approve' => await b.expenses.approve(t, id, body, requestId: rid),
            'reject' => await b.expenses.reject(t, id, body, requestId: rid),
            _ => await b.expenses.pay(t, id, body, requestId: rid),
          });
        }),
        write: true,
      ),
    );
  }

  // ------------------------------------------------------------ reports
  r.get(
    '$_v1/finance/dashboard',
    m.secured(g0((req, t) async => ok(req, await b.reports.dashboard(t, req)))),
  );
  Future<Response> report(
    Request req,
    TenantContext t,
    String name,
    Future<Map<String, Object?>> Function() build,
  ) async {
    final data = await build();
    if (req.url.queryParameters['format'] == 'csv') {
      return await b.reports.csv(t, name, data, requestId: m.rid(req));
    }
    return ok(req, data);
  }

  r.get(
    '$_v1/finance/reports/collections',
    m.secured(
      g0(
        (req, t) =>
            report(req, t, 'collections', () => b.reports.collections(t, req)),
      ),
    ),
  );
  r.get(
    '$_v1/finance/reports/outstanding',
    m.secured(
      g0(
        (req, t) =>
            report(req, t, 'outstanding', () => b.reports.outstanding(t, req)),
      ),
    ),
  );
  r.get(
    '$_v1/finance/reports/refunds',
    m.secured(
      g0(
        (req, t) => report(req, t, 'refunds', () => b.reports.refunds(t, req)),
      ),
    ),
  );
  r.get(
    '$_v1/finance/reports/expenses',
    m.secured(
      g0(
        (req, t) =>
            report(req, t, 'expenses', () => b.reports.expenses(t, req)),
      ),
    ),
  );
  r.get(
    '$_v1/finance/reports/branch-wise',
    m.secured(
      g0(
        (req, t) =>
            report(req, t, 'branch-wise', () => b.reports.branchWise(t, req)),
      ),
    ),
  );
  r.get(
    '$_v1/finance/reports/doctor-wise',
    m.secured(
      g0(
        (req, t) =>
            report(req, t, 'doctor-wise', () => b.reports.doctorWise(t, req)),
      ),
    ),
  );
}
