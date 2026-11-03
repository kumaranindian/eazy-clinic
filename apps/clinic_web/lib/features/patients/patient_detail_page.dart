import 'package:common_models/common_models.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../clinic_admin/providers.dart';
import '../control_plane/data/control_plane_repository.dart';
import '../scheduling/queue_page.dart' show PatientAppointmentsTab;
import '../shared/async_body.dart';
import '../shared/ui_helpers.dart';
import '../shared/ui_kit.dart';
import 'dialogs.dart';
import 'patient_providers.dart';
import 'patient_tabs.dart';

/// One clinic patient record. Tabs appear only for roles that may see their
/// content; the backend authorizes every request again.
class PatientDetailPage extends ConsumerWidget {
  const PatientDetailPage({required this.patientId, super.key});

  final String patientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(patientDetailProvider(patientId));
    void reload() => ref.invalidate(patientDetailProvider(patientId));
    return AsyncBody(
      value: value,
      onRetry: reload,
      builder: (p) {
        final tabs = <(String, Widget)>[
          ('Overview', _Overview(patient: p, reload: reload)),
          if (can(ref, ClinicPermission.historyView))
            ('Medical history', HistoryTab(patientId: patientId)),
          if (can(ref, ClinicPermission.allergiesView))
            ('Allergies', AllergiesTab(patientId: patientId)),
          if (can(ref, ClinicPermission.medicationsView))
            ('Medications', MedicationsTab(patientId: patientId)),
          if (can(ref, ClinicPermission.alertsView))
            ('Alerts', AlertsTab(patientId: patientId)),
          if (can(ref, ClinicPermission.appointmentsView))
            ('Appointments', PatientAppointmentsTab(patientId: patientId)),
          if (can(ref, ClinicPermission.consentsView))
            ('Consent', ConsentTab(patient: p)),
          if (can(ref, ClinicPermission.patientDocumentsView))
            ('Documents', DocumentsTab(patientId: patientId)),
          if (can(ref, ClinicPermission.patientsLinkAccount))
            ('Identity', IdentityTab(patient: p, onChanged: reload)),
          if (can(ref, ClinicPermission.patientAuditView))
            ('Audit', AuditTab(patientId: patientId)),
        ];
        return DefaultTabController(
          key: ValueKey(tabs.length),
          length: tabs.length,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  EcSpacing.lg,
                  EcSpacing.lg,
                  EcSpacing.lg,
                  0,
                ),
                child: _Header(patient: p, reload: reload),
              ),
              _SafetyBanner(patient: p),
              TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: [for (final t in tabs) Tab(text: t.$1)],
              ),
              Expanded(
                child: TabBarView(children: [for (final t in tabs) t.$2]),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header({required this.patient, required this.reload});

  final Json patient;
  final VoidCallback reload;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = '${patient['patientId']}';
    final status = '${patient['status']}';
    final repo = ref.read(controlPlaneRepositoryProvider);
    Future<void> change(
      String path,
      String done,
      String title,
      String msg,
    ) async {
      final reason = await askReason(context, title: title, message: msg);
      if (reason == null || !context.mounted) return;
      await runAction(
        context,
        action: () =>
            repo.sendMap('POST', '/patients/$id/$path', {'reason': reason}),
        success: done,
        after: reload,
      );
    }

    final editable = status == 'active' || status == 'inactive';
    return PageHeader(
      title: '${patient['fullName']}',
      subtitle:
          '${patient['mrn']} · ${patient['dateOfBirth']} · ${Fmt.humanize(patient['gender'])}',
      actions: [
        statusChip(status),
        if (editable && can(ref, ClinicPermission.patientsUpdate))
          EcSecondaryButton(
            label: 'Edit',
            compact: true,
            onPressed: () => context.go('/clinic/patients/$id/edit'),
          ),
        if (can(ref, ClinicPermission.patientsStatus)) ...[
          if (status == 'inactive')
            EcPrimaryButton(
              label: 'Activate',
              compact: true,
              onPressed: () async {
                await runAction(
                  context,
                  action: () => repo.sendMap('POST', '/patients/$id/activate'),
                  success: 'Patient activated.',
                  after: reload,
                );
              },
            ),
          if (status == 'active')
            EcSecondaryButton(
              label: 'Deactivate',
              compact: true,
              onPressed: () => change(
                'deactivate',
                'Patient deactivated.',
                'Deactivate patient?',
                'The record and its history are kept.',
              ),
            ),
          if (editable)
            EcSecondaryButton(
              label: 'Archive',
              compact: true,
              onPressed: () => change(
                'archive',
                'Patient archived.',
                'Archive patient?',
                'Archived records stay on file but cannot be changed or reactivated.',
              ),
            ),
        ],
      ],
    );
  }
}

/// Active alerts and allergies, shown before anything else. Missing allergy
/// information is never presented as "no allergies".
class _SafetyBanner extends ConsumerWidget {
  const _SafetyBanner({required this.patient});

