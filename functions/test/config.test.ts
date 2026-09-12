import { afterAll, beforeEach, describe, expect, it } from 'vitest'

import { DEFAULT_CONFIG, readConfig } from '../src/config.js'
import { testDb, wipe } from './harness.js'

const { db, dispose } = testDb()

afterAll(dispose)
beforeEach(() => wipe(db))

describe('readConfig', () => {
  it('falls back to defaults when the document is missing', async () => {
    expect(await readConfig(db)).toEqual(DEFAULT_CONFIG)
  })

  it('reads values that are present', async () => {
    await db.doc('config/app').set({ slotsPerRound: 5, intermissionSeconds: 10 })

    const cfg = await readConfig(db)
    expect(cfg.slotsPerRound).toBe(5)
    expect(cfg.intermissionSeconds).toBe(10)
    expect(cfg.slotSeconds).toBe(DEFAULT_CONFIG.slotSeconds)
  })

  it('treats a wrong type as absent rather than trusting it', async () => {
    await db.doc('config/app').set({ slotsPerRound: '5', slotSeconds: -3 })

    const cfg = await readConfig(db)
    expect(cfg.slotsPerRound).toBe(DEFAULT_CONFIG.slotsPerRound)
    expect(cfg.slotSeconds).toBe(DEFAULT_CONFIG.slotSeconds)
  })

  it('refuses a read phase that would leave no Window', async () => {
    await db.doc('config/app').set({ slotSeconds: 5, readSeconds: 9 })

    const cfg = await readConfig(db)
    expect(cfg.readSeconds).toBeLessThan(cfg.slotSeconds)
  })
})
