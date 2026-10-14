'use client'

import { useMemo, useState, type ReactNode } from 'react'
import Link from 'next/link'
import type { Route } from 'next'
import { ColumnTable, type ColumnDef, type ColumnRow } from '@/components/table/Columns'
import { Chip, Group } from '@/components/ui/Chip'
import { Panel } from '@/components/ui/Panel'
import { Rail, StateFlag, humanize, runTone } from '@/components/ui/State'
import { Money } from '@/components/ui/Money'
import { fieldClass } from '@/components/ui/Dialog'
import { runs } from '@/fixtures/billing'
import { useAccess } from '@/lib/access'
import { count, date, stamp } from '@/lib/format'
import { openFor, openReason, useBatchCorrections, type BatchCorrection } from '@/lib/run-corrections-store'
import { requestTone } from '@/components/runs/RunCorrections'

/**
 * The run history list.
 *
 * Fixture runs and the batch corrections requested in this browser share one
 * table, because to an auditor a queued correction run is a run: it has a
 * number, a period, bills and a status. Withdrawn requests stay listed,
 * struck. Each posted run has its Void and rebill one click from the row.
 */

export type RunRow = {
  id: string
  number: string
  period: string
  periodStart: string
  periodEnd: string
  type: string
  isDryRun: boolean
  status: string
  bills: number
  amount: string
  exceptions: number
  estimated: number
  startedAt: string | null
  approvedAt: string | null
  postedAt: string | null
  validAt: string
  recordedAt: string
  corrects: { id: string; number: string }[]
  correctedBy: { id: string; number: string; bills: number }[]
  eligible: boolean
  eligibilityReason: string
}

const COLUMNS: ColumnDef[] = [
  { key: 'rail', label: '', menuLabel: 'Status rail', width: '3px', rail: true, fixed: true },
  { key: 'run', label: 'Run' },
  { key: 'period', label: 'Period' },
  { key: 'type', label: 'Type' },
  { key: 'status', label: 'Status' },
  { key: 'bills', label: 'Bills', align: 'right' },
  { key: 'amount', label: 'Billed amount', align: 'right' },
  { key: 'lineage', label: 'Corrections', cellClassName: 'max-w-72' },
  { key: 'started', label: 'Started', hidden: true },
  { key: 'posted', label: 'Posted' },
  { key: 'action', label: '', menuLabel: 'Void and rebill', align: 'right' },
  { key: 'exceptions', label: 'Exceptions', align: 'right', hidden: true },
  { key: 'estimated', label: 'Est. reads', menuLabel: 'Estimated reads', align: 'right', hidden: true },
  { key: 'approved', label: 'Approved', hidden: true },
  { key: 'validAt', label: 'Valid at', hidden: true },
  { key: 'recordedAt', label: 'Recorded at', hidden: true },
]

type Item = {
  key: string
  sortAt: string
  type: string
  status: string
  corrected: boolean
  text: string
  cells: Record<string, ReactNode>
}

const TYPES = ['regular', 'correction', 'off_cycle', 'final', 'dry_run'] as const
const STATUSES = ['posted', 'review', 'in_progress', 'awaiting_approval', 'approved', 'withdrawn', 'failed', 'cancelled'] as const

const link = 'text-accent-text hover:text-accent-text-hover underline'

