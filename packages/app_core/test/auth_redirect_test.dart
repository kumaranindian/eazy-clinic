import 'package:app_core/app_core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

String? redirect(AuthState auth, String location, {Set<String>? public}) =>
    authRedirect(
      auth: auth,
      location: Uri.parse(location),
      isPublic: (p) => (public ?? const {}).contains(p),
    );

final authed = Authenticated(user: testUser, session: activeSession());

void main() {
  group('while resolving', () {
    test('protected deep link is held and remembered', () {
      expect(
        redirect(const AuthResolving(), '/patients/42'),
        '/starting?from=%2Fpatients%2F42',
      );
    });
    test('does not loop on the loading screen', () {
      expect(redirect(const AuthResolving(), '/starting'), isNull);
    });
    test('login screen is also held until resolved', () {
      expect(redirect(const AuthResolving(), '/login'), '/starting');
    });
  });

  group('unauthenticated', () {
    test('protected route → login with return location', () {
      expect(
        redirect(const Unauthenticated(), '/appointments?day=1'),
        '/login?from=%2Fappointments%3Fday%3D1',
      );
    });
    test('home → login', () {
      expect(redirect(const Unauthenticated(), '/'), '/login');
    });
    test('entry screens and public paths are reachable', () {
      for (final p in ['/login', '/register', '/forgot-password']) {
        expect(redirect(const Unauthenticated(), p), isNull);
      }
      expect(
        redirect(const Unauthenticated(), '/gallery', public: {'/gallery'}),
        isNull,
      );
    });
    test('status screens are not reachable when signed out', () {
      expect(redirect(const Unauthenticated(), '/access-denied'), '/login');
      expect(redirect(const Unauthenticated(), '/verify-email'), '/login');
    });
    test('signed-out landing replaces login for the home location only', () {
      String? r(String loc) => authRedirect(
        auth: const Unauthenticated(),
        location: Uri.parse(loc),
        isPublic: (p) => p == '/welcome',
        signedOutLanding: '/welcome',
      );
      expect(r('/'), '/welcome');
      expect(r('/welcome'), isNull);
      expect(r('/starting'), '/welcome', reason: 'after startup resolves');
      expect(r('/patients/1'), '/login?from=%2Fpatients%2F1');
    });
    test('registration disabled → login', () {
      expect(
        authRedirect(
          auth: const Unauthenticated(),
          location: Uri.parse('/register'),
          isPublic: (_) => false,
          registrationEnabled: false,
        ),
        '/login',
      );
    });
  });

  group('authenticated', () {
    test('leaves auth screens for home', () {
      expect(redirect(authed, '/login'), '/');
      expect(redirect(authed, '/starting'), '/');
    });
    test('returns to the remembered deep link', () {
      expect(redirect(authed, '/login?from=%2Fpatients%2F42'), '/patients/42');
    });
    test('rejects open-redirect attempts', () {
      for (final evil in [
        'https://evil.example',
        '//evil.example',
        '/\\evil',
        'javascript:alert(1)',
        '/login',
      ]) {
        expect(
          redirect(authed, '/login?from=${Uri.encodeComponent(evil)}'),
          '/',
          reason: evil,
        );
      }
    });
    test('protected routes are open', () {
      expect(redirect(authed, '/patients'), isNull);
    });
  });

  group('signed in but not admitted', () {
    test('suspended → access denied screen only', () {
      const s = AccessDenied(reason: AccessDeniedReason.suspended);
      expect(redirect(s, '/'), '/access-denied');
      expect(redirect(s, '/patients'), '/access-denied');
      expect(redirect(s, '/access-denied'), isNull);
    });
    test('unverified email → verification screen', () {
      const s = AccessDenied(reason: AccessDeniedReason.emailUnverified);
      expect(redirect(s, '/'), '/verify-email');
      expect(redirect(s, '/verify-email'), isNull);
    });
    test('failed verification → error screen', () {
      const s = AuthFailed(isNetwork: true);
      expect(redirect(s, '/patients'), '/auth-error');
      expect(redirect(s, '/auth-error'), isNull);
    });
  });
}
