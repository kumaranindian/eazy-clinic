import 'package:flutter/material.dart';

import '../tokens/ec_colors.dart';
import '../tokens/ec_dimensions.dart';

/// Read-only field that opens the Material date picker.
class EcDateField extends StatelessWidget {
  const EcDateField({
    required this.label,
    required this.firstDate,
    required this.lastDate,
    required this.onChanged,
    this.value,
    this.validator,
    super.key,
  });

  final String label;
  final DateTime? value;
  final DateTime firstDate;
  final DateTime lastDate;
  final ValueChanged<DateTime> onChanged;
  final FormFieldValidator<DateTime>? validator;

  @override
  Widget build(BuildContext context) {
    return FormField<DateTime>(
      initialValue: value,
      validator: validator,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      builder: (state) {
        final selected = state.value ?? value;
        return InkWell(
          borderRadius: EcRadii.input,
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: selected ?? DateTime.now(),
              firstDate: firstDate,
              lastDate: lastDate,
            );
            if (picked != null) {
              state.didChange(picked);
              onChanged(picked);
            }
          },
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: label,
              errorText: state.errorText,
              suffixIcon: const Icon(
                Icons.calendar_today_outlined,
                size: EcIconSizes.md,
                color: EcColors.textSecondary,
              ),
            ),
            child: Text(
              selected == null
                  ? ''
                  : MaterialLocalizations.of(
                      context,
                    ).formatMediumDate(selected),
            ),
          ),
        );
      },
    );
  }
}
