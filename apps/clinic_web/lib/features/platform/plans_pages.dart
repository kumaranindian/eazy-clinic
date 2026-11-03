import 'package:app_core/app_core.dart';
import 'package:common_models/common_models.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../control_plane/data/control_plane_repository.dart';
import '../control_plane/providers.dart';
import '../shared/async_body.dart';
import '../shared/ui_helpers.dart';
import '../shared/ui_kit.dart';

class PlansPage extends ConsumerWidget {
  const PlansPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canManage = ref
        .watch(platformPermissionsProvider)
        .contains(Permission.managePlans);
    return ListScreen(
      title: 'Subscription plans',
      subtitle:
          'Plans define price, limits and enabled features. Limits are enforced by the backend.',
      path: '/platform/subscription-plans',
      statusOptions: [for (final s in PlanStatus.values) s.wireName],
      emptyTitle: 'No plans yet',
      emptyMessage:
          'Create a plan, then activate it so tenants can be assigned to it.',
      actions: [
        if (canManage)
          EcPrimaryButton(
            label: 'New plan',
            icon: Icons.add,
            compact: true,
            onPressed: () => context.go('/platform/plans/new'),
          ),
      ],
      rowBuilder: (context, p) => RowCard(
        title: '${p['name']}',
        subtitle:
            '${Fmt.money(p['priceMinor'], p['currency'])} / ${p['billingInterval']} · trial ${p['trialDays']} days · v${p['version']}',
        status: p['status'],
        onTap: () => context.go('/platform/plans/${p['planId']}'),
      ),
    );
  }
}

class PlanDetailPage extends ConsumerWidget {
  const PlanDetailPage({required this.planId, super.key});

