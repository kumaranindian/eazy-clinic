import 'dart:convert';

import 'package:utilities/utilities.dart';

import '../../config/app_config.dart';

/// Structured JSON logger (one object per line, stdout), ready for Cloud
/// Logging. Every field map passes through [redact], so personal and clinical
/// values cannot reach logs even by accident. Still: do not log them.
class AppLogger {
  AppLogger({
    this.minLevel = LogLevel.info,
    void Function(String line)? sink,
    DateTime Function()? clock,
  }) : _sink = sink ?? _stdoutSink,
       _clock = clock ?? DateTime.now;

  final LogLevel minLevel;
  final void Function(String line) _sink;
  final DateTime Function() _clock;

  static void _stdoutSink(String line) {
    // ignore: avoid_print
    print(line);
  }

  void debug(String message, [Map<String, Object?> fields = const {}]) =>
      _log(LogLevel.debug, message, fields);
  void info(String message, [Map<String, Object?> fields = const {}]) =>
      _log(LogLevel.info, message, fields);
  void warning(String message, [Map<String, Object?> fields = const {}]) =>
      _log(LogLevel.warning, message, fields);
  void error(String message, [Map<String, Object?> fields = const {}]) =>
      _log(LogLevel.error, message, fields);

  void _log(LogLevel level, String message, Map<String, Object?> fields) {
    if (level.index < minLevel.index) return;
    _sink(
      jsonEncode({
        'time': _clock().toUtc().toIso8601String(),
        'severity': level.name.toUpperCase(),
        'message': message,
        ...redact(fields),
      }),
    );
  }
}
