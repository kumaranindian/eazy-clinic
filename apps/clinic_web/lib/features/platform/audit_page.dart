import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

import '../shared/ui_helpers.dart';
import '../shared/ui_kit.dart';

class AuditPage extends StatelessWidget {
  const AuditPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListScreen(
      title: 'Audit log',
      subtitle:
          'Append-only record of platform actions. Filter by clinic (tenant ID).',
      path: '/platform/audit-logs',
      searchHint: 'Filter by tenant ID',
      searchParam: 'tenantId',
      emptyTitle: 'No audit entries',
      emptyMessage: 'Platform actions will be listed here.',
      rowBuilder: (context, a) => EcCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(Fmt.humanize(a['action']), style: EcTypography.bodyStrong),
            Text(
              '${Fmt.dateTime(a['timestamp'])} · ${a['actorRole'] ?? 'system'} (${a['actorUid'] ?? '—'}) · ${a['targetType'] ?? ''} ${a['targetId'] ?? ''}',
              style: EcTypography.bodySecondary,
            ),
            if (a['reason'] != null)
              Text('Reason: ${a['reason']}', style: EcTypography.body),
          ],
        ),
      ),
    );
  }
}
