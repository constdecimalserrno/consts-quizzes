import { afterAll, beforeEach, describe, expect, it } from 'vitest'

import { ensurePlayer } from '../src/players.js'
import { testDb, wipe } from './harness.js'

const { db, dispose } = testDb()
const deps = { db }

afterAll(dispose)
beforeEach(() => wipe(db))

describe('ensurePlayer', () => {
  it('creates a Player document on first sight', async () => {
    await ensurePlayer(deps, 'u1', true)

    const snap = await db.doc('players/u1').get()
    expect(snap.exists).toBe(true)
    expect(snap.data()).toMatchObject({ anonymous: true })
    expect(snap.data()?.createdAt).toBeDefined()
  })

  it('leaves an existing Player alone but marks them seen', async () => {
    await ensurePlayer(deps, 'u1', true)
    const first = (await db.doc('players/u1').get()).data()!

    await new Promise((r) => setTimeout(r, 20))
    await ensurePlayer(deps, 'u1', true)
    const second = (await db.doc('players/u1').get()).data()!

    expect(second.createdAt.isEqual(first.createdAt)).toBe(true)
    expect(second.lastSeenAt.toMillis()).toBeGreaterThan(
      first.lastSeenAt.toMillis(),
    )
  })

  it('records whether the Player arrived anonymously', async () => {
    await ensurePlayer(deps, 'u2', false)
    expect((await db.doc('players/u2').get()).data()).toMatchObject({
      anonymous: false,
    })
  })
})
