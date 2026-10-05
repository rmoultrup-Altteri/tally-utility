'use client'

import { useState, type ReactNode } from 'react'
import { PageHeader } from '@/components/shell/PageHeader'
import { Button, Field, FieldGrid } from '@/components/ui/Panel'
import { Money } from '@/components/ui/Money'
import { StateBlock, StateFlag, humanize } from '@/components/ui/State'
import { Dialog, EditButton, FormField, fieldClass } from '@/components/ui/Dialog'
import {
  CUSTOMER_REASONED,
  saveCustomer,
  useCustomer,
  useLastEdit,
  type CustomerEdit,
} from '@/lib/edits-store'
import { asOf } from '@/fixtures/tenant'
import { CustomerType, DisconnectProtectionType } from '@/schemas/enums'
import { customerName, type Customer, type ServiceLocation } from '@/schemas/models'
import { date, stamp } from '@/lib/format'

/**
 * The parts of the account screen that show editable fields. They read the
 * account through `useCustomer`, so an edit saved in the dialog shows at once
 * everywhere on the page without a reload.
 */

export function AccountHeader({ customer: base, actions }: { customer: Customer; actions: ReactNode }) {
  const customer = useCustomer(base)
  const edited = useLastEdit('customer', base.id)
  const [open, setOpen] = useState(false)
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
            {actions}
            <EditButton onClick={() => setOpen(true)} />
          </>
        }
      />
      <EditAccount base={base} current={customer} open={open} onClose={() => setOpen(false)} />
    </>
  )
}

/** Protections and holds come first. A CSR must never miss these. */
export function AccountAlerts({ customer: base }: { customer: Customer }) {
  const customer = useCustomer(base)
  if (!customer.do_not_disconnect && !customer.billing_hold) return null
  return (
    <div className="px-5 py-3 border-b border-rule-hair bg-surface space-y-2">
      {customer.do_not_disconnect ? (
        <StateBlock tone="critical">
          <p className="text-data text-ink-primary">
            <strong className="font-semibold">Do not disconnect.</strong>{' '}
            {humanize(customer.disconnect_protection_type ?? '')} on file
            {customer.disconnect_protection_expiry ? <>, expires {date(customer.disconnect_protection_expiry)}</> : null}.
            Collections activity on this account is suspended until then.
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

export function AccountFields({ customer: base, location }: { customer: Customer; location?: ServiceLocation }) {
  const customer = useCustomer(base)
  return (
    <FieldGrid cols={4}>
      <Field label="Status">
        <StateFlag tone={customer.status === 'active' ? 'approved' : 'failed'}>{humanize(customer.status)}</StateFlag>
      </Field>
      <Field label="Balance">
        <Money value={customer.balance} arrears={customer.status === 'collections'} />
      </Field>
      <Field label="Deposit held">
        <Money value={customer.deposit_amount} />
      </Field>
      <Field label="Tax exempt">{customer.is_tax_exempt ? 'Yes' : 'No'}</Field>
      <Field label="Phone">{customer.phone ?? '—'}</Field>
      <Field label="Email">{customer.email ?? '—'}</Field>
      <Field label="Premise">
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
      <Field
        label="Franchise city"
        hint={location?.inside_city_limits ? 'Inside city limits — franchise fee applies' : 'Outside city limits — no franchise fee'}
      >
        {location?.franchise_city ?? 'None'}
      </Field>
    </FieldGrid>
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
function toEdit(d: Draft): CustomerEdit {
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
  if (d.do_not_disconnect) {
    if (!d.disconnect_protection_type) e.disconnect_protection_type = 'Choose the protection on file'
    if (!d.disconnect_protection_expiry) e.disconnect_protection_expiry = 'Enter when the protection expires'
    else if (d.disconnect_protection_expiry <= asOf.validAt)
      e.disconnect_protection_expiry = `Must be after ${date(asOf.validAt)}`
  }
  const edit = toEdit(d)
  const reasoned = CUSTOMER_REASONED.some((k) => edit[k] !== current[k])
  if (reasoned && !d.reason.trim()) e.reason = 'Protections, holds and tax status need a reason on record'
  return e
}

function EditAccount({
  base,
  current,
  open,
  onClose,
}: {
  base: Customer
  current: Customer
  open: boolean
  onClose: () => void
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

  const edit = toEdit(draft)
  const needsReason = CUSTOMER_REASONED.some((k) => edit[k] !== current[k])
  const person = draft.customer_type === 'residential'

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
                </select>
              </FormField>
              <FormField label="Expires" htmlFor="acct-disconnect_protection_expiry" error={errors.disconnect_protection_expiry}>
                {input('disconnect_protection_expiry', { type: 'date' })}
              </FormField>
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
          only through bills, payments and the ledger; the premise and meter belong to the service
          location, not the customer. Changes are kept in this browser until the API exists.
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
