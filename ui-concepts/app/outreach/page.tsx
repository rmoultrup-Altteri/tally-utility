import Link from 'next/link'
import type { Route } from 'next'
import { AppShell, PageHeader } from '@/components/shell/AppShell'
import { OutreachBoard } from '@/components/outreach/OutreachBoard'
import { cycle } from '@/fixtures/tenant'
import { currentRun } from '@/fixtures/billing'
import { date } from '@/lib/format'

/**
 * High-bill outreach — tell the customer before the bill does.
 *
 * Every utility knows which bills jumped before it mails them; the pre-mail
 * queue flags them. What none of them do is pick up the phone first. This
 * board turns that list into a heads-up with the real reason in it, sent from
 * the same template library and explained by the same engine the customer
 * will see in the portal when the bill arrives.
 */

export default async function OutreachPage({ searchParams }: PageProps<'/outreach'>) {
  const params = await searchParams
  const account = typeof params.account === 'string' ? params.account : undefined

  return (
    <AppShell current="High-bill outreach">
      <PageHeader
        title="High-bill outreach"
        meta={
          <>
            {cycle.label} · {cycle.periodLabel} · run {currentRun.run_number} · bills dated {date(cycle.billDate)} ·{' '}
            <Link href={'/communications/high-bill-heads-up' as Route} className="underline hover:text-ink-secondary">
              Message template
            </Link>{' '}
            ·{' '}
            <Link href={'/settings/billing' as Route} className="underline hover:text-ink-secondary">
              Threshold
            </Link>
          </>
        }
      />
      <OutreachBoard initialId={account ? `out-${account}` : undefined} />
    </AppShell>
  )
}
