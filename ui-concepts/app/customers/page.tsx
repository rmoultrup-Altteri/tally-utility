import { AppShell, PageHeader } from '@/components/shell/AppShell'
import { AccountsList, type AccountRow } from '@/components/accounts/AccountsList'
import { customers, locationById, meterById, serviceLinks } from '@/fixtures/accounts'
import { customerName } from '@/schemas/models'
import { count } from '@/lib/format'

/**
 * The account list — where "Accounts" lands before any one customer is open.
 *
 * One row per account at its current premise. Search covers the two things a
 * caller actually gives you, their name and their address; everything else is
 * a sort, not a filter.
 */
export default function CustomersPage() {
  const rows: AccountRow[] = customers.map((c) => {
    const link = serviceLinks.find((l) => l.customerId === c.id)
    const location = link ? locationById.get(link.locationId) : undefined
    const meter = link ? meterById.get(link.meterId) : undefined
    return {
      id: c.id,
      customerNumber: c.customer_number,
      createdAt: c.created_at,
      ownerName: customerName(c),
      streetAddress: location?.address ?? null,
      cityLine: location ? `${location.city}, ${location.state} ${location.zip}` : null,
      meterNumber: meter?.meter_number ?? null,
      amrId: meter?.ami_endpoint_id ?? null,
    }
  })

  return (
    <AppShell current="Accounts">
      <PageHeader title="Accounts" meta={`${count(rows.length)} accounts`} />
      <div className="flex-1 overflow-auto">
        <div className="px-5 py-5">
          <AccountsList rows={rows} />
        </div>
      </div>
    </AppShell>
  )
}
