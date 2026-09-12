import { initializeApp } from 'firebase-admin/app'
import { getFirestore } from 'firebase-admin/firestore'
import { setGlobalOptions } from 'firebase-functions/v2'
import { HttpsError, onCall } from 'firebase-functions/v2/https'

import { ensurePlayer as ensurePlayerDoc } from './players.js'

initializeApp()

// Spend here scales with the number of function instances as much as with the
// number of Players, and a billing alert arrives a day late. `maxInstances` is
// the guard that acts immediately, so it is set once, globally, rather than
// remembered per function.
setGlobalOptions({ region: 'us-central1', maxInstances: 10 })

const db = () => getFirestore()

export const ensurePlayer = onCall(async (request) => {
  const auth = request.auth
  if (!auth) throw new HttpsError('unauthenticated', 'Sign in first.')
  await ensurePlayerDoc({ db: db() }, auth.uid, auth.token.firebase?.sign_in_provider === 'anonymous')
  return { ok: true }
})
