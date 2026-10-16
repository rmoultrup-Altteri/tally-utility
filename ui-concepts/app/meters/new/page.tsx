import { AppShell, PageHeader } from '@/components/shell/AppShell'
import { NewMeterForm } from '@/components/records/NewMeterForm'

/** One meter received by hand — into stock, or set at a premise that has none. */
export default async function NewMeterPage({ searchParams }: PageProps<'/meters/new'>) {
  /* New premise and New account link here with ?address=<number>; the form picks it if it is still awaiting a meter. */
  const params = await searchParams
  const premise = typeof params.address === 'string' ? params.address : null
  return (
    <AppShell current="Meters">
      <PageHeader back={{ href: '/meters', label: 'Meters' }} title="New meter" meta="Received into stock or set at a service address" />
      <div className="flex-1 overflow-auto">
        <div className="max-w-5xl px-5 py-5">
          <NewMeterForm premise={premise} />
        </div>
      </div>
    </AppShell>
  )
}
