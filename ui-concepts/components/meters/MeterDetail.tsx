'use client'

import { useState } from 'react'
import Link from 'next/link'
import type { Route } from 'next'
import { PageHeader } from '@/components/shell/PageHeader'
import { Button, Field, FieldGrid, Panel, PanelHeader } from '@/components/ui/Panel'
import { Dialog, EditButton, FormField, fieldClass } from '@/components/ui/Dialog'
import { StateBlock, StateFlag, humanize } from '@/components/ui/State'
import { StatusButton, StatusChangeDialog, type Consequence } from '@/components/ui/StatusChange'
import {
  METER_INACTIVATE_REASONS,
  METER_REACTIVATE_REASONS,
  meterStatus,
  sizeLabel,
} from '@/components/meters/status'
import {
  METER_REASONED,
  changeStatus,
  saveMeter,
  useCustomer,
  useEdits,
  useLastEdit,
  useLastStatusChange,
  useMeter,
  type MeterEdit,
} from '@/lib/edits-store'
import { ReplaceButton, ReplaceMeterDialog } from '@/components/meters/ReplaceMeter'
import { Table, HeadRow, Th, Row, Td } from '@/components/table/Table'
import { AccountNumber } from '@/components/ui/RecordLink'
import {
  replacedBy,
  replacing,
  useLastRead,
  useMeterNow,
  useReplacements,
  useServed,
  useSetAt,
} from '@/lib/replacements'
import { deployments, meterDetailById, meterDetails, type MeterDetail } from '@/fixtures/meters'
import { useRecords } from '@/lib/records'
import { rateSchedules } from '@/fixtures/rates'
import { customerName, type Customer, type Meter, type MeterReading } from '@/schemas/models'
import { date, factor, reading, stamp } from '@/lib/format'

/**
 * The parts of the meter screen that move with its status or an edit. They
 * read the meter through `useMeter`, so an inactivation or a corrected serial
 * shows at once everywhere on the page and in the meter list without a reload.
 */

