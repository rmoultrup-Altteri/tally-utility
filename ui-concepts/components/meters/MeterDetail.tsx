'use client'

import { useState } from 'react'
import Link from 'next/link'
import type { Route } from 'next'
import { PageHeader } from '@/components/shell/PageHeader'
import { StateBlock, StateFlag, humanize } from '@/components/ui/State'
import { StatusButton, StatusChangeDialog, type Consequence } from '@/components/ui/StatusChange'
import {
  METER_INACTIVATE_REASONS,
  METER_REACTIVATE_REASONS,
  meterStatus,
  sizeLabel,
} from '@/components/meters/status'
import { changeStatus, useCustomer, useEdits, useLastStatusChange, useMeter } from '@/lib/edits-store'
import { customerName, type Customer, type Meter, type MeterReading, type ServiceLocation } from '@/schemas/models'
import { date, stamp } from '@/lib/format'

/**
 * The parts of the meter screen that move with its status. They read the
 * meter through `useMeter`, so an inactivation shows at once everywhere on
 * the page and in the meter list without a reload.
 */

type Served = { customer: Customer; location: ServiceLocation } | null

export function MeterHeader({
  meter: base,
  served,
  read,
  lastReadDate,
}: {
  meter: Meter
  served: Served
  read: MeterReading | null
  lastReadDate: string | null
}) {
  const meter = useMeter(base)
  const customerEdit = useEdits().customers[served?.customer.id ?? '']
  const customer = served ? { ...served.customer, ...customerEdit } : null
  const changed = useLastStatusChange('meter', base.id)
  const [open, setOpen] = useState(false)
  const st = meterStatus(meter.status)
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
            While the meter is inactive no usage bills at this premise; the account’s fixed charges keep billing
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
      text: 'A technician has taken a turn-on read, checked for leaks and relit the appliances at the premise.',
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
            {changed ? (
              <span title={changed.reason ?? undefined}>
                {' '}
                · {changed.changes.status.to === 'inactive' ? 'inactivated' : 'reactivated'} {stamp(changed.at)} by{' '}
                {changed.by}
              </span>
            ) : null}
          </>
        }
        actions={verb ? <StatusButton verb={verb} onClick={() => setOpen(true)} /> : null}
      />
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
          earliest={verb === 'Inactivate' ? lastReadDate : (changed?.effective ?? null)}
          onConfirm={(reason, effective) =>
            changeStatus('meter', base, verb === 'Inactivate' ? 'inactive' : 'active', reason, effective)
          }
        />
      ) : null}
    </>
  )
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
  if (meter.status === 'active') return null
  return (
    <div className="border-b border-rule-hair bg-surface px-5 py-3">
      <StateBlock tone={meterStatus(meter.status).tone}>
        <p className="text-data text-ink-primary">
          {meter.status === 'inactive' ? (
            <>
              <strong className="font-semibold">Inactive</strong>
              {changed?.effective ? <> since {date(changed.effective)}</> : null}
              {changed?.reason ? <> — {changed.reason}</> : null}. The meter is still set at the premise; no usage
              bills and no route reads it until it is reactivated.
            </>
          ) : meter.status === 'in_stock' ? (
            <>
              <strong className="font-semibold">In stock</strong>
              {warehouseLocation ? <> at {warehouseLocation}</> : null}. Tested and ready to set; a service order
              sets it at a premise.
            </>
          ) : (
            <>
              <strong className="font-semibold">Removed</strong>
              {removalDate ? <> {date(removalDate)}</> : null}
              {warehouseLocation ? <>, now at {warehouseLocation}</> : null}. Its reads and bills stay on the
              premise’s history.
            </>
          )}
        </p>
      </StateBlock>
    </div>
  )
}

/** A meter number linking to its record, with its status when it is anything but active. */
export function MeterLink({ meter: base }: { meter: Meter }) {
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

