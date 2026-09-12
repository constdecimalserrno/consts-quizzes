import type { Question } from './questions.js'
import { questionId } from './questions.js'
import { isDifficulty, isTheme, mapTriviaApiTheme } from './themes.js'

/** Fetches a URL and returns the response body. Injected so tests never dial out. */
export type Fetch = (url: string) => Promise<string>

/** Waits between requests. Injected so tests do not actually sleep. */
export type Sleep = (ms: number) => Promise<void>

export type SourceDeps = { fetch: Fetch; sleep: Sleep; now?: () => number }

/** Both APIs ask for a gap between calls, and both mean it. */
const POLITENESS_MS = 5_000
const PAGE_SIZE = 50

const decode = (b64: string): string =>
  Buffer.from(b64, 'base64').toString('utf8')

const build = (
  raw: {
    theme: unknown
    difficulty: unknown
    prompt: unknown
    correct: unknown
    incorrect: unknown
  },
  source: string,
  now: number,
): Question | null => {
  const { theme, difficulty, prompt, correct, incorrect } = raw
  if (!isTheme(theme) || !isDifficulty(difficulty)) return null
  if (typeof prompt !== 'string' || typeof correct !== 'string') return null
  if (!Array.isArray(incorrect)) return null

  const wrong = incorrect.filter((c): c is string => typeof c === 'string')
  // Fewer than one wrong Choice is not a question; more than three would not
  // fit the four-Choice layout the game is built around.
  if (wrong.length < 1 || wrong.length > 3) return null
  if (prompt.trim() === '' || correct.trim() === '') return null

  return {
    id: questionId(prompt),
    theme,
    difficulty,
    prompt: prompt.trim(),
    correct: correct.trim(),
    incorrect: wrong.map((c) => c.trim()),
    source,
    fetchedAt: now,
  }
}

/**
 * OpenTDB, in base64 mode.
 *
 * Plain mode returns HTML entities that have to be unescaped by hand, and gets
 * them wrong often enough to matter; base64 sidesteps the whole question. A
 * session token stops the same Questions coming back page after page, and is
 * re-issued when the API says the token is exhausted.
 */
export async function fetchOpenTdb(
  deps: SourceDeps,
  pages: number,
): Promise<Question[]> {
  const now = deps.now ?? Date.now
  const out: Question[] = []

  const tokenBody = JSON.parse(
    await deps.fetch('https://opentdb.com/api_token.php?command=request'),
  ) as { token?: string }
  let token = tokenBody.token ?? ''

  for (let page = 0; page < pages; page++) {
    if (page > 0) await deps.sleep(POLITENESS_MS)

    const url = `https://opentdb.com/api.php?amount=${PAGE_SIZE}&encode=base64${token ? `&token=${token}` : ''}`
    const body = JSON.parse(await deps.fetch(url)) as {
      response_code: number
      results?: Array<Record<string, unknown>>
    }

    // 3 and 4 both mean "this token is done"; asking again with a fresh one is
    // the documented recovery, and without it the loop silently returns empty.
    if (body.response_code === 3 || body.response_code === 4) {
      const refreshed = JSON.parse(
        await deps.fetch('https://opentdb.com/api_token.php?command=request'),
      ) as { token?: string }
      token = refreshed.token ?? ''
      continue
    }
    if (body.response_code !== 0 || !body.results?.length) break

    for (const r of body.results) {
      const q = build(
        {
          theme: decode(String(r.category)),
          difficulty: decode(String(r.difficulty)),
          prompt: decode(String(r.question)),
          correct: decode(String(r.correct_answer)),
          incorrect: (r.incorrect_answers as string[] | undefined)?.map(decode),
        },
        'opentdb',
        now(),
      )
      if (q) out.push(q)
    }
  }
  return out
}

/** the-trivia-api. Plain JSON, camelCase, and its own category vocabulary. */
export async function fetchTriviaApi(
  deps: SourceDeps,
  pages: number,
): Promise<Question[]> {
  const now = deps.now ?? Date.now
  const out: Question[] = []

  for (let page = 0; page < pages; page++) {
    if (page > 0) await deps.sleep(POLITENESS_MS)

    const body = JSON.parse(
      await deps.fetch(
        `https://the-trivia-api.com/v2/questions?limit=${PAGE_SIZE}`,
      ),
    ) as Array<Record<string, unknown>>
    if (!Array.isArray(body) || body.length === 0) break

    for (const r of body) {
      const theme = mapTriviaApiTheme(String(r.category ?? ''))
      if (!theme) continue // unmappable category: drop rather than widen the taxonomy
      const text = r.question as { text?: string } | string | undefined
      const q = build(
        {
          theme,
          difficulty: r.difficulty,
          prompt: typeof text === 'string' ? text : text?.text,
          correct: r.correctAnswer,
          incorrect: r.incorrectAnswers,
        },
        'trivia-api',
        now(),
      )
      if (q) out.push(q)
    }
  }
  return out
}
