import { AppShell, PageHeader } from '@/components/shell/AppShell'
import { BillsList, type BillRow, type BillStatus } from '@/components/bills/BillsList'
import { invoices } from '@/fixtures/billing'
import { customerById, locationById } from '@/fixtures/accounts'
import { asOf } from '@/fixtures/tenant'
import { customerName, type Invoice } from '@/schemas/models'
import { count } from '@/lib/format'

/**
 * The bill list — where "Bills" lands before any one bill is open.
 *
 * Status is collapsed to what a CSR says on the phone: current, past due or
 * paid. A bill that was never issued (draft, held) or no longer counts (void)
 * keeps its own word rather than being forced into one of the three — calling
 * a held bill "current" would tell a customer they owe something they were
 * never sent.
 */
function billStatus(invoice: Invoice): BillStatus {
  switch (invoice.status) {
    case 'void':
    case 'write_off':
      return 'void'
    case 'draft':
    case 'pending':
      return 'draft'
    case 'held':
      return 'held'
  }
  if (Number(invoice.balance) <= 0) return 'paid'
  return invoice.due_date < asOf.validAt ? 'past_due' : 'current'
}

const daysBetween = (a: string, b: string) =>
  Math.round((Date.parse(`${b}T00:00:00Z`) - Date.parse(`${a}T00:00:00Z`)) / 86400000)

export default function InvoicesPage() {
  const rows: BillRow[] = invoices.map((inv) => {
    const customer = customerById.get(inv.customer_id)
    const location = locationById.get(inv.location_id)
    return {
      id: inv.id,
      invoiceNumber: inv.invoice_number,
      invoiceDate: inv.invoice_date,
      status: billStatus(inv),
      customerName: customer ? customerName(customer) : '—',
      streetAddress: location?.address ?? null,
      cityLine: location ? `${location.city}, ${location.state} ${location.zip}` : null,
      amountDue: inv.amount_due,
      amountPaid: inv.amount_paid,
      dueDate: inv.due_date,
      /* Same count the bill's own lines carry in days_in_period. */
      daysBilled: daysBetween(inv.period_start, inv.period_end),
    }
  })

  return (
    <AppShell current="Bills">
      <PageHeader title="Bills" meta={`${count(rows.length)} bills on file`} />
      <div className="flex-1 overflow-auto">
        <div className="px-5 py-5">
          <BillsList rows={rows} asOf={asOf.validAt} />
        </div>
      </div>
    </AppShell>
  )
}
