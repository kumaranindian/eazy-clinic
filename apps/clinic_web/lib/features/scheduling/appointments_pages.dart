import 'package:app_core/app_core.dart';
import 'package:common_models/common_models.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../clinic_admin/providers.dart';
import '../control_plane/data/control_plane_repository.dart';
import '../patients/dialogs.dart';
import '../shared/async_body.dart';
import '../shared/ui_helpers.dart';
import '../shared/ui_kit.dart';
import 'scheduling_providers.dart';

const _statuses = [
  'pending',
  'confirmed',
  'checked_in',
  'in_progress',
  'completed',
  'cancelled',
  'rescheduled',
  'no_show',
];

EcStatusTone _tone(Object? s) => switch (s) {
  'completed' => EcStatusTone.success,
  'cancelled' || 'no_show' => EcStatusTone.error,
  'rescheduled' || 'pending' => EcStatusTone.warning,
  'checked_in' || 'in_progress' => EcStatusTone.info,
  _ => EcStatusTone.neutral,
};

Widget apptStatus(Object? s) =>
    EcStatusChip(label: Fmt.humanize(s), tone: _tone(s));

String _monday(DateTime d) =>
    isoDate(d.subtract(Duration(days: d.weekday - 1)));

/// Appointments: day, week and month calendars plus a list. The backend does
/// all filtering, slot calculation and conflict marking; this page only shows
/// what it returns.
class AppointmentsPage extends ConsumerStatefulWidget {
  const AppointmentsPage({super.key});

  @override
  ConsumerState<AppointmentsPage> createState() => _AppointmentsState();
}

class _AppointmentsState extends ConsumerState<AppointmentsPage> {
  DateTime _date = DateTime.now();
  String _view = 'day';
  String? _doctor;
  String? _status;
  String? _branch;
  String _q = '';

  (String, String) get _range {
    switch (_view) {
      case 'week':
        final m = DateTime.parse('${_monday(_date)}T00:00:00');
        return (isoDate(m), isoDate(m.add(const Duration(days: 6))));
      case 'month':
        final first = DateTime(_date.year, _date.month);
        final last = DateTime(_date.year, _date.month + 1, 0);
        return (isoDate(first), isoDate(last));
      case 'list':
        return (isoDate(_date), isoDate(_date.add(const Duration(days: 13))));
      default:
        return (isoDate(_date), isoDate(_date));
    }
  }

  void _shift(int dir) => setState(() {
    _date = switch (_view) {
      'week' => _date.add(Duration(days: 7 * dir)),
      'month' => DateTime(_date.year, _date.month + dir, 1),
      'list' => _date.add(Duration(days: 14 * dir)),
      _ => _date.add(Duration(days: dir)),
    };
  });

