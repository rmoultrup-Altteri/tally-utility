'use client'

import { useMemo, useState, type ReactNode } from 'react'
import { Button, Field, FieldGrid } from '@/components/ui/Panel'
import { Rail, StateBlock, StateFlag, type Tone } from '@/components/ui/State'
import { Money } from '@/components/ui/Money'
import { AccountNumber } from '@/components/ui/RecordLink'
import { ColumnTable, type ColumnDef } from '@/components/table/Columns'
import { TableFooter } from '@/components/table/Table'
import { asOf } from '@/fixtures/tenant'
import { transfers as recorded } from '@/fixtures/transfers'
import { buildHandoffs, HANDOFF_LABEL, spoken, type Handoff, type HandoffState } from '@/lib/handoffs'
import type { CheckLevel } from '@/lib/transfers'
import { useAddedTransfers } from '@/lib/transfers-store'
import { addCalendarDays } from '@/lib/working-days'
import { date, dateShort, days, stamp } from '@/lib/format'

/**
 * Move-out / move-in, worked like the transfers beside it: every premise with
 * a stop or a start pending, the conflicts first. Each row puts the outgoing
 * customer's termination next to the incoming customer's application at the
 * same address, so the analyst sees on one line whether the meter passes
 * cleanly from one to the other.
 */

const STATE_TONE: Record<HandoffState, Tone> = {
  conflict: 'critical',
  needs_review: 'warning',
  matched: 'cleared',
  move_out_only: 'pending',
}
const STATE_ORDER: HandoffState[] = ['conflict', 'needs_review', 'matched', 'move_out_only']

const LEVEL_TONE: Record<CheckLevel, Tone> = { block: 'critical', review: 'warning', ok: 'cleared', info: 'info' }
const LEVEL_LABEL: Record<CheckLevel, string> = { block: 'Blocks', review: 'Review', ok: 'OK', info: 'Note' }

const COLUMNS: ColumnDef[] = [
  { key: 'rail', label: '', menuLabel: 'State rail', width: '3px', rail: true, fixed: true },
  { key: 'premise', label: 'Service address', width: '30%' },
  { key: 'out', label: 'Moving out', width: '22%' },
  { key: 'in', label: 'Moving in', width: '22%' },
  { key: 'handoff', label: 'Handoff', width: '14%' },
  { key: 'balance', label: 'Left owing', width: '9%', align: 'right' },
  { key: 'meter', label: 'Meter', hidden: true },
  { key: 'requested', label: 'Requested', hidden: true },
]

const FILTERS: { key: HandoffState | 'all'; label: string }[] = [
  { key: 'all', label: 'All' },
  { key: 'conflict', label: 'Conflicts' },
  { key: 'needs_review', label: 'Review' },
  { key: 'matched', label: 'Matched' },
  { key: 'move_out_only', label: 'No move-in' },
]

/** How the stop and the start meet, in a few words. */
function handoffSummary(h: Handoff): { text: string; tone: 'ok' | 'warn' | 'bad' | 'none' } {
  if (!h.out) return { text: 'No stop on file', tone: 'bad' }
  if (!h.in) return { text: h.out.afterStop === 'lock_off' ? 'Lock-off' : h.out.afterStop === 'owner_takes_service' ? 'Owner takes it' : 'Left on', tone: 'none' }
  const gap = days(h.out.stopDate, h.in.startDate)
  if (gap < 0) return { text: `${-gap}-day overlap`, tone: 'bad' }
  if (gap > 1) return { text: `${gap - 1}-day gap`, tone: 'warn' }
  return { text: gap === 0 ? 'Same day' : 'Next day', tone: 'ok' }
}

