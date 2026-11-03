import 'package:common_models/common_models.dart';

/// Status a subscription has *right now*. Expiry is evaluated from dates, so
/// no scheduled job is needed for correctness: a `trial` past its trial end or
/// an `active` subscription past its end date is treated as `expired` even
/// before an admin records it.
SubscriptionStatus effectiveSubscriptionStatus(
  Map<String, Object?> sub,
  DateTime now,
) {
  final stored =
      SubscriptionStatus.tryParse(sub['status'] as String?) ??
      SubscriptionStatus.cancelled;
  if (stored == SubscriptionStatus.trial) {
    final end = (sub['trialEndDate'] ?? sub['endDate']) as DateTime?;
    if (end != null && !now.isBefore(end)) return SubscriptionStatus.expired;
  }
  if (stored == SubscriptionStatus.active) {
    final end = sub['endDate'] as DateTime?;
    if (end != null && !now.isBefore(end)) return SubscriptionStatus.expired;
  }
  return stored;
}

/// Snapshot copied from a plan into a subscription.
Map<String, Object?> planSnapshot(Map<String, Object?> plan) => {
  'planId': plan['planId'],
  'planVersion': plan['version'],
  'name': plan['name'],
  'billingInterval': plan['billingInterval'],
  'priceMinor': plan['priceMinor'],
  'currency': plan['currency'],
  'limits': Map<String, Object?>.from(plan['limits']! as Map),
  'features': Map<String, Object?>.from(plan['features']! as Map),
};
