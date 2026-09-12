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
const SLOT_MS = DEFAULT_CONFIG.slotSeconds * 1000
const READ_MS = DEFAULT_CONFIG.readSeconds * 1000

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
    expect(r.slots[0]!.opensAt).toBeLessThan(r.slots[0]!.closesAt)
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

    const result = await tick({ db, now: () => start + 1_000, rng: seeded(3) })
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
    const batch = db.batch()
    for (const difficulty of ['easy', 'medium', 'hard'] as const) {
      for (let i = 0; i < 12; i++) {
        batch.set(db.doc(`questions/geo-${difficulty}-${i}`), {
          theme: 'Geography',
          difficulty,
          prompt: `geo ${difficulty} ${i}`,
          correct: 'right',
          incorrect: ['a', 'b', 'c'],
          source: 'test',
          fetchedAt: 0,
        })
      }
    }
    await batch.commit()

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
