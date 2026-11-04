import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../control_plane/data/control_plane_repository.dart';
import '../shared/async_body.dart';
import '../shared/ui_helpers.dart';

/// Rupees typed by a person → minor units (paise). `null` when invalid. The
/// backend validates again and does all calculations; this only converts input.
int? parseMinor(String? v) {
  final t = (v ?? '').trim().replaceAll(',', '');
  final m = RegExp(r'^(\d{1,9})(?:\.(\d{1,2}))?$').firstMatch(t);
  if (m == null) return null;
  final whole = int.parse(m.group(1)!);
  final frac = int.parse((m.group(2) ?? '').padRight(2, '0'));
  return whole * 100 + frac;
}

/// Minor units → text for an input field (`125050` → `1250.50`).
String minorToInput(Object? minor) {
  if (minor is! int) return '';
  return '${minor ~/ 100}.${(minor % 100).toString().padLeft(2, '0')}';
}

/// Percent typed by a person → basis points (`2.5` → `250`).
int? parseBps(String? v) {
  final t = (v ?? '').trim();
  final m = RegExp(r'^(\d{1,3})(?:\.(\d{1,2}))?$').firstMatch(t);
  if (m == null) return null;
  final bps =
      int.parse(m.group(1)!) * 100 +
      int.parse((m.group(2) ?? '').padRight(2, '0'));
  return bps > 10000 ? null : bps;
}

String bpsText(Object? bps) => bps is int
    ? '${(bps / 100).toStringAsFixed(bps % 100 == 0 ? 0 : 2)}%'
    : '—';

/// Gives a design-system button (which asks for unbounded width) the width of
/// its own content.
Widget sized(Widget button, [double minWidth = 0]) => ConstrainedBox(
  constraints: BoxConstraints(minWidth: minWidth),
  child: IntrinsicWidth(child: button),
);

/// One figure of a dashboard or summary.
class MoneyTile extends StatelessWidget {
  const MoneyTile(
    this.label,
    this.minor, {
    this.currency,
    this.tileKey,
    super.key,
  });

  final String label;
  final Object? minor;
  final Object? currency;
  final String? tileKey;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 220,
    child: EcCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            Fmt.money(minor, currency),
            key: tileKey == null ? null : Key(tileKey!),
            style: EcTypography.sectionTitle,
          ),
          const SizedBox(height: 2),
          Text(label, style: EcTypography.bodySecondary),
        ],
      ),
    ),
  );
}

/// Finds a patient by name, number or phone. Returns the patient row.
Future<Map<String, Object?>?> pickPatient(BuildContext context) =>
    showDialog<Map<String, Object?>>(
      context: context,
      builder: (_) => const _PatientPicker(),
    );

class _PatientPicker extends ConsumerStatefulWidget {
  const _PatientPicker();

  @override
  ConsumerState<_PatientPicker> createState() => _PatientPickerState();
}

class _PatientPickerState extends ConsumerState<_PatientPicker> {
  final _q = TextEditingController();
  List<Map<String, Object?>>? _rows;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final rows = await ref.read(controlPlaneRepositoryProvider).getList(
        '/patients',
        {'q': _q.text.trim(), 'limit': '10'},
      );
      if (mounted) setState(() => _rows = rows);
    } on ApiFailure catch (e) {
      if (mounted) setState(() => _error = failureText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Find patient'),
    content: SizedBox(
      width: 460,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: EcTextField(
                  label: 'Name, patient number or phone',
                  controller: _q,
                  onSubmitted: (_) => _search(),
                ),
              ),
              const SizedBox(width: EcSpacing.sm),
              IconButton(
                tooltip: 'Search',
                onPressed: _busy ? null : _search,
                icon: const Icon(Icons.search),
              ),
            ],
          ),
          if (_error != null)
            EcInlineMessage(tone: EcStatusTone.error, message: _error!),
          if (_rows != null && _rows!.isEmpty) const Text('No patients found.'),
          if (_rows != null)
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final p in _rows!)
                    ListTile(
                      key: Key('pick-${p['patientId']}'),
                      title: Text('${p['fullName']}'),
                      subtitle: Text('${p['mrn'] ?? ''}'),
                      onTap: () => Navigator.of(context).pop(p),
                    ),
                ],
              ),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
    ],
  );
}
