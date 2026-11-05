import 'package:common_models/common_models.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../control_plane/data/control_plane_repository.dart';
import '../control_plane/providers.dart';
import '../shared/async_body.dart';
import '../shared/reason_dialog.dart';
import '../shared/ui_kit.dart';

const _warningText = {
  'never_reviewed': 'Not reviewed yet',
  'no_review_sources': 'No review sources recorded',
  'no_suggested_timezone': 'No suggested time zone',
  'no_supported_currencies': 'No supported currencies listed',
  'postal_required_without_pattern': 'Postal code required but no format set',
  'no_native_name': 'No native-language name',
  'invalid_profile': 'Stored profile is invalid and is hidden from onboarding',
};

/// Platform-managed country master: availability for new clinics, version,
/// completeness warnings. Every change needs a reason and is audited by the
/// backend; a country with active clinics cannot be disabled.
class CountriesPage extends ConsumerWidget {
  const CountriesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final perms = ref.watch(platformPermissionsProvider);
    final canManage = perms.contains(Permission.manageCountries);
    final value = ref.watch(countriesProvider);
    void reload() => ref.invalidate(countriesProvider);
    final repo = ref.read(controlPlaneRepositoryProvider);

    return AsyncBody<List<Json>>(
      value: value,
      onRetry: reload,
      builder: (countries) => ListView(
        padding: const EdgeInsets.all(EcSpacing.lg),
        children: [
          PageHeader(
            title: 'Countries',
            subtitle:
                'Where new clinics can register. A clinic\'s legal country is '
                'fixed when it is approved and can only be corrected by an '
                'audited migration.',
            actions: [
              EcSecondaryButton(
                label: 'Backfill report',
                compact: true,
                onPressed: () =>
                    context.go('/platform/countries/backfill-report'),
              ),
              if (canManage)
                EcSecondaryButton(
                  label: 'Seed India and UAE',
                  compact: true,
                  onPressed: () => runAction(
                    context,
                    action: repo.seedCountries,
                    success:
                        'Baseline profiles checked. Existing profiles were not changed.',
                    after: reload,
                  ),
                ),
            ],
          ),
          if (countries.isEmpty)
            const EcEmptyState(
              title: 'No countries yet',
              message:
                  'Seed the reviewed India and UAE profiles, or add a country through the API.',
              icon: Icons.public,
            ),
          for (final c in countries)
            Padding(
              padding: const EdgeInsets.only(bottom: EcSpacing.md),
              child: _CountryCard(
                country: c,
                canManage: canManage,
                onChanged: reload,
              ),
            ),
        ],
      ),
    );
  }
}

class _CountryCard extends ConsumerWidget {
  const _CountryCard({
    required this.country,
    required this.canManage,
    required this.onChanged,
  });

  final Json country;
  final bool canManage;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = country;
    final code = '${c['code']}';
    final invalid = c['invalid'] == true;
    final version = c['configurationVersion'] as int?;
    final active = (c['activeTenants'] as int?) ?? 0;
    final onboarding = c['onboardingEnabled'] == true;
    final warnings = ((c['completenessWarnings'] as List?) ?? const [])
        .map((w) => _warningText['$w'] ?? '$w')
        .toList();
    final repo = ref.read(controlPlaneRepositoryProvider);

    Future<void> change(
      String title,
      String message,
      Json patch, {
      bool destructive = false,
    }) async {
      final reason = await showReasonDialog(
        context,
        title: title,
        message: message,
        confirmLabel: 'Confirm',
        destructive: destructive,
      );
      if (reason == null || !context.mounted) return;
      await runAction(
        context,
        action: () => repo.updateCountry(code, {
          'expectedVersion': version,
          'reason': reason,
          ...patch,
        }),
        success: 'Country updated.',
        after: onChanged,
      );
    }

