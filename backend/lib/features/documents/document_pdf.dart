import 'dart:typed_data';

import 'package:shelf/shelf.dart';

import '../laboratory/lab_pdf.dart';

/// Printable documents (invoice, receipt, prescription) rendered from the
/// same authorized, allow-listed data the screens show. Nothing is computed
/// here: totals, balances and medicines are printed exactly as stored.
///
/// The writer is the dependency-free text PDF writer (Latin-1, Helvetica), so
/// amounts use "Rs" rather than the rupee sign.

String money(Object? minor, [Object? currency]) {
  if (minor is! int) return '-';
  final neg = minor < 0;
  final v = minor.abs();
  final whole = (v ~/ 100).toString();
  final b = StringBuffer();
  for (var i = 0; i < whole.length; i++) {
    if (i > 0 && (whole.length - i) % 3 == 0) b.write(',');
    b.write(whole[i]);
  }
  final cur = currency == null || currency == 'INR' ? 'Rs' : '$currency';
  return '${neg ? '-' : ''}$cur $b.${(v % 100).toString().padLeft(2, '0')}';
}

String _human(Object? v) {
  final s = '${v ?? ''}'.replaceAll('_', ' ').trim();
  return s.isEmpty ? '-' : s[0].toUpperCase() + s.substring(1);
}

String _date(Object? iso) {
  final s = '${iso ?? ''}';
  return s.length >= 10 ? s.substring(0, 10) : (s.isEmpty ? '-' : s);
}

List<PdfLine> _clinicHeader(
  Map<String, Object?>? clinic,
  String? fallbackName,
) {
  final name = '${clinic?['name'] ?? fallbackName ?? 'Clinic'}';
  final a = (clinic?['address'] as Map?)?.cast<String, Object?>();
  final addr = a == null
      ? null
      : [
          a['line1'],
          a['line2'],
          a['city'],
          a['state'],
          a['postalCode'],
        ].where((e) => e != null && '$e'.isNotEmpty).join(', ');
  return [
    PdfLine(name, size: 16, bold: true),
    if (clinic?['branchName'] != null) PdfLine('${clinic!['branchName']}'),
    if (addr != null && addr.isNotEmpty) PdfLine(addr, size: 9),
    if (clinic?['phone'] != null)
      PdfLine('Phone: ${clinic!['phone']}', size: 9),
  ];
}

/// An invoice. Refuses nothing itself: the caller decides which invoices may
/// be printed (drafts are not).
Uint8List invoicePdf(Map<String, Object?> inv, {String? clinicName}) {
  final cur = inv['currency'];
  final lines = <PdfLine>[
    ..._clinicHeader(null, '${inv['clinicName'] ?? clinicName ?? 'Clinic'}'),
    if (inv['branchName'] != null) PdfLine('${inv['branchName']}'),
    PdfLine(
      'INVOICE ${inv['invoiceNumber'] ?? ''}',
      size: 13,
      bold: true,
      gap: 12,
    ),
    PdfLine(
      'Date: ${_date(inv['invoiceDate'])}    Due: ${_date(inv['dueDate'])}',
    ),
    PdfLine('Status: ${_human(inv['displayStatus'] ?? inv['status'])}'),
    if (inv['patientName'] != null)
      PdfLine(
        'Patient: ${inv['patientName']}${inv['patientMrn'] == null ? '' : '  (${inv['patientMrn']})'}',
        gap: 6,
      ),
    const PdfLine(
      'Description  |  Qty  |  Rate  |  Discount  |  Tax  |  Amount',
      size: 9,
      bold: true,
      gap: 12,
    ),
    for (final l
        in ((inv['lines'] as List?) ?? const []).cast<Map<String, Object?>>())
      PdfLine(
        '${l['description']}  |  ${l['quantity']}  |  ${money(l['unitMinor'], cur)}  |  '
        '${money(l['lineDiscount'] ?? 0, cur)}  |  ${money(l['tax'] ?? 0, cur)}  |  ${money(l['total'], cur)}',
        size: 9,
      ),
    PdfLine('Subtotal: ${money(inv['subtotal'], cur)}', gap: 12),
    PdfLine('Discount: ${money(inv['discountTotal'], cur)}'),
    PdfLine('Tax: ${money(inv['taxTotal'], cur)}'),
    PdfLine(
      'Total: ${money(inv['adjustedTotal'] ?? inv['grandTotal'], cur)}',
      bold: true,
    ),
    PdfLine('Paid: ${money(inv['amountPaid'], cur)}'),
    if ((inv['amountRefunded'] as int? ?? 0) != 0)
      PdfLine('Refunded: ${money(inv['amountRefunded'], cur)}'),
    PdfLine('Balance due: ${money(inv['outstanding'], cur)}', bold: true),
    if (inv['notes'] != null)
      PdfLine('Notes: ${inv['notes']}', size: 9, gap: 8),
    const PdfLine('This is a computer-generated invoice.', size: 8, gap: 16),
  ];
  return buildPdf(lines, title: 'Invoice ${inv['invoiceNumber'] ?? ''}');
}

