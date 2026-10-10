import { AppShell, PageHeader } from '@/components/shell/AppShell'
import { MetersList, type MeterRow } from '@/components/meters/MetersList'
import { customerById, locationById, meters, serviceLinks } from '@/fixtures/accounts'
import { meterDetailById } from '@/fixtures/meters'
import { readingByMeterId } from '@/fixtures/reads'
import { asOf } from '@/fixtures/tenant'
import { customerName } from '@/schemas/models'

/**
 * The meter list — every meter the utility owns, set at a premise or not.
 *
 * Accounts answer "who"; this answers "what is on the wall". A meter's
 * premise comes from the service link, never the customer, because the meter
 * outlives every occupant of the house it is set at.
 */
export default function MetersPage() {
  const rows: MeterRow[] = meters.map((m) => {
    const link = serviceLinks.find((l) => l.meterId === m.id)
    const detail = meterDetailById.get(m.id)
    const customer = link ? customerById.get(link.customerId) : undefined
    const location = link ? locationById.get(link.locationId) : undefined
    const read = readingByMeterId.get(m.id)
    return {
      id: m.id,
      meterNumber: m.meter_number,
      serialNumber: m.serial_number,
      manufacturer: m.manufacturer,
      model: m.model,
      size: m.size,
      readType: m.read_type,
      endpointId: m.ami_endpoint_id,
      routeId: m.route_id,
      routeSequence: m.route_sequence,
      status: m.status,
      customerId: customer?.id ?? null,
      customerName: customer ? customerName(customer) : null,
      customerNumber: customer?.customer_number ?? null,
      streetAddress: location?.address ?? null,
      cityLine: location ? `${location.city}, ${location.state} ${location.zip}` : null,
      warehouseLocation: detail?.warehouseLocation ?? null,
      lastReadDate: read?.reading_date ?? detail?.lastReadDate ?? null,
      nextTestDueDate: detail?.nextTestDueDate ?? null,
      estimates: m.consecutive_estimate_count,
      endpointSilent: detail?.amiSyncStatus === 'error',
    }
  })

  return (
    <AppShell current="Meters">
      <PageHeader
        title="Meters"
        meta={`${rows.length.toLocaleString('en-US')} meters · ${rows.filter((r) => r.customerId).length} set at a premise`}
      />
      <div className="flex-1 overflow-auto">
        <div className="px-5 py-5">
          <MetersList rows={rows} asOf={asOf.validAt} />
        </div>
      </div>
    </AppShell>
  )
}
