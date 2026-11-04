import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/portal_repository.dart';
import 'providers.dart';
import 'ui_kit.dart';

/// Linked clinics, clinic search and linking with a clinic-issued code.
class ClinicsPage extends ConsumerStatefulWidget {
  const ClinicsPage({super.key});

  @override
  ConsumerState<ClinicsPage> createState() => _ClinicsState();
}

class _ClinicsState extends ConsumerState<ClinicsPage> {
  String _q = '';
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _link() async {
    final person = ref.read(selectedPersonProvider);
    final v = await showFormDialog(
      context,
      title: 'Link a clinic record',
      note:
          'Enter the one-time code the clinic gave you after checking your identity. Your phone number or e-mail alone never links a record.',
      confirmLabel: 'Link',
      fields: const [
        FieldSpec('code', 'Link code', required: true, maxLength: 30),
      ],
    );
    if (v == null || !mounted) return;
    await runAction(
      context,
      action: () => ref.read(portalRepositoryProvider).send(
        'POST',
        '/patient-accounts/me/link-clinic-record',
        {'code': v['code'], 'forAccountId': ?person},
      ),
      success: 'Clinic linked.',
      after: () => refreshAll(ref),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(mapProvider(Query('/patient/profile')));
    final searchQ = Query('/patient/clinics', {'q': _q});
    final linked =
        ((profile.asData?.value['linkedClinics'] as List?) ?? const [])
            .cast<Json>();
    return ListView(
      padding: const EdgeInsets.all(EcSpacing.lg),
      children: [
        PageHeader(
          title: 'Clinics',
          subtitle:
              'Find a clinic, then link your record with a code from the clinic.',
          actions: [
            sized(
              EcPrimaryButton(
                label: 'Link with a code',
                icon: Icons.link,
                onPressed: _link,
              ),
              220,
            ),
          ],
        ),
        Section(
          title: 'My clinics',
          child: linked.isEmpty
              ? const Text('You have not linked a clinic yet.')
              : Column(
                  children: [
                    for (final c in linked)
                      ListTile(
                        key: Key('linked-${c['clinicId']}'),
                        title: Text('${c['clinicName'] ?? 'Clinic'}'),
                        subtitle: Text('Patient number ${c['mrn'] ?? '—'}'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => context.go('/clinics/${c['clinicId']}'),
                      ),
                  ],
                ),
        ),
        EcSearchField(
          hint: 'Search clinics by name',
          onChanged: (v) {
            _debounce?.cancel();
            _debounce = Timer(const Duration(milliseconds: 350), () {
              if (mounted) setState(() => _q = v.trim());
            });
          },
        ),
        const SizedBox(height: EcSpacing.md),
        AsyncBody(
          value: ref.watch(listProvider(searchQ)),
          onRetry: () => ref.invalidate(listProvider(searchQ)),
          builder: (rows) => rows.isEmpty
              ? const EcEmptyState(
                  title: 'No clinics found',
                  message:
                      'Only clinics that accept patients in this app are listed.',
                  icon: Icons.search_off_outlined,
                )
              : Column(
                  children: [
                    for (final c in rows)
                      Card(
                        child: ListTile(
                          key: Key('clinic-${c['clinicId']}'),
                          title: Text('${c['name']}'),
                          subtitle: Text(_address(c['address'])),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => context.go('/clinics/${c['clinicId']}'),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

String _address(Object? a) {
  if (a is! Map) return '';
  return [
    a['line1'],
    a['city'],
    a['state'],
  ].where((e) => e != null && '$e'.isNotEmpty).join(', ');
}

/// A clinic's public profile: branches, appointment types and doctors.
class ClinicDetailPage extends ConsumerStatefulWidget {
  const ClinicDetailPage({required this.clinicId, super.key});

  final String clinicId;

  @override
  ConsumerState<ClinicDetailPage> createState() => _ClinicDetailState();
}

class _ClinicDetailState extends ConsumerState<ClinicDetailPage> {
  String? _speciality;

  @override
  Widget build(BuildContext context) {
    final q = Query('/patient/clinics/${widget.clinicId}');
    final specQ = Query('/patient/clinics/${widget.clinicId}/specialities');
    final docQ = Query('/patient/clinics/${widget.clinicId}/doctors', {
      'speciality': _speciality ?? '',
    });
    final profile = ref
        .watch(mapProvider(Query('/patient/profile')))
        .asData
        ?.value;
    final isLinked = ((profile?['linkedClinics'] as List?) ?? const []).any(
      (c) => (c as Map)['clinicId'] == widget.clinicId,
    );
    return AsyncBody(
      value: ref.watch(mapProvider(q)),
      onRetry: () => ref.invalidate(mapProvider(q)),
      builder: (c) {
        final branches = ((c['branches'] as List?) ?? const []).cast<Json>();
        final types = ((c['appointmentTypes'] as List?) ?? const [])
            .cast<Json>();
        return ListView(
          padding: const EdgeInsets.all(EcSpacing.lg),
          children: [
            PageHeader(
              title: '${c['name']}',
              subtitle: _address(c['address']),
              actions: [
                if (isLinked)
                  sized(
                    EcPrimaryButton(
                      label: 'Book appointment',
                      icon: Icons.event_available_outlined,
                      onPressed: () => context.go(
                        '/appointments/new?clinicId=${widget.clinicId}',
                      ),
                    ),
                    240,
                  ),
              ],
            ),
            if (!isLinked)
              const EcInlineMessage(
                tone: EcStatusTone.info,
                message:
                    'Viewing a clinic does not give access to any record. To book and see your records, link your record with a code from this clinic.',
              ),
            Section(
              title: 'Contact',
              child: KeyValues([
                ('Phone', c['phone']),
                ('E-mail', c['email']),
                ('Website', c['website']),
                ('About', c['description']),
              ]),
            ),
            Section(
              title: 'Branches',
              child: Column(
                children: [
                  for (final b in branches)
                    ListTile(
                      dense: true,
                      title: Text('${b['name']}'),
                      subtitle: Text(
                        '${_address(b['address'])}${b['phone'] == null ? '' : ' · ${b['phone']}'}',
                      ),
                    ),
                ],
              ),
            ),
            Section(
              title: 'Appointment types',
              child: types.isEmpty
                  ? const Text('Not published.')
                  : Column(
                      children: [
                        for (final t in types)
                          ListTile(
                            dense: true,
                            title: Text('${t['name']}'),
                            subtitle: Text('${t['durationMinutes']} minutes'),
                          ),
                      ],
                    ),
            ),
            Section(
              title: 'Doctors',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AsyncBody(
                    value: ref.watch(stringsProvider(specQ)),
                    onRetry: () => ref.invalidate(stringsProvider(specQ)),
                    builder: (specs) => Wrap(
                      spacing: EcSpacing.sm,
                      children: [
                        ChoiceChip(
                          label: const Text('All'),
                          selected: _speciality == null,
                          onSelected: (_) => setState(() => _speciality = null),
                        ),
                        for (final s in specs)
                          ChoiceChip(
                            label: Text(s),
                            selected: _speciality == s,
                            onSelected: (_) => setState(() => _speciality = s),
                          ),
                      ],
                    ),
                  ),
                  AsyncBody(
                    value: ref.watch(listProvider(docQ)),
                    onRetry: () => ref.invalidate(listProvider(docQ)),
                    builder: (rows) => Column(
                      children: [
                        for (final d in rows)
                          ListTile(
                            key: Key('doctor-${d['doctorId']}'),
                            title: Text('${d['fullName']}'),
                            subtitle: Text(
                              [
                                d['specialty'],
                                if (d['yearsOfExperience'] != null)
                                  '${d['yearsOfExperience']} years',
                              ].where((e) => e != null).join(' · '),
                            ),
                            trailing: d['consultationFeeMinor'] == null
                                ? null
                                : Text(money(d['consultationFeeMinor'])),
                            onTap: () => _doctor(context, d),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  void _doctor(BuildContext context, Json d) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('${d['fullName']}'),
      content: SingleChildScrollView(
        child: KeyValues([
          ('Speciality', d['specialty']),
          (
            'Qualifications',
            ((d['qualifications'] as List?) ?? const []).join(', '),
          ),
          (
            'Experience',
            d['yearsOfExperience'] == null
                ? null
                : '${d['yearsOfExperience']} years',
          ),
          ('Languages', ((d['languages'] as List?) ?? const []).join(', ')),
          (
            'Consultation fee',
            d['consultationFeeMinor'] == null
                ? null
                : money(d['consultationFeeMinor']),
          ),
          ('About', d['biography']),
          ('Consultation', 'In person'),
        ]),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}
