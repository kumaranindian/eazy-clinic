import 'dart:convert';

import 'package:backend/features/documents/document_pdf.dart';
import 'package:test/test.dart';

import '../../support/billing_fixtures.dart';
import '../../support/clinical_fixtures.dart';
import '../../support/patient_fixtures.dart';
import '../../support/platform_http_fixtures.dart';
import '../../support/portal_fixtures.dart';
import '../../support/scheduling_fixtures.dart';

void main() {
  late PlatformHarness h;
  late PortalClinic p;
  late BillingClinic b;
  late String invId;
  late String rctId;

  setUp(() async {
    h = PlatformHarness();
    p = PortalClinic(h);
    await p.init();
    b = BillingClinic.on(h, p.k.c);
    final inv = await b.finalized(amount: 100000);
    invId = inv['invoiceId']! as String;
    rctId = (await b.pay(invId, 40000))['receiptId']! as String;
  });

  Future<String> pdfText(String path, String uid, {int status = 200}) async {
    final r = await h.call('GET', path, uid: uid);
    expect(r.statusCode, status, reason: path);
    if (status != 200) return '';
    expect(r.headers['content-type'], 'application/pdf');
    expect(r.headers['cache-control'], contains('no-store'));
    expect(r.headers['content-disposition'], contains('attachment'));
    final bytes = await r.read().expand((e) => e).toList();
    expect(ascii.decode(bytes.sublist(0, 5)), '%PDF-');
    return latin1.decode(bytes);
  }

  Future<String> issuedRx() async {
    final cid = await p.k.readyConsultation();
    final rx = (await p.k.newRx(cid))['prescriptionId']! as String;
    await h.actOk('docuser', '/prescriptions/$rx/finalize');
    return rx;
  }

  group('money formatting', () {
    test('paise are printed exactly, with grouping', () {
      expect(money(0), 'Rs 0.00');
      expect(money(5), 'Rs 0.05');
      expect(money(100000), 'Rs 1,000.00');
      expect(money(123456789), 'Rs 1,234,567.89');
      expect(money(-2550), '-Rs 25.50');
      expect(money(null), '-');
      expect(money(100, 'USD'), 'USD 1.00');
    });
  });

  group('invoice and receipt', () {
    test('a finalized invoice prints its stored totals', () async {
      final t = await pdfText('/billing/invoices/$invId/pdf', 'recep');
      expect(t, contains('INVOICE INV-000001'));
      expect(t, contains('Rs 1,000.00'));
      expect(t, contains('Balance due: Rs 600.00'));
      expect(t, contains('Asha Patil'));
    });

    test('a draft invoice is not printable', () async {
      final d = await b.draft(
        lines: [
          {'description': 'Draft', 'unitMinor': 5000, 'quantity': 1},
        ],
      );
      await pdfText(
        '/billing/invoices/${d['invoiceId']}/pdf',
        'recep',
        status: 409,
      );
    });

    test('a receipt prints amount, method and the invoice it paid', () async {
      final t = await pdfText('/billing/receipts/$rctId/pdf', 'recep');
      expect(t, contains('RECEIPT RCT-000001'));
      expect(t, contains('Amount: Rs 400.00'));
      expect(t, contains('INV-000001'));
    });

    test('permissions and tenant isolation are those of the screens', () async {
      await pdfText('/billing/invoices/$invId/pdf', 'nurse', status: 403);
      await pdfText('/billing/receipts/$rctId/pdf', 'docuser', status: 403);
      expect(await h.status('GET', '/billing/invoices/$invId/pdf'), 401);
      await h.createClinic(
        'rival',
        name: 'Rival Clinic',
        city: 'Nagpur',
        pin: '440001',
      );
      await pdfText('/billing/invoices/$invId/pdf', 'rival', status: 404);
      await pdfText('/billing/receipts/$rctId/pdf', 'rival', status: 404);
    });
  });

  group('prescription', () {
    test('an issued prescription prints what the doctor authorized', () async {
      final rx = await issuedRx();
      final t = await pdfText('/prescriptions/$rx/pdf', 'docuser');
      expect(t, contains('PRESCRIPTION RX-000001'));
      expect(t, contains('Paracetamol 500 mg'));
      expect(t, contains('three times a day'));
      expect(t, contains('Issued by the treating doctor'));
      // printing is audited like viewing
      expect(
        h.clinicalActions().where((a) => a == 'prescription.viewed'),
        isNotEmpty,
      );
    });

    test('a draft prescription cannot be printed', () async {
      final cid = await p.k.readyConsultation();
      final rx = (await p.k.newRx(cid))['prescriptionId']! as String;
      await pdfText('/prescriptions/$rx/pdf', 'docuser', status: 409);
    });

    test('roles without prescription access are refused', () async {
      final rx = await issuedRx();
      await pdfText('/prescriptions/$rx/pdf', 'acct', status: 403);
      await h.createClinic(
        'rival',
        name: 'Rival Clinic',
        city: 'Nagpur',
        pin: '440001',
      );
      await pdfText('/prescriptions/$rx/pdf', 'rival', status: anyOfStatus);
    });
  });

  group('patient app', () {
    test(
      'the patient downloads their own invoice, receipt and prescription',
      () async {
        final rx = await issuedRx();
        final base = '/patient/clinics/${p.tid}';
        expect(
          await pdfText('$base/invoices/$invId/pdf', 'asha'),
          contains('INVOICE INV-000001'),
        );
        expect(
          await pdfText('$base/receipts/$rctId/pdf', 'asha'),
          contains('RECEIPT RCT-000001'),
        );
        final t = await pdfText('$base/prescriptions/$rx/pdf', 'asha');
        expect(t, contains('Paracetamol'));
        // staff-only data does not reach the patient's copy
        expect(t.contains('docuser'), isFalse);
      },
    );

    test('another patient gets nothing', () async {
      final rx = await issuedRx();
      await p.createAccount('ravi');
      final base = '/patient/clinics/${p.tid}';
      for (final path in [
        '$base/invoices/$invId/pdf',
        '$base/receipts/$rctId/pdf',
        '$base/prescriptions/$rx/pdf',
      ]) {
        await pdfText(path, 'ravi', status: 404);
      }
    });

    test('a draft prescription does not exist for the patient', () async {
      final cid = await p.k.readyConsultation();
      final rx = (await p.k.newRx(cid))['prescriptionId']! as String;
      await pdfText(
        '/patient/clinics/${p.tid}/prescriptions/$rx/pdf',
        'asha',
        status: 404,
      );
    });
  });
}

const anyOfStatus = 404;
