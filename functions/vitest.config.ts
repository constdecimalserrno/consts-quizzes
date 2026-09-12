import { defineConfig } from 'vitest/config'

// The emulator is slow to start and slower to seed; a per-test timeout that
// assumes a local in-memory database will flake on CI and nowhere else.
export default defineConfig({
  test: {
    include: ['test/**/*.test.ts'],
    testTimeout: 20_000,
    hookTimeout: 30_000,
    fileParallelism: false,
  },
})
