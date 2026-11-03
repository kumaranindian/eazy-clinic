import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// First screen for signed-out patients: brand, purpose, and the two ways in.
class WelcomePage extends StatelessWidget {
  const WelcomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EcColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(EcSpacing.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: EcSizes.maxFormWidth),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(child: EcBrandLogo.full(height: 200)),
                  const SizedBox(height: EcSpacing.xl),
                  Semantics(
                    header: true,
                    child: Text(
                      'Welcome to EazyClinic',
                      style: EcTypography.pageTitle,
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: EcSpacing.sm),
                  Text(
                    'Your clinic visits, appointments and records in one '
                    'place. You decide which clinics you connect with.',
                    style: EcTypography.bodySecondary,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: EcSpacing.xxl),
                  EcPrimaryButton(
                    label: 'Create account',
                    onPressed: () => context.go(AuthPaths.register),
                  ),
                  const SizedBox(height: EcSpacing.md),
                  EcSecondaryButton(
                    label: 'Sign in',
                    onPressed: () => context.go(AuthPaths.login),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
