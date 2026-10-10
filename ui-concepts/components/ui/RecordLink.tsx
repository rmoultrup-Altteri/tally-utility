import Link from 'next/link'
import type { Route } from 'next'
import { customers, meters } from '@/fixtures/accounts'

/**
 * An account or meter number, wherever it appears, opens that record.
 *
 * Resolved by number rather than trusted from the caller, because most
 * screens carry the number as text — a report row, an audit entry, a
 * collections line. A number with no record behind it (portfolio accounts the
 * prototype does not model, an import kept in this browser) renders as plain
 * text, never as a link to a page that would not exist.
 */

const customerIdByNumber = new Map(customers.map((c) => [c.customer_number, c.id]))
const meterIdByNumber = new Map(meters.map((m) => [m.meter_number, m.id]))

const LINK = 'ident text-accent-text underline-offset-2 hover:text-accent-text-hover hover:underline'

export function AccountNumber({
  number,
  id,
  className = '',
  plainClassName = '',
}: {
  number: string
  /** The customer id, when the caller already has it. */
  id?: string
  className?: string
  /** Ink for a number with no record behind it, which shows as text. */
  plainClassName?: string
}) {
  const target = id && customers.some((c) => c.id === id) ? id : customerIdByNumber.get(number)
  if (!target) return <span className={`ident ${className} ${plainClassName}`}>{number}</span>
  return (
    <Link href={`/customers/${target}` as Route} className={`${LINK} ${className}`} title="Open account">
      {number}
    </Link>
  )
}

export function MeterNumber({
  number,
  id,
  className = '',
  plainClassName = '',
}: {
  number: string
  /** The meter id, when the caller already has it. */
  id?: string
  className?: string
  /** Ink for a number with no record behind it, which shows as text. */
  plainClassName?: string
}) {
  const target = id && meters.some((m) => m.id === id) ? id : meterIdByNumber.get(number)
  if (!target) return <span className={`ident ${className} ${plainClassName}`}>{number}</span>
  return (
    <Link href={`/meters/${target}` as Route} className={`${LINK} ${className}`} title="Open meter">
      {number}
    </Link>
  )
}
