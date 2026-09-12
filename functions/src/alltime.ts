import { FieldValue, type Firestore } from 'firebase-admin/firestore'

import type { AppConfig } from './config.js'
import { TOP_N } from './leaderboard.js'

export const ALL_TIME_BOARD = 'leaderboards/allTime'

export type Career = {
  /** Rounds counted toward the average: joined early enough to compete. */
  rankedRounds: number
  /** Every Round played, ranked or not. Shown, never ranked on. */
  roundsPlayed: number
  totalScore: number
  bestRound: number
  averageScore: number
}

const EMPTY: Career = {
  rankedRounds: 0,
  roundsPlayed: 0,
  totalScore: 0,
  bestRound: 0,
  averageScore: 0,
}

const readCareer = (raw: unknown): Career => {
  const c = (raw ?? {}) as Partial<Career>
  const n = (v: unknown) => (typeof v === 'number' && v >= 0 ? v : 0)
  return {
    rankedRounds: n(c.rankedRounds),
    roundsPlayed: n(c.roundsPlayed),
    totalScore: n(c.totalScore),
    bestRound: n(c.bestRound),
    averageScore: n(c.averageScore),
  }
}

/**
 * Folds a finished Round's Entries into each Player's career.
 *
 * Read, compute, write — no transactions and no increments. This runs once per
 * Round, from the Tick, so there is exactly one writer; a transaction would
 * buy nothing and `bestRound` is a maximum, which `increment` cannot express
 * anyway.
 *
 * Careers are stored rather than derived because ranking all-time otherwise
 * means reading every Entry ever written, every time anybody looks.
 *
 * An Entry from a Player who joined late is recorded but does not count toward
 * the average. They played; they were not in a position to compete.
 */
export async function foldRoundIntoCareers(
  db: Firestore,
  roundId: string,
  cfg: AppConfig,
): Promise<number> {
  const entries = await db.collection(`rounds/${roundId}/entries`).get()
  if (entries.empty) return 0

  for (let i = 0; i < entries.docs.length; i += 200) {
    const slice = entries.docs.slice(i, i + 200)
    const [players, seats] = await Promise.all([
      db.getAll(...slice.map((d) => db.doc(`players/${d.id}`))),
      // Where each Player came in, recorded once when they took their seat.
      // Deriving it from Answers instead would need a read per Slot, and an
      // earlier attempt that folded it into scoring silently recorded the
      // *last* Slot answered — which marked anyone who played to the end as a
      // late joiner and left them permanently unranked.
      db.getAll(...slice.map((d) => db.doc(`rounds/${roundId}/seatHolders/${d.id}`))),
    ])

    const batch = db.batch()
    for (const [n, entry] of slice.entries()) {
      const score = (entry.data().score as number) ?? 0
      const joinedAt = (seats[n]?.data()?.joinedAtSlot as number) ?? 0
      const ranked = joinedAt <= cfg.rankedJoinBySlot
      const was = readCareer(players[n]?.data()?.career)

      const rankedRounds = was.rankedRounds + (ranked ? 1 : 0)
      const totalScore = was.totalScore + (ranked ? score : 0)

      const career: Career = {
        roundsPlayed: was.roundsPlayed + 1,
        rankedRounds,
        totalScore,
        bestRound: Math.max(was.bestRound, score),
        averageScore: rankedRounds > 0 ? Math.round(totalScore / rankedRounds) : 0,
      }
      batch.set(
        db.doc(`players/${entry.id}`),
        { career, lastSeenAt: FieldValue.serverTimestamp() },
        { merge: true },
      )
    }
    await batch.commit()
  }
  return entries.size
}

export type CareerStanding = {
  uid: string
  handle: string
  averageScore: number
  bestRound: number
  roundsPlayed: number
}

/**
 * Publishes the all-time board.
 *
 * Ranked on average rather than lifetime total. In a game that never stops —
 * and that welcomes Bots — a cumulative board ranks by how long a tab was left
 * open, which is not an achievement. The minimum-Rounds floor stops one lucky
 * Round sitting on top forever.
 *
 * Bots are excluded here and ranked on their own board: a Bot answers
 * instantly and would take every place on this one.
 */
export async function publishAllTimeBoard(
  db: Firestore,
  cfg: AppConfig,
  now: number,
): Promise<{ ranked: number }> {
  const snap = await db
    .collection('players')
    .where('career.rankedRounds', '>=', cfg.minRankedRounds)
    .orderBy('career.averageScore', 'desc')
    .limit(TOP_N * 2)
    .get()

  const top: CareerStanding[] = snap.docs
    .filter((d) => d.data().bot !== true)
    .slice(0, TOP_N)
    .map((d) => ({
      uid: d.id,
      handle: (d.data().handle as string) ?? 'someone',
      averageScore: (d.data().career?.averageScore as number) ?? 0,
      bestRound: (d.data().career?.bestRound as number) ?? 0,
      roundsPlayed: (d.data().career?.roundsPlayed as number) ?? 0,
    }))

  await db.doc(ALL_TIME_BOARD).set({ top, updatedAt: now })
  return { ranked: top.length }
}
