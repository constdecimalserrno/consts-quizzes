import { Timestamp } from 'firebase-admin/firestore'
import { afterAll, beforeEach, describe, expect, it } from 'vitest'

import { scoreSlot } from '../src/answers.js'
import { DEFAULT_CONFIG } from '../src/config.js'
import type { Round } from '../src/round.js'
import { testDb, wipe } from './harness.js'

const { db, dispose } = testDb()
afterAll(dispose)

const OPENS = 100_000
const CLOSES = 111_000
const ROUND_ID = 'r1'

const round = (): Round =>
  ({
    id: ROUND_ID,
    theme: 'History',
    startedAt: OPENS - 4000,
    endsAt: CLOSES,
    openSlot: 0,
    question: null,
    nextRoundAt: CLOSES + 60_000,
    slots: [
      { questionId: 'q1', startsAt: OPENS - 4000, opensAt: OPENS, closesAt: CLOSES },
    ],
  }) as Round

beforeEach(async () => {
  await wipe(db)
  await db.recursiveDelete(db.collection('questions'))
  await db.recursiveDelete(db.collection('rounds'))
  await db.doc('questions/q1').set({
    theme: 'History',
    difficulty: 'easy',
    prompt: 'p',
    correct: 'Paris',
    incorrect: ['London'],
  })
})

const putAnswer = (uid: string, choice: string, atMs: number) =>
  db.doc(`rounds/${ROUND_ID}/answers/0_${uid}`).set({
    uid,
    slot: 0,
    choice,
    answeredAt: Timestamp.fromMillis(atMs),
  })

const entry = async (uid: string) =>
  (await db.doc(`rounds/${ROUND_ID}/entries/${uid}`).get()).data()

describe('scoreSlot', () => {
  it('does nothing when nobody answered', async () => {
    expect(await scoreSlot(db, round(), 0, DEFAULT_CONFIG)).toEqual({
      scored: 0,
      correct: 0,
    })
  })

  it('pays the maximum for an Answer at the instant the Window opened', async () => {
    await putAnswer('alice', 'Paris', OPENS)
    await scoreSlot(db, round(), 0, DEFAULT_CONFIG)

    expect(await entry('alice')).toMatchObject({
      score: DEFAULT_CONFIG.maxPoints,
      correct: 1,
      answered: 1,
    })
  })

  it('pays nothing for a wrong Answer but still records it', async () => {
    await putAnswer('bob', 'London', OPENS)
    await scoreSlot(db, round(), 0, DEFAULT_CONFIG)

    expect(await entry('bob')).toMatchObject({
      score: 0,
      correct: 0,
      answered: 1,
    })
  })

  it('decays with how long the Player took', async () => {
    await putAnswer('alice', 'Paris', OPENS)
    await putAnswer('bob', 'Paris', OPENS + (CLOSES - OPENS) / 2)
    await scoreSlot(db, round(), 0, DEFAULT_CONFIG)

    const [a, b] = [await entry('alice'), await entry('bob')]
    expect(a!.score).toBeGreaterThan(b!.score)
    expect(b!.score).toBeGreaterThan(DEFAULT_CONFIG.minPoints - 1)
  })

  it('times from the Window opening, not the Slot starting', async () => {
    // A Player who answered the instant Answers opened has spent no time at
    // all, even though four seconds of read phase came before it.
    await putAnswer('alice', 'Paris', OPENS)
    await scoreSlot(db, round(), 0, DEFAULT_CONFIG)

    expect((await entry('alice'))!.score).toBe(DEFAULT_CONFIG.maxPoints)
  })

  it('marks each Answer with its own outcome', async () => {
    await putAnswer('alice', 'Paris', OPENS)
    await putAnswer('bob', 'London', OPENS)
    await scoreSlot(db, round(), 0, DEFAULT_CONFIG)

    const a = await db.doc(`rounds/${ROUND_ID}/answers/0_alice`).get()
    const b = await db.doc(`rounds/${ROUND_ID}/answers/0_bob`).get()
    expect(a.data()).toMatchObject({ correct: true })
    expect(b.data()).toMatchObject({ correct: false, points: 0 })
  })

  it('accumulates across Slots rather than replacing', async () => {
    await putAnswer('alice', 'Paris', OPENS)
    await scoreSlot(db, round(), 0, DEFAULT_CONFIG)
    const first = (await entry('alice'))!.score

    await db.doc(`rounds/${ROUND_ID}/answers/0_alice`).delete()
    await putAnswer('alice', 'Paris', OPENS)
    await scoreSlot(db, round(), 0, DEFAULT_CONFIG)

    expect((await entry('alice'))!.score).toBe(first * 2)
  })

  it('records the Slot a Player first appeared on', async () => {
    await putAnswer('alice', 'Paris', OPENS)
    await db.doc(`rounds/${ROUND_ID}/answers/0_alice`).set(
      { firstSlot: 12 },
      { merge: true },
    )
    await scoreSlot(db, round(), 0, DEFAULT_CONFIG)

    expect((await entry('alice'))!.firstSlot).toBe(12)
  })

  it('scores a whole field of Players in one pass', async () => {
    for (let i = 0; i < 25; i++) {
      await putAnswer(`p${i}`, i % 2 === 0 ? 'Paris' : 'London', OPENS)
    }
    const result = await scoreSlot(db, round(), 0, DEFAULT_CONFIG)

    expect(result).toEqual({ scored: 25, correct: 13 })
  })
})
