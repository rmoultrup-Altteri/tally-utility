import { customers } from '@/fixtures/accounts'
import type { RateAssignment } from '@/lib/rate-assignments'

/**
 * Each account's rate schedule assignments, as the fixtures already know them.
 *
 * One standing row per account, from the move-in date. The schedule is the
 * one every bill on the account was priced on: residential accounts bill on
 * R-1 and every other class on G-1, in `billing.ts` and `bill-history.ts`
 * alike. Nothing here is older or different from what the bills show, so no
 * history is invented that a bill would contradict.
 *
 * Two of these read oddly and are left as the bills have them: Brazos Linen
 * (large commercial) and the school district (government) bill on G-1, the
 * small-commercial schedule, not G-2.
 */
export const seedRateAssignments: RateAssignment[] = customers.map((c) => ({
  id: `ra-${c.id.slice(4)}-1`,
  customer_id: c.id,
  schedule_code: c.customer_type === 'residential' ? 'R-1' : 'G-1',
  start_date: c.move_in_date ?? c.created_at.slice(0, 10),
  end_date: null,
  reason: 'Service started on the schedule for the customer class',
  pending: false,
  source_exception_id: null,
  recorded_at: c.created_at,
  recorded_by: 'Account opening',
}))
