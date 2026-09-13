import { afterAll, beforeEach, describe, expect, it } from 'vitest'

import { clearXProfile, saveXProfile } from '../src/profiles.js'
import { testDb, wipe } from './harness.js'

const { db, dispose } = testDb()
afterAll(dispose)
beforeEach(() => wipe(db))

const linked = [
  {
    providerId: 'twitter.com',
    displayName: 'Const',
    photoURL: 'https://pbs.twimg.com/profile_images/1/face_normal.jpg',
  },
]

const x = async (uid: string) =>
  (await db.doc(`players/${uid}`).get()).data()?.x

describe('saveXProfile', () => {
  it('records the details of a Player who has linked X', async () => {
    const saved = await saveXProfile(db, linked, 'u1', {
      username: 'Const',
      bannerUrl: 'https://pbs.twimg.com/profile_banners/1/2',
    })

    expect(saved).toMatchObject({
      username: 'const',
      name: 'Const',
      bannerUrl: 'https://pbs.twimg.com/profile_banners/1/2',
    })
    expect(await x('u1')).toMatchObject({ username: 'const' })
  })

  it('asks X for a face rather than a thumbnail', async () => {
    const saved = await saveXProfile(db, linked, 'u1', { username: 'const' })

    expect(saved!.photoUrl).toContain('_400x400')
    expect(saved!.photoUrl).not.toContain('_normal')
  })

  it('refuses a Player who has not linked X', async () => {
    const saved = await saveXProfile(
      db,
      [{ providerId: 'google.com', displayName: 'Someone' }],
      'u1',
      { username: 'someoneelse' },
    )

    expect(saved).toBeNull()
    expect(await x('u1')).toBeUndefined()
  })

  it('refuses a username that is not one', async () => {
    for (const username of ['', 'way-too-long-for-x-handles', 'has spaces', 42]) {
      expect(await saveXProfile(db, linked, 'u1', { username })).toBeNull()
    }
  })

  it('ignores a banner that is not an https URL', async () => {
    const saved = await saveXProfile(db, linked, 'u1', {
      username: 'const',
      bannerUrl: 'javascript:alert(1)',
    })

    expect(saved!.bannerUrl).toBeNull()
  })

  it('lowercases the username so links resolve consistently', async () => {
    const saved = await saveXProfile(db, linked, 'u1', { username: 'CoNsT' })
    expect(saved!.username).toBe('const')
  })
})

describe('clearXProfile', () => {
  it('removes the details, not just the login', async () => {
    await saveXProfile(db, linked, 'u1', {
      username: 'const',
      bannerUrl: 'https://pbs.twimg.com/profile_banners/1/2',
    })
    await clearXProfile(db, 'u1')

    // Somebody who disconnects and still sees their own face has not been
    // disconnected from anything.
    expect(await x('u1')).toBeUndefined()
  })

  it('leaves the rest of the Player alone', async () => {
    await db.doc('players/u1').set({ handle: 'jolly-teal-otter-777' })
    await saveXProfile(db, linked, 'u1', { username: 'const' })
    await clearXProfile(db, 'u1')

    expect((await db.doc('players/u1').get()).data()).toMatchObject({
      handle: 'jolly-teal-otter-777',
    })
  })

  it('does nothing surprising when there was nothing to clear', async () => {
    await db.doc('players/u1').set({ handle: 'jolly-teal-otter-777' })
    await clearXProfile(db, 'u1')

    expect((await db.doc('players/u1').get()).exists).toBe(true)
  })
})
