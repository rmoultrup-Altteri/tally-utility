'use client'

import { useMemo, useState, type ReactNode } from 'react'
import Link from 'next/link'
import type { Route } from 'next'
import { Panel, PanelHeader } from '@/components/ui/Panel'
import { Money } from '@/components/ui/Money'
import { AccountNumber } from '@/components/ui/RecordLink'
import { StateFlag } from '@/components/ui/State'
import { Table, Row, Td, TableFooter } from '@/components/table/Table'
import { sortRows, useSort } from '@/components/table/Sort'
import { ColumnHead, ColumnsMenu, useColumns, type ColumnDef } from '@/components/table/Columns'
import type { Payment } from '@/schemas/models'
import type { PaymentStatus } from '@/schemas/enums'
import { count, date, money } from '@/lib/format'
import { matchesSearch } from '@/lib/search'
import { useAddedPayments } from '@/lib/payments-store'
import { CHANNEL, METHOD, STATUS, STATUS_ORDER, cents, fromCents, type CustomerRef, type InvoiceRef } from './vocabulary'

type Choice = PaymentStatus | 'all'

type SortKey =
  | 'paymentNumber'
  | 'date'
  | 'customer'
  | 'street'
  | 'method'
  | 'amount'
  | 'status'
  | 'channel'
  | 'reference'
  | 'applied'
  | 'unapplied'

/** What one row's cells draw on: the payment, who paid it, and the bills it went to. */
type Line = {
  p: Payment
  customer: CustomerRef | undefined
  invoices: Record<string, InvoiceRef>
  /** Status under the payment number, when the list mixes statuses and the Status column is off. */
  showStatus: boolean
}

type PaymentColumn = ColumnDef<SortKey> & {
  cell: (l: Line) => ReactNode
  className?: string
}

/**
 * The shipped six, then fields an operator can add from the Columns menu:
 * status as its own column, the channel and reference split out of Method,
 * and the applied and unapplied amounts as sortable figures.
 */
const COLUMNS: PaymentColumn[] = [
  {
    key: 'paymentNumber',
    label: 'Payment',
    width: '10rem',
    cell: ({ p, showStatus }) => (
      <>
        <span className="ident text-ink-primary">{p.payment_number}</span>
        {showStatus ? (
          <span className="block">
            <StateFlag tone={STATUS[p.status].tone}>{STATUS[p.status].label}</StateFlag>
          </span>
        ) : null}
      </>
    ),
  },
  { key: 'date', label: 'Date', width: '8rem', className: 'tabular-nums whitespace-nowrap', cell: ({ p }) => date(p.payment_date) },
  { key: 'customer', label: 'Customer', cell: ({ customer }) => <CustomerCell customer={customer} /> },
  { key: 'street', label: 'Street address', cell: (l) => <StreetCell {...l} /> },
  {
    key: 'method',
    label: 'Method',
    width: '10rem',
    cell: ({ p }) => {
      const ref = reference(p)
      return (
        <>
          {METHOD[p.payment_method]}
          <span className="block text-micro text-ink-tertiary">
            {CHANNEL[p.channel]}
            {ref ? ` · ${ref}` : ''}
          </span>
        </>
      )
    },
  },
  {
    key: 'amount',
    label: 'Amount',
    align: 'right',
    width: '8rem',
    cell: ({ p }) => (
      <>
        <Money value={p.amount} />
        {cents(p.unapplied_amount) > 0 && p.applications.length > 0 ? (
          <span className="block text-micro text-ink-tertiary">{money(fromCents(cents(p.applied_amount)))} applied</span>
        ) : null}
      </>
    ),
  },
  {
    key: 'status',
    label: 'Status',
    width: '7rem',
    hidden: true,
    cell: ({ p }) => <StateFlag tone={STATUS[p.status].tone}>{STATUS[p.status].label}</StateFlag>,
  },
  { key: 'channel', label: 'Channel', width: '9rem', hidden: true, cell: ({ p }) => CHANNEL[p.channel] },
  { key: 'reference', label: 'Reference', hidden: true, className: 'ident', cell: ({ p }) => reference(p) ?? '—' },
  { key: 'applied', label: 'Applied', align: 'right', width: '8rem', hidden: true, cell: ({ p }) => <Money value={p.applied_amount} /> },
  {
    key: 'unapplied',
    label: 'Unapplied',
    menuLabel: 'Unapplied (held on account)',
    align: 'right',
    width: '8rem',
    hidden: true,
    cell: ({ p }) => <Money value={p.unapplied_amount} />,
  },
]