export function MeterHeader({
  meter: base,
  read,
  lastReadDate,
  lastReadValue,
  scheduleCode,
}: {
  meter: Meter
  read: MeterReading | null
  lastReadDate: string | null
  lastReadValue: string | null
  scheduleCode: string | null
}) {
  const meter = useMeter(base)
  const served = useServed(base.id)
  const lastRead = useLastRead(base.id, { value: lastReadValue, date: lastReadDate })
  const customerEdit = useEdits().customers[served?.customer.id ?? '']
  const customer = served ? { ...served.customer, ...customerEdit } : null
  const changed = useLastStatusChange('meter', base.id)
  const edited = useLastEdit('meter', base.id)
  const reps = useReplacements()
  const [open, setOpen] = useState(false)
  const [editOpen, setEditOpen] = useState(false)
  const [replaceOpen, setReplaceOpen] = useState(false)
  const st = meterStatus(meter.status)
  const replaceable = !!served && (meter.status === 'active' || meter.status === 'inactive')
  /* An exchange schedules with the meter it set; a fixture meter keeps its own. */
  const schedule = replacing(base.id, reps)?.rateScheduleCode ?? scheduleCode
  const verb = meter.status === 'active' ? 'Inactivate' : meter.status === 'inactive' ? 'Reactivate' : null

  const consequences: Consequence[] = []
  if (verb === 'Inactivate') {
    if (customer?.do_not_disconnect)
      consequences.push({
        id: 'dnd',
        tone: 'critical',
        acknowledge: true,
        text: (
          <>
            <strong className="font-semibold">Do-not-disconnect protection</strong> on {customerName(customer)}’s
            account ({humanize(customer.disconnect_protection_type ?? '')}
            {customer.disconnect_protection_expiry ? `, until ${date(customer.disconnect_protection_expiry)}` : ''}).
            Service may be shut off only for safety.
          </>
        ),
      })
    if (customer && served)
      consequences.push({
        id: 'billing',
        tone: 'warning',
        acknowledge: true,
        text: (
          <>
            Serves <strong className="font-semibold">{customerName(customer)}</strong> at {served.location.address}.
            While the meter is inactive no usage bills at this service address; the account’s fixed charges keep billing
            unless the account is inactivated too.
          </>
        ),
      })
    if (read && !read.billing_period_locked && read.validation_status !== 'released_to_billing')
      consequences.push({
        id: 'read',
        tone: 'warning',
        acknowledge: true,
        text: (
          <>
            The read from {date(read.reading_date)} is still {humanize(read.validation_status).toLowerCase()}. Usage
            up to the effective date bills from it, so resolve it in Read validation before the run posts.
          </>
        ),
      })
    consequences.push({
      id: 'route',
      tone: 'info',
      text: (
        <>
          {meter.route_id ? (
            <>
              Route {meter.route_id} skips this meter (sequence {meter.route_sequence})
            </>
          ) : (
            'No route reads this meter'
          )}
          {meter.ami_endpoint_id ? <>, and endpoint {meter.ami_endpoint_id} stops being polled</> : null}. Take a
          shut-off read in the field and lock the valve.
        </>
      ),
    })
  } else if (verb === 'Reactivate') {
    consequences.push({
      id: 'relight',
      tone: 'warning',
      acknowledge: true,
      text: 'A technician has taken a turn-on read, checked for leaks and relit the appliances at the service address.',
    })
    consequences.push({
      id: 'route',
      tone: 'info',
      text: meter.route_id
        ? `Route ${meter.route_id} resumes reading this meter at sequence ${meter.route_sequence}, and usage bills again from the effective date.`
        : 'Usage bills again from the effective date.',
    })
  }

  return (
    <>
      <PageHeader
        back={{ href: '/meters', label: 'Meters' }}
        title={
          <span className="flex items-center gap-3">
            <span>
              Meter <span className="ident">{meter.meter_number}</span>
            </span>
            <StateFlag tone={st.tone}>{st.label}</StateFlag>
          </span>
        }
        meta={
          <>
            <span className="ident">{meter.serial_number ?? '—'}</span> ·{' '}
            {[meter.manufacturer, meter.model].filter(Boolean).join(' ')} · {sizeLabel(meter.size)} ·{' '}
            {humanize(meter.read_type)}
            {edited ? (
              <span title={edited.reason ?? undefined}>
                {' '}
                ·{' '}
                {editVerb(edited.changes.status)} {stamp(edited.at)} by {edited.by}
              </span>
            ) : null}
          </>
        }
        actions={
          <>
            {verb ? <StatusButton verb={verb} onClick={() => setOpen(true)} /> : null}
            {replaceable ? <ReplaceButton onClick={() => setReplaceOpen(true)} /> : null}
            <EditButton onClick={() => setEditOpen(true)} />
          </>
        }
      />
      <EditMeter base={base} current={meter} lastRead={lastRead} open={editOpen} onClose={() => setEditOpen(false)} />
      {replaceable && served ? (
        <ReplaceMeterDialog
          current={meter}
          served={{ customer: customer ?? served.customer, location: served.location }}
          lastRead={lastRead}
          latest={read}
          scheduleCode={schedule}
          open={replaceOpen}
          onClose={() => setReplaceOpen(false)}
        />
      ) : null}
      {verb ? (
        <StatusChangeDialog
          open={open}
          onClose={() => setOpen(false)}
          verb={verb}
          title={`${verb} meter`}
          meta={
            <>
              <span className="ident">{meter.meter_number}</span>
              {served ? ` · ${served.location.address}` : ''}
            </>
          }
          reasons={verb === 'Inactivate' ? METER_INACTIVATE_REASONS : METER_REACTIVATE_REASONS}
          consequences={consequences}
          earliest={verb === 'Inactivate' ? lastRead.date : (changed?.effective ?? null)}
          onConfirm={(reason, effective) =>
            changeStatus('meter', base, verb === 'Inactivate' ? 'inactive' : 'active', reason, effective)
          }
        />
      ) : null}
    </>
  )
}

/** The word for a logged change in the header: a status move names itself, anything else is an edit. */
function editVerb(status: { from: unknown; to: unknown } | undefined): string {
  if (!status) return 'edited'
  if (status.to === 'removed') return 'replaced'
  if (status.from === 'in_stock') return 'set at service address'
  return status.to === 'inactive' ? 'inactivated' : 'reactivated'
}

