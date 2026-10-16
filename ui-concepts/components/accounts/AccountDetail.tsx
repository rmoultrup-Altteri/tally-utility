'use client'

import { useState, type ReactNode } from 'react'
import { PageHeader } from '@/components/shell/PageHeader'
import { Button, Field, FieldGrid } from '@/components/ui/Panel'
import { Money } from '@/components/ui/Money'
import { StateBlock, StateFlag, humanize } from '@/components/ui/State'
import { Dialog, EditButton, FormField, fieldClass } from '@/components/ui/Dialog'
import { StatusButton, StatusChangeDialog, type Consequence } from '@/components/ui/StatusChange'
import { ACCOUNT_INACTIVATE_REASONS, ACCOUNT_REACTIVATE_REASONS, accountTone } from '@/components/meters/status'
import {
  CUSTOMER_REASONED,
  changeStatus,
  saveCustomer,
  useCustomer,
  useEdits,
  useLastEdit,
  useLastStatusChange,
  type CustomerEdit,
} from '@/lib/edits-store'
import { DeceasedAction, RecordDeath, useCanRecordDeath } from '@/components/accounts/Deceased'
import { useMeterNow } from '@/lib/replacements'
import { RateScheduleField } from '@/components/accounts/RateSchedule'
import { useDeceased } from '@/lib/deceased-store'
import { PROOFS, reviewOverdue } from '@/lib/deceased'
import { asOf } from '@/fixtures/tenant'
import { BillingDeliveryMethod, ContactMethod, CustomerType, DisconnectProtectionType, PreferredLanguage } from '@/schemas/enums'
import {
  BILL_DELIVERY_LABEL,
  CONTACT_METHOD_LABEL,
  LANGUAGE_LABEL,
  billingAddressLines,
  contactPreferences,
  customerName,
  type Customer,
  type Meter,
  type ServiceLocation,
} from '@/schemas/models'
import { date, money, stamp } from '@/lib/format'

/**
 * The parts of the account screen that show editable fields. They read the
 * account through `useCustomer`, so an edit saved in the dialog shows at once
 * everywhere on the page without a reload.
 */

export function AccountHeader({
  customer: base,
  actions,
  meter,
  location,
}: {
  customer: Customer
  actions: ReactNode
  meter?: Meter
  location?: ServiceLocation
}) {
  const customer = useCustomer(base)
  const edited = useLastEdit('customer', base.id)
  const [open, setOpen] = useState(false)
  const [statusOpen, setStatusOpen] = useState(false)
  const [deathOpen, setDeathOpen] = useState(false)
  const verb = customer.status === 'inactive' ? 'Reactivate' : 'Inactivate'
  return (
    <>
      <PageHeader
        back={{ href: '/customers', label: 'Accounts' }}
        title={customerName(customer)}
        meta={
          <>
            <span className="ident">{customer.customer_number}</span> · {humanize(customer.customer_type)} ·
            customer since {date(customer.created_at)}
            {edited ? (
              <span title={edited.reason ?? undefined}>
                {' '}
                · edited {stamp(edited.at)} by {edited.by}
              </span>
            ) : null}
          </>
        }
        actions={
          <>
            <StatusButton verb={verb} onClick={() => setStatusOpen(true)} />
            {actions}
            <DeceasedAction base={base} current={customer} />
            <EditButton onClick={() => setOpen(true)} />
          </>
        }
      />
      <EditAccount
        base={base}
        current={customer}
        open={open}
        onClose={() => setOpen(false)}
        onRecordDeath={() => {
          setOpen(false)
          setDeathOpen(true)
        }}
      />
      <RecordDeath base={base} current={customer} open={deathOpen} onClose={() => setDeathOpen(false)} />
      <AccountStatusChange
        base={base}
        current={customer}
        verb={verb}
        meter={meter}
        location={location}
        open={statusOpen}
        onClose={() => setStatusOpen(false)}
      />
    </>
  )
}

