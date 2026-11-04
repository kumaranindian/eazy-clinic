import 'dart:convert';

import 'package:api_contracts/api_contracts.dart';
import 'package:common_models/common_models.dart';

import '../../core/data/document_store.dart';
import '../../core/errors/api_exception.dart';
import '../../core/ids.dart';
import '../clinic/common/clinic_deps.dart';
import '../clinic/common/tenant_context.dart';
import '../patients/patient_support.dart';
import '../platform/common/body_reader.dart';
import '../scheduling/scheduling_support.dart';
import '../scheduling/time_support.dart';

/// Shared rules of the clinical services: who may author or see a record,
/// patient/branch loading, validation of the narrative sections and the
/// clinical audit trail.
class ClinicalSupport {
  ClinicalSupport(this.d, this.patients, this.sched);

  final ClinicDeps d;
  final PatientSupport patients;
  final SchedulingSupport sched;

  String path(TenantContext t, String collection, [String? id]) =>
      d.path(t, collection, id);

  /// The doctor profile linked to the caller. Only a **doctor** whose login is
  /// linked to a profile may author clinical records; owners and other roles
  /// can read (if permitted) but never author.
  Future<String> requireDoctorSelf(TenantContext t) async {
    if (t.role != ClinicRole.doctor) {
      throw const ApiException.forbidden(
        'Only the treating doctor can do this.',
      );
    }
    final id = await sched.ownDoctorId(t);
    if (id == null) {
      throw const ApiException.forbidden(
        'Your login is not linked to a doctor profile.',
      );
    }
    return id;
  }

  Future<void> requireAuthor(TenantContext t, DocData record) async {
    final me = await requireDoctorSelf(t);
    if (record['doctorId'] != me) {
      throw const ApiException.forbidden(
        'This record belongs to another doctor.',
      );
    }
  }

  /// Whether the caller may read [record]: the author, or a holder of
  /// `consultations.view_all`.
  Future<bool> canSee(TenantContext t, DocData record) async {
    if (!t.scope.allows('${record['branchId']}')) return false;
    if (t.can(ClinicPermission.consultationsViewAll)) return true;
    if (!t.can(ClinicPermission.consultationsView)) return false;
    return await sched.ownDoctorId(t) == record['doctorId'];
  }

  Future<DocData> consultation(
    TenantContext t,
    String id, {
    TxContext? tx,
  }) async {
    final p = path(t, 'consultations', id);
    final c = tx == null ? await d.store.get(p) : await tx.get(p);
    // other doctors' and other branches' consultations do not exist for us
    if (c == null || !await canSee(t, c)) {
      throw const ApiException.notFound('Consultation not found.');
    }
    return c;
  }

  void requireOpen(DocData c) {
    if (c['status'] != 'draft' && c['status'] != 'in_progress') {
      throw const ApiException.conflict(
        'This consultation is finalized. Use an amendment to correct it.',
      );
    }
  }

  CreateOp audit(
    TenantContext t, {
    required String action,
    required String resourceType,
    required String resourceId,
    String? branchId,
    String? patientId,
    String? consultationId,
    String? reason,
    String? requestId,
    Map<String, Object?>? before,
    Map<String, Object?>? after,
  }) => CreateOp(d.path(t, 'clinical_audit_logs', newId()), {
    'tenantId': t.tenantId,
    'branchId': branchId,
    'patientId': patientId,
    'consultationId': consultationId,
    'action': action,
    'resourceType': resourceType,
    'resourceId': resourceId,
    'actorUid': t.uid,
    'actorRole': t.role.wireName,
    'reason': reason,
    'requestId': requestId,
    'before': before,
    'after': after,
    'timestamp': d.now,
  });

  static Map<String, Object?> present(Map<String, Object?> doc) =>
      jsonSafe(doc);

  static Map<String, Object?> jsonSafe(Map<String, Object?> m) =>
      (_safe(m)! as Map).cast<String, Object?>();

  static Object? _safe(Object? v) {
    if (v is DateTime) return v.toUtc().toIso8601String();
    if (v is Map) {
      return {for (final e in v.entries) '${e.key}': _safe(e.value)};
    }
    if (v is List) return v.map(_safe).toList();
    return v;
  }
}

/// The narrative sections of a consultation and their validation.
abstract final class ConsultationSections {
  static const List<String> names = [
    'chiefComplaint',
    'observations',
    'assessment',
    'treatmentPlan',
    'followUp',
  ];

  static const Set<String> severities = {
    'mild',
    'moderate',
    'severe',
    'unknown',
  };

