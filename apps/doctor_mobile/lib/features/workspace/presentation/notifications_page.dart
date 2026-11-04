import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/clinical_repository.dart';
import 'providers.dart';
import 'ui_kit.dart';

/// Where a notification leads. The link is a convenience only: the target
/// screen and the API check access again.
String? _route(Json n) => switch (n['resourceType']) {
  'appointment' => '/today',
  'followup' => '/followups',
  _ => null,
};

/// The doctor's notification center and preferences.
class NotificationsPage extends ConsumerWidget {
  const NotificationsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final q = Query('/notifications', {'limit': '50'});
    final cq = Query('/notifications/unread-count');
    final repo = ref.read(clinicalRepositoryProvider);
    return ListView(
      padding: const EdgeInsets.all(EcSpacing.lg),
      children: [
        PageHeader(
          title: 'Notifications',
          subtitle: 'Appointments, reports and follow-ups that need you.',
          actions: [
            sized(
              EcSecondaryButton(
                key: const Key('mark-all-read'),
                label: 'Mark all read',
                onPressed: () => runAction(
                  context,
                  action: () =>
                      repo.send('POST', '/notifications/read-all', {}),
                  success: 'All marked as read.',
                  after: () => refreshAll(ref),
                ),
              ),
              180,
            ),
            TextButton(
              key: const Key('open-preferences'),
              onPressed: () => context.go('/notifications/settings'),
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
              '${c['unread']}${c['capped'] == true ? '+' : ''} unread',
              key: const Key('unread-count'),
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
                message: 'New messages appear here.',
                icon: Icons.notifications_none,
              );
            }
            return Column(
              children: [
                for (final n in items)
                  EcCard(
                    key: Key('notification-${n['notificationId']}'),
                    onTap: () async {
                      final route = _route(n);
                      if (n['read'] != true) {
                        await repo.send(
                          'POST',
                          '/notifications/${n['notificationId']}/read',
                          {},
                        );
                        refreshAll(ref);
                      }
                      if (route != null && context.mounted) context.go(route);
                    },
                    child: Row(
                      children: [
                        Icon(
                          n['read'] == true
                              ? Icons.notifications_none
                              : Icons.notifications_active,
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
                                shortDateTime(n['createdAt']),
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
                            action: () => repo.send(
                              'POST',
                              '/notifications/${n['notificationId']}/archive',
                              {},
                            ),
                            success: 'Dismissed.',
                            after: () => refreshAll(ref),
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

class NotificationPreferencesPage extends ConsumerWidget {
  const NotificationPreferencesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final q = Query('/notifications/preferences');
    final repo = ref.read(clinicalRepositoryProvider);
    Future<void> save(Json body) => runAction(
      context,
      action: () => repo.send('PATCH', '/notifications/preferences', body),
      success: 'Preferences saved.',
      after: () => ref.invalidate(mapProvider(q)),
    );
    return AsyncBody(
      value: ref.watch(mapProvider(q)),
      onRetry: () => ref.invalidate(mapProvider(q)),
      builder: (p) {
        final cats = ((p['categories'] as Map?) ?? const {})
            .cast<String, Object?>();
        final essential = ((p['essentialCategories'] as List?) ?? const [])
            .cast<String>();
        return ListView(
          padding: const EdgeInsets.all(EcSpacing.lg),
          children: [
            const PageHeader(
              title: 'Notification preferences',
              subtitle:
                  'Service messages always appear in your notifications. You choose which also reach you as push messages.',
            ),
            SwitchListTile(
              key: const Key('pref-push'),
              title: const Text('Push notifications'),
              value: p['pushEnabled'] != false,
              onChanged: (v) => save({'pushEnabled': v}),
            ),
            for (final c in cats.entries)
              SwitchListTile(
                key: Key('pref-cat-${c.key}'),
                title: Text(humanize(c.key)),
                subtitle: Text(
                  essential.contains(c.key)
                      ? 'Service message: always in the app.'
                      : 'Optional.',
                ),
                value: c.value == true,
                onChanged: (v) => save({
                  'categories': {c.key: v},
                }),
              ),
          ],
        );
      },
    );
  }
}