export function RunHistory({ rows }: { rows: RunRow[] }) {
  const access = useAccess()
  const requests = useBatchCorrections()
  const [types, setTypes] = useState<string[]>([])
  const [statuses, setStatuses] = useState<string[]>([])
  const [correctedOnly, setCorrectedOnly] = useState(false)
  const [q, setQ] = useState('')

  const items = useMemo<Item[]>(() => {
    const requestsFor = (runId: string) => requests.filter((r) => r.targetRunId === runId && r.status !== 'withdrawn')
    const fromRuns = rows.map((r): Item => {
      const tone = runTone(r.status, r.isDryRun)
      const pending = requestsFor(r.id)
      const blockedBy = openFor(requests, r.id)[0]
      const canVoid = r.eligible && access.can('invoice.void') && !blockedBy
      return {
        key: r.id,
        sortAt: r.startedAt ?? r.recordedAt,
        type: r.type,
        status: r.status,
        corrected: r.correctedBy.length + pending.length > 0,
        text: `${r.number} ${r.period}`.toLowerCase(),
        cells: {
          rail: <Rail tone={tone} />,
          run: (
            <Link href={`/runs/${r.id}` as Route} className={`ident whitespace-nowrap ${link}`}>
              {r.number}
            </Link>
          ),
          period: (
            <span className="whitespace-nowrap">
              {r.period} <span className="text-micro text-ink-tertiary">· {date(r.periodStart)} → {date(r.periodEnd)}</span>
            </span>
          ),
          type: humanize(r.type),
          status: <StateFlag tone={tone}>{humanize(r.status)}</StateFlag>,
          bills: <span className="figures">{count(r.bills)}</span>,
          amount: <Money value={r.amount} />,
          lineage: (
            <span className="text-micro text-ink-secondary">
              {[
                ...r.corrects.map((c) => (
                  <span key={`c-${c.id}`}>
                    Corrects{' '}
                    <Link href={`/runs/${c.id}` as Route} className={`ident whitespace-nowrap ${link}`}>
                      {c.number}
                    </Link>
                  </span>
                )),
                ...r.correctedBy.map((c) => (
                  <span key={`b-${c.id}`}>
                    {c.bills} bill{c.bills === 1 ? '' : 's'} replaced on{' '}
                    <Link href={`/runs/${c.id}` as Route} className={`ident whitespace-nowrap ${link}`}>
                      {c.number}
                    </Link>
                  </span>
                )),
                ...pending.map((p) => (
                  <span key={`p-${p.id}`}>
                    <Link href={`/runs/${r.id}#corrections` as Route} className={`ident whitespace-nowrap ${link}`}>
                      {p.runNumber}
                    </Link>{' '}
                    {humanize(p.status).toLowerCase()}
                  </span>
                )),
              ].flatMap((el, i) => (i ? [<span key={`sep-${i}`}> · </span>, el] : [el]))}
            </span>
          ),
          started: <span className="text-micro text-ink-secondary whitespace-nowrap">{stamp(r.startedAt)}</span>,
          posted: <span className="text-micro text-ink-secondary whitespace-nowrap">{r.postedAt ? stamp(r.postedAt) : '—'}</span>,
          action: r.eligible ? (
            canVoid ? (
              <Link href={`/runs/${r.id}/rebill` as Route} className={`text-micro whitespace-nowrap ${link}`}>
                Void and rebill
              </Link>
            ) : (
              <span
                className="text-micro text-ink-tertiary whitespace-nowrap"
                title={blockedBy ? openReason(blockedBy) : 'Needs the Void bills capability'}
              >
                {blockedBy ? humanize(blockedBy.status) : 'Void and rebill'}
              </span>
            )
          ) : null,
          exceptions: <span className="figures">{count(r.exceptions)}</span>,
          estimated: <span className="figures">{count(r.estimated)}</span>,
          approved: <span className="text-micro text-ink-secondary whitespace-nowrap">{r.approvedAt ? stamp(r.approvedAt) : '—'}</span>,
          validAt: <span className="text-micro whitespace-nowrap">{date(r.validAt)}</span>,
          recordedAt: <span className="text-micro whitespace-nowrap">{stamp(r.recordedAt)}</span>,
        },
      }
    })
    const fromRequests = requests.map((c): Item => requestItem(c))
    return [...fromRuns, ...fromRequests].sort((a, b) => Date.parse(b.sortAt) - Date.parse(a.sortAt))
  }, [rows, requests, access])

  const filtered = items.filter(
    (i) =>
      (!types.length || types.includes(i.type)) &&
      (!statuses.length || statuses.includes(i.status)) &&
      (!correctedOnly || i.corrected) &&
      (!q.trim() || i.text.includes(q.trim().toLowerCase())),
  )
  const toggle = (xs: string[], x: string) => (xs.includes(x) ? xs.filter((y) => y !== x) : [...xs, x])
  const presentTypes = TYPES.filter((t) => items.some((i) => i.type === t))
  const presentStatuses = STATUSES.filter((s) => items.some((i) => i.status === s))
  const corrected = items.filter((i) => i.corrected).length
  const waiting = requests.filter((r) => r.status === 'awaiting_approval').length

  const tableRows: ColumnRow[] = filtered.map((i) => ({ key: i.key, cells: i.cells }))

  return (
    <div className="flex min-h-0 flex-1 flex-col px-5 py-5 gap-4">
      <p className="text-data text-ink-secondary">
        <span className="figures text-ink-primary">{items.length}</span> runs ·{' '}
        <span className="figures text-ink-primary">{corrected}</span> with corrections against them
        {waiting ? (
          <>
            {' '}
            · <span className="figures text-state-pending-text font-medium">{waiting}</span> awaiting approval
          </>
        ) : null}
      </p>
      <Panel className="flex min-h-0 flex-1 flex-col">
        <ColumnTable
          listId="runs"
          caption="Billing runs, newest first"
          columns={COLUMNS}
          rows={tableRows}
          fill
          empty="No run matches these filters"
          toolbar={
            <>
              <input
                type="search"
                value={q}
                onChange={(e) => setQ(e.target.value)}
                placeholder="Run number or period"
                aria-label="Search runs"
                className={`${fieldClass} mt-0! h-7! w-48! rounded-full!`}
              />
              <Group label="Type">
                {presentTypes.map((t) => (
                  <Chip key={t} on={types.includes(t)} onClick={() => setTypes((xs) => toggle(xs, t))}>
                    {humanize(t)}
                  </Chip>
                ))}
              </Group>
              <Group label="Status">
                {presentStatuses.map((s) => (
                  <Chip key={s} on={statuses.includes(s)} onClick={() => setStatuses((xs) => toggle(xs, s))}>
                    {humanize(s)}
                  </Chip>
                ))}
              </Group>
              <Chip on={correctedOnly} onClick={() => setCorrectedOnly((v) => !v)}>
                Corrected
              </Chip>
            </>
          }
        />
      </Panel>
    </div>
  )
}

