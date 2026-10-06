import type { Tone } from '@/components/ui/State'
import type { ReportKey } from '@/lib/views'
import { arAging, revenue } from '@/fixtures/billing'
import { tenant } from '@/fixtures/tenant'

/**
 * Sample reports.
 *
 * Every report is the same shape — a period, a handful of headline figures, a
 * table and its notes — so one renderer serves all of them. The figures are
 * built to tie out with each other and with the rest of the prototype, the way
 * the real ones must:
 *
 *   AR aging            = the dashboard's AR strip, bucket for bucket
 *   Revenue by type     + pass-through taxes = billed net of voids ($412,884.19)
 *   Cash collected      = the dashboard's collected figure ($361,447.02)
 *   GL billing entry    = revenue by type + franchise fees + sales tax
 *   Franchise fees      = the franchise-fee credits in the GL billing entry
 *   WNA, February       = the WNA column in revenue by type
 *
 * The last row or column of each tie-out is computed as the remainder, so an
 * edit to one figure cannot silently break the reconciliation.
 */

export type Cell = string | number | null

export type Column = {
  key: string
  label: string
  kind?: 'text' | 'ident' | 'money' | 'number' | 'percent' | 'factor' | 'date' | 'status'
  /** Summed into the footer row. */
  total?: boolean
  /** For `status` columns: value → tone. */
  tones?: Record<string, Tone>
}

export type ReportRow = Record<string, Cell> & { _group?: string }

export type Report = {
  id: ReportKey
  title: string
  category: Category
  description: string
  period: string
  source: string
  summary: { label: string; value: string; note?: string }[]
  columns: Column[]
  rows: ReportRow[]
  notes: string[]
}

export const CATEGORIES = [
  'Receivables',
  'Revenue and cash',
  'Accounting',
  'Meter reads',
  'Rates and weather',
  'Deposits',
  'Taxes',
  'Regulatory',
] as const
export type Category = (typeof CATEGORIES)[number]

/* ---- Cent arithmetic -------------------------------------------------- */

const cents = (v: Cell) => Math.round(Number(v ?? 0) * 100)
const dollars = (c: number) => (c / 100).toFixed(2)
const sum = (vals: Cell[]) => dollars(vals.reduce<number>((n, v) => n + cents(v), 0))
/** Whatever is left of `total` after `parts` — the figure that makes a tie-out exact. */
const rest = (total: Cell, parts: Cell[]) => dollars(cents(total) - parts.reduce<number>((n, v) => n + cents(v), 0))
const times = (a: number, b: number) => dollars(Math.round(a * b * 100))
const usd = (v: Cell) => {
  const n = Number(v)
  const s = Math.abs(n).toLocaleString('en-US', { style: 'currency', currency: 'USD' })
  return n < 0 ? `(${s})` : s
}

/** A deterministic pseudo-random stream, so generated detail is stable across renders. */
function rng(seed: number) {
  let s = (seed * 2654435761) >>> 0 || 1
  return () => {
    s = (Math.imul(s, 1664525) + 1013904223) >>> 0
    return s / 2 ** 32
  }
}
/** `n` weights scattered around 1. */
const weights = (n: number, seed: number, spread = 1.2) => {
  const r = rng(seed)
  return Array.from({ length: n }, () => 1 - spread / 2 + r() * spread)
}
/** Splits an integer `total` across `w` in proportion, exactly — the remainder is spread a unit at a time. */
function allocate(total: number, w: number[]): number[] {
  if (w.length === 0) return []
  const sw = w.reduce((a, b) => a + b, 0)
  const out = w.map((x) => Math.trunc((total * x) / sw))
  let diff = total - out.reduce((a, b) => a + b, 0)
  const step = Math.sign(diff)
  for (let i = 0; diff !== 0; i++) {
    out[i % out.length] += step
    diff -= step
  }
  return out
}
const allocDollars = (total: Cell, w: number[]) => allocate(cents(total), w).map(dollars)

const addMonths = (iso: string, n: number) => {
  const [y, m, d] = iso.split('-').map(Number)
  return new Date(Date.UTC(y, m - 1 + n, d)).toISOString().slice(0, 10)
}

const pick = <T,>(arr: readonly T[], i: number) => arr[i % arr.length]
const FIRST = ['Maria', 'James', 'Linda', 'Robert', 'Patricia', 'Michael', 'Elena', 'David', 'Grace', 'Thomas', 'Rosa', 'Samuel', 'Nora']
const LAST = ['Alvarez', 'Whitfield', 'Nguyen', 'Kowalski', 'Hargrove', 'Okafor', 'Delgado', 'Brennan', 'Castillo', 'Pruitt', 'Lindqvist']
const STREETS = ['Pendleton Dr', 'Villa Maria Rd', 'Tabor Rd', 'Briarcrest Dr', 'Texas Ave', 'Finfeather Rd', 'Old College Rd', 'Wellborn Rd']
const person = (i: number) => `${pick(LAST, i * 3 + 1)}, ${pick(FIRST, i * 5 + 2)}`
const acct = (i: number) => `100-${String(250000 + i * 4177).slice(-6)}`
const meter = (i: number) => String(4100 + i * 263).padStart(6, '0')
const route = (i: number) => `RT-${String(3 + ((i * 7) % 20)).padStart(2, '0')}`

/* ---- Shared figures ---------------------------------------------------- */

const PGA = 0.3764
const WNA = {
  /* $/therm by month; residential and general service coefficients. */
  'Nov 2025': { hdd: 318, normal: 295, res: -0.0142, gs: -0.0122, resTherms: 98_400, gsTherms: 38_120 },
  'Dec 2025': { hdd: 470, normal: 432, res: -0.0142, gs: -0.0122, resTherms: 151_220, gsTherms: 55_430 },
  'Jan 2026': { hdd: 529, normal: 488, res: -0.0187, gs: -0.0161, resTherms: 172_880, gsTherms: 63_210 },
  'Feb 2026': { hdd: 612, normal: 548, res: -0.0213, gs: -0.0184, resTherms: 168_420, gsTherms: 61_880 },
}
const feb = WNA['Feb 2026']

/* Revenue by class, Cycle 04 — the public-authority base charge closes the tie-out. */
const TAXES = { bryan: '8904.12', collegeStation: '3210.40', navasota: '902.66', salesTax: '1885.15' }
const taxTotal = sum(Object.values(TAXES))
const operatingRevenue = rest(revenue.billedNetOfVoids, [taxTotal])

const classes = [
  { type: 'Residential', schedule: 'R-1', bills: 3012, therms: feb.resTherms, base: '121488.40', wna: times(feb.resTherms, feb.res) },
  { type: 'Small commercial', schedule: 'G-1', bills: 318, therms: feb.gsTherms, base: '31206.55', wna: times(feb.gsTherms, feb.gs) },
  { type: 'Large commercial', schedule: 'G-2', bills: 49, therms: 118_600, base: '38904.10', wna: '0.00' },
  { type: 'Public authority & industrial', schedule: 'G-2 / I-1', bills: 19, therms: 140_200, base: '', wna: '0.00' },
].map((c) => ({ ...c, pga: times(c.therms, PGA) }))
{
  const last = classes[classes.length - 1]
  const others = classes.slice(0, -1).flatMap((c) => [c.base, c.pga, c.wna])
  last.base = rest(operatingRevenue, [...others, last.pga, last.wna])
}
const classRevenue = classes.map((c) => ({ ...c, total: sum([c.base, c.pga, c.wna]) }))

/* ---- The reports ------------------------------------------------------- */

const agingByType = (() => {
  const [cur, d30, d60, d90] = arAging.map((b) => b.amount)
  const rows = [
    { type: 'Residential', invoices: 3020, current: '198442.17', d30: '41877.20', d60: '15112.48', d90: '17884.02' },
    { type: 'Small commercial', invoices: 610, current: '51208.90', d30: '11204.66', d60: '4702.19', d90: '6229.40' },
    { type: 'Large commercial', invoices: 112, current: '24877.35', d30: '6118.04', d60: '2410.77', d90: '6150.00' },
  ]
  const col = (k: 'current' | 'd30' | 'd60' | 'd90') => rows.map((r) => r[k])
  rows.push({
    type: 'Public authority & industrial',
    invoices: 41,
    current: rest(cur, col('current')),
    d30: rest(d30, col('d30')),
    d60: rest(d60, col('d60')),
    d90: rest(d90, col('d90')),
  })
  return rows.map((r) => ({ ...r, total: sum([r.current, r.d30, r.d60, r.d90]) }))
})()
const arTotal = sum(arAging.map((b) => b.amount))

