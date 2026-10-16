import { meterIdFor } from '@/lib/assistant/protocol'
import type { Cell, Column, ReportRow } from '@/fixtures/reports'
import { invoiceTone, severityTone, type Tone } from '@/components/ui/State'
import { accountTone, meterStatus, sizeLabel } from '@/components/meters/status'
import { label } from '@/lib/vocabulary'
import {
  customerName,
  type Customer,
  type Exception,
  type Invoice,
  type Meter,
  type MeterReading,
  type Payment,
  type ServiceLocation,
} from '@/schemas/models'
import {
  AnomalySeverity,
  AnomalyStatus,
  CustomerStatus,
  InvoiceStatus,
  PaymentStatus,
  ReadingStatus,
} from '@/schemas/enums'

/**
 * The custom report builder's catalogue and query engine.
 *
 * A source is a flat table of the records an operator already sees on other
 * screens — one row per account, bill, payment, meter, read or exception —
 * with its fields labelled the way those screens label them. A custom report
 * stores only its definition (source, columns, filters, grouping, sort);
 * rows are rebuilt every time it opens, so a saved report never goes stale.
 *
 * Row builders take their lookups as arguments rather than importing
 * fixtures, so the server can build the fixture rows and the browser can
 * build rows for records imported or created here with the same code.
 */

/* ---- Sources and fields ----------------------------------------------- */

export const SOURCE_KEYS = ['accounts', 'bills', 'payments', 'meters', 'reads', 'exceptions'] as const
export type SourceKey = (typeof SOURCE_KEYS)[number]

/** A column a source offers. `enum` fields filter by picking from the values present. */
export type Field = Column & { enum?: boolean }

export type SourceDef = {
  key: SourceKey
  label: string
  /** Singular and plural, for the row count line. */
  noun: [string, string]
  description: string
  fields: Field[]
  /** Ticked when the source is first picked. */
  defaults: string[]
}

/** Status words are humanized in the rows, so their tones are keyed the same way. */
const tonesOf = (values: readonly string[], tone: (v: string) => Tone) =>
  Object.fromEntries(values.map((v) => [label(v), tone(v)]))

const PAYMENT_TONES: Record<string, Tone> = {
  Pending: 'pending',
  Posted: 'posted',
  NSF: 'failed',
  Reversed: 'void',
  Refunded: 'superseded',
  Voided: 'void',
}

const READING_TONES: Record<string, Tone> = {
  Active: 'approved',
  Disputed: 'warning',
  'Under review': 'pending',
  Replaced: 'superseded',
  Voided: 'void',
}

const METER_TONES = Object.fromEntries(
  ['active', 'inactive', 'in_stock', 'removed'].map((s) => [meterStatus(s).label, meterStatus(s).tone]),
)

const SEVERITY_TONES = tonesOf(AnomalySeverity.options, (s) => severityTone(s))
const EXCEPTION_STATUS_TONES: Record<string, Tone> = {
  ...tonesOf(AnomalyStatus.options, () => 'warning'),
  Open: 'critical',
  Acknowledged: 'warning',
  Investigating: 'pending',
  Resolved: 'cleared',
  'False positive': 'cleared',
  Deferred: 'snoozed',
  Snoozed: 'snoozed',
}

/* `account` and `meter` keep their keys in every source: ReportTable links those two by number. */
const account: Field = { key: 'account', label: 'Account', kind: 'ident' }
const customer: Field = { key: 'customer', label: 'Customer', kind: 'text' }
const meter: Field = { key: 'meter', label: 'Meter', kind: 'ident' }

