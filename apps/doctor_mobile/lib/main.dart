import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:utilities/utilities.dart';

import 'app.dart';
import 'core/config/client_config_provider.dart';

/// Build-time configuration, supplied with
/// `--dart-define-from-file=../../environments/<env>/app.json`.
/// See environments/README.md. Contains no secrets.
const String _appEnv = String.fromEnvironment('APP_ENV');
const String _apiBaseUrl = String.fromEnvironment('API_BASE_URL');
const String _fbApiKey = String.fromEnvironment('FIREBASE_API_KEY');
const String _fbAppId = String.fromEnvironment('FIREBASE_APP_ID');
const String _fbSenderId = String.fromEnvironment(
  'FIREBASE_MESSAGING_SENDER_ID',
);
const String _fbProjectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
const String _fbAuthDomain = String.fromEnvironment('FIREBASE_AUTH_DOMAIN');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final ClientConfig config;
  final FirebaseClientConfig firebase;
  try {
    config = ClientConfig.validated(appEnv: _appEnv, apiBaseUrl: _apiBaseUrl);
    firebase = FirebaseClientConfig.validated(
      apiKey: _fbApiKey,
      appId: _fbAppId,
      messagingSenderId: _fbSenderId,
      projectId: _fbProjectId,
      authDomain: _fbAuthDomain,
    );
  } on ConfigurationException catch (e) {
    // Fail loudly and safely: a misconfigured build must never silently talk
    // to the wrong environment.
    runApp(ConfigurationErrorApp(message: e.message));
    return;
  }

  await initializeFirebase(firebase);
  final authRepository = FirebaseAuthRepository();

  runApp(
    ProviderScope(
      overrides: [
        clientConfigProvider.overrideWithValue(config),
        authRepositoryProvider.overrideWithValue(authRepository),
        authApiProvider.overrideWithValue(
          DioAuthApi(baseUrl: config.apiBaseUrl, auth: authRepository),
        ),
        appAudienceProvider.overrideWithValue(AppAudience.doctor),
        authUiConfigProvider.overrideWithValue(
          const AuthUiConfig(
            appName: 'Doctor Workspace',
            audienceLabel: 'Sign in to your doctor workspace',
            registrationEnabled: false,
            registrationNote: null,
            deniedHint:
                'Your account does not have a doctor role at any clinic yet. Ask your clinic administrator to invite you.',
          ),
        ),
      ],
      child: const EazyClinicApp(),
    ),
  );
}
