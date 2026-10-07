'use client'

import { useSyncExternalStore } from 'react'
import { currentUser } from '@/fixtures/tenant'
import { USERS, type User } from '@/fixtures/roles'

/**
 * Who is signed in.
 *
 * There is no authentication behind the concepts, so the session is the
 * fixture user — unless the user menu's concept-only "View as" has switched
 * it, which exists so role-gated screens can be seen from both sides without
 * editing fixtures. Kept in sessionStorage: it ends with the tab, like a
 * session would, and never follows anyone to another browser.
 */

const KEY = 'tu-view-as'
const SIGNED_IN = currentUser.id

let current: string = SIGNED_IN
let hydrated = false
const listeners = new Set<() => void>()

function hydrate() {
  if (hydrated) return
  hydrated = true
  try {
    const stored = window.sessionStorage.getItem(KEY)
    if (stored && USERS.some((u) => u.id === stored)) current = stored
  } catch {
    /* Storage denied — stay as the signed-in user. */
  }
}

function subscribe(onChange: () => void) {
  hydrate()
  listeners.add(onChange)
  return () => listeners.delete(onChange)
}

export function useActiveUserId(): string {
  return useSyncExternalStore(
    subscribe,
    () => current,
    () => SIGNED_IN,
  )
}

export function setActiveUser(id: string) {
  current = id
  try {
    if (id === SIGNED_IN) window.sessionStorage.removeItem(KEY)
    else window.sessionStorage.setItem(KEY, id)
  } catch {
    /* Storage denied — the switch still holds until reload. */
  }
  for (const l of listeners) l()
}

export const isViewingAs = (id: string) => id !== SIGNED_IN

export const userById = (id: string): User => USERS.find((u) => u.id === id) ?? USERS.find((u) => u.id === SIGNED_IN)!

/** For audit stamps written from client stores. */
export function activeUserName(): string {
  hydrate()
  return userById(current).name
}
