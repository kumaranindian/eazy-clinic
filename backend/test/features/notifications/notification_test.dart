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
  String? apptId;
  String? apptStart;

  Future<void> boot({
    MockFcm? sender,
    Map<String, MessageProvider>? providers,
  }) async {
    apptId = null;
    fcm = sender ?? MockFcm();
    h = PlatformHarness(fcm: fcm, providers: providers ?? const {});
    p = PortalClinic(h);
    await p.init();
  }

  setUp(() => boot());

  var n = 0;
  Future<String> emitFor({
    String type = 'payment_received',
    String? key,
    String? accountId,
    String? staffUid,
    String? patientId,
    Map<String, String> variables = const {},
  }) async {
    String? rid;
    var data = <String, String>{};
    if (type == 'appointment_reminder') {
      if (apptId == null) {
        final a = await h.bookOk('recep', p.k.c.body());
        apptId = a['appointmentId']! as String;
        final st =
            h.store.docs['tenants/${p.tid}/appointments/$apptId']!['startUtc']
                as DateTime;
        apptStart = st.toUtc().toIso8601String();
      }
      rid = apptId;
      data = {'startUtc': apptStart!};
    }
    return h.clinic.hub.emit(
      tenantId: p.tid,
      type: type,
      dedupeKey: key ?? 'k${n++}',
      accountId:
          accountId ??
          (staffUid == null && patientId == null ? p.accountId : null),
      patientId: patientId,
      staffUid: staffUid,
      resourceType: rid == null ? null : 'appointment',
      resourceId: rid,
      variables: variables,
      data: data,
      fallbackTitle: 'Payment received',
      fallbackBody: 'Open the app for details.',
    );
  }

  Future<void> addDevice([
    String uid = 'asha',
    String token = 'tok-aaaaaaaaaaaaaaaaaaaaaaaa',
  ]) => h
      .okData(
        h.call(
          'POST',
          '/patient/devices',
          uid: uid,
          body: {
            'deviceId': 'device-$uid-01',
            'token': token,
            'platform': 'android',
          },
        ),
        status: 201,
      )
      .then((_) {});

  Iterable<Map<String, Object?>> deliveries([String? channel]) => h
      .docsOf('notification_deliveries')
      .where((d) => channel == null || d['channel'] == channel);

  Future<void> run() async {
    await h.clinic.hub.processPending(p.tid);
    await h.clinic.hub.dispatchDue(p.tid);
  }

  group('events and delivery', () {
    test(
      'an event becomes an inbox entry and a tracked in-app delivery',
      () async {
        await emitFor();
        await run();
        final inbox = h.docsOf('patient_notifications').toList();
        expect(inbox, hasLength(1));
        expect(inbox.single['accountId'], p.accountId);
        final d = deliveries('in_app').single;
        expect(d['status'], 'delivered');
        expect(d['type'], 'payment_received');
      },
    );

    test('replaying an event creates nothing twice', () async {
      await emitFor(key: 'same');
      await emitFor(key: 'same');
      await run();
      await run();
      expect(h.docsOf('notification_events'), hasLength(1));
      expect(h.docsOf('patient_notifications'), hasLength(1));
      expect(deliveries('in_app'), hasLength(1));
    });

    test('concurrent workers still produce one notification', () async {
      final id = await emitFor();
      await Future.wait([
        for (var i = 0; i < 4; i++) h.clinic.hub.processEvent(p.tid, id),
      ]);
      expect(h.docsOf('patient_notifications'), hasLength(1));
    });

    test(
      'an event whose worker died is picked up again after the lease',
      () async {
        final id = await emitFor();
        h.store.docs['tenants/${p.tid}/notification_events/$id']!
          ..['status'] = 'processing'
          ..['leaseUntil'] = h.clock.now.add(const Duration(minutes: 5));
        expect(
          await h.clinic.hub.processEvent(p.tid, id),
          isFalse,
          reason: 'another worker holds it',
        );
        h.clock.now = h.clock.now.add(const Duration(minutes: 6));
        expect(await h.clinic.hub.processEvent(p.tid, id), isTrue);
        expect(h.docsOf('patient_notifications'), hasLength(1));
      },
    );

    test('recipients come from the clinic record, not the request', () async {
      // an event naming no resolvable recipient delivers to nobody
      await h.clinic.hub.emit(
        tenantId: p.tid,
        type: 'payment_received',
        dedupeKey: 'ghost',
        patientId: 'pt_does_not_exist',
        fallbackTitle: 't',
        fallbackBody: 'b',
      );
      await run();
      expect(h.docsOf('patient_notifications'), isEmpty);
      expect(deliveries(), isEmpty);
    });
  });

  group('push', () {
    test('accepted by FCM is "sent", never "delivered"', () async {
      await addDevice();
      await emitFor();
      await run();
      final d = deliveries('push').single;
      expect(d['status'], 'sent');
      expect(d['providerMessageId'], 'm1');
      expect(fcm.sent.single.token, 'tok-aaaaaaaaaaaaaaaaaaaaaaaa');
      expect(
        deliveries().where(
          (x) => x['status'] == 'delivered' && x['channel'] == 'push',
        ),
        isEmpty,
      );
    });

    test('without configuration the delivery says so', () async {
      await boot(sender: MockFcm(configuredFlag: false));
      await addDevice();
      await emitFor();
      await run();
      expect(deliveries('push').single['status'], 'configuration_required');
      expect(fcm.sent, isEmpty);
    });

    test(
      'a transient failure is retried with backoff, then succeeds',
      () async {
        fcm.script = [
          const ProviderResult('transient', error: 'http_503'),
          const ProviderResult('accepted', messageId: 'ok1'),
        ];
        await addDevice();
        await emitFor();
        await run();
        var d = deliveries('push').single;
        expect(d['status'], 'retry_scheduled');
        expect(d['attempts'], 1);
        expect((d['nextAttemptAt']! as DateTime).isAfter(h.clock.now), isTrue);
        await run(); // not due yet
        expect(fcm.sent, hasLength(1));
        h.clock.now = h.clock.now.add(const Duration(minutes: 2));
        await run();
        d = deliveries('push').single;
        expect(d['status'], 'sent');
        expect(d['attempts'], 2);
      },
    );

    test('retries are bounded', () async {
      fcm.script = [const ProviderResult('transient', error: 'http_503')];
      await addDevice();
      await emitFor();
      for (var i = 0; i < maxDeliveryAttempts + 2; i++) {
        await run();
        h.clock.now = h.clock.now.add(const Duration(hours: 1));
      }
      final d = deliveries('push').single;
      expect(d['status'], 'permanently_failed');
      expect(d['attempts'], maxDeliveryAttempts);
      expect(fcm.sent, hasLength(maxDeliveryAttempts));
    });

    test(
      'an invalid token deactivates the device and fails permanently',
      () async {
        fcm.script = [
          const ProviderResult('invalid_token', error: 'token_unregistered'),
        ];
        await addDevice();
        await emitFor();
        await run();
        expect(deliveries('push').single['status'], 'permanently_failed');
        expect(h.docsOf('patient_devices').single['active'], false);
      },
    );

    test(
      'a user with no device gets the inbox entry and a cancelled push',
      () async {
        await emitFor();
        await run();
        expect(deliveries('push').single['status'], 'cancelled');
        expect(deliveries('push').single['error'], 'no_active_device');
        expect(h.docsOf('patient_notifications'), hasLength(1));
      },
    );

    test('several devices each receive it', () async {
      await addDevice('asha', 'tok-aaaaaaaaaaaaaaaaaaaaaaaa');
      await h.okData(
        h.call(
          'POST',
          '/patient/devices',
          uid: 'asha',
          body: {
            'deviceId': 'device-asha-02',
            'token': 'tok-bbbbbbbbbbbbbbbbbbbbbbbb',
            'platform': 'android',
          },
        ),
        status: 201,
      );
      await emitFor();
      await run();
      expect(
        fcm.sent.map((s) => s.token),
        unorderedEquals([
          'tok-aaaaaaaaaaaaaaaaaaaaaaaa',
          'tok-bbbbbbbbbbbbbbbbbbbbbbbb',
        ]),
      );
    });
  });

  group('preferences and consent', () {
    test(
      'turning push off removes the push but keeps the essential inbox entry',
      () async {
        await addDevice();
        await h.okData(
          h.call(
            'PUT',
            '/patient/notifications/preferences',
            uid: 'asha',
            body: {'pushEnabled': false},
          ),
        );
        await emitFor();
        await run();
        expect(deliveries('push'), isEmpty);
        expect(fcm.sent, isEmpty);
        expect(h.docsOf('patient_notifications'), hasLength(1));
      },
    );

    test('preferences are re-checked when a queued push is sent', () async {
      await addDevice();
      await emitFor();
      await h.clinic.hub.processPending(p.tid);
      await h.okData(
        h.call(
          'PUT',
          '/patient/notifications/preferences',
          uid: 'asha',
          body: {'pushEnabled': false},
        ),
      );
      await h.clinic.hub.dispatchDue(p.tid);
      expect(deliveries('push').single['status'], 'cancelled');
      expect(fcm.sent, isEmpty);
    });

    test('promotional messages need an explicit opt-in', () async {
      await emitFor(type: 'clinic_announcement', key: 'promo1');
      await run();
      expect(h.docsOf('patient_notifications'), isEmpty);
      await h.okData(
        h.call(
          'PUT',
          '/patient/notifications/preferences',
          uid: 'asha',
          body: {
            'categories': {'clinic_announcement': true},
          },
        ),
      );
      await emitFor(type: 'clinic_announcement', key: 'promo2');
      await run();
      expect(h.docsOf('patient_notifications'), hasLength(1));
    });

    test('an essential category cannot be switched off', () async {
      await h.okData(
        h.call(
          'PUT',
          '/patient/notifications/preferences',
          uid: 'asha',
          body: {
            'categories': {'payment_received': false},
          },
        ),
      );
      await emitFor(type: 'payment_received', key: 'p1');
      await run();
      expect(h.docsOf('patient_notifications'), hasLength(1));
      // but the push for it honours the choice
      expect(deliveries('push'), isEmpty);
    });

    test('staff preferences: view, change, audit', () async {
      final before = await h.get('docuser', '/notifications/preferences');
      expect(before['pushEnabled'], true);
      expect((before['categories'] as Map)['clinic_announcement'], false);
      final after = await h.okData(
        h.call(
          'PATCH',
          '/notifications/preferences',
          uid: 'docuser',
          body: {
            'pushEnabled': false,
            'categories': {'clinic_announcement': true},
          },
        ),
      );
      expect(after['pushEnabled'], false);
      expect((after['categories'] as Map)['clinic_announcement'], true);
      expect(
        h.docsOf('notification_audit_logs').map((d) => d['action']),
        contains('notification_preferences.updated'),
      );
      expect(
        await h.status(
          'PATCH',
          '/notifications/preferences',
          uid: 'docuser',
          body: {
            'categories': {'nope': true},
          },
        ),
        422,
      );
    });
  });

  group('patient inbox', () {
    test(
      'read-all and archive work on the caller\'s own entries only',
      () async {
        await emitFor(key: 'a1');
        await emitFor(key: 'a2');
        await run();
        var inbox = await p.get('/patient/notifications');
        expect(inbox['unread'], 2);
        final id =
            ((inbox['items']! as List).first as Map)['notificationId']!
                as String;
        await p.createAccount('ravi');
        expect(
          await p.status(
            'POST',
            '/patient/notifications/$id/archive',
            uid: 'ravi',
          ),
          404,
        );
        expect(
          await p.status('POST', '/patient/notifications/$id/archive'),
          200,
        );
        inbox = await p.get('/patient/notifications');
        expect((inbox['items']! as List), hasLength(1));
        expect(inbox['unread'], 1);
        await h.actOk('asha', '/patient/notifications/read-all');
        expect((await p.get('/patient/notifications'))['unread'], 0);
        // ravi's read-all touches nothing of asha's
        await emitFor(key: 'a3');
        await run();
        await h.actOk('ravi', '/patient/notifications/read-all');
        expect((await p.get('/patient/notifications'))['unread'], 1);
      },
    );
  });

  group('staff inbox and devices', () {
    Future<String> notifyDoctor([String key = 'd1']) async {
      await h.clinic.portal.notifier.notifyDoctor(
        p.tid,
        p.doctor,
        category: 'report_available',
        title: 'A report is ready',
        body: 'Open the app.',
        dedupeKey: key,
        resourceType: 'lab_report',
        resourceId: 'lr_1',
      );
      return key;
    }

    test('inbox, unread count, read, read-all and archive', () async {
      await notifyDoctor('d1');
      await notifyDoctor('d2');
      expect(
        (await h.get('docuser', '/notifications/unread-count'))['unread'],
        2,
      );
      final list = await h.list(
        await h.call('GET', '/notifications', uid: 'docuser'),
      );
      expect(list, hasLength(2));
      final id = (list.first! as Map)['notificationId']! as String;
      expect((list.first! as Map).containsKey('recipientUid'), isFalse);
      await h.actOk('docuser', '/notifications/$id/read');
      expect(
        (await h.get('docuser', '/notifications/unread-count'))['unread'],
        1,
      );
      await h.actOk('docuser', '/notifications/$id/archive');
      expect(
        await h.list(await h.call('GET', '/notifications', uid: 'docuser')),
        hasLength(1),
      );
      await h.actOk('docuser', '/notifications/read-all');
      expect(
        (await h.get('docuser', '/notifications/unread-count'))['unread'],
        0,
      );
    });

    test('pagination returns pages', () async {
      for (var i = 0; i < 5; i++) {
        await notifyDoctor('p$i');
      }
      final res = await h.call('GET', '/notifications?limit=2', uid: 'docuser');
      final body = jsonDecode(await res.readAsString()) as Map;
      expect((body['data'] as List), hasLength(2));
      expect((body['meta'] as Map).isNotEmpty, true);
    });

    test('nobody else can read, mark or archive it', () async {
      await notifyDoctor();
      final id = h.docsOf('notifications').single['notificationId']! as String;
      for (final uid in ['recep', 'owner']) {
        expect(
          await h.status('POST', '/notifications/$id/read', uid: uid),
          404,
          reason: uid,
        );
        expect(
          await h.status('POST', '/notifications/$id/archive', uid: uid),
          404,
          reason: uid,
        );
        expect((await h.get(uid, '/notifications/unread-count'))['unread'], 0);
      }
    });

    test('another clinic sees nothing', () async {
      await notifyDoctor();
      await h.createClinic(
        'rival',
        name: 'Rival Clinic',
        city: 'Nagpur',
        pin: '440001',
      );
      expect(
        (await h.get('rival', '/notifications/unread-count'))['unread'],
        0,
      );
    });

    test('device tokens belong to the caller and are never returned', () async {
      final r = await h.okData(
        h.call(
          'POST',
          '/notifications/devices',
          uid: 'docuser',
          body: {
            'deviceId': 'doctor-phone-01',
            'token': 'tok-ccccccccccccccccccccccccc',
            'platform': 'android',
          },
        ),
        status: 201,
      );
      expect(jsonEncode(r).contains('tok-ccc'), isFalse);
      final stored = h.docsOf('notification_devices').single;
      expect(stored['uid'], 'docuser');
      expect(
        await h.status(
          'DELETE',
          '/notifications/devices/${r['id']}',
          uid: 'recep',
        ),
        404,
      );
      expect(h.docsOf('notification_devices').single['active'], true);
      expect(
        await h.status(
          'DELETE',
          '/notifications/devices/${r['id']}',
          uid: 'docuser',
        ),
        200,
      );
      expect(h.docsOf('notification_devices').single['active'], false);
      // re-registering refreshes the same device record
      await h.okData(
        h.call(
          'POST',
          '/notifications/devices',
          uid: 'docuser',
          body: {
            'deviceId': 'doctor-phone-01',
            'token': 'tok-ccccccccccccccccccccccccc',
            'platform': 'android',
          },
        ),
        status: 201,
      );
      expect(h.docsOf('notification_devices'), hasLength(1));
      expect(h.docsOf('notification_devices').single['active'], true);
      expect(
        await h.status(
          'POST',
          '/notifications/devices',
          uid: 'docuser',
          body: {
            'deviceId': 'x',
            'token': 'short',
            'platform': 'android',
            'uid': 'recep',
          },
        ),
        422,
      );
    });

    test('a staff push goes to that user\'s device only', () async {
      await h.okData(
        h.call(
          'POST',
          '/notifications/devices',
          uid: 'docuser',
          body: {
            'deviceId': 'doctor-phone-01',
            'token': 'tok-ccccccccccccccccccccccccc',
            'platform': 'android',
          },
        ),
        status: 201,
      );
      await notifyDoctor();
      expect(fcm.sent.map((s) => s.token), ['tok-ccccccccccccccccccccccccc']);
    });
  });

  group('templates', () {
    test('only managers use the template administration', () async {
      for (final uid in ['docuser', 'recep', 'nurse']) {
        expect(
          await h.status('GET', '/admin/notification-templates', uid: uid),
          403,
          reason: uid,
        );
      }
      final list = await h.list(
        await h.call('GET', '/admin/notification-templates', uid: 'admin'),
      );
      expect(list.any((t) => (t! as Map)['builtin'] == true), isTrue);
    });

    Map<String, Object?> tpl({
      String body = 'See you on {{date}} at {{time}}.',
    }) => {
      'name': 'Reminder',
      'eventType': 'appointment_reminder',
      'channel': 'in_app',
      'locale': 'en',
      'subject': 'Visit soon',
      'body': body,
    };

    test('unknown variables and odd placeholders are refused', () async {
      expect(
        await h.status(
          'POST',
          '/admin/notification-templates',
          uid: 'admin',
          body: tpl(body: 'Diagnosis: {{diagnosis}}'),
        ),
        422,
      );
      expect(
        await h.status(
          'POST',
          '/admin/notification-templates',
          uid: 'admin',
          body: tpl(body: 'Hi {{ date | upper }}'),
        ),
        422,
      );
      expect(
        await h.status(
          'POST',
          '/admin/notification-templates',
          uid: 'admin',
          body: {...tpl(), 'eventType': 'nope'},
        ),
        422,
      );
    });

    test(
      'create, duplicate, edit with versions, preview without sending',
      () async {
        final t = await h.okData(
          h.call(
            'POST',
            '/admin/notification-templates',
            uid: 'admin',
            body: tpl(),
          ),
          status: 201,
        );
        expect(t['version'], 1);
        expect(
          await h.status(
            'POST',
            '/admin/notification-templates',
            uid: 'admin',
            body: tpl(),
          ),
          409,
        );
        final u = await h.okData(
          h.call(
            'PATCH',
            '/admin/notification-templates/${t['templateId']}',
            uid: 'admin',
            body: {'body': 'Visit on {{date}}.'},
          ),
        );
        expect(u['version'], 2);
        expect(h.docsOf('notification_template_versions'), hasLength(1));
        expect(
          h.docsOf('notification_template_versions').single['body'],
          'See you on {{date}} at {{time}}.',
        );
        final pv = await h.okData(
          h.call(
            'POST',
            '/admin/notification-templates/${t['templateId']}/preview',
            uid: 'admin',
            body: {
              'variables': {'date': '2026-07-01'},
            },
          ),
        );
        expect(pv['body'], 'Visit on 2026-07-01.');
        expect(fcm.sent, isEmpty);
        expect(h.docsOf('notification_deliveries'), isEmpty);
        expect(
          h.docsOf('notification_audit_logs').map((d) => d['action']),
          containsAll([
            'notification_template.created',
            'notification_template.updated',
          ]),
        );
      },
    );

    test(
      'a clinic template replaces the built-in one and records its version',
      () async {
        await h.okData(
          h.call(
            'POST',
            '/admin/notification-templates',
            uid: 'admin',
            body: tpl(body: 'Please come on {{date}} at {{time}}.'),
          ),
          status: 201,
        );
        await emitFor(
          type: 'appointment_reminder',
          key: 'r1',
          variables: {
            'clinicName': 'C',
            'doctorName': 'D',
            'date': '2026-07-01',
            'time': '09:00',
          },
        );
        await run();
        final d = deliveries('in_app').single;
        expect(d['body'], 'Please come on 2026-07-01 at 09:00.');
        expect(d['templateVersion'], 1);
        expect((d['templateRef']! as String).startsWith('tpl_'), isTrue);
      },
    );

    test(
      'a missing variable fails that delivery, never sends a broken message',
      () async {
        await emitFor(
          type: 'appointment_reminder',
          key: 'r2',
          variables: {'clinicName': 'C'},
        );
        await run();
        final d = deliveries('in_app').single;
        expect(d['status'], 'permanently_failed');
        expect((d['error']! as String), contains('template_error'));
        expect(h.docsOf('patient_notifications'), isEmpty);
      },
    );

    test('values cannot inject markup or placeholders', () {
      expect(
        renderTemplate(
          'Hi {{name}}',
          {'name': '<script>alert(1)</script>'},
          allowed: {'name'},
          html: true,
        ),
        'Hi &lt;script&gt;alert(1)&lt;/script&gt;',
      );
      expect(
        renderTemplate(
          'Hi {{name}}',
          {'name': '{{secret}}'},
          allowed: {'name'},
        ),
        'Hi secret',
      );
      expect(
        () => renderTemplate('{{x}}', {'x': 'y'}, allowed: {'name'}),
        throwsA(isA<TemplateException>()),
      );
      expect(
        () => renderTemplate('{{name}}', {}, allowed: {'name'}),
        throwsA(isA<TemplateException>()),
      );
    });

    test('push text for reminders stays generic', () async {
      await addDevice();
      await emitFor(
        type: 'appointment_reminder',
        key: 'r3',
        variables: {
          'clinicName': 'C',
          'doctorName': 'Dr Secret',
          'date': '2026-07-01',
          'time': '09:00',
        },
      );
      await run();
      final s = fcm.sent.single;
      expect('${s.title} ${s.body}'.contains('Dr Secret'), isFalse);
      expect('${s.title} ${s.body}'.contains('2026'), isFalse);
    });
  });

  group('email adapter', () {
    test('unconfigured provider is reported, not faked', () async {
      await h.okData(
        h.call(
          'PUT',
          '/admin/notification-settings',
          uid: 'admin',
          body: {
            'channels': ['in_app', 'push', 'email'],
          },
        ),
      );
      h.store.docs['tenants/${p.tid}/patients/${p.patientId}']!['email'] =
          'asha@example.test';
      await emitFor(
        type: 'appointment_reminder',
        key: 'e1',
        variables: {
          'clinicName': 'C',
          'doctorName': 'D',
          'date': 'x',
          'time': 'y',
        },
      );
      // the event names the account only; give it the patient for the address
      await run();
      expect(deliveries('email').single['status'], 'configuration_required');
    });

    test(
      'a configured provider is called with the clinic record\'s address',
      () async {
        final mail = MockProvider();
        await boot(providers: {'email': mail});
        await h.okData(
          h.call(
            'PUT',
            '/admin/notification-settings',
            uid: 'admin',
            body: {
              'channels': ['in_app', 'email'],
            },
          ),
        );
        h.store.docs['tenants/${p.tid}/patients/${p.patientId}']!['email'] =
            'asha@example.test';
        await emitFor(
          type: 'appointment_reminder',
          key: 'e2',
          patientId: p.patientId,
          variables: {
            'clinicName': '<b>C</b>',
            'doctorName': 'D',
            'date': '2026-07-01',
            'time': '09:00',
          },
        );
        await run();
        expect(mail.sent.single.address, 'asha@example.test');
        expect(mail.sent.single.subject, contains('&lt;b&gt;C&lt;/b&gt;'));
        expect(deliveries('email').single['status'], 'sent');
      },
    );
  });
}
