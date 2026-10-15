'use client'

import { useSyncExternalStore } from 'react'

/**
 * Each operator's dashboard: which portlets show, in what order, and how
 * they have arranged the tasks assigned to them.
 *
 * The same store shape as the columns store — one module, localStorage,
 * never able to break a page. Only ids are stored, never portlet content, so
 * a portlet added to the catalogue later shows up in "Add a portlet", and one
 * removed from the catalogue simply drops out. In the product this is a
 * per-user setting.
 *
 * Whether the board is being configured is not stored: it is a mode of this
 * page view, shared between the header button and the board.
 */

type Stored = {
  /** The portlets showing, in order. Null until the operator changes it. */
  order: string[] | null
  /** Task order per user id, since "assigned to me" changes with View as. */
  tasks: Record<string, string[]>
}

const KEY = 'tu-dashboard'
const EMPTY: Stored = { order: null, tasks: {} }

let current: Stored = EMPTY
let configuring = false
let hydrated = false
const listeners = new Set<() => void>()

function read(): Stored {
  try {
    const parsed = JSON.parse(window.localStorage.getItem(KEY) ?? 'null')
    return parsed && typeof parsed === 'object' && !Array.isArray(parsed) ? { ...EMPTY, ...parsed } : EMPTY
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

function notify() {
  for (const l of listeners) l()
}

function write(next: Stored) {
  current = next
  try {
    window.localStorage.setItem(KEY, JSON.stringify(next))
  } catch {
    /* Storage denied. The layout still applies for this session. */
  }
  notify()
}

/** The stored portlet order, or null when the operator has never changed it. */
export function usePortletOrder(): string[] | null {
  return useSyncExternalStore(
    subscribe,
    () => current.order,
    () => null,
  )
}

/** Null resets to the shipped layout. */
export function setPortletOrder(order: string[] | null) {
  write({ ...current, order })
}

/** The stored task order for a user, or null when they have never moved one. */
export function useTaskOrder(userId: string): string[] | null {
  return useSyncExternalStore(
    subscribe,
    () => current.tasks[userId] ?? null,
    () => null,
  )
}

export function setTaskOrder(userId: string, order: string[] | null) {
  const tasks = { ...current.tasks }
  if (order) tasks[userId] = order
  else delete tasks[userId]
  write({ ...current, tasks })
}

export function useConfiguring(): boolean {
  return useSyncExternalStore(
    subscribe,
    () => configuring,
    () => false,
  )
}

export function setConfiguring(on: boolean) {
  configuring = on
  notify()
}

/** Move `id` to position `to` in `list`, clamped to its ends. */
export function moveTo<T>(list: T[], item: T, to: number): T[] {
  const from = list.indexOf(item)
  if (from < 0) return list
  const next = list.filter((x) => x !== item)
  next.splice(Math.max(0, Math.min(to, next.length)), 0, item)
  return next
}
