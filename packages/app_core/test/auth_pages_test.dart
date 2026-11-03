import 'package:api_contracts/api_contracts.dart';
import 'package:app_core/app_core.dart';
import 'package:common_models/common_models.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'support/fakes.dart';

class Harness {
  Harness({
    FakeAuthRepository? repo,
    FakeAuthApi? api,
    this.audience = AppAudience.patient,
    this.registration = true,
  }) : repo = repo ?? FakeAuthRepository(),
       api = api ?? FakeAuthApi();

  final FakeAuthRepository repo;
  final FakeAuthApi api;
  final AppAudience audience;
  final bool registration;
  late GoRouter router;

  Widget build() {
    return ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(repo),
        authApiProvider.overrideWithValue(api),
        appAudienceProvider.overrideWithValue(audience),
        authUiConfigProvider.overrideWithValue(
          AuthUiConfig(
            appName: 'Test',
            audienceLabel: 'Sign in to test',
            registrationEnabled: registration,
            registrationNote: 'Registration grants no access.',
          ),
        ),
        _routerProvider.overrideWith((ref) {
          router = buildAuthAwareRouter(
            ref,
            registrationEnabled: registration,
            publicPaths: const {},
            routes: [
              GoRoute(
                path: '/',
                builder: (c, s) => const Scaffold(body: Text('PROTECTED HOME')),
              ),
              GoRoute(
                path: '/patients/:id',
                builder: (c, s) =>
                    Scaffold(body: Text('PATIENT ${s.pathParameters['id']}')),
              ),
            ],
          );
          return router;
        }),
      ],
      child: Consumer(
        builder: (context, ref, _) => MaterialApp.router(
          theme: EcTheme.light(),
          routerConfig: ref.watch(_routerProvider),
        ),
      ),
    );
  }
}

final _routerProvider = Provider<GoRouter>((ref) => throw UnimplementedError());

