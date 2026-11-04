import 'package:shelf/shelf.dart';

import '../../core/data/document_store.dart';
import '../../core/errors/api_exception.dart';
import '../auth/domain/auth_context.dart';
import '../clinic/common/object_storage.dart';
import 'portal_support.dart';

/// Laboratory reports for the patient app.
///
/// Only a report that the laboratory verified and published (and that is the
/// current version) is visible. Results are read from the verified result
/// records through an allow-list: internal comments, who entered or verified,
/// amendment history and storage paths never leave the clinic. A dependent's
/// reports need the same family permission as other records. The PDF is
/// streamed through this authenticated endpoint; there is no public link.
class PortalLabService {
  PortalLabService(this._s, this._storage);

  final PortalSupport _s;
  final ObjectStorage _storage;

  static const List<String> _reportFields = [
    'reportId',
    'reportNumber',
    'orderNumber',
    'version',
    'external',
    'label',
    'verifiedByClinic',
    'publishedAt',
    'contentType',
  ];

  Future<List<DocData>> _currentReports(ClinicLink link) async {
    final rows = await _s.store.query(
      DocQuery(
        _s.path(link.tenantId, 'lab_reports'),
        filters: [
          QueryFilter('patientId', FilterOp.eq, link.patientId),
          const QueryFilter('status', FilterOp.eq, 'published'),
        ],
        limit: 100,
      ),
    );
    return [
      for (final r in rows)
        if (r.data['current'] == true) r.data,
    ];
  }

  Future<List<Map<String, Object?>>> _tests(
    ClinicLink link,
    DocData report,
  ) async {
    final order = await _s.store.get(
      _s.path(link.tenantId, 'lab_orders', '${report['orderId']}'),
    );
    if (order == null || order['status'] != 'published') return const [];
    final out = <Map<String, Object?>>[];
    for (final i in (order['items'] as List).cast<Map<String, Object?>>()) {
      final item = <String, Object?>{'name': i['name']};
      if (report['external'] != true) {
        final res = await _s.store.get(
          _s.path(
            link.tenantId,
            'lab_results',
            '${report['orderId']}__${i['itemId']}',
          ),
        );
        if (res == null || res['status'] != 'verified') continue;
        item['observations'] = [
          for (final o in (res['observations'] as List))
            PortalSupport.pick((o as Map).cast<String, Object?>(), [
              'name',
              'value',
              'unit',
              'flag',
              'range',
            ]),
        ];
      }
      out.add(item);
    }
    return out;
  }

  Map<String, Object?> _summary(ClinicLink link, DocData r) => {
    'clinicId': link.tenantId,
    'clinicName': link.clinicName,
    ...PortalSupport.pick(r, _reportFields),
  };

  Future<List<Map<String, Object?>>> list(
    AuthContext ctx, {
    String? accountId,
    String? clinicId,
  }) async {
    final subject = await _s.subject(
      ctx,
      accountId,
      PortalSupport.scopeRecords,
    );
    final out = <Map<String, Object?>>[];
    final audits = <WriteOp>[];
    for (final link in await _s.links(subject, clinicId: clinicId)) {
      for (final r in await _currentReports(link)) {
        final tests = await _tests(link, r);
        if (tests.isEmpty && r['external'] != true) continue;
        out.add({
          ..._summary(link, r),
          'tests': [for (final t in tests) t['name']],
        });
      }
      final t = await _s.actingIn(ctx, link.tenantId);
      audits.add(_s.audit(t, link, 'portal.lab_reports_viewed'));
    }
    out.sort((a, b) => '${b['publishedAt']}'.compareTo('${a['publishedAt']}'));
    if (audits.isNotEmpty) await _s.store.commit(audits);
    return out;
  }

  Future<DocData> _owned(ClinicLink link, String reportId) async {
    final r = await _s.store.get(
      _s.path(link.tenantId, 'lab_reports', reportId),
    );
    if (r == null ||
        r['patientId'] != link.patientId ||
        r['status'] != 'published' ||
        r['current'] != true) {
      throw const ApiException.notFound('Report not found.');
    }
    return r;
  }

  Future<Map<String, Object?>> detail(
    AuthContext ctx,
    String clinicId,
    String reportId, {
    String? accountId,
  }) async {
    final subject = await _s.subject(
      ctx,
      accountId,
      PortalSupport.scopeRecords,
    );
    final link = await _s.requireLink(subject, clinicId);
    final r = await _owned(link, reportId);
    final tests = await _tests(link, r);
    if (tests.isEmpty && r['external'] != true) {
      throw const ApiException.notFound('Report not found.');
    }
    final t = await _s.actingIn(ctx, link.tenantId);
    await _s.store.commit([
      _s.audit(
        t,
        link,
        'portal.lab_report_viewed',
        resourceType: 'lab_report',
        resourceId: reportId,
      ),
    ]);
    return {
      ..._summary(link, r),
      'tests': tests,
      'disclaimer':
          'Reference ranges are those of the laboratory that produced this '
          'report. Discuss your results with your doctor.',
    };
  }

  Future<Response> download(
    AuthContext ctx,
    String clinicId,
    String reportId, {
    String? accountId,
  }) async {
    final subject = await _s.subject(
      ctx,
      accountId,
      PortalSupport.scopeRecords,
    );
    final link = await _s.requireLink(subject, clinicId);
    final r = await _owned(link, reportId);
    final obj = await _storage.get('${r['storagePath']}');
    if (obj == null) throw const ApiException.notFound('Report not found.');
    final t = await _s.actingIn(ctx, link.tenantId);
    await _s.store.commit([
      _s.audit(
        t,
        link,
        'portal.lab_report_downloaded',
        resourceType: 'lab_report',
        resourceId: reportId,
      ),
    ]);
    return Response.ok(
      obj.$1,
      headers: {
        'content-type': '${r['contentType']}',
        'content-disposition':
            'attachment; filename="${r['reportNumber']}.${r['contentType'] == 'application/pdf' ? 'pdf' : 'bin'}"',
        'cache-control': 'private, no-store',
        'x-content-type-options': 'nosniff',
      },
    );
  }
}
