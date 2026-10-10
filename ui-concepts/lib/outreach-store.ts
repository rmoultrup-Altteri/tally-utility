'use client'

import { useSyncExternalStore } from 'react'

/**
 * What has been sent from the outreach board, until the API exists.
 *
 * Append-only like every message log should be: a heads-up that went out
 * stays sent, and a second action on the same customer is a second entry.
 * Kept in this browser, and never able to break the page if storage is
 * unavailable.
 */

const KEY = 'tu-outreach'

export type OutreachAction = {
  candidateId: string
  kind: 'sent' | 'scheduled' | 'called' | 'bill_message' | 'skipped'
  channels: ('text' | 'email' | 'phone' | 'bill')[]
  note: string | null
  by: string
  at: string
}

let current: OutreachAction[] = []
let hydrated = false
const listeners = new Set<() => void>()
const EMPTY: OutreachAction[] = []

function read(): OutreachAction[] {
  try {
    const raw = window.localStorage.getItem(KEY)
    const parsed = raw ? JSON.parse(raw) : null
    return Array.isArray(parsed) ? parsed : []
  } catch {
    return []
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

export function useOutreachLog(): OutreachAction[] {
  return useSyncExternalStore(
    subscribe,
    () => current,
    () => EMPTY,
  )
}

export function logOutreach(actions: Omit<OutreachAction, 'at'>[]) {
  if (!hydrated) {
    hydrated = true
    current = read()
  }
  const at = new Date().toISOString()
  current = [...current, ...actions.map((a) => ({ ...a, at }))]
  try {
    window.localStorage.setItem(KEY, JSON.stringify(current))
  } catch {
    /* Storage denied. The board still shows the send for this session. */
  }
  for (const l of listeners) l()
}

/** The latest action per customer — what the board's status column shows. */
export function latestBy(log: OutreachAction[]): Map<string, OutreachAction> {
  const m = new Map<string, OutreachAction>()
  for (const a of log) m.set(a.candidateId, a)
  return m
}
