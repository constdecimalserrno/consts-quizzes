import { createHash } from 'node:crypto'

import type { Difficulty, Theme } from './themes.js'

export type Question = {
  /** Stable hash of the normalised prompt; the document id. */
  id: string
  theme: Theme
  difficulty: Difficulty
  prompt: string
  correct: string
  /** One to three of them, so a Question has two to four Choices in all. */
  incorrect: string[]
  source: string
  fetchedAt: number
}

/**
 * Strips a prompt down to what makes it the same question: case, punctuation
 * and runs of whitespace all go. Two sources that word a question identically
 * but punctuate it differently should collide here rather than both land in
 * the Bank.
 */
export const normalisePrompt = (prompt: string): string =>
  prompt
    .toLowerCase()
    .replace(/[^\p{L}\p{N}\s]/gu, '')
    .replace(/\s+/g, ' ')
    .trim()

/**
 * SHA-1 of the normalised prompt, truncated.
 *
 * The Rust implementation this is ported from used `DefaultHasher`, which is
 * SipHash with a Rust-specific seed and not reproducible anywhere else — so ids
 * cannot be carried across, and re-ingesting from scratch is the migration.
 */
export const questionId = (prompt: string): string =>
  createHash('sha1').update(normalisePrompt(prompt)).digest('hex').slice(0, 16)