    return EcCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: EcSpacing.sm,
            runSpacing: EcSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                invalid ? code : '${c['name']} ($code)',
                style: EcTypography.subsectionTitle,
              ),
              if (!invalid) statusChip(c['status']),
              if (!invalid)
                EcStatusChip(
                  label: onboarding ? 'Onboarding open' : 'Onboarding paused',
                  tone: onboarding
                      ? EcStatusTone.success
                      : EcStatusTone.warning,
                ),
              if (invalid)
                const EcStatusChip(label: 'Invalid', tone: EcStatusTone.error),
            ],
          ),
          if (!invalid) ...[
            const SizedBox(height: EcSpacing.sm),
            Text(
              '${c['callingCode']} · ${c['defaultCurrency']} · '
              '${(c['suggestedTimezones'] as List).join(', ')} · '
              'version $version · $active active clinic${active == 1 ? '' : 's'}',
              style: EcTypography.bodySecondary,
            ),
          ],
          if (warnings.isNotEmpty) ...[
            const SizedBox(height: EcSpacing.sm),
            for (final w in warnings) Text('• $w', style: EcTypography.helper),
          ],
          if (canManage && !invalid) ...[
            const SizedBox(height: EcSpacing.md),
            Wrap(
              spacing: EcSpacing.sm,
              runSpacing: EcSpacing.sm,
              children: [
                EcSecondaryButton(
                  label: onboarding ? 'Pause onboarding' : 'Open onboarding',
                  compact: true,
                  onPressed: () => change(
                    onboarding ? 'Pause onboarding?' : 'Open onboarding?',
                    onboarding
                        ? 'New clinics will not be able to choose this country. Existing clinics are not affected.'
                        : 'New clinics will be able to choose this country. The review date and sources must be recorded first.',
                    {'onboardingEnabled': !onboarding},
                  ),
                ),
                if (c['status'] == 'supported')
                  Tooltip(
                    message: active > 0
                        ? 'Not allowed while clinics use this country.'
                        : 'Disable this country.',
                    child: EcSecondaryButton(
                      label: 'Disable',
                      compact: true,
                      onPressed: active > 0
                          ? null
                          : () => change(
                              'Disable $code?',
                              'The country can no longer be used. No clinics use it.',
                              {
                                'status': 'disabled',
                                'onboardingEnabled': false,
                              },
                              destructive: true,
                            ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

const _classTone = {
  'verified': EcStatusTone.success,
  'ambiguous': EcStatusTone.warning,
  'unmapped': EcStatusTone.error,
};

/// Dry-run report of existing clinics that have no legal country yet. Nothing
/// is changed by viewing it; each clinic is assigned individually, with a
/// reason, through an audited action.
class BackfillReportPage extends ConsumerWidget {
  const BackfillReportPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canMigrate = ref
        .watch(platformPermissionsProvider)
        .contains(Permission.migrateTenantCountry);
    final value = ref.watch(backfillReportProvider);
    void reload() => ref.invalidate(backfillReportProvider);
    final countries = ref.watch(countriesProvider).value ?? const <Json>[];
    return AsyncBody<Json>(
      value: value,
      onRetry: reload,
      builder: (report) {
        final summary = (report['summary']! as Map).cast<String, Object?>();
        final rows = (report['tenants']! as List).cast<Json>();
        return ListView(
          padding: const EdgeInsets.all(EcSpacing.lg),
          children: [
            PageHeader(
              title: 'Country backfill report',
              subtitle:
                  'Dry run: classifies clinics without a legal country from what '
                  'the applicant entered. Nothing is changed until you assign a '
                  'country to a clinic below.',
              actions: [
                EcSecondaryButton(
                  label: 'Back to countries',
                  compact: true,
                  onPressed: () => context.go('/platform/countries'),
                ),
              ],
            ),
            Wrap(
              spacing: EcSpacing.sm,
              children: [
                EcStatusChip(
                  label: 'Already assigned: ${report['alreadyAssigned']}',
                  tone: EcStatusTone.info,
                ),
                for (final k in const ['verified', 'ambiguous', 'unmapped'])
                  EcStatusChip(
                    label: '$k: ${summary[k]}',
                    tone: _classTone[k]!,
                  ),
              ],
            ),
            const SizedBox(height: EcSpacing.lg),
            if (rows.isEmpty)
              const EcEmptyState(
                title: 'Nothing to migrate',
                message: 'Every clinic already has a legal country.',
                icon: Icons.check_circle_outline,
              ),
            for (final r in rows)
              Padding(
                padding: const EdgeInsets.only(bottom: EcSpacing.md),
                child: EcCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: EcSpacing.sm,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            '${r['clinicName']}',
                            style: EcTypography.subsectionTitle,
                          ),
                          EcStatusChip(
                            label: '${r['classification']}',
                            tone:
                                _classTone['${r['classification']}'] ??
                                EcStatusTone.neutral,
                          ),
                          if (r['candidateCountry'] != null)
                            EcStatusChip(
                              label: 'Candidate: ${r['candidateCountry']}',
                              tone: EcStatusTone.info,
                            ),
                        ],
                      ),
                      if ((r['reasons'] as List).isNotEmpty) ...[
                        const SizedBox(height: EcSpacing.xs),
                        Text(
                          (r['reasons'] as List).join(', '),
                          style: EcTypography.helper,
                        ),
                      ],
                      if (canMigrate) ...[
                        const SizedBox(height: EcSpacing.md),
                        EcSecondaryButton(
                          label: 'Assign country…',
                          compact: true,
                          onPressed: () => _assign(
                            context,
                            ref,
                            tenant: r,
                            countries: countries,
                            onDone: () {
                              reload();
                              ref.invalidate(countriesProvider);
                            },
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Future<void> _assign(
    BuildContext context,
    WidgetRef ref, {
    required Json tenant,
    required List<Json> countries,
    required VoidCallback onDone,
  }) async {
    final options = [
      for (final c in countries)
        if (c['status'] == 'supported') '${c['code']}',
    ];
    final picked = await showDialog<(String, String)>(
      context: context,
      builder: (_) => _AssignDialog(
        clinic: '${tenant['clinicName']}',
        options: options,
        initial: tenant['candidateCountry'] as String?,
      ),
    );
    if (picked == null || !context.mounted) return;
    await runAction(
      context,
      action: () => ref
          .read(controlPlaneRepositoryProvider)
          .assignTenantCountry(
            '${tenant['tenantId']}',
            countryCode: picked.$1,
            reason: picked.$2,
          ),
      success: 'Country assigned.',
      after: onDone,
    );
  }
}

class _AssignDialog extends StatefulWidget {
  const _AssignDialog({
    required this.clinic,
    required this.options,
    required this.initial,
  });

  final String clinic;
  final List<String> options;
  final String? initial;

  @override
  State<_AssignDialog> createState() => _AssignDialogState();
}

class _AssignDialogState extends State<_AssignDialog> {
  final _form = GlobalKey<FormState>();
  final _reason = TextEditingController();
  String? _code;

  @override
  void initState() {
    super.initState();
    _code = widget.options.contains(widget.initial) ? widget.initial : null;
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Assign country to ${widget.clinic}'),
      content: Form(
        key: _form,
        child: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'This sets the clinic\'s legal country. It is audited and '
                'cannot be changed by the clinic.',
              ),
              const SizedBox(height: EcSpacing.md),
              EcDropdown<String>(
                label: 'Country',
                items: widget.options,
                value: _code,
                onChanged: (v) => setState(() => _code = v),
                validator: (v) => v == null ? 'Choose a country.' : null,
              ),
              const SizedBox(height: EcSpacing.md),
              EcTextField(
                label: 'Reason',
                controller: _reason,
                maxLines: 2,
                validator: (v) => (v ?? '').trim().length < 3
                    ? 'Enter at least 3 characters.'
                    : null,
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
        TextButton(
          onPressed: () {
            if (!_form.currentState!.validate()) return;
            Navigator.of(context).pop((_code!, _reason.text.trim()));
          },
          child: const Text('Assign'),
        ),
      ],
    );
  }
}
