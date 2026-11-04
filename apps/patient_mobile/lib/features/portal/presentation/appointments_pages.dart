import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/portal_repository.dart';
import 'common_widgets.dart';
import 'providers.dart';
import 'ui_kit.dart';

const _filters = [
  'upcoming',
  'completed',
  'cancelled',
  'rescheduled',
  'no_show',
];

class AppointmentsPage extends ConsumerStatefulWidget {
  const AppointmentsPage({super.key});

  @override
  ConsumerState<AppointmentsPage> createState() => _AppointmentsState();
}

class _AppointmentsState extends ConsumerState<AppointmentsPage> {
  String _filter = 'upcoming';

  @override
  Widget build(BuildContext context) {
    final person = ref.watch(selectedPersonProvider);
    final q = Query(
      '/patient/appointments',
      forPerson(person, {'filter': _filter}),
    );
    return ListView(
      padding: const EdgeInsets.all(EcSpacing.lg),
      children: [
        PageHeader(
          title: 'Appointments',
          subtitle: 'Your visits across linked clinics.',
          actions: [
            sized(
              EcPrimaryButton(
                label: 'Book',
                icon: Icons.add,
                onPressed: () => context.go('/appointments/new'),
              ),
              140,
            ),
          ],
        ),
        const PersonBar(),
        Wrap(
          spacing: EcSpacing.sm,
          children: [
            for (final f in _filters)
              ChoiceChip(
                key: Key('filter-$f'),
                label: Text(humanize(f)),
                selected: _filter == f,
                onSelected: (_) => setState(() => _filter = f),
              ),
          ],
        ),
        const SizedBox(height: EcSpacing.md),
        AsyncBody(
          value: ref.watch(listProvider(q)),
          onRetry: () => ref.invalidate(listProvider(q)),
          builder: (rows) => rows.isEmpty
              ? EcEmptyState(
                  title: 'No ${humanize(_filter).toLowerCase()} appointments',
                  message: _filter == 'upcoming'
                      ? 'Book a visit with a linked clinic.'
                      : 'Nothing to show here.',
                  icon: Icons.event_busy_outlined,
                )
              : Column(
                  children: [
                    for (final a in rows)
                      Card(
                        child: ListTile(
                          key: Key('appt-${a['appointmentId']}'),
                          title: Text(
                            '${a['doctorName']} · ${shortDate(a['localDate'])} ${a['startTime']}',
                          ),
                          subtitle: Text(
                            '${a['clinicName'] ?? ''} · ${a['typeName'] ?? ''}',
                          ),
                          trailing: statusChip(a['status']),
                          onTap: () => context.go(
                            '/appointments/${a['clinicId']}/${a['appointmentId']}${person == null ? '' : '?accountId=$person'}',
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

String _dateOnly(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Slot picker used by booking and rescheduling. Slots are a hint from the
/// backend's scheduling engine; the backend checks again when you confirm.
class SlotPicker extends ConsumerWidget {
  const SlotPicker({
    required this.clinicId,
    required this.branchId,
    required this.doctorId,
    required this.typeId,
    required this.date,
    required this.selected,
    required this.onSelect,
    super.key,
  });

  final String clinicId;
  final String branchId;
  final String doctorId;
  final String? typeId;
  final String date;
  final String? selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final q = Query('/patient/clinics/$clinicId/availability', {
      'branchId': branchId,
      'doctorId': doctorId,
      'date': date,
      'typeId': typeId ?? '',
    });
    return AsyncBody(
      value: ref.watch(mapProvider(q)),
      onRetry: () => ref.invalidate(mapProvider(q)),
      builder: (d) {
        final slots = ((d['slots'] as List?) ?? const [])
            .cast<Json>()
            .where((s) => s['available'] != false && s['full'] != true)
            .toList();
        if (slots.isEmpty) {
          return const EcInlineMessage(
            tone: EcStatusTone.warning,
            message: 'No free times on this day. Try another date.',
          );
        }
        return Wrap(
          spacing: EcSpacing.sm,
          runSpacing: EcSpacing.sm,
          children: [
            for (final s in slots)
              ChoiceChip(
                key: Key('slot-${s['startTime']}'),
                label: Text('${s['startTime']}'),
                selected: selected == s['startTime'],
                onSelected: (_) => onSelect('${s['startTime']}'),
              ),
          ],
        );
      },
    );
  }
}

class BookAppointmentPage extends ConsumerStatefulWidget {
  const BookAppointmentPage({this.clinicId, super.key});

  final String? clinicId;

  @override
  ConsumerState<BookAppointmentPage> createState() => _BookState();
}

class _BookState extends ConsumerState<BookAppointmentPage> {
  String? _clinic;
  String? _branch;
  String? _doctor;
  String? _type;
  DateTime? _date;
  String? _slot;
  bool _busy = false;
  String? _error;
  String? _key;

  void _changed() {
    // different choices are a different booking: never reuse the old key
    _key = null;
    _error = null;
  }

  Future<void> _confirm(Json clinic, Json doctor) async {
    final person = ref.read(selectedPersonProvider);
    final branches = ((clinic['branches'] as List?) ?? const []).cast<Json>();
    final types = ((clinic['appointmentTypes'] as List?) ?? const [])
        .cast<Json>();
    final branchName = branches.firstWhere(
      (b) => b['branchId'] == _branch,
    )['name'];
    final typeName = types.firstWhere((t) => t['typeId'] == _type)['name'];
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm your request'),
        content: KeyValues([
          ('Clinic', clinic['name']),
          ('Branch', branchName),
          ('Doctor', doctor['fullName']),
          ('Type', typeName),
          ('When', '${shortDate(_dateOnly(_date!))} at $_slot'),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Back'),
          ),
          TextButton(
            key: const Key('confirm-booking'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Request appointment'),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    _key ??= newIdempotencyKey();
    try {
      final a = await ref
          .read(portalRepositoryProvider)
          .send(
            'POST',
            '/patient/appointments',
            {
              'clinicId': _clinic,
              'branchId': _branch,
              'doctorId': _doctor,
              'typeId': _type,
              'date': _dateOnly(_date!),
              'startTime': _slot,
              'accountId': ?person,
            },
            {'Idempotency-Key': _key!},
          );
      refreshAll(ref);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Request received'),
          content: KeyValues([
            ('Reference', a['reference']),
            ('Status', humanize(a['status'])),
            ('Doctor', a['doctorName']),
            ('When', '${shortDate(a['localDate'])} at ${a['startTime']}'),
            (
              'Next',
              'The clinic will confirm your appointment. You will see the update here.',
            ),
          ]),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Done'),
            ),
          ],
        ),
      );
      if (mounted) context.go('/appointments');
    } on ApiFailure catch (e) {
      // keep the key only for network faults, where the same request may have
      // reached the server; a refusal means the choice must be made again
      if (e.code != null) _key = null;
      ref.invalidate(mapProvider);
      if (mounted) {
        setState(() {
          _error = e.code?.httpStatus == 409
              ? '${failureText(e)} Pick another time; the list has been refreshed.'
              : failureText(e);
          if (e.code?.httpStatus == 409) _slot = null;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref
        .watch(mapProvider(Query('/patient/profile')))
        .asData
        ?.value;
    final person = ref.watch(selectedPersonProvider);
    final linked = ((profile?['linkedClinics'] as List?) ?? const [])
        .cast<Json>();
    final clinicId =
        _clinic ??
        widget.clinicId ??
        (linked.length == 1 ? '${linked.single['clinicId']}' : null);
    if (_clinic == null && clinicId != null) _clinic = clinicId;
    return ListView(
      padding: const EdgeInsets.all(EcSpacing.lg),
      children: [
        const PageHeader(
          title: 'Book an appointment',
          subtitle: 'The clinic confirms your request.',
        ),
        const PersonBar(),
        if (linked.isEmpty)
          const LinkClinicHint()
        else ...[
          EcDropdown<String>(
            label: 'Clinic',
            items: [for (final c in linked) '${c['clinicId']}'],
            value: clinicId,
            itemLabel: (id) =>
                '${linked.firstWhere((c) => c['clinicId'] == id)['clinicName']}',
            onChanged: (v) => setState(() {
              _clinic = v;
              _branch = _doctor = _type = _slot = null;
              _changed();
            }),
          ),
          if (clinicId != null)
            AsyncBody(
              value: ref.watch(
                mapProvider(Query('/patient/clinics/$clinicId')),
              ),
              onRetry: () => ref.invalidate(mapProvider),
              builder: (clinic) => _form(clinic, clinicId, person),
            ),
        ],
      ],
    );
  }

  Widget _form(Json clinic, String clinicId, String? person) {
    final branches = ((clinic['branches'] as List?) ?? const []).cast<Json>();
    final types = ((clinic['appointmentTypes'] as List?) ?? const [])
        .cast<Json>();
    final branch =
        _branch ??
        (branches.length == 1 ? '${branches.single['branchId']}' : null);
    if (_branch == null && branch != null) _branch = branch;
    final docQ = Query('/patient/clinics/$clinicId/doctors', {
      'branchId': branch ?? '',
    });
    final doctors =
        ref.watch(listProvider(docQ)).asData?.value ?? const <Json>[];
    Json? doctor;
    for (final d in doctors) {
      if (d['doctorId'] == _doctor) doctor = d;
    }
    final ready =
        branch != null &&
        doctor != null &&
        _type != null &&
        _date != null &&
        _slot != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: EcSpacing.md),
        if (branches.length > 1)
          EcDropdown<String>(
            label: 'Branch',
            items: [for (final b in branches) '${b['branchId']}'],
            value: branch,
            itemLabel: (id) =>
                '${branches.firstWhere((b) => b['branchId'] == id)['name']}',
            onChanged: (v) => setState(() {
              _branch = v;
              _doctor = _slot = null;
              _changed();
            }),
          ),
        const SizedBox(height: EcSpacing.md),
        EcDropdown<String>(
          label: 'Doctor',
          items: [for (final d in doctors) '${d['doctorId']}'],
          value: doctor == null ? null : _doctor,
          itemLabel: (id) =>
              '${doctors.firstWhere((d) => d['doctorId'] == id)['fullName']}'
              '${doctors.firstWhere((d) => d['doctorId'] == id)['specialty'] == null ? '' : ' (${doctors.firstWhere((d) => d['doctorId'] == id)['specialty']})'}',
          onChanged: (v) => setState(() {
            _doctor = v;
            _slot = null;
            _changed();
          }),
        ),
        const SizedBox(height: EcSpacing.md),
        EcDropdown<String>(
          label: 'Appointment type',
          items: [for (final t in types) '${t['typeId']}'],
          value: _type,
          itemLabel: (id) =>
              '${types.firstWhere((t) => t['typeId'] == id)['name']}',
          onChanged: (v) => setState(() {
            _type = v;
            _slot = null;
            _changed();
          }),
        ),
        const SizedBox(height: EcSpacing.md),
        sized(
          EcSecondaryButton(
            key: const Key('pick-date'),
            label: _date == null
                ? 'Choose a date'
                : shortDate(_dateOnly(_date!)),
            icon: Icons.calendar_today_outlined,
            onPressed: () async {
              final now = DateTime.now();
              final d = await showDatePicker(
                context: context,
                initialDate: _date ?? now,
                firstDate: now,
                lastDate: now.add(const Duration(days: 60)),
              );
              if (d != null) {
                setState(() {
                  _date = d;
                  _slot = null;
                  _changed();
                });
              }
            },
          ),
          240,
        ),
        const SizedBox(height: EcSpacing.md),
        if (branch != null && _doctor != null && _date != null)
          SlotPicker(
            clinicId: clinicId,
            branchId: branch,
            doctorId: _doctor!,
            typeId: _type,
            date: _dateOnly(_date!),
            selected: _slot,
            onSelect: (s) => setState(() {
              _slot = s;
              _changed();
            }),
          ),
        if (_error != null)
          EcInlineMessage(tone: EcStatusTone.error, message: _error!),
        const SizedBox(height: EcSpacing.lg),
        sized(
          EcPrimaryButton(
            key: const Key('review-booking'),
            label: 'Review and request',
            onPressed: ready && !_busy ? () => _confirm(clinic, doctor!) : null,
          ),
          260,
        ),
      ],
    );
  }
}

class AppointmentDetailPage extends ConsumerStatefulWidget {
  const AppointmentDetailPage({
    required this.clinicId,
    required this.appointmentId,
    this.accountId,
    super.key,
  });

  final String clinicId;
  final String appointmentId;
  final String? accountId;

  @override
  ConsumerState<AppointmentDetailPage> createState() => _DetailState();
}

class _DetailState extends ConsumerState<AppointmentDetailPage> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // the queue is refreshed on a timer; the Refresh button works at any time
    _timer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) ref.invalidate(mapProvider);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Map<String, String> get _p => forPerson(widget.accountId);

  String get _base =>
      '/patient/clinics/${widget.clinicId}/appointments/${widget.appointmentId}';

  Future<void> _act(String action, String ok, [Json? body]) => runAction(
    context,
    action: () => ref.read(portalRepositoryProvider).send(
      'POST',
      '$_base/$action',
      {...?body, 'accountId': ?widget.accountId},
    ),
    success: ok,
    after: () => refreshAll(ref),
  );

  @override
  Widget build(BuildContext context) {
    final q = Query(_base, _p);
    return AsyncBody(
      value: ref.watch(mapProvider(q)),
      onRetry: () => ref.invalidate(mapProvider(q)),
      builder: (a) {
        final status = '${a['status']}';
        final live = status == 'checked_in' || status == 'in_consultation';
        return ListView(
          padding: const EdgeInsets.all(EcSpacing.lg),
          children: [
            PageHeader(
              title: '${a['doctorName']}',
              subtitle: '${a['clinicName'] ?? ''} · ${a['reference'] ?? ''}',
              actions: [statusChip(status)],
            ),
            Section(
              title: 'Details',
              child: KeyValues([
                ('Date', shortDate(a['localDate'])),
                ('Time', '${a['startTime']} – ${a['endTime']}'),
                ('Type', a['typeName']),
                ('Branch', a['branchName']),
                ('Queue token', a['tokenDisplay']),
                ('Booked', shortDateTime(a['createdAt'])),
                ('Cancelled because', a['cancelReason']),
              ]),
            ),
            if (live) _QueueSection(queueQ: Query('$_base/queue', _p)),
            Wrap(
              spacing: EcSpacing.md,
              runSpacing: EcSpacing.md,
              children: [
                if (status == 'confirmed')
                  sized(
                    EcPrimaryButton(
                      label: 'Check in',
                      icon: Icons.how_to_reg_outlined,
                      onPressed: () => _act('check-in', 'You are checked in.'),
                    ),
                    200,
                  ),
                if (a['canCancel'] == true)
                  sized(
                    EcSecondaryButton(
                      label: 'Reschedule',
                      icon: Icons.edit_calendar_outlined,
                      onPressed: () => _reschedule(a),
                    ),
                    200,
                  ),
                if (a['canCancel'] == true)
                  sized(
                    EcSecondaryButton(
                      label: 'Cancel appointment',
                      icon: Icons.cancel_outlined,
                      onPressed: () async {
                        final sure = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Cancel this appointment?'),
                            content: const Text(
                              'The clinic is told and the time is released for others.',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () =>
                                    Navigator.of(context).pop(false),
                                child: const Text('Keep it'),
                              ),
                              TextButton(
                                key: const Key('confirm-cancel'),
                                onPressed: () =>
                                    Navigator.of(context).pop(true),
                                child: const Text('Cancel appointment'),
                              ),
                            ],
                          ),
                        );
                        if (sure == true && mounted) {
                          await _act('cancel', 'Appointment cancelled.');
                        }
                      },
                    ),
                    240,
                  ),
                _ContactClinic(clinicId: widget.clinicId),
              ],
            ),
          ],
        );
      },
    );
  }

  Future<void> _reschedule(Json a) async {
    final picked = await showDialog<(String, String)>(
      context: context,
      builder: (context) =>
          _RescheduleDialog(clinicId: widget.clinicId, appt: a),
    );
    if (picked == null || !mounted) return;
    await _act('reschedule', 'Appointment moved.', {
      'date': picked.$1,
      'startTime': picked.$2,
    });
    if (mounted) context.go('/appointments');
  }
}

class _ContactClinic extends ConsumerWidget {
  const _ContactClinic({required this.clinicId});

  final String clinicId;

  @override
  Widget build(BuildContext context, WidgetRef ref) => sized(
    EcSecondaryButton(
      label: 'Contact clinic',
      icon: Icons.phone_outlined,
      onPressed: () async {
        final c = await ref
            .read(portalRepositoryProvider)
            .getMap('/patient/clinics/$clinicId');
        if (!context.mounted) return;
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('${c['name']}'),
            content: KeyValues([('Phone', c['phone']), ('E-mail', c['email'])]),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ],
          ),
        );
      },
    ),
    200,
  );
}

class _RescheduleDialog extends ConsumerStatefulWidget {
  const _RescheduleDialog({required this.clinicId, required this.appt});

  final String clinicId;
  final Json appt;

  @override
  ConsumerState<_RescheduleDialog> createState() => _RescheduleState();
}

class _RescheduleState extends ConsumerState<_RescheduleDialog> {
  DateTime? _date;
  String? _slot;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Choose a new time'),
    content: SizedBox(
      width: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          sized(
            EcSecondaryButton(
              label: _date == null
                  ? 'Choose a date'
                  : shortDate(_dateOnly(_date!)),
              onPressed: () async {
                final now = DateTime.now();
                final d = await showDatePicker(
                  context: context,
                  initialDate: now,
                  firstDate: now,
                  lastDate: now.add(const Duration(days: 60)),
                );
                if (d != null) {
                  setState(() {
                    _date = d;
                    _slot = null;
                  });
                }
              },
            ),
            240,
          ),
          const SizedBox(height: EcSpacing.md),
          if (_date != null)
            SlotPicker(
              clinicId: widget.clinicId,
              branchId: '${widget.appt['branchId']}',
              doctorId: '${widget.appt['doctorId']}',
              typeId: widget.appt['typeId'] as String?,
              date: _dateOnly(_date!),
              selected: _slot,
              onSelect: (s) => setState(() => _slot = s),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      TextButton(
        key: const Key('confirm-reschedule'),
        onPressed: _date == null || _slot == null
            ? null
            : () => Navigator.of(context).pop((_dateOnly(_date!), _slot!)),
        child: const Text('Move appointment'),
      ),
    ],
  );
}

/// Token and position from the backend. No other patient is ever shown and no
/// waiting time is promised.
class _QueueSection extends ConsumerWidget {
  const _QueueSection({required this.queueQ});

  final Query queueQ;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Section(
    title: 'Queue',
    trailing: IconButton(
      key: const Key('refresh-queue'),
      tooltip: 'Refresh',
      icon: const Icon(Icons.refresh),
      onPressed: () => ref.invalidate(mapProvider(queueQ)),
    ),
    child: AsyncBody(
      value: ref.watch(mapProvider(queueQ)),
      onRetry: () => ref.invalidate(mapProvider(queueQ)),
      builder: (q) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          KeyValues([
            ('Your token', q['token']),
            ('Now serving', q['currentToken']),
            ('Patients ahead of you', q['patientsAhead']),
            ('Status', humanize(q['status'])),
          ]),
          const SizedBox(height: EcSpacing.sm),
          Text(
            '${q['estimatedWaitNote'] ?? ''}',
            style: EcTypography.bodySecondary,
          ),
        ],
      ),
    ),
  );
}
