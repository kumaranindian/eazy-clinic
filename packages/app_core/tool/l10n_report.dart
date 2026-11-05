// Translation completeness report for the ARB resources.
//
//   dart run tool/l10n_report.dart            # print the report
//   dart run tool/l10n_report.dart --out F.md # write it to a file
//   dart run tool/l10n_report.dart --check    # exit 1 on any defect
//
// A defect is a missing key, an empty value, or a placeholder / plural-argument
// that differs from the English template. Missing keys are never shown to
// users as raw keys: the generated localizations fall back to English.
import 'dart:convert';
import 'dart:io';

class LocaleReport {
  LocaleReport(this.locale, this.total);

  final String locale;
  final int total;
  final List<String> missing = [];
  final List<String> empty = [];
  final List<String> placeholderMismatches = [];
  final bool starter = false;

  int get translated => total - missing.length;
  double get percent => total == 0 ? 100 : translated * 100 / total;
  bool get hasDefects =>
      missing.isNotEmpty ||
      empty.isNotEmpty ||
      placeholderMismatches.isNotEmpty;
}

// `{name}` that is NOT the body of a plural branch (`=0{none}`, `other{..}`).
final RegExp _placeholder = RegExp(
  r'(?<!=\d)(?<!zero)(?<!one)(?<!two)(?<!few)(?<!many)(?<!other)\{\s*([A-Za-z_]\w*)\s*\}',
);

// `{count, plural, ...}` / `{gender, select, ...}` headers.
final RegExp _header = RegExp(
  r'\{\s*([A-Za-z_]\w*)\s*,\s*(?:plural|select)\s*,',
);

/// Argument names used by an ICU message: plain placeholders and the
/// argument of plural/select blocks. Plural category bodies are text, not
/// arguments.
Set<String> argumentsIn(String message) => {
  for (final m in _placeholder.allMatches(message)) m.group(1)!,
  for (final m in _header.allMatches(message)) m.group(1)!,
};

Map<String, String> _load(File f) {
  final json = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
  return {
    for (final e in json.entries)
      if (!e.key.startsWith('@') && e.value is String) e.key: e.value as String,
  };
}

List<LocaleReport> analyze(String arbDir) {
  final dir = Directory(arbDir);
  final files =
      dir
          .listSync()
          .whereType<File>()
          .where((f) => RegExp(r'app_[a-z]+\.arb$').hasMatch(f.path))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  final en = _load(files.firstWhere((f) => f.path.endsWith('app_en.arb')));
  final reports = <LocaleReport>[];
  for (final f in files) {
    final locale = RegExp(r'app_([a-z]+)\.arb$').firstMatch(f.path)!.group(1)!;
    final r = LocaleReport(locale, en.length);
    final tr = _load(f);
    for (final e in en.entries) {
      final v = tr[e.key];
      if (v == null) {
        r.missing.add(e.key);
      } else if (v.trim().isEmpty) {
        r.empty.add(e.key);
      } else if (locale != 'en' &&
          argumentsIn(v).difference(argumentsIn(e.value)).isNotEmpty) {
        r.placeholderMismatches.add(e.key);
      } else if (locale != 'en' &&
          argumentsIn(e.value).difference(argumentsIn(v)).isNotEmpty) {
        r.placeholderMismatches.add(e.key);
      }
    }
    reports.add(r);
  }
  return reports;
}

String toMarkdown(List<LocaleReport> reports) {
  final b = StringBuffer()
    ..writeln(
      '| Locale | Keys | Translated | Missing | Empty | Placeholder mismatches | Complete |',
    )
    ..writeln('|---|---|---|---|---|---|---|');
  for (final r in reports) {
    b.writeln(
      '| ${r.locale} | ${r.total} | ${r.translated} | ${r.missing.length} | '
      '${r.empty.length} | ${r.placeholderMismatches.length} | '
      '${r.percent.toStringAsFixed(1)}% |',
    );
  }
  for (final r in reports.where((r) => r.hasDefects)) {
    b
      ..writeln()
      ..writeln('**${r.locale}**');
    if (r.missing.isNotEmpty) b.writeln('- missing: ${r.missing.join(', ')}');
    if (r.empty.isNotEmpty) b.writeln('- empty: ${r.empty.join(', ')}');
    if (r.placeholderMismatches.isNotEmpty) {
      b.writeln(
        '- placeholder mismatch: ${r.placeholderMismatches.join(', ')}',
      );
    }
  }
  return b.toString();
}

void main(List<String> args) {
  final reports = analyze('lib/l10n');
  final md = toMarkdown(reports);
  final out = args.contains('--out') ? args[args.indexOf('--out') + 1] : null;
  if (out != null) {
    File(out).writeAsStringSync(md);
  } else {
    stdout.write(md);
  }
  if (args.contains('--check') && reports.any((r) => r.hasDefects)) exit(1);
}