/** A requested batch correction, as the queued correction run it is. */
function requestItem(c: BatchCorrection): Item {
  const target = runs.find((r) => r.id === c.targetRunId)
  const tone = requestTone(c.status)
  const struck = c.status === 'withdrawn'
  return {
    key: c.id,
    sortAt: c.requestedAt,
    type: 'correction',
    status: c.status,
    corrected: false,
    text: `${c.runNumber} ${target?.billing_period ?? ''}`.toLowerCase(),
    cells: {
      rail: <Rail tone={tone} />,
      run: (
        <Link href={`/runs/${c.targetRunId}#corrections` as Route} className={`ident whitespace-nowrap ${link} ${struck ? 'line-through' : ''}`}>
          {c.runNumber}
        </Link>
      ),
      period: target ? (
        <span className="whitespace-nowrap">
          {target.billing_period}{' '}
          <span className="text-micro text-ink-tertiary">
            · {date(target.period_start)} → {date(target.period_end)}
          </span>
        </span>
      ) : null,
      type: 'Correction',
      status: <StateFlag tone={tone}>{humanize(c.status)}</StateFlag>,
      bills: <span className="figures">{count(c.billCount)}</span>,
      amount: (
        <span className="text-micro text-ink-tertiary" title="A queued correction run is priced when it runs">
          Not run yet
        </span>
      ),
      lineage: target ? (
        <span className="text-micro text-ink-secondary">
          Corrects{' '}
          <Link href={`/runs/${target.id}` as Route} className={`ident whitespace-nowrap ${link}`}>
            {target.run_number}
          </Link>{' '}
          · {humanize(c.reasonCode).toLowerCase()} · {c.mode} rates
        </span>
      ) : null,
      started: (
        <span className="text-micro text-ink-secondary whitespace-nowrap" title={`Requested by ${c.requestedBy}`}>
          {stamp(c.requestedAt)}
        </span>
      ),
      posted: <span className="text-micro text-ink-secondary">—</span>,
      action: null,
      exceptions: null,
      estimated: null,
      approved: (
        <span className="text-micro text-ink-secondary whitespace-nowrap">
          {c.status === 'approved' && c.decidedAt ? stamp(c.decidedAt) : '—'}
        </span>
      ),
      validAt: null,
      recordedAt: null,
    },
  }
}