export const SOURCES: Record<SourceKey, SourceDef> = {
  accounts: {
    key: 'accounts',
    label: 'Accounts',
    noun: ['account', 'accounts'],
    description: 'One row per account, with the service address and meter it is linked to.',
    fields: [
      account,
      customer,
      { key: 'customer_type', label: 'Type', kind: 'text', enum: true },
      { key: 'status', label: 'Status', kind: 'status', tones: tonesOf(CustomerStatus.options, accountTone) },
      { key: 'balance', label: 'Balance', kind: 'money' },
      { key: 'deposit', label: 'Deposit', kind: 'money' },
      { key: 'created', label: 'Customer since', kind: 'date' },
      { key: 'move_in', label: 'Move-in', kind: 'date' },
      { key: 'email', label: 'Email', kind: 'text' },
      { key: 'phone', label: 'Phone', kind: 'text' },
      { key: 'tax_exempt', label: 'Tax exempt', kind: 'text', enum: true },
      { key: 'billing_hold', label: 'Billing hold', kind: 'text', enum: true },
      { key: 'premise', label: 'Service address no.', kind: 'ident' },
      { key: 'address', label: 'Address', kind: 'text' },
      { key: 'city', label: 'City', kind: 'text', enum: true },
      { key: 'zip', label: 'ZIP', kind: 'text' },
      { key: 'inside_city', label: 'Inside city limits', kind: 'text', enum: true },
      { key: 'cycle', label: 'Billing cycle', kind: 'text', enum: true },
      meter,
      { key: 'meter_status', label: 'Meter status', kind: 'status', tones: METER_TONES },
      { key: 'read_type', label: 'Read type', kind: 'text', enum: true },
    ],
    defaults: ['account', 'customer', 'status', 'address', 'meter', 'balance'],
  },
  bills: {
    key: 'bills',
    label: 'Bills',
    noun: ['bill', 'bills'],
    description: 'Every invoice, the current cycle and the billing history.',
    fields: [
      { key: 'invoice', label: 'Invoice', kind: 'ident' },
      account,
      customer,
      { key: 'period', label: 'Period', kind: 'text', enum: true },
      { key: 'invoice_date', label: 'Bill date', kind: 'date' },
      { key: 'due_date', label: 'Due', kind: 'date' },
      { key: 'type', label: 'Type', kind: 'text', enum: true },
      { key: 'status', label: 'Status', kind: 'status', tones: tonesOf(InvoiceStatus.options, invoiceTone) },
      { key: 'previous_balance', label: 'Previous balance', kind: 'money' },
      { key: 'charges', label: 'Charges', kind: 'money' },
      { key: 'credits', label: 'Credits', kind: 'money' },
      { key: 'taxes', label: 'Taxes', kind: 'money' },
      { key: 'adjustments', label: 'Adjustments', kind: 'money' },
      { key: 'amount_due', label: 'Amount due', kind: 'money' },
      { key: 'amount_paid', label: 'Paid', kind: 'money' },
      { key: 'balance', label: 'Balance', kind: 'money' },
      { key: 'dunning', label: 'Dunning stage', kind: 'text', enum: true },
      { key: 'estimated', label: 'Estimated reads', kind: 'text', enum: true },
      { key: 'hold_reason', label: 'Hold reason', kind: 'text' },
    ],
    defaults: ['invoice', 'account', 'customer', 'period', 'invoice_date', 'status', 'amount_due', 'balance'],
  },
  payments: {
    key: 'payments',
    label: 'Payments',
    noun: ['payment', 'payments'],
    description: 'Payments received, including any recorded in this browser.',
    fields: [
      { key: 'payment', label: 'Payment', kind: 'ident' },
      { key: 'date', label: 'Date', kind: 'date' },
      account,
      customer,
      { key: 'amount', label: 'Amount', kind: 'money' },
      { key: 'method', label: 'Method', kind: 'text', enum: true },
      { key: 'channel', label: 'Channel', kind: 'text', enum: true },
      { key: 'status', label: 'Status', kind: 'status', tones: { ...tonesOf(PaymentStatus.options, () => 'draft'), ...PAYMENT_TONES } },
      { key: 'applied', label: 'Applied', kind: 'money' },
      { key: 'unapplied', label: 'Unapplied', kind: 'money' },
      { key: 'deposit', label: 'Deposit', kind: 'text', enum: true },
      { key: 'reference', label: 'Reference', kind: 'text' },
      { key: 'received_by', label: 'Received by', kind: 'text', enum: true },
    ],
    defaults: ['payment', 'date', 'account', 'customer', 'method', 'status', 'amount'],
  },
  meters: {
    key: 'meters',
    label: 'Meters',
    noun: ['meter', 'meters'],
    description: 'Every meter the utility owns, with the service address and account it serves.',
    fields: [
      meter,
      { key: 'serial', label: 'Serial', kind: 'ident' },
      { key: 'status', label: 'Status', kind: 'status', tones: METER_TONES },
      { key: 'manufacturer', label: 'Manufacturer', kind: 'text', enum: true },
      { key: 'model', label: 'Model', kind: 'text', enum: true },
      { key: 'size', label: 'Size', kind: 'text', enum: true },
      { key: 'read_type', label: 'Read type', kind: 'text', enum: true },
      { key: 'endpoint', label: 'Endpoint', kind: 'ident' },
      { key: 'route', label: 'Route', kind: 'text', enum: true },
      { key: 'multiplier', label: 'Multiplier', kind: 'factor' },
      { key: 'estimates', label: 'Consecutive estimates', kind: 'number' },
      account,
      customer,
      { key: 'address', label: 'Address', kind: 'text' },
      { key: 'city', label: 'City', kind: 'text', enum: true },
      { key: 'last_read', label: 'Last read', kind: 'date' },
      { key: 'next_test', label: 'Next test due', kind: 'date' },
    ],
    defaults: ['meter', 'status', 'read_type', 'account', 'customer', 'address', 'last_read'],
  },
  reads: {
    key: 'reads',
    label: 'Meter reads',
    noun: ['read', 'reads'],
    description: 'The current cycle’s meter reads, as they stand in validation.',
    fields: [
      meter,
      account,
      customer,
      { key: 'reading_date', label: 'Read date', kind: 'date' },
      { key: 'reading_value', label: 'Reading', kind: 'number' },
      { key: 'previous_value', label: 'Previous', kind: 'number' },
      { key: 'consumption', label: 'Consumption', kind: 'number' },
      { key: 'unit', label: 'Unit', kind: 'text', enum: true },
      { key: 'therms', label: 'Therms', kind: 'number' },
      { key: 'days', label: 'Days', kind: 'number' },
      { key: 'method', label: 'Method', kind: 'text', enum: true },
      { key: 'purpose', label: 'Purpose', kind: 'text', enum: true },
      { key: 'estimated', label: 'Estimated', kind: 'text', enum: true },
      { key: 'quality', label: 'Quality', kind: 'text', enum: true },
      { key: 'status', label: 'Status', kind: 'status', tones: { ...tonesOf(ReadingStatus.options, () => 'draft'), ...READING_TONES } },
      { key: 'validation', label: 'Validation', kind: 'text', enum: true },
      { key: 'access', label: 'Access', kind: 'text', enum: true },
    ],
    defaults: ['meter', 'account', 'customer', 'reading_date', 'consumption', 'unit', 'estimated', 'status'],
  },
  exceptions: {
    key: 'exceptions',
    label: 'Exceptions',
    noun: ['exception', 'exceptions'],
    description: 'The pre-mail exception queue, open and closed.',
    fields: [
      { key: 'description', label: 'Description', kind: 'text' },
      { key: 'type', label: 'Type', kind: 'text', enum: true },
      { key: 'severity', label: 'Severity', kind: 'status', tones: SEVERITY_TONES },
      { key: 'status', label: 'Status', kind: 'status', tones: EXCEPTION_STATUS_TONES },
      account,
      customer,
      meter,
      { key: 'detected', label: 'Detected', kind: 'date' },
      { key: 'impact', label: 'Estimated impact', kind: 'money' },
      { key: 'confidence', label: 'Confidence', kind: 'percent' },
      { key: 'recurrence', label: 'Recurrences', kind: 'number' },
      { key: 'detector', label: 'Detector', kind: 'text', enum: true },
      { key: 'assigned_to', label: 'Assigned to', kind: 'text', enum: true },
      { key: 'blocks_delivery', label: 'Blocks delivery', kind: 'text', enum: true },
    ],
    defaults: ['description', 'severity', 'status', 'account', 'customer', 'impact', 'detected'],
  },
}