/** Protections and holds come first. A CSR must never miss these. */
export function AccountAlerts({ customer: base }: { customer: Customer }) {
  const customer = useCustomer(base)
  const changed = useLastStatusChange('customer', base.id)
  const deceased = useDeceased(base.id)
  const held = !!deceased?.holdActive
  const inactive = customer.status === 'inactive'
  if (!held && !inactive && !customer.do_not_disconnect && !customer.billing_hold) return null
  return (
    <div className="px-5 py-3 border-b border-rule-hair bg-surface space-y-2">
      {held && deceased ? (
        <StateBlock tone="critical">
          <p className="text-data text-ink-primary">
            <strong className="font-semibold">Deceased — account on hold.</strong> Died{' '}
            {date(deceased.dateOfDeath)}. No shutoff and no collections activity until the account is
            changed over to a family member. Proof on file:{' '}
            {PROOFS.filter((p) => deceased.proofs[p.kind]).length} of {PROOFS.length}.{' '}
            {reviewOverdue(deceased, asOf.validAt)
              ? `No update since ${date(deceased.lastUpdateOn)} — review overdue.`
              : `Review due ${date(deceased.reviewDueOn)} if nothing is recorded before then.`}
          </p>
        </StateBlock>
      ) : null}
      {inactive ? (
        <StateBlock tone="void">
          <p className="text-data text-ink-primary">
            <strong className="font-semibold">Inactive</strong>
            {changed?.effective ? <> since {date(changed.effective)}</> : null}
            {changed?.reason ? <> — {changed.reason}</> : null}. No bills are issued; payments still post
            against any remaining balance.
          </p>
        </StateBlock>
      ) : null}
      {customer.do_not_disconnect ? (
        <StateBlock tone="critical">
          <p className="text-data text-ink-primary">
            <strong className="font-semibold">Do not disconnect.</strong>{' '}
            {humanize(customer.disconnect_protection_type ?? '')} on file
            {customer.disconnect_protection_expiry ? <>, expires {date(customer.disconnect_protection_expiry)}</> : null}.
            No disconnection until then. Reminders and notices may continue where the rule allows
            them.
          </p>
        </StateBlock>
      ) : null}
      {customer.billing_hold ? (
        <StateBlock tone="held">
          <p className="text-data text-ink-primary">
            <strong className="font-semibold">Billing hold.</strong> {customer.billing_hold_reason}
          </p>
        </StateBlock>
      ) : null}
    </div>
  )
}

export function AccountFields({
  customer: base,
  location,
  premiseCount = 1,
}: {
  customer: Customer
  location?: ServiceLocation
  /** More than one on a landlord's account; the rest are listed under Service addresses. */
  premiseCount?: number
}) {
  const customer = useCustomer(base)
  const billTo = billingAddressLines(customer)
  const prefs = contactPreferences(customer)
  return (
    <FieldGrid cols={4}>
      <Field label="Status">
        <StateFlag tone={accountTone(customer.status)}>{humanize(customer.status)}</StateFlag>
      </Field>
      <Field label="Balance">
        <Money value={customer.balance} arrears={customer.status === 'collections'} />
      </Field>
      <Field label="Deposit held">
        <Money value={customer.deposit_amount} />
      </Field>
      <Field label="Tax exempt">{customer.is_tax_exempt ? 'Yes' : 'No'}</Field>
      <RateScheduleField customerId={base.id} />
      <Field label="Phone">{customer.phone ?? '—'}</Field>
      <Field label="Email">{customer.email ?? '—'}</Field>
      <Field label="Contact preferences">
        <span className="block">Reach by {CONTACT_METHOD_LABEL[prefs.contact].toLowerCase()}</span>
        <span className="block">{LANGUAGE_LABEL[prefs.language]}</span>
        <span className="text-ink-secondary">Bills: {BILL_DELIVERY_LABEL[prefs.delivery].toLowerCase()}</span>
      </Field>
      <Field
        label="Service address"
        hint={premiseCount > 1 ? `Primary · ${premiseCount - 1} more under Service addresses` : undefined}
      >
        {location ? (
          <>
            {location.address}
            <br />
            <span className="text-ink-secondary">
              {location.city}, {location.state} {location.zip}
            </span>
          </>
        ) : (
          '—'
        )}
      </Field>
      <Field label="Billing address" hint={billTo ? 'Bills and letters are mailed here' : undefined}>
        {billTo ? (
          <>
            {billTo.slice(0, -1).map((l) => (
              <span key={l} className="block">
                {l}
              </span>
            ))}
            <span className="text-ink-secondary">{billTo[billTo.length - 1]}</span>
          </>
        ) : (
          <span className="text-ink-secondary">Same as service address</span>
        )}
      </Field>
      <Field
        label="Franchise city"
        hint={location?.inside_city_limits ? 'Inside city limits — franchise fee applies' : 'Outside city limits — no franchise fee'}
      >
        {location?.franchise_city ?? 'None'}
      </Field>
    </FieldGrid>
  )
}

