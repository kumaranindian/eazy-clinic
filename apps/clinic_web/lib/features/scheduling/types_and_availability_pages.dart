import 'package:app_core/app_core.dart';
import 'package:common_models/common_models.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../clinic_admin/providers.dart';
import '../control_plane/data/control_plane_repository.dart';
import '../patients/dialogs.dart';
import '../shared/async_body.dart';
import '../shared/paged_list.dart';
import '../shared/ui_helpers.dart';
import '../shared/ui_kit.dart';
import 'scheduling_providers.dart';

// ------------------------------------------------------ appointment types

class AppointmentTypesPage extends ConsumerWidget {
  const AppointmentTypesPage({super.key});

  static const _fields = [
    FieldSpec('name', 'Name', required: true, maxLength: 60),
    FieldSpec('description', 'Description', maxLength: 300),
    FieldSpec(
      'durationMinutes',
      'Duration (minutes)',
      required: true,
      maxLength: 3,
    ),
    FieldSpec('bufferMinutes', 'Buffer after (minutes)', maxLength: 3),
    FieldSpec('defaultFeeMinor', 'Default fee (paise, optional)', maxLength: 9),
  ];

  Map<String, Object?> _body(Map<String, Object?> r) => {
    for (final e in r.entries)
      e.key:
          [
            'durationMinutes',
            'bufferMinutes',
            'defaultFeeMinor',
          ].contains(e.key)
          ? int.tryParse('${e.value}') ?? e.value
          : e.value,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(controlPlaneRepositoryProvider);
    final manage = can(ref, ClinicPermission.appointmentTypesManage);
    void reload() {
      ref.invalidate(pagedListProvider);
      ref.invalidate(appointmentTypeChoicesProvider);
    }

    return ListScreen(
      title: 'Appointment types',
      subtitle:
          'Visit kinds with their duration and buffer. Slots are built from these.',
      path: '/appointment-types',
      statusOptions: const ['active', 'inactive'],
      emptyTitle: 'No appointment types yet',
      emptyMessage: 'Add a type such as "General consultation" before booking.',
      actions: [
        if (manage)
          EcPrimaryButton(
            label: 'New type',
            icon: Icons.add,
            compact: true,
            onPressed: () async {
              final r = await showRecordDialog(
                context,
                title: 'New appointment type',
                fields: _fields,
                confirmLabel: 'Create',
              );
              if (r == null || !context.mounted) return;
              await runAction(
                context,
                action: () =>
                    repo.sendMap('POST', '/appointment-types', _body(r)),
                success: 'Appointment type created.',
                after: reload,
              );
            },
          ),
      ],
      rowBuilder: (context, t) => RowCard(
        title: '${t['name']}',
        subtitle:
            '${t['durationMinutes']} min${(t['bufferMinutes'] ?? 0) == 0 ? '' : ' + ${t['bufferMinutes']} min buffer'}${t['description'] == null ? '' : ' · ${t['description']}'}',
        status: t['status'],
        onTap: !manage
            ? () {}
            : () async {
                final active = t['status'] == 'active';
                final choice = await showDialog<String>(
                  context: context,
                  builder: (context) => SimpleDialog(
                    title: Text('${t['name']}'),
                    children: [
                      SimpleDialogOption(
                        onPressed: () => Navigator.of(context).pop('edit'),
                        child: const Text('Edit'),
                      ),
                      SimpleDialogOption(
                        onPressed: () => Navigator.of(
                          context,
                        ).pop(active ? 'deactivate' : 'activate'),
                        child: Text(active ? 'Deactivate' : 'Activate'),
                      ),
                    ],
                  ),
                );
                if (choice == null || !context.mounted) return;
                if (choice == 'edit') {
                  final r = await showRecordDialog(
                    context,
                    title: 'Edit appointment type',
                    fields: _fields,
                    initial: t,
                  );
                  if (r == null || !context.mounted) return;
                  await runAction(
                    context,
                    action: () => repo.sendMap(
                      'PATCH',
                      '/appointment-types/${t['typeId']}',
                      _body(r),
                    ),
                    success: 'Appointment type updated.',
                    after: reload,
                  );
                } else {
                  await runAction(
                    context,
                    action: () => repo.sendMap(
                      'POST',
                      '/appointment-types/${t['typeId']}/$choice',
                    ),
                    success: 'Appointment type ${choice}d.',
                    after: reload,
                  );
                }
              },
      ),
    );
  }
}

// ------------------------------------------------------------ availability

const _dayNames = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

