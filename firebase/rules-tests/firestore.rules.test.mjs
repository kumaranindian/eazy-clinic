// Firestore rules tests. Run through the emulator only:
//   scripts/test_emulator.sh
// Never point these at a real project (project id is demo-*, so the emulator
// refuses real credentials anyway).
import { readFileSync } from 'node:fs';
import { after, before, beforeEach, describe, it } from 'node:test';
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import { doc, getDoc, setDoc, updateDoc, deleteDoc, collection, getDocs, addDoc } from 'firebase/firestore';

let env;

const patientPaths = [
  'patient_accounts/pa_1',
  'patient_account_uids/alice',
  'patient_clinic_links/t1_p1',
  'family_relationships/fr_1',
  'tenants/t1/patients/p1',
  'tenants/t1/patient_consents/c1',
  'tenants/t1/patient_history_entries/h1',
  'tenants/t1/patient_allergies/a1',
  'tenants/t1/patient_medications/m1',
  'tenants/t1/patient_alerts/al1',
  'tenants/t1/patient_documents/d1',
  'tenants/t1/patient_link_codes/lc1',
  'tenants/t1/patient_identity_links/il1',
  'tenants/t1/patient_audit_logs/au1',
  'tenants/t1/patient_record_revisions/r1',
  'tenants/t1/patient_emergency_contacts/p1',
  'tenants/t1/patient_duplicate_reviews/dr1',
  'tenants/t1/doctor_availability/sch1',
  'tenants/t1/doctor_schedule_exceptions/exc1',
  'tenants/t1/appointment_types/aty1',
  'tenants/t1/appointments/apt1',
  'tenants/t1/appointment_slot_reservations/r1',
  'tenants/t1/appointment_idempotency/k1',
  'tenants/t1/appointment_audit_logs/au1',
  'tenants/t1/queues/q1',
  'tenants/t1/queue_entries/qe1',
  'tenants/t1/queue_tokens/q1_1',
  'tenants/t1/consultations/con1',
  'tenants/t1/consultation_versions/con1_r0',
  'tenants/t1/consultation_amendments/amd1',
  'tenants/t1/consultation_appointments/apt1',
  'tenants/t1/diagnoses/dx1',
  'tenants/t1/diagnosis_catalogue/dc1',
  'tenants/t1/medicine_catalogue/md1',
  'tenants/t1/prescriptions/rx1',
  'tenants/t1/prescription_numbers/RX-000001',
  'tenants/t1/patient_vitals/vt1',
  'tenants/t1/clinical_templates/tpl1',
  'tenants/t1/followups/fu1',
  'tenants/t1/investigation_requests/inv1',
  'tenants/t1/clinical_audit_logs/ca1',
  'tenants/t1/counters/prescription_number',
  'tenants/t1/service_catalogue/svc1',
  'tenants/t1/service_price_history/sph1',
  'tenants/t1/tax_rules/tx1',
  'tenants/t1/billing_settings/main',
  'tenants/t1/invoices/inv1',
  'tenants/t1/invoice_numbers/INV-000001',
  'tenants/t1/invoice_adjustments/adj1',
  'tenants/t1/invoice_sources/appointment_apt1',
  'tenants/t1/payments/pay1',
  'tenants/t1/payment_allocations/al1',
  'tenants/t1/receipts/rct1',
  'tenants/t1/receipt_numbers/RCT-000001',
  'tenants/t1/patient_credit_ledger/le1',
  'tenants/t1/patient_credit_balances/p1',
  'tenants/t1/refunds/rf1',
  'tenants/t1/expenses/exp1',
  'tenants/t1/expense_categories/ec1',
  'tenants/t1/billing_idempotency/hash1',
  'tenants/t1/financial_audit_logs/fa1',
  'tenants/t1/lab_tests/lt1',
  'tenants/t1/lab_test_codes/hb',
  'tenants/t1/external_laboratories/el1',
  'tenants/t1/lab_orders/lo1',
  'tenants/t1/lab_order_numbers/LAB-000001',
  'tenants/t1/lab_order_keys/c1_lt1',
  'tenants/t1/lab_samples/ls1',
  'tenants/t1/lab_sample_ids/SMP-1',
  'tenants/t1/lab_results/lo1__it1',
  'tenants/t1/lab_reports/lr1',
  'tenants/t1/lab_report_numbers/RPT-000001',
  'tenants/t1/lab_idempotency/hash1',
  'tenants/t1/lab_audit_logs/la1',
  'patient_notifications/n1',
  'patient_devices/dev1',
  'patient_notification_preferences/pa1',
  'account_deletion_requests/pa1',
];

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-eazyclinic-rules',
    firestore: {
      rules: readFileSync(new URL('../firestore.rules', import.meta.url), 'utf8'),
    },
  });
});

