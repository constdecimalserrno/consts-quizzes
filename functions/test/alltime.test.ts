import { afterAll, beforeEach, describe, expect, it } from 'vitest'

import {
  ALL_TIME_BOARD,
  foldRoundIntoCareers,
  publishAllTimeBoard,
} from '../src/alltime.js'
import { DEFAULT_CONFIG } from '../src/config.js'
import { testDb, wipe } from './harness.js'

const { db, dispose } = testDb()
afterAll(dispose)

const cfg = { ...DEFAULT_CONFIG, minRankedRounds: 2, rankedJoinBySlot: 5 }

beforeEach(async () => {
  await wipe(db)
  await db.recursiveDelete(db.collection('rounds'))
  await db.recursiveDelete(db.collection('leaderboards'))
})

const entry = async (round: string, uid: string, score: number, joinedAtSlot = 0) => {
  await db.doc(`rounds/${round}/entries/${uid}`).set({ uid, score, answered: 20 })
  await db
    .doc(`rounds/${round}/seatHolders/${uid}`)
    .set({ joinedAtSlot })
}

const career = async (uid: string) =>
  (await db.doc(`players/${uid}`).get()).data()?.career

const board = async () =>
  (await db.doc(ALL_TIME_BOARD).get()).data() as {
    top: { uid: string; averageScore: number; bestRound: number }[]
  }

describe('foldRoundIntoCareers', () => {
  it('does nothing for a Round nobody played', async () => {
    expect(await foldRoundIntoCareers(db, 'r1', cfg)).toBe(0)
  })

  it('records a first Round', async () => {
    await entry('r1', 'u1', 900)
    await foldRoundIntoCareers(db, 'r1', cfg)

    expect(await career('u1')).toMatchObject({
      roundsPlayed: 1,
      rankedRounds: 1,
      totalScore: 900,
      bestRound: 900,
      averageScore: 900,
    })
  })

  it('averages across Rounds', async () => {
    await entry('r1', 'u1', 900)
    await foldRoundIntoCareers(db, 'r1', cfg)
    await entry('r2', 'u1', 300)
    await foldRoundIntoCareers(db, 'r2', cfg)

    expect(await career('u1')).toMatchObject({
      rankedRounds: 2,
      averageScore: 600,
      bestRound: 900,
    })
  })

  it('keeps the best Round even when later ones are worse', async () => {
    await entry('r1', 'u1', 900)
    await foldRoundIntoCareers(db, 'r1', cfg)
    await entry('r2', 'u1', 100)
    await foldRoundIntoCareers(db, 'r2', cfg)

    expect((await career('u1'))!.bestRound).toBe(900)
  })

  it('counts a Round for a Player whose seat was never recorded', async () => {
    // An absent seat reads as slot 0: not being able to prove somebody joined
    // late is not a reason to leave them out.
    await db.doc('rounds/rX/entries/u1').set({ uid: 'u1', score: 500, answered: 20 })
    await foldRoundIntoCareers(db, 'rX', cfg)

    expect((await career('u1'))!.rankedRounds).toBe(1)
  })

  it('does not count a Round joined too late toward the average', async () => {
    await entry('r1', 'u1', 900, 0)
    await foldRoundIntoCareers(db, 'r1', cfg)
    await entry('r2', 'u1', 100, 18)
    await foldRoundIntoCareers(db, 'r2', cfg)

    const c = await career('u1')
    expect(c).toMatchObject({ roundsPlayed: 2, rankedRounds: 1 })
    // The late Round neither helped nor hurt.
    expect(c!.averageScore).toBe(900)
  })

  it('still shows a late Round as played', async () => {
    await entry('r1', 'u1', 100, 19)
    await foldRoundIntoCareers(db, 'r1', cfg)

    expect(await career('u1')).toMatchObject({
      roundsPlayed: 1,
      rankedRounds: 0,
      averageScore: 0,
    })
  })

  it('folds a whole field in one call', async () => {
    for (let i = 0; i < 30; i++) await entry('r1', `p${i}`, i * 10)
    expect(await foldRoundIntoCareers(db, 'r1', cfg)).toBe(30)
    expect((await career('p29'))!.averageScore).toBe(290)
  })
})

describe('publishAllTimeBoard', () => {
  const play = async (uid: string, scores: number[]) => {
    for (const [i, s] of scores.entries()) {
      await entry(`round${uid}${i}`, uid, s)
      await foldRoundIntoCareers(db, `round${uid}${i}`, cfg)
    }
    await db.doc(`players/${uid}`).set({ handle: `${uid}-001` }, { merge: true })
  }

  it('ranks by average, not by total', async () => {
    // `grinder` has far more points but a worse average than `sharp`.
    await play('sharp', [900, 900])
    await play('grinder', [400, 400, 400, 400, 400, 400, 400, 400])
    await publishAllTimeBoard(db, cfg, 1)

    const { top } = await board()
    expect(top[0]!.uid).toBe('sharp')
    expect(top[1]!.uid).toBe('grinder')
  })

  it('leaves out anyone below the minimum Rounds', async () => {
    await play('newcomer', [1000])
    await play('regular', [500, 500])
    await publishAllTimeBoard(db, cfg, 1)

    const { top } = await board()
    expect(top.map((t) => t.uid)).toEqual(['regular'])
  })

  it('shows the best Round alongside without ranking on it', async () => {
    await play('spiky', [1000, 100])
    await play('steady', [600, 600])
    await publishAllTimeBoard(db, cfg, 1)

    const { top } = await board()
    expect(top[0]!.uid).toBe('steady')
    expect(top[1]!.bestRound).toBe(1000)
  })

  it('keeps Bots off the human board', async () => {
    await play('human', [500, 500])
    await play('machine', [1000, 1000])
    await db.doc('players/machine').set({ bot: true }, { merge: true })
    await publishAllTimeBoard(db, cfg, 1)

    const { top } = await board()
    expect(top.map((t) => t.uid)).toEqual(['human'])
  })
})
