import 'roles.dart';

/// Tenant-level (clinic) permission catalog. This is an allow-list: platform
/// permissions (`platform.*`) can never appear here, so a clinic role can
/// never carry one. Enforced by the backend on every request.
abstract final class ClinicPermission {
  static const String clinicView = 'clinic.view';
  static const String clinicUpdate = 'clinic.update';
  static const String clinicSettingsManage = 'clinic.settings.manage';

  static const String branchesView = 'branches.view';
  static const String branchesCreate = 'branches.create';
  static const String branchesUpdate = 'branches.update';
  static const String branchesActivate = 'branches.activate';
  static const String branchesDeactivate = 'branches.deactivate';

  static const String doctorsView = 'doctors.view';
  static const String doctorsCreate = 'doctors.create';
  static const String doctorsUpdate = 'doctors.update';
  static const String doctorsActivate = 'doctors.activate';
  static const String doctorsAssignBranch = 'doctors.assign_branch';

  static const String staffView = 'staff.view';
  static const String staffCreate = 'staff.create';
  static const String staffUpdate = 'staff.update';
  static const String staffInvite = 'staff.invite';
  static const String staffActivate = 'staff.activate';
  static const String staffDeactivate = 'staff.deactivate';
  static const String staffAssignRole = 'staff.assign_role';
  static const String staffAssignBranch = 'staff.assign_branch';

  static const String rolesView = 'roles.view';
  static const String rolesManage = 'roles.manage';
  static const String permissionsView = 'permissions.view';

  // Phase 4: patients (clinic-specific records)
  static const String patientsView = 'patients.view';
  static const String patientsCreate = 'patients.create';
  static const String patientsUpdate = 'patients.update';
  static const String patientsStatus = 'patients.status';
  static const String patientsLinkAccount = 'patients.link_account';
  static const String patientsDuplicates = 'patients.duplicates';
  static const String historyView = 'history.view';
  static const String historyManage = 'history.manage';
  static const String allergiesView = 'allergies.view';
  static const String allergiesManage = 'allergies.manage';
  static const String medicationsView = 'medications.view';
  static const String medicationsManage = 'medications.manage';
  static const String alertsView = 'alerts.view';
  static const String alertsManage = 'alerts.manage';
  static const String consentsView = 'consents.view';
  static const String consentsManage = 'consents.manage';
  static const String patientDocumentsView = 'patient_documents.view';
  static const String patientDocumentsManage = 'patient_documents.manage';
  static const String patientAuditView = 'patient_audit.view';

  // Phase 5: scheduling and queue
  static const String appointmentTypesView = 'appointment_types.view';
  static const String appointmentTypesManage = 'appointment_types.manage';
  static const String availabilityView = 'availability.view';
  static const String availabilityManage = 'availability.manage';
  static const String availabilityManageOwn = 'availability.manage_own';
  static const String appointmentsView = 'appointments.view';
  static const String appointmentsBook = 'appointments.book';
  static const String appointmentsManage = 'appointments.manage';
  static const String appointmentsCheckIn = 'appointments.check_in';
  static const String appointmentsConsult = 'appointments.consult';
  static const String appointmentsCancelCheckedIn =
      'appointments.cancel_checked_in';
  static const String queueView = 'queue.view';
  static const String queueOperate = 'queue.operate';
  static const String queueConsult = 'queue.consult';
  static const String queuePriority = 'queue.priority';

  // Phase 7: billing, payments, refunds, expenses, finance reports
  static const String billingView = 'billing.view';
  static const String billingCreate = 'billing.create';
  static const String billingEditDraft = 'billing.edit_draft';
  static const String billingFinalize = 'billing.finalize';
  static const String billingCancel = 'billing.cancel';
  static const String billingApplyDiscount = 'billing.apply_discount';
  static const String billingAdjust = 'billing.adjust';
  static const String billingSettingsManage = 'billing.settings.manage';
  static const String paymentView = 'payment.view';
  static const String paymentCollect = 'payment.collect';
  static const String paymentAllocate = 'payment.allocate';
  static const String paymentRecordAdvance = 'payment.record_advance';
  static const String refundRequest = 'refund.request';
  static const String refundApprove = 'refund.approve';
  static const String refundProcess = 'refund.process';
  static const String expenseView = 'expense.view';
  static const String expenseCreate = 'expense.create';
  static const String expenseEdit = 'expense.edit';
  static const String expenseApprove = 'expense.approve';
  static const String expenseReject = 'expense.reject';
  static const String expensePay = 'expense.pay';
  static const String financeReportsView = 'finance.reports.view';
  static const String financeReportsExport = 'finance.reports.export';
  static const String serviceCatalogueManage = 'service_catalogue.manage';