  @override
  Widget build(BuildContext context) {
    final active = ref.watch(activeBranchProvider);
    final branchChoices =
        ref.watch(branchChoicesProvider).asData?.value ?? const <Json>[];
    final branch =
        _branch ??
        active ??
        (branchChoices.length == 1
            ? '${branchChoices.single['branchId']}'
            : null);
    final doctors =
        ref.watch(doctorChoicesProvider(branch)).asData?.value ??
        const <Json>[];
    final (from, to) = _range;
    final query = Query('/appointments', {
      'from': from,
      'to': to,
      'limit': '100',
      'branchId': branch ?? '',
      'doctorId': _doctor ?? '',
      'status': _status ?? '',
      'q': _q,
    });
    final data = ref.watch(listProvider(query));

    return ListView(
      padding: const EdgeInsets.all(EcSpacing.lg),
      children: [
        PageHeader(
          title: 'Appointments',
          subtitle:
              'Calendar and list of bookings. Slots and conflicts come from the server.',
          actions: [
            if (can(ref, ClinicPermission.appointmentsBook)) ...[
              EcPrimaryButton(
                label: 'Book appointment',
                icon: Icons.add,
                compact: true,
                onPressed: () => context.go('/clinic/appointments/new'),
              ),
              EcSecondaryButton(
                label: 'Walk-in',
                icon: Icons.directions_walk,
                compact: true,
                onPressed: () => context.go('/clinic/appointments/walk-in'),
              ),
            ],
          ],
        ),
        Wrap(
          spacing: EcSpacing.md,
          runSpacing: EcSpacing.md,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'day', label: Text('Day')),
                ButtonSegment(value: 'week', label: Text('Week')),
                ButtonSegment(value: 'month', label: Text('Month')),
                ButtonSegment(value: 'list', label: Text('List')),
              ],
              selected: {_view},
              onSelectionChanged: (s) => setState(() => _view = s.first),
            ),
            IconButton(
              tooltip: 'Previous',
              onPressed: () => _shift(-1),
              icon: const Icon(Icons.chevron_left),
            ),
            Text(
              _view == 'day'
                  ? Fmt.date('${isoDate(_date)}T00:00:00Z')
                  : '$from → $to',
              key: const Key('calendar-range'),
              style: EcTypography.bodyStrong,
            ),
            IconButton(
              tooltip: 'Next',
              onPressed: () => _shift(1),
              icon: const Icon(Icons.chevron_right),
            ),
            TextButton(
              onPressed: () => setState(() => _date = DateTime.now()),
              child: const Text('Today'),
            ),
          ],
        ),
        const SizedBox(height: EcSpacing.md),
        Wrap(
          spacing: EcSpacing.md,
          runSpacing: EcSpacing.md,
          children: [
            if (active == null)
              SizedBox(
                width: 220,
                child: EcDropdown<String>(
                  label: 'Branch',
                  items: [for (final b in branchChoices) '${b['branchId']}'],
                  value: _branch,
                  itemLabel: (id) =>
                      '${branchChoices.firstWhere((b) => b['branchId'] == id)['name']}',
                  onChanged: (v) => setState(() {
                    _branch = v;
                    _doctor = null;
                  }),
                ),
              ),
            SizedBox(
              width: 240,
              child: EcDropdown<String>(
                label: 'Doctor',
                items: [for (final d in doctors) '${d['doctorId']}'],
                value: doctors.any((d) => d['doctorId'] == _doctor)
                    ? _doctor
                    : null,
                itemLabel: (id) =>
                    '${doctors.firstWhere((d) => d['doctorId'] == id)['fullName']}',
                onChanged: (v) => setState(() => _doctor = v),
              ),
            ),
            SizedBox(
              width: 200,
              child: EcDropdown<String>(
                label: 'Status',
                items: _statuses,
                value: _status,
                itemLabel: Fmt.humanize,
                onChanged: (v) => setState(() => _status = v),
              ),
            ),
            SizedBox(
              width: 260,
              child: EcTextField(
                label: 'Search patient, MRN or reference',
                maxLength: 60,
                onChanged: (v) => setState(() => _q = v.trim()),
              ),
            ),
            if (_doctor != null || _status != null)
              TextButton(
                onPressed: () => setState(() {
                  _doctor = null;
                  _status = null;
                }),
                child: const Text('Clear filters'),
              ),
          ],
        ),
        const SizedBox(height: EcSpacing.lg),
        if (_view == 'day' && _doctor != null && branch != null)
          _DayAvailability(
            branch: branch,
            doctor: _doctor!,
            date: isoDate(_date),
          ),
        AsyncBody(
          value: data,
          onRetry: () => ref.invalidate(listProvider(query)),
          builder: (rows) => switch (_view) {
            'month' => _MonthGrid(
              rows: rows,
              month: _date,
              onPick: (d) => setState(() {
                _date = d;
                _view = 'day';
              }),
            ),
            'week' => _WeekColumns(rows: rows, start: _monday(_date)),
            _ => _AppointmentRows(rows: rows),
          },
        ),
      ],
    );
  }
}

/// Availability of one doctor on one day: open slots, breaks and blocks.
class _DayAvailability extends ConsumerWidget {
  const _DayAvailability({
    required this.branch,
    required this.doctor,
    required this.date,
  });

