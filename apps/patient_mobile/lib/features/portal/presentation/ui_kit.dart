import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// `viral_fever` → `Viral fever`.
String humanize(Object? v) {
  final s = '${v ?? ''}'.replaceAll('_', ' ').trim();
  return s.isEmpty ? '—' : s[0].toUpperCase() + s.substring(1);
}

/// Minor units → localized money with the currency's decimals. Display only;
/// amounts come from the server.
String money(Object? minor, [Object? currency]) =>
    RegionalDisplay.money(minor, currency);

/// Date in the clinic's time zone and the user's language.
String shortDate(Object? iso, {String? timezone}) =>
    RegionalDisplay.date(iso, timezone: timezone);

String shortDateTime(Object? iso, {String? timezone}) =>
    RegionalDisplay.dateTime(iso, timezone: timezone);

EcStatusTone tone(Object? status) => switch (status) {
  'finalized' ||
  'completed' ||
  'verified' ||
  'confirmed' => EcStatusTone.success,
  'draft' ||
  'pending' ||
  'requested' ||
  'partially_paid' ||
  'overdue' ||
  'provisional' ||
  'unverified' ||
  'scheduled' => EcStatusTone.warning,
  'amended' || 'in_progress' || 'called' || 'checked_in' => EcStatusTone.info,
  'cancelled' || 'no_show' || 'missed' || 'removed' => EcStatusTone.error,
  _ => EcStatusTone.neutral,
};

Widget statusChip(Object? status) => Builder(
  builder: (context) => EcStatusChip(
    label: statusLabel(context.l10n, status),
    tone: tone(status),
  ),
);

String failureText(Object error) {
  if (error is! ApiFailure) return 'Something went wrong. Please try again.';
  if (error.issues.isEmpty) return error.displayMessage;
  return '${error.displayMessage} ${error.issues.map((i) => '${i.field}: ${i.message}').join(' · ')}';
}

/// Loading / error (with retry) / data for an [AsyncValue].
class AsyncBody<T> extends StatelessWidget {
  const AsyncBody({
    required this.value,
    required this.onRetry,
    required this.builder,
    super.key,
  });

  final AsyncValue<T> value;
  final VoidCallback onRetry;
  final Widget Function(T data) builder;

  @override
  Widget build(BuildContext context) => value.when(
    loading: () => const EcLoadingIndicator(),
    error: (e, _) => EcErrorState(
      title: e is ApiFailure && e.code?.httpStatus == 403
          ? 'Not permitted'
          : 'Could not load this page',
      message: e is ApiFailure ? e.displayMessage : 'Please try again.',
      onRetry: e is ApiFailure && e.code?.httpStatus == 403 ? null : onRetry,
    ),
    data: builder,
  );
}

/// Runs a backend action with success and error feedback.
Future<bool> runAction(
  BuildContext context, {
  required Future<Object?> Function() action,
  required String success,
  VoidCallback? after,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await action();
    messenger.showSnackBar(SnackBar(content: Text(success)));
    after?.call();
    return true;
  } on ApiFailure catch (e) {
    messenger.showSnackBar(
      SnackBar(content: Text(failureText(e)), backgroundColor: EcColors.error),
    );
    return false;
  }
}

class PageHeader extends StatelessWidget {
  const PageHeader({
    required this.title,
    this.subtitle,
    this.actions = const [],
    super.key,
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: EcSpacing.lg),
    child: Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: EcSpacing.md,
      runSpacing: EcSpacing.sm,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 200, maxWidth: 640),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: EcTypography.pageTitle),
              if (subtitle != null)
                Text(subtitle!, style: EcTypography.bodySecondary),
            ],
          ),
        ),
        ...actions,
      ],
    ),
  );
}

class Section extends StatelessWidget {
  const Section({
    required this.title,
    required this.child,
    this.trailing,
    super.key,
  });

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: EcSpacing.lg),
    child: EcCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(title, style: EcTypography.subsectionTitle)),
              ?trailing,
            ],
          ),
          const SizedBox(height: EcSpacing.md),
          child,
        ],
      ),
    ),
  );
}

class KeyValues extends StatelessWidget {
  const KeyValues(this.rows, {super.key});

  final List<(String, Object?)> rows;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (final (k, v) in rows)
        if (v != null && '$v'.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 160,
                  child: Text(k, style: EcTypography.bodySecondary),
                ),
                Expanded(child: Text('$v')),
              ],
            ),
          ),
    ],
  );
}

/// Gives a design-system button (which asks for unbounded width) the width
/// of its own content. [width] is only a lower bound.
Widget sized(Widget button, [double width = 0]) => ConstrainedBox(
  constraints: BoxConstraints(minWidth: width < 160 ? width : 160),
  child: IntrinsicWidth(child: button),
);

enum FieldKind { text, multiline, date, choice }

class FieldSpec {
  const FieldSpec(
    this.key,
    this.label, {
    this.kind = FieldKind.text,
    this.options = const [],
    this.required = false,
    this.maxLength = 200,
  });

  final String key;
  final String label;
  final FieldKind kind;
  final List<String> options;
  final bool required;
  final int maxLength;
}

final RegExp _isoDate = RegExp(r'^\d{4}-\d{2}-\d{2}$');

/// Small form dialog; returns the non-empty values or null when cancelled.
Future<Map<String, Object?>?> showFormDialog(
  BuildContext context, {
  required String title,
  required List<FieldSpec> fields,
  Map<String, Object?> initial = const {},
  String confirmLabel = 'Save',
  String? note,
}) => showDialog<Map<String, Object?>>(
  context: context,
  builder: (context) => _FormDialog(title, fields, initial, confirmLabel, note),
);

class _FormDialog extends StatefulWidget {
  const _FormDialog(
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
  State<_FormDialog> createState() => _FormDialogState();
}

class _FormDialogState extends State<_FormDialog> {
  final _form = GlobalKey<FormState>();
  late final Map<String, TextEditingController> _c = {
    for (final f in widget.fields)
      if (f.kind != FieldKind.choice)
        f.key: TextEditingController(text: '${widget.initial[f.key] ?? ''}'),
  };
  late final Map<String, String?> _choice = {
    for (final f in widget.fields)
      if (f.kind == FieldKind.choice) f.key: widget.initial[f.key] as String?,
  };

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
  Widget build(BuildContext context) => AlertDialog(
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
                EcInlineMessage(tone: EcStatusTone.info, message: widget.note!),
                const SizedBox(height: EcSpacing.md),
              ],
              for (final f in widget.fields)
                Padding(
                  padding: const EdgeInsets.only(bottom: EcSpacing.md),
                  child: f.kind == FieldKind.choice
                      ? EcDropdown<String>(
                          label: f.label,
                          items: f.options,
                          value: _choice[f.key],
                          itemLabel: humanize,
                          validator: (v) => f.required && v == null
                              ? '${f.label} is required.'
                              : null,
                          onChanged: (v) => setState(() => _choice[f.key] = v),
                        )
                      : EcTextField(
                          label: f.kind == FieldKind.date
                              ? '${f.label} (YYYY-MM-DD)'
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

/// Asks for a reason (at least 5 characters). Null when cancelled.
Future<String?> askReason(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Continue',
}) async {
  final r = await showFormDialog(
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
