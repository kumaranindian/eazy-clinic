import 'package:backend/core/localization/document_locale.dart';
import 'package:backend/features/notifications/notification_core.dart';
import 'package:common_models/common_models.dart';
import 'package:test/test.dart';

import '../../support/platform_fixtures.dart';
import '../../support/platform_http_fixtures.dart';

/// Builds a bidi control character without a literal in the source.
class U {
  static String c(int code) => String.fromCharCode(code);
}

void main() {
  group('template rendering and bidirectional text', () {
    const allowed = {'clinicName', 'date', 'time'};
    final vars = {
      'clinicName': 'Green Valley Clinic',
      'date': '12 Jun 2026',
      'time': '10:30',
    };

    test('right-to-left templates isolate every value', () {
      final out = renderTemplate(
        'لديك موعد في {{clinicName}} بتاريخ {{date}} الساعة {{time}}.',
        vars,
        allowed: allowed,
        rtl: true,
      );
      expect(out, contains('${U.c(0x2068)}Green Valley Clinic${U.c(0x2069)}'));
      expect(out, contains('${U.c(0x2068)}10:30${U.c(0x2069)}'));
      expect(out.startsWith('لديك'), isTrue);
    });

    test('left-to-right output is unchanged (no isolates)', () {
      final out = renderTemplate(
        'See {{clinicName}} on {{date}} at {{time}}.',
        vars,
        allowed: allowed,
      );
      expect(out, 'See Green Valley Clinic on 12 Jun 2026 at 10:30.');
    });

    test('bidi control characters in a value are removed, not honoured', () {
      final evil = {
        ...vars,
        'clinicName':
            'Cl${U.c(0x202E)}inic${U.c(0x2066)} ${U.c(0x200F)}${U.c(0x61C)}X${U.c(0x2069)}${U.c(0x202C)}',
      };
      final out = renderTemplate(
        '{{clinicName}} {{date}} {{time}}',
        evil,
        allowed: allowed,
        rtl: true,
      );
      for (final c in [U.c(0x202E), U.c(0x202C), U.c(0x200F), U.c(0x61C)]) {
        expect(
          out.contains(c),
          isFalse,
          reason: 'U+${c.runes.first.toRadixString(16)}',
        );
      }
      // only the isolates added by the renderer remain
      expect(U.c(0x2066).allMatches(out), isEmpty);
      expect(U.c(0x2068).allMatches(out), hasLength(3));
      expect(out, contains('Clinic X'));
    });

    test('Unicode names and digits pass through intact', () {
      final out = renderTemplate(
        '{{clinicName}}',
        {'clinicName': 'مستشفى النور — د. ليلى 12'},
        allowed: allowed,
        rtl: true,
      );
      expect(out, contains('مستشفى النور — د. ليلى 12'));
      expect(
        renderTemplate('{{clinicName}}', {
          'clinicName': 'வள்ளி கிளினிக்',
        }, allowed: allowed),
        'வள்ளி கிளினிக்',
      );
    });

    test('HTML is still escaped and isolated in right-to-left emails', () {
      final out = renderTemplate(
        '{{clinicName}}',
        {'clinicName': '<b>نور</b>'},
        allowed: allowed,
        html: true,
        rtl: true,
      );
      expect(out, contains('&lt;b&gt;'));
      expect(out, isNot(contains('<b>')));
    });

    test('a missing or disallowed variable still fails in every language', () {
      expect(
        () => renderTemplate('{{nope}}', vars, allowed: allowed, rtl: true),
        throwsA(isA<TemplateException>()),
      );
      expect(
        () => renderTemplate('{{date}}', {}, allowed: allowed, rtl: true),
        throwsA(isA<TemplateException>()),
      );
    });
  });

  group('built-in translated templates', () {
    test(
      'every translation uses exactly the placeholders of its English original',
      () {
        final english = {
          for (final t in builtinTemplates.where((t) => t.locale == 'en'))
            '${t.eventType}/${t.channel}': placeholdersIn(
              '${t.subject} ${t.body}',
            ),
        };
        final translated = builtinTemplates
            .where((t) => t.locale != 'en')
            .toList();
        expect(translated, isNotEmpty);
        for (final t in translated) {
          final key = '${t.eventType}/${t.channel}';
          expect(
            english.containsKey(key),
            isTrue,
            reason: 'no English for $key',
          );
          expect(
            placeholdersIn('${t.subject} ${t.body}'),
            english[key],
            reason: '${t.locale} $key',
          );
          expect(supportedUiLanguages, contains(t.locale));
        }
      },
    );

    test('Arabic, Hindi and Tamil reminders exist for in-app and push', () {
      for (final lang in ['ar', 'hi', 'ta']) {
        for (final type in ['appointment_reminder', 'followup_reminder']) {
          for (final ch in ['in_app', 'push']) {
            expect(
              builtinTemplates.any(
                (t) =>
                    t.locale == lang && t.eventType == type && t.channel == ch,
              ),
              isTrue,
              reason: '$lang $type $ch',
            );
          }
        }
      }
    });

    test('translated texts carry no clinical detail variables', () {
      const clinical = {'diagnosis', 'medicine', 'result', 'complaint'};
      for (final t in builtinTemplates.where((t) => t.locale != 'en')) {
        expect(
          placeholdersIn('${t.subject} ${t.body}').intersection(clinical),
          isEmpty,
        );
      }
    });
  });

  group('document localization hook', () {
    test(
      'recipient, clinic, country, then English; only available languages',
      () {
        const available = {'en', 'ar'};
        expect(
          resolveDocumentLocale(
            availableLanguages: available,
            recipientLanguage: 'ar',
            clinicLanguage: 'en',
          ).language,
          'ar',
        );
        final r = resolveDocumentLocale(
          availableLanguages: available,
          recipientLanguage: 'ta', // no Tamil template for this document
          clinicLanguage: 'ar',
        );
        expect((r.language, r.source), ('ar', 'clinic'));
        expect(r.rtl, isTrue);
        final fallback = resolveDocumentLocale(
          availableLanguages: {'en'},
          recipientLanguage: 'ar',
          countryLanguage: 'hi',
        );
        expect((fallback.language, fallback.source), ('en', 'default'));
        expect(fallback.rtl, isFalse);
        expect(
          resolveDocumentLocale(
            availableLanguages: available,
            recipientLanguage: 'xx',
          ).language,
          'en',
        );
      },
    );
  });

  group('preferred language on the account', () {
    PlatformHarness harness() => PlatformHarness()..user('u1');

    test('a user can set, read back and clear their language', () async {
      final h = harness();
      final set = await h.okData(
        h.call(
          'PATCH',
          '/auth/me',
          uid: 'u1',
          body: {'preferredLanguage': 'ar'},
        ),
      );
      expect(set['preferredLanguage'], 'ar');
      final session = await h.okData(h.call('GET', '/auth/session', uid: 'u1'));
      expect(session['preferredLanguage'], 'ar');
      final cleared = await h.okData(
        h.call(
          'PATCH',
          '/auth/me',
          uid: 'u1',
          body: {'preferredLanguage': null},
        ),
      );
      expect(cleared.containsKey('preferredLanguage'), isFalse);
    });

    test('unsupported or malformed languages are rejected', () async {
      final h = harness();
      for (final bad in ['fr', 'AR', 'ar-AE', '', 'english', 7]) {
        final r = await h.call(
          'PATCH',
          '/auth/me',
          uid: 'u1',
          body: {'preferredLanguage': bad},
        );
        expect(r.statusCode, anyOf(400, 422), reason: '$bad');
      }
    });

    test('language does not alter roles, tenant or country', () async {
      final h = harness()..user('root', role: PlatformRole.superAdmin);
      final tid = await h.createClinic('owner1');
      final before = Map.of(h.store.docs['tenants/$tid']!);
      await h.okData(
        h.call(
          'PATCH',
          '/auth/me',
          uid: 'owner1',
          body: {'preferredLanguage': 'ta'},
        ),
      );
      expect(
        h.store.docs['tenants/$tid']!['countryCode'],
        before['countryCode'],
      );
      final cfg = await h.okData(
        h.call('GET', '/clinics/current/country-config', uid: 'owner1'),
      );
      expect((cfg['country']! as Map)['code'], 'IN');
    });

    test(
      'a language cannot be smuggled together with forbidden fields',
      () async {
        final h = harness();
        final r = await h.call(
          'PATCH',
          '/auth/me',
          uid: 'u1',
          body: {'preferredLanguage': 'ar', 'platformRole': 'super_admin'},
        );
        expect(r.statusCode, 422);
        expect(h.store.docs['platform_users/u1']!['platformRole'], isNull);
      },
    );

    test(
      'request logs never contain the chosen language or any body',
      () async {
        final h = harness();
        await h.okData(
          h.call(
            'PATCH',
            '/auth/me',
            uid: 'u1',
            body: {'preferredLanguage': 'hi'},
          ),
        );
        final logs = h.logs.join();
        expect(logs, contains('profile_updated'));
        expect(logs, isNot(contains('"hi"')));
        expect(logs, isNot(contains('preferredLanguage":"')));
      },
    );
  });

  group('Unicode in names and text', () {
    test(
      'Arabic, Tamil and Hindi owner and clinic names are accepted',
      () async {
        final h = PlatformHarness();
        h.user('root', role: PlatformRole.superAdmin);
        for (final (i, name) in [
          (0, 'عيادة النور'),
          (1, 'வள்ளி கிளினிக்'),
          (2, 'आरोग्य क्लिनिक'),
        ]) {
          h.user('u$i');
          final b = applicationBody(name: '$name $i');
          (b['owner']! as Map<String, Object?>)['fullName'] = 'د. ليلى الأحمد';
          final r = await h.call(
            'POST',
            '/clinic-applications',
            uid: 'u$i',
            body: b,
          );
          expect(r.statusCode, 201, reason: name);
        }
      },
    );
  });
}
