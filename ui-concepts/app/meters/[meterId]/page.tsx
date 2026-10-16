import Link from 'next/link'
import { notFound } from 'next/navigation'
import { AppShell } from '@/components/shell/AppShell'
import {
  MeterEndpoint,
  MeterEquipment,
  MeterFactors,
  MeterDeployments,
  MeterHeader,
  MeterLifecycle,
  MeterPremise,
  MeterStatusNote,
} from '@/components/meters/MeterDetail'
import { Field, FieldGrid, Panel, PanelHeader } from '@/components/ui/Panel'
import { StateFlag, humanize } from '@/components/ui/State'
import { Table, HeadRow, Th, Row, Td } from '@/components/table/Table'
import { meterById, meters } from '@/fixtures/accounts'
import { endpointHistory, meterDetailById } from '@/fixtures/meters'
import { readings } from '@/fixtures/reads'
import { exceptions } from '@/fixtures/exceptions'
import { asOf } from '@/fixtures/tenant'
import { date, reading } from '@/lib/format'
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
  const reads = readings.filter((r) => r.meter_id === meter.id)
  const latest = reads.at(-1) ?? null
  const lastReadDate = latest?.reading_date ?? detail?.lastReadDate ?? null
  const radios = endpointHistory.filter((e) => e.meterId === meter.id)
  const open = exceptions.filter((e) => e.meter_id === meter.id && e.status !== 'resolved')
  const overdue = !!detail?.nextTestDueDate && detail.nextTestDueDate < asOf.validAt

  return (
    <AppShell current="Meters">
      <MeterHeader
        meter={meter}
        scheduleCode={detail?.rateScheduleCode ?? null}
        read={latest}
        lastReadDate={lastReadDate}
        lastReadValue={latest?.reading_value ?? detail?.lastReadValue ?? null}
      />
      <MeterStatusNote
        meter={meter}
        warehouseLocation={detail?.warehouseLocation ?? null}
        removalDate={detail?.removalDate ?? null}
      />

      <div className="flex-1 overflow-auto">
        <div className="px-5 py-5 space-y-5">
          <div className="grid grid-cols-1 lg:grid-cols-3 gap-5">
            <MeterEquipment meter={meter} detail={detail ?? null} scheduleCode={detail?.rateScheduleCode ?? null} />

            <MeterPremise meter={meter} detail={detail ?? null} />
          </div>

          <div className="grid grid-cols-1 lg:grid-cols-3 gap-5">
            <MeterFactors
              meter={meter}
              detail={detail ?? null}
              lastRead={{ value: latest?.reading_value ?? detail?.lastReadValue ?? null, date: lastReadDate }}
            />

            <MeterEndpoint meter={meter} detail={detail ?? null} />

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

          <MeterLifecycle meter={meter} detail={detail ?? null} />

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
            <MeterDeployments meter={meter} />

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