export const fieldOf = (source: SourceKey, key: string) => SOURCES[source].fields.find((f) => f.key === key)

/* ---- Row builders ----------------------------------------------------- */

/**
 * What a row builder may look up. Hidden `_customer`, `_meter` and `_invoice`
 * keys ride along on each row so the browser can lay edits made here over a
 * server-built row without rebuilding it.
 */
export type Lookups = {
  customerById: Map<string, Customer>
  locationById: Map<string, ServiceLocation>
  meterById: Map<string, Meter>
  links: readonly { customerId: string | null; locationId: string; meterId: string | null }[]
  /** Latest read date by meter id. */
  lastRead?: Map<string, string>
  /** Next meter-shop test date by meter id. */
  nextTest?: Map<string, string>
}

const yesNo = (b: boolean) => (b ? 'Yes' : 'No')
const day = (iso: string | null | undefined) => (iso ? iso.slice(0, 10) : null)

export function accountRows(customers: Customer[], x: Lookups): ReportRow[] {
  return customers.map((c) => {
    const link = x.links.find((l) => l.customerId === c.id)
    const loc = link ? x.locationById.get(link.locationId) : undefined
    const meterId = meterIdFor(link, x.links)
    const m = meterId ? x.meterById.get(meterId) : undefined
    return {
      _customer: c.id,
      _meter: m?.id ?? null,
      account: c.customer_number,
      customer: customerName(c),
      customer_type: label(c.customer_type),
      status: label(c.status),
      balance: c.balance,
      deposit: c.deposit_amount,
      created: day(c.created_at),
      move_in: c.move_in_date,
      email: c.email,
      phone: c.phone,
      tax_exempt: yesNo(c.is_tax_exempt),
      billing_hold: yesNo(c.billing_hold),
      premise: loc?.location_number ?? null,
      address: loc?.address ?? null,
      city: loc?.city ?? null,
      zip: loc?.zip ?? null,
      inside_city: loc ? yesNo(loc.inside_city_limits) : null,
      cycle: loc?.billing_cycle ?? null,
      meter: m?.meter_number ?? null,
      meter_status: m ? meterStatus(m.status).label : null,
      read_type: m ? label(m.read_type) : null,
    }
  })
}

