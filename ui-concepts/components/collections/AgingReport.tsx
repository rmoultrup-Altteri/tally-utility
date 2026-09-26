'use client'

import { useMemo, useState } from 'react'
import Link from 'next/link'
import type { Route } from 'next'
import { Panel, PanelHeader } from '@/components/ui/Panel'
import { Money } from '@/components/ui/Money'
import { Table, Row, Td, TableFooter } from '@/components/table/Table'
import { SortHeader, sortRows, useSort, type SortColumn } from '@/components/table/Sort'
import { count, date, money } from '@/lib/format'

export type CustomerClass = 'Residential' | 'Commercial' | 'Government'

/** One issued bill with money still owing on it. */
export type OpenBill = {
  id: string
  invoiceNumber: string
  customerId: string
  customerName: string
  customerClass: CustomerClass
  streetAddress: string | null
  invoiceDate: string
  dueDate: string
  /** Days past the due date at the as-of coordinate. Zero or negative is not yet due. */
  daysPastDue: number
  balance: string
}

type Bucket = { key: string; label: string; test: (days: number) => boolean }

/** Aged by days past the due date, the way the dunning clock counts. */
const BUCKETS: Bucket[] = [
  { key: 'current', label: 'Current', test: (d) => d <= 0 },
  { key: '1-30', label: '1–30 days', test: (d) => d >= 1 && d <= 30 },
  { key: '31-60', label: '31–60 days', test: (d) => d >= 31 && d <= 60 },
  { key: '61-90', label: '61–90 days', test: (d) => d >= 61 && d <= 90 },
  { key: '90+', label: '90+ days', test: (d) => d > 90 },
]
const CLASSES: CustomerClass[] = ['Residential', 'Commercial', 'Government']

/** A drill-down selection. `null` on either axis means every bucket or every class. */
type Cell = { bucket: string | null; cls: CustomerClass | null }

const inCell = (b: OpenBill, c: Cell) =>
  (c.bucket === null || BUCKETS.find((x) => x.key === c.bucket)!.test(b.daysPastDue)) &&
  (c.cls === null || b.customerClass === c.cls)

const sumCents = (bills: OpenBill[]) => bills.reduce((a, b) => a + Math.round(Number(b.balance) * 100), 0)

type SortKey = 'invoiceNumber' | 'customerName' | 'streetAddress' | 'invoiceDate' | 'dueDate' | 'daysPastDue' | 'balance'
const COLUMNS: SortColumn<SortKey>[] = [
  { key: 'invoiceNumber', label: 'Bill', width: '12rem' },
  { key: 'customerName', label: 'Customer' },
  { key: 'streetAddress', label: 'Street address' },
  { key: 'invoiceDate', label: 'Bill date', width: '8rem' },
  { key: 'dueDate', label: 'Due date', width: '8rem' },
  { key: 'daysPastDue', label: 'Days past due', align: 'right', width: '8rem' },
  { key: 'balance', label: 'Balance', align: 'right', width: '8rem' },
]

/**
 * Accounts-receivable aging. Every total is a button: pick one and the bills
 * that make it up are listed under the report, so no figure on it has to be
 * taken on trust.
 */
