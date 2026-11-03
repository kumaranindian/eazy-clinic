import 'package:test/test.dart';
import 'package:validation/validation.dart';

void main() {
  test('required', () {
    expect(Validators.required('  ')!.code, 'required');
    expect(Validators.required('x'), isNull);
  });

  test('email', () {
    expect(Validators.email('a@b.co'), isNull);
    expect(Validators.email('a@b')!.code, 'invalid_email');
    expect(Validators.email('')!.code, 'required');
  });

  test('indianMobile', () {
    expect(Validators.indianMobile('98765 43210'), isNull);
    expect(Validators.indianMobile('+91-9876543210'), isNull);
    expect(Validators.indianMobile('1234567890')!.code, 'invalid_phone');
    expect(Validators.indianMobile('98765')!.code, 'invalid_phone');
    expect(Validators.indianMobile(null)!.code, 'required');
  });

  test('password', () {
    expect(Validators.password('abc12345'), isNull);
    expect(Validators.password('short1')!.code, 'weak_password');
    expect(Validators.password('onlyletters')!.code, 'weak_password');
  });

  test('compose returns the first failure', () {
    final v = Validators.compose([
      (s) => Validators.required(s, field: 'Name'),
      Validators.minLength(3, field: 'Name'),
    ]);
    expect(v('')!.code, 'required');
    expect(v('ab')!.code, 'too_short');
    expect(v('abc'), isNull);
  });
}
