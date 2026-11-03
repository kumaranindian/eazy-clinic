import 'dart:convert';
import 'dart:typed_data';

import 'package:api_contracts/api_contracts.dart';

import '../../../core/data/document_store.dart';
import '../../../core/errors/api_exception.dart';
import '../../platform/applications/application_service.dart' show clinicTypes;
import '../../platform/audit/audit_service.dart';
import '../../platform/common/body_reader.dart';
import '../../platform/common/paging.dart';
import '../common/clinic_deps.dart';
import '../common/object_storage.dart';
import '../common/tenant_context.dart';
import 'operating_hours.dart';

const List<String> supportedLanguages = [
  'en',
  'hi',
  'mr',
  'ta',
  'te',
  'bn',
  'gu',
  'kn',
  'ml',
  'pa',
];
const List<String> supportedCurrencies = ['INR'];
const int maxLogoBytes = 512 * 1024;

/// Clinic profile, regional/operating settings and logo.
///
/// Tenant identity (`tenantId`, owner, status, slug, subscription) and the
/// registration-verification status are never writable here: unknown or
/// protected fields are rejected with 422.
class ClinicService {
  ClinicService(this._d, this._storage);

  final ClinicDeps _d;
  final ObjectStorage _storage;

  static const Set<String> profileFields = {
    'name',
    'type',
    'specialities',
    'registrationNumber',
    'description',
    'email',
    'alternateEmail',
    'phone',
    'alternatePhone',
    'website',
    'address',
  };
  static const Set<String> settingsFields = {
    'timezone',
    'currency',
    'language',
    'appointmentDurationMinutes',
    'consultationDurationMinutes',
    'weeklyHours',
    'holidays',
    'specialDays',
    'doctorRegistrationRequired',
    'minorAgeYears',
  };

  String _profilePath(TenantContext t) =>
      _d.path(t, 'clinic_settings', 'profile');
  String _settingsPath(TenantContext t) =>
      _d.path(t, 'clinic_settings', 'operations');

  // ---------------------------------------------------------------- profile

  Future<Map<String, Object?>> getProfile(TenantContext t) async {
    final tenant = await _d.store.get('tenants/${t.tenantId}');
    if (tenant == null) throw const ApiException.notFound('Clinic not found.');
    final stored = await _d.store.get(_profilePath(t));
    final app = await _d.store.get(
      'clinic_applications/${tenant['applicationId']}',
    );
    final clinic =
        (app?['clinic'] as Map?)?.cast<String, Object?>() ?? const {};
    final address =
        (app?['address'] as Map?)?.cast<String, Object?>() ?? const {};
    final profile = <String, Object?>{
      // defaults come from the approved application until the clinic edits them
      'name': tenant['clinicName'],
      'type': tenant['clinicType'],
      'specialities': <String>[],
      'registrationNumber': clinic['registrationNumber'],
      'description': clinic['description'],
      'email': clinic['email'],
      'alternateEmail': null,
      'phone': clinic['phone'],
      'alternatePhone': null,
      'website': clinic['website'],
      'address': address,
      ...?stored,
    };
    return {
      'tenantId': t.tenantId,
      'slug': tenant['slug'],
      'status': tenant['status'],
      'verificationStatus': stored?['verificationStatus'] ?? 'unverified',
      'logo': stored?['logo'],
      'profile': {for (final k in profileFields) k: profile[k]},
      'updatedAt': jsonSafe(stored?['updatedAt']),
    };
  }

