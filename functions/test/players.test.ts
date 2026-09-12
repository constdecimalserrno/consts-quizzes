import { afterAll, beforeEach, describe, expect, it } from 'vitest'

import { HANDLE_PATTERN, isHandle, randomHandle } from '../src/handles.js'
import { ensurePlayer } from '../src/players.js'
import { testDb, wipe } from './harness.js'

const { db, dispose } = testDb()
const deps = { db }

afterAll(dispose)
beforeEach(() => wipe(db))

describe('randomHandle', () => {
  it('produces the emotion-color-animal-NNN shape', () => {
    for (let i = 0; i < 50; i++) expect(randomHandle()).toMatch(HANDLE_PATTERN)
  })

  it('rejects anything that is not that shape', () => {
    expect(isHandle('grumpy-teal-walrus')).toBe(false) // the pre-number shape
    expect(isHandle('grumpy-teal-walrus-12')).toBe(false)
    expect(isHandle('Grumpy-Teal-Walrus-123')).toBe(false)
    expect(isHandle(42)).toBe(false)
  })

  it('draws widely enough that fifty in a row do not collide', () => {
    const seen = new Set(Array.from({ length: 50 }, randomHandle))
    expect(seen.size).toBe(50)
  })
})

describe('ensurePlayer', () => {
  it('mints a Handle on first sight and reserves it', async () => {
    const handle = await ensurePlayer(deps, 'u1', true)

    expect(handle).toMatch(HANDLE_PATTERN)
    expect((await db.doc('players/u1').get()).data()).toMatchObject({
      handle,
      anonymous: true,
    })
    expect((await db.doc(`handles/${handle}`).get()).data()).toMatchObject({
      uid: 'u1',
    })
  })

  it('returns the same Handle for a returning Player', async () => {
    const first = await ensurePlayer(deps, 'u1', true)
    const second = await ensurePlayer(deps, 'u1', true)

    expect(second).toBe(first)
  })

  it('marks a returning Player seen without disturbing createdAt', async () => {
    await ensurePlayer(deps, 'u1', true)
    const before = (await db.doc('players/u1').get()).data()!

    await new Promise((r) => setTimeout(r, 20))
    await ensurePlayer(deps, 'u1', true)
    const after = (await db.doc('players/u1').get()).data()!

    expect(after.createdAt.isEqual(before.createdAt)).toBe(true)
    expect(after.lastSeenAt.toMillis()).toBeGreaterThan(
      before.lastSeenAt.toMillis(),
    )
  })

  it('skips a Handle that is already reserved', async () => {
    const taken = await ensurePlayer(deps, 'u1', true)

    // A generator that offers the taken Handle first and a free one after.
    let call = 0
    const handle = await ensurePlayer(
      { db, newHandle: () => (call++ === 0 ? taken : 'jolly-teal-otter-777') },
      'u2',
      true,
    )

    expect(handle).toBe('jolly-teal-otter-777')
    expect((await db.doc(`handles/${taken}`).get()).data()).toMatchObject({
      uid: 'u1',
    })
  })

  it('gives up rather than handing out a Handle somebody else holds', async () => {
    const taken = await ensurePlayer(deps, 'u1', true)

    await expect(
      ensurePlayer({ db, newHandle: () => taken }, 'u2', true),
    ).rejects.toThrow(/no free handle/)
    expect((await db.doc('players/u2').get()).exists).toBe(false)
  })

  it('records whether the Player arrived anonymously', async () => {
    await ensurePlayer(deps, 'u2', false)
    expect((await db.doc('players/u2').get()).data()).toMatchObject({
      anonymous: false,
    })
  })
})
