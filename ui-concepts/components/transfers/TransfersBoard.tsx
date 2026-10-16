'use client'

import { useMemo, useState, type ReactNode } from 'react'
import Link from 'next/link'
import type { Route } from 'next'
import { Button, Field, FieldGrid } from '@/components/ui/Panel'
import { Rail, StateBlock, StateFlag, type Tone } from '@/components/ui/State'
import { Money } from '@/components/ui/Money'
import { AccountNumber, MeterNumber } from '@/components/ui/RecordLink'
import { ColumnTable, type ColumnDef } from '@/components/table/Columns'
import { TableFooter } from '@/components/table/Table'
import { transferPremiseById, transfers as recorded, type Transfer } from '@/fixtures/transfers'
import { evaluateTransfer, STATE_LABEL, transferState, type CheckLevel, type TransferCheck, type TransferState } from '@/lib/transfers'
import { useAddedTransfers } from '@/lib/transfers-store'
import { date, dateShort, money, stamp } from '@/lib/format'

/**
 * Transfers of service, worked the way the exception queue is: what is stuck
 * first, then what needs a signature, then what is simply booked. The detail
 * beside the list follows the move in the order it happens — stop and final
 * read, final bill, turn-on, then what the account carries across.
 */

const STATE_TONE: Record<TransferState, Tone> = {
  blocked: 'critical',
  needs_review: 'warning',
  scheduled: 'pending',
  completed: 'posted',
}
const STATE_ORDER: TransferState[] = ['blocked', 'needs_review', 'scheduled', 'completed']

const LEVEL_TONE: Record<CheckLevel, Tone> = { block: 'critical', review: 'warning', ok: 'cleared', info: 'info' }
const LEVEL_LABEL: Record<CheckLevel, string> = { block: 'Blocks', review: 'Review', ok: 'OK', info: 'Note' }

const COLUMNS: ColumnDef[] = [
  { key: 'rail', label: '', menuLabel: 'State rail', width: '3px', rail: true, fixed: true },
  { key: 'transfer', label: 'Transfer', width: '30%' },
  { key: 'customer', label: 'Customer', width: '20%' },
  { key: 'from', label: 'From', width: '17%' },
  { key: 'to', label: 'To', width: '17%' },
  { key: 'move', label: 'Moves', width: '9%' },
  { key: 'balance', label: 'Balance', width: '7%', align: 'right' },
  { key: 'requested', label: 'Requested', hidden: true },
  { key: 'channel', label: 'Channel', hidden: true },
]

type Evaluated = { t: Transfer; checks: TransferCheck[]; state: TransferState; added: boolean }

export function TransfersBoard() {
  const added = useAddedTransfers()
  const all = useMemo(() => [...recorded, ...added], [added])
  const rows: Evaluated[] = useMemo(
    () =>
      all
        .map((t) => {
          const checks = evaluateTransfer(t, all, false)
          return { t, checks, state: transferState(t, checks), added: !recorded.includes(t) }
        })
        .sort((a, b) => STATE_ORDER.indexOf(a.state) - STATE_ORDER.indexOf(b.state) || a.t.startDate.localeCompare(b.t.startDate)),
    [all],
  )
  const [pick, setPick] = useState<string | null>(null)
  const selected = rows.find((r) => r.t.id === pick) ?? rows[0]
  const attention = rows.filter((r) => r.state === 'blocked' || r.state === 'needs_review').length

  return (
    <>
      <div className="px-5 py-3 border-b border-rule-solid bg-surface">
        <StateBlock tone={attention ? 'warning' : 'cleared'}>
          <p className="text-data text-ink-primary">
            {attention ? (
              <>
                <strong className="font-semibold">{attention} transfers need a decision.</strong> A blocked move cannot
                complete until its rule is cleared; one in review needs a person to sign off before the field orders go
                out.
              </>
            ) : (
              <strong className="font-semibold">Every transfer is clear to proceed.</strong>
            )}
          </p>
        </StateBlock>
      </div>

      <div className="flex-1 min-h-0 overflow-auto lg:overflow-hidden grid grid-cols-1 lg:grid-cols-[minmax(0,1fr)_26rem] lg:grid-rows-[minmax(0,1fr)]">
        <section className="min-w-0 min-h-0 border-r border-rule-solid flex flex-col">
          <ColumnTable
            fill
            listId="transfers"
            caption="Transfers of service, blocked and in review first"
            columns={COLUMNS}
            rows={rows.map((r) => ({ key: r.t.id, selected: r.t.id === selected?.t.id, cells: cells(r, () => setPick(r.t.id)) }))}
            empty="No transfers on file."
            toolbar={
              <p className="flex-1 min-w-0 text-micro text-ink-secondary">
                {STATE_ORDER.map((s) => {
                  const n = rows.filter((r) => r.state === s).length
                  return n ? (
                    <span key={s} className="mr-3">
                      <strong className="text-ink-primary font-semibold">{n}</strong> {STATE_LABEL[s].toLowerCase()}
                    </span>
                  ) : null
                })}
              </p>
            }
          />
          <TableFooter shown={rows.length} total={rows.length} noun="transfers this month" />
        </section>

        {selected ? <TransferDetail row={selected} /> : null}
      </div>
    </>
  )
}

