import { getFunctions } from 'firebase-admin/functions'
import { initializeApp } from 'firebase-admin/app'
import { getFirestore } from 'firebase-admin/firestore'
import { setGlobalOptions } from 'firebase-functions/v2'
import { HttpsError, onCall } from 'firebase-functions/v2/https'
import { onSchedule } from 'firebase-functions/v2/scheduler'
import { onTaskDispatched } from 'firebase-functions/v2/tasks'

import { ensurePlayer as ensurePlayerDoc } from './players.js'
import { tick } from './tick.js'

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
  const handle = await ensurePlayerDoc(
    { db: db() },
    auth.uid,
    auth.token.firebase?.sign_in_provider === 'anonymous',
  )
  return { handle }
})

/**
 * Asks for the next Tick at a precise instant.
 *
 * Cloud Scheduler cannot fire faster than once a minute and a Slot is about
 * fifteen seconds, so the clock has to be a chain of Cloud Tasks that each
 * enqueue the next.
 */
const schedule = async (at: number): Promise<void> => {
  await getFunctions()
    .taskQueue<{ at: number }>('tickTask')
    .enqueue({ at }, { scheduleTime: new Date(at) })
}

const deps = () => ({ db: db(), now: Date.now, schedule })

export const tickTask = onTaskDispatched(
  { retryConfig: { maxAttempts: 3 }, rateLimits: { maxConcurrentDispatches: 1 } },
  async () => {
    await tick(deps())
  },
)

/**
 * The heartbeat, and the reason a dropped task is survivable.
 *
 * A chain that each link re-forges stays broken once a link is lost, and the
 * game would stop forever with no error anywhere. `tick` is idempotent with
 * respect to time, so calling it once a minute regardless costs nothing when
 * the chain is healthy and restarts it when it is not.
 */
export const tickHeartbeat = onSchedule('every 1 minutes', async () => {
  await tick(deps())
})
