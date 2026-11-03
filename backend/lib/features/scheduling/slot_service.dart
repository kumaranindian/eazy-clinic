import 'package:common_models/common_models.dart';

import '../../core/data/document_store.dart';
import '../../core/errors/api_exception.dart';
import '../clinic/common/tenant_context.dart';
import 'appointment_type_service.dart';
import 'availability_service.dart';
import 'scheduling_support.dart';
import 'time_support.dart';

/// Reservation granularity: one reservation document per doctor, date,
/// 5-minute cell and lane. A booking creates the reservations of its whole
/// time range together with the appointment, so two bookings can never hold
/// the same cell in the same lane, whatever their length or branch.
const int cellMinutes = 5;

int _cell(int minute) => minute ~/ cellMinutes;

/// One candidate start time.
class Slot {
  Slot(this.start, this.end, this.duration, this.buffer, this.free, this.lane);

  final int start;
  final int end;
  final int duration;
  final int buffer;

  /// True when a lane is free for the whole range.
  final bool free;
  final int? lane;

  int get reservedUntil => end + buffer;
}

class SlotComputation {
  SlotComputation({
    required this.zone,
    required this.plan,
    required this.slots,
    required this.duration,
    required this.buffer,
  });

  final ClinicZone zone;
  final DayPlan plan;
  final List<Slot> slots;
  final int duration;
  final int buffer;
}

/// Backend-controlled slot calculation. The client never generates slots and
/// booking re-runs the same calculation.
class SlotService {
  SlotService(this._s, this._avail, this._types);

  final SchedulingSupport _s;
  final AvailabilityService _avail;
  final AppointmentTypeService _types;

  static const int maxDaysAhead = 365;

  String reservationId(String doctorId, String date, int cell, int lane) =>
      '${doctorId}_${date}_${cell}_$lane';

  /// Reservations of the doctor on [date]: cell → occupied lanes.
  Future<Map<int, Set<int>>> occupancy(
    TenantContext t,
    String doctorId,
    String date, {
    TxContext? tx,
  }) async {
    final q = DocQuery(
      _s.d.path(t, 'appointment_slot_reservations'),
      filters: [
        QueryFilter('doctorId', FilterOp.eq, doctorId),
        QueryFilter('localDate', FilterOp.eq, date),
      ],
      limit: 1000,
    );
    final rows = tx == null ? await _s.d.store.query(q) : await tx.query(q);
    final out = <int, Set<int>>{};
    for (final r in rows) {
      (out[r.data['cell']! as int] ??= {}).add(r.data['lane']! as int);
    }
    return out;
  }

  /// First lane (1..capacity) free in every cell of [from, until) minutes.
  int? freeLane(Map<int, Set<int>> occ, int capacity, int from, int until) {
    for (var lane = 1; lane <= capacity; lane++) {
      var free = true;
      for (var c = _cell(from); c <= _cell(until - 1); c++) {
        if (occ[c]?.contains(lane) ?? false) {
          free = false;
          break;
        }
      }
      if (free) return lane;
    }
    return null;
  }

  /// Candidate slots of one date with their availability.
  Future<SlotComputation> compute(
    TenantContext t, {
    required DocData branch,
    required String doctorId,
    required String date,
    String? typeId,
    bool includeCurrent = false,
    TxContext? tx,
  }) async {
    final branchId = '${branch['branchId']}';
    final zone = await _s.zoneFor(t, branch);
    final now = _s.d.now;
    final today = zone.localDate(now);
    if (!Dates.valid(date)) {
      throw const ApiException.badRequest('date must be YYYY-MM-DD.');
    }
    if (date.compareTo(today) < 0) {
      throw const ApiException.conflict(
        'Appointments cannot be made in the past.',
      );
    }
    if (Dates.daysBetween(today, date) > maxDaysAhead) {
      throw const ApiException.conflict('That date is too far ahead.');
    }
    final plan = await _avail.dayPlan(t, doctorId, branchId, date);
    var duration = plan.defaultDuration;
    var buffer = plan.defaultBuffer;
    if (typeId != null) {
      final type = await _types.activeType(t, typeId);
      duration = plan.typeDurations[typeId] ?? (type['durationMinutes'] as int);
      buffer = (type['bufferMinutes'] as int?) ?? buffer;
    }
    if (plan.closed) {
      return SlotComputation(
        zone: zone,
        plan: plan,
        slots: const [],
        duration: duration,
        buffer: buffer,
      );
    }
    final occ = await occupancy(t, doctorId, date, tx: tx);
    final slots = <Slot>[];
    final step = duration + buffer;
    for (final s in plan.sessions) {
      for (var start = s.from; start + duration <= s.to; start += step) {
        final end = start + duration;
        if (plan.breaks.any((b) => b.overlaps(start, end))) continue;
        if (plan.blocks.any((b) => b.overlaps(start, end))) continue;
        final startUtc = zone.toUtc(date, start);
        final endUtc = zone.toUtc(date, end);
        final past = includeCurrent
            ? !endUtc.isAfter(now)
            : !startUtc.isAfter(now);
        if (past) continue;
        final lane = freeLane(occ, plan.capacity, start, end + buffer);
        slots.add(Slot(start, end, duration, buffer, lane != null, lane));
      }
    }
    return SlotComputation(
      zone: zone,
      plan: plan,
      slots: slots,
      duration: duration,
      buffer: buffer,
    );
  }

  /// `GET /appointments/available-slots`.
  Future<Map<String, Object?>> availableSlots(
    TenantContext t, {
    required String branchId,
    required String doctorId,
    required String date,
    String? typeId,
    bool includeFull = false,
  }) async {
    t.require(ClinicPermission.appointmentsView);
    _s.requireFeature(t);
    final branch = await _s.branch(t, branchId);
    await _s.assignedDoctor(t, doctorId, branchId);
    final c = await compute(
      t,
      branch: branch,
      doctorId: doctorId,
      date: date,
      typeId: typeId,
    );
    return {
      'date': date,
      'branchId': branchId,
      'doctorId': doctorId,
      'timezone': c.zone.name,
      'durationMinutes': c.duration,
      'bufferMinutes': c.buffer,
      'day': c.plan.toJson(),
      'slots': [
        for (final s in c.slots)
          if (s.free || includeFull)
            {
              'startTime': Hm.format(s.start),
              'endTime': Hm.format(s.end),
              'startUtc': c.zone.toUtc(date, s.start).toIso8601String(),
              'endUtc': c.zone.toUtc(date, s.end).toIso8601String(),
              'available': s.free,
            },
      ],
    };
  }
}