function cells(r: Evaluated, open: () => void): Record<string, ReactNode> {
  const { t, checks, state } = r
  const to = transferPremiseById.get(t.toPremiseId)
  const first = checks.find((c) => c.level === 'block') ?? checks.find((c) => c.level === 'review')
  return {
    rail: <Rail tone={STATE_TONE[state]} />,
    transfer: (
      <>
        <div className="flex items-center gap-2">
          <StateFlag tone={STATE_TONE[state]}>{STATE_LABEL[state]}</StateFlag>
          {r.added ? <span className="text-micro text-ink-tertiary">added here</span> : null}
        </div>
        <button type="button" onClick={open} className="mt-0.5 text-left text-data text-accent-text hover:text-accent-text-hover hover:underline">
          <span className="ident">{t.number}</span>
        </button>
        {first ? <p className="text-micro text-ink-secondary">{first.title}</p> : null}
      </>
    ),
    customer: (
      <>
        <p className="text-data text-ink-primary truncate">{t.mover.name}</p>
        <AccountNumber number={t.mover.accountNumber} id={t.mover.customerId} />
      </>
    ),
    from: (
      <>
        <p className="text-data text-ink-primary truncate">{t.mover.from.address}</p>
        <p className="text-micro text-ink-tertiary">{t.mover.from.city}</p>
      </>
    ),
    to: to ? (
      <>
        <p className="text-data text-ink-primary truncate">{to.address}</p>
        <p className="text-micro text-ink-tertiary">{to.city}</p>
      </>
    ) : (
      <span className="text-ink-tertiary">—</span>
    ),
    move: (
      <span className="text-micro text-ink-secondary whitespace-nowrap">
        {dateShort(t.stopDate)}
        {t.startDate !== t.stopDate ? ` → ${dateShort(t.startDate)}` : ''}
      </span>
    ),
    balance: <Money value={t.mover.balance} arrears={t.mover.pastDueDays > 0} />,
    requested: <span className="text-micro text-ink-tertiary whitespace-nowrap">{dateShort(t.requestedAt)} · {t.requestedBy}</span>,
    channel: <span className="text-micro text-ink-secondary">{t.channel === 'walk_in' ? 'Walk-in' : t.channel === 'portal' ? 'Portal' : 'Phone'}</span>,
  }
}

/** The steps a move goes through, each with what is known about it today. */
function steps(t: Transfer, checks: TransferCheck[]) {
  const to = transferPremiseById.get(t.toPremiseId)
  const blockedRead = checks.some((c) => c.code.startsWith('exception_'))
  return [
    {
      title: `Stop at ${t.mover.from.address}`,
      done: t.finalRead.takenAt !== null && !blockedRead,
      stuck: blockedRead,
      detail: t.finalRead.takenAt
        ? `Final read ${t.finalRead.reading} on ${date(t.finalRead.takenAt)}${blockedRead ? ' — in dispute' : ''}`
        : `${t.finalRead.method === 'field_read' ? 'Field read' : t.finalRead.method === 'customer_read' ? 'Customer read' : 'Meter read'} on ${date(t.stopDate)}${t.afterStop === 'lock_off' ? ', then locked off' : t.afterStop === 'owner_takes_service' ? ', owner takes service' : ''}`,
    },
    {
      title: 'Final bill',
      done: t.finalInvoice !== null,
      stuck: blockedRead,
      detail: t.finalInvoice
        ? `${t.finalInvoice.number} · ${money(t.finalInvoice.amount)} · ${t.finalBill === 'roll_forward' ? 'rolled into the next bill' : 'billed on its own'}`
        : `Priced at the final read, ${t.finalBill === 'roll_forward' ? 'and rolled into the first bill at the new service address' : 'and billed on its own'}`,
    },
    {
      title: to ? `Start at ${to.address}` : 'Start',
      done: t.turnOn.completedAt !== null || (t.completedAt !== null && to?.meterState === 'on'),
      stuck: false,
      detail: t.turnOn.completedAt
        ? `Turned on ${stamp(t.turnOn.completedAt)} by ${t.turnOn.tech}`
        : to?.meterState === 'on'
          ? `Transfer read on ${date(t.startDate)} — the meter is already on`
          : `Turn-on and relight ${date(t.startDate)}, ${t.turnOn.window === 'AM' ? '8 am – noon' : 'noon – 5 pm'}`,
    },
    {
      title: 'Account carries across',
      done: t.completedAt !== null,
      stuck: false,
      detail: `Balance ${money(t.mover.balance)}${Number(t.mover.deposit) > 0 ? ` · deposit ${money(t.mover.deposit)} ${t.keepDeposit ? 'kept' : 'refunded'}` : ''}${t.mover.arrangement ? ' · arrangement continues' : ''}`,
    },
  ]
}

