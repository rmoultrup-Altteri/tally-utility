'use client'

import { useMemo, useState, type FormEvent, type ReactNode } from 'react'
import Link from 'next/link'
import type { Route } from 'next'
import { Button, Panel, PanelHeader } from '@/components/ui/Panel'
import { FormField, fieldClass } from '@/components/ui/Dialog'
import { humanize, StateBlock, StateFlag, type Tone } from '@/components/ui/State'
import { Money } from '@/components/ui/Money'
import { customers, customerById, locationById, meterById, serviceLinks } from '@/fixtures/accounts'
import { invoices } from '@/fixtures/billing'
import { readings } from '@/fixtures/reads'
import { asOf } from '@/fixtures/tenant'
import { transferPremises, transfers as recorded, type AfterStop, type FinalReadMethod, type Mover, type Transfer } from '@/fixtures/transfers'
import { customerName, isIssued } from '@/schemas/models'
import { useAccess } from '@/lib/access'
import { addTransfer, useAddedTransfers } from '@/lib/transfers-store'
import { evaluateTransfer, finalBillEstimate, type CheckLevel, type TransferDraft } from '@/lib/transfers'
import { addWorkingDays } from '@/lib/working-days'
import { date, days, money } from '@/lib/format'

/**
 * A transfer of service, keyed in while the customer is on the phone.
 *
 * Four sections in the order the move happens — who, stop, start, money —
 * with the rules evaluated live beside them, so the CSR hears about a locked
 * gate, an occupied premise or a protection to re-verify while the customer
 * is still on the line rather than from a field crew the next morning.
 */

const LEVEL_TONE: Record<CheckLevel, Tone> = { block: 'critical', review: 'warning', ok: 'cleared', info: 'info' }
const LEVEL_LABEL: Record<CheckLevel, string> = { block: 'Blocks', review: 'Review', ok: 'OK', info: 'Note' }

/** Everything the form needs to know about a modelled customer, read from the fixtures. */
function moverFor(customerId: string): (Mover & { lastRead: string | null; thermsPerDay: number; insideCity: boolean }) | null {
  const c = customerById.get(customerId)
  const link = serviceLinks.find((l) => l.customerId === customerId)
  if (!c || !link) return null
  const loc = locationById.get(link.locationId)!
  const meter = meterById.get(link.meterId)!
  const open = invoices.filter((i) => i.customer_id === c.id && isIssued(i) && i.status !== 'void' && Number(i.balance) > 0)
  const oldestDue = open.map((i) => i.due_date).sort()[0]
  const latest = readings.filter((r) => r.meter_id === meter.id).sort((a, b) => b.reading_date.localeCompare(a.reading_date))[0]
  const perDay = latest?.gas_therms && latest.days_in_period ? Number(latest.gas_therms) / latest.days_in_period : 0
  return {
    customerId: c.id,
    accountNumber: c.customer_number,
    name: customerName(c),
    isResidential: c.customer_type === 'residential',
    phone: c.phone ?? '—',
    from: { premiseNumber: loc.location_number, address: loc.address, city: loc.city, meterNumber: meter.meter_number, meterId: meter.id },
    balance: c.balance,
    pastDueDays: oldestDue && oldestDue < asOf.validAt ? days(oldestDue, asOf.validAt) : 0,
    deposit: c.deposit_amount,
    protection:
      c.do_not_disconnect && c.disconnect_protection_type && c.disconnect_protection_expiry
        ? { label: humanize(c.disconnect_protection_type), expires: c.disconnect_protection_expiry }
        : null,
    arrangement: null,
    lastRead: latest?.reading_date ?? null,
    thermsPerDay: perDay,
    insideCity: loc.inside_city_limits,
  }
}

const firstStop = addWorkingDays(asOf.validAt, 1)