  Future<Map<String, Object?>> updateProfile(
    TenantContext t,
    Map<String, Object?> body,
    Actor actor, {
    String? requestId,
  }) async {
    final r = BodyReader(body, partial: true)..rejectUnknown(profileFields);
    final name = r.str('name', min: 2, max: 120);
    final type = r.str('type', max: 40);
    if (type != null && !clinicTypes.contains(type)) {
      r.addIssue('type', 'invalid_value', 'Unsupported clinic type.');
    }
    List<String>? specialities;
    if (body.containsKey('specialities')) {
      final raw = body['specialities'];
      if (raw is! List ||
          raw.length > 10 ||
          raw.any((e) => e is! String || e.trim().isEmpty || e.length > 60)) {
        r.addIssue(
          'specialities',
          'invalid_value',
          'Up to 10 specialities of 1-60 characters.',
        );
      } else {
        specialities = raw.map((e) => (e as String).trim()).toList();
      }
    }
    final registration = r.str('registrationNumber', max: 50, required: false);
    final description = r.str(
      'description',
      min: 0,
      max: 1000,
      required: false,
    );
    final email = r.email('email', required: false);
    final altEmail = r.email('alternateEmail', required: false);
    final phone = r.phone('phone', required: false);
    final altPhone = r.phone('alternatePhone', required: false);
    final website = r.str('website', max: 200, required: false);
    if (website != null) {
      final u = Uri.tryParse(website);
      if (u == null ||
          !(u.scheme == 'http' || u.scheme == 'https') ||
          u.host.isEmpty) {
        r.addIssue('website', 'invalid_url', 'website must be an http(s) URL.');
      }
    }
    Map<String, Object?>? address;
    final a = r.object('address', required: false);
    if (a != null) {
      a.rejectUnknown({
        'line1',
        'line2',
        'city',
        'state',
        'country',
        'postalCode',
      });
      final country = a.str('country', min: 2, max: 60);
      final postal = a.str('postalCode', min: 3, max: 10);
      if (postal != null &&
          (country ?? 'india').toLowerCase() == 'india' &&
          !RegExp(r'^[1-9][0-9]{5}$').hasMatch(postal)) {
        a.addIssue(
          'postalCode',
          'invalid_postal_code',
          'Enter a valid 6-digit PIN code.',
        );
      }
      address = {
        for (final e in {
          'line1': a.str('line1', min: 3, max: 120),
          'line2': a.str('line2', max: 120, required: false),
          'city': a.str('city', min: 2, max: 60),
          'state': a.str('state', min: 2, max: 60),
          'country': country,
          'postalCode': postal,
        }.entries)
          if (e.value != null) e.key: e.value,
      };
    }
    r.throwIfInvalid();

    final changes = <String, Object?>{
      'name': ?name,
      'type': ?type,
      'specialities': ?specialities,
      'registrationNumber': ?registration,
      'description': ?description,
      'email': ?email,
      'alternateEmail': ?altEmail,
      'phone': ?phone,
      'alternatePhone': ?altPhone,
      'website': ?website,
    };
    if (changes.isEmpty && address == null) {
      throw const ApiException.badRequest('No profile fields to update.');
    }
    final now = _d.now;
    final defaults = await getProfile(t);
    await _d.store.transaction((tx) async {
      final existing = await tx.get(_profilePath(t));
      final baseAddress =
          (existing?['address'] ?? (defaults['profile']! as Map)['address'])
              as Map?;
      final mergedAddress = {
        ...?baseAddress?.cast<String, Object?>(),
        ...?address,
      };
      final patch = {
        ...changes,
        if (address != null) 'address': mergedAddress,
        'updatedAt': now,
        'updatedBy': t.uid,
      };
      tx.write([
        if (existing == null)
          CreateOp(_profilePath(t), {
            'verificationStatus': 'unverified',
            'createdAt': now,
            ...patch,
          })
        else
          UpdateOp(_profilePath(t), patch),
        // keep the platform's tenant record searchable under the new name
        if (name != null || type != null)
          UpdateOp('tenants/${t.tenantId}', {
            if (name != null) 'clinicName': name,
            if (name != null) 'clinicNameLower': name.toLowerCase(),
            'clinicType': ?type,
            'updatedAt': now,
          }),
        _d.audit.op(
          AuditEntry(
            actor: actor,
            action: 'clinic.profile_updated',
            targetType: 'clinic',
            targetId: t.tenantId,
            tenantId: t.tenantId,
            requestId: requestId,
            after: {
              'fields': [...changes.keys, if (address != null) 'address'],
            },
          ),
        ),
      ]);
    });
    return getProfile(t);
  }

  // --------------------------------------------------------------- settings

