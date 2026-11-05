import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:validation/validation.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../regional/language_selector.dart';

/// Adapts a shared [FieldValidator] to a Flutter form validator.
FormFieldValidator<String> asFormValidator(FieldValidator validator) =>
    (value) => validator(value)?.message;

/// Centered, scrollable single-column layout used by every auth screen.
class AuthScaffold extends StatelessWidget {
  const AuthScaffold({
    required this.title,
    required this.child,
    this.subtitle,
    this.footer,
    this.showBack = false,
    super.key,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? footer;
  final bool showBack;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EcColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(EcSpacing.lg),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: EcSizes.maxFormWidth),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: LanguageSelector(),
                  ),
                  const Center(child: EcBrandLogo.full(height: 120)),
                  const SizedBox(height: EcSpacing.xl),
                  Semantics(
                    header: true,
                    child: Text(
                      title,
                      style: EcTypography.pageTitle,
                      textAlign: TextAlign.center,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: EcSpacing.xs),
                    Text(
                      subtitle!,
                      style: EcTypography.bodySecondary,
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: EcSpacing.xl),
                  EcCard(
                    padding: const EdgeInsets.all(EcSpacing.xl),
                    child: child,
                  ),
                  if (footer != null) ...[
                    const SizedBox(height: EcSpacing.lg),
                    footer!,
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Localized field validators for the auth forms (same rules the backend
/// applies to its own inputs; Firebase enforces the final password policy).
/// The rules come from the shared `validation` package; only the wording is
/// localized here.
class AuthValidators {
  AuthValidators(this.l10n);

  final AppLocalizations l10n;

  String? _fail(ValidationFailure? f, String field, {int? min, int? max}) {
    if (f == null) return null;
    return switch (f.code) {
      'required' => l10n.validationRequired(field),
      'invalid_email' => l10n.validationEmail,
      'invalid_phone' => l10n.validationPhone,
      'too_short' => l10n.validationTooShort(field, min ?? 0),
      'too_long' => l10n.validationTooLong(field, max ?? 0),
      _ => l10n.errorGeneric,
    };
  }

  FormFieldValidator<String> get email =>
      (v) => _fail(Validators.email(v), l10n.email);

  FormFieldValidator<String> get name => (v) {
    final f = Validators.compose([
      (v) => Validators.required(v, field: 'name'),
      Validators.minLength(2, field: 'name'),
      Validators.maxLength(80, field: 'name'),
    ])(v);
    return _fail(f, l10n.fullName, min: 2, max: 80);
  };

  /// Registration: enforces the minimum password policy.
  FormFieldValidator<String> get newPassword => (v) {
    if (Validators.password(v) == null) return null;
    if (v == null || v.isEmpty) return l10n.passwordRequired;
    return v.length < 8
        ? l10n.validationPasswordLength
        : l10n.validationPasswordMix;
  };

  /// Login: only requires input (the policy applies when choosing a password).
  FormFieldValidator<String> get existingPassword =>
      (v) => (v == null || v.isEmpty) ? l10n.passwordRequired : null;

  FormFieldValidator<String> confirmPassword(TextEditingController password) =>
      (v) {
        if (v == null || v.isEmpty) return l10n.confirmPasswordPrompt;
        return v == password.text ? null : l10n.passwordsDoNotMatch;
      };
}
