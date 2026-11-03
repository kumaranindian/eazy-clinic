import '../../core/errors/api_exception.dart';

/// A clinic time zone with a fixed UTC offset.
///
/// Scheduling needs correct local-to-UTC conversion. The backend has no time
/// zone database, so only zones **without daylight-saving changes** are
/// supported (India, the initial market, has none). A zone that observes DST is
/// refused with a clear message instead of producing wrong slot times (TD-43).
class ClinicZone {
  const ClinicZone(this.name, this.offsetMinutes);

  final String name;
  final int offsetMinutes;

  static const Map<String, int> _fixed = {
    'Asia/Kolkata': 330,
    'Asia/Calcutta': 330,
    'Asia/Colombo': 330,
    'Asia/Kathmandu': 345,
    'Asia/Dhaka': 360,
    'Asia/Karachi': 300,
    'Asia/Dubai': 240,
    'Asia/Singapore': 480,
    'Asia/Bangkok': 420,
    'Asia/Tokyo': 540,
    'Africa/Nairobi': 180,
    'UTC': 0,
    'Etc/UTC': 0,
  };

  static List<String> get supported => _fixed.keys.toList()..sort();

  /// The zone named [name] (default `Asia/Kolkata`).
  static ClinicZone resolve(String? name) {
    final n = (name == null || name.isEmpty) ? 'Asia/Kolkata' : name;
    final off = _fixed[n];
    if (off == null) {
      throw ApiException.conflict(
        'Scheduling does not support the time zone "$n" yet (zones with daylight-saving changes are not supported).',
      );
    }
    return ClinicZone(n, off);
  }

  /// UTC instant of local [date] (`YYYY-MM-DD`) and [minutes] after midnight.
  DateTime toUtc(String date, int minutes) {
    final d = DateTime.parse('${date}T00:00:00Z');
    return d.add(Duration(minutes: minutes - offsetMinutes));
  }

  /// Local calendar date (`YYYY-MM-DD`) of a UTC instant.
  String localDate(DateTime utc) {
    final l = utc.toUtc().add(Duration(minutes: offsetMinutes));
    return '${l.year.toString().padLeft(4, '0')}-${l.month.toString().padLeft(2, '0')}-${l.day.toString().padLeft(2, '0')}';
  }

  /// Minutes after local midnight of a UTC instant.
  int localMinutes(DateTime utc) {
    final l = utc.toUtc().add(Duration(minutes: offsetMinutes));
    return l.hour * 60 + l.minute;
  }
}

abstract final class Hm {
  static final RegExp _re = RegExp(r'^([01]\d|2[0-3]):([0-5]\d)$');

  static int? parse(Object? v) {
    if (v is! String) return null;
    final m = _re.firstMatch(v);
    return m == null
        ? null
        : int.parse(m.group(1)!) * 60 + int.parse(m.group(2)!);
  }

  static String format(int minutes) =>
      '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';
}

abstract final class Dates {
  static final RegExp _re = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

  static bool valid(Object? v) {
    if (v is! String) return false;
    final m = _re.firstMatch(v);
    if (m == null) return false;
    final y = int.parse(m.group(1)!);
    final mo = int.parse(m.group(2)!);
    final d = int.parse(m.group(3)!);
    final dt = DateTime.utc(y, mo, d);
    return y >= 2000 && y <= 2100 && dt.month == mo && dt.day == d;
  }

  /// 1 = Monday … 7 = Sunday.
  static int weekday(String date) =>
      DateTime.parse('${date}T00:00:00Z').weekday;

  static String addDays(String date, int days) {
    final d = DateTime.parse('${date}T00:00:00Z').add(Duration(days: days));
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  static int daysBetween(String from, String to) => DateTime.parse(
    '${to}T00:00:00Z',
  ).difference(DateTime.parse('${from}T00:00:00Z')).inDays;

  static String compact(String date) => date.replaceAll('-', '');
}

/// Half-open range of minutes after local midnight.
class Span {
  const Span(this.from, this.to);
  final int from;
  final int to;

  bool overlaps(int a, int b) => a < to && b > from;
  Map<String, Object?> toJson() => {
    'from': Hm.format(from),
    'to': Hm.format(to),
  };
}
