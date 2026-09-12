import { FieldValue, type Firestore } from 'firebase-admin/firestore'

export type PlayerDeps = { db: Firestore }

/**
 * Creates `players/{uid}` if it is not already there, and returns nothing
 * either way.
 *
 * Minting a Handle happens here too, once there is one to mint. Until then the
 * document exists only so that later tickets have something to merge into, and
 * so a signed-in visitor is distinguishable from one who has never arrived.
 */
export async function ensurePlayer(
  { db }: PlayerDeps,
  uid: string,
  isAnonymous: boolean,
): Promise<void> {
  const ref = db.doc(`players/${uid}`)
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref)
    if (snap.exists) {
      tx.set(ref, { lastSeenAt: FieldValue.serverTimestamp() }, { merge: true })
      return
    }
    tx.create(ref, {
      anonymous: isAnonymous,
      createdAt: FieldValue.serverTimestamp(),
      lastSeenAt: FieldValue.serverTimestamp(),
    })
  })
}
