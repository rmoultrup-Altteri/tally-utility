/**
 * The demonstration tenant.
 *
 * Brazos Valley Gas is a fictional Texas municipal gas system sitting in the
 * middle of the target band — large enough to have a billing analyst and two
 * CSRs, small enough that the same person does rate maintenance and exception
 * triage. Everything downstream is dated into its February 2026 cycle.
 */

export const tenant = {
  id: 'tnt-bvg',
  name: 'Brazos Valley Gas',
  jurisdiction: 'Railroad Commission of Texas',
  meters: 14_218,
  franchiseCities: ['Bryan', 'College Station', 'Navasota'],
} as const

export const currentUser = {
  id: 'usr-dpearce',
  name: 'Dana Pearce',
  role: 'Billing Analyst',
  initials: 'DP',
} as const

/**
 * The as-of coordinate the whole application reads through.
 *
 * `validAt` is the world the data describes; `recordedAt` is the instant the
 * database knew it. Both are explicit because every date-effective lookup in
 * the schema requires the pair and refuses to default to now() (AC-15).
 * `isToday` false must change the appearance of the entire app.
 */
export const asOf = {
  validAt: '2026-02-14',
  recordedAt: '2026-02-14T09:12:00-06:00',
  isToday: true,
} as const

/** The cycle everything on screen belongs to. */
export const cycle = {
  code: '04',
  label: 'Cycle 04',
  periodLabel: 'Feb 2026',
  periodStart: '2026-01-15',
  periodEnd: '2026-02-14',
  readWindow: '2026-02-10 → 2026-02-14',
  billDate: '2026-02-17',
  dueDate: '2026-03-09',
} as const
