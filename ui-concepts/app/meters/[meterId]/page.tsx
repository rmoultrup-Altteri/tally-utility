import Link from 'next/link'
import type { Route } from 'next'
import { notFound } from 'next/navigation'
import { AppShell } from '@/components/shell/AppShell'
import { AccountStatusFlag, MeterHeader, MeterStatusNote } from '@/components/meters/MeterDetail'
import { sizeLabel } from '@/components/meters/status'
import { Field, FieldGrid, Panel, PanelHeader } from '@/components/ui/Panel'
import { StateFlag, humanize } from '@/components/ui/State'
import { Table, HeadRow, Th, Row, Td } from '@/components/table/Table'
import { AccountNumber } from '@/components/ui/RecordLink'
import { customerById, locationById, meterById, meters, serviceLinks } from '@/fixtures/accounts'
import { deployments, endpointHistory, meterDetailById, meterDetails } from '@/fixtures/meters'
import { readings } from '@/fixtures/reads'
import { rateSchedules } from '@/fixtures/rates'
import { exceptions } from '@/fixtures/exceptions'
import { asOf } from '@/fixtures/tenant'
import { date, factor, reading, stamp } from '@/lib/format'
import { unitLabel } from '@/lib/vocabulary'

/**
 * The meter record — the asset, not the account.
 *
 * Everything a meter shop, a field tech or a CSR needs about one meter: what
 * it is, where it is set and how to reach it, the factors that turn its dials
 * into therms, its radio, its test history, and every premise it has served.
 * The factors are shown exactly as stored, because a multiplier off by one
 * digit is a bill off by an order of magnitude.
 */

export function generateStaticParams() {
  return meters.map((m) => ({ meterId: m.id }))
}

