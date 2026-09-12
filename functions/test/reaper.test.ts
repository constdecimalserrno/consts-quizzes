import { Timestamp } from 'firebase-admin/firestore'
import { afterAll, beforeEach, describe, expect, it } from 'vitest'

import { reap } from '../src/reaper.js'
import { testDb, wipe } from './harness.js'

const { db, dispose } = testDb()
afterAll(dispose)

const NOW = 1_700_000_000_000
const DAY = 86_400_000
const deps = { db, now: () => NOW }

beforeEach(async () => {
  await wipe(db)
  await db.recursiveDelete(db.collection('reaperRuns'))
})

const player = (
  uid: string,
  daysIdle: number,
  extra: Record<string, unknown> = {},
) =>
  db.doc(`players/${uid}`).set({
    handle: `${uid}-001`,
    anonymous: true,
    lastSeenAt: Timestamp.fromMillis(NOW - daysIdle * DAY),
    ...extra,
  })

const exists = async (uid: string) =>
  (await db.doc(`players/${uid}`).get()).exists

describe('reap', () => {
  it('finds nobody in an empty game', async () => {
    expect(await reap(deps, 'reap', 90)).toMatchObject({ found: 0, deleted: 0 })
  })

  it('leaves a Player who was here yesterday', async () => {
    await player('recent', 1)
    await reap(deps, 'reap', 90)

    expect(await exists('recent')).toBe(true)
  })

  it('takes an anonymous Player past the window', async () => {
    await player('stale', 120)
    const run = await reap(deps, 'reap', 90)

    expect(run).toMatchObject({ found: 1, deleted: 1 })
    expect(await exists('stale')).toBe(false)
  })

  it('never takes a Player who signed in, however long they have been gone',
    async () => {
      await player('member', 900, { anonymous: false })
      const run = await reap(deps, 'reap', 90)

      expect(run.found).toBe(0)
      expect(await exists('member')).toBe(true)
    })

  it('leaves the Handle reserved after taking the Player', async () => {
    await player('stale', 120)
    await db.doc('handles/stale-001').set({ uid: 'stale' })

    await reap(deps, 'reap', 90)

    expect((await db.doc('handles/stale-001').get()).exists).toBe(true)
  })

  it('leaves a tombstone alone, since it is only holding a Handle', async () => {
    await player('merged', 200, { mergedInto: 'someoneElse' })
    const run = await reap(deps, 'reap', 90)

    expect(run.found).toBe(0)
    expect(await exists('merged')).toBe(true)
  })

  it('reports without deleting when it is not armed', async () => {
    await player('stale', 120)
    const run = await reap(deps, 'report', 90)

    expect(run).toMatchObject({ mode: 'report', found: 1, deleted: 0 })
    expect(await exists('stale')).toBe(true)
  })

  it('respects a shorter window from config', async () => {
    await player('monthOld', 40)

    expect(await reap(deps, 'report', 90)).toMatchObject({ found: 0 })
    expect(await reap(deps, 'report', 30)).toMatchObject({ found: 1 })
  })

  it('refuses to delete an implausible share of everybody', async () => {
    // Thirty Players, all idle: a rule that condemns everyone is a broken rule.
    for (let i = 0; i < 30; i++) await player(`p${i}`, 200)
    const run = await reap(deps, 'reap', 90)

    expect(run.deleted).toBe(0)
    expect(run.abortedBecause).toContain('over 25%')
    expect(await exists('p0')).toBe(true)
  })

  it('does not apply the fraction breaker to a tiny game', async () => {
    await player('a', 200)
    await player('b', 1)
    const run = await reap(deps, 'reap', 90)

    expect(run.deleted).toBe(1)
  })

  it('records every run, armed or not', async () => {
    await player('stale', 120)
    await reap(deps, 'report', 90)
    await reap(deps, 'reap', 90)

    const runs = await db.collection('reaperRuns').get()
    expect(runs.size).toBe(2)
    expect(runs.docs.map((d) => d.data().mode).sort()).toEqual(['reap', 'report'])
  })

  it('takes a Player`s sub-collections with them', async () => {
    await player('stale', 120)
    await db.doc('players/stale/private/notes').set({ anything: true })

    await reap(deps, 'reap', 90)

    expect((await db.doc('players/stale/private/notes').get()).exists).toBe(false)
  })
})
