import { afterAll, beforeEach, describe, expect, it } from 'vitest'

import { DEFAULT_CONFIG } from '../src/config.js'
import { LIVE_ROUND, ramp, shuffle, type Round } from '../src/round.js'
import { tick } from '../src/tick.js'
import { testDb, wipe } from './harness.js'

const { db, dispose } = testDb()

afterAll(dispose)

/** A deterministic generator, so a failing test fails the same way twice. */
const seeded = (seed: number) => () => {
  seed = (seed * 1664525 + 1013904223) % 4294967296
  return seed / 4294967296
}

const SLOTS = 4
const READ_MS = DEFAULT_CONFIG.readSeconds * 1000
const ANSWER_MS = DEFAULT_CONFIG.answerSeconds * 1000
/** A whole Slot: read, answer, reveal, then the beat before the next. */
const SLOT_MS =
  (DEFAULT_CONFIG.readSeconds +
    DEFAULT_CONFIG.answerSeconds +
    DEFAULT_CONFIG.revealSeconds +
    DEFAULT_CONFIG.transitionSeconds) *
  1000

async function seedTheme(theme: string, perDifficulty = 12) {
  const batch = db.batch()
  for (const difficulty of ['easy', 'medium', 'hard'] as const) {
    for (let i = 0; i < perDifficulty; i++) {
      batch.set(db.doc(`questions/${theme}-${difficulty}-${i}`), {
        theme,
        difficulty,
        prompt: `${theme} ${difficulty} ${i}`,
        correct: `right-${theme}-${difficulty}-${i}`,
        incorrect: ['w1', 'w2', 'w3'],
        source: 'test',
        fetchedAt: 0,
      })
    }
  }
  await batch.commit()
}

async function seedBank(perDifficulty = 12) {
  const batch = db.batch()
  for (const difficulty of ['easy', 'medium', 'hard'] as const) {
    for (let i = 0; i < perDifficulty; i++) {
      batch.set(db.doc(`questions/${difficulty}-${i}`), {
        theme: 'History',
        difficulty,
        prompt: `${difficulty} question ${i}`,
        correct: `right-${difficulty}-${i}`,
        incorrect: ['w1', 'w2', 'w3'],
        source: 'test',
        fetchedAt: 0,
      })
    }
  }
  await batch.commit()
}

beforeEach(async () => {
  await wipe(db)
  await db.recursiveDelete(db.collection('questions'))
  await db.recursiveDelete(db.collection('rounds'))
  await db.doc('config/app').set({ slotsPerRound: SLOTS })
  await seedBank()
})

const live = async () => (await db.doc(LIVE_ROUND).get()).data() as Round

describe('ramp', () => {
  it('runs easy through hard across the Round', () => {
    const r = ramp(20)
    expect(r).toHaveLength(20)
    expect(r[0]).toBe('easy')
    expect(r[19]).toBe('hard')
    const order = { easy: 0, medium: 1, hard: 2 }
    for (let i = 1; i < r.length; i++) {
      expect(order[r[i]!]).toBeGreaterThanOrEqual(order[r[i - 1]!])
    }
  })

  it('still produces one of each for a very short Round', () => {
    expect(new Set(ramp(3)).size).toBe(3)
  })
})

describe('shuffle', () => {
  it('keeps every element', () => {
    const xs = [1, 2, 3, 4, 5]
    expect([...shuffle([...xs], seeded(1))].sort()).toEqual(xs)
  })

  it('does not leave the correct Choice in one position', () => {
    const positions = new Set<number>()
    const rng = seeded(7)
    for (let i = 0; i < 40; i++) {
      positions.add(shuffle(['correct', 'a', 'b', 'c'], rng).indexOf('correct'))
    }
    expect(positions.size).toBeGreaterThan(1)
  })
})

