import 'client_config.dart';

/// Firebase client identifiers for one environment, supplied with
/// `--dart-define-from-file`. These identify the project; they are not
/// credentials. Each environment (dev/staging/production) uses its own
/// Firebase project, and each app (web/Android) its own `appId`.
class FirebaseClientConfig {
  const FirebaseClientConfig._({
    required this.apiKey,
    required this.appId,
    required this.messagingSenderId,
    required this.projectId,
    this.authDomain,
  });

  /// Throws [ConfigurationException] listing every missing or invalid value.
  factory FirebaseClientConfig.validated({
    required String apiKey,
    required String appId,
    required String messagingSenderId,
    required String projectId,
    String authDomain = '',
  }) {
    final problems = <String>[];
    void need(String name, String value) {
      final v = value.trim();
      if (v.isEmpty || v.startsWith('REPLACE_WITH')) {
        problems.add('$name is required.');
      }
    }

    need('FIREBASE_API_KEY', apiKey);
    need('FIREBASE_APP_ID', appId);
    need('FIREBASE_MESSAGING_SENDER_ID', messagingSenderId);
    need('FIREBASE_PROJECT_ID', projectId);
    if (problems.isNotEmpty) {
      throw ConfigurationException(problems.join(' '));
    }
    return FirebaseClientConfig._(
      apiKey: apiKey.trim(),
      appId: appId.trim(),
      messagingSenderId: messagingSenderId.trim(),
      projectId: projectId.trim(),
      authDomain: authDomain.trim().isEmpty ? null : authDomain.trim(),
    );
  }

  final String apiKey;
  final String appId;
  final String messagingSenderId;
  final String projectId;

  /// Needed on web only.
  final String? authDomain;
}
