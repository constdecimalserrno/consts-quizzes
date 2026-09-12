import { FieldValue, type Firestore } from 'firebase-admin/firestore'

import type { AppConfig } from './config.js'
import { points } from './score.js'
import { LIVE_ROUND, type Round } from './round.js'

/**
 * Scores every Answer for one Slot and folds the result into each Player's
 * Entry.
 *
 * Runs when the Slot closes, from the same Tick that opens the next one. The
 * correct Choice is read here and never leaves the server.
 *
 * Answers arrive as `rounds/{roundId}/answers/{slot}_{uid}` — a flat
 * collection keyed so that a Player can hold exactly one Answer per Slot, which
 * is what makes the write-once rule expressible in security rules.
 */
export async function scoreSlot(
  db: Firestore,
  round: Round,
  slot: number,
  cfg: AppConfig,
): Promise<{ scored: number; correct: number }> {
  const plan = round.slots[slot]
  if (!plan) return { scored: 0, correct: 0 }

  const [bank, answers] = await Promise.all([
    db.doc(`questions/${plan.questionId}`).get(),
    db
      .collection(`rounds/${round.id}/answers`)
      .where('slot', '==', slot)
      .get(),
  ])
  if (answers.empty) return { scored: 0, correct: 0 }

  const answer = bank.data()?.correct as string | undefined
  const windowMs = plan.closesAt - plan.opensAt
  let correctCount = 0

  const batch = db.batch()
  for (const doc of answers.docs) {
    const d = doc.data()
    const uid = d.uid as string
    const wasCorrect = typeof answer === 'string' && d.choice === answer
    if (wasCorrect) correctCount++

    // Elapsed is measured from the Window opening, not from the Slot starting:
    // the read phase is not part of what a Player is being timed on.
    const elapsed = Math.max(0, (d.answeredAt?.toMillis?.() ?? plan.closesAt) - plan.opensAt)
    const earned = points(wasCorrect, elapsed, windowMs, cfg)

    batch.set(doc.ref, { correct: wasCorrect, points: earned }, { merge: true })
    batch.set(
      db.doc(`rounds/${round.id}/entries/${uid}`),
      {
        uid,
        score: FieldValue.increment(earned),
        answered: FieldValue.increment(1),
        correct: FieldValue.increment(wasCorrect ? 1 : 0),
        firstSlot: d.firstSlot ?? slot,
      },
      { merge: true },
    )
  }
  await batch.commit()

  return { scored: answers.size, correct: correctCount }
}

/** The live Round id, for a client that needs to address its Answer. */
export const liveRoundPath = LIVE_ROUND
