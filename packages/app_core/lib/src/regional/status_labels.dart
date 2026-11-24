import '../../l10n/generated/app_localizations.dart';

/// Localized label for a status value from the API (`checked_in`,
/// `partially_paid` ...). Unknown values fall back to a readable form of the
/// wire value (never the raw key with underscores).
String statusLabel(AppLocalizations t, Object? wire) {
  final value = '${wire ?? ''}';
  return switch (value) {
    'booked' => t.statusBooked,
    'confirmed' => t.statusConfirmed,
    'checked_in' => t.statusCheckedIn,
    'in_consultation' => t.statusInConsultation,
    'completed' => t.statusCompleted,
    'cancelled' => t.statusCancelled,
    'no_show' => t.statusNoShow,
    'draft' => t.statusDraft,
    'finalized' => t.statusFinalized,
    'paid' => t.statusPaid,
    'partially_paid' => t.statusPartiallyPaid,
    'outstanding' => t.statusOutstanding,
    'refunded' => t.statusRefunded,
    _ => _humanize(value),
  };
}

String _humanize(String v) {
  final s = v.replaceAll(RegExp(r'[_.]'), ' ').trim();
  return s.isEmpty ? '—' : s[0].toUpperCase() + s.substring(1);
}
