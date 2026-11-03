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
