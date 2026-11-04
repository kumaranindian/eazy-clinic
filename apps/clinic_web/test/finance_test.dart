import 'package:api_contracts/api_contracts.dart';
import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_shell_test.dart' show buildApp;
import 'control_plane_test.dart' show open;
import 'support/fake_auth.dart';
import 'support/fake_repo.dart';

const _desk = [
  'clinic.view',
  'branches.view',
  'billing.view',
  'billing.create',
  'billing.edit_draft',
  'billing.finalize',
  'payment.view',
  'payment.collect',
  'payment.allocate',
  'payment.record_advance',
  'refund.request',
];
const _accountant = [
  ..._desk,
  'billing.cancel',
  'billing.apply_discount',
  'billing.adjust',
  'refund.process',
  'expense.view',
  'expense.create',
  'expense.edit',
  'expense.pay',
  'finance.reports.view',
  'finance.reports.export',
];
const _admin = [
  ..._accountant,
  'refund.approve',
  'expense.approve',
  'expense.reject',
  'service_catalogue.manage',
  'billing.settings.manage',
];

Map<String, Object?> _invoice({
  String status = 'finalized',
  int outstanding = 118000,
  int paid = 0,
  int rev = 2,
  List<Map<String, Object?>>? lines,
}) => {
  'invoiceId': 'inv_1',
  'invoiceNumber': status == 'draft' ? null : 'INV-000001',
  'status': status,
  'displayStatus': status,
  'overdue': false,
  'currency': 'INR',
  'patientId': 'pt_1',
  'patientName': 'Asha Patil',
  'patientMrn': 'MRN-000001',
  'branchId': 'br_1',
  'branchName': 'Main',
  'invoiceDate': '2026-06-01',
  'dueDate': '2026-06-08',
  'rev': rev,
  'subtotal': 100000,
  'lineDiscountTotal': 0,
  'invoiceDiscount': 0,
  'discountTotal': 0,
  'taxTotal': 18000,
  'grandTotal': 118000,
  'amountPaid': paid,
  'amountRefunded': 0,
  'adjustmentDebits': 0,
  'adjustmentCredits': 0,
  'outstanding': outstanding,
  'lines':
      lines ??
      [
        {
          'lineId': 'l1',
          'serviceId': 'svc_1',
          'description': 'General Consultation',
          'category': 'consultation',
          'quantity': 2,
          'unitMinor': 50000,
          'lineDiscount': 0,
          'tax': 18000,
          'taxRuleName': 'GST 18%',
          'total': 118000,
        },
      ],
  'allocations': <Object?>[],
  'adjustments': <Object?>[],
};

class Env {
  Env(this.perms);

  final List<String> perms;
  final List<(String, String, Object?, Map<String, String>?)> sent = [];
  final Map<String, Map<String, Object?>> maps = {};
  final Map<String, List<Map<String, Object?>>> rows = {};
  final Map<String, List<Map<String, Object?>>> lists = {};

  FakeRepo repo() {
    final r = FakeRepo();
    r.on('getMap', (a, n) {
      final path = a[0]! as String;
      if (path.startsWith('/members/current/permissions')) {
        return {
          'tenantId': 'ten_1',
          'role': 'accountant',
          'allBranches': true,
          'branches': [
            {'branchId': 'br_1', 'name': 'Main'},
          ],
          'accessLevel': 'full',
          'writesAllowed': true,
          'permissions': perms,
        };
      }
      if (path == '/billing/gateway') {
        return {
          'configured': false,
          'methods': ['cash', 'upi', 'card', 'bank_transfer', 'cheque'],
        };
      }
      final m = maps[path];
      if (m != null) return m;
      return ownerAccess(path);
    });
    r.on('getList', (a, n) {
      final path = a[0]! as String;
      if (lists.containsKey(path)) return lists[path]!;
      if (path == '/branches') {
        return [
          {'branchId': 'br_1', 'name': 'Main', 'status': 'active'},
        ];
      }
      return <Map<String, Object?>>[];
    });
    r.on('list', (a, n) => listOf(rows[a[0]! as String] ?? []));
    r.on('sendMap', (a, n) {
      sent.add((
        a[0]! as String,
        a[1]! as String,
        a[2],
        n['headers'] as Map<String, String>?,
      ));
      return <String, Object?>{'ok': true};
    });
    return r;
  }
}

