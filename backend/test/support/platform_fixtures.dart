import 'package:backend/features/platform/applications/application_service.dart';
import 'package:backend/features/platform/audit/audit_service.dart';
import 'package:backend/features/platform/plans/plan_service.dart';
import 'package:backend/features/platform/subscriptions/subscription_service.dart';
import 'package:backend/features/platform/tenants/tenant_service.dart';
import 'package:common_models/common_models.dart';
import 'package:country_config/country_config.dart';

import 'memory_document_store.dart';

const Actor admin = Actor('admin-1', 'super_admin');

/// Valid plan body for tests (override fields as needed).
Map<String, Object?> planBody({
  String name = 'Starter',
  int price = 99900,
  int trialDays = 14,
  String interval = 'monthly',
  Map<String, Object?>? limits,
  Map<String, Object?>? features,
}) => {
  'name': name,
  'billingInterval': interval,
  'priceMinor': price,
  'currency': 'INR',
  'trialDays': trialDays,
  'limits':
      limits ??
      {
        'max_branches': 1,
        'max_doctors': 3,
        'max_staff': 10,
        'max_patients': null,
      },
  'features': features ?? {'appointments': true, 'patient_management': true},
};

/// Mutable clock so tests can move time.
class TestClock {
  TestClock([DateTime? start]) : now = start ?? DateTime.utc(2026, 6, 1, 10);
  DateTime now;
  DateTime call() => now;
}

/// Seeds the reviewed India and UAE country master (what the platform admin's
/// "seed baseline" action creates) directly into a test store.
void seedCountries(MemoryDocumentStore store, {DateTime? at}) {
  final when = at ?? DateTime.utc(2026, 6, 1);
  for (final p in BaselineCountries.all(effectiveFrom: when)) {
    store.docs['countries/${p.code}'] = {
      ...p.toJson(),
      'effectiveFrom': p.effectiveFrom,
      'updatedAt': when,
      'updatedBy': 'seed',
    };
  }
}

class PlatformServices {
  PlatformServices({TestClock? clock}) : clock = clock ?? TestClock() {
    seedCountries(store);
    audit = AuditService(store, clock: this.clock.call);
    plans = PlanService(store, audit, clock: this.clock.call);
    subscriptions = SubscriptionService(store, audit, clock: this.clock.call);
    applications = ApplicationService(store, audit, clock: this.clock.call);
    tenants = TenantService(
      store,
      audit,
      subscriptions,
      clock: this.clock.call,
    );
  }

  final TestClock clock;
  final MemoryDocumentStore store = MemoryDocumentStore();
  late final AuditService audit;
  late final PlanService plans;
  late final SubscriptionService subscriptions;
  late final ApplicationService applications;
  late final TenantService tenants;

  void seedTenant(
    String id, {
    String status = 'active',
    String name = 'Clinic',
  }) {
    store.docs['tenants/$id'] = {
      'tenantId': id,
      'clinicName': name,
      'clinicNameLower': name.toLowerCase(),
      'status': status,
      'subscriptionId': null,
      'createdAt': clock.now,
      'updatedAt': clock.now,
    };
  }

  Future<String> activePlan({
    String name = 'Starter',
    int trialDays = 14,
    Map<String, Object?>? body,
  }) async {
    final plan = await plans.create(
      PlanInput.parse(
        body ?? planBody(name: name, trialDays: trialDays),
        partial: false,
      ),
      admin,
    );
    await plans.setStatus(plan['planId']! as String, PlanStatus.active, admin);
    return plan['planId']! as String;
  }
}

const Actor support = Actor('support-1', 'platform_support_admin');

/// A complete, valid application body.
Map<String, Object?> applicationBody({
  String name = 'Green Valley Clinic',
  String city = 'Pune',
  String postalCode = '411001',
  String? preferredPlanId,
  String countryCode = 'IN',
}) => {
  'clinic': {
    'name': name,
    'type': 'general_medicine',
    'registrationNumber': 'MH/2020/1234',
    'email': 'info@greenvalley.test',
    'phone': countryCode == 'AE' ? '+971501234567' : '9876543210',
    'website': 'https://greenvalley.test',
    'description': 'Family clinic',
  },
  'address': {
    'line1': '12 Main Road',
    'city': city,
    'state': countryCode == 'AE' ? 'Dubai' : 'Maharashtra',
    'countryCode': countryCode,
    'postalCode': postalCode,
  },
  'owner': {
    'fullName': 'Dr Asha Rao',
    'email': 'asha@greenvalley.test',
    'phone': countryCode == 'AE' ? '+971501234568' : '9876543211',
    'designation': 'Physician',
  },
  'expectations': {'doctors': 3, 'staff': 8, 'monthlyPatients': 600},
  'preferredPlanId': ?preferredPlanId,
};

extension PlatformFlows on PlatformServices {
  Future<Map<String, Object?>> submitApplication({
    String uid = 'applicant-1',
    Map<String, Object?>? body,
  }) => applications.submit(
    applicantUid: uid,
    applicantEmail: '$uid@example.test',
    input: ApplicationInput.parse(body ?? applicationBody(), partial: false),
  );
}
