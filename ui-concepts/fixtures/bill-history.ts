import type { BillingRun, Invoice, InvoiceLine } from '@/schemas/models'
import type { DunningStage } from '@/schemas/enums'
import { customers, locationById, meterById, serviceLinks } from '@/fixtures/accounts'
import { asOf } from '@/fixtures/tenant'

/**
 * Twelve months of issued bills behind the February 2026 cycle.
 *
 * The hand-written bills in `billing.ts` are the four the story is about; these
 * exist so the bill list has a year to filter across. They are generated, but
 * held to the same arithmetic the audit checks on the hand-written ones: tier
 * blocks sum to the commodity volume, Ccf × multiplier × BTU = therms, taxes
 * are basis × rate, and amount due − paid = balance.
 *
 * Each bill stands alone (previous balance 0.00). The arrears are the accounts
 * the collections worklist already names — Herrera, Boyd, Brazos Linen, Fry —
 * so an unpaid bill here is one that worklist would be chasing.
 */

/** Bill months, oldest first. February 2026 is the live cycle in `billing.ts`. */
const MONTHS = [
  '2025-02', '2025-03', '2025-04', '2025-05', '2025-06', '2025-07',
  '2025-08', '2025-09', '2025-10', '2025-11', '2025-12', '2026-01',
] as const
type Month = (typeof MONTHS)[number]

/**
 * PGA as billed, by bill month. October to December match the published
 * versions in `rates.ts`; the earlier months predate that fixture's history.
 *
 * January is December's factor on purpose. The January factor (pga-v4) was
 * not recorded until 16 Feb, so bills issued on 16 Jan priced with what the
 * database knew then — the situation the void-and-rebill of INV-2026-01-004913
 * exists to correct.
 */
const PGA: Record<Month, string> = {
  '2025-02': '0.471200', '2025-03': '0.419000', '2025-04': '0.365500',
  '2025-05': '0.338000', '2025-06': '0.329400', '2025-07': '0.342100',
  '2025-08': '0.351700', '2025-09': '0.348800', '2025-10': '0.361200',
  '2025-11': '0.394800', '2025-12': '0.412000', '2026-01': '0.412000',
}

/** WNA by bill month, [R-1, G-1]. The season opened 1 November (`priorVersions` in `rates.ts`). */
const WNA: Partial<Record<Month, [string, string]>> = {
  '2025-11': ['-0.014200', '-0.012400'],
  '2025-12': ['-0.014200', '-0.012400'],
  '2026-01': ['-0.018700', '-0.016100'],
}

/** The GRIP rider took effect 1 June 2025 (grip-v1). */
const GRIP_FROM: Month = '2025-06'
const GRIP_RATE = '0.030700'

/** Herrera's billed therms, which the Customer 360 usage chart also plots. */
const SEASON: Record<Month, number> = {
  '2025-02': 142, '2025-03': 88, '2025-04': 49, '2025-05': 31, '2025-06': 22, '2025-07': 20,
  '2025-08': 21, '2025-09': 24, '2025-10': 44, '2025-11': 97, '2025-12': 158, '2026-01': 171,
}

/** How each account's load compares with Herrera's. */
const SCALE: Record<string, number> = {
  'cus-0001': 1, 'cus-0002': 0.82, 'cus-0003': 11.4, 'cus-0004': 5.2,
  'cus-0005': 0.71, 'cus-0006': 1.18, 'cus-0007': 3.6, 'cus-0008': 0.93,
}

/**
 * Bills still open. `'all'` leaves the whole bill unpaid; a decimal is the
 * balance left after a partial payment. Everything else was paid in full.
 */
const OPEN: Record<string, Partial<Record<Month, 'all' | string>>> = {
  'cus-0001': { '2026-01': '92.43' },
  'cus-0002': { '2026-01': 'all' },
  'cus-0003': { '2025-12': 'all', '2026-01': 'all' },
  'cus-0006': { '2025-10': 'all', '2025-11': 'all', '2025-12': 'all', '2026-01': 'all' },
}

/** The dunning stage the collections worklist has each of those accounts at. */
const STAGE: Record<string, DunningStage> = {
  'cus-0001': 'shutoff_warning',
  'cus-0002': 'reminder_sent',
  'cus-0003': 'collections',
  'cus-0006': 'collections',
}