  // Phase 9: laboratory
  static const String labTestsView = 'lab.tests.view';
  static const String labTestsManage = 'lab.tests.manage';
  static const String labOrdersView = 'lab.orders.view';
  static const String labOrdersManage = 'lab.orders.manage';
  static const String labSamplesManage = 'lab.samples.manage';
  static const String labResultsEnter = 'lab.results.enter';
  static const String labResultsView = 'lab.results.view';
  static const String labResultsVerify = 'lab.results.verify';
  static const String labReportsPublish = 'lab.reports.publish';
  static const String labReportsView = 'lab.reports.view';
  static const String labExternalManage = 'lab.external.manage';
  static const String labDashboardView = 'lab.dashboard.view';
  static const String labAuditView = 'lab.audit.view';

  // Phase 10: reports and notifications
  static const String reportsView = 'reports.view';
  static const String reportsExport = 'reports.export';
  static const String notificationsManage = 'notifications.manage';

  // Phase 6: clinical workspace
  static const String consultationsView = 'consultations.view';
  static const String consultationsViewAll = 'consultations.view_all';
  static const String consultationsManage = 'consultations.manage';
  static const String consultationsFinalize = 'consultations.finalize';
  static const String vitalsView = 'vitals.view';
  static const String vitalsRecord = 'vitals.record';
  static const String prescriptionsView = 'prescriptions.view';
  static const String prescriptionsManage = 'prescriptions.manage';
  static const String prescriptionsFinalize = 'prescriptions.finalize';
  static const String clinicalCatalogueManage = 'clinical_catalogue.manage';
  static const String clinicalTemplatesView = 'clinical_templates.view';
  static const String clinicalTemplatesManage = 'clinical_templates.manage';
  static const String clinicalTemplatesManageClinic =
      'clinical_templates.manage_clinic';
  static const String followupsView = 'followups.view';
  static const String followupsManage = 'followups.manage';
  static const String investigationsRequest = 'investigations.request';
  static const String clinicalAuditView = 'clinical_audit.view';

  static const List<String> all = [
    clinicView,
    clinicUpdate,
    clinicSettingsManage,
    branchesView,
    branchesCreate,
    branchesUpdate,
    branchesActivate,
    branchesDeactivate,
    doctorsView,
    doctorsCreate,
    doctorsUpdate,
    doctorsActivate,
    doctorsAssignBranch,
    staffView,
    staffCreate,
    staffUpdate,
    staffInvite,
    staffActivate,
    staffDeactivate,
    staffAssignRole,
    staffAssignBranch,
    rolesView,
    rolesManage,
    permissionsView,
    patientsView,
    patientsCreate,
    patientsUpdate,
    patientsStatus,
    patientsLinkAccount,
    patientsDuplicates,
    historyView,
    historyManage,
    allergiesView,
    allergiesManage,
    medicationsView,
    medicationsManage,
    alertsView,
    alertsManage,
    consentsView,
    consentsManage,
    patientDocumentsView,
    patientDocumentsManage,
    patientAuditView,
    appointmentTypesView,
    appointmentTypesManage,
    availabilityView,
    availabilityManage,
    availabilityManageOwn,
    appointmentsView,
    appointmentsBook,
    appointmentsManage,
    appointmentsCheckIn,
    appointmentsConsult,
    appointmentsCancelCheckedIn,
    queueView,
    queueOperate,
    queueConsult,
    queuePriority,
    consultationsView,
    consultationsViewAll,
    consultationsManage,
    consultationsFinalize,
    vitalsView,
    vitalsRecord,
    prescriptionsView,
    prescriptionsManage,
    prescriptionsFinalize,
    clinicalCatalogueManage,
    clinicalTemplatesView,
    clinicalTemplatesManage,
    clinicalTemplatesManageClinic,
    followupsView,
    followupsManage,
    investigationsRequest,
    clinicalAuditView,
    billingView,
    billingCreate,
    billingEditDraft,
    billingFinalize,
    billingCancel,
    billingApplyDiscount,
    billingAdjust,
    billingSettingsManage,
    paymentView,
    paymentCollect,
    paymentAllocate,
    paymentRecordAdvance,
    refundRequest,
    refundApprove,
    refundProcess,
    expenseView,
    expenseCreate,
    expenseEdit,
    expenseApprove,
    expenseReject,
    expensePay,
    financeReportsView,
    financeReportsExport,
    serviceCatalogueManage,
    labTestsView,
    labTestsManage,
    labOrdersView,
    labOrdersManage,
    labSamplesManage,
    labResultsEnter,
    labResultsView,
    labResultsVerify,
    labReportsPublish,
    labReportsView,
    labExternalManage,
    labDashboardView,
    labAuditView,
    reportsView,
    reportsExport,
    notificationsManage,
  ];

  static bool isKnown(String key) => all.contains(key);
}

