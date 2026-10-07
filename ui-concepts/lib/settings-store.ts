'use client'

import { useSyncExternalStore } from 'react'
import { activeUserName } from '@/lib/session'

/**
 * Tenant settings changed in this browser, until the API exists.
 *
 * The same shape as the edits store: an overlay on the fixture defaults,
 * persisted to localStorage, never able to break a page when storage is
 * unavailable. Tenant configuration is history in the schema
 * (`tenant_configuration_history`, v5.4.1-02) — a value is never overwritten,
 * a new one takes effect from a date with a reason — so every save here
 * appends to the log with who, when, the effective date and why.
 */

export type SettingValue = string | number | boolean | string[] | null | object

export type SettingChange = {
  at: string
  by: string
  key: string
  from: SettingValue
  to: SettingValue
  effectiveFrom: string
  reason: string
}

export type SettingsState = {
  values: Record<string, SettingValue>
  log: SettingChange[]
}

const KEY = 'tu-settings'
export const EMPTY_SETTINGS: SettingsState = { values: {}, log: [] }

let current: SettingsState = EMPTY_SETTINGS
let hydrated = false
const listeners = new Set<() => void>()

function read(): SettingsState {
  try {
    const raw = window.localStorage.getItem(KEY)
    const parsed = raw ? JSON.parse(raw) : null
    return parsed && typeof parsed === 'object' ? { ...EMPTY_SETTINGS, ...parsed } : EMPTY_SETTINGS
  } catch {
    return EMPTY_SETTINGS
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

function write(next: SettingsState) {
  current = next
  try {
    window.localStorage.setItem(KEY, JSON.stringify(current))
  } catch {
    /* Storage denied. The change still shows for this session. */
  }
  for (const l of listeners) l()
}

export function useSettings(): SettingsState {
  return useSyncExternalStore(
    subscribe,
    () => current,
    () => EMPTY_SETTINGS,
  )
}

const same = (a: unknown, b: unknown) => JSON.stringify(a) === JSON.stringify(b)

/**
 * Save a set of changes under one effective date and one reason. `before`
 * holds the values in force (defaults overlaid with earlier saves). Returns
 * the number of keys that actually changed.
 */
export function saveSettings(
  before: Record<string, SettingValue>,
  next: Record<string, SettingValue>,
  effectiveFrom: string,
  reason: string,
): number {
  hydrate()
  const at = new Date().toISOString()
  const entries: SettingChange[] = []
  for (const [key, to] of Object.entries(next)) {
    const from = before[key] ?? null
    if (!same(from, to)) entries.push({ at, by: activeUserName(), key, from, to, effectiveFrom, reason })
  }
  if (!entries.length) return 0
  const values = { ...current.values }
  for (const e of entries) values[e.key] = e.to
  write({ values, log: [...current.log, ...entries] })
  return entries.length
}
