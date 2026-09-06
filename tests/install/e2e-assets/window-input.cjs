// Shared input setup for the install drivers. Only the selected app window
// is changed; helper windows retain their own coordinate system.
async function prepareWindowForInput(app, page) {
  const window = await app.browserWindow(page)
  // Use the same persistent setting as Appearance. A bare setZoomLevel is
  // overwritten by the app's focus/navigation handlers restoring saved zoom.
  const persistent = await page.evaluate(() => {
    const zoom = globalThis.hermesDesktop?.zoom
    if (!zoom?.setPercent || !zoom?.get) return false
    zoom.setPercent(100)
    return true
  })
  if (persistent) {
    await page.waitForFunction(async () => {
      const state = await globalThis.hermesDesktop.zoom.get()
      return state.percent === 100
    }, undefined, { timeout: 15_000 })
  } else {
    // Older sampled releases have no zoom preference bridge.
    await window.evaluate(win => win.webContents.setZoomLevel(0))
  }
  // DPR includes OS display scaling; 100% page zoom is not always DPR 1.
  const factor = await window.evaluate(win => win.webContents.getZoomFactor())
  if (Math.abs(factor - 1) > 0.001) {
    throw new Error(`could not set app window zoom to 100% (factor ${factor})`)
  }
}

module.exports = { prepareWindowForInput }
