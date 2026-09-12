import { describe, expect, it } from 'vitest'

import { DEFAULT_CONFIG } from '../src/config.js'
import { points } from '../src/score.js'

const cfg = DEFAULT_CONFIG
const WINDOW = 11_000

describe('points', () => {
  it('gives nothing for a wrong Answer, however fast', () => {
    expect(points(false, 0, WINDOW, cfg)).toBe(0)
  })

  it('gives the maximum for an instant correct Answer', () => {
    expect(points(true, 0, WINDOW, cfg)).toBe(cfg.maxPoints)
  })

  it('gives the minimum for one that lands as the Window closes', () => {
    expect(points(true, WINDOW, WINDOW, cfg)).toBe(cfg.minPoints)
  })

  it('decays linearly in between', () => {
    expect(points(true, WINDOW / 2, WINDOW, cfg)).toBe(
      (cfg.maxPoints + cfg.minPoints) / 2,
    )
  })

  it('never pays less than the minimum, even for a late write', () => {
    expect(points(true, WINDOW * 5, WINDOW, cfg)).toBe(cfg.minPoints)
  })

  it('never pays more than the maximum for a clock that ran backwards', () => {
    expect(points(true, -5_000, WINDOW, cfg)).toBe(cfg.maxPoints)
  })
})