Widget _app(Env e) => buildApp(
  repo: e.repo(),
  session: sessionWith(
    memberships: [
      const MembershipSummaryDto(tenantId: 'ten_1', role: 'accountant'),
    ],
  ),
);

Future<void> _type(WidgetTester t, String label, String text) async {
  final f = find.byWidgetPredicate(
    (w) =>
        w is TextField &&
        (w.decoration?.labelText == label ||
            (w.decoration?.labelText ?? '').startsWith(label)),
  );
  expect(f, findsOneWidget, reason: label);
  await t.ensureVisible(f);
  await t.enterText(f, text);
}

Future<void> _pick(WidgetTester t, String label, String item) async {
  final f = find.byWidgetPredicate(
    (w) => w is DropdownButtonFormField && w.decoration.labelText == label,
  );
  expect(f, findsOneWidget, reason: label);
  await t.ensureVisible(f);
  await t.tap(f);
  await t.pumpAndSettle();
  await t.tap(find.text(item).last);
  await t.pumpAndSettle();
}

void main() {
  group('navigation follows permissions', () {
    testWidgets('an accountant sees every finance entry', (t) async {
      await open(t, _app(Env(_accountant)), '/clinic');
      for (final l in [
        'Finance',
        'Invoices',
        'Payments',
        'Refunds',
        'Expenses',
        'Finance reports',
        'Services & charges',
      ]) {
        expect(find.text(l), findsWidgets, reason: l);
      }
    });

    testWidgets('the front desk sees billing but not finance or expenses', (
      t,
    ) async {
      await open(t, _app(Env(_desk)), '/clinic');
      for (final l in [
        'Invoices',
        'Payments',
        'Refunds',
        'Services & charges',
      ]) {
        expect(find.text(l), findsWidgets, reason: l);
      }
      for (final l in ['Finance', 'Expenses', 'Finance reports']) {
        expect(find.text(l), findsNothing, reason: l);
      }
    });
  });

  group('dashboard', () {
    testWidgets('shows the figures the server calculated', (t) async {
      final e = Env(_accountant)
        ..maps['/finance/dashboard'] = {
          'currency': 'INR',
          'asOf': '2026-06-01',
          'today': {
            'collected': 120000,
            'refunded': 20000,
            'netCollected': 100000,
          },
          'last7Days': {
            'collected': 120000,
            'refunded': 20000,
            'netCollected': 100000,
          },
          'monthToDate': {
            'invoiced': 160000,
            'collected': 120000,
            'refunded': 20000,
            'netCollected': 100000,
            'expensesApproved': 30000,
            'expensesPaid': 30000,
          },
          'outstanding': {
            'total': 40000,
            'invoices': 1,
            'overdueTotal': 40000,
            'overdueInvoices': 1,
          },
          'paymentMethods': {'cash': 100000, 'upi': 20000},
          'branchWise': [
            {
              'branchId': 'br_1',
              'branchName': 'Main',
              'invoiced': 160000,
              'collected': 120000,
              'refunded': 20000,
              'netCollected': 100000,
            },
          ],
          'doctorWise': [
            {'doctorId': 'dr_1', 'consultations': 1, 'revenue': 100000},
          ],
          'truncated': false,
        };
      await open(t, _app(e), '/clinic/finance');
      expect(
        t.widget<Text>(find.byKey(const Key('today-collected'))).data,
        '₹1200.00',
      );
      expect(
        t.widget<Text>(find.byKey(const Key('today-net'))).data,
        '₹1000.00',
      );
      expect(
        t.widget<Text>(find.byKey(const Key('month-invoiced'))).data,
        '₹1600.00',
      );
      expect(
        t.widget<Text>(find.byKey(const Key('outstanding-total'))).data,
        '₹400.00',
      );
      expect(find.textContaining('not profit'), findsOneWidget);
      expect(find.text('Upi'), findsOneWidget);
    });

    testWidgets('a role without finance access is refused politely', (t) async {
      final repo = Env(_desk).repo();
      final inner = repo.handlers['getMap']!;
      repo.on('getMap', (a, n) {
        if (a[0] == '/finance/dashboard') {
          throw const ApiFailure(code: ApiErrorCode.forbidden, message: 'no');
        }
        return inner(a, n);
      });
      await open(
        t,
        buildApp(
          repo: repo,
          session: sessionWith(
            memberships: [
              const MembershipSummaryDto(
                tenantId: 'ten_1',
                role: 'receptionist',
              ),
            ],
          ),
        ),
        '/clinic/finance',
      );
      expect(find.text('Not permitted'), findsOneWidget);
    });
  });

  group('invoices', () {
    testWidgets('the list shows numbers, balances and statuses', (t) async {
      final e = Env(_desk)
        ..rows['/billing/invoices'] = [
          {..._invoice(), 'displayStatus': 'overdue'},
        ];
      await open(t, _app(e), '/clinic/billing/invoices');
      expect(find.text('INV-000001 · Asha Patil'), findsOneWidget);
      expect(find.textContaining('Due ₹1180.00'), findsOneWidget);
      expect(find.text('Overdue'), findsWidgets);
    });

    testWidgets('a finalized invoice shows server totals and offers payment', (
      t,
    ) async {
      final e = Env(_desk)..maps['/billing/invoices/inv_1'] = _invoice();
      await open(t, _app(e), '/clinic/billing/invoices/inv_1');
      expect(find.text('Invoice INV-000001'), findsOneWidget);
      expect(find.text('₹1000.00'), findsWidgets);
      expect(find.text('₹180.00'), findsWidgets);
      expect(find.text('₹1180.00'), findsWidgets);
      expect(find.text('Collect payment'), findsOneWidget);
      expect(find.text('Finalize invoice'), findsNothing);
      expect(
        find.text('Add service'),
        findsNothing,
        reason: 'finalized invoices are not editable',
      );
      expect(
        find.text('Cancel invoice'),
        findsNothing,
        reason: 'needs billing.cancel',
      );
      expect(
        find.text('Credit / debit note'),
        findsNothing,
        reason: 'needs billing.adjust',
      );
    });

    testWidgets(
      'collecting a payment sends paise, the allocation and an idempotency key',
      (t) async {
        final e = Env(_desk)..maps['/billing/invoices/inv_1'] = _invoice();
        await open(t, _app(e), '/clinic/billing/invoices/inv_1');
        await t.tap(find.text('Collect payment'));
        await t.pumpAndSettle();
        await _type(t, 'Amount received', '500.50');
        await _pick(t, 'Method', 'Upi');
        await _type(t, 'Transaction reference', 'UTR9988');
        await t.tap(find.text('Record payment').last);
        await t.pumpAndSettle();
        final call = e.sent.singleWhere((s) => s.$2 == '/billing/payments');
        final body = call.$3! as Map<String, Object?>;
        expect(body['amountMinor'], 50050);
        expect(body['method'], 'upi');
        expect(body['reference'], 'UTR9988');
        expect(body['patientId'], 'pt_1');
        expect(body['branchId'], 'br_1');
        expect(body.containsKey('status'), isFalse);
        expect(body.containsKey('tenantId'), isFalse);
        expect((body['allocations']! as List).single, {
          'invoiceId': 'inv_1',
          'amountMinor': 50050,
        });
        expect(call.$4!['Idempotency-Key'], isNotEmpty);
      },
    );

    testWidgets('an invalid amount is not sent', (t) async {
      final e = Env(_desk)..maps['/billing/invoices/inv_1'] = _invoice();
      await open(t, _app(e), '/clinic/billing/invoices/inv_1');
      await t.tap(find.text('Collect payment'));
      await t.pumpAndSettle();
      await _type(t, 'Amount received', '12.345');
      await t.tap(find.text('Record payment').last);
      await t.pumpAndSettle();
      expect(find.text('Enter an amount like 1250.50.'), findsOneWidget);
      expect(e.sent, isEmpty);
    });

    testWidgets('a paid invoice offers no payment button', (t) async {
      final e = Env(_desk)
        ..maps['/billing/invoices/inv_1'] = _invoice(
          status: 'paid',
          outstanding: 0,
          paid: 118000,
        );
      await open(t, _app(e), '/clinic/billing/invoices/inv_1');
      expect(find.text('Collect payment'), findsNothing);
    });

    testWidgets('a draft can be edited and finalizing asks first', (t) async {
      final e = Env(_desk)
        ..maps['/billing/invoices/inv_1'] = _invoice(
          status: 'draft',
          outstanding: 0,
          rev: 3,
        );
      await open(t, _app(e), '/clinic/billing/invoices/inv_1');
      expect(find.text('Draft invoice'), findsOneWidget);
      await t.tap(find.text('Custom item'));
      await t.pumpAndSettle();
      await _type(t, 'Description', 'Dressing');
      await _type(t, 'Unit price', '250');
      await t.tap(find.text('Save').last);
      await t.pumpAndSettle();
      final patch = e.sent.singleWhere((s) => s.$1 == 'PATCH');
      final body = patch.$3! as Map<String, Object?>;
      expect(body['expectedRev'], 3);
      final lines = body['lines']! as List;
      expect(lines, hasLength(2));
      expect(
        (lines.first as Map)['serviceId'],
        'svc_1',
        reason: 'existing catalogue lines are re-sent as ids only',
      );
      expect((lines.first as Map).containsKey('unitMinor'), isFalse);
      expect(lines.last, {
        'description': 'Dressing',
        'unitMinor': 25000,
        'quantity': 1,
        'category': 'custom',
      });

      await t.tap(find.text('Finalize invoice'));
      await t.pumpAndSettle();
      expect(find.text('Finalize invoice?'), findsOneWidget);
      expect(e.sent.where((s) => s.$2.endsWith('/finalize')), isEmpty);
      await t.tap(find.widgetWithText(TextButton, 'Finalize'));
      await t.pumpAndSettle();
      expect(
        e.sent.where(
          (s) => s.$1 == 'POST' && s.$2 == '/billing/invoices/inv_1/finalize',
        ),
        hasLength(1),
      );
    });

    testWidgets('a draft with no lines cannot be finalized', (t) async {
      final e = Env(_desk)
        ..maps['/billing/invoices/inv_1'] = _invoice(
          status: 'draft',
          outstanding: 0,
          lines: [],
        );
      await open(t, _app(e), '/clinic/billing/invoices/inv_1');
      final btn = t.widget<EcPrimaryButton>(
        find.widgetWithText(EcPrimaryButton, 'Finalize invoice'),
      );
      expect(btn.onPressed, isNull);
    });

    testWidgets('accountants can cancel and adjust; the reason is required', (
      t,
    ) async {
      final e = Env(_accountant)..maps['/billing/invoices/inv_1'] = _invoice();
      await open(t, _app(e), '/clinic/billing/invoices/inv_1');
      expect(find.text('Credit / debit note'), findsOneWidget);
      await t.tap(find.text('Cancel invoice'));
      await t.pumpAndSettle();
      await t.tap(find.text('Cancel invoice').last);
      await t.pumpAndSettle();
      expect(find.text('Reason is required.'), findsOneWidget);
      expect(e.sent, isEmpty);
    });
  });

  group('receipts and patient account', () {
    testWidgets('a receipt shows the printed details and creates nothing', (
      t,
    ) async {
      final e = Env(_desk)
        ..maps['/billing/receipts/rct_1'] = {
          'receiptId': 'rct_1',
          'receiptNumber': 'RCT-000007',
          'paymentId': 'pay_1',
          'currency': 'INR',
          'amount': 50050,
          'method': 'upi',
          'reference': 'UTR9988',
          'receivedAt': '2026-06-01T10:00:00Z',
          'receivedByRole': 'receptionist',
          'patientName': 'Asha Patil',
          'patientMrn': 'MRN-000001',
          'clinic': {
            'name': 'Green Valley Clinic',
            'branchName': 'Main',
            'phone': '9876543210',
          },
          'invoices': [
            {
              'invoiceNumber': 'INV-000001',
              'amount': 50050,
              'outstandingAfter': 67950,
            },
          ],
          'advanceAmount': 0,
          'patientOutstandingNow': 67950,
        };
      await open(t, _app(e), '/clinic/billing/receipts/rct_1');
      expect(find.text('Receipt RCT-000007'), findsOneWidget);
      expect(find.text('Green Valley Clinic'), findsOneWidget);
      expect(
        t.widget<Text>(find.byKey(const Key('receipt-amount'))).data,
        '₹500.50',
      );
      expect(find.textContaining('₹679.50'), findsWidgets);
      expect(e.sent, isEmpty);
    });

    testWidgets(
      'the patient account shows what is owed and the credit balance',
      (t) async {
        final e = Env(_desk)
          ..rows['/billing/invoices'] = [_invoice()]
          ..maps['/billing/patients/pt_1/credits'] = {
            'patientId': 'pt_1',
            'currency': 'INR',
            'balance': 30000,
            'sources': [
              {'entryId': 'cr_1', 'amount': 30000, 'remaining': 30000},
            ],
            'ledger': [
              {
                'type': 'advance_in',
                'amount': 30000,
                'balanceAfter': 30000,
                'createdAt': '2026-06-01T10:00:00Z',
              },
            ],
          };
        e.lists['/billing/invoices'] = [_invoice()];
        await open(t, _app(e), '/clinic/billing/patients/pt_1');
        expect(
          t.widget<Text>(find.byKey(const Key('patient-outstanding'))).data,
          '₹1180.00',
        );
        expect(
          t.widget<Text>(find.byKey(const Key('credit-balance'))).data,
          '₹300.00',
        );
        expect(find.text('Apply credit to an invoice'), findsOneWidget);
      },
    );
  });

  group('refunds', () {
    Map<String, Object?> refund(String status) => {
      'refundId': 'rf_1',
      'paymentId': 'pay_1',
      'invoiceNumber': 'INV-000001',
      'patientName': 'Asha Patil',
      'amount': 30000,
      'currency': 'INR',
      'reason': 'Service not rendered',
      'status': status,
      'requestedAt': '2026-06-01T10:00:00Z',
      'attempts': 0,
      'history': [
        {
          'status': 'requested',
          'at': '2026-06-01T10:00:00Z',
          'role': 'receptionist',
        },
      ],
    };

    testWidgets('only approvers see approve and reject', (t) async {
      final desk = Env(_desk)
        ..maps['/billing/refunds/rf_1'] = refund('requested');
      await open(t, _app(desk), '/clinic/billing/refunds/rf_1');
      expect(find.text('Approve'), findsNothing);
      expect(find.text('Reject'), findsNothing);
      expect(find.text('Record payout'), findsNothing);
    });

    testWidgets('an approver approves; processors record the payout', (
      t,
    ) async {
      final e = Env(_admin)
        ..maps['/billing/refunds/rf_1'] = refund('requested');
      await open(t, _app(e), '/clinic/billing/refunds/rf_1');
      expect(
        find.text('Record payout'),
        findsNothing,
        reason: 'not before approval',
      );
      await t.tap(find.text('Approve'));
      await t.pumpAndSettle();
      expect(e.sent.single.$2, '/billing/refunds/rf_1/approve');
    });

    testWidgets('a failed refund can be retried or abandoned', (t) async {
      final e = Env(_admin)..maps['/billing/refunds/rf_1'] = refund('failed');
      await open(t, _app(e), '/clinic/billing/refunds/rf_1');
      expect(find.text('Retry payout'), findsOneWidget);
      expect(find.text('Abandon refund'), findsOneWidget);
    });

    testWidgets('requesting a refund sends the payment, invoice and paise', (
      t,
    ) async {
      final e = Env(_desk)
        ..maps['/billing/payments/pay_1'] = {
          'paymentId': 'pay_1',
          'receiptId': 'rct_1',
          'receiptNumber': 'RCT-000001',
          'patientName': 'Asha Patil',
          'amount': 118000,
          'currency': 'INR',
          'method': 'cash',
          'status': 'completed',
          'receivedAt': '2026-06-01T10:00:00Z',
          'allocatedTotal': 118000,
          'refundedTotal': 0,
          'allocations': [
            {
              'invoiceId': 'inv_1',
              'invoiceNumber': 'INV-000001',
              'amount': 118000,
            },
          ],
          'refunds': <Object?>[],
        };
      await open(t, _app(e), '/clinic/billing/payments/pay_1');
      await t.tap(find.text('Request refund'));
      await t.pumpAndSettle();
      await _pick(t, 'Invoice to refund against', 'INV-000001 — ₹1180.00');
      await _type(t, 'Amount to refund', '300');
      await _type(t, 'Reason', 'Overcharged at billing');
      await t.tap(find.text('Request refund').last);
      await t.pumpAndSettle();
      final call = e.sent.single;
      expect(call.$2, '/billing/refunds');
      final body = call.$3! as Map<String, Object?>;
      expect(body['amountMinor'], 30000);
      expect(body['paymentId'], 'pay_1');
      expect(body['invoiceId'], 'inv_1');
      expect(call.$4!['Idempotency-Key'], isNotEmpty);
    });
  });

  group('expenses', () {
    Map<String, Object?> expense(String status) => {
      'expenseId': 'exp_1',
      'description': 'Monthly rent',
      'categoryName': 'Rent',
      'amount': 500000,
      'currency': 'INR',
      'expenseDate': '2026-06-01',
      'status': status,
      'rev': 1,
      'history': [
        {'status': 'draft', 'at': '2026-06-01T10:00:00Z', 'role': 'accountant'},
      ],
    };

    testWidgets('a submitter submits; approval is not offered to them', (
      t,
    ) async {
      final e = Env(_accountant)..maps['/expenses/exp_1'] = expense('draft');
      await open(t, _app(e), '/clinic/expenses/exp_1');
      expect(find.text('Submit for approval'), findsOneWidget);
      expect(find.text('Approve'), findsNothing);
      await t.tap(find.text('Submit for approval'));
      await t.pumpAndSettle();
      expect(e.sent.single.$2, '/expenses/exp_1/submit');
    });

    testWidgets('approvers see approve and reject on a submitted expense', (
      t,
    ) async {
      final e = Env(_admin)..maps['/expenses/exp_1'] = expense('submitted');
      await open(t, _app(e), '/clinic/expenses/exp_1');
      expect(find.text('Approve'), findsOneWidget);
      expect(find.text('Reject'), findsOneWidget);
      expect(
        find.text('Record payment'),
        findsNothing,
        reason: 'not yet approved',
      );
    });

    testWidgets('an approved expense is read-only and can be paid', (t) async {
      final e = Env(_admin)..maps['/expenses/exp_1'] = expense('approved');
      await open(t, _app(e), '/clinic/expenses/exp_1');
      expect(find.text('Edit'), findsNothing);
      expect(find.text('Record payment'), findsOneWidget);
    });

    testWidgets('creating an expense needs a category and sends paise', (
      t,
    ) async {
      final e = Env(_accountant)
        ..lists['/expenses/categories'] = [
          {'categoryId': 'ecat_1', 'name': 'Rent', 'status': 'active'},
        ];
      await open(t, _app(e), '/clinic/expenses');
      await t.tap(find.text('New expense'));
      await t.pumpAndSettle();
      await _pick(t, 'Category', 'Rent');
      await _type(t, 'Description', 'June rent');
      await _type(t, 'Amount', '5000');
      await _type(t, 'Date', '2026-06-01');
      await t.tap(find.text('Save').last);
      await t.pumpAndSettle();
      final body = e.sent.single.$3! as Map<String, Object?>;
      expect(e.sent.single.$2, '/expenses');
      expect(body['amountMinor'], 500000);
      expect(body['categoryId'], 'ecat_1');
      expect(body.containsKey('status'), isFalse);
    });
  });

  group('services and reports', () {
    testWidgets('a new service is created with paise and its tax rule', (
      t,
    ) async {
      final e = Env(_admin)
        ..lists['/billing/tax-rules'] = [
          {'taxRuleId': 'tx_1', 'name': 'GST 18%', 'status': 'active'},
        ];
      await open(t, _app(e), '/clinic/billing/services');
      await t.tap(find.text('New service'));
      await t.pumpAndSettle();
      await _type(t, 'Name', 'Dental scaling');
      await _pick(t, 'Category', 'Procedure');
      await _type(t, 'Default price', '1250.5');
      await _pick(t, 'Tax rule', 'GST 18%');
      await t.tap(find.text('Save').last);
      await t.pumpAndSettle();
      final body = e.sent.single.$3! as Map<String, Object?>;
      expect(body['amountMinor'], 125050);
      expect(body['taxRuleId'], 'tx_1');
      expect(body['category'], 'procedure');
    });

    testWidgets('services cannot be added without the catalogue permission', (
      t,
    ) async {
      await open(t, _app(Env(_desk)), '/clinic/billing/services');
      expect(find.text('New service'), findsNothing);
    });

    testWidgets('reports load per tab and validate the dates', (t) async {
      final e = Env(_accountant)
        ..maps['/finance/reports/collections'] = {
          'currency': 'INR',
          'rows': [
            {
              'period': '2026-06-01',
              'payments': 2,
              'collected': 120000,
              'refunded': 20000,
              'netCollected': 100000,
            },
          ],
          'totals': {
            'payments': 2,
            'collected': 120000,
            'refunded': 20000,
            'netCollected': 100000,
          },
          'byMethod': {'cash': 100000, 'upi': 20000},
          'truncated': false,
        }
        ..maps['/finance/reports/outstanding'] = {
          'currency': 'INR',
          'rows': [
            {
              'invoiceNumber': 'INV-000002',
              'patientName': 'Ravi',
              'dueDate': '2026-05-25',
              'daysOverdue': 7,
              'outstanding': 40000,
            },
          ],
          'totals': {'invoices': 1, 'outstanding': 40000, 'overdue': 40000},
          'ageing': {
            'current': 0,
            'days1to30': 40000,
            'days31to60': 0,
            'days61to90': 0,
            'over90': 0,
          },
          'truncated': false,
        };
      await open(t, _app(e), '/clinic/finance/reports');
      expect(find.text('₹1200.00'), findsWidgets);
      expect(find.text('2026-06-01'), findsWidgets);
      await t.tap(find.byKey(const Key('report-outstanding')));
      await t.pumpAndSettle();
      expect(find.text('INV-000002'), findsOneWidget);
      expect(find.text('₹400.00'), findsWidgets);
      await _type(t, 'From', 'yesterday');
      await t.tap(find.text('Apply'));
      await t.pumpAndSettle();
      expect(find.text('Use dates like 2026-06-01.'), findsOneWidget);
    });
  });
}
