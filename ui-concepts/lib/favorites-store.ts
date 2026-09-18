'use client'

import { useSyncExternalStore } from 'react'
import type { Favorite } from '@/lib/views'
import { seedFavorites } from '@/fixtures/favorites'

/**
 * Favorites state, shared without a provider.
 *
 * The sidebar list and the star on each record list have to agree instantly,
 * and they sit on opposite sides of a server-rendered shell — so rather than
 * making the whole shell a client component to carry a context, both subscribe
 * to this module. `useSyncExternalStore` also gives the correct server
 * snapshot for free, which a `useState` + effect pair does not.
 *
 * Persistence is per-viewer localStorage, which is the right fidelity for a
 * prototype: in the product this is a per-user, tenant-scoped table.
 */

const KEY = 'tu-favorites'

let current: Favorite[] = seedFavorites
let hydrated = false
const listeners = new Set<() => void>()

function read(): Favorite[] {
  try {
    const raw = window.localStorage.getItem(KEY)
    if (!raw) return seedFavorites
    const parsed = JSON.parse(raw)
    return Array.isArray(parsed) ? (parsed as Favorite[]) : seedFavorites
  } catch {
    /* Private browsing, or a shape from an older build. The seed is a valid
       answer to both, and a broken favorites list must never break a page. */
    return seedFavorites
  }
}

function write(next: Favorite[]) {
  current = next
  try {
    window.localStorage.setItem(KEY, JSON.stringify(next))
  } catch {
    /* Storage denied. The change still applies for this session. */
  }
  for (const l of listeners) l()
}

function subscribe(onChange: () => void) {
  if (!hydrated) {
    hydrated = true
    current = read()
  }
  listeners.add(onChange)
  /* Another tab editing the same list should not drift out of sync. */
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

const getSnapshot = () => current
const getServerSnapshot = () => seedFavorites

export function useFavorites(): Favorite[] {
  return useSyncExternalStore(subscribe, getSnapshot, getServerSnapshot)
}

export function addFavorite(fav: Favorite) {
  if (current.some((f) => f.id === fav.id)) return
  write([...current, fav])
}

export function removeFavorite(id: string) {
  write(current.filter((f) => f.id !== id))
}

export function hasFavorite(id: string) {
  return current.some((f) => f.id === id)
}

/** A saved view's id is derived from its filters, so saving twice is a no-op. */
export function viewId(list: string, query: string) {
  return `view:${list}:${query}`
}
