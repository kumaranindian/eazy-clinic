import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/config/app_info.dart';
import 'core/routing/app_router.dart';

/// Root widget.
class EazyClinicApp extends ConsumerWidget {
  const EazyClinicApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: AppInfo.name,
      debugShowCheckedModeBanner: false,
      theme: EcTheme.light(),
      // Presentation language only: the user's choice, else the device, else
      // English. It never changes the clinic's country or any stored value.
      locale: ref.watch(appLocaleProvider),
      supportedLocales: supportedAppLocales,
      localizationsDelegates: appLocalizationDelegates,
      routerConfig: ref.watch(appRouterProvider),
    );
  }
}

/// Shown instead of the app when build-time configuration is invalid.
class ConfigurationErrorApp extends StatelessWidget {
  const ConfigurationErrorApp({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppInfo.name,
      debugShowCheckedModeBanner: false,
      theme: EcTheme.light(),
      home: Scaffold(
        body: EcErrorState(title: 'Configuration error', message: message),
      ),
    );
  }
}
