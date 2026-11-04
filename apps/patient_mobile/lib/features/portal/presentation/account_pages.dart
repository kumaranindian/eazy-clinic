import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/portal_repository.dart';
import '../push/push_service.dart';
import 'providers.dart';
import 'ui_kit.dart';

// ------------------------------------------------------------------- family

class FamilyPage extends ConsumerWidget {
  const FamilyPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final q = Query('/patient/family');
    final repo = ref.read(portalRepositoryProvider);
    Future<void> act(String path, String ok, [Json? body]) => runAction(
      context,
      action: () => repo.send('POST', path, body),
      success: ok,
      after: () => refreshAll(ref),
    );
    return ListView(
      padding: const EdgeInsets.all(EcSpacing.lg),
      children: [
        PageHeader(
          title: 'Family',
          subtitle:
              'Children you look after and people who help manage your care. Each one needs a verified relationship.',
          actions: [
            sized(
              EcPrimaryButton(
                label: 'Add a child',
                icon: Icons.child_care_outlined,
                onPressed: () async {
                  final v = await showFormDialog(
                    context,
                    title: 'Add a child',
                    note:
                        'You become the guardian. Linking a clinic record for your child needs a code from the clinic.',
                    confirmLabel: 'Add',
                    fields: const [
                      FieldSpec(
                        'displayName',
                        'Child\'s full name',
                        required: true,
                        maxLength: 100,
                      ),
                      FieldSpec(
                        'dateOfBirth',
                        'Date of birth',
                        kind: FieldKind.date,
                        required: true,
                      ),
                      FieldSpec(
                        'gender',
                        'Gender',
                        kind: FieldKind.choice,
                        options: ['female', 'male', 'other'],
                      ),
                    ],
                  );
                  if (v == null || !context.mounted) return;
                  await act('/patient-accounts/me/family', 'Child added.', {
                    'relationshipType': 'parent',
                    'isGuardian': true,
                    'permissionScope': [
                      'view_clinic_links',
                      'link_clinic_records',
                      'manage_appointments',
                      'view_records',
                      'give_consent',
                    ],
                    'dependent': {
                      'displayName': v['displayName'],
                      'dateOfBirth': v['dateOfBirth'],
                      'gender': ?v['gender'],
                    },
                  });
                },
              ),
              200,
            ),
          ],
        ),
        AsyncBody(
          value: ref.watch(listProvider(q)),
          onRetry: () => ref.invalidate(listProvider(q)),
          builder: (rows) => rows.isEmpty
              ? const EcEmptyState(
                  title: 'No family members yet',
                  message:
                      'Add a child, or accept a request from someone who helps with your care.',
                  icon: Icons.family_restroom_outlined,
                )
              : Column(
                  children: [
                    for (final f in rows)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(EcSpacing.md),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      '${f['otherName'] ?? 'Family member'}',
                                      style: EcTypography.bodyStrong,
                                    ),
                                  ),
                                  statusChip(f['status']),
                                ],
                              ),
                              Text(
                                f['direction'] == 'i_manage'
                                    ? 'You act for them · ${humanize(f['relationshipType'])}'
                                    : 'They can act for you · ${humanize(f['relationshipType'])}',
                                style: EcTypography.bodySecondary,
                              ),
                              Text(
                                'Allowed: ${((f['permissionScope'] as List?) ?? const []).map(humanize).join(', ')}',
                                style: EcTypography.bodySecondary,
                              ),
                              const SizedBox(height: EcSpacing.sm),
                              Wrap(
                                spacing: EcSpacing.sm,
                                children: [
                                  if (f['direction'] == 'manages_me' &&
                                      f['status'] == 'pending')
                                    TextButton(
                                      key: Key(
                                        'approve-${f['relationshipId']}',
                                      ),
                                      onPressed: () => act(
                                        '/family-relationships/${f['relationshipId']}/verify',
                                        'Access approved.',
                                        {'decision': 'approve'},
                                      ),
                                      child: const Text('Approve'),
                                    ),
                                  if (f['direction'] == 'manages_me' &&
                                      f['status'] == 'pending')
                                    TextButton(
                                      onPressed: () => act(
                                        '/family-relationships/${f['relationshipId']}/verify',
                                        'Request declined.',
                                        {'decision': 'reject'},
                                      ),
                                      child: const Text('Decline'),
                                    ),
                                  if (f['status'] == 'active' ||
                                      f['status'] == 'pending')
                                    TextButton(
                                      key: Key('revoke-${f['relationshipId']}'),
                                      onPressed: () async {
                                        final sure = await showDialog<bool>(
                                          context: context,
                                          builder: (context) => AlertDialog(
                                            title: const Text(
                                              'End this access?',
                                            ),
                                            content: const Text(
                                              'It stops immediately. You can ask again later.',
                                            ),
                                            actions: [
                                              TextButton(
                                                onPressed: () => Navigator.of(
                                                  context,
                                                ).pop(false),
                                                child: const Text('Keep'),
                                              ),
                                              TextButton(
                                                onPressed: () => Navigator.of(
                                                  context,
                                                ).pop(true),
                                                child: const Text('End access'),
                                              ),
                                            ],
                                          ),
                                        );
                                        if (sure == true && context.mounted) {
                                          await act(
                                            '/family-relationships/${f['relationshipId']}/revoke',
                                            'Access ended.',
                                            {},
                                          );
                                        }
                                      },
                                      child: const Text('End access'),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

// ----------------------------------------------------------- notifications

class NotificationsPage extends ConsumerWidget {
  const NotificationsPage({super.key});

  String _route(Json n) {
    final id = n['resourceId'];
    final clinic = n['clinicId'];
    return switch (n['resourceType']) {
      'appointment' when id != null && clinic != null =>
        '/appointments/$clinic/$id',
      'consultation' => '/records?tab=visits',
      'prescription' => '/records?tab=prescriptions',
      'invoice' || 'payment' || 'refund' => '/records?tab=bills',
      _ => '/notifications',
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final q = Query('/patient/notifications');
    return ListView(
      padding: const EdgeInsets.all(EcSpacing.lg),
      children: [
        PageHeader(
          title: 'Notifications',
          actions: [
            TextButton(
              onPressed: () => context.go('/notifications/settings'),
              child: const Text('Settings'),
            ),
          ],
        ),
        AsyncBody(
          value: ref.watch(mapProvider(q)),
          onRetry: () => ref.invalidate(mapProvider(q)),
          builder: (d) {
            final items = ((d['items'] as List?) ?? const []).cast<Json>();
            if (items.isEmpty) {
              return const EcEmptyState(
                title: 'Nothing new',
                message:
                    'Updates about your visits, prescriptions and bills appear here.',
                icon: Icons.notifications_none_outlined,
              );
            }
            return Column(
              children: [
                for (final n in items)
                  Card(
                    child: ListTile(
                      key: Key('note-${n['notificationId']}'),
                      leading: Icon(
                        n['read'] == true
                            ? Icons.notifications_none
                            : Icons.notifications_active_outlined,
                      ),
                      title: Text(
                        '${n['title']}',
                        style: n['read'] == true
                            ? null
                            : EcTypography.bodyStrong,
                      ),
                      subtitle: Text(
                        '${n['body']}\n${shortDateTime(n['createdAt'])}',
                      ),
                      isThreeLine: true,
                      onTap: () async {
                        if (n['read'] != true) {
                          try {
                            await ref
                                .read(portalRepositoryProvider)
                                .send(
                                  'POST',
                                  '/patient/notifications/${n['notificationId']}/read',
                                  {},
                                );
                          } on ApiFailure {
                            // reading still opens the item
                          }
                          ref.invalidate(mapProvider);
                        }
                        if (context.mounted) context.go(_route(n));
                      },
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

class NotificationSettingsPage extends ConsumerWidget {
  const NotificationSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final q = Query('/patient/notifications/preferences');
    Future<void> save(Json body) => runAction(
      context,
      action: () => ref
          .read(portalRepositoryProvider)
          .send('PUT', '/patient/notifications/preferences', body),
      success: 'Saved.',
      after: () => ref.invalidate(mapProvider),
    );
    return ListView(
      padding: const EdgeInsets.all(EcSpacing.lg),
      children: [
        const PageHeader(
          title: 'Notification settings',
          subtitle:
              'Choose what you want to hear about. Messages never include diagnoses, medicines or amounts.',
        ),
        AsyncBody(
          value: ref.watch(mapProvider(q)),
          onRetry: () => ref.invalidate(mapProvider(q)),
          builder: (d) {
            final cats = ((d['categories'] as Map?) ?? const {})
                .cast<String, Object?>();
            return Column(
              children: [
                SwitchListTile(
                  key: const Key('push-enabled'),
                  title: const Text('Push notifications'),
                  value: d['pushEnabled'] != false,
                  onChanged: (v) => save({'pushEnabled': v}),
                ),
                for (final e in cats.entries)
                  SwitchListTile(
                    dense: true,
                    title: Text(humanize(e.key)),
                    value: e.value != false,
                    onChanged: (v) => save({
                      'categories': {e.key: v},
                    }),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

// ------------------------------------------------------------------ profile

class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final q = Query('/patient/profile');
    final repo = ref.read(portalRepositoryProvider);
    return AsyncBody(
      value: ref.watch(mapProvider(q)),
      onRetry: () => ref.invalidate(mapProvider(q)),
      builder: (p) {
        final linked = ((p['linkedClinics'] as List?) ?? const []).cast<Json>();
        final address = (p['address'] as Map?) ?? const {};
        final emergency = (p['emergencyContact'] as Map?) ?? const {};
        return ListView(
          padding: const EdgeInsets.all(EcSpacing.lg),
          children: [
            PageHeader(
              title: '${p['displayName'] ?? 'My profile'}',
              subtitle: 'Profile ${p['profileCompletion']}% complete',
              actions: [
                sized(
                  EcSecondaryButton(
                    label: 'Edit',
                    icon: Icons.edit_outlined,
                    onPressed: () => _edit(context, ref, p),
                  ),
                  120,
                ),
              ],
            ),
            Section(
              title: 'Personal details',
              child: KeyValues([
                ('Name', p['displayName']),
                ('E-mail', p['email']),
                ('Mobile', p['phone']),
                ('Date of birth', p['dateOfBirth']),
                (
                  'Language',
                  p['preferredLanguage'] == null
                      ? null
                      : '${p['preferredLanguage']}'.toUpperCase(),
                ),
                (
                  'Address',
                  [
                    address['line1'],
                    address['city'],
                    address['postalCode'],
                  ].where((e) => e != null).join(', '),
                ),
                (
                  'Emergency contact',
                  emergency.isEmpty
                      ? null
                      : '${emergency['name']} · ${emergency['phone']}',
                ),
                ('Identity', humanize(p['identityVerification'])),
              ]),
            ),
            Section(
              title: 'Linked clinics',
              child: linked.isEmpty
                  ? const Text('None yet.')
                  : Column(
                      children: [
                        for (final c in linked)
                          ListTile(
                            dense: true,
                            title: Text('${c['clinicName']}'),
                            subtitle: Text('Patient number ${c['mrn'] ?? '—'}'),
                            trailing: TextButton(
                              onPressed: () => context.go(
                                '/profile/privacy/${c['clinicId']}',
                              ),
                              child: const Text('Privacy'),
                            ),
                          ),
                      ],
                    ),
            ),
            Section(
              title: 'Settings',
              child: Column(
                children: [
                  ListTile(
                    title: const Text('Family'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.go('/family'),
                  ),
                  ListTile(
                    title: const Text('Notification settings'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.go('/notifications/settings'),
                  ),
                  ListTile(
                    title: const Text('Help and support'),
                    subtitle: const Text(
                      'Contact your clinic from an appointment, or e-mail support@eazyclinic.example.',
                    ),
                  ),
                ],
              ),
            ),
            if (p['deletionRequest'] != null)
              EcInlineMessage(
                tone: EcStatusTone.info,
                message:
                    'Your account deletion request is ${(p['deletionRequest']! as Map)['status']}. Clinics keep medical records as the law requires.',
              )
            else
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  key: const Key('request-deletion'),
                  onPressed: () async {
                    final sure = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Request account deletion?'),
                        content: const Text(
                          'Nothing is deleted right away. Clinics keep medical records they are required to keep.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(false),
                            child: const Text('Not now'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(true),
                            child: const Text('Send request'),
                          ),
                        ],
                      ),
                    );
                    if (sure == true && context.mounted) {
                      await runAction(
                        context,
                        action: () => repo.send(
                          'POST',
                          '/patient/account/deletion-request',
                          {},
                        ),
                        success: 'Request sent.',
                        after: () => ref.invalidate(mapProvider),
                      );
                    }
                  },
                  child: const Text('Request account deletion'),
                ),
              ),
            const SizedBox(height: EcSpacing.md),
            sized(
              EcSecondaryButton(
                key: const Key('sign-out'),
                label: 'Sign out',
                icon: Icons.logout,
                onPressed: () async {
                  // stop pushes to this device before the session ends
                  await ref.read(pushRegistrarProvider).unregister();
                  await ref.read(authControllerProvider.notifier).signOut();
                },
              ),
              200,
            ),
          ],
        );
      },
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, Json p) async {
    final a = (p['address'] as Map?) ?? const {};
    final e = (p['emergencyContact'] as Map?) ?? const {};
    final v = await showFormDialog(
      context,
      title: 'Edit profile',
      note:
          'Name, date of birth, mobile and e-mail changes need verification and are not available here. Your clinics\' records are not changed by this.',
      initial: {
        'preferredLanguage': p['preferredLanguage'],
        'line1': a['line1'],
        'city': a['city'],
        'postalCode': a['postalCode'],
        'ecName': e['name'],
        'ecPhone': e['phone'],
        'ecRelationship': e['relationship'],
      },
      fields: const [
        FieldSpec(
          'preferredLanguage',
          'Language',
          kind: FieldKind.choice,
          options: ['en', 'hi', 'mr', 'ta', 'te', 'bn', 'gu', 'kn', 'ml', 'pa'],
        ),
        FieldSpec('line1', 'Address'),
        FieldSpec('city', 'City'),
        FieldSpec('postalCode', 'PIN code', maxLength: 10),
        FieldSpec('ecName', 'Emergency contact name'),
        FieldSpec('ecPhone', 'Emergency contact mobile', maxLength: 15),
        FieldSpec('ecRelationship', 'Relationship', maxLength: 40),
      ],
    );
    if (v == null || !context.mounted) return;
    final body = <String, Object?>{
      'preferredLanguage': ?v['preferredLanguage'],
      if (v['line1'] != null && v['city'] != null && v['postalCode'] != null)
        'address': {
          'line1': v['line1'],
          'city': v['city'],
          'postalCode': v['postalCode'],
        },
      if (v['ecName'] != null && v['ecPhone'] != null)
        'emergencyContact': {
          'name': v['ecName'],
          'phone': v['ecPhone'],
          'relationship': ?v['ecRelationship'],
        },
    };
    if (body.isEmpty) return;
    await runAction(
      context,
      action: () => ref
          .read(portalRepositoryProvider)
          .send('PATCH', '/patient/profile', body),
      success: 'Profile updated.',
      after: () => ref.invalidate(mapProvider),
    );
  }
}

// ------------------------------------------------------- privacy & consent

/// Consent decisions for one linked clinic. Each purpose is asked separately
/// and optional ones stay optional; nothing is assumed from registration.
class PrivacyPage extends ConsumerWidget {
  const PrivacyPage({required this.clinicId, super.key});

  final String clinicId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cat = Query('/patient/consent-catalog');
    final mine = Query('/patient/clinics/$clinicId/consents');
    final repo = ref.read(portalRepositoryProvider);
    return AsyncBody(
      value: ref.watch(mapProvider(cat)),
      onRetry: () => ref.invalidate(mapProvider(cat)),
      builder: (c) {
        final version = '${c['version']}';
        final purposes = ((c['purposes'] as List?) ?? const []).cast<Json>();
        return AsyncBody(
          value: ref.watch(listProvider(mine)),
          onRetry: () => ref.invalidate(listProvider(mine)),
          builder: (given) {
            Json? current(String type) {
              for (final g in given) {
                if (g['type'] == type && g['status'] == 'granted') return g;
              }
              return null;
            }

            return ListView(
              padding: const EdgeInsets.all(EcSpacing.lg),
              children: [
                const PageHeader(
                  title: 'Privacy and consent',
                  subtitle:
                      'Your choices for this clinic. Each one is recorded with its date and wording version. Showing these screens is not a claim of legal compliance.',
                ),
                for (final p in purposes)
                  Section(
                    title: '${p['purpose']}',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${p['text']}'),
                        const SizedBox(height: EcSpacing.sm),
                        if (current('${p['type']}') != null)
                          Row(
                            children: [
                              statusChip('granted'),
                              const SizedBox(width: EcSpacing.sm),
                              TextButton(
                                key: Key('withdraw-${p['type']}'),
                                onPressed: () => runAction(
                                  context,
                                  action: () => repo.send(
                                    'POST',
                                    '/patient/clinics/$clinicId/consents/${current('${p['type']}')!['consentId']}/revoke',
                                    {},
                                  ),
                                  success: 'Consent withdrawn.',
                                  after: () => ref.invalidate(listProvider),
                                ),
                                child: const Text('Withdraw'),
                              ),
                            ],
                          )
                        else
                          Wrap(
                            spacing: EcSpacing.sm,
                            children: [
                              TextButton(
                                key: Key('grant-${p['type']}'),
                                onPressed: () => runAction(
                                  context,
                                  action: () =>
                                      repo.send('POST', '/patient/consents', {
                                        'clinicId': clinicId,
                                        'type': p['type'],
                                        'decision': 'granted',
                                        'textVersion': version,
                                      }),
                                  success: 'Consent recorded.',
                                  after: () => ref.invalidate(listProvider),
                                ),
                                child: const Text('Allow'),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                Section(
                  title: 'History',
                  child: given.isEmpty
                      ? const Text('No decisions recorded.')
                      : Column(
                          children: [
                            for (final g in given)
                              ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                title: Text('${g['purpose']}'),
                                subtitle: Text(
                                  '${humanize(g['status'])} · version ${g['textVersion']} · ${shortDateTime(g['createdAt'])}',
                                ),
                              ),
                          ],
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
