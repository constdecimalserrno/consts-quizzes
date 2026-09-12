import type { Firestore } from 'firebase-admin/firestore'

/**
 * Runtime knobs, published at `config/app`.
 *
 * Two rules govern every reader here, and both exist because the document is
 * edited by hand against a live game:
 *
 * - **It is published.** Anyone may read it, signed in or not. Never put a
 *   secret in it.
 * - **Absence means the conservative value.** A missing document, a missing
 *   field and a field of the wrong type all have to read as the default, or a
 *   typo in the console becomes an outage.
 */
export type AppConfig = {
  /** How many Slots make up a Round. */
  slotsPerRound: number
  /** How long a Slot is on screen, start to finish. */
  slotSeconds: number
  /** Lead-in before a Slot's Window opens: the Question is up, Answers bounce. */
  readSeconds: number
  /** Gap between the end of one Round and the start of the next. */
  intermissionSeconds: number
  /** Score for an instant correct Answer, decaying to `minPoints`. */
  maxPoints: number
  /** Floor for a correct Answer, however slow. */
  minPoints: number
}

export const DEFAULT_CONFIG: AppConfig = {
  slotsPerRound: 20,
  slotSeconds: 15,
  readSeconds: 4,
  intermissionSeconds: 60,
  maxPoints: 1000,
  minPoints: 100,
}

const positive = (v: unknown, fallback: number): number =>
  typeof v === 'number' && Number.isFinite(v) && v > 0 ? v : fallback

export async function readConfig(db: Firestore): Promise<AppConfig> {
  const snap = await db.doc('config/app').get()
  const raw = (snap.data() ?? {}) as Record<string, unknown>
  const n = <K extends keyof AppConfig>(k: K) =>
    positive(raw[k], DEFAULT_CONFIG[k])

  const cfg: AppConfig = {
    slotsPerRound: n('slotsPerRound'),
    slotSeconds: n('slotSeconds'),
    readSeconds: n('readSeconds'),
    intermissionSeconds: n('intermissionSeconds'),
    maxPoints: n('maxPoints'),
    minPoints: n('minPoints'),
  }

  // A read phase at least as long as the Slot would leave no Window at all, so
  // the Slot could never be answered. Treat it as the typo it is.
  if (cfg.readSeconds >= cfg.slotSeconds) {
    cfg.readSeconds = DEFAULT_CONFIG.readSeconds
    cfg.slotSeconds = Math.max(cfg.slotSeconds, DEFAULT_CONFIG.slotSeconds)
  }
  if (cfg.minPoints > cfg.maxPoints) {
    cfg.minPoints = DEFAULT_CONFIG.minPoints
    cfg.maxPoints = DEFAULT_CONFIG.maxPoints
  }
  return cfg
}
