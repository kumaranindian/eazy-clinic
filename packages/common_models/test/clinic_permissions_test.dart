import 'package:common_models/common_models.dart';
import 'package:test/test.dart';

void main() {
  const billing = [
    ClinicPermission.billingView,
    ClinicPermission.billingCreate,
    ClinicPermission.billingEditDraft,
    ClinicPermission.billingFinalize,
    ClinicPermission.billingCancel,
    ClinicPermission.billingApplyDiscount,
    ClinicPermission.billingAdjust,
    ClinicPermission.billingSettingsManage,
    ClinicPermission.paymentView,
    ClinicPermission.paymentCollect,
    ClinicPermission.paymentAllocate,
    ClinicPermission.paymentRecordAdvance,
    ClinicPermission.refundRequest,
    ClinicPermission.refundApprove,
    ClinicPermission.refundProcess,
    ClinicPermission.expenseView,
    ClinicPermission.expenseCreate,
    ClinicPermission.expenseEdit,
    ClinicPermission.expenseApprove,
    ClinicPermission.expenseReject,
    ClinicPermission.expensePay,
    ClinicPermission.financeReportsView,
    ClinicPermission.financeReportsExport,
    ClinicPermission.serviceCatalogueManage,
  ];

  test('every Phase 7 permission is in the catalog exactly once', () {
    for (final p in billing) {
      expect(
        ClinicPermission.all.where((x) => x == p),
        hasLength(1),
        reason: p,
      );
    }
    expect(
      ClinicPermission.all.toSet(),
      hasLength(ClinicPermission.all.length),
    );
  });

  test('the owner holds every billing permission', () {
    for (final p in billing) {
      expect(
        ClinicRolePolicy.roleHas(ClinicRole.clinicOwner, p),
        isTrue,
        reason: p,
      );
    }
  });

  test('the admin runs the money side, including approvals', () {
    for (final p in billing) {
      expect(
        ClinicRolePolicy.roleHas(ClinicRole.clinicAdmin, p),
        isTrue,
        reason: p,
      );
    }
  });

  test(
    'the accountant collects, adjusts, pays and reports but approves nothing',
    () {
      for (final p in [
        ClinicPermission.billingView,
        ClinicPermission.billingFinalize,
        ClinicPermission.billingCancel,
        ClinicPermission.billingAdjust,
        ClinicPermission.billingApplyDiscount,
        ClinicPermission.paymentCollect,
        ClinicPermission.refundRequest,
        ClinicPermission.refundProcess,
        ClinicPermission.expenseCreate,
        ClinicPermission.expensePay,
        ClinicPermission.financeReportsView,
        ClinicPermission.financeReportsExport,
      ]) {
        expect(
          ClinicRolePolicy.roleHas(ClinicRole.accountant, p),
          isTrue,
          reason: p,
        );
      }
      for (final p in [
        ClinicPermission.refundApprove,
        ClinicPermission.expenseApprove,
        ClinicPermission.expenseReject,
        ClinicPermission.serviceCatalogueManage,
        ClinicPermission.billingSettingsManage,
      ]) {
        expect(
          ClinicRolePolicy.roleHas(ClinicRole.accountant, p),
          isFalse,
          reason: p,
        );
      }
    },
  );

  test(
    'the receptionist bills and collects but cannot discount, adjust, approve or see finance',
    () {
      for (final p in [
        ClinicPermission.billingCreate,
        ClinicPermission.billingFinalize,
        ClinicPermission.paymentCollect,
        ClinicPermission.paymentRecordAdvance,
        ClinicPermission.refundRequest,
      ]) {
        expect(
          ClinicRolePolicy.roleHas(ClinicRole.receptionist, p),
          isTrue,
          reason: p,
        );
      }
      for (final p in [
        ClinicPermission.billingApplyDiscount,
        ClinicPermission.billingAdjust,
        ClinicPermission.billingCancel,
        ClinicPermission.refundApprove,
        ClinicPermission.refundProcess,
        ClinicPermission.expenseView,
        ClinicPermission.financeReportsView,
        ClinicPermission.serviceCatalogueManage,
      ]) {
        expect(
          ClinicRolePolicy.roleHas(ClinicRole.receptionist, p),
          isFalse,
          reason: p,
        );
      }
    },
  );

  test('clinical and support roles hold no billing permission', () {
    for (final role in [
      ClinicRole.doctor,
      ClinicRole.nurse,
      ClinicRole.labTechnician,
      ClinicRole.pharmacist,
    ]) {
      for (final p in billing) {
        expect(
          ClinicRolePolicy.roleHas(role, p),
          isFalse,
          reason: '${role.wireName} $p',
        );
      }
    }
  });

  test('no platform permission can appear in a clinic role', () {
    for (final role in ClinicRole.values) {
      for (final p in ClinicRolePolicy.permissionsFor(role)) {
        expect(p.startsWith('platform.'), isFalse);
        expect(ClinicPermission.isKnown(p), isTrue);
      }
    }
  });
}
