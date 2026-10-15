'use client'

import { useSyncExternalStore } from 'react'
import { activeUserName } from '@/lib/session'
import { deceasedState, type DeceasedState, type DeceasedStep } from '@/lib/deceased'
import { seedDeceasedSteps } from '@/fixtures/deceased'
import { asOf } from '@/fixtures/tenant'

/**
 * Deceased-account steps recorded in this browser, until the API exists.
 *
 * The same shape as the edits store: one module every screen subscribes to,
 * persisted to localStorage, never able to break a page if storage is
 * unavailable. Steps are appended, never changed; the fixture steps come
 * first and this browser's follow.
 */

const KEY = 'tu-deceased'
const EMPTY: DeceasedStep[] = []

let current: DeceasedStep[] = EMPTY
let hydrated = false
const listeners = new Set<() => void>()

function read(): DeceasedStep[] {
  try {
    const parsed = JSON.parse(window.localStorage.getItem(KEY) ?? 'null')
    return Array.isArray(parsed) ? (parsed as DeceasedStep[]) : EMPTY
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

const useAdded = () =>
  useSyncExternalStore(
    subscribe,
    () => current,
    () => EMPTY,
  )

/** The account's deceased state, fixture and this browser's steps together. Null when no death is recorded. */
export function useDeceased(customerId: string): DeceasedState | null {
  return deceasedState(customerId, [...seedDeceasedSteps, ...useAdded()])
}

type StepInput = DeceasedStep extends infer S ? (S extends DeceasedStep ? Omit<S, 'id' | 'on' | 'at' | 'by'> : never) : never

/**
 * Append a step, stamped with who and when. `on` is the working day the
 * prototype is set on, so a step taken here restarts the review clock from
 * the same "today" every other screen uses.
 */
export function recordDeceasedStep(step: StepInput) {
  hydrate()
  const next = {
    ...step,
    id: `dec-${step.customer_id.slice(4)}-b${current.length + 1}`,
    on: asOf.validAt,
    at: new Date().toISOString(),
    by: activeUserName(),
  } as DeceasedStep
  current = [...current, next]
  try {
    window.localStorage.setItem(KEY, JSON.stringify(current))
  } catch {
    /* Storage denied. The step still shows for this session. */
  }
  for (const l of listeners) l()
}
