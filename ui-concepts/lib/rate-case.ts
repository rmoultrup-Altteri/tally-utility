import { population as residentialJanuary } from '@/fixtures/tariff'
import { linesByInvoiceId } from '@/fixtures/billing'
import { CLASSES, presentRates, rateCase, type ClassKey } from '@/fixtures/rate-case'
import { priceAt, sheetFrom, type PriceSheet } from '@/lib/bill-explain'

/**
 * The rate case, as arithmetic.
 *
 * Billing determinants come from the system's own consumption — the same
 * locked January cycle the old sandbox rehearsed against, carried across the
 * test year by the seasonal shape of real bills, and scaled from cycle 04 to
 * every account on the system. Revenue is determinants × rates. Solving a rate
 * design means finding rates whose revenue meets the class's share of the
 * requirement, then rounding them to the four decimals a tariff prints — and
 * saying out loud how far the rounding leaves it from the target.
 *
 * Dollars here are plain numbers because a proof of revenue is a planning
 * figure, rounded to the dollar on the exhibit. Bills are priced through the
 * same `priceAt` that reproduces every issued bill to the cent.
 */

export type Design = { cc: number; r1: number; r2: number }
export type Designs = Record<ClassKey, Design>

/** Test-year bill months, oldest first. */
export const TEST_YEAR = ['Feb 2025', 'Mar 2025', 'Apr 2025', 'May 2025', 'Jun 2025', 'Jul 2025', 'Aug 2025', 'Sep 2025', 'Oct 2025', 'Nov 2025', 'Dec 2025', 'Jan 2026'] as const

/** Residential load by bill month, relative to January — the shape of a year of actual bills. */
const SEASON: Record<(typeof TEST_YEAR)[number], number> = {
  'Feb 2025': 142, 'Mar 2025': 88, 'Apr 2025': 49, 'May 2025': 31, 'Jun 2025': 22, 'Jul 2025': 20,
  'Aug 2025': 21, 'Sep 2025': 24, 'Oct 2025': 44, 'Nov 2025': 97, 'Dec 2025': 158, 'Jan 2026': 171,
}
/** Commercial load has a process floor — kitchens and laundries run all summer. */
const SEASON_G: Record<(typeof TEST_YEAR)[number], number> = {
  'Feb 2025': 150, 'Mar 2025': 112, 'Apr 2025': 86, 'May 2025': 72, 'Jun 2025': 64, 'Jul 2025': 62,
  'Aug 2025': 63, 'Sep 2025': 66, 'Oct 2025': 80, 'Nov 2025': 118, 'Dec 2025': 160, 'Jan 2026': 171,
}

function seeded(seed: number): () => number {
  let s = seed >>> 0
  return () => {
    s = (s * 1664525 + 1013904223) >>> 0
    return s / 4294967296
  }
}

/** Cycle 04's general-service accounts, January. Seeded, so every reload reports the same case. */
function commercialJanuary(): number[] {
  const rand = seeded(918204)
  const out: number[] = []
  for (let i = 0; i < 236; i++) {
    const u1 = Math.max(rand(), 1e-9)
    const u2 = rand()
    const z = Math.sqrt(-2 * Math.log(u1)) * Math.cos(2 * Math.PI * u2)
    out.push(Math.round(Math.min(Math.max(Math.exp(Math.log(640) + 0.85 * z), 40), 9000) * 100) / 100)
  }
  return out
}

const JANUARY: Record<ClassKey, readonly number[]> = { 'R-1': residentialJanuary, 'G-1': commercialJanuary() }

export type MonthDeterminants = { month: string; bills: number; block1: number; block2: number }
export type Determinants = { klass: ClassKey; months: MonthDeterminants[]; bills: number; block1: number; block2: number; therms: number }

