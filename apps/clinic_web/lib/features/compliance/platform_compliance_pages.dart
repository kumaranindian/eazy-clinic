import 'package:common_models/common_models.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../control_plane/data/control_plane_repository.dart';
import '../control_plane/providers.dart' show platformPermissionsProvider;
import '../laboratory/lab_pages.dart' show reportSaverProvider;
import '../shared/async_body.dart';
import '../shared/reason_dialog.dart';
import '../shared/ui_helpers.dart';
import '../shared/ui_kit.dart';
import 'compliance_labels.dart';
import 'compliance_providers.dart';

/// Platform view of the compliance registers and the evidence review queue.
class PlatformCompliancePage extends ConsumerWidget {
  const PlatformCompliancePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final perms = ref.watch(platformPermissionsProvider);
    final canManage = perms.contains(Permission.manageCompliance);
    final canReview = perms.contains(Permission.reviewCompliance);
    void reload() {
      ref.invalidate(complianceOverviewProvider);
      ref.invalidate(complianceProfilesProvider);
      ref.invalidate(complianceReviewQueueProvider);
    }

    return AsyncBody<Json>(
      value: ref.watch(complianceOverviewProvider),
      onRetry: reload,
      builder: (o) => ListView(
        padding: const EdgeInsets.all(EcSpacing.lg),
        children: [
          PageHeader(
            title: 'Compliance registers',
            subtitle:
                'Country, jurisdiction and authority registers, and the evidence clinics submit against them.',
            actions: [
              if (canManage)
                EcSecondaryButton(
                  label: 'Seed baseline registers',
                  compact: true,
                  onPressed: () => runAction(
                    context,
                    action: ref
                        .read(controlPlaneRepositoryProvider)
                        .seedComplianceProfiles,
                    success:
                        'Baseline registers checked. Existing registers were not changed.',
                    after: reload,
                  ),
                ),
            ],
          ),
          EcInlineMessage(
            message: '${o['disclaimer']}',
            tone: EcStatusTone.info,
          ),
          const SizedBox(height: EcSpacing.md),
          Wrap(
            spacing: EcSpacing.sm,
            runSpacing: EcSpacing.sm,
            children: [
              EcStatusChip(label: 'Registers: ${o['profiles']}'),
              EcStatusChip(
                label:
                    'Awaiting legal validation: ${o['profilesAwaitingLegalValidation']}',
                tone: EcStatusTone.warning,
              ),
              EcStatusChip(
                label:
                    'Evidence awaiting review: ${o['evidenceAwaitingReview']}',
                tone: EcStatusTone.info,
              ),
              EcStatusChip(
                label:
                    'Confirmed applicabilities: ${o['confirmedApplicabilities']}',
              ),
            ],
          ),
          const SizedBox(height: EcSpacing.lg),
          if (canReview) const _ReviewQueue(),
          const _Profiles(),
        ],
      ),
    );
  }
}

