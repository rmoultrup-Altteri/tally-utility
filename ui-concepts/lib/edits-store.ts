'use client'

import { useSyncExternalStore } from 'react'
import { currentUser } from '@/fixtures/tenant'
import type { Customer, Invoice } from '@/schemas/models'

/**
 * Edits made to accounts and draft bills, until the API exists.
 *
 * The same shape as the payments and imports stores: one module every screen
 * subscribes to, persisted to localStorage, never able to break a page if
 * storage is unavailable. An edit is an overlay on the fixture row, never a
 * rewrite of it, and every save appends to a log with who, when, what changed
 * and — for the fields that need one — why.
 */

/** What an operator may change on an account. Number, status and money move by other routes. */
export const CUSTOMER_EDITABLE = [
  'first_name',
  'last_name',
  'company_name',
  'email',
  'phone',
  'customer_type',
  'is_tax_exempt',
  'billing_hold',
  'billing_hold_reason',
  'do_not_disconnect',
  'disconnect_protection_type',
  'disconnect_protection_expiry',
] as const satisfies readonly (keyof Customer)[]

/**
 * Fields the schema sets through `customer_state_events`, which records a
 * reason with each change. The edit form refuses to save them without one.
 */
export const CUSTOMER_REASONED = [
  'is_tax_exempt',
  'billing_hold',
  'billing_hold_reason',
  'do_not_disconnect',
  'disconnect_protection_type',
  'disconnect_protection_expiry',
] as const satisfies readonly (typeof CUSTOMER_EDITABLE)[number][]

/** What may change on a bill that has never been issued. Amounts and lines come from the run. */
export const INVOICE_EDITABLE = ['invoice_date', 'due_date', 'hold_reason'] as const satisfies readonly (keyof Invoice)[]

export type CustomerEdit = Partial<Pick<Customer, (typeof CUSTOMER_EDITABLE)[number]>>
export type InvoiceEdit = Partial<Pick<Invoice, (typeof INVOICE_EDITABLE)[number]>>

export type EditEntry = {
  at: string
  by: string
  entity: 'customer' | 'invoice'
  id: string
  changes: Record<string, { from: unknown; to: unknown }>
  reason: string | null
}

export type Edits = {
  customers: Record<string, CustomerEdit>
  invoices: Record<string, InvoiceEdit>
  log: EditEntry[]
}

const KEY = 'tu-edits'
export const EMPTY_EDITS: Edits = { customers: {}, invoices: {}, log: [] }

let current: Edits = EMPTY_EDITS
let hydrated = false
const listeners = new Set<() => void>()

function read(): Edits {
  try {
    const raw = window.localStorage.getItem(KEY)
    const parsed = raw ? JSON.parse(raw) : null
    return parsed && typeof parsed === 'object' ? { ...EMPTY_EDITS, ...parsed } : EMPTY_EDITS
  } catch {
    return EMPTY_EDITS
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

function write(next: Edits) {
  current = next
  try {
    window.localStorage.setItem(KEY, JSON.stringify(current))
  } catch {
    /* Storage denied. The edit still shows for this session. */
  }
  for (const l of listeners) l()
}

export function useEdits(): Edits {
  return useSyncExternalStore(
    subscribe,
    () => current,
    () => EMPTY_EDITS,
  )
}

export function getEdits(): Edits {
  hydrate()
  return current
}

/** The account as it stands after any edits made in this browser. */
export function useCustomer(c: Customer): Customer {
  const edit = useEdits().customers[c.id]
  return edit ? { ...c, ...edit } : c
}

/** The bill as it stands after any edits made in this browser. */
export function useInvoice(i: Invoice): Invoice {
  const edit = useEdits().invoices[i.id]
  return edit ? { ...i, ...edit } : i
}

/** The newest log entry for a record, for the "edited" note in its header. */
export function useLastEdit(entity: EditEntry['entity'], id: string): EditEntry | null {
  const log = useEdits().log
  for (let i = log.length - 1; i >= 0; i--) if (log[i].entity === entity && log[i].id === id) return log[i]
  return null
}

function diff<T extends object>(before: T, after: Partial<T>): Record<string, { from: unknown; to: unknown }> {
  const changes: Record<string, { from: unknown; to: unknown }> = {}
  for (const [k, v] of Object.entries(after)) {
    const was = (before as Record<string, unknown>)[k]
    if (was !== v) changes[k] = { from: was, to: v }
  }
  return changes
}

/** Save an account edit. `base` is the fixture row; `next` is the full edited set. Returns false when nothing changed. */
export function saveCustomer(base: Customer, next: CustomerEdit, reason: string | null): boolean {
  hydrate()
  const before = { ...base, ...current.customers[base.id] }
  const changes = diff(before, next)
  if (!Object.keys(changes).length) return false
  write({
    ...current,
    customers: { ...current.customers, [base.id]: { ...current.customers[base.id], ...next } },
    log: [...current.log, { at: new Date().toISOString(), by: currentUser.name, entity: 'customer', id: base.id, changes, reason }],
  })
  return true
}

/** Save a draft-bill edit. Refuses an issued bill: its content is frozen. */
export function saveInvoice(base: Invoice, next: InvoiceEdit): boolean {
  if (base.first_issued_at !== null) throw new Error('An issued bill cannot be edited. Void it and rebill instead.')
  hydrate()
  const before = { ...base, ...current.invoices[base.id] }
  const changes = diff(before, next)
  if (!Object.keys(changes).length) return false
  write({
    ...current,
    invoices: { ...current.invoices, [base.id]: { ...current.invoices[base.id], ...next } },
    log: [...current.log, { at: new Date().toISOString(), by: currentUser.name, entity: 'invoice', id: base.id, changes, reason: null }],
  })
  return true
}
