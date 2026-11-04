@Tags(['emulator'])
library;

import 'dart:io';

import 'package:backend/core/data/document_store.dart';
import 'package:backend/core/data/firestore_document_store.dart';
import 'package:backend/core/errors/api_exception.dart';
import 'package:backend/features/billing/billing_module.dart';
import 'package:backend/features/clinic/branches/branch_service.dart';
import 'package:backend/features/clinic/common/clinic_deps.dart';
import 'package:backend/features/clinic/common/seat_service.dart';
import 'package:backend/features/clinic/common/tenant_context.dart';
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

class _Client extends http.BaseClient {
  _Client(this._inner);
  final http.Client _inner;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers['authorization'] = 'Bearer owner';
    return _inner.send(request);
  }
}

/// The financial workflow on the real Firestore REST store: catalogue, tax,
/// invoice numbering, payments with idempotency, advance credit ledger,
/// refunds, expenses and aggregated reports (range, `in` and equality
/// queries), plus tenant isolation. Sequential (the emulator serializes
/// transactions).
void main() {
  final host = Platform.environment['FIRESTORE_EMULATOR_HOST'];

  group(
    'billing workflow on the Firestore emulator',
    () {
      test(
        'invoice, payment, credit, refund, expense, reports and isolation',
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
                'features': {
                  'multiple_branches': true,
                  'appointments': true,
                  'billing': true,
                },
                'startDate': start,
                'endDate': start.add(const Duration(days: 60)),
                'overrides': <String, Object?>{},
              }),
            ]);
            return tid;
          }

          final deps = ClinicDeps(
            store: store,
            audit: AuditService(store, clock: () => start),
            seats: SeatService(store, clock: () => start),
            entitlements: EntitlementService(store, clock: () => start),
            clock: () => start,
          );
          final patients = PatientModule(deps, MemoryObjectStorage());
          final sched = SchedulingModule(deps, patients.support);
          final bill = BillingModule(deps, patients.support, sched.support);
          final branches = BranchService(deps);
          final tidA = await tenant('a');
          final tidB = await tenant('b');

          Future<TenantContext> ctx(
            String tid,
            ClinicRole role,
            String uid,
          ) async => TenantContext(
            tenantId: tid,
            uid: '$uid$suffix',
            role: role,
            scope: const BranchScope(allBranches: true, branchIds: {}),
            entitlements: await deps.entitlements.forTenant(tid),
          );

          final owner = await ctx(tidA, ClinicRole.clinicOwner, 'owner');
          final admin = await ctx(tidA, ClinicRole.clinicAdmin, 'admin');
          final recep = await ctx(tidA, ClinicRole.receptionist, 'recep');
          final acct = await ctx(tidA, ClinicRole.accountant, 'acct');
          final ownerB = await ctx(tidB, ClinicRole.clinicOwner, 'ownerB');
          final br =
              (await branches.create(
                    owner,
                    branchBody(code: 'EMU'),
                  ))['branchId']!
                  as String;
          await branches.create(ownerB, branchBody(code: 'EMUB'));
          final patient =
              (await patients.patients.create(
                    owner,
                    patientBody(br),
                  ))['patientId']!
                  as String;

          // catalogue with GST
          final rule = await bill.catalogue.createTaxRule(owner, {
            'name': 'GST 18%',
            'components': [
              {'name': 'CGST', 'rateBps': 900},
              {'name': 'SGST', 'rateBps': 900},
            ],
          });
          final svc = await bill.catalogue.create(owner, {
            'name': 'General Consultation',
            'category': 'consultation',
            'amountMinor': 50000,
            'taxRuleId': rule['taxRuleId'],
          });

          // invoice: server prices it, finalization numbers it
          final draft = await bill.invoices.create(recep, {
            'patientId': patient,
            'branchId': br,
            'lines': [
              {'serviceId': svc['serviceId'], 'quantity': 2},
            ],
          });
          expect(draft['grandTotal'], 118000);
          final id = draft['invoiceId']! as String;
          final fin = await bill.invoices.finalize(recep, id);
          expect(fin['invoiceNumber'], 'INV-000001');
          final again = await bill.invoices.finalize(recep, id);
          expect(again['idempotentReplay'], true);
          await expectLater(
            bill.invoices.update(recep, id, {'notes': 'late'}),
            throwsA(isA<ApiException>()),
            reason: 'finalized invoices are not editable',
          );

          // partial payment, replay with the same key
          Future<Map<String, Object?>> pay(
            int amount,
            String key, {
            String method = 'cash',
            String? ref,
          }) => bill.payments.create(recep, {
            'patientId': patient,
            'branchId': br,
            'amountMinor': amount,
            'method': method,
            'reference': ?ref,
            'allocations': [
              {'invoiceId': id, 'amountMinor': amount},
            ],
          }, idempotencyKey: key);
          final p1 = await pay(40000, 'emu-pay-$suffix');
          final p1again = await pay(40000, 'emu-pay-$suffix');
          expect(p1again['idempotentReplay'], true);
          expect(p1again['paymentId'], p1['paymentId']);
          expect((p1['receipt']! as Map)['receiptNumber'], 'RCT-000001');
          var inv = await bill.invoices.detail(recep, id);
          expect(inv['status'], 'partially_paid');
          expect(inv['outstanding'], 78000);
          await expectLater(
            pay(900000, 'emu-pay-over-$suffix'),
            throwsA(isA<ApiException>()),
            reason: 'overpayment is rejected',
          );
          await pay(
            78000,
            'emu-pay2-$suffix',
            method: 'upi',
            ref: 'UTR$suffix',
          );
          inv = await bill.invoices.detail(recep, id);
          expect(inv['status'], 'paid');
          expect(inv['amountPaid'], 118000);

          // advance credit and its ledger
          final adv = await bill.payments.createCredit(recep, {
            'kind': 'advance',
            'patientId': patient,
            'branchId': br,
            'amountMinor': 30000,
            'method': 'cash',
          }, idempotencyKey: 'emu-adv-$suffix');
          final credit = adv['creditId']! as String;
          final inv2 = await bill.invoices.finalize(
            recep,
            (await bill.invoices.create(recep, {
                  'patientId': patient,
                  'branchId': br,
                  'lines': [
                    {
                      'description': 'Dressing',
                      'unitMinor': 20000,
                      'quantity': 1,
                    },
                  ],
                }))['invoiceId']!
                as String,
          );
          await bill.payments.allocateCredit(recep, credit, {
            'allocations': [
              {'invoiceId': inv2['invoiceId'], 'amountMinor': 20000},
            ],
          }, idempotencyKey: 'emu-apply-$suffix');
          final credits = await bill.payments.credits(recep, patient);
          expect(credits['balance'], 10000);
          await expectLater(
            bill.payments.allocateCredit(recep, credit, {
              'allocations': [
                {'invoiceId': inv2['invoiceId'], 'amountMinor': 1},
              ],
            }, idempotencyKey: 'emu-apply2-$suffix'),
            throwsA(isA<ApiException>()),
            reason: 'the invoice is already paid',
          );

          // refund of part of the first payment
          final rf = await bill.refunds.request(recep, {
            'paymentId': p1['paymentId'],
            'invoiceId': id,
            'amountMinor': 10000,
            'reason': 'Overcharged by mistake',
          }, idempotencyKey: 'emu-rf-$suffix');
          await bill.refunds.approve(admin, rf['refundId']! as String, {});
          final done = await bill.refunds.complete(
            acct,
            rf['refundId']! as String,
            {'outcome': 'completed', 'method': 'cash'},
          );
          expect(done['status'], 'completed');
          inv = await bill.invoices.detail(recep, id);
          expect(inv['status'], 'partially_refunded');
          expect(inv['amountRefunded'], 10000);

          // expense lifecycle
          final cat = await bill.expenses.createCategory(owner, {
            'name': 'Rent',
          });
          final exp = await bill.expenses.create(acct, {
            'categoryId': cat['categoryId'],
            'description': 'Monthly rent',
            'amountMinor': 30000,
            'expenseDate':
                '${start.year}-${start.month.toString().padLeft(2, '0')}-${start.day.toString().padLeft(2, '0')}',
            'branchId': br,
          });
          final eid = exp['expenseId']! as String;
          await bill.expenses.submit(acct, eid);
          await bill.expenses.approve(admin, eid, {});
          await bill.expenses.pay(acct, eid, {'method': 'cash'});

          // reports aggregate the same numbers
          final dash = await bill.reports.dashboard(
            owner,
            Request(
              'GET',
              Uri.parse('http://localhost/api/v1/finance/dashboard'),
            ),
          );
          final today = dash['today']! as Map;
          expect(today['collected'], 40000 + 78000 + 30000);
          expect(today['refunded'], 10000);
          expect((dash['outstanding']! as Map)['total'], 0);
          expect((dash['monthToDate']! as Map)['expensesPaid'], 30000);

          // tenant isolation on the real store
          final theirs = await bill.invoices.list(
            ownerB,
            Request(
              'GET',
              Uri.parse('http://localhost/api/v1/billing/invoices'),
            ),
          );
          expect(theirs.docs, isEmpty);
          await expectLater(
            bill.invoices.detail(ownerB, id),
            throwsA(isA<ApiException>()),
          );
          await expectLater(
            bill.payments.receiptOfPayment(ownerB, p1['paymentId']! as String),
            throwsA(isA<ApiException>()),
          );
        },
      );
    },
    skip: host == null ? 'FIRESTORE_EMULATOR_HOST is not set' : false,
  );
}
