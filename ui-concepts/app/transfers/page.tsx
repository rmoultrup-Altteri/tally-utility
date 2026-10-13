import Link from 'next/link'
import type { Route } from 'next'
import { AppShell, PageHeader } from '@/components/shell/AppShell'
import { WorkTabs } from '@/components/queue/WorkTabs'
import { TransfersBoard } from '@/components/transfers/TransfersBoard'
import { HandoffsBoard } from '@/components/transfers/HandoffsBoard'
import { handoffsNeedingAttention } from '@/lib/handoffs'
import { transfersNeedingAttention } from '@/lib/transfers'

/**
 * Transfers of service — a customer moving from one premise to another
 * without closing their account. Sits beside the exception queue because a
 * stuck move is the same kind of work: something the analyst clears before a
 * bill or a field order can go out.
 *
 * A second section reconciles the other kind of move: one customer's
 * termination and a new customer's application at the same address.
 */
export default async function TransfersPage({ searchParams }: PageProps<'/transfers'>) {
  const sp = await searchParams
  const view = (Array.isArray(sp.view) ? sp.view[0] : sp.view) === 'handoffs' ? 'handoffs' : 'moves'
  const sections = [
    { key: 'moves', href: '/transfers', label: 'Customer moves', count: transfersNeedingAttention(), title: 'One customer, two premises' },
    { key: 'handoffs', href: '/transfers?view=handoffs', label: 'Move-out / move-in', count: handoffsNeedingAttention(), title: 'One premise, two customers' },
  ] as const

  return (
    <AppShell current="Transfers">
      <PageHeader
        title="Transfers of service"
        meta={
          view === 'moves'
            ? 'Stop and final bill at the old premise, turn-on at the new one — balance, deposit and arrangements stay with the customer'
            : 'A termination and a new application at the same address — one read closes one account and opens the next'
        }
        actions={
          <Link
            href={'/transfers/new' as Route}
            className="inline-flex h-8 items-center rounded-sm border border-accent bg-accent px-3.5 text-data font-medium text-ink-inverse hover:bg-accent-hover hover:border-accent-hover transition-colors duration-fast"
          >
            New transfer
          </Link>
        }
      />
      <WorkTabs current="transfers" />
      <nav aria-label="Transfers sections" className="flex items-center gap-1 border-b border-rule-hair bg-surface px-5 py-2">
        {sections.map((s) => {
          const on = s.key === view
          return (
            <Link
              key={s.key}
              href={s.href as Route}
              aria-current={on ? 'page' : undefined}
              title={s.title}
              className={`inline-flex h-7 items-center gap-2 rounded-sm px-2.5 text-data transition-colors duration-fast ${
                on ? 'bg-surface-inset text-ink-primary font-medium' : 'text-ink-secondary hover:text-ink-primary hover:bg-surface-sunken'
              }`}
            >
              {s.label}
              {s.count > 0 ? <span className="figures rounded-full bg-exception-warning-wash px-1.5 text-micro text-exception-warning-text">{s.count}</span> : null}
            </Link>
          )
        })}
      </nav>
      {view === 'moves' ? <TransfersBoard /> : <HandoffsBoard />}
    </AppShell>
  )
}
