import 'package:flutter/widgets.dart';

/// Texts used inside design-system widgets (labels, tooltips, semantics).
///
/// The package has no dependency on any app localization. An app installs an
/// [EcTextsScope] built from its own localizations; without one the English
/// defaults below are used, so widgets never show keys or blanks.
class EcTexts {
  const EcTexts({
    this.retry = 'Try again',
    this.loading = 'Loading',
    this.password = 'Password',
    this.showPassword = 'Show password',
    this.hidePassword = 'Hide password',
    this.search = 'Search',
    this.clearSearch = 'Clear search',
    this.back = 'Back',
    this.errorTitle = 'Something went wrong',
    this.errorMessage = 'Please check your connection and try again.',
  });

  final String retry;
  final String loading;
  final String password;
  final String showPassword;
  final String hidePassword;
  final String search;
  final String clearSearch;
  final String back;
  final String errorTitle;
  final String errorMessage;

  static const EcTexts english = EcTexts();

  /// Texts of the nearest [EcTextsScope], or the English defaults.
  static EcTexts of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<EcTextsScope>()?.texts ??
      english;
}

/// Provides [EcTexts] to the widgets below it. Changing [texts] rebuilds the
/// dependents, so switching language updates design-system widgets in place.
class EcTextsScope extends InheritedWidget {
  const EcTextsScope({required this.texts, required super.child, super.key});

  final EcTexts texts;

  @override
  bool updateShouldNotify(EcTextsScope oldWidget) =>
      oldWidget.texts.retry != texts.retry ||
      oldWidget.texts.password != texts.password ||
      oldWidget.texts.back != texts.back ||
      oldWidget.texts.errorTitle != texts.errorTitle ||
      oldWidget.texts.search != texts.search;
}

/// Wraps a widget so it always lays out left-to-right (identifiers, phone
/// numbers, invoice and patient numbers inside right-to-left screens).
class EcLtrText extends StatelessWidget {
  const EcLtrText(this.text, {this.style, super.key});

  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.ltr,
    child: Text(text, style: style, textAlign: TextAlign.start),
  );
}
