import Link from 'next/link'
import type { Route } from 'next'
import { notFound } from 'next/navigation'
import { AppShell, PageHeader } from '@/components/shell/AppShell'
import { ExplainView } from '@/components/bills/ExplainView'
import { Button } from '@/components/ui/Panel'
import { invoiceById, invoices } from '@/fixtures/billing'
import { customerById } from '@/fixtures/accounts'
import { customerName } from '@/schemas/models'
import { budgetEstimate, explain, usageHistory } from '@/lib/bill-explain'

/**
 * Why this bill changed.
 *
 * The derivation rail on the bill answers "how was this number made". This
 * screen answers the question the customer actually asks — "why is it more
 * than last time" — in plain words, in English or Spanish, with every cause
 * priced exactly. The CSR reads it on the call; the customer reads the same
 * explanation in the portal before they ever call.
 */

export function generateStaticParams() {
  return invoices.filter((i) => i.status !== 'void').map((i) => ({ invoiceId: i.id }))
}

export default async function ExplainPage({ params }: PageProps<'/invoices/[invoiceId]/explain'>) {
  const { invoiceId } = await params
  const invoice = invoiceById.get(invoiceId)
  if (!invoice || invoice.status === 'void') notFound()
  const customer = customerById.get(invoice.customer_id)

  return (
    <AppShell current="Bills">
      <PageHeader
        back={{ href: `/invoices/${invoice.id}`, label: 'The bill' }}
        title="Why this bill changed"
        meta={
          <>
            <Link href={`/invoices/${invoice.id}` as Route} className="ident underline hover:text-ink-secondary">
              {invoice.invoice_number}
            </Link>{' '}
            · {customer ? customerName(customer) : '—'} · {invoice.billing_period}
          </>
        }
        actions={
          <Link href={`/portal/bills/${invoice.id}` as Route}>
            <Button>Customer view</Button>
          </Link>
        }
      />
      <div className="flex-1 overflow-auto">
        <div className="px-5 py-5">
          <ExplainView
            year={explain(invoice, 'year')}
            month={explain(invoice, 'month')}
            points={usageHistory(invoice.customer_id)}
            customerId={invoice.customer_id}
            customerName={customer ? customerName(customer) : 'The customer'}
            amountDue={invoice.amount_due}
            previousBalance={invoice.previous_balance}
            budgetCents={budgetEstimate(invoice.customer_id)}
            invoiceId={invoice.id}
          />
        </div>
      </div>
    </AppShell>
  )
}
