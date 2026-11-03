import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../control_plane/data/control_plane_repository.dart';

/// Shows the one-time invitation link. Delivery by e-mail/SMS is not
/// configured, so the administrator shares the link themselves; the dialog
/// says so plainly and never claims anything was sent.
Future<void> showInviteLinkDialog(BuildContext context, Json invitation) {
  String link;
  try {
    link = '${Uri.base.origin}${invitation['acceptPath']}';
  } on Object {
    link = '${invitation['acceptPath']}';
  }
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Invitation created'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const EcInlineMessage(
              tone: EcStatusTone.warning,
              message:
                  'No email or SMS was sent: delivery is not configured. Copy this link and send it to the invitee. It is shown only once and works for one person only.',
            ),
            const SizedBox(height: EcSpacing.lg),
            Text(
              'Invitee: ${invitation['email']}',
              style: EcTypography.bodyStrong,
            ),
            const SizedBox(height: EcSpacing.sm),
            SelectableText(
              link,
              key: const Key('invite-link'),
              style: EcTypography.body,
            ),
            const SizedBox(height: EcSpacing.sm),
            Text(
              'Expires ${invitation['expiresAt']}',
              style: EcTypography.helper,
            ),
            Text(
              'They must sign in (or register) with exactly this email address.',
              style: EcTypography.helper,
            ),
          ],
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: link));
            if (context.mounted) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('Link copied.')));
            }
          },
          icon: const Icon(Icons.copy, size: 18),
          label: const Text('Copy link'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ],
    ),
  );
}
