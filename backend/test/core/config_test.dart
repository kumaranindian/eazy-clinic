import 'package:backend/config/app_config.dart';
import 'package:test/test.dart';
import 'package:utilities/utilities.dart';

void main() {
  test('dev config needs only APP_ENV and applies defaults', () {
    final c = AppConfig.fromEnvironment({'APP_ENV': 'dev'});
    expect(c.port, 8080);
    expect(c.logLevel, LogLevel.info);
    expect(c.corsAllowedOrigins, isEmpty);
    expect(c.firebaseProjectId, isNull);
  });

  test('APP_ENV is mandatory and strictly validated', () {
    expect(
      () => AppConfig.fromEnvironment({}),
      throwsA(isA<ConfigurationException>()),
    );
    expect(
      () => AppConfig.fromEnvironment({'APP_ENV': 'prod'}),
      throwsA(isA<ConfigurationException>()),
    );
  });

  test('staging and production require FIREBASE_PROJECT_ID', () {
    for (final env in ['staging', 'production']) {
      expect(
        () => AppConfig.fromEnvironment({'APP_ENV': env}),
        throwsA(isA<ConfigurationException>()),
      );
      expect(
        AppConfig.fromEnvironment({
          'APP_ENV': env,
          'FIREBASE_PROJECT_ID': 'p',
        }).firebaseProjectId,
        'p',
      );
    }
  });

  test('invalid port, log level and wildcard CORS are all reported', () {
    try {
      AppConfig.fromEnvironment({
        'APP_ENV': 'dev',
        'PORT': '99999',
        'LOG_LEVEL': 'loud',
        'CORS_ALLOWED_ORIGINS': '*',
      });
      fail('expected ConfigurationException');
    } on ConfigurationException catch (e) {
      expect(e.message, contains('PORT'));
      expect(e.message, contains('LOG_LEVEL'));
      expect(e.message, contains('CORS_ALLOWED_ORIGINS'));
    }
  });

  test('non-dev CORS origins must be https', () {
    expect(
      () => AppConfig.fromEnvironment({
        'APP_ENV': 'staging',
        'FIREBASE_PROJECT_ID': 'p',
        'CORS_ALLOWED_ORIGINS': 'http://clinic.example.com',
      }),
      throwsA(isA<ConfigurationException>()),
    );
  });
}
