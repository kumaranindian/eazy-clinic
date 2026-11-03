import 'package:common_models/common_models.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../control_plane/data/control_plane_repository.dart';
import '../control_plane/providers.dart';
import '../shared/async_body.dart';
import '../shared/reason_dialog.dart';
import '../shared/ui_helpers.dart';
import '../shared/ui_kit.dart';

class TenantsPage extends StatelessWidget {
  const TenantsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListScreen(
      title: 'Tenants',
      subtitle: 'Clinics that have been approved on EazyClinic.',
      path: '/platform/tenants',
      searchHint: 'Search clinic name',
      statusOptions: [for (final s in TenantStatus.values) s.wireName],
      emptyTitle: 'No tenants found',
      emptyMessage:
          'Tenants are created when a clinic application is approved.',
      rowBuilder: (context, t) => RowCard(
        title: '${t['clinicName']}',
        subtitle: '${t['city'] ?? ''} · ${t['tenantId']}',
        trailing: Fmt.date(t['approvedAt']),
        status: t['status'],
        onTap: () => context.go('/platform/tenants/${t['tenantId']}'),
      ),
    );
  }
}

class TenantDetailPage extends ConsumerWidget {
  const TenantDetailPage({required this.tenantId, super.key});

  final String tenantId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(tenantDetailProvider(tenantId));
    final can = ref.watch(platformPermissionsProvider);
    void reload() => ref.invalidate(tenantDetailProvider(tenantId));
    return AsyncBody(
      value: value,
      onRetry: reload,
      builder: (t) {
        final status = t['status'] as String;
        final owner = (t['owner'] as Map?)?.cast<String, Object?>() ?? const {};
        final application = (t['application'] as Map?)?.cast<String, Object?>();
        final sub = (t['subscription'] as Map?)?.cast<String, Object?>();
        final job = (t['provisioning'] as Map?)?.cast<String, Object?>();
        final audit = (t['auditHistory'] as List? ?? const [])
            .cast<Map<String, Object?>>();
        final repo = ref.read(controlPlaneRepositoryProvider);
        final manage = can.contains(Permission.manageTenants);
        final manageSubs = can.contains(Permission.manageSubscriptions);
        return ListView(
          padding: const EdgeInsets.all(EcSpacing.lg),
          children: [
            PageHeader(
              title: '${t['clinicName']}',
              subtitle: 'Tenant ${t['tenantId']} · /${t['slug']}',
              actions: [
                statusChip(status),
                if (manage && status == 'provisioning')
                  EcPrimaryButton(
                    label: 'Retry provisioning',
                    compact: true,
                    onPressed: () => runAction(
                      context,
                      action: () => repo.retryProvisioning(tenantId),
                      success: 'Provisioning retried.',
                      after: reload,
                    ),
                  ),
                if (manage && status == 'active')
                  EcSecondaryButton(
                    label: 'Suspend',
                    compact: true,
                    onPressed: () async {
                      final reason = await showReasonDialog(
                        context,
                        title: 'Suspend clinic',
                        message:
                            'The clinic loses access immediately. Its data is kept.',
                        confirmLabel: 'Suspend clinic',
                        destructive: true,
                      );
                      if (reason != null && context.mounted) {
                        await runAction(
                          context,
                          action: () => repo.suspendTenant(tenantId, reason),
                          success: 'Clinic suspended.',
                          after: reload,
                        );
                      }
                    },
                  ),
                if (manage && status == 'suspended')
                  EcPrimaryButton(
                    label: 'Reactivate',
                    compact: true,
                    onPressed: () async {
                      final reason = await showReasonDialog(
                        context,
                        title: 'Reactivate clinic',
                        message:
                            'Requires a valid subscription. Access is restored only if backend checks pass.',
                        confirmLabel: 'Reactivate',
                      );
                      if (reason != null && context.mounted) {
                        await runAction(
                          context,
                          action: () => repo.reactivateTenant(tenantId, reason),
                          success: 'Clinic reactivated.',
                          after: reload,
                        );
                      }
                    },
                  ),
                if (manage && status != 'closed')
                  EcSecondaryButton(
                    label: 'Close clinic',
                    compact: true,
                    onPressed: () async {
                      final reason = await showReasonDialog(
                        context,
                        title: 'Close clinic',
                        message:
                            'Closing is final: the subscription is cancelled and the clinic cannot be reopened. '
                            'No clinical or financial data is deleted.',
                        confirmLabel: 'Close clinic permanently',
                        destructive: true,
                      );
                      if (reason != null && context.mounted) {
                        await runAction(
                          context,
                          action: () => repo.closeTenant(tenantId, reason),
                          success: 'Clinic closed.',
                          after: reload,
                        );
                      }
                    },
                  ),
              ],
            ),
            if (status == 'provisioning' && job?['status'] == 'failed')
              Padding(
                padding: const EdgeInsets.only(bottom: EcSpacing.lg),
                child: EcInlineMessage(
                  message:
                      'Provisioning failed (${job!['lastError']}). The clinic is not active yet. Retry when the cause is fixed.',
                ),
              ),
            if (t['statusReason'] != null)
              Padding(
                padding: const EdgeInsets.only(bottom: EcSpacing.lg),
                child: EcInlineMessage(
                  tone: EcStatusTone.info,
                  message: 'Last status reason: ${t['statusReason']}',
                ),
              ),
            Section(
              title: 'Overview',
              child: KeyValues([
                ('Tenant ID', t['tenantId']),
                ('Slug', t['slug']),
                ('Type', Fmt.humanize(t['clinicType'])),
                ('Created', Fmt.dateTime(t['createdAt'])),
                ('Approved', Fmt.dateTime(t['approvedAt'])),
                ('Approved by', t['approvedBy']),
              ]),
            ),
            Section(
              title: 'Owner',
              child: KeyValues([
                ('Name', owner['fullName']),
                ('Email', owner['email']),
                ('Phone', owner['phone']),
                ('Owner account ID', t['ownerUid']),
              ]),
            ),
            Section(
              title: 'Application',
              child: application == null
                  ? const Text('—')
                  : TextButton(
                      onPressed: () => context.go(
                        '/platform/applications/${application['applicationId']}',
                      ),
                      child: Text(
                        '${application['applicationId']} (${Fmt.humanize(application['status'])})',
                      ),
                    ),
            ),
            Section(
              title: 'Subscription',
              trailing:
                  manageSubs &&
                      (sub == null ||
                          ['expired', 'cancelled'].contains(sub['status']))
                  ? TextButton(
                      onPressed: () => _assign(context, ref, reload),
                      child: const Text('Assign subscription'),
                    )
                  : null,
              child: sub == null
                  ? const Text('No subscription.')
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        KeyValues([
                          ('Plan', '${sub['name']} (v${sub['planVersion']})'),
                          ('Status', statusChip(sub['effectiveStatus'])),
                          (
                            'Price',
                            '${Fmt.money(sub['priceMinor'], sub['currency'])} / ${sub['billingInterval']}',
                          ),
                          ('Ends', Fmt.date(sub['endDate'])),
                        ]),
                        TextButton(
                          onPressed: () => context.go(
                            '/platform/subscriptions/${sub['subscriptionId']}',
                          ),
                          child: const Text('Open subscription'),
                        ),
                      ],
                    ),
            ),
            if (job != null)
              Section(
                title: 'Provisioning',
                child: KeyValues([
                  ('Job status', statusChip(job['status'])),
                  ('Attempts', job['attempts']),
                  ('Last error', job['lastError']),
                ]),
              ),
            Section(
              title: 'Audit history',
              child: audit.isEmpty
                  ? const Text('No entries.')
                  : Column(
                      children: [
                        for (final a in audit)
                          ListTile(
                            dense: true,
                            title: Text(Fmt.humanize(a['action'])),
                            subtitle: Text(
                              '${Fmt.dateTime(a['timestamp'])} · ${a['actorRole'] ?? 'system'}${a['reason'] != null ? ' · ${a['reason']}' : ''}',
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

  Future<void> _assign(
    BuildContext context,
    WidgetRef ref,
    VoidCallback reload,
  ) async {
    final choice = await showDialog<(String, bool)>(
      context: context,
      builder: (_) => const _AssignDialog(),
    );
    if (choice == null || !context.mounted) return;
    await runAction(
      context,
      action: () => ref
          .read(controlPlaneRepositoryProvider)
          .assignSubscription(
            tenantId: tenantId,
            planId: choice.$1,
            trial: choice.$2,
            reason: 'Assigned by platform admin',
          ),
      success: 'Subscription assigned.',
      after: reload,
    );
  }
}

class _AssignDialog extends ConsumerStatefulWidget {
  const _AssignDialog();

  @override
  ConsumerState<_AssignDialog> createState() => _AssignDialogState();
}

class _AssignDialogState extends ConsumerState<_AssignDialog> {
  String? _plan;
  bool _trial = false;

  @override
  Widget build(BuildContext context) {
    final plans = ref.watch(activePlansProvider);
    return AlertDialog(
      title: const Text('Assign subscription'),
      content: SizedBox(
        width: 420,
        child: plans.when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => Text(failureText(e)),
          data: (list) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              EcDropdown<String>(
                label: 'Plan',
                items: [for (final p in list) p['planId'] as String],
                value: _plan,
                itemLabel: (id) =>
                    '${list.firstWhere((p) => p['planId'] == id)['name']}',
                onChanged: (v) => setState(() => _plan = v),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _trial,
                onChanged: (v) => setState(() => _trial = v ?? false),
                title: const Text('Start as a trial'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _plan == null
              ? null
              : () => Navigator.of(context).pop((_plan!, _trial)),
          child: const Text('Assign'),
        ),
      ],
    );
  }
}
