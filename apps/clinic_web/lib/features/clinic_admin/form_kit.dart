import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

import '../shared/ui_helpers.dart';

/// Owns the text controllers of a form.
class FormFields {
  FormFields(Iterable<String> keys)
    : _c = {for (final k in keys) k: TextEditingController()};

  final Map<String, TextEditingController> _c;

  TextEditingController operator [](String key) => _c[key]!;

  String text(String key) => _c[key]!.text.trim();

  /// Null when empty (so optional fields are simply omitted).
  String? opt(String key) => text(key).isEmpty ? null : text(key);

  void set(String key, Object? value) =>
      _c[key]!.text = value == null ? '' : '$value';

  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
  }
}

String? requiredText(String? v, {int min = 1, String label = 'This field'}) =>
    (v ?? '').trim().length < min ? '$label is required.' : null;

String? wholeNumber(String? v, {bool optional = false, int? max}) {
  final t = (v ?? '').trim();
  if (t.isEmpty) return optional ? null : 'Required.';
  final n = int.tryParse(t);
  if (n == null || n < 0 || (max != null && n > max)) {
    return 'Enter a whole number${max == null ? '' : ' up to $max'}.';
  }
  return null;
}

class TextRow extends StatelessWidget {
  const TextRow({
    required this.label,
    required this.controller,
    this.validator,
    this.enabled = true,
    this.width = 300,
    this.maxLength = 200,
    this.lines = 1,
    this.type,
    super.key,
  });

  final String label;
  final TextEditingController controller;
  final String? Function(String?)? validator;
  final bool enabled;
  final double width;
  final int maxLength;
  final int lines;
  final TextInputType? type;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: EcTextField(
      label: label,
      controller: controller,
      validator: validator,
      enabled: enabled,
      maxLength: maxLength,
      maxLines: lines,
      keyboardType: type,
    ),
  );
}

