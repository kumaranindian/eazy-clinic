import 'dart:io';

import 'package:common_models/common_models.dart';
import 'package:test/test.dart';

import '../support/platform_http_fixtures.dart';

/// Release gate: every registered API route refuses an unauthenticated caller.
///
/// The routes are read from the source (`r.get('...')` and friends), so a new
/// route that forgets its auth wrapper fails this test. The only routes that
/// may answer without a token are listed explicitly below and each needs a
/// reason.
void main() {
  // path (with <params> as written) -> why it is public
  const publicRoutes = <String, String>{
    '/health': 'liveness probe, no data',
    '/ready': 'readiness probe, no data',
  };

  final routes = <(String, String)>[];
  final re = RegExp(r"\br\.(get|post|put|patch|delete)\(\s*'([^']+)'");
  for (final f
      in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
    final src = f.readAsStringSync();
    for (final m in re.allMatches(src)) {
      var path = m.group(2)!;
      // auth routes are mounted under /auth
      if (f.path.endsWith('auth_routes.dart') && path.startsWith('/')) {
        path = '/auth$path';
      }
      // routes built from loops (`$action`) are covered by the explicit list
      if (path.contains(r'${') ||
          RegExp(r'\$(?!_v1|apiV1Prefix)').hasMatch(path)) {
        continue;
      }
      routes.add((m.group(1)!.toUpperCase(), path));
    }
  }

  // routes generated in loops: path templates and their actions
  const generated = <(String, String, List<String>)>[
    ('POST', '/consultations/abc12345/', ['release', 'start', 'finalize']),
    ('POST', '/admin/notification-channels/push/', ['pause', 'resume']),
    ('POST', '/billing/refunds/abc12345/', ['approve', 'reject', 'complete']),
    ('POST', '/expenses/abc12345/', ['approve', 'reject', 'pay']),
    ('POST', '/staff/abc12345/', ['deactivate', 'activate']),
    (
      'GET',
      '/reports/',
      [
        'dashboard',
        'appointments',
        'queues',
        'patients',
        'consultations',
        'laboratory',
        'billing',
      ],
    ),
  ];
  for (final (method, base, tails) in generated) {
    for (final t in tails) {
      routes.add((method, '$base$t'));
    }
  }

  test('the route scan finds the API', () {
    expect(routes.length, greaterThan(300));
  });

  String concrete(String raw) => raw
      .replaceAll(r'$_v1', '')
      .replaceAll(r'$apiV1Prefix', '')
      .replaceAllMapped(RegExp(r'<[^>]+>'), (_) => 'abc12345');

  test('every route needs a valid token', () async {
    final h = PlatformHarness();
    final open = <String>[];
    for (final (method, raw) in routes) {
      final path = concrete(raw);
      if (publicRoutes.containsKey(path)) continue;
      final res = await h.call(method, path);
      if (res.statusCode != 401) open.add('$method $path -> ${res.statusCode}');
    }
    expect(
      open,
      isEmpty,
      reason: 'routes answering without a token:\n${open.join('\n')}',
    );
  });

  test('a garbage token is refused everywhere', () async {
    final h = PlatformHarness();
    final bad = <String>[];
    for (final (method, raw) in routes) {
      final path = concrete(raw);
      if (publicRoutes.containsKey(path)) continue;
      final res = await h.call(
        method,
        path,
        headers: {'authorization': 'Bearer not.a.token'},
      );
      if (res.statusCode != 401) bad.add('$method $path -> ${res.statusCode}');
    }
    expect(bad, isEmpty, reason: bad.join('\n'));
  });

  // Least-privilege sweep: a signed-in clinic member whose role holds only
  // the basic read permissions must not be able to use any route that
  // changes data or reads clinical, financial or staff information.
  test(
    'a least-privileged member and a stranger get no unexpected access',
    () async {
      final h = PlatformHarness();
      final tid = await _clinic(h);
      h.member('basic', tid, 'pharmacist');
      h.user('stranger');
      // routes a basic member may legitimately read
      const okForBasic = {
        '/members/current/permissions',
        '/clinics/current',
        '/branches',
        '/tenants/current/entitlements',
        '/permissions',
        '/notifications',
        '/notifications/unread-count',
        '/notifications/preferences',
        '/notifications/read-all', // own notifications
        '/clinics/current/settings', // clinic hours and time zone, every member
        '/clinics/current/country-config', // client-safe country DTO, every member
        '/laboratory/categories', // fixed lists, no data
        '/patient/consent-catalog', // static wording
        '/patient/documents', // fixed 'not available' answer
        '/reports/dashboard',
      };
      // routes about the caller's own account, open to any signed-in person
      bool selfService(String path) =>
          path.startsWith('/auth/') ||
          path.startsWith('/patient-accounts') ||
          path == '/clinic-applications/my' ||
          path == '/consent-catalog' ||
          // onboarding selector: public-by-design list of countries a new
          // clinic may choose (client-safe fields only)
          path == '/countries' ||
          // idempotent, bound to the caller's own uid; no data
          path.startsWith('/patient/devices/') ||
          path == '/patient/consent-catalog' ||
          path == '/patient/documents';
      final unexpected = <String>[];
      for (final (method, raw) in routes) {
        final path = concrete(raw);
        if (selfService(path)) continue;
        final isOk =
            okForBasic.contains(path) ||
            (path.startsWith('/branches/') && method == 'GET');
        for (final uid in ['basic', 'stranger']) {
          final res = await h.call(
            method,
            path,
            uid: uid,
            body: method == 'GET' || method == 'DELETE'
                ? null
                : <String, Object?>{},
          );
          final code = res.statusCode;
          final granted = code >= 200 && code < 300;
          if (granted && !(uid == 'basic' && isOk)) {
            unexpected.add('$uid $method $path -> $code');
          }
          if (code >= 500) {
            unexpected.add('$uid $method $path -> $code (server error)');
          }
        }
      }
      expect(unexpected, isEmpty, reason: unexpected.join('\n'));
    },
  );

  // Mass-assignment sweep: the owner sends every changing route a body made
  // only of fields no route accepts (tenant, role, status, uid, ...). A route
  // that answers 2xx accepted a body it should have rejected or ignores it.
  test('bodies with only forbidden fields never succeed', () async {
    final h = PlatformHarness();
    final tid = await _clinic(h);
    expect(tid, isNotEmpty);
    // routes that take no body at all (actions) may succeed on an empty or
    // ignored body, but they must not be steered by it either
    final accepted = <String>[];
    for (final (method, raw) in routes) {
      if (method == 'GET') continue;
      final path = concrete(raw);
      if (path.startsWith('/auth/') || path.startsWith('/patient-accounts')) {
        continue;
      }
      // idempotent actions on the caller's own data that take no body
      if (path == '/notifications/read-all' ||
          path.startsWith('/admin/notification-channels/') ||
          path.startsWith('/patient/devices/')) {
        continue;
      }
      final res = await h.call(
        method,
        path,
        uid: 'owner',
        body: <String, Object?>{
          'tenantId': 'ten_other',
          'role': 'clinic_owner',
          'status': 'active',
          'uid': 'someone',
          'isAdmin': true,
          'permissions': ['*'],
        },
      );
      if (res.statusCode >= 200 && res.statusCode < 300) {
        accepted.add('$method $path -> ${res.statusCode}');
      }
      if (res.statusCode >= 500) {
        accepted.add('$method $path -> ${res.statusCode} (server error)');
      }
    }
    expect(accepted, isEmpty, reason: accepted.join('\n'));
  });
}

Future<String> _clinic(PlatformHarness h) async {
  h.user('root', role: PlatformRole.superAdmin);
  return h.createClinic('owner');
}