/** Why the meter is not active, when it is not. */
export function MeterStatusNote({
  meter: base,
  warehouseLocation,
  removalDate,
}: {
  meter: Meter
  warehouseLocation: string | null
  removalDate: string | null
}) {
  const meter = useMeter(base)
  const changed = useLastStatusChange('meter', base.id)
  const out = replacedBy(base.id, useReplacements())
  const { meterById, locationById } = useRecords()
  if (meter.status === 'active') return null
  if (meter.status === 'removed' && out) {
    const next = meterById.get(out.newMeterId)
    const from = locationById.get(out.locationId)
    return (
      <div className="border-b border-rule-hair bg-surface px-5 py-3">
        <StateBlock tone={meterStatus('removed').tone}>
          <p className="text-data text-ink-primary">
            <strong className="font-semibold">Removed {date(out.swapDate)}</strong>
            {from ? <> from {from.address}</> : null} at <span className="ident">{reading(out.removalRead)}</span>
            {next ? (
              <>
                , replaced by <MeterLink meter={next} />
              </>
            ) : null}{' '}
            — {out.reason}. Its reads and bills stay on the service address’s history; send it to the meter shop for test.
          </p>
        </StateBlock>
      </div>
    )
  }
  return (
    <div className="border-b border-rule-hair bg-surface px-5 py-3">
      <StateBlock tone={meterStatus(meter.status).tone}>
        <p className="text-data text-ink-primary">
          {meter.status === 'inactive' ? (
            <>
              <strong className="font-semibold">Inactive</strong>
              {changed?.effective ? <> since {date(changed.effective)}</> : null}
              {changed?.reason ? <> — {changed.reason}</> : null}. The meter is still set at the service address; no usage
              bills and no route reads it until it is reactivated.
            </>
          ) : meter.status === 'in_stock' ? (
            <>
              <strong className="font-semibold">In stock</strong>
              {warehouseLocation ? <> at {warehouseLocation}</> : null}. Tested and ready to set; a service order
              sets it at a service address.
            </>
          ) : (
            <>
              <strong className="font-semibold">Removed</strong>
              {removalDate ? <> {date(removalDate)}</> : null}
              {warehouseLocation ? <>, now at {warehouseLocation}</> : null}. Its reads and bills stay on the
              service address’s history.
            </>
          )}
        </p>
      </StateBlock>
    </div>
  )
}

/**
 * A meter number linking to its record, with its status when it is anything
 * but active. `follow` shows the meter set at the premise now, so an account
 * links to the new meter once its old one has been replaced.
 */
export function MeterLink({ meter: given, follow = false }: { meter: Meter; follow?: boolean }) {
  const now = useMeterNow(given)
  const base = follow ? now : given
  const meter = useMeter(base)
  const st = meterStatus(meter.status)
  return (
    <span className="inline-flex flex-wrap items-center gap-2">
      <Link href={`/meters/${base.id}` as Route} className="ident text-accent-text underline hover:text-accent-text-hover">
        {meter.meter_number}
      </Link>
      {meter.status !== 'active' ? <StateFlag tone={st.tone}>{st.label}</StateFlag> : null}
    </span>
  )
}

/** The served account's status as it stands in this browser. */
export function AccountStatusFlag({ customer: base }: { customer: Customer }) {
  const customer = useCustomer(base)
  return (
    <Link href={`/customers/${base.id}` as Route} className="text-accent-text underline hover:text-accent-text-hover">
      {customerName(customer)}
      {customer.status !== 'active' ? <span className="text-ink-tertiary"> · {humanize(customer.status)}</span> : null}
    </Link>
  )
}

/* ---- The panels that show editable fields ----------------------------- */

export function MeterEquipment({
  meter: base,
  detail,
  scheduleCode,
}: {
  meter: Meter
  detail: MeterDetail | null
  scheduleCode: string | null
}) {
  const meter = useMeter(base)
  const reps = useReplacements()
  const set = replacing(base.id, reps)
  /* The schedule and seal belong to the meter at the premise; a removed meter has neither. */
  const out = replacedBy(base.id, reps)
  const code = out ? null : (set?.rateScheduleCode ?? scheduleCode)
  const schedule = rateSchedules.find((s) => s.code === code)
  const seal = out ? null : (set?.sealNumber ?? detail?.sealNumber)
  return (
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
            <span className="ident">{seal ?? '—'}</span>
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
  )
}

export function MeterFactors({
  meter: base,
  detail,
  lastRead: fixtureRead,
}: {
  meter: Meter
  detail: MeterDetail | null
  lastRead: { value: string | null; date: string | null }
}) {
  const meter = useMeter(base)
  const lastRead = useLastRead(base.id, fixtureRead)
  const atCap = meter.consecutive_estimate_count >= 3
  return (
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
            {lastRead.date ? (
              <>
                <span className="ident">{lastRead.value ? reading(lastRead.value) : '—'}</span>
                <span className="block text-micro text-ink-tertiary">{date(lastRead.date)}</span>
              </>
            ) : (
              '—'
            )}
          </Field>
          <Field label="Estimates in a row" hint={atCap ? 'At the Texas cap' : undefined}>
            <span className={atCap ? 'text-exception-critical-text font-medium' : ''}>{meter.consecutive_estimate_count}</span>
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
  )
}

