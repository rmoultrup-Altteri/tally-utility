'use client'

import Link from 'next/link'
import type { Route } from 'next'
import { useRecords } from '@/lib/records'

/**
 * An account or meter number, wherever it appears, opens that record.
 *
 * Resolved by number rather than trusted from the caller, because most
 * screens carry the number as text — a report row, an audit entry, a
 * collections line. A number with no record behind it (portfolio accounts the
 * prototype does not model) renders as plain text, never as a link to a page
 * that would not exist. Records added in this browser have pages, so their
 * numbers link once the browser's store is read.
 */

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
  const { customerById, customerIdByNumber } = useRecords()
  const target = id && customerById.has(id) ? id : customerIdByNumber.get(number)
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
  const { meterById, meterIdByNumber } = useRecords()
  const target = id && meterById.has(id) ? id : meterIdByNumber.get(number)
  if (!target) return <span className={`ident ${className} ${plainClassName}`}>{number}</span>
  return (
    <Link href={`/meters/${target}` as Route} className={`${LINK} ${className}`} title="Open meter">
      {number}
    </Link>
  )
}
