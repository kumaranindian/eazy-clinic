import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/portal_repository.dart';
import 'providers.dart';

/// Chips to choose whose information is shown: me, or a family member the
/// backend lets me act for. The choice is only a selector.
class PersonBar extends ConsumerWidget {
  const PersonBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final family = ref.watch(listProvider(Query('/patient/family')));
    final selected = ref.watch(selectedPersonProvider);
    final people = [
      for (final f in family.asData?.value ?? const <Json>[])
        if (f['canActFor'] == true) f,
    ];
    if (people.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: EcSpacing.md),
      child: Wrap(
        spacing: EcSpacing.sm,
        children: [
          ChoiceChip(
            key: const Key('person-me'),
            label: const Text('Me'),
            selected: selected == null,
            onSelected: (_) =>
                ref.read(selectedPersonProvider.notifier).select(null),
          ),
          for (final f in people)
            ChoiceChip(
              key: Key('person-${f['otherAccountId']}'),
              label: Text('${f['otherName'] ?? 'Family member'}'),
              selected: selected == f['otherAccountId'],
              onSelected: (_) => ref
                  .read(selectedPersonProvider.notifier)
                  .select('${f['otherAccountId']}'),
            ),
        ],
      ),
    );
  }
}

/// Shown where records need a clinic link.
class LinkClinicHint extends StatelessWidget {
  const LinkClinicHint({super.key});

  @override
  Widget build(BuildContext context) => const EcEmptyState(
    title: 'No clinic linked yet',
    message:
        'Ask your clinic for a link code, then link it from the Clinics tab to see your records here.',
    icon: Icons.link_outlined,
  );
}
