'use client'

import { useSyncExternalStore } from 'react'
import type { Payment } from '@/schemas/models'

/**
 * Payments taken in this browser, until the API exists.
 *
 * The add-payment page writes here and the payments list reads from here, so
 * a payment taken at the counter shows up in the list straight away. The same
 * shape as the favorites store: one module both pages subscribe to, persisted
 * to localStorage, never able to break a page if storage is unavailable.
 */

const KEY = 'tu-payments-added'
const EMPTY: Payment[] = []

let current: Payment[] = EMPTY
let hydrated = false
const listeners = new Set<() => void>()

function read(): Payment[] {
  try {
    const raw = window.localStorage.getItem(KEY)
    const parsed = raw ? JSON.parse(raw) : []
    return Array.isArray(parsed) ? (parsed as Payment[]) : EMPTY
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

export function useAddedPayments(): Payment[] {
  return useSyncExternalStore(
    subscribe,
    () => current,
    () => EMPTY,
  )
}

export function addPayment(p: Payment) {
  if (!hydrated) {
    hydrated = true
    current = read()
  }
  current = [...current, p]
  try {
    window.localStorage.setItem(KEY, JSON.stringify(current))
  } catch {
    /* Storage denied. The payment still shows for this session. */
  }
  for (const l of listeners) l()
}
