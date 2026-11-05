import 'package:utilities/utilities.dart';

/// Backend configuration, read from environment variables.
///
/// No secrets are defined here. Service-account credentials are supplied to
/// the runtime by the hosting platform (Application Default Credentials) and
/// are never read from the repository.
class AppConfig {
  const AppConfig._({
    required this.environment,
    required this.port,
    required this.logLevel,
    required this.corsAllowedOrigins,
    required this.firebaseProjectId,
    required this.authCheckRevoked,
    required this.trustForwardedFor,
    required this.storageBucket,
    required this.fcmEnabled,
    required this.notificationWorkerEnabled,
  });

  /// Builds a validated config from [env] (normally `Platform.environment`).
  /// Throws [ConfigurationException] listing every problem found.
  factory AppConfig.fromEnvironment(Map<String, String> env) {
    final problems = <String>[];

    AppEnvironment? environment;
    try {
      environment = AppEnvironment.parse(env['APP_ENV']);
    } on FormatException catch (e) {
      problems.add(e.message);
    }

    final port = int.tryParse(env['PORT'] ?? '8080');
    if (port == null || port < 1 || port > 65535) {
      problems.add('PORT must be an integer between 1 and 65535.');
    }

    final logLevel = LogLevel.tryParse(env['LOG_LEVEL'] ?? 'info');
    if (logLevel == null) {
      problems.add('LOG_LEVEL must be one of: debug, info, warning, error.');
    }

    final origins = (env['CORS_ALLOWED_ORIGINS'] ?? '')
        .split(',')
        .map((o) => o.trim())
        .where((o) => o.isNotEmpty)
        .toList();
    for (final origin in origins) {
      final uri = Uri.tryParse(origin);
      if (origin == '*' || uri == null || !uri.hasAuthority) {
        problems.add(
          'CORS_ALLOWED_ORIGINS entry "$origin" is not a valid origin '
          '(wildcards are not allowed).',
        );
      } else if (environment == AppEnvironment.production &&
          const [
            'localhost',
            '127.0.0.1',
            '10.0.2.2',
            '::1',
          ].contains(uri.host)) {
        problems.add(
          'CORS_ALLOWED_ORIGINS entry "$origin" is a local address and is '
          'not allowed in production.',
        );
      } else if (environment != null &&
          environment != AppEnvironment.dev &&
          uri.scheme != 'https') {
        problems.add(
          'CORS_ALLOWED_ORIGINS entry "$origin" must use https in '
          '${environment.wireName}.',
        );
      }
    }

    final projectId = env['FIREBASE_PROJECT_ID']?.trim();
    if (environment != null &&
        environment != AppEnvironment.dev &&
        (projectId == null || projectId.isEmpty)) {
      problems.add(
        'FIREBASE_PROJECT_ID is required in ${environment.wireName}.',
      );
    }

    final checkRevokedRaw = (env['AUTH_CHECK_REVOKED'] ?? 'true').toLowerCase();
    if (checkRevokedRaw != 'true' && checkRevokedRaw != 'false') {
      problems.add('AUTH_CHECK_REVOKED must be "true" or "false".');
    }
    final checkRevoked = checkRevokedRaw != 'false';
    if (!checkRevoked &&
        environment != null &&
        environment != AppEnvironment.dev) {
      problems.add(
        'AUTH_CHECK_REVOKED=false is only allowed in dev '
        '(revocation checks are mandatory in ${environment.wireName}).',
      );
    }
    final trustRaw = (env['TRUST_FORWARDED_FOR'] ?? 'false').toLowerCase();
    if (trustRaw != 'true' && trustRaw != 'false') {
      problems.add('TRUST_FORWARDED_FOR must be "true" or "false".');
    }

    final bucket = env['STORAGE_BUCKET']?.trim();
    if (bucket != null &&
        bucket.isNotEmpty &&
        !RegExp(r'^[a-z0-9][a-z0-9._\-]{2,221}$').hasMatch(bucket)) {
      problems.add('STORAGE_BUCKET is not a valid bucket name.');
    }
    if (environment != null &&
        environment != AppEnvironment.dev &&
        (bucket == null || bucket.isEmpty)) {
      problems.add('STORAGE_BUCKET is required in ${environment.wireName}.');
    }

    bool flag(String name, bool fallback) {
      final raw = (env[name] ?? '$fallback').toLowerCase();
      if (raw != 'true' && raw != 'false') {
        problems.add('$name must be "true" or "false".');
      }
      return raw == 'true';
    }

    final fcmEnabled = flag('NOTIFICATIONS_FCM_ENABLED', false);
    final worker = flag('NOTIFICATIONS_WORKER_ENABLED', true);

    if (problems.isNotEmpty) {
      throw ConfigurationException(problems.join(' '));
    }

    return AppConfig._(
      environment: environment!,
      port: port!,
      logLevel: logLevel!,
      corsAllowedOrigins: origins,
      firebaseProjectId: (projectId == null || projectId.isEmpty)
          ? null
          : projectId,
      authCheckRevoked: checkRevoked,
      trustForwardedFor: trustRaw == 'true',
      storageBucket: (bucket == null || bucket.isEmpty) ? null : bucket,
      fcmEnabled: fcmEnabled,
      notificationWorkerEnabled: worker,
    );
  }

  final AppEnvironment environment;
  final int port;
  final LogLevel logLevel;

  /// Exact origins allowed to call the API from a browser. Never `*`.
  final List<String> corsAllowedOrigins;

  /// Firebase project of this environment. Dev/staging/production use
  /// different projects. Required to verify ID tokens; when absent (dev only)
  /// every protected endpoint answers 503.
  final String? firebaseProjectId;

  /// Check each ID token against Firebase revocation state and the disabled
  /// flag. Mandatory outside dev.
  final bool authCheckRevoked;

  /// Behind a trusted proxy (Cloud Run), use the last `X-Forwarded-For` entry
  /// as the client address for rate limiting.
  final bool trustForwardedFor;

  /// Private Cloud Storage bucket of this environment (clinic logos). When
  /// absent (dev only) logo endpoints answer 503.
  final String? storageBucket;

  /// Whether push messages are sent through FCM (needs the messaging scope on
  /// the service account). Off by default: deliveries then report
  /// `configuration_required` instead of pretending to send.
  final bool fcmEnabled;

  /// Whether this instance runs the notification worker (reminders, outbox,
  /// retries) on a timer.
  final bool notificationWorkerEnabled;
}

/// Log severity, ordered from most to least verbose.
enum LogLevel {
  debug,
  info,
  warning,
  error;

  static LogLevel? tryParse(String value) {
    for (final level in values) {
      if (level.name == value.toLowerCase()) return level;
    }
    return null;
  }
}
