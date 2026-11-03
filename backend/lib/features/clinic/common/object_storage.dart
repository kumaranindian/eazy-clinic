import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../../core/data/document_store.dart';

/// Private object storage (Cloud Storage in production). Objects are never
/// public: they are served through authenticated, tenant-checked endpoints.
abstract interface class ObjectStorage {
  Future<void> put(String path, Uint8List bytes, String contentType);

  /// `null` when the object does not exist.
  Future<(Uint8List, String)?> get(String path);
}

/// Cloud Storage JSON API client. [client] must carry service-account
/// credentials (ADC); nothing is ever exposed to Flutter apps.
class GcsObjectStorage implements ObjectStorage {
  GcsObjectStorage({
    required this.bucket,
    required http.Client client,
    this.host = 'https://storage.googleapis.com',
  }) : _client = client;

  final String bucket;
  final String host;
  final http.Client _client;

  @override
  Future<void> put(String path, Uint8List bytes, String contentType) async {
    final r = await _client.post(
      Uri.parse(
        '$host/upload/storage/v1/b/$bucket/o?uploadType=media&name=${Uri.encodeQueryComponent(path)}',
      ),
      headers: {'content-type': contentType},
      body: bytes,
    );
    if (r.statusCode != 200) {
      throw StoreException('Object upload failed (${r.statusCode}).');
    }
  }

  @override
  Future<(Uint8List, String)?> get(String path) async {
    final r = await _client.get(
      Uri.parse(
        '$host/storage/v1/b/$bucket/o/${Uri.encodeComponent(path)}?alt=media',
      ),
    );
    if (r.statusCode == 404) return null;
    if (r.statusCode != 200) {
      throw StoreException('Object download failed (${r.statusCode}).');
    }
    return (
      r.bodyBytes,
      r.headers['content-type'] ?? 'application/octet-stream',
    );
  }
}

/// Detects PNG / JPEG / WebP from the bytes themselves (the declared content
/// type is never trusted). Returns the canonical type or `null`.
String? sniffImageType(Uint8List b) {
  if (b.length >= 8 &&
      b[0] == 0x89 &&
      b[1] == 0x50 &&
      b[2] == 0x4E &&
      b[3] == 0x47 &&
      b[4] == 0x0D &&
      b[5] == 0x0A &&
      b[6] == 0x1A &&
      b[7] == 0x0A) {
    return 'image/png';
  }
  if (b.length >= 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) {
    return 'image/jpeg';
  }
  if (b.length >= 12 &&
      utf8.decode(b.sublist(0, 4), allowMalformed: true) == 'RIFF' &&
      utf8.decode(b.sublist(8, 12), allowMalformed: true) == 'WEBP') {
    return 'image/webp';
  }
  return null;
}