/** The check, card authorization or processor reference that identifies the money. */
function reference(p: Payment): string | null {
  return p.check_number
    ? `Check ${p.check_number}${p.check_bank_name ? ` · ${p.check_bank_name}` : ''}`
    : p.provider_authorization_code
      ? `Auth ${p.provider_authorization_code}`
      : p.reference_number
}

/**
 * Payments by status. Each status shows its count as a button; choosing one
 * lists those payments underneath. Payments taken in this browser on the
 * add-payment page are included alongside the recorded ones.
 */
export function PaymentsSummary({
  recorded,
  customers,
  invoices,
}: {
  recorded: Payment[]
  customers: Record<string, CustomerRef>
  invoices: Record<string, InvoiceRef>
}) {
  const added = useAddedPayments()
  const all = useMemo(() => [...recorded, ...added], [recorded, added])
  const [pick, setPick] = useState<Choice | null>(null)
  const [query, setQuery] = useState('')
  const { sort, toggle } = useSort<SortKey>({ key: 'date', dir: 'descending' })

  const tiles: { key: Choice; label: string; meaning: string; list: Payment[] }[] = [
    ...STATUS_ORDER.map((s) => ({ key: s as Choice, label: STATUS[s].label, meaning: STATUS[s].meaning, list: all.filter((p) => p.status === s) })),
    { key: 'all', label: 'All payments', meaning: 'Every status', list: all },
  ]

  const shown = useMemo(() => {
    if (!pick) return []
    const inPick = pick === 'all' ? all : all.filter((p) => p.status === pick)
    const matched = inPick.filter((p) => {
      const c = customers[p.customer_id]
      return matchesSearch(query, [p.payment_number, c?.name, c?.number, c?.street, p.reference_number, p.check_number])
    })
    return sortRows(matched, sort, (p, key) => {
      const c = customers[p.customer_id]
      switch (key) {
        case 'paymentNumber':
          return p.payment_number
        case 'date':
          return p.payment_date
        case 'customer':
          return c?.name ?? null
        case 'street':
          return c?.street ?? null
        case 'method':
          return METHOD[p.payment_method]
        case 'amount':
          return Number(p.amount)
        case 'status':
          return STATUS_ORDER.indexOf(p.status)
        case 'channel':
          return CHANNEL[p.channel]
        case 'reference':
          return reference(p)
        case 'applied':
          return Number(p.applied_amount)
        case 'unapplied':
          return Number(p.unapplied_amount)
      }
    })
  }, [all, pick, query, sort, customers])

  const picked = tiles.find((t) => t.key === pick)
  const cols = useColumns('payments', COLUMNS)
  /* With the Status column showing, the flag under the number would say it twice. */
  const showStatus = pick === 'all' && cols.isHidden('status')

  return (
    <div className="space-y-5">
      <Panel>
        <PanelHeader title="Payments by status" meta="Choose a count to list those payments" />
        <div className="grid grid-cols-2 gap-px bg-rule-hair sm:grid-cols-4 xl:grid-cols-7">
          {tiles.map((t) => {
            const on = pick === t.key
            const total = t.list.reduce((a, p) => a + cents(p.amount), 0)
            return (
              <div key={t.key} className={`px-4 py-3 ${on ? 'bg-accent-wash' : 'bg-surface-raised'} ${t.key === 'all' ? 'xl:border-l xl:border-rule-solid' : ''}`}>
                <p className="field-label">{t.label}</p>
                <button
                  type="button"
                  onClick={() => setPick(on ? null : t.key)}
                  aria-pressed={on}
                  aria-label={`${t.label}: ${t.list.length} payments — ${on ? 'hide' : 'show'} them`}
                  disabled={t.list.length === 0}
                  className={`mt-0.5 block text-left text-figure figures leading-none transition-colors duration-fast disabled:cursor-default disabled:text-ink-muted ${
                    on ? 'text-accent-text' : 'text-ink-primary hover:text-accent-text enabled:underline enabled:decoration-dotted enabled:underline-offset-4'
                  }`}
                >
                  {count(t.list.length)}
                </button>
                <p className="mt-1 figures text-left text-data text-ink-secondary">{money(total / 100)}</p>
                <p className="text-micro text-ink-tertiary">{t.meaning}</p>
              </div>
            )
          })}
        </div>
      </Panel>

      {picked ? (
        <Panel>
          <PanelHeader
            title={picked.key === 'all' ? 'All payments' : `${picked.label} payments`}
            meta={`${count(shown.length)} shown · ${money(shown.reduce((a, p) => a + cents(p.amount), 0) / 100)}`}
            actions={
              <button type="button" onClick={() => setPick(null)} className="text-micro text-ink-secondary underline hover:text-ink-primary">
                Close
              </button>
            }
          />
          <div className="flex flex-wrap items-center gap-x-1.5 gap-y-2 border-b border-rule-hair bg-surface px-cell-x py-2">
            <label htmlFor="payment-search" className="field-label">
              Search
            </label>
            <input
              id="payment-search"
              type="search"
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              placeholder="Customer, account, address, payment or check number…"
              className="h-6 w-80 rounded-sm border border-rule-solid bg-surface-raised px-2 text-micro text-ink-primary placeholder:text-ink-muted"
            />
            <div className="ml-auto">
              <ColumnsMenu cols={cols} />
            </div>
          </div>
          <Table caption={`${picked.label} payments`}>
            <thead>
              <ColumnHead cols={cols} sort={sort} onSort={toggle} />
            </thead>
            <tbody>
              {shown.map((p) => (
                <PaymentLine
                  key={p.id}
                  line={{ p, customer: customers[p.customer_id], invoices, showStatus }}
                  columns={cols.visible}
                />
              ))}
              {shown.length === 0 ? (
                <Row>
                  <Td colSpan={cols.visible.length} className="py-6 text-center text-ink-tertiary">
                    No payment matches “{query.trim()}”.
                  </Td>
                </Row>
              ) : null}
            </tbody>
          </Table>
          {shown.length > 0 ? <TableFooter shown={shown.length} total={shown.length} noun="payments" /> : null}
        </Panel>
      ) : null}
    </div>
  )
}

