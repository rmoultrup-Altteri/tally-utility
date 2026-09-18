/**
 * The R-1 tariff, as arithmetic.
 *
 * Every other screen reads rates that were already applied. The sandbox has to
 * apply them itself, against a population, to answer the only question a rate
 * change actually raises: who pays more, who pays less, and by how much.
 *
 * The card below reproduces INV-2026-02-004182 to the cent — 226.01 therms in,
 * $158.34 of charges and $7.12 of tax out. That equality is the calculator's
 * acceptance test: a sandbox whose baseline disagrees with the bills the system
 * already issued is worse than no sandbox at all.
 */

export type RateCard = {
  /** $/month, unconditional. */
  customerCharge: number
  /** $/therm on the first `block1Limit` therms. */
  block1Rate: number
  block1Limit: number
  /** $/therm beyond the breakpoint. */
  block2Rate: number
  /** Pass-through gas cost. Not a policy lever — see the sandbox's note. */
  pga: number
  /** Weather normalisation, signed. Negative is a credit. */
  wna: number
  /** Cost-of-service rider, $/therm. */
  grip: number
  /** Statutory pipeline safety fee, $/month. */
  psf: number
  franchisePct: number
  gutPct: number
  /** The floor a bill may not fall below. */
  minimumBill: number
}

/** R-1 as it stands at the current coordinate (Feb 2026 PGA). */
export const currentCard: RateCard = {
  customerCharge: 22.5,
  block1Rate: 0.1824,
  block1Limit: 50,
  block2Rate: 0.1419,
  pga: 0.4385,
  wna: -0.0213,
  grip: 0.0307,
  psf: 0.5,
  franchisePct: 0.04,
  gutPct: 0.005,
  minimumBill: 22.5,
}

/** The items an operator may move here. */
export type Lever = 'customerCharge' | 'block1Rate' | 'block2Rate' | 'grip'

export const LEVERS: { key: Lever; code: string; label: string; unit: string; step: number }[] = [
  { key: 'customerCharge', code: 'CUST-CHG-RES', label: 'Residential customer charge', unit: '/month', step: 0.25 },
  { key: 'block1Rate', code: 'DIST-RES-T1', label: 'Distribution — first 50 therms', unit: '/therm', step: 0.0005 },
  { key: 'block2Rate', code: 'DIST-RES-T2', label: 'Distribution — over 50 therms', unit: '/therm', step: 0.0005 },
  { key: 'grip', code: 'GRIP-2025', label: 'Cost of service adjustment (GRIP)', unit: '/therm', step: 0.0005 },
]

const cents = (n: number) => Math.round(n * 100) / 100

export type Bill = {
  charges: number
  franchise: number
  gut: number
  tax: number
  total: number
  /** True when the minimum-bill floor lifted the charge subtotal. */
  floored: boolean
}

/**
 * One bill. Components round to the cent individually, because that is how the
 * biller writes the lines and a total re-derived from unrounded components
 * drifts from the sum of the lines the customer can see.
 */
export function billFor(therms: number, card: RateCard): Bill {
  const block1 = Math.min(therms, card.block1Limit)
  const block2 = Math.max(0, therms - card.block1Limit)
  const raw =
    cents(card.customerCharge) +
    cents(block1 * card.block1Rate) +
    cents(block2 * card.block2Rate) +
    cents(therms * card.pga) +
    cents(therms * card.wna) +
    cents(card.psf) +
    cents(therms * card.grip)
  const floored = raw < card.minimumBill
  const charges = cents(floored ? card.minimumBill : raw)
  const franchise = cents(charges * card.franchisePct)
  const gut = cents(charges * card.gutPct)
  return { charges, franchise, gut, tax: cents(franchise + gut), total: cents(charges + franchise + gut), floored }
}

/* ---- The population ---------------------------------------------------- */

/**
 * Cycle 04's actual residential consumption.
 *
 * Generated from a fixed seed rather than listed, so the file stays readable
 * while the numbers stay identical on every run — a sandbox that reports a
 * different answer each reload cannot be used to sign off a rate change. The
 * shape is lognormal with a vacant tail, which is what a Texas winter cycle
 * looks like: a long right side of large heating loads and a few hundred
 * accounts at or near zero.
 */
function seeded(seed: number): () => number {
  let s = seed >>> 0
  return () => {
    s = (s * 1664525 + 1013904223) >>> 0
    return s / 4294967296
  }
}

function buildPopulation(): number[] {
  const rand = seeded(418204)
  const out: number[] = []
  for (let i = 0; i < 3180; i += 1) {
    /* 4% of the class drew no gas this cycle — vacant, seasonal, or off. */
    if (rand() < 0.04) {
      out.push(0)
      continue
    }
    /* Box–Muller into a lognormal centred near 95 therms. */
    const u1 = Math.max(rand(), 1e-9)
    const u2 = rand()
    const z = Math.sqrt(-2 * Math.log(u1)) * Math.cos(2 * Math.PI * u2)
    const therms = Math.exp(Math.log(95) + 0.72 * z)
    out.push(Math.round(Math.min(Math.max(therms, 1), 780) * 100) / 100)
  }
  return out
}

/** Frozen at module load; every consumer sees the same array. */
export const population: readonly number[] = Object.freeze(buildPopulation())

/**
 * What the rehearsal is standing on. The reads behind these volumes are
 * validated and locked, which is what makes the cycle usable as a baseline —
 * rehearsing against a cycle still taking read corrections would move under
 * the operator mid-review.
 */
export const baseline = {
  scheduleCode: 'R-1',
  scheduleName: 'Residential Firm Gas Service',
  cycleLabel: 'Cycle 04 · Jan 2026',
  runNumber: 'BR-2026-01-04',
  periodStart: '2025-12-15',
  periodEnd: '2026-01-14',
  accountsInCycle: 3412,
  accountsOnSchedule: population.length,
  accountsOtherSchedules: 3412 - population.length,
  readsLockedAt: '2026-01-16T02:10:00-06:00',
} as const

/** The change the screen opens on: a rate-design shift, not a rate increase. */
export const openingProposal = {
  customerCharge: 24.0,
  block2Rate: 0.129,
} as const

/**
 * The revenue requirement the proposal is measured against.
 *
 * A rate change is not judged by whether bills went up. It is judged against
 * the increase the commission authorised, over a full year of volumes — which
 * is why this figure is annual and the rehearsal below refuses to produce an
 * annual number from one winter cycle.
 */
export const authorised = {
  docket: 'RRC GUD-11042',
  annualRevenueRequirement: 486000,
  filedOn: '2026-01-09',
} as const
