import { readFileSync } from 'node:fs'

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  type RulesTestEnvironment,
} from '@firebase/rules-unit-testing'
import { doc, setDoc, Timestamp, serverTimestamp } from 'firebase/firestore'
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest'

let env: RulesTestEnvironment

const ROUND = 'r1'
const SLOT = 3
/** Far enough either side that the test is never racing the real clock. */
const OPENS_AT = () => Date.now() - 60_000
const CLOSES_AT = () => Date.now() + 60_000

beforeAll(async () => {
  env = await initializeTestEnvironment({
    projectId: 'consts-quizzes-rules',
    firestore: {
      host: '127.0.0.1',
      port: 8080,
      rules: readFileSync('../firestore.rules', 'utf8'),
    },
  })
})

afterAll(() => env.cleanup())

/** Publishes a live Round with one open Slot, bypassing the rules. */
async function publishRound({
  opensAt = OPENS_AT(),
  closesAt = CLOSES_AT(),
  openSlot = SLOT,
}: { opensAt?: number; closesAt?: number; openSlot?: number } = {}) {
  await env.withSecurityRulesDisabled(async (ctx) => {
    const slots = Array.from({ length: 20 }, (_, i) => ({
      questionId: `q${i}`,
      startsAt: opensAt - 4000,
      opensAt,
      closesAt,
    }))
    await setDoc(doc(ctx.firestore(), 'rounds/current'), {
      id: ROUND,
      theme: 'History',
      openSlot,
      slots,
      nextRoundAt: closesAt + 60_000,
    })
    // Everyone in these tests holds a seat unless a test takes it away.
    for (const uid of ['alice', 'bob']) {
      await setDoc(doc(ctx.firestore(), `rounds/${ROUND}/seatHolders/${uid}`), {
        at: Timestamp.now(),
      })
    }
  })
}

async function setKillSwitch(on: boolean) {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'config/app'), { killSwitch: on })
  })
}

async function revokeSeat(uid: string) {
  await env.withSecurityRulesDisabled(async (ctx) => {
    const { deleteDoc } = await import('firebase/firestore')
    await deleteDoc(doc(ctx.firestore(), `rounds/${ROUND}/seatHolders/${uid}`))
  })
}

const answer = (
  uid: string,
  overrides: Record<string, unknown> = {},
  slot = SLOT,
) => ({
  uid,
  slot,
  choice: 'Paris',
  answeredAt: serverTimestamp(),
  ...overrides,
})

beforeEach(async () => {
  await env.clearFirestore()
  await publishRound()
})

describe('answer rules', () => {
  it('accepts an Answer inside the Window', async () => {
    const db = env.authenticatedContext('alice').firestore()
    await assertSucceeds(
      setDoc(doc(db, `rounds/${ROUND}/answers/${SLOT}_alice`), answer('alice')),
    )
  })

  it('refuses an Answer before the Window opens', async () => {
    await publishRound({ opensAt: Date.now() + 30_000 })
    const db = env.authenticatedContext('alice').firestore()
    await assertFails(
      setDoc(doc(db, `rounds/${ROUND}/answers/${SLOT}_alice`), answer('alice')),
    )
  })

  it('refuses an Answer after the Window closes', async () => {
    await publishRound({ closesAt: Date.now() - 5_000 })
    const db = env.authenticatedContext('alice').firestore()
    await assertFails(
      setDoc(doc(db, `rounds/${ROUND}/answers/${SLOT}_alice`), answer('alice')),
    )
  })

  it('refuses a second Answer for the same Slot', async () => {
    const db = env.authenticatedContext('alice').firestore()
    await assertSucceeds(
      setDoc(doc(db, `rounds/${ROUND}/answers/${SLOT}_alice`), answer('alice')),
    )
    await assertFails(
      setDoc(doc(db, `rounds/${ROUND}/answers/${SLOT}_alice`), answer('alice', {
        choice: 'London',
      })),
    )
  })

  it('refuses answering a Slot that is not the open one', async () => {
    const db = env.authenticatedContext('alice').firestore()
    await assertFails(
      setDoc(
        doc(db, `rounds/${ROUND}/answers/${SLOT + 4}_alice`),
        answer('alice', {}, SLOT + 4),
      ),
    )
  })

  it('refuses answering for somebody else', async () => {
    const db = env.authenticatedContext('alice').firestore()
    await assertFails(
      setDoc(doc(db, `rounds/${ROUND}/answers/${SLOT}_bob`), answer('bob')),
    )
  })

  it('refuses an id that does not match the Player and Slot', async () => {
    const db = env.authenticatedContext('alice').firestore()
    await assertFails(
      setDoc(doc(db, `rounds/${ROUND}/answers/sneaky`), answer('alice')),
    )
  })

  it('refuses a client-chosen answeredAt', async () => {
    const db = env.authenticatedContext('alice').firestore()
    await assertFails(
      setDoc(
        doc(db, `rounds/${ROUND}/answers/${SLOT}_alice`),
        answer('alice', { answeredAt: Timestamp.fromMillis(1) }),
      ),
    )
  })

  it('refuses a signed-out visitor', async () => {
    const db = env.unauthenticatedContext().firestore()
    await assertFails(
      setDoc(doc(db, `rounds/${ROUND}/answers/${SLOT}_alice`), answer('alice')),
    )
  })

  it('refuses an Answer from a Player holding no seat', async () => {
    await revokeSeat('alice')
    const db = env.authenticatedContext('alice').firestore()
    await assertFails(
      setDoc(doc(db, `rounds/${ROUND}/answers/${SLOT}_alice`), answer('alice')),
    )
  })

  it('refuses every Answer while the kill switch is on', async () => {
    await setKillSwitch(true)
    const db = env.authenticatedContext('alice').firestore()
    await assertFails(
      setDoc(doc(db, `rounds/${ROUND}/answers/${SLOT}_alice`), answer('alice')),
    )
    await setKillSwitch(false)
  })

  it('refuses an Answer against a Round that is not live', async () => {
    const db = env.authenticatedContext('alice').firestore()
    await assertFails(
      setDoc(doc(db, `rounds/other/answers/${SLOT}_alice`), answer('alice')),
    )
  })
})

describe('everything else', () => {
  it('lets a signed-out visitor read the live Round', async () => {
    const db = env.unauthenticatedContext().firestore()
    await assertSucceeds(
      import('firebase/firestore').then((m) =>
        m.getDoc(doc(db, 'rounds/current')),
      ),
    )
  })

  it('lets a signed-out visitor read the published config', async () => {
    const db = env.unauthenticatedContext().firestore()
    await assertSucceeds(
      import('firebase/firestore').then((m) => m.getDoc(doc(db, 'config/app'))),
    )
  })

  it('refuses a client writing its own Player document', async () => {
    const db = env.authenticatedContext('alice').firestore()
    await assertFails(
      setDoc(doc(db, 'players/alice'), { handle: 'chosen-by-me-001' }),
    )
  })

  it('refuses reading or squatting the Handle table', async () => {
    const db = env.authenticatedContext('alice').firestore()
    await assertFails(setDoc(doc(db, 'handles/mine-own-handle-001'), { uid: 'alice' }))
    await assertFails(
      import('firebase/firestore').then((m) =>
        m.getDoc(doc(db, 'handles/anything-at-all-001')),
      ),
    )
  })
})
