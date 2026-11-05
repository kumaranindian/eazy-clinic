import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

bool _initialised = false;

void _ensureInitialised() {
  if (_initialised) return;
  tzdata.initializeTimeZones();
  _initialised = true;
}

/// IANA time-zone helpers backed by the maintained `timezone` package (tz
/// database). A time zone is a configurable default, never an invariant.
abstract final class Timezones {
  /// True when [name] is a known IANA zone (e.g. `Asia/Kolkata`).
  static bool isValid(String? name) {
    if (name == null || name.isEmpty || name.length > 64) return false;
    _ensureInitialised();
    return tz.timeZoneDatabase.locations.containsKey(name);
  }

  /// Converts a UTC instant to wall-clock time in [name]. Throws
  /// [ArgumentError] for an unknown zone so callers never silently fall back.
  static tz.TZDateTime toZone(DateTime instant, String name) {
    if (!isValid(name)) {
      throw ArgumentError.value(name, 'name', 'Unknown IANA time zone');
    }
    return tz.TZDateTime.from(instant.toUtc(), tz.getLocation(name));
  }

  /// UTC offset of [name] at [instant].
  static Duration offsetAt(DateTime instant, String name) =>
      toZone(instant, name).timeZoneOffset;
}
