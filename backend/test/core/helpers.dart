import 'package:backend/app.dart';
import 'package:backend/config/app_config.dart';
import 'package:backend/core/logging/app_logger.dart';
import 'package:shelf/shelf.dart';

AppConfig testConfig([Map<String, String> overrides = const {}]) =>
    AppConfig.fromEnvironment({'APP_ENV': 'dev', ...overrides});

/// Builds the real app with a capturing logger.
({Handler handler, List<String> logs}) buildTestApp([AppConfig? config]) {
  final logs = <String>[];
  final handler = buildApp(
    config ?? testConfig(),
    AppLogger(minLevel: LogLevel.debug, sink: logs.add),
  );
  return (handler: handler, logs: logs);
}
