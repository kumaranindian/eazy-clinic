import 'dart:convert';
import 'dart:typed_data';

/// A minimal text-only PDF writer (PDF 1.4, A4, Helvetica) used for laboratory
/// reports, so no PDF dependency is needed. Text is limited to Latin-1;
/// anything else is replaced by `?`. Long lines are wrapped; pages are added as
/// needed. The result is deterministic for the same input.
class PdfLine {
  const PdfLine(this.text, {this.size = 10, this.bold = false, this.gap = 0});
  final String text;
  final double size;
  final bool bold;

  /// Extra space before the line.
  final double gap;
}

Uint8List buildPdf(List<PdfLine> lines, {String title = 'Report'}) {
  const pageW = 595.0, pageH = 842.0, margin = 50.0;
  final pages = <List<(PdfLine, String, double)>>[[]];
  var y = pageH - margin;
  for (final line in lines) {
    final width = (pageW - 2 * margin) / (line.size * 0.5);
    for (final part in _wrap(_latin1(line.text), width.floor())) {
      final lead = line.size * 1.35 + (part == _firstPart(line) ? line.gap : 0);
      if (y - lead < margin) {
        pages.add([]);
        y = pageH - margin;
      }
      y -= lead;
      pages.last.add((line, part, y));
    }
  }

  final objs = <String>[];
  // 1 catalog, 2 pages, 3 Helvetica, 4 Helvetica-Bold, then page+content pairs
  objs
    ..add('<< /Type /Catalog /Pages 2 0 R >>')
    ..add('')
    ..add(
      '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>',
    )
    ..add(
      '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold /Encoding /WinAnsiEncoding >>',
    );
  final kids = <String>[];
  for (var i = 0; i < pages.length; i++) {
    final pageNo = 5 + i * 2;
    final contentNo = pageNo + 1;
    kids.add('$pageNo 0 R');
    final sb = StringBuffer();
    for (final (line, text, py) in pages[i]) {
      sb.writeln(
        'BT /${line.bold ? 'F2' : 'F1'} ${line.size} Tf $margin ${py.toStringAsFixed(1)} Td (${_escape(text)}) Tj ET',
      );
    }
    sb.writeln(
      'BT /F1 8 Tf $margin 28 Td (${_escape('$title - page ${i + 1} of ${pages.length}')}) Tj ET',
    );
    final content = sb.toString();
    objs
      ..add(
        '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 $pageW $pageH] /Resources << /Font << /F1 3 0 R /F2 4 0 R >> >> /Contents $contentNo 0 R >>',
      )
      ..add('<< /Length ${content.length} >>\nstream\n${content}endstream');
  }
  objs[1] =
      '<< /Type /Pages /Kids [${kids.join(' ')}] /Count ${pages.length} >>';

  final out = StringBuffer('%PDF-1.4\n');
  final offsets = <int>[];
  for (var i = 0; i < objs.length; i++) {
    offsets.add(out.length);
    out.write('${i + 1} 0 obj\n${objs[i]}\nendobj\n');
  }
  final xref = out.length;
  out.write('xref\n0 ${objs.length + 1}\n0000000000 65535 f \n');
  for (final o in offsets) {
    out.write('${o.toString().padLeft(10, '0')} 00000 n \n');
  }
  out.write(
    'trailer\n<< /Size ${objs.length + 1} /Root 1 0 R >>\nstartxref\n$xref\n%%EOF\n',
  );
  return Uint8List.fromList(latin1.encode(out.toString()));
}

String _firstPart(PdfLine l) => _wrap(_latin1(l.text), 1 << 20).first;

String _latin1(String s) => s.runes
    .map(
      (r) =>
          r >= 32 && r <= 255 ? String.fromCharCode(r) : (r == 9 ? ' ' : '?'),
    )
    .join();

String _escape(String s) =>
    s.replaceAll(r'\', r'\\').replaceAll('(', r'\(').replaceAll(')', r'\)');

List<String> _wrap(String text, int width) {
  if (text.length <= width) return [text];
  final out = <String>[];
  var cur = '';
  for (final w in text.split(' ')) {
    if (cur.isEmpty) {
      cur = w;
    } else if (cur.length + 1 + w.length <= width) {
      cur = '$cur $w';
    } else {
      out.add(cur);
      cur = w;
    }
    while (cur.length > width) {
      out.add(cur.substring(0, width));
      cur = cur.substring(width);
    }
  }
  if (cur.isNotEmpty) out.add(cur);
  return out;
}
