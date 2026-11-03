import 'package:app_core/app_core.dart';
import 'package:common_models/common_models.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../control_plane/data/control_plane_repository.dart';
import '../control_plane/providers.dart';
import '../shared/async_body.dart';
import '../shared/reason_dialog.dart';
import '../shared/ui_helpers.dart';
import '../shared/ui_kit.dart';

class ApplicationsPage extends StatelessWidget {
  const ApplicationsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListScreen(
      title: 'Clinic applications',
      subtitle: 'Review clinics that want to join EazyClinic.',
      path: '/platform/clinic-applications',
      searchHint: 'Search clinic name or application ID',
      statusOptions: [
        for (final s in ApplicationStatus.values)
          if (s != ApplicationStatus.draft) s.wireName,
      ],
      emptyTitle: 'No applications found',
      emptyMessage:
          'Applications appear here when a clinic submits its registration.',
      rowBuilder: (context, a) {
        final clinic = (a['clinic'] as Map<String, Object?>?) ?? const {};
        final address = (a['address'] as Map<String, Object?>?) ?? const {};
        return RowCard(
          title: '${clinic['name']}',
          subtitle:
              '${address['city'] ?? ''} · ${(a['owner'] as Map<String, Object?>?)?['fullName'] ?? ''} · ${a['applicationId']}',
          trailing: Fmt.date(a['submittedAt']),
          status: a['status'],
          onTap: () =>
              context.go('/platform/applications/${a['applicationId']}'),
        );
      },
    );
  }
}

class ApplicationDetailPage extends ConsumerWidget {
  const ApplicationDetailPage({required this.applicationId, super.key});

