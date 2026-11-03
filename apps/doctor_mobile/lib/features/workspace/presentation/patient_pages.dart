import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/clinical_repository.dart';
import 'providers.dart';
import 'ui_kit.dart';
import 'workspace_pages.dart';

/// Find a patient of the clinic (branch scope is applied by the backend).
class PatientSearchPage extends ConsumerStatefulWidget {
  const PatientSearchPage({super.key});

  @override
  ConsumerState<PatientSearchPage> createState() => _PatientSearchState();
}

class _PatientSearchState extends ConsumerState<PatientSearchPage> {
  String _q = '';
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = Query('/patients', {'q': _q, 'limit': '25'});
    return ListView(
      padding: const EdgeInsets.all(EcSpacing.lg),
      children: [
        const PageHeader(
          title: 'Patients',
          subtitle: 'Search by name, patient number or phone.',
        ),
        EcSearchField(
          hint: 'Search patients',
          onChanged: (v) {
            _debounce?.cancel();
            _debounce = Timer(const Duration(milliseconds: 350), () {
              if (mounted) setState(() => _q = v.trim());
            });
          },
        ),
        const SizedBox(height: EcSpacing.md),
        AsyncBody(
          value: ref.watch(listProvider(q)),
          onRetry: () => ref.invalidate(listProvider(q)),
          builder: (rows) => rows.isEmpty
              ? const EcEmptyState(
                  title: 'No patients found',
                  message: 'Try a different name, number or phone.',
                  icon: Icons.person_search_outlined,
                )
              : Column(
                  children: [
                    for (final p in rows)
                      Card(
                        child: ListTile(
                          key: Key('patient-${p['patientId']}'),
                          title: Text('${p['fullName'] ?? ''}'),
                          subtitle: Text(
                            '${p['mrn'] ?? ''} · ${humanize(p['gender'])}',
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () =>
                              context.go('/patients/${p['patientId']}'),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

/// Clinical view of one patient: alerts, allergies, medicines, history,
/// previous consultations and vitals. Opening it is audited by the backend.
class PatientClinicalPage extends ConsumerWidget {
  const PatientClinicalPage({required this.patientId, super.key});

  final String patientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final oq = overviewQuery(patientId);
    return AsyncBody(
      value: ref.watch(mapProvider(oq)),
      onRetry: () => ref.invalidate(mapProvider(oq)),
      builder: (o) {
        final p = (o['patient'] as Map).cast<String, Object?>();
        List<Json>? list(String k) => (o[k] as List?)
            ?.cast<Map<dynamic, dynamic>>()
            .map((e) => e.cast<String, Object?>())
            .toList();
        final alerts = list('alerts') ?? const [];
        final allergies = list('allergies');
        final meds = list('medications');
        final history = list('medicalHistory');
        return ListView(
          padding: const EdgeInsets.all(EcSpacing.lg),
          children: [
            PageHeader(
              title: '${p['fullName']}',
              subtitle:
                  '${p['mrn']} · ${p['age'] ?? '—'} yrs · ${humanize(p['gender'])}'
                  '${p['bloodGroup'] != null ? ' · ${p['bloodGroup']}' : ''}',
              actions: [
                sized(
                  EcPrimaryButton(
                    label: 'New consultation',
                    icon: Icons.medical_services_outlined,
                    onPressed: () => openConsultation(
                      context,
                      ref,
                      patientId: patientId,
                      branchId: p['branchId'] as String?,
                    ),
                  ),
                  300,
                ),
              ],
            ),
            if (alerts.isNotEmpty)
              Section(
                title: 'Alerts',
                child: Column(
                  children: [
                    for (final a in alerts)
                      EcInlineMessage(
                        tone: EcStatusTone.warning,
                        message: '${a['title'] ?? a['message'] ?? a['type']}',
                      ),
                  ],
                ),
              ),
            Section(
              title: 'Allergies',
              child: allergies == null
                  ? const Text('Not available for your role.')
                  : allergies.isEmpty
                  ? const Text('No allergies recorded.')
                  : Column(
                      children: [
                        for (final a in allergies)
                          ListTile(
                            dense: true,
                            title: Text('${a['allergen'] ?? a['name']}'),
                            subtitle: Text(
                              '${humanize(a['severity'])} · ${a['reaction'] ?? ''}',
                            ),
                          ),
                      ],
                    ),
            ),
            Section(
              title: 'Current medications',
              child: meds == null
                  ? const Text('Not available for your role.')
                  : meds.isEmpty
                  ? const Text('None recorded.')
                  : Column(
                      children: [
                        for (final m in meds)
                          ListTile(
                            dense: true,
                            title: Text('${m['name']}'),
                            subtitle: Text(
                              [
                                m['dosage'],
                                m['frequency'],
                              ].where((e) => e != null).join(' · '),
                            ),
                          ),
                      ],
                    ),
            ),
            Section(
              title: 'Medical history',
              child: history == null
                  ? const Text('Not available for your role.')
                  : history.isEmpty
                  ? const Text('None recorded.')
                  : Column(
                      children: [
                        for (final h in history)
                          ListTile(
                            dense: true,
                            title: Text(
                              '${h['title'] ?? h['condition'] ?? h['name']}',
                            ),
                            subtitle: Text(
                              humanize(h['category'] ?? h['type']),
                            ),
                          ),
                      ],
                    ),
            ),
            _VitalsSection(patientId: patientId),
            _HistorySection(patientId: patientId),
          ],
        );
      },
    );
  }
}

class _VitalsSection extends ConsumerWidget {
  const _VitalsSection({required this.patientId});

  final String patientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final q = vitalsQuery(patientId);
    return Section(
      title: 'Vitals',
      trailing: sized(
        EcSecondaryButton(
          label: 'Record vitals',
          icon: Icons.monitor_heart_outlined,
          onPressed: () async {
            final v = await showFormDialog(
              context,
              title: 'Record vitals',
              note:
                  'Enter only what was measured. BMI is calculated, not guessed.',
              fields: const [
                FieldSpec('systolic', 'Systolic (mmHg)'),
                FieldSpec('diastolic', 'Diastolic (mmHg)'),
                FieldSpec('pulse', 'Pulse (bpm)'),
                FieldSpec('temperature', 'Temperature (°C)'),
                FieldSpec('weight', 'Weight (kg)'),
                FieldSpec('height', 'Height (cm)'),
                FieldSpec('notes', 'Notes', kind: FieldKind.multiline),
              ],
            );
            if (v == null || !context.mounted) return;
            final body = <String, Object?>{};
            const units = {'weight': 'kg', 'height': 'cm', 'temperature': 'C'};
            for (final e in v.entries) {
              final n = num.tryParse('${e.value}');
              if (e.key == 'notes') {
                body[e.key] = e.value;
              } else if (units.containsKey(e.key)) {
                body[e.key] = {'value': n ?? e.value, 'unit': units[e.key]};
              } else {
                body[e.key] = n ?? e.value;
              }
            }
            await runAction(
              context,
              action: () => ref
                  .read(clinicalRepositoryProvider)
                  .send('POST', '/clinical/patients/$patientId/vitals', body),
              success: 'Vitals recorded.',
              after: () => refreshAll(ref),
            );
          },
        ),
        300,
      ),
      child: AsyncBody(
        value: ref.watch(listProvider(q)),
        onRetry: () => ref.invalidate(listProvider(q)),
        builder: (rows) => rows.isEmpty
            ? const Text('No vitals recorded.')
            : Column(
                children: [
                  for (final r in rows)
                    ListTile(
                      dense: true,
                      title: Text(shortDateTime(r['measuredAt'])),
                      subtitle: Text(_vitalsLine(r)),
                    ),
                ],
              ),
      ),
    );
  }

  String _vitalsLine(Json r) {
    final parts = <String>[
      if (r['systolic'] != null) 'BP ${r['systolic']}/${r['diastolic']}',
      if (r['pulse'] != null) 'Pulse ${r['pulse']}',
      if (r['temperatureC'] != null) 'Temp ${r['temperatureC']} °C',
      if (r['weightKg'] != null) 'Wt ${r['weightKg']} kg',
      if (r['heightCm'] != null) 'Ht ${r['heightCm']} cm',
      if (r['bmi'] != null)
        'BMI ${r['bmi']}${r['bmiCalculated'] == true ? ' (calculated)' : ''}',
    ];
    return parts.isEmpty ? '—' : parts.join(' · ');
  }
}

String _primary(Json c) {
  final dx = ((c['diagnoses'] as List?) ?? const [])
      .cast<Map<String, Object?>>();
  for (final d in dx) {
    if (d['kind'] == 'primary') return '${d['label']}';
  }
  return humanize(c['type']);
}

class _HistorySection extends ConsumerWidget {
  const _HistorySection({required this.patientId});

  final String patientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final q = historyQuery(patientId);
    return Section(
      title: 'Previous consultations',
      child: AsyncBody(
        value: ref.watch(mapProvider(q)),
        onRetry: () => ref.invalidate(mapProvider(q)),
        builder: (h) {
          final cons = ((h['consultations'] as List?) ?? const []).cast<Json>();
          final lab = (h['laboratory'] as Map?) ?? const {};
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (cons.isEmpty) const Text('No previous consultations.'),
              for (final c in cons)
                ListTile(
                  key: Key('history-${c['consultationId']}'),
                  dense: true,
                  title: Text(shortDate(c['consultationAt'])),
                  subtitle: Text(_primary(c)),
                  trailing: statusChip(c['status']),
                  onTap: () =>
                      context.go('/consultations/${c['consultationId']}'),
                ),
              if (lab['available'] == false)
                const Padding(
                  padding: EdgeInsets.only(top: EcSpacing.sm),
                  child: Text('Laboratory results are not available yet.'),
                ),
            ],
          );
        },
      ),
    );
  }
}
