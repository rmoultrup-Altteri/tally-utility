import type { RateItemVersion } from '@/schemas/models'
import { pgaVersions, versionAsOf } from '@/fixtures/rates'
import { asOf } from '@/fixtures/tenant'

/**
 * The purchased gas adjustment, read on both time axes at once.
 *
 * A version timeline answers "what is the factor for January". It cannot
 * answer "what did we believe the factor for January was, on the morning we
 * billed it" — and that second question is the one that decides whether a bill
 * gets voided, whether a refund is owed, and what a regulator sees on audit.
 *
 * So this fixture carries the OTHER axis: the ordered list of instants at
 * which the database's knowledge changed. Some of those instants are filings.
 * Some are billing events that consumed the knowledge standing at the time.
 * Crossing them against the service months produces a lattice in which the
 * late January filing is visible as a step that lands well below where the
 * rest of the staircase runs.
 */

/** A service month, probed at its last day — bills price at period end. */
export type ServiceMonth = {
  key: string
  label: string
  /** The `valid_at` used to probe the version chain for this column. */
  probeAt: string
}

export const serviceMonths: ServiceMonth[] = [
  { key: '2025-10', label: 'Oct 2025', probeAt: '2025-10-31' },
  { key: '2025-11', label: 'Nov 2025', probeAt: '2025-11-30' },
  { key: '2025-12', label: 'Dec 2025', probeAt: '2025-12-31' },
  { key: '2026-01', label: 'Jan 2026', probeAt: '2026-01-31' },
  { key: '2026-02', label: 'Feb 2026', probeAt: '2026-02-28' },
  { key: '2026-03', label: 'Mar 2026', probeAt: '2026-03-31' },
]

/**
 * An instant at which the record changed, or was consumed.
 *
 * `filing` rows record a new factor. `billing` rows record nothing — they are
 * moments when a run read the chain and priced against whatever it found, and
 * they are on this axis precisely because the interesting failures happen
 * between filings, not at them.
 */
export type RecordedInstant = {
  id: string
  at: string
  label: string
  kind: 'filing' | 'billing' | 'viewpoint' | 'correction'
  detail?: string
}

export const recordedInstants: RecordedInstant[] = [
  {
    id: 'ri-v1',
    at: '2025-09-24T14:02:00-05:00',
    label: 'October factor filed',
    kind: 'filing',
  },
  {
    id: 'ri-v2',
    at: '2025-10-27T09:41:00-05:00',
    label: 'November factor filed',
    kind: 'filing',
  },
  {
    id: 'ri-v3',
    at: '2025-11-25T11:18:00-06:00',
    label: 'December factor filed',
    kind: 'filing',
  },
  {
    id: 'ri-jan-run',
    at: '2026-01-16T18:02:00-06:00',
    label: 'January cycle billed',
    kind: 'billing',
    detail:
      'BR-2026-01-04 issued 3,412 bills for service through 14 Jan. No January factor had been recorded — the run priced them anyway.',
  },
  {
    id: 'ri-v5',
    at: '2026-01-28T10:07:00-06:00',
    label: 'February factor filed',
    kind: 'filing',
  },
  {
    id: 'ri-now',
    at: asOf.recordedAt,
    label: 'You are here',
    kind: 'viewpoint',
    detail: 'The coordinate the rest of the application is reading through.',
  },
  {
    id: 'ri-v6',
    at: '2026-02-14T16:30:00-06:00',
    label: 'March factor filed',
    kind: 'filing',
  },
  {
    id: 'ri-v4',
    at: '2026-02-16T08:52:00-06:00',
    label: 'January factor filed — 46 days late',
    kind: 'filing',
    detail:
      'Gas Supply recorded the January filing six weeks after the month it applies to. Every January bill already issued was priced without it.',
  },
  {
    id: 'ri-correction',
    at: '2026-02-16T10:04:00-06:00',
    label: 'Correction run reprices January',
    kind: 'correction',
    detail:
      'BR-2026-02-COR-1, rate-date election: historical. Voids and rebills against the factor as it now stands for January.',
  },
]

/** The cell at (service month, recorded instant). */
export function factorAt(month: ServiceMonth, instant: RecordedInstant): RateItemVersion | null {
  return versionAsOf(pgaVersions, month.probeAt, instant.at)
}

/**
 * Calendar days between a filing being recorded and the period it governs
 * opening. Negative is filed ahead of the month; positive is filed into the
 * past. Counted on dates rather than instants, because "46 days late" is how
 * this gets written into a commission response — the clock time a clerk hit
 * save at is not part of the claim.
 */
export function filingLagDays(version: RateItemVersion): number {
  const recordedDate = version.recorded_from.slice(0, 10)
  const recorded = Date.parse(`${recordedDate}T00:00:00Z`)
  const effective = Date.parse(`${version.effective_from}T00:00:00Z`)
  return Math.round((recorded - effective) / 86_400_000)
}

/**
 * The one cell where a bill exists but no factor does.
 *
 * The January run read the chain at (14 Jan 2026, 16 Jan 2026) and found
 * nothing standing — the December version's valid time had already closed.
 * A correct implementation raises here. This one carried December forward,
 * which is the defect the whole void-and-rebill lineage exists to repair.
 */
export const carryForwardDefect = {
  monthKey: '2026-01',
  instantId: 'ri-jan-run',
  billedFactor: '0.412000',
  billedFactorSource: 'pga-v3',
  correctFactor: '0.376400',
  correctFactorSource: 'pga-v4',
} as const

/**
 * The blast radius of the late filing.
 *
 * Totals are the cycle's; only INV-2026-01-004913 is modelled line-by-line in
 * these fixtures. Every bill was overcharged, because the December factor the
 * run carried forward was higher than the January factor eventually filed.
 */
export const backfillExposure = {
  recordedAt: '2026-02-16T08:52:00-06:00',
  servicePeriod: 'Jan 2026',
  billedFactor: '0.412000',
  filedFactor: '0.376400',
  deltaFactor: '0.035600',
  billsIssued: 3412,
  /**
   * Not every affected bill is worth voiding. A de-minimis threshold exists so
   * that a correction run does not mail three thousand replacement statements
   * to recover a dollar each; below it the difference is carried as an
   * adjustment on the next bill instead. The split here is the breakpoint at
   * 54 therms, which is where $0.035600 plus franchise fee clears $2.00.
   */
  thresholdAmount: '2.00',
  thresholdTherms: '54.0',
  billsOverThreshold: 2592,
  billsUnderThreshold: 820,
  therms: '525835.55',
  gasDelta: '18719.75',
  taxDelta: '1084.32',
  totalCredit: '19804.07',
  rebilled: 1,
  /** Credit already returned by the one bill repriced so far. */
  creditIssued: '7.57',
  remainingBills: 2591,
  remainingCredit: '19796.50',
} as const

/** The single fully-modelled bill in the exposure, for the worklist row. */
export const exposureSample = {
  invoiceId: 'inv-0003',
  rebillId: 'inv-0004',
  invoiceNumber: 'INV-2026-01-004913',
  rebillNumber: 'INV-2026-02-C00418',
  accountName: 'Nwosu, Ada',
  therms: '204.34',
  billedAmount: '146.29',
  rebillAmount: '138.72',
  credit: '7.57',
} as const
