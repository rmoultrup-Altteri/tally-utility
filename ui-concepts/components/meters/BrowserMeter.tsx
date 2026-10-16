'use client'

import { PageHeader } from '@/components/shell/PageHeader'
import {
  MeterDeployments,
  MeterEndpoint,
  MeterEquipment,
  MeterFactors,
  MeterHeader,
  MeterLifecycle,
  MeterPremise,
  MeterStatusNote,
} from '@/components/meters/MeterDetail'
import { Panel, PanelHeader } from '@/components/ui/Panel'
import { StateBlock } from '@/components/ui/State'
import { useImportedReady } from '@/lib/imports-store'
import { useRecords } from '@/lib/records'

/**
 * A meter added in this browser — by hand or through the assistant.
 *
 * The server builds pages only for the fixtures, so this one is drawn from
 * the browser's store, with the same panels as any meter: Edit, Inactivate
 * and Replace work the same. It has no shop record, test history or reads
 * yet; those arrive with the API and the first route read.
 */
export function BrowserMeter({ id }: { id: string }) {
  const ready = useImportedReady()
  const meter = useRecords().meterById.get(id)

  if (!ready) return <PageHeader back={{ href: '/meters', label: 'Meters' }} title="Meter" meta="Loading…" />
  if (!meter)
    return (
      <>
        <PageHeader back={{ href: '/meters', label: 'Meters' }} title="Meter not found" />
        <div className="px-5 py-5">
          <StateBlock tone="warning">
            <p className="text-data text-ink-primary">
              No meter with this id is on file or in this browser. A meter added in another browser stays there
              until the API exists.
            </p>
          </StateBlock>
        </div>
      </>
    )

  return (
    <>
      <MeterHeader meter={meter} scheduleCode={null} read={null} lastReadDate={null} lastReadValue={null} />
      <MeterStatusNote meter={meter} warehouseLocation={null} removalDate={null} />

      <div className="flex-1 overflow-auto">
        <div className="px-5 py-5 space-y-5">
          <StateBlock tone="info">
            <p className="text-data text-ink-primary">
              Added in this browser and kept here until the API exists. Reads and test history show once the meter
              has been read.
            </p>
          </StateBlock>

          <div className="grid grid-cols-1 lg:grid-cols-3 gap-5">
            <MeterEquipment meter={meter} detail={null} scheduleCode={null} />
            <MeterPremise meter={meter} detail={null} />
          </div>

          <div className="grid grid-cols-1 lg:grid-cols-3 gap-5">
            <MeterFactors meter={meter} detail={null} lastRead={{ value: null, date: null }} />
            <MeterEndpoint meter={meter} detail={null} />
            <Panel>
              <PanelHeader title="Reads" />
              <p className="px-4 py-5 text-center text-data text-ink-tertiary">No reads yet.</p>
            </Panel>
          </div>

          <MeterLifecycle meter={meter} detail={null} />
          <MeterDeployments meter={meter} />
        </div>
      </div>
    </>
  )
}
