/// A failed validation: a stable [code] plus a user-facing [message].
class ValidationFailure {
  const ValidationFailure(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => '$code: $message';
}

/// A validator returns `null` when the value is valid.
typedef FieldValidator = ValidationFailure? Function(String? value);

/// Library of reusable validators. Backend request validation is authoritative;
/// the same rules run in the apps only to give faster feedback.
abstract final class Validators {
  static ValidationFailure? required(
    String? value, {
    String field = 'This field',
  }) {
    if (value == null || value.trim().isEmpty) {
      return ValidationFailure('required', '$field is required.');
    }
    return null;
  }

  static final RegExp _emailPattern = RegExp(
    r'^[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$',
  );

  static ValidationFailure? email(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) {
      return const ValidationFailure('required', 'Email is required.');
    }
    if (v.length > 254 || !_emailPattern.hasMatch(v)) {
      return const ValidationFailure(
        'invalid_email',
        'Enter a valid email address.',
      );
    }
    return null;
  }

  /// Indian mobile number: 10 digits starting 6-9, with optional +91 / 91 / 0.
  static final RegExp _indianMobile = RegExp(r'^(?:\+?91|0)?[6-9]\d{9}$');

  static ValidationFailure? indianMobile(String? value) {
    final v = (value ?? '').replaceAll(RegExp(r'[\s\-]'), '');
    if (v.isEmpty) {
      return const ValidationFailure('required', 'Phone number is required.');
    }
    if (!_indianMobile.hasMatch(v)) {
      return const ValidationFailure(
        'invalid_phone',
        'Enter a valid 10-digit mobile number.',
      );
    }
    return null;
  }

  static FieldValidator minLength(int min, {String field = 'Value'}) {
    return (value) => (value ?? '').trim().length < min
        ? ValidationFailure(
            'too_short',
            '$field must be at least $min characters.',
          )
        : null;
  }

  static FieldValidator maxLength(int max, {String field = 'Value'}) {
    return (value) => (value ?? '').length > max
        ? ValidationFailure(
            'too_long',
            '$field must be at most $max characters.',
          )
        : null;
  }

  /// Minimum bar for account passwords: 8+ characters with a letter and a digit.
  static ValidationFailure? password(String? value) {
    final v = value ?? '';
    if (v.isEmpty) {
      return const ValidationFailure('required', 'Password is required.');
    }
    if (v.length < 8) {
      return const ValidationFailure(
        'weak_password',
        'Password must be at least 8 characters.',
      );
    }
    if (!RegExp(r'[A-Za-z]').hasMatch(v) || !RegExp(r'\d').hasMatch(v)) {
      return const ValidationFailure(
        'weak_password',
        'Password must contain letters and numbers.',
      );
    }
    return null;
  }

  /// Runs [validators] in order and returns the first failure.
  static FieldValidator compose(List<FieldValidator> validators) {
    return (value) {
      for (final validator in validators) {
        final failure = validator(value);
        if (failure != null) return failure;
      }
      return null;
    };
  }
}