/* ---- Inactivate / reactivate ----------------------------------------- */

function AccountStatusChange({
  base,
  current,
  verb,
  meter: meterBase,
  location,
  open,
  onClose,
}: {
  base: Customer
  current: Customer
  verb: 'Inactivate' | 'Reactivate'
  meter?: Meter
  location?: ServiceLocation
  open: boolean
  onClose: () => void
}) {
  /* The meter set at the premise now: an exchange moves the account to the new one. */
  const meterNow = useMeterNow(meterBase)
  const meterEdit = useEdits().meters[meterNow?.id ?? '']
  const meter = meterNow ? { ...meterNow, ...meterEdit } : undefined
  const changed = useLastStatusChange('customer', base.id)
  const balance = Number(current.balance)
  const deposit = Number(current.deposit_amount)

  const consequences: Consequence[] = []
  if (verb === 'Inactivate') {
    if (balance > 0)
      consequences.push({
        id: 'balance',
        tone: 'warning',
        acknowledge: true,
        text: (
          <>
            A balance of <strong className="font-semibold">{money(balance)}</strong> stays on the account.
            Inactivating doesn’t bill it or write it off — issue the final bill, and anything left unpaid moves
            through collections.
          </>
        ),
      })
    if (balance < 0)
      consequences.push({
        id: 'credit',
        tone: 'warning',
        acknowledge: true,
        text: <>A credit of {money(-balance)} is owed to the customer and must be refunded.</>,
      })
    if (deposit > 0)
      consequences.push({
        id: 'deposit',
        tone: 'warning',
        acknowledge: true,
        text: <>A deposit of {money(deposit)} is still held. Apply it to the final bill or refund it.</>,
      })
    if (current.status === 'collections')
      consequences.push({
        id: 'collections',
        tone: 'warning',
        acknowledge: true,
        text: 'The account is in collections. Inactivating stops dunning notices; the debt stays on the account.',
      })
    if (current.do_not_disconnect)
      consequences.push({
        id: 'dnd',
        tone: 'info',
        text: 'The do-not-disconnect protection ends with the account. Confirm the customer asked to close it.',
      })
    consequences.push({
      id: 'bills',
      tone: 'info',
      text: 'No bills are issued after the effective date. Bills, payments and the ledger stay on the account.',
    })
  } else {
    consequences.push({
      id: 'bills',
      tone: 'info',
      text: 'Billing resumes on the next run for the service address. Bills skipped while inactive are not back-billed.',
    })
  }

  /* Offer the premise's meter only when it is in the status this change moves away from. */
  const offerMeter = !!meter && meter.status === (verb === 'Inactivate' ? 'active' : 'inactive')
  const extras = offerMeter
    ? [
        {
          id: 'meter',
          label: `Also ${verb.toLowerCase()} meter ${meter.meter_number}${location ? ` at ${location.address}` : ''}`,
          hint:
            verb === 'Inactivate'
              ? 'Leaves the service address shut off until a new account starts service there.'
              : 'Turns service back on at the service address from the same date.',
        },
      ]
    : []

  return (
    <StatusChangeDialog
      open={open}
      onClose={onClose}
      verb={verb}
      title={`${verb} account`}
      meta={
        <>
          <span className="ident">{base.customer_number}</span> · {customerName(current)}
        </>
      }
      reasons={verb === 'Inactivate' ? ACCOUNT_INACTIVATE_REASONS : ACCOUNT_REACTIVATE_REASONS}
      consequences={consequences}
      extras={extras}
      earliest={verb === 'Inactivate' ? current.move_in_date : (changed?.effective ?? null)}
      onConfirm={(reason, effective, chosen) => {
        const to = verb === 'Inactivate' ? 'inactive' : 'active'
        changeStatus('customer', base, to, reason, effective)
        if (meterNow && chosen.includes('meter')) changeStatus('meter', meterNow, to, reason, effective)
      }}
    />
  )
}

