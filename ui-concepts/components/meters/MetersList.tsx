'use client'

import { useMemo, useState, type ReactNode } from 'react'
import Link from 'next/link'
import type { Route } from 'next'
import { Panel } from '@/components/ui/Panel'
import { Chip, Group } from '@/components/ui/Chip'
import { StateFlag, humanize } from '@/components/ui/State'
import { Table, Row, Td, TableFooter } from '@/components/table/Table'
import { sortRows, useSort } from '@/components/table/Sort'
import { ColumnHead, ColumnsMenu, useColumns, type ColumnDef } from '@/components/table/Columns'
import { METER_STATUS, meterStatus, sizeLabel, type MeterStatus } from '@/components/meters/status'
import { AccountNumber } from '@/components/ui/RecordLink'
import { count, date } from '@/lib/format'
import { matchesSearch } from '@/lib/search'
import { useEdits, type Edits, type MeterEdit, type Replacement } from '@/lib/edits-store'
import { useImported } from '@/lib/imports-store'
import { customers, locations, serviceLinks } from '@/fixtures/accounts'
import { customerName } from '@/schemas/models'
import type { ImportedData } from '@/lib/assistant/protocol'

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
  /** Added in this browser — by hand or through the assistant — so it has no meter page yet. */
  imported?: boolean
}

type SortKey =
  | 'meterNumber'
  | 'status'
  | 'customerName'
  | 'make'
  | 'readType'
  | 'route'
  | 'lastReadDate'
  | 'nextTestDueDate'
  | 'manufacturer'
  | 'model'
  | 'size'
  | 'endpointId'
  | 'customerNumber'

/** Test dates read against the as-of date, so a cell needs it as well as the row. */
type MeterColumn = ColumnDef<SortKey> & {
  cell: (r: MeterRow, asOf: string) => ReactNode
  className?: (r: MeterRow, asOf: string) => string
  title?: (r: MeterRow, asOf: string) => string | undefined
}

const testOverdue = (r: MeterRow, asOf: string) => !!r.nextTestDueDate && r.nextTestDueDate < asOf

/** A size as a number — "3/4_inch" is 0.75 — so sizes order by bore, not by text. */
const sizeValue = (size: string) => parseFloat(size.replace('3/4', '0.75'))

const dash = <span className="text-ink-muted">—</span>

/**
 * The shipped eight, then single fields an operator can add from the Columns
 * menu — the make, model and size split apart, the bare endpoint, the account
 * number — for sorting or exporting on one of them alone.
 */
