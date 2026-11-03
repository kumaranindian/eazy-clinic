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
import 'providers.dart';

const branchTypeChoices = [
  'main',
  'satellite',
  'clinic',
  'diagnostic',
  'other',
];

class BranchesPage extends ConsumerWidget {
  const BranchesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListScreen(
      title: 'Branches',
      subtitle: 'Locations of your clinic. Limits come from your subscription.',
      path: '/branches',
      searchHint: 'Search name or code',
      statusOptions: const ['active', 'inactive'],
      emptyTitle: 'No branches yet',
      emptyMessage:
          'Create your first branch to start assigning doctors and staff.',
      actions: [
        if (can(ref, ClinicPermission.branchesCreate))
          EcPrimaryButton(
            label: 'New branch',
            icon: Icons.add,
            compact: true,
            onPressed: () => context.go('/clinic/branches/new'),
          ),
      ],
      rowBuilder: (context, b) => RowCard(
        title: '${b['name']} (${b['code']})',
        subtitle:
            '${Fmt.humanize(b['type'])} · ${(b['address'] as Map<String, Object?>?)?['city'] ?? ''}',
        status: b['status'],
        onTap: () => context.go('/clinic/branches/${b['branchId']}'),
      ),
    );
  }
}

class BranchDetailPage extends ConsumerWidget {
  const BranchDetailPage({required this.branchId, super.key});

  final String branchId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(branchDetailProvider(branchId));
    void reload() {
      ref.invalidate(branchDetailProvider(branchId));
      ref.invalidate(branchChoicesProvider);
    }

