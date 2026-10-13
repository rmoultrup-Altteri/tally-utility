import type { ReactNode } from 'react'
import Link from 'next/link'
import { notFound } from 'next/navigation'
import { AppShell, PageHeader } from '@/components/shell/AppShell'
import { Button, Field, FieldGrid, Panel, PanelHeader } from '@/components/ui/Panel'
import { Rail, StateBlock, StateFlag, runTone, humanize } from '@/components/ui/State'
import { Money } from '@/components/ui/Money'
import { ColumnTable, type ColumnDef } from '@/components/table/Columns'
import { runs, currentRun, invoices, invoiceById } from '@/fixtures/billing'
import { blockingCount, openExceptions } from '@/fixtures/exceptions'
import { customerById } from '@/fixtures/accounts'
import { customerName } from '@/schemas/models'
import type { Invoice } from '@/schemas/models'
import { count, date, dateShort, stamp } from '@/lib/format'

/**
 * The billing run cockpit.
 *
 * A run is a pipeline with a gate at the end: it cannot post while anything
 * that blocks delivery is open. The gate is stated as a sentence rather than
 * implied by a greyed-out button, because "why can't I post?" is the question
 * this screen exists to answer.
 *
 * A dry run is marked by colour AND a hatch. Mistaking a rehearsal for a posted
 * run is the most expensive error available here.
 */

export function generateStaticParams() {
  return runs.map((r) => ({ runId: r.id }))
}

const STAGES = [
  { key: 'reads', label: 'Reads released', done: true },
  { key: 'usage', label: 'Usage calculated', done: true },
  { key: 'correction', label: 'BTU + pressure correction', done: true },
  { key: 'rating', label: 'Rates applied', done: true },
  { key: 'wna', label: 'WNA applied', done: true },
  { key: 'tax', label: 'Taxes and franchise fees', done: true },
  { key: 'audit', label: 'Pre-mail audit', done: false },
  { key: 'post', label: 'Post and deliver', done: false },
]

/** The bills table: the shipped seven after the rail, then more of each bill's arithmetic. */
const COLUMNS: ColumnDef[] = [
  { key: 'rail', label: '', menuLabel: 'Status rail', width: '3px', rail: true, fixed: true },
  { key: 'invoice', label: 'Invoice' },
  { key: 'account', label: 'Account' },
  { key: 'charges', label: 'Charges', align: 'right' },
  { key: 'taxes', label: 'Taxes', align: 'right' },
  { key: 'due', label: 'Amount due', align: 'right' },
  { key: 'status', label: 'Status' },
  { key: 'note', label: 'Note', cellClassName: 'max-w-72' },
  { key: 'previous', label: 'Previous balance', align: 'right', hidden: true },
  { key: 'credits', label: 'Credits', align: 'right', hidden: true },
  { key: 'dueDate', label: 'Due date', hidden: true },
  { key: 'estimated', label: 'Est. reads', menuLabel: 'Estimated reads', align: 'right', hidden: true },
]

/** One bill's cells, rendered here on the server and arranged by `ColumnTable`. */
function invoiceCells(inv: Invoice): Record<string, ReactNode> {
  const customer = customerById.get(inv.customer_id)
  const invTone = inv.held_at ? 'held' : runTone(inv.status, false)
  return {
    rail: <Rail tone={invTone} />,
    invoice: (
      <Link href={`/invoices/${inv.id}`} className="ident text-accent-text hover:text-accent-text-hover underline">
        {inv.invoice_number}
      </Link>
    ),
    account: customer ? customerName(customer) : '—',
    charges: <Money value={inv.total_charges} />,
    taxes: <Money value={inv.total_taxes} />,
    due: <Money value={inv.amount_due} />,
    status: <StateFlag tone={invTone}>{humanize(inv.status)}</StateFlag>,
    note: <span className="text-micro text-ink-secondary">{inv.hold_reason ?? ''}</span>,
    previous: <Money value={inv.previous_balance} />,
    credits: <Money value={inv.total_credits} />,
    dueDate: <span className="text-micro text-ink-secondary whitespace-nowrap">{dateShort(inv.due_date)}</span>,
    estimated: (
      <span className={`figures ${inv.estimated_read_count > 0 ? 'text-exception-warning-text' : 'text-ink-tertiary'}`}>
        {inv.estimated_read_count}
      </span>
    ),
  }
}

