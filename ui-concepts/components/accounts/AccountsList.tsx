'use client'

import { useMemo, useState } from 'react'
import Link from 'next/link'
import type { Route } from 'next'
import { Panel } from '@/components/ui/Panel'
import { Table, Row, Td, TableFooter } from '@/components/table/Table'
import { SortHeader, sortRows, useSort, type SortColumn } from '@/components/table/Sort'
import { date } from '@/lib/format'
import { matchesSearch } from '@/lib/search'

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
export function AccountsList({ rows }: { rows: AccountRow[] }) {
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
                <Link
                  href={`/customers/${r.id}` as Route}
                  className="text-ink-primary font-medium hover:underline"
                >
                  {r.ownerName}
                </Link>
                <span className="block ident text-micro text-ink-tertiary">{r.customerNumber}</span>
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
