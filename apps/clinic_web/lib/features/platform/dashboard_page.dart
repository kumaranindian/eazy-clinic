import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../control_plane/providers.dart';
import '../shared/async_body.dart';
import '../shared/ui_helpers.dart';
import '../shared/ui_kit.dart';

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(dashboardProvider);
    return AsyncBody(
      value: value,
      onRetry: () => ref.invalidate(dashboardProvider),
      builder: (d) {
        final apps = (d['applications']! as Map).cast<String, Object?>();
        final tenants = (d['tenants']! as Map).cast<String, Object?>();
        final subs = (d['subscriptions']! as Map).cast<String, Object?>();
        final dist = (d['planDistribution']! as List)
            .cast<Map<String, Object?>>();
        final recentApps = (d['recentApplications']! as List)
            .cast<Map<String, Object?>>();
        final recentTenants = (d['recentlyApprovedClinics']! as List)
            .cast<Map<String, Object?>>();
        final activity = (d['recentActivity']! as List)
            .cast<Map<String, Object?>>();
        final mrr =
            (d['monthlyRecurringRevenue']!
                as Map<String, Object?>)['available'] ==
            true;
        return ListView(
          padding: const EdgeInsets.all(EcSpacing.lg),
          children: [
            PageHeader(
              title: 'Platform overview',
              subtitle:
                  'Counts are read from live data. Updated ${Fmt.dateTime(d['generatedAt'])}.',
              actions: [
                IconButton(
                  tooltip: 'Refresh',
                  icon: const Icon(Icons.refresh),
                  onPressed: () => ref.invalidate(dashboardProvider),
                ),
              ],
            ),
            _Stats(
              title: 'Clinics',
              tiles: [
                ('Registered clinics', tenants['total']),
                ('Active clinics', tenants['active']),
                ('Suspended', tenants['suspended']),
                ('Provisioning', tenants['provisioning']),
              ],
            ),
            _Stats(
              title: 'Applications',
              tiles: [
                ('Pending review', apps['pending']),
                ('Info requested', apps['additionalInformationRequired']),
                ('Approved', apps['approved']),
                ('Rejected', apps['rejected']),
              ],
            ),
            _Stats(
              title: 'Subscriptions',
              tiles: [
                ('Active', subs['active']),
                ('Trials', subs['trial']),
                ('Past due', subs['pastDue']),
                ('Expired', subs['expired']),
              ],
            ),
            Section(
              title: 'Subscription plan distribution',
              child: dist.isEmpty
                  ? const Text('No plans yet.')
                  : Column(
                      children: [
                        for (final p in dist)
                          ListTile(
                            dense: true,
                            title: Text('${p['name']}'),
                            trailing: Text(
                              '${p['subscriptions']} subscriptions',
                            ),
                          ),
                      ],
                    ),
            ),
            if (!mrr)
              const Section(
                title: 'Monthly recurring revenue',
                child: Text(
                  'Not available yet: online billing is not enabled, so there is no reliable revenue data.',
                ),
              ),
            Section(
              title: 'Recent clinic applications',
              trailing: TextButton(
                onPressed: () => context.go('/platform/applications'),
                child: const Text('View all'),
              ),
              child: recentApps.isEmpty
                  ? const Text('No applications yet.')
                  : Column(
                      children: [
                        for (final a in recentApps)
                          ListTile(
                            dense: true,
                            title: Text('${a['clinicName']}'),
                            subtitle: Text(Fmt.date(a['submittedAt'])),
                            trailing: statusChip(a['status']),
                            onTap: () => context.go(
                              '/platform/applications/${a['applicationId']}',
                            ),
                          ),
                      ],
                    ),
            ),
            Section(
              title: 'Recently approved clinics',
              child: recentTenants.isEmpty
                  ? const Text('No approved clinics yet.')
                  : Column(
                      children: [
                        for (final t in recentTenants)
                          ListTile(
                            dense: true,
                            title: Text('${t['clinicName']}'),
                            subtitle: Text(Fmt.date(t['approvedAt'])),
                            trailing: statusChip(t['status']),
                            onTap: () => context.go(
                              '/platform/tenants/${t['tenantId']}',
                            ),
                          ),
                      ],
                    ),
            ),
            Section(
              title: 'Recent platform activity',
              child: activity.isEmpty
                  ? const Text('No activity yet.')
                  : Column(
                      children: [
                        for (final a in activity)
                          ListTile(
                            dense: true,
                            title: Text(Fmt.humanize(a['action'])),
                            subtitle: Text(
                              '${Fmt.dateTime(a['timestamp'])} · ${a['actorRole'] ?? 'system'}',
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _Stats extends StatelessWidget {
  const _Stats({required this.title, required this.tiles});

  final String title;
  final List<(String, Object?)> tiles;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: EcSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: EcTypography.subsectionTitle),
          const SizedBox(height: EcSpacing.sm),
          Wrap(
            spacing: EcSpacing.md,
            runSpacing: EcSpacing.md,
            children: [
              for (final (label, value) in tiles)
                SizedBox(
                  width: 200,
                  child: EcStatTile(value: '${value ?? 0}', label: label),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
