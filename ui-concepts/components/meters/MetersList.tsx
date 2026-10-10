'use client'

import { useMemo, useState } from 'react'
import Link from 'next/link'
import type { Route } from 'next'
import { Panel } from '@/components/ui/Panel'
import { Chip, Group } from '@/components/ui/Chip'
import { StateFlag, humanize } from '@/components/ui/State'
import { Table, Row, Td, TableFooter } from '@/components/table/Table'
import { SortHeader, sortRows, useSort, type SortColumn } from '@/components/table/Sort'
import { METER_STATUS, meterStatus, sizeLabel, type MeterStatus } from '@/components/meters/status'
import { AccountNumber } from '@/components/ui/RecordLink'
import { count, date } from '@/lib/format'
import { matchesSearch } from '@/lib/search'
import { useEdits } from '@/lib/edits-store'

export type MeterRow = {
  id: string
  meterNumber: string
  serialNumber: string | null
  manufacturer: string | null
  model: string | null
  size: string | null
  readType: string
  /** `meters.ami_endpoint_id`. Null on a manually read meter. */
  endpointId: string | null
  routeId: string | null
  routeSequence: number | null
  status: string
  customerId: string | null
  customerName: string | null
  customerNumber: string | null
  streetAddress: string | null
  cityLine: string | null
  /** Where an unset meter sits, in place of a premise. */
  warehouseLocation: string | null
  lastReadDate: string | null
  nextTestDueDate: string | null
  estimates: number
  endpointSilent: boolean
}

type SortKey = 'meterNumber' | 'status' | 'customerName' | 'make' | 'readType' | 'route' | 'lastReadDate' | 'nextTestDueDate'

const COLUMNS: SortColumn<SortKey>[] = [
  { key: 'meterNumber', label: 'Meter', width: '9rem' },
  { key: 'status', label: 'Status', width: '7rem' },
  { key: 'customerName', label: 'Account · premise' },
  { key: 'make', label: 'Make · size' },
  { key: 'readType', label: 'Read type · endpoint', width: '10rem' },
  { key: 'route', label: 'Route', width: '7rem' },
  { key: 'lastReadDate', label: 'Last read', width: '8rem' },
  { key: 'nextTestDueDate', label: 'Next test due', width: '8.5rem' },
]

const READ_TYPES = ['amr', 'ami', 'manual'] as const

type Flag = 'cap' | 'overdue' | 'due' | 'silent'

const addMonths = (iso: string, n: number) => {
  const [y, m, d] = iso.split('-').map(Number)
  return new Date(Date.UTC(y, m - 1 + n, d)).toISOString().slice(0, 10)
}

/**
 * The conditions that put a meter on a worklist, resolved against the as-of
 * date. "Due" is the six-month look-ahead a meter shop schedules tests on.
 */
function flagsFor(asOf: string): { key: Flag; label: string; test: (r: MeterRow) => boolean }[] {
  const soon = addMonths(asOf, 6)
  return [
    { key: 'cap', label: 'At estimate cap', test: (r) => r.estimates >= 3 },
    { key: 'overdue', label: 'Test overdue', test: (r) => !!r.nextTestDueDate && r.nextTestDueDate < asOf },
    {
      key: 'due',
      label: 'Test due in 6 months',
      test: (r) => !!r.nextTestDueDate && r.nextTestDueDate >= asOf && r.nextTestDueDate <= soon,
    },
    { key: 'silent', label: 'Endpoint not reporting', test: (r) => r.endpointSilent },
  ]
}

/**
 * Every meter on the system, set or not: filter by status, read type, route
 * and the conditions that put a meter on someone's worklist, search by any
 * number a caller or a tech reads off the meter, sort on any column.
 *
 * It opens on active meters. A search looks across every status unless a
 * single status has been picked, so an inactive meter is found by its number
 * without changing the filter first.
 */
