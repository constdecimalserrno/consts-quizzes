import { getFunctions } from 'firebase-admin/functions'
import { initializeApp } from 'firebase-admin/app'
import { getAuth } from 'firebase-admin/auth'
import { FieldValue, getFirestore } from 'firebase-admin/firestore'
import { logger } from 'firebase-functions'
import { setGlobalOptions } from 'firebase-functions/v2'
import { onMessagePublished } from 'firebase-functions/v2/pubsub'
import { HttpsError, onCall, onRequest } from 'firebase-functions/v2/https'
import { onSchedule } from 'firebase-functions/v2/scheduler'
import { onTaskDispatched } from 'firebase-functions/v2/tasks'

import { issueApiKey, publishBotBoard, revokeApiKey } from './bots.js'
import { verdict, type BudgetNotification } from './budget.js'
import { mergePlayers } from './linking.js'
import { isOpen, readConfig } from './config.js'
import { ensurePlayer as ensurePlayerDoc } from './players.js'
import { reap, type ReaperMode } from './reaper.js'
import { LIVE_ROUND } from './round.js'
import { takeSeat } from './seats.js'
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

  // A seat is per Round, so this is also where a returning Player is admitted
  // to whatever Round is running now.
  const [cfg, open, live] = await Promise.all([
    readConfig(db()),
    isOpen(db()),
    db().doc(LIVE_ROUND).get(),
  ])
  const roundId = live.data()?.id as string | undefined
  const seat = roundId
    ? await takeSeat(
        db(),
        roundId,
        auth.uid,
        cfg.maxConcurrentPlayers,
        open,
        Math.max(0, (live.data()?.openSlot as number) ?? 0),
      )
    : { seated: false as const, reason: 'closed' as const, taken: 0 }

  return { handle, seated: seat.seated, reason: seat.seated ? null : seat.reason }
})

/**
 * Claims an abandoned anonymous Player's history for the account the viewer
 * has just signed in as.
 *
 * Only needed when linking failed because the provider already had an account.
 * The ordinary case — an anonymous account with a provider attached — keeps
 * its uid and never calls this.
 *
 * The abandoned uid is proved by a fresh ID token for it, not merely named: a
 * uid alone would let anybody claim any Player's history.
 */
export const claimAnonymousHistory = onCall(async (request) => {
  const auth = request.auth
  if (!auth) throw new HttpsError('unauthenticated', 'Sign in first.')

  const token = request.data?.abandonedIdToken
  if (typeof token !== 'string' || token === '') {
    throw new HttpsError('invalid-argument', 'Needs the previous ID token.')
  }

  let abandonedUid: string
  try {
    abandonedUid = (await getAuth().verifyIdToken(token)).uid
  } catch {
    throw new HttpsError('permission-denied', 'That token is not valid.')
  }

  const result = await mergePlayers(db(), auth.uid, abandonedUid)
  return { merged: result.merged, career: result.career }
})

/**
 * Issues an API key so this Player can play headlessly.
 *
 * Taking a key moves the Player to the Bot board. That is the whole of the
 * split: a category label, chosen by the Player, not a boundary anyone is
 * being kept out of.
 */
export const createApiKey = onCall(async (request) => {
  const auth = request.auth
  if (!auth) throw new HttpsError('unauthenticated', 'Sign in first.')

  const label = typeof request.data?.label === 'string'
    ? request.data.label.slice(0, 60)
    : 'unnamed bot'

  const key = await issueApiKey(db(), auth.uid, label)
  // Said once. Only its hash is kept, so it cannot be shown again.
  return { secret: key.secret, keyId: key.keyId }
})

export const deleteApiKey = onCall(async (request) => {
  const auth = request.auth
  if (!auth) throw new HttpsError('unauthenticated', 'Sign in first.')
  const keyId = request.data?.keyId
  if (typeof keyId !== 'string') {
    throw new HttpsError('invalid-argument', 'Needs a keyId.')
  }
  return { revoked: await revokeApiKey(db(), auth.uid, keyId) }
})

/**
 * Receives Cloud Billing's budget notifications over Pub/Sub.
 *
 * See `budget.ts` for why this is the slow half of the defence.
 */
export const budgetWatch = onMessagePublished('budget-alerts', async (event) => {
  const msg = (event.data.message.json ?? {}) as BudgetNotification
  const call = verdict(msg)
  if (call === 'ok') return

  await db().doc('config/app').set(
    {
      killSwitch: true,
      killedAt: FieldValue.serverTimestamp(),
      killedBecause: `spend ${msg.costAmount} of ${msg.budgetAmount}`,
    },
    { merge: true },
  )
  logger.error('budget threshold crossed', { verdict: call, ...msg })
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

const deps = () => ({
  db: db(),
  now: Date.now,
  schedule,
  onError: (what: string, err: unknown) =>
    logger.error(`intermission job failed: ${what}`, err),
})

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

/**
 * The Reaper, daily and deliberately off the hour so it never lands with a
 * Tick.
 *
 * Armed by data rather than by a deploy: `config/app.reaperMode` must say
 * `reap`, and anything else — including the field being absent — means report
 * only. The first live run should be read before anything is deleted.
 */
export const reaperDaily = onSchedule('17 9 * * *', async () => {
  const cfg = await readConfig(db())
  const snap = await db().doc('config/app').get()
  const mode: ReaperMode =
    snap.data()?.reaperMode === 'reap' ? 'reap' : 'report'

  const run = await reap({ db: db(), now: Date.now }, mode, cfg.reaperDays)
  logger.info('reaper run', run)
})

/**
 * The server's clock, for clients to measure their own offset against.
 *
 * The Slot schedule is absolute server time, so a visitor whose machine is a
 * minute fast would be shown the wrong Question and have their Answers
 * rejected as late — with nothing on screen to explain why. One request per
 * session fixes it; caching is off because a cached clock is not a clock.
 */
export const serverTime = onRequest(
  { cors: true },
  (_request, response) => {
    response.set('Cache-Control', 'no-store')
    response.json({ now: Date.now() })
  },
)
