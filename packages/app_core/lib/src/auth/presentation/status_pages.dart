import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/auth_ui_config.dart';
import '../application/auth_controller.dart';
import '../domain/auth_state.dart';
import 'auth_layout.dart';

/// Shown while the stored session is being checked. Protected routes are
/// unreachable until this resolves.
class AuthLoadingPage extends StatelessWidget {
  const AuthLoadingPage({super.key});

  @override
  Widget build(BuildContext context) => const Scaffold(
    backgroundColor: EcColors.background,
    body: EcLoadingIndicator(message: 'Checking your session…'),
  );
}

/// Session could not be verified (offline or server problem).
class AuthErrorPage extends ConsumerWidget {
  const AuthErrorPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(authControllerProvider);
    final offline = state is AuthFailed && state.isNetwork;
    return Scaffold(
      backgroundColor: EcColors.background,
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          EcErrorState(
            title: offline ? 'You appear to be offline' : 'Cannot sign you in',
            message: offline
                ? 'Check your internet connection and try again.'
                : 'We could not verify your session. Please try again.',
            onRetry: () => ref.read(authControllerProvider.notifier).retry(),
          ),
          TextButton(
            onPressed: () =>
                ref.read(authControllerProvider.notifier).signOut(),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
  }
}

/// Signed in, but this account may not use this application.
class AccessDeniedPage extends ConsumerWidget {
  const AccessDeniedPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ui = ref.watch(authUiConfigProvider);
    final state = ref.watch(authControllerProvider);
    final reason = state is AccessDenied
        ? state.reason
        : AccessDeniedReason.notAuthorized;
    final (title, message, icon) = switch (reason) {
      AccessDeniedReason.suspended => (
        'Account suspended',
        'This account has been suspended. Please contact EazyClinic support '
            'or your clinic administrator.',
        Icons.pause_circle_outline,
      ),
      AccessDeniedReason.disabled => (
        'Account disabled',
        'This account has been disabled. Please contact EazyClinic support.',
        Icons.block,
      ),
      _ => ('Access not available', ui.deniedHint, Icons.lock_outline),
    };
    return AuthScaffold(
      title: title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(icon, size: EcIconSizes.xl, color: EcColors.textSecondary),
          const SizedBox(height: EcSpacing.lg),
          Text(
            message,
            style: EcTypography.bodySecondary,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: EcSpacing.xl),
          EcSecondaryButton(
            label: 'Sign out',
            icon: Icons.logout,
            onPressed: () =>
                ref.read(authControllerProvider.notifier).signOut(),
          ),
        ],
      ),
    );
  }
}

/// New account: waiting for the user to confirm their e-mail address.
class VerifyEmailPage extends ConsumerStatefulWidget {
  const VerifyEmailPage({super.key});

  @override
  ConsumerState<VerifyEmailPage> createState() => _VerifyEmailPageState();
}

class _VerifyEmailPageState extends ConsumerState<VerifyEmailPage> {
  bool _busy = false;
  String? _message;
  bool _isError = false;

  Future<void> _run(
    Future<dynamic> Function() action, {
    String? success,
  }) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    final failure = await action();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _isError = failure != null;
      _message = failure?.message as String? ?? success;
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.read(authControllerProvider.notifier);
    final state = ref.watch(authControllerProvider);
    final email = state is AccessDenied ? state.user?.email : null;
    return AuthScaffold(
      title: 'Verify your email',
      subtitle: email == null
          ? 'We sent you a verification link.'
          : 'We sent a verification link to $email.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_message != null) ...[
            EcInlineMessage(
              message: _message!,
              tone: _isError ? EcStatusTone.error : EcStatusTone.success,
            ),
            const SizedBox(height: EcSpacing.lg),
          ],
          Text(
            'Open the link in that email, then come back and continue. '
            'You will get access once your email is verified.',
            style: EcTypography.bodySecondary,
          ),
          const SizedBox(height: EcSpacing.xl),
          EcPrimaryButton(
            label: "I've verified my email",
            isLoading: _busy,
            onPressed: () => _run(controller.refreshAccess),
          ),
          const SizedBox(height: EcSpacing.md),
          EcSecondaryButton(
            label: 'Resend verification email',
            onPressed: _busy
                ? null
                : () => _run(
                    controller.resendVerificationEmail,
                    success: 'Verification email sent.',
                  ),
          ),
          TextButton(
            onPressed: _busy ? null : () => controller.signOut(),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
  }
}
