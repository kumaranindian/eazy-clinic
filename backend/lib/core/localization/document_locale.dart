import 'package:common_models/common_models.dart';

/// Kinds of patient- or clinic-facing documents that can be produced in a
/// language. Only the hook exists in Phase 13: the documents themselves (their
/// legal and clinical content and templates) are unchanged and not yet
/// translated.
enum DocumentKind { invoice, prescription, report, consentForm }

/// The language a document should be rendered in, and its direction.
class DocumentLocale {
  const DocumentLocale(this.language, this.source);

  /// One of [supportedUiLanguages].
  final String language;

  /// Which input decided: `recipient`, `clinic`, `country` or `default`.
  final String source;

  bool get rtl => rtlUiLanguages.contains(language);
}

/// Decides the language of a generated document: the recipient's language,
/// then the clinic default, then the country default, then English; each only
/// if the document kind actually has a template in that language
/// ([availableLanguages]). Document content must never be machine-translated
/// at render time; a missing translation falls back, it is not generated.
DocumentLocale resolveDocumentLocale({
  required Set<String> availableLanguages,
  String? recipientLanguage,
  String? clinicLanguage,
  String? countryLanguage,
}) {
  for (final (value, source) in [
    (recipientLanguage, 'recipient'),
    (clinicLanguage, 'clinic'),
    (countryLanguage, 'country'),
  ]) {
    if (value != null &&
        isSupportedUiLanguage(value) &&
        availableLanguages.contains(value)) {
      return DocumentLocale(value, source);
    }
  }
  return const DocumentLocale('en', 'default');
}
