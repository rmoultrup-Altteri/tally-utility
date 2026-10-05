import { customers, locations, meters, serviceLinks } from '@/fixtures/accounts'
import { currentRun, invoices, lines, runs, arAging, revenue } from '@/fixtures/billing'
import { historyInvoices, historyLines } from '@/fixtures/bill-history'
import { exceptions } from '@/fixtures/exceptions'
import { payments } from '@/fixtures/payments'
import { readings } from '@/fixtures/reads'
import { g1Items, gutItem, pgaVersions, priorVersions, r1Items, rateSchedules, versionAsOf } from '@/fixtures/rates'
import { pipeline, worklist } from '@/fixtures/collections'
import { asOf, currentUser, cycle, tenant } from '@/fixtures/tenant'
import { customerName, type Customer, type Meter, type RateItemVersion, type ServiceLocation } from '@/schemas/models'
import { matchesSearch } from '@/lib/search'
import type { ImportedData, ImportedLink } from './protocol'

/**
 * The tenant's account as the assistant reads it: every fixture, plus
 * whatever this browser has imported. Read-only. The tools here answer
 * questions; nothing in this file can change a record.
 */

export type TenantView = {
  customers: Customer[]
  locations: ServiceLocation[]
  meters: Meter[]
  links: ImportedLink[]
  rateVersions: (RateItemVersion & { rate_schedule_code?: string })[]
  imported: ImportedData
}

const fixtureRates: RateItemVersion[] = [
  ...new Map([...pgaVersions, gutItem, ...r1Items, ...g1Items, ...priorVersions].map((v) => [v.id, v])).values(),
]

export function tenantView(imported: ImportedData): TenantView {
  return {
    customers: [...customers, ...imported.customers],
    locations: [...locations, ...imported.locations],
    meters: [...meters, ...imported.meters],
    links: [...serviceLinks, ...imported.links],
    rateVersions: [...fixtureRates, ...imported.rateItems],
    imported,
  }
}

/** Which schedules bill an item. Riders such as the PGA ride every schedule. */
function schedulesFor(v: RateItemVersion & { rate_schedule_code?: string }): string[] {
  if (v.rate_schedule_code) return [v.rate_schedule_code]
  const on: string[] = []
  if (r1Items.some((x) => x.item_code === v.item_code)) on.push('R-1')
  if (g1Items.some((x) => x.item_code === v.item_code)) on.push('G-1')
  return on.length ? on : rateSchedules.map((s) => s.code)
}

/** Exception statuses that no longer need anyone. */
const CLOSED = new Set(['resolved', 'false_positive'])

const allInvoices = () => [...invoices, ...historyInvoices]

/* ---- Tools ----------------------------------------------------------- */

export function searchTenant(view: TenantView, query: string, limit = 15) {
  const hits: { kind: string; id: string; label: string; detail: string }[] = []
  for (const c of view.customers) {
    const link = view.links.find((l) => l.customerId === c.id)
    const loc = link ? view.locations.find((l) => l.id === link.locationId) : undefined
    const mtr = link?.meterId ? view.meters.find((m) => m.id === link.meterId) : undefined
    if (matchesSearch(query, [customerName(c), c.customer_number, loc?.address, loc?.city, mtr?.meter_number, mtr?.serial_number]))
      hits.push({
        kind: 'customer',
        id: c.id,
        label: customerName(c),
        detail: [c.customer_number, loc && `${loc.address}, ${loc.city}`, mtr && `meter ${mtr.meter_number}`].filter(Boolean).join(' · '),
      })
  }
  for (const l of view.locations) {
    if (view.links.some((k) => k.locationId === l.id && k.customerId)) continue
    if (matchesSearch(query, [l.location_number, l.address, l.city, l.zip]))
      hits.push({ kind: 'premise (vacant)', id: l.id, label: l.address, detail: `${l.location_number} · ${l.city}` })
  }
  for (const m of view.meters) {
    if (view.links.some((k) => k.meterId === m.id && k.customerId)) continue
    if (matchesSearch(query, [m.meter_number, m.serial_number, m.ami_endpoint_id]))
      hits.push({ kind: 'meter (unassigned)', id: m.id, label: m.meter_number, detail: m.serial_number ?? '' })
  }
  for (const i of allInvoices()) {
    if (matchesSearch(query, [i.invoice_number]))
      hits.push({ kind: 'invoice', id: i.id, label: i.invoice_number, detail: `${i.billing_period} · ${i.status} · due ${i.amount_due}` })
  }
  return { query, total: hits.length, hits: hits.slice(0, limit) }
}