/// "09:00-13:00, 17:00-20:00" → [{from,to}…]; null when malformed.
List<Map<String, String>>? parseRanges(String text) {
  final t = text.trim();
  if (t.isEmpty) return [];
  final out = <Map<String, String>>[];
  for (final part in t.split(',')) {
    final m = RegExp(
      r'^\s*(\d{2}:\d{2})\s*-\s*(\d{2}:\d{2})\s*$',
    ).firstMatch(part);
    if (m == null) return null;
    out.add({'from': m.group(1)!, 'to': m.group(2)!});
  }
  return out;
}

String formatRanges(Object? raw) => [
  for (final e in (raw as List? ?? const []))
    '${(e as Map)['from']}-${e['to']}',
].join(', ');

/// Doctor schedules per branch, the weekly editor, and leave/holidays.
class AvailabilityPage extends ConsumerStatefulWidget {
  const AvailabilityPage({super.key});

  @override
  ConsumerState<AvailabilityPage> createState() => _AvailabilityState();
}

class _AvailabilityState extends ConsumerState<AvailabilityPage> {
  String? _doctor;
  String? _branch;

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
    final manage =
        can(ref, ClinicPermission.availabilityManage) ||
        can(ref, ClinicPermission.availabilityManageOwn);
    final repo = ref.read(controlPlaneRepositoryProvider);
    final schedQ = _doctor == null
        ? null
        : Query('/doctors/$_doctor/availability', {'limit': '50'});
    final excQ = _doctor == null
        ? null
        : Query('/doctors/$_doctor/schedule-exceptions', {
            'limit': '50',
            'from': isoDate(DateTime.now()),
          });
    final holidayQ = _branch == null
        ? null
        : Query('/schedule-exceptions', {
            'limit': '50',
            'branchId': _branch!,
            'from': isoDate(DateTime.now()),
          });

    void reload() {
      ref.invalidate(listProvider);
    }

    Future<void> editSchedule(Json? existing) async {
      final result = await showDialog<Map<String, Object?>>(
        context: context,
        builder: (context) => _WeeklyDialog(
          existing: existing,
          branches: branches,
          branch: _branch,
        ),
      );
      if (result == null || !context.mounted) return;
      await runAction(
        context,
        action: () => existing == null
            ? repo.sendMap('POST', '/doctors/$_doctor/availability', result)
            : repo.sendMap(
                'PATCH',
                '/doctors/$_doctor/availability/${existing['scheduleId']}',
                result,
              ),
        success: 'Schedule saved.',
        after: reload,
      );
    }

