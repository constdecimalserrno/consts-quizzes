import { afterAll, beforeEach, describe, expect, it } from 'vitest'

import {
  BOT_BOARD,
  issueApiKey,
  playerForKey,
  publishBotBoard,
  revokeApiKey,
} from '../src/bots.js'
import { testDb, wipe } from './harness.js'

const { db, dispose } = testDb()
afterAll(dispose)

beforeEach(async () => {
  await wipe(db)
  await db.recursiveDelete(db.collection('apiKeys'))
  await db.recursiveDelete(db.collection('leaderboards'))
})

describe('api keys', () => {
  it('issues a key that resolves back to its Player', async () => {
    const key = await issueApiKey(db, 'u1', 'my bot')

    expect(key.secret).toMatch(/^cq_[0-9a-f]{48}$/)
    expect(await playerForKey(db, key.secret)).toBe('u1')
  })

  it('never stores the secret itself', async () => {
    const key = await issueApiKey(db, 'u1', 'my bot')
    const stored = (await db.doc(`apiKeys/${key.keyId}`).get()).data()

    expect(JSON.stringify(stored)).not.toContain(key.secret)
  })

  it('marks the Player as a Bot', async () => {
    await issueApiKey(db, 'u1', 'my bot')

    expect((await db.doc('players/u1').get()).data()?.bot).toBe(true)
  })

  it('refuses a key that was never issued', async () => {
    expect(await playerForKey(db, 'cq_nonsense')).toBeNull()
  })

  it('refuses a revoked key', async () => {
    const key = await issueApiKey(db, 'u1', 'my bot')
    expect(await revokeApiKey(db, 'u1', key.keyId)).toBe(true)

    expect(await playerForKey(db, key.secret)).toBeNull()
  })

  it('will not let one Player revoke another Player`s key', async () => {
    const key = await issueApiKey(db, 'u1', 'my bot')

    expect(await revokeApiKey(db, 'someoneElse', key.keyId)).toBe(false)
    expect(await playerForKey(db, key.secret)).toBe('u1')
  })

  it('issues distinct keys to the same Player', async () => {
    const a = await issueApiKey(db, 'u1', 'one')
    const b = await issueApiKey(db, 'u1', 'two')

    expect(a.secret).not.toBe(b.secret)
    expect(await playerForKey(db, a.secret)).toBe('u1')
    expect(await playerForKey(db, b.secret)).toBe('u1')
  })
})

describe('bot board', () => {
  const career = (uid: string, avg: number, bot: boolean) =>
    db.doc(`players/${uid}`).set({
      handle: `${uid}-001`,
      bot,
      career: {
        rankedRounds: 5,
        roundsPlayed: 5,
        totalScore: avg * 5,
        bestRound: avg,
        averageScore: avg,
      },
    })

  const board = async () =>
    (await db.doc(BOT_BOARD).get()).data() as {
      top: { uid: string }[]
    }

  it('lists Bots and nobody else', async () => {
    await career('machine', 980, true)
    await career('person', 620, false)

    await publishBotBoard(db, 3, 1)

    expect((await board()).top.map((t) => t.uid)).toEqual(['machine'])
  })

  it('ranks Bots against each other by average', async () => {
    await career('fast', 980, true)
    await career('slower', 700, true)

    await publishBotBoard(db, 3, 1)

    expect((await board()).top.map((t) => t.uid)).toEqual(['fast', 'slower'])
  })

  it('is empty rather than absent when no Bot has qualified', async () => {
    await career('person', 620, false)
    await publishBotBoard(db, 3, 1)

    expect((await board()).top).toEqual([])
  })
})