after(async () => env?.cleanup());

beforeEach(async () => {
  await env.clearFirestore();
  // The backend (Admin/service account) is not subject to rules.
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'platform_users/alice'), {
      uid: 'alice', email: 'alice@example.test', accountStatus: 'active', displayName: 'Alice',
    });
    await setDoc(doc(db, 'platform_users/bob'), {
      uid: 'bob', email: 'bob@example.test', accountStatus: 'pending', displayName: 'Bob',
    });
    await setDoc(doc(db, 'platform_audit_logs/log1'), { event: 'logout', uid: 'alice' });
    await setDoc(doc(db, 'tenants/t1/patients/p1'), { name: 'Patient One' });
    for (const p of patientPaths) await setDoc(doc(db, p), { patientId: 'p1', accountId: 'alice', status: 'active', codeHash: 'abc', phoneNorm: '9876500001' });
  });
});

const alice = () => env.authenticatedContext('alice', { email_verified: true }).firestore();
const anon = () => env.unauthenticatedContext().firestore();

describe('platform_users', () => {
  it('unauthenticated clients cannot read or write', async () => {
    await assertFails(getDoc(doc(anon(), 'platform_users/alice')));
    await assertFails(setDoc(doc(anon(), 'platform_users/new'), { uid: 'new' }));
  });

  it('a signed-in user cannot read their own profile directly (backend only)', async () => {
    await assertFails(getDoc(doc(alice(), 'platform_users/alice')));
  });

  it("a signed-in user cannot read another user's profile", async () => {
    await assertFails(getDoc(doc(alice(), 'platform_users/bob')));
    await assertFails(getDocs(collection(alice(), 'platform_users')));
  });

  it('a user cannot create their own profile (no client-side initialization)', async () => {
    await assertFails(setDoc(doc(env.authenticatedContext('carol').firestore(), 'platform_users/carol'), {
      uid: 'carol', accountStatus: 'active',
    }));
  });

  it('a user cannot change accountStatus', async () => {
    await assertFails(updateDoc(doc(alice(), 'platform_users/alice'), { accountStatus: 'active' }));
    const bob = env.authenticatedContext('bob').firestore();
    await assertFails(updateDoc(doc(bob, 'platform_users/bob'), { accountStatus: 'active' }));
  });

  it('a user cannot grant themselves a platform role', async () => {
    await assertFails(updateDoc(doc(alice(), 'platform_users/alice'), { platformRole: 'super_admin' }));
  });

  it('a user cannot add tenant memberships or permissions', async () => {
    await assertFails(updateDoc(doc(alice(), 'platform_users/alice'), { memberships: [{ tenantId: 't1', role: 'clinic_owner' }] }));
    await assertFails(updateDoc(doc(alice(), 'platform_users/alice'), { permissions: ['*'] }));
  });

  it("a user cannot modify another user's profile or delete a profile", async () => {
    await assertFails(updateDoc(doc(alice(), 'platform_users/bob'), { displayName: 'Hacked' }));
    await assertFails(deleteDoc(doc(alice(), 'platform_users/alice')));
  });

  it('a token claiming a platform role still gets no access (claims are not trusted)', async () => {
    const fake = env.authenticatedContext('mallory', { role: 'super_admin', platformRole: 'super_admin', admin: true }).firestore();
    await assertFails(getDoc(doc(fake, 'platform_users/alice')));
    await assertFails(updateDoc(doc(fake, 'platform_users/alice'), { accountStatus: 'disabled' }));
  });

  it('the backend (rules bypass) can still read and write', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await assertSucceeds(getDoc(doc(db, 'platform_users/alice')));
      await assertSucceeds(updateDoc(doc(db, 'platform_users/alice'), { accountStatus: 'suspended' }));
    });
  });
});

