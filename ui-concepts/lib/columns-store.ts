'use client'

import { useSyncExternalStore } from 'react'

/**
 * Each operator's column layout, per list: which columns show and in what
 * order. The same store shape as favorites — one module, localStorage,
 * never able to break a page. In the product this is a per-user setting.
 *
 * Only the layout is stored, never the column definitions, so a column added
 * to a list later appears for everyone, and one removed simply drops out.
 */

export type ColumnLayout = { order: string[]; hidden: string[] }

const KEY = 'tu-columns'
const EMPTY: Record<string, ColumnLayout> = {}

let current: Record<string, ColumnLayout> = EMPTY
let hydrated = false
const listeners = new Set<() => void>()

function read(): Record<string, ColumnLayout> {
  try {
    const parsed = JSON.parse(window.localStorage.getItem(KEY) ?? 'null')
    return parsed && typeof parsed === 'object' && !Array.isArray(parsed) ? parsed : EMPTY
  } catch {
    return EMPTY
  }
}

function subscribe(onChange: () => void) {
  if (!hydrated) {
    hydrated = true
    current = read()
  }
  listeners.add(onChange)
  const onStorage = (e: StorageEvent) => {
    if (e.key !== KEY) return
    current = read()
    onChange()
  }
  window.addEventListener('storage', onStorage)
  return () => {
    listeners.delete(onChange)
    window.removeEventListener('storage', onStorage)
  }
}

function write(next: Record<string, ColumnLayout>) {
  current = next
  try {
    window.localStorage.setItem(KEY, JSON.stringify(next))
  } catch {
    /* Storage denied. The layout still applies for this session. */
  }
  for (const l of listeners) l()
}

/** The stored layout for one list, or null when the operator has never changed it. */
export function useColumnLayout(listId: string): ColumnLayout | null {
  return useSyncExternalStore(
    subscribe,
    () => current[listId] ?? null,
    () => null,
  )
}

export function setColumnLayout(listId: string, layout: ColumnLayout | null) {
  const next = { ...current }
  if (layout) next[listId] = layout
  else delete next[listId]
  write(next)
}
