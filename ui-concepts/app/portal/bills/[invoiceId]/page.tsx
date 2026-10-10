import Link from 'next/link'
import type { Route } from 'next'
import { notFound } from 'next/navigation'
import { PortalBill } from '@/components/bills/PortalBill'
import { ForceLight } from '@/components/shell/ForceLight'
import { invoiceById, invoices } from '@/fixtures/billing'
import { customerById } from '@/fixtures/accounts'
import { customerName } from '@/schemas/models'
import { budgetEstimate, explain, usageHistory } from '@/lib/bill-explain'

/**
 * The customer portal's bill page, previewed from inside Tally.
 *
 * Outside the app shell on purpose: this is the customer's screen, in the
 * utility's brand, at phone width, in the light. A thin staff band on top
 * says whose view this is and leads back, so nobody mistakes the preview for
 * the instrument.
 */

export function generateStaticParams() {
  return invoices.filter((i) => i.status !== 'void').map((i) => ({ invoiceId: i.id }))
}

export default async function PortalBillPage({ params }: PageProps<'/portal/bills/[invoiceId]'>) {
  const { invoiceId } = await params
  const invoice = invoiceById.get(invoiceId)
  if (!invoice || invoice.status === 'void') notFound()
  const customer = customerById.get(invoice.customer_id)
  const name = customer ? customerName(customer) : 'Customer'

  return (
    <div className="min-h-dvh bg-surface-inset">
      <ForceLight />
      <div className="flex items-center justify-between gap-4 bg-surface-ink px-4 py-2 text-micro text-ink-inverse">
        <span>
          Customer portal preview · what <strong className="font-semibold">{name}</strong> sees on their phone
        </span>
        <span className="flex gap-4">
          <Link href={`/invoices/${invoice.id}/explain` as Route} className="underline opacity-90 hover:opacity-100">
            CSR explanation
          </Link>
          <Link href={`/invoices/${invoice.id}` as Route} className="underline opacity-90 hover:opacity-100">
            Back to the bill
          </Link>
        </span>
      </div>
      <div className="px-4 py-5">
        <PortalBill
          e={explain(invoice, 'year') ?? explain(invoice, 'month')}
          firstName={customer?.first_name ?? name}
          amountDue={invoice.amount_due}
          dueDate={invoice.due_date}
          previousBalance={invoice.previous_balance}
          points={usageHistory(invoice.customer_id)}
          budgetCents={budgetEstimate(invoice.customer_id)}
          invoiceNumber={invoice.invoice_number}
        />
      </div>
    </div>
  )
}
