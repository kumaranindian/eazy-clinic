import 'app_environment.dart';

/// Thrown when application configuration is missing or unsafe.
class ConfigurationException implements Exception {
  const ConfigurationException(this.message);

  final String message;

  @override
  String toString() => 'ConfigurationException: $message';
}

/// Runtime configuration for a Flutter app, supplied at build time with
/// `--dart-define-from-file` (see environments/*/app.example.json).
///
/// Contains no secrets: Firebase client identifiers are not secrets, but
/// service-account keys and Razorpay secrets must never appear here.
class ClientConfig {
  const ClientConfig._({required this.environment, required this.apiBaseUrl});

  /// Builds a validated config. Throws [ConfigurationException] when invalid.
  factory ClientConfig.validated({
    required String appEnv,
    required String apiBaseUrl,
  }) {
    final AppEnvironment environment;
    try {
      environment = AppEnvironment.parse(appEnv);
    } on FormatException catch (e) {
      throw ConfigurationException(e.message);
    }

    final uri = Uri.tryParse(apiBaseUrl);
    if (uri == null || !uri.hasAuthority || uri.host.isEmpty) {
      throw const ConfigurationException(
        'API_BASE_URL must be an absolute http(s) URL.',
      );
    }
    if (uri.scheme != 'https' && uri.scheme != 'http') {
      throw const ConfigurationException(
        'API_BASE_URL must use http or https.',
      );
    }
    final isLoopback =
        uri.host == 'localhost' ||
        uri.host == '127.0.0.1' ||
        uri.host == '10.0.2.2';
    if (environment != AppEnvironment.dev && uri.scheme != 'https') {
      throw ConfigurationException(
        'API_BASE_URL must use https in ${environment.wireName}.',
      );
    }
    if (environment.isProduction && isLoopback) {
      throw const ConfigurationException(
        'API_BASE_URL must not point to a local address in production.',
      );
    }

    final normalized = apiBaseUrl.endsWith('/')
        ? apiBaseUrl.substring(0, apiBaseUrl.length - 1)
        : apiBaseUrl;
    return ClientConfig._(environment: environment, apiBaseUrl: normalized);
  }

  final AppEnvironment environment;

  /// Backend origin without a trailing slash and without `/api/v1`.
  final String apiBaseUrl;
}