describe('SaaS control-plane collections are backend-only (Phase 2)', () => {
  const paths = [
    'clinic_applications/app_1',
    'clinic_applications/app_1/internal_notes/n1',
    'clinic_applications/app_1/history/h1',
    'tenants/ten_1',
    'tenants/ten_1/members/alice',
    'tenant_slugs/green-valley',
    'tenant_provisioning_jobs/ten_1',
    'subscription_plans/plan_1',
    'subscription_plans/plan_1/versions/1',
    'platform_subscriptions/sub_1',
    'platform_subscriptions/sub_1/history/h1',
    // Phase 3: clinic administration data
    'tenants/ten_1/clinic_settings/profile',
    'tenants/ten_1/clinic_settings/operations',
    'tenants/ten_1/branches/br_1',
    'tenants/ten_1/branch_codes/MAIN',
    'tenants/ten_1/doctors/doc_1',
    'tenants/ten_1/doctor_regs/mh12345',
    'tenants/ten_1/doctor_branch_assignments/asg_1',
    'tenants/ten_1/doctor_branch_active/doc_1_br_1',
    'tenants/ten_1/staff/stf_1',
    'tenants/ten_1/staff_emails/nina_example_test',
    'tenants/ten_1/invitations/inv_1',
    'tenants/ten_1/seats/staff_1',
  ];

  beforeEach(async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      for (const p of paths) await setDoc(doc(db, p), { applicantUid: 'alice', uid: 'alice', status: 'active' });
    });
  });

  it('no client can read any of them, including the owner of the record', async () => {
    for (const p of paths) {
      await assertFails(getDoc(doc(alice(), p)));
      await assertFails(getDoc(doc(anon(), p)));
    }
  });

  it('no client can create, change or delete any of them', async () => {
    for (const p of paths) {
      await assertFails(setDoc(doc(alice(), p.replace(/[^/]+$/, 'new_doc')), { status: 'approved' }));
      await assertFails(updateDoc(doc(alice(), p), { status: 'approved' }));
      await assertFails(deleteDoc(doc(alice(), p)));
    }
  });

  it('an applicant cannot approve their own application or create a tenant/membership', async () => {
    await assertFails(updateDoc(doc(alice(), 'clinic_applications/app_1'), { status: 'approved' }));
    await assertFails(setDoc(doc(alice(), 'tenants/ten_mine'), { ownerUid: 'alice', status: 'active' }));
    await assertFails(setDoc(doc(alice(), 'tenants/ten_1/members/alice'), { role: 'clinic_owner', status: 'active' }));
  });

  it('a client cannot grant itself a subscription or entitlement override', async () => {
    await assertFails(setDoc(doc(alice(), 'platform_subscriptions/sub_self'), { tenantId: 'ten_1', status: 'active' }));
    await assertFails(updateDoc(doc(alice(), 'platform_subscriptions/sub_1'), { overrides: { features: { billing: true } } }));
  });

  it('clients cannot look up invitations by token hash (collection group) or read any invitation', async () => {
    const { collectionGroup, query, where } = await import('firebase/firestore');
    await assertFails(getDocs(query(collectionGroup(alice(), 'invitations'), where('tokenHash', '==', 'abc'))));
    await assertFails(getDocs(query(collectionGroup(anon(), 'invitations'), where('tokenHash', '==', 'abc'))));
  });

  it('a member cannot change their own role, branches or status, or create memberships', async () => {
    await assertFails(updateDoc(doc(alice(), 'tenants/ten_1/members/alice'), { role: 'clinic_owner' }));
    await assertFails(updateDoc(doc(alice(), 'tenants/ten_1/members/alice'), { allBranches: true, status: 'active' }));
    await assertFails(setDoc(doc(alice(), 'tenants/ten_1/members/mallory'), { uid: 'mallory', role: 'clinic_admin', status: 'active' }));
  });

  it('collection-group queries on members are denied to clients', async () => {
    const { collectionGroup, query, where } = await import('firebase/firestore');
    await assertFails(getDocs(query(collectionGroup(alice(), 'members'), where('uid', '==', 'alice'))));
  });
});

