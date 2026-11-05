import 'package:common_models/common_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/application/auth_controller.dart';
import '../auth/domain/auth_state.dart';
import 'l10n_context.dart';
import 'locale_providers.dart';

/// A language menu. The choice is presentation only; for a signed-in user it
/// is also saved on the account (best effort).
class LanguageSelector extends ConsumerWidget {
  const LanguageSelector({super.key});

  static String nativeName(String code) => switch (code) {
    'ar' => 'العربية',
    'hi' => 'हिन्दी',
    'ta' => 'தமிழ்',
    _ => 'English',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(localePreferenceProvider);
    final signedIn = ref.watch(authControllerProvider) is Authenticated;
    final t = context.l10n;
    return PopupMenuButton<String>(
      tooltip: t.language,
      icon: const Icon(Icons.language),
      initialValue: current ?? '',
      onSelected: (code) => ref
          .read(localePreferenceProvider.notifier)
          .choose(code.isEmpty ? null : code, persist: signedIn),
      itemBuilder: (_) => [
        PopupMenuItem(value: '', child: Text(t.languageSystem)),
        for (final code in supportedUiLanguages)
          PopupMenuItem(value: code, child: Text(nativeName(code))),
      ],
    );
  }
}
