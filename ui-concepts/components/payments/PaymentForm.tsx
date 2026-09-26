'use client'

import { useEffect, useMemo, useRef, useState } from 'react'
import Link from 'next/link'
import type { Route } from 'next'
import { Button, Panel, PanelHeader } from '@/components/ui/Panel'
import { Money } from '@/components/ui/Money'
import { StateBlock, StateFlag } from '@/components/ui/State'
import type { Payment } from '@/schemas/models'
import type { PaymentChannel, PaymentMethod } from '@/schemas/enums'
import { date, money, stamp } from '@/lib/format'
import { matchesSearch } from '@/lib/search'
import { addPayment, useAddedPayments } from '@/lib/payments-store'
import { CHANNEL, METHOD, STATUS, cents, fromCents, type CustomerRef, type InvoiceRef } from './vocabulary'

export type OpenInvoice = {
  id: string
  number: string
  customerId: string
  billingPeriod: string
  invoiceDate: string
  dueDate: string
  amountDue: string
  balance: string
}

/** A pending payment already against an invoice — shown so nobody takes it twice. */
export type PendingOnInvoice = { paymentNumber: string; amount: string; date: string; method: PaymentMethod }

export type AccountNote = { tone: 'warning' | 'critical' | 'info'; text: string }

const METHODS: PaymentMethod[] = ['cash', 'check', 'money_order', 'credit_card', 'debit_card', 'ach', 'wire', 'other']
const CHANNELS: PaymentChannel[] = ['walk_in', 'agent_phone', 'mail']
/** Dollars and cents. A trailing point ("30.") is accepted, so a total never jumps mid-keystroke. */
const MONEY = /^\d+(\.\d{0,2})?$/

const field = 'h-8 w-full rounded-xs border border-rule-solid bg-surface-raised px-2 text-data text-ink-primary placeholder:text-ink-muted'
const small = 'h-6 rounded-xs border border-rule-solid bg-surface-raised px-1.5 text-micro text-ink-primary placeholder:text-ink-muted'

const daysBetween = (a: string, b: string) =>
  Math.round((Date.parse(`${b}T00:00:00Z`) - Date.parse(`${a}T00:00:00Z`)) / 86400000)

/**
 * Taking a payment.
 *
 * Find the account first — by name, account number, street address or any of
 * its invoice numbers — and its open bills fill in underneath, oldest first. A
 * total typed in the amount is applied to the oldest bill first and the rest
 * carries down the list; changing a line instead makes the amount their total.
 * What is not applied is held on the account as a credit rather than guessed at.
 *
 * No card or bank number is ever typed here. Cards are taken on the terminal
 * or the provider's hosted field and come back as an authorization code; ACH
 * comes back as a trace number. That is the whole of what this system holds.
 */
