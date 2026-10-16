import { AppShell, PageHeader } from '@/components/shell/AppShell'
import { NewPremiseForm } from '@/components/records/NewPremiseForm'

/** One service address added by hand, ahead of its meter and its account. */
export default function NewPremisePage() {
  return (
    <AppShell current="Accounts">
      <PageHeader back={{ href: '/customers', label: 'Accounts' }} title="New service address" meta="A service address with no meter or account yet · * required" />
      <div className="flex-1 overflow-auto">
        <div className="max-w-5xl px-5 py-5">
          <NewPremiseForm />
        </div>
      </div>
    </AppShell>
  )
}