const plans = [
  { account: '100-287365', name: 'Hollis, Duane', start: '2025-10-20', of: 9, paid: 4, inst: '148.81', status: 'On track', next: '2026-02-20' },
  { account: '100-262118', name: 'Okafor, Grace', start: '2025-09-05', of: 6, paid: 5, inst: '96.40', status: 'On track', next: '2026-03-05' },
  { account: '100-271904', name: 'Delgado, Rosa', start: '2025-12-01', of: 12, paid: 2, inst: '61.25', status: 'On track', next: '2026-03-01' },
  { account: '200-118842', name: 'Riverside Diner', start: '2025-08-15', of: 10, paid: 5, inst: '412.00', status: 'Missed 1', next: '2026-02-15' },
  { account: '100-254410', name: 'Pruitt, Samuel', start: '2025-11-10', of: 6, paid: 3, inst: '118.73', status: 'On track', next: '2026-03-10' },
  { account: '100-239877', name: 'Whitfield, Linda', start: '2025-05-01', of: 8, paid: 8, inst: '75.00', status: 'Completed', next: null },
  { account: '100-280551', name: 'Brennan, Thomas', start: '2025-10-01', of: 9, paid: 2, inst: '134.50', status: 'Defaulted', next: null },
  { account: '100-266741', name: 'Nguyen, Elena', start: '2026-01-12', of: 6, paid: 1, inst: '88.16', status: 'On track', next: '2026-03-12' },
  { account: '200-140558', name: 'Navasota Feed & Seed', start: '2025-11-20', of: 12, paid: 3, inst: '640.00', status: 'Missed 1', next: '2026-02-20' },
  { account: '100-248877', name: 'Castillo, Maria', start: '2025-12-15', of: 4, paid: 2, inst: '102.30', status: 'On track', next: '2026-02-15' },
].map((p) => {
  /* Instalments fall due monthly from the start date. An active plan's start
     is set back from its next due date, so the instalments already due are
     exactly the ones paid plus any missed. */
  const missed = p.status === 'Missed 1' ? 1 : 0
  const start = p.next ? addMonths(p.next, -(p.paid + missed + 1)) : p.start
  const original = times(p.of, Number(p.inst))
  const paid = times(p.paid, Number(p.inst))
  return { ...p, start, progress: `${p.paid} of ${p.of}`, original, paidAmt: paid, remaining: rest(original, [paid]), pct: p.paid / p.of }
})

const cashRows = (() => {
  const rows = [
    { type: 'Residential', service: '128402.18', pga: '62118.40', taxes: '7402.55', deposits: '4350.00', late: '1882.40' },
    { type: 'Small commercial', service: '34887.12', pga: '21904.30', taxes: '4118.66', deposits: '1200.00', late: '412.80' },
    { type: 'Large commercial', service: '32118.44', pga: '38420.10', taxes: '3320.18', deposits: '0.00', late: '155.20' },
  ]
  const others = rows.flatMap((r) => [r.service, r.pga, r.taxes, r.deposits, r.late])
  const gov = { type: 'Public authority & industrial', service: '9880.40', pga: '9512.06', taxes: '', deposits: '0.00', late: '0.00' }
  gov.taxes = rest(revenue.collected, [...others, gov.service, gov.pga, gov.deposits, gov.late])
  rows.push(gov)
  return rows.map((r) => ({ ...r, total: sum([r.service, r.pga, r.taxes, r.deposits, r.late]) }))
})()
const depositsCollected = sum(cashRows.map((r) => r.deposits))

const cityReceipts = [
  { city: 'Bryan', ordinance: 'Ord. 2019-41', accounts: 2214, fee: TAXES.bryan, pop: '10,000+', grt: 0.01997 },
  { city: 'College Station', ordinance: 'Ord. 4211', accounts: 802, fee: TAXES.collegeStation, pop: '10,000+', grt: 0.01997 },
  { city: 'Navasota', ordinance: 'Ord. 688-17', accounts: 241, fee: TAXES.navasota, pop: '2,500–9,999', grt: 0.0107 },
].map((c) => ({ ...c, receipts: dollars(Math.round((cents(c.fee) / 0.04))) }))
const salesTaxBasis = dollars(Math.round(cents(TAXES.salesTax) / 0.0625))

const highLow = [
  ...Array.from({ length: 28 }, (_, i) => ({ i, flag: 'High', ratio: 2.1 + ((i * 7) % 18) * 0.15 })),
  ...Array.from({ length: 9 }, (_, i) => ({ i: i + 40, flag: 'Low', ratio: 0.12 + ((i * 5) % 7) * 0.05 })),
].map(({ i, flag, ratio }) => {
  const baseline = 38 + ((i * 13) % 70)
  const current = Math.round(baseline * ratio)
  return {
    meter: meter(i),
    route: route(i),
    account: acct(i),
    name: person(i),
    schedule: i % 6 === 0 ? 'G-1' : 'R-1',
    current,
    baseline,
    variance: current / baseline - 1,
    flag,
    disposition: pick(flag === 'High' ? ['Billed — verified by re-read', 'Re-read ordered', 'Held for review', 'Billed — cold-weather consistent'] : ['Re-read ordered', 'Billed — vacancy confirmed', 'Field check'], i),
  }
})

const glBilling = [
  { account: '1420', name: 'Customer accounts receivable', debit: revenue.billedNetOfVoids, credit: null },
  ...classRevenue.map((c, i) => ({ account: String(4800 + i * 10), name: `Gas sales — ${c.type.toLowerCase()}`, debit: null, credit: c.total })),
  { account: '2410', name: 'Franchise fees payable — Bryan', debit: null, credit: TAXES.bryan },
  { account: '2411', name: 'Franchise fees payable — College Station', debit: null, credit: TAXES.collegeStation },
  { account: '2412', name: 'Franchise fees payable — Navasota', debit: null, credit: TAXES.navasota },
  { account: '2420', name: 'State sales tax payable', debit: null, credit: TAXES.salesTax },
]
const glCash = [
  { account: '1131', name: 'Cash — operating', debit: revenue.collected, credit: null },
  { account: '1420', name: 'Customer accounts receivable', debit: null, credit: rest(revenue.collected, [depositsCollected]) },
  { account: '2350', name: 'Customer deposits', debit: null, credit: depositsCollected },
]
const glDeposits = [
  { account: '2350', name: 'Customer deposits', debit: '2140.00', credit: null },
  { account: '2360', name: 'Deposit interest payable', debit: '38.42', credit: null },
  { account: '1420', name: 'Customer accounts receivable', debit: null, credit: '2178.42' },
]

const DEPOSIT_RATE = 0.041
const deposits = Array.from({ length: 17 }, (_, i) => {
  const amount = pick(['75.00', '100.00', '150.00', '225.00', '400.00'], i * 3)
  const paidYear = 2024 + (i % 3 === 0 ? 0 : 1)
  const paidOn = `${paidYear}-${String(1 + ((i * 5) % 12)).padStart(2, '0')}-${String(3 + ((i * 7) % 24)).padStart(2, '0')}`
  const years = (Date.parse('2026-02-14') - Date.parse(paidOn)) / (365.25 * 86400000)
  const interest = times(Number(amount), DEPOSIT_RATE * years)
  const overdue = Math.max(0, Math.round((years - 1) * 365.25) - 30)
  return {
    account: acct(i + 60),
    name: person(i + 60),
    amount,
    paidOn,
    interest,
    refund: sum([amount, interest]),
    overdue,
    disposition: overdue > 60 ? 'Overdue' : overdue > 0 ? 'Due' : i % 2 ? 'Apply to bill' : 'Refund check',
  }
}).sort((a, b) => b.overdue - a.overdue)

const zeroReads = Array.from({ length: 11 }, (_, i) => ({
  meter: meter(i + 80),
  route: route(i + 80),
  account: acct(i + 80),
  address: `${1100 + i * 217} ${pick(STREETS, i)}`,
  status: pick(['Active', 'Active', 'Vacant — owner account', 'Active'], i),
  cycles: 1 + ((i * 2) % 4),
  lastUsage: `2025-${String(10 + (i % 3)).padStart(2, '0')}-${String(10 + (i % 5)).padStart(2, '0')}`,
  action: pick(['Field check — stopped meter', 'Confirm vacancy', 'Re-read ordered', 'AMI register check'], i),
}))

const RRC_CLASSES = [
  { type: 'Residential', customers: 12_604, mcf: 452_800, revenue: '5182440.00' },
  { type: 'Small commercial', customers: 1_288, mcf: 196_300, revenue: '1614880.00' },
  { type: 'Large commercial', customers: 198, mcf: 368_900, revenue: '2402110.00' },
  { type: 'Public authority & industrial', customers: 76, mcf: 410_200, revenue: '2018330.00' },
]
const rrcRevenue = sum(RRC_CLASSES.map((c) => c.revenue))
const MONTHS_2025 = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'].map((m) => `${m} 2025`)
/* Heating load by month. Residential follows the weather; the larger classes
   carry more year-round process load, so their curve is flatter. */
