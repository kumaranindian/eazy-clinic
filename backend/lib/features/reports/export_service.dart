import 'dart:convert';
import 'dart:typed_data';

import 'package:api_contracts/api_contracts.dart';
import 'package:common_models/common_models.dart';
import 'package:crypto/crypto.dart';
import 'package:shelf/shelf.dart';

import '../../core/data/document_store.dart';
import '../../core/errors/api_exception.dart';
import '../../core/ids.dart';
import '../clinic/common/clinic_deps.dart';
import '../clinic/common/object_storage.dart';
import '../clinic/common/tenant_context.dart';
import '../laboratory/lab_pdf.dart';
import '../platform/common/body_reader.dart';
import '../platform/common/paging.dart';
import 'report_service.dart';

const int maxExportRows = 10000;
const int maxExportBytes = 5 * 1024 * 1024;
const Duration exportLifetime = Duration(hours: 6);

/// Spreadsheet programs run text that starts with `=`, `+`, `-`, `@`, a tab or
/// a carriage return as a formula. Such text is prefixed with an apostrophe so
/// it is shown, not executed. Numbers are written as numbers.
String csvCell(Object? v) {
  if (v == null) return '';
  var s = v is Map || v is List ? jsonEncode(v) : '$v';
  if (v is String && s.isNotEmpty && '=+-@\t\r'.contains(s[0])) s = "'$s";
  if (s.contains(',') ||
      s.contains('"') ||
      s.contains('\n') ||
      s.contains('\r')) {
    s = '"${s.replaceAll('"', '""')}"';
  }
  return s;
}

String toCsv(List<String> columns, List<Map<String, Object?>> rows) {
  final b = StringBuffer()..writeln(columns.map(csvCell).join(','));
  for (final r in rows) {
    b.writeln([for (final c in columns) csvCell(r[c])].join(','));
  }
  return b.toString();
}

/// Server-side report exports (CSV and PDF), generated within hard limits and
/// stored in private storage. A download is possible only for the person who
/// asked for it, only through this authenticated API, and only for a limited
/// time. Every request and download is audited (ids and filters, no content).
class ExportService {
  ExportService(this._d, this._reports, this._storage);

  final ClinicDeps _d;
  final ReportService _reports;
  final ObjectStorage _storage;

  String _p(TenantContext t, String c, [String? id]) =>
      'tenants/${t.tenantId}/$c${id == null ? '' : '/$id'}';

  CreateOp _audit(
    TenantContext t,
    String action,
    String id, {
    Map<String, Object?>? after,
    String? requestId,
  }) => CreateOp(
    _p(t, 'report_audit_logs', newId()),
    {
      'tenantId': t.tenantId,
      'action': action,
      'resourceType': 'report_export',
      'resourceId': id,
      'actorUid': t.uid,
      'actorRole': t.actorLabel,
      'requestId': requestId,
      'after': after,
      'timestamp': _d.now,
    }..removeWhere((k, v) => v == null),
  );

  Map<String, Object?> present(DocData d) => {
    for (final k in const [
      'exportId',
      'report',
      'format',
      'status',
      'filters',
      'rows',
      'sizeBytes',
      'errorCode',
      'requestedAt',
      'readyAt',
      'expiresAt',
    ])
      if (d[k] != null) k: _safe(d[k]),
    'expired':
        d['expiresAt'] is DateTime &&
        !(d['expiresAt']! as DateTime).isAfter(_d.now),
  };

  Object? _safe(Object? v) {
    if (v is DateTime) return v.toUtc().toIso8601String();
    if (v is Map) {
      return {for (final e in v.entries) '${e.key}': _safe(e.value)};
    }
    return v;
  }

  Uint8List _pdf(ReportResult r) {
    final lines = <PdfLine>[
      PdfLine(r.title, size: 16, bold: true),
      PdfLine(
        'Period ${r.filters['from']} to ${r.filters['to']} (${r.filters['timezone']})',
        size: 9,
        gap: 4,
      ),
      PdfLine('Generated ${r.generatedAt}', size: 9),
      for (final n in r.notes) PdfLine(n, size: 8, gap: 4),
      PdfLine(r.columns.join('  |  '), size: 8, bold: true, gap: 10),
      for (final row in r.rows)
        PdfLine(
          [for (final c in r.columns) '${row[c] ?? ''}'].join('  |  '),
          size: 8,
        ),
      PdfLine('Definitions', size: 10, bold: true, gap: 14),
      for (final e in r.definitions.entries)
        PdfLine('${e.key}: ${e.value}', size: 8),
    ];
    return buildPdf(lines, title: r.title);
  }