/* ---- The edit form --------------------------------------------------- */

type Draft = {
  first_name: string
  last_name: string
  company_name: string
  email: string
  phone: string
  customer_type: Customer['customer_type']
  is_tax_exempt: boolean
  billing_hold: boolean
  billing_hold_reason: string
  do_not_disconnect: boolean
  disconnect_protection_type: string
  disconnect_protection_expiry: string
  billing_same: boolean
  billing_address_line1: string
  billing_address_line2: string
  billing_city: string
  billing_state: string
  billing_zip: string
  preferred_contact_method: ContactMethod
  preferred_language: PreferredLanguage
  billing_delivery_method: BillingDeliveryMethod
  reason: string
}

function draftFrom(c: Customer): Draft {
  return {
    first_name: c.first_name ?? '',
    last_name: c.last_name ?? '',
    company_name: c.company_name ?? '',
    email: c.email ?? '',
    phone: c.phone ?? '',
    customer_type: c.customer_type,
    is_tax_exempt: c.is_tax_exempt,
    billing_hold: c.billing_hold,
    billing_hold_reason: c.billing_hold_reason ?? '',
    do_not_disconnect: c.do_not_disconnect,
    disconnect_protection_type: c.disconnect_protection_type ?? '',
    disconnect_protection_expiry: c.disconnect_protection_expiry ?? '',
    billing_same: !c.billing_address_line1,
    billing_address_line1: c.billing_address_line1 ?? '',
    billing_address_line2: c.billing_address_line2 ?? '',
    billing_city: c.billing_city ?? '',
    billing_state: c.billing_state ?? 'TX',
    billing_zip: c.billing_zip ?? '',
    preferred_contact_method: contactPreferences(c).contact,
    preferred_language: contactPreferences(c).language,
    billing_delivery_method: contactPreferences(c).delivery,
    reason: '',
  }
}

const blank = (s: string) => (s.trim() === '' ? null : s.trim())

function formatPhone(v: string): string | null {
  const t = v.trim()
  if (!t) return null
  const digits = t.replace(/\D/g, '').replace(/^1(?=\d{10}$)/, '')
  return digits.length === 10 ? `(${digits.slice(0, 3)}) ${digits.slice(3, 6)}-${digits.slice(6)}` : t
}

/** The draft as the edit it would save, with protections cleared when switched off. */
function toEdit(d: Draft, current: Customer): CustomerEdit {
  const prefs = contactPreferences(current)
  return {
    first_name: blank(d.first_name),
    last_name: blank(d.last_name),
    company_name: blank(d.company_name),
    email: blank(d.email),
    phone: formatPhone(d.phone),
    customer_type: d.customer_type,
    is_tax_exempt: d.is_tax_exempt,
    billing_hold: d.billing_hold,
    billing_hold_reason: d.billing_hold ? blank(d.billing_hold_reason) : null,
    do_not_disconnect: d.do_not_disconnect,
    disconnect_protection_type: d.do_not_disconnect
      ? ((blank(d.disconnect_protection_type) as Customer['disconnect_protection_type']) ?? null)
      : null,
    disconnect_protection_expiry: d.do_not_disconnect ? blank(d.disconnect_protection_expiry) : null,
    /* Same as service address clears the billing address, so mail follows the service address again. */
    billing_address_line1: d.billing_same ? null : blank(d.billing_address_line1),
    billing_address_line2: d.billing_same ? null : blank(d.billing_address_line2),
    billing_city: d.billing_same ? null : blank(d.billing_city),
    billing_state: d.billing_same ? null : blank(d.billing_state),
    billing_zip: d.billing_same ? null : blank(d.billing_zip),
    /* A record without a preference reads the schema default; leaving the default alone records nothing. */
    ...(current.preferred_contact_method || d.preferred_contact_method !== prefs.contact
      ? { preferred_contact_method: d.preferred_contact_method }
      : {}),
    ...(current.preferred_language || d.preferred_language !== prefs.language ? { preferred_language: d.preferred_language } : {}),
    ...(current.billing_delivery_method || d.billing_delivery_method !== prefs.delivery
      ? { billing_delivery_method: d.billing_delivery_method }
      : {}),
  }
}