export function billRows(invoices: Invoice[], x: Lookups): ReportRow[] {
  return invoices.map((i) => {
    const c = x.customerById.get(i.customer_id)
    return {
      _invoice: i.id,
      _customer: i.customer_id,
      invoice: i.invoice_number,
      account: c?.customer_number ?? null,
      customer: c ? customerName(c) : null,
      period: i.billing_period,
      invoice_date: i.invoice_date,
      due_date: i.due_date,
      type: label(i.invoice_type),
      status: label(i.status),
      previous_balance: i.previous_balance,
      charges: i.total_charges,
      credits: i.total_credits,
      taxes: i.total_taxes,
      adjustments: i.total_adjustments,
      amount_due: i.amount_due,
      amount_paid: i.amount_paid,
      balance: i.balance,
      dunning: label(i.dunning_stage),
      estimated: yesNo(i.has_estimated_reads),
      hold_reason: i.hold_reason,
    }
  })
}

export function paymentRows(payments: Payment[], x: Lookups): ReportRow[] {
  return payments.map((p) => {
    const c = x.customerById.get(p.customer_id)
    return {
      _customer: p.customer_id,
      payment: p.payment_number,
      date: p.payment_date,
      account: c?.customer_number ?? null,
      customer: c ? customerName(c) : null,
      amount: p.amount,
      method: label(p.payment_method),
      channel: label(p.channel),
      status: label(p.status),
      applied: p.applied_amount,
      unapplied: p.unapplied_amount,
      deposit: yesNo(p.is_deposit),
      reference: p.reference_number ?? p.check_number,
      received_by: p.received_by,
    }
  })
}

