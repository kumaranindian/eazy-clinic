/// Converts between plain Dart values and Firestore REST `Value` JSON.
Map<String, Object?> encodeFields(Map<String, Object?> map) => {
  for (final e in map.entries) e.key: encodeValue(e.value),
};

Map<String, Object?> encodeValue(Object? v) {
  if (v == null) return {'nullValue': null};
  if (v is bool) return {'booleanValue': v};
  if (v is String) return {'stringValue': v};
  if (v is int) return {'integerValue': v.toString()};
  if (v is double) return {'doubleValue': v};
  if (v is DateTime) return {'timestampValue': v.toUtc().toIso8601String()};
  if (v is List) {
    return {
      'arrayValue': {'values': v.map(encodeValue).toList()},
    };
  }
  if (v is Map) {
    return {
      'mapValue': {'fields': encodeFields(v.cast<String, Object?>())},
    };
  }
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
  if (v.containsKey('doubleValue')) {
    return (v['doubleValue']! as num).toDouble();
  }
  if (v.containsKey('timestampValue')) {
    return DateTime.parse(v['timestampValue']! as String).toUtc();
  }
  if (v.containsKey('arrayValue')) {
    final values = ((v['arrayValue']! as Map)['values'] as List?) ?? const [];
    return values
        .map((e) => decodeValue((e! as Map).cast<String, Object?>()))
        .toList();
  }
  if (v.containsKey('mapValue')) {
    final fields =
        ((v['mapValue']! as Map)['fields'] as Map?)?.cast<String, Object?>() ??
        const <String, Object?>{};
    return decodeFields(fields);
  }
  return null;
}
