import 'dart:typed_data';

import 'package:app_core/app_core.dart';
import 'package:common_models/common_models.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../control_plane/data/control_plane_repository.dart';
import '../control_plane/providers.dart' show noRetry;

/// The caller's role, permissions, branch scope and authorised branches in the
/// current clinic, straight from the backend. UI hints only: every API call is
/// authorised again by the backend.
final clinicAccessProvider = FutureProvider.autoDispose<Json>(
  retry: noRetry,
  (ref) => ref
      .watch(controlPlaneRepositoryProvider)
      .getMap('/members/current/permissions'),
);

final clinicPermissionsProvider = Provider.autoDispose<Set<String>>((ref) {
  final v = ref.watch(clinicAccessProvider).asData?.value;
  return {...((v?['permissions'] as List?) ?? const []).cast<String>()};
});

bool can(WidgetRef ref, String permission) =>
    ref.watch(clinicPermissionsProvider).contains(permission);

/// Navigation context only. Choosing a branch filters what is *shown*; it
/// never grants access (the backend checks the membership scope).
class ActiveBranch extends Notifier<String?> {
  @override
  String? build() => null;
  // ignore: use_setters_to_change_properties
  void select(String? branchId) => state = branchId;
}

final activeBranchProvider = NotifierProvider<ActiveBranch, String?>(
  ActiveBranch.new,
);

final clinicProfileProvider = FutureProvider.autoDispose<Json>(
  retry: noRetry,
  (ref) => ref.watch(controlPlaneRepositoryProvider).getMap('/clinics/current'),
);

final clinicSettingsProvider = FutureProvider.autoDispose<Json>(
  retry: noRetry,
  (ref) => ref
      .watch(controlPlaneRepositoryProvider)
      .getMap('/clinics/current/settings'),
);

final clinicLogoProvider = FutureProvider.autoDispose<Uint8List?>(
  retry: noRetry,
  (ref) async {
    try {
      return await ref.watch(controlPlaneRepositoryProvider).logoBytes();
    } on ApiFailure catch (e) {
      if (e.code == null || e.code!.httpStatus == 404) return null;
      rethrow;
    }
  },
);

final branchDetailProvider = FutureProvider.autoDispose.family<Json, String>(
  retry: noRetry,
  (ref, id) =>
      ref.watch(controlPlaneRepositoryProvider).getMap('/branches/$id'),
);

final doctorDetailProvider = FutureProvider.autoDispose.family<Json, String>(
  retry: noRetry,
  (ref, id) => ref.watch(controlPlaneRepositoryProvider).getMap('/doctors/$id'),
);

final staffDetailProvider = FutureProvider.autoDispose.family<Json, String>(
  retry: noRetry,
  (ref, id) => ref.watch(controlPlaneRepositoryProvider).getMap('/staff/$id'),
);

final rolesProvider = FutureProvider.autoDispose<List<Json>>(
  retry: noRetry,
  (ref) => ref.watch(controlPlaneRepositoryProvider).getList('/roles'),
);

final permissionCatalogProvider = FutureProvider.autoDispose<Json>(
  retry: noRetry,
  (ref) => ref.watch(controlPlaneRepositoryProvider).getMap('/permissions'),
);

/// Branches the caller may pick from (pickers, filters).
final branchChoicesProvider = FutureProvider.autoDispose<List<Json>>(
  retry: noRetry,
  (ref) => ref.watch(controlPlaneRepositoryProvider).getList('/branches', {
    'limit': '100',
  }),
);

/// Logo file picker, replaceable in tests.
class PickedImage {
  const PickedImage(this.bytes, this.contentType);
  final Uint8List bytes;
  final String contentType;
}

final logoPickerProvider = Provider<Future<PickedImage?> Function()>(
  (ref) => () async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'Images',
          extensions: ['png', 'jpg', 'jpeg', 'webp'],
          mimeTypes: ['image/png', 'image/jpeg', 'image/webp'],
        ),
      ],
    );
    if (file == null) return null;
    final name = file.name.toLowerCase();
    final type = name.endsWith('.png')
        ? 'image/png'
        : name.endsWith('.webp')
        ? 'image/webp'
        : 'image/jpeg';
    return PickedImage(await file.readAsBytes(), type);
  },
);

/// Roles shown in pickers (the owner role is never assignable).
const assignableRoles = [
  ClinicRole.clinicAdmin,
  ClinicRole.doctor,
  ClinicRole.receptionist,
  ClinicRole.nurse,
  ClinicRole.accountant,
  ClinicRole.labTechnician,
  ClinicRole.pharmacist,
];
