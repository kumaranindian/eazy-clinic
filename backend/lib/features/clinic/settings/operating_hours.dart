import '../../platform/common/body_reader.dart';

/// Validation and normalisation of clinic / branch operating hours.
///
/// A day is `{open: bool, from: "HH:MM", to: "HH:MM", breaks: [{from, to}]}`.
/// Overnight operation is supported: when `to` is earlier than `from` the day
/// runs past midnight into the next calendar day (breaks are then measured from
/// the opening time). `from == to` is rejected. Times are local to the
/// explicitly stored time zone.
class HoursParser {
  HoursParser(this.reader);

  final BodyReader reader;

  static final RegExp _time = RegExp(r'^([01]\d|2[0-3]):([0-5]\d)$');
  static final RegExp _date = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');
  static const int maxBreaks = 5;

  static int? minutes(Object? v) {
    if (v is! String) return null;
    final m = _time.firstMatch(v);
    return m == null
        ? null
        : int.parse(m.group(1)!) * 60 + int.parse(m.group(2)!);
  }

  static bool validDate(Object? v, {int minYear = 2000, int maxYear = 2100}) {
    if (v is! String) return false;
    final m = _date.firstMatch(v);
    if (m == null) return false;
    final y = int.parse(m.group(1)!),
        mo = int.parse(m.group(2)!),
        d = int.parse(m.group(3)!);
    final dt = DateTime.utc(y, mo, d);
    return dt.year == y &&
        dt.month == mo &&
        dt.day == d &&
        y >= minYear &&
        y <= maxYear;
  }

  /// Parses one day. Returns the normalised map or null (issues recorded).
  Map<String, Object?>? day(
    Object? raw,
    String field, {
    bool requireOpen = false,
  }) {
    if (raw is! Map) {
      reader.addIssue(field, 'invalid_type', 'Must be an object.');
      return null;
    }
    for (final k in raw.keys) {
      if (!const {'open', 'from', 'to', 'breaks', 'note', 'date'}.contains(k)) {
        reader.addIssue(
          '$field.$k',
          'not_allowed',
          'This field is not accepted.',
        );
      }
    }
    final open = raw['open'];
    if (open is! bool) {
      reader.addIssue(
        '$field.open',
        'invalid_type',
        'open must be true or false.',
      );
      return null;
    }
    if (!open) {
      if (requireOpen)
        reader.addIssue(
          '$field.open',
          'invalid_value',
          'A special working day must be open.',
        );
      return {'open': false};
    }
    final from = minutes(raw['from']);
    final to = minutes(raw['to']);
    if (from == null || to == null) {
      reader.addIssue(
        field,
        'invalid_time',
        'from and to must be times like 09:00.',
      );
      return null;
    }
    if (from == to) {
      reader.addIssue(
        field,
        'invalid_period',
        'Opening and closing time cannot be equal.',
      );
      return null;
    }
    final overnight = to < from;
    final end = overnight ? to + 1440 : to;
    final breaksRaw = raw['breaks'] ?? const <Object?>[];
    if (breaksRaw is! List || breaksRaw.length > maxBreaks) {
      reader.addIssue(
        '$field.breaks',
        'invalid_value',
        'At most $maxBreaks breaks.',
      );
      return null;
    }
    final spans = <(int, int)>[];
    final breaks = <Map<String, Object?>>[];
    for (var i = 0; i < breaksRaw.length; i++) {
      final b = breaksRaw[i];
      final bf = b is Map ? minutes(b['from']) : null;
      final bt = b is Map ? minutes(b['to']) : null;
      if (bf == null || bt == null) {
        reader.addIssue(
          '$field.breaks[$i]',
          'invalid_time',
          'Break times must be like 13:00.',
        );
        return null;
      }
      // measure relative to the opening time so overnight breaks work
      var s = bf < from ? bf + 1440 : bf;
      var e = bt < from ? bt + 1440 : bt;
      if (!overnight && bt <= bf) {
        reader.addIssue(
          '$field.breaks[$i]',
          'invalid_period',
          'A break must end after it starts.',
        );
        return null;
      }
      if (overnight && e <= s) e += 1440;
      if (s < from || e > end || s >= e) {
        reader.addIssue(
          '$field.breaks[$i]',
          'outside_hours',
          'A break must be inside the opening hours.',
        );
        return null;
      }
      spans.add((s, e));
      breaks.add({'from': b['from'], 'to': b['to']});
    }
    spans.sort((a, b) => a.$1.compareTo(b.$1));
    for (var i = 1; i < spans.length; i++) {
      if (spans[i].$1 < spans[i - 1].$2) {
        reader.addIssue('$field.breaks', 'overlap', 'Breaks must not overlap.');
        return null;
      }
    }
    return {
      'open': true,
      'from': raw['from'],
      'to': raw['to'],
      'overnight': overnight,
      'breaks': breaks,
      if (raw['note'] is String) 'note': (raw['note'] as String).trim(),
    };
  }

