import 'package:app_core/app_core.dart';
import 'package:common_models/common_models.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:validation/validation.dart';

import '../control_plane/data/control_plane_repository.dart';
import '../shared/async_body.dart';
import '../shared/ui_helpers.dart';
import '../shared/ui_kit.dart';
import 'form_kit.dart';
import 'invite_dialog.dart';
import 'providers.dart';

class DoctorsPage extends ConsumerWidget {
  const DoctorsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final branch = ref.watch(activeBranchProvider);
    return ListScreen(
      title: 'Doctors',
      subtitle: branch == null
          ? 'All doctors you can see.'
          : 'Doctors assigned to the selected branch.',
      path: '/doctors',
      searchHint: 'Search by name',
      statusOptions: const ['active', 'inactive'],
      extraText: const ('Speciality', 'specialty'),
      extraParams: {'branchId': ?branch},
      emptyTitle: 'No doctors found',
      emptyMessage: 'Add a doctor profile, then assign them to a branch.',
      actions: [
        if (can(ref, ClinicPermission.doctorsCreate))
          EcPrimaryButton(
            label: 'Add doctor',
            icon: Icons.add,
            compact: true,
            onPressed: () => context.go('/clinic/doctors/new'),
          ),
      ],
      rowBuilder: (context, d) => RowCard(
        title: '${d['fullName']}',
        subtitle: [
          d['specialty'],
          d['registrationNumber'],
        ].where((e) => e != null && '$e'.isNotEmpty).join(' · '),
        trailing: d['accountStatus'] == 'linked' ? 'Has login' : null,
        status: d['status'],
        onTap: () => context.go('/clinic/doctors/${d['doctorId']}'),
      ),
    );
  }
}

class DoctorDetailPage extends ConsumerWidget {
  const DoctorDetailPage({required this.doctorId, super.key});