export function HandoffsBoard() {
  const added = useAddedTransfers()
  const rows = useMemo(
    () =>
      buildHandoffs([...recorded, ...added]).sort((a, b) => {
        const when = (h: Handoff) => (h.out?.stopDate ?? h.in?.startDate ?? '')
        return STATE_ORDER.indexOf(a.state) - STATE_ORDER.indexOf(b.state) || when(a).localeCompare(when(b))
      }),
    [added],
  )
  const [filter, setFilter] = useState<HandoffState | 'all'>('all')
  const [pick, setPick] = useState<string | null>(null)
  const shown = filter === 'all' ? rows : rows.filter((r) => r.state === filter)
  const selected = shown.find((r) => r.premiseNumber === pick) ?? shown[0]
  const conflicts = rows.filter((r) => r.state === 'conflict').length
  const review = rows.filter((r) => r.state === 'needs_review').length
  const paired = rows.filter((r) => r.out && r.in).length

  return (
    <>
      <div className="px-5 py-3 border-b border-rule-solid bg-surface">
        <StateBlock tone={conflicts ? 'critical' : review ? 'warning' : 'cleared'}>
          <p className="text-data text-ink-primary">
            <strong className="font-semibold">
              {paired} of {rows.length} service addresses have a move-out and a move-in to reconcile.
            </strong>{' '}
            {conflicts ? `${conflicts} conflict${conflicts === 1 ? '' : 's'} would bill one meter to two accounts, or start service nobody has cleared. ` : ''}
            {review ? `${review} need a person to choose a read, a date or a lock-off before the field orders go out.` : ''}
            {!conflicts && !review ? 'Every stop meets its start on one read.' : ''}
          </p>
        </StateBlock>
      </div>

      <div className="flex-1 min-h-0 overflow-auto lg:overflow-hidden grid grid-cols-1 lg:grid-cols-[minmax(0,1fr)_28rem] lg:grid-rows-[minmax(0,1fr)]">
        <section className="min-w-0 min-h-0 border-r border-rule-solid flex flex-col">
          <ColumnTable
            fill
            listId="handoffs"
            caption="Move-outs and move-ins at the same service address, conflicts first"
            columns={COLUMNS}
            rows={shown.map((r) => ({ key: r.premiseNumber, selected: r.premiseNumber === selected?.premiseNumber, cells: cells(r, () => setPick(r.premiseNumber)) }))}
            empty="Nothing in this view."
            toolbar={
              <div role="group" aria-label="Show" className="flex flex-1 min-w-0 flex-wrap items-center gap-1">
                {FILTERS.map((f) => {
                  const n = f.key === 'all' ? rows.length : rows.filter((r) => r.state === f.key).length
                  const on = filter === f.key
                  return (
                    <button
                      key={f.key}
                      type="button"
                      aria-pressed={on}
                      onClick={() => setFilter(f.key)}
                      className={`inline-flex h-7 items-center gap-1.5 rounded-sm border px-2.5 text-micro transition-colors duration-fast ${
                        on ? 'border-accent bg-accent-wash text-ink-primary font-medium' : 'border-rule-solid bg-surface-raised text-ink-secondary hover:text-ink-primary'
                      }`}
                    >
                      {f.label}
                      <span className="figures text-ink-tertiary">{n}</span>
                    </button>
                  )
                })}
              </div>
            }
          />
          <TableFooter shown={shown.length} total={rows.length} noun="service addresses with a stop or start pending" />
        </section>

        {selected ? <HandoffDetail h={selected} /> : null}
      </div>
    </>
  )
}

