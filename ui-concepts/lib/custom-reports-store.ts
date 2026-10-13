'use client'

import { useSyncExternalStore } from 'react'
import { SOURCE_KEYS, type CustomReport } from '@/lib/report-builder'

/**
 * Reports built with "Create your own report", until the API exists.
 *
 * The same shape as the favorites and imports stores: one module the library
 * and the builder both subscribe to, persisted to localStorage, never able to
 * break a page if storage is unavailable. Only the definition is kept — the
 * rows are rebuilt from the records each time the report opens, so a saved
 * report always shows today's numbers.
 */

const KEY = 'tu-custom-reports'
const EMPTY: CustomReport[] = []

let current: CustomReport[] = EMPTY
let hydrated = false
const listeners = new Set<() => void>()

/** A definition from an older build, or hand-edited storage, is dropped rather than trusted. */
const isReport = (r: unknown): r is CustomReport =>
  !!r &&
  typeof r === 'object' &&
  typeof (r as CustomReport).id === 'string' &&
  (SOURCE_KEYS as readonly string[]).includes((r as CustomReport).source) &&
  Array.isArray((r as CustomReport).columns) &&
  Array.isArray((r as CustomReport).filters)

function read(): CustomReport[] {
  try {
    const raw = window.localStorage.getItem(KEY)
    const parsed = raw ? JSON.parse(raw) : []
    return Array.isArray(parsed) ? parsed.filter(isReport) : EMPTY
  } catch {
    return EMPTY
  }
}

function hydrate() {
  if (!hydrated) {
    hydrated = true
    current = read()
  }
}

function subscribe(onChange: () => void) {
  hydrate()
  listeners.add(onChange)
  /* A report saved in another tab should appear in this one's library. */
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

function write(next: CustomReport[]) {
  current = next
  try {
    window.localStorage.setItem(KEY, JSON.stringify(next))
  } catch {
    /* Storage denied. The report still exists for this session. */
  }
  for (const l of listeners) l()
}

export function useCustomReports(): CustomReport[] {
  return useSyncExternalStore(
    subscribe,
    () => current,
    () => EMPTY,
  )
}

const noop = () => () => {}

/**
 * False on the server and during hydration, true after. The store's server
 * snapshot is an empty list, so "no saved report with this id" can only be
 * believed once this is true.
 */
export function useStoreReady(): boolean {
  return useSyncExternalStore(
    noop,
    () => true,
    () => false,
  )
}

/** Save a definition — a new one is appended, an existing id is replaced in place. */
export function saveCustomReport(report: Omit<CustomReport, 'updatedAt'>): CustomReport {
  hydrate()
  const saved: CustomReport = { ...report, updatedAt: new Date().toISOString() }
  const at = current.findIndex((r) => r.id === report.id)
  write(at === -1 ? [...current, saved] : current.map((r, i) => (i === at ? saved : r)))
  return saved
}

export function deleteCustomReport(id: string) {
  hydrate()
  write(current.filter((r) => r.id !== id))
}

/** Short, URL-safe and unique enough for one browser's list. */
export function newReportId(): string {
  return `cr-${Date.now().toString(36)}${Math.random().toString(36).slice(2, 6)}`
}
