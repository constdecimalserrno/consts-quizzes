import { afterAll, beforeEach, describe, expect, it } from 'vitest'

import type { Career } from '../src/alltime.js'
import { combine, mergePlayers } from '../src/linking.js'
import { testDb, wipe } from './harness.js'

const { db, dispose } = testDb()
afterAll(dispose)

beforeEach(() => wipe(db))

const career = (p: Partial<Career>): Career => ({
  rankedRounds: 0,
  roundsPlayed: 0,
  totalScore: 0,
  bestRound: 0,
  averageScore: 0,
  ...p,
})

const player = (uid: string, c: Partial<Career>, handle = `${uid}-001`) =>
  db.doc(`players/${uid}`).set({ handle, career: career(c) })

const read = async (uid: string) => (await db.doc(`players/${uid}`).get()).data()

describe('combine', () => {
  it('adds totals and keeps the better best', () => {
    const a = career({ rankedRounds: 2, totalScore: 1000, bestRound: 700, roundsPlayed: 3 })
    const b = career({ rankedRounds: 3, totalScore: 900, bestRound: 900, roundsPlayed: 4 })

    expect(combine(a, b)).toMatchObject({
      rankedRounds: 5,
      totalScore: 1900,
      bestRound: 900,
      roundsPlayed: 7,
      averageScore: 380,
    })
  })

  it('recomputes the average from totals rather than averaging averages', () => {
    // Three Rounds at 900 and one at 100 is an average of 700, not 500.
    const many = career({ rankedRounds: 3, totalScore: 2700, averageScore: 900 })
    const one = career({ rankedRounds: 1, totalScore: 100, averageScore: 100 })

    expect(combine(many, one).averageScore).toBe(700)
  })

  it('handles two empty careers without dividing by zero', () => {
    expect(combine(career({}), career({})).averageScore).toBe(0)
  })
})

describe('mergePlayers', () => {
  it('combines an abandoned Player into the survivor', async () => {
    await player('kept', { rankedRounds: 2, totalScore: 1000, bestRound: 600, roundsPlayed: 2 })
    await player('anon', { rankedRounds: 1, totalScore: 800, bestRound: 800, roundsPlayed: 1 })

    const result = await mergePlayers(db, 'kept', 'anon')

    expect(result.merged).toBe(true)
    expect(result.career).toMatchObject({
      rankedRounds: 3,
      totalScore: 1800,
      bestRound: 800,
      averageScore: 600,
    })
  })

  it('leaves the survivor their own Handle', async () => {
    await player('kept', { rankedRounds: 1, totalScore: 100 }, 'chosen-name-001')
    await player('anon', { rankedRounds: 1, totalScore: 100 }, 'throwaway-002')

    await mergePlayers(db, 'kept', 'anon')

    expect((await read('kept'))!.handle).toBe('chosen-name-001')
  })

  it('tombstones rather than deletes, so the old Handle stays reserved', async () => {
    await player('kept', { rankedRounds: 1, totalScore: 100 })
    await player('anon', { rankedRounds: 1, totalScore: 900 })

    await mergePlayers(db, 'kept', 'anon')
    const gone = await read('anon')

    expect(gone).toBeDefined()
    expect(gone!.mergedInto).toBe('kept')
    expect(gone!.handle).toBe('anon-001')
    expect(gone!.career.totalScore).toBe(0)
  })

  it('does not double a score when the client retries', async () => {
    await player('kept', { rankedRounds: 1, totalScore: 100, roundsPlayed: 1 })
    await player('anon', { rankedRounds: 1, totalScore: 900, roundsPlayed: 1 })

    await mergePlayers(db, 'kept', 'anon')
    const second = await mergePlayers(db, 'kept', 'anon')

    expect(second.merged).toBe(false)
    expect((await read('kept'))!.career.totalScore).toBe(1000)
  })

  it('does nothing when the two are the same Player', async () => {
    await player('kept', { rankedRounds: 1, totalScore: 500 })

    const result = await mergePlayers(db, 'kept', 'kept')

    expect(result.merged).toBe(false)
    expect((await read('kept'))!.career.totalScore).toBe(500)
  })

  it('survives an abandoned uid that was never a Player', async () => {
    await player('kept', { rankedRounds: 1, totalScore: 500 })

    const result = await mergePlayers(db, 'kept', 'never-existed')

    expect(result.merged).toBe(false)
    expect(result.career.totalScore).toBe(500)
  })

  it('marks the survivor as no longer anonymous', async () => {
    await player('kept', { rankedRounds: 1, totalScore: 100 })
    await player('anon', { rankedRounds: 1, totalScore: 100 })

    await mergePlayers(db, 'kept', 'anon')

    expect((await read('kept'))!.anonymous).toBe(false)
  })
})
