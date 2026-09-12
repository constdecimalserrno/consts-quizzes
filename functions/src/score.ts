import type { AppConfig } from './config.js'

/**
 * Points for one Answer.
 *
 * Correct Answers decay linearly from `maxPoints` at the instant the Window
 * opens to `minPoints` at the instant it closes; wrong and absent Answers
 * score nothing. Ported from the Rust implementation, where it was already a
 * pure function of the Window rather than of any particular Slot length.
 *
 * `elapsed` is derived from the Answer's `answeredAt`, which security rules
 * pin to `request.time` — the server's clock at the moment of the write. A
 * client therefore cannot claim to have answered faster than it did; delaying
 * the write is possible and only costs them points.
 */
export function points(
  correct: boolean,
  elapsedMs: number,
  windowMs: number,
  cfg: Pick<AppConfig, 'maxPoints' | 'minPoints'>,
): number {
  if (!correct) return 0
  if (windowMs <= 0) return cfg.maxPoints

  const fraction = Math.min(1, Math.max(0, elapsedMs / windowMs))
  const spread = cfg.maxPoints - cfg.minPoints
  return Math.round(cfg.maxPoints - fraction * spread)
}
