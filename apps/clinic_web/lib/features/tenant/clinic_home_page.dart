import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../control_plane/providers.dart';
import '../shared/async_body.dart';
import '../shared/ui_helpers.dart';
import '../shared/ui_kit.dart';

/// Clinic owner landing page. Operational modules arrive in later phases;
/// today it shows what the clinic's subscription allows, as decided by the
/// backend from the caller's own membership.
class ClinicHomePage extends ConsumerWidget {
  const ClinicHomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(entitlementsProvider);
    return AsyncBody(
      value: value,
      onRetry: () => ref.invalidate(entitlementsProvider),
      builder: (e) {
        final level = e['accessLevel'] as String;
        final features = (e['features']! as Map<String, Object?>);
        final limits = (e['limits']! as Map<String, Object?>);
        final sub = e['subscription'] as Map<String, Object?>?;
        final reason = e['reason'] as String?;
        return ListView(
          padding: const EdgeInsets.all(EcSpacing.lg),
          children: [
            PageHeader(
              title: 'Your clinic',
              subtitle:
                  'Clinic management modules will appear here as they are released.',
              actions: [statusChip(level), statusChip(e['tenantStatus'])],
            ),
            if (level == 'blocked')
              EcInlineMessage(message: _blockedMessage(reason)),
            if (level == 'read_only')
              const EcInlineMessage(
                tone: EcStatusTone.warning,
                message:
                    'Your subscription payment is overdue. You can view existing information but cannot make changes until it is renewed.',
              ),
            const SizedBox(height: EcSpacing.lg),
            Section(
              title: 'Subscription',
              child: sub == null
                  ? const Text('No subscription.')
                  : KeyValues([
                      ('Plan', sub['planName']),
                      ('Status', statusChip(sub['status'])),
                      ('Ends', Fmt.date(sub['endsAt'])),
                    ]),
            ),
            Section(
              title: 'Included features',
              child: Wrap(
                spacing: EcSpacing.sm,
                runSpacing: EcSpacing.sm,
                children: [
                  for (final entry in features.entries)
                    EcStatusChip(
                      label: Fmt.humanize(entry.key),
                      tone: entry.value == true
                          ? EcStatusTone.success
                          : EcStatusTone.neutral,
                    ),
                ],
              ),
            ),
            Section(
              title: 'Limits',
              child: KeyValues([
                for (final entry in limits.entries)
                  (Fmt.humanize(entry.key), Fmt.limit(entry.value)),
              ]),
            ),
          ],
        );
      },
    );
  }

  String _blockedMessage(String? reason) => switch (reason) {
    'tenant_suspended' =>
      'Your clinic is suspended. Contact EazyClinic support.',
    'tenant_closed' => 'Your clinic account is closed.',
    'tenant_provisioning' =>
      'Your clinic is still being set up. Please check back shortly.',
    'subscription_expired' =>
      'Your subscription has expired. Contact EazyClinic to renew it.',
    'subscription_cancelled' => 'Your subscription was cancelled.',
    'subscription_suspended' =>
      'Your subscription is suspended. Contact EazyClinic support.',
    'no_subscription' => 'Your clinic does not have a subscription yet.',
    _ => 'Access to your clinic is restricted. Contact EazyClinic support.',
  };
}
