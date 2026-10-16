'use client'

import Link from 'next/link'
import type { Route } from 'next'
import { PageHeader } from '@/components/shell/PageHeader'
import { AccountAlerts, AccountFields, AccountHeader } from '@/components/accounts/AccountDetail'
import { AccountMeterPanel } from '@/components/meters/MeterDetail'
import { Button, Panel, PanelHeader } from '@/components/ui/Panel'
import { StateBlock } from '@/components/ui/State'
import { meterIdFor } from '@/lib/assistant/protocol'
import { useImportedReady } from '@/lib/imports-store'
import { useRecords } from '@/lib/records'

/**
 * An account added in this browser — by hand or through the assistant.
 *
 * The server builds pages only for the fixtures, so this one is drawn from
 * the browser's store. It uses the same header, alerts, fields and meter
 * panel as any account, so Edit, Inactivate and the rest work the same; what
 * it cannot have yet is history — bills, usage and exceptions come with
 * billing, which waits for the API.
 */
export function BrowserAccount({ id }: { id: string }) {
  const ready = useImportedReady()
  const { customerById, locationById, meterById, links } = useRecords()
  const customer = customerById.get(id)

  if (!ready) return <PageHeader back={{ href: '/customers', label: 'Accounts' }} title="Account" meta="Loading…" />
  if (!customer) return <NotHere />

  const link = links.find((l) => l.customerId === customer.id)
  const location = link ? locationById.get(link.locationId) : undefined
  const meterId = meterIdFor(link, links)
  const meter = meterId ? meterById.get(meterId) : undefined
  const premise = location ? `?address=${encodeURIComponent(location.location_number)}` : ''

  return (
    <>
      <AccountHeader
        customer={customer}
        meter={meter}
        location={location}
        actions={
          !meter && location ? (
            <Link href={`/meters/new${premise}` as Route}>
              <Button variant="primary">Set a meter here</Button>
            </Link>
          ) : null
        }
      />

      <AccountAlerts customer={customer} />

      <div className="flex-1 overflow-auto">
        <div className="px-5 py-5 space-y-5">
          <StateBlock tone="info">
            <p className="text-data text-ink-primary">
              Added in this browser and kept here until the API exists. Bills, payments and usage show once the
              account has been billed.
            </p>
          </StateBlock>

          <div className="grid grid-cols-1 lg:grid-cols-3 gap-5">
            <Panel className="lg:col-span-2">
              <PanelHeader title="Account" />
              <div className="px-4 py-4">
                <AccountFields customer={customer} location={location} />
              </div>
            </Panel>

            {meter ? (
              <AccountMeterPanel meter={meter} lastReadDate={null} />
            ) : (
              <Panel>
                <PanelHeader title="Meter" />
                <div className="px-4 py-4 space-y-2">
                  <p className="text-data text-ink-secondary">No meter set at the service address yet.</p>
                  {location ? (
                    <Link href={`/meters/new${premise}` as Route} className="text-data text-accent-text underline hover:text-accent-text-hover">
                      Set a meter here
                    </Link>
                  ) : null}
                </div>
              </Panel>
            )}
          </div>

          <Panel>
            <PanelHeader title="Bills" />
            <p className="px-4 py-5 text-center text-data text-ink-tertiary">No bills yet.</p>
          </Panel>
        </div>
      </div>
    </>
  )
}

function NotHere() {
  return (
    <>
      <PageHeader back={{ href: '/customers', label: 'Accounts' }} title="Account not found" />
      <div className="px-5 py-5">
        <StateBlock tone="warning">
          <p className="text-data text-ink-primary">
            No account with this id is on file or in this browser. An account added in another browser stays
            there until the API exists.
          </p>
        </StateBlock>
      </div>
    </>
  )
}