export function MeterEndpoint({ meter: base, detail }: { meter: Meter; detail: MeterDetail | null }) {
  const meter = useMeter(base)
  return (
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
  )
}

/** Where the meter is: its premise and account, the premise it was taken from, or the shelf. */
export function MeterPremise({ meter: base, detail }: { meter: Meter; detail: MeterDetail | null }) {
  const reps = useReplacements()
  /* Set at a premise, whether or not anyone takes service there yet. */
  const served = useSetAt(base.id)
  const { locationById } = useRecords()
  const out = replacedBy(base.id, reps)
  const set = replacing(base.id, reps)
  const from = out ? locationById.get(out.locationId) : undefined
  /* Access notes belong to the premise; a meter set by exchange inherits its predecessor's. */
  const notes = detail?.locationNotes ?? (set ? meterDetailById.get(set.oldMeterId)?.locationNotes : null) ?? '—'
  return (
    <Panel>
      <PanelHeader title={served ? 'Service address' : 'Location'} meta={(served?.location ?? from)?.location_number} />
      <div className="px-4 py-4">
        {served ? (
          <FieldGrid cols={2}>
            <Field label="Account">
              {served.customer ? (
                <>
                  <AccountStatusFlag customer={served.customer} />
                  <span className="block text-micro">
                    <AccountNumber number={served.customer.customer_number} id={served.customer.id} />
                  </span>
                </>
              ) : (
                <>
                  <span className="text-ink-tertiary">Nobody taking service yet</span>
                  <Link
                    href={`/customers/new?address=${encodeURIComponent(served.location.location_number)}` as Route}
                    className="block text-micro text-accent-text underline hover:text-accent-text-hover"
                  >
                    Open an account here
                  </Link>
                </>
              )}
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
              <Field label="Access notes">{notes}</Field>
            </div>
          </FieldGrid>
        ) : (
          <FieldGrid cols={2}>
            <Field label="Stored at">{out ? 'In transit to the meter shop' : (detail?.warehouseLocation ?? '—')}</Field>
            <Field label="Service address">
              {from ? (
                <>
                  Removed from {from.address}
                  <span className="block text-micro text-ink-tertiary">{date(out!.swapDate)}</span>
                </>
              ) : (
                'Not set at a service address'
              )}
            </Field>
          </FieldGrid>
        )}
      </div>
    </Panel>
  )
}

/** Install, removal and the meters on either side of an exchange. */
export function MeterLifecycle({ meter: base, detail }: { meter: Meter; detail: MeterDetail | null }) {
  const reps = useReplacements()
  const { meterById } = useRecords()
  const out = replacedBy(base.id, reps)
  const set = replacing(base.id, reps)
  const fixtureNext = meterDetails.find((d) => d.replacesMeterId === base.id)
  const replaces = set ? meterById.get(set.oldMeterId) : detail?.replacesMeterId ? meterById.get(detail.replacesMeterId) : undefined
  const replacedByMeter = out ? meterById.get(out.newMeterId) : fixtureNext ? meterById.get(fixtureNext.meterId) : undefined
  const swapReason = set?.reason ?? out?.reason ?? detail?.swapReason ?? fixtureNext?.swapReason ?? '—'
  return (
    <Panel>
      <PanelHeader title="Lifecycle" />
      <div className="px-4 py-4">
        <FieldGrid cols={4}>
          <Field label="Installed">{date(set?.swapDate ?? detail?.installDate)}</Field>
          <Field label="In service since">{date(set?.swapDate ?? detail?.startDate)}</Field>
          <Field label="Removed">{date(out?.swapDate ?? detail?.removalDate)}</Field>
          <Field label="Out of service">{date(out?.swapDate ?? detail?.endDate)}</Field>
          <Field label="Replaces">{replaces ? <MeterLink meter={replaces} /> : '—'}</Field>
          <Field label="Replaced by">{replacedByMeter ? <MeterLink meter={replacedByMeter} /> : '—'}</Field>
          <div className="sm:col-span-2">
            <Field label="Swap reason">{swapReason}</Field>
          </div>
        </FieldGrid>
      </div>
    </Panel>
  )
}

