import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../core/data/document_store.dart';
import '../clinic/common/clinic_deps.dart';

/// Categories of patient notifications (see PATIENT_NOTIFICATION_WORKFLOW.md).
const List<String> notificationCategories = [
  'appointment_booked',
  'appointment_confirmed',
  'appointment_rescheduled',
  'appointment_cancelled',
  'appointment_reminder',
  'token_generated',
  'doctor_calling',
  'queue_changed',
  'summary_available',
  'prescription_available',
  'report_available',
  'followup_reminder',
  'invoice_generated',
  'payment_received',
  'refund_status',
  'clinic_announcement',
];

/// Writes in-app notifications for a patient account.
///
/// This is the single interface through which anything tells a patient about
/// something. It stores the in-app inbox entry only; delivering a push message
/// (FCM) and scheduling reminders belong to the Phase 10 notification module,
/// which will call this same interface so there is one notification system.
///
/// Text must never carry diagnoses, medicines or amounts: it is shown on lock
/// screens. Detail is fetched from the authorized API after the tap.
class PortalNotifier {
  PortalNotifier(this._d);

  final ClinicDeps _d;

  /// Idempotent: the same [dedupeKey] never creates a second entry.
  Future<void> publish({
    required String accountId,
    required String category,
    required String title,
    required String body,
    required String dedupeKey,
    String? clinicId,
    String? resourceType,
    String? resourceId,
  }) async {
    final id =
        'n_${sha256.convert(utf8.encode('$accountId:$dedupeKey')).toString().substring(0, 24)}';
    try {
      await _d.store.commit([
        CreateOp(
          'patient_notifications/$id',
          {
            'notificationId': id,
            'accountId': accountId,
            'category': category,
            'title': title,
            'body': body,
            'clinicId': clinicId,
            'resourceType': resourceType,
            'resourceId': resourceId,
            'read': false,
            'createdAt': _d.now,
          }..removeWhere((k, v) => v == null),
        ),
      ]);
    } on AlreadyExistsException {
      // already delivered
    }
  }

  /// Notifies the patient account linked to a clinic patient record, if any.
  /// Clinics call this for events about a patient who has not linked an
  /// account: it simply does nothing.
  Future<void> publishForPatient(
    String tenantId,
    String patientId, {
    required String category,
    required String title,
    required String body,
    required String dedupeKey,
    String? resourceType,
    String? resourceId,
  }) async {
    final p = await _d.store.get('tenants/$tenantId/patients/$patientId');
    final account = p?['patientAccountId'] as String?;
    if (account == null) return;
    await publish(
      accountId: account,
      category: category,
      title: title,
      body: body,
      dedupeKey: dedupeKey,
      clinicId: tenantId,
      resourceType: resourceType,
      resourceId: resourceId,
    );
  }
}
