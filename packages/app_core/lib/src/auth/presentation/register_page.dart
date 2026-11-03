import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../config/auth_ui_config.dart';
import '../application/auth_controller.dart';
import '../application/auth_redirect.dart';
import 'auth_layout.dart';

class RegisterPage extends ConsumerStatefulWidget {
  const RegisterPage({super.key});

  @override
  ConsumerState<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends ConsumerState<RegisterPage> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _accepted = false;
  bool _showTermsError = false;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final valid = _formKey.currentState!.validate();
    setState(() => _showTermsError = !_accepted);
    if (!valid || !_accepted) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    final failure = await ref
        .read(authControllerProvider.notifier)
        .register(
          displayName: _name.text,
          email: _email.text,
          password: _password.text,
        );
    if (!mounted) return;
    setState(() {
      _submitting = false;
      _error = failure?.message;
    });
  }

  @override
  Widget build(BuildContext context) {
    final ui = ref.watch(authUiConfigProvider);
    return AuthScaffold(
      title: 'Create your account',
      subtitle: ui.registrationNote,
      footer: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const Text('Already have an account?'),
          TextButton(
            onPressed: _submitting ? null : () => context.go(AuthPaths.login),
            child: const Text('Sign in'),
          ),
        ],
      ),
      child: Form(
        key: _formKey,
        child: AutofillGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_error != null) ...[
                EcInlineMessage(message: _error!),
                const SizedBox(height: EcSpacing.lg),
              ],
              EcTextField(
                label: 'Full name',
                controller: _name,
                prefixIcon: Icons.person_outline,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.name],
                enabled: !_submitting,
                validator: AuthValidators.name,
              ),
              const SizedBox(height: EcSpacing.lg),
              EcTextField(
                label: 'Email',
                controller: _email,
                prefixIcon: Icons.mail_outline,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.email],
                enabled: !_submitting,
                validator: AuthValidators.email,
              ),
              const SizedBox(height: EcSpacing.lg),
              EcPasswordField(
                controller: _password,
                enabled: !_submitting,
                textInputAction: TextInputAction.next,
                validator: AuthValidators.newPassword,
              ),
              const SizedBox(height: EcSpacing.lg),
              EcPasswordField(
                label: 'Confirm password',
                controller: _confirm,
                enabled: !_submitting,
                textInputAction: TextInputAction.done,
                validator: AuthValidators.confirmPassword(_password),
              ),
              const SizedBox(height: EcSpacing.md),
              CheckboxListTile(
                value: _accepted,
                onChanged: _submitting
                    ? null
                    : (v) => setState(() {
                        _accepted = v ?? false;
                        _showTermsError = false;
                      }),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(
                  'I accept the Terms of Service and acknowledge the '
                  'Privacy Policy.',
                  style: EcTypography.body,
                ),
              ),
              if (_showTermsError)
                Padding(
                  padding: const EdgeInsets.only(bottom: EcSpacing.sm),
                  child: Text(
                    'You must accept the terms to continue.',
                    style: EcTypography.error,
                  ),
                ),
              const SizedBox(height: EcSpacing.sm),
              EcPrimaryButton(
                label: 'Create account',
                isLoading: _submitting,
                onPressed: _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
