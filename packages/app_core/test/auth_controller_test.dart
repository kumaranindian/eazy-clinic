import 'package:api_contracts/api_contracts.dart';
import 'package:app_core/app_core.dart';
import 'package:common_models/common_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

ProviderContainer makeContainer(
  FakeAuthRepository repo,
  FakeAuthApi api, {
  AppAudience audience = AppAudience.patient,
}) {
  final c = ProviderContainer(
    overrides: [
      authRepositoryProvider.overrideWithValue(repo),
      authApiProvider.overrideWithValue(api),
      appAudienceProvider.overrideWithValue(audience),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

Future<void> settle() => Future<void>.delayed(Duration.zero);

void main() {
  group('session restoration', () {
    test('starts resolving, then unauthenticated when no user', () async {
      final c = makeContainer(FakeAuthRepository(), FakeAuthApi());
      expect(c.read(authControllerProvider), isA<AuthResolving>());
      await settle();
      expect(c.read(authControllerProvider), isA<Unauthenticated>());
    });

    test('restored user is verified with the backend before access', () async {
      final api = FakeAuthApi()..sessions = [activeSession()];
      final c = makeContainer(FakeAuthRepository(initial: testUser), api);
      c.read(authControllerProvider);
      expect(
        c.read(authControllerProvider),
        isA<AuthResolving>(),
        reason: 'protected routes stay closed until the backend answers',
      );
      await settle();
      expect(c.read(authControllerProvider), isA<Authenticated>());
      expect(api.sessionCalls, 1);
      expect(api.provisionCalls, 0, reason: 'restore is not a login');
    });

    test('unprovisioned account is provisioned once', () async {
      final api = FakeAuthApi()
        ..sessions = [
          const AuthApiException(code: ApiErrorCode.accountNotProvisioned),
        ];
      final c = makeContainer(FakeAuthRepository(initial: testUser), api);
      c.read(authControllerProvider);
      await settle();
      expect(api.provisionCalls, 1);
      expect(c.read(authControllerProvider), isA<Authenticated>());
    });

    test('revoked session signs the user out with a notice', () async {
      final repo = FakeAuthRepository(initial: testUser);
      final api = FakeAuthApi()
        ..sessions = [
          const AuthApiException(code: ApiErrorCode.sessionRevoked),
        ];
      final c = makeContainer(repo, api);
      c.read(authControllerProvider);
      await settle();
      final state = c.read(authControllerProvider);
      expect(state, isA<Unauthenticated>());
      expect((state as Unauthenticated).notice, isNotNull);
      expect(repo.signOutCalls, 1);
    });

    test('network failure keeps the user and allows retry', () async {
      final api = FakeAuthApi()
        ..sessions = [const AuthApiException(isNetwork: true), activeSession()];
      final c = makeContainer(FakeAuthRepository(initial: testUser), api);
      c.read(authControllerProvider);
      await settle();
      expect(c.read(authControllerProvider), isA<AuthFailed>());
      await c.read(authControllerProvider.notifier).retry();
      expect(c.read(authControllerProvider), isA<Authenticated>());
    });

    test('suspended account is denied', () async {
      final api = FakeAuthApi()
        ..sessions = [activeSession(status: AccountStatus.suspended)];
      final c = makeContainer(FakeAuthRepository(initial: testUser), api);
      c.read(authControllerProvider);
      await settle();
      final s = c.read(authControllerProvider);
      expect(s, isA<AccessDenied>());
      expect((s as AccessDenied).reason, AccessDeniedReason.suspended);
    });

    test('disabled account is denied', () async {
      final api = FakeAuthApi()
        ..sessions = [
          const AuthApiException(code: ApiErrorCode.accountDisabled),
        ];
      final c = makeContainer(FakeAuthRepository(initial: testUser), api);
      c.read(authControllerProvider);
      await settle();
      expect(
        (c.read(authControllerProvider) as AccessDenied).reason,
        AccessDeniedReason.disabled,
      );
    });

    test('pending account is asked to verify email', () async {
      final api = FakeAuthApi()
        ..sessions = [activeSession(status: AccountStatus.pending)];
      final c = makeContainer(FakeAuthRepository(initial: testUser), api);
      c.read(authControllerProvider);
      await settle();
      expect(
        (c.read(authControllerProvider) as AccessDenied).reason,
        AccessDeniedReason.emailUnverified,
      );
    });

    test('active account without app access is not authorized', () async {
      final api = FakeAuthApi()..sessions = [activeSession()];
      final c = makeContainer(
        FakeAuthRepository(initial: testUser),
        api,
        audience: AppAudience.clinicWeb,
      );
      c.read(authControllerProvider);
      await settle();
      expect(
        (c.read(authControllerProvider) as AccessDenied).reason,
        AccessDeniedReason.notAuthorized,
      );
    });
  });

  group('sign in / register', () {
    test('successful sign in provisions and authenticates', () async {
      final repo = FakeAuthRepository();
      final api = FakeAuthApi()..provisionResult = activeSession();
      final c = makeContainer(repo, api);
      c.read(authControllerProvider);
      await settle();
      final failure = await c
          .read(authControllerProvider.notifier)
          .signIn(email: 'a@b.co', password: 'secret123');
      expect(failure, isNull);
      expect(c.read(authControllerProvider), isA<Authenticated>());
      expect(api.provisionCalls, 1);
    });

    test(
      'invalid credentials: failure returned, stays unauthenticated',
      () async {
        final repo = FakeAuthRepository()
          ..signInFailure = const AuthFailure(
            AuthFailureCode.invalidCredentials,
          );
        final c = makeContainer(repo, FakeAuthApi());
        c.read(authControllerProvider);
        await settle();
        final failure = await c
            .read(authControllerProvider.notifier)
            .signIn(email: 'a@b.co', password: 'bad');
        expect(failure?.code, AuthFailureCode.invalidCredentials);
        expect(c.read(authControllerProvider), isA<Unauthenticated>());
      },
    );

    test('registration with unverified email lands on verification', () async {
      final api = FakeAuthApi()
        ..provisionResult = activeSession(status: AccountStatus.pending);
      final c = makeContainer(FakeAuthRepository(), api);
      c.read(authControllerProvider);
      await settle();
      final failure = await c
          .read(authControllerProvider.notifier)
          .register(
            displayName: 'New User',
            email: 'n@b.co',
            password: 'secret123',
          );
      expect(failure, isNull);
      final s = c.read(authControllerProvider) as AccessDenied;
      expect(s.reason, AccessDeniedReason.emailUnverified);
    });

    test('registering as "doctor" style fields grants nothing', () async {
      // The controller API has no role or tenant parameter at all; access
      // comes only from the backend session, which is empty for new users.
      final api = FakeAuthApi()
        ..provisionResult = activeSession(status: AccountStatus.active);
      final c = makeContainer(
        FakeAuthRepository(),
        api,
        audience: AppAudience.doctor,
      );
      c.read(authControllerProvider);
      await settle();
      await c
          .read(authControllerProvider.notifier)
          .register(
            displayName: 'Dr Fake',
            email: 'd@b.co',
            password: 'abc12345',
          );
      expect(
        (c.read(authControllerProvider) as AccessDenied).reason,
        AccessDeniedReason.notAuthorized,
      );
    });

    test(
      'backend dead-session error during sign in closes the session',
      () async {
        final repo = FakeAuthRepository();
        final api = FakeAuthApi()
          ..provisionResult = const AuthApiException(
            code: ApiErrorCode.sessionRevoked,
          );
        final c = makeContainer(repo, api);
        c.read(authControllerProvider);
        await settle();
        await c
            .read(authControllerProvider.notifier)
            .signIn(email: 'a@b.co', password: 'secret123');
        await settle();
        expect(c.read(authControllerProvider), isA<Unauthenticated>());
      },
    );
  });

  group('sign out', () {
    Future<(ProviderContainer, FakeAuthRepository, FakeAuthApi)>
    signedIn() async {
      final repo = FakeAuthRepository(initial: testUser);
      final api = FakeAuthApi()..sessions = [activeSession()];
      final c = makeContainer(repo, api);
      c.read(authControllerProvider);
      await settle();
      expect(c.read(authControllerProvider), isA<Authenticated>());
      return (c, repo, api);
    }

    test('clears authenticated state and calls the backend', () async {
      final (c, repo, api) = await signedIn();
      final failure = await c.read(authControllerProvider.notifier).signOut();
      expect(failure, isNull);
      expect(c.read(authControllerProvider), isA<Unauthenticated>());
      expect(repo.signOutCalls, 1);
      expect(api.logoutCalls, 1);
    });

    test('backend logout failure still signs out', () async {
      final (c, repo, api) = await signedIn();
      api.logoutFails = true;
      await c.read(authControllerProvider.notifier).signOut();
      expect(c.read(authControllerProvider), isA<Unauthenticated>());
      expect(repo.signOutCalls, 1);
    });

    test(
      'identity provider failure is reported but local state is cleared',
      () async {
        final (c, repo, _) = await signedIn();
        repo.signOutFailure = const AuthFailure(AuthFailureCode.network);
        final failure = await c.read(authControllerProvider.notifier).signOut();
        expect(failure?.code, AuthFailureCode.network);
        expect(c.read(authControllerProvider), isA<Unauthenticated>());
      },
    );

    test('allDevices is forwarded to the backend', () async {
      final (c, _, api) = await signedIn();
      await c.read(authControllerProvider.notifier).signOut(allDevices: true);
      expect(api.logoutAllDevices, isTrue);
    });
  });

  group('password reset', () {
    test('sends the reset email', () async {
      final repo = FakeAuthRepository();
      final c = makeContainer(repo, FakeAuthApi());
      final failure = await c
          .read(authControllerProvider.notifier)
          .sendPasswordReset('a@b.co');
      expect(failure, isNull);
      expect(repo.resetRequests, ['a@b.co']);
    });

    test('surfaces rate limiting', () async {
      final repo = FakeAuthRepository()
        ..resetFailure = const AuthFailure(AuthFailureCode.tooManyRequests);
      final c = makeContainer(repo, FakeAuthApi());
      final failure = await c
          .read(authControllerProvider.notifier)
          .sendPasswordReset('a@b.co');
      expect(failure?.code, AuthFailureCode.tooManyRequests);
    });
  });

  group('AppAudience', () {
    test('clinic web needs a platform role or clinic staff membership', () {
      expect(AppAudience.clinicWeb.admits(activeSession()), isFalse);
      expect(
        AppAudience.clinicWeb.admits(
          activeSession(platformRole: PlatformRole.superAdmin),
        ),
        isTrue,
      );
      expect(
        AppAudience.clinicWeb.admits(
          activeSession(
            memberships: [
              const MembershipSummaryDto(tenantId: 't', role: 'receptionist'),
            ],
          ),
        ),
        isTrue,
      );
    });

    test('unknown membership roles are denied', () {
      expect(
        AppAudience.clinicWeb.admits(
          activeSession(
            memberships: [
              const MembershipSummaryDto(tenantId: 't', role: 'wizard'),
            ],
          ),
        ),
        isFalse,
      );
    });

    test('doctor app requires the doctor role', () {
      final receptionist = activeSession(
        memberships: [
          const MembershipSummaryDto(tenantId: 't', role: 'receptionist'),
        ],
      );
      expect(AppAudience.doctor.admits(receptionist), isFalse);
      final doctor = activeSession(
        memberships: [
          const MembershipSummaryDto(tenantId: 't', role: 'doctor'),
        ],
      );
      expect(AppAudience.doctor.admits(doctor), isTrue);
    });

    test('inactive accounts are never admitted', () {
      for (final audience in AppAudience.values) {
        expect(
          audience.admits(activeSession(status: AccountStatus.suspended)),
          isFalse,
        );
      }
    });
  });
}