void main() {
  setUp(() => TestWidgetsFlutterBinding.ensureInitialized());

  Future<void> pump(WidgetTester t, Harness h) async {
    t.view.physicalSize = const Size(900, 1600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(h.build());
    await t.pumpAndSettle();
  }

  Finder field(String label) => find.widgetWithText(TextFormField, label);

  group('startup & protected navigation', () {
    testWidgets('unauthenticated user is sent to login', (t) async {
      await pump(t, Harness());
      expect(find.text('Sign in'), findsWidgets);
      expect(find.text('PROTECTED HOME'), findsNothing);
    });

    testWidgets('protected content is never shown while resolving', (t) async {
      final repo = FakeAuthRepository(initial: testUser);
      final api = FakeAuthApi()..sessions = [activeSession()];
      final h = Harness(repo: repo, api: api);
      t.view.physicalSize = const Size(900, 1600);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(h.build());
      // First frame: backend has not answered yet.
      expect(find.text('PROTECTED HOME'), findsNothing);
      expect(find.text('Checking your session…'), findsOneWidget);
      await t.pumpAndSettle();
      expect(find.text('PROTECTED HOME'), findsOneWidget);
    });

    testWidgets('deep link survives login', (t) async {
      final h = Harness();
      await pump(t, h);
      h.router.go('/patients/42');
      await t.pumpAndSettle();
      expect(find.text('PATIENT 42'), findsNothing);
      expect(find.text('Sign in'), findsWidgets);

      h.api.provisionResult = activeSession();
      await t.enterText(field('Email'), 'a@b.co');
      await t.enterText(field('Password'), 'secret123');
      await t.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await t.pumpAndSettle();
      expect(find.text('PATIENT 42'), findsOneWidget);
    });

    testWidgets('logout closes protected screens', (t) async {
      final h = Harness(
        repo: FakeAuthRepository(initial: testUser),
        api: FakeAuthApi()..sessions = [activeSession()],
      );
      await pump(t, h);
      expect(find.text('PROTECTED HOME'), findsOneWidget);
      final container = ProviderScope.containerOf(
        t.element(find.text('PROTECTED HOME')),
      );
      await container.read(authControllerProvider.notifier).signOut();
      await t.pumpAndSettle();
      expect(find.text('PROTECTED HOME'), findsNothing);
      expect(find.text('Sign in'), findsWidgets);
      h.router.go('/');
      await t.pumpAndSettle();
      expect(find.text('PROTECTED HOME'), findsNothing);
    });

    testWidgets('authenticated user is moved off the login screen', (t) async {
      final h = Harness(
        repo: FakeAuthRepository(initial: testUser),
        api: FakeAuthApi()..sessions = [activeSession()],
      );
      await pump(t, h);
      h.router.go('/login');
      await t.pumpAndSettle();
      expect(find.text('PROTECTED HOME'), findsOneWidget);
    });

    testWidgets('suspended account sees the suspended screen', (t) async {
      final h = Harness(
        repo: FakeAuthRepository(initial: testUser),
        api: FakeAuthApi()
          ..sessions = [activeSession(status: AccountStatus.suspended)],
      );
      await pump(t, h);
      expect(find.text('Account suspended'), findsOneWidget);
      h.router.go('/');
      await t.pumpAndSettle();
      expect(find.text('PROTECTED HOME'), findsNothing);
    });

    testWidgets('unauthorized role sees access-not-available', (t) async {
      final h = Harness(
        audience: AppAudience.clinicWeb,
        repo: FakeAuthRepository(initial: testUser),
        api: FakeAuthApi()..sessions = [activeSession()],
      );
      await pump(t, h);
      expect(find.text('Access not available'), findsOneWidget);
      expect(find.text('PROTECTED HOME'), findsNothing);
    });

    testWidgets('network failure shows retry, not the app', (t) async {
      final h = Harness(
        repo: FakeAuthRepository(initial: testUser),
        api: FakeAuthApi()
          ..sessions = [
            const AuthApiException(isNetwork: true),
            activeSession(),
          ],
      );
      await pump(t, h);
      expect(find.text('You appear to be offline'), findsOneWidget);
      await t.tap(find.text('Try again'));
      await t.pumpAndSettle();
      expect(find.text('PROTECTED HOME'), findsOneWidget);
    });

    testWidgets('revoked session returns to login with a notice', (t) async {
      final h = Harness(
        repo: FakeAuthRepository(initial: testUser),
        api: FakeAuthApi()
          ..sessions = [
            const AuthApiException(code: ApiErrorCode.sessionRevoked),
          ],
      );
      await pump(t, h);
      expect(
        find.text('Your session has ended. Please sign in again.'),
        findsOneWidget,
      );
    });
  });

  group('login form', () {
    testWidgets('validates email and password', (t) async {
      await pump(t, Harness());
      await t.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await t.pump();
      expect(find.text('Email is required.'), findsOneWidget);
      expect(find.text('Password is required.'), findsOneWidget);
      await t.enterText(field('Email'), 'not-an-email');
      await t.pump();
      expect(find.text('Enter a valid email address.'), findsOneWidget);
    });

    testWidgets('password visibility toggle', (t) async {
      await pump(t, Harness());
      bool obscured() => t
          .widget<EditableText>(
            find.descendant(
              of: field('Password'),
              matching: find.byType(EditableText),
            ),
          )
          .obscureText;
      expect(obscured(), isTrue);
      await t.tap(find.byTooltip('Show password'));
      await t.pump();
      expect(obscured(), isFalse);
      await t.tap(find.byTooltip('Hide password'));
      await t.pump();
      expect(obscured(), isTrue);
    });

    testWidgets('invalid credentials show a generic error and clear password', (
      t,
    ) async {
      final repo = FakeAuthRepository()
        ..signInFailure = const AuthFailure(AuthFailureCode.invalidCredentials);
      await pump(t, Harness(repo: repo));
      await t.enterText(field('Email'), 'a@b.co');
      await t.enterText(field('Password'), 'wrongpass1');
      await t.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await t.pumpAndSettle();
      expect(
        find.text('The email or password is incorrect. Please try again.'),
        findsOneWidget,
      );
      expect(
        t
            .widget<EditableText>(
              find.descendant(
                of: field('Password'),
                matching: find.byType(EditableText),
              ),
            )
            .controller
            .text,
        isEmpty,
      );
    });

    testWidgets('network error message', (t) async {
      final repo = FakeAuthRepository()
        ..signInFailure = const AuthFailure(AuthFailureCode.network);
      await pump(t, Harness(repo: repo));
      await t.enterText(field('Email'), 'a@b.co');
      await t.enterText(field('Password'), 'secret123');
      await t.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await t.pumpAndSettle();
      expect(find.textContaining('Cannot reach the server'), findsOneWidget);
    });

    testWidgets('disabled account message', (t) async {
      final repo = FakeAuthRepository()
        ..signInFailure = const AuthFailure(AuthFailureCode.accountDisabled);
      await pump(t, Harness(repo: repo));
      await t.enterText(field('Email'), 'a@b.co');
      await t.enterText(field('Password'), 'secret123');
      await t.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await t.pumpAndSettle();
      expect(find.textContaining('has been disabled'), findsOneWidget);
    });

    testWidgets('registration link hidden when disabled', (t) async {
      await pump(t, Harness(registration: false));
      expect(find.text('Create account'), findsNothing);
    });
  });

  group('registration form', () {
    Future<void> open(WidgetTester t, Harness h) async {
      await pump(t, h);
      await t.tap(find.text('Create account'));
      await t.pumpAndSettle();
    }

    testWidgets('validates every field and terms', (t) async {
      await open(t, Harness());
      await t.tap(find.widgetWithText(FilledButton, 'Create account'));
      await t.pump();
      expect(find.text('Full name is required.'), findsOneWidget);
      expect(find.text('Email is required.'), findsOneWidget);
      expect(find.text('Password is required.'), findsOneWidget);
      expect(find.text('Please confirm your password.'), findsOneWidget);
      expect(
        find.text('You must accept the terms to continue.'),
        findsOneWidget,
      );
    });

    testWidgets('rejects weak password and mismatch', (t) async {
      await open(t, Harness());
      await t.enterText(field('Password'), 'short');
      await t.enterText(field('Confirm password'), 'different1');
      await t.pump();
      expect(
        find.text('Password must be at least 8 characters.'),
        findsOneWidget,
      );
      expect(find.text('Passwords do not match.'), findsOneWidget);
    });

    testWidgets('submits valid data and shows verification step', (t) async {
      final h = Harness()
        ..api.provisionResult = activeSession(status: AccountStatus.pending);
      await open(t, h);
      await t.enterText(field('Full name'), 'New Person');
      await t.enterText(field('Email'), 'new@b.co');
      await t.enterText(field('Password'), 'secret123');
      await t.enterText(field('Confirm password'), 'secret123');
      await t.tap(find.byType(Checkbox));
      await t.pump();
      await t.tap(find.widgetWithText(FilledButton, 'Create account'));
      await t.pumpAndSettle();
      expect(find.text('Verify your email'), findsOneWidget);
      expect(h.api.provisionCalls, 1);
    });

    testWidgets('email already in use is reported without leaking details', (
      t,
    ) async {
      final h = Harness(
        repo: FakeAuthRepository()
          ..registerFailure = const AuthFailure(AuthFailureCode.emailInUse),
      );
      await open(t, h);
      await t.enterText(field('Full name'), 'New Person');
      await t.enterText(field('Email'), 'new@b.co');
      await t.enterText(field('Password'), 'secret123');
      await t.enterText(field('Confirm password'), 'secret123');
      await t.tap(find.byType(Checkbox));
      await t.pump();
      await t.tap(find.widgetWithText(FilledButton, 'Create account'));
      await t.pumpAndSettle();
      expect(find.textContaining('may already exist'), findsOneWidget);
    });
  });

  group('forgot password', () {
    Future<void> open(WidgetTester t, Harness h) async {
      await pump(t, h);
      await t.tap(find.text('Forgot password?'));
      await t.pumpAndSettle();
    }

    testWidgets('validates email', (t) async {
      await open(t, Harness());
      await t.tap(find.widgetWithText(FilledButton, 'Send reset link'));
      await t.pump();
      expect(find.text('Email is required.'), findsOneWidget);
    });

    testWidgets('shows a neutral confirmation', (t) async {
      final h = Harness();
      await open(t, h);
      await t.enterText(field('Email'), 'a@b.co');
      await t.tap(find.widgetWithText(FilledButton, 'Send reset link'));
      await t.pumpAndSettle();
      expect(h.repo.resetRequests, ['a@b.co']);
      expect(find.textContaining('If an account exists'), findsOneWidget);
    });

    testWidgets('shows rate-limit errors', (t) async {
      final h = Harness(
        repo: FakeAuthRepository()
          ..resetFailure = const AuthFailure(AuthFailureCode.tooManyRequests),
      );
      await open(t, h);
      await t.enterText(field('Email'), 'a@b.co');
      await t.tap(find.widgetWithText(FilledButton, 'Send reset link'));
      await t.pumpAndSettle();
      expect(find.textContaining('Too many attempts'), findsOneWidget);
    });
  });
}