export function meterRows(meters: Meter[], x: Lookups): ReportRow[] {
  return meters.map((m) => {
    const link = x.links.find((l) => l.meterId === m.id)
    const c = link?.customerId ? x.customerById.get(link.customerId) : undefined
    const loc = link ? x.locationById.get(link.locationId) : undefined
    return {
      _meter: m.id,
      _customer: c?.id ?? null,
      meter: m.meter_number,
      serial: m.serial_number,
      status: meterStatus(m.status).label,
      manufacturer: m.manufacturer,
      model: m.model,
      size: m.size ? sizeLabel(m.size) : null,
      read_type: label(m.read_type),
      endpoint: m.ami_endpoint_id,
      route: m.route_id,
      multiplier: m.multiplier,
      estimates: m.consecutive_estimate_count,
      account: c?.customer_number ?? null,
      customer: c ? customerName(c) : null,
      address: loc?.address ?? null,
      city: loc?.city ?? null,
      last_read: x.lastRead?.get(m.id) ?? null,
      next_test: x.nextTest?.get(m.id) ?? null,
    }
  })
}

export function readRows(readings: MeterReading[], x: Lookups): ReportRow[] {
  return readings.map((r) => {
    const m = x.meterById.get(r.meter_id)
    const link = x.links.find((l) => l.meterId === r.meter_id)
    const c = link?.customerId ? x.customerById.get(link.customerId) : undefined
    return {
      _meter: r.meter_id,
      _customer: c?.id ?? null,
      meter: m?.meter_number ?? null,
      account: c?.customer_number ?? null,
      customer: c ? customerName(c) : null,
      reading_date: r.reading_date,
      reading_value: r.reading_value,
      previous_value: r.previous_value,
      consumption: r.consumption,
      unit: label(r.consumption_unit),
      therms: r.gas_therms,
      days: r.days_in_period,
      method: label(r.read_method),
      purpose: label(r.reading_purpose),
      estimated: yesNo(r.is_estimated),
      quality: label(r.quality_flag),
      status: label(r.status),
      validation: label(r.validation_status),
      access: label(r.access_status),
    }
  })
}

export function exceptionRows(exceptions: Exception[], x: Lookups): ReportRow[] {
  return exceptions.map((e) => {
    const c = e.customer_id ? x.customerById.get(e.customer_id) : undefined
    const m = e.meter_id ? x.meterById.get(e.meter_id) : undefined
    return {
      _customer: e.customer_id,
      _meter: e.meter_id,
      description: e.description,
      type: label(e.anomaly_type),
      severity: label(e.severity),
      status: label(e.status),
      account: c?.customer_number ?? null,
      customer: c ? customerName(c) : null,
      meter: m?.meter_number ?? null,
      detected: day(e.detected_at),
      impact: e.estimated_impact,
      confidence: e.confidence,
      recurrence: e.recurrence_count,
      detector: e.detector_name ? label(e.detector_name) : null,
      assigned_to: e.assigned_to,
      blocks_delivery: yesNo(e.blocks_delivery),
    }
  })
}

export type SourceRows = Record<SourceKey, ReportRow[]>

/* ---- Definitions ------------------------------------------------------ */

export type Op = 'contains' | 'is' | 'is_not' | 'empty' | 'not_empty' | 'eq' | 'ne' | 'gt' | 'ge' | 'lt' | 'le'

export type Filter = { field: string; op: Op; value: string }

export type CustomReport = {
  id: string
  title: string
  source: SourceKey
  /** Field keys shown. Displayed in the source's field order, not the order ticked. */
  columns: string[]
  filters: Filter[]
  groupBy: string | null
  sort: { key: string; dir: 'asc' | 'desc' } | null
  updatedAt: string
}

const NUMERIC = new Set(['money', 'number', 'percent', 'factor'])
const ORDERED = new Set([...NUMERIC, 'date'])

export type OpFamily = 'text' | 'enum' | 'ordered'

/** Which operators a field offers. Identifiers filter as text: an operator types part of a number. */
export function familyOf(f: Field): OpFamily {
  if (f.kind === 'status' || f.enum) return 'enum'
  if (ORDERED.has(f.kind ?? 'text')) return 'ordered'
  return 'text'
}

