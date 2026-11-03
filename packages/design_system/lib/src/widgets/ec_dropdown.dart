import 'package:flutter/material.dart';

import '../tokens/ec_colors.dart';
import '../tokens/ec_dimensions.dart';

/// Standard dropdown, styled like [EcTextField].
class EcDropdown<T> extends StatelessWidget {
  const EcDropdown({
    required this.label,
    required this.items,
    required this.onChanged,
    this.value,
    this.itemLabel,
    this.validator,
    this.prefixIcon,
    super.key,
  });

  final String label;
  final List<T> items;
  final T? value;

  /// Text for each item. Defaults to `toString()`.
  final String Function(T item)? itemLabel;
  final ValueChanged<T?>? onChanged;
  final FormFieldValidator<T>? validator;
  final IconData? prefixIcon;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      // `value` is used because the pinned Flutter 3.32 has no `initialValue`
      // on DropdownButtonFormField. Migrate when the SDK is upgraded.
      value: value,
      isExpanded: true,
      validator: validator,
      icon: const Icon(
        Icons.keyboard_arrow_down,
        color: EcColors.textSecondary,
      ),
      onChanged: onChanged,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: prefixIcon == null
            ? null
            : Icon(
                prefixIcon,
                size: EcIconSizes.md,
                color: EcColors.textSecondary,
              ),
      ),
      items: [
        for (final item in items)
          DropdownMenuItem<T>(
            value: item,
            child: Text(itemLabel?.call(item) ?? item.toString()),
          ),
      ],
    );
  }
}
