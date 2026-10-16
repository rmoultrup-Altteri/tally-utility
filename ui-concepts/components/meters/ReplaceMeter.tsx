'use client'

import { useState } from 'react'
import Link from 'next/link'
import type { Route } from 'next'
import { Button } from '@/components/ui/Panel'
import { Dialog, FormField, fieldClass } from '@/components/ui/Dialog'
import { StateBlock, humanize, type Tone } from '@/components/ui/State'
import { sizeLabel } from '@/components/meters/status'
import { useAccess } from '@/lib/access'
import { replaceMeter, useEdits } from '@/lib/edits-store'
import { meters } from '@/fixtures/accounts'
import { meterDetailById } from '@/fixtures/meters'
import { asOf } from '@/fixtures/tenant'
import { customerName, type Customer, type Meter, type MeterReading, type ServiceLocation } from '@/schemas/models'
import { date, factor, reading } from '@/lib/format'

/**
 * Exchanging the meter at a premise.
 *
 * Not an edit: the old meter keeps its number, its reads and its bills, and
 * leaves the premise; a meter from stock takes its place. The dialog asks for
 * what every change-out ticket records — the date, the old meter's removal
 * read, the new meter's set read, why, and who did the work — and makes the
 * operator acknowledge that the next bill splits at the swap.
 */

export const REPLACE_REASONS = [
  'Failed accuracy test',
  'Periodic change-out — test due',
  'Stopped or not registering',
  'Damaged or leaking',
  'AMR / AMI upgrade',
  'Tampering found',
  'Wrong size for the load',
]

const OTHER = 'Other'

type Note = { id: string; tone: Tone; text: React.ReactNode; acknowledge?: boolean }

type Draft = {
  incomingId: string
  swapDate: string
  removalRead: string
  rolledOver: boolean
  installRead: string
  reason: string
  other: string
  technician: string
  sealNumber: string
  serviceOrder: string
  endpoint: 'move' | 'new' | 'none'
  newEndpointId: string
}

const isReading = (s: string) => /^\d+(\.\d+)?$/.test(s.trim())

/** Meters on the shelf, as they stand after anything done in this browser. */
function useStock(): Meter[] {
  const edits = useEdits().meters
  return meters.map((m) => ({ ...m, ...edits[m.id] })).filter((m) => m.status === 'in_stock')
}

export function ReplaceButton({ onClick }: { onClick: () => void }) {
  const { can, holders } = useAccess()
  const allowed = can('customer.edit')
  return (
    <Button
      onClick={onClick}
      disabled={!allowed}
      title={
        allowed
          ? undefined
          : `Your role can’t replace meters. Ask someone with ${holders('customer.edit')
              .map((r) => r.name)
              .join(', ')}.`
      }
    >
      Replace meter
    </Button>
  )
}