const SEASON = [1.9, 1.7, 1.3, 0.9, 0.6, 0.45, 0.4, 0.4, 0.45, 0.7, 1.2, 1.7]
const rrcMonthly = RRC_CLASSES.map((c, k) => {
  const flat = [0, 0.35, 0.6, 0.7][k]
  const load = SEASON.map((s) => s * (1 - flat) + flat)
  const mcf = allocate(c.mcf, load)
  /* Revenue carries a fixed customer charge, so it swings less than volume. */
  const revenue = allocate(cents(c.revenue), load.map((l) => 0.3 + 0.7 * l)).map(dollars)
  return MONTHS_2025.map((month, m) => ({
    month,
    customers: Math.round(c.customers * (1 + 0.004 * Math.cos((m / 12) * 2 * Math.PI))),
    mcf: mcf[m],
    revenue: revenue[m],
  }))
})
const booksByMonth = MONTHS_2025.map((_, m) => sum(rrcMonthly.map((c) => c[m].revenue)))
/* Q3: a rebill posted in September after the return was filed. */
const Q3_REBILL = '2828.00'
const quarters = (() => {
  const books = [0, 1, 2, 3].map((q) => sum(booksByMonth.slice(q * 3, q * 3 + 3)))
  const filed = [...books]
  filed[2] = rest(books[2], [Q3_REBILL])
  return books.map((b, i) => {
    const taxBooks = times(Number(b), 0.005)
    const taxPaid = times(Number(filed[i]), 0.005)
    return {
      quarter: `Q${i + 1} 2025`,
      books: b,
      filed: filed[i],
      difference: rest(b, [filed[i]]),
      taxBooks,
      taxPaid,
      variance: rest(taxBooks, [taxPaid]),
      status: cents(b) === cents(filed[i]) ? 'Reconciled' : 'Finding',
    }
  })
})()

const readExceptions = [
  { meter: '004913', route: 'RT-14', account: '100-277451', exception: 'Estimate streak at cap', reading: 'Estimated', prior: '2,114', disposition: 'Field order — locked gate' },
  { meter: '119004', route: 'RT-09', account: '200-114027', exception: 'Negative consumption', reading: '8,402', prior: '8,511', disposition: 'Re-read ordered' },
  { meter: '062118', route: 'RT-22', account: '200-140558', exception: 'Tamper flag', reading: '41,880', prior: '41,102', disposition: 'Investigating' },
  { meter: meter(3), route: route(3), account: acct(3), exception: 'High vs baseline', reading: '6,214', prior: '6,021', disposition: 'Billed — verified' },
  { meter: meter(4), route: route(4), account: acct(4), exception: 'No read — AMI silent', reading: 'Missing', prior: '3,904', disposition: 'Estimated (1st)' },
  { meter: meter(5), route: route(5), account: acct(5), exception: 'Zero usage, active', reading: '1,288', prior: '1,288', disposition: 'Field check' },
  { meter: meter(6), route: route(6), account: acct(6), exception: 'Register rollover', reading: '0,142', prior: '9,961', disposition: 'Billed — rollover confirmed' },
  { meter: meter(7), route: route(7), account: acct(7), exception: 'Meter exchange unreported', reading: '0,018', prior: '5,540', disposition: 'Exchange record added' },
  { meter: meter(8), route: route(8), account: acct(8), exception: 'Out of read window', reading: '2,870', prior: '2,801', disposition: 'Prorated' },
  { meter: meter(9), route: route(9), account: acct(9), exception: 'Low vs baseline', reading: '4,402', prior: '4,396', disposition: 'Re-read ordered' },
]

const STATUS_TONES: Record<string, Tone> = {
  'On track': 'posted',
  Completed: 'cleared',
  'Missed 1': 'warning',
  Defaulted: 'critical',
  High: 'warning',
  Low: 'info',
  Due: 'warning',
  Overdue: 'critical',
  'Apply to bill': 'pending',
  'Refund check': 'pending',
  Reconciled: 'posted',
  Finding: 'critical',
}

