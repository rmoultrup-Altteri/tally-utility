import { addCalendarDays } from '@/lib/working-days'
import { date } from '@/lib/format'

/**
 * Which rate schedule a customer was on, and when (R-09).
 *
 * Not the Rate History tab, which versions the rates themselves. This is the
 * customer's side: a dated, add-only list of assignments with no overlaps.
 * The same close-then-insert discipline as `rates.ts`: a change closes the
 * standing row the day before the new one starts and inserts a successor.
 * No row is edited after it is written and no row is deleted. A correction
 * is a new row with a reason.
 *
 * The database keeps the schedule on the meter (`meters.rate_schedule_id`,
 * copied to `meter_deployments`), not on the customer. This history is keyed
 * by customer because R-09 asks for it that way.
 */

export type RateAssignment = {
  id: string
  customer_id: string
  schedule_code: string
  start_date: string
  /** Blank on the standing row. Written once, by the close, when a successor is added. */
  end_date: string | null
  reason: string
  /** A proposed change waiting on supervisor approval. It takes its dates but bills nothing yet. */
  pending: boolean
  /** The exception that proposed it, when one did. */
  source_exception_id: string | null
  recorded_at: string
  recorded_by: string
}

/** The row open on `day`, if any. A pending row is never current. */
export function currentAssignment(rows: RateAssignment[], day: string): RateAssignment | null {
  return (
    rows.find((r) => !r.pending && r.start_date <= day && (r.end_date === null || r.end_date >= day)) ?? null
  )
}

/** Newest start first, which is how the history reads. */
export function byStartDesc(rows: RateAssignment[]): RateAssignment[] {
  return [...rows].sort((a, b) => (a.start_date < b.start_date ? 1 : a.start_date > b.start_date ? -1 : 0))
}

/**
 * Why a new row starting on `start` can't be added, or null when it can.
 *
 * The only row a new one may close is the standing (open-ended) row, and only
 * if the new row starts after it does. Any closed row the new start falls
 * inside, and any row that starts on or after it, would overlap.
 */
export function overlapProblem(rows: RateAssignment[], start: string): string | null {
  const waiting = rows.find((r) => r.pending)
  if (waiting)
    return `A change to ${waiting.schedule_code} from ${date(waiting.start_date)} is waiting on supervisor approval. Nothing else can be added until it is decided.`
  for (const r of rows) {
    if (r.start_date >= start)
      return `Overlaps ${r.schedule_code}${r.pending ? ' (pending)' : ''}, which starts ${date(r.start_date)}. A new row must start after every row already on the account.`
    if (r.end_date !== null && r.end_date >= start)
      return `Overlaps ${r.schedule_code}, which runs to ${date(r.end_date)}. Start on or after ${date(addCalendarDays(r.end_date, 1))}.`
  }
  return null
}

/** The open row a new row starting on `start` closes, and the end date the close writes. */
export function closeFor(rows: RateAssignment[], start: string): { id: string; end_date: string } | null {
  const open = rows.find((r) => r.end_date === null && !r.pending && r.start_date < start)
  return open ? { id: open.id, end_date: addCalendarDays(start, -1) } : null
}

/**
 * The end date a pending successor would write on this row if approved. A
 * pending row closes nothing yet, so the standing row stays current until
 * the change is decided.
 */
export function pendingEnd(rows: RateAssignment[], row: RateAssignment): { end_date: string; successor: RateAssignment } | null {
  if (row.pending || row.end_date !== null) return null
  const successor = rows.find((r) => r.pending && r.start_date > row.start_date)
  return successor ? { end_date: addCalendarDays(successor.start_date, -1), successor } : null
}
