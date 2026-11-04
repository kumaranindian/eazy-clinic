import 'dart:convert';

import 'package:backend/features/notifications/notification_core.dart';
import 'package:test/test.dart';

import '../../support/clinical_fixtures.dart';
import '../../support/notification_fixtures.dart';
import '../../support/patient_fixtures.dart';
import '../../support/platform_http_fixtures.dart';
import '../../support/portal_fixtures.dart';
import '../../support/scheduling_fixtures.dart';

void main() {
  late PlatformHarness h;
  late PortalClinic p;
  late MockFcm fcm;
  late String apptId;

  setUp(() async {
    fcm = MockFcm();
    h = PlatformHarness(fcm: fcm);
    p = PortalClinic(h);
    await p.init();
    // a confirmed visit on Tuesday 2 June 09:00 IST (03:30 UTC)
    final a = await h.bookOk('recep', p.k.c.body());
    apptId = a['appointmentId']! as String;
    expect(a['status'], 'confirmed');
    await h.okData(
      h.call(
        'POST',
        '/patient/devices',
        uid: 'asha',
        body: {
          'deviceId': 'device-asha-01',
          'token': 'tok-aaaaaaaaaaaaaaaaaaaaaaaa',
          'platform': 'android',
        },
      ),
      status: 201,
    );
  });

  void at(String iso) => h.clock.now = DateTime.parse(iso);
  Iterable<Map<String, Object?>> events([
    String type = 'appointment_reminder',
  ]) => h.docsOf('notification_events').where((e) => e['type'] == type);
  Iterable<Map<String, Object?>> reminderPushes() => h
      .docsOf('notification_deliveries')
      .where(
        (d) => d['channel'] == 'push' && d['type'] == 'appointment_reminder',
      );
  Iterable<Map<String, Object?>> deliveries([String? channel]) => h
      .docsOf('notification_deliveries')
      .where((d) => channel == null || d['channel'] == channel);
  Future<void> work() async {
    await h.clinic.hub.scanReminders(p.tid);
    await h.clinic.hub.processPending(p.tid);
    await h.clinic.hub.dispatchDue(p.tid);
  }

  group('appointment reminders', () {
    test('nothing is created before a reminder window opens', () async {
      at('2026-05-30T10:00:00Z');
      await work();
      expect(events(), isEmpty);
    });

    test('a reminder is created once per window and delivered', () async {
      at('2026-06-01T10:00:00Z'); // inside the 24 h window
      await work();
      await work();
      expect(events(), hasLength(1));
      final n = h.docsOf('patient_notifications').single;
      expect(n['category'], 'appointment_reminder');
      expect(n['body'], contains('2026-06-02'));
      expect(n['body'], contains('09:00'));
      // push is generic
      final push = fcm.sent.single;
      expect(push.body.contains('09:00'), isFalse);
      expect(deliveries('push').single['status'], 'sent');
    });

    test('the second lead time gives a second, separate reminder', () async {
      at('2026-06-01T10:00:00Z');
      await work();
      at('2026-06-02T02:00:00Z'); // 90 minutes before: inside the 2 h window
      await work();
      expect(events(), hasLength(2));
      expect(h.docsOf('patient_notifications'), hasLength(2));
    });

    test(
      'a visit booked inside the nearest window gets one reminder, not two',
      () async {
        at('2026-06-02T02:30:00Z'); // one hour before
        await work();
        expect(events(), hasLength(1));
      },
    );

    test('unconfirmed or cancelled visits get none', () async {
      at('2026-06-01T10:00:00Z');
      h.store.docs['tenants/${p.tid}/appointments/$apptId']!['status'] =
          'pending';
      await work();
      expect(events(), isEmpty);
    });

    test('cancelling before processing suppresses the reminder', () async {
      at('2026-06-01T10:00:00Z');
      await h.clinic.hub.scanReminders(p.tid);
      await h.actOk(
        'recep',
        '/appointments/$apptId/cancel',
        body: {'reason': 'Patient request'},
      );
      await h.clinic.hub.processPending(p.tid);
      await h.clinic.hub.dispatchDue(p.tid);
      final e = events().single;
      expect(e['status'], 'suppressed');
      expect(e['suppressedReason'], 'appointment_no_longer_confirmed');
      expect(
        h
            .docsOf('patient_notifications')
            .where((n) => n['category'] == 'appointment_reminder'),
        isEmpty,
      );
      expect(reminderPushes(), isEmpty);
    });

    test('cancelling after the push was queued cancels the push', () async {
      at('2026-06-01T10:00:00Z');
      await h.clinic.hub.scanReminders(p.tid);
      await h.clinic.hub.processPending(p.tid);
      await h.actOk(
        'recep',
        '/appointments/$apptId/cancel',
        body: {'reason': 'Patient request'},
      );
      await h.clinic.hub.dispatchDue(p.tid);
      expect(reminderPushes().single['status'], 'cancelled');
      expect(
        reminderPushes().single['error'],
        'appointment_no_longer_confirmed',
      );
      expect(fcm.sent.where((m) => m.title.contains('reminder')), isEmpty);
    });

    test(
      'moving the visit suppresses the old reminder and the new time gets its own',
      () async {
        at('2026-06-01T10:00:00Z');
        await h.clinic.hub.scanReminders(p.tid);
        final a = h.store.docs['tenants/${p.tid}/appointments/$apptId']!;
        a['startUtc'] = (a['startUtc'] as DateTime).add(
          const Duration(hours: 1),
        );
        await h.clinic.hub.processPending(p.tid);
        expect(events().single['status'], 'suppressed');
        expect(events().single['suppressedReason'], 'appointment_rescheduled');
        await work();
        expect(events(), hasLength(2));
        expect(events().where((e) => e['status'] == 'processed'), hasLength(1));
      },
    );

    test('a visit that already passed is never reminded', () async {
      at('2026-06-02T05:00:00Z');
      await work();
      expect(events(), isEmpty);
    });

    test('clinic lead times are configurable and validated', () async {
      expect(
        await h.status(
          'PUT',
          '/admin/notification-settings',
          uid: 'admin',
          body: {
            'reminderLeadMinutes': [5],
          },
        ),
        422,
      );
      await h.okData(
        h.call(
          'PUT',
          '/admin/notification-settings',
          uid: 'admin',
          body: {
            'reminderLeadMinutes': [60],
          },
        ),
      );
      at('2026-06-01T10:00:00Z'); // 24 h window no longer exists
      await work();
      expect(events(), isEmpty);
      at('2026-06-02T02:45:00Z');
      await work();
      expect(events(), hasLength(1));
    });

    test('a follow-up reminder is created the day before', () async {
      at('2026-06-01T04:00:00Z');
      final cid = await p.k.readyConsultation();
      await h.actOk('docuser', '/consultations/$cid/finalize');
      await h.actOk(
        'docuser',
        '/consultations/$cid/followups',
        status: 201,
        body: {'recommendedDate': '2026-06-02', 'reason': 'Review'},
      );
      await work();
      expect(
        events(
          'followup_reminder',
        ).where((e) => '${e['dedupeKey']}'.startsWith('followup:')),
        hasLength(1),
      );
      expect(
        h
            .docsOf('patient_notifications')
            .where((n) => n['category'] == 'followup_reminder'),
        hasLength(2),
        reason: 'one when recommended, one the day before',
      );
      await work();
      expect(
        events(
          'followup_reminder',
        ).where((e) => '${e['dedupeKey']}'.startsWith('followup:')),
        hasLength(1),
      );
    });

    test(
      'the worker tick does the whole job for every active clinic',
      () async {
        at('2026-06-01T10:00:00Z');
        await h.clinic.hub.tick();
        expect(deliveries('push').single['status'], 'sent');
        expect(h.docsOf('patient_notifications'), hasLength(1));
      },
    );
  });

  group('delivery administration', () {
    Future<void> failOne() async {
      fcm.script = [const ProviderResult('permanent', error: 'http_403')];
      at('2026-06-01T10:00:00Z');
      await work();
    }

    test('failures are listed without message content or recipient', () async {
      await failOne();
      final list = await h.list(
        await h.call(
          'GET',
          '/admin/notification-deliveries?status=permanently_failed',
          uid: 'admin',
        ),
      );
      expect(list, hasLength(1));
      final row = list.single! as Map;
      expect(row['error'], 'http_403');
      for (final k in ['title', 'body', 'recipientRef', 'token']) {
        expect(row.containsKey(k), isFalse, reason: k);
      }
      expect(
        await h.status(
          'GET',
          '/admin/notification-deliveries?status=bogus',
          uid: 'admin',
        ),
        400,
      );
    });

    test('only managers see or change delivery administration', () async {
      await failOne();
      final id =
          h
                  .docsOf('notification_deliveries')
                  .firstWhere((d) => d['channel'] == 'push')['deliveryId']!
              as String;
      for (final uid in ['docuser', 'recep', 'nurse', 'acct', 'labtech']) {
        h.member(uid, p.tid, uid == 'docuser' ? 'doctor' : 'receptionist');
        expect(
          await h.status('GET', '/admin/notification-deliveries', uid: uid),
          403,
          reason: uid,
        );
        expect(
          await h.status(
            'POST',
            '/admin/notification-deliveries/$id/retry',
            uid: uid,
          ),
          403,
          reason: uid,
        );
        expect(
          await h.status(
            'POST',
            '/admin/notification-channels/push/pause',
            uid: uid,
          ),
          403,
          reason: uid,
        );
        expect(
          await h.status('GET', '/admin/notification-health', uid: uid),
          403,
          reason: uid,
        );
        expect(
          await h.status(
            'PUT',
            '/admin/notification-settings',
            uid: uid,
            body: {},
          ),
          403,
          reason: uid,
        );
      }
    });

    test('manual retry sends again, is audited and idempotent', () async {
      await failOne();
      final id =
          h
                  .docsOf('notification_deliveries')
                  .firstWhere((d) => d['channel'] == 'push')['deliveryId']!
              as String;
      fcm.script = [];
      final r = await h.okData(
        h.call(
          'POST',
          '/admin/notification-deliveries/$id/retry',
          uid: 'admin',
        ),
      );
      expect(r['status'], 'sent');
      expect(r['manualRetries'], 1);
      expect(fcm.sent, hasLength(2));
      // retrying a delivery that is no longer failed is refused, not repeated
      expect(
        await h.status(
          'POST',
          '/admin/notification-deliveries/$id/retry',
          uid: 'admin',
        ),
        409,
      );
      expect(fcm.sent, hasLength(2));
      expect(
        h.docsOf('notification_audit_logs').map((d) => d['action']),
        contains('notification_delivery.retried'),
      );
    });

    test('a queued delivery retried twice is not duplicated', () async {
      await failOne();
      final id =
          h
                  .docsOf('notification_deliveries')
                  .firstWhere((d) => d['channel'] == 'push')['deliveryId']!
              as String;
      h.store.docs['tenants/${p.tid}/notification_deliveries/$id']!['status'] =
          'queued';
      final r = await h.okData(
        h.call(
          'POST',
          '/admin/notification-deliveries/$id/retry',
          uid: 'admin',
        ),
      );
      expect(r['idempotentReplay'], true);
    });

    test('another clinic cannot see or retry it', () async {
      await failOne();
      final id =
          h
                  .docsOf('notification_deliveries')
                  .firstWhere((d) => d['channel'] == 'push')['deliveryId']!
              as String;
      await h.createClinic(
        'rival',
        name: 'Rival Clinic',
        city: 'Nagpur',
        pin: '440001',
      );
      expect(
        await h.list(
          await h.call('GET', '/admin/notification-deliveries', uid: 'rival'),
        ),
        isEmpty,
      );
      expect(
        await h.status(
          'POST',
          '/admin/notification-deliveries/$id/retry',
          uid: 'rival',
        ),
        404,
      );
    });

    test(
      'pausing a channel keeps records queued; resuming sends them',
      () async {
        await h.actOk('admin', '/admin/notification-channels/push/pause');
        at('2026-06-01T10:00:00Z');
        await work();
        expect(fcm.sent, isEmpty);
        expect(deliveries('push').single['status'], 'queued');
        expect(
          h.docsOf('patient_notifications'),
          hasLength(1),
          reason: 'in-app is a different channel',
        );
        await h.actOk('admin', '/admin/notification-channels/push/resume');
        h.clock.now = h.clock.now.add(const Duration(minutes: 10));
        await h.clinic.hub.dispatchDue(p.tid);
        expect(deliveries('push').single['status'], 'sent');
        expect(
          h.docsOf('notification_audit_logs').map((d) => d['action']),
          containsAll([
            'notification_channel.paused',
            'notification_channel.resumed',
          ]),
        );
        expect(
          await h.status(
            'POST',
            '/admin/notification-channels/carrier_pigeon/pause',
            uid: 'admin',
          ),
          404,
        );
      },
    );

    test('channel status reports configuration honestly', () async {
      final chans = await h.list(
        await h.call('GET', '/admin/notification-channels', uid: 'admin'),
      );
      Map<Object?, Object?> ch(String c) =>
          chans.firstWhere((x) => (x! as Map)['channel'] == c)!
              as Map<Object?, Object?>;
      expect(ch('in_app')['configured'], true);
      expect(ch('push')['configured'], true);
      expect(ch('email')['configured'], false);
      expect(ch('email')['status'], 'configuration_required');
    });

    test('health shows counts, backlog and a delivery caveat', () async {
      await failOne();
      final hl = await h.get('admin', '/admin/notification-health');
      expect(hl['failed'], 1);
      expect(jsonEncode(hl), contains('not confirmation'));
    });
  });
}