/** One class's test-year determinants, scaled from cycle 04 to the whole system. */
function determinantsFor(klass: ClassKey): Determinants {
  const def = CLASSES.find((c) => c.key === klass)!
  const sample = JANUARY[klass]
  const scale = def.systemAccounts / sample.length
  const shape = klass === 'R-1' ? SEASON : SEASON_G
  const months = TEST_YEAR.map((month) => {
    const f = shape[month] / shape['Jan 2026']
    let b1 = 0
    let b2 = 0
    for (const jan of sample) {
      const t = Math.round(jan * f * 100) / 100
      const first = Math.min(t, def.blockLimit)
      b1 += first
      b2 += t - first
    }
    return { month, bills: def.systemAccounts, block1: Math.round(b1 * scale), block2: Math.round(b2 * scale) }
  })
  const sum = (k: 'bills' | 'block1' | 'block2') => months.reduce((a, m) => a + m[k], 0)
  return { klass, months, bills: sum('bills'), block1: sum('block1'), block2: sum('block2'), therms: sum('block1') + sum('block2') }
}

export const determinants: Record<ClassKey, Determinants> = { 'R-1': determinantsFor('R-1'), 'G-1': determinantsFor('G-1') }

/* ---- Revenue ------------------------------------------------------------ */

export type Revenue = { customer: number; block1: number; block2: number; total: number }

export function revenue(klass: ClassKey, d: Design): Revenue {
  const det = determinants[klass]
  const customer = Math.round(det.bills * d.cc)
  const block1 = Math.round(det.block1 * d.r1)
  const block2 = Math.round(det.block2 * d.r2)
  return { customer, block1, block2, total: customer + block1 + block2 }
}

export const presentRevenue: Record<ClassKey, Revenue> = {
  'R-1': revenue('R-1', presentRates['R-1']),
  'G-1': revenue('G-1', presentRates['G-1']),
}
export const presentTotal = presentRevenue['R-1'].total + presentRevenue['G-1'].total

/** Schedule A: the cost of service that the settled increase implies. */
export function revenueRequirement() {
  const c = rateCase.costOfService
  const requirement = presentTotal + rateCase.requestedIncrease
  const ret = Math.round(c.rateBase * c.rateOfReturn)
  const total = requirement + c.otherRevenue
  const om = total - ret - c.depreciation - c.taxesOther
  return {
    rows: [
      { label: 'Operations and maintenance', amount: om, note: 'Settled — the residual of the black-box agreement' },
      { label: 'Depreciation', amount: c.depreciation, note: 'Test-year plant at approved rates' },
      { label: 'Taxes other than income', amount: c.taxesOther, note: 'Ad valorem and payroll' },
      { label: `Return on rate base (${(c.rateOfReturn * 100).toFixed(2)}% × $${(c.rateBase / 1e6).toFixed(2)}M)`, amount: ret, note: 'Weighted cost of capital' },
    ],
    costOfService: total,
    otherRevenue: c.otherRevenue,
    requirement,
    present: presentTotal,
    increase: rateCase.requestedIncrease,
  }
}

/** Each class's revenue target, from the allocation of the increase. */
export function targets(shareR1: number): Record<ClassKey, number> {
  const r = Math.round(rateCase.requestedIncrease * shareR1)
  return {
    'R-1': presentRevenue['R-1'].total + r,
    'G-1': presentRevenue['G-1'].total + (rateCase.requestedIncrease - r),
  }
}

const round4 = (v: number) => Math.round(v * 10000) / 10000

/** Hold the customer charge; scale both blocks by one factor until revenue meets the target. */
export function solveVolumetric(klass: ClassKey, target: number, cc: number, shape: Design = presentRates[klass]): Design {
  const det = determinants[klass]
  const volumetric = det.block1 * shape.r1 + det.block2 * shape.r2
  const k = (target - det.bills * cc) / volumetric
  return { cc, r1: round4(shape.r1 * k), r2: round4(shape.r2 * k) }
}

/** Hold the volumetric rates; solve the customer charge, to the cent. */
export function solveCustomerCharge(klass: ClassKey, target: number, d: Design): Design {
  const det = determinants[klass]
  const cc = (target - det.block1 * d.r1 - det.block2 * d.r2) / det.bills
  return { ...d, cc: Math.round(cc * 100) / 100 }
}

