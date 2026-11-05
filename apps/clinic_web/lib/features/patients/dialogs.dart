import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

import '../shared/ui_helpers.dart';

enum FieldKind { text, multiline, date, choice, money }

/// One input of a record dialog.
class FieldSpec {
  const FieldSpec(
    this.key,
    this.label, {
    this.kind = FieldKind.text,
    this.options = const [],
    this.required = false,
    this.maxLength = 200,
    this.editable = true,
  });

  final String key;
  final String label;
  final FieldKind kind;
  final List<String> options;
  final bool required;
  final int maxLength;

  /// False for fields that cannot change after creation.
  final bool editable;
}

final RegExp _isoDate = RegExp(r'^\d{4}-\d{2}-\d{2}$');
final RegExp _money = RegExp(r'^\d{1,9}(\.\d{1,2})?$');

/// Generic form dialog; returns the non-empty values or null when cancelled.
Future<Map<String, Object?>?> showRecordDialog(
  BuildContext context, {
  required String title,
  required List<FieldSpec> fields,
  Map<String, Object?> initial = const {},
  String confirmLabel = 'Save',
  String? note,
}) {
  return showDialog<Map<String, Object?>>(
    context: context,
    builder: (context) =>
        _RecordDialog(title, fields, initial, confirmLabel, note),
  );
}

class _RecordDialog extends StatefulWidget {
  const _RecordDialog(
    this.title,
    this.fields,
    this.initial,
    this.confirmLabel,
    this.note,
  );

  final String title;
  final List<FieldSpec> fields;
  final Map<String, Object?> initial;
  final String confirmLabel;
  final String? note;

  @override
  State<_RecordDialog> createState() => _RecordDialogState();
}

class _RecordDialogState extends State<_RecordDialog> {
  final _form = GlobalKey<FormState>();
  late final Map<String, TextEditingController> _c;
  late final Map<String, String?> _choice;

  @override
  void initState() {
    super.initState();
    _c = {
      for (final f in widget.fields)
        if (f.kind != FieldKind.choice)
          f.key: TextEditingController(text: '${widget.initial[f.key] ?? ''}'),
    };
    _choice = {
      for (final f in widget.fields)
        if (f.kind == FieldKind.choice)
          f.key: widget.initial[f.key] as String? ?? (f.required ? null : null),
    };
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _submit() {
    if (!_form.currentState!.validate()) return;
    final out = <String, Object?>{};
    for (final f in widget.fields) {
      final v = f.kind == FieldKind.choice
          ? _choice[f.key]
          : _c[f.key]!.text.trim();
      if (v != null && v.isNotEmpty) out[f.key] = v;
    }
    Navigator.of(context).pop(out);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 460,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.note != null) ...[
                  EcInlineMessage(
                    tone: EcStatusTone.info,
                    message: widget.note!,
                  ),
                  const SizedBox(height: EcSpacing.md),
                ],
                for (final f in widget.fields)
                  if (f.editable || widget.initial[f.key] == null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: EcSpacing.md),
                      child: f.kind == FieldKind.choice
                          ? EcDropdown<String>(
                              label: f.label,
                              items: f.options,
                              value: _choice[f.key],
                              // wire values (snake_case) are made readable; free labels stay as given
                              itemLabel: (v) =>
                                  RegExp(r'^[a-z0-9_]+$').hasMatch(v)
                                  ? Fmt.humanize(v)
                                  : v,
                              validator: (v) => f.required && v == null
                                  ? '${f.label} is required.'
                                  : null,
                              onChanged: (v) =>
                                  setState(() => _choice[f.key] = v),
                            )
                          : EcTextField(
                              label: f.kind == FieldKind.date
                                  ? '${f.label} (YYYY-MM-DD)'
                                  : f.kind == FieldKind.money
                                  ? '${f.label} (${RegionalDisplay.currencyLabel()})'
                                  : f.label,
                              controller: _c[f.key],
                              maxLength: f.maxLength,
                              maxLines: f.kind == FieldKind.multiline ? 3 : 1,
                              validator: (v) {
                                final t = (v ?? '').trim();
                                if (t.isEmpty) {
                                  return f.required
                                      ? '${f.label} is required.'
                                      : null;
                                }
                                if (f.kind == FieldKind.date &&
                                    !_isoDate.hasMatch(t)) {
                                  return 'Use the format YYYY-MM-DD.';
                                }
                                if (f.kind == FieldKind.money &&
                                    (!_money.hasMatch(t.replaceAll(',', '')) ||
                                        double.parse(t.replaceAll(',', '')) <=
                                            0)) {
                                  return 'Enter an amount like 1250.50.';
                                }
                                return null;
                              },
                            ),
                    ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        EcPrimaryButton(
          label: widget.confirmLabel,
          compact: true,
          onPressed: _submit,
        ),
      ],
    );
  }
}

/// Asks for a reason (at least 5 characters). Null when cancelled.
Future<String?> askReason(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Continue',
}) async {
  final r = await showRecordDialog(
    context,
    title: title,
    note: message,
    confirmLabel: confirmLabel,
    fields: const [
      FieldSpec('reason', 'Reason', required: true, maxLength: 300),
    ],
  );
  final reason = r?['reason'] as String?;
  return reason != null && reason.length >= 5 ? reason : null;
}
