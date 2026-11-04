import 'package:design_system/design_system.dart';

/// Display helpers shared by the control-plane screens.
abstract final class Fmt {
  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  /// `2026-06-01T10:00:00Z` → `1 Jun 2026` (local time zone).
  static String date(Object? iso) {
    final d = iso is String ? DateTime.tryParse(iso)?.toLocal() : null;
    if (d == null) return '—';
    return '${d.day} ${_months[d.month - 1]} ${d.year}';
  }

  static String dateTime(Object? iso) {
    final d = iso is String ? DateTime.tryParse(iso)?.toLocal() : null;
    if (d == null) return '—';
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    return '${date(iso)}, $hh:$mm';
  }

  /// Amount in minor units (paise) → `₹999.00`.
  static String money(Object? minor, [Object? currency]) {
    if (minor is! int) return '—';
    final symbol = currency == 'INR' || currency == null ? '₹' : '$currency ';
    final major = minor ~/ 100;
    final frac = (minor % 100).toString().padLeft(2, '0');
    return '$symbol$major.$frac';
  }

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
