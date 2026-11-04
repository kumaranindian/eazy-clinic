import 'dart:convert';

import 'package:backend/features/laboratory/lab_evaluation.dart';
import 'package:backend/features/laboratory/lab_pdf.dart';
import 'package:test/test.dart';

Map<String, Object?> param({
  List<Map<String, Object?>>? ranges,
  String type = 'numeric',
}) => {'valueType': type, 'referenceRanges': ranges ?? []};

void main() {
  group('flags use only configured ranges', () {
    final p = param(
      ranges: [
        {
          'sex': 'male',
          'ageMinYears': 18,
          'low': 13.0,
          'high': 17.0,
          'criticalLow': 7.0,
          'criticalHigh': 20.0,
          'unit': 'g/dL',
          'source': 'Clinic SOP v1',
        },
        {
          'sex': 'female',
          'ageMinYears': 18,
          'low': 12.0,
          'high': 15.5,
          'criticalLow': 7.0,
          'unit': 'g/dL',
        },
      ],
    );
    Evaluation ev(
      num v, {
      String? sex = 'male',
      int? age = 30,
      String? unit = 'g/dL',
    }) => evaluate(p, value: v, unit: unit, sex: sex, ageYears: age);

    test('normal, low, high and critical', () {
      expect(ev(15).flag, 'normal');
      expect(ev(12).flag, 'low');
      expect(ev(18).flag, 'high');
      expect(ev(6).flag, 'critical_low');
      expect(ev(21).flag, 'critical_high');
      expect(ev(13).flag, 'normal', reason: 'bounds are inclusive');
    });
    test('the range depends on sex and age', () {
      expect(ev(12.5, sex: 'female').flag, 'normal');
      expect(ev(12.5, sex: 'male').flag, 'low');
      expect(
        ev(12.5, age: 10).flag,
        'not_assessed',
        reason: 'no range for a child is configured',
      );
      expect(
        ev(12.5, age: null).flag,
        'not_assessed',
        reason: 'unknown age cannot match an age range',
      );
      expect(ev(12.5, sex: null).flag, 'not_assessed');
    });
    test('a range is never invented or compared across units', () {
      expect(
        evaluate(
          param(),
          value: 5,
          unit: 'g/dL',
          sex: 'male',
          ageYears: 30,
        ).flag,
        'not_assessed',
      );
      expect(ev(130, unit: 'g/L').flag, 'unit_mismatch');
      expect(ev(15).range!['source'], 'Clinic SOP v1');
    });
    test('the critical limit is optional', () {
      expect(ev(3.0, sex: 'female').flag, 'critical_low');
      expect(
        ev(40, sex: 'female').flag,
        'high',
        reason: 'no critical high configured for women',
      );
    });
  });

  test('qualitative values follow the configured options only', () {
    final p = {
      'valueType': 'qualitative',
      'qualitativeOptions': [
        {'value': 'Negative'},
        {'value': 'Positive', 'abnormal': true},
        {'value': 'Panic', 'critical': true},
      ],
    };
    Evaluation q(String v) =>
        evaluate(p, value: v, unit: null, sex: null, ageYears: null);
    expect(q('Negative').flag, 'normal');
    expect(q('Positive').flag, 'abnormal');
    expect(q('Panic').flag, 'critical');
    expect(q('Maybe').flag, 'not_assessed');
    expect(
      evaluate(
        {'valueType': 'text'},
        value: 'x',
        unit: null,
        sex: null,
        ageYears: null,
      ).flag,
      'not_applicable',
    );
  });

  test('flag helpers and age', () {
    expect(isAbnormal('critical_high'), true);
    expect(isAbnormal('normal'), false);
    expect(isAbnormal('not_assessed'), false);
    expect(isCritical('critical'), true);
    expect(ageInYears('1990-06-02', DateTime.utc(2026, 6, 1)), 35);
    expect(ageInYears('1990-06-01', DateTime.utc(2026, 6, 1)), 36);
    expect(ageInYears(null, DateTime.utc(2026, 6, 1)), isNull);
    expect(ageInYears('2030-01-01', DateTime.utc(2026, 6, 1)), isNull);
  });

  group('pdf', () {
    test('is a structurally valid PDF containing the text', () {
      final bytes = buildPdf([
        const PdfLine('Laboratory Report', size: 16, bold: true),
        const PdfLine('Haemoglobin: 14.2 g/dL (13 - 17)'),
        const PdfLine('Note (with) parentheses \\ and backslash'),
      ], title: 'LRP-000001');
      final text = latin1.decode(bytes);
      expect(text, startsWith('%PDF-1.4'));
      expect(text.trimRight(), endsWith('%%EOF'));
      expect(text, contains('Haemoglobin: 14.2 g/dL'));
      expect(text, contains(r'\(with\)'));
      final xref = int.parse(
        RegExp(r'startxref\n(\d+)').firstMatch(text)!.group(1)!,
      );
      expect(text.substring(xref), startsWith('xref'));
      expect(text, contains('/Count 1'));
    });
    test('wraps long lines, paginates and replaces unsupported characters', () {
      final lines = [
        for (var i = 0; i < 160; i++) PdfLine('Line $i ${'word ' * 40}'),
      ];
      final text = latin1.decode(buildPdf(lines));
      expect(RegExp(r'/Count (\d+)').firstMatch(text)!.group(1), isNot('1'));
      final one = latin1.decode(buildPdf([const PdfLine('Rupee ₹ and हि')]));
      expect(one, contains('Rupee ? and ??'));
    });
    test('is deterministic', () {
      final a = buildPdf([const PdfLine('same')]);
      final b = buildPdf([const PdfLine('same')]);
      expect(a, b);
    });
  });
}