export function TransferForm({ initialCustomerId }: { initialCustomerId: string | null }) {
  const { can, user, holders } = useAccess()
  const added = useAddedTransfers()
  const [customerId, setCustomerId] = useState(initialCustomerId && customerById.has(initialCustomerId) ? initialCustomerId : '')
  const [stopDate, setStopDate] = useState(firstStop)
  const [startDate, setStartDate] = useState(firstStop)
  const [method, setMethod] = useState<FinalReadMethod>('meter_read')
  const [afterStop, setAfterStop] = useState<AfterStop>('lock_off')
  const [toPremiseId, setToPremiseId] = useState('')
  const [slot, setSlot] = useState<'AM' | 'PM'>('AM')
  const [adultPresent, setAdultPresent] = useState(false)
  const [appliances, setAppliances] = useState('2')
  const [finalBill, setFinalBill] = useState<'roll_forward' | 'separate'>('roll_forward')
  const [keepDeposit, setKeepDeposit] = useState(true)
  const [channel, setChannel] = useState<Transfer['channel']>('phone')
  const [note, setNote] = useState('')
  const [done, setDone] = useState<Transfer | null>(null)

  const mover = customerId ? moverFor(customerId) : null
  const premise = transferPremises.find((p) => p.id === toPremiseId)
  const all = useMemo(() => [...recorded, ...added], [added])

  const draft: TransferDraft | null = mover
    ? {
        requestedBy: user.name,
        channel,
        mover,
        stopDate,
        finalRead: { method, reading: null, takenAt: null },
        afterStop,
        toPremiseId,
        startDate,
        turnOn: { window: slot, adultPresent, appliances: Math.max(0, Number(appliances) || 0), completedAt: null, tech: null },
        finalBill,
        finalInvoice: null,
        keepDeposit,
        note: note.trim() || null,
      }
    : null
  const checks = draft ? evaluateTransfer(draft, all, true) : []
  const blocks = checks.filter((c) => c.level === 'block')
  const reviews = checks.filter((c) => c.level === 'review')
  const allowed = can('customer.edit')

  const estimate =
    mover && mover.isResidential && mover.lastRead && stopDate > mover.lastRead
      ? { days: days(mover.lastRead, stopDate), ...finalBillEstimate(days(mover.lastRead, stopDate), mover.thermsPerDay, mover.insideCity) }
      : null

  function submit(e: FormEvent) {
    e.preventDefault()
    if (!draft || blocks.length || !allowed) return
    const seq = 220 + added.length
    const t: Transfer = {
      ...draft,
      id: `tr-local-${seq}`,
      number: `TR-2026-0${seq}`,
      requestedAt: asOf.recordedAt,
      completedAt: null,
    }
    addTransfer(t)
    setDone(t)
  }

  if (done) {
    return (
      <Panel>
        <div className="space-y-3 px-5 py-5">
          <p className="text-h3 text-ink-primary">
            <span className="ident">{done.number}</span> booked for {done.mover.name}
          </p>
          <p className="text-data text-ink-secondary">
            {reviews.length
              ? `It waits on the Transfers tab for a sign-off on ${reviews.length === 1 ? 'one check' : `${reviews.length} checks`} before the field orders go out.`
              : 'Every check passed. The stop, final read and turn-on orders go out with the next dispatch.'}
          </p>
          <p className="text-micro text-ink-tertiary">Kept in this browser until the API exists.</p>
          <div className="flex gap-2 pt-1">
            <Link
              href={'/transfers' as Route}
              className="inline-flex h-8 items-center rounded-sm border border-accent bg-accent px-3.5 text-data font-medium text-ink-inverse hover:bg-accent-hover"
            >
              Open Transfers
            </Link>
            <Button onClick={() => setDone(null)}>Back to the form</Button>
          </div>
        </div>
      </Panel>
    )
  }

  return (
    <form onSubmit={submit} noValidate className="grid grid-cols-1 gap-5 xl:grid-cols-[minmax(0,1fr)_22rem]">
      <div className="min-w-0 space-y-5">
        <Section n={1} title="Who is moving">
          <FormField label="Customer *" htmlFor="tr-customer" className="sm:col-span-2">
            <select id="tr-customer" value={customerId} onChange={(e) => setCustomerId(e.target.value)} className={fieldClass}>
              <option value="">Choose an account</option>
              {customers
                .filter((c) => c.status !== 'inactive')
                .map((c) => (
                  <option key={c.id} value={c.id}>
                    {customerName(c)} · {c.customer_number}
                  </option>
                ))}
            </select>
          </FormField>
          <FormField label="Requested by" htmlFor="tr-channel">
            <select id="tr-channel" value={channel} onChange={(e) => setChannel(e.target.value as Transfer['channel'])} className={fieldClass}>
              <option value="phone">Phone</option>
              <option value="walk_in">Walk-in</option>
              <option value="portal">Portal</option>
            </select>
          </FormField>
          {mover ? (
            <dl className="sm:col-span-3 grid grid-cols-2 gap-x-6 gap-y-2 rounded-sm bg-surface-sunken px-3 py-2.5 sm:grid-cols-4">
              <Fact label="Now at">
                {mover.from.address}, {mover.from.city}
              </Fact>
              <Fact label="Meter">
                <span className="ident">{mover.from.meterNumber}</span>
                {mover.lastRead ? <span className="text-ink-tertiary"> · read {date(mover.lastRead)}</span> : null}
              </Fact>
              <Fact label="Balance">
                <Money value={mover.balance} arrears={mover.pastDueDays > 0} />
                {mover.pastDueDays > 0 ? <span className="text-ink-tertiary"> · {mover.pastDueDays}d past due</span> : null}
              </Fact>
              <Fact label="Deposit">
                <Money value={mover.deposit} />
              </Fact>
            </dl>
          ) : null}
        </Section>

        <Section n={2} title="Stop at the current premise" meta={mover ? `${mover.from.address}, ${mover.from.city}` : undefined}>
          <FormField label="Stop date *" htmlFor="tr-stop">
            <input
              id="tr-stop"
              type="date"
              min={asOf.validAt}
              value={stopDate}
              onChange={(e) => {
                /* Keep a same-day move same-day unless the start was set on its own. */
                if (startDate === stopDate) setStartDate(e.target.value)
                setStopDate(e.target.value)
              }}
              className={fieldClass}
            />
          </FormField>
          <FormField label="Final read" htmlFor="tr-read" hint={method === 'customer_read' ? 'Needs a dated photo of the dial' : undefined}>
            <select id="tr-read" value={method} onChange={(e) => setMethod(e.target.value as FinalReadMethod)} className={fieldClass}>
              <option value="meter_read">Meter read on the stop date (AMR / AMI)</option>
              <option value="field_read">Field read order</option>
              <option value="customer_read">Customer reads the meter</option>
            </select>
          </FormField>
          <FormField label="After the stop" htmlFor="tr-after">
            <select id="tr-after" value={afterStop} onChange={(e) => setAfterStop(e.target.value as AfterStop)} className={fieldClass}>
              <option value="lock_off">Lock off the meter</option>
              <option value="owner_takes_service">Leave on — owner or landlord takes service</option>
              <option value="next_customer">Leave on — a new customer moves in</option>
            </select>
          </FormField>
        </Section>

        <Section n={3} title="Start at the new premise">
          <FormField label="New premise *" htmlFor="tr-premise" className="sm:col-span-2">
            <select id="tr-premise" value={toPremiseId} onChange={(e) => setToPremiseId(e.target.value)} className={fieldClass}>
              <option value="">Choose the service address</option>
              {transferPremises.map((p) => (
                <option key={p.id} value={p.id}>
                  {p.address}, {p.city} · {p.number} · {occupancy(p.occupant)}
                </option>
              ))}
            </select>
          </FormField>
          <FormField label="Start date *" htmlFor="tr-start">
            <input id="tr-start" type="date" min={asOf.validAt} value={startDate} onChange={(e) => setStartDate(e.target.value)} className={fieldClass} />
          </FormField>
          {premise?.meterState === 'locked_off' ? (
            <>
              <FormField label="Turn-on window" htmlFor="tr-window" hint="A tech pressure-tests the line and relights every pilot">
                <select id="tr-window" value={slot} onChange={(e) => setSlot(e.target.value as 'AM' | 'PM')} className={fieldClass}>
                  <option value="AM">8 am – noon</option>
                  <option value="PM">noon – 5 pm</option>
                </select>
              </FormField>
              <FormField label="Appliances to relight" htmlFor="tr-appl">
                <input id="tr-appl" type="number" min={0} max={12} value={appliances} onChange={(e) => setAppliances(e.target.value)} className={fieldClass} />
              </FormField>
              <div className="flex items-start gap-2 self-end pb-1.5">
                <input id="tr-adult" type="checkbox" checked={adultPresent} onChange={(e) => setAdultPresent(e.target.checked)} className="mt-0.5" />
                <label htmlFor="tr-adult" className="text-data text-ink-primary">
                  An adult will be home
                  <span className="block text-micro text-ink-tertiary">18 or older, for the whole window</span>
                </label>
              </div>
            </>
          ) : premise ? (
            <p className="sm:col-span-3 text-micro text-ink-tertiary">
              The meter at {premise.address} is on. A read on the start date opens the new service; no truck roll.
            </p>
          ) : null}
        </Section>

        <Section n={4} title="Money">
          <div className="sm:col-span-3 space-y-1">
            <p className="field-label">Final bill at the old premise</p>
            <p className="text-data text-ink-primary">
              {estimate ? (
                <>
                  About <Money value={String(estimate.total)} /> — {estimate.days} days since the {date(mover!.lastRead)} read at
                  about {mover!.thermsPerDay.toFixed(1)} therms a day, monthly charges prorated.
                </>
              ) : mover && !mover.isResidential ? (
                'Priced at the final read on the commercial schedule.'
              ) : (
                'Priced at the final read.'
              )}
            </p>
          </div>
          <FormField label="Final bill" htmlFor="tr-final">
            <select id="tr-final" value={finalBill} onChange={(e) => setFinalBill(e.target.value as 'roll_forward' | 'separate')} className={fieldClass}>
              <option value="roll_forward">Roll into the first bill at the new premise</option>
              <option value="separate">Bill it on its own now</option>
            </select>
          </FormField>
          {mover && Number(mover.deposit) > 0 ? (
            <FormField label="Deposit" htmlFor="tr-deposit">
              <select id="tr-deposit" value={keepDeposit ? 'keep' : 'refund'} onChange={(e) => setKeepDeposit(e.target.value === 'keep')} className={fieldClass}>
                <option value="keep">Keep {money(mover.deposit)} on the account</option>
                <option value="refund">Apply to the final bill, refund the rest</option>
              </select>
            </FormField>
          ) : null}
          <FormField label="Note" htmlFor="tr-note" className="sm:col-span-3">
            <input id="tr-note" value={note} onChange={(e) => setNote(e.target.value)} placeholder="Anything the field crew or the reviewer should know" className={fieldClass} />
          </FormField>
        </Section>
      </div>

      <aside className="min-w-0 xl:sticky xl:top-0 xl:self-start space-y-3">
        <Panel>
          <PanelHeader title="Checks" meta={draft ? `${blocks.length} blocking · ${reviews.length} for review` : 'Choose a customer'} />
          <ul className="space-y-2.5 px-4 py-3">
            {draft ? (
              [...checks]
                .sort((a, b) => order(a.level) - order(b.level))
                .map((c) => (
                  <li key={c.code} className="flex gap-2.5">
                    <span className="w-14 shrink-0 pt-0.5">
                      <StateFlag tone={LEVEL_TONE[c.level]}>{LEVEL_LABEL[c.level]}</StateFlag>
                    </span>
                    <div className="min-w-0">
                      <p className="text-data text-ink-primary">{c.title}</p>
                      <p className="text-micro text-ink-tertiary">{c.detail}</p>
                    </div>
                  </li>
                ))
            ) : (
              <li className="text-micro text-ink-tertiary">The rules run as you fill the form: dates, the final read, who holds the new premise, the turn-on, and what the account carries.</li>
            )}
          </ul>
        </Panel>
        {!allowed ? (
          <StateBlock tone="info">
            <p className="text-micro text-ink-primary">
              Booking a transfer needs <strong>Edit accounts</strong>. Held by {holders('customer.edit').map((r) => r.name).join(', ')}.
            </p>
          </StateBlock>
        ) : null}
        <div className="flex gap-2">
          <Button type="submit" variant="primary" disabled={!draft || blocks.length > 0 || !allowed}>
            {reviews.length ? 'Book for review' : 'Book transfer'}
          </Button>
          <Link
            href={'/transfers' as Route}
            className="inline-flex h-8 items-center rounded-sm border border-rule-solid bg-surface-raised px-3.5 text-data font-medium text-ink-primary hover:bg-surface-sunken"
          >
            Cancel
          </Link>
        </div>
      </aside>
    </form>
  )
}

const order = (l: CheckLevel) => ['block', 'review', 'ok', 'info'].indexOf(l)

function occupancy(o: (typeof transferPremises)[number]['occupant']): string {
  if (o.kind === 'vacant') return 'vacant'
  if (o.kind === 'owner') return `owner holds service`
  return `${o.name} on service`
}

function Section({ n, title, meta, children }: { n: number; title: string; meta?: string; children: ReactNode }) {
  return (
    <Panel>
      <PanelHeader
        title={
          <span className="flex items-center gap-2">
            <span aria-hidden className="flex h-5 w-5 items-center justify-center rounded-full bg-surface-inset text-micro text-ink-secondary">
              {n}
            </span>
            {title}
          </span>
        }
        meta={meta}
      />
      <div className="grid grid-cols-1 gap-x-5 gap-y-4 px-4 py-4 sm:grid-cols-3">{children}</div>
    </Panel>
  )
}

function Fact({ label, children }: { label: string; children: ReactNode }) {
  return (
    <div className="min-w-0">
      <dt className="field-label">{label}</dt>
      <dd className="text-data text-ink-primary truncate">{children}</dd>
    </div>
  )
}
