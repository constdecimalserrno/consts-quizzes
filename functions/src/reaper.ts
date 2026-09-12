import { Timestamp, type Firestore } from 'firebase-admin/firestore'

/**
 * The Reaper: deletes anonymous Players who have stopped coming.
 *
 * Two things it deliberately is not.
 *
 * It is not part of the Tick. It runs daily and the Tick runs every fifteen
 * seconds; folding a daily sweep into the game's clock would put a scan of the
 * whole Player collection on the path that has to open a Slot on time.
 *
 * It is not armed by default. It ships reporting-only and is turned on by
 * writing to `config/app`, so the first live run can be read before anything
 * is deleted. A deletion pass that has never been inspected is how you find
 * out your idle detection was wrong by losing everybody.
 */
export type ReaperMode = 'report' | 'reap'

export type ReaperDeps = {
  db: Firestore
  now: () => number
}

export type ReaperRun = {
  mode: ReaperMode
  scanned: number
  found: number
  deleted: number
  /** Set when a circuit breaker stopped the run. */
  abortedBecause?: string
}

/** Never delete more than this in one run, however many look idle. */
const MAX_DELETIONS = 500
/** Nor more than this share of everyone, which would mean the rule is wrong. */
const MAX_FRACTION = 0.25
/** Below this many Players the fraction is meaningless, so it is not applied. */
const MIN_FOR_FRACTION = 20
const PAGE = 300

/**
 * A Player is idle if they have not been seen within the window.
 *
 * Watching counts, not just answering: `lastSeenAt` is stamped every time a
 * Player is admitted to a Round. Someone who leaves the broadcast on all day
 * and never presses a thing is still here.
 */
export async function reap(
  { db, now }: ReaperDeps,
  mode: ReaperMode,
  reaperDays: number,
): Promise<ReaperRun> {
  const cutoff = Timestamp.fromMillis(now() - reaperDays * 86_400_000)

  const total = (await db.collection('players').count().get()).data().count
  const candidates: string[] = []

  let cursor: FirebaseFirestore.QueryDocumentSnapshot | undefined
  let scanned = 0
  for (;;) {
    let q = db
      .collection('players')
      .where('anonymous', '==', true)
      .where('lastSeenAt', '<', cutoff)
      .orderBy('lastSeenAt')
      .limit(PAGE)
    if (cursor) q = q.startAfter(cursor)

    const page = await q.get()
    if (page.empty) break
    scanned += page.size

    for (const doc of page.docs) {
      // A tombstone is already spent: its history moved to another Player and
      // its Handle is only being held. Deleting it would release the Handle.
      if (doc.data().mergedInto) continue
      candidates.push(doc.id)
    }
    cursor = page.docs[page.docs.length - 1]
    if (page.size < PAGE) break
  }

  const run: ReaperRun = {
    mode,
    scanned,
    found: candidates.length,
    deleted: 0,
  }

  if (candidates.length > MAX_DELETIONS) {
    run.abortedBecause = `${candidates.length} candidates exceeds ${MAX_DELETIONS}`
  } else if (
    total >= MIN_FOR_FRACTION &&
    candidates.length / total > MAX_FRACTION
  ) {
    run.abortedBecause = `${candidates.length} of ${total} players is over ${MAX_FRACTION * 100}%`
  }

  if (mode === 'reap' && !run.abortedBecause) {
    for (const uid of candidates) {
      // The Player goes; the Handle reservation stays. A released Handle turns
      // every old link into somebody else's page.
      await db.recursiveDelete(db.doc(`players/${uid}`))
      run.deleted++
    }
  }

  await db.collection('reaperRuns').add({ ...run, at: Timestamp.now() })
  return run
}