type DeploymentRow = {
  key: string
  locationId: string
  /* Unknown for a meter set when it was added in this browser: no set order recorded it. */
  installDate: string | null
  installReadValue: string | null
  installedBy: string | null
  removalDate: string | null
  removalReadValue: string | null
  removalReason: string | null
}

/** Every premise the meter has been set at, with exchanges made in this browser applied in order. */
export function MeterDeployments({ meter: base }: { meter: Meter }) {
  const reps = useReplacements()
  const { locationById, links } = useRecords()
  const rows: DeploymentRow[] = deployments
    .filter((d) => d.meterId === base.id)
    .map((d) => ({ ...d, key: String(d.deploymentNumber) }))
  /* A meter set at a premise when it was added in this browser has a link but no deployment row. */
  const addedAt = rows.length ? null : links.find((l) => l.meterId === base.id)
  if (addedAt)
    rows.push({
      key: 'added',
      locationId: addedAt.locationId,
      installDate: null,
      installReadValue: null,
      installedBy: null,
      removalDate: null,
      removalReadValue: null,
      removalReason: null,
    })
  for (const r of reps) {
    if (r.newMeterId === base.id)
      rows.push({
        key: `swap-${r.at}`,
        locationId: r.locationId,
        installDate: r.swapDate,
        installReadValue: r.installRead,
        installedBy: r.technician,
        removalDate: null,
        removalReadValue: null,
        removalReason: null,
      })
    if (r.oldMeterId === base.id) {
      const open = rows.findLast((d) => d.removalDate === null)
      if (open) Object.assign(open, { removalDate: r.swapDate, removalReadValue: r.removalRead, removalReason: r.reason })
    }
  }
  return (
    <Panel>
      <PanelHeader title="Service addresses served" meta={`${rows.length} on record`} />
      <Table caption="Every service address this meter has been set at">
        <thead>
          <HeadRow>
            <Th>Service address</Th>
            <Th>Set</Th>
            <Th>Pulled</Th>
          </HeadRow>
        </thead>
        <tbody>
          {rows.map((d) => {
            const loc = locationById.get(d.locationId)
            return (
              <Row key={d.key}>
                <Td>
                  {loc?.address ?? '—'}
                  <span className="block ident text-micro text-ink-tertiary">{loc?.location_number}</span>
                </Td>
                <Td className="whitespace-nowrap">
                  {d.installDate ? date(d.installDate) : <span className="text-ink-tertiary">Set when added</span>}
                  {d.installReadValue ? (
                    <span className="block text-micro text-ink-tertiary">
                      at <span className="ident">{reading(d.installReadValue)}</span> · {d.installedBy}
                    </span>
                  ) : null}
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
          {rows.length === 0 ? (
            <Row>
              <Td colSpan={3} className="py-5 text-center text-ink-tertiary">
                Never set at a service address.
              </Td>
            </Row>
          ) : null}
        </tbody>
      </Table>
    </Panel>
  )
}

/** The meter panel on an account: the meter set at its premise now, with edits and exchanges applied. */
export function AccountMeterPanel({
  meter: given,
  lastReadDate,
}: {
  meter: Meter | undefined
  lastReadDate: string | null
}) {
  const now = useMeterNow(given)
  const edits = useEdits().meters
  const meter = now ? { ...now, ...edits[now.id] } : undefined
  const lastRead = useLastRead(meter?.id ?? '', { value: null, date: lastReadDate })
  const atCap = (meter?.consecutive_estimate_count ?? 0) >= 3
  return (
    <Panel>
      <PanelHeader title="Meter" meta={meter?.route_id ?? undefined} />
      <div className="px-4 py-4">
        <FieldGrid cols={2}>
          <Field label="Meter">{given ? <MeterLink meter={given} follow /> : '—'}</Field>
          <Field label="Read type">{humanize(meter?.read_type ?? '')}</Field>
          <Field label="Multiplier">{meter?.multiplier ?? '—'}</Field>
          <Field label="BTU factor">{meter?.gas_btu_factor ?? '—'}</Field>
          <Field label="Last read">{lastRead.date ? date(lastRead.date) : '—'}</Field>
          <Field label="Estimates in a row" hint={atCap ? 'At the Texas cap' : undefined}>
            <span className={atCap ? 'text-exception-critical-text font-medium' : ''}>{meter?.consecutive_estimate_count ?? 0}</span>
          </Field>
        </FieldGrid>
      </div>
    </Panel>
  )
}

/* ---- The edit form --------------------------------------------------- */

const SIZES = ['3/4_inch', '1_inch', '1.5_inch', '2_inch', '3_inch', '4_inch']
const READ_TYPES = ['amr', 'ami', 'manual']
const FACTOR_LABELS: Record<(typeof METER_REASONED)[number], string> = {
  multiplier: 'Multiplier',
  gas_btu_factor: 'BTU factor',
  rollover_point: 'Rollover point',
}

type Draft = {
  serial_number: string
  manufacturer: string
  model: string
  size: string
  read_type: string
  ami_endpoint_id: string
  multiplier: string
  gas_btu_factor: string
  rollover_point: string
  route_id: string
  route_sequence: string
  reason: string
  effective: string
}

function draftFrom(m: Meter): Draft {
  return {
    serial_number: m.serial_number ?? '',
    manufacturer: m.manufacturer ?? '',
    model: m.model ?? '',
    size: m.size ?? '',
    read_type: m.read_type,
    ami_endpoint_id: m.ami_endpoint_id ?? '',
    multiplier: m.multiplier,
    gas_btu_factor: m.gas_btu_factor ?? '',
    rollover_point: m.rollover_point ?? '',
    route_id: m.route_id ?? '',
    route_sequence: m.route_sequence == null ? '' : String(m.route_sequence),
    reason: '',
    effective: '',
  }
}

const blank = (s: string) => (s.trim() === '' ? null : s.trim())
const isDecimal = (s: string) => /^\d+(\.\d+)?$/.test(s.trim())

/**
 * A factor as typed, kept as stored when it is the same number: `1` over
 * `1.0000` is not a change, and must not demand a reason.
 */
function sameDecimal(typed: string, was: string | null): string | null {
  const t = blank(typed)
  if (t === null) return null
  return was !== null && isDecimal(t) && Number(t) === Number(was) ? was : t
}

/** The draft as the edit it would save. A manual meter has no endpoint; no route, no sequence. */
function toEdit(d: Draft, current: Meter): MeterEdit {
  const route = blank(d.route_id)?.toUpperCase() ?? null
  return {
    serial_number: blank(d.serial_number),
    manufacturer: blank(d.manufacturer),
    model: blank(d.model),
    size: blank(d.size),
    read_type: d.read_type,
    ami_endpoint_id: d.read_type === 'manual' ? null : blank(d.ami_endpoint_id),
    multiplier: sameDecimal(d.multiplier, current.multiplier) ?? '',
    gas_btu_factor: sameDecimal(d.gas_btu_factor, current.gas_btu_factor),
    rollover_point: sameDecimal(d.rollover_point, current.rollover_point),
    route_id: route,
    route_sequence: route && d.route_sequence.trim() ? Number(d.route_sequence) : null,
  }
}

function validate(d: Draft, current: Meter, lastReadValue: string | null): Partial<Record<keyof Draft, string>> {
  const e: Partial<Record<keyof Draft, string>> = {}
  if (!d.multiplier.trim()) e.multiplier = 'Enter the multiplier — 1 when the dials read volume directly'
  else if (!isDecimal(d.multiplier) || Number(d.multiplier) <= 0) e.multiplier = 'Enter a positive number like 1.0000 or 10'
  if (d.gas_btu_factor.trim() && (!isDecimal(d.gas_btu_factor) || Number(d.gas_btu_factor) <= 0))
    e.gas_btu_factor = 'Enter a positive number like 1.0350'
  if (d.rollover_point.trim()) {
    if (!/^\d+$/.test(d.rollover_point.trim()) || Number(d.rollover_point) <= 0)
      e.rollover_point = 'Enter a whole number like 100000'
    else if (lastReadValue && Number(d.rollover_point) <= Number(lastReadValue))
      e.rollover_point = `Must be above the last reading, ${reading(lastReadValue)}`
  }
  if (d.route_id.trim()) {
    if (!d.route_sequence.trim()) e.route_sequence = 'Enter where on the route this meter is read'
    else if (!/^\d+$/.test(d.route_sequence.trim()) || Number(d.route_sequence) <= 0)
      e.route_sequence = 'Enter a whole number like 212'
  }
  const edit = toEdit(d, current)
  if (METER_REASONED.some((k) => edit[k] !== current[k])) {
    if (!d.reason.trim()) e.reason = 'A factor change needs a reason on record'
    if (!d.effective) e.effective = 'Enter the date the new factor takes effect'
  }
  return e
}

function EditMeter({
  base,
  current,
  lastRead,
  open,
  onClose,
}: {
  base: Meter
  current: Meter
  lastRead: { value: string | null; date: string | null }
  open: boolean
  onClose: () => void
}) {
  const [draft, setDraft] = useState<Draft>(() => draftFrom(current))
  const [errors, setErrors] = useState<Partial<Record<keyof Draft, string>>>({})
  const [notice, setNotice] = useState<string | null>(null)
  const [lastOpen, setLastOpen] = useState(open)

  /* Each opening starts from the meter as it stands now. */
  if (open !== lastOpen) {
    setLastOpen(open)
    if (open) {
      setDraft(draftFrom(current))
      setErrors({})
      setNotice(null)
    }
  }

  const set = <K extends keyof Draft>(k: K, v: Draft[K]) => {
    setDraft((d) => ({ ...d, [k]: v }))
    if (errors[k]) setErrors((e) => ({ ...e, [k]: undefined }))
    setNotice(null)
  }

  const edit = toEdit(draft, current)
  const factorChanges = METER_REASONED.filter((k) => edit[k] !== current[k])
  const needsReason = factorChanges.length > 0
  const manual = draft.read_type === 'manual'
  const backdated = needsReason && !!draft.effective && !!lastRead.date && draft.effective <= lastRead.date

  function save() {
    const found = validate(draft, current, lastRead.value)
    setErrors(found)
    if (Object.keys(found).length) return
    const changed = saveMeter(base, edit, needsReason ? draft.reason.trim() : null, needsReason ? draft.effective : null)
    if (!changed) {
      setNotice('Nothing has changed yet.')
      return
    }
    onClose()
  }

  const input = (k: keyof Draft, props: React.InputHTMLAttributes<HTMLInputElement> = {}) => (
    <input
      id={`mtr-${k}`}
      value={draft[k]}
      onChange={(e) => set(k, e.target.value)}
      aria-invalid={errors[k] ? true : undefined}
      aria-describedby={errors[k] ? `mtr-${k}-error` : undefined}
      className={fieldClass}
      autoComplete="off"
      {...props}
    />
  )

  const sizes = draft.size && !SIZES.includes(draft.size) ? [draft.size, ...SIZES] : SIZES
  const shown = (k: (typeof METER_REASONED)[number], v: string | null | undefined) =>
    v ? (k === 'rollover_point' ? Number(v).toLocaleString('en-US') : factor(v)) : 'none'

  return (
    <Dialog
      open={open}
      onClose={onClose}
      title="Edit meter"
      meta={
        <>
          <span className="ident">{base.meter_number}</span> · {meterStatus(current.status).label}
        </>
      }
      footer={
        <>
          {notice ? <span className="mr-auto text-micro text-ink-tertiary">{notice}</span> : null}
          <Button variant="quiet" onClick={onClose}>
            Cancel
          </Button>
          <Button variant="primary" onClick={save}>
            Save changes
          </Button>
        </>
      }
    >
      <form
        onSubmit={(e) => {
          e.preventDefault()
          save()
        }}
        className="space-y-5"
      >
        <StateBlock tone="info" className="px-3! py-2.5!">
          <p className="text-data text-ink-primary">
            This corrects the record. If a different meter went in at the service address, use{' '}
            <strong className="font-semibold">Replace meter</strong> instead, so the old meter keeps its reads and
            the bill splits at the swap.
          </p>
        </StateBlock>
        <fieldset className="space-y-3">
          <legend className="text-h3 text-ink-primary mb-2">Equipment</legend>
          <FormField label="Serial number" htmlFor="mtr-serial_number">
            {input('serial_number')}
          </FormField>
          <div className="grid grid-cols-2 gap-3">
            <FormField label="Manufacturer" htmlFor="mtr-manufacturer">
              {input('manufacturer')}
            </FormField>
            <FormField label="Model" htmlFor="mtr-model">
              {input('model')}
            </FormField>
          </div>
          <FormField label="Size" htmlFor="mtr-size">
            <select id="mtr-size" value={draft.size} onChange={(e) => set('size', e.target.value)} className={fieldClass}>
              <option value="">Not recorded</option>
              {sizes.map((s) => (
                <option key={s} value={s}>
                  {sizeLabel(s)}
                </option>
              ))}
            </select>
          </FormField>
        </fieldset>

        <fieldset className="space-y-3 border-t border-rule-hair pt-4">
          <legend className="sr-only">Reading</legend>
          <p className="text-h3 text-ink-primary">Reading</p>
          <div className="grid grid-cols-2 gap-3">
            <FormField label="Read type" htmlFor="mtr-read_type">
              <select
                id="mtr-read_type"
                value={draft.read_type}
                onChange={(e) => set('read_type', e.target.value)}
                className={fieldClass}
              >
                {READ_TYPES.map((t) => (
                  <option key={t} value={t}>
                    {humanize(t)}
                  </option>
                ))}
              </select>
            </FormField>
            <FormField
              label="Endpoint ID"
              htmlFor="mtr-ami_endpoint_id"
              hint={manual ? 'A manually read meter has no endpoint' : 'The radio module fitted to the meter'}
            >
              {input('ami_endpoint_id', { disabled: manual, value: manual ? '' : draft.ami_endpoint_id })}
            </FormField>
          </div>
          <div className="grid grid-cols-2 gap-3">
            <FormField label="Route" htmlFor="mtr-route_id" hint="Blank when no route reads it">
              {input('route_id', { placeholder: 'RT-14' })}
            </FormField>
            <FormField label="Route sequence" htmlFor="mtr-route_sequence" error={errors.route_sequence}>
              {input('route_sequence', { inputMode: 'numeric', disabled: !draft.route_id.trim() })}
            </FormField>
          </div>
        </fieldset>

        <fieldset className="space-y-3 border-t border-rule-hair pt-4">
          <legend className="sr-only">Billing factors</legend>
          <p className="text-h3 text-ink-primary">Billing factors</p>
          <div className="grid grid-cols-3 gap-3">
            <FormField label="Multiplier" htmlFor="mtr-multiplier" error={errors.multiplier}>
              {input('multiplier', { inputMode: 'decimal', className: `${fieldClass} ident` })}
            </FormField>
            <FormField label="BTU factor" htmlFor="mtr-gas_btu_factor" error={errors.gas_btu_factor}>
              {input('gas_btu_factor', { inputMode: 'decimal', placeholder: '1.0350', className: `${fieldClass} ident` })}
            </FormField>
            <FormField label="Rollover point" htmlFor="mtr-rollover_point" error={errors.rollover_point}>
              {input('rollover_point', { inputMode: 'numeric', placeholder: '100000', className: `${fieldClass} ident` })}
            </FormField>
          </div>
          {needsReason ? (
            <>
              <StateBlock tone="warning">
                <ul className="text-data text-ink-primary">
                  {factorChanges.map((k) => (
                    <li key={k}>
                      {FACTOR_LABELS[k]}: <span className="ident">{shown(k, current[k])}</span> →{' '}
                      <span className="ident font-semibold">{shown(k, edit[k])}</span>
                    </li>
                  ))}
                </ul>
                <p className="mt-1 text-micro text-ink-secondary">
                  Billing uses the factor in effect on each read date. Check every digit.
                </p>
              </StateBlock>
              <FormField
                label="Takes effect"
                htmlFor="mtr-effective"
                error={errors.effective}
                hint={
                  backdated
                    ? 'Reads already taken from this date billed with the old factor and will need a rebill.'
                    : 'Reads on or after this date bill with the new factor.'
                }
              >
                {input('effective', { type: 'date' })}
              </FormField>
              <FormField label="Reason for this change" htmlFor="mtr-reason" error={errors.reason} hint="Recorded with the change.">
                <textarea
                  id="mtr-reason"
                  rows={2}
                  value={draft.reason}
                  onChange={(e) => set('reason', e.target.value)}
                  aria-invalid={errors.reason ? true : undefined}
                  className={`${fieldClass} h-auto py-1.5`}
                />
              </FormField>
            </>
          ) : null}
        </fieldset>

        <p className="rounded-sm bg-surface-sunken px-3 py-2 text-micro text-ink-secondary">
          The meter number and status aren’t edited here: status moves only through an inactivation or
          reactivation, and the estimate count is kept by the database. Changes are kept in this browser
          until the API exists.
        </p>
        {/* Enter in a field submits. */}
        <button type="submit" className="hidden" aria-hidden tabIndex={-1} />
      </form>
    </Dialog>
  )
}

