import { type Firestore } from 'firebase-admin/firestore'

import type { AppConfig } from './config.js'
import type { Difficulty, Theme } from './themes.js'
import { DIFFICULTIES, THEMES } from './themes.js'

/** Where the live document lives. One Round is live at a time, globally. */
export const LIVE_ROUND = 'rounds/current'

export type SlotPlan = {
  questionId: string
  /** Milliseconds since the epoch, absolute so a client needs no arithmetic. */
  startsAt: number
  /** When Answers begin to be accepted: `startsAt` plus the read phase. */
  opensAt: number
  closesAt: number
}

export type Round = {
  id: string
  theme: Theme
  startedAt: number
  endsAt: number
  slots: SlotPlan[]
  /** Index of the open Slot, or -1 during the Intermission. */
  openSlot: number
  /** Denormalised copy of the open Slot's Question. Never the correct Choice. */
  question: PublicQuestion | null
  nextRoundAt: number
}

export type PublicQuestion = {
  slot: number
  prompt: string
  /** Shuffled, so the correct Choice is not always in the same position. */
  choices: string[]
  difficulty: Difficulty
  opensAt: number
  closesAt: number
}

export type Rng = () => number

/**
 * Shuffles in place, Fisher-Yates.
 *
 * The naive `sort(() => rng() - 0.5)` is not a shuffle: it produces a
 * distribution that leans heavily toward the original order, which here would
 * mean the correct Choice showing up in the same slot far more often than one
 * time in four.
 */
export function shuffle<T>(xs: T[], rng: Rng): T[] {
  for (let i = xs.length - 1; i > 0; i--) {
    const j = Math.floor(rng() * (i + 1))
    ;[xs[i], xs[j]] = [xs[j]!, xs[i]!]
  }
  return xs
}

/**
 * How a Round's Difficulty ramp is split across its Slots.
 *
 * Three buckets over twenty Slots is the whole of the ramp — Slots 1 and 7 are
 * indistinguishable. That is accepted: observed difficulty, derived from how
 * often a Question is actually answered correctly, is the upgrade, and it
 * cannot be computed before anyone has played.
 */
export function ramp(slots: number): Difficulty[] {
  if (slots <= 0) return []
  if (slots === 1) return ['easy']
  if (slots === 2) return ['easy', 'hard']

  // Floors rather than a proportional split, so that a short Round still ends
  // on a hard Question. Taking the ceiling of both ends leaves the remainder at
  // zero and a four-Slot Round never gets out of medium.
  const easy = Math.max(1, Math.floor(slots * 0.35))
  const hard = Math.max(1, Math.floor(slots * 0.3))
  const medium = slots - easy - hard

  return [
    ...Array<Difficulty>(easy).fill('easy'),
    ...Array<Difficulty>(Math.max(0, medium)).fill('medium'),
    ...Array<Difficulty>(hard).fill('hard'),
  ].slice(0, slots)
}

export type BankQuestion = {
  id: string
  prompt: string
  correct: string
  incorrect: string[]
  difficulty: Difficulty
}

/**
 * Draws a Round's worth of Questions for one Theme, easy first.
 *
 * Reads each Difficulty separately because the ramp needs a known count of
 * each, and orders by a random cursor rather than fetching the Theme and
 * shuffling in memory — a Theme can hold hundreds of Questions and this runs
 * every few minutes.
 *
 * A Difficulty that comes up short is topped up from whatever the Theme does
 * have. A Theme with too few Questions overall should not have been chosen;
 * see `fillableThemes`.
 */
export async function drawSlots(
  db: Firestore,
  theme: Theme,
  count: number,
  rng: Rng,
): Promise<BankQuestion[]> {
  const wanted = ramp(count)
  const need: Record<Difficulty, number> = { easy: 0, medium: 0, hard: 0 }
  for (const d of wanted) need[d]++

  const pools: Record<Difficulty, BankQuestion[]> = {
    easy: [],
    medium: [],
    hard: [],
  }
  for (const d of DIFFICULTIES) {
    // `__name__ >= <random id>` gives a cheap random window into the Theme
    // without an extra indexed field or a full read of the collection.
    const cursor = Math.random().toString(16).slice(2, 10)
    const at = (op: FirebaseFirestore.WhereFilterOp, limit: number) =>
      db
        .collection('questions')
        .where('theme', '==', theme)
        .where('difficulty', '==', d)
        .orderBy('__name__')
        .where('__name__', op, db.doc(`questions/${cursor}`))
        .limit(limit)
        .get()

    const take = need[d] * 3
    const first = await at('>=', take)
    const docs = [...first.docs]
    if (docs.length < take) docs.push(...(await at('<', take - docs.length)).docs)

    pools[d] = docs.map((doc) => ({
      id: doc.id,
      prompt: doc.data().prompt,
      correct: doc.data().correct,
      incorrect: doc.data().incorrect ?? [],
      difficulty: d,
    }))
    shuffle(pools[d], rng)
  }

  const spare = () => [...pools.easy, ...pools.medium, ...pools.hard]
  const out: BankQuestion[] = []
  const used = new Set<string>()
  for (const d of wanted) {
    let q = pools[d].pop()
    while (q && used.has(q.id)) q = pools[d].pop()
    if (!q) {
      const alt = spare().find((c) => !used.has(c.id))
      if (!alt) break
      q = alt
    }
    used.add(q.id)
    out.push(q)
  }
  return out
}

/** Builds the Slot schedule. Every time is absolute; clients do no arithmetic. */
export function planSlots(
  questions: BankQuestion[],
  startedAt: number,
  cfg: AppConfig,
): SlotPlan[] {
  return questions.map((q, i) => {
    const startsAt = startedAt + i * cfg.slotSeconds * 1000
    return {
      questionId: q.id,
      startsAt,
      opensAt: startsAt + cfg.readSeconds * 1000,
      closesAt: startsAt + cfg.slotSeconds * 1000,
    }
  })
}

/** The public projection of a Slot: everything but the answer. */
export function publicQuestion(
  q: BankQuestion,
  plan: SlotPlan,
  slot: number,
  rng: Rng,
): PublicQuestion {
  return {
    slot,
    prompt: q.prompt,
    choices: shuffle([q.correct, ...q.incorrect], rng),
    difficulty: q.difficulty,
    opensAt: plan.opensAt,
    closesAt: plan.closesAt,
  }
}

/**
 * Themes with enough Questions to fill a Round.
 *
 * The tail of the taxonomy is thin — some Themes hold fewer Questions than a
 * Round has Slots — and picking one uniformly would produce a Round that
 * repeats itself inside a single sitting.
 */
export async function fillableThemes(
  db: Firestore,
  slots: number,
  exclude?: Theme,
): Promise<Theme[]> {
  const counts = await Promise.all(
    THEMES.map(async (theme) => {
      const snap = await db
        .collection('questions')
        .where('theme', '==', theme)
        .count()
        .get()
      return [theme, snap.data().count] as const
    }),
  )
  // Twice a Round's length, so consecutive Rounds on a Theme are not identical.
  const fillable = counts.filter(([, n]) => n >= slots * 2).map(([t]) => t)
  const pool = fillable.length > 0 ? fillable : counts.map(([t]) => t)

  // Back-to-back Rounds on the same Theme read as a bug even when they are
  // honest chance, so the Theme that just ran is off the table — unless it is
  // the only one that can fill a Round.
  const fresh = pool.filter((t) => t !== exclude)
  return fresh.length > 0 ? fresh : pool
}