    Future<void> addException({required bool branchWide}) async {
      final branchId =
          _branch ??
          (branches.length == 1 ? '${branches.single['branchId']}' : null);
      if (branchId == null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Choose a branch first.')));
        return;
      }
      final r = await showRecordDialog(
        context,
        title: branchWide
            ? 'Branch holiday or closure'
            : 'Doctor leave or special hours',
        confirmLabel: 'Add',
        note:
            'Existing appointments in the period are not cancelled: they are listed so you can reschedule or cancel them yourself.',
        fields: [
          FieldSpec(
            'type',
            'Type',
            kind: FieldKind.choice,
            required: true,
            options: branchWide
                ? const [
                    'clinic_holiday',
                    'branch_closure',
                    'emergency_unavailability',
                  ]
                : const [
                    'doctor_leave',
                    'personal_leave',
                    'sick_leave',
                    'emergency_unavailability',
                    'special_working_day',
                  ],
          ),
          const FieldSpec(
            'startDate',
            'First day',
            kind: FieldKind.date,
            required: true,
          ),
          const FieldSpec(
            'endDate',
            'Last day (optional)',
            kind: FieldKind.date,
          ),
          const FieldSpec(
            'fromTime',
            'Only from (HH:MM, optional)',
            maxLength: 5,
          ),
          const FieldSpec(
            'toTime',
            'Only until (HH:MM, optional)',
            maxLength: 5,
          ),
          if (!branchWide)
            const FieldSpec(
              'sessions',
              'Working hours for a special day (09:00-13:00)',
              maxLength: 80,
            ),
          const FieldSpec('reason', 'Reason', required: true, maxLength: 300),
        ],
      );
      if (r == null || !context.mounted) return;
      final body = <String, Object?>{
        'branchId': branchId,
        'type': r['type'],
        'startDate': r['startDate'],
        'endDate': r['endDate'] ?? r['startDate'],
        'reason': r['reason'],
        if (r['fromTime'] != null && r['toTime'] != null) ...{
          'fullDay': false,
          'fromTime': r['fromTime'],
          'toTime': r['toTime'],
        },
        if (r['sessions'] != null) 'sessions': parseRanges('${r['sessions']}'),
      };
      try {
        final out = await repo.sendMap(
          'POST',
          branchWide
              ? '/schedule-exceptions'
              : '/doctors/$_doctor/schedule-exceptions',
          body,
        );
        reload();
        final affected = (out['affectedAppointments'] as List?) ?? const [];
        if (affected.isNotEmpty && context.mounted) {
          await showDialog<void>(
            context: context,
            builder: (context) => AlertDialog(
              title: Text('${affected.length} appointment(s) need attention'),
              content: SizedBox(
                width: 460,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const EcInlineMessage(
                      tone: EcStatusTone.warning,
                      message:
                          'They are still booked. Open each one to reschedule or cancel it.',
                    ),
                    const SizedBox(height: EcSpacing.md),
                    for (final a in affected.cast<Map<String, Object?>>())
                      Text(
                        '${a['localDate']} ${a['startTime']} · ${a['patientName']} · ${a['reference']}',
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
              ],
            ),
          );
        } else if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Saved.')));
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
    }

    return ListView(
      padding: const EdgeInsets.all(EcSpacing.lg),
      children: [
        const PageHeader(
          title: 'Doctor availability',
          subtitle:
              'Weekly hours per branch, leave, holidays and special days.',
        ),
        Wrap(
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
                onChanged: (v) => setState(() => _doctor = v),
              ),
            ),
          ],
        ),
        const SizedBox(height: EcSpacing.lg),
        if (_doctor == null)
          const EcEmptyState(
            title: 'Choose a doctor',
            message:
                'Pick a branch and a doctor to see or edit their schedule.',
          )
        else ...[
          Section(
            title: 'Weekly schedules',
            trailing: manage
                ? SizedBox(
                    width: 300,
                    child: EcPrimaryButton(
                      label: 'New schedule',
                      compact: true,
                      icon: Icons.add,
                      onPressed: () => editSchedule(null),
                    ),
                  )
                : null,
            child: AsyncBody(
              value: ref.watch(listProvider(schedQ!)),
              onRetry: () => ref.invalidate(listProvider(schedQ)),
              builder: (rows) => rows.isEmpty
                  ? const Text('No schedule yet: this doctor cannot be booked.')
                  : Column(
                      children: [
                        for (final s in rows)
                          Padding(
                            padding: const EdgeInsets.only(
                              bottom: EcSpacing.sm,
                            ),
                            child: EcCard(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          '${_branchName(branches, s['branchId'])} · from ${s['effectiveFrom']}${s['effectiveTo'] == null ? '' : ' to ${s['effectiveTo']}'}',
                                          style: EcTypography.bodyStrong,
                                        ),
                                      ),
                                      statusChip(s['status']),
                                    ],
                                  ),
                                  for (var d = 1; d <= 7; d++)
                                    Text(
                                      '${_dayNames[d - 1]}: ${_dayText(s, d)}',
                                      style: EcTypography.bodySecondary,
                                    ),
                                  Text(
                                    'Default ${s['defaultDurationMinutes']} min, buffer ${s['bufferMinutes']} min, ${s['maxPerSlot']} per slot · ${s['timezone']}',
                                    style: EcTypography.helper,
                                  ),
                                  if (manage && s['status'] == 'active')
                                    Row(
                                      children: [
                                        TextButton(
                                          onPressed: () => editSchedule(s),
                                          child: const Text('Edit'),
                                        ),
                                        TextButton(
                                          onPressed: () async {
                                            final ok = await showEcConfirmDialog(
                                              context,
                                              title: 'End this schedule?',
                                              message:
                                                  'The doctor cannot be booked for these dates any more. The schedule is kept as history.',
                                              confirmLabel: 'End schedule',
                                              destructive: true,
                                            );
                                            if (!ok || !context.mounted) return;
                                            await runAction(
                                              context,
                                              action: () => repo
                                                  .deleteAt(
                                                    '/doctors/$_doctor/availability/${s['scheduleId']}',
                                                  )
                                                  .then((_) {}),
                                              success: 'Schedule ended.',
                                              after: reload,
                                            );
                                          },
                                          child: const Text('End schedule'),
                                        ),
                                      ],
                                    ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
          ),
          Section(
            title: 'Leave and special days',
            trailing: manage
                ? SizedBox(
                    width: 300,
                    child: EcSecondaryButton(
                      label: 'Add leave',
                      compact: true,
                      icon: Icons.event_busy,
                      onPressed: () => addException(branchWide: false),
                    ),
                  )
                : null,
            child: _ExceptionList(
              query: excQ!,
              manage: manage,
              doctorId: _doctor,
              onChanged: reload,
            ),
          ),
        ],
        if (_branch != null)
          Section(
            title: 'Branch holidays and closures',
            trailing: can(ref, ClinicPermission.availabilityManage)
                ? SizedBox(
                    width: 300,
                    child: EcSecondaryButton(
                      label: 'Add holiday',
                      compact: true,
                      icon: Icons.beach_access_outlined,
                      onPressed: () => addException(branchWide: true),
                    ),
                  )
                : null,
            child: _ExceptionList(
              query: holidayQ!,
              manage: can(ref, ClinicPermission.availabilityManage),
              doctorId: null,
              onChanged: reload,
            ),
          ),
      ],
    );
  }

