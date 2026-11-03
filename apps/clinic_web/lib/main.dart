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

void main() {
  final ClientConfig config;
  try {
    config = ClientConfig.validated(appEnv: _appEnv, apiBaseUrl: _apiBaseUrl);
  } on ConfigurationException catch (e) {
    // Fail loudly and safely: a misconfigured build must never silently talk
    // to the wrong environment.
    runApp(ConfigurationErrorApp(message: e.message));
    return;
  }

  runApp(
    ProviderScope(
      overrides: [clientConfigProvider.overrideWithValue(config)],
      child: const EazyClinicApp(),
    ),
  );
}
