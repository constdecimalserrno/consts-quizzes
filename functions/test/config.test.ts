import { afterAll, beforeEach, describe, expect, it } from 'vitest'

import { DEFAULT_CONFIG, readConfig, slotMillis } from '../src/config.js'
import { testDb, wipe } from './harness.js'

const { db, dispose } = testDb()

afterAll(dispose)
beforeEach(() => wipe(db))

describe('readConfig', () => {
  it('caps the Round at 99 Players unless told otherwise', async () => {
    expect(DEFAULT_CONFIG.maxConcurrentPlayers).toBe(99)
    expect((await readConfig(db)).maxConcurrentPlayers).toBe(99)
  })

  it('falls back to defaults when the document is missing', async () => {
    expect(await readConfig(db)).toEqual(DEFAULT_CONFIG)
  })

  it('reads values that are present', async () => {
    await db.doc('config/app').set({ slotsPerRound: 5, intermissionSeconds: 10 })

    const cfg = await readConfig(db)
    expect(cfg.slotsPerRound).toBe(5)
    expect(cfg.intermissionSeconds).toBe(10)
    expect(cfg.answerSeconds).toBe(DEFAULT_CONFIG.answerSeconds)
  })

  it('treats a wrong type as absent rather than trusting it', async () => {
    await db.doc('config/app').set({ slotsPerRound: '5', answerSeconds: -3 })

    const cfg = await readConfig(db)
    expect(cfg.slotsPerRound).toBe(DEFAULT_CONFIG.slotsPerRound)
    expect(cfg.answerSeconds).toBe(DEFAULT_CONFIG.answerSeconds)
  })

  it('reads each of the four phases independently', async () => {
    await db.doc('config/app').set({ readSeconds: 5, revealSeconds: 6 })

    const cfg = await readConfig(db)
    expect(cfg.readSeconds).toBe(5)
    expect(cfg.revealSeconds).toBe(6)
    expect(cfg.answerSeconds).toBe(DEFAULT_CONFIG.answerSeconds)
    expect(cfg.transitionSeconds).toBe(DEFAULT_CONFIG.transitionSeconds)
  })

  it('adds the four phases up into a Slot', async () => {
    await db.doc('config/app').set({
      readSeconds: 3,
      answerSeconds: 10,
      revealSeconds: 4,
      transitionSeconds: 2,
    })

    expect(slotMillis(await readConfig(db))).toBe(19_000)
  })
})
