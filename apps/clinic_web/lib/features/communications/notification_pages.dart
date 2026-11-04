import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../control_plane/data/control_plane_repository.dart';
import '../finance/finance_kit.dart';
import '../patients/dialogs.dart';
import '../scheduling/scheduling_providers.dart';
import '../shared/async_body.dart';
import '../shared/ui_helpers.dart';
import '../shared/ui_kit.dart';

void _refresh(WidgetRef ref) {
  ref
    ..invalidate(mapProvider)
    ..invalidate(listProvider);
}

/// Where a notification leads. The link is only a convenience: the target
/// screen and the API check access again.
String? notificationRoute(Map<String, Object?> n) {
  final id = n['resourceId'];
  return switch (n['resourceType']) {
    'appointment' => '/clinic/appointments',
    'lab_report' || 'lab_order' when id != null => '/clinic/laboratory/orders',
    _ => null,
  };
}

// ------------------------------------------------------------ notification center

class NotificationCenterPage extends ConsumerWidget {
  const NotificationCenterPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final q = Query('/notifications', const {'limit': '50'});
    final cq = Query('/notifications/unread-count');
    final repo = ref.read(controlPlaneRepositoryProvider);
    return ListView(
      padding: const EdgeInsets.all(EcSpacing.lg),
      children: [
        PageHeader(
          title: 'Notifications',
          subtitle: 'Messages for you about this clinic.',
          actions: [
            sized(
              EcSecondaryButton(
                key: const Key('mark-all-read'),
                label: 'Mark all read',
                onPressed: () => runAction(
                  context,
                  action: () async =>
                      repo.sendMap('POST', '/notifications/read-all', {}),
                  success: 'All marked as read',
                  after: () => _refresh(ref),
                ),
              ),
            ),
            TextButton(
              onPressed: () => context.go('/clinic/notifications/settings'),
              child: const Text('Preferences'),
            ),
          ],
        ),
        AsyncBody(
          value: ref.watch(mapProvider(cq)),
          onRetry: () => ref.invalidate(mapProvider(cq)),
          builder: (c) => Padding(
            padding: const EdgeInsets.only(bottom: EcSpacing.md),
            child: Text(
              key: const Key('unread-count'),
              '${c['unread']}${c['capped'] == true ? '+' : ''} unread',
              style: EcTypography.bodyStrong,
            ),
          ),
        ),
        AsyncBody(
          value: ref.watch(listProvider(q)),
          onRetry: () => ref.invalidate(listProvider(q)),
          builder: (items) {
            if (items.isEmpty) {
              return const EcEmptyState(
                title: 'No notifications',
                message:
                    'New messages about appointments, reports and the clinic appear here.',
                icon: Icons.notifications_none,
              );
            }
            return Column(
              children: [
                for (final n in items)
                  EcCard(
                    key: Key('notification-${n['notificationId']}'),
                    onTap: () async {
                      final route = notificationRoute(n);
                      if (n['read'] != true) {
                        await repo.sendMap(
                          'POST',
                          '/notifications/${n['notificationId']}/read',
                          {},
                        );
                        _refresh(ref);
                      }
                      if (route != null && context.mounted) context.go(route);
                    },
                    child: Row(
                      children: [
                        Icon(
                          n['read'] == true
                              ? Icons.notifications_none
                              : Icons.notifications_active,
                          color: n['read'] == true
                              ? EcColors.textSecondary
                              : EcColors.blue,
                        ),
                        const SizedBox(width: EcSpacing.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${n['title']}',
                                style: n['read'] == true
                                    ? EcTypography.body
                                    : EcTypography.bodyStrong,
                              ),
                              Text(
                                '${n['body'] ?? ''}',
                                style: EcTypography.bodySecondary,
                              ),
                              Text(
                                Fmt.dateTime(n['createdAt']),
                                style: EcTypography.bodySecondary,
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          key: Key('archive-${n['notificationId']}'),
                          tooltip: 'Dismiss',
                          icon: const Icon(Icons.close),
                          onPressed: () => runAction(
                            context,
                            action: () async => repo.sendMap(
                              'POST',
                              '/notifications/${n['notificationId']}/archive',
                              {},
                            ),
                            success: 'Dismissed',
                            after: () => _refresh(ref),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

// ------------------------------------------------------------------ preferences

class NotificationPreferencesPage extends ConsumerWidget {
  const NotificationPreferencesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final q = Query('/notifications/preferences');
    final repo = ref.read(controlPlaneRepositoryProvider);
    Future<void> save(Map<String, Object?> body) => runAction(
      context,
      action: () async =>
          repo.sendMap('PATCH', '/notifications/preferences', body),
      success: 'Preferences saved',
      after: () => ref.invalidate(mapProvider(q)),
    );
    return AsyncBody(
      value: ref.watch(mapProvider(q)),
      onRetry: () => ref.invalidate(mapProvider(q)),
      builder: (p) {
        final cats = ((p['categories'] as Map?) ?? const {})
            .cast<String, Object?>();
        final chans = ((p['channels'] as Map?) ?? const {})
            .cast<String, Object?>();
        final essential = ((p['essentialCategories'] as List?) ?? const [])
            .cast<String>();
        return ListView(
          padding: const EdgeInsets.all(EcSpacing.lg),
          children: [
            const PageHeader(
              title: 'Notification preferences',
              subtitle:
                  'Service messages always appear in your notification centre. You choose which ones also reach you as push, email, SMS or WhatsApp.',
            ),
            Section(
              title: 'Channels',
              child: Column(
                children: [
                  SwitchListTile(
                    key: const Key('pref-push'),
                    title: const Text('Push notifications'),
                    value: p['pushEnabled'] != false,
                    onChanged: (v) => save({'pushEnabled': v}),
                  ),
                  for (final c in chans.entries)
                    SwitchListTile(
                      key: Key('pref-${c.key}'),
                      title: Text(Fmt.humanize(c.key)),
                      subtitle: const Text(
                        'Used only if your clinic has set this channel up.',
                      ),
                      value: c.value != false,
                      onChanged: (v) => save({
                        'channels': {c.key: v},
                      }),
                    ),
                ],
              ),
            ),
            Section(
              title: 'Messages',
              child: Column(
                children: [
                  for (final c in cats.entries)
                    SwitchListTile(
                      key: Key('pref-cat-${c.key}'),
                      title: Text(Fmt.humanize(c.key)),
                      subtitle: Text(
                        essential.contains(c.key)
                            ? 'Service message: always shown in the app. This switch controls extra channels.'
                            : 'Optional. Sent only if you turn it on.',
                      ),
                      value: c.value == true,
                      onChanged: (v) => save({
                        'categories': {c.key: v},
                      }),
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

// -------------------------------------------------------------------- administration

class NotificationAdminPage extends ConsumerStatefulWidget {
  const NotificationAdminPage({super.key});

  @override
  ConsumerState<NotificationAdminPage> createState() => _AdminState();
}

class _AdminState extends ConsumerState<NotificationAdminPage> {
  String _tab = 'deliveries';

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(EcSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PageHeader(
            title: 'Notification administration',
            subtitle:
                'Delivery monitoring, templates and channels for this clinic.',
          ),
          Wrap(
            spacing: EcSpacing.sm,
            children: [
              for (final (k, l) in const [
                ('deliveries', 'Deliveries'),
                ('templates', 'Templates'),
                ('channels', 'Channels'),
              ])
                ChoiceChip(
                  key: Key('admin-tab-$k'),
                  label: Text(l),
                  selected: _tab == k,
                  onSelected: (_) => setState(() => _tab = k),
                ),
            ],
          ),
          const SizedBox(height: EcSpacing.md),
          Expanded(
            child: switch (_tab) {
              'templates' => const SingleChildScrollView(child: _Templates()),
              'channels' => const SingleChildScrollView(child: _Channels()),
              _ => const _Deliveries(),
            },
          ),
        ],
      ),
    );
  }
}

class _Deliveries extends ConsumerWidget {
  const _Deliveries();

  static const _statuses = [
    'queued',
    'processing',
    'sent',
    'delivered',
    'retry_scheduled',
    'cancelled',
    'permanently_failed',
    'configuration_required',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hq = Query('/admin/notification-health');
    final repo = ref.read(controlPlaneRepositoryProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AsyncBody(
          value: ref.watch(mapProvider(hq)),
          onRetry: () => ref.invalidate(mapProvider(hq)),
          builder: (h) => Wrap(
            spacing: EcSpacing.md,
            runSpacing: EcSpacing.md,
            children: [
              for (final (k, l) in const [
                ('failed', 'Failed'),
                ('retryBacklog', 'Waiting to send'),
                ('configurationRequired', 'Need configuration'),
                ('eventsWaiting', 'Events waiting'),
              ])
                SizedBox(
                  width: 200,
                  child: EcCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${h[k] ?? 0}',
                          key: Key('health-$k'),
                          style: EcTypography.sectionTitle,
                        ),
                        Text(l, style: EcTypography.bodySecondary),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: EcSpacing.sm),
        Text(
          '"Sent" means the provider accepted the message. It does not confirm that the person received it.',
          style: EcTypography.bodySecondary,
        ),
        Expanded(
          child: ListScreen(
            title: 'Deliveries',
            path: '/admin/notification-deliveries',
            statusOptions: _statuses,
            searchHint: 'Filter by status',
            emptyTitle: 'No deliveries',
            emptyMessage: 'Deliveries appear when notifications are created.',
            rowBuilder: (context, d) {
              final failed =
                  d['status'] == 'permanently_failed' ||
                  d['status'] == 'configuration_required';
              return EcCard(
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${Fmt.humanize(d['type'])} · ${Fmt.humanize(d['channel'])}',
                            style: EcTypography.bodyStrong,
                          ),
                          Text(
                            '${Fmt.dateTime(d['createdAt'])} · attempts ${d['attempts'] ?? 0}'
                            '${d['error'] == null ? '' : ' · ${d['error']}'}',
                            style: EcTypography.bodySecondary,
                          ),
                        ],
                      ),
                    ),
                    statusChip(d['status']),
                    if (failed)
                      TextButton(
                        key: Key('retry-${d['deliveryId']}'),
                        onPressed: () async {
                          final ok = await showDialog<bool>(
                            context: context,
                            builder: (dctx) => AlertDialog(
                              title: const Text('Retry this delivery?'),
                              content: const Text(
                                'The message is sent again to the same recipient. This is recorded in the audit trail.',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.of(dctx).pop(false),
                                  child: const Text('Cancel'),
                                ),
                                FilledButton(
                                  key: const Key('confirm-retry'),
                                  onPressed: () => Navigator.of(dctx).pop(true),
                                  child: const Text('Retry'),
                                ),
                              ],
                            ),
                          );
                          if (ok != true || !context.mounted) return;
                          await runAction(
                            context,
                            action: () async => repo.sendMap(
                              'POST',
                              '/admin/notification-deliveries/${d['deliveryId']}/retry',
                              {},
                            ),
                            success: 'Retry started',
                            after: () => _refresh(ref),
                          );
                        },
                        child: const Text('Retry'),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _Templates extends ConsumerWidget {
  const _Templates();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final q = Query('/admin/notification-templates');
    final repo = ref.read(controlPlaneRepositoryProvider);
    return AsyncBody(
      value: ref.watch(listProvider(q)),
      onRetry: () => ref.invalidate(listProvider(q)),
      builder: (items) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          sized(
            EcPrimaryButton(
              key: const Key('new-template'),
              label: 'New template',
              onPressed: () async {
                final v = await showRecordDialog(
                  context,
                  title: 'New template',
                  note:
                      'Use {{clinicName}}, {{doctorName}}, {{date}} and {{time}} where the event allows them. Never put clinical details in a message.',
                  fields: const [
                    FieldSpec('name', 'Name', required: true),
                    FieldSpec('eventType', 'Event', required: true),
                    FieldSpec(
                      'channel',
                      'Channel',
                      kind: FieldKind.choice,
                      required: true,
                      options: ['in_app', 'push', 'email', 'sms', 'whatsapp'],
                    ),
                    FieldSpec(
                      'locale',
                      'Language (2 letters)',
                      required: true,
                      maxLength: 2,
                    ),
                    FieldSpec('subject', 'Subject', maxLength: 150),
                    FieldSpec(
                      'body',
                      'Message',
                      kind: FieldKind.multiline,
                      required: true,
                      maxLength: 1000,
                    ),
                  ],
                );
                if (v == null || !context.mounted) return;
                await runAction(
                  context,
                  action: () async =>
                      repo.sendMap('POST', '/admin/notification-templates', v),
                  success: 'Template created',
                  after: () => _refresh(ref),
                );
              },
            ),
          ),
          const SizedBox(height: EcSpacing.md),
          for (final t in items)
            EcCard(
              key: Key('template-${t['templateId']}'),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${Fmt.humanize(t['eventType'])} · ${Fmt.humanize(t['channel'])} · ${t['locale']}',
                          style: EcTypography.bodyStrong,
                        ),
                        Text('${t['body']}', style: EcTypography.bodySecondary),
                        Text(
                          '${t['builtin'] == true ? 'Built in' : 'This clinic'} · version ${t['version']}',
                          style: EcTypography.bodySecondary,
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    key: Key('preview-${t['templateId']}'),
                    onPressed: () async {
                      final r = await repo.sendMap(
                        'POST',
                        '/admin/notification-templates/${t['templateId']}/preview',
                        {},
                      );
                      if (!context.mounted) return;
                      await showDialog<void>(
                        context: context,
                        builder: (dctx) => AlertDialog(
                          title: const Text('Preview'),
                          content: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${r['subject']}',
                                style: EcTypography.bodyStrong,
                              ),
                              Text(
                                '${r['body']}',
                                key: const Key('preview-body'),
                              ),
                              const SizedBox(height: EcSpacing.sm),
                              Text(
                                '${r['note']}',
                                style: EcTypography.bodySecondary,
                              ),
                            ],
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(dctx).pop(),
                              child: const Text('Close'),
                            ),
                          ],
                        ),
                      );
                    },
                    child: const Text('Preview'),
                  ),
                  if (t['builtin'] != true)
                    TextButton(
                      key: Key('edit-${t['templateId']}'),
                      onPressed: () async {
                        final v = await showRecordDialog(
                          context,
                          title: 'Edit template',
                          note:
                              'Saving creates version ${(t['version'] as int? ?? 1) + 1}. Earlier versions are kept.',
                          initial: {'subject': t['subject'], 'body': t['body']},
                          fields: const [
                            FieldSpec('subject', 'Subject', maxLength: 150),
                            FieldSpec(
                              'body',
                              'Message',
                              kind: FieldKind.multiline,
                              required: true,
                              maxLength: 1000,
                            ),
                          ],
                        );
                        if (v == null || !context.mounted) return;
                        await runAction(
                          context,
                          action: () async => repo.sendMap(
                            'PATCH',
                            '/admin/notification-templates/${t['templateId']}',
                            v,
                          ),
                          success: 'Template saved',
                          after: () => _refresh(ref),
                        );
                      },
                      child: const Text('Edit'),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Channels extends ConsumerWidget {
  const _Channels();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final q = Query('/admin/notification-channels');
    final repo = ref.read(controlPlaneRepositoryProvider);
    return AsyncBody(
      value: ref.watch(listProvider(q)),
      onRetry: () => ref.invalidate(listProvider(q)),
      builder: (items) => Column(
        children: [
          for (final c in items)
            EcCard(
              key: Key('channel-${c['channel']}'),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          Fmt.humanize(c['channel']),
                          style: EcTypography.bodyStrong,
                        ),
                        Text(
                          c['configured'] == true
                              ? (c['paused'] == true
                                    ? 'Paused: queued messages wait'
                                    : 'Configured')
                              : 'Configuration required: no provider is set up for this environment',
                          style: EcTypography.bodySecondary,
                        ),
                      ],
                    ),
                  ),
                  if (c['channel'] != 'in_app')
                    TextButton(
                      key: Key('toggle-${c['channel']}'),
                      onPressed: () => runAction(
                        context,
                        action: () async => repo.sendMap(
                          'POST',
                          '/admin/notification-channels/${c['channel']}/${c['paused'] == true ? 'resume' : 'pause'}',
                          {},
                        ),
                        success: c['paused'] == true
                            ? 'Channel resumed'
                            : 'Channel paused',
                        after: () => _refresh(ref),
                      ),
                      child: Text(c['paused'] == true ? 'Resume' : 'Pause'),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