export default async function RunPage({ params }: PageProps<'/runs/[runId]'>) {
  const { runId } = await params
  const run = runs.find((r) => r.id === runId)
  if (!run) notFound()

  const tone = runTone(run.status, run.is_dry_run)
  const runInvoices = invoices.filter((i) => i.billing_run_id === run.id)

  return (
    <AppShell current="Billing run">
      <PageHeader
        title={<span className="ident text-h1">{run.run_number}</span>}
        meta={
          <>
            {humanize(run.run_type)} · {run.billing_period} · {date(run.period_start)} →{' '}
            {date(run.period_end)}
          </>
        }
        actions={
          <>
            <StateFlag tone={tone}>{humanize(run.status)}</StateFlag>
            <Button>Export</Button>
            <Button
              variant="primary"
              disabled={blockingCount > 0}
              title={
                blockingCount > 0
                  ? `${blockingCount} exceptions block delivery`
                  : 'Post this run'
              }
            >
              Post run
            </Button>
          </>
        }
      />

      {run.is_dry_run ? (
        <div className="hatch-dryrun border-b border-state-dryrun-rail">
          <div className="bg-state-dryrun-wash/90 px-5 py-2.5">
            <p className="text-data text-state-dryrun-text font-medium">
              Dry run — nothing here is real. No invoice is created, no ledger entry is written, and
              no customer is billed. This is a rehearsal against {count(run.total_locations)} live
              accounts.
            </p>
          </div>
        </div>
      ) : null}

      <div className="flex-1 overflow-auto">
        <div className="px-5 py-5 space-y-5">
          <div className="grid grid-cols-2 md:grid-cols-5 gap-px overflow-clip rounded-md bg-rule-hair border border-rule-hair shadow-panel">
            <Stat label="Accounts" value={count(run.total_locations)} />
            <Stat label="Bills" value={count(run.total_invoices)} />
            <Stat label="Billed amount" value={<Money value={run.total_amount} />} />
            <Stat
              label="Exceptions"
              value={count(run.total_exceptions)}
              tone={run.total_exceptions > 0 ? 'critical' : undefined}
            />
            <Stat
              label="Estimated reads"
              value={count(run.total_estimated_reads)}
              tone={run.total_estimated_reads > 0 ? 'warning' : undefined}
            />
          </div>

          <Panel>
            <PanelHeader title="Pipeline" meta={`Started ${stamp(run.started_at)}`} />
            <ol className="divide-y divide-rule-hair">
              {STAGES.map((s, i) => (
                <li key={s.key} className="flex items-center gap-3 px-4 py-2.5">
                  <span
                    className={`ident flex h-5 w-5 shrink-0 items-center justify-center rounded-sm ${
                      s.done
                        ? 'bg-exception-cleared-wash text-exception-cleared-text'
                        : 'bg-surface-inset text-ink-tertiary'
                    }`}
                  >
                    {s.done ? '✓' : i + 1}
                  </span>
                  <span
                    className={`text-data ${s.done ? 'text-ink-primary' : 'text-ink-tertiary'}`}
                  >
                    {s.label}
                  </span>
                  {s.key === 'audit' ? (
                    <span className="ml-auto text-micro text-exception-critical-text">
                      {blockingCount} blocking · {openExceptions.length} open
                    </span>
                  ) : null}
                </li>
              ))}
            </ol>
          </Panel>

          {blockingCount > 0 && !run.is_dry_run ? (
            <StateBlock tone="critical">
              <p className="text-data text-ink-primary">
                <strong className="font-semibold">This run cannot post.</strong>{' '}
                {blockingCount} exceptions block delivery. Bills on those accounts cannot reach{' '}
                <em>pending</em> or <em>sent</em> until each is resolved.{' '}
                <Link href="/" className="text-accent-text hover:text-accent-text-hover underline">
                  Work the queue
                </Link>
                .
              </p>
            </StateBlock>
          ) : null}

          {/* The coordinate this run resolved once and reused everywhere. */}
          <Panel>
            <PanelHeader
              title="Pricing coordinate"
              meta="Resolved once per run, passed to every rate lookup"
            />
            <div className="px-4 py-4">
              <FieldGrid cols={4}>
                <Field label="Valid at" hint="the world the bills describe">
                  {date(run.valid_at)}
                </Field>
                <Field label="Recorded at" hint="what the database knew then">
                  {stamp(run.recorded_at)}
                </Field>
                <Field label="Correction rate mode">{humanize(run.correction_rate_mode)}</Field>
                <Field label="Generation">Manual</Field>
              </FieldGrid>
              <p className="text-micro text-ink-tertiary mt-3">
                Every bill this run produced can be reproduced exactly from this pair, because no
                lookup it made was allowed to fall back to a current value.
              </p>
            </div>
          </Panel>

          {runInvoices.length > 0 ? (
            <Panel>
              <PanelHeader title="Bills in this run" meta={`${runInvoices.length} shown`} />
              <ColumnTable
                listId="run"
                caption="Invoices produced by this billing run"
                columns={COLUMNS}
                rows={runInvoices.map((inv) => ({ key: inv.id, cells: invoiceCells(inv) }))}
              />
            </Panel>
          ) : null}
        </div>
      </div>
    </AppShell>
  )
}

function Stat({
  label,
  value,
  tone,
}: {
  label: string
  value: React.ReactNode
  tone?: 'critical' | 'warning'
}) {
  const color =
    tone === 'critical'
      ? 'text-exception-critical-text'
      : tone === 'warning'
        ? 'text-exception-warning-text'
        : 'text-ink-primary'
  return (
    <div className="bg-surface-raised px-4 py-3">
      <p className="field-label">{label}</p>
      <p className={`text-figure mt-1 ${color}`}>{value}</p>
    </div>
  )
}