describe('tick', () => {
  it('starts a Round and opens its first Slot in one step', async () => {
    const result = await tick({ db, now: () => 1_000, rng: seeded(1) })

    expect(result).toMatchObject({ action: 'started', theme: 'History' })
    const r = await live()
    expect(r.slots).toHaveLength(SLOTS)
    expect(r.openSlot).toBe(0)
    expect(r.question?.prompt).toBeDefined()
  })

  it('never publishes the correct Choice', async () => {
    await tick({ db, now: () => 1_000, rng: seeded(1) })
    const r = await live()

    const bank = await db.doc(`questions/${r.slots[0]!.questionId}`).get()
    expect(r.question!.choices).toContain(bank.data()!.correct)
    expect(JSON.stringify(r)).not.toContain('"correct"')
  })

  it('opens Answers only after the read phase', async () => {
    await tick({ db, now: () => 1_000, rng: seeded(1) })
    const r = await live()

    expect(r.slots[0]!.opensAt).toBe(r.slots[0]!.startsAt + READ_MS)
    expect(r.slots[0]!.closesAt).toBe(r.slots[0]!.opensAt + ANSWER_MS)
  })

  it('lays out all four phases in order', async () => {
    await tick({ db, now: () => 1_000, rng: seeded(1) })
    const p = (await live()).slots[0]!

    expect(p.startsAt).toBeLessThan(p.opensAt)
    expect(p.opensAt).toBeLessThan(p.closesAt)
    expect(p.closesAt).toBeLessThan(p.revealUntil)
    expect(p.revealUntil).toBeLessThan(p.endsAt)
  })

  it('runs Slots back to back with no gap', async () => {
    await tick({ db, now: () => 1_000, rng: seeded(1) })
    const slots = (await live()).slots

    for (let i = 1; i < slots.length; i++) {
      expect(slots[i]!.startsAt).toBe(slots[i - 1]!.endsAt)
    }
  })

  it('publishes the answer at the reveal, and not before', async () => {
    const start = 1_000
    await tick({ db, now: () => start, rng: seeded(1) })
    const plan = (await live()).slots[0]!

    // Mid-Window: still secret.
    await tick({ db, now: () => plan.opensAt + 1, rng: seeded(2) })
    expect((await live()).question?.correct).toBeUndefined()

    const result = await tick({ db, now: () => plan.closesAt + 1, rng: seeded(3) })
    expect(result).toMatchObject({ action: 'revealed', slot: 0 })

    const shown = (await live()).question!
    const bank = await db.doc(`questions/${plan.questionId}`).get()
    expect(shown.correct).toBe(bank.data()!.correct)
    expect(shown.choices).toContain(shown.correct)
  })

  it('does not reveal twice', async () => {
    const start = 1_000
    await tick({ db, now: () => start, rng: seeded(1) })
    const plan = (await live()).slots[0]!

    await tick({ db, now: () => plan.closesAt + 1, rng: seeded(3) })
    const again = await tick({ db, now: () => plan.closesAt + 2, rng: seeded(4) })

    expect(again).toMatchObject({ action: 'idle' })
  })

  it('clears the answer when the next Slot opens', async () => {
    const start = 1_000
    await tick({ db, now: () => start, rng: seeded(1) })
    const plan = (await live()).slots[0]!

    await tick({ db, now: () => plan.closesAt + 1, rng: seeded(3) })
    await tick({ db, now: () => plan.endsAt + 1, rng: seeded(5) })

    const q = (await live()).question!
    expect(q.slot).toBe(1)
    expect(q.correct).toBeUndefined()
  })

  it('advances to the next Slot when the previous one closes', async () => {
    const start = 1_000
    await tick({ db, now: () => start, rng: seeded(1) })

    const result = await tick({ db, now: () => start + SLOT_MS, rng: seeded(2) })
    expect(result).toMatchObject({ action: 'opened', slot: 1 })
    expect((await live()).question?.slot).toBe(1)
  })

  it('does nothing when called again inside the same Slot', async () => {
    const start = 1_000
    await tick({ db, now: () => start, rng: seeded(1) })
    const before = await live()

    const result = await tick({ db, now: () => start + 500, rng: seeded(3) })
    expect(result).toMatchObject({ action: 'idle' })
    expect((await live()).question).toEqual(before.question)
  })

  it('catches up rather than replaying when a Tick is dropped', async () => {
    const start = 1_000
    await tick({ db, now: () => start, rng: seeded(1) })

    // Slot 1's Tick never fires; the next one arrives during Slot 3.
    const result = await tick({
      db,
      now: () => start + SLOT_MS * 3 + 100,
      rng: seeded(4),
    })
    expect(result).toMatchObject({ action: 'opened', slot: 3 })
  })

  it('falls into an Intermission after the last Slot', async () => {
    const start = 1_000
    await tick({ db, now: () => start, rng: seeded(1) })

    const result = await tick({
      db,
      now: () => start + SLOT_MS * SLOTS + 10,
      rng: seeded(5),
    })
    expect(result).toMatchObject({ action: 'intermission' })
    const r = await live()
    expect(r.openSlot).toBe(-1)
    expect(r.question).toBeNull()
  })

  it('does not run the same Theme twice in a row', async () => {
    // Two Themes can fill a Round; the draw must alternate rather than repeat.
    await seedTheme('Geography')

    let now = 1_000
    const themes: string[] = []
    for (let round = 0; round < 4; round++) {
      await tick({ db, now: () => now, rng: seeded(round + 1) })
      themes.push((await live()).theme)
      now = (await live()).nextRoundAt + 1
    }

    for (let i = 1; i < themes.length; i++) {
      expect(themes[i]).not.toBe(themes[i - 1])
    }
  })

  it('still reaches the Intermission when a board fails to publish', async () => {
    // A leaderboard query that threw on the way into the Intermission once
    // froze every Round on its final Question. The state change comes first
    // now, and the bookkeeping cannot take the show down with it.
    await seedTheme('Geography')
    const start = 1_000
    await tick({ db, now: () => start, rng: seeded(1) })

    // Make the careers fold fail by removing what it reads.
    await db.recursiveDelete(db.collection(`rounds/${(await live()).id}/entries`))
    const failures: string[] = []

    const result = await tick({
      db,
      now: () => start + SLOT_MS * SLOTS + 10,
      rng: seeded(5),
      onError: (what) => failures.push(what),
    })

    expect(result).toMatchObject({ action: 'intermission' })
    const r = await live()
    expect(r.openSlot).toBe(-1)
    expect(r.question).toBeNull()
    expect(r.nextTheme).toBeDefined()
  })

  it('announces the next Theme during the Intermission', async () => {
    // Needs somewhere else to go: with one fillable Theme, repeating it is
    // correct rather than a bug.
    await seedTheme('Geography')
    const start = 1_000
    await tick({ db, now: () => start, rng: seeded(1) })

    await tick({
      db,
      now: () => start + SLOT_MS * SLOTS + 10,
      rng: seeded(5),
    })

    const r = await live()
    expect(r.openSlot).toBe(-1)
    expect(r.nextTheme).toBeDefined()
    expect(r.nextTheme).not.toBe(r.theme)
  })

  it('runs the Theme it announced', async () => {
    await seedTheme('Geography')
    const start = 1_000
    await tick({ db, now: () => start, rng: seeded(1) })
    await tick({ db, now: () => start + SLOT_MS * SLOTS + 10, rng: seeded(5) })
    const announced = (await live()).nextTheme

    const at = (await live()).nextRoundAt + 1
    await tick({ db, now: () => at, rng: seeded(6) })
    expect((await live()).theme).toBe(announced)
  })

  it('starts the next Round when the Intermission is over', async () => {
    const start = 1_000
    await tick({ db, now: () => start, rng: seeded(1) })
    const first = await live()

    const result = await tick({
      db,
      now: () => first.nextRoundAt + 1,
      rng: seeded(6),
    })
    expect(result).toMatchObject({ action: 'started' })
    expect((await live()).id).not.toBe(first.id)
  })

  it('runs a whole Round unattended', async () => {
    let now = 1_000
    const seen: string[] = []
    for (let i = 0; i < 40; i++) {
      seen.push((await tick({ db, now: () => now, rng: seeded(i) })).action)
      now += SLOT_MS / 2
    }
    expect(seen.filter((a) => a === 'opened').length).toBeGreaterThanOrEqual(
      SLOTS - 1,
    )
    expect(seen).toContain('intermission')
  })

  it('asks to be woken when the open Slot closes', async () => {
    const woken: number[] = []
    await tick({
      db,
      now: () => 1_000,
      rng: seeded(1),
      schedule: async (at) => void woken.push(at),
    })
    const r = await live()
    expect(woken).toEqual([r.slots[0]!.closesAt])
  })

  it('ramps Difficulty across the Round', async () => {
    await tick({ db, now: () => 1_000, rng: seeded(9) })
    const r = await live()

    const diffs: string[] = []
    for (const s of r.slots) {
      diffs.push((await db.doc(`questions/${s.questionId}`).get()).data()!.difficulty)
    }
    expect(diffs[0]).toBe('easy')
    expect(diffs[diffs.length - 1]).toBe('hard')
  })

  it('never draws the same Question twice in one Round', async () => {
    await tick({ db, now: () => 1_000, rng: seeded(11) })
    const ids = (await live()).slots.map((s) => s.questionId)

    expect(new Set(ids).size).toBe(ids.length)
  })
})
