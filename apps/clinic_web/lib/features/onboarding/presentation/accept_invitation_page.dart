import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../control_plane/data/control_plane_repository.dart';

/// Landing page of an invitation link (`/accept-invitation?token=…`).
/// The caller must be signed in (the router keeps the link through sign-in)
/// with the invited email address; role, clinic and branches come from the
/// invitation and cannot be changed here.
class AcceptInvitationPage extends ConsumerStatefulWidget {
  const AcceptInvitationPage({required this.token, super.key});

  final String? token;

  @override
  ConsumerState<AcceptInvitationPage> createState() => _AcceptState();
}

class _AcceptState extends ConsumerState<AcceptInvitationPage> {
  bool _busy = false;
  String? _error;

  Future<void> _accept() async {
    final token = widget.token;
    if (_busy || token == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(controlPlaneRepositoryProvider).sendMap(
        'POST',
        '/invitations/accept',
        {'token': token},
      );
      // re-read the session so the new membership is picked up
      await ref.read(authControllerProvider.notifier).retry();
      if (mounted) context.go('/');
    } on ApiFailure catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.isNetwork ? e.displayMessage : e.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final email = auth is Authenticated ? auth.user.email : null;
    return Scaffold(
      backgroundColor: EcColors.background,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(EcSpacing.lg),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: EcSizes.maxFormWidth),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Center(child: EcBrandLogo.full(height: 110)),
                const SizedBox(height: EcSpacing.xl),
                Text(
                  'Join a clinic',
                  style: EcTypography.pageTitle,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: EcSpacing.lg),
                EcCard(
                  padding: const EdgeInsets.all(EcSpacing.xl),
                  child: widget.token == null
                      ? const EcInlineMessage(
                          message:
                              'This invitation link is incomplete. Ask the clinic to send it again.',
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (_error != null) ...[
                              EcInlineMessage(message: _error!),
                              const SizedBox(height: EcSpacing.lg),
                            ],
                            Text(
                              'You are signed in as ${email ?? 'your account'}. The invitation only works for the email address it was sent to.',
                              style: EcTypography.bodySecondary,
                            ),
                            const SizedBox(height: EcSpacing.lg),
                            EcPrimaryButton(
                              label: 'Accept invitation',
                              isLoading: _busy,
                              onPressed: _accept,
                            ),
                            const SizedBox(height: EcSpacing.md),
                            TextButton(
                              onPressed: _busy
                                  ? null
                                  : () => ref
                                        .read(authControllerProvider.notifier)
                                        .signOut(),
                              child: const Text('Use a different account'),
                            ),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
