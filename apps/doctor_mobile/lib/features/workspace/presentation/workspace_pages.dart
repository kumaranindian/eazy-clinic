import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/clinical_repository.dart';
import 'providers.dart';
import 'ui_kit.dart';

/// Today at a glance: counts, upcoming visits, the queue and recent work.
class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final q = dashboardQuery();
    return AsyncBody(
      value: ref.watch(mapProvider(q)),
      onRetry: () => ref.invalidate(mapProvider(q)),
      builder: (d) {
        final c = (d['counts'] as Map?) ?? const {};
        Widget tile(String label, String key) => SizedBox(
          width: 170,
          child: EcCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${c[key] ?? 0}',
                  key: Key('count-$key'),
                  style: EcTypography.sectionTitle,
                ),
                Text(label, style: EcTypography.bodySecondary),
              ],
            ),
          ),
        );
        final upcoming = ((d['upcoming'] as List?) ?? const []).cast<Json>();
        final queues = ((d['queues'] as List?) ?? const []).cast<Json>();
        final recent = ((d['recentConsultations'] as List?) ?? const [])
            .cast<Json>();
        return ListView(
          padding: const EdgeInsets.all(EcSpacing.lg),
          children: [
            const PageHeader(
              title: 'Today',
              subtitle: 'Your appointments and patients.',
            ),
            Wrap(
              spacing: EcSpacing.md,
              runSpacing: EcSpacing.md,
              children: [
                tile('Appointments', 'scheduled'),
                tile('Waiting', 'waiting'),
                tile('Checked in', 'checkedIn'),
                tile('In consultation', 'inProgress'),
                tile('Completed', 'completed'),
                tile('Cancelled', 'cancelled'),
                tile('No-show', 'noShow'),
              ],
            ),
            const SizedBox(height: EcSpacing.lg),
            Section(
              title: 'Queue',
              child: queues.isEmpty
                  ? const Text('No branch queue today.')
                  : Column(
                      children: [
                        for (final q in queues)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              '${q['branchName'] ?? 'Branch'}: ${q['waiting']} waiting',
                            ),
                            subtitle: Text(
                              'Now serving ${(q['currentToken'] as Map?)?['displayToken'] ?? '—'} · next ${(q['nextToken'] as Map?)?['displayToken'] ?? '—'}',
                            ),
                            onTap: () => context.go('/queue'),
                          ),
                      ],
                    ),
            ),
            Section(
              title: 'Upcoming appointments',
              child: upcoming.isEmpty
                  ? const Text('Nothing else is booked for today.')
                  : Column(
                      children: [
                        for (final a in upcoming)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              '${a['startTime']} · ${a['patientName']}',
                            ),
                            subtitle: Text(
                              '${a['patientMrn']} · ${a['typeName']}',
                            ),
                            trailing: statusChip(a['status']),
                            onTap: () =>
                                context.go('/patients/${a['patientId']}'),
                          ),
                      ],
                    ),
            ),
            Section(
              title: 'Recent consultations',
              child: recent.isEmpty
                  ? const Text('No consultations yet.')
                  : Column(
                      children: [
                        for (final r in recent)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              '${r['patientName']} · ${r['patientMrn']}',
                            ),
                            subtitle: Text(
                              '${shortDateTime(r['consultationAt'])} · ${r['reason'] ?? ''}',
                            ),
                            trailing: statusChip(r['status']),
                            onTap: () => context.go(
                              '/consultations/${r['consultationId']}',
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

/// Opens (or resumes) the consultation of an appointment.
Future<void> openConsultation(
  BuildContext context,
  WidgetRef ref, {
  required String patientId,
  String? appointmentId,
  String? branchId,
}) async {
  final repo = ref.read(clinicalRepositoryProvider);
  try {
    String? templateId;
    final templates = await repo.getList('/clinical/templates');
    if (templates.isNotEmpty && context.mounted) {
      templateId = await showDialog<String>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('Start from a template?'),
          children: [
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(''),
              child: const Text('No template'),
            ),
            for (final t in templates)
              SimpleDialogOption(
                onPressed: () =>
                    Navigator.of(context).pop('${t['templateId']}'),
                child: Text('${t['name']}'),
              ),
          ],
        ),
      );
      if (templateId == null) return;
    }
    final c = await repo.send('POST', '/consultations', {
      'patientId': patientId,
      'appointmentId': ?appointmentId,
      if (appointmentId == null) 'branchId': branchId,
      if (templateId != null && templateId.isNotEmpty) 'templateId': templateId,
    });
    refreshAll(ref);
    if (context.mounted) context.go('/consultations/${c['consultationId']}');
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

class TodayPage extends ConsumerWidget {
  const TodayPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final q = Query('/doctor/appointments/today');
    return AsyncBody(
      value: ref.watch(listProvider(q)),
      onRetry: () => ref.invalidate(listProvider(q)),
      builder: (rows) => ListView(
        padding: const EdgeInsets.all(EcSpacing.lg),
        children: [
          const PageHeader(
            title: "Today's appointments",
            subtitle: 'Your patients for today, in time order.',
          ),
          if (rows.isEmpty)
            const EcEmptyState(
              title: 'No appointments today',
              message: 'Nothing is booked for you today.',
            )
          else
            for (final a in rows)
              Padding(
                padding: const EdgeInsets.only(bottom: EcSpacing.sm),
                child: EcCard(
                  child: Row(
                    children: [
                      SizedBox(
                        width: 110,
                        child: Text(
                          '${a['startTime']}-${a['endTime']}',
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
                              '${a['typeName']}${a['tokenDisplay'] == null ? '' : ' · token ${a['tokenDisplay']}'}',
                              style: EcTypography.bodySecondary,
                            ),
                          ],
                        ),
                      ),
                      statusChip(a['status']),
                      const SizedBox(width: EcSpacing.sm),
                      TextButton(
                        onPressed: () =>
                            context.go('/patients/${a['patientId']}'),
                        child: const Text('Patient'),
                      ),
                      if (const {
                        'checked_in',
                        'in_progress',
                        'confirmed',
                      }.contains(a['status']))
                        TextButton(
                          onPressed: () => openConsultation(
                            context,
                            ref,
                            patientId: '${a['patientId']}',
                            appointmentId: '${a['appointmentId']}',
                          ),
                          child: const Text('Consult'),
                        ),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

/// The doctor's queue for today. Refreshes itself and never moves back to an
/// older snapshot.
class QueuePage extends ConsumerStatefulWidget {
  const QueuePage({this.pollSeconds = 10, super.key});

  final int pollSeconds;

  @override
  ConsumerState<QueuePage> createState() => _QueueState();
}

class _QueueState extends ConsumerState<QueuePage> {
  Timer? _timer;
  final Map<String, int> _versions = {};
  List<Json>? _shown;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(Duration(seconds: widget.pollSeconds), (_) {
      if (mounted) ref.invalidate(listProvider);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = Query('/doctor/queue');
    return AsyncBody(
      value: ref.watch(listProvider(q)),
      onRetry: () => ref.invalidate(listProvider(q)),
      builder: (fresh) {
        // a snapshot older than the one on screen is ignored
        var accept = _shown == null || fresh.length != _shown!.length;
        for (final f in fresh) {
          final v = (f['version'] as int?) ?? 0;
          if (v >= (_versions['${f['queueId']}'] ?? -1)) accept = true;
        }
        if (accept) {
          _shown = fresh;
          for (final f in fresh) {
            _versions['${f['queueId']}'] = (f['version'] as int?) ?? 0;
          }
        }
        final queues = _shown ?? fresh;
        final repo = ref.read(clinicalRepositoryProvider);
        return ListView(
          padding: const EdgeInsets.all(EcSpacing.lg),
          children: [
            PageHeader(
              title: 'Queue',
              subtitle:
                  'Patients checked in for you. Refreshes every few seconds.',
              actions: [
                IconButton(
                  tooltip: 'Refresh now',
                  onPressed: () => ref.invalidate(listProvider),
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            if (queues.isEmpty)
              const EcEmptyState(
                title: 'No queue today',
                message: 'You have no branch queue today.',
              ),
            for (final qu in queues) ...[
              Text(
                '${qu['branchName'] ?? 'Branch'}',
                style: EcTypography.subsectionTitle,
              ),
              const SizedBox(height: EcSpacing.sm),
              Wrap(
                spacing: EcSpacing.md,
                children: [
                  Text(
                    'Now serving: ${(qu['currentToken'] as Map?)?['displayToken'] ?? '—'}',
                    key: const Key('current-token'),
                    style: EcTypography.bodyStrong,
                  ),
                  Text(
                    'Waiting: ${qu['waiting']}',
                    key: const Key('waiting-count'),
                  ),
                ],
              ),
              const SizedBox(height: EcSpacing.sm),
              if (((qu['entries'] as List?) ?? const []).isEmpty)
                const Padding(
                  padding: EdgeInsets.only(bottom: EcSpacing.lg),
                  child: Text('Nobody has checked in yet.'),
                ),
              for (final e
                  in ((qu['entries'] as List?) ?? const []).cast<Json>())
                Padding(
                  padding: const EdgeInsets.only(bottom: EcSpacing.sm),
                  child: EcCard(
                    child: Row(
                      children: [
                        SizedBox(
                          width: 64,
                          child: Text(
                            '${e['displayToken']}',
                            style: EcTypography.sectionTitle,
                          ),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${e['patientName']}',
                                style: EcTypography.bodyStrong,
                              ),
                              Text(
                                '${e['queuePosition'] == null ? '' : 'Position ${e['queuePosition']} · '}${e['source'] == 'walk_in' ? 'Walk-in' : 'Scheduled'}${e['priority'] == 'priority' ? ' · Priority' : ''}',
                                style: EcTypography.bodySecondary,
                              ),
                            ],
                          ),
                        ),
                        statusChip(e['status']),
                        if (e['status'] == 'waiting')
                          TextButton(
                            onPressed: () => runAction(
                              context,
                              action: () => repo.send(
                                'POST',
                                '/doctor/queue/${e['entryId']}/call',
                              ),
                              success: 'Patient called.',
                              after: () => ref.invalidate(listProvider),
                            ),
                            child: const Text('Call'),
                          ),
                        if (e['status'] == 'called' ||
                            e['status'] == 'in_progress')
                          TextButton(
                            onPressed: () => openConsultation(
                              context,
                              ref,
                              patientId: '${e['patientId']}',
                              appointmentId: '${e['appointmentId']}',
                            ),
                            child: Text(
                              e['status'] == 'called'
                                  ? 'Start consultation'
                                  : 'Open',
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ],
        );
      },
    );
  }
}

/// Follow-ups: upcoming and overdue, with status changes and booking.
class FollowupsPage extends ConsumerStatefulWidget {
  const FollowupsPage({super.key});

  @override
  ConsumerState<FollowupsPage> createState() => _FollowupsState();
}

class _FollowupsState extends ConsumerState<FollowupsPage> {
  String _view = 'upcoming';

  @override
  Widget build(BuildContext context) {
    final q = Query('/doctor/followups', {_view: 'true', 'limit': '50'});
    final repo = ref.read(clinicalRepositoryProvider);
    return ListView(
      padding: const EdgeInsets.all(EcSpacing.lg),
      children: [
        const PageHeader(
          title: 'Follow-ups',
          subtitle:
              'A follow-up is a recommendation until it is booked as an appointment.',
        ),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'upcoming', label: Text('Upcoming')),
            ButtonSegment(value: 'overdue', label: Text('Overdue')),
          ],
          selected: {_view},
          onSelectionChanged: (s) => setState(() => _view = s.first),
        ),
        const SizedBox(height: EcSpacing.lg),
        AsyncBody(
          value: ref.watch(listProvider(q)),
          onRetry: () => ref.invalidate(listProvider(q)),
          builder: (rows) => rows.isEmpty
              ? EcEmptyState(
                  title: _view == 'overdue'
                      ? 'Nothing overdue'
                      : 'No upcoming follow-ups',
                  message:
                      'Follow-ups you plan during consultations appear here.',
                )
              : Column(
                  children: [
                    for (final f in rows)
                      Padding(
                        padding: const EdgeInsets.only(bottom: EcSpacing.sm),
                        child: EcCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      '${f['recommendedDate']} · ${f['patientName']} (${f['patientMrn']})',
                                      style: EcTypography.bodyStrong,
                                    ),
                                  ),
                                  if (f['overdue'] == true)
                                    const EcStatusChip(
                                      label: 'Overdue',
                                      tone: EcStatusTone.error,
                                    ),
                                  const SizedBox(width: EcSpacing.xs),
                                  statusChip(f['status']),
                                ],
                              ),
                              Text(
                                '${f['reason'] ?? ''}',
                                style: EcTypography.bodySecondary,
                              ),
                              if (f['appointmentReference'] != null)
                                Text(
                                  'Booked: ${f['appointmentReference']}',
                                  style: EcTypography.helper,
                                ),
                              Wrap(
                                children: [
                                  TextButton(
                                    onPressed: () => context.go(
                                      '/patients/${f['patientId']}',
                                    ),
                                    child: const Text('Patient'),
                                  ),
                                  if (f['status'] == 'scheduled' ||
                                      f['status'] == 'missed')
                                    TextButton(
                                      onPressed: () => runAction(
                                        context,
                                        action: () => repo.send(
                                          'PATCH',
                                          '/followups/${f['followupId']}',
                                          {'status': 'completed'},
                                        ),
                                        success: 'Marked as completed.',
                                        after: () =>
                                            ref.invalidate(listProvider),
                                      ),
                                      child: const Text('Mark completed'),
                                    ),
                                  if (f['status'] == 'scheduled')
                                    TextButton(
                                      onPressed: () => runAction(
                                        context,
                                        action: () => repo.send(
                                          'PATCH',
                                          '/followups/${f['followupId']}',
                                          {'status': 'missed'},
                                        ),
                                        success: 'Marked as missed.',
                                        after: () =>
                                            ref.invalidate(listProvider),
                                      ),
                                      child: const Text('Mark missed'),
                                    ),
                                  if (f['status'] == 'scheduled' &&
                                      f['appointmentId'] == null)
                                    TextButton(
                                      onPressed: () => _book(context, f),
                                      child: const Text('Book appointment'),
                                    ),
                                  if (f['status'] == 'scheduled')
                                    TextButton(
                                      onPressed: () async {
                                        final ok = await showEcConfirmDialog(
                                          context,
                                          title: 'Cancel this follow-up?',
                                          message:
                                              'The recommendation is dropped. A booked appointment is not cancelled.',
                                          confirmLabel: 'Cancel follow-up',
                                          destructive: true,
                                        );
                                        if (!ok || !context.mounted) return;
                                        await runAction(
                                          context,
                                          action: () => repo.send(
                                            'PATCH',
                                            '/followups/${f['followupId']}',
                                            {'status': 'cancelled'},
                                          ),
                                          success: 'Follow-up cancelled.',
                                          after: () =>
                                              ref.invalidate(listProvider),
                                        );
                                      },
                                      child: const Text('Cancel'),
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
      ],
    );
  }

  /// Chooses a type, date and one of the server's free slots, then books it
  /// through the appointment service.
  Future<void> _book(BuildContext context, Json f) async {
    final repo = ref.read(clinicalRepositoryProvider);
    final types = await repo
        .getList('/appointment-types', {'status': 'active', 'limit': '50'})
        .catchError((_) => <Json>[]);
    if (!context.mounted) return;
    final r = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => _BookDialog(followup: f, types: types),
    );
    if (r == null || !context.mounted) return;
    await runAction(
      context,
      action: () => repo.send(
        'POST',
        '/followups/${f['followupId']}/appointment',
        r,
        {'Idempotency-Key': newIdempotencyKey()},
      ),
      success: 'Appointment booked.',
      after: () => ref.invalidate(listProvider),
    );
  }
}

class _BookDialog extends ConsumerStatefulWidget {
  const _BookDialog({required this.followup, required this.types});

  final Json followup;
  final List<Json> types;

  @override
  ConsumerState<_BookDialog> createState() => _BookDialogState();
}

class _BookDialogState extends ConsumerState<_BookDialog> {
  late final TextEditingController _date = TextEditingController(
    text: '${widget.followup['recommendedDate']}',
  );
  String? _type;
  String? _slot;

  @override
  void initState() {
    super.initState();
    _date.addListener(() => setState(() => _slot = null));
  }

  @override
  void dispose() {
    _date.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ok = RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(_date.text.trim());
    final slotsQ = ok && _type != null
        ? Query('/appointments/available-slots', {
            'branchId': '${widget.followup['branchId']}',
            'doctorId': '${widget.followup['doctorId']}',
            'date': _date.text.trim(),
            'typeId': _type!,
          })
        : null;
    return AlertDialog(
      title: const Text('Book the follow-up'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              EcDropdown<String>(
                label: 'Appointment type',
                items: [for (final t in widget.types) '${t['typeId']}'],
                value: _type,
                itemLabel: (id) =>
                    '${widget.types.firstWhere((t) => t['typeId'] == id)['name']}',
                onChanged: (v) => setState(() {
                  _type = v;
                  _slot = null;
                }),
              ),
              const SizedBox(height: EcSpacing.md),
              EcTextField(
                label: 'Date (YYYY-MM-DD)',
                controller: _date,
                maxLength: 10,
              ),
              const SizedBox(height: EcSpacing.md),
              if (slotsQ != null)
                ref
                    .watch(mapProvider(slotsQ))
                    .when(
                      loading: () => const Text('Loading times…'),
                      error: (e, _) => Text(
                        e is ApiFailure
                            ? e.displayMessage
                            : 'Could not load times.',
                      ),
                      data: (d) {
                        final slots = ((d['slots'] as List?) ?? const [])
                            .cast<Json>();
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
          label: 'Book',
          compact: true,
          onPressed: _type == null || _slot == null
              ? null
              : () => Navigator.of(context).pop({
                  'typeId': _type!,
                  'date': _date.text.trim(),
                  'startTime': _slot!,
                }),
        ),
      ],
    );
  }
}
