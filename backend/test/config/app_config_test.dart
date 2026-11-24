import 'package:backend/config/app_config.dart';
import 'package:test/test.dart';
import 'package:utilities/utilities.dart';

/// Release gate: production configuration fails closed.
void main() {
  Map<String, String> prod([Map<String, String> extra = const {}]) => {
    'APP_ENV': 'production',
    'FIREBASE_PROJECT_ID': 'example-prod-project',
    'STORAGE_BUCKET': 'example-prod-bucket',
    'CORS_ALLOWED_ORIGINS': 'https://app.example.com',
    ...extra,
  };

  String problems(Map<String, String> env) {
    try {
      AppConfig.fromEnvironment(env);
    } on ConfigurationException catch (e) {
      return e.message;
    }
    return '';
  }

  test('a complete production configuration is accepted', () {
    final c = AppConfig.fromEnvironment(prod());
    expect(c.environment, AppEnvironment.production);
    expect(c.authCheckRevoked, isTrue);
    expect(c.fcmEnabled, isFalse, reason: 'push is opt-in');
  });

  test('DEPLOYMENT_REGION is optional, informational and validated', () {
    expect(AppConfig.fromEnvironment(prod()).deploymentRegion, isNull);
    expect(
      AppConfig.fromEnvironment(
        prod({'DEPLOYMENT_REGION': 'asia-south1'}),
      ).deploymentRegion,
      'asia-south1',
    );
    for (final bad in ['Asia South', 'x', 'asia_south1', '-bad-region-']) {
      expect(
        problems(prod({'DEPLOYMENT_REGION': bad})),
        contains('DEPLOYMENT_REGION'),
        reason: bad,
      );
    }
  });

  test('production refuses to start without its essentials', () {
    expect(
      problems(prod({'FIREBASE_PROJECT_ID': ''})),
      contains('FIREBASE_PROJECT_ID'),
    );
    expect(problems(prod({'STORAGE_BUCKET': ''})), contains('STORAGE_BUCKET'));
    expect(problems({'APP_ENV': 'production'}), isNotEmpty);
    expect(
      problems({}),
      contains('APP_ENV'),
      reason: 'no silent default environment',
    );
  });

  test('production origins must be https, exact and not local', () {
    expect(
      problems(prod({'CORS_ALLOWED_ORIGINS': '*'})),
      contains('wildcards'),
    );
    expect(
      problems(prod({'CORS_ALLOWED_ORIGINS': 'http://app.example.com'})),
      contains('https'),
    );
    expect(
      problems(prod({'CORS_ALLOWED_ORIGINS': 'https://localhost:3000'})),
      contains('local address'),
    );
    expect(
      problems(prod({'CORS_ALLOWED_ORIGINS': 'https://127.0.0.1'})),
      contains('local address'),
    );
  });

  test('revocation checks cannot be switched off outside dev', () {
    expect(
      problems(prod({'AUTH_CHECK_REVOKED': 'false'})),
      contains('AUTH_CHECK_REVOKED'),
    );
    expect(
      problems({
        'APP_ENV': 'staging',
        'FIREBASE_PROJECT_ID': 'x',
        'STORAGE_BUCKET': 'bucket-x',
        'AUTH_CHECK_REVOKED': 'false',
      }),
      contains('AUTH_CHECK_REVOKED'),
    );
  });

  test('flags and ports are validated', () {
    expect(
      problems(prod({'NOTIFICATIONS_FCM_ENABLED': 'maybe'})),
      contains('NOTIFICATIONS_FCM_ENABLED'),
    );
    expect(problems(prod({'PORT': '70000'})), contains('PORT'));
    expect(problems(prod({'LOG_LEVEL': 'verbose'})), contains('LOG_LEVEL'));
    expect(
      problems(prod({'TRUST_FORWARDED_FOR': 'yes'})),
      contains('TRUST_FORWARDED_FOR'),
    );
  });

  test('the error text never echoes secret-looking values', () {
    final msg = problems(prod({'STORAGE_BUCKET': 'Bad Bucket With Spaces'}));
    expect(msg, contains('STORAGE_BUCKET'));
  });
}