class _ReviewQueue extends ConsumerWidget {
  const _ReviewQueue();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Section(
      title: 'Evidence waiting for review',
      child: ref
          .watch(complianceReviewQueueProvider)
          .when(
            loading: () => const EcLoadingIndicator(),
            error: (e, _) => EcErrorState(
              onRetry: () => ref.invalidate(complianceReviewQueueProvider),
            ),
            data: (items) => items.isEmpty
                ? const Text('Nothing is waiting for review.')
                : Column(
                    children: [
                      for (final e in items)
                        ListTile(
                          key: Key('queue-${e['evidenceId']}'),
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            e['profileKey'] != null
                                ? '${humanizeKey(e['requirementKey'])} · ${e['profileKey']}'
                                : 'Credential document',
                          ),
                          subtitle: Text(
                            'Clinic ${e['tenantId']} · submitted ${Fmt.dateTime(e['uploadedAt'])}',
                          ),
                          // a button's minimum width is unbounded in a ListTile
                          trailing: SizedBox(
                            width: 110,
                            child: EcSecondaryButton(
                              label: 'Review',
                              compact: true,
                              onPressed: () => context.go(
                                '/platform/compliance/tenants/${e['tenantId']}',
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
    );
  }
}

class _Profiles extends ConsumerWidget {
  const _Profiles();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Section(
      title: 'Registers',
      child: ref
          .watch(complianceProfilesProvider)
          .when(
            loading: () => const EcLoadingIndicator(),
            error: (e, _) => EcErrorState(
              onRetry: () => ref.invalidate(complianceProfilesProvider),
            ),
            data: (items) => items.isEmpty
                ? const EcEmptyState(
                    title: 'No registers yet',
                    message: 'Seed the baseline registers to start.',
                    icon: Icons.fact_check_outlined,
                  )
                : Column(
                    children: [
                      for (final p in items)
                        Padding(
                          key: Key('register-${p['key']}'),
                          padding: const EdgeInsets.symmetric(
                            vertical: EcSpacing.sm,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Wrap(
                                spacing: EcSpacing.sm,
                                runSpacing: EcSpacing.xs,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Text(
                                    '${p['title']}',
                                    style: EcTypography.bodyStrong,
                                  ),
                                  EcStatusChip(
                                    label:
                                        '${p['countryCode']} · ${humanizeKey(p['jurisdiction'])}',
                                  ),
                                  EcStatusChip(
                                    label: 'Version ${p['version']}',
                                  ),
                                  EcStatusChip(
                                    label:
                                        (p['legalReview'] as Map)['status'] ==
                                            'reviewed'
                                        ? 'Validated by counsel'
                                        : 'Not validated by counsel',
                                    tone:
                                        (p['legalReview'] as Map)['status'] ==
                                            'reviewed'
                                        ? EcStatusTone.success
                                        : EcStatusTone.warning,
                                  ),
                                ],
                              ),
                              Text(
                                '${(p['authority'] as Map)['name']} · ${(p['requirements'] as List).length} requirements',
                                style: EcTypography.helper,
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
          ),
    );
  }
}

/// A platform reviewer's view of one clinic: confirm applicability, review
/// evidence and verify credentials. Every action needs a reason or a clear
/// decision, and is audited by the backend.
class TenantCompliancePage extends ConsumerWidget {
  const TenantCompliancePage({required this.tenantId, super.key});

  final String tenantId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canReview = ref
        .watch(platformPermissionsProvider)
        .contains(Permission.reviewCompliance);
    void reload() {
      ref.invalidate(platformComplianceTenantProvider(tenantId));
      ref.invalidate(platformComplianceCredentialsProvider(tenantId));
      ref.invalidate(complianceReviewQueueProvider);
    }

    return AsyncBody<Json>(
      value: ref.watch(platformComplianceTenantProvider(tenantId)),
      onRetry: reload,
      builder: (d) {
        final profiles = (d['profiles']! as List).cast<Json>();
        return ListView(
          padding: const EdgeInsets.all(EcSpacing.lg),
          children: [
            PageHeader(
              title: 'Clinic compliance',
              subtitle:
                  'Clinic $tenantId · country ${d['countryCode'] ?? 'not assigned'}',
              actions: [
                EcSecondaryButton(
                  label: 'Back',
                  compact: true,
                  onPressed: () => context.go('/platform/compliance'),
                ),
              ],
            ),
            EcInlineMessage(
              message: '${d['disclaimer']}',
              tone: EcStatusTone.info,
            ),
            const SizedBox(height: EcSpacing.sm),
            Text(
              readinessLabel(d['readiness']),
              key: const Key('readiness-text'),
            ),
            const SizedBox(height: EcSpacing.lg),
            for (final p in profiles)
              Padding(
                padding: const EdgeInsets.only(bottom: EcSpacing.md),
                child: _TenantProfileCard(
                  tenantId: tenantId,
                  profile: p,
                  canReview: canReview,
                  onChanged: reload,
                ),
              ),
            _TenantCredentials(
              tenantId: tenantId,
              canReview: canReview,
              onChanged: reload,
            ),
          ],
        );
      },
    );
  }
}

class _TenantProfileCard extends ConsumerWidget {
  const _TenantProfileCard({
    required this.tenantId,
    required this.profile,
    required this.canReview,
    required this.onChanged,
  });

  final String tenantId;
  final Json profile;
  final bool canReview;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = profile;
    final key = '${p['key']}';
    final status = '${(p['applicability'] as Map)['status']}';
    final repo = ref.read(controlPlaneRepositoryProvider);

    Future<void> setApplicability(String to, String title) async {
      final reason = await showReasonDialog(
        context,
        title: title,
        message:
            'This decides whether the register applies to this clinic. It is recorded with your reason.',
        confirmLabel: 'Confirm',
      );
      if (reason == null || !context.mounted) return;
      await runAction(
        context,
        action: () =>
            repo.setComplianceApplicability(tenantId, key, to, reason),
        success: 'Applicability updated.',
        after: onChanged,
      );
    }

    return EcCard(
      key: Key('tenant-profile-$key'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: EcSpacing.sm,
            runSpacing: EcSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('${p['title']}', style: EcTypography.subsectionTitle),
              EcStatusChip(label: 'Version ${p['version']}'),
              EcStatusChip(
                label: (p['legalReview'] as Map)['status'] == 'reviewed'
                    ? 'Validated by counsel'
                    : 'Not validated by counsel',
                tone: (p['legalReview'] as Map)['status'] == 'reviewed'
                    ? EcStatusTone.success
                    : EcStatusTone.warning,
              ),
              EcStatusChip(
                key: Key('applicability-$key'),
                label: status == 'applies'
                    ? 'Applies'
                    : status == 'not_applicable'
                    ? 'Does not apply'
                    : 'Not confirmed',
                tone: status == 'applies'
                    ? EcStatusTone.info
                    : EcStatusTone.neutral,
              ),
            ],
          ),
          if (canReview)
            Wrap(
              spacing: EcSpacing.sm,
              children: [
                if (status != 'applies')
                  EcSecondaryButton(
                    key: Key('apply-$key'),
                    label: 'Confirm it applies',
                    compact: true,
                    onPressed: () => setApplicability(
                      'applies',
                      'Confirm that this register applies?',
                    ),
                  ),
                if (status != 'not_applicable')
                  EcSecondaryButton(
                    label: 'Mark not applicable',
                    compact: true,
                    onPressed: () => setApplicability(
                      'not_applicable',
                      'Mark this register not applicable?',
                    ),
                  ),
                if (status != 'unknown')
                  EcSecondaryButton(
                    label: 'Reset to unknown',
                    compact: true,
                    onPressed: () =>
                        setApplicability('unknown', 'Reset applicability?'),
                  ),
              ],
            ),
          const SizedBox(height: EcSpacing.sm),
          if (status == 'applies')
            for (final r in (p['requirements'] as List).cast<Json>())
              _TenantRequirement(
                tenantId: tenantId,
                profileKey: key,
                requirement: r,
                canReview: canReview,
                onChanged: onChanged,
              ),
        ],
      ),
    );
  }
}

class _TenantRequirement extends ConsumerWidget {
  const _TenantRequirement({
    required this.tenantId,
    required this.profileKey,
    required this.requirement,
    required this.canReview,
    required this.onChanged,
  });

  final String tenantId;
  final String profileKey;
  final Json requirement;
  final bool canReview;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = requirement;
    final status = '${r['status']}';
    final repo = ref.read(controlPlaneRepositoryProvider);
    final eid = r['evidenceId'] as String?;

    Future<void> decide(String decision) async {
      String? note;
      if (decision == 'reject') {
        note = await showReasonDialog(
          context,
          title: 'Reject this evidence?',
          message:
              'The clinic will see your reason and can upload new evidence.',
          confirmLabel: 'Reject',
          destructive: true,
        );
        if (note == null || !context.mounted) return;
      } else {
        final ok = await showEcConfirmDialog(
          context,
          title: 'Approve this evidence?',
          message:
              'Only approve after you have checked the document. The approval expires with the document.',
          confirmLabel: 'Approve',
        );
        if (!ok || !context.mounted) return;
      }
      await runAction(
        context,
        action: () => repo.reviewComplianceEvidence(tenantId, eid!, {
          'decision': decision,
          'note': ?note,
        }),
        success: decision == 'accept'
            ? 'Evidence approved.'
            : 'Evidence rejected.',
        after: onChanged,
      );
    }

    Future<void> setStatus(String to, String title) async {
      final reason = await showReasonDialog(
        context,
        title: title,
        message: 'This is recorded with your reason.',
        confirmLabel: 'Confirm',
      );
      if (reason == null || !context.mounted) return;
      await runAction(
        context,
        action: () => repo.setComplianceItemStatus(
          tenantId,
          profileKey,
          '${r['key']}',
          {'status': to, 'reason': reason},
        ),
        success: 'Requirement updated.',
        after: onChanged,
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: EcSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: EcSpacing.sm,
            runSpacing: EcSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('${r['title']}', style: EcTypography.bodyStrong),
              EcStatusChip(
                key: Key('status-${r['key']}'),
                label: complianceStatusLabel(status),
                tone: complianceStatusTone(status),
              ),
            ],
          ),
          if (r['expiresAt'] != null)
            Text(
              'Valid until ${Fmt.date(r['expiresAt'])}',
              style: EcTypography.helper,
            ),
          if (canReview)
            Wrap(
              spacing: EcSpacing.sm,
              children: [
                if (eid != null)
                  EcSecondaryButton(
                    key: Key('download-${r['key']}'),
                    label: 'Download file',
                    compact: true,
                    onPressed: () => runAction(
                      context,
                      action: () async {
                        final bytes = await repo.platformEvidenceBytes(
                          tenantId,
                          eid,
                        );
                        await ref.read(reportSaverProvider)(
                          'evidence-$eid',
                          bytes,
                        );
                      },
                      success: 'File downloaded.',
                    ),
                  ),
                if (status == 'under_review' && eid != null) ...[
                  EcPrimaryButton(
                    key: Key('accept-${r['key']}'),
                    label: 'Approve',
                    compact: true,
                    onPressed: () => decide('accept'),
                  ),
                  EcSecondaryButton(
                    key: Key('reject-${r['key']}'),
                    label: 'Reject',
                    compact: true,
                    onPressed: () => decide('reject'),
                  ),
                ],
                if (status != 'not_applicable')
                  EcSecondaryButton(
                    label: 'Mark not applicable',
                    compact: true,
                    onPressed: () => setStatus(
                      'not_applicable',
                      'Mark this requirement not applicable?',
                    ),
                  ),
                if (status == 'not_applicable')
                  EcSecondaryButton(
                    label: 'Ask for evidence again',
                    compact: true,
                    onPressed: () => setStatus(
                      'pending_evidence',
                      'Reopen this requirement?',
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _TenantCredentials extends ConsumerWidget {
  const _TenantCredentials({
    required this.tenantId,
    required this.canReview,
    required this.onChanged,
  });

  final String tenantId;
  final bool canReview;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(controlPlaneRepositoryProvider);
    return Section(
      title: 'Credentials',
      child: ref
          .watch(platformComplianceCredentialsProvider(tenantId))
          .when(
            loading: () => const EcLoadingIndicator(),
            error: (e, _) => EcErrorState(
              onRetry: () => ref.invalidate(
                platformComplianceCredentialsProvider(tenantId),
              ),
            ),
            data: (items) => items.isEmpty
                ? const Text('No credentials recorded.')
                : Column(
                    children: [
                      for (final c in items)
                        Padding(
                          key: Key('credential-${c['credentialId']}'),
                          padding: const EdgeInsets.symmetric(
                            vertical: EcSpacing.sm,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Wrap(
                                spacing: EcSpacing.sm,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Text(
                                    '${c['subjectName']}',
                                    style: EcTypography.bodyStrong,
                                  ),
                                  EcStatusChip(
                                    label: validityLabel(c['validity']),
                                    tone: validityTone(c['validity']),
                                  ),
                                  EcStatusChip(
                                    label: verificationLabel(
                                      (c['verification'] as Map?)?['status'],
                                    ),
                                    tone: verificationTone(
                                      (c['verification'] as Map?)?['status'],
                                    ),
                                  ),
                                ],
                              ),
                              Text(
                                '${c['authorityName']} · No. ${c['number']}',
                                style: EcTypography.helper,
                              ),
                              if (canReview &&
                                  c['evidenceId'] != null &&
                                  (c['verification'] as Map?)?['status'] ==
                                      'unverified')
                                Wrap(
                                  spacing: EcSpacing.sm,
                                  children: [
                                    EcPrimaryButton(
                                      label: 'Verify',
                                      compact: true,
                                      onPressed: () => runAction(
                                        context,
                                        action: () =>
                                            repo.verifyComplianceCredential(
                                              tenantId,
                                              '${c['credentialId']}',
                                              {'decision': 'verify'},
                                            ),
                                        success: 'Credential verified.',
                                        after: onChanged,
                                      ),
                                    ),
                                    EcSecondaryButton(
                                      label: 'Reject',
                                      compact: true,
                                      onPressed: () async {
                                        final note = await showReasonDialog(
                                          context,
                                          title: 'Reject this credential?',
                                          message:
                                              'The clinic will see your reason.',
                                          confirmLabel: 'Reject',
                                          destructive: true,
                                        );
                                        if (note == null || !context.mounted) {
                                          return;
                                        }
                                        await runAction(
                                          context,
                                          action: () =>
                                              repo.verifyComplianceCredential(
                                                tenantId,
                                                '${c['credentialId']}',
                                                {
                                                  'decision': 'reject',
                                                  'note': note,
                                                },
                                              ),
                                          success: 'Credential rejected.',
                                          after: onChanged,
                                        );
                                      },
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
          ),
    );
  }
}