String fmtTime(TimeOfDay t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

TimeOfDay? parseTime(Object? v) {
  if (v is! String) return null;
  final m = RegExp(r'^(\d{2}):(\d{2})$').firstMatch(v);
  return m == null
      ? null
      : TimeOfDay(hour: int.parse(m.group(1)!), minute: int.parse(m.group(2)!));
}

String fmtDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

const List<String> weekdayNames = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

class _Day {
  _Day({
    this.open = false,
    this.from = const TimeOfDay(hour: 9, minute: 0),
    this.to = const TimeOfDay(hour: 17, minute: 0),
    List<(TimeOfDay, TimeOfDay)>? breaks,
  }) : breaks = breaks ?? [];
  bool open;
  TimeOfDay from;
  TimeOfDay to;
  List<(TimeOfDay, TimeOfDay)> breaks;
}

/// Weekly operating-hours editor (Mon–Sun, multiple breaks, overnight allowed).
/// Reports the JSON the API expects through [onChanged].
class WeeklyHoursEditor extends StatefulWidget {
  const WeeklyHoursEditor({
    required this.initial,
    required this.onChanged,
    this.enabled = true,
    super.key,
  });

  final Map<String, Object?>? initial;
  final ValueChanged<Map<String, Object?>> onChanged;
  final bool enabled;

  @override
  State<WeeklyHoursEditor> createState() => _WeeklyHoursEditorState();
}

class _WeeklyHoursEditorState extends State<WeeklyHoursEditor> {
  late final Map<int, _Day> _days = {
    for (var d = 1; d <= 7; d++)
      d: _fromJson((widget.initial?['$d'] as Map?)?.cast<String, Object?>()),
  };

  _Day _fromJson(Map<String, Object?>? j) {
    if (j == null || j['open'] != true) return _Day();
    return _Day(
      open: true,
      from: parseTime(j['from']) ?? const TimeOfDay(hour: 9, minute: 0),
      to: parseTime(j['to']) ?? const TimeOfDay(hour: 17, minute: 0),
      breaks: [
        for (final b
            in ((j['breaks'] as List?) ?? const [])
                .cast<Map<String, Object?>>())
          (
            parseTime(b['from']) ?? const TimeOfDay(hour: 13, minute: 0),
            parseTime(b['to']) ?? const TimeOfDay(hour: 14, minute: 0),
          ),
      ],
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _emit());
  }

  void _emit() => widget.onChanged({
    for (final e in _days.entries)
      '${e.key}': e.value.open
          ? {
              'open': true,
              'from': fmtTime(e.value.from),
              'to': fmtTime(e.value.to),
              'breaks': [
                for (final b in e.value.breaks)
                  {'from': fmtTime(b.$1), 'to': fmtTime(b.$2)},
              ],
            }
          : {'open': false},
  });

  Future<TimeOfDay?> _pick(TimeOfDay initial) => showTimePicker(
    context: context,
    initialTime: initial,
    builder: (c, w) => MediaQuery(
      data: MediaQuery.of(c).copyWith(alwaysUse24HourFormat: true),
      child: w!,
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var d = 1; d <= 7; d++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: EcSpacing.xs),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: EcSpacing.md,
                  children: [
                    SizedBox(
                      width: 130,
                      child: SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: Text(
                          weekdayNames[d - 1],
                          style: EcTypography.bodyStrong,
                        ),
                        value: _days[d]!.open,
                        onChanged: widget.enabled
                            ? (v) => setState(() {
                                _days[d]!.open = v;
                                _emit();
                              })
                            : null,
                      ),
                    ),
                    if (_days[d]!.open) ...[
                      OutlinedButton(
                        onPressed: widget.enabled
                            ? () async {
                                final t = await _pick(_days[d]!.from);
                                if (t != null) {
                                  setState(() {
                                    _days[d]!.from = t;
                                    _emit();
                                  });
                                }
                              }
                            : null,
                        child: Text('Opens ${fmtTime(_days[d]!.from)}'),
                      ),
                      OutlinedButton(
                        onPressed: widget.enabled
                            ? () async {
                                final t = await _pick(_days[d]!.to);
                                if (t != null) {
                                  setState(() {
                                    _days[d]!.to = t;
                                    _emit();
                                  });
                                }
                              }
                            : null,
                        child: Text('Closes ${fmtTime(_days[d]!.to)}'),
                      ),
                      TextButton.icon(
                        onPressed: widget.enabled && _days[d]!.breaks.length < 5
                            ? () => setState(() {
                                _days[d]!.breaks.add((
                                  const TimeOfDay(hour: 13, minute: 0),
                                  const TimeOfDay(hour: 14, minute: 0),
                                ));
                                _emit();
                              })
                            : null,
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Add break'),
                      ),
                    ] else
                      Text('Closed', style: EcTypography.bodySecondary),
                  ],
                ),
                if (_days[d]!.open &&
                    _days[d]!.to.hour * 60 + _days[d]!.to.minute <
                        _days[d]!.from.hour * 60 + _days[d]!.from.minute)
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 4),
                    child: Text(
                      'Closes after midnight (overnight).',
                      style: EcTypography.helper,
                    ),
                  ),
                if (_days[d]!.open)
                  for (var i = 0; i < _days[d]!.breaks.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(left: 140),
                      child: Wrap(
                        spacing: EcSpacing.sm,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          const Text('Break'),
                          OutlinedButton(
                            onPressed: widget.enabled
                                ? () async {
                                    final t = await _pick(
                                      _days[d]!.breaks[i].$1,
                                    );
                                    if (t != null) {
                                      setState(() {
                                        _days[d]!.breaks[i] = (
                                          t,
                                          _days[d]!.breaks[i].$2,
                                        );
                                        _emit();
                                      });
                                    }
                                  }
                                : null,
                            child: Text(fmtTime(_days[d]!.breaks[i].$1)),
                          ),
                          const Text('to'),
                          OutlinedButton(
                            onPressed: widget.enabled
                                ? () async {
                                    final t = await _pick(
                                      _days[d]!.breaks[i].$2,
                                    );
                                    if (t != null) {
                                      setState(() {
                                        _days[d]!.breaks[i] = (
                                          _days[d]!.breaks[i].$1,
                                          t,
                                        );
                                        _emit();
                                      });
                                    }
                                  }
                                : null,
                            child: Text(fmtTime(_days[d]!.breaks[i].$2)),
                          ),
                          IconButton(
                            tooltip: 'Remove break',
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: widget.enabled
                                ? () => setState(() {
                                    _days[d]!.breaks.removeAt(i);
                                    _emit();
                                  })
                                : null,
                          ),
                        ],
                      ),
                    ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Small helper: shows `Fmt.humanize` text of a role wire name.
String roleLabel(Object? role) => Fmt.humanize(role);