  static String _branchName(List<Json> branches, Object? id) {
    for (final b in branches) {
      if (b['branchId'] == id) return '${b['name']}';
    }
    return '$id';
  }

  static String _dayText(Json s, int d) {
    final day = (s['weeklyHours'] as Map?)?['$d'] as Map?;
    final sessions = formatRanges(day?['sessions']);
    if (sessions.isEmpty) return 'closed';
    final breaks = formatRanges(day?['breaks']);
    return breaks.isEmpty ? sessions : '$sessions (breaks $breaks)';
  }
}

class _ExceptionList extends ConsumerWidget {
  const _ExceptionList({
    required this.query,
    required this.manage,
    required this.doctorId,
    required this.onChanged,
  });

  final Query query;
  final bool manage;
  final String? doctorId;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(controlPlaneRepositoryProvider);
    return AsyncBody(
      value: ref.watch(listProvider(query)),
      onRetry: () => ref.invalidate(listProvider(query)),
      builder: (rows) {
        final active = rows.where((e) => e['status'] == 'active').toList();
        if (active.isEmpty) return const Text('Nothing upcoming.');
        return Column(
          children: [
            for (final e in active)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  '${Fmt.humanize(e['type'])}: ${e['startDate']}${e['endDate'] == e['startDate'] ? '' : ' to ${e['endDate']}'}${e['fullDay'] == false && e['fromTime'] != null ? ' (${e['fromTime']}-${e['toTime']})' : ''}',
                ),
                subtitle: Text(
                  '${e['reason']}${e['approval'] == 'self_declared' ? ' · declared by the doctor' : ''}',
                ),
                trailing: manage
                    ? TextButton(
                        onPressed: () async {
                          final ok = await showEcConfirmDialog(
                            context,
                            title: 'Cancel this entry?',
                            message:
                                'The doctor becomes bookable again for these dates.',
                            confirmLabel: 'Cancel entry',
                            destructive: true,
                          );
                          if (!ok || !context.mounted) return;
                          await runAction(
                            context,
                            action: () => repo
                                .deleteAt(
                                  doctorId == null
                                      ? '/schedule-exceptions/${e['exceptionId']}'
                                      : '/doctors/$doctorId/schedule-exceptions/${e['exceptionId']}',
                                )
                                .then((_) {}),
                            success: 'Entry cancelled.',
                            after: onChanged,
                          );
                        },
                        child: const Text('Cancel'),
                      )
                    : null,
              ),
          ],
        );
      },
    );
  }
}

/// Weekly editor: one line per day with sessions and breaks as time ranges.
class _WeeklyDialog extends StatefulWidget {
  const _WeeklyDialog({
    required this.existing,
    required this.branches,
    required this.branch,
  });

  final Json? existing;
  final List<Json> branches;
  final String? branch;

  @override
  State<_WeeklyDialog> createState() => _WeeklyDialogState();
}

class _WeeklyDialogState extends State<_WeeklyDialog> {
  final _form = GlobalKey<FormState>();
  late final List<TextEditingController> _sessions;
  late final List<TextEditingController> _breaks;
  final _duration = TextEditingController(text: '15');
  final _buffer = TextEditingController(text: '0');
  final _capacity = TextEditingController(text: '1');
  final _from = TextEditingController();
  final _to = TextEditingController();
  String? _branch;

