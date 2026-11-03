/// Keys whose values must never reach logs. Matching is case-insensitive and
/// substring-based, so `patientPhone` and `Authorization` are both caught.
const List<String> sensitiveKeyFragments = [
  'authorization',
  'token',
  'password',
  'secret',
  'cookie',
  'otp',
  'phone',
  'email',
  'name',
  'dob',
  'dateofbirth',
  'address',
  'diagnosis',
  'complaint',
  'symptom',
  'prescription',
  'medicine',
  'note',
  'allerg',
  'vital',
  'card',
  'account',
];

const String redactedValue = '[REDACTED]';

/// Returns a deep copy of [input] with sensitive values replaced. Used by the
/// structured logger so clinical and personal data never appear in logs.
Map<String, Object?> redact(Map<String, Object?> input) {
  return {
    for (final entry in input.entries)
      entry.key: _isSensitive(entry.key)
          ? redactedValue
          : _redactValue(entry.value),
  };
}

bool _isSensitive(String key) {
  final lower = key.toLowerCase();
  return sensitiveKeyFragments.any(lower.contains);
}

Object? _redactValue(Object? value) {
  if (value is Map) {
    return redact(value.cast<String, Object?>());
  }
  if (value is List) {
    return value.map(_redactValue).toList();
  }
  return value;
}
