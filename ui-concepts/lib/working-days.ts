/**
 * Working-day arithmetic for dunning.
 *
 * Both statutory dunning clocks — five working days past delinquency, and a
 * termination notice delivered five working days before the stated date —
 * count working days, not calendar days. Counting calendar days across a
 * holiday week makes an account eligible two days early, which is the
 * failure this module exists to prevent.
 *
 * The calendar is Texas state and national holidays. Whether partial-staffing
 * state holidays count, and whether a tenant may add local closures, is still
 * with the domain expert; the settings page says so.
 */

export type Holiday = { date: string; name: string; kind: 'national' | 'state' }

export const HOLIDAYS_2026: Holiday[] = [
  { date: '2026-01-01', name: 'New Year’s Day', kind: 'national' },
  { date: '2026-01-19', name: 'Martin Luther King Jr. Day', kind: 'national' },
  { date: '2026-02-16', name: 'Presidents’ Day', kind: 'national' },
  { date: '2026-03-02', name: 'Texas Independence Day', kind: 'state' },
  { date: '2026-04-21', name: 'San Jacinto Day', kind: 'state' },
  { date: '2026-05-25', name: 'Memorial Day', kind: 'national' },
  { date: '2026-06-19', name: 'Emancipation Day', kind: 'state' },
  { date: '2026-07-04', name: 'Independence Day', kind: 'national' },
  { date: '2026-08-27', name: 'Lyndon Baines Johnson Day', kind: 'state' },
  { date: '2026-09-07', name: 'Labor Day', kind: 'national' },
  { date: '2026-11-11', name: 'Veterans Day', kind: 'national' },
  { date: '2026-11-26', name: 'Thanksgiving Day', kind: 'national' },
  { date: '2026-11-27', name: 'Day after Thanksgiving', kind: 'state' },
  { date: '2026-12-24', name: 'Christmas Eve', kind: 'state' },
  { date: '2026-12-25', name: 'Christmas Day', kind: 'national' },
  { date: '2026-12-26', name: 'Day after Christmas', kind: 'state' },
]

const HOLIDAY = new Map(HOLIDAYS_2026.map((h) => [h.date, h]))

const toDate = (iso: string) => new Date(`${iso.slice(0, 10)}T00:00:00Z`)
const toIso = (d: Date) => d.toISOString().slice(0, 10)

export function addCalendarDays(iso: string, n: number): string {
  const d = toDate(iso)
  d.setUTCDate(d.getUTCDate() + n)
  return toIso(d)
}

export const weekday = (iso: string) =>
  toDate(iso).toLocaleDateString('en-US', { weekday: 'short', timeZone: 'UTC' })

export const holidayOn = (iso: string) => HOLIDAY.get(iso) ?? null

export function isWorkingDay(iso: string): boolean {
  const dow = toDate(iso).getUTCDay()
  return dow !== 0 && dow !== 6 && !HOLIDAY.has(iso)
}

/** The date `n` working days after `iso`. Zero returns `iso` itself. */
export function addWorkingDays(iso: string, n: number): string {
  let d = iso
  let left = n
  while (left > 0) {
    d = addCalendarDays(d, 1)
    if (isWorkingDay(d)) left--
  }
  return d
}

/**
 * Service may not be disconnected on a weekend or holiday, or on the day
 * before either — nobody would be in the office to take the payment that
 * restores it.
 */
export function disconnectAllowedOn(iso: string): boolean {
  return isWorkingDay(iso) && isWorkingDay(addCalendarDays(iso, 1))
}

/** The first date on or after `iso` a disconnect may happen. */
export function nextDisconnectDay(iso: string): string {
  let d = iso
  while (!disconnectAllowedOn(d)) d = addCalendarDays(d, 1)
  return d
}

/** Why a date is not a disconnect day, for the preview. */
export function disconnectBlockedBecause(iso: string): string | null {
  if (!isWorkingDay(iso)) return HOLIDAY.get(iso)?.name ?? 'Weekend'
  const next = addCalendarDays(iso, 1)
  if (!isWorkingDay(next)) return `Day before ${HOLIDAY.get(next)?.name ?? 'the weekend'}`
  return null
}