export const OPS: Record<OpFamily, { op: Op; label: string }[]> = {
  text: [
    { op: 'contains', label: 'contains' },
    { op: 'is', label: 'is' },
    { op: 'is_not', label: 'is not' },
    { op: 'empty', label: 'is empty' },
    { op: 'not_empty', label: 'is not empty' },
  ],
  enum: [
    { op: 'is', label: 'is' },
    { op: 'is_not', label: 'is not' },
  ],
  ordered: [
    { op: 'eq', label: '=' },
    { op: 'ne', label: '≠' },
    { op: 'gt', label: '>' },
    { op: 'ge', label: '≥' },
    { op: 'lt', label: '<' },
    { op: 'le', label: '≤' },
  ],
}

export const needsValue = (op: Op) => op !== 'empty' && op !== 'not_empty'

/* ---- Exact arithmetic ------------------------------------------------- */

const cents = (v: Cell) => Math.round(Number(v ?? 0) * 100)
const dollars = (c: number) => (c / 100).toFixed(2)
/** Non-money sums, carried to four places so float dust never shows. */
const SCALE = 10_000
const units = (v: Cell) => Math.round(Number(v ?? 0) * SCALE)

/**
 * A comparable form of a cell. Money compares in whole cents, so `= 12.3`
 * finds `12.30`; a percent is typed as a whole percent and stored as a
 * fraction, so it compares scaled.
 */
function comparable(f: Field, v: Cell | string): number | string | null {
  if (v === null || v === '') return null
  if (f.kind === 'date') return String(v).slice(0, 10)
  if (f.kind === 'money') return cents(v)
  if (NUMERIC.has(f.kind ?? 'text')) {
    const n = Number(v)
    return Number.isFinite(n) ? Math.round(n * SCALE) : null
  }
  return String(v)
}

function matches(row: ReportRow, f: Field, filter: Filter): boolean {
  const raw = row[f.key] ?? null
  const blank = raw === null || raw === ''
  if (filter.op === 'empty') return blank
  if (filter.op === 'not_empty') return !blank
  const value = filter.value.trim()
  /* A filter still being written narrows nothing. */
  if (value === '') return true
  const family = familyOf(f)
  if (family === 'ordered') {
    const typed = f.kind === 'percent' ? String(Number(value) / 100) : value
    const a = comparable(f, raw)
    const b = comparable(f, typed)
    if (b === null || (typeof b === 'number' && Number.isNaN(b))) return true
    if (a === null) return filter.op === 'ne'
    switch (filter.op) {
      case 'eq':
        return a === b
      case 'ne':
        return a !== b
      case 'gt':
        return a > b
      case 'ge':
        return a >= b
      case 'lt':
        return a < b
      case 'le':
        return a <= b
      default:
        return true
    }
  }
  const text = blank ? '' : String(raw).toLowerCase()
  const want = value.toLowerCase()
  switch (filter.op) {
    case 'contains':
      return text.includes(want)
    case 'is':
      return text === want
    case 'is_not':
      return text !== want
    default:
      return true
  }
}

function compare(f: Column, a: Cell, b: Cell): number {
  const blankA = a === null || a === ''
  const blankB = b === null || b === ''
  if (blankA || blankB) return blankA === blankB ? 0 : blankA ? 1 : -1
  if (NUMERIC.has(f.kind ?? 'text')) return Number(a) - Number(b)
  return String(a).localeCompare(String(b), 'en-US', { numeric: true, sensitivity: 'base' })
}

/* ---- Running a definition --------------------------------------------- */

export const COUNT_KEY = 'row_count'

export type Result = { columns: Column[]; rows: ReportRow[]; matched: number; grouped: boolean }

/**
 * Filter, group and sort a source's rows by a definition.
 *
 * Grouping yields one row per value of the group field, a count, and the sum
 * of every money or number column picked; money sums in whole cents, as
 * ReportTable's footer does, so a grouped report ties back to the ungrouped
 * one to the cent. Percent and factor columns are dropped when grouped —
 * there is no honest sum of a rate.
 */