function cells(h: Handoff, open: () => void): Record<string, ReactNode> {
  const first = h.checks.find((c) => c.level === 'block') ?? h.checks.find((c) => c.level === 'review')
  const s = handoffSummary(h)
  return {
    rail: <Rail tone={STATE_TONE[h.state]} />,
    premise: (
      <>
        <StateFlag tone={STATE_TONE[h.state]}>{HANDOFF_LABEL[h.state]}</StateFlag>
        <button type="button" onClick={open} className="mt-0.5 block text-left text-data text-accent-text hover:text-accent-text-hover hover:underline truncate max-w-full">
          {h.address}
        </button>
        <p className="text-micro text-ink-tertiary">
          {h.city} · <span className="ident">{h.premiseNumber}</span>
        </p>
        {first ? <p className="text-micro text-ink-secondary">{first.title}</p> : null}
      </>
    ),
    out: h.out ? (
      <>
        <p className="text-data text-ink-primary truncate">{h.out.customer.name}</p>
        <p className="text-micro text-ink-tertiary">
          Stops {dateShort(h.out.stopDate)} <span className="ident block">{h.out.number}</span>
        </p>
      </>
    ) : h.in?.currentCustomer ? (
      <>
        <p className="text-data text-ink-primary truncate">{h.in.currentCustomer.name}</p>
        <p className="text-micro text-exception-critical-text">No stop ordered</p>
      </>
    ) : (
      <span className="text-ink-tertiary">—</span>
    ),
    in: h.in ? (
      <>
        <p className="text-data text-ink-primary truncate">{h.in.applicant.name}</p>
        <p className="text-micro text-ink-tertiary">
          Starts {dateShort(h.in.startDate)} <span className="ident block">{h.in.number}</span>
        </p>
      </>
    ) : (
      <span className="text-micro text-ink-tertiary">No application</span>
    ),
    handoff: (
      <span
        className={`text-micro whitespace-nowrap ${
          s.tone === 'bad' ? 'text-exception-critical-text font-medium' : s.tone === 'warn' ? 'text-exception-warning-text font-medium' : s.tone === 'ok' ? 'text-exception-cleared-text' : 'text-ink-secondary'
        }`}
      >
        {s.text}
      </span>
    ),
    balance: h.out ? <Money value={h.out.balance} arrears={h.out.pastDueDays > 0} /> : <span className="text-ink-tertiary">—</span>,
    meter: <span className="ident text-micro">{h.meterNumber}</span>,
    requested: (
      <span className="text-micro text-ink-tertiary whitespace-nowrap">
        {[h.out?.requestedAt, h.in?.requestedAt].filter(Boolean).map((d) => dateShort(d)).join(' / ')}
      </span>
    ),
  }
}

/**
 * The two services on one line of days: the outgoing account running up to
 * its stop, the incoming one from its start, and whatever lies between — an
 * overlap where both would bill, or a gap where nobody does.
 */
