'use client'

import { useMemo, useState } from 'react'
import Link from 'next/link'
import type { Route } from 'next'
import { Panel } from '@/components/ui/Panel'
import { Chip, Group } from '@/components/ui/Chip'
import { Money } from '@/components/ui/Money'
import { StateFlag, type Tone } from '@/components/ui/State'
import { Table, Row, Td, TableFooter } from '@/components/table/Table'
import { SortHeader, sortRows, useSort, type SortColumn } from '@/components/table/Sort'
import { count, date, money } from '@/lib/format'
import { matchesSearch } from '@/lib/search'

export type BillStatus = 'current' | 'past_due' | 'paid' | 'draft' | 'held' | 'void'

export type BillRow = {
  id: string
  invoiceNumber: string
  invoiceDate: string
  status: BillStatus
  customerName: string
  streetAddress: string | null
  cityLine: string | null
  amountDue: string
  amountPaid: string
  dueDate: string
  daysBilled: number
}

const STATUS: Record<BillStatus, { label: string; tone: Tone; rank: number }> = {
  current: { label: 'Current', tone: 'pending', rank: 1 },
  past_due: { label: 'Past due', tone: 'critical', rank: 2 },
  paid: { label: 'Paid', tone: 'posted', rank: 3 },
  draft: { label: 'Draft', tone: 'draft', rank: 4 },
  held: { label: 'Held', tone: 'held', rank: 5 },
  void: { label: 'Void', tone: 'void', rank: 6 },
}

type SortKey =
  | 'invoiceDate'
  | 'status'
  | 'customerName'
  | 'streetAddress'
  | 'amountDue'
  | 'amountPaid'
  | 'dueDate'
  | 'daysBilled'

const COLUMNS: SortColumn<SortKey>[] = [
  { key: 'invoiceDate', label: 'Bill date', width: '10rem' },
  { key: 'status', label: 'Status', width: '7rem' },
  { key: 'customerName', label: 'Customer' },
  { key: 'streetAddress', label: 'Street address' },
  { key: 'amountDue', label: 'Total amount', align: 'right', width: '8rem' },
  { key: 'amountPaid', label: 'Total paid', align: 'right', width: '8rem' },
  { key: 'dueDate', label: 'Due date', width: '8rem' },
  { key: 'daysBilled', label: 'Days billed', align: 'right', width: '7rem' },
]

const sortValue = (r: BillRow, key: SortKey) => {
  switch (key) {
    case 'status':
      return STATUS[r.status].rank
    case 'amountDue':
      return Number(r.amountDue)
    case 'amountPaid':
      return Number(r.amountPaid)
    default:
      return r[key]
  }
}

/* ---- Bill-date ranges ------------------------------------------------- */

type Preset = 'current' | 'previous' | 'quarter' | 'six' | 'year' | 'all' | 'custom'

const PRESETS: { key: Preset; label: string }[] = [
  { key: 'current', label: 'Current month' },
  { key: 'previous', label: 'Previous month' },
  { key: 'quarter', label: 'Last quarter' },
  { key: 'six', label: 'Last 6 months' },
  { key: 'year', label: 'Last year' },
  { key: 'all', label: 'All' },
  { key: 'custom', label: 'Custom' },
]

type Range = { from: string | null; to: string | null }

const iso = (ms: number) => new Date(ms).toISOString().slice(0, 10)

/**
 * Resolve a preset against the as-of date, not the wall clock — viewing the
 * app as of an earlier day must move "current month" with it.
 *
 * Every range runs in whole calendar months, because bills are monthly and a
 * range that cut a cycle in half would show half a cycle. "Last quarter" is
 * the previous calendar quarter; "last 6 months" and "last year" count back
 * from the as-of month, which is included.
 */
function resolve(preset: Preset, asOf: string, custom: Range): Range {
  const [y, m] = asOf.split('-').map(Number)
  const start = (offset: number) => iso(Date.UTC(y, m - 1 + offset, 1))
  const end = (offset: number) => iso(Date.UTC(y, m + offset, 0))
  switch (preset) {
    case 'current':
      return { from: start(0), to: end(0) }
    case 'previous':
      return { from: start(-1), to: end(-1) }
    case 'quarter': {
      const back = ((m - 1) % 3) + 3
      return { from: start(-back), to: end(-back + 2) }
    }
    case 'six':
      return { from: start(-5), to: end(0) }
    case 'year':
      return { from: start(-11), to: end(0) }
    case 'all':
      return { from: null, to: null }
    case 'custom':
      return custom
  }
}

function describe(range: Range): string {
  if (range.from && range.to) return `${date(range.from)} – ${date(range.to)}`
  if (range.from) return `From ${date(range.from)}`
  if (range.to) return `Through ${date(range.to)}`
  return 'Every bill on file'
}

/**
 * The bill list: filter by bill date, status and customer, sort on any column.
 * Opening a bill goes to the bill itself.
 */
