import { createHash, randomBytes } from 'node:crypto'

import { FieldValue, type Firestore } from 'firebase-admin/firestore'

/**
 * Bots: Players that play through the API rather than the app.
 *
 * They are welcome. Rather than fight clients that read their own traffic —
 * which this game permits anyway — headless play is documented and supported,
 * which turns the broadcast into a trivia benchmark that runs around the
 * clock.
 *
 * They cannot share a Leaderboard with people. Scoring decays with elapsed
 * time, so a Bot answering in fifty milliseconds takes a perfect Round every
 * time and would own the human board permanently. The split is keyed off an
 * API key, and it is a category label rather than a security boundary — which
 * is consistent with permitting cheating in the first place.
 */
export type ApiKey = {
  /** Shown once, at creation. Only its hash is stored. */
  secret: string
  keyId: string
}

const hash = (secret: string) =>
  createHash('sha256').update(secret).digest('hex')

export async function issueApiKey(
  db: Firestore,
  uid: string,
  label: string,
): Promise<ApiKey> {
  const secret = `cq_${randomBytes(24).toString('hex')}`
  const keyId = hash(secret).slice(0, 16)

  await db.doc(`apiKeys/${keyId}`).set({
    uid,
    label,
    // The secret itself is never stored: a leaked key table should not be a
    // leaked set of working keys.
    secretHash: hash(secret),
    createdAt: FieldValue.serverTimestamp(),
    revokedAt: null,
  })
  // Marking the Player is what moves them to the Bot board.
  await db.doc(`players/${uid}`).set({ bot: true }, { merge: true })

  return { secret, keyId }
}

export async function revokeApiKey(
  db: Firestore,
  uid: string,
  keyId: string,
): Promise<boolean> {
  const ref = db.doc(`apiKeys/${keyId}`)
  const snap = await ref.get()
  if (!snap.exists || snap.data()?.uid !== uid) return false

  await ref.set({ revokedAt: FieldValue.serverTimestamp() }, { merge: true })
  return true
}

/** Resolves a presented key to the Player it belongs to, or null. */
export async function playerForKey(
  db: Firestore,
  secret: string,
): Promise<string | null> {
  const snap = await db.doc(`apiKeys/${hash(secret).slice(0, 16)}`).get()
  const data = snap.data()
  if (!data || data.revokedAt) return null
  return data.secretHash === hash(secret) ? (data.uid as string) : null
}

export const BOT_BOARD = 'leaderboards/bots'

/**
 * The Bot board, ranked the same way the human one is.
 *
 * Same rules, separate division — like a race that scores wheelchair entrants
 * on their own board rather than pretending the field is comparable.
 */
export async function publishBotBoard(
  db: Firestore,
  minRankedRounds: number,
  now: number,
): Promise<{ ranked: number }> {
  const snap = await db
    .collection('players')
    .where('career.rankedRounds', '>=', minRankedRounds)
    .orderBy('career.averageScore', 'desc')
    .limit(40)
    .get()

  const top = snap.docs
    .filter((d) => d.data().bot === true)
    .slice(0, 20)
    .map((d) => ({
      uid: d.id,
      handle: (d.data().handle as string) ?? 'someone',
      averageScore: (d.data().career?.averageScore as number) ?? 0,
      bestRound: (d.data().career?.bestRound as number) ?? 0,
      roundsPlayed: (d.data().career?.roundsPlayed as number) ?? 0,
    }))

  await db.doc(BOT_BOARD).set({ top, updatedAt: now })
  return { ranked: top.length }
}
