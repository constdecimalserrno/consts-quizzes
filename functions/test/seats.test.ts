import { afterAll, beforeEach, describe, expect, it } from 'vitest'

import { verdict } from '../src/budget.js'
import { isOpen } from '../src/config.js'
import { seatDoc, takeSeat } from '../src/seats.js'
import { testDb, wipe } from './harness.js'

const { db, dispose } = testDb()
afterAll(dispose)

const ROUND = 'r1'

beforeEach(async () => {
  await wipe(db)
  await db.recursiveDelete(db.collection('rounds'))
})

const taken = async () =>
  (await db.doc(seatDoc(ROUND)).get()).data()?.taken ?? 0

describe('takeSeat', () => {
  it('seats a Player when there is room', async () => {
    expect(await takeSeat(db, ROUND, 'u1', 3, true)).toMatchObject({
      seated: true,
    })
    expect(await taken()).toBe(1)
  })

  it('refuses once the cap is reached', async () => {
    for (const u of ['a', 'b', 'c']) await takeSeat(db, ROUND, u, 3, true)

    expect(await takeSeat(db, ROUND, 'd', 3, true)).toMatchObject({
      seated: false,
      reason: 'full',
    })
    expect(await taken()).toBe(3)
  })

  it('does not spend a second seat on a Player who already holds one', async () => {
    await takeSeat(db, ROUND, 'u1', 3, true)
    await takeSeat(db, ROUND, 'u1', 3, true)
    await takeSeat(db, ROUND, 'u1', 3, true)

    expect(await taken()).toBe(1)
  })

  it('still seats a returning Player when the Round is full', async () => {
    await takeSeat(db, ROUND, 'u1', 1, true)

    // A refresh must not lock somebody out of the Round they are already in.
    expect(await takeSeat(db, ROUND, 'u1', 1, true)).toMatchObject({
      seated: true,
    })
  })

  it('admits nobody at all when the game is closed', async () => {
    expect(await takeSeat(db, ROUND, 'u1', 100, false)).toMatchObject({
      seated: false,
      reason: 'closed',
    })
    expect(await taken()).toBe(0)
  })

  it('never admits more than the cap when everyone arrives at once', async () => {
    const cap = 5
    await Promise.all(
      Array.from({ length: 25 }, (_, i) =>
        takeSeat(db, ROUND, `p${i}`, cap, true).catch(() => null),
      ),
    )

    expect(await taken()).toBeLessThanOrEqual(cap)
  })

  it('counts seats per Round, so a new Round starts empty', async () => {
    await takeSeat(db, ROUND, 'u1', 3, true)
    await takeSeat(db, 'r2', 'u1', 3, true)

    expect((await db.doc(seatDoc('r2')).get()).data()?.taken).toBe(1)
  })
})

describe('isOpen', () => {
  it('is open when there is no config at all', async () => {
    expect(await isOpen(db)).toBe(true)
  })

  it('is open when the field is absent', async () => {
    await db.doc('config/app').set({ slotsPerRound: 20 })
    expect(await isOpen(db)).toBe(true)
  })

  it('closes only on an actual true', async () => {
    await db.doc('config/app').set({ killSwitch: true })
    expect(await isOpen(db)).toBe(false)
  })

  it('is not closed by a stray string', async () => {
    await db.doc('config/app').set({ killSwitch: 'true' })
    expect(await isOpen(db)).toBe(true)
  })
})

describe('budget verdict', () => {
  it('says nothing is wrong well under budget', () => {
    expect(verdict({ costAmount: 10, budgetAmount: 50 })).toBe('ok')
  })

  it('trips soft at four fifths', () => {
    expect(verdict({ costAmount: 40, budgetAmount: 50 })).toBe('soft')
  })

  it('trips hard at the budget', () => {
    expect(verdict({ costAmount: 50, budgetAmount: 50 })).toBe('hard')
  })

  it('ignores a message it cannot read rather than shutting the game down', () => {
    expect(verdict({})).toBe('ok')
    expect(verdict({ costAmount: 40 })).toBe('ok')
    expect(verdict({ costAmount: 40, budgetAmount: 0 })).toBe('ok')
  })
})