  Map<String, Object?> _defaultSettings() => {
    'timezone': null,
    'currency': 'INR',
    'language': 'en',
    'appointmentDurationMinutes': 15,
    'consultationDurationMinutes': 15,
    'weeklyHours': {
      for (var d = 1; d <= 7; d++) '$d': {'open': false},
    },
    'holidays': <Object?>[],
    'specialDays': <Object?>[],
    'doctorRegistrationRequired': true,
    // Age below which a patient is treated as a minor (guardian consent).
    'minorAgeYears': 18,
  };

  Future<Map<String, Object?>> getSettings(TenantContext t) async {
    final stored = await _d.store.get(_settingsPath(t));
    final s = {..._defaultSettings(), ...?stored};
    return {
      'configured': s['timezone'] != null,
      for (final k in settingsFields) k: jsonSafe(s[k]),
      'updatedAt': jsonSafe(stored?['updatedAt']),
    };
  }

  static final RegExp _tz = RegExp(
    r'^[A-Za-z][A-Za-z_]*(/[A-Za-z0-9_+\-]+){1,2}$|^UTC$',
  );

  Future<Map<String, Object?>> updateSettings(
    TenantContext t,
    Map<String, Object?> body,
    Actor actor, {
    String? requestId,
  }) async {
    final r = BodyReader(body, partial: true)..rejectUnknown(settingsFields);
    final tz = r.str('timezone', max: 64);
    if (tz != null && !_tz.hasMatch(tz)) {
      r.addIssue(
        'timezone',
        'invalid_timezone',
        'Use an IANA time zone such as Asia/Kolkata.',
      );
    }
    final currency = r.str('currency', min: 3, max: 3);
    if (currency != null && !supportedCurrencies.contains(currency)) {
      r.addIssue('currency', 'unsupported', 'Unsupported currency.');
    }
    final language = r.str('language', min: 2, max: 5);
    if (language != null && !supportedLanguages.contains(language)) {
      r.addIssue('language', 'unsupported', 'Unsupported language.');
    }
    final appt = r.integer(
      'appointmentDurationMinutes',
      min: 5,
      max: 240,
      required: false,
    );
    final consult = r.integer(
      'consultationDurationMinutes',
      min: 5,
      max: 240,
      required: false,
    );
    final regRequired = r.boolean('doctorRegistrationRequired');
    final minorAge = r.integer(
      'minorAgeYears',
      min: 1,
      max: 25,
      required: false,
    );
    final hours = HoursParser(r);
    final weekly = body.containsKey('weeklyHours')
        ? hours.weekly(body['weeklyHours'], 'weeklyHours')
        : null;
    final holidays = body.containsKey('holidays')
        ? hours.holidays(body['holidays'], 'holidays')
        : null;
    final existing = await _d.store.get(_settingsPath(t));
    final holidayDates = {
      for (final h
          in (holidays ??
              (existing?['holidays'] as List?) ??
              const <Object?>[]))
        (h as Map)['date'] as String,
    };
    final special = body.containsKey('specialDays')
        ? hours.specialDays(body['specialDays'], 'specialDays', holidayDates)
        : null;
    r.throwIfInvalid();

    final changes = <String, Object?>{
      'timezone': ?tz,
      'currency': ?currency,
      'language': ?language,
      'appointmentDurationMinutes': ?appt,
      'consultationDurationMinutes': ?consult,
      'doctorRegistrationRequired': ?regRequired,
      'minorAgeYears': ?minorAge,
      'weeklyHours': ?weekly,
      'holidays': ?holidays,
      'specialDays': ?special,
    };
    if (changes.isEmpty) {
      throw const ApiException.badRequest('No settings to update.');
    }
    final now = _d.now;
    final path = _settingsPath(t);
    await _d.store.transaction((tx) async {
      final cur = await tx.get(path);
      final patch = {...changes, 'updatedAt': now, 'updatedBy': t.uid};
      // holidays and special days must stay disjoint after a partial update
      final allHolidays = {
        for (final h
            in (holidays ?? (cur?['holidays'] as List?) ?? const <Object?>[]))
          (h as Map)['date'],
      };
      final allSpecial =
          (special ?? (cur?['specialDays'] as List?) ?? const <Object?>[]);
      if (allSpecial.any((s) => allHolidays.contains((s as Map)['date']))) {
        throw ApiException.validation([
          _issue(
            'specialDays',
            'conflict',
            'A date cannot be both a holiday and a special working day.',
          ),
        ]);
      }
      tx.write([
        if (cur == null)
          CreateOp(path, {..._defaultSettings(), ...patch, 'createdAt': now})
        else
          UpdateOp(path, patch),
        _d.audit.op(
          AuditEntry(
            actor: actor,
            action: 'clinic.settings_updated',
            targetType: 'clinic',
            targetId: t.tenantId,
            tenantId: t.tenantId,
            requestId: requestId,
            after: {'fields': changes.keys.toList()},
          ),
        ),
      ]);
    });
    return getSettings(t);
  }

