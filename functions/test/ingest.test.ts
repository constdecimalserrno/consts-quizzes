import { afterAll, beforeEach, describe, expect, it, vi } from 'vitest'

import { bankStats, ingest } from '../src/ingest.js'
import { normalisePrompt, questionId } from '../src/questions.js'
import type { Fetch } from '../src/sources.js'
import { testDb, wipe } from './harness.js'

const { db, dispose } = testDb()

afterAll(dispose)
beforeEach(async () => {
  await wipe(db)
  await db.recursiveDelete(db.collection('questions'))
})

const b64 = (s: string) => Buffer.from(s, 'utf8').toString('base64')

const openTdbItem = (prompt: string, theme = 'History', diff = 'easy') => ({
  type: b64('multiple'),
  difficulty: b64(diff),
  category: b64(theme),
  question: b64(prompt),
  correct_answer: b64('right'),
  incorrect_answers: [b64('a'), b64('b'), b64('c')],
})

/** A `Fetch` that answers from a script rather than the network. */
const stubFetch = (
  openTdb: Array<Record<string, unknown>>,
  triviaApi: Array<Record<string, unknown>> = [],
): Fetch => {
  let openTdbServed = false
  let triviaServed = false
  return async (url: string) => {
    if (url.includes('api_token.php')) return JSON.stringify({ token: 'tok' })
    if (url.includes('opentdb.com/api.php')) {
      if (openTdbServed) return JSON.stringify({ response_code: 1, results: [] })
      openTdbServed = true
      return JSON.stringify({ response_code: 0, results: openTdb })
    }
    if (url.includes('the-trivia-api.com')) {
      if (triviaServed) return JSON.stringify([])
      triviaServed = true
      return JSON.stringify(triviaApi)
    }
    throw new Error(`unexpected url ${url}`)
  }
}

const deps = (fetch: Fetch) => ({ db, fetch, sleep: async () => {}, now: () => 1 })

describe('normalisePrompt', () => {
  it('collapses the differences that do not make a different question', () => {
    expect(normalisePrompt('  What is  the Capital, of France? ')).toBe(
      'what is the capital of france',
    )
  })

  it('gives two spellings of the same prompt the same id', () => {
    expect(questionId('Who wrote "Hamlet"?')).toBe(questionId('who wrote hamlet'))
  })
})

describe('ingest', () => {
  it('writes fetched Questions into the Bank without touching the network', async () => {
    const report = await ingest(deps(stubFetch([openTdbItem('Q one')])), 1)

    expect(report).toMatchObject({ fetched: 1, written: 1, duplicates: 0 })
    const stats = await bankStats(db)
    expect(stats.total).toBe(1)
    expect(stats.byTheme).toEqual({ History: 1 })
  })

  it('decodes base64 payloads rather than storing them raw', async () => {
    await ingest(deps(stubFetch([openTdbItem('What year was it?')])), 1)

    const doc = await db.doc(`questions/${questionId('What year was it?')}`).get()
    expect(doc.data()).toMatchObject({
      prompt: 'What year was it?',
      correct: 'right',
      theme: 'History',
      difficulty: 'easy',
      source: 'opentdb',
    })
  })

  it('does not duplicate on a second run', async () => {
    const items = [openTdbItem('Q one'), openTdbItem('Q two')]
    await ingest(deps(stubFetch(items)), 1)
    const second = await ingest(deps(stubFetch(items)), 1)

    expect(second.written).toBe(0)
    expect(second.duplicates).toBe(2)
    expect((await bankStats(db)).total).toBe(2)
  })

  it('collapses the same prompt arriving from both sources', async () => {
    const fetch = stubFetch(
      [openTdbItem('Shared question')],
      [
        {
          category: 'history',
          difficulty: 'easy',
          question: { text: 'Shared question' },
          correctAnswer: 'right',
          incorrectAnswers: ['a', 'b', 'c'],
        },
      ],
    )
    const report = await ingest(deps(fetch), 1)

    expect(report.fetched).toBe(2)
    expect(report.written).toBe(1)
    expect((await bankStats(db)).total).toBe(1)
  })

  it('drops a Question whose category is outside the taxonomy', async () => {
    const fetch = stubFetch(
      [openTdbItem('Kept', 'History')],
      [
        {
          category: 'basket_weaving',
          difficulty: 'easy',
          question: { text: 'Dropped' },
          correctAnswer: 'right',
          incorrectAnswers: ['a'],
        },
      ],
    )
    await ingest(deps(fetch), 1)

    expect((await bankStats(db)).total).toBe(1)
  })

  it('drops a Question with no wrong Choices or too many', async () => {
    const none = { ...openTdbItem('No choices'), incorrect_answers: [] }
    const many = {
      ...openTdbItem('Too many'),
      incorrect_answers: ['a', 'b', 'c', 'd'].map((s) => b64(s)),
    }
    await ingest(deps(stubFetch([none, many, openTdbItem('Fine')])), 1)

    expect((await bankStats(db)).total).toBe(1)
  })

  it('asks for a fresh token when the old one is exhausted', async () => {
    let tokens = 0
    let served = false
    const fetch: Fetch = async (url) => {
      if (url.includes('api_token.php')) {
        tokens++
        return JSON.stringify({ token: `tok${tokens}` })
      }
      if (!served) {
        served = true
        return JSON.stringify({ response_code: 4, results: [] })
      }
      return JSON.stringify({ response_code: 0, results: [openTdbItem('After reset')] })
    }
    const report = await ingest({ ...deps(fetch), fetch }, 3)

    expect(tokens).toBeGreaterThan(1)
    expect(report.written).toBe(1)
  })

  it('waits between pages so the sources are not hammered', async () => {
    const sleep = vi.fn(async () => {})
    await ingest(
      { db, fetch: stubFetch([openTdbItem('Q')]), sleep, now: () => 1 },
      3,
    )

    expect(sleep).toHaveBeenCalled()
  })
})