export function ReplaceMeterDialog({
  current,
  served,
  lastRead,
  latest,
  scheduleCode,
  open,
  onClose,
}: {
  /** The outgoing meter as it stands now. */
  current: Meter
  served: { customer: Customer; location: ServiceLocation }
  lastRead: { value: string | null; date: string | null }
  latest: MeterReading | null
  scheduleCode: string | null
  open: boolean
  onClose: () => void
}) {
  const stock = useStock()
  const blankDraft = (): Draft => ({
    incomingId: '',
    swapDate: asOf.validAt,
    removalRead: '',
    rolledOver: false,
    installRead: '',
    reason: '',
    other: '',
    technician: '',
    sealNumber: '',
    serviceOrder: '',
    endpoint: current.ami_endpoint_id ? 'move' : 'none',
    newEndpointId: '',
  })
  const [draft, setDraft] = useState<Draft>(blankDraft)
  const [acked, setAcked] = useState<string[]>([])
  const [errors, setErrors] = useState<Partial<Record<keyof Draft | 'ack', string>>>({})
  const [lastOpen, setLastOpen] = useState(open)

  /* Each opening starts blank. */
  if (open !== lastOpen) {
    setLastOpen(open)
    if (open) {
      setDraft(blankDraft())
      setAcked([])
      setErrors({})
    }
  }

  const set = <K extends keyof Draft>(k: K, v: Draft[K]) => {
    setDraft((d) => ({ ...d, [k]: v }))
    if (errors[k]) setErrors((e) => ({ ...e, [k]: undefined }))
  }

  function pickIncoming(id: string) {
    const m = stock.find((s) => s.id === id)
    const detail = meterDetailById.get(id)
    setDraft((d) => ({
      ...d,
      incomingId: id,
      /* The register as it left the shop, which the tech confirms on site. */
      installRead: detail?.lastReadValue ?? d.installRead,
      newEndpointId: m?.ami_endpoint_id ?? '',
      endpoint: d.endpoint === 'none' && m?.ami_endpoint_id ? 'new' : d.endpoint,
    }))
    setErrors((e) => ({ ...e, incomingId: undefined }))
  }

  const incoming = stock.find((s) => s.id === draft.incomingId) ?? null
  const below = isReading(draft.removalRead) && !!lastRead.value && Number(draft.removalRead) < Number(lastRead.value)
  const customer = served.customer
  const toggle = (id: string) => setAcked((xs) => (xs.includes(id) ? xs.filter((x) => x !== id) : [...xs, id]))

  const notes: Note[] = []
  if (incoming) {
    const sameMultiplier = Number(incoming.multiplier) === Number(current.multiplier)
    notes.push({
      id: 'split',
      tone: sameMultiplier ? 'warning' : 'critical',
      acknowledge: true,
      text: (
        <>
          <strong className="font-semibold">The next bill splits at {date(draft.swapDate)}.</strong>{' '}
          {customerName(customer)} is billed for <span className="ident">{current.meter_number}</span> from its last
          read to the removal read, then <span className="ident">{incoming.meter_number}</span> from the set read on.
          {sameMultiplier ? (
            <> Both meters use multiplier <span className="ident">{factor(current.multiplier)}</span>.</>
          ) : (
            <>
              {' '}
              The multipliers differ: <span className="ident">{factor(current.multiplier)}</span> on the old meter,{' '}
              <span className="ident font-semibold">{factor(incoming.multiplier)}</span> on the new one. Check the new
              meter’s dial face before saving.
            </>
          )}
        </>
      ),
    })
  }
  if (latest && !latest.billing_period_locked && latest.validation_status !== 'released_to_billing')
    notes.push({
      id: 'read',
      tone: 'warning',
      acknowledge: true,
      text: (
        <>
          The read from {date(latest.reading_date)} on the old meter is still {humanize(latest.validation_status).toLowerCase()}.
          Resolve it in Read validation before the run posts, or the split starts from the wrong index.
        </>
      ),
    })
  if (current.status === 'inactive')
    notes.push({
      id: 'inactive',
      tone: 'info',
      text: 'The meter is inactive, so the new meter is set inactive too. Reactivate it with a turn-on read when service is restored.',
    })
  notes.push({
    id: 'carry',
    tone: 'info',
    text: (
      <>
        {current.route_id ? (
          <>
            Route <span className="ident">{current.route_id}</span> sequence {current.route_sequence}
          </>
        ) : (
          'No route'
        )}
        {scheduleCode ? (
          <>
            {' '}
            and rate schedule <span className="ident">{scheduleCode}</span>
          </>
        ) : null}{' '}
        carry over to the new meter. <span className="ident">{current.meter_number}</span> becomes Removed and keeps its
        reads and bills; send it to the meter shop.
      </>
    ),
  })

  function save() {
    const e: typeof errors = {}
    if (!incoming) e.incomingId = 'Choose the meter going in'
    if (!draft.swapDate) e.swapDate = 'Enter the date of the change-out'
    else if (draft.swapDate > asOf.validAt) e.swapDate = `Can’t be after ${date(asOf.validAt)}`
    else if (lastRead.date && draft.swapDate < lastRead.date) e.swapDate = `Can’t be before the last read, ${date(lastRead.date)}`
    if (!draft.removalRead.trim()) e.removalRead = 'Enter the old meter’s reading as it came off'
    else if (!isReading(draft.removalRead)) e.removalRead = 'Enter the dials as a number, like 4835'
    else if (below && !current.rollover_point)
      e.removalRead = `Below the last reading, ${reading(lastRead.value!)}, and the meter has no rollover point`
    else if (below && !draft.rolledOver) e.rolledOver = 'Confirm the register rolled over, or correct the reading'
    else if (current.rollover_point && Number(draft.removalRead) >= Number(current.rollover_point))
      e.removalRead = `Must be below the rollover point, ${Number(current.rollover_point).toLocaleString('en-US')}`
    if (!draft.installRead.trim()) e.installRead = 'Enter the new meter’s reading as it was set'
    else if (!isReading(draft.installRead)) e.installRead = 'Enter the dials as a number, like 0'
    else if (incoming?.rollover_point && Number(draft.installRead) >= Number(incoming.rollover_point))
      e.installRead = `Must be below the rollover point, ${Number(incoming.rollover_point).toLocaleString('en-US')}`
    const why = draft.reason === OTHER ? draft.other.trim() : draft.reason
    if (!why) e[draft.reason === OTHER ? 'other' : 'reason'] = draft.reason === OTHER ? 'Say why' : 'Choose a reason'
    if (!draft.technician.trim()) e.technician = 'Enter who did the change-out'
    if (draft.endpoint === 'new' && !draft.newEndpointId.trim()) e.newEndpointId = 'Enter the ID printed on the new radio'
    if (notes.some((n) => n.acknowledge && !acked.includes(n.id))) e.ack = 'Tick each item above to confirm you’ve read it'
    setErrors(e)
    if (Object.keys(e).length || !incoming) return
    replaceMeter(
      current,
      incoming,
      {
        locationId: served.location.id,
        customerId: customer.id,
        swapDate: draft.swapDate,
        removalRead: draft.removalRead.trim(),
        rolledOver: below,
        installRead: draft.installRead.trim(),
        reason: why,
        technician: draft.technician.trim(),
        sealNumber: draft.sealNumber.trim() || null,
        serviceOrder: draft.serviceOrder.trim() || null,
        endpoint: draft.endpoint,
        rateScheduleCode: scheduleCode,
      },
      draft.endpoint === 'new' ? draft.newEndpointId.trim() : null,
    )
    onClose()
  }

  const input = (k: keyof Draft, props: React.InputHTMLAttributes<HTMLInputElement> = {}) => (
    <input
      id={`swap-${k}`}
      value={draft[k] as string}
      onChange={(e) => set(k, e.target.value as never)}
      aria-invalid={errors[k] ? true : undefined}
      aria-describedby={errors[k] ? `swap-${k}-error` : undefined}
      className={fieldClass}
      autoComplete="off"
      {...props}
    />
  )

  return (
    <Dialog
      open={open}
      onClose={onClose}
      title="Replace meter"
      meta={
        <>
          <span className="ident">{current.meter_number}</span> · {served.location.address} · {customerName(customer)}
        </>
      }
      footer={
        <>
          <Button variant="quiet" onClick={onClose}>
            Cancel
          </Button>
          <Button variant="primary" onClick={save} disabled={!stock.length}>
            Replace meter
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
        <fieldset className="space-y-3">
          <legend className="text-h3 text-ink-primary mb-2">Meter going in</legend>
          {stock.length ? (
            <FormField
              label="Incoming meter"
              htmlFor="swap-incomingId"
              error={errors.incomingId}
              hint={incoming ? [incoming.manufacturer, incoming.model, sizeLabel(incoming.size), `multiplier ${factor(incoming.multiplier)}`].filter(Boolean).join(' · ') : 'Meters in stock'}
            >
              <select
                id="swap-incomingId"
                value={draft.incomingId}
                onChange={(e) => pickIncoming(e.target.value)}
                aria-invalid={errors.incomingId ? true : undefined}
                className={fieldClass}
              >
                <option value="">Choose…</option>
                {stock.map((m) => (
                  <option key={m.id} value={m.id}>
                    {m.meter_number} · {[m.manufacturer, m.model].filter(Boolean).join(' ')} · {sizeLabel(m.size)}
                    {meterDetailById.get(m.id)?.warehouseLocation ? ` · ${meterDetailById.get(m.id)!.warehouseLocation}` : ''}
                  </option>
                ))}
              </select>
            </FormField>
          ) : (
            <StateBlock tone="warning">
              <p className="text-data text-ink-primary">
                No meter is in stock.{' '}
                <Link href={'/meters/new' as Route} className="text-accent-text underline">
                  Receive one into stock
                </Link>{' '}
                first, then replace this meter.
              </p>
            </StateBlock>
          )}
          {incoming && current.size && incoming.size && incoming.size !== current.size ? (
            <p className="text-micro text-exception-warning-text">
              Size changes from {sizeLabel(current.size)} to {sizeLabel(incoming.size)}. Make sure the reason says why.
            </p>
          ) : null}
        </fieldset>

        <fieldset className="space-y-3 border-t border-rule-hair pt-4">
          <legend className="sr-only">The change-out</legend>
          <p className="text-h3 text-ink-primary">The change-out</p>
          <div className="grid grid-cols-2 gap-3">
            <FormField
              label="Swap date"
              htmlFor="swap-swapDate"
              error={errors.swapDate}
              hint={lastRead.date ? `Last read ${date(lastRead.date)}` : undefined}
            >
              {input('swapDate', { type: 'date', min: lastRead.date ?? undefined, max: asOf.validAt })}
            </FormField>
            <FormField label="Technician" htmlFor="swap-technician" error={errors.technician}>
              {input('technician', { placeholder: 'R. Salinas' })}
            </FormField>
          </div>
          <div className="grid grid-cols-2 gap-3">
            <FormField
              label="Removal read — old meter"
              htmlFor="swap-removalRead"
              error={errors.removalRead}
              hint={lastRead.value ? `Last reading ${reading(lastRead.value)}` : undefined}
            >
              {input('removalRead', { inputMode: 'decimal', className: `${fieldClass} ident` })}
            </FormField>
            <FormField label="Set read — new meter" htmlFor="swap-installRead" error={errors.installRead}>
              {input('installRead', { inputMode: 'decimal', className: `${fieldClass} ident` })}
            </FormField>
          </div>
          {below && current.rollover_point ? (
            <label className="flex cursor-pointer items-start gap-2.5">
              <input
                type="checkbox"
                checked={draft.rolledOver}
                onChange={() => set('rolledOver', !draft.rolledOver)}
                className="mt-0.5 h-4 w-4 shrink-0 accent-accent"
              />
              <span>
                <span className="block text-data text-ink-primary">
                  The register rolled over past {Number(current.rollover_point).toLocaleString('en-US')}
                </span>
                <span className={`block text-micro ${errors.rolledOver ? 'text-exception-critical-text' : 'text-ink-tertiary'}`}>
                  {errors.rolledOver ?? `The removal read is below the last reading, ${reading(lastRead.value!)}.`}
                </span>
              </span>
            </label>
          ) : null}
          <div className="grid grid-cols-2 gap-3">
            <FormField label="Reason" htmlFor="swap-reason" error={errors.reason}>
              <select
                id="swap-reason"
                value={draft.reason}
                onChange={(e) => set('reason', e.target.value)}
                aria-invalid={errors.reason ? true : undefined}
                className={fieldClass}
              >
                <option value="">Choose…</option>
                {[...REPLACE_REASONS, OTHER].map((r) => (
                  <option key={r} value={r}>
                    {r}
                  </option>
                ))}
              </select>
            </FormField>
            <FormField label="Seal number" htmlFor="swap-sealNumber" hint="Optional">
              {input('sealNumber', { className: `${fieldClass} ident` })}
            </FormField>
          </div>
          {draft.reason === OTHER ? (
            <FormField label="Describe the reason" htmlFor="swap-other" error={errors.other}>
              {input('other')}
            </FormField>
          ) : null}
          <FormField label="Service order" htmlFor="swap-serviceOrder" hint="Optional — the change-out ticket number">
            {input('serviceOrder', { className: `${fieldClass} ident`, placeholder: 'SO-' })}
          </FormField>
        </fieldset>

        <fieldset className="space-y-2 border-t border-rule-hair pt-4">
          <legend className="sr-only">Endpoint</legend>
          <p className="text-h3 text-ink-primary">Endpoint</p>
          {(
            [
              ...(current.ami_endpoint_id
                ? [{ v: 'move' as const, label: `Move ${current.ami_endpoint_id} to the new meter` }]
                : []),
              { v: 'new' as const, label: 'Fit a different endpoint' },
              { v: 'none' as const, label: 'No endpoint — read manually' },
            ]
          ).map((o) => (
            <label key={o.v} className="flex cursor-pointer items-center gap-2.5 text-data text-ink-primary">
              <input
                type="radio"
                name="swap-endpoint"
                checked={draft.endpoint === o.v}
                onChange={() => set('endpoint', o.v)}
                className="h-4 w-4 accent-accent"
              />
              {o.label}
            </label>
          ))}
          {draft.endpoint === 'new' ? (
            <FormField label="New endpoint ID" htmlFor="swap-newEndpointId" error={errors.newEndpointId} className="pl-6">
              {input('newEndpointId', { className: `${fieldClass} ident` })}
            </FormField>
          ) : null}
        </fieldset>

        <div className="space-y-2 border-t border-rule-hair pt-4">
          {notes.map((n) => (
            <StateBlock key={n.id} tone={n.tone} className="px-3! py-2.5!">
              {n.acknowledge ? (
                <label className="flex cursor-pointer items-start gap-2.5 text-data text-ink-primary">
                  <input
                    type="checkbox"
                    checked={acked.includes(n.id)}
                    onChange={() => {
                      toggle(n.id)
                      setErrors((x) => ({ ...x, ack: undefined }))
                    }}
                    className="mt-0.5 h-4 w-4 shrink-0 accent-accent"
                  />
                  <span>{n.text}</span>
                </label>
              ) : (
                <p className="text-data text-ink-primary">{n.text}</p>
              )}
            </StateBlock>
          ))}
          {errors.ack ? <p className="text-micro text-exception-critical-text">{errors.ack}</p> : null}
        </div>

        <p className="rounded-sm bg-surface-sunken px-3 py-2 text-micro text-ink-secondary">
          Recorded on both meters with your name, the reason and the swap date. Nothing is deleted: the old meter’s
          reads and bills stay on its record and on the premise’s history. Kept in this browser until the API exists.
        </p>
        <button type="submit" className="hidden" aria-hidden tabIndex={-1} />
      </form>
    </Dialog>
  )
}
