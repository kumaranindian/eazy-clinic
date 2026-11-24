import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../config/auth_ui_config.dart';
import '../../regional/l10n_context.dart';
import '../application/auth_controller.dart';
import '../application/auth_redirect.dart';
import '../domain/auth_failure.dart';
import '../domain/auth_state.dart';
import 'auth_layout.dart';

/// Shown while the stored session is being checked. Protected routes are
/// unreachable until this resolves.
class AuthLoadingPage extends StatelessWidget {
  const AuthLoadingPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: EcColors.background,
    body: EcLoadingIndicator(message: context.l10n.checkingSession),
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
            title: offline
                ? context.l10n.offlineTitle
                : context.l10n.cannotSignInTitle,
            message: offline
                ? context.l10n.offlineMessage
                : context.l10n.sessionVerifyFailed,
            onRetry: () => ref.read(authControllerProvider.notifier).retry(),
          ),
          TextButton(
            onPressed: () =>
                ref.read(authControllerProvider.notifier).signOut(),
            child: Text(context.l10n.signOut),
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
        context.l10n.accountSuspendedTitle,
        context.l10n.accountSuspendedMessage,
        Icons.pause_circle_outline,
      ),
      AccessDeniedReason.disabled => (
        context.l10n.accountDisabledTitle,
        context.l10n.accountDisabledMessage,
        Icons.block,
      ),
      _ => (
        context.l10n.accessUnavailableTitle,
        ui.deniedHint,
        Icons.lock_outline,
      ),
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
            label: context.l10n.signOut,
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
    final failure = await action() as AuthFailure?;
    if (!mounted) return;
    setState(() {
      _busy = false;
      _isError = failure != null;
      _message = failure?.localized(context.l10n) ?? success;
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.read(authControllerProvider.notifier);
    final state = ref.watch(authControllerProvider);
    final email = state is AccessDenied ? state.user?.email : null;
    return AuthScaffold(
      title: context.l10n.verifyEmailTitle,
      subtitle: email == null
          ? context.l10n.verificationSentGeneric
          : context.l10n.verificationSentTo(email),
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
            context.l10n.verifyEmailInstructions,
            style: EcTypography.bodySecondary,
          ),
          const SizedBox(height: EcSpacing.xl),
          EcPrimaryButton(
            label: context.l10n.verifiedMyEmail,
            isLoading: _busy,
            onPressed: () => _run(controller.refreshAccess),
          ),
          const SizedBox(height: EcSpacing.md),
          EcSecondaryButton(
            label: context.l10n.resendVerification,
            onPressed: _busy
                ? null
                : () => _run(
                    controller.resendVerificationEmail,
                    success: context.l10n.verificationResent,
                  ),
          ),
          TextButton(
            onPressed: _busy ? null : () => controller.signOut(),
            child: Text(context.l10n.signOut),
          ),
        ],
      ),
    );
  }
}

/// Confirmation after requesting a password reset. Deliberately identical for
/// every address so it cannot be used to discover which e-mails have accounts.
class PasswordResetSentPage extends StatelessWidget {
  const PasswordResetSentPage({super.key});

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: context.l10n.checkYourEmailTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(
            Icons.mark_email_read_outlined,
            size: EcIconSizes.xl,
            color: EcColors.blue,
          ),
          const SizedBox(height: EcSpacing.lg),
          Text(
            context.l10n.resetLinkInfo,
            style: EcTypography.bodySecondary,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: EcSpacing.xl),
          EcPrimaryButton(
            label: context.l10n.backToSignIn,
            onPressed: () => context.go(AuthPaths.login),
          ),
          const SizedBox(height: EcSpacing.md),
          EcSecondaryButton(
            label: context.l10n.useDifferentEmail,
            onPressed: () => context.go(AuthPaths.forgotPassword),
          ),
        ],
      ),
    );
  }
}
