import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'common_widgets.dart';
import 'providers.dart';
import 'ui_kit.dart';

/// Today at a glance: next visit, what is owed, notifications and shortcuts.
class PatientHomePage extends ConsumerWidget {
  const PatientHomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final person = ref.watch(selectedPersonProvider);
    final profileQ = Query('/patient/profile');
    final apptQ = Query(
      '/patient/appointments',
      forPerson(person, {'filter': 'upcoming'}),
    );
    final billQ = Query('/patient/billing-summary', forPerson(person));
    final notesQ = Query('/patient/notifications');
    final profile = ref.watch(mapProvider(profileQ)).asData?.value;
    final linked = ((profile?['linkedClinics'] as List?) ?? const []).length;
    return ListView(
      padding: const EdgeInsets.all(EcSpacing.lg),
      children: [
        PageHeader(
          title:
              'Hello${profile == null ? '' : ', ${profile['displayName'] ?? ''}'}',
          subtitle: 'Your care in one place.',
          actions: [
            Consumer(
              builder: (context, ref, _) {
                final n = ref.watch(mapProvider(notesQ)).asData?.value;
                final unread = (n?['unread'] as int?) ?? 0;
                return IconButton(
                  key: const Key('open-notifications'),
                  tooltip: 'Notifications',
                  onPressed: () => context.go('/notifications'),
                  icon: Badge(
                    isLabelVisible: unread > 0,
                    label: Text('$unread'),
                    child: const Icon(Icons.notifications_outlined),
                  ),
                );
              },
            ),
          ],
        ),
        const PersonBar(),
        if (profile != null &&
            (profile['profileCompletion'] as int? ?? 100) < 100)
          EcInlineMessage(
            tone: EcStatusTone.info,
            message:
                'Your profile is ${profile['profileCompletion']}% complete. Add the missing details in Profile.',
          ),
        if (linked == 0) ...[
          const LinkClinicHint(),
          Align(
            child: sized(
              EcPrimaryButton(
                label: 'Find or link a clinic',
                onPressed: () => context.go('/clinics'),
              ),
              240,
            ),
          ),
        ] else ...[
          Section(
            title: 'Next appointment',
            trailing: sized(
              EcSecondaryButton(
                label: 'Book',
                icon: Icons.add,
                onPressed: () => context.go('/appointments/new'),
              ),
              120,
            ),
            child: AsyncBody(
              value: ref.watch(listProvider(apptQ)),
              onRetry: () => ref.invalidate(listProvider(apptQ)),
              builder: (rows) {
                if (rows.isEmpty) {
                  return const Text('No upcoming appointments.');
                }
                final a = rows.last;
                return ListTile(
                  key: const Key('next-appointment'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    '${a['doctorName']} · ${shortDate(a['localDate'])} ${a['startTime']}',
                  ),
                  subtitle: Text('${a['clinicName'] ?? ''}'),
                  trailing: statusChip(a['status']),
                  onTap: () => context.go(
                    '/appointments/${a['clinicId']}/${a['appointmentId']}${person == null ? '' : '?accountId=$person'}',
                  ),
                );
              },
            ),
          ),
          Section(
            title: 'Bills',
            child: AsyncBody(
              value: ref.watch(listProvider(billQ)),
              onRetry: () => ref.invalidate(listProvider(billQ)),
              builder: (rows) {
                final owed = rows.fold<int>(
                  0,
                  (a, r) => a + ((r['outstanding'] as int?) ?? 0),
                );
                return Row(
                  children: [
                    Expanded(
                      child: Text(
                        owed == 0 ? 'Nothing is due.' : '${money(owed)} due',
                        key: const Key('home-owed'),
                      ),
                    ),
                    TextButton(
                      onPressed: () => context.go('/records?tab=bills'),
                      child: const Text('View bills'),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
        Section(
          title: 'Quick links',
          child: Wrap(
            spacing: EcSpacing.sm,
            runSpacing: EcSpacing.sm,
            children: [
              ActionChip(
                label: const Text('Prescriptions'),
                onPressed: () => context.go('/records?tab=prescriptions'),
              ),
              ActionChip(
                label: const Text('Visit summaries'),
                onPressed: () => context.go('/records?tab=visits'),
              ),
              ActionChip(
                label: const Text('Family'),
                onPressed: () => context.go('/family'),
              ),
              ActionChip(
                label: const Text('Privacy & consent'),
                onPressed: () => context.go('/profile'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
