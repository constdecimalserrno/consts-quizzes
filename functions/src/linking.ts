import { FieldValue, type Firestore } from 'firebase-admin/firestore'

import type { Career } from './alltime.js'

export type MergeResult = {
  /** The Player that survives: the one the viewer is now signed in as. */
  uid: string
  merged: boolean
  career: Career
}

const zero: Career = {
  rankedRounds: 0,
  roundsPlayed: 0,
  totalScore: 0,
  bestRound: 0,
  averageScore: 0,
}

const read = (raw: unknown): Career => {
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
 * Combines two careers into one.
 *
 * Totals add, the best Round is whichever was better, and the average is
 * recomputed from the combined totals rather than averaged — averaging two
 * averages weights a three-Round career the same as a three-hundred-Round one.
 */
export function combine(a: Career, b: Career): Career {
  const rankedRounds = a.rankedRounds + b.rankedRounds
  const totalScore = a.totalScore + b.totalScore
  return {
    roundsPlayed: a.roundsPlayed + b.roundsPlayed,
    rankedRounds,
    totalScore,
    bestRound: Math.max(a.bestRound, b.bestRound),
    averageScore: rankedRounds > 0 ? Math.round(totalScore / rankedRounds) : 0,
  }
}

/**
 * Folds an abandoned anonymous Player into the account it was linked to.
 *
 * Firebase linking handles the easy case itself: an anonymous account with a
 * provider attached keeps its uid, and nothing here runs. This is the other
 * case — the provider already belonged to an account, so linking fails, the
 * client signs in as the existing account instead, and the anonymous Player's
 * history would otherwise be stranded on a uid nobody will ever hold again.
 *
 * The surviving Player keeps their Handle. Two Handles cannot merge, and the
 * one somebody signed in to keep is the one they mean to be known by.
 */
export async function mergePlayers(
  db: Firestore,
  survivorUid: string,
  abandonedUid: string,
): Promise<MergeResult> {
  if (survivorUid === abandonedUid) {
    const snap = await db.doc(`players/${survivorUid}`).get()
    return { uid: survivorUid, merged: false, career: read(snap.data()?.career) }
  }

  return db.runTransaction(async (tx) => {
    const survivorRef = db.doc(`players/${survivorUid}`)
    const abandonedRef = db.doc(`players/${abandonedUid}`)
    const [survivor, abandoned] = await Promise.all([
      tx.get(survivorRef),
      tx.get(abandonedRef),
    ])

    // Nothing to take, or already taken: merging is idempotent so a client
    // that retries after a dropped connection does not double anyone's score.
    if (!abandoned.exists || abandoned.data()?.mergedInto) {
      return {
        uid: survivorUid,
        merged: false,
        career: read(survivor.data()?.career),
      }
    }

    const career = combine(
      read(survivor.data()?.career),
      read(abandoned.data()?.career),
    )

    tx.set(survivorRef, { career, anonymous: false }, { merge: true })
    // The abandoned Player is tombstoned rather than deleted: its Handle stays
    // reserved, and old links to it keep resolving to whoever it became.
    tx.set(
      abandonedRef,
      {
        mergedInto: survivorUid,
        mergedAt: FieldValue.serverTimestamp(),
        career: zero,
      },
      { merge: true },
    )
    return { uid: survivorUid, merged: true, career }
  })
}