  final Json patient;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alerts = ((patient['alerts'] as List?) ?? const [])
        .cast<Map<String, Object?>>();
    final allergies = patient['activeAllergies'] as List?;
    if (alerts.isEmpty && allergies == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: EcSpacing.lg,
        vertical: EcSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final a in alerts)
            Padding(
              padding: const EdgeInsets.only(bottom: EcSpacing.xs),
              child: EcInlineMessage(
                key: Key('alert-${a['alertId']}'),
                tone: a['priority'] == 'critical'
                    ? EcStatusTone.error
                    : EcStatusTone.warning,
                message: '${a['title']}: ${a['message']}',
              ),
            ),
          if (allergies != null)
            allergies.isEmpty
                ? const EcInlineMessage(
                    key: Key('no-allergy-info'),
                    tone: EcStatusTone.info,
                    message:
                        'No allergy information recorded. This does not mean the patient has no known allergies.',
                  )
                : EcInlineMessage(
                    key: const Key('allergy-banner'),
                    tone: EcStatusTone.error,
                    message:
                        'Allergies: ${allergies.cast<Map<String, Object?>>().map((a) => '${a['allergen']}${a['severity'] == 'severe' ? ' (severe)' : ''}${a['verificationStatus'] == 'verified' ? '' : ' (unverified)'}').join(', ')}',
                  ),
        ],
      ),
    );
  }
}

class _Overview extends ConsumerWidget {
  const _Overview({required this.patient, required this.reload});

  final Json patient;
  final VoidCallback reload;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = (patient['address'] as Map<String, Object?>?) ?? const {};
    final g = patient['guardian'] as Map<String, Object?>?;
    final id = '${patient['patientId']}';
    final contacts = ref.watch(emergencyContactsProvider(id));
    final names = {
      for (final b
          in ref.watch(branchChoicesProvider).asData?.value ?? const <Json>[])
        '${b['branchId']}': '${b['name']}',
    };
    return ListView(
      padding: const EdgeInsets.all(EcSpacing.lg),
      children: [
        Section(
          title: 'Personal information',
          child: KeyValues([
            ('Preferred name', patient['preferredName']),
            ('Blood group', patient['bloodGroup']),
            ('Occupation', patient['occupation']),
            ('Branch', names['${patient['branchId']}'] ?? patient['branchId']),
            ('Clinic ID', patient['patientId']),
            (
              'Mobile app',
              patient['patientAccountId'] == null ? 'Not linked' : 'Linked',
            ),
            ('Registered', Fmt.date(patient['createdAt'])),
            ('Last updated', Fmt.date(patient['updatedAt'])),
            if (patient.containsKey('restrictedNotes'))
              ('Restricted notes', patient['restrictedNotes']),
          ]),
        ),
        Section(
          title: 'Contact and address',
          child: KeyValues([
            ('Phone', patient['phone']),
            ('Alternate phone', patient['alternatePhone']),
            ('Email', patient['email']),
            ('Language', patient['preferredLanguage']),
            (
              'Preferred contact',
              Fmt.humanize(patient['preferredContactMethod']),
            ),
            (
              'Address',
              [
                a['line1'],
                a['line2'],
                a['city'],
                a['state'],
                a['postalCode'],
                a['country'],
              ].where((e) => e != null && '$e'.isNotEmpty).join(', '),
            ),
          ]),
        ),
        if (g != null)
          Section(
            title: 'Guardian',
            child: KeyValues([
              ('Name', g['name']),
              ('Relationship', g['relationship']),
              ('Phone', g['phone']),
              (
                'Verification',
                g['verified'] == true
                    ? 'Verified by staff (${Fmt.humanize(g['verificationMethod'])})'
                    : 'Not verified',
              ),
            ]),
          ),
        Section(
          title: 'Emergency contacts',
          child: AsyncBody(
            value: contacts,
            onRetry: () => ref.invalidate(emergencyContactsProvider(id)),
            builder: (c) {
              final list = ((c['contacts'] as List?) ?? const [])
                  .cast<Map<String, Object?>>();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (list.isEmpty)
                    const Text('No emergency contact recorded.'),
                  for (final e in list)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        '${e['name']} (${e['relationship']})${e['preferred'] == true ? ' · preferred' : ''}',
                      ),
                      subtitle: Text(
                        '${e['phone']}${e['alternatePhone'] == null ? '' : ' · ${e['alternatePhone']}'}',
                      ),
                    ),
                  if (can(ref, ClinicPermission.patientsUpdate) &&
                      patient['status'] != 'archived')
                    EcSecondaryButton(
                      label: list.isEmpty
                          ? 'Add contact'
                          : 'Replace main contact',
                      compact: true,
                      onPressed: () async {
                        final r = await showRecordDialog(
                          context,
                          title: 'Emergency contact',
                          fields: const [
                            FieldSpec('name', 'Name', required: true),
                            FieldSpec(
                              'relationship',
                              'Relationship',
                              required: true,
                            ),
                            FieldSpec('phone', 'Phone', required: true),
                            FieldSpec('alternatePhone', 'Alternate phone'),
                          ],
                          initial: list.isEmpty ? const {} : list.first,
                        );
                        if (r == null || !context.mounted) return;
                        await runAction(
                          context,
                          action: () =>
                              ref.read(controlPlaneRepositoryProvider).sendMap(
                                'PUT',
                                '/patients/$id/emergency-contacts',
                                {
                                  'contacts': [
                                    {...r, 'preferred': true},
                                    ...list
                                        .skip(1)
                                        .map(
                                          (e) => {
                                            'name': e['name'],
                                            'relationship': e['relationship'],
                                            'phone': e['phone'],
                                            'preferred': false,
                                          },
                                        ),
                                  ],
                                },
                              ),
                          success: 'Emergency contact saved.',
                          after: () =>
                              ref.invalidate(emergencyContactsProvider(id)),
                        );
                      },
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}
