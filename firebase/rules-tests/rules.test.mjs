// Firestore security rules, checked against the local emulator.
// Run from the repo root:
//   firebase emulators:exec --only firestore "npm test --prefix firebase/rules-tests"
import { readFileSync } from 'node:fs';
import { after, before, beforeEach, describe, test } from 'node:test';

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  collection,
  query,
  setDoc,
  updateDoc,
  where,
  writeBatch,
} from 'firebase/firestore';

let env;

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'cricscore-rules-test',
    firestore: {
      rules: readFileSync(new URL('../../firestore.rules', import.meta.url), 'utf8'),
      host: '127.0.0.1',
      port: 8085,
    },
  });
});

after(() => env.cleanup());
beforeEach(() => env.clearFirestore());

const sam = () => env.authenticatedContext('sam').firestore();
const ali = () => env.authenticatedContext('ali').firestore();
const anyone = () => env.unauthenticatedContext().firestore();

const match = (overrides = {}) => ({
  ownerUid: 'sam',
  title: 'Lions v Tigers',
  format: 'T20',
  status: 'inProgress',
  summary: 'Not started',
  setup: { v: 1 },
  eventCount: 1,
  ...overrides,
});

/** Saves a match with one event, bypassing the rules. */
async function seed(data = match()) {
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'matches/m1'), data);
    await setDoc(doc(db, 'matches/m1/events/000000'), { seq: 0, e: { type: 'delivery' } });
  });
}

describe('matches', () => {
  test('the owner can upload a match and its events in one batch', async () => {
    const db = sam();
    const batch = writeBatch(db);
    batch.set(doc(db, 'matches/m1/events/000000'), { seq: 0, e: { type: 'delivery' } });
    batch.set(doc(db, 'matches/m1'), match());
    await assertSucceeds(batch.commit());
  });

  test('a large upload may start with only the owner', async () => {
    const db = sam();
    const batch = writeBatch(db);
    batch.set(doc(db, 'matches/m1'), { ownerUid: 'sam' }, { merge: true });
    batch.set(doc(db, 'matches/m1/events/000000'), { seq: 0, e: {} });
    await assertSucceeds(batch.commit());
  });

  test('nobody can create a match in someone else\'s name', async () => {
    await assertFails(setDoc(doc(ali(), 'matches/m1'), match()));
    await assertFails(setDoc(doc(anyone(), 'matches/m1'), match()));
  });

  test('the owner can read, list, update and delete their match', async () => {
    await seed();
    const db = sam();
    await assertSucceeds(getDoc(doc(db, 'matches/m1')));
    await assertSucceeds(getDocs(query(collection(db, 'matches'), where('ownerUid', '==', 'sam'))));
    await assertSucceeds(getDocs(collection(db, 'matches/m1/events')));
    await assertSucceeds(updateDoc(doc(db, 'matches/m1'), { summary: 'Lions 4/0 (0.1)', eventCount: 2 }));
    await assertSucceeds(deleteDoc(doc(db, 'matches/m1/events/000000')));
    await assertSucceeds(deleteDoc(doc(db, 'matches/m1')));
  });

  test('other people cannot read a private match or its events', async () => {
    await seed();
    await assertFails(getDoc(doc(ali(), 'matches/m1')));
    await assertFails(getDocs(collection(ali(), 'matches/m1/events')));
    await assertFails(getDoc(doc(anyone(), 'matches/m1')));
    await assertFails(getDocs(query(collection(ali(), 'matches'), where('ownerUid', '==', 'sam'))));
  });

  test('anyone can read a shared match, but only the owner can change it', async () => {
    await seed(match({ shared: true }));
    await assertSucceeds(getDoc(doc(anyone(), 'matches/m1')));
    await assertSucceeds(getDocs(collection(anyone(), 'matches/m1/events')));
    await assertFails(updateDoc(doc(ali(), 'matches/m1'), { summary: 'hacked' }));
    await assertFails(setDoc(doc(ali(), 'matches/m1/events/000001'), { seq: 1, e: {} }));
    await assertFails(deleteDoc(doc(anyone(), 'matches/m1')));
  });

  test('the owner cannot hand a match to someone else', async () => {
    await seed();
    await assertFails(updateDoc(doc(sam(), 'matches/m1'), { ownerUid: 'ali' }));
  });

  test('others cannot add events to a match', async () => {
    await seed();
    await assertFails(setDoc(doc(ali(), 'matches/m1/events/000001'), { seq: 1, e: {} }));
    await assertFails(deleteDoc(doc(ali(), 'matches/m1/events/000000')));
  });

  test('malformed data is refused', async () => {
    const db = sam();
    await assertFails(setDoc(doc(db, 'matches/a'), match({ status: 'paused' })));
    await assertFails(setDoc(doc(db, 'matches/b'), match({ eventCount: -1 })));
    await assertFails(setDoc(doc(db, 'matches/c'), match({ title: 'x'.repeat(201) })));
    await assertFails(setDoc(doc(db, 'matches/d'), match({ shared: 'yes' })));
    await seed();
    await assertFails(setDoc(doc(db, 'matches/m1/events/000001'), { seq: '1', e: {} }));
  });
});

describe('teams', () => {
  const team = { name: 'Lions', players: [{ id: 'a1', name: 'Sam' }] };

  test('each account keeps its teams private', async () => {
    await assertSucceeds(setDoc(doc(sam(), 'users/sam/teams/t1'), team));
    await assertSucceeds(getDoc(doc(sam(), 'users/sam/teams/t1')));
    await assertFails(getDoc(doc(ali(), 'users/sam/teams/t1')));
    await assertFails(setDoc(doc(ali(), 'users/sam/teams/t2'), team));
    await assertFails(getDoc(doc(anyone(), 'users/sam/teams/t1')));
  });

  test('a team must have a name and a list of players', async () => {
    await assertFails(setDoc(doc(sam(), 'users/sam/teams/t1'), { players: [] }));
    await assertFails(setDoc(doc(sam(), 'users/sam/teams/t1'), { name: 'Lions', players: 'Sam' }));
  });
});

test('anything else is refused', async () => {
  await assertFails(setDoc(doc(sam(), 'secrets/x'), { a: 1 }));
  await assertFails(getDoc(doc(sam(), 'users/sam')));
});
