import { FieldValue, type Firestore } from 'firebase-admin/firestore'

import { randomHandle } from './handles.js'

export type PlayerDeps = {
  db: Firestore
  /** Injected so a test can force the collision path. */
  newHandle?: () => string
}

/**
 * How many Handles to try before giving up.
 *
 * The space is billions wide, so a single collision is already unlikely and
 * eight in a row effectively impossible. If this ever throws, the namespace is
 * not the problem — something else is.
 */
const HANDLE_ATTEMPTS = 8

/**
 * Creates `players/{uid}` with a Handle if it is not already there, and returns
 * the Handle either way.
 *
 * Uniqueness comes from creating `handles/{handle}` inside the same
 * transaction, not from trusting the random draw. A query cannot do this
 * safely — Firestore transactions do not prevent a document appearing that a
 * query did not see — but a create against a keyed document fails loudly if
 * somebody got there first.
 *
 * Handles are never released, including when the Player is later reaped. A
 * released Handle turns every old link into somebody else's page.
 */
export async function ensurePlayer(
  { db, newHandle = randomHandle }: PlayerDeps,
  uid: string,
  isAnonymous: boolean,
): Promise<string> {
  const ref = db.doc(`players/${uid}`)

  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref)
    const held = snap.data()?.handle
    if (typeof held === 'string' && held.length > 0) {
      tx.set(ref, { lastSeenAt: FieldValue.serverTimestamp() }, { merge: true })
      return held
    }

    let handle: string | null = null
    for (let i = 0; i < HANDLE_ATTEMPTS && handle === null; i++) {
      const candidate = newHandle()
      const taken = await tx.get(db.doc(`handles/${candidate}`))
      if (!taken.exists) handle = candidate
    }
    if (handle === null) {
      throw new Error(`no free handle in ${HANDLE_ATTEMPTS} attempts`)
    }

    tx.create(db.doc(`handles/${handle}`), {
      uid,
      createdAt: FieldValue.serverTimestamp(),
    })
    tx.set(
      ref,
      {
        handle,
        anonymous: isAnonymous,
        lastSeenAt: FieldValue.serverTimestamp(),
        ...(snap.exists ? {} : { createdAt: FieldValue.serverTimestamp() }),
      },
      { merge: true },
    )
    return handle
  })
}