  final String planId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(planDetailProvider(planId));
    final canManage = ref
        .watch(platformPermissionsProvider)
        .contains(Permission.managePlans);
    void reload() => ref.invalidate(planDetailProvider(planId));
    return AsyncBody(
      value: value,
      onRetry: reload,
      builder: (p) {
        final limits = (p['limits']! as Map<String, Object?>);
        final features = (p['features']! as Map<String, Object?>);
        final tenants = (p['assignedTenants']! as List)
            .cast<Map<String, Object?>>();
        final repo = ref.read(controlPlaneRepositoryProvider);
        final active = p['status'] == 'active';
        return ListView(
          padding: const EdgeInsets.all(EcSpacing.lg),
          children: [
            PageHeader(
              title: '${p['name']}',
              subtitle: 'Plan ${p['planId']} · version ${p['version']}',
              actions: [
                statusChip(p['status']),
                if (canManage)
                  EcSecondaryButton(
                    label: 'Edit',
                    compact: true,
                    onPressed: () => context.go('/platform/plans/$planId/edit'),
                  ),
                if (canManage)
                  EcSecondaryButton(
                    label: active ? 'Deactivate' : 'Activate',
                    compact: true,
                    onPressed: () async {
                      if (active) {
                        final ok = await showEcConfirmDialog(
                          context,
                          title: 'Deactivate plan?',
                          message:
                              'New subscriptions can no longer use this plan. Plans with live subscriptions cannot be deactivated.',
                          confirmLabel: 'Deactivate',
                        );
                        if (!ok || !context.mounted) return;
                      }
                      await runAction(
                        context,
                        action: () =>
                            repo.setPlanActive(planId, active: !active),
                        success: active
                            ? 'Plan deactivated.'
                            : 'Plan activated.',
                        after: reload,
                      );
                    },
                  ),
              ],
            ),
            if ((p['description'] as String?)?.isNotEmpty ?? false)
              Padding(
                padding: const EdgeInsets.only(bottom: EcSpacing.lg),
                child: Text('${p['description']}'),
              ),
            Section(
              title: 'Pricing',
              child: KeyValues([
                (
                  'Price',
                  '${Fmt.money(p['priceMinor'], p['currency'])} / ${p['billingInterval']}',
                ),
                ('Trial', '${p['trialDays']} days'),
                ('Updated', Fmt.dateTime(p['updatedAt'])),
              ]),
            ),
            Section(
              title: 'Limits',
              child: KeyValues([
                for (final k in LimitKey.all)
                  (Fmt.humanize(k), Fmt.limit(limits[k])),
              ]),
            ),
            Section(
              title: 'Features',
              child: Wrap(
                spacing: EcSpacing.sm,
                runSpacing: EcSpacing.sm,
                children: [
                  for (final k in FeatureKey.all)
                    EcStatusChip(
                      label: Fmt.humanize(k),
                      tone: features[k] == true
                          ? EcStatusTone.success
                          : EcStatusTone.neutral,
                    ),
                ],
              ),
            ),
            Section(
              title: 'Tenants on this plan',
              child: tenants.isEmpty
                  ? const Text('No live subscriptions use this plan.')
                  : Column(
                      children: [
                        for (final t in tenants)
                          ListTile(
                            dense: true,
                            title: Text('${t['clinicName']}'),
                            trailing: statusChip(t['subscriptionStatus']),
                            onTap: () => context.go(
                              '/platform/tenants/${t['tenantId']}',
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

/// Create / edit form. Values are validated here for quick feedback and again
/// by the backend, which is authoritative.
class PlanFormPage extends ConsumerStatefulWidget {
  const PlanFormPage({this.planId, super.key});

  final String? planId;

  @override
  ConsumerState<PlanFormPage> createState() => _PlanFormPageState();
}

class _PlanFormPageState extends ConsumerState<PlanFormPage> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _price = TextEditingController(text: '0');
  final _trial = TextEditingController(text: '0');
  final Map<String, TextEditingController> _limits = {
    for (final k in LimitKey.all) k: TextEditingController(),
  };
  final Map<String, bool> _features = {
    for (final k in FeatureKey.all) k: false,
  };
  BillingInterval _interval = BillingInterval.monthly;
  bool _loaded = false;
  bool _saving = false;
  String? _error;

  bool get _editing => widget.planId != null;

  @override
  void dispose() {
    for (final c in [_name, _description, _price, _trial, ..._limits.values]) {
      c.dispose();
    }
    super.dispose();
  }

  void _fill(Json p) {
    _name.text = '${p['name']}';
    _description.text = '${p['description'] ?? ''}';
    _price.text = ((p['priceMinor']! as int) / 100).toStringAsFixed(2);
    _trial.text = '${p['trialDays']}';
    _interval =
        BillingInterval.tryParse(p['billingInterval'] as String?) ??
        BillingInterval.monthly;
    final limits = p['limits']! as Map<String, Object?>;
    for (final k in LimitKey.all) {
      _limits[k]!.text = limits[k] == null ? '' : '${limits[k]}';
    }
    final features = p['features']! as Map<String, Object?>;
    for (final k in FeatureKey.all) {
      _features[k] = features[k] == true;
    }
    _loaded = true;
  }

  String? _wholeNumber(String? v, {bool allowEmpty = false}) {
    final t = (v ?? '').trim();
    if (t.isEmpty) return allowEmpty ? null : 'Required.';
    final n = int.tryParse(t);
    return n == null || n < 0 ? 'Enter a whole number (0 or more).' : null;
  }

  String? _priceError(String? v) {
    final n = double.tryParse((v ?? '').trim());
    return n == null || n < 0
        ? 'Enter an amount in rupees, e.g. 999.00.'
        : null;
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final body = <String, Object?>{
      'name': _name.text.trim(),
      'description': _description.text.trim(),
      'billingInterval': _interval.wireName,
      'priceMinor': (double.parse(_price.text.trim()) * 100).round(),
      'currency': 'INR',
      'trialDays': int.parse(_trial.text.trim()),
      'limits': {
        for (final k in LimitKey.all)
          k: _limits[k]!.text.trim().isEmpty
              ? null
              : int.parse(_limits[k]!.text.trim()),
      },
      'features': Map<String, bool>.from(_features),
    };
    final repo = ref.read(controlPlaneRepositoryProvider);
    try {
      final saved = _editing
          ? await repo.updatePlan(widget.planId!, body)
          : await repo.createPlan(body);
      if (!mounted) return;
      ref.invalidate(planDetailProvider(saved['planId']! as String));
      context.go('/platform/plans/${saved['planId']}');
    } on ApiFailure catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = failureText(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_editing && !_loaded) {
      final value = ref.watch(planDetailProvider(widget.planId!));
      return AsyncBody(
        value: value,
        onRetry: () => ref.invalidate(planDetailProvider(widget.planId!)),
        builder: (p) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && !_loaded) setState(() => _fill(p));
          });
          return const EcLoadingIndicator();
        },
      );
    }
    return ListView(
      padding: const EdgeInsets.all(EcSpacing.lg),
      children: [
        PageHeader(
          title: _editing ? 'Edit plan' : 'New plan',
          subtitle:
              'Changes apply to new subscriptions. Existing subscriptions keep their original terms.',
        ),
        Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_error != null) ...[
                EcInlineMessage(message: _error!),
                const SizedBox(height: EcSpacing.lg),
              ],
              EcTextField(
                label: 'Plan name',
                controller: _name,
                enabled: !_saving,
                validator: (v) => (v ?? '').trim().length < 2
                    ? 'Enter a name (2–80 characters).'
                    : null,
              ),
              const SizedBox(height: EcSpacing.lg),
              EcTextField(
                label: 'Description',
                controller: _description,
                maxLines: 2,
                maxLength: 500,
                enabled: !_saving,
              ),
              const SizedBox(height: EcSpacing.lg),
              Wrap(
                spacing: EcSpacing.lg,
                runSpacing: EcSpacing.lg,
                children: [
                  SizedBox(
                    width: 220,
                    child: EcDropdown<BillingInterval>(
                      label: 'Billing interval',
                      items: BillingInterval.values,
                      value: _interval,
                      itemLabel: (i) => Fmt.humanize(i.wireName),
                      onChanged: _saving
                          ? null
                          : (v) => setState(() => _interval = v ?? _interval),
                    ),
                  ),
                  SizedBox(
                    width: 220,
                    child: EcTextField(
                      label: 'Price (₹)',
                      controller: _price,
                      enabled: !_saving,
                      keyboardType: TextInputType.number,
                      validator: _priceError,
                    ),
                  ),
                  SizedBox(
                    width: 220,
                    child: EcTextField(
                      label: 'Trial (days)',
                      controller: _trial,
                      enabled: !_saving,
                      keyboardType: TextInputType.number,
                      validator: _wholeNumber,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: EcSpacing.xl),
              Text(
                'Limits (leave empty for unlimited)',
                style: EcTypography.subsectionTitle,
              ),
              const SizedBox(height: EcSpacing.md),
              Wrap(
                spacing: EcSpacing.lg,
                runSpacing: EcSpacing.lg,
                children: [
                  for (final k in LimitKey.all)
                    SizedBox(
                      width: 220,
                      child: EcTextField(
                        label: Fmt.humanize(k),
                        controller: _limits[k],
                        enabled: !_saving,
                        keyboardType: TextInputType.number,
                        validator: (v) => _wholeNumber(v, allowEmpty: true),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: EcSpacing.xl),
              Text('Enabled features', style: EcTypography.subsectionTitle),
              Wrap(
                spacing: EcSpacing.lg,
                children: [
                  for (final k in FeatureKey.all)
                    SizedBox(
                      width: 300,
                      child: CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _features[k],
                        title: Text(Fmt.humanize(k)),
                        onChanged: _saving
                            ? null
                            : (v) => setState(() => _features[k] = v ?? false),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: EcSpacing.xl),
              Row(
                children: [
                  SizedBox(
                    width: 200,
                    child: EcPrimaryButton(
                      label: _editing ? 'Save changes' : 'Create plan',
                      isLoading: _saving,
                      onPressed: _save,
                    ),
                  ),
                  const SizedBox(width: EcSpacing.md),
                  TextButton(
                    onPressed: _saving
                        ? null
                        : () => context.go('/platform/plans'),
                    child: const Text('Cancel'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
