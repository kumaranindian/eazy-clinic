import 'package:api_contracts/api_contracts.dart';
import 'package:validation/validation.dart';

import '../../../core/errors/api_exception.dart';

/// Validating reader for JSON request bodies. Collects every problem and
/// throws one 422. Unknown fields are rejected via [rejectUnknown].
class BodyReader {
  BodyReader(this.body, {this.partial = false});

  final Map<String, Object?> body;

  /// In partial (PATCH-like) mode, absent fields are simply skipped.
  final bool partial;
  final List<FieldIssue> issues = [];

  void addIssue(String f, String code, String msg) =>
      issues.add(FieldIssue(field: f, code: code, message: msg));

  bool has(String f) => body.containsKey(f);

  void rejectUnknown(Set<String> allowed, {String prefix = ''}) {
    for (final k in body.keys) {
      if (!allowed.contains(k)) {
        addIssue('$prefix$k', 'not_allowed', 'This field is not accepted.');
      }
    }
  }

  String? str(
    String f, {
    int min = 1,
    int max = 200,
    bool required = true,
    String prefix = '',
  }) {
    final raw = body[f];
    if (raw == null) {
      if (required && !partial) {
        addIssue('$prefix$f', 'required', '$f is required.');
      }
      return null;
    }
    if (raw is! String) {
      addIssue('$prefix$f', 'invalid_type', '$f must be a string.');
      return null;
    }
    final v = raw.trim();
    if (v.length < min || v.length > max) {
      addIssue(
        '$prefix$f',
        'invalid_length',
        '$f must be $min-$max characters.',
      );
      return null;
    }
    if (RegExp(r'[\u0000-\u0008\u000B\u000C\u000E-\u001F]').hasMatch(v)) {
      addIssue(
        '$prefix$f',
        'invalid_characters',
        '$f contains invalid characters.',
      );
      return null;
    }
    return v;
  }

  String? email(String f, {bool required = true, String prefix = ''}) {
    final v = str(f, max: 254, required: required, prefix: prefix);
    if (v == null) return null;
    final failure = Validators.email(v);
    if (failure != null) {
      addIssue('$prefix$f', failure.code, failure.message);
      return null;
    }
    return v.toLowerCase();
  }

  String? phone(String f, {bool required = true, String prefix = ''}) {
    final v = str(f, min: 1, max: 20, required: required, prefix: prefix);
    if (v == null) return null;
    final failure = Validators.indianMobile(v);
    if (failure != null) {
      addIssue('$prefix$f', failure.code, failure.message);
      return null;
    }
    return v.replaceAll(RegExp(r'[\s\-]'), '');
  }

  int? integer(
    String f, {
    required int min,
    required int max,
    bool required = true,
    String prefix = '',
  }) {
    final raw = body[f];
    if (raw == null) {
      if (required && !partial) {
        addIssue('$prefix$f', 'required', '$f is required.');
      }
      return null;
    }
    if (raw is! int || raw < min || raw > max) {
      addIssue(
        '$prefix$f',
        'out_of_range',
        '$f must be a whole number from $min to $max.',
      );
      return null;
    }
    return raw;
  }

  bool? boolean(String f, {bool required = false}) {
    final raw = body[f];
    if (raw == null) {
      if (required && !partial) addIssue(f, 'required', '$f is required.');
      return null;
    }
    if (raw is! bool) {
      addIssue(f, 'invalid_type', '$f must be true or false.');
      return null;
    }
    return raw;
  }

  T? enumOf<T>(
    String f,
    List<T> values,
    String Function(T) wire, {
    bool required = true,
  }) {
    final raw = body[f];
    if (raw == null) {
      if (required && !partial) addIssue(f, 'required', '$f is required.');
      return null;
    }
    for (final v in values) {
      if (raw is String && wire(v) == raw) return v;
    }
    addIssue(f, 'invalid_value', '$f has an unsupported value.');
    return null;
  }

  /// A nested object, wrapped in its own reader (issues are merged).
  BodyReader? object(
    String f, {
    bool required = true,
    bool partialChild = false,
  }) {
    final raw = body[f];
    if (raw == null) {
      if (required && !partial) addIssue(f, 'required', '$f is required.');
      return null;
    }
    if (raw is! Map) {
      addIssue(f, 'invalid_type', '$f must be an object.');
      return null;
    }
    final child = BodyReader(
      raw.cast<String, Object?>(),
      partial: partialChild || partial,
    );
    child.issues.clear();
    _children.add((f, child));
    return child;
  }

  final List<(String, BodyReader)> _children = [];

  void throwIfInvalid() {
    final all = [
      ...issues,
      for (final (name, c) in _children)
        for (final i in c.issues)
          FieldIssue(
            field: '$name.${i.field}',
            code: i.code,
            message: i.message,
          ),
    ];
    if (all.isNotEmpty) throw ApiException.validation(all);
  }
}
