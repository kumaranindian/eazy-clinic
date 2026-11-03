import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:validation/validation.dart';

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

/// Shared field validators for the auth forms (same rules the backend applies
/// to its own inputs; Firebase enforces the final password policy).
abstract final class AuthValidators {
  static final FormFieldValidator<String> email = asFormValidator(
    Validators.email,
  );

  static final FormFieldValidator<String> name = asFormValidator(
    Validators.compose([
      (v) => Validators.required(v, field: 'Full name'),
      Validators.minLength(2, field: 'Full name'),
      Validators.maxLength(80, field: 'Full name'),
    ]),
  );

  /// Registration: enforces the minimum password policy.
  static final FormFieldValidator<String> newPassword = asFormValidator(
    Validators.password,
  );

  /// Login: only requires input (the policy applies when choosing a password).
  static String? existingPassword(String? v) =>
      (v == null || v.isEmpty) ? 'Password is required.' : null;

  static FormFieldValidator<String> confirmPassword(
    TextEditingController password,
  ) => (v) {
    if (v == null || v.isEmpty) return 'Please confirm your password.';
    return v == password.text ? null : 'Passwords do not match.';
  };
}
