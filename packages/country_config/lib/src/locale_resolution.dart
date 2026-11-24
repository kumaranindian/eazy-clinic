/// Languages written right-to-left.
const Set<String> rtlLanguages = {'ar', 'he', 'fa', 'ur'};

/// A resolved UI locale.
class ResolvedLocale {
  const ResolvedLocale(this.tag, this.source);

  /// BCP-47 tag from the app's supported list (e.g. `ar`, `en-IN`).
  final String tag;

  /// Which layer decided: `user`, `tenant`, `country` or `fallback`.
  final String source;

  String get languageCode => tag.split(RegExp('[-_]')).first.toLowerCase();

  bool get isRtl => rtlLanguages.contains(languageCode);
}

/// Resolves the UI locale. Order: user preference → tenant default → country
/// default → [fallback]. The first candidate matching [supported] wins (exact
/// tag, else same language). The locale only affects presentation: it never
/// changes tenant, legal country, currency or any stored value.
ResolvedLocale resolveLocale({
  required List<String> supported,
  String? userPreference,
  String? tenantDefault,
  String? countryDefault,
  String fallback = 'en',
}) {
  String? match(String? candidate) {
    if (candidate == null || candidate.isEmpty) return null;
    final norm = candidate.replaceAll('_', '-').toLowerCase();
    for (final s in supported) {
      if (s.toLowerCase() == norm) return s;
    }
    final lang = norm.split('-').first;
    for (final s in supported) {
      if (s.toLowerCase().split('-').first == lang) return s;
    }
    return null;
  }

  for (final (value, source) in [
    (userPreference, 'user'),
    (tenantDefault, 'tenant'),
    (countryDefault, 'country'),
  ]) {
    final m = match(value);
    if (m != null) return ResolvedLocale(m, source);
  }
  return ResolvedLocale(match(fallback) ?? fallback, 'fallback');
}