  final String branch;
  final String doctor;
  final String date;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final q = Query('/appointments/available-slots', {
      'branchId': branch,
      'doctorId': doctor,
      'date': date,
    });
    final v = ref.watch(slotsProvider(q));
    return v.when(
      loading: () => const SizedBox.shrink(),
      error: (e, _) => Padding(
        padding: const EdgeInsets.only(bottom: EcSpacing.md),
        child: EcInlineMessage(
          tone: EcStatusTone.info,
          message: e is ApiFailure
              ? e.displayMessage
              : 'No availability information.',
        ),
      ),
      data: (d) {
        final day = (d['day'] as Map?) ?? const {};
        final slots = ((d['slots'] as List?) ?? const [])
            .cast<Map<String, Object?>>();
        String ranges(Object? l) => ((l as List?) ?? const [])
            .map((e) => '${(e as Map)['from']}-${e['to']}')
            .join(', ');
        return Section(
          title: 'Availability',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (day['closed'] == true)
                EcInlineMessage(
                  tone: EcStatusTone.warning,
                  message: '${day['reason'] ?? 'Not available'}',
                )
              else ...[
                Text('Working: ${ranges(day['sessions'])}'),
                if ((day['breaks'] as List?)?.isNotEmpty ?? false)
                  Text(
                    'Breaks: ${ranges(day['breaks'])}',
                    style: EcTypography.bodySecondary,
                  ),
                if ((day['blocked'] as List?)?.isNotEmpty ?? false)
                  Text(
                    'Blocked: ${ranges(day['blocked'])}',
                    style: EcTypography.bodySecondary,
                  ),
                const SizedBox(height: EcSpacing.sm),
                Wrap(
                  spacing: EcSpacing.sm,
                  runSpacing: EcSpacing.sm,
                  children: [
                    for (final s in slots)
                      ActionChip(
                        label: Text('${s['startTime']}'),
                        onPressed: () => context.go(
                          '/clinic/appointments/new?branchId=$branch&doctorId=$doctor&date=$date&time=${s['startTime']}',
                        ),
                      ),
                    if (slots.isEmpty) const Text('No open slots.'),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

bool _overlap(Map<String, Object?> a, Map<String, Object?> b) =>
    a['localDate'] == b['localDate'] &&
    a['doctorId'] == b['doctorId'] &&
    '${a['startTime']}'.compareTo('${b['endTime']}') < 0 &&
    '${b['startTime']}'.compareTo('${a['endTime']}') < 0;

class _AppointmentRows extends StatelessWidget {
  const _AppointmentRows({required this.rows});

  final List<Json> rows;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return const EcEmptyState(
        title: 'No appointments',
        message: 'Nothing is booked for this period and filters.',
      );
    }
    final live = rows
        .where(
          (r) => !const {
            'cancelled',
            'rescheduled',
            'no_show',
          }.contains(r['status']),
        )
        .toList();
    return Column(
      children: [
        for (final a in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: EcSpacing.sm),
            child: EcCard(
              onTap: () =>
                  context.go('/clinic/appointments/${a['appointmentId']}'),
              child: Row(
                children: [
                  SizedBox(
                    width: 130,
                    child: Text(
                      '${a['localDate']}\n${a['startTime']}-${a['endTime']}',
                      style: EcTypography.bodyStrong,
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${a['patientName']} · ${a['patientMrn']}',
                          style: EcTypography.bodyStrong,
                        ),
                        Text(
                          '${a['doctorName']} · ${a['typeName']} · ${Fmt.humanize(a['source'])}${a['tokenDisplay'] == null ? '' : ' · token ${a['tokenDisplay']}'}',
                          style: EcTypography.bodySecondary,
                        ),
                      ],
                    ),
                  ),
                  if (a['needsAttention'] == true)
                    const Tooltip(
                      message: 'Needs attention: the doctor is unavailable',
                      child: Icon(Icons.warning_amber, color: EcColors.warning),
                    ),
                  if (live.any(
                    (o) => o != a && live.contains(a) && _overlap(a, o),
                  ))
                    const Tooltip(
                      message: 'Overlaps another appointment of this doctor',
                      child: Icon(Icons.error_outline, color: EcColors.error),
                    ),
                  const SizedBox(width: EcSpacing.sm),
                  apptStatus(a['status']),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _WeekColumns extends StatelessWidget {
  const _WeekColumns({required this.rows, required this.start});

  final List<Json> rows;
  final String start;

  @override
  Widget build(BuildContext context) {
    final days = [
      for (var i = 0; i < 7; i++)
        isoDate(DateTime.parse('${start}T00:00:00').add(Duration(days: i))),
    ];
    return Wrap(
      spacing: EcSpacing.sm,
      runSpacing: EcSpacing.sm,
      children: [
        for (final d in days)
          SizedBox(
            width: 220,
            child: EcCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    Fmt.date('${d}T00:00:00Z'),
                    style: EcTypography.bodyStrong,
                  ),
                  const Divider(),
                  for (final a
                      in rows.where((r) => r['localDate'] == d).take(12))
                    InkWell(
                      onTap: () => context.go(
                        '/clinic/appointments/${a['appointmentId']}',
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text(
                          '${a['startTime']} ${a['patientName']}${const {'cancelled', 'no_show', 'rescheduled'}.contains(a['status']) ? ' (${Fmt.humanize(a['status']).toLowerCase()})' : ''}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  if (rows.every((r) => r['localDate'] != d))
                    Text('—', style: EcTypography.bodySecondary),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.rows,
    required this.month,
    required this.onPick,
  });

  final List<Json> rows;
  final DateTime month;
  final void Function(DateTime) onPick;

  @override
  Widget build(BuildContext context) {
    final first = DateTime(month.year, month.month);
    final days = DateTime(month.year, month.month + 1, 0).day;
    final counts = <String, int>{};
    for (final r in rows) {
      if (!const {'cancelled', 'rescheduled'}.contains(r['status'])) {
        counts['${r['localDate']}'] = (counts['${r['localDate']}'] ?? 0) + 1;
      }
    }
    return Wrap(
      spacing: EcSpacing.sm,
      runSpacing: EcSpacing.sm,
      children: [
        for (var d = 1; d <= days; d++)
          SizedBox(
            width: 96,
            child: EcCard(
              onTap: () => onPick(DateTime(first.year, first.month, d)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('$d', style: EcTypography.bodyStrong),
                  Text(
                    '${counts[isoDate(DateTime(first.year, first.month, d))] ?? 0} booked',
                    style: EcTypography.helper,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------- patient search

/// Patient picker: type to search the directory (masked contact details).
class PatientPicker extends ConsumerStatefulWidget {
  const PatientPicker({required this.onPicked, this.selected, super.key});

  final void Function(Json patient) onPicked;
  final Json? selected;

  @override
  ConsumerState<PatientPicker> createState() => _PatientPickerState();
}

class _PatientPickerState extends ConsumerState<PatientPicker> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final results = _q.length < 2
        ? null
        : ref.watch(
            listProvider(
              Query('/patients', {'q': _q, 'limit': '8', 'status': 'active'}),
            ),
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.selected != null)
          EcInlineMessage(
            tone: EcStatusTone.success,
            message:
                'Patient: ${widget.selected!['fullName']} · ${widget.selected!['mrn']}',
          ),
        SizedBox(
          width: 360,
          child: EcTextField(
            label: widget.selected == null
                ? 'Find patient (name, MRN or phone)'
                : 'Change patient',
            maxLength: 60,
            onChanged: (v) => setState(() => _q = v.trim()),
          ),
        ),
        if (results != null)
          results.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(EcSpacing.sm),
              child: Text('Searching…'),
            ),
            error: (e, _) =>
                Text(e is ApiFailure ? e.displayMessage : 'Search failed.'),
            data: (rows) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (rows.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: EcSpacing.sm),
                    child: Row(
                      children: [
                        const Text('No patient found. '),
                        if (can(ref, ClinicPermission.patientsCreate))
                          TextButton(
                            onPressed: () => context.go('/clinic/patients/new'),
                            child: const Text('Register a new patient'),
                          ),
                      ],
                    ),
                  ),
                for (final p in rows)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text('${p['fullName']} · ${p['mrn']}'),
                    subtitle: Text('${p['dateOfBirth']} · ${p['maskedPhone']}'),
                    onTap: () {
                      widget.onPicked(p);
                      setState(() => _q = '');
                    },
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

// ------------------------------------------------------------------ booking

class BookAppointmentPage extends ConsumerStatefulWidget {
  const BookAppointmentPage({
    this.walkIn = false,
    this.initial = const {},
    super.key,
  });

  final bool walkIn;
  final Map<String, String> initial;

  @override
  ConsumerState<BookAppointmentPage> createState() => _BookState();
}

class _BookState extends ConsumerState<BookAppointmentPage> {
  Json? _patient;
  String? _branch;
  String? _doctor;
  String? _type;
  final _date = TextEditingController();
  String? _slot;
  String? _error;
  bool _busy = false;
  String _key = newIdempotencyKey();

  @override
  void initState() {
    super.initState();
    _branch = widget.initial['branchId'];
    _doctor = widget.initial['doctorId'];
    _slot = widget.initial['time'];
    _date.text =
        widget.initial['date'] ??
        isoDate(DateTime.now().add(const Duration(days: 1)));
    _date.addListener(
      () => setState(() {
        _slot = null;
        _key = newIdempotencyKey();
      }),
    );
    final pid = widget.initial['patientId'];
    if (pid != null) {
      ref.read(controlPlaneRepositoryProvider).getMap('/patients/$pid').then((
        p,
      ) {
        if (mounted) setState(() => _patient = p);
      });
    }
  }

  @override
  void dispose() {
    _date.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    final repo = ref.read(controlPlaneRepositoryProvider);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final body = <String, Object?>{
        'patientId': _patient!['patientId'],
        'doctorId': _doctor,
        'branchId': _branch,
        'typeId': _type,
        if (!widget.walkIn) ...{'date': _date.text.trim(), 'startTime': _slot},
      };
      final a = await repo.sendMap(
        'POST',
        widget.walkIn ? '/appointments/walk-in' : '/appointments',
        body,
        {'Idempotency-Key': _key},
      );
      if (!mounted) return;
      setState(() => _busy = false);
      ref.invalidate(listProvider);
      if (widget.walkIn) {
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Walk-in added'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Token'),
                Text(
                  '${a['tokenDisplay']}',
                  key: const Key('walk-in-token'),
                  style: EcTypography.pageTitle,
                ),
                Text('Seen around ${a['startTime']} by ${a['doctorName']}'),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Done'),
              ),
            ],
          ),
        );
        if (mounted) context.go('/clinic/queue');
      } else {
        context.go('/clinic/appointments/${a['appointmentId']}');
      }
    } on ApiFailure catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = failureText(e);
          // the slot may be gone: look again, with a fresh key
          _slot = null;
          _key = newIdempotencyKey();
        });
        ref.invalidate(slotsProvider);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final branches =
        ref
            .watch(branchChoicesProvider)
            .asData
            ?.value
            .where((b) => b['status'] == 'active')
            .toList() ??
        const <Json>[];
    final doctors =
        ref.watch(doctorChoicesProvider(_branch)).asData?.value ??
        const <Json>[];
    final types =
        ref.watch(appointmentTypeChoicesProvider).asData?.value ??
        const <Json>[];
    final ready =
        _patient != null && _branch != null && _doctor != null && _type != null;
    final dateOk = RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(_date.text.trim());
    final slotsQ = !widget.walkIn && ready && dateOk
        ? Query('/appointments/available-slots', {
            'branchId': _branch!,
            'doctorId': _doctor!,
            'date': _date.text.trim(),
            'typeId': _type!,
          })
        : null;
    return ListView(
      padding: const EdgeInsets.all(EcSpacing.lg),
      children: [
        PageHeader(
          title: widget.walkIn ? 'Walk-in patient' : 'Book appointment',
          subtitle: widget.walkIn
              ? 'Adds the patient to today\'s queue in the next free slot. A full day cannot be overbooked.'
              : 'Choose who, with whom and when. Available times come from the server.',
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: EcSpacing.lg),
            child: EcInlineMessage(message: _error!),
          ),
        Section(
          title: '1. Patient',
          child: PatientPicker(
            selected: _patient,
            onPicked: (p) => setState(() {
              _patient = p;
              _key = newIdempotencyKey();
            }),
          ),
        ),
        Section(
          title: '2. Branch, doctor and type',
          child: Wrap(
            spacing: EcSpacing.lg,
            runSpacing: EcSpacing.md,
            children: [
              SizedBox(
                width: 260,
                child: EcDropdown<String>(
                  label: 'Branch',
                  items: [for (final b in branches) '${b['branchId']}'],
                  value: _branch,
                  itemLabel: (id) =>
                      '${branches.firstWhere((b) => b['branchId'] == id)['name']}',
                  onChanged: (v) => setState(() {
                    _branch = v;
                    _doctor = null;
                    _slot = null;
                  }),
                ),
              ),
              SizedBox(
                width: 280,
                child: EcDropdown<String>(
                  label: 'Doctor',
                  items: [for (final d in doctors) '${d['doctorId']}'],
                  value: doctors.any((d) => d['doctorId'] == _doctor)
                      ? _doctor
                      : null,
                  itemLabel: (id) =>
                      '${doctors.firstWhere((d) => d['doctorId'] == id)['fullName']}',
                  onChanged: (v) => setState(() {
                    _doctor = v;
                    _slot = null;
                  }),
                ),
              ),
              SizedBox(
                width: 260,
                child: EcDropdown<String>(
                  label: 'Appointment type',
                  items: [for (final t in types) '${t['typeId']}'],
                  value: types.any((t) => t['typeId'] == _type) ? _type : null,
                  itemLabel: (id) =>
                      '${types.firstWhere((t) => t['typeId'] == id)['name']} (${types.firstWhere((t) => t['typeId'] == id)['durationMinutes']} min)',
                  onChanged: (v) => setState(() {
                    _type = v;
                    _slot = null;
                  }),
                ),
              ),
            ],
          ),
        ),
        if (!widget.walkIn)
          Section(
            title: '3. Date and time',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 220,
                  child: EcTextField(
                    label: 'Date (YYYY-MM-DD)',
                    controller: _date,
                    maxLength: 10,
                  ),
                ),
                const SizedBox(height: EcSpacing.md),
                if (slotsQ == null)
                  const Text(
                    'Choose a patient, branch, doctor, type and date to see times.',
                  )
                else
                  AsyncBody(
                    value: ref.watch(slotsProvider(slotsQ)),
                    onRetry: () => ref.invalidate(slotsProvider(slotsQ)),
                    builder: (d) {
                      final slots = ((d['slots'] as List?) ?? const [])
                          .cast<Map<String, Object?>>();
                      final day = (d['day'] as Map?) ?? const {};
                      if (slots.isEmpty) {
                        return EcInlineMessage(
                          tone: EcStatusTone.warning,
                          message: day['closed'] == true
                              ? '${day['reason'] ?? 'Not available.'}'
                              : 'No free times on this date.',
                        );
                      }
                      return Wrap(
                        spacing: EcSpacing.sm,
                        runSpacing: EcSpacing.sm,
                        children: [
                          for (final s in slots)
                            ChoiceChip(
                              label: Text('${s['startTime']}'),
                              selected: _slot == s['startTime'],
                              onSelected: (_) => setState(() {
                                _slot = '${s['startTime']}';
                                _key = newIdempotencyKey();
                              }),
                            ),
                        ],
                      );
                    },
                  ),
              ],
            ),
          ),
        Section(
          title: widget.walkIn ? '3. Review' : '4. Review and confirm',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (ready && (widget.walkIn || _slot != null))
                Text(
                  widget.walkIn
                      ? '${_patient!['fullName']} will be added to today\'s queue.'
                      : '${_patient!['fullName']} on ${_date.text.trim()} at $_slot.',
                  key: const Key('booking-review'),
                )
              else
                const Text('Complete the steps above.'),
              const SizedBox(height: EcSpacing.md),
              SizedBox(
                width: 240,
                child: EcPrimaryButton(
                  label: widget.walkIn ? 'Add walk-in' : 'Confirm booking',
                  isLoading: _busy,
                  onPressed: ready && (widget.walkIn || _slot != null)
                      ? _confirm
                      : null,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------------- detail

final appointmentProvider = FutureProvider.autoDispose.family<Json, String>(
  (ref, id) =>
      ref.watch(controlPlaneRepositoryProvider).getMap('/appointments/$id'),
  retry: (_, _) => null,
);

class AppointmentDetailPage extends ConsumerWidget {
  const AppointmentDetailPage({required this.appointmentId, super.key});

  final String appointmentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(appointmentProvider(appointmentId));
    void reload() {
      ref.invalidate(appointmentProvider(appointmentId));
      ref.invalidate(listProvider);
    }

    final repo = ref.read(controlPlaneRepositoryProvider);
    return AsyncBody(
      value: value,
      onRetry: reload,
      builder: (a) {
        final status = '${a['status']}';
        Future<void> act(String path, String done, {Json? body}) => runAction(
          context,
          action: () =>
              repo.sendMap('POST', '/appointments/$appointmentId/$path', body),
          success: done,
          after: reload,
        );
        Future<void> cancel() async {
          final reason = await askReason(
            context,
            title: 'Cancel appointment?',
            message: status == 'checked_in'
                ? 'The patient has checked in. Cancelling removes them from the queue.'
                : 'The slot becomes free again. The booking stays on record.',
            confirmLabel: 'Cancel appointment',
          );
          if (reason == null || !context.mounted) return;
          await act(
            'cancel',
            'Appointment cancelled.',
            body: {'reason': reason},
          );
        }

        final history = ((a['history'] as List?) ?? const [])
            .cast<Map<String, Object?>>();
        return ListView(
          padding: const EdgeInsets.all(EcSpacing.lg),
          children: [
            PageHeader(
              title: '${a['patientName']}',
              subtitle:
                  '${a['reference']} · ${a['localDate']} ${a['startTime']}-${a['endTime']}',
              actions: [
                apptStatus(status),
                if (status != 'cancelled' &&
                    status != 'no_show' &&
                    can(ref, ClinicPermission.billingCreate))
                  EcSecondaryButton(
                    label: 'Create invoice',
                    compact: true,
                    onPressed: () => context.go(
                      '/clinic/billing/invoices/new?appointmentId=${a['appointmentId']}'
                      '&patientId=${a['patientId']}'
                      '&patientName=${Uri.encodeQueryComponent('${a['patientName']}')}'
                      '&patientMrn=${a['patientMrn'] ?? ''}'
                      '&branchId=${a['branchId']}',
                    ),
                  ),
                if (status == 'pending' &&
                    can(ref, ClinicPermission.appointmentsManage))
                  EcPrimaryButton(
                    label: 'Confirm',
                    compact: true,
                    onPressed: () => act('confirm', 'Appointment confirmed.'),
                  ),
                if (status == 'confirmed' &&
                    can(ref, ClinicPermission.appointmentsCheckIn))
                  EcPrimaryButton(
                    label: 'Check in',
                    compact: true,
                    onPressed: () => act('check-in', 'Patient checked in.'),
                  ),
                if ((status == 'confirmed' || status == 'pending') &&
                    can(ref, ClinicPermission.appointmentsManage))
                  EcSecondaryButton(
                    label: 'Reschedule',
                    compact: true,
                    onPressed: () async {
                      final r = await showDialog<Map<String, Object?>>(
                        context: context,
                        builder: (context) => _RescheduleDialog(appointment: a),
                      );
                      if (r == null || !context.mounted) return;
                      try {
                        final n = await repo.sendMap(
                          'POST',
                          '/appointments/$appointmentId/reschedule',
                          r,
                        );
                        ref.invalidate(listProvider);
                        if (context.mounted) {
                          context.go(
                            '/clinic/appointments/${n['appointmentId']}',
                          );
                        }
                      } on ApiFailure catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(failureText(e)),
                              backgroundColor: EcColors.error,
                            ),
                          );
                        }
                      }
                    },
                  ),
                if (const {'pending', 'confirmed'}.contains(status) &&
                        can(ref, ClinicPermission.appointmentsManage) ||
                    status == 'checked_in' &&
                        can(ref, ClinicPermission.appointmentsCancelCheckedIn))
                  EcSecondaryButton(
                    label: 'Cancel',
                    compact: true,
                    onPressed: cancel,
                  ),
                if (status == 'confirmed' &&
                    can(ref, ClinicPermission.appointmentsManage))
                  EcSecondaryButton(
                    label: 'Mark no-show',
                    compact: true,
                    onPressed: () async {
                      final ok = await showEcConfirmDialog(
                        context,
                        title: 'Mark as no-show?',
                        message:
                            'The patient did not arrive. The slot is released.',
                        confirmLabel: 'Mark no-show',
                        destructive: true,
                      );
                      if (ok && context.mounted) {
                        await act('mark-no-show', 'Marked as no-show.');
                      }
                    },
                  ),
                if (status == 'in_progress' &&
                    can(ref, ClinicPermission.appointmentsConsult))
                  EcPrimaryButton(
                    label: 'Complete',
                    compact: true,
                    onPressed: () => act('complete', 'Appointment completed.'),
                  ),
                if (status == 'checked_in')
                  EcSecondaryButton(
                    label: 'Open queue',
                    compact: true,
                    onPressed: () => context.go('/clinic/queue'),
                  ),
              ],
            ),
            if (a['needsAttention'] == true)
              const Padding(
                padding: EdgeInsets.only(bottom: EcSpacing.lg),
                child: EcInlineMessage(
                  tone: EcStatusTone.warning,
                  message:
                      'The doctor is unavailable at this time. Reschedule or cancel the appointment.',
                ),
              ),
            Section(
              title: 'Appointment',
              child: KeyValues([
                ('Reference', a['reference']),
                ('Patient', '${a['patientName']} (${a['patientMrn']})'),
                ('Doctor', a['doctorName']),
                ('Type', '${a['typeName']} · ${a['durationMinutes']} min'),
                (
                  'When',
                  '${a['localDate']} ${a['startTime']}-${a['endTime']} (${a['timezone']})',
                ),
                ('Booked via', Fmt.humanize(a['source'])),
                ('Token', a['tokenDisplay']),
                ('Notes', a['notes']),
                if (a['cancelReason'] != null)
                  (
                    'Cancelled',
                    '${a['cancelReason']} (${Fmt.humanize(a['cancelSource'])})',
                  ),
                if (a['rescheduledToId'] != null)
                  ('Rescheduled to', a['rescheduledToId']),
                if (a['rescheduledFromId'] != null)
                  ('Rescheduled from', a['rescheduledFromId']),
              ]),
            ),
            Section(
              title: 'History',
              child: history.isEmpty
                  ? const Text('No history yet.')
                  : Column(
                      children: [
                        for (final h in history)
                          ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              Fmt.humanize(
                                '${h['action']}'.replaceAll('.', ' '),
                              ),
                            ),
                            subtitle: Text(
                              '${Fmt.dateTime(h['timestamp'])} · ${Fmt.humanize(h['actorRole'])}${h['reason'] == null ? '' : ' · ${h['reason']}'}',
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _RescheduleDialog extends ConsumerStatefulWidget {
  const _RescheduleDialog({required this.appointment});

  final Json appointment;

  @override
  ConsumerState<_RescheduleDialog> createState() => _RescheduleState();
}

class _RescheduleState extends ConsumerState<_RescheduleDialog> {
  final _date = TextEditingController();
  final _reason = TextEditingController();
  String? _slot;

  @override
  void initState() {
    super.initState();
    _date.text = '${widget.appointment['localDate']}';
    _date.addListener(() => setState(() => _slot = null));
    _reason.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _date.dispose();
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.appointment;
    final dateOk = RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(_date.text.trim());
    final q = dateOk
        ? Query('/appointments/available-slots', {
            'branchId': '${a['branchId']}',
            'doctorId': '${a['doctorId']}',
            'date': _date.text.trim(),
            'typeId': '${a['typeId']}',
          })
        : null;
    return AlertDialog(
      title: const Text('Reschedule appointment'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Now: ${a['localDate']} ${a['startTime']} with ${a['doctorName']}. The old booking is kept as history.',
              ),
              const SizedBox(height: EcSpacing.md),
              EcTextField(
                label: 'New date (YYYY-MM-DD)',
                controller: _date,
                maxLength: 10,
              ),
              const SizedBox(height: EcSpacing.md),
              if (q != null)
                ref
                    .watch(slotsProvider(q))
                    .when(
                      loading: () => const Text('Loading times…'),
                      error: (e, _) => Text(
                        e is ApiFailure
                            ? e.displayMessage
                            : 'Could not load times.',
                      ),
                      data: (d) {
                        final slots = ((d['slots'] as List?) ?? const [])
                            .cast<Map<String, Object?>>();
                        if (slots.isEmpty) {
                          return const Text('No free times on this date.');
                        }
                        return Wrap(
                          spacing: EcSpacing.sm,
                          children: [
                            for (final s in slots)
                              ChoiceChip(
                                label: Text('${s['startTime']}'),
                                selected: _slot == s['startTime'],
                                onSelected: (_) =>
                                    setState(() => _slot = '${s['startTime']}'),
                              ),
                          ],
                        );
                      },
                    ),
              const SizedBox(height: EcSpacing.md),
              EcTextField(label: 'Reason', controller: _reason, maxLength: 300),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        EcPrimaryButton(
          label: 'Reschedule',
          compact: true,
          onPressed: _slot == null || _reason.text.trim().length < 3
              ? null
              : () => Navigator.of(context).pop({
                  'date': _date.text.trim(),
                  'startTime': _slot,
                  'reason': _reason.text.trim(),
                }),
        ),
      ],
    );
  }
}
