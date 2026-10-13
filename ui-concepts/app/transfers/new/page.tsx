import { AppShell, PageHeader } from '@/components/shell/AppShell'
import { TransferForm } from '@/components/transfers/TransferForm'

/** A transfer of service, booked from the Transfers tab or from an account's page. */
export default async function NewTransferPage({ searchParams }: PageProps<'/transfers/new'>) {
  const sp = await searchParams
  const customer = Array.isArray(sp.customer) ? sp.customer[0] : sp.customer
  return (
    <AppShell current="Transfers">
      <PageHeader
        back={{ href: '/transfers', label: 'Transfers' }}
        title="New transfer"
        meta="Move a customer to a new premise without closing their account · * required"
      />
      <div className="flex-1 overflow-auto">
        <div className="max-w-6xl px-5 py-5">
          <TransferForm initialCustomerId={customer ?? null} />
        </div>
      </div>
    </AppShell>
  )
}
