// Production smoke test: joins the live Round as a real anonymous Player and
// answers one Slot correctly, then waits for the Tick to score it.
//
// Reads the correct Choice with admin credentials, which no player can do —
// that is the point: it proves the payout path without guessing.
//
// Run: node tools/smoke.mjs <webApiKey>
import { initializeApp as admInit, applicationDefault } from 'firebase-admin/app'
import { getFirestore as admDb } from 'firebase-admin/firestore'
import { initializeApp } from 'firebase/app'
import { getAuth, signInAnonymously } from 'firebase/auth'
import { doc, getDoc, getFirestore, serverTimestamp, setDoc } from 'firebase/firestore'

admInit({ credential: applicationDefault(), projectId: 'consts-quizzes' })
const adm = admDb()
const app = initializeApp({ apiKey: process.argv[2], projectId: 'consts-quizzes', authDomain: 'consts-quizzes.firebaseapp.com' })
const { user } = await signInAnonymously(getAuth(app))
const db = getFirestore(app)
await fetch('https://us-central1-consts-quizzes.cloudfunctions.net/ensurePlayer',
  { method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${await user.getIdToken()}` }, body: '{"data":{}}' })

let r, q
for (let i = 0; i < 60; i++) {
  r = (await getDoc(doc(db, 'rounds/current'))).data(); q = r?.question
  const now = Date.now()
  if (q && now >= q.opensAt && now < q.closesAt - 2500) break
  await new Promise(x => setTimeout(x, 1200))
}
// Operator privilege: read the answer the audience cannot see, to prove payout.
const correct = (await adm.doc(`questions/${r.slots[q.slot].questionId}`).get()).data().correct
console.log(`slot ${q.slot}: ${q.prompt.slice(0,50)} -> answering "${correct}" (elapsed ${((Date.now()-q.opensAt)/1000).toFixed(1)}s of ${((q.closesAt-q.opensAt)/1000)}s)`)
await setDoc(doc(db, `rounds/${r.id}/answers/${q.slot}_${user.uid}`),
  { uid: user.uid, slot: q.slot, choice: correct, answeredAt: serverTimestamp() })

for (let i = 0; i < 30; i++) {
  const a = (await adm.doc(`rounds/${r.id}/answers/${q.slot}_${user.uid}`).get()).data()
  if (a && 'correct' in a) {
    const e = (await adm.doc(`rounds/${r.id}/entries/${user.uid}`).get()).data()
    console.log('answer:', JSON.stringify({ correct: a.correct, points: a.points }))
    console.log('entry :', JSON.stringify({ score: e.score, correct: e.correct, answered: e.answered }))
    process.exit(0)
  }
  await new Promise(x => setTimeout(x, 3000))
}
console.log('not scored'); process.exit(1)
