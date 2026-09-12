import { type Firestore } from 'firebase-admin/firestore'

import { foldRoundIntoCareers, publishAllTimeBoard } from './alltime.js'
import { scoreSlot } from './answers.js'
import { publishLiveBoard } from './leaderboard.js'
import { readConfig } from './config.js'
import {
  drawSlots,
  fillableThemes,
  LIVE_ROUND,
  planSlots,
  publicQuestion,

  type BankQuestion,
  type Rng,
  type Round,
} from './round.js'
import type { Theme } from './themes.js'

export type TickDeps = {
  db: Firestore
  /** Injected so tests can drive a whole Round in milliseconds. */
  now: () => number
  rng?: Rng
  /**
   * Asks for `tick` to be called again at a given instant. Cloud Tasks in
   * production; a no-op in tests, which call `tick` themselves.
   */
  schedule?: (at: number) => Promise<void>
}

export type TickResult =
  | { action: 'started'; roundId: string; theme: string }
  | { action: 'opened'; slot: number }
  | { action: 'closed'; slot: number }
  | { action: 'intermission' }
  | { action: 'idle' }

/**
 * Advances the game by one step and says what it did.
 *
 * This is the only way a Round moves. Everything — drawing a Round, opening
 * and closing Slots, the Intermission, starting the next Round — happens here,
 * so a test can drive the whole game with a fake clock and assert on documents
 * rather than on mocks.
 *
 * It is deliberately idempotent with respect to time: calling it twice at the
 * same instant does the same thing twice, and calling it late does whatever
 * should have happened by now. A dropped Cloud Task therefore costs one Slot's
 * timing, not the Round.
 */
export async function tick(deps: TickDeps): Promise<TickResult> {
  const { db } = deps
  const rng = deps.rng ?? Math.random
  const now = deps.now()

  const snap = await db.doc(LIVE_ROUND).get()
  const round = snap.exists ? (snap.data() as Round) : null

  if (!round || now >= round.nextRoundAt) {
    const started = await startRound(deps, rng, now, round?.theme, round?.nextTheme)
    await deps.schedule?.(started.slots[0]!.closesAt)
    return { action: 'started', roundId: started.id, theme: started.theme }
  }

  // Which Slot should be on screen at `now`, if any.
  const current = round.slots.findIndex(
    (s) => now >= s.startsAt && now < s.closesAt,
  )

  if (current === -1) {
    // Past the last Slot but not yet time for the next Round: Intermission.
    if (round.openSlot !== -1) {
      const cfg = await readConfig(db)
      await scoreSlot(db, round, round.openSlot, cfg)
      await publishLiveBoard(db, round.id, round.openSlot, now)

      // The Round is over, so careers settle now rather than when the next one
      // starts: the Intermission is exactly when somebody looks at the board.
      await foldRoundIntoCareers(db, round.id, cfg)
      await publishAllTimeBoard(db, cfg, now)

      const upcoming = await fillableThemes(db, cfg.slotsPerRound, round.theme)
      await db.doc(LIVE_ROUND).set(
        {
          openSlot: -1,
          question: null,
          nextTheme: upcoming[Math.floor(rng() * upcoming.length)]!,
        },
        { merge: true },
      )
      await deps.schedule?.(round.nextRoundAt)
      return { action: 'intermission' }
    }
    await deps.schedule?.(round.nextRoundAt)
    return { action: 'idle' }
  }

  if (current === round.openSlot) {
    await deps.schedule?.(round.slots[current]!.closesAt)
    return { action: 'idle' }
  }

  // The Slot that was on screen has just closed, so it is scored here, in the
  // same step that opens the next one: one wake-up per Slot, not two.
  if (round.openSlot >= 0) {
    await scoreSlot(db, round, round.openSlot, await readConfig(db))
    await publishLiveBoard(db, round.id, round.openSlot, now)
  }

  const plan = round.slots[current]!
  const bank = await db.doc(`questions/${plan.questionId}`).get()
  const q: BankQuestion = {
    id: bank.id,
    prompt: bank.data()?.prompt ?? '',
    correct: bank.data()?.correct ?? '',
    incorrect: bank.data()?.incorrect ?? [],
    difficulty: bank.data()?.difficulty ?? 'easy',
  }

  await db.doc(LIVE_ROUND).set(
    { openSlot: current, question: publicQuestion(q, plan, current, rng) },
    { merge: true },
  )
  // The next thing to happen is this Slot closing, which is also when the next
  // one opens: one task, not two.
  await deps.schedule?.(plan.closesAt)
  return { action: 'opened', slot: current }
}

async function startRound(
  deps: TickDeps,
  rng: Rng,
  now: number,
  previousTheme?: Theme,
  announced?: Theme,
): Promise<Round> {
  const { db } = deps
  const cfg = await readConfig(db)

  // If the Intermission already told the audience what is coming, honour it.
  // Announcing one Theme and then running another is worse than not announcing.
  const themes = await fillableThemes(db, cfg.slotsPerRound, previousTheme)
  const theme = announced && themes.includes(announced)
    ? announced
    : themes[Math.floor(rng() * themes.length)]!
  const questions = await drawSlots(db, theme, cfg.slotsPerRound, rng)
  const slots = planSlots(questions, now, cfg)
  const last = slots[slots.length - 1]

  const round: Round = {
    id: `r${now}`,
    theme,
    startedAt: now,
    endsAt: last?.closesAt ?? now,
    slots,
    openSlot: -1,
    question: null,
    nextRoundAt: (last?.closesAt ?? now) + cfg.intermissionSeconds * 1000,
  }
  await db.doc(LIVE_ROUND).set(round)

  // Open the first Slot in the same step, so a Round never begins with a gap.
  if (questions[0]) {
    await db.doc(LIVE_ROUND).set(
      {
        openSlot: 0,
        question: publicQuestion(questions[0], slots[0]!, 0, rng),
      },
      { merge: true },
    )
    round.openSlot = 0
  }
  return round
}