export function AgingReport({ bills, asOf }: { bills: OpenBill[]; asOf: string }) {
  const [cell, setCell] = useState<Cell | null>(null)
  const { sort, toggle } = useSort<SortKey>({ key: 'daysPastDue', dir: 'descending' })

  const selected = useMemo(
    () =>
      cell
        ? sortRows(
            bills.filter((b) => inCell(b, cell)),
            sort,
            (b, key) => (key === 'balance' ? Number(b.balance) : b[key]),
          )
        : [],
    [bills, cell, sort],
  )

  const total = sumCents(bills)
  const same = (c: Cell) => cell !== null && cell.bucket === c.bucket && cell.cls === c.cls
  const label = (c: Cell) =>
    [c.cls ?? 'All classes', c.bucket ? BUCKETS.find((x) => x.key === c.bucket)!.label : 'all ages'].join(' · ')

  /** A clickable total. Empty cells are plain text — there is nothing behind them to open. */
  const amount = (c: Cell, strong = false) => {
    const matched = bills.filter((b) => inCell(b, c))
    const cents = sumCents(matched)
    if (matched.length === 0) return <span className="figures text-money-zero">{money(0)}</span>
    const on = same(c)
    return (
      <button
        type="button"
        onClick={() => setCell(on ? null : c)}
        aria-pressed={on}
        title={`${count(matched.length)} bills — ${on ? 'hide' : 'show'} them`}
        className={`-mx-1.5 rounded-xs px-1.5 py-0.5 text-right transition-colors duration-fast ${
          on ? 'bg-accent text-ink-inverse' : 'hover:bg-accent-wash'
        }`}
      >
        <span className={`block figures ${strong ? 'font-semibold' : ''} ${on ? '' : 'text-accent-text underline decoration-dotted underline-offset-2'}`}>
          {money(cents / 100)}
        </span>
        <span className={`block text-micro ${on ? 'opacity-80' : 'text-ink-tertiary'}`}>
          {count(matched.length)} {matched.length === 1 ? 'bill' : 'bills'}
        </span>
      </button>
    )
  }

  const th = 'label-caps bg-surface-raised px-cell-x py-1.5 font-semibold'

  return (
    <Panel>
      <PanelHeader
        title="AR aging"
        meta={`Open balances on issued bills, aged by days past due · as of ${date(asOf)}`}
        actions={<span className="text-micro text-ink-secondary">Click any total to see its bills</span>}
      />
      <div className="overflow-x-auto">
        <table className="w-full text-data">
          <caption className="sr-only">Accounts receivable aging by customer class</caption>
          <thead>
            <tr className="border-b border-rule-heavy">
              <th scope="col" className={`${th} text-left`}>
                Customer class
              </th>
              {BUCKETS.map((b) => (
                <th key={b.key} scope="col" className={`${th} text-right`}>
                  {b.label}
                </th>
              ))}
              <th scope="col" className={`${th} text-right border-l border-rule-solid`}>
                Total
              </th>
            </tr>
          </thead>
          <tbody>
            {CLASSES.map((cls) => (
              <tr key={cls} className="border-b border-rule-hair">
                <th scope="row" className="px-cell-x py-cell-y-compact text-left font-normal text-ink-primary">
                  {cls}
                </th>
                {BUCKETS.map((b) => (
                  <td key={b.key} className="px-cell-x py-cell-y-compact text-right">
                    {amount({ bucket: b.key, cls })}
                  </td>
                ))}
                <td className="px-cell-x py-cell-y-compact text-right border-l border-rule-solid">
                  {amount({ bucket: null, cls })}
                </td>
              </tr>
            ))}
            <tr className="border-t border-rule-heavy bg-surface-sunken">
              <th scope="row" className="px-cell-x py-cell-y-compact text-left font-semibold text-ink-primary">
                Total
              </th>
              {BUCKETS.map((b) => (
                <td key={b.key} className="px-cell-x py-cell-y-compact text-right">
                  {amount({ bucket: b.key, cls: null }, true)}
                </td>
              ))}
              <td className="px-cell-x py-cell-y-compact text-right border-l border-rule-solid">
                {amount({ bucket: null, cls: null }, true)}
              </td>
            </tr>
            <tr>
              <th scope="row" className="px-cell-x py-1.5 text-left text-micro font-normal text-ink-tertiary">
                Share of AR
              </th>
              {BUCKETS.map((b) => {
                const cents = sumCents(bills.filter((x) => b.test(x.daysPastDue)))
                return (
                  <td key={b.key} className="px-cell-x py-1.5 text-right text-micro figures text-ink-tertiary">
                    {total ? `${((cents / total) * 100).toFixed(1)}%` : '—'}
                  </td>
                )
              })}
              <td className="px-cell-x py-1.5 text-right text-micro figures text-ink-tertiary border-l border-rule-solid">
                100.0%
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      {cell ? (
        <div className="border-t border-rule-solid">
          <div className="flex items-baseline justify-between gap-4 bg-surface px-cell-x py-2">
            <p className="text-data text-ink-primary">
              <span className="font-medium">{label(cell)}</span>
              <span className="ml-2 text-micro text-ink-tertiary">
                {count(selected.length)} bills · <Money value={(sumCents(selected) / 100).toFixed(2)} />
              </span>
            </p>
            <button
              type="button"
              onClick={() => setCell(null)}
              className="text-micro text-ink-secondary underline hover:text-ink-primary"
            >
              Close
            </button>
          </div>
          <Table caption={`Open bills — ${label(cell)}`}>
            <thead>
              <SortHeader columns={COLUMNS} sort={sort} onSort={toggle} />
            </thead>
            <tbody>
              {selected.map((b) => (
                <Row key={b.id}>
                  <Td>
                    <Link
                      href={`/invoices/${b.id}` as Route}
                      className="ident text-accent-text hover:text-accent-text-hover hover:underline"
                    >
                      {b.invoiceNumber}
                    </Link>
                  </Td>
                  <Td>
                    <Link
                      href={`/customers/${b.customerId}` as Route}
                      className="text-ink-primary hover:text-accent-text hover:underline"
                    >
                      {b.customerName}
                    </Link>
                    <span className="block text-micro text-ink-tertiary">{b.customerClass}</span>
                  </Td>
                  <Td>{b.streetAddress ?? '—'}</Td>
                  <Td className="tabular-nums whitespace-nowrap">{date(b.invoiceDate)}</Td>
                  <Td className="tabular-nums whitespace-nowrap">{date(b.dueDate)}</Td>
                  <Td align="right" className={`figures ${b.daysPastDue > 60 ? 'text-exception-critical-text' : ''}`}>
                    {b.daysPastDue > 0 ? b.daysPastDue : 'Not due'}
                  </Td>
                  <Td align="right">
                    <Money value={b.balance} arrears={b.daysPastDue > 60} />
                  </Td>
                </Row>
              ))}
            </tbody>
          </Table>
          <TableFooter shown={selected.length} total={selected.length} noun="bills" />
        </div>
      ) : null}
    </Panel>
  )
}
