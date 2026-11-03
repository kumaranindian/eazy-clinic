import 'package:test/test.dart';
import 'package:utilities/utilities.dart';

void main() {
  firebaseClientConfigTests();
  group('AppEnvironment', () {
    test('parses known values and rejects unknown ones', () {
      expect(AppEnvironment.parse('dev'), AppEnvironment.dev);
      expect(AppEnvironment.parse('production').isProduction, isTrue);
      expect(() => AppEnvironment.parse('prod'), throwsFormatException);
      expect(() => AppEnvironment.parse(null), throwsFormatException);
    });
  });

  group('ClientConfig.validated', () {
    test('accepts http localhost in dev and strips trailing slash', () {
      final config = ClientConfig.validated(
        appEnv: 'dev',
        apiBaseUrl: 'http://localhost:8080/',
      );
      expect(config.apiBaseUrl, 'http://localhost:8080');
      expect(config.environment, AppEnvironment.dev);
    });

    test('requires https outside dev', () {
      expect(
        () => ClientConfig.validated(
          appEnv: 'staging',
          apiBaseUrl: 'http://staging.example.com',
        ),
        throwsA(isA<ConfigurationException>()),
      );
    });

    test('rejects loopback in production', () {
      expect(
        () => ClientConfig.validated(
          appEnv: 'production',
          apiBaseUrl: 'https://localhost',
        ),
        throwsA(isA<ConfigurationException>()),
      );
    });

    test('rejects missing, malformed and unknown values', () {
      expect(
        () => ClientConfig.validated(appEnv: 'dev', apiBaseUrl: ''),
        throwsA(isA<ConfigurationException>()),
      );
      expect(
        () => ClientConfig.validated(appEnv: 'qa', apiBaseUrl: 'https://x.io'),
        throwsA(isA<ConfigurationException>()),
      );
      expect(
        () => ClientConfig.validated(appEnv: 'dev', apiBaseUrl: 'ftp://x.io'),
        throwsA(isA<ConfigurationException>()),
      );
    });
  });

  group('redact', () {
    test('masks sensitive keys, including nested ones', () {
      final out = redact({
        'method': 'POST',
        'Authorization': 'Bearer abc',
        'body': {'patientPhone': '9876543210', 'status': 'ok'},
        'items': [
          {'diagnosis': 'x', 'id': 1},
        ],
      });
      expect(out['method'], 'POST');
      expect(out['Authorization'], redactedValue);
      expect((out['body']! as Map)['patientPhone'], redactedValue);
      expect((out['body']! as Map)['status'], 'ok');
      expect(
        ((out['items']! as List).single as Map)['diagnosis'],
        redactedValue,
      );
      expect(((out['items']! as List).single as Map)['id'], 1);
    });
  });
}

void firebaseClientConfigTests() {
  group('FirebaseClientConfig', () {
    test('accepts complete configuration', () {
      final c = FirebaseClientConfig.validated(
        apiKey: 'k',
        appId: 'a',
        messagingSenderId: 's',
        projectId: 'p',
        authDomain: 'p.firebaseapp.com',
      );
      expect(c.projectId, 'p');
      expect(c.authDomain, 'p.firebaseapp.com');
    });

    test('reports every missing or placeholder value', () {
      expect(
        () => FirebaseClientConfig.validated(
          apiKey: '',
          appId: 'REPLACE_WITH_APP_ID',
          messagingSenderId: 's',
          projectId: '',
        ),
        throwsA(
          isA<ConfigurationException>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('FIREBASE_API_KEY'),
              contains('FIREBASE_APP_ID'),
              contains('FIREBASE_PROJECT_ID'),
              isNot(contains('MESSAGING')),
            ),
          ),
        ),
      );
    });
  });
}
