import Link from 'next/link'
import type { Route } from 'next'
import { AppShell, PageHeader } from '@/components/shell/AppShell'
import { WorkTabs } from '@/components/queue/WorkTabs'
import { TransfersBoard } from '@/components/transfers/TransfersBoard'

/**
 * Transfers of service — a customer moving from one premise to another
 * without closing their account. Sits beside the exception queue because a
 * stuck move is the same kind of work: something the analyst clears before a
 * bill or a field order can go out.
 */
export default function TransfersPage() {
  return (
    <AppShell current="Transfers">
      <PageHeader
        title="Transfers of service"
        meta="Stop and final bill at the old premise, turn-on at the new one — balance, deposit and arrangements stay with the customer"
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
      <TransfersBoard />
    </AppShell>
  )
}
