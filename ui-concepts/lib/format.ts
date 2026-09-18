/**
 * Display formatting for billing values.
 *
 * Money in this prototype is carried as a string of exact decimal digits, never
 * as a JS number — the engine is .NET `decimal` end to end and the portal must
 * not be the place a cent goes missing. Formatting parses only at the edge,
 * for display.
 */

const USD = new Intl.NumberFormat('en-US', {
  style: 'currency',
  currency: 'USD',
  minimumFractionDigits: 2,
  maximumFractionDigits: 2,
})

/** `1234.5` -> `$1,234.50`. Negative amounts render parenthesised, accounting style. */
export function money(amount: string | number): string {
  const value = typeof amount === 'string' ? Number(amount) : amount
  if (!Number.isFinite(value)) return '—'
  const formatted = USD.format(Math.abs(value))
  return value < 0 ? `(${formatted})` : formatted
}

/** True when the amount should read as a credit / money owed back to the customer. */
export function isCredit(amount: string | number): boolean {
  const value = typeof amount === 'string' ? Number(amount) : amount
  return Number.isFinite(value) && value < 0
}

function decimals(value: string | number, places: number): string {
  const parsed = typeof value === 'string' ? Number(value) : value
  if (!Number.isFinite(parsed)) return '—'
  return parsed.toLocaleString('en-US', {
    minimumFractionDigits: places,
    maximumFractionDigits: places,
  })
}

/** Billed volume, in therms. Two decimals — tariffs bill to the hundredth. */
export const therms = (value: string | number) => `${decimals(value, 2)} th`

/** Raw metered volume, in Ccf (hundred cubic feet) as the index reads. */
export const ccf = (value: string | number) => `${decimals(value, 1)} Ccf`

/** Mcf — thousand cubic feet. Used on transport and large-commercial accounts. */
export const mcf = (value: string | number) => `${decimals(value, 3)} Mcf`

/** BTU / heating-value factor. Four decimals: the factor moves in the 4th place. */
export const factor = (value: string | number) => decimals(value, 4)

/**
 * A per-unit tariff rate at full stored precision — five decimals, trailing
 * zeros preserved. Rounding a rate for visual tidiness is how disputes start.
 * The sign leads the currency symbol, as accounting convention requires.
 */
export function rate(value: string | number): string {
  const parsed = typeof value === 'string' ? Number(value) : value
  if (!Number.isFinite(parsed)) return '—'
  const sign = parsed < 0 ? '\u2212' : ''
  return `${sign}$${decimals(Math.abs(parsed), 5)}`
}

/** A rate expressed as a percentage of a base, e.g. a franchise fee. */
export function percentRate(value: string | number): string {
  const parsed = typeof value === 'string' ? Number(value) : value
  if (!Number.isFinite(parsed)) return '—'
  return `${decimals(parsed * 100, 4)}%`
}

/**
 * Render a rate according to the unit it is quoted in. A percentage stored as
 * 0.04 must never display as $0.04000 — it is four percent, not four cents.
 */
export function rateInUnit(value: string | number, unit?: string | null): string {
  return unit === 'percent' ? percentRate(value) : rate(value)
}

/** Meter index reading — whole dial units, no decimals, no grouping. */
export function reading(value: string | number): string {
  const parsed = typeof value === 'string' ? Number(value) : value
  return Number.isFinite(parsed) ? String(Math.trunc(parsed)) : '—'
}

/** `2026-03-14` -> `Mar 14, 2026`. Parsed as a plain date, never shifted by zone. */
export function date(iso: string | null | undefined): string {
  if (!iso) return '—'
  const [y, m, d] = iso.slice(0, 10).split('-').map(Number)
  if (!y || !m || !d) return '—'
  return new Date(Date.UTC(y, m - 1, d)).toLocaleDateString('en-US', {
    month: 'short',
    day: 'numeric',
    year: 'numeric',
    timeZone: 'UTC',
  })
}

/** Short form for dense table cells: `03/14/26`. */
export function dateShort(iso: string | null | undefined): string {
  if (!iso) return '—'
  const [y, m, d] = iso.slice(0, 10).split('-')
  return y && m && d ? `${m}/${d}/${y.slice(2)}` : '—'
}

/** A timestamp the database stamped — shown to the minute, for audit reading. */
export function stamp(iso: string | null | undefined): string {
  if (!iso) return '—'
  const parsed = new Date(iso)
  if (Number.isNaN(parsed.getTime())) return '—'
  return parsed.toLocaleString('en-US', {
    month: 'short',
    day: 'numeric',
    year: 'numeric',
    hour: 'numeric',
    minute: '2-digit',
  })
}

/** `2026-01-01` + `null` -> `Jan 1, 2026 — open`. The date-effective range label. */
export function effectiveRange(from: string, to: string | null): string {
  return `${date(from)} → ${to ? date(to) : 'open'}`
}

/** Days between two plain dates, inclusive of neither end — a billing period length. */
export function days(from: string, to: string): number {
  const a = Date.parse(`${from.slice(0, 10)}T00:00:00Z`)
  const b = Date.parse(`${to.slice(0, 10)}T00:00:00Z`)
  return Number.isFinite(a) && Number.isFinite(b) ? Math.round((b - a) / 86_400_000) : 0
}

/** Heating degree days and other whole-number counts. */
export const count = (value: number) => value.toLocaleString('en-US')

/** `0.0834` -> `8.34%`. Used for variance, not for rates. */
export function percent(value: number, places = 1): string {
  return `${(value * 100).toLocaleString('en-US', {
    minimumFractionDigits: places,
    maximumFractionDigits: places,
  })}%`
}
