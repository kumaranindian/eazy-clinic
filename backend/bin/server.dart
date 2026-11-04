import 'dart:async';
import 'dart:io';

import 'package:backend/app.dart';
import 'package:backend/bootstrap.dart';
import 'package:backend/config/app_config.dart';
import 'package:backend/core/logging/app_logger.dart';
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
  final modules = await buildProductionModules(config, logger);
  final server = await shelf_io.serve(
    buildApp(
      config,
      logger,
      auth: modules.auth,
      platform: modules.platform,
      clinic: modules.clinic,
    ),
    InternetAddress.anyIPv4,
    config.port,
  );
  logger.info('server_started', {
    'port': server.port,
    'environment': config.environment.wireName,
  });

  // Notification worker: reminders, outbox processing and delivery retries.
  // There is no other scheduler in the project, so this uses a plain timer in
  // the server process. A pass never overlaps the previous one, and passes
  // are safe to run on several instances (every claim is transactional).
  Timer? worker;
  final hub = modules.clinic?.hub;
  if (hub != null && config.notificationWorkerEnabled) {
    var running = false;
    worker = Timer.periodic(const Duration(seconds: 60), (_) async {
      if (running) return;
      running = true;
      try {
        await hub.tick();
      } on Object catch (e) {
        logger.error('notification_worker_failed', {
          'exceptionType': e.runtimeType.toString(),
        });
      } finally {
        running = false;
      }
    });
    logger.info('notification_worker_started', {'intervalSeconds': 60});
  }

  // Graceful shutdown on SIGINT / SIGTERM (Cloud Run sends SIGTERM).
  Future<void> shutdown(ProcessSignal signal) async {
    logger.info('server_stopping', {'signal': signal.toString()});
    worker?.cancel();
    await server.close(force: false);
    exit(0);
  }

  ProcessSignal.sigint.watch().listen(shutdown);
  if (!Platform.isWindows) ProcessSignal.sigterm.watch().listen(shutdown);
}
