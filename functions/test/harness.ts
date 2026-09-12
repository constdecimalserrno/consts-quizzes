import { deleteApp, initializeApp } from 'firebase-admin/app'
import { getFirestore, type Firestore } from 'firebase-admin/firestore'

export const PROJECT_ID = 'consts-quizzes-test'

/**
 * An Admin SDK handle on the Firestore emulator.
 *
 * These tests drive the real seams against a real database rather than a mock,
 * because what they are checking — transactions, merges, server timestamps — is
 * exactly the part a mock would get wrong.
 */
export function testDb(): { db: Firestore; dispose: () => Promise<void> } {
  process.env.FIRESTORE_EMULATOR_HOST ??= '127.0.0.1:8080'
  const app = initializeApp({ projectId: PROJECT_ID }, `t${Math.random()}`)
  return { db: getFirestore(app), dispose: () => deleteApp(app) }
}

export async function wipe(db: Firestore): Promise<void> {
  await db.recursiveDelete(db.collection('players'))
  await db.recursiveDelete(db.collection('config'))
}
