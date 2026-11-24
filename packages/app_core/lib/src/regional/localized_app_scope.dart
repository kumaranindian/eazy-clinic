import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../auth/application/auth_controller.dart';
import '../auth/domain/auth_state.dart';
import 'l10n_context.dart';
import 'locale_providers.dart';
import 'regional_display.dart';

/// Install with `MaterialApp.router(builder: localizedAppBuilder)`.
///
/// It (1) gives design-system widgets their localized texts, (2) applies the
/// signed-in account's language and resets it on sign-out, (3) keeps
/// [RegionalDisplay] (time zone, currency, number style) in step with the
/// clinic configuration, and (4) refreshes the visible screens when the
/// language or region changes, **keeping their state** (typed text, scroll,
/// selections), so switching language never loses user input.
Widget localizedAppBuilder(BuildContext context, Widget? child) =>
    LocalizedAppScope(child: child ?? const SizedBox.shrink());

class LocalizedAppScope extends ConsumerStatefulWidget {
  const LocalizedAppScope({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<LocalizedAppScope> createState() => _LocalizedAppScopeState();
}

class _LocalizedAppScopeState extends ConsumerState<LocalizedAppScope> {
  String? _displayKey;

  void _rebuildAll() {
    void visit(Element e) {
      e.markNeedsBuild();
      e.visitChildren(visit);
    }

    if (!mounted) return;
    (context as Element).visitChildren(visit);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AuthState>(authControllerProvider, (prev, next) {
      final prefs = ref.read(localePreferenceProvider.notifier);
      if (next is Authenticated) {
        prefs.applyAccountLanguage(next.session.preferredLanguage);
      } else if (prev is Authenticated) {
        prefs.reset();
      }
    });

    final auth = ref.watch(authControllerProvider);
    final hasClinic =
        auth is Authenticated && auth.session.memberships.isNotEmpty;
    final config = hasClinic
        ? ref.watch(regionalConfigProvider(null)).value
        : null;

    final language = Localizations.localeOf(context).languageCode;
    RegionalDisplay.update(
      language: language,
      countryCode: config?.countryCode,
      timezone: config?.countryConfigured == true
          ? config!.effectiveTimezone
          : null,
      currency: config?.countryConfigured == true ? config!.currency : null,
    );

    final key =
        '${RegionalDisplay.locale}|${RegionalDisplay.timezone}|${RegionalDisplay.currency}';
    if (_displayKey != null && _displayKey != key) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _rebuildAll());
    }
    _displayKey = key;
    Intl.defaultLocale = RegionalDisplay.locale;

    final t = context.l10n;
    return EcTextsScope(
      texts: EcTexts(
        retry: t.retry,
        loading: t.loading,
        password: t.password,
        showPassword: t.showPassword,
        hidePassword: t.hidePassword,
        search: t.searchHint,
        clearSearch: t.clearSearch,
        back: t.back,
        errorTitle: t.errorStateTitle,
        errorMessage: t.errorStateMessage,
      ),
      child: widget.child,
    );
  }
}
