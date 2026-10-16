'use client'

import { useSyncExternalStore } from 'react'
import { activeUserName } from '@/lib/session'
import type { Customer, Invoice, Meter } from '@/schemas/models'

/**
 * Edits made to accounts, meters and draft bills, until the API exists.
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
  'billing_address_line1',
  'billing_address_line2',
  'billing_city',
  'billing_state',
  'billing_zip',
  'preferred_contact_method',
  'preferred_language',
  'billing_delivery_method',
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

/**
 * What an operator may change on a meter. The meter number is its identity,
 * status moves only through an inactivation or reactivation, and the estimate
 * count is database-maintained.
 */
export const METER_EDITABLE = [
  'serial_number',
  'manufacturer',
  'model',
  'size',
  'read_type',
  'ami_endpoint_id',
  'multiplier',
  'gas_btu_factor',
  'rollover_point',
  'route_id',
  'route_sequence',
] as const satisfies readonly (keyof Meter)[]

/**
 * The factors that turn dials into a bill. Billing honours the value effective
 * on the read date, so the edit form refuses to save them without a reason
 * and the date they take effect.
 */
export const METER_REASONED = ['multiplier', 'gas_btu_factor', 'rollover_point'] as const satisfies readonly (typeof METER_EDITABLE)[number][]

/** What may change on a bill that has never been issued. Amounts and lines come from the run. */
export const INVOICE_EDITABLE = ['invoice_date', 'due_date', 'hold_reason'] as const satisfies readonly (keyof Invoice)[]

/** `status` is never in the edit form: it moves only through an inactivation or reactivation, with a reason. */
export type CustomerEdit = Partial<Pick<Customer, (typeof CUSTOMER_EDITABLE)[number] | 'status'>>
export type MeterEdit = Partial<Pick<Meter, (typeof METER_EDITABLE)[number] | 'status'>>
export type InvoiceEdit = Partial<Pick<Invoice, (typeof INVOICE_EDITABLE)[number]>>

export type EditEntry = {
  at: string
  by: string
  entity: 'customer' | 'invoice' | 'meter'
  id: string
  changes: Record<string, { from: unknown; to: unknown }>
  reason: string | null
  /** The service date a status change takes effect, which need not be the day it was recorded. */
  effective?: string
}

/**
 * A meter exchange at a premise: the old meter's removal read and the new
 * meter's set read, on one date. The schema writes this as a `meter_change_out`
 * service order, a `removal` and an `installation` reading, a closed and an
 * opened `meter_deployments` row, and `replaces_meter_id` on the new meter.
 */
export type Replacement = {
  at: string
  by: string
  oldMeterId: string
  newMeterId: string
  locationId: string
  customerId: string | null
  swapDate: string
  removalRead: string
  /** The old register wrapped past its rollover point since the last read. */
  rolledOver: boolean
  installRead: string
  reason: string
  technician: string
  sealNumber: string | null
  serviceOrder: string | null
  /** What happened to the radio: moved across, a new one fitted, or none (manual read). */
  endpoint: 'move' | 'new' | 'none'
  rateScheduleCode: string | null
}

export type Edits = {
  customers: Record<string, CustomerEdit>
  invoices: Record<string, InvoiceEdit>
  meters: Record<string, MeterEdit>
  replacements: Replacement[]
  log: EditEntry[]
}

const KEY = 'tu-edits'
export const EMPTY_EDITS: Edits = { customers: {}, invoices: {}, meters: {}, replacements: [], log: [] }

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

/** The meter as it stands after any edits or status change made in this browser. */
export function useMeter(m: Meter): Meter {
  const edit = useEdits().meters[m.id]
  return edit ? { ...m, ...edit } : m
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
    /* A field a record never had reads as null, so saving it unchanged logs nothing. */
    if ((was ?? null) !== (v ?? null)) changes[k] = { from: was ?? null, to: v }
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
    log: [...current.log, { at: new Date().toISOString(), by: activeUserName(), entity: 'customer', id: base.id, changes, reason }],
  })
  return true
}

/**
 * Save a meter edit. `base` is the fixture row; `next` is the full edited set.
 * A factor change carries its reason and the date it takes effect. Returns
 * false when nothing changed.
 */
