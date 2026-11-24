import '../../../core/data/document_store.dart';
import '../../platform/audit/audit_service.dart';
import '../../platform/countries/country_directory.dart';
import '../../platform/entitlements/entitlement_service.dart';
import 'seat_service.dart';
import 'tenant_context.dart';

/// Shared collaborators of the clinic-administration services.
class ClinicDeps {
  ClinicDeps({
    required this.store,
    required this.audit,
    required this.seats,
    required this.entitlements,
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;

  final DocumentStore store;
  final AuditService audit;
  final SeatService seats;
  final EntitlementService entitlements;
  final DateTime Function() clock;

  /// Country master access (Phase 12). Created from [store] so existing
  /// construction sites keep working.
  late final CountryDirectory countries = CountryDirectory(store, clock: clock);

  DateTime get now => clock().toUtc();

  Actor actorOf(TenantContext t) => Actor(t.uid, t.actorLabel);

  /// Path of a tenant-scoped document. Every path is built from the tenant id
  /// of the caller's membership, never from request input.
  String path(TenantContext t, String collection, [String? id]) =>
      'tenants/${t.tenantId}/$collection${id == null ? '' : '/$id'}';
}
