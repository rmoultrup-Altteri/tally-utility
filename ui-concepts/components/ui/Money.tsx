import { money as fmtMoney, isCredit, rateInUnit, therms as fmtTherms } from '@/lib/format'
import { unitLabel } from '@/lib/vocabulary'

/**
 * Money and unit display.
 *
 * Sign is typographic — a minus or accounting parentheses — not chromatic.
 * Red already means exception here, and colour-coded sign fails a meaningful
 * share of the audience. Red appears in money only for aged arrears, and only
 * where the caller asks for it.
 */

export function Money({
  value,
  arrears = false,
  className = '',
}: {
  value: string
  arrears?: boolean
  className?: string
}) {
  const zero = Number(value) === 0
  const tone = arrears
    ? 'text-money-arrears'
    : zero
      ? 'text-money-zero'
      : isCredit(value)
        ? 'text-money-credit'
        : 'text-money'
  return <span className={`figures ${tone} ${className}`}>{fmtMoney(value)}</span>
}

/**
 * A per-unit tariff rate at full stored precision. A percentage renders as a
 * percentage — a franchise fee stored as 0.04 is four percent, not four cents.
 */
export function Rate({ value, unit }: { value: string; unit?: string | null }) {
  return (
    <span className="figures text-ink-primary">
      {rateInUnit(value, unit)}
    </span>
  )
}

/** A quantity with its unit as a tertiary suffix. */
export function Quantity({
  value,
  unit,
  className = '',
}: {
  value: string | null
  unit?: string | null
  className?: string
}) {
  if (value === null) return <Nil />
  const formatted = Number(value).toLocaleString('en-US', {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  })
  return (
    <span className={`figures ${className}`}>
      {formatted}
      {unit ? (
        <span className="text-ink-tertiary text-[0.85em]"> {unitLabel(unit)}</span>
      ) : null}
    </span>
  )
}

export function Therms({ value }: { value: string | null }) {
  if (value === null) return <Nil />
  return <span className="figures">{fmtTherms(value)}</span>
}

/**
 * No value. Deliberately distinct from a real zero — conflating "we have no
 * reading" with "the reading was zero" is a classic read-validation failure.
 */
export function Nil() {
  return (
    <span className="figures text-ink-muted" title="No value recorded">
      —
    </span>
  )
}

/**
 * A signed variance against a baseline, suppressed below the threshold so the
 * column speaks only when it has something to say.
 */
export function Variance({ pct, threshold = 5 }: { pct: string | null; threshold?: number }) {
  if (pct === null) return <Nil />
  const value = Number(pct)
  if (Math.abs(value) < threshold) {
    return <span className="figures text-ink-muted">·</span>
  }
  const up = value > 0
  return (
    <span className={`figures ${up ? 'text-exception-warning-text' : 'text-ink-secondary'}`}>
      {up ? '▲' : '▼'} {Math.abs(value).toFixed(1)}%
    </span>
  )
}
