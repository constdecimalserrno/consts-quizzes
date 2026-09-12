/**
 * The Theme taxonomy: a closed set, fixed in code.
 *
 * A Round picks its Theme at random, which is only possible over a set the
 * game knows in full. Category strings arriving from a source are free text —
 * randomizing over those means randomizing over whatever the internet happened
 * to send today, and a Theme that appears once and never again is not a Theme.
 *
 * These are OpenTDB's categories, which is the larger and more stable of the
 * two taxonomies. Other sources are mapped onto it; anything unmappable is
 * dropped rather than quietly widening the set.
 */
export const THEMES = [
  'General Knowledge',
  'Entertainment: Books',
  'Entertainment: Film',
  'Entertainment: Music',
  'Entertainment: Musicals & Theatres',
  'Entertainment: Television',
  'Entertainment: Video Games',
  'Entertainment: Board Games',
  'Science & Nature',
  'Science: Computers',
  'Science: Mathematics',
  'Mythology',
  'Sports',
  'Geography',
  'History',
  'Politics',
  'Art',
  'Celebrities',
  'Animals',
  'Vehicles',
  'Entertainment: Comics',
  'Science: Gadgets',
  'Entertainment: Japanese Anime & Manga',
  'Entertainment: Cartoon & Animations',
] as const

export type Theme = (typeof THEMES)[number]

const THEME_SET: ReadonlySet<string> = new Set(THEMES)

export const isTheme = (v: unknown): v is Theme =>
  typeof v === 'string' && THEME_SET.has(v)

/** the-trivia-api's categories, mapped onto the taxonomy above. */
const TRIVIA_API_THEMES: Readonly<Record<string, Theme>> = {
  music: 'Entertainment: Music',
  sport_and_leisure: 'Sports',
  film_and_tv: 'Entertainment: Film',
  arts_and_literature: 'Art',
  history: 'History',
  society_and_culture: 'General Knowledge',
  science: 'Science & Nature',
  geography: 'Geography',
  food_and_drink: 'General Knowledge',
  general_knowledge: 'General Knowledge',
}

export const mapTriviaApiTheme = (raw: string): Theme | null =>
  TRIVIA_API_THEMES[raw.toLowerCase()] ?? null

export const DIFFICULTIES = ['easy', 'medium', 'hard'] as const
export type Difficulty = (typeof DIFFICULTIES)[number]

export const isDifficulty = (v: unknown): v is Difficulty =>
  v === 'easy' || v === 'medium' || v === 'hard'
