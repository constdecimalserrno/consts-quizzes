import { FieldValue, type Firestore } from 'firebase-admin/firestore'

/** What an X account contributes to a Player's page. */
export type XProfile = {
  username: string
  name: string | null
  photoUrl: string | null
  bannerUrl: string | null
}

const X_PROVIDER = 'twitter.com'

/**
 * Records the X details of a Player who has actually linked X.
 *
 * The username and banner only exist in the credential the client receives at
 * link time, so the client has to send them. What it cannot do is claim them
 * without having linked: `providerData` is read here, from the Admin SDK, and
 * a Player with no X provider attached is refused. That is the difference
 * between decoration and a claim of identity.
 */
export async function saveXProfile(
  db: Firestore,
  providerData: { providerId: string; displayName?: string | null; photoURL?: string | null }[],
  uid: string,
  claimed: { username?: unknown; bannerUrl?: unknown },
): Promise<XProfile | null> {
  const linked = providerData.find((p) => p.providerId === X_PROVIDER)
  if (!linked) return null

  const username =
    typeof claimed.username === 'string' && /^[A-Za-z0-9_]{1,15}$/.test(claimed.username)
      ? claimed.username.toLowerCase()
      : null
  if (!username) return null

  const bannerUrl =
    typeof claimed.bannerUrl === 'string' &&
    claimed.bannerUrl.startsWith('https://')
      ? claimed.bannerUrl
      : null

  const profile: XProfile = {
    username,
    name: linked.displayName ?? null,
    // Firebase hands over X's 48px thumbnail; the page wants a face.
    photoUrl: linked.photoURL?.replace(/_normal(\.\w+)$/, '_400x400$1') ?? null,
    bannerUrl,
  }

  await db.doc(`players/${uid}`).set(
    { x: { ...profile, syncedAt: FieldValue.serverTimestamp() } },
    { merge: true },
  )
  return profile
}

/**
 * Wipes a Player's X details.
 *
 * Disconnecting has to actually remove the data, not just the login. Somebody
 * who unlinks their account and still sees their own face on the page has not
 * been disconnected from anything.
 */
export async function clearXProfile(
  db: Firestore,
  uid: string,
): Promise<void> {
  await db.doc(`players/${uid}`).set(
    { x: FieldValue.delete() },
    { merge: true },
  )
}
