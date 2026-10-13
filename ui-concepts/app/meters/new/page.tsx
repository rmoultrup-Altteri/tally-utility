import { AppShell, PageHeader } from '@/components/shell/AppShell'
import { NewMeterForm } from '@/components/records/NewMeterForm'

/** One meter received by hand — into stock, or set at a premise that has none. */
export default function NewMeterPage() {
  return (
    <AppShell current="Meters">
      <PageHeader back={{ href: '/meters', label: 'Meters' }} title="New meter" meta="Received into stock or set at a premise" />
      <div className="flex-1 overflow-auto">
        <div className="max-w-5xl px-5 py-5">
          <NewMeterForm />
        </div>
      </div>
    </AppShell>
  )
}
