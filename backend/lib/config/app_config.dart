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
    );
  }

  final AppEnvironment environment;
  final int port;
  final LogLevel logLevel;

  /// Exact origins allowed to call the API from a browser. Never `*`.
  final List<String> corsAllowedOrigins;

  /// Firebase project of this environment. Dev/staging/production use
  /// different projects. Not used until Phase 1.
  final String? firebaseProjectId;
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