export function getAccount(view: TenantView, ref: string) {
  const c = view.customers.find((x) => x.id === ref || x.customer_number === ref)
  if (!c) return { error: `No account ${ref}. Use search_tenant to find one.` }
  const premises = view.links
    .filter((l) => l.customerId === c.id)
    .map((l) => {
      const loc = view.locations.find((x) => x.id === l.locationId)
      const mtr = l.meterId ? view.meters.find((x) => x.id === l.meterId) : undefined
      const read = mtr ? readings.find((r) => r.meter_id === mtr.id) : undefined
      return {
        location: loc,
        meter: mtr,
        latest_reading: read && {
          reading_date: read.reading_date,
          reading_value: read.reading_value,
          consumption: read.consumption,
          consumption_unit: read.consumption_unit,
          is_estimated: read.is_estimated,
          status: read.status,
          validation_status: read.validation_status,
          gas_therms: read.gas_therms,
        },
      }
    })
  const bills = allInvoices()
    .filter((i) => i.customer_id === c.id)
    .sort((a, b) => b.invoice_date.localeCompare(a.invoice_date))
    .map((i) => ({
      id: i.id,
      invoice_number: i.invoice_number,
      billing_period: i.billing_period,
      invoice_date: i.invoice_date,
      due_date: i.due_date,
      amount_due: i.amount_due,
      amount_paid: i.amount_paid,
      balance: i.balance,
      status: i.status,
      invoice_type: i.invoice_type,
      dunning_stage: i.dunning_stage,
      hold_reason: i.hold_reason,
    }))
  const paid = payments
    .filter((p) => p.customer_id === c.id)
    .sort((a, b) => b.payment_date.localeCompare(a.payment_date))
    .map((p) => ({
      payment_number: p.payment_number,
      payment_date: p.payment_date,
      amount: p.amount,
      method: p.payment_method,
      status: p.status,
      nsf_reason: p.nsf_reason,
    }))
  return {
    customer: c,
    display_name: customerName(c),
    imported: view.imported.customers.some((x) => x.id === c.id),
    portal_link: `/customers/${c.id}`,
    premises,
    invoices: bills.slice(0, 24),
    invoice_count: bills.length,
    payments: paid.slice(0, 24),
    open_exceptions: exceptions
      .filter((e) => e.customer_id === c.id && !CLOSED.has(e.status))
      .map((e) => ({ id: e.id, severity: e.severity, type: e.anomaly_type, description: e.description, blocks_delivery: e.blocks_delivery })),
    collections: worklist.find((w) => w.customerId === c.id) ?? null,
  }
}

export function getInvoice(ref: string, includeLines = true) {
  const i = allInvoices().find((x) => x.id === ref || x.invoice_number === ref)
  if (!i) return { error: `No invoice ${ref}.` }
  const lineRows = includeLines
    ? [...lines, ...historyLines].filter((l) => l.invoice_id === i.id).sort((a, b) => a.line_order - b.line_order)
    : undefined
  return { invoice: i, portal_link: `/invoices/${i.id}`, lines: lineRows }
}

/* ---- Generic query --------------------------------------------------- */

export const QUERY_ENTITIES = [
  'customers',
  'locations',
  'meters',
  'service_links',
  'readings',
  'invoices',
  'payments',
  'exceptions',
  'rate_schedules',
  'rate_versions',
  'billing_runs',
  'collections_worklist',
] as const
export type QueryEntity = (typeof QUERY_ENTITIES)[number]

function rowsFor(view: TenantView, entity: QueryEntity): Record<string, unknown>[] {
  switch (entity) {
    case 'customers':
      return view.customers.map((c) => ({ ...c, display_name: customerName(c) }))
    case 'locations':
      return view.locations
    case 'meters':
      return view.meters
    case 'service_links':
      return view.links
    case 'readings':
      return readings
    case 'invoices':
      return allInvoices()
    case 'payments':
      return payments.map(({ applications, ...p }) => ({ ...p, applied_to: applications.map((a) => a.invoice_id) }))
    case 'exceptions':
      return exceptions
    case 'rate_schedules':
      return rateSchedules
    case 'rate_versions':
      return view.rateVersions.map((v) => ({ ...v, schedules: schedulesFor(v) }))
    case 'billing_runs':
      return runs
    case 'collections_worklist':
      return worklist
  }
}

/** `>`, `>=`, `<`, `<=`, `!=` and `~` (contains) prefixes; otherwise equality, case-insensitive. */
function matches(value: unknown, test: string | number | boolean): boolean {
  if (typeof test !== 'string') return value === test || String(value) === String(test)
  const m = test.match(/^(>=|<=|!=|>|<|~)\s*(.*)$/)
  const op = m?.[1] ?? '='
  const want = m ? m[2] : test
  if (op === '~') return String(value ?? '').toLowerCase().includes(want.toLowerCase())
  if (want.toLowerCase() === 'null') return op === '!=' ? value != null : value == null
  const a = Number(value)
  const b = Number(want)
  const numeric = value !== null && value !== '' && !Number.isNaN(a) && !Number.isNaN(b) && want !== ''
  const cmp = numeric ? a - b : String(value ?? '').toLowerCase().localeCompare(want.toLowerCase())
  switch (op) {
    case '>':
      return cmp > 0
    case '>=':
      return cmp >= 0
    case '<':
      return cmp < 0
    case '<=':
      return cmp <= 0
    case '!=':
      return cmp !== 0
    default:
      return cmp === 0
  }
}

