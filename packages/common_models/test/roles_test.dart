import 'package:common_models/common_models.dart';
import 'package:test/test.dart';

void main() {
  test('wire names are unique within each role enum', () {
    expect(
      ClinicRole.values.map((r) => r.wireName).toSet().length,
      ClinicRole.values.length,
    );
    expect(
      PlatformRole.values.map((r) => r.wireName).toSet().length,
      PlatformRole.values.length,
    );
    expect(
      PatientRole.values.map((r) => r.wireName).toSet().length,
      PatientRole.values.length,
    );
  });

  test('tryParse round-trips and rejects unknown values', () {
    for (final role in ClinicRole.values) {
      expect(ClinicRole.tryParse(role.wireName), role);
    }
    expect(ClinicRole.tryParse('root'), isNull);
    expect(ClinicRole.tryParse(null), isNull);
    expect(PlatformRole.tryParse('super_admin'), PlatformRole.superAdmin);
    expect(PatientRole.tryParse('patient'), PatientRole.patient);
  });
}
