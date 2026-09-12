import type { Firestore } from 'firebase-admin/firestore'

import type { Question } from './questions.js'
import { fetchOpenTdb, fetchTriviaApi, type SourceDeps } from './sources.js'

export type IngestDeps = SourceDeps & { db: Firestore }

export type IngestReport = {
  fetched: number
  /** Collisions within this run and against what the Bank already held. */
  duplicates: number
  written: number
}

/** Firestore caps a batch at 500 writes. */
const BATCH_LIMIT = 500
/** `getAll` is happy with more, but chunking keeps the argument list sane. */
const LOOKUP_CHUNK = 300

const chunk = <T>(xs: T[], n: number): T[][] =>
  Array.from({ length: Math.ceil(xs.length / n) }, (_, i) =>
    xs.slice(i * n, i * n + n),
  )

/**
 * Fills the Bank from both sources.
 *
 * Deduplication is structural: the document id is a hash of the normalised
 * prompt, so the same Question from two sources is the same document however
 * many times this runs. Existing ids are looked up before writing rather than
 * blindly overwritten — a read is a fraction of the price of a write, and on a
 * re-run almost everything is already there.
 */
export async function ingest(
  deps: IngestDeps,
  pagesPerSource = 20,
): Promise<IngestReport> {
  const fetched = [
    ...(await fetchOpenTdb(deps, pagesPerSource)),
    ...(await fetchTriviaApi(deps, pagesPerSource)),
  ]

  const unique = new Map<string, Question>()
  for (const q of fetched) if (!unique.has(q.id)) unique.set(q.id, q)

  const candidates = [...unique.values()]
  const known = new Set<string>()
  for (const ids of chunk(
    candidates.map((q) => q.id),
    LOOKUP_CHUNK,
  )) {
    const refs = ids.map((id) => deps.db.doc(`questions/${id}`))
    for (const snap of await deps.db.getAll(...refs)) {
      if (snap.exists) known.add(snap.id)
    }
  }

  const fresh = candidates.filter((q) => !known.has(q.id))
  for (const group of chunk(fresh, BATCH_LIMIT)) {
    const batch = deps.db.batch()
    for (const q of group) {
      const { id: _id, ...rest } = q
      batch.set(deps.db.doc(`questions/${q.id}`), rest)
    }
    await batch.commit()
  }

  return {
    fetched: fetched.length,
    duplicates: fetched.length - fresh.length,
    written: fresh.length,
  }
}

/** Counts the Bank by Theme and by Difficulty, for `ingest`'s operator report. */
export async function bankStats(db: Firestore): Promise<{
  total: number
  byTheme: Record<string, number>
  byDifficulty: Record<string, number>
}> {
  const snap = await db.collection('questions').get()
  const byTheme: Record<string, number> = {}
  const byDifficulty: Record<string, number> = {}
  for (const doc of snap.docs) {
    const d = doc.data()
    byTheme[d.theme] = (byTheme[d.theme] ?? 0) + 1
    byDifficulty[d.difficulty] = (byDifficulty[d.difficulty] ?? 0) + 1
  }
  return { total: snap.size, byTheme, byDifficulty }
}