export const settledDesigns: Designs = (() => {
  const t = targets(rateCase.settledAllocation['R-1'])
  return {
    'R-1': solveVolumetric('R-1', t['R-1'], rateCase.settledCustomerCharge['R-1']),
    'G-1': solveVolumetric('G-1', t['G-1'], rateCase.settledCustomerCharge['G-1']),
  }
})()

/* ---- Bills -------------------------------------------------------------- */

/**
 * A bill on each schedule, priced exactly as the biller would: today's riders
 * and taxes from a real bill on that schedule, the design's base rates, and
 * the weather adjustment left out — a typical-bill table compares rates, not
 * weather.
 */
const SHEET: Record<ClassKey, PriceSheet> = {
  'R-1': { ...sheetFrom(linesByInvoiceId('inv-0001')), wna: 0 },
  'G-1': { ...sheetFrom(linesByInvoiceId('inv-0002')), wna: 0 },
}

export const currentPga = SHEET['R-1'].pga

export function billAt(klass: ClassKey, therms: number, d: Design) {
  return priceAt(therms, { ...SHEET[klass], customerCharge: d.cc, block1: d.r1, block2: d.r2 })
}

export const TYPICAL_USAGE: Record<ClassKey, number[]> = {
  'R-1': [0, 10, 25, 50, 75, 100, 150, 200, 300],
  'G-1': [100, 250, 500, 1000, 2000, 4000],
}

/** The average customer on a schedule, across the test year, month by month. */
export function averageCustomer(klass: ClassKey, d: Design) {
  const det = determinants[klass]
  const accounts = det.bills / 12
  const months = det.months.map((m) => {
    const therms = (m.block1 + m.block2) / accounts
    return { month: m.month, therms, present: billAt(klass, therms, presentRates[klass]).total, proposed: billAt(klass, therms, d).total }
  })
  const present = months.reduce((a, m) => a + m.present, 0)
  const proposed = months.reduce((a, m) => a + m.proposed, 0)
  return { months, annualTherms: det.therms / accounts, present, proposed, monthlyChange: Math.round((proposed - present) / 12) }
}

/** How every residential bill in the January cycle moves — the distribution, not the average. */
export function januaryImpact(klass: ClassKey, d: Design) {
  const sample = JANUARY[klass]
  const deltas = sample.map((t) => billAt(klass, t, d).total - billAt(klass, t, presentRates[klass]).total)
  const pcts = sample.map((t, i) => deltas[i] / Math.max(billAt(klass, t, presentRates[klass]).total, 1))
  /* Where a design that moves recovery onto the fixed charge stops costing a customer money. */
  let breakEven: number | null = null
  const sign = (t: number) => billAt(klass, t, d).total - billAt(klass, t, presentRates[klass]).total
  const start = sign(0)
  for (let t = 0; t <= (klass === 'R-1' ? 800 : 9000); t += klass === 'R-1' ? 0.5 : 5) {
    if (start > 0 ? sign(t) <= 0 : sign(t) >= 0) {
      breakEven = t
      break
    }
  }
  return { sample, deltas, pcts, breakEven, zeroUsage: sign(0) }
}

export function changedItems(designs: Designs) {
  return CLASSES.flatMap((c) => {
    const now = presentRates[c.key]
    const next = designs[c.key]
    return (
      [
        [c.codes[0], 'Customer charge', now.cc, next.cc, 'month'],
        [c.codes[1], `Distribution, first ${c.blockLimit} therms`, now.r1, next.r1, 'therm'],
        [c.codes[2], `Distribution, over ${c.blockLimit} therms`, now.r2, next.r2, 'therm'],
      ] as [string, string, number, number, string][]
    )
      .filter(([, , a, b]) => Math.abs(a - b) > 1e-9)
      .map(([code, label, from, to, unit]) => ({ klass: c.key, code, label, from, to, unit }))
  })
}
