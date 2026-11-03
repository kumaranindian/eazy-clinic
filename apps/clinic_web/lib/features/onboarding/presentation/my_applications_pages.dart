import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../control_plane/data/control_plane_repository.dart';
import '../../control_plane/providers.dart';
import '../../shared/async_body.dart';
import '../../shared/reason_dialog.dart';
import '../../shared/ui_helpers.dart';
import '../../shared/ui_kit.dart';

class MyApplicationsPage extends StatelessWidget {
  const MyApplicationsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListScreen(
      title: 'My clinic applications',
      path: '/clinic-applications/my',
      emptyTitle: 'No applications yet',
      emptyMessage: 'Register your clinic to get started.',
      actions: [
        EcPrimaryButton(
          label: 'Register a clinic',
          icon: Icons.add,
          compact: true,
          onPressed: () => context.go('/apply'),
        ),
      ],
      rowBuilder: (context, a) => RowCard(
        title: '${(a['clinic'] as Map<String, Object?>?)?['name']}',
        subtitle:
            'Submitted ${Fmt.date(a['submittedAt'])} · ${a['applicationId']}',
        status: a['status'],
        onTap: () => context.go('/applications/${a['applicationId']}'),
      ),
    );
  }
}

class MyApplicationDetailPage extends ConsumerWidget {
  const MyApplicationDetailPage({required this.applicationId, super.key});

  final String applicationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(myApplicationProvider(applicationId));
    void reload() => ref.invalidate(myApplicationProvider(applicationId));
    return AsyncBody(
      value: value,
      onRetry: reload,
      builder: (a) {
        final clinic = (a['clinic']! as Map<String, Object?>);
        final status = a['status'] as String;
        final history = (a['history']! as List).cast<Map<String, Object?>>();
        final repo = ref.read(controlPlaneRepositoryProvider);
        final info = a['infoRequest'] as Map<String, Object?>?;
        final open = const [
          'submitted',
          'under_review',
          'additional_information_required',
        ].contains(status);
        return ListView(
          padding: const EdgeInsets.all(EcSpacing.lg),
          children: [
            PageHeader(
              title: '${clinic['name']}',
              subtitle: 'Application ${a['applicationId']}',
              actions: [
                statusChip(status),
                if (open)
                  EcSecondaryButton(
                    label: 'Withdraw',
                    compact: true,
                    onPressed: () async {
                      final ok = await showEcConfirmDialog(
                        context,
                        title: 'Withdraw application?',
                        message: 'You can submit a new application afterwards.',
                        confirmLabel: 'Withdraw',
                      );
                      if (ok && context.mounted) {
                        await runAction(
                          context,
                          action: () => repo.withdraw(applicationId),
                          success: 'Application withdrawn.',
                          after: reload,
                        );
                      }
                    },
                  ),
              ],
            ),
            switch (status) {
              'approved' => const EcInlineMessage(
                tone: EcStatusTone.success,
                message:
                    'Your clinic has been approved. Sign out and back in if you do not see it yet.',
              ),
              'rejected' => EcInlineMessage(
                message:
                    'Not approved: ${a['decisionReason'] ?? 'no reason given'}',
              ),
              'additional_information_required' => EcInlineMessage(
                tone: EcStatusTone.warning,
                message: 'We need more information: ${info?['message']}',
              ),
              _ => const EcInlineMessage(
                tone: EcStatusTone.info,
                message:
                    'Your application is with the EazyClinic team. You will see the decision here.',
              ),
            },
            const SizedBox(height: EcSpacing.lg),
            if (status == 'additional_information_required')
              Padding(
                padding: const EdgeInsets.only(bottom: EcSpacing.lg),
                child: EcPrimaryButton(
                  label: 'Respond',
                  onPressed: () async {
                    final msg = await showReasonDialog(
                      context,
                      title: 'Respond to the request',
                      message:
                          'Your answer goes back to the reviewer and your application is re-submitted.',
                      confirmLabel: 'Send response',
                      fieldLabel: 'Your response',
                      minLength: 3,
                    );
                    if (msg != null && context.mounted) {
                      await runAction(
                        context,
                        action: () =>
                            repo.respond(applicationId, {'message': msg}),
                        success: 'Response sent.',
                        after: reload,
                      );
                    }
                  },
                ),
              ),
            Section(
              title: 'Clinic',
              child: KeyValues([
                ('Type', Fmt.humanize(clinic['type'])),
                ('Email', clinic['email']),
                ('Phone', clinic['phone']),
                ('City', (a['address']! as Map<String, Object?>)['city']),
                ('Submitted', Fmt.dateTime(a['submittedAt'])),
              ]),
            ),
            Section(
              title: 'Progress',
              child: Column(
                children: [
                  for (final h in history)
                    ListTile(
                      dense: true,
                      title: Text(Fmt.humanize(h['status'])),
                      subtitle: Text(
                        '${Fmt.dateTime(h['at'])} · ${h['by']}${h['reason'] != null ? ' · ${h['reason']}' : ''}',
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
}
