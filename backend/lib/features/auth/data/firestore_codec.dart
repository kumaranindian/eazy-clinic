/// Converts between plain Dart values and Firestore REST `Value` JSON.
/// Supports exactly the types platform documents use.
Map<String, Object?> encodeFields(Map<String, Object?> map) => {
  for (final e in map.entries) e.key: encodeValue(e.value),
};

Map<String, Object?> encodeValue(Object? v) {
  if (v == null) return {'nullValue': null};
  if (v is bool) return {'booleanValue': v};
  if (v is String) return {'stringValue': v};
  if (v is int) return {'integerValue': v.toString()};
  if (v is DateTime) return {'timestampValue': v.toUtc().toIso8601String()};
  throw ArgumentError('Unsupported Firestore value type: ${v.runtimeType}');
}

Map<String, Object?> decodeFields(Map<String, Object?> fields) => {
  for (final e in fields.entries)
    e.key: decodeValue((e.value! as Map).cast<String, Object?>()),
};

Object? decodeValue(Map<String, Object?> v) {
  if (v.containsKey('nullValue')) return null;
  if (v.containsKey('booleanValue')) return v['booleanValue'];
  if (v.containsKey('stringValue')) return v['stringValue'];
  if (v.containsKey('integerValue')) {
    return int.parse(v['integerValue']! as String);
  }
  if (v.containsKey('timestampValue')) {
    return DateTime.parse(v['timestampValue']! as String).toUtc();
  }
  return null;
}
