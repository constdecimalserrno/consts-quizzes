// Operator script: fills the Bank from the live sources.
//
// Not a deployed function. Ingestion is occasional, runs for minutes, and
// wants a human watching the report — none of which a Cloud Function is good
// at. Run it with `node tools/ingest.mjs [pagesPerSource]`.
import { initializeApp, applicationDefault } from 'firebase-admin/app'
import { getFirestore } from 'firebase-admin/firestore'

import { bankStats, ingest } from '../lib/ingest.js'

const pages = Number(process.argv[2] ?? 20)

initializeApp({ credential: applicationDefault(), projectId: 'consts-quizzes' })
const db = getFirestore()

const deps = {
  db,
  fetch: async (url) => {
    const res = await fetch(url, { headers: { 'user-agent': 'consts-quizzes' } })
    if (!res.ok) throw new Error(`${res.status} ${url}`)
    return res.text()
  },
  sleep: (ms) => new Promise((r) => setTimeout(r, ms)),
}

console.log(`ingesting up to ${pages} pages per source...`)
console.log(await ingest(deps, pages))
const stats = await bankStats(db)
console.log(`bank: ${stats.total} questions`)
console.log('by difficulty:', stats.byDifficulty)
console.log('themes:', Object.keys(stats.byTheme).length)
for (const [t, n] of Object.entries(stats.byTheme).sort((a, b) => b[1] - a[1])) {
  console.log(`  ${String(n).padStart(5)}  ${t}`)
}
process.exit(0)