  @override
  void initState() {
    super.initState();
    final w = widget.existing?['weeklyHours'] as Map?;
    _sessions = [
      for (var d = 1; d <= 7; d++)
        TextEditingController(
          text: formatRanges((w?['$d'] as Map?)?['sessions']),
        ),
    ];
    _breaks = [
      for (var d = 1; d <= 7; d++)
        TextEditingController(
          text: formatRanges((w?['$d'] as Map?)?['breaks']),
        ),
    ];
    if (widget.existing != null) {
      _duration.text = '${widget.existing!['defaultDurationMinutes']}';
      _buffer.text = '${widget.existing!['bufferMinutes']}';
      _capacity.text = '${widget.existing!['maxPerSlot']}';
      _from.text = '${widget.existing!['effectiveFrom']}';
      _to.text = '${widget.existing!['effectiveTo'] ?? ''}';
      _branch = widget.existing!['branchId'] as String?;
    } else {
      _branch =
          widget.branch ??
          (widget.branches.length == 1
              ? '${widget.branches.single['branchId']}'
              : null);
      _from.text = isoDate(DateTime.now());
    }
  }

  @override
  void dispose() {
    for (final c in [
      ..._sessions,
      ..._breaks,
      _duration,
      _buffer,
      _capacity,
      _from,
      _to,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _ranges(String? v) =>
      parseRanges(v ?? '') == null ? 'Use 09:00-13:00, 17:00-20:00' : null;

  void _submit() {
    if (!_form.currentState!.validate()) return;
    final weekly = <String, Object?>{
      for (var d = 1; d <= 7; d++)
        '$d': {
          'sessions': parseRanges(_sessions[d - 1].text),
          'breaks': parseRanges(_breaks[d - 1].text),
        },
    };
    Navigator.of(context).pop({
      if (widget.existing == null) 'branchId': _branch,
      'weeklyHours': weekly,
      'defaultDurationMinutes': int.tryParse(_duration.text) ?? 15,
      'bufferMinutes': int.tryParse(_buffer.text) ?? 0,
      'maxPerSlot': int.tryParse(_capacity.text) ?? 1,
      'effectiveFrom': _from.text.trim(),
      if (_to.text.trim().isNotEmpty) 'effectiveTo': _to.text.trim(),
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.existing == null ? 'New weekly schedule' : 'Edit weekly schedule',
    ),
    content: SizedBox(
      width: 640,
      child: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const EcInlineMessage(
                tone: EcStatusTone.info,
                message:
                    'Write each day as time ranges, for example 09:00-13:00, 17:00-20:00. Leave a day empty when the doctor does not work. Times are in the branch time zone.',
              ),
              const SizedBox(height: EcSpacing.md),
              if (widget.existing == null)
                EcDropdown<String>(
                  label: 'Branch',
                  items: [for (final b in widget.branches) '${b['branchId']}'],
                  value: _branch,
                  itemLabel: (id) =>
                      '${widget.branches.firstWhere((b) => b['branchId'] == id)['name']}',
                  validator: (v) => v == null ? 'Choose a branch.' : null,
                  onChanged: (v) => setState(() => _branch = v),
                ),
              for (var d = 0; d < 7; d++)
                Padding(
                  padding: const EdgeInsets.only(top: EcSpacing.md),
                  child: Row(
                    children: [
                      SizedBox(width: 90, child: Text(_dayNames[d])),
                      Expanded(
                        child: EcTextField(
                          label: 'Sessions',
                          controller: _sessions[d],
                          validator: _ranges,
                          maxLength: 60,
                        ),
                      ),
                      const SizedBox(width: EcSpacing.md),
                      Expanded(
                        child: EcTextField(
                          label: 'Breaks',
                          controller: _breaks[d],
                          validator: _ranges,
                          maxLength: 60,
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: EcSpacing.md),
              Wrap(
                spacing: EcSpacing.md,
                runSpacing: EcSpacing.md,
                children: [
                  SizedBox(
                    width: 140,
                    child: EcTextField(
                      label: 'Slot (min)',
                      controller: _duration,
                      maxLength: 3,
                    ),
                  ),
                  SizedBox(
                    width: 140,
                    child: EcTextField(
                      label: 'Buffer (min)',
                      controller: _buffer,
                      maxLength: 3,
                    ),
                  ),
                  SizedBox(
                    width: 140,
                    child: EcTextField(
                      label: 'Per slot',
                      controller: _capacity,
                      maxLength: 2,
                    ),
                  ),
                  SizedBox(
                    width: 180,
                    child: EcTextField(
                      label: 'Effective from (YYYY-MM-DD)',
                      controller: _from,
                      maxLength: 10,
                    ),
                  ),
                  SizedBox(
                    width: 180,
                    child: EcTextField(
                      label: 'Until (optional)',
                      controller: _to,
                      maxLength: 10,
                    ),
                  ),
                ],
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
        label: 'Save schedule',
        compact: true,
        onPressed: _submit,
      ),
    ],
  );
}