/// Default permissions per clinic role and the authority rules for changing
/// roles. Pure functions so the same rules are testable everywhere.
abstract final class ClinicRolePolicy {
  static const Set<String> _readBasics = {
    ClinicPermission.clinicView,
    ClinicPermission.branchesView,
    // each report section still needs its own module permission
    ClinicPermission.reportsView,
  };

  /// Permissions that expose clinical information.
  static const Set<String> _clinical = {
    ClinicPermission.historyView,
    ClinicPermission.historyManage,
    ClinicPermission.allergiesView,
    ClinicPermission.allergiesManage,
    ClinicPermission.medicationsView,
    ClinicPermission.medicationsManage,
    ClinicPermission.patientDocumentsView,
    ClinicPermission.patientDocumentsManage,
    ClinicPermission.consultationsView,
    ClinicPermission.consultationsViewAll,
    ClinicPermission.consultationsManage,
    ClinicPermission.consultationsFinalize,
    ClinicPermission.vitalsView,
    ClinicPermission.vitalsRecord,
    ClinicPermission.prescriptionsView,
    ClinicPermission.prescriptionsManage,
    ClinicPermission.prescriptionsFinalize,
    ClinicPermission.followupsManage,
    ClinicPermission.investigationsRequest,
    ClinicPermission.clinicalAuditView,
    ClinicPermission.labResultsEnter,
    ClinicPermission.labResultsView,
    ClinicPermission.labResultsVerify,
    ClinicPermission.labReportsPublish,
    ClinicPermission.labReportsView,
    ClinicPermission.labAuditView,
  };

  /// Actions that belong to the treating clinician.
  static const Set<String> _consulting = {
    ClinicPermission.appointmentsConsult,
    ClinicPermission.queueConsult,
  };

  static const Set<String> _patientCare = {
    ClinicPermission.patientsView,
    ClinicPermission.patientsCreate,
    ClinicPermission.patientsUpdate,
    ClinicPermission.patientsDuplicates,
    ClinicPermission.historyView,
    ClinicPermission.allergiesView,
    ClinicPermission.allergiesManage,
    ClinicPermission.medicationsView,
    ClinicPermission.medicationsManage,
    ClinicPermission.alertsView,
    ClinicPermission.alertsManage,
    ClinicPermission.consentsView,
    ClinicPermission.consentsManage,
    ClinicPermission.patientDocumentsView,
    ClinicPermission.patientDocumentsManage,
  };

  /// Money handling roles (Phase 7).
  static const Set<String> _billingDesk = {
    ClinicPermission.billingView,
    ClinicPermission.billingCreate,
    ClinicPermission.billingEditDraft,
    ClinicPermission.billingFinalize,
    ClinicPermission.paymentView,
    ClinicPermission.paymentCollect,
    ClinicPermission.paymentAllocate,
    ClinicPermission.paymentRecordAdvance,
    ClinicPermission.refundRequest,
  };

  static const Set<String> _accounts = {
    ..._billingDesk,
    ClinicPermission.billingCancel,
    ClinicPermission.billingApplyDiscount,
    ClinicPermission.billingAdjust,
    ClinicPermission.refundProcess,
    ClinicPermission.expenseView,
    ClinicPermission.expenseCreate,
    ClinicPermission.expenseEdit,
    ClinicPermission.expensePay,
    ClinicPermission.financeReportsView,
    ClinicPermission.financeReportsExport,
  };

  /// Laboratory (Phase 9). Results and reports are clinical: administrators
  /// manage the catalogue, orders and external labs but never read results.
  static const Set<String> _labDesk = {
    ClinicPermission.labTestsView,
    ClinicPermission.labOrdersView,
    ClinicPermission.labOrdersManage,
    ClinicPermission.labSamplesManage,
    ClinicPermission.labDashboardView,
  };

  static const Set<String> _labTech = {
    ..._labDesk,
    ClinicPermission.labResultsEnter,
    ClinicPermission.labResultsView,
    ClinicPermission.labResultsVerify,
    ClinicPermission.labReportsPublish,
    ClinicPermission.labReportsView,
    ClinicPermission.labExternalManage,
  };

