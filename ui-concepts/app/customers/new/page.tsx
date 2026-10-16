import { AppShell, PageHeader } from '@/components/shell/AppShell'
import { NewAccountForm } from '@/components/records/NewAccountForm'

/** One account opened by hand — the counter-side twin of an accounts import. */
export default async function NewAccountPage({ searchParams }: PageProps<'/customers/new'>) {
  /* New premise and New meter link here with ?address=<number>. A premise added
     in this browser is not known on the server, so the form looks it up. */
  const params = await searchParams
  const premise = typeof params.address === 'string' ? params.address : null
  return (
    <AppShell current="Accounts">
      <PageHeader back={{ href: '/customers', label: 'Accounts' }} title="New account" meta="Customer, service address and meter · * required" />
      <div className="flex-1 overflow-auto">
        <div className="max-w-5xl px-5 py-5">
          <NewAccountForm premise={premise} />
        </div>
      </div>
    </AppShell>
  )
}