export const reports: Report[] = [
  {
    id: 'ar_aging',
    title: 'AR aging',
    category: 'Receivables',
    description: 'Open receivables aged by invoice, split by customer type.',
    period: 'As of Feb 14, 2026',
    source: 'Open invoices, aged from each invoice’s due date',
    summary: [
      { label: 'Total receivables', value: usd(arTotal) },
      { label: '90+ days', value: usd(arAging[3].amount), note: `${((cents(arAging[3].amount) / cents(arTotal)) * 100).toFixed(1)}% of total` },
      { label: 'Accounts 90+ days', value: arAging[3].accounts.toLocaleString('en-US') },
    ],
    columns: [
      { key: 'type', label: 'Customer type' },
      { key: 'invoices', label: 'Open invoices', kind: 'number', total: true },
      { key: 'current', label: 'Current', kind: 'money', total: true },
      { key: 'd30', label: '30 days', kind: 'money', total: true },
      { key: 'd60', label: '60 days', kind: 'money', total: true },
      { key: 'd90', label: '90+ days', kind: 'money', total: true },
      { key: 'total', label: 'Total', kind: 'money', total: true },
    ],
    rows: agingByType,
    notes: [
      'Aged by invoice, not by customer: an account with unpaid bills of different ages appears in more than one bucket.',
      'Bucket totals tie to the accounts receivable strip on the dashboard.',
    ],
  },
  {
    id: 'payment_plans',
    title: 'Payment plans and progress',
    category: 'Receivables',
    description: 'Customers on deferred payment arrangements, instalments paid and what remains.',
    period: 'As of Feb 14, 2026',
    source: 'Payment arrangements and the payments applied against them',
    summary: [
      { label: 'Active plans', value: String(plans.filter((p) => p.status !== 'Completed' && p.status !== 'Defaulted').length) },
      { label: 'Remaining under plan', value: usd(sum(plans.filter((p) => p.status !== 'Defaulted').map((p) => p.remaining))) },
      { label: 'Behind or defaulted', value: String(plans.filter((p) => p.status === 'Missed 1' || p.status === 'Defaulted').length) },
    ],
    columns: [
      { key: 'account', label: 'Account', kind: 'ident' },
      { key: 'name', label: 'Customer' },
      { key: 'start', label: 'Started', kind: 'date' },
      { key: 'progress', label: 'Instalments' },
      { key: 'pct', label: 'Progress', kind: 'percent' },
      { key: 'original', label: 'Plan amount', kind: 'money', total: true },
      { key: 'paidAmt', label: 'Paid', kind: 'money', total: true },
      { key: 'remaining', label: 'Remaining', kind: 'money', total: true },
      { key: 'next', label: 'Next due', kind: 'date' },
      { key: 'status', label: 'Status', kind: 'status', tones: STATUS_TONES },
    ],
    rows: plans,
    notes: [
      'A plan in good standing suspends disconnection for the accounts it covers; one missed instalment moves it to “Missed 1” and a second ends the protection.',
      'Defaulted plans return their remaining balance to the regular collections worklist.',
    ],
  },
  {
    id: 'revenue_by_type',
    title: 'Revenue by customer type',
    category: 'Revenue and cash',
    description: 'Operating revenue billed this month by customer class, with gas cost and weather normalization shown separately.',
    period: revenue.windowLabel,
    source: 'Posted bill lines, net of voids at their void date',
    summary: [
      { label: 'Operating revenue', value: usd(operatingRevenue) },
      { label: 'Pass-through taxes and fees', value: usd(taxTotal) },
      { label: 'Billed, net of voids', value: usd(revenue.billedNetOfVoids), note: 'Ties to the dashboard' },
    ],
    columns: [
      { key: 'type', label: 'Customer type' },
      { key: 'schedule', label: 'Rate', kind: 'ident' },
      { key: 'bills', label: 'Bills', kind: 'number', total: true },
      { key: 'therms', label: 'Therms', kind: 'number', total: true },
      { key: 'base', label: 'Customer & delivery', kind: 'money', total: true },
      { key: 'pga', label: 'Gas cost (PGA)', kind: 'money', total: true },
      { key: 'wna', label: 'WNA', kind: 'money', total: true },
      { key: 'total', label: 'Revenue', kind: 'money', total: true },
    ],
    rows: classRevenue,
    notes: [
      `Gas cost is billed at the PGA factor of $${PGA.toFixed(4)} per therm and passes through to cost of gas; it is not margin.`,
      'WNA credits reflect a colder-than-normal February (612 HDD against 548 normal). G-2 and industrial service carry no WNA.',
      'Franchise fees and sales tax are excluded here — they are liabilities, not revenue — and reported under Taxes.',
    ],
  },
  {
    id: 'cash_by_type_item',
    title: 'Cash collected by customer type and item',
    category: 'Revenue and cash',
    description: 'Payments received this month, broken down by customer class and by what the money paid for.',
    period: revenue.windowLabel,
    source: 'Posted payments, distributed by the payment-application order',
    summary: [
      { label: 'Collected', value: usd(revenue.collected), note: 'Ties to the dashboard' },
      { label: 'Gas cost (PGA) recovered', value: usd(sum(cashRows.map((r) => r.pga))) },
      { label: 'Deposits received', value: usd(depositsCollected) },
    ],
    columns: [
      { key: 'type', label: 'Customer type' },
      { key: 'service', label: 'Gas service', kind: 'money', total: true },
      { key: 'pga', label: 'Gas cost (PGA)', kind: 'money', total: true },
      { key: 'taxes', label: 'Taxes & fees', kind: 'money', total: true },
      { key: 'deposits', label: 'Deposits', kind: 'money', total: true },
      { key: 'late', label: 'Late fees & other', kind: 'money', total: true },
      { key: 'total', label: 'Total', kind: 'money', total: true },
    ],
    rows: cashRows,
    notes: [
      'Posting date basis. Most of this month’s cash pays last month’s bills, so this is not a collection rate against revenue billed.',
      'Payments apply oldest charges first, taxes and fees before gas service within a bill.',
    ],
  },
  {
    id: 'gl_journal',
    title: 'General ledger journal entries',
    category: 'Accounting',
    description: 'The journal entries billing and payments posted to the general ledger this month.',
    period: revenue.windowLabel,
    source: 'Billing run posts, payment batches and deposit applications',
    summary: [
      { label: 'Entries', value: '3' },
      { label: 'Total debits', value: usd(sum([...glBilling, ...glCash, ...glDeposits].map((l) => l.debit))) },
      { label: 'Out of balance', value: usd(rest(sum([...glBilling, ...glCash, ...glDeposits].map((l) => l.debit)), [sum([...glBilling, ...glCash, ...glDeposits].map((l) => l.credit))])) },
    ],
    columns: [
      { key: 'account', label: 'GL account', kind: 'ident' },
      { key: 'name', label: 'Description' },
      { key: 'debit', label: 'Debit', kind: 'money', total: true },
      { key: 'credit', label: 'Credit', kind: 'money', total: true },
    ],
    rows: [
      ...glBilling.map((l) => ({ ...l, _group: 'JE-2026-02-0417 · Feb 14 · Billing posted, month to date' })),
      ...glCash.map((l) => ({ ...l, _group: 'JE-2026-02-0418 · Feb 15 · Cash receipts, month to date' })),
      ...glDeposits.map((l) => ({ ...l, _group: 'JE-2026-02-0419 · Feb 15 · Deposit refunds applied to bills' })),
    ],
    notes: [
      'Each entry balances on its own. The billing entry’s revenue credits tie to Revenue by customer type, and its franchise-fee credits to Municipal franchise fees.',
      'Gas cost (PGA) is credited inside each revenue account here; tenants that book it to a separate cost-of-gas recovery account map it in GL configuration.',
    ],
  },
  {
    id: 'read_exceptions',
    title: 'Meter read exceptions',
    category: 'Meter reads',
    description: 'Every read in the cycle that failed validation, and what was done about it.',
    period: 'Cycle 04 · read window Feb 10–14, 2026',
    source: 'Read validation results for the cycle',
    summary: [
      { label: 'Reads expected', value: '3,412' },
      { label: 'Exceptions', value: String(readExceptions.length) },
      { label: 'Still open', value: String(readExceptions.filter((r) => /order|Investigating|check/i.test(r.disposition)).length) },
    ],
    columns: [
      { key: 'meter', label: 'Meter', kind: 'ident' },
      { key: 'route', label: 'Route', kind: 'ident' },
      { key: 'account', label: 'Account', kind: 'ident' },
      { key: 'exception', label: 'Exception' },
      { key: 'reading', label: 'Reading', kind: 'ident' },
      { key: 'prior', label: 'Prior', kind: 'ident' },
      { key: 'disposition', label: 'Disposition' },
    ],
    rows: readExceptions,
    notes: ['Texas allows no more than three consecutive estimates; meter 004913 is at the cap and needs an actual read before Cycle 04 posts.'],
  },
  {
    id: 'zero_reads',
    title: 'Zero reads',
    category: 'Meter reads',
    description: 'Meters on active or owner accounts that recorded no consumption this cycle.',
    period: 'Cycle 04 · read window Feb 10–14, 2026',
    source: 'Validated reads with zero consumption',
    summary: [
      { label: 'Zero-use meters', value: String(zeroReads.length) },
      { label: 'Two cycles or more', value: String(zeroReads.filter((z) => z.cycles >= 2).length) },
      { label: 'Vacant', value: String(zeroReads.filter((z) => z.status.startsWith('Vacant')).length) },
    ],
    columns: [
      { key: 'meter', label: 'Meter', kind: 'ident' },
      { key: 'route', label: 'Route', kind: 'ident' },
      { key: 'account', label: 'Account', kind: 'ident' },
      { key: 'address', label: 'Service address' },
      { key: 'status', label: 'Account status' },
      { key: 'cycles', label: 'Zero cycles', kind: 'number' },
      { key: 'lastUsage', label: 'Last usage', kind: 'date' },
      { key: 'action', label: 'Action' },
    ],
    rows: zeroReads,
    notes: ['Zero use in a heating month on an occupied premise usually means a stopped meter or a bypass; both are revenue lost until found.'],
  },
  {
    id: 'high_low_reads',
    title: 'High / low reads',
    category: 'Meter reads',
    description: 'Reads outside the expected range for the account’s same-month baseline.',
    period: 'Cycle 04 · read window Feb 10–14, 2026',
    source: 'Read validation, compared with the same month last year, weather-adjusted',
    summary: [
      { label: 'High', value: String(highLow.filter((r) => r.flag === 'High').length), note: 'Over 2× baseline' },
      { label: 'Low', value: String(highLow.filter((r) => r.flag === 'Low').length), note: 'Under 0.5× baseline' },
      { label: 'Held for review', value: String(highLow.filter((r) => r.disposition === 'Held for review').length) },
    ],
    columns: [
      { key: 'flag', label: 'Flag', kind: 'status', tones: STATUS_TONES },
      { key: 'meter', label: 'Meter', kind: 'ident' },
      { key: 'route', label: 'Route', kind: 'ident' },
      { key: 'account', label: 'Account', kind: 'ident' },
      { key: 'name', label: 'Customer' },
      { key: 'schedule', label: 'Rate', kind: 'ident' },
      { key: 'current', label: 'Therms', kind: 'number' },
      { key: 'baseline', label: 'Baseline', kind: 'number' },
      { key: 'variance', label: 'Variance', kind: 'percent' },
      { key: 'disposition', label: 'Disposition' },
    ],
    rows: highLow,
    notes: ['The baseline is weather-adjusted by heating degree days, so a cold month alone does not trip the high flag.'],
  },
  {
    id: 'wna',
    title: 'Degree-day weather normalization',
    category: 'Rates and weather',
    description: 'Heating degree days against normal, the WNA factor each month, and what it adjusted on bills.',
    period: 'WNA season to date · Nov 2025 – Feb 2026',
    source: 'Weather zone BV-N, WNA schedule factors as billed',
    summary: [
      { label: 'Season HDD', value: Object.values(WNA).reduce((n, m) => n + m.hdd, 0).toLocaleString('en-US') },
      { label: 'Normal HDD', value: Object.values(WNA).reduce((n, m) => n + m.normal, 0).toLocaleString('en-US') },
      {
        label: 'WNA credited',
        value: usd(sum(Object.values(WNA).flatMap((m) => [times(m.resTherms, m.res), times(m.gsTherms, m.gs)]))),
      },
    ],
    columns: [
      { key: 'month', label: 'Month' },
      { key: 'hdd', label: 'Actual HDD', kind: 'number', total: true },
      { key: 'normal', label: 'Normal HDD', kind: 'number', total: true },
      { key: 'deviation', label: 'vs normal', kind: 'percent' },
      { key: 'res', label: 'R-1 factor', kind: 'factor' },
      { key: 'resWna', label: 'R-1 WNA', kind: 'money', total: true },
      { key: 'gs', label: 'G-1 factor', kind: 'factor' },
      { key: 'gsWna', label: 'G-1 WNA', kind: 'money', total: true },
      { key: 'total', label: 'Total WNA', kind: 'money', total: true },
    ],
    rows: Object.entries(WNA).map(([month, m]) => {
      const resWna = times(m.resTherms, m.res)
      const gsWna = times(m.gsTherms, m.gs)
      return { month, hdd: m.hdd, normal: m.normal, deviation: m.hdd / m.normal - 1, res: m.res, resWna, gs: m.gs, gsWna, total: sum([resWna, gsWna]) }
    }),
    notes: [
      'A colder-than-normal month produces a credit (negative factor); a warmer one, a surcharge. The adjustment keeps margin recovery independent of weather.',
      'February’s figures tie to the WNA column in Revenue by customer type.',
    ],
  },
  {
    id: 'deposit_refunds',
    title: 'Deposit refunds',
    category: 'Deposits',
    description: 'Customer deposits that have earned a refund, with interest owed.',
    period: 'As of Feb 14, 2026',
    source: 'Deposits held, payment history and the deposit interest rate',
    summary: [
      { label: 'Refunds due', value: String(deposits.length) },
      { label: 'Owed, with interest', value: usd(sum(deposits.map((d) => d.refund))) },
      { label: 'Overdue past 60 days', value: String(deposits.filter((d) => d.disposition === 'Overdue').length) },
    ],
    columns: [
      { key: 'account', label: 'Account', kind: 'ident' },
      { key: 'name', label: 'Customer' },
      { key: 'paidOn', label: 'Deposit paid', kind: 'date' },
      { key: 'amount', label: 'Deposit', kind: 'money', total: true },
      { key: 'interest', label: 'Interest', kind: 'money', total: true },
      { key: 'refund', label: 'Refund', kind: 'money', total: true },
      { key: 'overdue', label: 'Days overdue', kind: 'number' },
      { key: 'disposition', label: 'Status', kind: 'status', tones: STATUS_TONES },
    ],
    rows: deposits,
    notes: [
      `Residential deposits are refunded after twelve consecutive months of on-time payment. Interest accrues at the tenant’s configured annual rate (sample: ${(DEPOSIT_RATE * 100).toFixed(2)}%).`,
    ],
  },
  {
    id: 'franchise_fees',
    title: 'Municipal franchise fees',
    category: 'Taxes',
    description: 'Franchise fees billed inside each city’s limits and owed to that city.',
    period: 'February 2026 · billed basis',
    source: 'Franchise-fee bill lines, by service location city',
    summary: [
      { label: 'Gross receipts in cities', value: usd(sum(cityReceipts.map((c) => c.receipts))) },
      { label: 'Fees owed', value: usd(sum(cityReceipts.map((c) => c.fee))), note: 'Ties to the GL billing entry' },
      { label: 'Due to cities', value: 'Mar 31, 2026' },
    ],
    columns: [
      { key: 'city', label: 'City' },
      { key: 'ordinance', label: 'Franchise', kind: 'ident' },
      { key: 'accounts', label: 'Accounts', kind: 'number', total: true },
      { key: 'receipts', label: 'Gross receipts', kind: 'money', total: true },
      { key: 'rate', label: 'Rate', kind: 'percent' },
      { key: 'fee', label: 'Fee owed', kind: 'money', total: true },
    ],
    rows: cityReceipts.map((c) => ({ city: c.city, ordinance: c.ordinance, accounts: c.accounts, receipts: c.receipts, rate: 0.04, fee: c.fee })),
    notes: [
      'Only service locations inside city limits carry the fee; rural accounts in the same ZIP code do not.',
      'Rates and remittance dates come from each franchise ordinance in tenant configuration.',
    ],
  },
  {
    id: 'state_gross_receipts',
    title: 'State gross receipts and sales tax',
    category: 'Taxes',
    description: 'State gas-utility gross receipts tax by city, and state sales tax on non-residential service.',
    period: 'February 2026 · accrues to the Q1 return',
    source: 'Gross receipts by city and taxable non-residential sales',
    summary: [
      {
        label: 'Gross receipts tax',
        value: usd(sum(cityReceipts.map((c) => times(Number(c.receipts), c.grt)))),
      },
      { label: 'Sales tax', value: usd(TAXES.salesTax) },
      { label: 'Return due', value: 'Apr 20, 2026' },
    ],
    columns: [
      { key: 'tax', label: 'Tax' },
      { key: 'jurisdiction', label: 'Jurisdiction' },
      { key: 'bracket', label: 'Population bracket' },
      { key: 'basis', label: 'Taxable receipts', kind: 'money', total: true },
      { key: 'rate', label: 'Rate', kind: 'percent' },
      { key: 'due', label: 'Tax due', kind: 'money', total: true },
    ],
    rows: [
      ...cityReceipts.map((c) => ({
        tax: 'Gas utility gross receipts',
        jurisdiction: c.city,
        bracket: c.pop,
        basis: c.receipts,
        rate: c.grt,
        due: times(Number(c.receipts), c.grt),
      })),
      { tax: 'State sales tax', jurisdiction: 'Texas', bracket: '—', basis: salesTaxBasis, rate: 0.0625, due: TAXES.salesTax },
    ],
    notes: [
      'The gross receipts tax rate steps with each city’s population. Residential gas service is exempt from state sales tax.',
      'Rates shown are sample values from tenant configuration; confirm them against the current Comptroller schedule before filing.',
    ],
  },
  {
    id: 'rrc_annual',
    title: 'RRC annual report',
    category: 'Regulatory',
    description: 'Customers, volumes and operating revenue by class for the Railroad Commission’s gas utility annual report.',
    period: 'Calendar year 2025',
    source: 'Posted bills and the customer master, calendar-year basis',
    summary: [
      { label: 'Operating revenue', value: usd(rrcRevenue) },
      { label: 'Mcf sold', value: RRC_CLASSES.reduce((n, c) => n + c.mcf, 0).toLocaleString('en-US') },
      { label: 'Meters in service', value: tenant.meters.toLocaleString('en-US'), note: 'Lost and unaccounted-for gas 2.1%' },
    ],
    columns: [
      { key: 'type', label: 'Customer class' },
      { key: 'customers', label: 'Avg. customers', kind: 'number', total: true },
      { key: 'mcf', label: 'Mcf sold', kind: 'number', total: true },
      { key: 'revenue', label: 'Operating revenue', kind: 'money', total: true },
      { key: 'perMcf', label: 'Revenue per Mcf', kind: 'money' },
    ],
    rows: RRC_CLASSES.map((c) => ({ ...c, perMcf: (Number(c.revenue) / c.mcf).toFixed(2) })),
    notes: [
      'Volumes are reported in Mcf at the RRC’s standard pressure base; bills are rendered in therms and converted at each month’s BTU factor.',
      `Filed for ${tenant.name} under the ${tenant.jurisdiction}.`,
    ],
  },
  {
    id: 'rrc_audit',
    title: 'RRC gas utility tax audit',
    category: 'Regulatory',
    description: 'Gross receipts on the books against what was reported on each quarterly gas utility tax return.',
    period: 'Calendar year 2025 · audit reconciliation',
    source: 'General ledger revenue and filed gas utility tax returns',
    summary: [
      { label: 'Gross receipts per books', value: usd(rrcRevenue), note: 'Ties to the RRC annual report' },
      { label: 'Findings', value: String(quarters.filter((q) => q.status === 'Finding').length) },
      { label: 'Additional tax due', value: usd(sum(quarters.map((q) => q.variance))) },
    ],
    columns: [
      { key: 'quarter', label: 'Quarter' },
      { key: 'books', label: 'Receipts per books', kind: 'money', total: true },
      { key: 'filed', label: 'Receipts reported', kind: 'money', total: true },
      { key: 'difference', label: 'Difference', kind: 'money', total: true },
      { key: 'taxBooks', label: 'Tax per books', kind: 'money', total: true },
      { key: 'taxPaid', label: 'Tax paid', kind: 'money', total: true },
      { key: 'variance', label: 'Variance', kind: 'money', total: true },
      { key: 'status', label: 'Status', kind: 'status', tones: STATUS_TONES },
    ],
    rows: quarters,
    notes: [
      'Q3: a rebill posted after the return was filed added $2,828.00 of receipts. Amend the Q3 return or carry the difference onto the next return with an explanation.',
      'Tax computed at the sample rate of 0.5% of gross receipts from tenant configuration.',
    ],
  },
]