  final String applicationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(applicationDetailProvider(applicationId));
    final canReview = ref
        .watch(platformPermissionsProvider)
        .contains(Permission.reviewApplications);
    void reload() => ref.invalidate(applicationDetailProvider(applicationId));
    return AsyncBody(
      value: value,
      onRetry: reload,
      builder: (app) {
        final clinic = (app['clinic']! as Map).cast<String, Object?>();
        final address = (app['address']! as Map).cast<String, Object?>();
        final owner = (app['owner']! as Map).cast<String, Object?>();
        final exp = (app['expectations']! as Map).cast<String, Object?>();
        final status = app['status'] as String;
        final history = (app['history']! as List).cast<Map<String, Object?>>();
        final notes = (app['internalNotes']! as List)
            .cast<Map<String, Object?>>();
        final repo = ref.read(controlPlaneRepositoryProvider);
        final reviewable = status == 'submitted' || status == 'under_review';
        return ListView(
          padding: const EdgeInsets.all(EcSpacing.lg),
          children: [
            PageHeader(
              title: '${clinic['name']}',
              subtitle:
                  'Application ${app['applicationId']} · submitted ${Fmt.date(app['submittedAt'])}',
              actions: [
                statusChip(status),
                if (canReview && status == 'submitted')
                  EcSecondaryButton(
                    label: 'Start review',
                    compact: true,
                    onPressed: () => runAction(
                      context,
                      action: () => repo.startReview(applicationId),
                      success: 'Review started.',
                      after: reload,
                    ),
                  ),
                if (canReview &&
                    (reviewable || status == 'additional_information_required'))
                  EcSecondaryButton(
                    label: 'Request information',
                    compact: true,
                    onPressed: reviewable
                        ? () async {
                            final msg = await showReasonDialog(
                              context,
                              title: 'Request additional information',
                              message:
                                  'The applicant will see this message and can respond.',
                              confirmLabel: 'Send request',
                              fieldLabel: 'Message',
                              minLength: 5,
                            );
                            if (msg != null && context.mounted) {
                              await runAction(
                                context,
                                action: () =>
                                    repo.requestInformation(applicationId, msg),
                                success: 'Information requested.',
                                after: reload,
                              );
                            }
                          }
                        : null,
                  ),
                if (canReview &&
                    (reviewable || status == 'additional_information_required'))
                  EcSecondaryButton(
                    label: 'Reject',
                    compact: true,
                    onPressed: () async {
                      final reason = await showReasonDialog(
                        context,
                        title: 'Reject application',
                        message:
                            'The applicant will see the reason. This cannot be undone.',
                        confirmLabel: 'Reject application',
                        destructive: true,
                      );
                      if (reason != null && context.mounted) {
                        await runAction(
                          context,
                          action: () => repo.reject(applicationId, reason),
                          success: 'Application rejected.',
                          after: reload,
                        );
                      }
                    },
                  ),
                if (canReview && reviewable)
                  EcPrimaryButton(
                    label: 'Approve…',
                    compact: true,
                    onPressed: () => _approve(context, ref, app, reload),
                  ),
              ],
            ),
            if (app['infoRequest'] != null)
              Padding(
                padding: const EdgeInsets.only(bottom: EcSpacing.lg),
                child: EcInlineMessage(
                  tone: EcStatusTone.warning,
                  message:
                      'Information requested: ${(app['infoRequest']! as Map<String, Object?>)['message']}',
                ),
              ),
            if (app['decisionReason'] != null)
              Padding(
                padding: const EdgeInsets.only(bottom: EcSpacing.lg),
                child: EcInlineMessage(
                  tone: EcStatusTone.info,
                  message: 'Decision note: ${app['decisionReason']}',
                ),
              ),
            if (app['tenantId'] != null)
              Section(
                title: 'Tenant',
                child: TextButton(
                  onPressed: () =>
                      context.go('/platform/tenants/${app['tenantId']}'),
                  child: Text('Open tenant ${app['tenantId']}'),
                ),
              ),
            Section(
              title: 'Clinic',
              child: KeyValues([
                ('Type', Fmt.humanize(clinic['type'])),
                ('Registration number', clinic['registrationNumber']),
                ('Email', clinic['email']),
                ('Phone', clinic['phone']),
                ('Website', clinic['website']),
                ('Description', clinic['description']),
              ]),
            ),
            Section(
              title: 'Address',
              child: KeyValues([
                ('Line 1', address['line1']),
                ('Line 2', address['line2']),
                ('City', address['city']),
                ('State', address['state']),
                ('Country', address['country']),
                ('PIN / postal code', address['postalCode']),
              ]),
            ),
            Section(
              title: 'Applicant / owner',
              child: KeyValues([
                ('Full name', owner['fullName']),
                ('Email', owner['email']),
                ('Phone', owner['phone']),
                ('Designation', owner['designation']),
                ('Signed-in applicant', app['applicantEmail']),
              ]),
            ),
            Section(
              title: 'Expected usage',
              child: KeyValues([
                ('Doctors', exp['doctors']),
                ('Staff', exp['staff']),
                ('Patients per month', exp['monthlyPatients']),
                ('Preferred plan', app['preferredPlanId']),
              ]),
            ),
            Section(
              title: 'Status history',
              child: Column(
                children: [
                  for (final h in history)
                    ListTile(
                      dense: true,
                      title: Text(Fmt.humanize(h['toStatus'])),
                      subtitle: Text(
                        '${Fmt.dateTime(h['at'])} · ${h['actorRole']}${h['reason'] != null ? ' · ${h['reason']}' : ''}',
                      ),
                    ),
                ],
              ),
            ),
            Section(
              title: 'Internal notes (not visible to the applicant)',
              trailing: canReview
                  ? TextButton(
                      onPressed: () async {
                        final note = await showReasonDialog(
                          context,
                          title: 'Add internal note',
                          message: 'Only platform staff can see this.',
                          confirmLabel: 'Add note',
                          fieldLabel: 'Note',
                          minLength: 2,
                        );
                        if (note != null && context.mounted) {
                          await runAction(
                            context,
                            action: () => repo.addNote(applicationId, note),
                            success: 'Note added.',
                            after: reload,
                          );
                        }
                      },
                      child: const Text('Add note'),
                    )
                  : null,
              child: notes.isEmpty
                  ? const Text('No notes.')
                  : Column(
                      children: [
                        for (final n in notes)
                          ListTile(
                            dense: true,
                            title: Text('${n['note']}'),
                            subtitle: Text(Fmt.dateTime(n['at'])),
                          ),
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _approve(
    BuildContext context,
    WidgetRef ref,
    Json app,
    VoidCallback reload,
  ) async {
    final result = await showDialog<_ApprovalChoice>(
      context: context,
      builder: (_) => _ApproveDialog(app: app),
    );
    if (result == null || !context.mounted) return;
    final repo = ref.read(controlPlaneRepositoryProvider);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final r = await repo.approve(
        applicationId,
        planId: result.planId,
        trial: result.trial,
        note: result.note,
      );
      reload();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            r['provisioningComplete'] == true
                ? 'Application approved. The clinic is active.'
                : 'Approved, but provisioning did not finish. Open the tenant and retry provisioning.',
          ),
        ),
      );
    } on ApiFailure catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(failureText(e)),
          backgroundColor: EcColors.error,
        ),
      );
    }
  }
}