/** One payment, its cells in the operator's column order. */
function PaymentLine({ line, columns }: { line: Line; columns: PaymentColumn[] }) {
  return (
    <Row muted={line.p.status === 'voided'}>
      {columns.map((c) => (
        <Td key={c.key} align={c.align} className={c.className}>
          {c.cell(line)}
        </Td>
      ))}
    </Row>
  )
}

/** The customer, linked, with the account number beneath. */
function CustomerCell({ customer }: { customer: CustomerRef | undefined }) {
  if (!customer) return <>—</>
  return (
    <>
      <Link href={`/customers/${customer.id}` as Route} className="text-ink-primary hover:text-accent-text hover:underline">
        {customer.name}
      </Link>
      <span className="block text-micro">
        <AccountNumber number={customer.number} id={customer.id} />
      </span>
    </>
  )
}

/** The street, then what the money did and — when it did not post — why. */
function StreetCell({ p, customer, invoices }: Line) {
  const reason =
    p.status === 'nsf'
      ? `${p.nsf_reason} · returned ${date(p.nsf_date)}`
      : p.status === 'reversed'
        ? p.reversed_reason
        : p.status === 'refunded'
          ? p.refund_reason
          : null
  return (
    <>
      {customer?.street ?? '—'}
      {/* What the money did, under the address it came from. */}
      <span className="block text-micro text-ink-tertiary">
        {p.applications.length > 0
          ? p.applications.map((a, i) => (
              <span key={a.invoice_id}>
                {i > 0 ? ', ' : ''}
                {money(a.amount)} to{' '}
                <Link href={`/invoices/${a.invoice_id}` as Route} className="ident text-accent-text hover:underline">
                  {invoices[a.invoice_id]?.number ?? a.invoice_id}
                </Link>
              </span>
            ))
          : null}
        {Number(p.unapplied_amount) > 0 && p.status === 'posted'
          ? `${p.applications.length ? ' · ' : ''}${money(p.unapplied_amount)} ${p.is_deposit ? 'held as deposit' : 'held on account'}`
          : null}
      </span>
      {reason ? <span className="block text-micro text-exception-warning-text">{reason}</span> : null}
      {p.notes ? <span className="block text-micro text-ink-tertiary">{p.notes}</span> : null}
    </>
  )
}
