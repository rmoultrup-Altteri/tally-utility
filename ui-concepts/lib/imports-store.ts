'use client'

import { useSyncExternalStore } from 'react'
import { ENTITY_NOUN, EMPTY_IMPORTED, type ImportedData, type ImportProposal } from '@/lib/assistant/protocol'

/**
 * Records imported through the assistant, until the API exists.
 *
 * The same shape as the payments store: one module every surface subscribes
 * to, persisted to localStorage, never able to break a page if storage is
 * unavailable. Nothing here edits a fixture row — imports only ever add.
 */

const KEY = 'tu-imported'

let current: ImportedData = EMPTY_IMPORTED
let hydrated = false
const listeners = new Set<() => void>()

function read(): ImportedData {
  try {
    const raw = window.localStorage.getItem(KEY)
    const parsed = raw ? JSON.parse(raw) : null
    return parsed && typeof parsed === 'object' ? { ...EMPTY_IMPORTED, ...parsed } : EMPTY_IMPORTED
  } catch {
    return EMPTY_IMPORTED
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

function write(next: ImportedData) {
  current = next
  try {
    window.localStorage.setItem(KEY, JSON.stringify(current))
  } catch {
    /* Storage denied. The import still shows for this session. */
  }
  for (const l of listeners) l()
}

export function useImported(): ImportedData {
  return useSyncExternalStore(
    subscribe,
    () => current,
    () => EMPTY_IMPORTED,
  )
}

export function getImported(): ImportedData {
  hydrate()
  return current
}

/**
 * Apply a staged import. Rows whose natural key arrived since the proposal
 * was staged — the same file applied twice, say — are skipped rather than
 * duplicated. Returns how many records were written.
 */
export function applyProposal(p: ImportProposal): number {
  hydrate()
  const r = p.records
  const has = <T,>(rows: T[], key: (t: T) => string) => new Set(rows.map(key))
  const customerNos = has(current.customers, (c) => c.customer_number)
  const locationNos = has(current.locations, (l) => l.location_number)
  const meterNos = has(current.meters, (m) => m.meter_number)
  const rateKeys = has(current.rateItems, (i) => `${i.rate_schedule_code}|${i.item_code}|${i.effective_from}`)

  const customers = r.customers.filter((c) => !customerNos.has(c.customer_number))
  const locations = r.locations.filter((l) => !locationNos.has(l.location_number))
  const meters = r.meters.filter((m) => !meterNos.has(m.meter_number))
  const rateItems = r.rateItems.filter(
    (i) => !rateKeys.has(`${i.rate_schedule_code}|${i.item_code}|${i.effective_from}`),
  )
  const kept = new Set([...customers, ...locations, ...meters].map((x) => x.id))
  const links = r.links.filter(
    (l) => kept.has(l.locationId) || (l.customerId && kept.has(l.customerId)) || (l.meterId && kept.has(l.meterId)),
  )

  const primary =
    p.entity === 'accounts' || p.entity === 'customers'
      ? customers.length
      : p.entity === 'locations'
        ? locations.length
        : p.entity === 'meters'
          ? meters.length
          : rateItems.length
  if (primary === 0) return 0

  write({
    customers: [...current.customers, ...customers],
    locations: [...current.locations, ...locations],
    meters: [...current.meters, ...meters],
    rateItems: [...current.rateItems, ...rateItems],
    links: [...current.links, ...links],
    batches: [
      ...current.batches,
      {
        id: p.id,
        entity: p.entity,
        label: `${primary} ${ENTITY_NOUN[p.entity][primary === 1 ? 0 : 1]}${p.source ? ` from ${p.source}` : ''}`,
        count: primary,
        appliedAt: new Date().toISOString(),
      },
    ],
  })
  return primary
}

/** Forget everything imported in this browser. The fixtures are untouched. */
export function clearImported() {
  hydrate()
  write(EMPTY_IMPORTED)
}
