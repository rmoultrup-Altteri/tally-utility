import Link from 'next/link'
import type { Route } from 'next'
import { AppShell, PageHeader } from '@/components/shell/AppShell'
import { Button } from '@/components/ui/Panel'
import { PaymentsSummary } from '@/components/payments/PaymentsSummary'
import { payments } from '@/fixtures/payments'
import { asOf } from '@/fixtures/tenant'
import { customerRefs, invoiceRefs } from '@/lib/payment-refs'
import { count, date } from '@/lib/format'

/**
 * Payments received, summarised by status.
 *
 * Only a posted payment reduces a bill. The other five statuses are money
 * that is on its way, came back, or never counted — which is why they are
 * counted separately rather than folded into one total.
 */
export default function PaymentsPage() {
  return (
    <AppShell current="Payments">
      <PageHeader title="Payments" meta={`${count(payments.length)} payments on file · as of ${date(asOf.validAt)}`} />
      <div className="flex-1 overflow-auto">
        <div className="px-5 py-5 space-y-3">
          <div>
            <Link href={'/payments/new' as Route}>
              <Button variant="primary">+ Add payment</Button>
            </Link>
          </div>
          <PaymentsSummary recorded={payments} customers={customerRefs()} invoices={invoiceRefs()} />
        </div>
      </div>
    </AppShell>
  )
}
