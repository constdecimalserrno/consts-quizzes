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
  /**
   * The four phases of a Slot, in order.
   *
   * Ported from the Rust game, where the shape earns its keep: you read before
   * you can answer, you answer against a draining clock, you are told what the
   * answer was, and then there is a beat before the next one. Collapsing read
   * and answer into one phase makes the first second of every Question a
   * scramble; collapsing away reveal means nobody ever learns anything.
   */
  readSeconds: number
  answerSeconds: number
  revealSeconds: number
  transitionSeconds: number
  /** Gap between the end of one Round and the start of the next. */
  intermissionSeconds: number
  /** Score for an instant correct Answer, decaying to `minPoints`. */
  maxPoints: number
  /** Floor for a correct Answer, however slow. */
  minPoints: number
  /**
   * How many Players may hold a seat in a Round at once.
   *
   * This is the budget. Spend is dominated by per-Player-per-Slot reads and
   * writes, which scale linearly with Players, and billing alerts arrive six
   * to twenty-four hours late — so the only guard that acts in time is the one
   * on the way in. Changing this is a spending decision, not a config tweak.
   */
  maxConcurrentPlayers: number
  /**
   * How many Rounds a Player must finish before they are ranked all-time.
   *
   * Ranking on average without a floor means one lucky Round tops the board
   * forever.
   */
  minRankedRounds: number
  /**
   * The last Slot a Player can join on and still have the Round count toward
   * their average.
   *
   * Without this, dropping in near the end permanently damages a rating and
   * people stop dropping in — which is the one thing this game is for.
   */
  rankedJoinBySlot: number
  /** How long an anonymous Player may be idle before the Reaper takes them. */
  reaperDays: number
}

export const DEFAULT_CONFIG: AppConfig = {
  slotsPerRound: 20,
  readSeconds: 3,
  answerSeconds: 10,
  revealSeconds: 4,
  transitionSeconds: 2,
  intermissionSeconds: 60,
  maxPoints: 1000,
  minPoints: 100,
  maxConcurrentPlayers: 99,
  minRankedRounds: 3,
  rankedJoinBySlot: 5,
  reaperDays: 90,
}

const positive = (v: unknown, fallback: number): number =>
  typeof v === 'number' && Number.isFinite(v) && v > 0 ? v : fallback

/**
 * Whether the game is open for business.
 *
 * Flipped by the budget watcher when spend crosses the soft threshold. Read
 * separately from the rest of the config because it is the one field a client
 * needs before it does anything else.
 */
export async function isOpen(db: Firestore): Promise<boolean> {
  const snap = await db.doc('config/app').get()
  // Absence means open: a missing document must not take the game down.
  return snap.data()?.killSwitch !== true
}

export async function readConfig(db: Firestore): Promise<AppConfig> {
  const snap = await db.doc('config/app').get()
  const raw = (snap.data() ?? {}) as Record<string, unknown>
  const n = <K extends keyof AppConfig>(k: K) =>
    positive(raw[k], DEFAULT_CONFIG[k])

  const cfg: AppConfig = {
    slotsPerRound: n('slotsPerRound'),
    readSeconds: n('readSeconds'),
    answerSeconds: n('answerSeconds'),
    revealSeconds: n('revealSeconds'),
    transitionSeconds: n('transitionSeconds'),
    intermissionSeconds: n('intermissionSeconds'),
    maxPoints: n('maxPoints'),
    minPoints: n('minPoints'),
    maxConcurrentPlayers: n('maxConcurrentPlayers'),
    minRankedRounds: n('minRankedRounds'),
    rankedJoinBySlot: n('rankedJoinBySlot'),
    reaperDays: n('reaperDays'),
  }

  if (cfg.minPoints > cfg.maxPoints) {
    cfg.minPoints = DEFAULT_CONFIG.minPoints
    cfg.maxPoints = DEFAULT_CONFIG.maxPoints
  }
  return cfg
}

/** How long one Slot takes, all four phases. */
export const slotMillis = (cfg: AppConfig): number =>
  (cfg.readSeconds +
    cfg.answerSeconds +
    cfg.revealSeconds +
    cfg.transitionSeconds) *
  1000
