import type { Firestore } from 'firebase-admin/firestore'

/** Where the live standings are published. One document, read by everyone. */
export const LIVE_BOARD = 'leaderboards/live'

/** How many Players the live board names. */
export const TOP_N = 20

export type Standing = {
  uid: string
  handle: string
  score: number
  correct: number
}

export type LiveBoard = {
  roundId: string
  slot: number
  playing: number
  top: Standing[]
  updatedAt: number
}

/**
 * Publishes the standings for the live Round into a single document.
 *
 * The shape is the whole point. Firestore bills per document read, so a board
 * where every Player listens to every other Player's Entry costs N reads per
 * Player per Slot — N squared in total, which at a few hundred Players is a
 * bill nobody wants and at a few thousand is ruinous. One document that
 * everyone listens to costs N.
 *
 * Only the top are named. "Top twenty and 1,483 playing" is what an audience
 * actually reads; the other 1,463 names are cost without information.
 */
export async function publishLiveBoard(
  db: Firestore,
  roundId: string,
  slot: number,
  now: number,
): Promise<LiveBoard> {
  const entries = await db
    .collection(`rounds/${roundId}/entries`)
    .orderBy('score', 'desc')
    .limit(TOP_N)
    .get()

  // The count is of everyone with an Entry, not just those named above.
  const playing = (
    await db.collection(`rounds/${roundId}/entries`).count().get()
  ).data().count

  const handles = await resolveHandles(
    db,
    entries.docs.map((d) => d.id),
  )

  const board: LiveBoard = {
    roundId,
    slot,
    playing,
    top: entries.docs.map((d) => ({
      uid: d.id,
      handle: handles.get(d.id) ?? 'someone',
      score: (d.data().score as number) ?? 0,
      correct: (d.data().correct as number) ?? 0,
    })),
    updatedAt: now,
  }

  await db.doc(LIVE_BOARD).set(board)
  return board
}

/**
 * Handles for the named Players, in one batched read.
 *
 * A reaped Player's document is gone but their Entry may survive, so a missing
 * Handle is expected rather than exceptional.
 */
async function resolveHandles(
  db: Firestore,
  uids: string[],
): Promise<Map<string, string>> {
  if (uids.length === 0) return new Map()
  const snaps = await db.getAll(...uids.map((u) => db.doc(`players/${u}`)))
  return new Map(
    snaps
      .filter((s) => s.exists)
      .map((s) => [s.id, (s.data()?.handle as string) ?? 'someone']),
  )
}
