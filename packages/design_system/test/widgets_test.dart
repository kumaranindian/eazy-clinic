import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child, {Size size = const Size(400, 800)}) {
  return MediaQuery(
    data: MediaQueryData(size: size),
    child: MaterialApp(
      theme: EcTheme.light(),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
}

void main() {
  testWidgets('primary button fires onPressed and ignores taps while loading', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      _host(EcPrimaryButton(label: 'Save', onPressed: () => taps++)),
    );
    await tester.tap(find.text('Save'));
    expect(taps, 1);

    await tester.pumpWidget(
      _host(
        EcPrimaryButton(
          label: 'Save',
          onPressed: () => taps++,
          isLoading: true,
        ),
      ),
    );
    await tester.tap(find.byType(FilledButton));
    expect(taps, 1);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('disabled primary button is not tappable', (tester) async {
    await tester.pumpWidget(
      _host(const EcPrimaryButton(label: 'Save', onPressed: null)),
    );
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
  });

  testWidgets('password field toggles visibility', (tester) async {
    await tester.pumpWidget(_host(const EcPasswordField()));
    EditableText field() =>
        tester.widget<EditableText>(find.byType(EditableText));
    expect(field().obscureText, isTrue);
    await tester.tap(find.byTooltip('Show password'));
    await tester.pump();
    expect(field().obscureText, isFalse);
  });

  testWidgets('search field shows a clear button once text is entered', (
    tester,
  ) async {
    final changes = <String>[];
    await tester.pumpWidget(_host(EcSearchField(onChanged: changes.add)));
    expect(find.byTooltip('Clear search'), findsNothing);
    await tester.enterText(find.byType(TextField), 'ravi');
    await tester.pump();
    expect(find.byTooltip('Clear search'), findsOneWidget);
    await tester.tap(find.byTooltip('Clear search'));
    await tester.pump();
    expect(changes.last, '');
  });

  testWidgets('empty and error states render their actions', (tester) async {
    var retried = false;
    await tester.pumpWidget(
      _host(
        Column(
          children: [
            const SizedBox(
              height: 300,
              child: EcEmptyState(title: 'Nothing here', message: 'Add one.'),
            ),
            SizedBox(
              height: 300,
              child: EcErrorState(onRetry: () => retried = true),
            ),
          ],
        ),
      ),
    );
    expect(find.text('Nothing here'), findsOneWidget);
    await tester.tap(find.text('Try again'));
    expect(retried, isTrue);
  });

  testWidgets('confirm dialog returns the user choice', (tester) async {
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: EcTheme.light(),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => result = await showEcConfirmDialog(
              context,
              title: 'Delete?',
              message: 'Sure?',
              confirmLabel: 'Delete',
              destructive: true,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(result, isTrue);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(result, isFalse);
  });

  testWidgets(
    'nav scaffold uses a bottom bar on phones and a side nav on desktop',
    (tester) async {
      const destinations = [
        EcNavDestination(label: 'Home', icon: Icons.home_outlined),
        EcNavDestination(label: 'Patients', icon: Icons.people_outline),
      ];
      Widget build(Size size) => MediaQuery(
        data: MediaQueryData(size: size),
        child: MaterialApp(
          theme: EcTheme.light(),
          home: EcNavScaffold(
            destinations: destinations,
            selectedIndex: 0,
            onSelected: (_) {},
            body: const Text('body'),
          ),
        ),
      );

      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      tester.view.physicalSize = const Size(400, 800);
      await tester.pumpWidget(build(const Size(400, 800)));
      expect(find.byType(NavigationBar), findsOneWidget);

      tester.view.physicalSize = const Size(1280, 800);
      await tester.pumpWidget(build(const Size(1280, 800)));
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.text('Patients'), findsOneWidget);
    },
  );

  testWidgets('gallery renders every section without errors', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(900, 3000);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(theme: EcTheme.light(), home: const DesignSystemGallery()),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('Colours'), findsOneWidget);
  });
}
