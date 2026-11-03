import 'package:app_core/app_core.dart';
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

class SubscriptionsPage extends StatelessWidget {
  const SubscriptionsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListScreen(
      title: 'Subscriptions',
      subtitle: 'Admin-managed. No online payments are connected yet.',
      path: '/platform/subscriptions',
      statusOptions: [for (final s in SubscriptionStatus.values) s.wireName],
      emptyTitle: 'No subscriptions yet',
      emptyMessage:
          'Assign a plan to an approved clinic to create a subscription.',
      rowBuilder: (context, s) => RowCard(
        title: '${s['name']} · ${s['tenantId']}',
        subtitle:
            '${Fmt.money(s['priceMinor'], s['currency'])} / ${s['billingInterval']} · ends ${Fmt.date(s['endDate'])}',
        status: s['status'],
        onTap: () =>
            context.go('/platform/subscriptions/${s['subscriptionId']}'),
      ),
    );
  }
}

class SubscriptionDetailPage extends ConsumerWidget {
  const SubscriptionDetailPage({required this.subscriptionId, super.key});

  final String subscriptionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(subscriptionDetailProvider(subscriptionId));
    final can = ref.watch(platformPermissionsProvider);
    void reload() => ref.invalidate(subscriptionDetailProvider(subscriptionId));
    return AsyncBody(
      value: value,
      onRetry: reload,
      builder: (s) {
        final repo = ref.read(controlPlaneRepositoryProvider);
        final status = s['status'] as String;
        final effective = s['effectiveStatus'] as String;
        final history = (s['history']! as List).cast<Map<String, Object?>>();
        final overrides = (s['overrides'] as Map<String, Object?>?) ?? const {};
        final manage = can.contains(Permission.manageSubscriptions);
        final live = status != 'cancelled';
        Future<void> withReason(
          String title,
          String label,
          Future<void> Function(String) call,
          String done, {
          bool destructive = false,
        }) async {
          final reason = await showReasonDialog(
            context,
            title: title,
            message: 'This is recorded in the audit log.',
            confirmLabel: label,
            destructive: destructive,
          );
          if (reason != null && context.mounted) {
            await runAction(
              context,
              action: () => call(reason),
              success: done,
              after: reload,
            );
          }
        }

        return ListView(
          padding: const EdgeInsets.all(EcSpacing.lg),
          children: [
            PageHeader(
              title: '${s['name']}',
              subtitle:
                  '${s['clinicName'] ?? s['tenantId']} · ${s['subscriptionId']}',
              actions: [
                statusChip(effective),
                if (manage && live) ...[
                  if (status == 'trial')
                    EcSecondaryButton(
                      label: 'Extend trial',
                      compact: true,
                      onPressed: () async {
                        final days = await showDialog<int>(
                          context: context,
                          builder: (_) => const _DaysDialog(),
                        );
                        if (days == null || !context.mounted) return;
                        await withReason(
                          'Extend trial by $days days',
                          'Extend',
                          (r) => repo.extendTrial(subscriptionId, days, r),
                          'Trial extended.',
                        );
                      },
                    ),
                  EcSecondaryButton(
                    label: 'Renew',
                    compact: true,
                    onPressed: () => runAction(
                      context,
                      action: () => repo.renew(subscriptionId),
                      success: 'Subscription renewed.',
                      after: reload,
                    ),
                  ),
                  if (status == 'active')
                    EcSecondaryButton(
                      label: 'Mark past due',
                      compact: true,
                      onPressed: () => runAction(
                        context,
                        action: () => repo.markPastDue(subscriptionId),
                        success: 'Marked past due.',
                        after: reload,
                      ),
                    ),
                  EcSecondaryButton(
                    label: 'Change plan',
                    compact: true,
                    onPressed: () async {
                      final planId = await showDialog<String>(
                        context: context,
                        builder: (_) => const _PlanPickerDialog(),
                      );
                      if (planId == null || !context.mounted) return;
                      await withReason(
                        'Change plan',
                        'Change plan',
                        (r) => repo.changePlan(subscriptionId, planId, r),
                        'Plan changed.',
                      );
                    },
                  ),
                  if (status != 'suspended')
                    EcSecondaryButton(
                      label: 'Suspend',
                      compact: true,
                      onPressed: () => withReason(
                        'Suspend subscription',
                        'Suspend',
                        (r) => repo.suspendSubscription(subscriptionId, r),
                        'Subscription suspended.',
                        destructive: true,
                      ),
                    ),
                  EcSecondaryButton(
                    label: 'Cancel',
                    compact: true,
                    onPressed: () => withReason(
                      'Cancel subscription',
                      'Cancel subscription',
                      (r) => repo.cancelSubscription(subscriptionId, r),
                      'Subscription cancelled.',
                      destructive: true,
                    ),
                  ),
                ],
              ],
            ),
            if (effective != status)
              Padding(
                padding: const EdgeInsets.only(bottom: EcSpacing.lg),
                child: EcInlineMessage(
                  tone: EcStatusTone.warning,
                  message:
                      'Recorded status is "${Fmt.humanize(status)}" but its end date has passed, so it is treated as expired. Renew it to restore access.',
                ),
              ),
            Section(
              title: 'Terms (snapshot at assignment)',
              child: KeyValues([
                ('Tenant', s['tenantId']),
                ('Plan', '${s['name']} (v${s['planVersion']})'),
                (
                  'Price',
                  '${Fmt.money(s['priceMinor'], s['currency'])} / ${s['billingInterval']}',
                ),
                ('Started', Fmt.date(s['startDate'])),
                ('Trial ends', Fmt.date(s['trialEndDate'])),
                ('Ends', Fmt.date(s['endDate'])),
                ('Cancellation reason', s['cancellationReason']),
                ('Previous subscription', s['previousSubscriptionId']),
              ]),
            ),
            Section(
              title: 'Entitlement overrides',
              trailing: can.contains(Permission.overrideEntitlements) && live
                  ? TextButton(
                      onPressed: () async {
                        final result = await showDialog<Map<String, bool>>(
                          context: context,
                          builder: (_) => _OverridesDialog(
                            current:
                                ((overrides['features']
                                            as Map<String, Object?>?) ??
                                        const {})
                                    .map((k, v) => MapEntry(k, v == true)),
                          ),
                        );
                        if (result == null || !context.mounted) return;
                        await withReason(
                          'Save entitlement overrides',
                          'Save',
                          (r) => ref
                              .read(apiClientProvider)
                              .patch(
                                '/platform/subscriptions/$subscriptionId',
                                body: {
                                  'overrides': result.isEmpty
                                      ? <String, Object?>{}
                                      : {'features': result},
                                  'reason': r,
                                },
                              ),
                          'Overrides saved.',
                        );
                      },
                      child: const Text('Edit'),
                    )
                  : null,
              child: overrides.isEmpty
                  ? const Text('None. The plan defaults apply.')
                  : KeyValues([
                      for (final e
                          in ((overrides['features']
                                      as Map<String, Object?>?) ??
                                  const {})
                              .entries)
                        (
                          Fmt.humanize(e.key),
                          e.value == true ? 'Enabled' : 'Disabled',
                        ),
                    ]),
            ),
            Section(
              title: 'History',
              child: Column(
                children: [
                  for (final h in history)
                    ListTile(
                      dense: true,
                      title: Text(Fmt.humanize(h['type'])),
                      subtitle: Text(
                        '${Fmt.dateTime(h['at'])} · ${h['actorRole']}${h['reason'] != null ? ' · ${h['reason']}' : ''}',
                      ),
                      trailing: h['toStatus'] == null
                          ? null
                          : statusChip(h['toStatus']),
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

class _DaysDialog extends StatefulWidget {
  const _DaysDialog();

  @override
  State<_DaysDialog> createState() => _DaysDialogState();
}

class _DaysDialogState extends State<_DaysDialog> {
  final _form = GlobalKey<FormState>();
  final _days = TextEditingController(text: '7');

  @override
  void dispose() {
    _days.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Extend trial'),
      content: Form(
        key: _form,
        child: EcTextField(
          label: 'Days (1–90)',
          controller: _days,
          keyboardType: TextInputType.number,
          validator: (v) {
            final n = int.tryParse((v ?? '').trim());
            return n == null || n < 1 || n > 90 ? 'Enter 1 to 90.' : null;
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (_form.currentState!.validate()) {
              Navigator.of(context).pop(int.parse(_days.text.trim()));
            }
          },
          child: const Text('Continue'),
        ),
      ],
    );
  }
}

class _PlanPickerDialog extends ConsumerStatefulWidget {
  const _PlanPickerDialog();

  @override
  ConsumerState<_PlanPickerDialog> createState() => _PlanPickerDialogState();
}

class _PlanPickerDialogState extends ConsumerState<_PlanPickerDialog> {
  String? _plan;

  @override
  Widget build(BuildContext context) {
    final plans = ref.watch(activePlansProvider);
    return AlertDialog(
      title: const Text('Choose the new plan'),
      content: SizedBox(
        width: 420,
        child: plans.when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => Text(failureText(e)),
          data: (list) => EcDropdown<String>(
            label: 'Plan',
            items: [for (final p in list) p['planId'] as String],
            value: _plan,
            itemLabel: (id) =>
                '${list.firstWhere((p) => p['planId'] == id)['name']}',
            onChanged: (v) => setState(() => _plan = v),
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
              : () => Navigator.of(context).pop(_plan),
          child: const Text('Continue'),
        ),
      ],
    );
  }
}

/// Per-feature override: plan default / enabled / disabled.
class _OverridesDialog extends StatefulWidget {
  const _OverridesDialog({required this.current});
  final Map<String, bool> current;

  @override
  State<_OverridesDialog> createState() => _OverridesDialogState();
}

class _OverridesDialogState extends State<_OverridesDialog> {
  late final Map<String, bool?> _state = {
    for (final k in FeatureKey.all) k: widget.current[k],
  };

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Entitlement overrides'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            children: [
              for (final k in FeatureKey.all)
                Row(
                  children: [
                    Expanded(child: Text(Fmt.humanize(k))),
                    DropdownButton<bool?>(
                      value: _state[k],
                      items: const [
                        DropdownMenuItem(
                          value: null,
                          child: Text('Plan default'),
                        ),
                        DropdownMenuItem(value: true, child: Text('Enabled')),
                        DropdownMenuItem(value: false, child: Text('Disabled')),
                      ],
                      onChanged: (v) => setState(() => _state[k] = v),
                    ),
                  ],
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
          onPressed: () => Navigator.of(context).pop({
            for (final e in _state.entries)
              if (e.value != null) e.key: e.value!,
          }),
          child: const Text('Continue'),
        ),
      ],
    );
  }
}
