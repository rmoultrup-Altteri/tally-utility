import { Suspense } from 'react'
import { AppShell, PageHeader } from '@/components/shell/AppShell'
import { ReportBuilder } from '@/components/reports/ReportBuilder'
import { customerById, customers, locationById, meterById, meters, serviceLinks } from '@/fixtures/accounts'
import { invoices } from '@/fixtures/billing'
import { historyInvoices } from '@/fixtures/bill-history'
import { exceptions } from '@/fixtures/exceptions'
import { meterDetails } from '@/fixtures/meters'
import { payments } from '@/fixtures/payments'
import { readings } from '@/fixtures/reads'
import {
  accountRows,
  billRows,
  exceptionRows,
  meterRows,
  paymentRows,
  readRows,
  type Lookups,
  type SourceRows,
} from '@/lib/report-builder'

/**
 * Create your own report.
 *
 * A static segment, so it wins over `[reportId]`. The fixture rows for every
 * source are built here and handed down; the builder adds what this browser
 * has imported, created or edited, and reads which saved report to open from
 * `?id=` — the one part that cannot be known at build time, hence the
 * Suspense boundary.
 */
export default function ReportBuilderPage() {
  const lastRead = new Map<string, string>()
  for (const d of meterDetails) if (d.lastReadDate) lastRead.set(d.meterId, d.lastReadDate)
  /* The current cycle's read is newer than anything the meter record remembers. */
  for (const r of readings) if (r.reading_date > (lastRead.get(r.meter_id) ?? '')) lastRead.set(r.meter_id, r.reading_date)

  const lookups: Lookups = {
    customerById,
    locationById,
    meterById,
    links: serviceLinks,
    lastRead,
    nextTest: new Map(meterDetails.flatMap((d) => (d.nextTestDueDate ? [[d.meterId, d.nextTestDueDate] as const] : []))),
  }
  /* The current cycle and the history overlap on nothing today, but a bill must never count twice. */
  const bills = [...new Map([...invoices, ...historyInvoices].map((i) => [i.id, i])).values()]

  const data: SourceRows = {
    accounts: accountRows(customers, lookups),
    bills: billRows(bills, lookups),
    payments: paymentRows(payments, lookups),
    meters: meterRows(meters, lookups),
    reads: readRows(readings, lookups),
    exceptions: exceptionRows(exceptions, lookups),
  }

  return (
    <AppShell current="Reports">
      <Suspense fallback={<PageHeader back={{ href: '/reports', label: 'Reports' }} title="Custom report" meta="Loading…" />}>
        <ReportBuilder data={data} />
      </Suspense>
    </AppShell>
  )
}
