import 'dart:async';

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
import 'appointments_pages.dart';
import 'scheduling_providers.dart';

/// Live queue of one doctor at one branch for one day. The backend owns every
/// state change; the page reads a fresh snapshot every [pollSeconds] seconds
/// and ignores a snapshot older than the one it already shows.
class QueuePage extends ConsumerStatefulWidget {
  const QueuePage({this.pollSeconds = 10, super.key});

  final int pollSeconds;

  @override
  ConsumerState<QueuePage> createState() => _QueueState();
}

class _QueueState extends ConsumerState<QueuePage> {
  String? _branch;
  String? _doctor;
  Timer? _timer;
  int _shownVersion = -1;
  Json? _shown;
  DateTime? _updated;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(Duration(seconds: widget.pollSeconds), (_) {
      if (mounted) _refresh();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _refresh() {
    ref.invalidate(mapProvider);
    ref.invalidate(listProvider);
  }

  @override
  Widget build(BuildContext context) {
    final active = ref.watch(activeBranchProvider);
    final branches =
        ref
            .watch(branchChoicesProvider)
            .asData
            ?.value
            .where((b) => b['status'] == 'active')
            .toList() ??
        const <Json>[];
    final branch =
        _branch ??
        active ??
        (branches.length == 1 ? '${branches.single['branchId']}' : null);
    final doctors =
        ref.watch(doctorChoicesProvider(branch)).asData?.value ??
        const <Json>[];
    final doctor = doctors.any((d) => d['doctorId'] == _doctor)
        ? _doctor
        : null;
    final queueQ = branch == null || doctor == null
        ? null
        : Query('/queues/current', {'branchId': branch, 'doctorId': doctor});
    final repo = ref.read(controlPlaneRepositoryProvider);

    return ListView(
      padding: const EdgeInsets.all(EcSpacing.lg),
      children: [
        PageHeader(
          title: 'Queue',
          subtitle: 'Today\'s patients for one doctor.',
          actions: [
            const Tooltip(
              message: 'The page refreshes itself every few seconds.',
              child: EcStatusChip(label: 'Live', tone: EcStatusTone.success),
            ),
            IconButton(
              tooltip: 'Refresh now',
              onPressed: _refresh,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        Wrap(
          spacing: EcSpacing.lg,
          runSpacing: EcSpacing.md,
          children: [
            if (active == null)
              SizedBox(
                width: 240,
                child: EcDropdown<String>(
                  label: 'Branch',
                  items: [for (final b in branches) '${b['branchId']}'],
                  value: branch,
                  itemLabel: (id) =>
                      '${branches.firstWhere((b) => b['branchId'] == id)['name']}',
                  onChanged: (v) => setState(() {
                    _branch = v;
                    _doctor = null;
                    _shownVersion = -1;
                  }),
                ),
              ),
            SizedBox(
              width: 280,
              child: EcDropdown<String>(
                label: 'Doctor',
                items: [for (final d in doctors) '${d['doctorId']}'],
                value: doctor,
                itemLabel: (id) =>
                    '${doctors.firstWhere((d) => d['doctorId'] == id)['fullName']}',
                onChanged: (v) => setState(() {
                  _doctor = v;
                  _shownVersion = -1;
                  _shown = null;
                }),
              ),
            ),
          ],
        ),
        const SizedBox(height: EcSpacing.lg),
        if (queueQ == null)
          const EcEmptyState(
            title: 'Choose a doctor',
            message: 'Pick the branch and doctor whose queue you want to run.',
          )
        else
          AsyncBody(
            value: ref.watch(mapProvider(queueQ)),
            onRetry: () => ref.invalidate(mapProvider(queueQ)),
            builder: (fresh) {
              // out-of-order or repeated snapshots never move the screen back
              final v = (fresh['version'] as int?) ?? 0;
              if (v >= _shownVersion || _shown == null) {
                _shown = fresh;
                _shownVersion = v;
                _updated = DateTime.now();
              }
              final q = _shown!;
              final entriesQ = q['queueId'] != null && q['version'] != 0
                  ? Query('/queues/${q['queueId']}/entries', {
                      'v': '${q['version']}',
                    })
                  : null;
              return _QueueBody(
                summary: q,
                entriesQuery: entriesQ,
                updated: _updated,
                onChanged: _refresh,
                repo: repo,
              );
            },
          ),
      ],
    );
  }
}

class _QueueBody extends ConsumerWidget {
  const _QueueBody({
    required this.summary,
    required this.entriesQuery,
    required this.updated,
    required this.onChanged,
    required this.repo,
  });

  final Json summary;
  final Query? entriesQuery;
  final DateTime? updated;
  final VoidCallback onChanged;
  final ControlPlaneRepository repo;

  Widget _tile(String label, Object? value, {Key? key}) => SizedBox(
    width: 150,
    child: EcCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$value', key: key, style: EcTypography.sectionTitle),
          Text(label, style: EcTypography.bodySecondary),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = summary['currentToken'] as Map<String, Object?>?;
    final next = summary['nextToken'] as Map<String, Object?>?;
    final operate = can(ref, ClinicPermission.queueOperate);
    final consult = can(ref, ClinicPermission.queueConsult);
    final priority = can(ref, ClinicPermission.queuePriority);
    final cancelCheckedIn = can(
      ref,
      ClinicPermission.appointmentsCancelCheckedIn,
    );
    Future<void> act(
      String entryId,
      String action,
      String done, {
      Json? body,
    }) => runAction(
      context,
      action: () =>
          repo.sendMap('POST', '/queue-entries/$entryId/$action', body),
      success: done,
      after: onChanged,
    );
    final entries = entriesQuery == null
        ? const AsyncData<List<Json>>([])
        : ref.watch(listProvider(entriesQuery!));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: EcSpacing.md,
          runSpacing: EcSpacing.md,
          children: [
            _tile('Scheduled', summary['scheduledAppointments']),
            _tile('Checked in', summary['checkedIn']),
            _tile(
              'Waiting',
              summary['waiting'],
              key: const Key('count-waiting'),
            ),
            _tile('In consultation', summary['inConsultation']),
            _tile('Completed', summary['completed']),
            _tile('No-show', summary['noShow']),
          ],
        ),
        const SizedBox(height: EcSpacing.lg),
        EcCard(
          child: Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Now serving', style: EcTypography.bodySecondary),
                  Text(
                    current == null ? '—' : '${current['displayToken']}',
                    key: const Key('current-token'),
                    style: EcTypography.pageTitle,
                  ),
                  if (current != null) Text('${current['patientName']}'),
                ],
              ),
              const SizedBox(width: EcSpacing.xl),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Next', style: EcTypography.bodySecondary),
                  Text(
                    next == null ? '—' : '${next['displayToken']}',
                    key: const Key('next-token'),
                    style: EcTypography.sectionTitle,
                  ),
                  if (next != null) Text('${next['patientName']}'),
                ],
              ),
              const Spacer(),
              if (operate && (summary['waiting'] as int? ?? 0) > 0)
                SizedBox(
                  width: 300,
                  child: EcPrimaryButton(
                    label: 'Call next',
                    compact: true,
                    icon: Icons.campaign_outlined,
                    onPressed: () => runAction(
                      context,
                      action: () => repo.sendMap(
                        'POST',
                        '/queues/${summary['queueId']}/call-next',
                      ),
                      success: 'Next patient called.',
                      after: onChanged,
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: EcSpacing.lg),
        Text(
          updated == null
              ? ''
              : 'Updated ${updated!.hour.toString().padLeft(2, '0')}:${updated!.minute.toString().padLeft(2, '0')}:${updated!.second.toString().padLeft(2, '0')}',
          style: EcTypography.helper,
        ),
        const SizedBox(height: EcSpacing.sm),
        AsyncBody(
          value: entries,
          onRetry: () => ref.invalidate(listProvider(entriesQuery!)),
          builder: (rows) {
            if (rows.isEmpty) {
              return const EcEmptyState(
                title: 'Nobody checked in yet',
                message: 'Patients appear here after check-in or as walk-ins.',
              );
            }
            return Column(
              children: [
                for (final e in rows)
                  Padding(
                    padding: const EdgeInsets.only(bottom: EcSpacing.sm),
                    child: EcCard(
                      child: Row(
                        children: [
                          SizedBox(
                            width: 70,
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
                          const SizedBox(width: EcSpacing.sm),
                          ..._actions(
                            context,
                            e,
                            operate,
                            consult,
                            priority,
                            cancelCheckedIn,
                            act,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  List<Widget> _actions(
    BuildContext context,
    Map<String, Object?> e,
    bool operate,
    bool consult,
    bool priority,
    bool cancelCheckedIn,
    Future<void> Function(String, String, String, {Json? body}) act,
  ) {
    final id = '${e['entryId']}';
    final status = '${e['status']}';
    Widget b(String label, VoidCallback f) => Padding(
      padding: const EdgeInsetsDirectional.only(start: 4),
      child: TextButton(onPressed: f, child: Text(label)),
    );
    Future<void> withReason(
      String action,
      String title,
      String done,
      String confirm,
    ) async {
      final reason = await askReason(
        context,
        title: title,
        message: 'This is recorded in the queue history.',
        confirmLabel: confirm,
      );
      if (reason == null || !context.mounted) return;
      await act(id, action, done, body: {'reason': reason});
    }

    return [
      if (status == 'waiting' && operate)
        b('Call', () => act(id, 'call', 'Patient called.')),
      if (status == 'waiting' && operate)
        b('Skip', () => act(id, 'skip', 'Patient skipped.')),
      if (status == 'waiting' && priority)
        b('Priority', () async {
          final reason = await askReason(
            context,
            title: 'Give priority?',
            message: 'Only for urgent cases. The reason is recorded.',
            confirmLabel: 'Give priority',
          );
          if (reason == null || !context.mounted) return;
          await act(
            id,
            'priority',
            'Priority set.',
            body: {'priority': 'priority', 'reason': reason},
          );
        }),
      if (status == 'called' && operate)
        b('Recall', () => act(id, 'recall', 'Patient recalled.')),
      if (status == 'called' && consult)
        b('Start', () => act(id, 'start', 'Consultation started.')),
      if (status == 'called' && operate)
        b('Skip', () => act(id, 'skip', 'Patient skipped.')),
      if (status == 'called' && operate)
        b(
          'No-show',
          () => withReason(
            'no-show',
            'Mark as no-show?',
            'Marked as no-show.',
            'Mark no-show',
          ),
        ),
      if (status == 'skipped' && operate)
        b('Restore', () => act(id, 'restore', 'Patient back in the queue.')),
      if (status == 'in_progress' && consult)
        b('Complete', () => act(id, 'complete', 'Consultation completed.')),
      if ((status == 'waiting' || status == 'called' || status == 'skipped') &&
          operate &&
          cancelCheckedIn)
        b(
          'Cancel',
          () => withReason(
            'cancel',
            'Remove from queue?',
            'Removed from the queue.',
            'Remove',
          ),
        ),
    ];
  }
}

/// Appointment history of one patient (timeline tab).
class PatientAppointmentsTab extends ConsumerWidget {
  const PatientAppointmentsTab({required this.patientId, super.key});

  final String patientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final q = Query('/patients/$patientId/appointments', {'limit': '50'});
    return ListView(
      padding: const EdgeInsets.all(EcSpacing.lg),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Visits and bookings at this clinic, newest first. No clinical notes are shown here.',
                style: EcTypography.bodySecondary,
              ),
            ),
            if (can(ref, ClinicPermission.appointmentsBook))
              SizedBox(
                width: 300,
                child: EcSecondaryButton(
                  label: 'Book',
                  compact: true,
                  onPressed: () => context.go(
                    '/clinic/appointments/new?patientId=$patientId',
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: EcSpacing.md),
        AsyncBody(
          value: ref.watch(listProvider(q)),
          onRetry: () => ref.invalidate(listProvider(q)),
          builder: (rows) => rows.isEmpty
              ? const EcEmptyState(
                  title: 'No appointments',
                  message: 'This patient has no bookings yet.',
                )
              : Column(
                  children: [
                    for (final a in rows)
                      Padding(
                        padding: const EdgeInsets.only(bottom: EcSpacing.sm),
                        child: EcCard(
                          onTap: () => context.go(
                            '/clinic/appointments/${a['appointmentId']}',
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${a['localDate']} ${a['startTime']} · ${a['doctorName']}',
                                      style: EcTypography.bodyStrong,
                                    ),
                                    Text(
                                      '${a['typeName']} · ${Fmt.humanize(a['source'])}${a['tokenDisplay'] == null ? '' : ' · token ${a['tokenDisplay']}'}${a['cancelReason'] == null ? '' : ' · ${a['cancelReason']}'}${a['rescheduledToId'] == null ? '' : ' · rescheduled'}',
                                      style: EcTypography.bodySecondary,
                                    ),
                                  ],
                                ),
                              ),
                              apptStatus(a['status']),
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
}
