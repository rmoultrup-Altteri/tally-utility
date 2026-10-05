'use client'

import { useState } from 'react'
import { Button } from '@/components/ui/Panel'
import { StateBlock } from '@/components/ui/State'
import { Dialog, EditButton, FormField, fieldClass } from '@/components/ui/Dialog'
import { saveInvoice, useInvoice, useLastEdit } from '@/lib/edits-store'
import { date, dateShort, days, stamp } from '@/lib/format'
import type { Invoice } from '@/schemas/models'

/**
 * Editing a bill before it is issued.
 *
 * Only a draft or held bill — one with no `first_issued_at` — can be edited,
 * and only the fields a person sets: the bill date, the due date and why it
 * is held. The amounts and lines come from the billing run. An issued bill
 * never shows this button; its only correction is void, then rebill.
 */

export function EditInvoice({ invoice: base, runNumber }: { invoice: Invoice; runNumber: string | null }) {
  const [open, setOpen] = useState(false)
  if (base.first_issued_at !== null || base.status === 'void') return null
  return (
    <>
      <EditButton onClick={() => setOpen(true)} />
      <EditInvoiceDialog base={base} runNumber={runNumber} open={open} onClose={() => setOpen(false)} />
    </>
  )
}

type Draft = { invoice_date: string; due_date: string; hold_reason: string }

function EditInvoiceDialog({
  base,
  runNumber,
  open,
  onClose,
}: {
  base: Invoice
  runNumber: string | null
  open: boolean
  onClose: () => void
}) {
  const current = useInvoice(base)
  const held = base.held_at !== null
  const fresh = (): Draft => ({
    invoice_date: current.invoice_date,
    due_date: current.due_date,
    hold_reason: current.hold_reason ?? '',
  })
  const [draft, setDraft] = useState<Draft>(fresh)
  const [errors, setErrors] = useState<Partial<Record<keyof Draft, string>>>({})
  const [notice, setNotice] = useState<string | null>(null)
  const [lastOpen, setLastOpen] = useState(open)

  if (open !== lastOpen) {
    setLastOpen(open)
    if (open) {
      setDraft(fresh())
      setErrors({})
      setNotice(null)
    }
  }

  const set = (k: keyof Draft, v: string) => {
    setDraft((d) => ({ ...d, [k]: v }))
    if (errors[k]) setErrors((e) => ({ ...e, [k]: undefined }))
    setNotice(null)
  }

  function validate(): Partial<Record<keyof Draft, string>> {
    const e: Partial<Record<keyof Draft, string>> = {}
    if (!draft.invoice_date) e.invoice_date = 'Enter the bill date'
    else if (draft.invoice_date < base.period_end)
      e.invoice_date = `A bill can’t be dated before its service period ends (${date(base.period_end)})`
    if (!draft.due_date) e.due_date = 'Enter the due date'
    else if (draft.invoice_date && draft.due_date <= draft.invoice_date) e.due_date = 'The due date must come after the bill date'
    if (held && !draft.hold_reason.trim()) e.hold_reason = 'A held bill needs a reason on record'
    return e
  }

  function save() {
    const found = validate()
    setErrors(found)
    if (Object.keys(found).length) return
    const changed = saveInvoice(base, {
      invoice_date: draft.invoice_date,
      due_date: draft.due_date,
      ...(held ? { hold_reason: draft.hold_reason.trim() } : {}),
    })
    if (!changed) {
      setNotice('Nothing has changed yet.')
      return
    }
    onClose()
  }

  const gap = draft.invoice_date && draft.due_date && draft.due_date > draft.invoice_date ? days(draft.invoice_date, draft.due_date) : null

  return (
    <Dialog
      open={open}
      onClose={onClose}
      title={held ? 'Edit held bill' : 'Edit draft bill'}
      meta={
        <>
          <span className="ident">{base.invoice_number}</span> · {base.billing_period} · not yet issued
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
        className="space-y-4"
      >
        <div className="grid grid-cols-2 gap-3">
          <FormField label="Bill date" htmlFor="inv-date" error={errors.invoice_date}>
            <input
              id="inv-date"
              type="date"
              value={draft.invoice_date}
              onChange={(e) => set('invoice_date', e.target.value)}
              aria-invalid={errors.invoice_date ? true : undefined}
              aria-describedby={errors.invoice_date ? 'inv-date-error' : undefined}
              className={fieldClass}
            />
          </FormField>
          <FormField
            label="Due date"
            htmlFor="inv-due"
            error={errors.due_date}
            hint={gap !== null ? `${gap} days after the bill date` : undefined}
          >
            <input
              id="inv-due"
              type="date"
              value={draft.due_date}
              onChange={(e) => set('due_date', e.target.value)}
              aria-invalid={errors.due_date ? true : undefined}
              aria-describedby={errors.due_date ? 'inv-due-error' : undefined}
              className={fieldClass}
            />
          </FormField>
        </div>

        {held ? (
          <FormField
            label="Hold reason"
            htmlFor="inv-hold"
            error={errors.hold_reason}
            hint="Releasing the hold is a separate step; this only changes the reason on record."
          >
            <textarea
              id="inv-hold"
              rows={3}
              value={draft.hold_reason}
              onChange={(e) => set('hold_reason', e.target.value)}
              aria-invalid={errors.hold_reason ? true : undefined}
              className={`${fieldClass} h-auto py-1.5`}
            />
          </FormField>
        ) : null}

        <p className="rounded-sm bg-surface-sunken px-3 py-2 text-micro text-ink-secondary">
          The service period, usage, rates and amounts come from{' '}
          {runNumber ? (
            <>
              billing run <span className="ident">{runNumber}</span>
            </>
          ) : (
            'the billing run'
          )}{' '}
          and aren’t
          edited here. To change them, correct the read or the rate and re-run the bill. Once this bill is
          issued it can no longer be edited at all — only voided and rebilled. Changes are kept in this
          browser until the API exists.
        </p>
        <button type="submit" className="hidden" aria-hidden tabIndex={-1} />
      </form>
    </Dialog>
  )
}

/** The held-bill callout, reading the hold reason as edited. */
export function HoldNote({ invoice: base }: { invoice: Invoice }) {
  const invoice = useInvoice(base)
  if (!invoice.held_at) return null
  return (
    <StateBlock tone="held">
      <p className="text-data text-ink-primary">
        <strong className="font-semibold">Held {stamp(invoice.held_at)}.</strong> {invoice.hold_reason}
      </p>
      <p className="text-micro text-ink-secondary mt-1">
        A person stopped this bill and a person must release it. It cannot be sent while the blocking
        exception stands.
      </p>
    </StateBlock>
  )
}

/** "· edited Oct 5 by Dana Pearce" in a bill header, once it has been. */
export function InvoiceEditedNote({ id }: { id: string }) {
  const edited = useLastEdit('invoice', id)
  return edited ? (
    <>
      {' '}
      · edited {stamp(edited.at)} by {edited.by}
    </>
  ) : null
}

/** A bill date or due date in a table, as edited. */
export function InvoiceDateText({ invoice, field }: { invoice: Invoice; field: 'invoice_date' | 'due_date' }) {
  return <>{dateShort(useInvoice(invoice)[field])}</>
}
