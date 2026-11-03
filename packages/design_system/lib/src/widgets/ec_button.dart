import 'package:flutter/material.dart';

import '../tokens/ec_dimensions.dart';

/// Primary action button (Healthcare Red). Use once per screen section.
///
/// Pass `onPressed: null` for the disabled state and `isLoading: true` while
/// an action is in flight (taps are ignored while loading).
class EcPrimaryButton extends StatelessWidget {
  const EcPrimaryButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.isLoading = false,
    this.compact = false,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool isLoading;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: isLoading ? null : onPressed,
      style: _style(compact),
      child: _ButtonContent(
        label: label,
        icon: icon,
        isLoading: isLoading,
        loadingColor: Theme.of(context).colorScheme.onPrimary,
      ),
    );
  }
}

/// Secondary action button (Medical Blue outline).
class EcSecondaryButton extends StatelessWidget {
  const EcSecondaryButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.isLoading = false,
    this.compact = false,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool isLoading;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: isLoading ? null : onPressed,
      style: _style(compact),
      child: _ButtonContent(
        label: label,
        icon: icon,
        isLoading: isLoading,
        loadingColor: Theme.of(context).colorScheme.secondary,
      ),
    );
  }
}

ButtonStyle _style(bool compact) => ButtonStyle(
  minimumSize: WidgetStatePropertyAll(
    Size.fromHeight(
      compact ? EcSizes.buttonHeightCompact : EcSizes.buttonHeight,
    ),
  ),
);

class _ButtonContent extends StatelessWidget {
  const _ButtonContent({
    required this.label,
    required this.icon,
    required this.isLoading,
    required this.loadingColor,
  });

  final String label;
  final IconData? icon;
  final bool isLoading;
  final Color loadingColor;

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return Semantics(
        label: 'Loading',
        child: SizedBox(
          width: EcIconSizes.md,
          height: EcIconSizes.md,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            color: loadingColor,
          ),
        ),
      );
    }
    if (icon == null) return Text(label);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: EcIconSizes.md),
        const SizedBox(width: EcSpacing.sm),
        Text(label),
      ],
    );
  }
}
