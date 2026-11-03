import 'dart:convert';

import 'package:backend/config/app_config.dart';
import 'package:backend/core/logging/app_logger.dart';
import 'package:test/test.dart';

void main() {
  test('writes JSON lines and redacts sensitive fields', () {
    final lines = <String>[];
    AppLogger(
      sink: lines.add,
      clock: () => DateTime.utc(2026, 1, 1),
    ).info('event', {'patientPhone': '9876543210', 'count': 3});
    final entry = jsonDecode(lines.single) as Map;
    expect(entry['severity'], 'INFO');
    expect(entry['time'], '2026-01-01T00:00:00.000Z');
    expect(entry['patientPhone'], '[REDACTED]');
    expect(entry['count'], 3);
  });

  test('respects the minimum level', () {
    final lines = <String>[];
    AppLogger(minLevel: LogLevel.warning, sink: lines.add)
      ..info('skip')
      ..error('keep');
    expect(lines, hasLength(1));
  });
}