/** Bills written by hand in `billing.ts` for months this generator would otherwise cover. */
const SKIP = new Set(['cus-0005:2026-01'])

type Schedule = {
  code: 'R-1' | 'G-1'
  charge: { label: string; item: string; amount: string }
  split: number
  blocks: [{ item: string; rate: string }, { item: string; rate: string }]
}

const R1: Schedule = {
  code: 'R-1',
  charge: { label: 'Residential customer charge', item: 'CUST-CHG-RES', amount: '22.500000' },
  split: 50,
  blocks: [
    { item: 'DIST-RES-T1', rate: '0.182400' },
    { item: 'DIST-RES-T2', rate: '0.141900' },
  ],
}
const G1: Schedule = {
  code: 'G-1',
  charge: { label: 'General service customer charge', item: 'CUST-CHG-GS', amount: '48.000000' },
  split: 500,
  blocks: [
    { item: 'DIST-GS-T1', rate: '0.108500' },
    { item: 'DIST-GS-T2', rate: '0.084200' },
  ],
}

/* ---- Exact arithmetic ------------------------------------------------- */

/** Money in integer cents; nothing here goes through a float sum. */
const cents = (v: string) => Math.round(Number(v) * 100)
const fromCents = (c: number) => {
  const sign = c < 0 ? '-' : ''
  const a = Math.abs(c)
  return `${sign}${Math.floor(a / 100)}.${String(a % 100).padStart(2, '0')}`
}
/** quantity × rate, rounded half-up to the cent. */
const extend = (qty: string, rate: string) => Math.round(Number(qty) * Number(rate) * 100)
const q2 = (v: number) => (Math.round(v * 100) / 100).toFixed(2)

/* ---- Calendar ---------------------------------------------------------- */

const MONTH_NAMES = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec']
const iso = (d: Date) => d.toISOString().slice(0, 10)
const utc = (y: number, m: number, d: number) => new Date(Date.UTC(y, m - 1, d))
const addDays = (isoDate: string, n: number) => {
  const d = new Date(`${isoDate}T00:00:00Z`)
  d.setUTCDate(d.getUTCDate() + n)
  return iso(d)
}
const daysBetween = (a: string, b: string) =>
  Math.round((Date.parse(`${b}T00:00:00Z`) - Date.parse(`${a}T00:00:00Z`)) / 86400000)
/** US Central: daylight time runs 2025-03-09 → 2025-11-02. */
const offset = (isoDate: string) => (isoDate >= '2025-03-09' && isoDate < '2025-11-02' ? '-05:00' : '-06:00')

function calendar(month: Month) {
  const [y, m] = month.split('-').map(Number)
  const invoiceDate = iso(utc(y, m, 16))
  return {
    label: `${MONTH_NAMES[m - 1]} ${y}`,
    periodStart: iso(utc(y, m - 1, 15)),
    periodEnd: iso(utc(y, m, 14)),
    invoiceDate,
    dueDate: addDays(invoiceDate, 20),
    runId: `run-${month}-04`,
  }
}

/* ---- Runs -------------------------------------------------------------- */

/** One posted cycle-04 run per month. January 2026 already exists in `billing.ts`. */
export const historyRuns: BillingRun[] = MONTHS.filter((m) => m !== '2026-01').map((month) => {
  const c = calendar(month)
  const tz = offset(c.invoiceDate)
  const invoicesInRun = 3380 + (MONTHS.indexOf(month) * 3)
  return {
    id: c.runId,
    run_number: `BR-${month}-04`,
    billing_period: c.label,
    period_start: c.periodStart,
    period_end: c.periodEnd,
    run_type: 'regular',
    is_dry_run: false,
    correction_rate_mode: 'historical',
    status: 'posted',
    total_locations: invoicesInRun,
    total_invoices: invoicesInRun,
    total_amount: fromCents(Math.round(SEASON[month] * invoicesInRun * 0.84 * 100) + 4_200_000),
    total_exceptions: 6 + (SEASON[month] > 90 ? 5 : 0),
    total_estimated_reads: 24 + Math.round(SEASON[month] / 10),
    started_at: `${c.invoiceDate}T04:00:10${tz}`,
    completed_at: `${c.invoiceDate}T04:11:48${tz}`,
    approved_at: `${c.invoiceDate}T16:52:30${tz}`,
    posted_at: `${c.invoiceDate}T17:10:05${tz}`,
    valid_at: c.periodEnd,
    recorded_at: `${c.invoiceDate}T04:00:10${tz}`,
  }
})

