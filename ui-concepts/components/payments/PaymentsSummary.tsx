'use client'

import { useMemo, useState } from 'react'
import Link from 'next/link'
import type { Route } from 'next'
import { Panel, PanelHeader } from '@/components/ui/Panel'
import { Money } from '@/components/ui/Money'
import { StateFlag } from '@/components/ui/State'
import { Table, Row, Td, TableFooter } from '@/components/table/Table'
import { SortHeader, sortRows, useSort, type SortColumn } from '@/components/table/Sort'
import type { Payment } from '@/schemas/models'
import type { PaymentStatus } from '@/schemas/enums'
import { count, date, money } from '@/lib/format'
import { matchesSearch } from '@/lib/search'
import { useAddedPayments } from '@/lib/payments-store'
import { CHANNEL, METHOD, STATUS, STATUS_ORDER, cents, fromCents, type CustomerRef, type InvoiceRef } from './vocabulary'

type Choice = PaymentStatus | 'all'

type SortKey = 'paymentNumber' | 'date' | 'customer' | 'street' | 'method' | 'amount'
const COLUMNS: SortColumn<SortKey>[] = [
  { key: 'paymentNumber', label: 'Payment', width: '10rem' },
  { key: 'date', label: 'Date', width: '8rem' },
  { key: 'customer', label: 'Customer' },
  { key: 'street', label: 'Street address' },
  { key: 'method', label: 'Method', width: '10rem' },
  { key: 'amount', label: 'Amount', align: 'right', width: '8rem' },
]

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
      }
    })
  }, [all, pick, query, sort, customers])

  const picked = tiles.find((t) => t.key === pick)

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
                <p className="label-caps">{t.label}</p>
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
          <div className="flex items-center gap-1.5 border-b border-rule-hair bg-surface px-cell-x py-2">
            <label htmlFor="payment-search" className="label-caps">
              Search
            </label>
            <input
              id="payment-search"
              type="search"
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              placeholder="Customer, account, address, payment or check number…"
              className="h-6 w-80 rounded-xs border border-rule-solid bg-surface-raised px-2 text-micro text-ink-primary placeholder:text-ink-muted"
            />
          </div>
          <Table caption={`${picked.label} payments`}>
            <thead>
              <SortHeader columns={COLUMNS} sort={sort} onSort={toggle} />
            </thead>
            <tbody>
              {shown.map((p) => (
                <PaymentLine key={p.id} p={p} customer={customers[p.customer_id]} invoices={invoices} showStatus={pick === 'all'} />
              ))}
              {shown.length === 0 ? (
                <Row>
                  <Td colSpan={6} className="py-6 text-center text-ink-tertiary">
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

/** One payment, with what it paid and — when it did not post — why. */
function PaymentLine({
  p,
  customer,
  invoices,
  showStatus,
}: {
  p: Payment
  customer: CustomerRef | undefined
  invoices: Record<string, InvoiceRef>
  showStatus: boolean
}) {
  const reason =
    p.status === 'nsf'
      ? `${p.nsf_reason} · returned ${date(p.nsf_date)}`
      : p.status === 'reversed'
        ? p.reversed_reason
        : p.status === 'refunded'
          ? p.refund_reason
          : null
  const reference = p.check_number
    ? `Check ${p.check_number}${p.check_bank_name ? ` · ${p.check_bank_name}` : ''}`
    : p.provider_authorization_code
      ? `Auth ${p.provider_authorization_code}`
      : p.reference_number
  return (
    <Row muted={p.status === 'voided'}>
      <Td>
        <span className="ident text-ink-primary">{p.payment_number}</span>
        {showStatus ? (
          <span className="block">
            <StateFlag tone={STATUS[p.status].tone}>{STATUS[p.status].label}</StateFlag>
          </span>
        ) : null}
      </Td>
      <Td className="tabular-nums whitespace-nowrap">{date(p.payment_date)}</Td>
      <Td>
        {customer ? (
          <Link href={`/customers/${customer.id}` as Route} className="text-ink-primary hover:text-accent-text hover:underline">
            {customer.name}
          </Link>
        ) : (
          '—'
        )}
        <span className="block ident text-micro text-ink-tertiary">{customer?.number}</span>
      </Td>
      <Td>
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
      </Td>
      <Td>
        {METHOD[p.payment_method]}
        <span className="block text-micro text-ink-tertiary">
          {CHANNEL[p.channel]}
          {reference ? ` · ${reference}` : ''}
        </span>
      </Td>
      <Td align="right">
        <Money value={p.amount} />
        {cents(p.unapplied_amount) > 0 && p.applications.length > 0 ? (
          <span className="block text-micro text-ink-tertiary">{money(fromCents(cents(p.applied_amount)))} applied</span>
        ) : null}
      </Td>
    </Row>
  )
}
