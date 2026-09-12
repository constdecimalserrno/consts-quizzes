// A bot written only from what llms.txt says, to prove the published
// instructions are enough to play without reading the source.
import { initializeApp } from 'firebase/app'
import { getAuth, signInAnonymously } from 'firebase/auth'
import { doc, getDoc, getFirestore, serverTimestamp, setDoc } from 'firebase/firestore'

const P = 'consts-quizzes'
const app = initializeApp({ apiKey: process.argv[2], projectId: P, authDomain: `${P}.firebaseapp.com` })
const { user } = await signInAnonymously(getAuth(app))
const db = getFirestore(app)
const token = await user.getIdToken()

const ep = await (await fetch(`https://us-central1-${P}.cloudfunctions.net/ensurePlayer`,
  { method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` }, body: '{"data":{}}' })).json()
console.log('handle:', ep.result.handle, '| seated:', ep.result.seated, ep.result.reason ?? '')
if (!ep.result.seated) process.exit(1)

const t0 = Date.now()
const { now } = await (await fetch(`https://us-central1-${P}.cloudfunctions.net/serverTime`)).json()
const offset = now + (Date.now() - t0) / 2 - Date.now()
console.log('clock offset:', Math.round(offset), 'ms')
const serverNow = () => Date.now() + offset

const key = await (await fetch(`https://us-central1-${P}.cloudfunctions.net/createApiKey`,
  { method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
    body: JSON.stringify({ data: { label: 'llms.txt conformance bot' } }) })).json()
console.log('api key issued:', key.result.secret.slice(0, 12) + '...', '-> bot board')

let answered = 0
const seen = new Set()
const deadline = Date.now() + 120_000
while (answered < 3 && Date.now() < deadline) {
  const r = (await getDoc(doc(db, 'rounds/current'))).data()
  const q = r?.question
  const key = q && `${r.id}:${q.slot}`
  if (q && !seen.has(key) && serverNow() >= q.opensAt && serverNow() < q.closesAt - 800) {
    seen.add(key)
    const choice = q.choices[Math.floor(Math.random() * q.choices.length)]
    try {
      await setDoc(doc(db, `rounds/${r.id}/answers/${q.slot}_${user.uid}`),
        { uid: user.uid, slot: q.slot, choice, answeredAt: serverTimestamp() })
      answered++
      console.log(`  slot ${q.slot}: answered "${choice.slice(0, 28)}"`)
    } catch (e) { console.log(`  slot ${q.slot}: refused (${e.code})`) }
  }
  await new Promise((r) => setTimeout(r, 1500))
}

const r = (await getDoc(doc(db, 'rounds/current'))).data()
const entry = (await getDoc(doc(db, `rounds/${r.id}/entries/${user.uid}`))).data()
console.log('entry:', JSON.stringify(entry ?? {}))
process.exit(0)