  Future<Map<String, Object?>> create(
    TenantContext t,
    Map<String, Object?> body, {
    String? requestId,
  }) async {
    t.require(ClinicPermission.reportsExport);
    final r = BodyReader(body)
      ..rejectUnknown({
        'report',
        'format',
        'from',
        'to',
        'branchId',
        'doctorId',
      });
    final kind = r.enumOf<String>('report', reportKinds, (v) => v);
    final format = r.enumOf<String>('format', const ['csv', 'pdf'], (v) => v);
    final from = r.str('from', max: 10, required: false);
    final to = r.str('to', max: 10, required: false);
    final branch = r.str('branchId', max: 40, required: false);
    final doctor = r.str('doctorId', max: 40, required: false);
    r.throwIfInvalid();
    final filters = <String, String>{
      'from': ?from,
      'to': ?to,
      'branchId': ?branch,
      'doctorId': ?doctor,
    };
    final id = 'rx_${newId(length: 14)}';
    final now = _d.now;
    final base = <String, Object?>{
      'exportId': id,
      'tenantId': t.tenantId,
      'report': kind,
      'format': format,
      'filters': filters,
      'requestedBy': t.uid,
      'requestedAt': now,
    };
    await _d.store.commit([
      CreateOp(_p(t, 'report_exports', id), {...base, 'status': 'processing'}),
      _audit(
        t,
        'report.export_requested',
        id,
        requestId: requestId,
        after: {'report': kind, 'format': format, ...filters},
      ),
    ]);
    try {
      // the same access checks, scope and limits as the on-screen report
      final res = await _reports.run(t, kind!, filters);
      if (res.truncated) {
        throw ApiException.validation([
          const FieldIssue(
            field: 'from',
            code: 'too_large',
            message:
                'Too many records for an export. Choose a shorter period or a branch.',
          ),
        ]);
      }
      if (res.rows.length > maxExportRows) {
        throw ApiException.validation([
          const FieldIssue(
            field: 'from',
            code: 'too_large',
            message: 'The report has too many rows. Choose a shorter period.',
          ),
        ]);
      }
      final Uint8List bytes = format == 'csv'
          ? Uint8List.fromList(utf8.encode(toCsv(res.columns, res.rows)))
          : _pdf(res);
      if (bytes.length > maxExportBytes) {
        throw ApiException.validation([
          const FieldIssue(
            field: 'from',
            code: 'too_large',
            message: 'The file would be too large.',
          ),
        ]);
      }
      final path = '${t.tenantId}/report_exports/$id.$format';
      await _storage.put(
        path,
        bytes,
        format == 'csv' ? 'text/csv; charset=utf-8' : 'application/pdf',
      );
      final ready = {
        'status': 'ready',
        'rows': res.rows.length,
        'sizeBytes': bytes.length,
        'sha256': sha256.convert(bytes).toString(),
        'storagePath': path,
        'readyAt': _d.now,
        'expiresAt': _d.now.add(exportLifetime),
      };
      await _d.store.commit([
        UpdateOp(_p(t, 'report_exports', id), ready),
        _audit(
          t,
          'report.export_ready',
          id,
          requestId: requestId,
          after: {'rows': res.rows.length, 'bytes': bytes.length},
        ),
      ]);
      return present({...base, ...ready, 'status': 'ready'});
    } on ApiException catch (e) {
      await _d.store.commit([
        UpdateOp(_p(t, 'report_exports', id), {
          'status': 'failed',
          'errorCode': e.code.name,
        }),
        _audit(
          t,
          'report.export_failed',
          id,
          requestId: requestId,
          after: {'code': e.code.name},
        ),
      ]);
      rethrow;
    }
  }

  Future<DocData> _own(TenantContext t, String id) async {
    t.require(ClinicPermission.reportsExport);
    final d = await _d.store.get(_p(t, 'report_exports', id));
    if (d == null || d['requestedBy'] != t.uid) {
      throw const ApiException.notFound('Export not found.');
    }
    return d;
  }

  Future<Map<String, Object?>> detail(TenantContext t, String id) async =>
      present(await _own(t, id));

  Future<Paged> history(TenantContext t, Request req) {
    t.require(ClinicPermission.reportsExport);
    return runPaged(
      _d.store,
      DocQuery(
        _p(t, 'report_exports'),
        filters: [QueryFilter('requestedBy', FilterOp.eq, t.uid)],
        orderBy: const OrderBy('requestedAt', descending: true),
      ),
      req,
    );
  }

  Future<Response> download(
    TenantContext t,
    String id, {
    String? requestId,
  }) async {
    final d = await _own(t, id);
    if (d['status'] != 'ready') {
      throw ApiException.conflict('This export is ${d['status']}.');
    }
    final exp = d['expiresAt'] as DateTime?;
    if (exp == null || !exp.isAfter(_d.now)) {
      throw const ApiException.notFound(
        'This export has expired. Request it again.',
      );
    }
    final obj = await _storage.get('${d['storagePath']}');
    if (obj == null) {
      throw const ApiException.notFound('Export file not found.');
    }
    await _d.store.commit([
      _audit(t, 'report.export_downloaded', id, requestId: requestId),
    ]);
    final fmt = '${d['format']}';
    return Response.ok(
      obj.$1,
      headers: {
        'content-type': fmt == 'csv'
            ? 'text/csv; charset=utf-8'
            : 'application/pdf',
        'content-disposition': 'attachment; filename="${d['report']}-$id.$fmt"',
        'cache-control': 'private, no-store',
        'x-content-type-options': 'nosniff',
      },
    );
  }
}
