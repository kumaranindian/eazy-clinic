import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../tokens/ec_colors.dart';
import '../tokens/ec_dimensions.dart';
import 'ec_texts.dart';

/// Standard form text input: filled field, optional leading icon, label above.
///
/// [validator] plugs into a surrounding [Form]. Use the `validation` package
/// for the rules, e.g. `(v) => Validators.email(v)?.message`.
class EcTextField extends StatelessWidget {
  const EcTextField({
    required this.label,
    this.controller,
    this.hint,
    this.helperText,
    this.prefixIcon,
    this.suffix,
    this.validator,
    this.onChanged,
    this.onSubmitted,
    this.keyboardType,
    this.textInputAction,
    this.inputFormatters,
    this.autofillHints,
    this.maxLines = 1,
    this.maxLength,
    this.obscureText = false,
    this.enabled = true,
    this.readOnly = false,
    this.onTap,
    this.textDirection,
    super.key,
  });

  final String label;
  final TextEditingController? controller;
  final String? hint;
  final String? helperText;
  final IconData? prefixIcon;
  final Widget? suffix;
  final FormFieldValidator<String>? validator;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final List<TextInputFormatter>? inputFormatters;
  final Iterable<String>? autofillHints;
  final int maxLines;
  final int? maxLength;
  final bool obscureText;
  final bool enabled;
  final bool readOnly;
  final VoidCallback? onTap;

  /// Text direction of the typed value. Defaults to the screen direction,
  /// except for e-mail, phone, URL and number fields, which are always typed
  /// left-to-right (even inside a right-to-left screen).
  final TextDirection? textDirection;

  static bool _isLtrData(TextInputType? type) =>
      type == TextInputType.emailAddress ||
      type == TextInputType.phone ||
      type == TextInputType.url ||
      type == TextInputType.number;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      textDirection:
          textDirection ??
          (_isLtrData(keyboardType) ? TextDirection.ltr : null),
      controller: controller,
      enabled: enabled,
      readOnly: readOnly,
      onTap: onTap,
      obscureText: obscureText,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      inputFormatters: inputFormatters,
      autofillHints: autofillHints,
      maxLines: obscureText ? 1 : maxLines,
      maxLength: maxLength,
      validator: validator,
      onChanged: onChanged,
      onFieldSubmitted: onSubmitted,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        helperText: helperText,
        counterText: '',
        floatingLabelBehavior: FloatingLabelBehavior.auto,
        prefixIcon: prefixIcon == null
            ? null
            : Icon(
                prefixIcon,
                size: EcIconSizes.md,
                color: EcColors.textSecondary,
              ),
        suffixIcon: suffix,
      ),
    );
  }
}

/// Password input with a show/hide toggle.
class EcPasswordField extends StatefulWidget {
  const EcPasswordField({
    this.label,
    this.controller,
    this.validator,
    this.onSubmitted,
    this.textInputAction,
    this.enabled = true,
    super.key,
  });

  /// Defaults to the localized "Password" text.
  final String? label;
  final TextEditingController? controller;
  final FormFieldValidator<String>? validator;
  final ValueChanged<String>? onSubmitted;
  final TextInputAction? textInputAction;
  final bool enabled;

  @override
  State<EcPasswordField> createState() => _EcPasswordFieldState();
}

class _EcPasswordFieldState extends State<EcPasswordField> {
  bool _obscured = true;

  @override
  Widget build(BuildContext context) {
    final texts = EcTexts.of(context);
    return EcTextField(
      label: widget.label ?? texts.password,
      controller: widget.controller,
      validator: widget.validator,
      onSubmitted: widget.onSubmitted,
      textInputAction: widget.textInputAction,
      enabled: widget.enabled,
      prefixIcon: Icons.lock_outline,
      obscureText: _obscured,
      keyboardType: TextInputType.visiblePassword,
      autofillHints: const [AutofillHints.password],
      suffix: IconButton(
        tooltip: _obscured ? texts.showPassword : texts.hidePassword,
        icon: Icon(
          _obscured ? Icons.visibility_outlined : Icons.visibility_off_outlined,
          size: EcIconSizes.md,
          color: EcColors.textSecondary,
        ),
        onPressed: () => setState(() => _obscured = !_obscured),
      ),
    );
  }
}

/// Search input with a clear button. Calls [onChanged] on every keystroke;
/// debounce in the controller/provider layer, not here.
class EcSearchField extends StatefulWidget {
  const EcSearchField({this.hint, this.controller, this.onChanged, super.key});

  /// Defaults to the localized "Search" text.
  final String? hint;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;

  @override
  State<EcSearchField> createState() => _EcSearchFieldState();
}

class _EcSearchFieldState extends State<EcSearchField> {
  late final TextEditingController _controller =
      widget.controller ?? TextEditingController();

  @override
  void dispose() {
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final texts = EcTexts.of(context);
    return TextField(
      controller: _controller,
      onChanged: widget.onChanged,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: widget.hint ?? texts.search,
        prefixIcon: const Icon(
          Icons.search,
          size: EcIconSizes.md,
          color: EcColors.textSecondary,
        ),
        suffixIcon: ValueListenableBuilder<TextEditingValue>(
          valueListenable: _controller,
          builder: (context, value, _) => value.text.isEmpty
              ? const SizedBox.shrink()
              : IconButton(
                  tooltip: texts.clearSearch,
                  icon: const Icon(Icons.close, size: EcIconSizes.md),
                  onPressed: () {
                    _controller.clear();
                    widget.onChanged?.call('');
                  },
                ),
        ),
      ),
    );
  }
}
