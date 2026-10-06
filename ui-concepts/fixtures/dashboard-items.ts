import { portlets } from '@/fixtures/billing'

/**
 * The rows behind each dashboard portlet count (T8-4 drilldown).
 *
 * A portlet count is only trustworthy if clicking it lands on a list of
 * exactly that many rows — the same reconciliation rule the AR aging strip
 * lives by. So the rows here are generated FROM the portlet counts rather
 * than alongside them: "Failed calculations · 3" opens three rows, always.
 *
 * Each item type reads from a different table (a failed calculation is a
 * `billing_run_meters.outcome`, a held invoice is `invoices.status`, and so
 * on), so every row names its source. The accounts are synthetic: the
 * hand-built account fixtures are far too few to back 139 rows.
 */

export type Tier = (typeof portlets)[number]['tier']

export type DashboardItem = {
  id: string
  itemType: string
  typeLabel: string
  tier: Tier
  source: string
  reference: string
  accountName: string
  accountNumber: string
  detail: string
  amount: string | null
  detectedAt: string
}

type Spec = {
  source: string
  reference: (i: number) => string
  detail: (i: number) => string
  amount?: (i: number) => string
}

const pick = <T,>(arr: readonly T[], i: number) => arr[i % arr.length]
const meterNo = (i: number) => String(4100 + i * 137).padStart(6, '0')
const invoiceNo = (i: number) => `INV-2026-02-${String(8811 + i * 29).padStart(5, '0')}`
const dollars = (base: number, step: number) => (i: number) => (base + ((i * step) % 400)).toFixed(2)

const SPECS: Record<string, Spec> = {
  failed_calculation: {
    source: 'Billing run meter',
    reference: (i) => `Meter ${meterNo(i)}`,
    detail: (i) =>
      pick(
        [
          'No effective rate item for G-1 on the service-from date',
          'BTU factor missing for the read date',
          'Tier configuration has a gap between 50 and 51 therms',
        ],
        i,
      ),
  },
  negative_consumption: {
    source: 'Meter reading',
    reference: (i) => `Meter ${meterNo(i)}`,
    detail: () => 'Current read lower than prior with no rollover or exchange recorded',
  },
  estimated_streak: {
    source: 'Meter reading',
    reference: (i) => `Meter ${meterNo(i)}`,
    detail: (i) => `Third consecutive estimate — at Texas cap${i % 2 ? ' · locked gate' : ''}`,
  },
  held_invoice: {
    source: 'Invoice',
    reference: invoiceNo,
    detail: (i) => pick(['Held for supervisor review', 'Held — amount over 3× prior bill', 'Held pending rebill'], i),
    amount: dollars(148, 97),
  },
  backbilling_cap: {
    source: 'Invoice',
    reference: invoiceNo,
    detail: () => 'Backbill exceeds the six-month statutory cap',
  },
  tamper_detected: {
    source: 'Meter event',
    reference: (i) => `Meter ${meterNo(i)}`,
    detail: (i) => pick(['Reverse-flow flag on AMI endpoint', 'Index seal reported broken by field tech'], i),
  },
  high_usage: {
    source: 'Meter reading',
    reference: (i) => `Meter ${meterNo(i)}`,
    detail: (i) => `${(2.1 + (i % 9) * 0.4).toFixed(1)}× the same-month baseline`,
    amount: dollars(92, 53),
  },
  zero_usage: {
    source: 'Meter reading',
    reference: (i) => `Meter ${meterNo(i)}`,
    detail: (i) => `Zero consumption on an active account · ${1 + (i % 3)} cycle${i % 3 ? 's' : ''}`,
  },
  delivery_failure: {
    source: 'Invoice',
    reference: invoiceNo,
    detail: (i) => pick(['Returned mail — undeliverable address', 'Email bounced', 'Print vendor rejected record'], i),
    amount: dollars(61, 71),
  },
  endpoint_offline: {
    source: 'AMI endpoint',
    reference: (i) => `Endpoint ${String(880210 + i * 311)}`,
    detail: (i) => `No transmission for ${4 + (i % 11)} days`,
  },
  rate_schedule_mismatch: {
    source: 'Account',
    reference: (i) => `Meter ${meterNo(i)}`,
    detail: () => 'Commercial premise billed on R-1',
  },
  unbilled_service: {
    source: 'Service location',
    reference: (i) => `Meter ${meterNo(i)}`,
    detail: () => 'Active meter with consumption and no billing account',
  },
  deposit_refund_overdue: {
    source: 'Deposit',
    reference: (i) => `DEP-${String(30418 + i * 13)}`,
    detail: (i) => `Refund due ${3 + (i % 20)} days ago after 12 months of on-time payment`,
    amount: dollars(75, 25),
  },
  tax_exemption_expired: {
    source: 'Tax exemption',
    reference: (i) => `CERT-${String(7710 + i * 7)}`,
    detail: (i) => `Certificate expires in ${5 + (i % 25)} days`,
  },
  credit_balance_stale: {
    source: 'Account',
    reference: () => 'Account ledger',
    detail: (i) => `Credit balance unchanged for ${7 + (i % 12)} months`,
    amount: dollars(12, 43),
  },
  address_mismatch: {
    source: 'Account',
    reference: () => 'Mailing address',
    detail: () => 'Mailing address does not validate against USPS',
  },
}

const FIRST = ['Maria', 'James', 'Linda', 'Robert', 'Patricia', 'Michael', 'Elena', 'David', 'Grace', 'Thomas', 'Rosa', 'Samuel', 'Nora']
const LAST = ['Alvarez', 'Whitfield', 'Nguyen', 'Kowalski', 'Hargrove', 'Okafor', 'Delgado', 'Brennan', 'Castillo', 'Pruitt', 'Lindqvist']
const BUSINESS = ['Navasota Feed & Seed', 'Aggieland Laundry', 'Brazos Bakery', 'Bryan Tire Co.', 'Riverside Diner']

export const dashboardItems: DashboardItem[] = portlets.flatMap((p) =>
  p.rows.flatMap((row) => {
    const spec = SPECS[row.itemType]
    return Array.from({ length: row.count }, (_, i): DashboardItem => {
      const seed = row.itemType.length * 7 + i * 5
      const business = (seed + i) % 6 === 0
      return {
        id: `${row.itemType}-${i + 1}`,
        itemType: row.itemType,
        typeLabel: row.label,
        tier: p.tier,
        source: spec?.source ?? '—',
        reference: spec?.reference(i) ?? '—',
        accountName: business ? pick(BUSINESS, seed) : `${pick(FIRST, seed)} ${pick(LAST, seed + i)}`,
        accountNumber: `${pick(['100', '200', '300'], seed)}-${String(240000 + seed * 977).slice(-6)}`,
        detail: spec?.detail(i) ?? row.label,
        amount: spec?.amount?.(i) ?? null,
        detectedAt: `2026-02-${String(15 - (i % 9)).padStart(2, '0')}T0${4 + (i % 5)}:${String(10 + ((i * 7) % 50))}:00-06:00`,
      }
    })
  }),
)

export const TIERS = portlets.map((p) => p.tier)

/** Item types by tier, in portlet order, for the drilldown's filter bar. */
export const typesByTier = portlets.map((p) => ({
  tier: p.tier,
  types: p.rows.map((r) => ({ itemType: r.itemType, label: r.label, count: r.count })),
}))
