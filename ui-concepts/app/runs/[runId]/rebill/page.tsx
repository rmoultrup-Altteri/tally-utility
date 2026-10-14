import Link from 'next/link'
import { notFound } from 'next/navigation'
import { AppShell, PageHeader } from '@/components/shell/AppShell'
import { Button } from '@/components/ui/Panel'
import { BatchRebill } from '@/components/runs/BatchRebill'
import { currentRun, runs } from '@/fixtures/billing'
import { humanize } from '@/components/ui/State'
import { count } from '@/lib/format'

/**
 * Void and rebill a whole run.
 *
 * The button lives on the run, because "this run used the wrong rate" is a
 * statement about the run, and correcting it one bill at a time would mean
 * thousands of identical elections. The form is the single-bill election at
 * run scale; see `lib/run-corrections.ts`.
 */

export function generateStaticParams() {
  return runs.map((r) => ({ runId: r.id }))
}

export default async function RunRebillPage({ params }: PageProps<'/runs/[runId]/rebill'>) {
  const { runId } = await params
  const run = runs.find((r) => r.id === runId)
  if (!run) notFound()

  return (
    <AppShell current={run.id === currentRun.id ? 'Billing run' : 'Run history'}>
      <PageHeader
        back={{ href: `/runs/${run.id}`, label: 'the run' }}
        title="Void and rebill run"
        meta={
          <>
            <span className="ident">{run.run_number}</span> · {humanize(run.run_type)} · {run.billing_period} ·{' '}
            {count(run.total_invoices)} bills
          </>
        }
        actions={
          <Link href={`/runs/${run.id}`}>
            <Button variant="quiet">Cancel</Button>
          </Link>
        }
      />
      <div className="flex-1 overflow-auto">
        <BatchRebill runId={run.id} />
      </div>
    </AppShell>
  )
}