function HandoffTimeline({ h }: { h: Handoff }) {
  const stop = h.out?.stopDate ?? null
  const start = h.in?.startDate ?? null
  const marks = [stop, start, asOf.validAt].filter((d): d is string => !!d).sort()
  const lo = addCalendarDays(marks[0], -3)
  const hi = addCalendarDays(marks[marks.length - 1], 3)
  const span = days(lo, hi)
  const at = (d: string) => `${(days(lo, d) / span) * 100}%`
  const overlap = stop && start && start < stop
  const gap = stop && start && days(stop, start) > 1
  const stillOn = !h.out && h.in?.currentCustomer

  const track = "relative h-3 rounded-sm bg-surface-inset overflow-hidden"
  return (
    <div>
      <div className="relative" role="img" aria-label={`Outgoing service ${stop ? `to ${date(stop)}` : "with no stop"}; incoming ${start ? `from ${date(start)}` : "with no application"}`}>
        {/* Overlap or gap, behind both rows */}
        {overlap ? <div className="absolute inset-y-0 bg-exception-critical-wash border-x border-exception-critical-rail/60" style={{ left: at(start!), width: `calc(${at(stop!)} - ${at(start!)})` }} aria-hidden /> : null}
        {gap ? <div className="absolute inset-y-0 bg-exception-warning-wash border-x border-exception-warning-rail/60" style={{ left: at(stop!), width: `calc(${at(start!)} - ${at(stop!)})` }} aria-hidden /> : null}

        <div className="relative">
          <p className="text-micro text-ink-secondary">
            {h.out ? <>{spoken(h.out.customer.name)} · through {dateShort(stop)}</> : stillOn ? <span className="text-exception-critical-text">{spoken(h.in!.currentCustomer!.name)} · no stop ordered</span> : "Nobody on service"}
          </p>
          <div className={`mt-1 ${track}`}>
            {h.out || stillOn ? <div className={`absolute inset-y-0 left-0 ${stillOn ? "bg-exception-critical-rail" : "bg-ink-tertiary"}`} style={{ width: stop ? at(stop) : "100%" }} /> : null}
          </div>
        </div>
        <div className="relative mt-3">
          <p className="text-micro text-ink-secondary text-right">{h.in ? <>{spoken(h.in.applicant.name)} · from {dateShort(start)}</> : "Nobody applied"}</p>
          <div className={`mt-1 ${track}`}>{h.in ? <div className="absolute inset-y-0 right-0 bg-accent" style={{ left: at(start!) }} /> : null}</div>
        </div>

        {/* Today */}
        <div className="absolute inset-y-0 border-l border-dashed border-ink-secondary" style={{ left: at(asOf.validAt) }} aria-hidden />
      </div>
      <div className="mt-1 flex justify-between text-micro text-ink-tertiary">
        <span>{dateShort(lo)}</span>
        <span>{dateShort(hi)}</span>
      </div>
      <p className="mt-2 text-micro text-ink-tertiary">
        <span className="inline-block w-3 border-t border-dashed border-ink-secondary align-middle mr-1" aria-hidden /> today, {date(asOf.validAt)}
        {overlap ? <span className="ml-3 text-exception-critical-text">■ both accounts on the meter</span> : null}
        {gap ? <span className="ml-3 text-exception-warning-text">■ nobody on the account</span> : null}
      </p>
    </div>
  )
}

const READ_LABEL = { meter_read: 'Meter read', field_read: 'Field read', customer_read: 'Customer read' } as const