export function MetersList({ rows: fixtureRows, asOf }: { rows: MeterRow[]; asOf: string }) {
  /* A meter inactivated in this browser lists under its new status. */
  const edits = useEdits().meters
  const rows = useMemo(
    () => fixtureRows.map((r) => (edits[r.id]?.status ? { ...r, status: edits[r.id].status! } : r)),
    [fixtureRows, edits],
  )

  const [query, setQuery] = useState('')
  const [pick, setPick] = useState<MeterStatus | 'all'>('active')
  const [readTypes, setReadTypes] = useState<string[]>([])
  const [route, setRoute] = useState('')
  const [size, setSize] = useState('')
  const [flags, setFlags] = useState<Flag[]>([])
  const { sort, toggle } = useSort<SortKey>({ key: 'meterNumber', dir: 'ascending' })

  const FLAGS = useMemo(() => flagsFor(asOf), [asOf])

  const routes = [...new Set(rows.map((r) => r.routeId).filter((x): x is string => !!x))].sort()
  const sizes = [...new Set(rows.map((r) => r.size).filter((x): x is string => !!x))].sort(
    (a, b) => parseFloat(a.replace('3/4', '0.75')) - parseFloat(b.replace('3/4', '0.75')),
  )

  const searching = query.trim() !== ''
  /* Typing a search widens the default view to every status. */
  const effective = searching && pick === 'active' ? 'all' : pick

  const shown = useMemo(() => {
    const matched = rows.filter(
      (r) =>
        (effective === 'all' || r.status === effective) &&
        (readTypes.length === 0 || readTypes.includes(r.readType)) &&
        (!route || (route === 'none' ? !r.routeId : r.routeId === route)) &&
        (!size || r.size === size) &&
        flags.every((f) => FLAGS.find((x) => x.key === f)!.test(r)) &&
        matchesSearch(query, [
          r.meterNumber,
          r.serialNumber,
          r.endpointId,
          r.customerName,
          r.customerNumber,
          r.streetAddress,
          r.cityLine,
          r.manufacturer,
          r.model,
        ]),
    )
    return sortRows(matched, sort, (r, key) => {
      switch (key) {
        case 'status':
          return meterStatus(r.status).rank
        case 'make':
          return [r.manufacturer, r.model].filter(Boolean).join(' ') || null
        case 'route':
          return r.routeId ? `${r.routeId}-${String(r.routeSequence ?? 0).padStart(4, '0')}` : null
        default:
          return r[key]
      }
    })
  }, [rows, effective, readTypes, route, size, flags, query, sort, FLAGS])

  const filtered = pick !== 'active' || readTypes.length + flags.length > 0 || !!route || !!size || searching
  const clear = () => {
    setPick('active')
    setReadTypes([])
    setRoute('')
    setSize('')
    setFlags([])
    setQuery('')
  }
  const flip = <T,>(set: (f: (xs: T[]) => T[]) => void, v: T) =>
    set((xs) => (xs.includes(v) ? xs.filter((x) => x !== v) : [...xs, v]))
  const selectClass =
    'h-6 rounded-sm border border-rule-solid bg-surface-raised px-1.5 text-micro text-ink-primary'

  return (
    <Panel>
      <div className="space-y-2 border-b border-rule-hair bg-surface px-cell-x py-2">
        <div className="flex flex-wrap items-center gap-x-5 gap-y-2">
          <div className="flex items-center gap-1.5">
            <label htmlFor="meter-search" className="field-label">
              Search
            </label>
            <input
              id="meter-search"
              type="search"
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              placeholder="Meter, serial, AMR ID, account, customer or address…"
              className="h-6 w-80 rounded-sm border border-rule-solid bg-surface-raised px-2 text-micro text-ink-primary placeholder:text-ink-muted"
            />
          </div>
          <Group label="Status">
            {(Object.keys(METER_STATUS) as MeterStatus[]).map((s) => (
              <Chip key={s} on={pick === s} onClick={() => setPick(s)}>
                {METER_STATUS[s].label}
              </Chip>
            ))}
            <Chip on={pick === 'all'} onClick={() => setPick('all')}>
              All
            </Chip>
          </Group>
          <Group label="Read type">
            {READ_TYPES.map((t) => (
              <Chip key={t} on={readTypes.includes(t)} onClick={() => flip(setReadTypes, t)}>
                {humanize(t)}
              </Chip>
            ))}
          </Group>
        </div>

        <div className="flex flex-wrap items-center gap-x-5 gap-y-2">
          <div className="flex items-center gap-1.5">
            <label htmlFor="meter-route" className="field-label">
              Route
            </label>
            <select id="meter-route" value={route} onChange={(e) => setRoute(e.target.value)} className={selectClass}>
              <option value="">All routes</option>
              {routes.map((r) => (
                <option key={r} value={r}>
                  {r}
                </option>
              ))}
              <option value="none">Not on a route</option>
            </select>
          </div>
          <div className="flex items-center gap-1.5">
            <label htmlFor="meter-size" className="field-label">
              Size
            </label>
            <select id="meter-size" value={size} onChange={(e) => setSize(e.target.value)} className={selectClass}>
              <option value="">All sizes</option>
              {sizes.map((s) => (
                <option key={s} value={s}>
                  {sizeLabel(s)}
                </option>
              ))}
            </select>
          </div>
          <Group label="Needs attention">
            {FLAGS.map((f) => (
              <Chip key={f.key} on={flags.includes(f.key)} onClick={() => flip(setFlags, f.key)}>
                {f.label}
              </Chip>
            ))}
          </Group>
          <p className="ml-auto flex items-center gap-3 text-micro text-ink-secondary">
            {filtered ? (
              <button type="button" onClick={clear} className="text-accent-text underline hover:text-accent-text-hover">
                Clear filters
              </button>
            ) : null}
            {searching && pick === 'active' ? 'Searching every status · ' : ''}
            {count(shown.length)} of {count(rows.length)} meters
          </p>
        </div>
      </div>

      <Table caption="Meters">
        <thead>
          <SortHeader columns={COLUMNS} sort={sort} onSort={toggle} />
        </thead>
        <tbody>
          {shown.map((r) => {
            const st = meterStatus(r.status)
            const overdue = !!r.nextTestDueDate && r.nextTestDueDate < asOf
            return (
              <Row key={r.id} muted={r.status === 'removed'}>
                <Td className="whitespace-nowrap">
                  <Link href={`/meters/${r.id}` as Route} className="group block">
                    <span className="block ident font-medium text-accent-text group-hover:text-accent-text-hover group-hover:underline">
                      {r.meterNumber}
                    </span>
                    <span className="block ident text-micro text-ink-tertiary">{r.serialNumber ?? '—'}</span>
                  </Link>
                </Td>
                <Td>
                  <StateFlag tone={st.tone}>{st.label}</StateFlag>
                </Td>
                <Td>
                  {r.customerId ? (
                    <>
                      <Link href={`/customers/${r.customerId}` as Route} className="text-ink-primary hover:underline">
                        {r.customerName}
                      </Link>
                      {r.customerNumber ? (
                        <span className="ml-2 text-micro">
                          <AccountNumber number={r.customerNumber} id={r.customerId} />
                        </span>
                      ) : null}
                      <span className="block text-micro text-ink-tertiary">
                        {r.streetAddress}
                        {r.cityLine ? ` · ${r.cityLine}` : ''}
                      </span>
                    </>
                  ) : (
                    <span className="text-ink-tertiary">{r.warehouseLocation ?? 'No premise'}</span>
                  )}
                </Td>
                <Td>
                  {[r.manufacturer, r.model].filter(Boolean).join(' ') || '—'}
                  <span className="block text-micro text-ink-tertiary">{sizeLabel(r.size)}</span>
                </Td>
                <Td>
                  {humanize(r.readType)}
                  <span
                    className={`block ident text-micro ${r.endpointSilent ? 'text-exception-critical-text' : 'text-ink-tertiary'}`}
                    title={r.endpointSilent ? 'Endpoint not reporting' : undefined}
                  >
                    {r.endpointId ?? '—'}
                    {r.endpointSilent ? ' · silent' : ''}
                  </span>
                </Td>
                <Td className="ident whitespace-nowrap">
                  {r.routeId ? (
                    <>
                      {r.routeId} <span className="text-ink-tertiary">· {r.routeSequence}</span>
                    </>
                  ) : (
                    <span className="text-ink-muted">—</span>
                  )}
                </Td>
                <Td className="tabular-nums whitespace-nowrap">
                  {r.lastReadDate ? date(r.lastReadDate) : <span className="text-ink-muted">—</span>}
                  {r.estimates > 0 ? (
                    <span
                      className={`block text-micro ${r.estimates >= 3 ? 'text-exception-critical-text font-medium' : 'text-ink-tertiary'}`}
                    >
                      {r.estimates} estimate{r.estimates === 1 ? '' : 's'} in a row
                    </span>
                  ) : null}
                </Td>
                <Td
                  className={`tabular-nums whitespace-nowrap ${overdue ? 'text-exception-critical-text font-medium' : ''}`}
                  title={overdue ? 'Periodic test overdue' : undefined}
                >
                  {r.nextTestDueDate ? date(r.nextTestDueDate) : <span className="text-ink-muted">—</span>}
                  {overdue ? <span className="block text-micro font-normal">Overdue</span> : null}
                </Td>
              </Row>
            )
          })}
          {shown.length === 0 ? (
            <Row>
              <Td colSpan={COLUMNS.length} className="py-6 text-center text-ink-tertiary">
                No meters match these filters.
              </Td>
            </Row>
          ) : null}
        </tbody>
      </Table>

      {shown.length > 0 ? <TableFooter shown={shown.length} total={shown.length} noun="meters" /> : null}
    </Panel>
  )
}