  // ------------------------------------------------------------------- logo

  String logoPath(TenantContext t, String ext) =>
      'tenants/${t.tenantId}/branding/clinic-logo/logo.$ext';

  Future<Map<String, Object?>> putLogo(
    TenantContext t,
    Map<String, Object?> body,
    Actor actor, {
    String? requestId,
  }) async {
    final r = BodyReader(body)..rejectUnknown({'contentType', 'dataBase64'});
    final declared = r.str('contentType', max: 40);
    final data = r.str('dataBase64', max: (maxLogoBytes * 4 ~/ 3) + 16);
    r.throwIfInvalid();
    final Uint8List bytes;
    try {
      bytes = base64Decode(data!);
    } on FormatException {
      throw ApiException.validation([
        _issue(
          'dataBase64',
          'invalid_base64',
          'The image data is not valid base64.',
        ),
      ]);
    }
    if (bytes.isEmpty || bytes.length > maxLogoBytes) {
      throw ApiException.validation([
        _issue(
          'dataBase64',
          'too_large',
          'The logo must be between 1 byte and 512 KB.',
        ),
      ]);
    }
    final real = sniffImageType(bytes);
    if (real == null || real != declared) {
      throw ApiException.validation([
        _issue(
          'contentType',
          'invalid_image',
          'The logo must be a PNG, JPEG or WebP image.',
        ),
      ]);
    }
    final ext = switch (real) {
      'image/png' => 'png',
      'image/jpeg' => 'jpg',
      _ => 'webp',
    };
    final path = logoPath(t, ext);
    await _storage.put(path, bytes, real);
    final now = _d.now;
    final logo = {
      'path': path,
      'contentType': real,
      'size': bytes.length,
      'updatedAt': now,
    };
    await _d.store.transaction((tx) async {
      final cur = await tx.get(_profilePath(t));
      tx.write([
        if (cur == null)
          CreateOp(_profilePath(t), {
            'verificationStatus': 'unverified',
            'createdAt': now,
            'logo': logo,
            'updatedAt': now,
            'updatedBy': t.uid,
          })
        else
          UpdateOp(_profilePath(t), {
            'logo': logo,
            'updatedAt': now,
            'updatedBy': t.uid,
          }),
        _d.audit.op(
          AuditEntry(
            actor: actor,
            action: 'clinic.logo_updated',
            targetType: 'clinic',
            targetId: t.tenantId,
            tenantId: t.tenantId,
            requestId: requestId,
            after: {'contentType': real, 'size': bytes.length},
          ),
        ),
      ]);
    });
    return jsonSafe(logo)! as Map<String, Object?>;
  }

  /// Logo bytes for the caller's own clinic (path comes from our own record).
  Future<(Uint8List, String)?> getLogo(TenantContext t) async {
    final profile = await _d.store.get(_profilePath(t));
    final path = (profile?['logo'] as Map?)?['path'] as String?;
    if (path == null || !path.startsWith('tenants/${t.tenantId}/branding/')) {
      return null;
    }
    return _storage.get(path);
  }
}

FieldIssue _issue(String f, String c, String m) =>
    FieldIssue(field: f, code: c, message: m);
