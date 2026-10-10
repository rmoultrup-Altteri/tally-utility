'use client'

import { useMemo, useState } from 'react'
import Link from 'next/link'
import type { Route } from 'next'
import { Panel } from '@/components/ui/Panel'
import { Chip, Group } from '@/components/ui/Chip'
import { StateFlag, humanize } from '@/components/ui/State'
import { accountTone } from '@/components/meters/status'
import { AccountNumber, MeterNumber } from '@/components/ui/RecordLink'
import { Table, Row, Td, TableFooter } from '@/components/table/Table'
import { SortHeader, sortRows, useSort, type SortColumn } from '@/components/table/Sort'
import { count, date, money } from '@/lib/format'
import { matchesSearch } from '@/lib/search'
import { useImported } from '@/lib/imports-store'
import { customerById, locations, meters } from '@/fixtures/accounts'
import { useEdits } from '@/lib/edits-store'
import { customerName } from '@/schemas/models'
import type { ImportedData } from '@/lib/assistant/protocol'

export type AccountRow = {
  id: string
  customerNumber: string
  /** `customers.status`, after any inactivation made in this browser. */
  status: string
  /** `customers.balance`. An inactive account still owing (or owed) money lists as active. */
  balance: string
  /** `customers.created_at` — when the account was opened, not the move-in date. */
  createdAt: string
  ownerName: string
  streetAddress: string | null
  cityLine: string | null
  meterNumber: string | null
  /** `meters.ami_endpoint_id`. Null on a manually read meter. */
  amrId: string | null
  /** Added through the assistant and kept in this browser; it has no account page yet. */
  imported?: boolean
}

type SortKey = 'createdAt' | 'ownerName' | 'streetAddress' | 'meterNumber' | 'amrId'

const COLUMNS: SortColumn<SortKey>[] = [
  { key: 'createdAt', label: 'Customer since', width: '9rem' },
  { key: 'ownerName', label: 'Owner name' },
  { key: 'streetAddress', label: 'Street address' },
  { key: 'meterNumber', label: 'Meter ID', width: '8rem' },
  { key: 'amrId', label: 'AMR ID', width: '9rem' },
]

/**
 * The status filter. "Active" is every account someone may still need to
 * work: in service, in collections, or closed with money still on it either
 * way. Each other chip is one stored status; All is every account.
 */
type StatusPick = 'active' | 'all' | string

const isActive = (r: AccountRow) => r.status === 'active' || r.status === 'collections' || Number(r.balance) !== 0

const matchesStatus = (r: AccountRow, pick: StatusPick) =>
  pick === 'all' ? true : pick === 'active' ? isActive(r) : r.status === pick

/**
 * The account list. It opens on active accounts; a search looks across every
 * status unless a single status has been picked, so a caller on an inactive
 * account is found without changing the filter first.
 */