Uint8List receiptPdf(Map<String, Object?> rc) {
  final cur = rc['currency'];
  final clinic = (rc['clinic'] as Map?)?.cast<String, Object?>();
  final lines = <PdfLine>[
    ..._clinicHeader(clinic, null),
    PdfLine(
      'RECEIPT ${rc['receiptNumber'] ?? ''}',
      size: 13,
      bold: true,
      gap: 12,
    ),
    PdfLine('Date: ${_date(rc['receivedAt'] ?? rc['issuedAt'])}'),
    if (rc['patientName'] != null)
      PdfLine(
        'Received from: ${rc['patientName']}${rc['patientMrn'] == null ? '' : '  (${rc['patientMrn']})'}',
      ),
    PdfLine('Amount: ${money(rc['amount'], cur)}', bold: true, gap: 8),
    PdfLine(
      'Method: ${_human(rc['method'])}${rc['reference'] == null ? '' : '   Reference: ${rc['reference']}'}',
    ),
    for (final i
        in ((rc['invoices'] as List?) ?? const []).cast<Map<String, Object?>>())
      PdfLine(
        'Against invoice ${i['invoiceNumber']}: ${money(i['amount'], cur)}  (balance after: ${money(i['outstandingAfter'], cur)})',
        size: 9,
      ),
    if ((rc['advanceAmount'] as int? ?? 0) > 0)
      PdfLine('Kept as advance: ${money(rc['advanceAmount'], cur)}', size: 9),
    const PdfLine('This is a computer-generated receipt.', size: 8, gap: 16),
  ];
  return buildPdf(lines, title: 'Receipt ${rc['receiptNumber'] ?? ''}');
}

/// A doctor-issued prescription, printed exactly as authorized. No dosage,
/// interaction or advice text is generated.
Uint8List prescriptionPdf(Map<String, Object?> rx) {
  final lines = <PdfLine>[
    PdfLine('${rx['clinicName'] ?? 'Clinic'}', size: 16, bold: true),
    PdfLine(
      'PRESCRIPTION ${rx['number'] ?? ''}',
      size: 13,
      bold: true,
      gap: 12,
    ),
    PdfLine(
      'Date: ${_date(rx['finalizedAt'] ?? rx['issuedAt'] ?? rx['prescribedAt'])}    Version: ${rx['version'] ?? 1}',
    ),
    if (rx['doctorName'] != null) PdfLine('Doctor: ${rx['doctorName']}'),
    if (rx['patientName'] != null)
      PdfLine(
        'Patient: ${rx['patientName']}${rx['patientMrn'] == null ? '' : '  (${rx['patientMrn']})'}',
      ),
    if (rx['superseded'] == true || rx['status'] == 'amended')
      const PdfLine(
        'SUPERSEDED: a newer version of this prescription exists.',
        bold: true,
        gap: 6,
      ),
    const PdfLine('Medicines', size: 11, bold: true, gap: 12),
  ];
  var n = 0;
  for (final m
      in ((rx['medicines'] as List?) ?? const [])
          .cast<Map<String, Object?>>()) {
    n++;
    lines
      ..add(
        PdfLine(
          '$n. ${m['name']}${m['strength'] == null ? '' : ' ${m['strength']}'}'
          '${m['genericName'] == null ? '' : ' (${m['genericName']})'}',
          bold: true,
          gap: 6,
        ),
      )
      ..add(
        PdfLine(
          [
            if (m['dosage'] != null) '${m['dosage']}',
            if (m['route'] != null) _human(m['route']),
            if (m['frequency'] != null) '${m['frequency']}',
            if (m['durationValue'] != null)
              'for ${m['durationValue']} ${m['durationUnit'] ?? ''}',
            if (m['foodRelation'] != null) _human(m['foodRelation']),
          ].join('  |  '),
          size: 9,
        ),
      );
    if (m['instructions'] != null) {
      lines.add(PdfLine('Instructions: ${m['instructions']}', size: 9));
    }
    if (m['warnings'] != null) {
      lines.add(PdfLine('Warning: ${m['warnings']}', size: 9));
    }
  }
  if (rx['notes'] != null) {
    lines.add(PdfLine('Notes: ${rx['notes']}', size: 9, gap: 10));
  }
  lines.add(
    PdfLine(
      '${rx['disclaimer'] ?? 'Issued by the treating doctor. Follow the doctor\'s instructions.'}',
      size: 8,
      gap: 16,
    ),
  );
  return buildPdf(lines, title: 'Prescription ${rx['number'] ?? ''}');
}

/// A private, non-cacheable PDF download.
Response pdfResponse(Uint8List bytes, String fileName) => Response.ok(
  bytes,
  headers: {
    'content-type': 'application/pdf',
    'content-disposition':
        'attachment; filename="${fileName.replaceAll(RegExp(r'[^A-Za-z0-9_.\-]'), '_')}.pdf"',
    'cache-control': 'private, no-store',
    'x-content-type-options': 'nosniff',
  },
);