export default async function MeterPage({ params }: PageProps<'/meters/[meterId]'>) {
  const { meterId } = await params
  const meter = meterById.get(meterId)
  if (!meter) notFound()

  const detail = meterDetailById.get(meter.id)
  const link = serviceLinks.find((l) => l.meterId === meter.id)
  const customer = link ? customerById.get(link.customerId) : undefined
  const location = link ? locationById.get(link.locationId) : undefined
  const served = customer && location ? { customer, location } : null
  const reads = readings.filter((r) => r.meter_id === meter.id)
  const latest = reads.at(-1) ?? null
  const lastReadDate = latest?.reading_date ?? detail?.lastReadDate ?? null
  const schedule = rateSchedules.find((s) => s.code === detail?.rateScheduleCode)
  const replaces = detail?.replacesMeterId ? meterById.get(detail.replacesMeterId) : undefined
  const replacedBy = meterDetails.find((d) => d.replacesMeterId === meter.id)
  const replacedByMeter = replacedBy ? meterById.get(replacedBy.meterId) : undefined
  const history = deployments.filter((d) => d.meterId === meter.id)
  const radios = endpointHistory.filter((e) => e.meterId === meter.id)
  const open = exceptions.filter((e) => e.meter_id === meter.id && e.status !== 'resolved')
  const overdue = !!detail?.nextTestDueDate && detail.nextTestDueDate < asOf.validAt
  const atCap = meter.consecutive_estimate_count >= 3

  return (
    <AppShell current="Meters">
      <MeterHeader meter={meter} served={served} read={latest} lastReadDate={lastReadDate} />
      <MeterStatusNote
        meter={meter}
        warehouseLocation={detail?.warehouseLocation ?? null}
        removalDate={detail?.removalDate ?? null}
      />

      <div className="flex-1 overflow-auto">
        <div className="px-5 py-5 space-y-5">
          <div className="grid grid-cols-1 lg:grid-cols-3 gap-5">
            <Panel className="lg:col-span-2">
              <PanelHeader title="Equipment" />
              <div className="px-4 py-4">
                <FieldGrid cols={4}>
                  <Field label="Meter number">
                    <span className="ident">{meter.meter_number}</span>
                  </Field>
                  <Field label="Serial number">
                    <span className="ident">{meter.serial_number ?? '—'}</span>
                  </Field>
                  <Field label="Manufacturer">{meter.manufacturer ?? '—'}</Field>
                  <Field label="Model">{meter.model ?? '—'}</Field>
                  <Field label="Size">{sizeLabel(meter.size)}</Field>
                  <Field label="Dials">{detail?.dialCount ?? '—'}</Field>
                  <Field label="Rollover point" hint="The register wraps to zero here">
                    <span className="ident">{meter.rollover_point ? Number(meter.rollover_point).toLocaleString('en-US') : '—'}</span>
                  </Field>
                  <Field label="Seal number">
                    <span className="ident">{detail?.sealNumber ?? '—'}</span>
                  </Field>
                  <Field label="Service">{humanize(detail?.serviceType ?? 'gas')}</Field>
                  <Field label="Rate schedule">
                    {schedule ? (
                      <>
                        <span className="ident">{schedule.code}</span>
                        <span className="block text-micro text-ink-tertiary">{schedule.name}</span>
                      </>
                    ) : (
                      '—'
                    )}
                  </Field>
                  <Field label="Warranty expires">{date(detail?.warrantyExpiration)}</Field>
                  <Field label="Asset ID">
                    <span className="ident">{detail?.externalId ?? '—'}</span>
                  </Field>
                </FieldGrid>
              </div>
            </Panel>

            <Panel>
              <PanelHeader title={served ? 'Premise' : 'Location'} meta={location?.location_number} />
              <div className="px-4 py-4">
                {served ? (
                  <FieldGrid cols={2}>
                    <Field label="Account">
                      <AccountStatusFlag customer={served.customer} />
                      <span className="block text-micro">
                        <AccountNumber number={served.customer.customer_number} id={served.customer.id} />
                      </span>
                    </Field>
                    <Field label="Service address">
                      {served.location.address}
                      <span className="block text-ink-secondary">
                        {served.location.city}, {served.location.state} {served.location.zip}
                      </span>
                    </Field>
                    <Field label="Billing cycle">{served.location.billing_cycle}</Field>
                    <Field label="Franchise city">{served.location.franchise_city ?? 'None'}</Field>
                    <div className="sm:col-span-2">
                      <Field label="Access notes">{detail?.locationNotes ?? '—'}</Field>
                    </div>
                  </FieldGrid>
                ) : (
                  <FieldGrid cols={2}>
                    <Field label="Stored at">{detail?.warehouseLocation ?? '—'}</Field>
                    <Field label="Premise">Not set at a premise</Field>
                  </FieldGrid>
                )}
              </div>
            </Panel>
          </div>

          <div className="grid grid-cols-1 lg:grid-cols-3 gap-5">
            <Panel>
              <PanelHeader title="Reading and billing factors" />
              <div className="px-4 py-4">
                <FieldGrid cols={2}>
                  <Field label="Read type">{humanize(meter.read_type)}</Field>
                  <Field label="Route">
                    {meter.route_id ? (
                      <span className="ident">
                        {meter.route_id} · {meter.route_sequence}
                      </span>
                    ) : (
                      '—'
                    )}
                  </Field>
                  <Field label="Multiplier" hint="Dial reading × multiplier = volume">
                    <span className="ident">{factor(meter.multiplier)}</span>
                  </Field>
                  <Field
                    label="Pressure factor"
                    hint={detail?.meterFactor && Number(detail.meterFactor) !== 1 ? 'Elevated delivery pressure' : 'Standard delivery pressure'}
                  >
                    <span className="ident">{detail?.meterFactor ? factor(detail.meterFactor) : '—'}</span>
                  </Field>
                  <Field label="BTU factor" hint="Therms per Ccf">
                    <span className="ident">{meter.gas_btu_factor ? factor(meter.gas_btu_factor) : '—'}</span>
                  </Field>
                  <Field label="Last read">
                    {lastReadDate ? (
                      <>
                        <span className="ident">{latest ? reading(latest.reading_value) : detail?.lastReadValue}</span>
                        <span className="block text-micro text-ink-tertiary">{date(lastReadDate)}</span>
                      </>
                    ) : (
                      '—'
                    )}
                  </Field>
                  <Field label="Estimates in a row" hint={atCap ? 'At the Texas cap' : undefined}>
                    <span className={atCap ? 'text-exception-critical-text font-medium' : ''}>
                      {meter.consecutive_estimate_count}
                    </span>
                  </Field>
                  <Field label="Estimation">
                    {detail?.estimationBlocked ? (
                      <>
                        <StateFlag tone="critical">Blocked</StateFlag>
                        <span className="block text-micro text-ink-tertiary mt-1">{detail.estimationBlockedReason}</span>
                      </>
                    ) : (
                      'Allowed'
                    )}
                  </Field>
                </FieldGrid>
              </div>
            </Panel>

            <Panel>
              <PanelHeader title="Endpoint" meta={detail?.amiSystem ?? undefined} />
              <div className="px-4 py-4">
                {meter.ami_endpoint_id ? (
                  <FieldGrid cols={2}>
                    <Field label="Endpoint ID">
                      <span className="ident">{meter.ami_endpoint_id}</span>
                    </Field>
                    <Field label="System">{detail?.amiSystem ?? '—'}</Field>
                    <Field label="Sync">
                      {detail?.amiSyncStatus === 'error' ? (
                        <StateFlag tone="critical">Not reporting</StateFlag>
                      ) : detail?.amiSyncStatus === 'ok' ? (
                        <StateFlag tone="approved">Reporting</StateFlag>
                      ) : (
                        <StateFlag tone="draft">Not configured</StateFlag>
                      )}
                    </Field>
                    <Field label="Last heard">{detail?.amiLastSyncAt ? stamp(detail.amiLastSyncAt) : '—'}</Field>
                    {detail?.amiSyncError ? (
                      <div className="sm:col-span-2">
                        <Field label="Sync error">
                          <span className="text-exception-critical-text">{detail.amiSyncError}</span>
                        </Field>
                      </div>
                    ) : null}
                  </FieldGrid>
                ) : (
                  <p className="text-data text-ink-secondary">
                    Manually read — no radio endpoint is fitted. A route reader keys the dials in the field.
                  </p>
                )}
              </div>
            </Panel>

            <Panel>
              <PanelHeader title="Testing" meta={detail?.testIntervalMonths ? `Every ${detail.testIntervalMonths / 12} years` : undefined} />
              <div className="px-4 py-4">
                <FieldGrid cols={2}>
                  <Field label="Last tested">{date(detail?.lastTestDate)}</Field>
                  <Field label="Result">
                    {detail?.lastTestResult ? (
                      <>
                        <StateFlag tone={detail.lastTestResult === 'pass' ? 'approved' : 'failed'}>
                          {detail.lastTestResult === 'pass' ? 'Pass' : 'Fail'}
                        </StateFlag>
                        {detail.lastTestAccuracy ? (
                          <span className="block text-micro text-ink-tertiary mt-1">Registered {detail.lastTestAccuracy}% of true volume</span>
                        ) : null}
                      </>
                    ) : (
                      '—'
                    )}
                  </Field>
                  <Field label="Next test due" hint={overdue ? 'Overdue — schedule a change-out' : undefined}>
                    <span className={overdue ? 'text-exception-critical-text font-medium' : ''}>
                      {date(detail?.nextTestDueDate)}
                    </span>
                  </Field>
                  <Field label="Interval">{detail?.testIntervalMonths ? `${detail.testIntervalMonths} months` : '—'}</Field>
                </FieldGrid>
              </div>
            </Panel>
          </div>

          <Panel>
            <PanelHeader title="Lifecycle" />
            <div className="px-4 py-4">
              <FieldGrid cols={4}>
                <Field label="Installed">{date(detail?.installDate)}</Field>
                <Field label="In service since">{date(detail?.startDate)}</Field>
                <Field label="Removed">{date(detail?.removalDate)}</Field>
                <Field label="Out of service">{date(detail?.endDate)}</Field>
                <Field label="Replaces">
                  {replaces ? (
                    <Link href={`/meters/${replaces.id}` as Route} className="ident text-accent-text underline hover:text-accent-text-hover">
                      {replaces.meter_number}
                    </Link>
                  ) : (
                    '—'
                  )}
                </Field>
                <Field label="Replaced by">
                  {replacedByMeter ? (
                    <Link href={`/meters/${replacedByMeter.id}` as Route} className="ident text-accent-text underline hover:text-accent-text-hover">
                      {replacedByMeter.meter_number}
                    </Link>
                  ) : (
                    '—'
                  )}
                </Field>
                <div className="sm:col-span-2">
                  <Field label="Swap reason">{detail?.swapReason ?? replacedBy?.swapReason ?? '—'}</Field>
                </div>
              </FieldGrid>
            </div>
          </Panel>

          {open.length > 0 ? (
            <Panel>
              <PanelHeader title="Open exceptions" meta={`${open.length} on this meter`} />
              <ul className="divide-y divide-rule-hair">
                {open.map((e) => (
                  <li key={e.id} className="flex items-baseline gap-3 px-4 py-2.5">
                    <StateFlag tone={e.severity === 'critical' ? 'critical' : 'warning'}>{e.severity}</StateFlag>
                    <span className="text-data text-ink-primary">{e.description}</span>
                    <Link href="/" className="ml-auto text-micro text-accent-text underline">
                      Open in queue
                    </Link>
                  </li>
                ))}
              </ul>
            </Panel>
          ) : null}

          <Panel>
            <PanelHeader title="Reads" meta="This cycle’s reads; earlier reads sit on the premise’s bills" />
            <Table caption="Reads on this meter">
              <thead>
                <HeadRow>
                  <Th>Read date</Th>
                  <Th align="right">Reading</Th>
                  <Th align="right">Previous</Th>
                  <Th align="right">Consumption</Th>
                  <Th>Method</Th>
                  <Th>Validation</Th>
                </HeadRow>
              </thead>
              <tbody>
                {reads.map((r) => (
                  <Row key={r.id}>
                    <Td className="tabular-nums whitespace-nowrap">{date(r.reading_date)}</Td>
                    <Td align="right" className="ident">
                      {reading(r.reading_value)}
                    </Td>
                    <Td align="right" className="ident">
                      {r.previous_value ? reading(r.previous_value) : '—'}
                    </Td>
                    <Td align="right" className="tabular-nums">
                      {r.consumption ? `${Number(r.consumption).toLocaleString('en-US')} ${unitLabel(r.consumption_unit)}` : '—'}
                    </Td>
                    <Td>
                      {r.is_estimated ? <StateFlag tone="warning">Estimated</StateFlag> : humanize(r.read_method)}
                    </Td>
                    <Td>{humanize(r.validation_status)}</Td>
                  </Row>
                ))}
                {reads.length === 0 ? (
                  <Row>
                    <Td colSpan={6} className="py-5 text-center text-ink-tertiary">
                      No reads this cycle.
                    </Td>
                  </Row>
                ) : null}
              </tbody>
            </Table>
          </Panel>

          <div className="grid grid-cols-1 lg:grid-cols-2 gap-5">
            <Panel>
              <PanelHeader title="Premises served" meta={`${history.length} on record`} />
              <Table caption="Every premise this meter has been set at">
                <thead>
                  <HeadRow>
                    <Th>Premise</Th>
                    <Th>Set</Th>
                    <Th>Pulled</Th>
                  </HeadRow>
                </thead>
                <tbody>
                  {history.map((d) => {
                    const loc = locationById.get(d.locationId)
                    return (
                      <Row key={d.deploymentNumber}>
                        <Td>
                          {loc?.address ?? '—'}
                          <span className="block ident text-micro text-ink-tertiary">{loc?.location_number}</span>
                        </Td>
                        <Td className="whitespace-nowrap">
                          {date(d.installDate)}
                          <span className="block text-micro text-ink-tertiary">
                            at <span className="ident">{reading(d.installReadValue)}</span> · {d.installedBy}
                          </span>
                        </Td>
                        <Td>
                          {d.removalDate ? (
                            <>
                              {date(d.removalDate)}
                              <span className="block text-micro text-ink-tertiary">
                                at <span className="ident">{reading(d.removalReadValue ?? '0')}</span> · {d.removalReason}
                              </span>
                            </>
                          ) : (
                            <span className="text-ink-tertiary">Still set</span>
                          )}
                        </Td>
                      </Row>
                    )
                  })}
                  {history.length === 0 ? (
                    <Row>
                      <Td colSpan={3} className="py-5 text-center text-ink-tertiary">
                        Never set at a premise.
                      </Td>
                    </Row>
                  ) : null}
                </tbody>
              </Table>
            </Panel>

            <Panel>
              <PanelHeader title="Endpoint history" meta={`${radios.length} on record`} />
              <Table caption="Radio endpoints fitted to this meter">
                <thead>
                  <HeadRow>
                    <Th>Endpoint</Th>
                    <Th>Fitted</Th>
                    <Th>Removed</Th>
                  </HeadRow>
                </thead>
                <tbody>
                  {radios.map((e) => (
                    <Row key={e.endpointId}>
                      <Td>
                        <span className="ident">{e.endpointId}</span>
                        <span className="block text-micro text-ink-tertiary">{e.endpointType}</span>
                      </Td>
                      <Td className="whitespace-nowrap">
                        {date(e.installDate)}
                        <span className="block text-micro text-ink-tertiary">{e.installedBy}</span>
                      </Td>
                      <Td>
                        {e.removalDate ? (
                          <>
                            {date(e.removalDate)}
                            <span className="block text-micro text-ink-tertiary">{e.removalReason}</span>
                          </>
                        ) : (
                          <span className="text-ink-tertiary">Fitted</span>
                        )}
                      </Td>
                    </Row>
                  ))}
                  {radios.length === 0 ? (
                    <Row>
                      <Td colSpan={3} className="py-5 text-center text-ink-tertiary">
                        No endpoint has been fitted.
                      </Td>
                    </Row>
                  ) : null}
                </tbody>
              </Table>
            </Panel>
          </div>
        </div>
      </div>
    </AppShell>
  )
}