function validate(d: Draft, current: Customer): Partial<Record<keyof Draft, string>> {
  const e: Partial<Record<keyof Draft, string>> = {}
  if (!d.first_name.trim() && !d.last_name.trim() && !d.company_name.trim())
    e[d.customer_type === 'residential' ? 'last_name' : 'company_name'] = 'Enter a person or a company name'
  if (d.email.trim() && !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(d.email.trim())) e.email = 'Enter an email like name@example.com'
  if (d.phone.trim() && d.phone.replace(/\D/g, '').replace(/^1(?=\d{10}$)/, '').length !== 10)
    e.phone = 'Enter a 10-digit phone number'
  if (d.billing_hold && !d.billing_hold_reason.trim()) e.billing_hold_reason = 'Say why billing is held'
  /* A preference the account has no way to honour. Checked only on a change, so an old record still saves. */
  const prefs = contactPreferences(current)
  const noEmail = !d.email.trim()
  const noPhone = !d.phone.trim()
  if (d.preferred_contact_method !== prefs.contact) {
    if (d.preferred_contact_method === 'email' && noEmail) e.preferred_contact_method = 'Add an email address first'
    if ((d.preferred_contact_method === 'phone' || d.preferred_contact_method === 'text') && noPhone)
      e.preferred_contact_method = 'Add a phone number first'
  }
  if (d.billing_delivery_method !== prefs.delivery && (d.billing_delivery_method === 'email' || d.billing_delivery_method === 'both') && noEmail)
    e.billing_delivery_method = 'Add an email address first'
  if (!d.billing_same) {
    if (!d.billing_address_line1.trim()) e.billing_address_line1 = 'Enter the street address or P.O. box'
    if (!d.billing_city.trim()) e.billing_city = 'Enter the city'
    if (!d.billing_zip.trim()) e.billing_zip = 'Enter the ZIP'
  }
  if (d.do_not_disconnect && d.disconnect_protection_type === DECEASED) {
    e.disconnect_protection_type = 'Use Record death below, or choose another protection'
  } else if (d.do_not_disconnect) {
    if (!d.disconnect_protection_type) e.disconnect_protection_type = 'Choose the protection on file'
    if (!d.disconnect_protection_expiry) e.disconnect_protection_expiry = 'Enter when the protection expires'
    else if (d.disconnect_protection_expiry <= asOf.validAt)
      e.disconnect_protection_expiry = `Must be after ${date(asOf.validAt)}`
  }
  const edit = toEdit(d, current)
  const reasoned = CUSTOMER_REASONED.some((k) => edit[k] !== current[k])
  if (reasoned && !d.reason.trim()) e.reason = 'Protections, holds and tax status need a reason on record'
  return e
}

/** The protection dropdown's hand-off to Record death. Never saved as a protection type. */
const DECEASED = 'deceased'

/** The fields an edit would change, treating a field the record never had as null. */
function diffKeys(edit: CustomerEdit, current: Customer): Record<string, true> {
  const out: Record<string, true> = {}
  for (const [k, v] of Object.entries(edit)) if ((current[k as keyof Customer] ?? null) !== (v ?? null)) out[k] = true
  return out
}