    return AsyncBody(
      value: value,
      onRetry: reload,
      builder: (b) {
        final address = (b['address'] as Map<String, Object?>?) ?? const {};
        final hours = b['weeklyHours'] as Map<String, Object?>?;
        final doctors = (b['doctors']! as List).cast<Map<String, Object?>>();
        final staff = (b['staff']! as List).cast<Map<String, Object?>>();
        final repo = ref.read(controlPlaneRepositoryProvider);
        final active = b['status'] == 'active';
        return ListView(
          padding: const EdgeInsets.all(EcSpacing.lg),
          children: [
            PageHeader(
              title: '${b['name']}',
              subtitle: 'Code ${b['code']} · ${b['branchId']}',
              actions: [
                statusChip(b['status']),
                if (can(ref, ClinicPermission.branchesUpdate))
                  EcSecondaryButton(
                    label: 'Edit',
                    compact: true,
                    onPressed: () =>
                        context.go('/clinic/branches/$branchId/edit'),
                  ),
                if (active && can(ref, ClinicPermission.branchesDeactivate))
                  EcSecondaryButton(
                    label: 'Deactivate',
                    compact: true,
                    onPressed: () async {
                      final ok = await showEcConfirmDialog(
                        context,
                        title: 'Deactivate branch?',
                        message:
                            'The branch stays on record with its history but can no longer be used. A clinic needs at least one active branch.',
                        confirmLabel: 'Deactivate',
                      );
                      if (ok && context.mounted) {
                        await runAction(
                          context,
                          action: () => repo.sendMap(
                            'POST',
                            '/branches/$branchId/deactivate',
                          ),
                          success: 'Branch deactivated.',
                          after: reload,
                        );
                      }
                    },
                  ),
                if (!active &&
                    b['status'] == 'inactive' &&
                    can(ref, ClinicPermission.branchesActivate))
                  EcPrimaryButton(
                    label: 'Activate',
                    compact: true,
                    onPressed: () => runAction(
                      context,
                      action: () =>
                          repo.sendMap('POST', '/branches/$branchId/activate'),
                      success: 'Branch activated.',
                      after: reload,
                    ),
                  ),
              ],
            ),
            Section(
              title: 'Details',
              child: KeyValues([
                ('Type', Fmt.humanize(b['type'])),
                ('Email', b['email']),
                ('Phone', b['phone']),
                (
                  'Address',
                  [
                    address['line1'],
                    address['line2'],
                    address['city'],
                    address['state'],
                    address['postalCode'],
                  ].where((e) => e != null && '$e'.isNotEmpty).join(', '),
                ),
                ('Time zone', b['timezone'] ?? 'Clinic default'),
              ]),
            ),
            Section(
              title: 'Operating hours',
              child: hours == null
                  ? const Text('Uses the clinic hours.')
                  : Column(
                      children: [
                        for (var d = 1; d <= 7; d++)
                          KeyValues([
                            (
                              weekdayNames[d - 1],
                              ((hours['$d']
                                          as Map<String, Object?>?)?['open'] ==
                                      true)
                                  ? '${(hours['$d'] as Map)['from']} – ${(hours['$d'] as Map)['to']}'
                                  : 'Closed',
                            ),
                          ]),
                      ],
                    ),
            ),
            Section(
              title: 'Doctors (${doctors.length})',
              child: doctors.isEmpty
                  ? const Text('No doctors assigned.')
                  : Column(
                      children: [
                        for (final d in doctors)
                          ListTile(
                            dense: true,
                            title: Text('${d['fullName']}'),
                            subtitle: Text('${d['specialty'] ?? ''}'),
                            onTap: () =>
                                context.go('/clinic/doctors/${d['doctorId']}'),
                          ),
                      ],
                    ),
            ),
            Section(
              title: 'Staff (${staff.length})',
              child: staff.isEmpty
                  ? const Text('No staff assigned.')
                  : Column(
                      children: [
                        for (final s in staff)
                          ListTile(
                            dense: true,
                            title: Text('${s['fullName']}'),
                            subtitle: Text(Fmt.humanize(s['role'])),
                            trailing: statusChip(s['status']),
                            onTap: () =>
                                context.go('/clinic/staff/${s['staffId']}'),
                          ),
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }
}

class BranchFormPage extends ConsumerStatefulWidget {
  const BranchFormPage({this.branchId, super.key});

  final String? branchId;

  @override
  ConsumerState<BranchFormPage> createState() => _BranchFormState();
}

class _BranchFormState extends ConsumerState<BranchFormPage> {
  final _form = GlobalKey<FormState>();
  final _f = FormFields([
    'name',
    'code',
    'email',
    'phone',
    'line1',
    'line2',
    'city',
    'state',
    'country',
    'postalCode',
  ]);
  String _type = 'clinic';
  bool _ownHours = false;
  Map<String, Object?> _weekly = {};
  Map<String, Object?>? _initialWeekly;
  bool _loaded = false;
  bool _saving = false;
  String? _error;

  bool get _editing => widget.branchId != null;

  @override
  void initState() {
    super.initState();
    if (!_editing) {
      _f.set('country', 'India');
      _loaded = true;
    }
  }

  @override
  void dispose() {
    _f.dispose();
    super.dispose();
  }

  void _fill(Json b) {
    final a = (b['address'] as Map<String, Object?>?) ?? const {};
    _f
      ..set('name', b['name'])
      ..set('code', b['code'])
      ..set('email', b['email'])
      ..set('phone', b['phone'])
      ..set('line1', a['line1'])
      ..set('line2', a['line2'])
      ..set('city', a['city'])
      ..set('state', a['state'])
      ..set('country', a['country'])
      ..set('postalCode', a['postalCode']);
    _type = branchTypeChoices.contains(b['type'])
        ? b['type']! as String
        : _type;
    _initialWeekly = (b['weeklyHours'] as Map?)?.cast<String, Object?>();
    _ownHours = _initialWeekly != null;
    _weekly = {...?_initialWeekly};
    _loaded = true;
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final body = <String, Object?>{
      'name': _f.text('name'),
      if (!_editing) 'code': _f.text('code'),
      'type': _type,
      'email': ?_f.opt('email'),
      'phone': ?_f.opt('phone'),
      'address': {
        'line1': _f.text('line1'),
        'line2': ?_f.opt('line2'),
        'city': _f.text('city'),
        'state': _f.text('state'),
        'country': _f.text('country'),
        'postalCode': _f.text('postalCode'),
      },
      if (_ownHours)
        'weeklyHours': _weekly
      else if (_editing)
        'weeklyHours': null,
    };
    final repo = ref.read(controlPlaneRepositoryProvider);
    try {
      final saved = _editing
          ? await repo.sendMap('PATCH', '/branches/${widget.branchId}', body)
          : await repo.sendMap('POST', '/branches', body);
      ref.invalidate(branchChoicesProvider);
      ref.invalidate(clinicAccessProvider);
      ref.invalidate(branchDetailProvider('${saved['branchId']}'));
      if (mounted) context.go('/clinic/branches/${saved['branchId']}');
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
        value: ref.watch(branchDetailProvider(widget.branchId!)),
        onRetry: () => ref.invalidate(branchDetailProvider(widget.branchId!)),
        builder: (b) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && !_loaded) setState(() => _fill(b));
          });
          return const EcLoadingIndicator();
        },
      );
    }
    return ListView(
      padding: const EdgeInsets.all(EcSpacing.lg),
      children: [
        PageHeader(title: _editing ? 'Edit branch' : 'New branch'),
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
                title: 'Branch',
                child: Wrap(
                  spacing: EcSpacing.lg,
                  runSpacing: EcSpacing.lg,
                  children: [
                    TextRow(
                      label: 'Branch name',
                      controller: _f['name'],
                      validator: (v) => requiredText(v, min: 2, label: 'Name'),
                      maxLength: 80,
                    ),
                    TextRow(
                      label: 'Branch code',
                      controller: _f['code'],
                      enabled: !_editing,
                      validator: (v) =>
                          RegExp(
                            r'^[A-Za-z0-9\-]{2,12}$',
                          ).hasMatch((v ?? '').trim())
                          ? null
                          : 'Use 2–12 letters, digits or hyphens.',
                      width: 200,
                      maxLength: 12,
                    ),
                    SizedBox(
                      width: 220,
                      child: EcDropdown<String>(
                        label: 'Type',
                        items: branchTypeChoices,
                        value: _type,
                        itemLabel: Fmt.humanize,
                        onChanged: (v) => setState(() => _type = v ?? _type),
                      ),
                    ),
                    TextRow(
                      label: 'Email',
                      controller: _f['email'],
                      validator: (v) => (v ?? '').trim().isEmpty
                          ? null
                          : Validators.email(v)?.message,
                    ),
                    TextRow(
                      label: 'Phone',
                      controller: _f['phone'],
                      validator: (v) => (v ?? '').trim().isEmpty
                          ? null
                          : Validators.indianMobile(v)?.message,
                    ),
                  ],
                ),
              ),
              Section(
                title: 'Address',
                child: Wrap(
                  spacing: EcSpacing.lg,
                  runSpacing: EcSpacing.lg,
                  children: [
                    TextRow(
                      label: 'Address line 1',
                      controller: _f['line1'],
                      validator: (v) =>
                          requiredText(v, min: 3, label: 'Address'),
                      maxLength: 120,
                    ),
                    TextRow(
                      label: 'Address line 2',
                      controller: _f['line2'],
                      maxLength: 120,
                    ),
                    TextRow(
                      label: 'City',
                      controller: _f['city'],
                      validator: (v) => requiredText(v, min: 2, label: 'City'),
                      maxLength: 60,
                    ),
                    TextRow(
                      label: 'State',
                      controller: _f['state'],
                      validator: (v) => requiredText(v, min: 2, label: 'State'),
                      maxLength: 60,
                    ),
                    TextRow(
                      label: 'Country',
                      controller: _f['country'],
                      validator: (v) =>
                          requiredText(v, min: 2, label: 'Country'),
                      maxLength: 60,
                    ),
                    TextRow(
                      label: 'PIN / postal code',
                      controller: _f['postalCode'],
                      validator: (v) =>
                          requiredText(v, min: 3, label: 'PIN code'),
                      maxLength: 10,
                    ),
                  ],
                ),
              ),
              Section(
                title: 'Operating hours',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('This branch has its own hours'),
                      subtitle: const Text(
                        'Otherwise it follows the clinic hours.',
                      ),
                      value: _ownHours,
                      onChanged: (v) => setState(() => _ownHours = v),
                    ),
                    if (_ownHours)
                      WeeklyHoursEditor(
                        initial: _initialWeekly,
                        onChanged: (w) => _weekly = w,
                      ),
                  ],
                ),
              ),
              Row(
                children: [
                  SizedBox(
                    width: 200,
                    child: EcPrimaryButton(
                      label: _editing ? 'Save changes' : 'Create branch',
                      isLoading: _saving,
                      onPressed: _save,
                    ),
                  ),
                  const SizedBox(width: EcSpacing.md),
                  TextButton(
                    onPressed: _saving
                        ? null
                        : () => context.go('/clinic/branches'),
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