export const reportById = new Map(reports.map((r) => [r.id, r]))

/* ---- Drill-down --------------------------------------------------------
   Every report line opens the records it was made from. The records are
   generated, but they are generated FROM the line — split exactly, to the
   cent — so the detail always sums back to the figure that was clicked. */

export type Drill = {
  title: string
  subtitle: string
  ties: { label: string; value: string }[]
  columns: Column[]
  rows: ReportRow[]
}

const CLASS_NAMES = ['Residential', 'Small commercial', 'Large commercial', 'Public authority & industrial']
const classOf = (type: Cell) => Math.max(0, CLASS_NAMES.indexOf(String(type)))
const BIZ_A = ['Brazos', 'Aggieland', 'Navasota', 'Riverside', 'Carter Creek', 'Wellborn', 'Tabor', 'Millican', 'Lake Bryan', 'Villa Maria']
const BIZ_B = ['Bakery', 'Laundry', 'Dental', 'Feed & Seed', 'Diner', 'Auto Care', 'Apartments', 'Cleaners', 'Grill', 'Clinic', 'Plastics', 'Creamery']
const PUBLIC = ['City of Bryan', 'Brazos County', 'Bryan ISD', 'College Station ISD', 'City of Navasota', 'Texas A&M']
const SITES = ['Admin building', 'Annex', 'Fire station', 'Campus', 'Service center', 'Water plant']

const who = (i: number, k: number) => ({
  account: `${k + 1}00-${String(100000 + ((i * 7919 + k * 104729) % 900000))}`,
  name:
    k === 0
      ? person(i * 7 + 3)
      : k === 3
        ? `${pick(PUBLIC, i)} — ${pick(SITES, i * 7 + 1)}`
        : `${pick(BIZ_A, i * 3 + k)} ${pick(BIZ_B, i * 5 + k)}`,
  address: `${100 + ((i * 37 + k * 11) % 4800)} ${pick(STREETS, i * 5 + k)}`,
})
const invNo = (k: number, i: number) => `INV-2026-02-${k + 1}${String(i + 1).padStart(4, '0')}`
const lines = (n: number, noun = 'rows') => `${n.toLocaleString('en-US')} ${noun}`

