'use client'

import { useSyncExternalStore } from 'react'
import type { Transfer } from '@/fixtures/transfers'

/**
 * Transfers requested in this browser, until the API exists.
 *
 * The new-transfer form writes here and the Transfers tab reads from here,
 * the same shape as the payments store: one module both pages subscribe to,
 * persisted to localStorage, never able to break a page if storage is
 * unavailable.
 */

const KEY = 'tu-transfers-added'
const EMPTY: Transfer[] = []

let current: Transfer[] = EMPTY
let hydrated = false
const listeners = new Set<() => void>()

function read(): Transfer[] {
  try {
    const raw = window.localStorage.getItem(KEY)
    const parsed = raw ? JSON.parse(raw) : []
    return Array.isArray(parsed) ? (parsed as Transfer[]) : EMPTY
  } catch {
    return EMPTY
  }
}

function hydrate() {
  if (hydrated) return
  hydrated = true
  current = read()
}

function subscribe(onChange: () => void) {
  hydrate()
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

export function useAddedTransfers(): Transfer[] {
  return useSyncExternalStore(
    subscribe,
    () => current,
    () => EMPTY,
  )
}

export function addTransfer(t: Transfer) {
  hydrate()
  current = [...current, t]
  try {
    window.localStorage.setItem(KEY, JSON.stringify(current))
  } catch {
    /* Storage denied. The transfer still shows for this session. */
  }
  for (const l of listeners) l()
}
