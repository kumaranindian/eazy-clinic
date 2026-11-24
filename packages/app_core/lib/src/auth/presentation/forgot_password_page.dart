import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../regional/l10n_context.dart';

import '../application/auth_controller.dart';
import '../application/auth_redirect.dart';
import 'auth_layout.dart';

class ForgotPasswordPage extends ConsumerStatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  ConsumerState<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends ConsumerState<ForgotPasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting || !_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    final failure = await ref
        .read(authControllerProvider.notifier)
        .sendPasswordReset(_email.text);
    if (!mounted) return;
    setState(() {
      _submitting = false;
      _error = failure?.localized(context.l10n);
    });
    // Same confirmation whether or not the address has an account.
    if (failure == null) context.go(AuthPaths.resetEmailSent);
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: context.l10n.resetYourPassword,
      subtitle: "Enter your email and we'll send you a reset link.",
      footer: TextButton(
        onPressed: () => context.go(AuthPaths.login),
        child: Text(context.l10n.backToSignIn),
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_error != null) ...[
              EcInlineMessage(message: _error!),
              const SizedBox(height: EcSpacing.lg),
            ],
            EcTextField(
              label: context.l10n.email,
              controller: _email,
              prefixIcon: Icons.mail_outline,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.email],
              enabled: !_submitting,
              onSubmitted: (_) => _submit(),
              validator: AuthValidators(context.l10n).email,
            ),
            const SizedBox(height: EcSpacing.xl),
            EcPrimaryButton(
              label: context.l10n.sendResetLink,
              isLoading: _submitting,
              onPressed: _submit,
            ),
          ],
        ),
      ),
    );
  }
}
