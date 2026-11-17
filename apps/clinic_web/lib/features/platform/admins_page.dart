import 'package:common_models/common_models.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../control_plane/data/control_plane_repository.dart';
import '../control_plane/providers.dart';
import '../finance/finance_kit.dart';
import '../patients/dialogs.dart';
import '../scheduling/scheduling_providers.dart';
import '../shared/async_body.dart';
import '../shared/ui_helpers.dart';
import '../shared/ui_kit.dart';

/// Platform administrators. Only a super admin can change roles; the backend
/// refuses changing your own role or removing the last super admin.
class PlatformAdminsPage extends ConsumerWidget {
  const PlatformAdminsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final q = Query('/platform/admins');
    final manage = ref
        .watch(platformPermissionsProvider)
        .contains(Permission.manageAdmins);
    final repo = ref.read(controlPlaneRepositoryProvider);
    void refresh() => ref.invalidate(listProvider(q));
    return ListView(
      padding: const EdgeInsets.all(EcSpacing.lg),
      children: [
        PageHeader(
          title: 'Platform administrators',
          subtitle:
              'People who can run the EazyClinic platform. Support admins can read; super admins can change things.',
          actions: [
            if (manage)
              sized(
                EcPrimaryButton(
                  key: const Key('add-admin'),
                  label: 'Add administrator',
                  onPressed: () async {
                    final v = await showRecordDialog(
                      context,
                      title: 'Add a platform administrator',
                      confirmLabel: 'Grant role',
                      note:
                          'The person must already have signed up and verified their e-mail address.',
                      fields: const [
                        FieldSpec(
                          'email',
                          'E-mail address',
                          required: true,
                          maxLength: 254,
                        ),
                        FieldSpec(
                          'role',
                          'Role',
                          kind: FieldKind.choice,
                          required: true,
                          options: ['platform_support_admin', 'super_admin'],
                        ),
                        FieldSpec(
                          'reason',
                          'Reason',
                          kind: FieldKind.multiline,
                          required: true,
                          maxLength: 500,
                        ),
                      ],
                    );
                    if (v == null || !context.mounted) return;
                    await runAction(
                      context,
                      action: () async =>
                          repo.sendMap('POST', '/platform/admins', v),
                      success: 'Role granted',
                      after: refresh,
                    );
                  },
                ),
              ),
          ],
        ),
        AsyncBody(
          value: ref.watch(listProvider(q)),
          onRetry: refresh,
          builder: (admins) => Column(
            children: [
              for (final a in admins)
                EcCard(
                  key: Key('admin-${a['uid']}'),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${a['displayName']}',
                              style: EcTypography.bodyStrong,
                            ),
                            Text(
                              '${a['email']} · ${Fmt.humanize(a['platformRole'])}',
                              style: EcTypography.bodySecondary,
                            ),
                          ],
                        ),
                      ),
                      statusChip(a['accountStatus']),
                      if (manage)
                        TextButton(
                          key: Key('revoke-${a['uid']}'),
                          onPressed: () async {
                            final v = await showRecordDialog(
                              context,
                              title:
                                  'Remove ${a['displayName']} as administrator',
                              confirmLabel: 'Remove role',
                              note:
                                  'They keep their account but lose all platform access at once.',
                              fields: const [
                                FieldSpec(
                                  'reason',
                                  'Reason',
                                  kind: FieldKind.multiline,
                                  required: true,
                                  maxLength: 500,
                                ),
                              ],
                            );
                            if (v == null || !context.mounted) return;
                            await runAction(
                              context,
                              action: () async => repo.sendMap(
                                'POST',
                                '/platform/admins/${a['uid']}/revoke',
                                v,
                              ),
                              success: 'Role removed',
                              after: refresh,
                            );
                          },
                          child: const Text('Remove'),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
