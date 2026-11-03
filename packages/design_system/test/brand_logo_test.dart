import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Reads width/height from a PNG header (IHDR chunk).
(int, int) _pngSize(ByteData data) {
  expect(data.getUint32(0), 0x89504E47, reason: 'not a PNG');
  return (data.getUint32(16), data.getUint32(20));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('logo assets are bundled with the original proportions', () async {
    final full = await rootBundle.load(
      'packages/design_system/assets/branding/eazyclinic_logo.png',
    );
    final icon = await rootBundle.load(
      'packages/design_system/assets/branding/eazyclinic_icon.png',
    );
    // 960x640 = the original 1536x1024 scaled uniformly (3:2).
    expect(_pngSize(full), (960, 640));
    expect(_pngSize(icon), (640, 560));
  });

  testWidgets('logo is never stretched', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Center(child: EcBrandLogo.full(height: 100))),
    );
    final image = tester.widget<Image>(find.byType(Image));
    expect(image.fit, BoxFit.contain);
    expect(image.width, isNull);
    expect(image.height, 100);
  });
}
