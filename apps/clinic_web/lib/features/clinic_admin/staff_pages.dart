import 'package:app_core/app_core.dart';
import 'package:common_models/common_models.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:validation/validation.dart';

import '../control_plane/data/control_plane_repository.dart';
import '../shared/async_body.dart';
import '../shared/paged_list.dart';
import '../shared/ui_helpers.dart';
import '../shared/ui_kit.dart';
import 'form_kit.dart';
import 'invite_dialog.dart';
import 'providers.dart';

class StaffPage extends ConsumerWidget {
  const StaffPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final branch = ref.watch(activeBranchProvider);
    return ListScreen(
      title: 'Staff',
      subtitle: branch == null
          ? 'People who work at your clinic.'
          : 'Staff of the selected branch.',
      path: '/staff',
      searchHint: 'Search by name',
      statusOptions: const ['inactive', 'invited', 'active', 'suspended'],
      extraDropdown: (
        'Role',
        'role',
        [for (final r in assignableRoles) r.wireName],
      ),
      extraParams: {'branchId': ?branch},
      emptyTitle: 'No staff yet',
      emptyMessage: 'Add a staff member and invite them to sign in.',
      actions: [
        if (can(ref, ClinicPermission.staffCreate))
          EcPrimaryButton(
            label: 'Add staff',
            icon: Icons.add,
            compact: true,
            onPressed: () => context.go('/clinic/staff/new'),
          ),
      ],
      rowBuilder: (context, s) => RowCard(
        title: '${s['fullName']}',
        subtitle: '${Fmt.humanize(s['role'])} · ${s['email']}',
        status: s['status'],
        onTap: () => context.go('/clinic/staff/${s['staffId']}'),
      ),
    );
  }
}

class StaffDetailPage extends ConsumerWidget {
  const StaffDetailPage({required this.staffId, super.key});

