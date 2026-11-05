import 'package:test/test.dart';

import '../support/billing_fixtures.dart';
import '../support/lab_fixtures.dart';
import '../support/patient_fixtures.dart';
import '../support/platform_http_fixtures.dart';
import '../support/portal_fixtures.dart';
import '../support/scheduling_fixtures.dart';

/// Release gate: a second clinic's owner, holding every permission in their
/// own clinic, can read or change nothing of the first clinic by id.
void main() {
  test(
    'resources of clinic A are invisible and untouchable from clinic B',
    () async {
      final h = PlatformHarness();
      final p = PortalClinic(h);
      await p.init();
      final tid = p.tid;

      // --- build a rich clinic A
      final appt =
          (await h.bookOk('recep', p.k.c.body()))['appointmentId']! as String;
      final cid = await p.k.readyConsultation();
      final rx = (await p.k.newRx(cid))['prescriptionId']! as String;
      final bill = BillingClinic.on(h, p.k.c);
      final inv = await bill.finalized(amount: 50000);
      final invId = inv['invoiceId']! as String;
      final pay = await bill.pay(invId, 10000);
      final lab = LabClinic.on(h, p.k.c);
      final test = (await lab.test())['testId']! as String;
      final orderId = await lab.verified(test);
      final rep = await lab.post(
        'labtech2',
        '/laboratory/orders/$orderId/publish',
      );
      final export = await h.okData(
        h.call(
          'POST',
          '/reports/exports',
          uid: 'owner',
          body: {
            'report': 'appointments',
            'format': 'csv',
            'from': '2026-06-01',
            'to': '2026-06-30',
          },
        ),
        status: 201,
      );
      await h.clinic.portal.notifier.notifyDoctor(
        tid,
        p.doctor,
        category: 'report_available',
        title: 't',
        body: 'b',
        dedupeKey: 'x1',
      );
      final note = h.docsOf('notifications').first['notificationId']! as String;
      final tpl = await h.okData(
        h.call(
          'POST',
          '/admin/notification-templates',
          uid: 'admin',
          body: {
            'name': 'Template',
            'eventType': 'followup_reminder',
            'channel': 'in_app',
            'locale': 'en',
            'body': 'See you {{date}}',
          },
        ),
        status: 201,
      );
      final delivery = h.docsOf('notification_deliveries').isEmpty
          ? 'dl_none'
          : h.docsOf('notification_deliveries').first['deliveryId']! as String;
      final entry = h.docsOf('queue_entries').isEmpty
          ? 'qe_none'
          : h.docsOf('queue_entries').first['entryId']! as String;

      // --- clinic B with its own owner
      await h.createClinic(
        'ownerB',
        name: 'Other Clinic',
        city: 'Nagpur',
        pin: '440001',
      );

      final reads = <String>[
        '/patients/${p.patientId}',
        '/patients/${p.patientId}/appointments',
        '/appointments/$appt',
        '/consultations/$cid',
        '/prescriptions/$rx',
        '/billing/invoices/$invId',
        '/billing/payments/${pay['paymentId']}',
        '/billing/receipts/${pay['receiptId']}',
        '/laboratory/orders/$orderId',
        '/laboratory/orders/$orderId/results',
        '/laboratory/reports/${rep['reportId']}',
        '/laboratory/reports/${rep['reportId']}/download',
        '/laboratory/tests/$test',
        '/reports/exports/${export['exportId']}',
        '/reports/exports/${export['exportId']}/download',
        '/doctors/${p.doctor}',
        '/branches/${p.br}',
        '/clinical/patients/${p.patientId}/overview',
        '/clinical/patients/${p.patientId}/history',
        '/patients/${p.patientId}/allergies',
        '/patients/${p.patientId}/documents',
      ];
      final leaks = <String>[];
      for (final path in reads) {
        final r = await h.call('GET', path, uid: 'ownerB');
        if (r.statusCode >= 200 && r.statusCode < 300) {
          leaks.add('GET $path -> ${r.statusCode}');
        }
      }
      final writes = <(String, String, Map<String, Object?>)>[
        ('PATCH', '/patients/${p.patientId}', {'fullName': 'Hijacked Name'}),
        (
          'POST',
          '/appointments/$appt/cancel',
          {'reason': 'cross tenant attempt'},
        ),
        ('POST', '/appointments/$appt/confirm', {}),
        ('PATCH', '/consultations/$cid', {'expectedVersion': 1}),
        ('POST', '/consultations/$cid/finalize', {}),
        ('POST', '/prescriptions/$rx/finalize', {}),
        (
          'POST',
          '/billing/invoices/$invId/cancel',
          {'reason': 'cross tenant attempt'},
        ),
        (
          'POST',
          '/laboratory/orders/$orderId/cancel',
          {'reason': 'cross tenant attempt'},
        ),
        ('POST', '/laboratory/orders/$orderId/publish', {}),
        (
          'POST',
          '/laboratory/orders/$orderId/results/it1/amend',
          {'reason': 'cross tenant attempt', 'observations': []},
        ),
        ('POST', '/notifications/$note/read', {}),
        ('POST', '/notifications/$note/archive', {}),
        (
          'PATCH',
          '/admin/notification-templates/${tpl['templateId']}',
          {'body': 'owned'},
        ),
        (
          'POST',
          '/admin/notification-templates/${tpl['templateId']}/preview',
          {},
        ),
        ('POST', '/admin/notification-deliveries/$delivery/retry', {}),
        ('POST', '/queue-entries/$entry/call', {}),
        ('DELETE', '/notifications/devices/dev_${tid.hashCode}', {}),
      ];
      for (final (m, path, body) in writes) {
        final r = await h.call(
          m,
          path,
          uid: 'ownerB',
          body: m == 'DELETE' ? null : body,
        );
        if (r.statusCode >= 200 && r.statusCode < 300) {
          leaks.add('$m $path -> ${r.statusCode}');
        }
        if (r.statusCode >= 500) {
          leaks.add('$m $path -> ${r.statusCode} (server error)');
        }
      }
      expect(leaks, isEmpty, reason: leaks.join('\n'));

      // lists show nothing of clinic A
      for (final path in [
        '/patients',
        '/appointments',
        '/billing/invoices',
        '/billing/payments',
        '/laboratory/orders',
        '/laboratory/reports',
        '/notifications',
        '/admin/notification-deliveries',
      ]) {
        final r = await h.call('GET', path, uid: 'ownerB');
        final rows = r.statusCode == 200 ? await h.list(r) : <Object?>[];
        expect(rows, isEmpty, reason: path);
      }

      // clinic A is unchanged
      expect(
        h.store.docs['tenants/$tid/patients/${p.patientId}']!['fullName'],
        isNot('Hijacked Name'),
      );
      expect(
        h.store.docs['tenants/$tid/appointments/$appt']!['status'],
        isNot('cancelled'),
      );
      expect(
        h
            .store
            .docs['tenants/$tid/notification_templates/${tpl['templateId']}']!['body'],
        'See you {{date}}',
      );
    },
  );
}
