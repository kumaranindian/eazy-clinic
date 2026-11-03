import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

/// Asks for a mandatory free-text reason. Returns it, or `null` if cancelled.
Future<String?> showReasonDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  String fieldLabel = 'Reason',
  int minLength = 3,
  bool destructive = false,
}) {
  return showDialog<String>(
    context: context,
    builder: (context) => _ReasonDialog(
      title: title,
      message: message,
      confirmLabel: confirmLabel,
      fieldLabel: fieldLabel,
      minLength: minLength,
      destructive: destructive,
    ),
  );
}

class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog({
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.fieldLabel,
    required this.minLength,
    required this.destructive,
  });

  final String title;
  final String message;
  final String confirmLabel;
  final String fieldLabel;
  final int minLength;
  final bool destructive;

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final _form = GlobalKey<FormState>();
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.message, style: EcTypography.bodySecondary),
              const SizedBox(height: EcSpacing.lg),
              EcTextField(
                label: widget.fieldLabel,
                controller: _text,
                maxLines: 3,
                maxLength: 500,
                validator: (v) => (v ?? '').trim().length < widget.minLength
                    ? '${widget.fieldLabel} is required (at least ${widget.minLength} characters).'
                    : null,
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
          style: widget.destructive
              ? FilledButton.styleFrom(backgroundColor: EcColors.error)
              : null,
          onPressed: () {
            if (_form.currentState!.validate()) {
              Navigator.of(context).pop(_text.text.trim());
            }
          },
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