const BILL_COLUMNS: Column[] = [
  { key: 'invoice', label: 'Invoice', kind: 'ident' },
  { key: 'account', label: 'Account', kind: 'ident' },
  { key: 'name', label: 'Customer' },
  { key: 'therms', label: 'Therms', kind: 'number', total: true },
  { key: 'base', label: 'Customer & delivery', kind: 'money', total: true },
  { key: 'pga', label: 'Gas cost (PGA)', kind: 'money', total: true },
  { key: 'wna', label: 'WNA', kind: 'money', total: true },
  { key: 'total', label: 'Revenue', kind: 'money', total: true },
]

/** One class's bills. PGA and WNA are split in proportion to therms, as they are billed. */
function classBills(k: number): ReportRow[] {
  const c = classRevenue[k]
  const therms = allocate(c.therms, weights(c.bills, 11 + k, 1.5))
  const pga = allocate(cents(c.pga), therms).map(dollars)
  const wna = allocate(cents(c.wna), therms).map(dollars)
  const base = allocDollars(c.base, weights(c.bills, 17 + k, 0.6))
  return therms.map((t, i) => {
    const w = who(i, k)
    return { invoice: invNo(k, i), account: w.account, name: w.name, therms: t, base: base[i], pga: pga[i], wna: wna[i], total: sum([base[i], pga[i], wna[i]]) }
  })
}

const TAXED_COLUMNS = (taxLabel: string): Column[] => [
  { key: 'invoice', label: 'Invoice', kind: 'ident' },
  { key: 'account', label: 'Account', kind: 'ident' },
  { key: 'name', label: 'Customer' },
  { key: 'address', label: 'Service address' },
  { key: 'receipts', label: 'Gross receipts', kind: 'money', total: true },
  { key: 'tax', label: taxLabel, kind: 'money', total: true },
]

/** Bills inside one city's limits, with the city's fee or tax split in proportion to receipts. */
function cityBills(cityIndex: number, tax: Cell): ReportRow[] {
  const c = cityReceipts[cityIndex]
  const receipts = allocate(cents(c.receipts), weights(c.accounts, 41 + cityIndex, 1.5))
  const taxes = allocate(cents(tax), receipts).map(dollars)
  return receipts.map((r, i) => {
    const k = i % 9 === 0 ? 1 : 0
    const w = who(i + cityIndex * 5000, k)
    return { invoice: invNo(k, i + cityIndex * 3000), account: w.account, name: w.name, address: `${w.address}, ${c.city}`, receipts: dollars(r), tax: taxes[i] }
  })
}

/** Non-residential bills that carried state sales tax. */
function salesTaxBills(): ReportRow[] {
  const n = 214
  const basis = allocate(cents(salesTaxBasis), weights(n, 53, 1.6))
  const tax = allocate(cents(TAXES.salesTax), basis).map(dollars)
  return basis.map((b, i) => {
    const k = i % 5 === 0 ? 2 : 1
    const w = who(i + 9000, k)
    return { invoice: invNo(k, i + 6000), account: w.account, name: w.name, address: w.address, receipts: dollars(b), tax: tax[i] }
  })
}

const BUSINESS_DAYS = ['2026-02-02', '2026-02-03', '2026-02-04', '2026-02-05', '2026-02-06', '2026-02-09', '2026-02-10', '2026-02-11', '2026-02-12', '2026-02-13']
const CHANNELS = ['Lockbox', 'Online', 'ACH autopay', 'Walk-in']

/** Daily payment batches by channel. The same seed lines up cash and AR. */
function batches(total: Cell): ReportRow[] {
  const keys = BUSINESS_DAYS.flatMap((d) => CHANNELS.map((ch) => ({ d, ch })))
  const w = weights(keys.length, 61, 1.4)
  const amounts = allocate(cents(total), w).map(dollars)
  const counts = allocate(Math.round(cents(revenue.collected) / 9800), w)
  return keys.map(({ d, ch }, i) => ({
    batch: `B-${d.slice(5).replace('-', '')}-${ch.slice(0, 3).toUpperCase()}`,
    date: d,
    channel: ch,
    payments: counts[i],
    amount: amounts[i],
  }))
}
const BATCH_COLUMNS: Column[] = [
  { key: 'batch', label: 'Batch', kind: 'ident' },
  { key: 'date', label: 'Deposited', kind: 'date' },
  { key: 'channel', label: 'Channel' },
  { key: 'payments', label: 'Payments', kind: 'number', total: true },
  { key: 'amount', label: 'Amount', kind: 'money', total: true },
]

/** Splits in whole units (e.g. $25 deposits) when the total divides evenly. */
function allocUnits(total: Cell, w: number[], unit: number): string[] {
  const c = cents(total)
  return c % unit === 0 ? allocate(c / unit, w).map((u) => dollars(u * unit)) : allocate(c, w).map(dollars)
}

function depositsReceived(total: Cell): ReportRow[] {
  const n = Math.max(1, Math.round(cents(total) / 15000))
  const amounts = allocUnits(total, weights(n, 71, 1.2), 2500)
  return amounts.map((a, i) => {
    const w = who(i + 300, i % 4 === 0 ? 1 : 0)
    return { date: pick(BUSINESS_DAYS, i * 3), account: w.account, name: w.name, amount: a }
  })
}

function depositApplications(): ReportRow[] {
  const deposit = allocUnits('2140.00', weights(14, 79, 1.0), 500)
  const interest = allocate(3842, deposit.map(cents)).map(dollars)
  return deposit.map((d, i) => {
    const w = who(i + 700, 0)
    return { account: w.account, name: w.name, deposit: d, interest: interest[i], total: sum([d, interest[i]]) }
  })
}

const READ_TONES: Record<string, Tone> = { Actual: 'posted', Estimated: 'warning', Missing: 'critical' }
const MONTH_ISO = (m: number) => {
  const monthIndex = (m + 1) % 12 // m = 0 is Feb 2025, m = 12 is Feb 2026
  const year = m >= 11 ? 2026 : 2025
  return { monthIndex, prefix: `${year}-${String(monthIndex + 1).padStart(2, '0')}` }
}

/** Thirteen months of reads, Feb 2025 through this cycle's. */
function readHistory(o: {
  seed: number
  lastTherms?: number
  sameMonthLastYear?: number
  zeroCycles?: number
  last?: Cell
  prior?: Cell
  exception?: string
}): { columns: Column[]; rows: ReportRow[] } {
  const base = 18 + (o.seed % 40)
  const months = Array.from({ length: 13 }, (_, m) => {
    const { monthIndex, prefix } = MONTH_ISO(m)
    return { date: `${prefix}-1${o.seed % 5}`, therms: Math.round(base * SEASON[monthIndex]) }
  })
  if (o.sameMonthLastYear !== undefined) months[0].therms = o.sameMonthLastYear
  if (o.lastTherms !== undefined) months[12].therms = o.lastTherms
  for (let z = 0; z < (o.zeroCycles ?? 0); z++) months[12 - z].therms = 0

  const num = (v: Cell | undefined) => (v === null || v === undefined ? NaN : Number(String(v).replace(/,/g, '')))
  const last = num(o.last)
  const prior = num(o.prior)
  const ccf = (t: number) => Math.round(t / 1.032)
  const registers: number[] = new Array(13)
  registers[11] = Number.isFinite(prior) ? prior : 1000 + ((o.seed * 377) % 7000)
  for (let m = 10; m >= 0; m--) registers[m] = registers[m + 1] - ccf(months[m + 1].therms)
  let type = 'Actual'
  if (Number.isFinite(last)) {
    registers[12] = last
    let used = last - registers[11]
    if (used < 0 && /rollover/i.test(o.exception ?? '')) used += 10000
    else if (used < 0 && /exchange/i.test(o.exception ?? '')) used = last
    months[12].therms = Math.round(used * 1.032)
  } else if (o.last !== undefined) {
    type = String(o.last) === 'Missing' ? 'Missing' : 'Estimated'
    registers[12] = registers[11] + ccf(months[12].therms)
  } else {
    registers[12] = registers[11] + ccf(months[12].therms)
  }
  const flag = o.exception ?? (o.zeroCycles ? 'Zero use' : undefined)
  return {
    columns: [
      { key: 'date', label: 'Read date', kind: 'date' },
      { key: 'type', label: 'Read type', kind: 'status', tones: READ_TONES },
      { key: 'register', label: 'Register (Ccf)', kind: 'ident' },
      { key: 'therms', label: 'Therms', kind: 'number' },
      { key: 'flag', label: 'Validation', kind: 'status', tones: flag ? { [flag]: 'warning' } : {} },
    ],
    rows: months.map((m, i) => ({
      date: m.date,
      type: i === 12 ? type : 'Actual',
      register: type === 'Missing' && i === 12 ? null : String(((registers[i] % 10000) + 10000) % 10000).padStart(4, '0'),
      therms: m.therms,
      flag: i === 12 && flag ? flag : null,
    })),
  }
}