export function queryRecords(
  view: TenantView,
  q: {
    entity: QueryEntity
    where?: Record<string, string | number | boolean>
    fields?: string[]
    sort_by?: string
    descending?: boolean
    limit?: number
    sum?: string
  },
) {
  const all = rowsFor(view, q.entity)
  const columns = all.length ? Object.keys(all[0]) : []
  for (const key of [...Object.keys(q.where ?? {}), ...(q.fields ?? []), q.sort_by, q.sum].filter(Boolean) as string[]) {
    if (all.length && !columns.includes(key)) return { error: `${q.entity} has no field "${key}". Fields: ${columns.join(', ')}` }
  }
  let rows = all.filter((r) => Object.entries(q.where ?? {}).every(([k, v]) => matches(r[k], v)))
  if (q.sort_by) {
    const k = q.sort_by
    rows = [...rows].sort((a, b) => {
      const x = a[k]
      const y = b[k]
      const n = Number(x) - Number(y)
      const c = Number.isNaN(n) ? String(x ?? '').localeCompare(String(y ?? '')) : n
      return q.descending ? -c : c
    })
  }
  const total = q.sum
    ? rows
        .reduce((acc, r) => acc + BigInt(Math.round(Number(r[q.sum!] ?? 0) * 1_000_000)), BigInt(0))
        .toString()
    : null
  const limit = Math.min(Math.max(q.limit ?? 25, 1), 200)
  const picked = rows.slice(0, limit).map((r) => (q.fields?.length ? Object.fromEntries(q.fields.map((f) => [f, r[f]])) : r))
  return {
    entity: q.entity,
    total_matching: rows.length,
    returned: picked.length,
    ...(total !== null ? { sum: { field: q.sum, value: formatMicros(total) } } : {}),
    rows: picked,
    fields: columns,
  }
}

/** Exact decimal from integer micro-units, so a sum of money never drifts a cent. */
function formatMicros(micros: string): string {
  const neg = micros.startsWith('-')
  const digits = (neg ? micros.slice(1) : micros).padStart(7, '0')
  const whole = digits.slice(0, -6)
  const frac = digits.slice(-6).replace(/0+$/, '').padEnd(2, '0')
  return `${neg ? '-' : ''}${whole}.${frac}`
}

/* ---- Rates and overview --------------------------------------------- */

export function listRates(view: TenantView, scheduleCode?: string, validAt: string = asOf.validAt) {
  const recordedAt = new Date().toISOString()
  const byCode = new Map<string, typeof view.rateVersions>()
  for (const v of view.rateVersions) byCode.set(v.item_code, [...(byCode.get(v.item_code) ?? []), v])
  const schedules = rateSchedules.filter((s) => !scheduleCode || s.code === scheduleCode)
  if (!schedules.length) return { error: `No schedule ${scheduleCode}. Schedules: ${rateSchedules.map((s) => s.code).join(', ')}` }
  return {
    valid_at: validAt,
    recorded_at: recordedAt,
    note: 'Percent rates are stored as fractions (0.04 is 4%). Every lookup is the pair valid_at + recorded_at.',
    schedules: schedules.map((s) => ({
      ...s,
      items: [...byCode.entries()]
        .filter(([, vs]) => vs.some((v) => schedulesFor(v).includes(s.code)))
        .map(([code, vs]) => {
          const inForce = versionAsOf(vs, validAt, recordedAt)
          const scheduled = vs
            .filter((v) => v.recorded_until === null && v.effective_from > validAt)
            .map((v) => ({ rate: v.rate, effective_from: v.effective_from, change_reason: v.change_reason }))
          return {
            item_code: code,
            item_name: (inForce ?? vs[0]).item_name,
            rate_unit: (inForce ?? vs[0]).rate_unit,
            calculation_type: (inForce ?? vs[0]).calculation_type,
            in_force: inForce && {
              rate: inForce.rate,
              effective_from: inForce.effective_from,
              effective_to: inForce.effective_to,
              regulatory_reference: inForce.regulatory_reference,
              change_reason: inForce.change_reason,
            },
            scheduled,
            versions_on_record: vs.length,
          }
        }),
    })),
  }
}

export function billingOverview(view: TenantView) {
  const open = exceptions.filter((e) => !CLOSED.has(e.status))
  const bySeverity = Object.fromEntries(
    ['critical', 'high', 'medium', 'low'].map((s) => [s, open.filter((e) => e.severity === s).length]),
  )
  return {
    tenant,
    user: currentUser,
    as_of: asOf,
    cycle,
    current_run: currentRun,
    revenue_month_to_date: revenue,
    ar_aging_by_invoice: arAging,
    open_exceptions: { total: open.length, blocking_delivery: open.filter((e) => e.blocks_delivery).length, by_severity: bySeverity },
    collections_pipeline: pipeline,
    modelled_records: {
      note: `The prototype models ${customers.length} accounts in full; the tenant serves ${tenant.meters} meters, so portfolio totals (AR, revenue, run totals) cover far more than the modelled rows.`,
      customers: view.customers.length,
      meters: view.meters.length,
      imported_batches: view.imported.batches,
    },
  }
}