  final String doctorId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(doctorDetailProvider(doctorId));
    void reload() => ref.invalidate(doctorDetailProvider(doctorId));
    return AsyncBody(
      value: value,
      onRetry: reload,
      builder: (d) {
        final repo = ref.read(controlPlaneRepositoryProvider);
        final active = d['status'] == 'active';
        final branches = (d['branches']! as List).cast<Map<String, Object?>>();
        final canAssign = can(ref, ClinicPermission.doctorsAssignBranch);
        return ListView(
          padding: const EdgeInsets.all(EcSpacing.lg),
          children: [
            PageHeader(
              title: '${d['fullName']}',
              subtitle: '${d['designation'] ?? ''} · ${d['doctorId']}',
              actions: [
                statusChip(d['status']),
                if (can(ref, ClinicPermission.doctorsUpdate))
                  EcSecondaryButton(
                    label: 'Edit',
                    compact: true,
                    onPressed: () =>
                        context.go('/clinic/doctors/$doctorId/edit'),
                  ),
                if (can(ref, ClinicPermission.doctorsActivate))
                  EcSecondaryButton(
                    label: active ? 'Deactivate' : 'Activate',
                    compact: true,
                    onPressed: () async {
                      if (active) {
                        final ok = await showEcConfirmDialog(
                          context,
                          title: 'Deactivate doctor?',
                          message:
                              'The profile and assignment history are kept. This frees a doctor seat.',
                          confirmLabel: 'Deactivate',
                        );
                        if (!ok || !context.mounted) return;
                      }
                      await runAction(
                        context,
                        action: () => repo.sendMap(
                          'POST',
                          '/doctors/$doctorId/${active ? 'deactivate' : 'activate'}',
                        ),
                        success: active
                            ? 'Doctor deactivated.'
                            : 'Doctor activated.',
                        after: reload,
                      );
                    },
                  ),
              ],
            ),
            Section(
              title: 'Professional profile',
              child: KeyValues([
                (
                  'Speciality',
                  [
                    d['specialty'],
                    d['subSpecialty'],
                  ].where((e) => e != null).join(' / '),
                ),
                (
                  'Qualifications',
                  ((d['qualifications'] as List?) ?? const []).join(', '),
                ),
                ('Registration number', d['registrationNumber']),
                ('Registration council', d['registrationCouncil']),
                (
                  'Experience',
                  d['yearsOfExperience'] == null
                      ? null
                      : '${d['yearsOfExperience']} years',
                ),
                (
                  'Languages',
                  ((d['languages'] as List?) ?? const []).join(', '),
                ),
                (
                  'Consultation fee',
                  Fmt.money(d['consultationFeeMinor'], 'INR'),
                ),
                ('Email', d['email']),
                ('Phone', d['phone']),
                if (d.containsKey('dateOfBirth'))
                  ('Date of birth', d['dateOfBirth']),
              ]),
            ),
            Section(
              title: 'Branches',
              trailing: canAssign && active
                  ? TextButton.icon(
                      onPressed: () => _assign(context, ref, reload),
                      icon: const Icon(Icons.add),
                      label: const Text('Assign to branch'),
                    )
                  : null,
              child: branches.isEmpty
                  ? const Text('Not assigned to any branch.')
                  : Column(
                      children: [
                        for (final b in branches)
                          ListTile(
                            dense: true,
                            title: Text('${b['branchName']}'),
                            subtitle: Text(
                              'Since ${b['effectiveFrom']}${b['consultationFeeMinor'] == null ? '' : ' · fee ${Fmt.money(b['consultationFeeMinor'], 'INR')}'}',
                            ),
                            trailing: canAssign
                                ? IconButton(
                                    tooltip: 'Remove from branch',
                                    icon: const Icon(Icons.link_off),
                                    onPressed: () async {
                                      final ok = await showEcConfirmDialog(
                                        context,
                                        title: 'Remove from branch?',
                                        message:
                                            'The assignment is ended and kept in the history.',
                                        confirmLabel: 'Remove',
                                      );
                                      if (ok && context.mounted) {
                                        await runAction(
                                          context,
                                          action: () => repo.deleteAt(
                                            '/doctors/$doctorId/branches/${b['branchId']}',
                                          ),
                                          success: 'Assignment ended.',
                                          after: reload,
                                        );
                                      }
                                    },
                                  )
                                : null,
                          ),
                      ],
                    ),
            ),
            Section(
              title: 'Login',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  KeyValues([
                    (
                      'Account',
                      statusChip(
                        d['accountStatus'] == 'linked'
                            ? 'active'
                            : d['accountStatus'] == 'invited'
                            ? 'pending'
                            : 'inactive',
                      ),
                    ),
                    ('Status', Fmt.humanize(d['accountStatus'])),
                  ]),
                  if (d['accountStatus'] == 'none' &&
                      active &&
                      can(ref, ClinicPermission.staffInvite))
                    EcSecondaryButton(
                      label: 'Invite to sign in',
                      icon: Icons.mail_outline,
                      compact: true,
                      onPressed: () async {
                        try {
                          final inv = await repo.sendMap(
                            'POST',
                            '/invitations',
                            {'doctorId': doctorId},
                          );
                          reload();
                          if (context.mounted) {
                            await showInviteLinkDialog(context, inv);
                          }
                        } on ApiFailure catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(failureText(e)),
                                backgroundColor: EcColors.error,
                              ),
                            );
                          }
                        }
                      },
                    ),
                  if (d['accountStatus'] == 'invited')
                    const Text(
                      'An invitation is pending. Manage it under Invitations.',
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _assign(
    BuildContext context,
    WidgetRef ref,
    VoidCallback reload,
  ) async {
    final choice = await showDialog<(String, int?)>(
      context: context,
      builder: (_) => const _AssignDialog(),
    );
    if (choice == null || !context.mounted) return;
    await runAction(
      context,
      action: () => ref
          .read(controlPlaneRepositoryProvider)
          .sendMap('POST', '/doctors/$doctorId/branches', {
            'branchId': choice.$1,
            if (choice.$2 != null) 'consultationFeeMinor': choice.$2,
          }),
      success: 'Doctor assigned.',
      after: reload,
    );
  }
}

class _AssignDialog extends ConsumerStatefulWidget {
  const _AssignDialog();

  @override
  ConsumerState<_AssignDialog> createState() => _AssignDialogState();
}

class _AssignDialogState extends ConsumerState<_AssignDialog> {
  String? _branch;
  final _fee = TextEditingController();

  @override
  void dispose() {
    _fee.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final branches = ref.watch(branchChoicesProvider);
    return AlertDialog(
      title: const Text('Assign to branch'),
      content: SizedBox(
        width: 420,
        child: branches.when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => Text(failureText(e)),
          data: (list) {
            final active = list.where((b) => b['status'] == 'active').toList();
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                EcDropdown<String>(
                  label: 'Branch',
                  items: [for (final b in active) b['branchId'] as String],
                  value: _branch,
                  itemLabel: (id) =>
                      '${active.firstWhere((b) => b['branchId'] == id)['name']}',
                  onChanged: (v) => setState(() => _branch = v),
                ),
                const SizedBox(height: EcSpacing.lg),
                EcTextField(
                  label: 'Branch consultation fee in ₹ (optional)',
                  controller: _fee,
                  keyboardType: TextInputType.number,
                ),
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _branch == null
              ? null
              : () {
                  final fee = double.tryParse(_fee.text.trim());
                  Navigator.of(
                    context,
                  ).pop((_branch!, fee == null ? null : (fee * 100).round()));
                },
          child: const Text('Assign'),
        ),
      ],
    );
  }
}

class DoctorFormPage extends ConsumerStatefulWidget {
  const DoctorFormPage({this.doctorId, super.key});

  final String? doctorId;

  @override
  ConsumerState<DoctorFormPage> createState() => _DoctorFormState();
}

class _DoctorFormState extends ConsumerState<DoctorFormPage> {
  final _form = GlobalKey<FormState>();
  final _f = FormFields([
    'fullName',
    'email',
    'phone',
    'designation',
    'qualifications',
    'registrationNumber',
    'registrationCouncil',
    'specialty',
    'subSpecialty',
    'years',
    'languages',
    'fee',
    'dob',
    'bio',
  ]);
  final Set<String> _branches = {};
  bool _loaded = false;
  bool _saving = false;
  String? _error;

  bool get _editing => widget.doctorId != null;

  @override
  void initState() {
    super.initState();
    _loaded = !_editing;
  }

  @override
  void dispose() {
    _f.dispose();
    super.dispose();
  }

  List<String> _list(String key) => _f
      .text(key)
      .split(',')
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();

  void _fill(Json d) {
    _f
      ..set('fullName', d['fullName'])
      ..set('email', d['email'])
      ..set('phone', d['phone'])
      ..set('designation', d['designation'])
      ..set(
        'qualifications',
        ((d['qualifications'] as List?) ?? const []).join(', '),
      )
      ..set('registrationNumber', d['registrationNumber'])
      ..set('registrationCouncil', d['registrationCouncil'])
      ..set('specialty', d['specialty'])
      ..set('subSpecialty', d['subSpecialty'])
      ..set('years', d['yearsOfExperience'])
      ..set('languages', ((d['languages'] as List?) ?? const []).join(', '))
      ..set(
        'fee',
        d['consultationFeeMinor'] == null
            ? null
            : ((d['consultationFeeMinor']! as int) / 100).toStringAsFixed(2),
      )
      ..set('dob', d['dateOfBirth'])
      ..set('bio', d['biography']);
    _loaded = true;
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final fee = double.tryParse(_f.text('fee'));
    final body = <String, Object?>{
      'fullName': _f.text('fullName'),
      'email': _f.text('email'),
      'phone': _f.text('phone'),
      'designation': ?_f.opt('designation'),
      if (_list('qualifications').isNotEmpty)
        'qualifications': _list('qualifications'),
      'registrationNumber': ?_f.opt('registrationNumber'),
      'registrationCouncil': ?_f.opt('registrationCouncil'),
      'specialty': ?_f.opt('specialty'),
      'subSpecialty': ?_f.opt('subSpecialty'),
      if (int.tryParse(_f.text('years')) != null)
        'yearsOfExperience': int.parse(_f.text('years')),
      if (_list('languages').isNotEmpty) 'languages': _list('languages'),
      if (fee != null) 'consultationFeeMinor': (fee * 100).round(),
      'dateOfBirth': ?_f.opt('dob'),
      'biography': ?_f.opt('bio'),
      if (!_editing && _branches.isNotEmpty) 'branchIds': _branches.toList(),
    };
    final repo = ref.read(controlPlaneRepositoryProvider);
    try {
      final saved = _editing
          ? await repo.sendMap('PATCH', '/doctors/${widget.doctorId}', body)
          : await repo.sendMap('POST', '/doctors', body);
      ref.invalidate(doctorDetailProvider('${saved['doctorId']}'));
      if (mounted) context.go('/clinic/doctors/${saved['doctorId']}');
    } on ApiFailure catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = failureText(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return AsyncBody(
        value: ref.watch(doctorDetailProvider(widget.doctorId!)),
        onRetry: () => ref.invalidate(doctorDetailProvider(widget.doctorId!)),
        builder: (d) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && !_loaded) setState(() => _fill(d));
          });
          return const EcLoadingIndicator();
        },
      );
    }
    final branchList =
        ref
            .watch(branchChoicesProvider)
            .asData
            ?.value
            .where((b) => b['status'] == 'active')
            .toList() ??
        const [];
    return ListView(
      padding: const EdgeInsets.all(EcSpacing.lg),
      children: [
        PageHeader(
          title: _editing ? 'Edit doctor' : 'Add doctor',
          subtitle:
              'A doctor has one profile and can work at several branches. A login is created later through an invitation.',
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: EcSpacing.lg),
            child: EcInlineMessage(message: _error!),
          ),
        Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Section(
                title: 'Profile',
                child: Wrap(
                  spacing: EcSpacing.lg,
                  runSpacing: EcSpacing.lg,
                  children: [
                    TextRow(
                      label: 'Full name',
                      controller: _f['fullName'],
                      validator: (v) => requiredText(v, min: 2, label: 'Name'),
                      maxLength: 100,
                    ),
                    TextRow(
                      label: 'Email',
                      controller: _f['email'],
                      validator: (v) => Validators.email(v)?.message,
                    ),
                    TextRow(
                      label: 'Phone',
                      controller: _f['phone'],
                      validator: (v) => Validators.indianMobile(v)?.message,
                    ),
                    TextRow(
                      label: 'Designation',
                      controller: _f['designation'],
                      maxLength: 80,
                    ),
                    TextRow(
                      label: 'Date of birth (YYYY-MM-DD)',
                      controller: _f['dob'],
                      maxLength: 10,
                    ),
                    TextRow(
                      label: 'Qualifications (comma separated)',
                      controller: _f['qualifications'],
                      width: 620,
                      maxLength: 400,
                    ),
                    TextRow(
                      label: 'Speciality',
                      controller: _f['specialty'],
                      maxLength: 60,
                    ),
                    TextRow(
                      label: 'Sub-speciality',
                      controller: _f['subSpecialty'],
                      maxLength: 60,
                    ),
                    TextRow(
                      label: 'Years of experience',
                      controller: _f['years'],
                      validator: (v) => wholeNumber(v, optional: true, max: 70),
                      width: 200,
                      maxLength: 2,
                    ),
                    TextRow(
                      label: 'Languages (comma separated)',
                      controller: _f['languages'],
                      maxLength: 200,
                    ),
                    TextRow(
                      label: 'Default consultation fee (₹)',
                      controller: _f['fee'],
                      width: 220,
                      maxLength: 9,
                      validator: (v) =>
                          (v ?? '').trim().isEmpty ||
                              double.tryParse(v!.trim()) != null
                          ? null
                          : 'Enter an amount.',
                    ),
                    TextRow(
                      label: 'Biography',
                      controller: _f['bio'],
                      width: 620,
                      lines: 3,
                      maxLength: 1000,
                    ),
                  ],
                ),
              ),
              Section(
                title: 'Medical registration',
                child: Wrap(
                  spacing: EcSpacing.lg,
                  runSpacing: EcSpacing.lg,
                  children: [
                    TextRow(
                      label: 'Registration number',
                      controller: _f['registrationNumber'],
                      maxLength: 30,
                    ),
                    TextRow(
                      label: 'Registration council / state',
                      controller: _f['registrationCouncil'],
                      maxLength: 80,
                    ),
                  ],
                ),
              ),
              if (!_editing)
                Section(
                  title: 'Branches',
                  child: branchList.isEmpty
                      ? const Text(
                          'No active branches yet. You can assign branches later.',
                        )
                      : Wrap(
                          spacing: EcSpacing.sm,
                          children: [
                            for (final b in branchList)
                              FilterChip(
                                label: Text('${b['name']}'),
                                selected: _branches.contains(b['branchId']),
                                onSelected: (v) => setState(
                                  () => v
                                      ? _branches.add('${b['branchId']}')
                                      : _branches.remove('${b['branchId']}'),
                                ),
                              ),
                          ],
                        ),
                ),
              Row(
                children: [
                  SizedBox(
                    width: 200,
                    child: EcPrimaryButton(
                      label: _editing ? 'Save changes' : 'Add doctor',
                      isLoading: _saving,
                      onPressed: _save,
                    ),
                  ),
                  const SizedBox(width: EcSpacing.md),
                  TextButton(
                    onPressed: _saving
                        ? null
                        : () => context.go('/clinic/doctors'),
                    child: const Text('Cancel'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
