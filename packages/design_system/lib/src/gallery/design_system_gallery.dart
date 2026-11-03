import 'package:flutter/material.dart';

import '../tokens/ec_colors.dart';
import '../tokens/ec_dimensions.dart';
import '../tokens/ec_typography.dart';
import '../widgets/ec_app_bar.dart';
import '../widgets/ec_brand_logo.dart';
import '../widgets/ec_button.dart';
import '../widgets/ec_card.dart';
import '../widgets/ec_date_field.dart';
import '../widgets/ec_dialogs.dart';
import '../widgets/ec_dropdown.dart';
import '../widgets/ec_empty_state.dart';
import '../widgets/ec_error_state.dart';
import '../widgets/ec_loading.dart';
import '../widgets/ec_responsive.dart';
import '../widgets/ec_status_chip.dart';
import '../widgets/ec_text_field.dart';

/// Developer-only showcase of every design-system component.
///
/// Apps expose it at `/design-system` in dev and staging builds only; it is
/// never routed in production.
class DesignSystemGallery extends StatelessWidget {
  const DesignSystemGallery({super.key});

  static const String routePath = '/design-system';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const EcAppBar(title: 'Design system'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: EcSpacing.xl),
        child: EcResponsiveContainer(
          maxWidth: 720,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Center(child: EcBrandLogo.full(height: 140)),
              _section('Colours', const _ColourSwatches()),
              _section('Typography', const _TypeScale()),
              _section(
                'Buttons',
                Column(
                  children: [
                    EcPrimaryButton(label: 'Primary', onPressed: () {}),
                    const SizedBox(height: EcSpacing.md),
                    EcSecondaryButton(label: 'Secondary', onPressed: () {}),
                    const SizedBox(height: EcSpacing.md),
                    const EcPrimaryButton(label: 'Disabled', onPressed: null),
                    const SizedBox(height: EcSpacing.md),
                    EcPrimaryButton(
                      label: 'Saving',
                      onPressed: () {},
                      isLoading: true,
                    ),
                  ],
                ),
              ),
              _section('Inputs', const _InputsDemo()),
              _section(
                'Status',
                const Wrap(
                  spacing: EcSpacing.sm,
                  runSpacing: EcSpacing.sm,
                  children: [
                    EcStatusChip(label: 'Paid', tone: EcStatusTone.success),
                    EcStatusChip(label: 'Pending', tone: EcStatusTone.warning),
                    EcStatusChip(label: 'Cancelled', tone: EcStatusTone.error),
                    EcStatusChip(
                      label: 'Consultation',
                      tone: EcStatusTone.info,
                    ),
                    EcStatusChip(label: 'Draft'),
                  ],
                ),
              ),
              _section(
                'Cards',
                const Row(
                  children: [
                    Expanded(
                      child: EcStatTile(
                        value: '20',
                        label: "Today's Appointments",
                      ),
                    ),
                    SizedBox(width: EcSpacing.md),
                    Expanded(
                      child: EcStatTile(value: '5', label: 'New Patients'),
                    ),
                  ],
                ),
              ),
              _section(
                'Dialogs',
                Row(
                  children: [
                    Expanded(
                      child: EcSecondaryButton(
                        label: 'Confirm dialog',
                        onPressed: () => showEcConfirmDialog(
                          context,
                          title: 'Delete item?',
                          message: 'This cannot be undone.',
                          confirmLabel: 'Delete',
                          destructive: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: EcSpacing.md),
                    Expanded(
                      child: EcSecondaryButton(
                        label: 'Bottom sheet',
                        onPressed: () => showEcBottomSheet<void>(
                          context,
                          builder: (_) => const Padding(
                            padding: EdgeInsets.only(bottom: EcSpacing.lg),
                            child: Text('Bottom sheet content'),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              _section(
                'Loading',
                const SizedBox(
                  height: 96,
                  child: EcLoadingIndicator(message: 'Loading…'),
                ),
              ),
              _section(
                'Empty state',
                const EcCard(
                  child: EcEmptyState(
                    title: 'No appointments yet',
                    message: 'Appointments you book will appear here.',
                  ),
                ),
              ),
              _section(
                'Error state',
                EcCard(child: EcErrorState(onRetry: () {})),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _section(String title, Widget child) => Padding(
    padding: const EdgeInsets.only(top: EcSpacing.xxl),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: EcTypography.sectionTitle),
        const SizedBox(height: EcSpacing.md),
        child,
      ],
    ),
  );
}

class _ColourSwatches extends StatelessWidget {
  const _ColourSwatches();

  static const _swatches = <(String, Color)>[
    ('Navy', EcColors.navy),
    ('Red', EcColors.red),
    ('Blue', EcColors.blue),
    ('Background', EcColors.background),
    ('Info bg', EcColors.infoBackground),
    ('Surface', EcColors.surface),
    ('Border', EcColors.border),
    ('Success', EcColors.success),
    ('Warning', EcColors.warning),
    ('Error', EcColors.error),
  ];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: EcSpacing.md,
      runSpacing: EcSpacing.md,
      children: [
        for (final (name, color) in _swatches)
          SizedBox(
            width: 96,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 48,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(EcRadii.sm),
                    border: Border.all(color: EcColors.border),
                  ),
                ),
                const SizedBox(height: EcSpacing.xs),
                Text(name, style: EcTypography.label),
              ],
            ),
          ),
      ],
    );
  }
}

class _TypeScale extends StatelessWidget {
  const _TypeScale();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Display', style: EcTypography.display),
        Text('Page title', style: EcTypography.pageTitle),
        Text('Section title', style: EcTypography.sectionTitle),
        Text('Body text', style: EcTypography.body),
        Text('Secondary body text', style: EcTypography.bodySecondary),
        Text('Label', style: EcTypography.label),
        Text('Helper text', style: EcTypography.helper),
      ],
    );
  }
}

class _InputsDemo extends StatelessWidget {
  const _InputsDemo();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const EcTextField(label: 'Full name', prefixIcon: Icons.person_outline),
        const SizedBox(height: EcSpacing.md),
        const EcPasswordField(),
        const SizedBox(height: EcSpacing.md),
        const EcSearchField(hint: 'Search patient name…'),
        const SizedBox(height: EcSpacing.md),
        EcDropdown<String>(
          label: 'Consultation type',
          items: const ['General Consultation', 'Follow Up'],
          onChanged: (_) {},
        ),
        const SizedBox(height: EcSpacing.md),
        EcDateField(
          label: 'Date',
          firstDate: DateTime(2020),
          lastDate: DateTime(2100),
          onChanged: (_) {},
        ),
        const SizedBox(height: EcSpacing.md),
        const EcTextField(label: 'Disabled field', enabled: false),
      ],
    );
  }
}