export function runReport(def: Pick<CustomReport, 'source' | 'columns' | 'filters' | 'groupBy' | 'sort'>, rows: ReportRow[]): Result {
  const src = SOURCES[def.source]
  const picked = src.fields.filter((f) => def.columns.includes(f.key))
  const filtered = rows.filter((r) =>
    def.filters.every((flt) => {
      const f = src.fields.find((x) => x.key === flt.field)
      return f ? matches(r, f, flt) : true
    }),
  )

  const group = def.groupBy ? src.fields.find((f) => f.key === def.groupBy) : undefined
  let columns: Column[]
  let out: ReportRow[]
  if (group) {
    const summed = picked.filter((f) => f.key !== group.key && (f.kind === 'money' || f.kind === 'number'))
    columns = [
      { key: group.key, label: group.label, kind: group.kind, tones: group.tones },
      { key: COUNT_KEY, label: 'Count', kind: 'number', total: true },
      ...summed.map((f) => ({ key: f.key, label: f.label, kind: f.kind, total: true })),
    ]
    const buckets = new Map<string, { value: Cell; rows: ReportRow[] }>()
    for (const r of filtered) {
      const value = r[group.key] ?? null
      const k = value === null ? '\u0000' : String(value)
      const b = buckets.get(k) ?? { value, rows: [] }
      b.rows.push(r)
      buckets.set(k, b)
    }
    out = [...buckets.values()].map(({ value, rows: members }) => {
      const row: ReportRow = { [group.key]: value, [COUNT_KEY]: members.length }
      for (const f of summed) {
        row[f.key] =
          f.kind === 'money'
            ? dollars(members.reduce((n, m) => n + cents(m[f.key] ?? null), 0))
            : members.reduce((n, m) => n + units(m[f.key] ?? null), 0) / SCALE
      }
      return row
    })
  } else {
    columns = picked.map((f) => ({ key: f.key, label: f.label, kind: f.kind, tones: f.tones, total: f.kind === 'money' }))
    out = filtered
  }

  const sortCol = def.sort ? columns.find((c) => c.key === def.sort!.key) : undefined
  /* A grouped report with no usable sort reads best in group order. */
  const by = sortCol ?? (group ? columns[0] : undefined)
  const dir = sortCol && def.sort?.dir === 'desc' ? -1 : 1
  if (by) {
    out = [...out].sort((a, b) => {
      const blankA = a[by.key] === null || a[by.key] === undefined || a[by.key] === ''
      const blankB = b[by.key] === null || b[by.key] === undefined || b[by.key] === ''
      /* Blanks sink to the bottom whichever way the sort runs. */
      if (blankA || blankB) return blankA === blankB ? 0 : blankA ? 1 : -1
      return dir * compare(by, a[by.key] ?? null, b[by.key] ?? null)
    })
  }
  return { columns, rows: out, matched: filtered.length, grouped: !!group }
}

/** The values an enum filter offers: whatever is present in the source, in order. */
export function valuesOf(rows: ReportRow[], key: string): string[] {
  const seen = new Set<string>()
  for (const r of rows) {
    const v = r[key]
    if (v !== null && v !== undefined && v !== '') seen.add(String(v))
  }
  return [...seen].sort((a, b) => a.localeCompare(b, 'en-US', { numeric: true }))
}

/** A fresh definition for a source: its default columns, no filters, no grouping. */
export function blankReport(source: SourceKey): Omit<CustomReport, 'id' | 'updatedAt'> {
  return { title: '', source, columns: [...SOURCES[source].defaults], filters: [], groupBy: null, sort: null }
}

/** One line saying what a saved report does, for the library list. */
export function describeReport(r: CustomReport): string {
  const src = SOURCES[r.source]
  const parts = [src.label, `${r.columns.length} ${r.columns.length === 1 ? 'column' : 'columns'}`]
  if (r.filters.length) parts.push(`${r.filters.length} ${r.filters.length === 1 ? 'filter' : 'filters'}`)
  const g = r.groupBy ? fieldOf(r.source, r.groupBy) : undefined
  if (g) parts.push(`grouped by ${g.label.toLowerCase()}`)
  return parts.join(' · ')
}
