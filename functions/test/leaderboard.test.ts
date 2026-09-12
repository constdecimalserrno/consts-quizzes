import { afterAll, beforeEach, describe, expect, it } from 'vitest'

import { LIVE_BOARD, publishLiveBoard, TOP_N } from '../src/leaderboard.js'
import type { LiveBoard } from '../src/leaderboard.js'
import { testDb, wipe } from './harness.js'

const { db, dispose } = testDb()
afterAll(dispose)

const ROUND = 'r1'

beforeEach(async () => {
  await wipe(db)
  await db.recursiveDelete(db.collection('rounds'))
  await db.recursiveDelete(db.collection('leaderboards'))
})

async function seedPlayers(n: number, score: (i: number) => number) {
  const batch = db.batch()
  for (let i = 0; i < n; i++) {
    batch.set(db.doc(`players/u${i}`), { handle: `player-${i}-001` })
    batch.set(db.doc(`rounds/${ROUND}/entries/u${i}`), {
      uid: `u${i}`,
      score: score(i),
      correct: i % 3,
      answered: 5,
      firstSlot: 0,
    })
  }
  await batch.commit()
}

const board = async () =>
  (await db.doc(LIVE_BOARD).get()).data() as LiveBoard

describe('publishLiveBoard', () => {
  it('publishes an empty board when nobody has played', async () => {
    await publishLiveBoard(db, ROUND, 3, 1000)

    expect(await board()).toMatchObject({ playing: 0, top: [], slot: 3 })
  })

  it('ranks by score, highest first', async () => {
    await seedPlayers(5, (i) => i * 100)
    await publishLiveBoard(db, ROUND, 3, 1000)

    const { top } = await board()
    expect(top.map((t) => t.score)).toEqual([400, 300, 200, 100, 0])
  })

  it('names Players by Handle, never by uid', async () => {
    await seedPlayers(2, () => 100)
    await publishLiveBoard(db, ROUND, 1, 1000)

    expect((await board()).top.every((t) => t.handle.endsWith('-001'))).toBe(true)
  })

  it('counts everyone playing, not just those it names', async () => {
    await seedPlayers(TOP_N + 15, (i) => i)
    await publishLiveBoard(db, ROUND, 1, 1000)

    const b = await board()
    expect(b.playing).toBe(TOP_N + 15)
    expect(b.top).toHaveLength(TOP_N)
  })

  it('survives a Player whose document has been reaped', async () => {
    await seedPlayers(2, () => 100)
    await db.doc('players/u0').delete()

    await publishLiveBoard(db, ROUND, 1, 1000)
    const { top } = await board()
    expect(top).toHaveLength(2)
    expect(top.some((t) => t.handle === 'someone')).toBe(true)
  })

  it('replaces the board rather than accumulating', async () => {
    await seedPlayers(3, (i) => i)
    await publishLiveBoard(db, ROUND, 1, 1000)
    await db.recursiveDelete(db.collection(`rounds/${ROUND}/entries`))
    await publishLiveBoard(db, ROUND, 2, 2000)

    expect(await board()).toMatchObject({ top: [], playing: 0, slot: 2 })
  })
})
