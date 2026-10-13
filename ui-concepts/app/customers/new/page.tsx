import { AppShell, PageHeader } from '@/components/shell/AppShell'
import { NewAccountForm } from '@/components/records/NewAccountForm'

/** One account opened by hand — the counter-side twin of an accounts import. */
export default function NewAccountPage() {
  return (
    <AppShell current="Accounts">
      <PageHeader back={{ href: '/customers', label: 'Accounts' }} title="New account" meta="Customer, service address and meter · * required" />
      <div className="flex-1 overflow-auto">
        <div className="max-w-5xl px-5 py-5">
          <NewAccountForm />
        </div>
      </div>
    </AppShell>
  )
}
