import 'dart:typed_data';

import 'package:api_contracts/api_contracts.dart';
import 'package:clinic_web/features/laboratory/lab_pages.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_shell_test.dart' show buildApp;
import 'control_plane_test.dart' show open;
import 'support/fake_auth.dart';
import 'support/fake_repo.dart';

const _perms = ['clinic.view', 'branches.view', 'billing.view', 'payment.view'];

FakeRepo _repo(Map<String, Map<String, Object?>> maps, List<String> asked) {
  final r = FakeRepo();
  r.on('getMap', (a, n) {
    final path = a[0]! as String;
    if (path.startsWith('/members/current/permissions')) {
      return {
        'tenantId': 'ten_1',
        'role': 'receptionist',
        'allBranches': true,
        'branches': [
          {'branchId': 'br_1', 'name': 'Main'},
        ],
        'accessLevel': 'full',
        'writesAllowed': true,
        'permissions': _perms,
      };
    }
    if (path == '/billing/gateway') {
      return {
        'configured': false,
        'methods': ['cash'],
      };
    }
    return maps[path] ?? ownerAccess(path);
  });
  r.on('getList', (a, n) => <Map<String, Object?>>[]);
  r.on('list', (a, n) => listOf([]));
  r.on('downloadBytes', (a, n) {
    asked.add(a[0]! as String);
    return Uint8List.fromList([37, 80, 68, 70]);
  });
  return r;
}

Map<String, Object?> _invoice(String status) => {
  'invoiceId': 'inv_1',
  'invoiceNumber': status == 'draft' ? null : 'INV-000001',
  'status': status,
  'displayStatus': status,
  'currency': 'INR',
  'patientId': 'pt_1',
  'patientName': 'Asha Patil',
  'patientMrn': 'MRN-000001',
  'branchName': 'Main',
  'invoiceDate': '2026-06-01',
  'rev': 1,
  'subtotal': 100000,
  'discountTotal': 0,
  'taxTotal': 0,
  'grandTotal': 100000,
  'amountPaid': 0,
  'amountRefunded': 0,
  'outstanding': 100000,
  'lines': <Object?>[],
  'allocations': <Object?>[],
  'adjustments': <Object?>[],
};

void main() {
  Future<List<String>> pump(
    WidgetTester t,
    Map<String, Map<String, Object?>> maps,
    String path,
    List<String> asked,
  ) async {
    final saved = <String>[];
    await open(
      t,
      buildApp(
        repo: _repo(maps, asked),
        overrides: [
          reportSaverProvider.overrideWithValue(
            (n, b) async => saved.add('$n:${b.length}'),
          ),
        ],
        session: sessionWith(
          memberships: [
            const MembershipSummaryDto(tenantId: 'ten_1', role: 'receptionist'),
          ],
        ),
      ),
      path,
    );
    return saved;
  }

  testWidgets('a finalized invoice downloads its PDF through the API', (
    t,
  ) async {
    final asked = <String>[];
    final saved = await pump(
      t,
      {'/billing/invoices/inv_1': _invoice('finalized')},
      '/clinic/billing/invoices/inv_1',
      asked,
    );
    await t.tap(find.byKey(const Key('invoice-pdf')));
    await t.pumpAndSettle();
    expect(asked, ['/billing/invoices/inv_1/pdf']);
    expect(saved, ['INV-000001.pdf:4']);
  });

  testWidgets('a draft invoice offers no PDF', (t) async {
    final asked = <String>[];
    await pump(
      t,
      {'/billing/invoices/inv_1': _invoice('draft')},
      '/clinic/billing/invoices/inv_1',
      asked,
    );
    expect(find.byKey(const Key('invoice-pdf')), findsNothing);
  });

  testWidgets('a receipt downloads its PDF', (t) async {
    final asked = <String>[];
    final saved = await pump(
      t,
      {
        '/billing/receipts/rct_1': {
          'receiptId': 'rct_1',
          'receiptNumber': 'RCT-000001',
          'paymentId': 'pay_1',
          'amount': 40000,
          'currency': 'INR',
          'method': 'cash',
          'receivedAt': '2026-06-01T10:00:00Z',
          'patientName': 'Asha Patil',
          'invoices': <Object?>[],
          'advanceAmount': 0,
          'clinic': {'name': 'Green Valley Clinic'},
        },
      },
      '/clinic/billing/receipts/rct_1',
      asked,
    );
    await t.tap(find.byKey(const Key('receipt-pdf')));
    await t.pumpAndSettle();
    expect(asked, ['/billing/receipts/rct_1/pdf']);
    expect(saved, ['RCT-000001.pdf:4']);
  });
}