export function AccountsList({ rows: fixtureRows }: { rows: AccountRow[] }) {
  const imported = useImported()
  const edits = useEdits().customers
  const rows = useMemo(() => {
    /* An account renamed in this browser lists under its edited name. */
    const named = fixtureRows.map((r) => {
      const base = customerById.get(r.id)
      if (!base || !edits[r.id]) return r
      const edited = { ...base, ...edits[r.id] }
      return { ...r, ownerName: customerName(edited), status: edited.status }
    })
    return [...named, ...importedRows(imported)]
  }, [fixtureRows, imported, edits])
  const [query, setQuery] = useState('')
  const [pick, setPick] = useState<StatusPick>('active')
  /* Inactive always shows, so an account just inactivated is one click away. */
  const others = [...new Set(['inactive', ...rows.map((r) => r.status)])].filter((s) => s !== 'active')
  const searching = query.trim() !== ''
  /* Typing a search widens the default view to every status. */
  const effective: StatusPick = searching && pick === 'active' ? 'all' : pick
  const { sort, toggle } = useSort<SortKey>({ key: 'ownerName', dir: 'ascending' })

  const shown = useMemo(
    () =>
      sortRows(
        rows.filter(
          (r) =>
            matchesStatus(r, effective) &&
            matchesSearch(query, [r.ownerName, r.customerNumber, r.streetAddress, r.cityLine, r.meterNumber, r.amrId]),
        ),
        sort,
        (r, key) => r[key],
      ),
    [rows, query, effective, sort],
  )

  return (
    <Panel>
      <div className="flex items-center gap-3 border-b border-rule-hair bg-surface px-cell-x py-2">
        <label htmlFor="account-search" className="field-label">
          Search
        </label>
        <input
          id="account-search"
          type="search"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          placeholder="Name, account, address or meter…"
          className="h-7 w-80 rounded-sm border border-rule-solid bg-surface-raised px-2 text-data text-ink-primary placeholder:text-ink-muted"
        />
        <Group label="Status">
          {['active', ...others, 'all'].map((s) => (
            <Chip key={s} on={pick === s} onClick={() => setPick(s)}>
              {s === 'all' ? 'All' : humanize(s)}
            </Chip>
          ))}
        </Group>
        <span className="ml-auto text-micro text-ink-tertiary">
          {searching && pick === 'active' ? 'Searching every status · ' : ''}
          {count(shown.length)} of {count(rows.length)} accounts
        </span>
      </div>

      <Table caption="Accounts">
        <thead>
          <SortHeader columns={COLUMNS} sort={sort} onSort={toggle} />
        </thead>
        <tbody>
          {shown.map((r) => (
            <Row key={r.id}>
              <Td className="tabular-nums whitespace-nowrap">{date(r.createdAt)}</Td>
              <Td>
                {r.imported ? (
                  <span className="text-ink-primary font-medium">{r.ownerName}</span>
                ) : (
                  <Link
                    href={`/customers/${r.id}` as Route}
                    className="text-ink-primary font-medium hover:underline"
                  >
                    {r.ownerName}
                  </Link>
                )}
                {r.status !== 'active' ? (
                  <span className="ml-2 align-middle">
                    <StateFlag
                      tone={accountTone(r.status)}
                      title={Number(r.balance) !== 0 ? `${money(r.balance)} still on the account` : undefined}
                    >
                      {humanize(r.status)}
                      {r.status === 'collections' || Number(r.balance) === 0
                        ? ''
                        : Number(r.balance) > 0
                          ? ' · balance due'
                          : ' · credit due'}
                    </StateFlag>
                  </span>
                ) : null}
                <span className="block text-micro">
                  {r.imported ? (
                    <span className="ident text-ink-tertiary">{r.customerNumber}</span>
                  ) : (
                    <AccountNumber number={r.customerNumber} id={r.id} />
                  )}
                  {r.imported ? (
                    <span className="font-sans text-exception-info-text" title="Imported through the assistant and kept in this browser until the API exists">
                      {' '}· imported
                    </span>
                  ) : null}
                </span>
              </Td>
              <Td>
                {r.streetAddress ?? '—'}
                {r.cityLine ? (
                  <span className="block text-micro text-ink-tertiary">{r.cityLine}</span>
                ) : null}
              </Td>
              <Td>{r.meterNumber ? <MeterNumber number={r.meterNumber} plainClassName="text-ink-primary" /> : '—'}</Td>
              <Td className="ident" title={r.amrId ? undefined : 'Manually read — no radio endpoint'}>
                {r.amrId ?? <span className="text-ink-muted">—</span>}
              </Td>
            </Row>
          ))}
          {shown.length === 0 ? (
            <Row>
              <Td colSpan={COLUMNS.length} className="py-6 text-center text-ink-tertiary">
                {query.trim() ? <>No account matches “{query.trim()}”.</> : 'No accounts match these filters.'}
              </Td>
            </Row>
          ) : null}
        </tbody>
      </Table>

      {shown.length > 0 ? <TableFooter shown={shown.length} total={shown.length} noun="accounts" /> : null}
    </Panel>
  )
}

/** Accounts the assistant imported, shaped like the fixture rows the page builds on the server. */
function importedRows(data: ImportedData): AccountRow[] {
  const allLocations = [...locations, ...data.locations]
  const allMeters = [...meters, ...data.meters]
  return data.customers.map((c) => {
    const link = data.links.find((l) => l.customerId === c.id)
    const location = link ? allLocations.find((l) => l.id === link.locationId) : undefined
    const meter = link?.meterId ? allMeters.find((m) => m.id === link.meterId) : undefined
    return {
      id: c.id,
      customerNumber: c.customer_number,
      status: c.status,
      balance: c.balance,
      createdAt: c.created_at,
      ownerName: customerName(c),
      streetAddress: location?.address ?? null,
      cityLine: location ? `${location.city}, ${location.state} ${location.zip}` : null,
      meterNumber: meter?.meter_number ?? null,
      amrId: meter?.ami_endpoint_id ?? null,
      imported: true,
    }
  })
}
/** The page header's account count, including accounts imported in this browser. */
export function AccountCount({ base }: { base: number }) {
  const n = base + useImported().customers.length
  return <>{n.toLocaleString('en-US')} accounts</>
}