export function BillsList({ rows, asOf }: { rows: BillRow[]; asOf: string }) {
  const [preset, setPreset] = useState<Preset>('current')
  const [custom, setCustom] = useState<Range>(() => resolve('current', asOf, { from: null, to: null }))
  const [statuses, setStatuses] = useState<BillStatus[]>([])
  const [query, setQuery] = useState('')
  const { sort, toggle } = useSort<SortKey>({ key: 'invoiceDate', dir: 'descending' })

  const range = resolve(preset, asOf, custom)
  const present = (Object.keys(STATUS) as BillStatus[]).filter((s) => rows.some((r) => r.status === s))

  const shown = useMemo(() => {
    const matched = rows.filter(
      (r) =>
        (!range.from || r.invoiceDate >= range.from) &&
        (!range.to || r.invoiceDate <= range.to) &&
        (statuses.length === 0 || statuses.includes(r.status)) &&
        matchesSearch(query, [r.customerName, r.streetAddress, r.cityLine]),
    )
    return sortRows(matched, sort, sortValue)
  }, [rows, range.from, range.to, statuses, query, sort])

  const billed = shown.reduce((a, r) => a + Math.round(Number(r.amountDue) * 100), 0) / 100
  const paid = shown.reduce((a, r) => a + Math.round(Number(r.amountPaid) * 100), 0) / 100

  const pick = (p: Preset) => {
    /* Custom opens on whatever range was showing, so it starts as an edit of it. */
    if (p === 'custom' && preset !== 'custom') setCustom(range)
    setPreset(p)
  }
  const toggleStatus = (s: BillStatus) =>
    setStatuses((xs) => (xs.includes(s) ? xs.filter((x) => x !== s) : [...xs, s]))

  return (
    <Panel>
      <div className="space-y-2 border-b border-rule-hair bg-surface px-cell-x py-2">
        <div className="flex flex-wrap items-center gap-x-5 gap-y-2">
          <Group label="Bill date">
            {PRESETS.map((p) => (
              <Chip key={p.key} on={preset === p.key} onClick={() => pick(p.key)}>
                {p.label}
              </Chip>
            ))}
          </Group>
          {preset === 'custom' ? (
            <div className="flex items-center gap-1.5 text-micro text-ink-secondary">
              <label htmlFor="bill-from" className="sr-only">
                From
              </label>
              <input
                id="bill-from"
                type="date"
                value={custom.from ?? ''}
                max={custom.to ?? undefined}
                onChange={(e) => setCustom((c) => ({ ...c, from: e.target.value || null }))}
                className="h-6 rounded-xs border border-rule-solid bg-surface-raised px-1.5 text-micro text-ink-primary"
              />
              <span aria-hidden>–</span>
              <label htmlFor="bill-to" className="sr-only">
                To
              </label>
              <input
                id="bill-to"
                type="date"
                value={custom.to ?? ''}
                min={custom.from ?? undefined}
                onChange={(e) => setCustom((c) => ({ ...c, to: e.target.value || null }))}
                className="h-6 rounded-xs border border-rule-solid bg-surface-raised px-1.5 text-micro text-ink-primary"
              />
            </div>
          ) : (
            <span className="text-micro text-ink-tertiary">{describe(range)}</span>
          )}
        </div>

        <div className="flex flex-wrap items-center gap-x-5 gap-y-2">
          <Group label="Status">
            {present.map((s) => (
              <Chip key={s} on={statuses.includes(s)} onClick={() => toggleStatus(s)}>
                {STATUS[s].label}
              </Chip>
            ))}
          </Group>
          <div className="flex items-center gap-1.5">
            <label htmlFor="bill-search" className="label-caps">
              Search
            </label>
            <input
              id="bill-search"
              type="search"
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              placeholder="Customer or street address…"
              className="h-6 w-64 rounded-xs border border-rule-solid bg-surface-raised px-2 text-micro text-ink-primary placeholder:text-ink-muted"
            />
          </div>
          <p className="ml-auto text-micro text-ink-secondary">
            {count(shown.length)} bills · {money(billed)} billed · {money(paid)} paid
          </p>
        </div>
      </div>

      <Table caption="Bills">
        <thead>
          <SortHeader columns={COLUMNS} sort={sort} onSort={toggle} />
        </thead>
        <tbody>
          {shown.map((r) => (
            <Row key={r.id} muted={r.status === 'void'}>
              <Td className="whitespace-nowrap">
                <Link href={`/invoices/${r.id}` as Route} className="group block">
                  <span className="block tabular-nums text-ink-primary font-medium group-hover:underline">
                    {date(r.invoiceDate)}
                  </span>
                  <span className="block ident text-micro text-accent-text group-hover:text-accent-text-hover">
                    {r.invoiceNumber}
                  </span>
                </Link>
              </Td>
              <Td>
                <StateFlag tone={STATUS[r.status].tone}>{STATUS[r.status].label}</StateFlag>
              </Td>
              <Td>{r.customerName}</Td>
              <Td>
                {r.streetAddress ?? '—'}
                {r.cityLine ? <span className="block text-micro text-ink-tertiary">{r.cityLine}</span> : null}
              </Td>
              <Td align="right">
                <Money value={r.amountDue} />
              </Td>
              <Td align="right">
                <Money value={r.amountPaid} />
              </Td>
              <Td className={`tabular-nums whitespace-nowrap ${r.status === 'past_due' ? 'text-exception-critical-text' : ''}`}>
                {date(r.dueDate)}
              </Td>
              <Td align="right" className="tabular-nums">
                {r.daysBilled}
              </Td>
            </Row>
          ))}
          {shown.length === 0 ? (
            <Row>
              <Td colSpan={COLUMNS.length} className="py-6 text-center text-ink-tertiary">
                No bills match these filters.
              </Td>
            </Row>
          ) : null}
        </tbody>
      </Table>

      {shown.length > 0 ? <TableFooter shown={shown.length} total={shown.length} noun="bills" /> : null}
    </Panel>
  )
}