  final String staffId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(staffDetailProvider(staffId));
    void reload() => ref.invalidate(staffDetailProvider(staffId));
    return AsyncBody(
      value: value,
      onRetry: reload,
      builder: (s) {
        final repo = ref.read(controlPlaneRepositoryProvider);
        final status = '${s['status']}';
        final branches = ((s['branchIds'] as List?) ?? const []).cast<String>();
        final names = {
          for (final b
              in ref.watch(branchChoicesProvider).asData?.value ??
                  const <Json>[])
            '${b['branchId']}': '${b['name']}',
        };
        Future<void> act(String path, String done, {String? confirm}) async {
          if (confirm != null) {
            final ok = await showEcConfirmDialog(
              context,
              title: confirm,
              message:
                  'The person keeps their EazyClinic account; only their access to this clinic changes.',
              confirmLabel: 'Continue',
            );
            if (!ok || !context.mounted) return;
          }
          await runAction(
            context,
            action: () => repo.sendMap('POST', '/staff/$staffId/$path'),
            success: done,
            after: reload,
          );
        }

        return ListView(
          padding: const EdgeInsets.all(EcSpacing.lg),
          children: [
            PageHeader(
              title: '${s['fullName']}',
              subtitle: '${Fmt.humanize(s['role'])} · ${s['staffId']}',
              actions: [
                statusChip(status),
                if (can(ref, ClinicPermission.staffUpdate))
                  EcSecondaryButton(
                    label: 'Edit',
                    compact: true,
                    onPressed: () => context.go('/clinic/staff/$staffId/edit'),
                  ),
                if (status == 'inactive' &&
                    s['uid'] == null &&
                    can(ref, ClinicPermission.staffInvite))
                  EcPrimaryButton(
                    label: 'Send invitation',
                    compact: true,
                    onPressed: () async {
                      try {
                        final inv = await repo.sendMap(
                          'POST',
                          '/staff/$staffId/invite',
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
                if ((status == 'inactive' || status == 'suspended') &&
                    s['uid'] != null &&
                    can(ref, ClinicPermission.staffActivate))
                  EcPrimaryButton(
                    label: 'Activate',
                    compact: true,
                    onPressed: () => act('activate', 'Staff member activated.'),
                  ),
                if (status == 'active' &&
                    can(ref, ClinicPermission.staffDeactivate))
                  EcSecondaryButton(
                    label: 'Suspend',
                    compact: true,
                    onPressed: () => act(
                      'suspend',
                      'Staff member suspended.',
                      confirm: 'Suspend access?',
                    ),
                  ),
                if ((status == 'active' || status == 'suspended') &&
                    can(ref, ClinicPermission.staffDeactivate))
                  EcSecondaryButton(
                    label: 'Deactivate',
                    compact: true,
                    onPressed: () => act(
                      'deactivate',
                      'Staff member deactivated.',
                      confirm: 'Deactivate this person?',
                    ),
                  ),
              ],
            ),
            if (status == 'invited' || status == 'invitation_expired')
              Padding(
                padding: const EdgeInsets.only(bottom: EcSpacing.lg),
                child: EcInlineMessage(
                  tone: status == 'invited'
                      ? EcStatusTone.info
                      : EcStatusTone.warning,
                  message: status == 'invited'
                      ? 'Invitation pending until ${Fmt.date(s['invitationExpiresAt'])}. Resend or revoke it from the Invitations page.'
                      : 'The invitation has expired. Resend it from the Invitations page.',
                ),
              ),
            Section(
              title: 'Profile',
              child: KeyValues([
                ('Email', s['email']),
                ('Phone', s['phone']),
                ('Designation', s['designation']),
                ('Department', s['department']),
                ('Joined', s['joiningDate']),
                ('Account', s['uid'] == null ? 'Not activated yet' : 'Linked'),
              ]),
            ),
            Section(
              title: 'Access',
              child: KeyValues([
                ('Role', Fmt.humanize(s['role'])),
                (
                  'Branches',
                  s['allBranches'] == true
                      ? 'All branches'
                      : branches.map((b) => names[b] ?? b).join(', '),
                ),
              ]),
            ),
          ],
        );
      },
    );
  }
}

class StaffFormPage extends ConsumerStatefulWidget {
  const StaffFormPage({this.staffId, super.key});

  final String? staffId;

  @override
  ConsumerState<StaffFormPage> createState() => _StaffFormState();
}

class _StaffFormState extends ConsumerState<StaffFormPage> {
  final _form = GlobalKey<FormState>();
  final _f = FormFields([
    'fullName',
    'email',
    'phone',
    'designation',
    'department',
    'joining',
  ]);
  String _role = ClinicRole.receptionist.wireName;
  bool _allBranches = false;
  bool _inviteNow = true;
  final Set<String> _branches = {};
  bool _preInvite = true;
  bool _loaded = false;
  bool _saving = false;
  String? _error;

  bool get _editing => widget.staffId != null;

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

  void _fill(Json s) {
    _f
      ..set('fullName', s['fullName'])
      ..set('email', s['email'])
      ..set('phone', s['phone'])
      ..set('designation', s['designation'])
      ..set('department', s['department'])
      ..set('joining', s['joiningDate']);
    _role = '${s['role']}';
    _allBranches = s['allBranches'] == true;
    _branches
      ..clear()
      ..addAll(((s['branchIds'] as List?) ?? const []).cast<String>());
    _preInvite = s['status'] == 'inactive' && s['uid'] == null;
    _loaded = true;
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    if (_preInvite && !_allBranches && _branches.isEmpty) {
      setState(() => _error = 'Choose at least one branch, or all branches.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final body = <String, Object?>{
      'fullName': _f.text('fullName'),
      'email': _f.text('email'),
      'phone': ?_f.opt('phone'),
      'designation': ?_f.opt('designation'),
      'department': ?_f.opt('department'),
      'joiningDate': ?_f.opt('joining'),
      if (_preInvite) ...{
        'role': _role,
        if (_allBranches)
          'allBranches': true
        else
          'branchIds': _branches.toList(),
      },
      if (!_editing && _inviteNow) 'invite': true,
    };
    if (_editing && body['email'] == null) body.remove('email');
    final repo = ref.read(controlPlaneRepositoryProvider);
    try {
      final saved = _editing
          ? await repo.sendMap('PATCH', '/staff/${widget.staffId}', body)
          : await repo.sendMap('POST', '/staff', body);
      ref.invalidate(staffDetailProvider('${saved['staffId']}'));
      if (!mounted) return;
      context.go('/clinic/staff/${saved['staffId']}');
      final inv = saved['invitation'];
      if (inv is Map<String, Object?>) await showInviteLinkDialog(context, inv);
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
        value: ref.watch(staffDetailProvider(widget.staffId!)),
        onRetry: () => ref.invalidate(staffDetailProvider(widget.staffId!)),
        builder: (s) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && !_loaded) setState(() => _fill(s));
          });
          return const EcLoadingIndicator();
        },
      );
    }
    final access = ref.watch(clinicAccessProvider).asData?.value;
    final actorAll = access?['allBranches'] == true;
    final actorRole = ClinicRole.tryParse('${access?['role']}');
    final branchList =
        ref
            .watch(branchChoicesProvider)
            .asData
            ?.value
            .where((b) => b['status'] == 'active')
            .toList() ??
        const [];
    final roleChoices = [
      for (final r in assignableRoles)
        if (actorRole != null && ClinicRolePolicy.canGrant(actorRole, r))
          r.wireName,
    ];
    return ListView(
      padding: const EdgeInsets.all(EcSpacing.lg),
      children: [
        PageHeader(
          title: _editing ? 'Edit staff member' : 'Add staff member',
          subtitle:
              'They get access only after accepting an invitation with this email address.',
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
                      validator: (v) => (v ?? '').trim().isEmpty
                          ? null
                          : Validators.indianMobile(v)?.message,
                    ),
                    TextRow(
                      label: 'Designation',
                      controller: _f['designation'],
                      maxLength: 80,
                    ),
                    TextRow(
                      label: 'Department',
                      controller: _f['department'],
                      maxLength: 80,
                    ),
                    TextRow(
                      label: 'Joining date (YYYY-MM-DD)',
                      controller: _f['joining'],
                      maxLength: 10,
                    ),
                  ],
                ),
              ),
              if (_preInvite)
                Section(
                  title: 'Role and branches',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 300,
                        child: EcDropdown<String>(
                          label: 'Role',
                          items: roleChoices.contains(_role)
                              ? roleChoices
                              : [...roleChoices, _role],
                          value: _role,
                          itemLabel: Fmt.humanize,
                          onChanged: (v) => setState(() => _role = v ?? _role),
                        ),
                      ),
                      const SizedBox(height: EcSpacing.md),
                      if (actorAll)
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Access to all branches'),
                          value: _allBranches,
                          onChanged: (v) => setState(() => _allBranches = v),
                        ),
                      if (!_allBranches)
                        Wrap(
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
                    ],
                  ),
                )
              else
                const Padding(
                  padding: EdgeInsets.only(bottom: EcSpacing.lg),
                  child: EcInlineMessage(
                    tone: EcStatusTone.info,
                    message:
                        'Role and branches of an invited or active person are changed under Roles & access.',
                  ),
                ),
              if (!_editing)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _inviteNow,
                  onChanged: (v) => setState(() => _inviteNow = v ?? false),
                  title: const Text('Create the invitation now'),
                  subtitle: const Text('Uses one staff seat of your plan.'),
                ),
              const SizedBox(height: EcSpacing.md),
              Row(
                children: [
                  SizedBox(
                    width: 200,
                    child: EcPrimaryButton(
                      label: _editing ? 'Save changes' : 'Add staff',
                      isLoading: _saving,
                      onPressed: _save,
                    ),
                  ),
                  const SizedBox(width: EcSpacing.md),
                  TextButton(
                    onPressed: _saving
                        ? null
                        : () => context.go('/clinic/staff'),
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

class InvitationsPage extends ConsumerWidget {
  const InvitationsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(controlPlaneRepositoryProvider);
    return ListScreen(
      title: 'Invitations',
      subtitle:
          'Single-use links that let people join your clinic. Delivery by email/SMS is not set up: share links yourself.',
      path: '/invitations',
      statusOptions: const ['pending', 'accepted', 'revoked'],
      extraDropdown: const ('Type', 'kind', ['staff', 'doctor']),
      emptyTitle: 'No invitations',
      emptyMessage: 'Invitations appear here when you invite staff or doctors.',
      rowBuilder: (context, i) {
        final effective = '${i['effectiveStatus']}';
        return EcCard(
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            runSpacing: EcSpacing.sm,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${i['email']}', style: EcTypography.bodyStrong),
                  Text(
                    '${Fmt.humanize(i['kind'])} · ${Fmt.humanize(i['role'])} · expires ${Fmt.date(i['expiresAt'])}',
                    style: EcTypography.bodySecondary,
                  ),
                ],
              ),
              Wrap(
                spacing: EcSpacing.sm,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  statusChip(effective),
                  if (i['status'] == 'pending') ...[
                    EcSecondaryButton(
                      label: 'Resend',
                      compact: true,
                      onPressed: () async {
                        try {
                          final inv = await repo.sendMap(
                            'POST',
                            '/invitations/${i['invitationId']}/resend',
                          );
                          ref.invalidate(pagedListProvider);
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
                    EcSecondaryButton(
                      label: 'Revoke',
                      compact: true,
                      onPressed: () async {
                        final ok = await showEcConfirmDialog(
                          context,
                          title: 'Revoke invitation?',
                          message: 'The link stops working immediately.',
                          confirmLabel: 'Revoke',
                        );
                        if (ok && context.mounted) {
                          await runAction(
                            context,
                            action: () => repo.sendMap(
                              'POST',
                              '/invitations/${i['invitationId']}/revoke',
                            ),
                            success: 'Invitation revoked.',
                            after: () => ref.invalidate(pagedListProvider),
                          );
                        }
                      },
                    ),
                  ],
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
