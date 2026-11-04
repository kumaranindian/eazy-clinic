/// Flags for laboratory observations.
///
/// The product ships **no** reference ranges. Every range comes from the
/// clinic's own test configuration (with its source and unit). When no
/// configured range applies, or the units differ, the observation is flagged
/// `not_assessed` / `unit_mismatch` instead of being compared or guessed. Flags
/// are information for the clinician, never a diagnosis.
library;

const List<String> flagValues = [
  'normal',
  'low',
  'high',
  'abnormal',
  'critical_low',
  'critical_high',
  'critical',
  'not_assessed',
  'unit_mismatch',
  'not_applicable',
];

bool isCritical(String flag) => flag.startsWith('critical');

bool isAbnormal(String flag) =>
    flag == 'low' || flag == 'high' || flag == 'abnormal' || isCritical(flag);

/// Whole years between [dob] (`YYYY-MM-DD`) and [on], or null when unknown.
int? ageInYears(String? dob, DateTime on) {
  final d = dob == null ? null : DateTime.tryParse(dob);
  if (d == null) return null;
  var age = on.year - d.year;
  if (on.month < d.month || (on.month == d.month && on.day < d.day)) age--;
  return age < 0 ? null : age;
}

num? _num(Object? v) => v is num ? v : null;

/// The first configured range that applies to the patient, or null.
Map<String, Object?>? applicableRange(
  List<Object?> ranges, {
  required String? sex,
  required int? ageYears,
}) {
  for (final raw in ranges) {
    final r = (raw as Map).cast<String, Object?>();
    final rs = r['sex'] as String? ?? 'any';
    if (rs != 'any' && rs != sex) continue;
    final lo = _num(r['ageMinYears']);
    final hi = _num(r['ageMaxYears']);
    if ((lo != null || hi != null) && ageYears == null) continue;
    if (lo != null && ageYears! < lo) continue;
    if (hi != null && ageYears! > hi) continue;
    return r;
  }
  return null;
}

class Evaluation {
  const Evaluation(this.flag, [this.range]);
  final String flag;

  /// The range used, kept on the result so the report states its source.
  final Map<String, Object?>? range;
}

/// Evaluates one observation of a configured [parameter].
Evaluation evaluate(
  Map<String, Object?> parameter, {
  required Object? value,
  required String? unit,
  required String? sex,
  required int? ageYears,
}) {
  final type = parameter['valueType'];
  if (type == 'text') return const Evaluation('not_applicable');
  if (type == 'qualitative') {
    final opts = (parameter['qualitativeOptions'] as List? ?? const []).map(
      (e) => (e as Map).cast<String, Object?>(),
    );
    for (final o in opts) {
      if (o['value'] == value) {
        if (o['critical'] == true) return const Evaluation('critical');
        if (o['abnormal'] == true) return const Evaluation('abnormal');
        return const Evaluation('normal');
      }
    }
    return const Evaluation('not_assessed');
  }
  final v = _num(value);
  if (v == null) return const Evaluation('not_assessed');
  final range = applicableRange(
    (parameter['referenceRanges'] as List?) ?? const [],
    sex: sex,
    ageYears: ageYears,
  );
  if (range == null) return const Evaluation('not_assessed');
  final rangeUnit = range['unit'] as String?;
  if (rangeUnit != null && unit != null && rangeUnit != unit) {
    return Evaluation('unit_mismatch', range);
  }
  final cl = _num(range['criticalLow']);
  final ch = _num(range['criticalHigh']);
  final lo = _num(range['low']);
  final hi = _num(range['high']);
  if (cl != null && v < cl) return Evaluation('critical_low', range);
  if (ch != null && v > ch) return Evaluation('critical_high', range);
  if (lo != null && v < lo) return Evaluation('low', range);
  if (hi != null && v > hi) return Evaluation('high', range);
  if (lo == null && hi == null) return Evaluation('not_assessed', range);
  return Evaluation('normal', range);
}
