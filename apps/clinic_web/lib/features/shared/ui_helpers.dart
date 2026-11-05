import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';

/// Display helpers shared by the control-plane screens.
abstract final class Fmt {
  /// `2026-06-01T10:00:00Z` → `1 Jun 2026` in the clinic's time zone (the
  /// device zone only for platform screens that have no clinic), in the
  /// user's language.
  static String date(Object? iso, {String? timezone}) =>
      RegionalDisplay.date(iso, timezone: timezone);

  static String dateTime(Object? iso, {String? timezone}) =>
      RegionalDisplay.dateTime(iso, timezone: timezone);

  /// Amount in minor units → localized money with the currency's own number
  /// of decimals (`₹1,180.00`, `AED 1,180.00`). Display only.
  static String money(Object? minor, [Object? currency]) =>
      RegionalDisplay.money(minor, currency);

  /// `additional_information_required` → `Additional information required`.
  static String humanize(Object? snake) {
    final s = '${snake ?? ''}'.replaceAll(RegExp(r'[_.]'), ' ').trim();
    return s.isEmpty ? '—' : s[0].toUpperCase() + s.substring(1);
  }

  static String limit(Object? v) => v == null ? 'Unlimited' : '$v';

  static EcStatusTone tone(Object? status) => switch ('$status') {
    'active' ||
    'approved' ||
    'completed' ||
    'full' ||
    'verified' ||
    'published' ||
    'collected' => EcStatusTone.success,
    'trial' ||
    'submitted' ||
    'under_review' ||
    'provisioning' ||
    'pending' ||
    'accepted' ||
    'sample_pending' ||
    'sample_collected' ||
    'processing' ||
    'result_entered' ||
    'verification_pending' ||
    'draft' ||
    'uploaded' => EcStatusTone.info,
    'past_due' ||
    'additional_information_required' ||
    'read_only' ||
    'recollection_required' ||
    'superseded' ||
    'returned' ||
    'inactive' => EcStatusTone.warning,
    'suspended' ||
    'rejected' ||
    'closed' ||
    'cancelled' ||
    'expired' ||
    'failed' ||
    'blocked' => EcStatusTone.error,
    _ => EcStatusTone.neutral,
  };
}
