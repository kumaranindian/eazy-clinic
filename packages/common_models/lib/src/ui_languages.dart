/// UI languages EazyClinic ships resources for (Phase 13). A language is a
/// presentation choice only: it never changes a clinic's legal country, its
/// currency, stored dates or any clinical or financial value.
///
/// Arabic, Hindi and Tamil are machine-assisted starter packs (see
/// docs/phase-13); English is the baseline.
const List<String> supportedUiLanguages = ['en', 'ar', 'hi', 'ta'];

/// Languages written right-to-left.
const Set<String> rtlUiLanguages = {'ar'};

bool isSupportedUiLanguage(String? code) =>
    code != null && supportedUiLanguages.contains(code);