class _ApprovalChoice {
  const _ApprovalChoice(this.planId, this.trial, this.note);
  final String? planId;
  final bool trial;
  final String? note;
}

/// Confirmation step required before approval (tenant creation).
class _ApproveDialog extends ConsumerStatefulWidget {
  const _ApproveDialog({required this.app});
  final Json app;

  @override
  ConsumerState<_ApproveDialog> createState() => _ApproveDialogState();
}

class _ApproveDialogState extends ConsumerState<_ApproveDialog> {
  String? _planId;
  bool _trial = false;
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final clinic = (widget.app['clinic']! as Map).cast<String, Object?>();
    final owner = (widget.app['owner']! as Map).cast<String, Object?>();
    final plans = ref.watch(activePlansProvider);
    return AlertDialog(
      title: const Text('Approve this clinic?'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              KeyValues([
                ('Clinic', clinic['name']),
                ('Owner', owner['fullName']),
                ('Owner email', owner['email']),
                ('Owner phone', owner['phone']),
                ('Requested plan', widget.app['preferredPlanId'] ?? 'None'),
              ]),
              const SizedBox(height: EcSpacing.md),
              const EcInlineMessage(
                tone: EcStatusTone.info,
                message:
                    'Approving creates a new clinic (tenant) and makes the applicant its owner. '
                    'The clinic becomes active once setup completes. This is recorded in the audit log.',
              ),
              const SizedBox(height: EcSpacing.lg),
              plans.when(
                loading: () => const LinearProgressIndicator(),
                error: (_, _) => const Text(
                  'Could not load plans. You can approve without a subscription.',
                ),
                data: (list) => EcDropdown<String?>(
                  label: 'Initial subscription plan (optional)',
                  items: [null, for (final p in list) p['planId'] as String],
                  value: _planId,
                  itemLabel: (id) => id == null
                      ? 'No subscription yet'
                      : '${list.firstWhere((p) => p['planId'] == id)['name']}',
                  onChanged: (v) => setState(() {
                    _planId = v;
                    if (v == null) _trial = false;
                  }),
                ),
              ),
              if (_planId != null)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _trial,
                  onChanged: (v) => setState(() => _trial = v ?? false),
                  title: const Text('Start with a trial'),
                ),
              const SizedBox(height: EcSpacing.md),
              EcTextField(
                label: 'Note (optional)',
                controller: _note,
                maxLength: 500,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(
            context,
          ).pop(_ApprovalChoice(_planId, _trial, _note.text.trim())),
          child: const Text('Approve and create clinic'),
        ),
      ],
    );
  }
}
