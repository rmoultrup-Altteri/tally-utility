'use client'

import { useSyncExternalStore } from 'react'
import { activeUserName } from '@/lib/session'
import { closeFor, overlapProblem, type RateAssignment } from '@/lib/rate-assignments'
import { seedRateAssignments } from '@/fixtures/rate-assignments'

/**
 * Rate schedule assignments added in this browser, until the API exists.
 *
 * The same shape as the edits store: one module every screen subscribes to,
 * persisted to localStorage, never able to break a page if storage is
 * unavailable. Fixture rows are never rewritten. What this browser adds is
 * kept apart: the new rows, and the end date each close wrote on an earlier
 * row, which is the only thing a close ever sets.
 */

type Added = {
  rows: RateAssignment[]
  /** Row id → the end date its close wrote. Set once; never changed after. */
  closed: Record<string, string>
}

const KEY = 'tu-rate-assignments'
const EMPTY: Added = { rows: [], closed: {} }

let current: Added = EMPTY
let hydrated = false
const listeners = new Set<() => void>()

function read(): Added {
  try {
    const parsed = JSON.parse(window.localStorage.getItem(KEY) ?? 'null')
    return parsed && typeof parsed === 'object' && Array.isArray(parsed.rows) ? { ...EMPTY, ...parsed } : EMPTY
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

function write(next: Added) {
  current = next
  try {
    window.localStorage.setItem(KEY, JSON.stringify(current))
  } catch {
    /* Storage denied. The row still shows for this session. */
  }
  for (const l of listeners) l()
}

function rowsFor(state: Added, customerId: string): RateAssignment[] {
  return [...seedRateAssignments, ...state.rows]
    .filter((r) => r.customer_id === customerId)
    .map((r) => (state.closed[r.id] ? { ...r, end_date: state.closed[r.id] } : r))
}

const useAdded = () =>
  useSyncExternalStore(
    subscribe,
    () => current,
    () => EMPTY,
  )

/** Every assignment on an account, fixture rows and this browser's together, with closes applied. */
export function useRateAssignments(customerId: string): RateAssignment[] {
  return rowsFor(useAdded(), customerId)
}

/**
 * Add a row, closing the standing row the day before it starts. A pending
 * row closes nothing until it is approved.
 *
 * Returns the reason it can't be added when the new row would overlap one
 * already on the account, and writes nothing in that case.
 */
export function addRateAssignment(
  customerId: string,
  row: Pick<RateAssignment, 'schedule_code' | 'start_date' | 'reason' | 'pending' | 'source_exception_id'>,
): string | null {
  hydrate()
  const existing = rowsFor(current, customerId)
  const problem = overlapProblem(existing, row.start_date)
  if (problem) return problem
  const close = row.pending ? null : closeFor(existing, row.start_date)
  write({
    rows: [
      ...current.rows,
      {
        ...row,
        id: `ra-${customerId.slice(4)}-b${current.rows.length + 1}`,
        customer_id: customerId,
        end_date: null,
        recorded_at: new Date().toISOString(),
        recorded_by: activeUserName(),
      },
    ],
    closed: close ? { ...current.closed, [close.id]: close.end_date } : current.closed,
  })
  return null
}