const COLUMNS: MeterColumn[] = [
  { key: 'meterNumber', label: 'Meter', width: '9rem', className: () => 'whitespace-nowrap', cell: (r) => <MeterCell r={r} /> },
  {
    key: 'status',
    label: 'Status',
    width: '7rem',
    cell: (r) => {
      const st = meterStatus(r.status)
      return <StateFlag tone={st.tone}>{st.label}</StateFlag>
    },
  },
  { key: 'customerName', label: 'Account · service address', cell: (r) => <PremiseCell r={r} /> },
  {
    key: 'make',
    label: 'Make · size',
    cell: (r) => (
      <>
        {[r.manufacturer, r.model].filter(Boolean).join(' ') || '—'}
        <span className="block text-micro text-ink-tertiary">{sizeLabel(r.size)}</span>
      </>
    ),
  },
  {
    key: 'readType',
    label: 'Read type · endpoint',
    width: '10rem',
    cell: (r) => (
      <>
        {humanize(r.readType)}
        <span
          className={`block ident text-micro ${r.endpointSilent ? 'text-exception-critical-text' : 'text-ink-tertiary'}`}
          title={r.endpointSilent ? 'Endpoint not reporting' : undefined}
        >
          {r.endpointId ?? '—'}
          {r.endpointSilent ? ' · silent' : ''}
        </span>
      </>
    ),
  },
  {
    key: 'route',
    label: 'Route',
    width: '7rem',
    className: () => 'ident whitespace-nowrap',
    cell: (r) =>
      r.routeId ? (
        <>
          {r.routeId} <span className="text-ink-tertiary">· {r.routeSequence}</span>
        </>
      ) : (
        dash
      ),
  },
  {
    key: 'lastReadDate',
    label: 'Last read',
    width: '8rem',
    className: () => 'tabular-nums whitespace-nowrap',
    cell: (r) => (
      <>
        {r.lastReadDate ? date(r.lastReadDate) : dash}
        {r.estimates > 0 ? (
          <span className={`block text-micro ${r.estimates >= 3 ? 'text-exception-critical-text font-medium' : 'text-ink-tertiary'}`}>
            {r.estimates} estimate{r.estimates === 1 ? '' : 's'} in a row
          </span>
        ) : null}
      </>
    ),
  },
  {
    key: 'nextTestDueDate',
    label: 'Next test due',
    width: '8.5rem',
    className: (r, asOf) => `tabular-nums whitespace-nowrap ${testOverdue(r, asOf) ? 'text-exception-critical-text font-medium' : ''}`,
    title: (r, asOf) => (testOverdue(r, asOf) ? 'Periodic test overdue' : undefined),
    cell: (r, asOf) => (
      <>
        {r.nextTestDueDate ? date(r.nextTestDueDate) : dash}
        {testOverdue(r, asOf) ? <span className="block text-micro font-normal">Overdue</span> : null}
      </>
    ),
  },
  { key: 'manufacturer', label: 'Manufacturer', hidden: true, cell: (r) => r.manufacturer ?? dash },
  { key: 'model', label: 'Model', hidden: true, cell: (r) => r.model ?? dash },
  { key: 'size', label: 'Size', width: '5rem', hidden: true, className: () => 'whitespace-nowrap', cell: (r) => (r.size ? sizeLabel(r.size) : dash) },
  {
    key: 'endpointId',
    label: 'AMR ID',
    width: '9rem',
    hidden: true,
    className: () => 'ident',
    title: (r) => (r.endpointId ? undefined : 'Manually read — no radio endpoint'),
    cell: (r) => r.endpointId ?? dash,
  },
  {
    key: 'customerNumber',
    label: 'Account number',
    width: '9rem',
    hidden: true,
    cell: (r) => (r.customerNumber && r.customerId ? <AccountNumber number={r.customerNumber} id={r.customerId} /> : dash),
  },
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
  /* A meter edited or inactivated in this browser lists as it now stands. */
  const { meters: edits, customers: customerEdits, replacements } = useEdits()
  const imported = useImported()
  const rows = useMemo(
    () => [
      ...withReplacements(fixtureRows, replacements ?? []).map((r) => withEdit(r, edits[r.id])),
      ...importedRows(imported, customerEdits).map((r) => withEdit(r, edits[r.id])),
    ],
    [fixtureRows, edits, replacements, imported, customerEdits],
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
    (a, b) => sizeValue(a) - sizeValue(b),
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
        case 'size':
          return r.size ? sizeValue(r.size) : null
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
  const cols = useColumns('meters', COLUMNS)
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
          <ColumnsMenu cols={cols} />
        </div>
      </div>

      <Table caption="Meters">
        <thead>
          <ColumnHead cols={cols} sort={sort} onSort={toggle} />
        </thead>
        <tbody>
          {shown.map((r) => (
            <Row key={r.id} muted={r.status === 'removed'}>
              {cols.visible.map((c) => (
                <Td key={c.key} align={c.align} className={c.className?.(r, asOf)} title={c.title?.(r, asOf)}>
                  {c.cell(r, asOf)}
                </Td>
              ))}
            </Row>
          ))}
          {shown.length === 0 ? (
            <Row>
              <Td colSpan={cols.visible.length} className="py-6 text-center text-ink-tertiary">
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

/** The meter number over its serial; a meter added in this browser is marked new. */
function MeterCell({ r }: { r: MeterRow }) {
  return (
    <Link href={`/meters/${r.id}` as Route} className="group block">
      <span className="block ident font-medium text-accent-text group-hover:text-accent-text-hover group-hover:underline">
        {r.meterNumber}
      </span>
      <span className="block text-micro text-ink-tertiary">
        <span className="ident">{r.serialNumber ?? '—'}</span>
        {r.imported ? (
          <span className="text-exception-info-text" title="Added in this browser and kept here until the API exists">
            {' '}· new
          </span>
        ) : null}
      </span>
    </Link>
  )
}

/** Who the meter serves and where, or where an unset meter is kept. */
function PremiseCell({ r }: { r: MeterRow }) {
  if (!r.customerId) return <span className="text-ink-tertiary">{r.warehouseLocation ?? 'No service address'}</span>
  return (
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
  )
}

/** The page header's meter count, including meters added in this browser. */
export function MeterCount({ base, set }: { base: number; set: number }) {
  const extra = importedRows(useImported(), {})
  const total = base + extra.length
  const atPremise = set + extra.filter((r) => r.streetAddress).length
  return <>{total.toLocaleString('en-US')} meters · {atPremise.toLocaleString('en-US')} set at a service address</>
}

/** Exchanges made in this browser, in order: each moves the premise and account from the old row to the new. */
function withReplacements(fixtureRows: MeterRow[], reps: Replacement[]): MeterRow[] {
  if (!reps.length) return fixtureRows
  const byId = new Map(fixtureRows.map((r) => [r.id, { ...r }]))
  for (const rep of reps) {
    const old = byId.get(rep.oldMeterId)
    const next = byId.get(rep.newMeterId)
    if (!old || !next) continue
    Object.assign(next, {
      customerId: old.customerId,
      customerName: old.customerName,
      customerNumber: old.customerNumber,
      streetAddress: old.streetAddress,
      cityLine: old.cityLine,
      warehouseLocation: null,
      lastReadDate: rep.swapDate,
    })
    Object.assign(old, {
      customerId: null,
      customerName: null,
      customerNumber: null,
      streetAddress: null,
      cityLine: null,
      warehouseLocation: 'In transit to the meter shop',
      lastReadDate: rep.swapDate,
    })
  }
  return fixtureRows.map((r) => byId.get(r.id)!)
}

/** A fixture row with any edit or status change made in this browser laid over it. */
function withEdit(r: MeterRow, e: MeterEdit | undefined): MeterRow {
  if (!e) return r
  return {
    ...r,
    serialNumber: e.serial_number !== undefined ? e.serial_number : r.serialNumber,
    manufacturer: e.manufacturer !== undefined ? e.manufacturer : r.manufacturer,
    model: e.model !== undefined ? e.model : r.model,
    size: e.size !== undefined ? e.size : r.size,
    readType: e.read_type ?? r.readType,
    endpointId: e.ami_endpoint_id !== undefined ? e.ami_endpoint_id : r.endpointId,
    routeId: e.route_id !== undefined ? e.route_id : r.routeId,
    routeSequence: e.route_sequence !== undefined ? e.route_sequence : r.routeSequence,
    status: e.status ?? r.status,
  }
}

/** Meters added in this browser, shaped like the fixture rows the page builds on the server. */
function importedRows(data: ImportedData, customerEdits: Edits['customers']): MeterRow[] {
  const allLinks = [...serviceLinks, ...data.links]
  const allLocations = [...locations, ...data.locations]
  const allCustomers = [...customers, ...data.customers]
  return data.meters.map((m) => {
    const link = allLinks.find((l) => l.meterId === m.id)
    const location = link ? allLocations.find((l) => l.id === link.locationId) : undefined
    /* A meter set at an occupied premise links to the premise, not the customer: find who lives there. */
    const customerId = link?.customerId ?? (location ? allLinks.find((l) => l.locationId === location.id && l.customerId)?.customerId : null) ?? null
    const found = customerId ? allCustomers.find((c) => c.id === customerId) : undefined
    const customer = found ? { ...found, ...customerEdits[found.id] } : undefined
    return {
      id: m.id,
      meterNumber: m.meter_number,
      serialNumber: m.serial_number,
      manufacturer: m.manufacturer,
      model: m.model,
      size: m.size,
      readType: m.read_type,
      endpointId: m.ami_endpoint_id,
      routeId: m.route_id,
      routeSequence: m.route_sequence,
      status: m.status,
      customerId: customer?.id ?? null,
      customerName: customer ? customerName(customer) : null,
      customerNumber: customer?.customer_number ?? null,
      streetAddress: location?.address ?? null,
      cityLine: location ? `${location.city}, ${location.state} ${location.zip}` : null,
      warehouseLocation: location ? null : 'In stock',
      lastReadDate: null,
      nextTestDueDate: null,
      estimates: m.consecutive_estimate_count,
      endpointSilent: false,
      imported: true,
    }
  })
}
