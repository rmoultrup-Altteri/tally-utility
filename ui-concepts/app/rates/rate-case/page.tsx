import Link from 'next/link'
import type { Route } from 'next'
import { AppShell, PageHeader } from '@/components/shell/AppShell'
import { RateCaseToolkit } from '@/components/rate-case/RateCaseToolkit'
import { rateCase } from '@/fixtures/rate-case'

/**
 * Rate case toolkit.
 *
 * Replaces the tariff sandbox. The sandbox answered "what does this rate do to
 * one cycle of customers"; a rate case needs the whole chain — requirement,
 * allocation, a design that proves its revenue against a year of real
 * volumes, typical bills, the filing schedules and the customer notice — and
 * then the new rates posted as versions, without a consultant in the middle.
 */

export default function RateCasePage() {
  return (
    <AppShell current="Rate case toolkit">
      <PageHeader
        title="Rate case toolkit"
        meta={
          <>
            <span className="ident">{rateCase.docket}</span> ·{' '}
            <Link href={'/rates' as Route} className="underline hover:text-ink-secondary">
              Rate versions
            </Link>{' '}
            ·{' '}
            <Link href={'/rates/pga' as Route} className="underline hover:text-ink-secondary">
              PGA console
            </Link>{' '}
            ·{' '}
            <Link href={'/communications/rate-change-notice' as Route} className="underline hover:text-ink-secondary">
              Customer notice
            </Link>
          </>
        }
      />
      <div className="flex-1 overflow-auto">
        <div className="px-5 py-5">
          <RateCaseToolkit />
        </div>
      </div>
    </AppShell>
  )
}
