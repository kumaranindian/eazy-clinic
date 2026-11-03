import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../control_plane/data/control_plane_repository.dart';
import '../control_plane/providers.dart' show noRetry;

final patientDetailProvider = FutureProvider.autoDispose.family<Json, String>(
  retry: noRetry,
  (ref, id) =>
      ref.watch(controlPlaneRepositoryProvider).getMap('/patients/$id'),
);

final emergencyContactsProvider = FutureProvider.autoDispose
    .family<Json, String>(
      retry: noRetry,
      (ref, id) => ref
          .watch(controlPlaneRepositoryProvider)
          .getMap('/patients/$id/emergency-contacts'),
    );

/// Consent purposes with the exact text and version the patient must be shown.
final consentCatalogProvider = FutureProvider.autoDispose<Json>(
  retry: noRetry,
  (ref) => ref.watch(controlPlaneRepositoryProvider).getMap('/consent-catalog'),
);

class PickedDocument {
  const PickedDocument(this.name, this.bytes, this.contentType);
  final String name;
  final Uint8List bytes;
  final String contentType;
}

/// Document file picker, replaceable in tests.
final documentPickerProvider = Provider<Future<PickedDocument?> Function()>(
  (ref) => () async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'Documents',
          extensions: ['pdf', 'png', 'jpg', 'jpeg', 'webp'],
          mimeTypes: [
            'application/pdf',
            'image/png',
            'image/jpeg',
            'image/webp',
          ],
        ),
      ],
    );
    if (file == null) return null;
    final name = file.name.toLowerCase();
    final type = name.endsWith('.pdf')
        ? 'application/pdf'
        : name.endsWith('.png')
        ? 'image/png'
        : name.endsWith('.webp')
        ? 'image/webp'
        : 'image/jpeg';
    return PickedDocument(file.name, await file.readAsBytes(), type);
  },
);