const SCHEDULE_TONES: Record<string, Tone> = { Paid: 'posted', Missed: 'critical', 'Next due': 'warning', Upcoming: 'draft', Cancelled: 'void' }

type DrillFn = (row: ReportRow, index: number) => Drill

const drills: Record<ReportKey, DrillFn> = {
  ar_aging: (row) => {
    const keys = ['current', 'd30', 'd60', 'd90'] as const
    const n = Number(row.invoices)
    const counts = allocate(n, keys.map((k) => Math.max(1, cents(row[k]))))
    const dueBase = { current: '2026-02-20', d30: '2026-01-12', d60: '2025-12-10', d90: '2025-10-28' }
    const k = classOf(row.type)
    let i = 0
    const rows = keys.flatMap((key, b) =>
      allocDollars(row[key], weights(counts[b], 83 + b * 7 + k, 1.6)).map((a, j) => {
        const w = who(i, k)
        const r: ReportRow = { invoice: invNo(k, i), account: w.account, name: w.name, due: addMonths(dueBase[key], b === 3 ? -(j % 4) : 0), current: null, d30: null, d60: null, d90: null }
        r[key] = a
        i++
        return r
      }),
    )
    return {
      title: `${row.type} — open invoices`,
      subtitle: 'As of Feb 14, 2026',
      ties: [
        { label: 'Open invoices', value: lines(n, 'invoices') },
        { label: 'Line total', value: usd(row.total) },
        { label: '90+ days', value: usd(row.d90) },
      ],
      columns: [
        { key: 'invoice', label: 'Invoice', kind: 'ident' },
        { key: 'account', label: 'Account', kind: 'ident' },
        { key: 'name', label: 'Customer' },
        { key: 'due', label: 'Due', kind: 'date' },
        { key: 'current', label: 'Current', kind: 'money', total: true },
        { key: 'd30', label: '30 days', kind: 'money', total: true },
        { key: 'd60', label: '60 days', kind: 'money', total: true },
        { key: 'd90', label: '90+ days', kind: 'money', total: true },
      ],
      rows,
    }
  },

  payment_plans: (row) => {
    const of = Number(row.of)
    const paid = Number(row.paid)
    const status = String(row.status)
    const rows = Array.from({ length: of }, (_, i) => {
      const due = addMonths(String(row.start), i + 1)
      let state = 'Upcoming'
      if (i < paid) state = 'Paid'
      else if (status === 'Defaulted') state = i < paid + 2 ? 'Missed' : 'Cancelled'
      else if (status === 'Missed 1' && i === paid) state = 'Missed'
      else if (i === paid || (status === 'Missed 1' && i === paid + 1)) state = 'Next due'
      return { n: i + 1, due, amount: row.inst, paidOn: state === 'Paid' ? addMonths(due, 0).slice(0, 8) + String(Math.max(1, Number(due.slice(8)) - (i % 3))).padStart(2, '0') : null, state }
    })
    return {
      title: `${row.name} — instalment schedule`,
      subtitle: `Account ${row.account} · started ${row.start}`,
      ties: [
        { label: 'Plan amount', value: usd(row.original) },
        { label: 'Paid', value: usd(row.paidAmt) },
        { label: 'Remaining', value: usd(row.remaining) },
      ],
      columns: [
        { key: 'n', label: 'Instalment', kind: 'number' },
        { key: 'due', label: 'Due', kind: 'date' },
        { key: 'amount', label: 'Amount', kind: 'money', total: true },
        { key: 'paidOn', label: 'Paid on', kind: 'date' },
        { key: 'state', label: 'Status', kind: 'status', tones: SCHEDULE_TONES },
      ],
      rows,
    }
  },

  revenue_by_type: (row) => ({
    title: `${row.type} — bills`,
    subtitle: revenue.windowLabel,
    ties: [
      { label: 'Bills', value: lines(Number(row.bills), 'bills') },
      { label: 'Therms', value: Number(row.therms).toLocaleString('en-US') },
      { label: 'Line revenue', value: usd(row.total) },
    ],
    columns: BILL_COLUMNS,
    rows: classBills(classOf(row.type)),
  }),

  cash_by_type_item: (row) => {
    const k = classOf(row.type)
    const n = Math.max(1, Math.round(cents(row.total) / [9500, 42000, 310000, 180000][k]))
    const w = weights(n, 31 + k, 1.6)
    const [service, pga, taxes] = (['service', 'pga', 'taxes'] as const).map((key) => allocDollars(row[key], w))
    /* Deposits and late fees ride on only some payments. */
    const sparse = (total: Cell, avg: number, unit: number, seed: number) => {
      const out: (string | null)[] = new Array(n).fill(null)
      const c = cents(total)
      const m = c === 0 ? 0 : Math.min(n, Math.max(1, Math.round(c / avg)))
      allocUnits(total, weights(m, seed, 1.0), unit).forEach((p, j) => (out[Math.floor((j * n) / m)] = p))
      return out
    }
    const deposits = sparse(row.deposits, 15000, 2500, 37 + k)
    const late = sparse(row.late, 1200, 1, 43 + k)
    const rows = service.map((s, i) => {
      const p = who(i, k)
      return {
        date: pick(BUSINESS_DAYS, i * 7),
        receipt: `RC-${String(410000 + i * 13 + k * 100000)}`,
        account: p.account,
        name: p.name,
        method: pick(CHANNELS, i * 3 + k),
        service: s,
        pga: pga[i],
        taxes: taxes[i],
        deposits: deposits[i],
        late: late[i],
        total: sum([s, pga[i], taxes[i], deposits[i], late[i]]),
      }
    })
    return {
      title: `${row.type} — payments received`,
      subtitle: revenue.windowLabel,
      ties: [
        { label: 'Payments', value: lines(n, 'payments') },
        { label: 'Line total', value: usd(row.total) },
        { label: 'Deposits', value: usd(row.deposits) },
      ],
      columns: [
        { key: 'date', label: 'Posted', kind: 'date' },
        { key: 'receipt', label: 'Receipt', kind: 'ident' },
        { key: 'account', label: 'Account', kind: 'ident' },
        { key: 'name', label: 'Customer' },
        { key: 'method', label: 'Channel' },
        { key: 'service', label: 'Gas service', kind: 'money', total: true },
        { key: 'pga', label: 'Gas cost', kind: 'money', total: true },
        { key: 'taxes', label: 'Taxes & fees', kind: 'money', total: true },
        { key: 'deposits', label: 'Deposits', kind: 'money', total: true },
        { key: 'late', label: 'Late & other', kind: 'money', total: true },
        { key: 'total', label: 'Total', kind: 'money', total: true },
      ],
      rows,
    }
  },

  gl_journal: (row) => {
    const account = String(row.account)
    const amount = row.debit ?? row.credit
    const side = row.debit ? 'Debit' : 'Credit'
    const subtitle = String(row._group)
    const ties = (n: number, noun: string) => [
      { label: 'GL account', value: `${account} · ${side}` },
      { label: 'Line amount', value: usd(amount) },
      { label: 'Source records', value: lines(n, noun) },
    ]
    if (subtitle.startsWith('JE-2026-02-0417')) {
      if (account.startsWith('48')) {
        const rows = classBills((Number(account) - 4800) / 10)
        return { title: `${row.name} — bills`, subtitle, ties: ties(rows.length, 'bills'), columns: BILL_COLUMNS, rows }
      }
      if (account.startsWith('241')) {
        const ci = Number(account) - 2410
        const rows = cityBills(ci, cityReceipts[ci].fee)
        return { title: `${row.name} — bills`, subtitle, ties: ties(rows.length, 'bills'), columns: TAXED_COLUMNS('Franchise fee'), rows }
      }
      if (account === '2420') {
        const rows = salesTaxBills()
        return { title: `${row.name} — taxable bills`, subtitle, ties: ties(rows.length, 'bills'), columns: TAXED_COLUMNS('Sales tax'), rows }
      }
      /* The receivable debit is made of the entry's credits. */
      const rows = glBilling.filter((l) => l.credit).map((l) => ({ account: l.account, name: l.name, amount: l.credit }))
      return {
        title: `${row.name} — what was billed`,
        subtitle,
        ties: ties(rows.length, 'credit lines'),
        columns: [
          { key: 'account', label: 'Offsetting account', kind: 'ident' },
          { key: 'name', label: 'Description' },
          { key: 'amount', label: 'Amount', kind: 'money', total: true },
        ],
        rows,
      }
    }
    if (subtitle.startsWith('JE-2026-02-0418')) {
      if (account === '2350') {
        const rows = depositsReceived(amount)
        return {
          title: 'Deposits received',
          subtitle,
          ties: ties(rows.length, 'deposits'),
          columns: [
            { key: 'date', label: 'Received', kind: 'date' },
            { key: 'account', label: 'Account', kind: 'ident' },
            { key: 'name', label: 'Customer' },
            { key: 'amount', label: 'Deposit', kind: 'money', total: true },
          ],
          rows,
        }
      }
      const rows = batches(amount)
      return { title: `${row.name} — payment batches`, subtitle, ties: ties(rows.length, 'batches'), columns: BATCH_COLUMNS, rows }
    }
    const rows = depositApplications()
    return {
      title: 'Deposits applied to bills',
      subtitle,
      ties: ties(rows.length, 'deposits'),
      columns: [
        { key: 'account', label: 'Account', kind: 'ident' },
        { key: 'name', label: 'Customer' },
        { key: 'deposit', label: 'Deposit (2350)', kind: 'money', total: true },
        { key: 'interest', label: 'Interest (2360)', kind: 'money', total: true },
        { key: 'total', label: 'Applied to AR (1420)', kind: 'money', total: true },
      ],
      rows,
    }
  },

  read_exceptions: (row, i) => ({
    title: `Meter ${row.meter} — read history`,
    subtitle: `${row.exception} · route ${row.route} · account ${row.account}`,
    ties: [
      { label: 'Exception', value: String(row.exception) },
      { label: 'This cycle', value: String(row.reading) },
      { label: 'Disposition', value: String(row.disposition) },
    ],
    ...readHistory({ seed: i * 11 + 5, last: row.reading, prior: row.prior, exception: String(row.exception) }),
  }),

  zero_reads: (row, i) => ({
    title: `Meter ${row.meter} — read history`,
    subtitle: `${row.address} · route ${row.route} · account ${row.account}`,
    ties: [
      { label: 'Zero cycles', value: String(row.cycles) },
      { label: 'Account status', value: String(row.status) },
      { label: 'Action', value: String(row.action) },
    ],
    ...readHistory({ seed: i * 13 + 2, zeroCycles: Number(row.cycles) }),
  }),

  high_low_reads: (row, i) => ({
    title: `Meter ${row.meter} — read history`,
    subtitle: `${row.name} · ${row.schedule} · account ${row.account}`,
    ties: [
      { label: 'This cycle', value: `${row.current} therms` },
      { label: 'Same month last year', value: `${row.baseline} therms` },
      { label: 'Disposition', value: String(row.disposition) },
    ],
    ...readHistory({ seed: i * 17 + 1, lastTherms: Number(row.current), sameMonthLastYear: Number(row.baseline), exception: `${row.flag} vs baseline` }),
  }),

  wna: (row) => {
    const m = WNA[String(row.month) as keyof typeof WNA]
    const w = weights(4, String(row.month).charCodeAt(0) + Number(row.hdd), 0.4)
    const resTherms = allocate(m.resTherms, w)
    const gsTherms = allocate(m.gsTherms, w)
    const resWna = allocate(cents(row.resWna), resTherms).map(dollars)
    const gsWna = allocate(cents(row.gsWna), gsTherms).map(dollars)
    const rows = [0, 1, 2, 3].map((c) => ({
      cycle: `Cycle 0${c + 1}`,
      hdd: Math.round(m.hdd * (0.94 + c * 0.04)),
      normal: Math.round(m.normal * (0.94 + c * 0.04)),
      resTherms: resTherms[c],
      resWna: resWna[c],
      gsTherms: gsTherms[c],
      gsWna: gsWna[c],
      total: sum([resWna[c], gsWna[c]]),
    }))
    return {
      title: `${row.month} — WNA by billing cycle`,
      subtitle: 'Weather zone BV-N',
      ties: [
        { label: 'Month HDD / normal', value: `${row.hdd} / ${row.normal}` },
        { label: 'R-1 WNA', value: usd(row.resWna) },
        { label: 'Total WNA', value: usd(row.total) },
      ],
      columns: [
        { key: 'cycle', label: 'Cycle' },
        { key: 'hdd', label: 'Cycle HDD', kind: 'number' },
        { key: 'normal', label: 'Normal', kind: 'number' },
        { key: 'resTherms', label: 'R-1 therms', kind: 'number', total: true },
        { key: 'resWna', label: 'R-1 WNA', kind: 'money', total: true },
        { key: 'gsTherms', label: 'G-1 therms', kind: 'number', total: true },
        { key: 'gsWna', label: 'G-1 WNA', kind: 'money', total: true },
        { key: 'total', label: 'Total WNA', kind: 'money', total: true },
      ],
      rows,
    }
  },

  deposit_refunds: (row) => {
    const paidOn = String(row.paidOn)
    const segments = [2024, 2025, 2026]
      .map((y) => {
        const from = Math.max(Date.parse(paidOn), Date.parse(`${y}-01-01`))
        const to = Math.min(Date.parse('2026-02-14'), Date.parse(`${y}-12-31`))
        return { y, days: Math.max(0, Math.round((to - from) / 86400000)), end: y === 2026 ? '2026-02-14' : `${y}-12-31` }
      })
      .filter((s) => s.days > 0)
    const interest = allocate(cents(row.interest), segments.map((s) => s.days)).map(dollars)
    return {
      title: `${row.name} — deposit ledger`,
      subtitle: `Account ${row.account} · deposit paid ${row.paidOn}`,
      ties: [
        { label: 'Deposit', value: usd(row.amount) },
        { label: 'Interest', value: usd(row.interest) },
        { label: 'Refund owed', value: usd(row.refund) },
      ],
      columns: [
        { key: 'date', label: 'Date', kind: 'date' },
        { key: 'entry', label: 'Entry' },
        { key: 'amount', label: 'Amount', kind: 'money', total: true },
      ],
      rows: [
        { date: paidOn, entry: 'Deposit paid', amount: row.amount },
        ...segments.map((s, j) => ({ date: s.end, entry: `Interest accrued, ${s.y} (${s.days} days)`, amount: interest[j] })),
      ],
    }
  },

  franchise_fees: (row, i) => {
    const rows = cityBills(i, row.fee)
    return {
      title: `${row.city} — bills inside city limits`,
      subtitle: `Franchise ${row.ordinance} · February 2026`,
      ties: [
        { label: 'Bills', value: lines(rows.length, 'bills') },
        { label: 'Gross receipts', value: usd(row.receipts) },
        { label: 'Fee owed', value: usd(row.fee) },
      ],
      columns: TAXED_COLUMNS('Franchise fee'),
      rows,
    }
  },

  state_gross_receipts: (row, i) => {
    const city = i < cityReceipts.length
    const rows = city ? cityBills(i, row.due) : salesTaxBills()
    return {
      title: `${row.tax} — ${row.jurisdiction}`,
      subtitle: 'February 2026 · billed basis',
      ties: [
        { label: 'Bills', value: lines(rows.length, 'bills') },
        { label: 'Taxable receipts', value: usd(row.basis) },
        { label: 'Tax due', value: usd(row.due) },
      ],
      columns: TAXED_COLUMNS(city ? 'Gross receipts tax' : 'Sales tax'),
      rows,
    }
  },

  rrc_annual: (row, i) => ({
    title: `${row.type} — by month`,
    subtitle: 'Calendar year 2025',
    ties: [
      { label: 'Avg. customers', value: Number(row.customers).toLocaleString('en-US') },
      { label: 'Mcf sold', value: Number(row.mcf).toLocaleString('en-US') },
      { label: 'Operating revenue', value: usd(row.revenue) },
    ],
    columns: [
      { key: 'month', label: 'Month' },
      { key: 'customers', label: 'Customers', kind: 'number' },
      { key: 'mcf', label: 'Mcf sold', kind: 'number', total: true },
      { key: 'revenue', label: 'Operating revenue', kind: 'money', total: true },
    ],
    rows: rrcMonthly[i],
  }),

  rrc_audit: (row, q) => {
    const months = [0, 1, 2].map((j) => q * 3 + j)
    const books = months.map((m) => booksByMonth[m])
    const filed = months.map((m, j) => (m === 8 ? rest(books[j], [Q3_REBILL]) : books[j]))
    const taxBooks = allocate(cents(row.taxBooks), books.map(cents)).map(dollars)
    const taxPaid = allocate(cents(row.taxPaid), filed.map(cents)).map(dollars)
    return {
      title: `${row.quarter} — by month`,
      subtitle: 'Calendar year 2025 · audit reconciliation',
      ties: [
        { label: 'Receipts per books', value: usd(row.books) },
        { label: 'Receipts reported', value: usd(row.filed) },
        { label: 'Variance', value: usd(row.variance) },
      ],
      columns: reportById.get('rrc_audit')!.columns.map((c) => (c.key === 'quarter' ? { ...c, key: 'month', label: 'Month' } : c)),
      rows: months.map((m, j) => ({
        month: MONTHS_2025[m],
        books: books[j],
        filed: filed[j],
        difference: rest(books[j], [filed[j]]),
        taxBooks: taxBooks[j],
        taxPaid: taxPaid[j],
        variance: rest(taxBooks[j], [taxPaid[j]]),
        status: books[j] === filed[j] ? 'Reconciled' : 'Finding',
      })),
    }
  },
}

/** The detail behind one report line, or null when there is no such line. */
export function drillFor(id: ReportKey, index: number): Drill | null {
  const report = reportById.get(id)
  const row = report?.rows[index]
  if (!report || !row) return null
  return drills[id](row, index)
}