function HandoffDetail({ h }: { h: Handoff }) {
  const order: CheckLevel[] = ['block', 'review', 'ok', 'info']
  const sorted = [...h.checks].sort((a, b) => order.indexOf(a.level) - order.indexOf(b.level))
  const conflict = h.state === 'conflict'
  const { out, in: inn } = h

  return (
    <aside className="min-w-0 overflow-auto bg-surface">
      <div className="px-4 py-3 border-b border-rule-solid bg-surface-raised">
        <StateFlag tone={STATE_TONE[h.state]}>{HANDOFF_LABEL[h.state]}</StateFlag>
        <h2 className="text-h2 text-ink-primary mt-1.5">{h.address}</h2>
        <p className="text-micro text-ink-tertiary mt-1">
          {h.city} · service address <span className="ident">{h.premiseNumber}</span> · meter <span className="ident">{h.meterNumber}</span>
        </p>
      </div>

      <div className="px-4 py-4 border-b border-rule-hair">
        <p className="field-label mb-2">One meter, two customers</p>
        <HandoffTimeline h={h} />
      </div>

      <div className="grid grid-cols-2 border-b border-rule-hair">
        <div className="px-4 py-4 border-r border-rule-hair min-w-0">
          <p className="field-label mb-2">Moving out</p>
          {out ? (
            <FieldGrid cols={2}>
              <div className="col-span-2 min-w-0">
                <p className="text-data text-ink-primary font-medium">{out.customer.name}</p>
                <AccountNumber number={out.customer.accountNumber} id={out.customer.customerId} />
              </div>
              <Field label="Stops">{date(out.stopDate)}</Field>
              <Field label="Final read">
                {out.finalRead.reading ?? '—'}
                <span className="block text-micro text-ink-tertiary">{READ_LABEL[out.finalRead.method]}</span>
              </Field>
              <Field label="Left owing">
                <Money value={out.balance} arrears={out.pastDueDays > 0} />
                {out.pastDueDays ? <span className="block text-micro text-ink-tertiary">{out.pastDueDays} days past due</span> : null}
              </Field>
              <Field label="After the read">{out.afterStop === 'lock_off' ? 'Lock off' : out.afterStop === 'owner_takes_service' ? 'Owner takes service' : 'Leave on'}</Field>
              <div className="col-span-2 min-w-0">
                <Field label={out.transferId ? 'Transfer' : 'Stop order'}>
                  <span className="ident">{out.number}</span>
                  <span className="block text-micro text-ink-tertiary">Requested {stamp(out.requestedAt)}</span>
                </Field>
              </div>
            </FieldGrid>
          ) : inn?.currentCustomer ? (
            <>
              <p className="text-data text-ink-primary font-medium">{inn.currentCustomer.name}</p>
              <p className="text-micro text-ink-tertiary ident">{inn.currentCustomer.accountNumber}</p>
              <p className="mt-2 text-micro text-exception-critical-text">On service today. No stop ordered.</p>
            </>
          ) : (
            <p className="text-micro text-ink-tertiary">Nobody on service.</p>
          )}
        </div>

        <div className="px-4 py-4 min-w-0">
          <p className="field-label mb-2">Moving in</p>
          {inn ? (
            <FieldGrid cols={2}>
              <div className="col-span-2 min-w-0">
                <p className="text-data text-ink-primary font-medium">{inn.applicant.name}</p>
                {inn.applicant.accountNumber ? (
                  <AccountNumber number={inn.applicant.accountNumber} id={inn.applicant.customerId} />
                ) : (
                  <p className="text-micro text-ink-tertiary">New customer · {inn.applicant.phone}</p>
                )}
              </div>
              <Field label="Starts">{date(inn.startDate)}</Field>
              <Field label="Opening read">
                {inn.openingRead.reading ?? (out && days(out.stopDate, inn.startDate) <= 1 && days(out.stopDate, inn.startDate) >= 0 ? 'Shared' : '—')}
                <span className="block text-micro text-ink-tertiary">{READ_LABEL[inn.openingRead.method]}</span>
              </Field>
              <Field label="Identity">
                {inn.idVerified ? 'Verified' : <span className="text-exception-critical-text font-medium">Not verified</span>}
              </Field>
              <Field label="Deposit">
                <Money value={inn.deposit.amount} />
              </Field>
              <div className="col-span-2 min-w-0">
                <Field label={inn.transferId ? 'Transfer' : 'Application'}>
                  <span className="ident">{inn.number}</span>
                  <span className="block text-micro text-ink-tertiary">Requested {stamp(inn.requestedAt)}</span>
                </Field>
              </div>
            </FieldGrid>
          ) : (
            <p className="text-micro text-ink-tertiary">No application at this address yet.</p>
          )}
        </div>
      </div>

      <div className="px-4 py-4 border-b border-rule-hair">
        <p className="field-label mb-2">Reconciliation</p>
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
      </div>

      <div className="px-4 py-4 flex flex-wrap gap-2">
        {out && inn ? (
          <>
            <Button variant="primary" disabled={conflict} title={conflict ? 'Clear the conflict first' : undefined}>
              {h.state === 'needs_review' ? 'Approve handoff' : 'Confirm handoff'}
            </Button>
            <Button>Change a date</Button>
            <Button variant="quiet">Unlink</Button>
          </>
        ) : inn ? (
          <>
            <Button variant="primary">{inn.currentCustomer ? `Order ${spoken(inn.currentCustomer.name)}’s stop` : 'Order a stop'}</Button>
            <Button>Record landlord confirmation</Button>
          </>
        ) : (
          <>
            <Button variant="primary" disabled={h.state !== 'needs_review'}>
              Order lock-off
            </Button>
            <Button>Link an application</Button>
          </>
        )}
      </div>
    </aside>
  )
}
