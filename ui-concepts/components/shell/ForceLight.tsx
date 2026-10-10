'use client'

import { useLayoutEffect } from 'react'

/**
 * Pins the day palette while a customer-facing preview is on screen, and puts
 * the operator's own choice back on the way out.
 *
 * The palette tokens resolve at the root, so pinning `color-scheme` on an
 * inner element is not enough to repaint a subtree that uses them — the
 * preview has to set the root the same way the theme switch does.
 */
export function ForceLight() {
  useLayoutEffect(() => {
    const root = document.documentElement
    const prior = root.getAttribute('data-theme')
    root.setAttribute('data-theme', 'light')
    return () => {
      if (prior === null) root.removeAttribute('data-theme')
      else root.setAttribute('data-theme', prior)
    }
  }, [])
  return null
}
