import Link from 'next/link'
import type { Route } from 'next'
import { AppShell, PageHeader } from '@/components/shell/AppShell'
import { PaymentForm, type AccountNote, type OpenInvoice, type PendingOnInvoice } from '@/components/payments/PaymentForm'
import { customers } from '@/fixtures/accounts'
import { invoices } from '@/fixtures/billing'
import { payments } from '@/fixtures/payments'
import { asOf, currentUser } from '@/fixtures/tenant'
import { isIssued } from '@/schemas/models'
import { customerRefs, invoiceRefs } from '@/lib/payment-refs'
import { date } from '@/lib/format'

/** Issued, live bills with money still owing — the only ones a payment can go to. */
function openInvoices(): OpenInvoice[] {
  return invoices
    .filter((i) => isIssued(i) && i.status !== 'void' && i.status !== 'write_off' && Number(i.balance) > 0)
    .map((i) => ({
      id: i.id,
      number: i.invoice_number,
      customerId: i.customer_id,
      billingPeriod: i.billing_period,
      invoiceDate: i.invoice_date,
      dueDate: i.due_date,
      amountDue: i.amount_due,
      balance: i.balance,
    }))
}

function pendingByInvoice(): Record<string, PendingOnInvoice[]> {
  const out: Record<string, PendingOnInvoice[]> = {}
  for (const p of payments.filter((x) => x.status === 'pending'))
    for (const a of p.applications)
      (out[a.invoice_id] ??= []).push({ paymentNumber: p.payment_number, amount: a.amount, date: p.payment_date, method: p.payment_method })
  return out
}

/** What a cashier must know before taking money from this account. */
function accountNotes(): Record<string, AccountNote[]> {
  const out: Record<string, AccountNote[]> = {}
  for (const c of customers) {
    const notes: AccountNote[] = []
    const returned = payments.find((p) => p.customer_id === c.id && p.status === 'nsf')
    if (returned)
      notes.push({
        tone: 'critical',
        text: `Returned check on file (${returned.payment_number}, ${date(returned.nsf_date)}) — accept cash, money order or card only.`,
      })
    if (c.status === 'collections') notes.push({ tone: 'warning', text: 'Account is in collections. Payment in full stops the disconnect process.' })
    if (c.billing_hold) notes.push({ tone: 'info', text: `Billing hold: ${c.billing_hold_reason}` })
    if (notes.length) out[c.id] = notes
  }
  return out
}

export default async function NewPaymentPage({ searchParams }: PageProps<'/payments/new'>) {
  /* Pay bill on a bill page links here with ?invoice=<id>; anything else is ignored. */
  const requested = (await searchParams).invoice
  const refs = invoiceRefs()
  const initialInvoice = typeof requested === 'string' && refs[requested] ? requested : null

  return (
    <AppShell current="Payments">
      <PageHeader
        title="Add payment"
        meta={
          <>
            <Link href={'/payments' as Route} className="underline hover:text-ink-primary">
              Payments
            </Link>{' '}
            · Find the account, apply to its open bills, record how it was paid
          </>
        }
      />
      <div className="flex-1 overflow-auto">
        <div className="px-5 py-5">
          <PaymentForm
            customers={customerRefs()}
            invoiceIndex={Object.values(refs)}
            openInvoices={openInvoices()}
            pending={pendingByInvoice()}
            notes={accountNotes()}
            asOf={asOf.validAt}
            recordedAt={asOf.recordedAt}
            by={currentUser.name}
            nextSeq={1040 + payments.length}
            initialInvoice={initialInvoice}
          />
        </div>
      </div>
    </AppShell>
  )
}