export function saveMeter(base: Meter, next: MeterEdit, reason: string | null, effective: string | null): boolean {
  hydrate()
  const before = { ...base, ...current.meters[base.id] }
  const changes = diff(before, next)
  if (!Object.keys(changes).length) return false
  write({
    ...current,
    meters: { ...current.meters, [base.id]: { ...current.meters[base.id], ...next } },
    log: [
      ...current.log,
      {
        at: new Date().toISOString(),
        by: activeUserName(),
        entity: 'meter',
        id: base.id,
        changes,
        reason,
        ...(effective ? { effective } : {}),
      },
    ],
  })
  return true
}

/**
 * Exchange the meter at a premise. `old` and `incoming` are the meters as they
 * stand now. The old meter is removed and keeps its history; the incoming one
 * takes its place in the same status, on the same route, with the radio moved,
 * replaced or dropped. Both records log the exchange with its reason and date.
 */
export function replaceMeter(
  old: Meter,
  incoming: Meter,
  r: Omit<Replacement, 'at' | 'by' | 'oldMeterId' | 'newMeterId'>,
  newEndpointId: string | null,
): void {
  hydrate()
  if (old.status !== 'active' && old.status !== 'inactive') throw new Error('Only a meter set at a service address can be replaced.')
  if (incoming.status !== 'in_stock') throw new Error('The incoming meter must be in stock.')
  const at = new Date().toISOString()
  const by = activeUserName()
  const endpoint = r.endpoint === 'move' ? old.ami_endpoint_id : r.endpoint === 'new' ? newEndpointId : null
  const oldNext: MeterEdit = {
    status: 'removed',
    route_id: null,
    route_sequence: null,
    ...(r.endpoint === 'move' ? { ami_endpoint_id: null } : {}),
  }
  const newNext: MeterEdit = {
    status: old.status,
    route_id: old.route_id,
    route_sequence: old.route_sequence,
    ami_endpoint_id: endpoint,
    read_type: endpoint === null ? 'manual' : old.read_type === 'manual' ? 'amr' : old.read_type,
    gas_btu_factor: incoming.gas_btu_factor ?? old.gas_btu_factor,
  }
  write({
    ...current,
    meters: {
      ...current.meters,
      [old.id]: { ...current.meters[old.id], ...oldNext },
      [incoming.id]: { ...current.meters[incoming.id], ...newNext },
    },
    replacements: [...(current.replacements ?? []), { ...r, at, by, oldMeterId: old.id, newMeterId: incoming.id }],
    log: [
      ...current.log,
      {
        at,
        by,
        entity: 'meter',
        id: old.id,
        changes: diff(old, oldNext),
        reason: `Replaced by ${incoming.meter_number} — ${r.reason}`,
        effective: r.swapDate,
      },
      {
        at,
        by,
        entity: 'meter',
        id: incoming.id,
        changes: diff(incoming, newNext),
        reason: `Replaces ${old.meter_number} — ${r.reason}`,
        effective: r.swapDate,
      },
    ],
  })
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
    log: [...current.log, { at: new Date().toISOString(), by: activeUserName(), entity: 'invoice', id: base.id, changes, reason: null }],
  })
  return true
}

/**
 * Inactivate or reactivate an account or a meter.
 *
 * A status change is a state event, not an edit: it always carries a reason
 * and the service date it takes effect, and never rides along with other
 * field changes. Returns false when the record is already in that status.
 */
export function changeStatus(
  entity: 'customer' | 'meter',
  base: Customer | Meter,
  status: string,
  reason: string,
  effective: string,
): boolean {
  hydrate()
  const store: Record<string, { status?: string }> = entity === 'customer' ? current.customers : current.meters
  const was = store[base.id]?.status ?? base.status
  if (was === status) return false
  const next = { ...store, [base.id]: { ...store[base.id], status } }
  write({
    ...current,
    ...(entity === 'customer'
      ? { customers: next as Edits['customers'] }
      : { meters: next as Edits['meters'] }),
    log: [
      ...current.log,
      {
        at: new Date().toISOString(),
        by: activeUserName(),
        entity,
        id: base.id,
        changes: { status: { from: was, to: status } },
        reason,
        effective,
      },
    ],
  })
  return true
}

/** The newest status change on a record, for the banner that explains it. */
export function useLastStatusChange(entity: 'customer' | 'meter', id: string): EditEntry | null {
  const log = useEdits().log
  for (let i = log.length - 1; i >= 0; i--) {
    const e = log[i]
    if (e.entity === entity && e.id === id && 'status' in e.changes) return e
  }
  return null
}
