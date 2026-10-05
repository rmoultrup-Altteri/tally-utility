'use client'

import { useMemo, useState } from 'react'
import Link from 'next/link'
import type { Route } from 'next'
import { Panel } from '@/components/ui/Panel'
import { Table, Row, Td, TableFooter } from '@/components/table/Table'
import { SortHeader, sortRows, useSort, type SortColumn } from '@/components/table/Sort'
import { date } from '@/lib/format'
import { matchesSearch } from '@/lib/search'
import { useImported } from '@/lib/imports-store'
import { locations, meters } from '@/fixtures/accounts'
import { customerName } from '@/schemas/models'
import type { ImportedData } from '@/lib/assistant/protocol'

export type AccountRow = {
  id: string
  customerNumber: string
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

/** The account list: search by name or address, sort on any column. */
export function AccountsList({ rows: fixtureRows }: { rows: AccountRow[] }) {
  const imported = useImported()
  const rows = useMemo(() => [...fixtureRows, ...importedRows(imported)], [fixtureRows, imported])
  const [query, setQuery] = useState('')
  const { sort, toggle } = useSort<SortKey>({ key: 'ownerName', dir: 'ascending' })

  const shown = useMemo(
    () =>
      sortRows(
        rows.filter((r) => matchesSearch(query, [r.ownerName, r.streetAddress, r.cityLine])),
        sort,
        (r, key) => r[key],
      ),
    [rows, query, sort],
  )

  return (
    <Panel>
      <div className="flex items-center gap-3 border-b border-rule-hair bg-surface px-cell-x py-2">
        <label htmlFor="account-search" className="label-caps">
          Search
        </label>
        <input
          id="account-search"
          type="search"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          placeholder="Owner name or street address…"
          className="h-7 w-80 rounded-xs border border-rule-solid bg-surface-raised px-2 text-data text-ink-primary placeholder:text-ink-muted"
        />
        {query ? (
          <span className="text-micro text-ink-tertiary">
            {shown.length} of {rows.length} match
          </span>
        ) : null}
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
                <span className="block ident text-micro text-ink-tertiary">
                  {r.customerNumber}
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
              <Td className="ident">{r.meterNumber ?? '—'}</Td>
              <Td className="ident" title={r.amrId ? undefined : 'Manually read — no radio endpoint'}>
                {r.amrId ?? <span className="text-ink-muted">—</span>}
              </Td>
            </Row>
          ))}
          {shown.length === 0 ? (
            <Row>
              <Td colSpan={COLUMNS.length} className="py-6 text-center text-ink-tertiary">
                No account matches “{query.trim()}”.
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