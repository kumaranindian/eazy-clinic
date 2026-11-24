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
  rtlTests();
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

void _rtlHost(WidgetTester tester, Widget child) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(600, 800);
}

void rtlTests() {
  group('right-to-left behaviour', () {
    Widget host(Widget child) => MaterialApp(
      theme: EcTheme.light(),
      builder: (context, child) =>
          Directionality(textDirection: TextDirection.rtl, child: child!),
      home: Scaffold(
        body: Padding(padding: const EdgeInsets.all(16), child: child),
      ),
    );

    testWidgets('e-mail and phone fields stay left-to-right in an RTL screen', (
      tester,
    ) async {
      _rtlHost(tester, const SizedBox());
      await tester.pumpWidget(
        host(
          const Column(
            children: [
              EcTextField(
                label: 'Email',
                keyboardType: TextInputType.emailAddress,
              ),
              EcTextField(label: 'Phone', keyboardType: TextInputType.phone),
              EcTextField(label: 'الاسم'),
            ],
          ),
        ),
      );
      final fields = tester
          .widgetList<TextField>(find.byType(TextField))
          .toList();
      expect(fields[0].textDirection, TextDirection.ltr);
      expect(fields[1].textDirection, TextDirection.ltr);
      expect(fields[2].textDirection, isNull); // follows the screen: RTL
    });

    testWidgets(
      'Unicode text (Arabic, Hindi, Tamil, mixed) is accepted and kept',
      (tester) async {
        await tester.pumpWidget(
          host(
            const Column(
              children: [
                EcTextField(label: 'Name'),
                EcSearchField(),
              ],
            ),
          ),
        );
        const names = [
          'ليلى الأحمد',
          'आरती शर्मा',
          'வள்ளி முருகன்',
          'Dr. ليلى (UHID 4821)',
          '+971 50 123 4567',
        ];
        for (final n in names) {
          await tester.enterText(find.byType(TextFormField), n);
          await tester.pump();
          expect(find.text(n), findsOneWidget, reason: n);
        }
      },
    );

    testWidgets(
      'identifiers keep left-to-right order inside right-to-left text',
      (tester) async {
        await tester.pumpWidget(host(const EcLtrText('INV-000123')));
        final dir = tester.widget<Directionality>(
          find.descendant(
            of: find.byType(EcLtrText),
            matching: find.byType(Directionality),
          ),
        );
        expect(dir.textDirection, TextDirection.ltr);
      },
    );

    testWidgets(
      'the side navigation edge accent follows the reading direction',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(1280, 800);
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          host(
            EcNavScaffold(
              destinations: const [
                EcNavDestination(label: 'A', icon: Icons.home_outlined),
                EcNavDestination(label: 'B', icon: Icons.people_outline),
              ],
              selectedIndex: 0,
              onSelected: (_) {},
              body: const Text('body'),
            ),
          ),
        );
        expect(tester.getCenter(find.text('B')).dx, greaterThan(1000));
        expect(tester.getCenter(find.text('body')).dx, lessThan(600));
      },
    );

    testWidgets('design-system texts can be localized through the scope', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          const EcTextsScope(
            texts: EcTexts(
              retry: 'حاول مرة أخرى',
              errorTitle: 'حدث خطأ ما',
              errorMessage: 'تحقق من اتصالك.',
              password: 'كلمة المرور',
              showPassword: 'إظهار كلمة المرور',
            ),
            child: Column(
              children: [
                EcPasswordField(),
                SizedBox(height: 200, child: EcErrorState()),
              ],
            ),
          ),
        ),
      );
      expect(find.text('كلمة المرور'), findsOneWidget);
      expect(find.byTooltip('إظهار كلمة المرور'), findsOneWidget);
      expect(find.text('حدث خطأ ما'), findsOneWidget);
      expect(find.text('Something went wrong'), findsNothing);
    });
  });
}