describe('patient, scheduling and clinical data is backend-only (Phases 4-6)', () => {
  const paths = patientPaths;


  it('no client can read patient, consent, document, identity or audit data', async () => {
    for (const p of paths) {
      await assertFails(getDoc(doc(alice(), p)));
      await assertFails(getDoc(doc(anon(), p)));
    }
  });

  it('a patient cannot read or edit their own account, links or relationships directly', async () => {
    await assertFails(updateDoc(doc(alice(), 'patient_accounts/pa_1'), { status: 'verified' }));
    await assertFails(updateDoc(doc(alice(), 'family_relationships/fr_1'), { status: 'active', verificationStatus: 'verified' }));
    await assertFails(setDoc(doc(alice(), 'patient_clinic_links/t2_p9'), { accountId: 'alice', tenantId: 't2', patientId: 'p9', status: 'linked' }));
  });

  it('no client can write, change or delete any patient collection, including audit and consent evidence', async () => {
    for (const p of paths) {
      await assertFails(setDoc(doc(alice(), p.replace(/[^/]+$/, 'new_doc')), { status: 'active' }));
      await assertFails(updateDoc(doc(alice(), p), { status: 'revoked' }));
      await assertFails(deleteDoc(doc(alice(), p)));
    }
  });

  it('no client can read or change appointments, reservations, queues or tokens', async () => {
    const { collectionGroup, query, where } = await import('firebase/firestore');
    await assertFails(getDocs(query(collectionGroup(alice(), 'appointments'), where('doctorId', '==', 'd1'))));
    await assertFails(getDocs(query(collectionGroup(anon(), 'queue_entries'), where('queueId', '==', 'q1'))));
    await assertFails(setDoc(doc(alice(), 'tenants/t1/queue_entries/qe1'), { status: 'completed', tokenNumber: 1 }));
    await assertFails(setDoc(doc(alice(), 'tenants/t1/appointment_slot_reservations/free'), { doctorId: 'd1' }));
    await assertFails(updateDoc(doc(alice(), 'tenants/t1/appointments/apt1'), { status: 'completed' }));
  });

  it('no client can read or change consultations, prescriptions, vitals or clinical audit records', async () => {
    const { collectionGroup, query, where } = await import('firebase/firestore');
    await assertFails(getDocs(query(collectionGroup(alice(), 'consultations'), where('doctorId', '==', 'd1'))));
    await assertFails(getDocs(query(collectionGroup(alice(), 'prescriptions'), where('patientId', '==', 'p1'))));
    await assertFails(getDocs(query(collectionGroup(anon(), 'patient_vitals'), where('patientId', '==', 'p1'))));
    await assertFails(updateDoc(doc(alice(), 'tenants/t1/consultations/con1'), { status: 'finalized' }));
    await assertFails(updateDoc(doc(alice(), 'tenants/t1/prescriptions/rx1'), { status: 'finalized' }));
    await assertFails(deleteDoc(doc(alice(), 'tenants/t1/clinical_audit_logs/ca1')));
    await assertFails(setDoc(doc(alice(), 'tenants/t1/consultation_versions/con1_r1'), { content: {} }));
  });

  it('no client can read or change invoices, payments, refunds, credit, expenses or financial audit records', async () => {
    const { collectionGroup, query, where } = await import('firebase/firestore');
    await assertFails(getDocs(query(collectionGroup(alice(), 'invoices'), where('patientId', '==', 'p1'))));
    await assertFails(getDocs(query(collectionGroup(alice(), 'payments'), where('patientId', '==', 'p1'))));
    await assertFails(getDocs(query(collectionGroup(anon(), 'refunds'), where('paymentId', '==', 'pay1'))));
    await assertFails(getDocs(query(collectionGroup(alice(), 'expenses'), where('status', '==', 'paid'))));
    await assertFails(getDocs(query(collectionGroup(alice(), 'patient_credit_ledger'), where('patientId', '==', 'p1'))));
    await assertFails(updateDoc(doc(alice(), 'tenants/t1/invoices/inv1'), { status: 'paid', outstanding: 0 }));
    await assertFails(updateDoc(doc(alice(), 'tenants/t1/payments/pay1'), { amount: 1 }));
    await assertFails(setDoc(doc(alice(), 'tenants/t1/patient_credit_balances/p1'), { balance: 999999 }));
    await assertFails(setDoc(doc(alice(), 'tenants/t1/refunds/rf2'), { status: 'completed', amount: 1 }));
    await assertFails(deleteDoc(doc(alice(), 'tenants/t1/financial_audit_logs/fa1')));
    await assertFails(setDoc(doc(alice(), 'tenants/t1/receipt_numbers/RCT-000002'), { receiptId: 'x' }));
  });

  it('no client can read or change laboratory catalogue, orders, samples, results, reports or audit records', async () => {
    const { collectionGroup, query, where } = await import('firebase/firestore');
    await assertFails(getDocs(query(collectionGroup(alice(), 'lab_orders'), where('patientId', '==', 'p1'))));
    await assertFails(getDocs(query(collectionGroup(alice(), 'lab_results'), where('patientId', '==', 'p1'))));
    await assertFails(getDocs(query(collectionGroup(anon(), 'lab_reports'), where('patientId', '==', 'p1'))));
    await assertFails(getDoc(doc(alice(), 'tenants/t1/lab_reports/lr1')));
    await assertFails(updateDoc(doc(alice(), 'tenants/t1/lab_orders/lo1'), { status: 'published' }));
    await assertFails(updateDoc(doc(alice(), 'tenants/t1/lab_results/lo1__it1'), { status: 'verified' }));
    await assertFails(setDoc(doc(alice(), 'tenants/t1/lab_tests/lt2'), { name: 'x' }));
    await assertFails(setDoc(doc(alice(), 'tenants/t1/lab_report_numbers/RPT-000002'), { ownerId: 'x' }));
    await assertFails(deleteDoc(doc(alice(), 'tenants/t1/lab_audit_logs/la1')));
  });

  it('no client can read or write patient notifications, device tokens, preferences or deletion requests', async () => {
    const { collectionGroup, query, where } = await import('firebase/firestore');
    await assertFails(getDocs(query(collectionGroup(alice(), 'patient_notifications'), where('accountId', '==', 'pa1'))));
    await assertFails(getDoc(doc(alice(), 'patient_devices/dev1')));
    await assertFails(setDoc(doc(alice(), 'patient_devices/dev2'), { uid: 'alice', token: 'x', active: true }));
    await assertFails(updateDoc(doc(alice(), 'patient_notifications/n1'), { read: true }));
    await assertFails(setDoc(doc(alice(), 'patient_notification_preferences/pa1'), { pushEnabled: false }));
    await assertFails(setDoc(doc(alice(), 'account_deletion_requests/pa1'), { status: 'approved' }));
    await assertFails(getDoc(doc(anon(), 'patient_notifications/n1')));
  });

  it('link codes cannot be looked up by hash from a client (collection group)', async () => {
    const { collectionGroup, query, where } = await import('firebase/firestore');
    await assertFails(getDocs(query(collectionGroup(alice(), 'patient_link_codes'), where('codeHash', '==', 'abc'))));
    await assertFails(getDocs(query(collectionGroup(alice(), 'patients'), where('phoneNorm', '==', '9876500001'))));
  });
});

describe('other collections stay closed', () => {
  it('audit logs are not readable or writable by clients', async () => {
    await assertFails(getDoc(doc(alice(), 'platform_audit_logs/log1')));
    await assertFails(addDoc(collection(alice(), 'platform_audit_logs'), { event: 'forged' }));
    await assertFails(deleteDoc(doc(alice(), 'platform_audit_logs/log1')));
  });

  it('tenant data is closed to every client (cross-tenant isolation baseline)', async () => {
    await assertFails(getDoc(doc(alice(), 'tenants/t1/patients/p1')));
    await assertFails(setDoc(doc(alice(), 'tenants/t2/patients/p9'), { name: 'x' }));
  });

  it('unknown collections are denied by default', async () => {
    await assertFails(getDoc(doc(alice(), 'anything/else')));
    await assertFails(setDoc(doc(alice(), 'anything/else'), { a: 1 }));
  });
});