function TransferDetail({ row }: { row: Evaluated }) {
  const { t, checks, state } = row
  const to = transferPremiseById.get(t.toPremiseId)
  const order: CheckLevel[] = ['block', 'review', 'ok', 'info']
  const sorted = [...checks].sort((a, b) => order.indexOf(a.level) - order.indexOf(b.level))
  const blocked = state === 'blocked'

  return (
    <aside className="min-w-0 overflow-auto bg-surface">
      <div className="px-4 py-3 border-b border-rule-solid bg-surface-raised">
        <StateFlag tone={STATE_TONE[state]}>{STATE_LABEL[state]}</StateFlag>
        <h2 className="text-h2 text-ink-primary mt-1.5">{t.mover.name}</h2>
        <p className="text-micro text-ink-tertiary mt-1">
          <span className="ident">{t.number}</span> · requested {stamp(t.requestedAt)} by {t.requestedBy}
        </p>
      </div>

      <div className="px-4 py-4 border-b border-rule-hair">
        <FieldGrid cols={2}>
          <Field label="Account">
            <AccountNumber number={t.mover.accountNumber} id={t.mover.customerId} />
          </Field>
          <Field label="Phone">{t.mover.phone}</Field>
          <Field label="From">
            {t.mover.from.address}, {t.mover.from.city}
            <span className="block text-micro text-ink-tertiary">
              Meter <MeterNumber number={t.mover.from.meterNumber} id={t.mover.from.meterId} /> · stops {date(t.stopDate)}
            </span>
          </Field>
          <Field label="To">
            {to ? (
              <>
                {to.address}, {to.city}
                <span className="block text-micro text-ink-tertiary">
                  Meter <span className="ident">{to.meterNumber}</span> · starts {date(t.startDate)}
                </span>
              </>
            ) : (
              '—'
            )}
          </Field>
        </FieldGrid>
      </div>

      <div className="px-4 py-4 border-b border-rule-hair">
        <p className="field-label mb-2">The move</p>
        <ol className="space-y-2.5">
          {steps(t, checks).map((s, i) => (
            <li key={s.title} className="flex gap-3">
              <span
                aria-hidden
                className={`mt-0.5 flex h-5 w-5 shrink-0 items-center justify-center rounded-full text-micro font-semibold ${
                  s.done ? 'bg-exception-cleared-wash text-exception-cleared-text' : s.stuck ? 'bg-exception-critical-wash text-exception-critical-text' : 'bg-surface-inset text-ink-secondary'
                }`}
              >
                {s.done ? '✓' : s.stuck ? '!' : i + 1}
              </span>
              <div className="min-w-0">
                <p className="text-data text-ink-primary">
                  {s.title}
                  <span className="sr-only">{s.done ? ' — done' : s.stuck ? ' — stuck' : ' — to do'}</span>
                </p>
                <p className="text-micro text-ink-tertiary">{s.detail}</p>
              </div>
            </li>
          ))}
        </ol>
      </div>

      <div className="px-4 py-4 border-b border-rule-hair">
        <p className="field-label mb-2">Checks</p>
        <ul className="space-y-2">
          {sorted.map((c) => (
            <li key={c.code} className="flex gap-2.5">
              <span className="w-14 shrink-0 pt-0.5">
                <StateFlag tone={LEVEL_TONE[c.level]}>{LEVEL_LABEL[c.level]}</StateFlag>
              </span>
              <div className="min-w-0">
                <p className="text-data text-ink-primary">{c.title}</p>
                <p className="text-micro text-ink-tertiary">{c.detail}</p>
              </div>
            </li>
          ))}
        </ul>
        {checks.some((c) => c.code.startsWith('exception_')) ? (
          <Link href={'/' as Route} className="mt-3 inline-block text-micro text-accent-text hover:text-accent-text-hover underline">
            Open the exception queue
          </Link>
        ) : null}
      </div>

      {t.note ? (
        <div className="px-4 py-3 border-b border-rule-hair">
          <p className="field-label mb-1">Note</p>
          <p className="text-data text-ink-secondary">{t.note}</p>
        </div>
      ) : null}

      {state !== 'completed' ? (
        <div className="px-4 py-4 flex flex-wrap gap-2">
          <Button variant="primary" disabled={blocked} title={blocked ? 'Clear what blocks this transfer first' : undefined}>
            {state === 'needs_review' ? 'Approve and send field orders' : 'Send field orders'}
          </Button>
          <Button>Reschedule</Button>
          <Button variant="quiet">Cancel transfer</Button>
        </div>
      ) : (
        <div className="px-4 py-4">
          <p className="text-micro text-ink-tertiary">Completed {stamp(t.completedAt)}. Nothing is left to do.</p>
        </div>
      )}
    </aside>
  )
}