  /// Parses the sections present in [r]. Missing sections are skipped; present
  /// ones may contain any subset of their fields.
  static Map<String, Map<String, Object?>> parse(BodyReader r) {
    final out = <String, Map<String, Object?>>{};
    void text(BodyReader c, Map<String, Object?> into, String k, int max) {
      final v = c.str(k, max: max, required: false);
      if (v != null) into[k] = v;
    }

    void texts(BodyReader c, Map<String, Object?> into, String k) {
      if (!c.has(k)) return;
      final raw = c.body[k];
      if (raw is! List ||
          raw.length > 20 ||
          raw.any((e) => e is! String || e.trim().isEmpty || e.length > 200)) {
        c.addIssue(k, 'invalid_value', 'Give up to 20 short entries.');
        return;
      }
      into[k] = raw.map((e) => (e as String).trim()).toList();
    }

    final cc = r.object('chiefComplaint', required: false);
    if (cc != null) {
      cc.rejectUnknown({'reason', 'symptoms', 'notes'});
      final m = <String, Object?>{};
      text(cc, m, 'reason', 500);
      text(cc, m, 'notes', 1000);
      if (cc.has('symptoms')) {
        final raw = cc.body['symptoms'];
        if (raw is! List || raw.length > 20) {
          cc.addIssue('symptoms', 'invalid_value', 'Give up to 20 symptoms.');
        } else {
          final list = <Map<String, Object?>>[];
          for (var i = 0; i < raw.length; i++) {
            final item = raw[i];
            if (item is! Map) {
              cc.addIssue('symptoms[$i]', 'invalid_type', 'Must be an object.');
              continue;
            }
            final s = BodyReader(item.cast<String, Object?>())
              ..rejectUnknown({
                'name',
                'duration',
                'onset',
                'severity',
                'notes',
              });
            final name = s.str('name', min: 2, max: 100);
            final duration = s.str('duration', max: 50, required: false);
            final onset = s.str('onset', max: 50, required: false);
            final severity = s.enumOf<String>(
              'severity',
              severities.toList(),
              (v) => v,
              required: false,
            );
            final notes = s.str('notes', max: 300, required: false);
            for (final issue in s.issues) {
              cc.addIssue(
                'symptoms[$i].${issue.field}',
                issue.code,
                issue.message,
              );
            }
            list.add({
              'name': name,
              'duration': ?duration,
              'onset': ?onset,
              'severity': ?severity,
              'notes': ?notes,
            });
          }
          m['symptoms'] = list;
        }
      }
      out['chiefComplaint'] = m;
    }
    final ob = r.object('observations', required: false);
    if (ob != null) {
      ob.rejectUnknown({
        'examination',
        'positiveFindings',
        'negativeFindings',
        'notes',
      });
      final m = <String, Object?>{};
      text(ob, m, 'examination', 2000);
      text(ob, m, 'notes', 2000);
      texts(ob, m, 'positiveFindings');
      texts(ob, m, 'negativeFindings');
      out['observations'] = m;
    }
    final a = r.object('assessment', required: false);
    if (a != null) {
      a.rejectUnknown({'notes'});
      final m = <String, Object?>{};
      text(a, m, 'notes', 2000);
      out['assessment'] = m;
    }
    final tp = r.object('treatmentPlan', required: false);
    if (tp != null) {
      tp.rejectUnknown({
        'recommendations',
        'lifestyle',
        'diet',
        'procedures',
        'patientInstructions',
      });
      final m = <String, Object?>{};
      text(tp, m, 'recommendations', 2000);
      text(tp, m, 'lifestyle', 1000);
      text(tp, m, 'diet', 1000);
      text(tp, m, 'procedures', 1000);
      text(tp, m, 'patientInstructions', 2000);
      out['treatmentPlan'] = m;
    }
    final fu = r.object('followUp', required: false);
    if (fu != null) {
      fu.rejectUnknown({
        'required',
        'recommendedDate',
        'reason',
        'instructions',
      });
      final m = <String, Object?>{};
      final req = fu.boolean('required');
      if (req != null) m['required'] = req;
      if (fu.has('recommendedDate')) {
        if (!Dates.valid(fu.body['recommendedDate'])) {
          fu.addIssue('recommendedDate', 'invalid_date', 'Use YYYY-MM-DD.');
        } else {
          m['recommendedDate'] = fu.body['recommendedDate'];
        }
      }
      text(fu, m, 'reason', 300);
      text(fu, m, 'instructions', 1000);
      out['followUp'] = m;
    }
    return out;
  }

  /// Applies parsed sections over existing content (field-wise merge).
  static Map<String, Object?> merge(
    Map<String, Object?> current,
    Map<String, Map<String, Object?>> incoming,
  ) {
    final out = {...current};
    for (final e in incoming.entries) {
      out[e.key] = {
        ...((current[e.key] as Map?)?.cast<String, Object?>() ?? const {}),
        ...e.value,
      };
    }
    return out;
  }

  /// Content of a consultation document (only the narrative sections).
  static Map<String, Object?> contentOf(Map<String, Object?> c) => {
    for (final n in names) n: c[n] ?? <String, Object?>{},
  };

  /// Names of sections whose content differs.
  static List<String> changed(
    Map<String, Object?> before,
    Map<String, Object?> after,
  ) => [
    for (final n in names)
      if (canon(before[n]) != canon(after[n])) n,
  ];

  /// Order-independent text form for comparing nested values.
  static String canon(Object? v) => jsonEncode(_sorted(v));

  static Object? _sorted(Object? v) {
    if (v is Map) {
      final keys = v.keys.map((e) => '$e').toList()..sort();
      return {for (final k in keys) k: _sorted(v[k])};
    }
    if (v is List) return v.map(_sorted).toList();
    if (v is DateTime) return v.toUtc().toIso8601String();
    return v;
  }
}

FieldIssue issue(String f, String code, String m) =>
    FieldIssue(field: f, code: code, message: m);