  static final Map<ClinicRole, Set<String>> _matrix = {
    // The owner holds every permission.
    ClinicRole.clinicOwner: {...ClinicPermission.all},
    // The admin runs the clinic but cannot manage roles themselves.
    // Administrators run the clinic but do not read clinical information
    // (history, allergies, medications, documents) by default.
    ClinicRole.clinicAdmin: {
      for (final p in ClinicPermission.all)
        if (p != ClinicPermission.rolesManage &&
            !_clinical.contains(p) &&
            !_consulting.contains(p))
          p,
    },
    ClinicRole.doctor: {
      ..._readBasics,
      ClinicPermission.doctorsView,
      ..._patientCare,
      ClinicPermission.historyManage,
      ClinicPermission.appointmentTypesView,
      ClinicPermission.availabilityView,
      ClinicPermission.availabilityManageOwn,
      ClinicPermission.appointmentsView,
      ClinicPermission.appointmentsBook,
      ClinicPermission.appointmentsConsult,
      ClinicPermission.queueView,
      ClinicPermission.queueOperate,
      ClinicPermission.queueConsult,
      ClinicPermission.consultationsView,
      ClinicPermission.consultationsManage,
      ClinicPermission.consultationsFinalize,
      ClinicPermission.vitalsView,
      ClinicPermission.vitalsRecord,
      ClinicPermission.prescriptionsView,
      ClinicPermission.prescriptionsManage,
      ClinicPermission.prescriptionsFinalize,
      ClinicPermission.clinicalTemplatesView,
      ClinicPermission.clinicalTemplatesManage,
      ClinicPermission.followupsView,
      ClinicPermission.followupsManage,
      ClinicPermission.investigationsRequest,
      // designated clinician: may verify and publish, and read reports
      ClinicPermission.labTestsView,
      ClinicPermission.labOrdersView,
      ClinicPermission.labResultsView,
      ClinicPermission.labResultsVerify,
      ClinicPermission.labReportsPublish,
      ClinicPermission.labReportsView,
    },
    ClinicRole.receptionist: {
      ..._readBasics,
      ClinicPermission.doctorsView,
      ClinicPermission.patientsView,
      ClinicPermission.patientsCreate,
      ClinicPermission.patientsUpdate,
      ClinicPermission.patientsDuplicates,
      ClinicPermission.patientsLinkAccount,
      ClinicPermission.alertsView,
      ClinicPermission.alertsManage,
      ClinicPermission.consentsView,
      ClinicPermission.consentsManage,
      ClinicPermission.appointmentTypesView,
      ClinicPermission.availabilityView,
      ClinicPermission.appointmentsView,
      ClinicPermission.appointmentsBook,
      ClinicPermission.appointmentsManage,
      ClinicPermission.appointmentsCheckIn,
      ClinicPermission.appointmentsCancelCheckedIn,
      ClinicPermission.queueView,
      ClinicPermission.queueOperate,
      ClinicPermission.followupsView,
      ..._billingDesk,
    },
    ClinicRole.nurse: {
      ..._readBasics,
      ClinicPermission.doctorsView,
      ..._patientCare,
      ClinicPermission.appointmentTypesView,
      ClinicPermission.availabilityView,
      ClinicPermission.appointmentsView,
      ClinicPermission.appointmentsCheckIn,
      ClinicPermission.queueView,
      ClinicPermission.queueOperate,
      ClinicPermission.vitalsView,
      ClinicPermission.vitalsRecord,
      ClinicPermission.followupsView,
      ClinicPermission.labTestsView,
      ClinicPermission.labOrdersView,
      ClinicPermission.labSamplesManage,
    },
    // Accountants see money, not the patient directory (Phase 4 decision).
    ClinicRole.accountant: {..._readBasics, ..._accounts},
    ClinicRole.labTechnician: {..._readBasics, ..._labTech},
    ClinicRole.pharmacist: {..._readBasics},
  };

  static Set<String> permissionsFor(ClinicRole? role) =>
      role == null ? const {} : (_matrix[role] ?? const {});

  static bool roleHas(ClinicRole? role, String permission) =>
      permissionsFor(role).contains(permission);

  /// Roles that can be given to staff through invitations / role changes
  /// (never the owner role: ownership is immutable through the API).
  static const List<ClinicRole> assignable = [
    ClinicRole.clinicAdmin,
    ClinicRole.doctor,
    ClinicRole.receptionist,
    ClinicRole.nurse,
    ClinicRole.accountant,
    ClinicRole.labTechnician,
    ClinicRole.pharmacist,
  ];

  /// Whether [actor] may grant [target] to someone else. Owner role is never
  /// assignable; only the owner may create or remove clinic admins.
  static bool canGrant(ClinicRole actor, ClinicRole target) {
    if (!roleHas(actor, ClinicPermission.staffAssignRole)) return false;
    if (target == ClinicRole.clinicOwner) return false;
    if (target == ClinicRole.clinicAdmin) {
      return actor == ClinicRole.clinicOwner;
    }
    return assignable.contains(target);
  }

  /// Whether [actor] may change or remove a member currently holding
  /// [current]. Owners are untouchable; admins are managed by the owner only.
  static bool canManageMember(ClinicRole actor, ClinicRole current) {
    if (current == ClinicRole.clinicOwner) return false;
    if (current == ClinicRole.clinicAdmin) {
      return actor == ClinicRole.clinicOwner;
    }
    return actor == ClinicRole.clinicOwner || actor == ClinicRole.clinicAdmin;
  }
}
