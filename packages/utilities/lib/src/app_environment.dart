/// The three isolated deployment environments. They never share Firebase
/// projects, data or credentials.
enum AppEnvironment {
  dev('dev'),
  staging('staging'),
  production('production');

  const AppEnvironment(this.wireName);

  final String wireName;

  bool get isProduction => this == AppEnvironment.production;

  /// Parses an environment name. Throws [FormatException] for unknown values
  /// so a misconfigured build fails loudly instead of defaulting silently.
  static AppEnvironment parse(String? value) {
    for (final env in values) {
      if (env.wireName == value) return env;
    }
    throw FormatException(
      'Unknown APP_ENV "$value". Expected one of: '
      '${values.map((e) => e.wireName).join(', ')}.',
    );
  }
}
