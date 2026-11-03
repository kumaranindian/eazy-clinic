import 'dart:io';

import 'package:backend/app.dart';
import 'package:backend/config/app_config.dart';
import 'package:backend/core/logging/app_logger.dart';
import 'package:backend/features/auth/auth_wiring.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:utilities/utilities.dart';

Future<void> main() async {
  final AppConfig config;
  try {
    config = AppConfig.fromEnvironment(Platform.environment);
  } on ConfigurationException catch (e) {
    stderr.writeln('Invalid configuration: ${e.message}');
    exit(78); // EX_CONFIG
  }

  final logger = AppLogger(minLevel: config.logLevel);
  final server = await shelf_io.serve(
    buildApp(
      config,
      logger,
      auth: await buildProductionAuthModule(config, logger),
    ),
    InternetAddress.anyIPv4,
    config.port,
  );
  logger.info('server_started', {
    'port': server.port,
    'environment': config.environment.wireName,
  });

  // Graceful shutdown on SIGINT / SIGTERM (Cloud Run sends SIGTERM).
  Future<void> shutdown(ProcessSignal signal) async {
    logger.info('server_stopping', {'signal': signal.toString()});
    await server.close(force: false);
    exit(0);
  }

  ProcessSignal.sigint.watch().listen(shutdown);
  if (!Platform.isWindows) ProcessSignal.sigterm.watch().listen(shutdown);
}