/* ---- Bills ------------------------------------------------------------- */

export const historyInvoices: Invoice[] = []
export const historyLines: InvoiceLine[] = []

for (const customer of customers) {
  const link = serviceLinks.find((l) => l.customerId === customer.id)!
  const location = locationById.get(link.locationId)!
  const meter = meterById.get(link.meterId)!
  const schedule = customer.customer_type === 'residential' ? R1 : G1
  const moveIn = customer.move_in_date ?? '2000-01-01'

  for (const month of MONTHS) {
    if (SKIP.has(`${customer.id}:${month}`)) continue
    const c = calendar(month)
    if (c.periodEnd <= moveIn) continue
    const periodStart = c.periodStart < moveIn ? moveIn : c.periodStart
    const days = daysBetween(periodStart, c.periodEnd)
    const fullDays = daysBetween(c.periodStart, c.periodEnd)

    /* Volume: pick the metered Ccf, then derive therms exactly as the engine does. */
    const mult = Number(meter.multiplier)
    const btu = Number(meter.gas_btu_factor ?? '1')
    const target = SEASON[month] * SCALE[customer.id] * (days / fullDays)
    const ccf = (Math.round((target / (mult * btu)) * 10) / 10).toFixed(1)
    const therms = q2(Number(ccf) * mult * btu)

    const id = `inv-${month.replace('-', '')}-${customer.id.slice(4)}`
    const lines: InvoiceLine[] = []
    const add = (
      l: Pick<InvoiceLine, 'charge_type' | 'description' | 'display_group' | 'rate_item_code' | 'rate' | 'amount'> &
        Partial<InvoiceLine>,
    ) => {
      /* Matches the hand-written bills: the pipeline safety fee and taxes are not taxable; everything else is. */
      const taxable = l.display_group !== 'taxes_fees' && l.rate_item_code !== 'PSF-TX'
      lines.push({
        id: `${id}-l${lines.length + 1}`,
        invoice_id: id,
        line_order: lines.length + 1,
        rate_schedule_code: schedule.code,
        usage_quantity: null,
        usage_unit: null,
        tier_label: null,
        coverage_start: periodStart,
        coverage_end: c.periodEnd,
        days_covered: days,
        days_in_period: days,
        partial_period_policy_applied: null,
        is_taxable: taxable,
        taxable_amount: taxable ? l.amount : '0.00',
        gas_meter_factor: null,
        gas_ccf_used: null,
        gas_therms_billed: null,
        gas_commodity_rate: null,
        gas_btu_factor: null,
        ...l,
      })
    }

    add({
      charge_type: 'customer_charge',
      description: schedule.charge.label,
      display_group: 'base_charges',
      rate_item_code: schedule.charge.item,
      rate: schedule.charge.amount,
      amount: fromCents(cents(schedule.charge.amount)),
    })
    const first = Math.min(Number(therms), schedule.split)
    const blocks = [first.toFixed(2), q2(Number(therms) - first)]
    blocks.forEach((qty, i) => {
      if (Number(qty) <= 0) return
      const b = schedule.blocks[i]
      add({
        charge_type: 'volumetric',
        description: `Distribution charge — ${i === 0 ? 'first' : 'over'} ${schedule.split} therms`,
        display_group: 'usage_charges',
        rate_item_code: b.item,
        usage_quantity: qty,
        usage_unit: 'therms',
        rate: b.rate,
        tier_label: i === 0 ? `Block 1 · 0–${schedule.split} th` : `Block 2 · ${schedule.split}+ th`,
        amount: fromCents(extend(qty, b.rate)),
      })
    })
    add({
      charge_type: 'pga',
      description: 'Purchased gas adjustment',
      display_group: 'usage_charges',
      rate_item_code: 'PGA-GAS',
      usage_quantity: therms,
      usage_unit: 'therms',
      rate: PGA[month],
      gas_meter_factor: meter.multiplier,
      gas_ccf_used: ccf,
      gas_therms_billed: therms,
      gas_commodity_rate: PGA[month],
      gas_btu_factor: meter.gas_btu_factor,
      amount: fromCents(extend(therms, PGA[month])),
    })
    const wna = WNA[month]?.[schedule.code === 'R-1' ? 0 : 1]
    if (wna)
      add({
        charge_type: 'wna',
        description: 'Weather normalization adjustment',
        display_group: 'adjustments',
        rate_item_code: schedule.code === 'R-1' ? 'WNA-RES' : 'WNA-GS',
        usage_quantity: therms,
        usage_unit: 'therms',
        rate: wna,
        tier_label: 'Zone BV-N · Form 2',
        amount: fromCents(extend(therms, wna)),
      })
    add({
      charge_type: 'rider',
      description: 'Pipeline safety fee',
      display_group: 'riders',
      rate_item_code: 'PSF-TX',
      rate: '0.500000',
      amount: '0.50',
    })
    if (month >= GRIP_FROM)
      add({
        charge_type: 'rider',
        description: 'Cost of service adjustment (GRIP)',
        display_group: 'riders',
        rate_item_code: 'GRIP-2025',
        usage_quantity: therms,
        usage_unit: 'therms',
        rate: GRIP_RATE,
        amount: fromCents(extend(therms, GRIP_RATE)),
      })

    const charges = lines.reduce((a, l) => a + cents(l.amount), 0)
    const basis = fromCents(charges)
    const taxes: Invoice['tax_breakdown'] = []
    const tax = (label: string, item: string, rate: string, chargeType: string) => {
      const amount = fromCents(extend(basis, rate))
      taxes.push({ label, basis, rate, amount })
      add({ charge_type: chargeType, description: label, display_group: 'taxes_fees', rate_item_code: item, rate, amount })
    }
    if (location.inside_city_limits && location.franchise_city) {
      const code = location.franchise_city === 'Bryan' ? 'FRAN-BRYAN' : 'FRAN-CSTAT'
      tax(`City of ${location.franchise_city} franchise fee`, code, '0.040000', 'franchise_fee')
    }
    if (customer.customer_type === 'residential') tax('Gas utility tax', 'GUT-TX', '0.005000', 'tax')
    else if (!customer.is_tax_exempt) tax('TX state sales tax', 'TX-SALES', '0.062500', 'tax')

    const totalTaxes = taxes.reduce((a, t) => a + cents(t.amount), 0)
    const due = charges + totalTaxes
    const open = OPEN[customer.id]?.[month]
    const balance = open === undefined ? 0 : open === 'all' ? due : Math.min(cents(open), due)
    const paid = due - balance
    const pastDue = balance > 0 && c.dueDate < asOf.validAt
    const tz = offset(c.invoiceDate)
    const estimated = customer.id === 'cus-0005' && ['2025-10', '2025-11', '2025-12'].includes(month)

    historyInvoices.push({
      id,
      invoice_number: `INV-${month}-${meter.meter_number}`,
      billing_run_id: c.runId,
      customer_id: customer.id,
      location_id: location.id,
      invoice_type: 'regular',
      replaces_invoice_id: null,
      invoice_date: c.invoiceDate,
      billing_period: c.label,
      period_start: periodStart,
      period_end: c.periodEnd,
      due_date: c.dueDate,
      previous_balance: '0.00',
      total_charges: basis,
      total_credits: '0.00',
      total_taxes: fromCents(totalTaxes),
      total_adjustments: '0.00',
      amount_due: fromCents(due),
      amount_paid: fromCents(paid),
      balance: fromCents(balance),
      tax_breakdown: taxes,
      has_estimated_reads: estimated,
      estimated_read_count: estimated ? 1 : 0,
      dunning_stage: pastDue ? (STAGE[customer.id] ?? 'reminder_sent') : 'current',
      has_anomalies: false,
      held_at: null,
      hold_reason: null,
      sent_at: `${c.invoiceDate}T18:30:00${tz}`,
      voided_at: null,
      void_reason_code: null,
      void_reason_notes: null,
      void_rebill_expected: false,
      first_issued_at: `${c.invoiceDate}T17:10:05${tz}`,
      status: balance === 0 ? 'paid' : pastDue ? 'overdue' : paid > 0 ? 'partial' : 'sent',
    })
    historyLines.push(...lines)
  }
}