export function PaymentForm({
  customers,
  invoiceIndex,
  openInvoices,
  pending,
  notes,
  asOf,
  recordedAt,
  by,
  nextSeq,
  initialInvoice = null,
  initialCustomer = null,
}: {
  customers: Record<string, CustomerRef>
  invoiceIndex: InvoiceRef[]
  openInvoices: OpenInvoice[]
  pending: Record<string, PendingOnInvoice[]>
  notes: Record<string, AccountNote[]>
  asOf: string
  /** The prototype's clock. Stamping with the wall clock would put a February payment in September. */
  recordedAt: string
  by: string
  nextSeq: number
  /** Arriving from a bill's Pay bill button: open on that bill's account, that bill first. */
  initialInvoice?: string | null
  /** Arriving from an account's Take payment button: open on that account, amount left to the cashier. */
  initialCustomer?: string | null
}) {
  const added = useAddedPayments()

  const [query, setQuery] = useState('')
  const [customerId, setCustomerId] = useState<string | null>(
    () => invoiceIndex.find((i) => i.id === initialInvoice)?.customerId ?? initialCustomer,
  )
  const [focusInvoice, setFocusInvoice] = useState<string | null>(initialInvoice)

  const [amount, setAmount] = useState('')
  const [paidOn, setPaidOn] = useState(asOf)
  const [method, setMethod] = useState<PaymentMethod>('cash')
  const [channel, setChannel] = useState<PaymentChannel>('walk_in')
  const [tendered, setTendered] = useState('')
  const [checkNumber, setCheckNumber] = useState('')
  const [checkDate, setCheckDate] = useState(asOf)
  const [bank, setBank] = useState('')
  const [authCode, setAuthCode] = useState('')
  const [reference, setReference] = useState('')
  const [memo, setMemo] = useState('')
  const [split, setSplit] = useState<Record<string, string>>({})
  const [manual, setManual] = useState(false)
  /** Lines just cut back to their bill's open balance, so the row can say so. */
  const [capped, setCapped] = useState<string[]>([])
  /** The unapplied cents the customer agreed to leave as a credit. If that amount changes, it must be agreed again. */
  const [creditAgreed, setCreditAgreed] = useState<number | null>(null)
  const [receipt, setReceipt] = useState<Payment | null>(null)

  /* ---- Search ---------------------------------------------------------- */

  const results = useMemo(() => {
    if (query.trim().length < 2) return []
    const byInvoice = new Map<string, string>()
    for (const i of invoiceIndex) if (matchesSearch(query, [i.number])) byInvoice.set(i.customerId, i.id)
    return Object.values(customers)
      .map((c) => ({
        c,
        invoiceId: byInvoice.get(c.id) ?? null,
        hit: byInvoice.has(c.id) || matchesSearch(query, [c.name, c.number, c.street, c.cityLine]),
      }))
      .filter((r) => r.hit)
      .slice(0, 8)
  }, [query, customers, invoiceIndex])

  /* ---- The account's open bills, net of payments taken in this browser ---- */

  const invoices = useMemo(() => {
    if (!customerId) return []
    const postedHere = new Map<string, number>()
    const pendingHere: Record<string, PendingOnInvoice[]> = {}
    for (const p of added)
      for (const a of p.applications) {
        if (p.status === 'posted') postedHere.set(a.invoice_id, (postedHere.get(a.invoice_id) ?? 0) + cents(a.amount))
        if (p.status === 'pending')
          (pendingHere[a.invoice_id] ??= []).push({ paymentNumber: p.payment_number, amount: a.amount, date: p.payment_date, method: p.payment_method })
      }
    return openInvoices
      .filter((i) => i.customerId === customerId)
      .map((i) => ({
        ...i,
        open: cents(i.balance) - (postedHere.get(i.id) ?? 0),
        pending: [...(pending[i.id] ?? []), ...(pendingHere[i.id] ?? [])],
      }))
      .filter((i) => i.open > 0)
      /* Oldest first — the order a payment is applied in, so the table reads top to bottom. */
      .sort((a, b) => a.dueDate.localeCompare(b.dueDate) || a.invoiceDate.localeCompare(b.invoiceDate))
  }, [customerId, openInvoices, pending, added])

  const owed = invoices.reduce((a, i) => a + i.open, 0)

  /* Pay bill: once the bill's open balance is known — after payments taken in
     this browser are netted off — offer exactly that amount, applied to it. */
  const prefilled = useRef(false)
  useEffect(() => {
    if (prefilled.current || !initialInvoice) return
    const bill = invoices.find((i) => i.id === initialInvoice)
    if (!bill) return
    prefilled.current = true
    setAmount(fromCents(bill.open))
    setSplit({ [bill.id]: fromCents(bill.open) })
  }, [initialInvoice, invoices])

  /** Spread an amount over the bills in order, never more than each one owes. */
  const allocate = (total: number) => {
    let left = total
    const next: Record<string, string> = {}
    for (const i of invoices) {
      const take = Math.max(0, Math.min(left, i.open))
      next[i.id] = take > 0 ? fromCents(take) : ''
      left -= take
    }
    return next
  }

  const choose = (id: string, invoiceId: string | null) => {
    setCustomerId(id)
    setFocusInvoice(invoiceId)
    setQuery('')
    setSplit({})
    setManual(false)
    setCapped([])
    setCreditAgreed(null)
    setAmount('')
  }

  /**
   * Typing a total re-spreads it: the oldest bill is paid first and whatever is
   * left moves on to the next, replacing any lines keyed by hand. Whichever of
   * the two was edited last — the total or a line — is the one that holds.
   */
  const onAmount = (v: string) => {
    setAmount(v)
    setManual(false)
    setCapped([])
    setSplit(MONEY.test(v.trim()) ? allocate(cents(v)) : {})
  }

  /**
   * Editing a bill's line makes the lines the source of truth: the payment
   * amount becomes their total, so what is keyed on the bills is what is taken.
   * A line never takes more than its bill still owes — anything typed above
   * that is cut back to the open balance. A line that is not yet a valid amount
   * counts as nothing until it is.
   */
  const onLine = (invoiceId: string, typed: string) => {
    const open = invoices.find((i) => i.id === invoiceId)?.open ?? 0
    const over = MONEY.test(typed.trim()) && cents(typed) > open
    const v = over ? fromCents(open) : typed
    setCapped((c) => [...c.filter((x) => x !== invoiceId), ...(over ? [invoiceId] : [])])
    const next = { ...split, [invoiceId]: v }
    const total = Object.values(next).reduce((a, x) => a + (MONEY.test(x.trim()) ? cents(x) : 0), 0)
    setManual(true)
    setSplit(next)
    setAmount(total > 0 ? fromCents(total) : '')
  }

  /* ---- Validation ------------------------------------------------------ */

  const amountCents = MONEY.test(amount.trim()) ? cents(amount) : null
  const applied = invoices.reduce((a, i) => a + (MONEY.test((split[i.id] ?? '').trim()) ? cents(split[i.id]) : 0), 0)
  const unapplied = amountCents === null ? 0 : amountCents - applied
  /*
   * Money left over is only ever more than the open bills can take: a typed
   * total fills every bill before any is left, and editing a line makes the
   * total their sum. So the only questions are "take less" or "hold a credit".
   */
  const creditOk = unapplied <= 0 || creditAgreed === unapplied
  const customerNotes = customerId ? (notes[customerId] ?? []) : []
  const noChecks = customerNotes.some((n) => n.text.startsWith('Returned check'))

  const problems: string[] = []
  if (!customerId) problems.push('Find the account this payment is for.')
  if (amountCents === null || amountCents <= 0) problems.push('Enter the payment amount in dollars and cents.')
  if (!paidOn) problems.push('Enter the payment date.')
  else if (paidOn > asOf) problems.push('The payment date cannot be after today.')
  if ((method === 'check' || method === 'money_order') && !checkNumber.trim())
    problems.push(method === 'check' ? 'Enter the check number.' : 'Enter the money order serial number.')
  if (method === 'check' && noChecks) problems.push('This account has a returned check on file — take cash, money order or card.')
  if ((method === 'credit_card' || method === 'debit_card') && !/^[A-Za-z0-9]{4,12}$/.test(authCode.trim()))
    problems.push('Enter the authorization code from the card terminal.')
  if ((method === 'ach' || method === 'wire') && !reference.trim()) problems.push('Enter the trace or confirmation number.')
  if (method === 'cash' && tendered && (!MONEY.test(tendered.trim()) || (amountCents !== null && cents(tendered) < amountCents)))
    problems.push('Cash tendered is less than the payment.')
  for (const i of invoices) {
    const v = (split[i.id] ?? '').trim()
    if (!v) continue
    if (!MONEY.test(v)) problems.push(`${i.number}: enter the amount to apply in dollars and cents.`)
  }
  if (amountCents !== null && applied > amountCents) problems.push('More is applied to bills than was paid.')
  if (!creditOk) problems.push(`Decide what to do with the ${money(fromCents(unapplied))} not applied to a bill.`)

  const status = method === 'ach' ? 'pending' : 'posted'

  const post = () => {
    const seq = nextSeq + added.length
    const p: Payment = {
      id: `pmt-local-${seq}`,
      payment_number: `PMT-${paidOn.slice(2, 4)}${paidOn.slice(5, 7)}-${String(seq).padStart(5, '0')}`,
      customer_id: customerId!,
      payment_date: paidOn,
      amount: fromCents(amountCents!),
      payment_method: method,
      channel,
      reference_number: method === 'money_order' ? checkNumber.trim() : reference.trim() || null,
      provider_authorization_code: method === 'credit_card' || method === 'debit_card' ? authCode.trim().toUpperCase() : null,
      check_number: method === 'check' ? checkNumber.trim() : null,
      check_date: method === 'check' ? checkDate || null : null,
      check_bank_name: method === 'check' ? bank.trim() || null : null,
      status,
      applied_amount: fromCents(applied),
      unapplied_amount: fromCents(unapplied),
      is_deposit: false,
      deposit_status: null,
      nsf_date: null,
      nsf_reason: null,
      refund_reason: null,
      reversed_at: null,
      reversed_reason: null,
      notes: memo.trim() || null,
      received_by: by,
      created_at: recordedAt,
      applications: invoices
        .filter((i) => MONEY.test((split[i.id] ?? '').trim()) && cents(split[i.id]) > 0)
        .map((i) => ({ invoice_id: i.id, amount: fromCents(cents(split[i.id])) })),
    }
    addPayment(p)
    setReceipt(p)
  }

  const reset = () => {
    setReceipt(null)
    setCustomerId(null)
    setFocusInvoice(null)
    setAmount('')
    setPaidOn(asOf)
    setMethod('cash')
    setChannel('walk_in')
    setTendered('')
    setCheckNumber('')
    setCheckDate(asOf)
    setBank('')
    setAuthCode('')
    setReference('')
    setMemo('')
    setSplit({})
    setManual(false)
    setCapped([])
    setCreditAgreed(null)
  }

  const customer = customerId ? customers[customerId] : null

  /* ---- Receipt --------------------------------------------------------- */

  if (receipt) {
    const c = customers[receipt.customer_id]
    return (
      <Panel className="max-w-3xl">
        <PanelHeader
          title={`Payment ${receipt.status === 'pending' ? 'submitted' : 'posted'} · ${receipt.payment_number}`}
          actions={<StateFlag tone={STATUS[receipt.status].tone}>{STATUS[receipt.status].label}</StateFlag>}
        />
        <div className="px-4 py-4 space-y-3">
          <p className="text-data text-ink-primary">
            <Money value={receipt.amount} /> from <strong className="font-semibold">{c?.name}</strong> ({c?.number}) by{' '}
            {METHOD[receipt.payment_method].toLowerCase()}, {CHANNEL[receipt.channel].toLowerCase()}, on {date(receipt.payment_date)}.
          </p>
          <ul className="border-y border-rule-hair divide-y divide-rule-hair">
            {receipt.applications.map((a) => {
              const i = invoices.find((x) => x.id === a.invoice_id) ?? openInvoices.find((x) => x.id === a.invoice_id)
              return (
                <li key={a.invoice_id} className="flex justify-between gap-4 py-1.5 text-data">
                  <span>
                    Applied to <span className="ident">{i?.number}</span>
                  </span>
                  <Money value={a.amount} />
                </li>
              )
            })}
            {cents(receipt.unapplied_amount) > 0 ? (
              <li className="flex justify-between gap-4 py-1.5 text-data">
                <span>Held on the account as a credit</span>
                <Money value={receipt.unapplied_amount} />
              </li>
            ) : null}
          </ul>
          {receipt.status === 'pending' ? (
            <StateBlock tone="info">
              <p className="text-data text-ink-primary">
                ACH settles in 2–3 business days. The bills stay open until it does, and the payment shows under Pending.
              </p>
            </StateBlock>
          ) : null}
          <p className="text-micro text-ink-tertiary">
            Received by {receipt.received_by} · {stamp(receipt.created_at)}. Prototype: saved in this browser only until the API lands; bill
            balances elsewhere in the app do not change.
          </p>
          <div className="flex gap-2">
            <Button onClick={() => window.print()}>Print receipt</Button>
            <Button variant="primary" onClick={reset}>
              Take another payment
            </Button>
            <Link href={'/payments' as Route}>
              <Button variant="quiet">Back to payments</Button>
            </Link>
          </div>
        </div>
      </Panel>
    )
  }

  /* ---- Form ------------------------------------------------------------ */

  return (
    <div className="grid grid-cols-1 gap-5 xl:grid-cols-[minmax(0,1fr)_24rem]">
      <div className="space-y-5 min-w-0">
        <Panel>
          <PanelHeader title="1 · Find the account" meta="Customer name, account number, street address or invoice number" />
          <div className="px-4 py-3">
            <label htmlFor="payment-find" className="sr-only">
              Find the account
            </label>
            <input
              id="payment-find"
              type="search"
              autoFocus={!initialInvoice && !initialCustomer}
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              onKeyDown={(e) => {
                if (e.key === 'Enter' && results[0]) choose(results[0].c.id, results[0].invoiceId)
              }}
              placeholder={customer ? `Change account — currently ${customer.name}` : 'e.g. Herrera, 100-248193, 1418 Ashburn, INV-2026-01-004182'}
              className={field}
            />
            {results.length > 0 ? (
              <ul className="mt-2 border border-rule-solid divide-y divide-rule-hair">
                {results.map(({ c, invoiceId }) => (
                  <li key={c.id}>
                    <button
                      type="button"
                      onClick={() => choose(c.id, invoiceId)}
                      className="flex w-full items-baseline justify-between gap-4 px-3 py-2 text-left hover:bg-accent-wash"
                    >
                      <span>
                        <span className="text-data text-ink-primary font-medium">{c.name}</span>
                        <span className="ml-2 ident text-micro text-ink-tertiary">{c.number}</span>
                        <span className="block text-micro text-ink-secondary">
                          {c.street}, {c.cityLine}
                        </span>
                      </span>
                      {invoiceId ? (
                        <span className="ident text-micro text-accent-text">
                          {invoiceIndex.find((i) => i.id === invoiceId)?.number}
                        </span>
                      ) : null}
                    </button>
                  </li>
                ))}
              </ul>
            ) : query.trim().length >= 2 ? (
              <p className="mt-2 text-micro text-ink-tertiary">No account matches “{query.trim()}”.</p>
            ) : null}
          </div>

          {customer ? (
            <div className="border-t border-rule-solid bg-surface px-4 py-3">
              <div className="flex flex-wrap items-baseline justify-between gap-3">
                <div>
                  <Link href={`/customers/${customer.id}` as Route} className="text-h3 text-ink-primary hover:underline">
                    {customer.name}
                  </Link>
                  <span className="ml-2 ident text-ink-tertiary">{customer.number}</span>
                  <p className="text-micro text-ink-secondary">
                    {customer.street}, {customer.cityLine}
                  </p>
                </div>
                <p className="text-data text-ink-secondary">
                  Open on bills: <Money value={fromCents(owed)} arrears={owed > 0} />
                </p>
              </div>
              {customerNotes.map((n) => (
                <p
                  key={n.text}
                  className={`mt-1 text-micro ${n.tone === 'critical' ? 'text-exception-critical-text' : n.tone === 'warning' ? 'text-exception-warning-text' : 'text-exception-info-text'}`}
                >
                  {n.text}
                </p>
              ))}
            </div>
          ) : null}
        </Panel>

        {customer ? (
          <Panel>
            <PanelHeader
              title="2 · Open invoices"
              meta={invoices.length ? 'The amount pays the oldest bill first, then the next — or change any line and the amount follows' : undefined}
              actions={
                manual ? (
                  <button
                    type="button"
                    onClick={() => {
                      setManual(false)
                      setSplit(amountCents ? allocate(amountCents) : {})
                    }}
                    className="text-micro text-accent-text hover:underline"
                  >
                    Reset to oldest first
                  </button>
                ) : null
              }
            />
            {invoices.length === 0 ? (
              <p className="px-4 py-4 text-data text-ink-secondary">
                No open invoices. Anything taken now is held on the account as a credit.
              </p>
            ) : (
              <div className="overflow-x-auto">
                <table className="w-full text-data">
                  <caption className="sr-only">Open invoices for {customer.name}</caption>
                  <thead>
                    <tr className="border-b border-rule-heavy">
                      {['Invoice', 'Bill date', 'Due', 'Past due', 'Open balance', 'Apply'].map((h, i) => (
                        <th key={h} scope="col" className={`label-caps bg-surface-raised px-cell-x py-1.5 font-semibold ${i >= 3 ? 'text-right' : 'text-left'}`}>
                          {h}
                        </th>
                      ))}
                    </tr>
                  </thead>
                  <tbody>
                    {invoices.map((i) => {
                      const late = daysBetween(i.dueDate, asOf)
                      return (
                        <tr key={i.id} className={`border-b border-rule-hair ${i.id === focusInvoice ? 'bg-accent-wash' : 'bg-surface-raised'}`}>
                          <td className="px-cell-x py-cell-y-compact">
                            <Link href={`/invoices/${i.id}` as Route} className="ident text-accent-text hover:underline">
                              {i.number}
                            </Link>
                            <span className="block text-micro text-ink-tertiary">{i.billingPeriod}</span>
                            {i.pending.map((p) => (
                              <span key={p.paymentNumber} className="block text-micro text-exception-info-text">
                                {METHOD[p.method]} {money(p.amount)} pending since {date(p.date)} ({p.paymentNumber})
                              </span>
                            ))}
                          </td>
                          <td className="px-cell-x py-cell-y-compact tabular-nums whitespace-nowrap">{date(i.invoiceDate)}</td>
                          <td className="px-cell-x py-cell-y-compact tabular-nums whitespace-nowrap">{date(i.dueDate)}</td>
                          <td className={`px-cell-x py-cell-y-compact text-right figures ${late > 60 ? 'text-exception-critical-text' : late > 0 ? 'text-exception-warning-text' : 'text-ink-tertiary'}`}>
                            {late > 0 ? `${late}d` : 'Not due'}
                          </td>
                          <td className="px-cell-x py-cell-y-compact text-right">
                            <Money value={fromCents(i.open)} />
                          </td>
                          <td className="px-cell-x py-cell-y-compact text-right">
                            <label htmlFor={`apply-${i.id}`} className="sr-only">
                              Amount to apply to {i.number}
                            </label>
                            <span className="inline-flex items-center gap-1">
                              <span className="text-micro text-ink-tertiary">$</span>
                              <input
                                id={`apply-${i.id}`}
                                inputMode="decimal"
                                value={split[i.id] ?? ''}
                                onChange={(e) => onLine(i.id, e.target.value)}
                                placeholder="0.00"
                                className={`${small} figures w-24 text-right`}
                              />
                              <button
                                type="button"
                                onClick={() => onLine(i.id, fromCents(i.open))}
                                title="Apply the full open balance"
                                className="text-micro text-accent-text hover:underline"
                              >
                                Full
                              </button>
                            </span>
                            {capped.includes(i.id) ? (
                              <span className="block text-micro text-exception-warning-text">
                                Capped at the {money(fromCents(i.open))} it owes
                              </span>
                            ) : null}
                          </td>
                        </tr>
                      )
                    })}
                  </tbody>
                </table>
              </div>
            )}
          </Panel>
        ) : null}
      </div>

      <Panel className="self-start">
        <PanelHeader title="3 · Payment" />
        <div className="space-y-3 px-4 py-3">
          <div className="grid grid-cols-2 gap-3">
            <label className="block">
              <span className="label-caps">Amount *</span>
              <span className="mt-0.5 flex items-center gap-1">
                <span className="text-ink-tertiary">$</span>
                <input inputMode="decimal" autoFocus={Boolean(initialInvoice || initialCustomer)} value={amount} onChange={(e) => onAmount(e.target.value)} placeholder="0.00" className={`${field} figures text-right`} />
              </span>
              {owed > 0 ? (
                <button type="button" onClick={() => onAmount(fromCents(owed))} className="mt-0.5 text-micro text-accent-text hover:underline">
                  Pay all open · {money(fromCents(owed))}
                </button>
              ) : null}
            </label>
            <label className="block">
              <span className="label-caps">Payment date *</span>
              <input type="date" value={paidOn} max={asOf} onChange={(e) => setPaidOn(e.target.value)} className={`${field} mt-0.5`} />
            </label>
          </div>

          <div className="grid grid-cols-2 gap-3">
            <label className="block">
              <span className="label-caps">Method *</span>
              <select value={method} onChange={(e) => setMethod(e.target.value as PaymentMethod)} className={`${field} mt-0.5`}>
                {METHODS.map((m) => (
                  <option key={m} value={m} disabled={m === 'check' && noChecks}>
                    {METHOD[m]}
                    {m === 'check' && noChecks ? ' — not accepted' : ''}
                  </option>
                ))}
              </select>
            </label>
            <label className="block">
              <span className="label-caps">Received *</span>
              <select value={channel} onChange={(e) => setChannel(e.target.value as PaymentChannel)} className={`${field} mt-0.5`}>
                {CHANNELS.map((c) => (
                  <option key={c} value={c}>
                    {CHANNEL[c]}
                  </option>
                ))}
              </select>
            </label>
          </div>

          {method === 'cash' ? (
            <div className="grid grid-cols-2 gap-3">
              <label className="block">
                <span className="label-caps">Cash tendered</span>
                <input inputMode="decimal" value={tendered} onChange={(e) => setTendered(e.target.value)} placeholder="0.00" className={`${field} mt-0.5 figures text-right`} />
              </label>
              <div>
                <span className="label-caps">Change due</span>
                <p className="mt-1.5 figures text-data text-ink-primary">
                  {tendered && MONEY.test(tendered.trim()) && amountCents !== null && cents(tendered) >= amountCents
                    ? money(fromCents(cents(tendered) - amountCents))
                    : '—'}
                </p>
              </div>
            </div>
          ) : null}

          {method === 'check' ? (
            <div className="grid grid-cols-2 gap-3">
              <label className="block">
                <span className="label-caps">Check number *</span>
                <input value={checkNumber} onChange={(e) => setCheckNumber(e.target.value)} className={`${field} mt-0.5 ident`} />
              </label>
              <label className="block">
                <span className="label-caps">Check date</span>
                <input type="date" value={checkDate} onChange={(e) => setCheckDate(e.target.value)} className={`${field} mt-0.5`} />
              </label>
              <label className="col-span-2 block">
                <span className="label-caps">Bank</span>
                <input value={bank} onChange={(e) => setBank(e.target.value)} placeholder="Bank the check is drawn on" className={`${field} mt-0.5`} />
              </label>
            </div>
          ) : null}

          {method === 'money_order' ? (
            <label className="block">
              <span className="label-caps">Money order serial *</span>
              <input value={checkNumber} onChange={(e) => setCheckNumber(e.target.value)} className={`${field} mt-0.5 ident`} />
            </label>
          ) : null}

          {method === 'credit_card' || method === 'debit_card' ? (
            <label className="block">
              <span className="label-caps">Authorization code *</span>
              <input value={authCode} onChange={(e) => setAuthCode(e.target.value)} placeholder="From the card terminal" className={`${field} mt-0.5 ident uppercase`} />
              <span className="text-micro text-ink-tertiary">Run the card on the terminal first. Card numbers are never entered here.</span>
            </label>
          ) : null}

          {method === 'ach' || method === 'wire' ? (
            <label className="block">
              <span className="label-caps">{method === 'ach' ? 'ACH trace number *' : 'Wire confirmation *'}</span>
              <input value={reference} onChange={(e) => setReference(e.target.value)} className={`${field} mt-0.5 ident`} />
              <span className="text-micro text-ink-tertiary">
                {method === 'ach'
                  ? 'Bank details stay with the payment provider. ACH posts as pending until it settles.'
                  : 'From the bank’s incoming-wire notice.'}
              </span>
            </label>
          ) : null}

          {method === 'other' ? (
            <label className="block">
              <span className="label-caps">Reference</span>
              <input value={reference} onChange={(e) => setReference(e.target.value)} className={`${field} mt-0.5`} />
            </label>
          ) : null}

          <label className="block">
            <span className="label-caps">Notes</span>
            <textarea value={memo} onChange={(e) => setMemo(e.target.value)} rows={2} className="mt-0.5 w-full rounded-xs border border-rule-solid bg-surface-raised px-2 py-1 text-data text-ink-primary" />
          </label>

          <dl className="border-y border-rule-hair divide-y divide-rule-hair text-data">
            <div className="flex justify-between py-1.5">
              <dt className="text-ink-secondary">Payment</dt>
              <dd className="figures">{amountCents !== null ? money(fromCents(amountCents)) : '—'}</dd>
            </div>
            <div className="flex justify-between py-1.5">
              <dt className="text-ink-secondary">Applied to bills</dt>
              <dd className="figures">{money(fromCents(applied))}</dd>
            </div>
            <div className="flex justify-between py-1.5">
              <dt className="text-ink-secondary">{unapplied > 0 && creditOk ? 'Credit on account' : 'Not applied to a bill'}</dt>
              <dd className={`figures ${unapplied < 0 ? 'text-exception-critical-text' : unapplied > 0 && !creditOk ? 'text-exception-warning-text' : ''}`}>
                {money(fromCents(unapplied))}
              </dd>
            </div>
          </dl>

          {/* Money that is not on a bill is never parked silently: the customer chooses. */}
          {unapplied > 0 ? (
            <StateBlock tone={creditOk ? 'info' : 'warning'}>
              <p className="text-data text-ink-primary">
                {money(fromCents(unapplied))}{' '}
                {invoices.length ? 'is more than every open bill.' : 'has no open bill to go to.'}
              </p>
              {applied > 0 ? (
                <div className="mt-1.5">
                  <Button onClick={() => setAmount(fromCents(applied))}>Take only {money(fromCents(applied))}</Button>
                </div>
              ) : null}
              <label className="mt-1.5 flex items-start gap-1.5 text-micro text-ink-primary">
                <input
                  type="checkbox"
                  checked={creditAgreed === unapplied}
                  onChange={(e) => setCreditAgreed(e.target.checked ? unapplied : null)}
                  className="mt-0.5"
                />
                <span>
                  Hold {money(fromCents(unapplied))} as a credit on the account — the customer wants it applied to future bills
                </span>
              </label>
            </StateBlock>
          ) : null}

          {problems.length > 0 && (customerId || amount) ? (
            <ul className="space-y-0.5">
              {problems.map((p) => (
                <li key={p} className="text-micro text-exception-critical-text">
                  ✕ {p}
                </li>
              ))}
            </ul>
          ) : null}

          <p className="text-micro text-ink-tertiary">Received by {by}</p>
          <Button variant="primary" disabled={problems.length > 0} onClick={post}>
            {status === 'pending' ? 'Submit ACH payment' : 'Post payment'}
            {amountCents ? ` · ${money(fromCents(amountCents))}` : ''}
          </Button>
        </div>
      </Panel>
    </div>
  )
}
