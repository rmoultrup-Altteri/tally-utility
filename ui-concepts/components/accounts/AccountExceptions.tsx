'use client'

import Link from 'next/link'
import { Panel, PanelHeader } from '@/components/ui/Panel'
import { StateFlag, severityTone } from '@/components/ui/State'
import { ProposeReclassification } from '@/components/accounts/RateSchedule'
import { useDeceased } from '@/lib/deceased-store'
import { reviewException } from '@/lib/deceased'
import { byConsequence, exceptions } from '@/fixtures/exceptions'
import { serviceLinks } from '@/fixtures/accounts'
import { asOf } from '@/fixtures/tenant'
import type { Exception } from '@/schemas/models'
import { date } from '@/lib/format'

/**
 * The account's open exceptions.
 *
 * The deceased-account review is worked out here from the account's steps
 * rather than read from the fixture, so a proof or note recorded on this page
 * takes it off at once, and a change-over resolves it.
 */
export function AccountExceptions({ customerId }: { customerId: string }) {
  const state = useDeceased(customerId)
  const fixed = exceptions.filter((e) => e.customer_id === customerId && e.status !== 'resolved')
  const review = state
    ? reviewException(state, asOf.validAt, {
        id: fixed.find((e) => e.anomaly_type === 'deceased_account_review')?.id ?? `exc-review-${customerId}`,
        meterId: serviceLinks.find((l) => l.customerId === customerId)?.meterId ?? null,
      })
    : null
  const open: Exception[] = byConsequence([
    ...fixed.filter((e) => e.anomaly_type !== 'deceased_account_review'),
    ...(review ? [review] : []),
  ])
  if (open.length === 0) return null

  return (
    <Panel>
      <PanelHeader title="Open exceptions" meta={`${open.length} on this account`} />
      <ul className="divide-y divide-rule-hair">
        {open.map((e) => (
          <li key={e.id} className="px-4 py-2.5">
            <div className="flex items-baseline gap-3">
              <StateFlag tone={severityTone(e.severity, e.status)}>{e.severity}</StateFlag>
              <span className="text-data text-ink-primary">{e.description}</span>
              <Link href="/" className="ml-auto text-micro text-accent-text underline">
                Open in queue
              </Link>
            </div>
            {e.anomaly_type === 'rate_schedule_mismatch' ? (
              <div className="mt-2 pl-1">
                <ProposeReclassification exception={e} />
              </div>
            ) : null}
            {e.anomaly_type === 'deceased_account_review' ? (
              <p className="mt-1 text-micro text-ink-secondary">
                No update since {date(String(e.details.last_update))}. Record a proof or a note below to restart the clock.
              </p>
            ) : null}
          </li>
        ))}
      </ul>
    </Panel>
  )
}
