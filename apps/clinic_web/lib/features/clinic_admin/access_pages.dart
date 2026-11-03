import 'package:common_models/common_models.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../control_plane/data/control_plane_repository.dart';
import '../shared/async_body.dart';
import '../shared/paged_list.dart';
import '../shared/ui_helpers.dart';
import '../shared/ui_kit.dart';
import 'providers.dart';

/// Roles & access: the role catalogue with its permission matrix, and the
/// members of the clinic with role and branch assignment.
class AccessPage extends ConsumerWidget {
  const AccessPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          const Material(
            color: EcColors.surface,
            child: TabBar(
              tabs: [
                Tab(text: 'Members'),
                Tab(text: 'Roles'),
                Tab(text: 'Permission matrix'),
              ],
            ),
          ),
          const Expanded(
            child: TabBarView(
              children: [MembersTab(), RolesTab(), MatrixTab()],
            ),
          ),
        ],
      ),
    );
  }
}

class RolesTab extends ConsumerWidget {
  const RolesTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AsyncBody(
      value: ref.watch(rolesProvider),
      onRetry: () => ref.invalidate(rolesProvider),
      builder: (roles) => ListView(
        padding: const EdgeInsets.all(EcSpacing.lg),
        children: [
          const PageHeader(
            title: 'Roles',
            subtitle:
                'Predefined roles. Custom roles are not available yet. Platform permissions can never be part of a clinic role.',
          ),
          for (final r in roles)
            Section(
              title: Fmt.humanize(r['role']),
              trailing: r['assignableByYou'] == true
                  ? const EcStatusChip(
                      label: 'You can assign',
                      tone: EcStatusTone.success,
                    )
                  : null,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${r['description']}',
                    style: EcTypography.bodySecondary,
                  ),
                  const SizedBox(height: EcSpacing.md),
                  Wrap(
                    spacing: EcSpacing.xs,
                    runSpacing: EcSpacing.xs,
                    children: [
                      for (final p
                          in (r['permissions']! as List).cast<String>())
                        EcStatusChip(label: p, tone: EcStatusTone.info),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class MatrixTab extends ConsumerWidget {
  const MatrixTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AsyncBody(
      value: ref.watch(permissionCatalogProvider),
      onRetry: () => ref.invalidate(permissionCatalogProvider),
      builder: (c) {
        final matrix = (c['matrix']! as Map<String, Object?>);
        final roles = matrix.keys.toList();
        return ListView(
          padding: const EdgeInsets.all(EcSpacing.lg),
          children: [
            const PageHeader(
              title: 'Permission matrix',
              subtitle:
                  'What each role may do. Enforced by the server on every request.',
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: [
                  const DataColumn(label: Text('Permission')),
                  for (final r in roles)
                    DataColumn(label: Text(Fmt.humanize(r))),
                ],
                rows: [
                  for (final p in ClinicPermission.all)
                    DataRow(
                      cells: [
                        DataCell(Text(p)),
                        for (final r in roles)
                          DataCell(
                            Icon(
                              ((matrix[r]! as List).contains(p))
                                  ? Icons.check_circle
                                  : Icons.remove,
                              size: 18,
                              color: ((matrix[r]! as List).contains(p))
                                  ? EcColors.success
                                  : EcColors.textSecondary,
                              semanticLabel: ((matrix[r]! as List).contains(p))
                                  ? 'Allowed'
                                  : 'Not allowed',
                            ),
                          ),
                      ],
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

class MembersTab extends ConsumerWidget {
  const MembersTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canRole = can(ref, ClinicPermission.staffAssignRole);
    final canBranch = can(ref, ClinicPermission.staffAssignBranch);
    final repo = ref.read(controlPlaneRepositoryProvider);
    return ListScreen(
      title: 'Members',
      subtitle:
          'People with access to this clinic. Their Firebase account is separate: removing access here never deletes it.',
      path: '/members',
      extraDropdown: (
        'Role',
        'role',
        [for (final r in ClinicRole.values) r.wireName],
      ),
      statusOptions: const ['active', 'suspended', 'deactivated'],
      emptyTitle: 'No members',
      emptyMessage: 'Members appear here once invitations are accepted.',
      rowBuilder: (context, m) {
        final isOwner = m['role'] == 'clinic_owner';
        final you = m['isYou'] == true;
        return EcCard(
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            runSpacing: EcSpacing.sm,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${m['displayName'] ?? m['email'] ?? m['uid']}${you ? ' (you)' : ''}',
                    style: EcTypography.bodyStrong,
                  ),
                  Text(
                    '${Fmt.humanize(m['role'])} · ${m['allBranches'] == true ? 'All branches' : '${(m['branchIds'] as List).length} branch(es)'}',
                    style: EcTypography.bodySecondary,
                  ),
                ],
              ),
              Wrap(
                spacing: EcSpacing.sm,
                children: [
                  statusChip(m['status']),
                  if (canRole && !isOwner && !you)
                    EcSecondaryButton(
                      label: 'Change role',
                      compact: true,
                      onPressed: () async {
                        final role = await showDialog<String>(
                          context: context,
                          builder: (_) => _RoleDialog(current: '${m['role']}'),
                        );
                        if (role != null && context.mounted) {
                          await runAction(
                            context,
                            action: () => repo.sendMap(
                              'PATCH',
                              '/members/${m['memberId']}/role',
                              {'role': role},
                            ),
                            success: 'Role updated.',
                            after: () => ref.invalidate(pagedListProvider),
                          );
                        }
                      },
                    ),
                  if (canBranch && !isOwner && !you && m['doctorId'] == null)
                    EcSecondaryButton(
                      label: 'Branch access',
                      compact: true,
                      onPressed: () async {
                        final result = await showDialog<Json>(
                          context: context,
                          builder: (_) => _BranchesDialog(
                            current: ((m['branchIds'] as List?) ?? const [])
                                .cast<String>(),
                            all: m['allBranches'] == true,
                          ),
                        );
                        if (result != null && context.mounted) {
                          await runAction(
                            context,
                            action: () => repo.sendMap(
                              'PATCH',
                              '/members/${m['memberId']}/branches',
                              result,
                            ),
                            success: 'Branch access updated.',
                            after: () => ref.invalidate(pagedListProvider),
                          );
                        }
                      },
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _RoleDialog extends ConsumerStatefulWidget {
  const _RoleDialog({required this.current});
  final String current;

  @override
  ConsumerState<_RoleDialog> createState() => _RoleDialogState();
}

class _RoleDialogState extends ConsumerState<_RoleDialog> {
  String? _role;

  @override
  Widget build(BuildContext context) {
    final actor = ClinicRole.tryParse(
      '${ref.watch(clinicAccessProvider).asData?.value['role']}',
    );
    final choices = [
      for (final r in assignableRoles)
        if (actor != null && ClinicRolePolicy.canGrant(actor, r)) r.wireName,
    ];
    return AlertDialog(
      title: const Text('Change role'),
      content: SizedBox(
        width: 360,
        child: EcDropdown<String>(
          label: 'New role',
          items: choices,
          value: _role,
          itemLabel: Fmt.humanize,
          onChanged: (v) => setState(() => _role = v),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _role == null || _role == widget.current
              ? null
              : () => Navigator.of(context).pop(_role),
          child: const Text('Change role'),
        ),
      ],
    );
  }
}

class _BranchesDialog extends ConsumerStatefulWidget {
  const _BranchesDialog({required this.current, required this.all});
  final List<String> current;
  final bool all;

  @override
  ConsumerState<_BranchesDialog> createState() => _BranchesDialogState();
}

class _BranchesDialogState extends ConsumerState<_BranchesDialog> {
  late bool _all = widget.all;
  late final Set<String> _ids = {...widget.current};

  @override
  Widget build(BuildContext context) {
    final access = ref.watch(clinicAccessProvider).asData?.value;
    final actorAll = access?['allBranches'] == true;
    final branches =
        ref
            .watch(branchChoicesProvider)
            .asData
            ?.value
            .where((b) => b['status'] == 'active')
            .toList() ??
        const [];
    return AlertDialog(
      title: const Text('Branch access'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (actorAll)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('All branches'),
                value: _all,
                onChanged: (v) => setState(() => _all = v),
              ),
            if (!_all)
              Wrap(
                spacing: EcSpacing.sm,
                children: [
                  for (final b in branches)
                    FilterChip(
                      label: Text('${b['name']}'),
                      selected: _ids.contains(b['branchId']),
                      onSelected: (v) => setState(
                        () => v
                            ? _ids.add('${b['branchId']}')
                            : _ids.remove('${b['branchId']}'),
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: !_all && _ids.isEmpty
              ? null
              : () => Navigator.of(context).pop(
                  _all
                      ? <String, Object?>{'allBranches': true}
                      : <String, Object?>{'branchIds': _ids.toList()},
                ),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