  /// `{ "1": day, ... "7": day }` (1 = Monday). Missing days are closed.
  Map<String, Object?>? weekly(Object? raw, String field) {
    if (raw is! Map) {
      reader.addIssue(
        field,
        'invalid_type',
        'Must be an object keyed by weekday 1-7.',
      );
      return null;
    }
    final out = <String, Object?>{};
    var ok = true;
    for (final k in raw.keys) {
      final n = int.tryParse('$k');
      if (n == null || n < 1 || n > 7) {
        reader.addIssue(
          '$field.$k',
          'invalid_value',
          'Weekday must be 1 (Mon) to 7 (Sun).',
        );
        ok = false;
      }
    }
    for (var d = 1; d <= 7; d++) {
      final v = raw['$d'];
      if (v == null) {
        out['$d'] = {'open': false};
        continue;
      }
      final parsed = day(v, '$field.$d');
      if (parsed == null) {
        ok = false;
      } else {
        out['$d'] = parsed;
      }
    }
    return ok ? out : null;
  }

  List<Map<String, Object?>>? holidays(Object? raw, String field) {
    if (raw is! List || raw.length > 100) {
      reader.addIssue(
        field,
        'invalid_value',
        'Provide a list of at most 100 holidays.',
      );
      return null;
    }
    final seen = <String>{};
    final out = <Map<String, Object?>>[];
    for (var i = 0; i < raw.length; i++) {
      final h = raw[i];
      if (h is! Map || !validDate(h['date'])) {
        reader.addIssue(
          '$field[$i]',
          'invalid_date',
          'Each holiday needs a valid date (YYYY-MM-DD).',
        );
        return null;
      }
      if (!seen.add(h['date']! as String)) {
        reader.addIssue('$field[$i]', 'duplicate', 'Duplicate holiday date.');
        return null;
      }
      final name = h['name'];
      if (name != null && (name is! String || name.length > 80)) {
        reader.addIssue(
          '$field[$i].name',
          'invalid_length',
          'Name must be at most 80 characters.',
        );
        return null;
      }
      out.add({'date': h['date'], 'name': (name as String?)?.trim() ?? ''});
    }
    return out;
  }

  List<Map<String, Object?>>? specialDays(
    Object? raw,
    String field,
    Set<String> holidayDates,
  ) {
    if (raw is! List || raw.length > 100) {
      reader.addIssue(
        field,
        'invalid_value',
        'Provide a list of at most 100 special days.',
      );
      return null;
    }
    final seen = <String>{};
    final out = <Map<String, Object?>>[];
    for (var i = 0; i < raw.length; i++) {
      final s = raw[i];
      if (s is! Map || !validDate(s['date'])) {
        reader.addIssue(
          '$field[$i]',
          'invalid_date',
          'Each special day needs a valid date (YYYY-MM-DD).',
        );
        return null;
      }
      final date = s['date']! as String;
      if (!seen.add(date)) {
        reader.addIssue('$field[$i]', 'duplicate', 'Duplicate special day.');
        return null;
      }
      if (holidayDates.contains(date)) {
        reader.addIssue(
          '$field[$i]',
          'conflict',
          'A date cannot be both a holiday and a special working day.',
        );
        return null;
      }
      final d = day(s, '$field[$i]', requireOpen: true);
      if (d == null) return null;
      out.add({'date': date, ...d});
    }
    return out;
  }
}
