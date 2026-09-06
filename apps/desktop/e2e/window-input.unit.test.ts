import { createRequire } from 'node:module'

import { expect, test } from 'vitest'

const { prepareWindowForInput } = createRequire(import.meta.url)(
  '../../../tests/install/e2e-assets/window-input.cjs',
)

test('awaits the zoom response instead of accepting a truthy Promise', async () => {
  let reads = 0
  let factor = 0.9

  const zoom = {
    setPercent: () => undefined,
    get: async () => {
      reads++

      if (reads > 1) {factor = 1}

      return { percent: factor * 100 }
    },
  }

  const previous = (globalThis as any).hermesDesktop

  ;(globalThis as any).hermesDesktop = { zoom }
  const window = { evaluate: async (fn: any) => fn({ webContents: { getZoomFactor: () => factor } }) }

  const page = {
    evaluate: async (fn: any) => fn(),
    // Playwright 1.58 accepts the predicate's Promise before it resolves.
    waitForFunction: async (fn: any) => { await fn() },
    waitForTimeout: async () => undefined,
  }

  try {
    await prepareWindowForInput({ browserWindow: async () => window }, page)
    expect(reads).toBeGreaterThan(1)
    expect(factor).toBe(1)
  } finally {
    ;(globalThis as any).hermesDesktop = previous
  }
})
