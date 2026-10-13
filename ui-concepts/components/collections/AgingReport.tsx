'use client'

import { useMemo, useState, type ReactNode } from 'react'
import Link from 'next/link'
import type { Route } from 'next'
import { Panel, PanelHeader } from '@/components/ui/Panel'
import { Money } from '@/components/ui/Money'
import { AccountNumber } from '@/components/ui/RecordLink'
import { Table, Row, Td, TableFooter } from '@/components/table/Table'
import { sortRows, useSort } from '@/components/table/Sort'
import { ColumnHead, ColumnsMenu, useColumns, type ColumnDef } from '@/components/table/Columns'
import { count, date, money } from '@/lib/format'

export type CustomerClass = 'Residential' | 'Commercial' | 'Government'

/** One issued bill with money still owing on it. */
export type OpenBill = {
  id: string
  invoiceNumber: string
  customerId: string
  /** `customers.customer_number`, or null where the bill's customer is not modelled. */
  customerNumber: string | null
  customerName: string
  customerClass: CustomerClass
  streetAddress: string | null
  invoiceDate: string
  dueDate: string
  /** Days past the due date at the as-of coordinate. Zero or negative is not yet due. */
  daysPastDue: number
  /** `invoices.amount_due` — what the bill asked for, before anything was paid on it. */
  amountDue: string
  /** `invoices.amount_paid`. */
  amountPaid: string
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

type SortKey =
  | 'invoiceNumber'
  | 'customerName'
  | 'streetAddress'
  | 'invoiceDate'
  | 'dueDate'
  | 'daysPastDue'
  | 'balance'
  | 'customerNumber'
  | 'customerClass'
  | 'amountDue'
  | 'amountPaid'

/** Money sorts as a number, not as "$1,052" text. */
const MONEY_KEYS = new Set<SortKey>(['balance', 'amountDue', 'amountPaid'])

type BillColumn = ColumnDef<SortKey> & {
  cell: (b: OpenBill) => ReactNode
  className?: string | ((b: OpenBill) => string)
}

/** The shipped seven, then the ones an operator can add from the Columns menu. */
const COLUMNS: BillColumn[] = [
  {
    key: 'invoiceNumber',
    label: 'Bill',
    width: '12rem',
    cell: (b) => (
      <Link href={`/invoices/${b.id}` as Route} className="ident text-accent-text hover:text-accent-text-hover hover:underline">
        {b.invoiceNumber}
      </Link>
    ),
  },
  {
    key: 'customerName',
    label: 'Customer',
    cell: (b) => (
      <>
        <Link href={`/customers/${b.customerId}` as Route} className="text-ink-primary hover:text-accent-text hover:underline">
          {b.customerName}
        </Link>
        <span className="block text-micro text-ink-tertiary">{b.customerClass}</span>
      </>
    ),
  },
  { key: 'streetAddress', label: 'Street address', cell: (b) => b.streetAddress ?? '—' },
  { key: 'invoiceDate', label: 'Bill date', width: '8rem', className: 'tabular-nums whitespace-nowrap', cell: (b) => date(b.invoiceDate) },
  { key: 'dueDate', label: 'Due date', width: '8rem', className: 'tabular-nums whitespace-nowrap', cell: (b) => date(b.dueDate) },
  {
    key: 'daysPastDue',
    label: 'Days past due',
    align: 'right',
    width: '8rem',
    className: (b) => `figures ${b.daysPastDue > 60 ? 'text-exception-critical-text' : ''}`,
    cell: (b) => (b.daysPastDue > 0 ? b.daysPastDue : 'Not due'),
  },
  { key: 'balance', label: 'Balance', align: 'right', width: '8rem', cell: (b) => <Money value={b.balance} arrears={b.daysPastDue > 60} /> },
  {
    key: 'customerNumber',
    label: 'Account number',
    width: '9rem',
    hidden: true,
    cell: (b) => (b.customerNumber ? <AccountNumber number={b.customerNumber} id={b.customerId} /> : '—'),
  },
  { key: 'customerClass', label: 'Class', width: '8rem', hidden: true, cell: (b) => b.customerClass },
  { key: 'amountDue', label: 'Amount due', align: 'right', width: '8rem', hidden: true, cell: (b) => <Money value={b.amountDue} /> },
  { key: 'amountPaid', label: 'Paid', align: 'right', width: '8rem', hidden: true, cell: (b) => <Money value={b.amountPaid} /> },
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
            (b, key) => (MONEY_KEYS.has(key) ? Number(b[key]) : b[key]),
          )
        : [],
    [bills, cell, sort],
  )
  const cols = useColumns('aging-open-bills', COLUMNS)

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
        className={`-mx-1.5 rounded-sm px-1.5 py-0.5 text-right transition-colors duration-fast ${
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

  const th = 'field-label bg-surface-raised px-cell-x py-1.5 font-semibold'

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
          {/* Wraps, so Columns and Close stay reachable on a narrow window. */}
          <div className="flex flex-wrap items-center gap-x-4 gap-y-2 bg-surface px-cell-x py-2">
            <p className="text-data text-ink-primary">
              <span className="font-medium">{label(cell)}</span>
              <span className="ml-2 text-micro text-ink-tertiary">
                {count(selected.length)} bills · <Money value={(sumCents(selected) / 100).toFixed(2)} />
              </span>
            </p>
            <div className="ml-auto flex items-center gap-3">
              <ColumnsMenu cols={cols} />
              <button
                type="button"
                onClick={() => setCell(null)}
                className="text-micro text-ink-secondary underline hover:text-ink-primary"
              >
                Close
              </button>
            </div>
          </div>
          <Table caption={`Open bills — ${label(cell)}`}>
            <thead>
              <ColumnHead cols={cols} sort={sort} onSort={toggle} />
            </thead>
            <tbody>
              {selected.map((b) => (
                <Row key={b.id}>
                  {cols.visible.map((c) => (
                    <Td
                      key={c.key}
                      align={c.align}
                      className={typeof c.className === 'function' ? c.className(b) : c.className}
                    >
                      {c.cell(b)}
                    </Td>
                  ))}
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
