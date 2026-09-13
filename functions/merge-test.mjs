// Proves the account-merge path against production: an anonymous Player with
// a career is claimed by a second account, exactly as a Google sign-in
// collision would.
import { initializeApp as admInit, applicationDefault } from 'firebase-admin/app'
import { getFirestore as admDb } from 'firebase-admin/firestore'
import { initializeApp } from 'firebase/app'
import { getAuth, signInAnonymously } from 'firebase/auth'

const P = 'consts-quizzes'
admInit({ credential: applicationDefault(), projectId: P })
const adm = admDb()
const app = initializeApp({ apiKey: process.argv[2], projectId: P, authDomain: `${P}.firebaseapp.com` })

const call = async (fn, token, data = {}) =>
  (await (await fetch(`https://us-central1-${P}.cloudfunctions.net/${fn}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
    body: JSON.stringify({ data }),
  })).json())

// Two separate anonymous accounts, as if one had signed in and hit an
// existing account.
const a = (await signInAnonymously(getAuth(app))).user
const aToken = await a.getIdToken()
await call('ensurePlayer', aToken)
await adm.doc(`players/${a.uid}`).set({
  career: { roundsPlayed: 4, rankedRounds: 4, totalScore: 3200, bestRound: 1000, averageScore: 800 },
}, { merge: true })
console.log('abandoned :', a.uid.slice(0, 8), 'avg 800 over 4 rounds')

await getAuth(app).signOut()
const b = (await signInAnonymously(getAuth(app))).user
const bToken = await b.getIdToken()
await call('ensurePlayer', bToken)
await adm.doc(`players/${b.uid}`).set({
  career: { roundsPlayed: 2, rankedRounds: 2, totalScore: 800, bestRound: 500, averageScore: 400 },
}, { merge: true })
console.log('survivor  :', b.uid.slice(0, 8), 'avg 400 over 2 rounds')

const r1 = await call('claimAnonymousHistory', bToken, { abandonedIdToken: aToken })
console.log('claim     :', JSON.stringify(r1.result ?? r1.error))

const merged = (await adm.doc(`players/${b.uid}`).get()).data().career
console.log('merged    :', JSON.stringify(merged))
console.log('  6 rounds, 4000 points, best 1000, avg 667 ->',
  merged.rankedRounds === 6 && merged.totalScore === 4000 &&
  merged.bestRound === 1000 && merged.averageScore === 667 ? 'CORRECT' : 'WRONG')

const r2 = await call('claimAnonymousHistory', bToken, { abandonedIdToken: aToken })
const again = (await adm.doc(`players/${b.uid}`).get()).data().career
console.log('retry     :', JSON.stringify(r2.result ?? r2.error),
  '| still 4000:', again.totalScore === 4000 ? 'yes' : 'NO — doubled')

const tomb = (await adm.doc(`players/${a.uid}`).get()).data()
console.log('tombstone :', 'mergedInto set:', !!tomb.mergedInto, '| handle kept:', !!tomb.handle)

const stolen = await call('claimAnonymousHistory', aToken, { abandonedIdToken: 'not-a-token' })
console.log('bad token :', JSON.stringify(stolen.error?.status ?? stolen.result))
process.exit(0)