function EditAccount({
  base,
  current,
  open,
  onClose,
  onRecordDeath,
}: {
  base: Customer
  current: Customer
  open: boolean
  onClose: () => void
  onRecordDeath: () => void
}) {
  const [draft, setDraft] = useState<Draft>(() => draftFrom(current))
  const [errors, setErrors] = useState<Partial<Record<keyof Draft, string>>>({})
  const [notice, setNotice] = useState<string | null>(null)
  const [lastOpen, setLastOpen] = useState(open)

  /* Each opening starts from the account as it stands now. */
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
  const death = useCanRecordDeath(base, current)
  /* "Deceased" is not a protection the edit saves: it hands over to Record death, which holds the account. */
  const deathChosen = draft.do_not_disconnect && draft.disconnect_protection_type === DECEASED
  const needsReason = !deathChosen && CUSTOMER_REASONED.some((k) => edit[k] !== current[k])
  const person = draft.customer_type === 'residential'
  const otherChanges = Object.keys(diffKeys(edit, current)).some(
    (k) => k !== 'do_not_disconnect' && k !== 'disconnect_protection_type' && k !== 'disconnect_protection_expiry',
  )

  function save() {
    const found = validate(draft, current)
    setErrors(found)
    if (Object.keys(found).length) return
    const changed = saveCustomer(base, edit, needsReason ? draft.reason.trim() : null)
    if (!changed) {
      setNotice('Nothing has changed yet.')
      return
    }
    onClose()
  }

  const input = (k: keyof Draft, props: React.InputHTMLAttributes<HTMLInputElement> = {}) => (
    <input
      id={`acct-${k}`}
      value={draft[k] as string}
      onChange={(e) => set(k, e.target.value as never)}
      aria-invalid={errors[k] ? true : undefined}
      aria-describedby={errors[k] ? `acct-${k}-error` : undefined}
      className={fieldClass}
      {...props}
    />
  )

  return (
    <Dialog
      open={open}
      onClose={onClose}
      title="Edit account"
      meta={
        <>
          <span className="ident">{base.customer_number}</span> · {customerName(current)}
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
        <fieldset className="space-y-3">
          <legend className="text-h3 text-ink-primary mb-2">Customer</legend>
          <FormField label="Customer type" htmlFor="acct-customer_type" hint="A class change can move the account to another rate schedule on its next bill.">
            <select
              id="acct-customer_type"
              value={draft.customer_type}
              onChange={(e) => set('customer_type', e.target.value as Customer['customer_type'])}
              className={fieldClass}
            >
              {CustomerType.options.map((t) => (
                <option key={t} value={t}>
                  {humanize(t)}
                </option>
              ))}
            </select>
          </FormField>
          {person ? (
            <div className="grid grid-cols-2 gap-3">
              <FormField label="First name" htmlFor="acct-first_name" error={errors.first_name}>
                {input('first_name', { autoComplete: 'off' })}
              </FormField>
              <FormField label="Last name" htmlFor="acct-last_name" error={errors.last_name}>
                {input('last_name', { autoComplete: 'off' })}
              </FormField>
            </div>
          ) : (
            <FormField label="Company name" htmlFor="acct-company_name" error={errors.company_name}>
              {input('company_name', { autoComplete: 'off' })}
            </FormField>
          )}
          <div className="grid grid-cols-2 gap-3">
            <FormField label="Phone" htmlFor="acct-phone" error={errors.phone}>
              {input('phone', { type: 'tel', placeholder: '(979) 555-0100', autoComplete: 'off' })}
            </FormField>
            <FormField label="Email" htmlFor="acct-email" error={errors.email}>
              {input('email', { type: 'email', placeholder: 'name@example.com', autoComplete: 'off' })}
            </FormField>
          </div>
        </fieldset>

        <fieldset className="space-y-3 border-t border-rule-hair pt-4">
          <legend className="sr-only">Contact preferences</legend>
          <p className="text-h3 text-ink-primary">Contact preferences</p>
          <div className="grid grid-cols-1 gap-3 sm:grid-cols-3">
            <FormField label="Reach by" htmlFor="acct-preferred_contact_method" error={errors.preferred_contact_method}>
              <select
                id="acct-preferred_contact_method"
                value={draft.preferred_contact_method}
                onChange={(e) => set('preferred_contact_method', e.target.value as ContactMethod)}
                className={fieldClass}
              >
                {ContactMethod.options.map((m) => (
                  <option key={m} value={m}>
                    {CONTACT_METHOD_LABEL[m]}
                  </option>
                ))}
              </select>
            </FormField>
            <FormField label="Language" htmlFor="acct-preferred_language">
              <select
                id="acct-preferred_language"
                value={draft.preferred_language}
                onChange={(e) => set('preferred_language', e.target.value as PreferredLanguage)}
                className={fieldClass}
              >
                {PreferredLanguage.options.map((l) => (
                  <option key={l} value={l}>
                    {LANGUAGE_LABEL[l]}
                  </option>
                ))}
              </select>
            </FormField>
            <FormField label="Bills sent by" htmlFor="acct-billing_delivery_method" error={errors.billing_delivery_method}>
              <select
                id="acct-billing_delivery_method"
                value={draft.billing_delivery_method}
                onChange={(e) => set('billing_delivery_method', e.target.value as BillingDeliveryMethod)}
                className={fieldClass}
              >
                {BillingDeliveryMethod.options.map((m) => (
                  <option key={m} value={m}>
                    {BILL_DELIVERY_LABEL[m]}
                  </option>
                ))}
              </select>
            </FormField>
          </div>
        </fieldset>

        <fieldset className="space-y-3 border-t border-rule-hair pt-4">
          <legend className="sr-only">Billing address</legend>
          <p className="text-h3 text-ink-primary">Billing address</p>
          <Toggle
            id="acct-billing-same"
            checked={draft.billing_same}
            onChange={(v) => set('billing_same', v)}
            label="Same as service address"
            hint="Turn off to mail bills and letters to a landlord, a P.O. box or an office that pays the bill."
          />
          {draft.billing_same ? null : (
            <div className="space-y-3 pl-11">
              <FormField label="Street address or P.O. box" htmlFor="acct-billing_address_line1" error={errors.billing_address_line1}>
                {input('billing_address_line1', { autoComplete: 'off' })}
              </FormField>
              <FormField label="Line 2" htmlFor="acct-billing_address_line2" hint="Attn, suite or unit">
                {input('billing_address_line2', { autoComplete: 'off' })}
              </FormField>
              <div className="grid grid-cols-[minmax(0,1fr)_4.5rem_6.5rem] gap-3">
                <FormField label="City" htmlFor="acct-billing_city" error={errors.billing_city}>
                  {input('billing_city', { autoComplete: 'off' })}
                </FormField>
                <FormField label="State" htmlFor="acct-billing_state">
                  {input('billing_state', { autoComplete: 'off', maxLength: 2 })}
                </FormField>
                <FormField label="ZIP" htmlFor="acct-billing_zip" error={errors.billing_zip}>
                  {input('billing_zip', { autoComplete: 'off', inputMode: 'numeric' })}
                </FormField>
              </div>
            </div>
          )}
        </fieldset>

        <fieldset className="space-y-3 border-t border-rule-hair pt-4">
          <legend className="sr-only">Protections and holds</legend>
          <p className="text-h3 text-ink-primary">Protections and holds</p>
          <Toggle
            id="acct-tax"
            checked={draft.is_tax_exempt}
            onChange={(v) => set('is_tax_exempt', v)}
            label="Tax exempt"
            hint="Keep the exemption certificate on file before turning this on."
          />
          <Toggle
            id="acct-hold"
            checked={draft.billing_hold}
            onChange={(v) => set('billing_hold', v)}
            label="Billing hold"
            hint="No bill is issued while the hold stands."
          />
          {draft.billing_hold ? (
            <FormField label="Hold reason" htmlFor="acct-billing_hold_reason" error={errors.billing_hold_reason} className="pl-11">
              {input('billing_hold_reason', { placeholder: 'Move-out read disputed, pending field recheck' })}
            </FormField>
          ) : null}
          <Toggle
            id="acct-dnd"
            checked={draft.do_not_disconnect}
            onChange={(v) => set('do_not_disconnect', v)}
            label="Do not disconnect"
            hint="Suspends collections activity until the protection expires."
          />
          {draft.do_not_disconnect ? (
            <div className="grid grid-cols-2 gap-3 pl-11">
              <FormField label="Protection" htmlFor="acct-disconnect_protection_type" error={errors.disconnect_protection_type}>
                <select
                  id="acct-disconnect_protection_type"
                  value={draft.disconnect_protection_type}
                  onChange={(e) => set('disconnect_protection_type', e.target.value)}
                  aria-invalid={errors.disconnect_protection_type ? true : undefined}
                  className={fieldClass}
                >
                  <option value="">Choose…</option>
                  {DisconnectProtectionType.options.map((t) => (
                    <option key={t} value={t}>
                      {humanize(t)}
                    </option>
                  ))}
                  {death.offered ? (
                    <option value={DECEASED} disabled={!!death.blockedBecause} title={death.blockedBecause ?? undefined}>
                      Deceased — record death
                    </option>
                  ) : null}
                </select>
              </FormField>
              {deathChosen ? null : (
                <FormField label="Expires" htmlFor="acct-disconnect_protection_expiry" error={errors.disconnect_protection_expiry}>
                  {input('disconnect_protection_expiry', { type: 'date' })}
                </FormField>
              )}
              {deathChosen ? (
                <StateBlock tone="held" className="col-span-2 px-3! py-2.5!">
                  <p className="text-data text-ink-primary">
                    Recording a death holds the account: no shutoff and no collections until it is changed over to
                    a family member. You’ll enter the date of death and confirm what happens next.
                  </p>
                  {otherChanges ? (
                    <p className="mt-1 text-micro text-exception-warning-text">
                      Other changes in this form aren’t saved by recording the death. Save them first, then come back.
                    </p>
                  ) : null}
                  <div className="mt-2">
                    <Button variant="primary" onClick={onRecordDeath} disabled={otherChanges}>
                      Record death…
                    </Button>
                  </div>
                </StateBlock>
              ) : null}
            </div>
          ) : null}
          {needsReason ? (
            <FormField
              label="Reason for this change"
              htmlFor="acct-reason"
              error={errors.reason}
              hint="Recorded with the change, as the schema's state events require."
            >
              <textarea
                id="acct-reason"
                rows={2}
                value={draft.reason}
                onChange={(e) => set('reason', e.target.value)}
                aria-invalid={errors.reason ? true : undefined}
                className={`${fieldClass} h-auto py-1.5`}
              />
            </FormField>
          ) : null}
        </fieldset>

        <p className="rounded-sm bg-surface-sunken px-3 py-2 text-micro text-ink-secondary">
          The account number, status, balance and deposit aren’t edited here. Balance and deposit move
          only through bills, payments and the ledger; the service address and meter belong to the
          property, not the customer — the billing address is the customer’s. Changes are kept in this browser until the API exists.
        </p>
        {/* Enter in a field submits. */}
        <button type="submit" className="hidden" aria-hidden tabIndex={-1} />
      </form>
    </Dialog>
  )
}

function Toggle({
  id,
  checked,
  onChange,
  label,
  hint,
}: {
  id: string
  checked: boolean
  onChange: (v: boolean) => void
  label: string
  hint: string
}) {
  return (
    <div className="flex items-start gap-3">
      <button
        id={id}
        type="button"
        role="switch"
        aria-checked={checked}
        onClick={() => onChange(!checked)}
        className={`relative mt-0.5 h-5 w-8 shrink-0 rounded-full transition-colors duration-fast ${
          checked ? 'bg-accent' : 'bg-surface-inset border border-rule-solid'
        }`}
      >
        <span
          aria-hidden
          className={`absolute top-1/2 h-3.5 w-3.5 -translate-y-1/2 rounded-full bg-surface-raised shadow-panel transition-transform duration-fast ${
            checked ? 'translate-x-3.5 left-0.5' : 'left-0.5'
          }`}
        />
      </button>
      <label htmlFor={id} className="min-w-0 cursor-pointer">
        <span className="block text-data text-ink-primary">{label}</span>
        <span className="block text-micro text-ink-tertiary">{hint}</span>
      </label>
    </div>
  )
}
