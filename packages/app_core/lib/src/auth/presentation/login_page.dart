import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../config/auth_ui_config.dart';
import '../application/auth_controller.dart';
import '../application/auth_redirect.dart';
import '../domain/auth_state.dart';
import 'auth_layout.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
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
        .signIn(email: _email.text, password: _password.text);
    if (!mounted) return;
    setState(() {
      _submitting = false;
      _error = failure?.message;
      if (failure != null) _password.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final ui = ref.watch(authUiConfigProvider);
    final auth = ref.watch(authControllerProvider);
    final notice = auth is Unauthenticated ? auth.notice : null;
    return AuthScaffold(
      title: 'Sign in',
      subtitle: ui.audienceLabel,
      footer: ui.registrationEnabled
          ? Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text('New to EazyClinic?'),
                TextButton(
                  onPressed: _submitting
                      ? null
                      : () => context.go(AuthPaths.register),
                  child: const Text('Create account'),
                ),
              ],
            )
          : null,
      child: Form(
        key: _formKey,
        child: AutofillGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (notice != null && _error == null) ...[
                EcInlineMessage(message: notice, tone: EcStatusTone.info),
                const SizedBox(height: EcSpacing.lg),
              ],
              if (_error != null) ...[
                EcInlineMessage(message: _error!),
                const SizedBox(height: EcSpacing.lg),
              ],
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
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
                validator: AuthValidators.existingPassword,
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _submitting
                      ? null
                      : () => context.go(AuthPaths.forgotPassword),
                  child: const Text('Forgot password?'),
                ),
              ),
              const SizedBox(height: EcSpacing.sm),
              EcPrimaryButton(
                label: 'Sign in',
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
