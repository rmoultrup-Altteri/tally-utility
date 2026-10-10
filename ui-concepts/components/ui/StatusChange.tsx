'use client'

import { useState, type ReactNode } from 'react'
import { Button } from '@/components/ui/Panel'
import { Dialog, FormField, fieldClass } from '@/components/ui/Dialog'
import { StateBlock, type Tone } from '@/components/ui/State'
import { useAccess } from '@/lib/access'
import { asOf } from '@/fixtures/tenant'
import { date } from '@/lib/format'

/**
 * Inactivating or reactivating an account or a meter.
 *
 * Both are state events, so the dialog asks the same three things of either:
 * why, from what service date, and — when something downstream will move —
 * an explicit acknowledgement of each consequence. A consequence the operator
 * has not ticked blocks the save; a note only informs.
 */

export type Consequence = {
  id: string
  tone: Tone
  text: ReactNode
  /** True when the operator must tick it before the change can save. */
  acknowledge?: boolean
}

export type Extra = { id: string; label: string; hint?: string }

const OTHER = 'Other'

export function StatusChangeDialog({
  open,
  onClose,
  verb,
  title,
  meta,
  reasons,
  consequences,
  extras = [],
  earliest,
  onConfirm,
}: {
  open: boolean
  onClose: () => void
  verb: 'Inactivate' | 'Reactivate'
  title: ReactNode
  meta?: ReactNode
  reasons: string[]
  consequences: Consequence[]
  /** Optional companion actions offered as checkboxes, such as inactivating the premise's meter too. */
  extras?: Extra[]
  /** The earliest effective date allowed, such as the last read the record was billed on. */
  earliest?: string | null
  onConfirm: (reason: string, effective: string, extras: string[]) => void
}) {
  const [reason, setReason] = useState('')
  const [other, setOther] = useState('')
  const [effective, setEffective] = useState<string>(asOf.validAt)
  const [acked, setAcked] = useState<string[]>([])
  const [chosen, setChosen] = useState<string[]>([])
  const [errors, setErrors] = useState<{ reason?: string; effective?: string; ack?: string }>({})
  const [lastOpen, setLastOpen] = useState(open)

  /* Each opening starts blank. */
  if (open !== lastOpen) {
    setLastOpen(open)
    if (open) {
      setReason('')
      setOther('')
      setEffective(asOf.validAt)
      setAcked([])
      setChosen([])
      setErrors({})
    }
  }

  const required = consequences.filter((c) => c.acknowledge)
  const toggle = (xs: string[], id: string) => (xs.includes(id) ? xs.filter((x) => x !== id) : [...xs, id])

  function save() {
    const e: typeof errors = {}
    const why = reason === OTHER ? other.trim() : reason
    if (!why) e.reason = reason === OTHER ? 'Say why' : 'Choose a reason'
    if (!effective) e.effective = 'Enter the date this takes effect'
    else if (earliest && effective < earliest) e.effective = `Can’t be before ${date(earliest)}`
    if (required.some((c) => !acked.includes(c.id))) e.ack = 'Tick each item above to confirm you’ve read it'
    setErrors(e)
    if (Object.keys(e).length) return
    onConfirm(why, effective, chosen)
    onClose()
  }

  return (
    <Dialog
      open={open}
      onClose={onClose}
      title={title}
      meta={meta}
      footer={
        <>
          <Button variant="quiet" onClick={onClose}>
            Cancel
          </Button>
          <Button variant={verb === 'Inactivate' ? 'danger' : 'primary'} onClick={save}>
            {verb}
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
        {consequences.length ? (
          <div className="space-y-2">
            {consequences.map((c) => (
              <StateBlock key={c.id} tone={c.tone} className="px-3! py-2.5!">
                {c.acknowledge ? (
                  <label className="flex cursor-pointer items-start gap-2.5 text-data text-ink-primary">
                    <input
                      type="checkbox"
                      checked={acked.includes(c.id)}
                      onChange={() => {
                        setAcked((xs) => toggle(xs, c.id))
                        setErrors((x) => ({ ...x, ack: undefined }))
                      }}
                      className="mt-0.5 h-4 w-4 shrink-0 accent-accent"
                    />
                    <span>{c.text}</span>
                  </label>
                ) : (
                  <p className="text-data text-ink-primary">{c.text}</p>
                )}
              </StateBlock>
            ))}
            {errors.ack ? <p className="text-micro text-exception-critical-text">{errors.ack}</p> : null}
          </div>
        ) : null}

        <div className="grid grid-cols-2 gap-3">
          <FormField label="Reason" htmlFor="status-reason" error={errors.reason}>
            <select
              id="status-reason"
              value={reason}
              onChange={(e) => {
                setReason(e.target.value)
                setErrors((x) => ({ ...x, reason: undefined }))
              }}
              aria-invalid={errors.reason && reason !== OTHER ? true : undefined}
              className={fieldClass}
            >
              <option value="">Choose…</option>
              {[...reasons, OTHER].map((r) => (
                <option key={r} value={r}>
                  {r}
                </option>
              ))}
            </select>
          </FormField>
          <FormField
            label="Effective"
            htmlFor="status-effective"
            error={errors.effective}
            hint={earliest ? `On or after ${date(earliest)}` : undefined}
          >
            <input
              id="status-effective"
              type="date"
              value={effective}
              min={earliest ?? undefined}
              onChange={(e) => {
                setEffective(e.target.value)
                setErrors((x) => ({ ...x, effective: undefined }))
              }}
              aria-invalid={errors.effective ? true : undefined}
              className={fieldClass}
            />
          </FormField>
        </div>
        {reason === OTHER ? (
          <FormField label="Describe the reason" htmlFor="status-other" error={errors.reason}>
            <textarea
              id="status-other"
              rows={2}
              value={other}
              onChange={(e) => {
                setOther(e.target.value)
                setErrors((x) => ({ ...x, reason: undefined }))
              }}
              aria-invalid={errors.reason ? true : undefined}
              className={`${fieldClass} h-auto py-1.5`}
            />
          </FormField>
        ) : null}

        {extras.length ? (
          <div className="space-y-2 border-t border-rule-hair pt-3">
            {extras.map((x) => (
              <label key={x.id} className="flex cursor-pointer items-start gap-2.5">
                <input
                  type="checkbox"
                  checked={chosen.includes(x.id)}
                  onChange={() => setChosen((xs) => toggle(xs, x.id))}
                  className="mt-0.5 h-4 w-4 shrink-0 accent-accent"
                />
                <span>
                  <span className="block text-data text-ink-primary">{x.label}</span>
                  {x.hint ? <span className="block text-micro text-ink-tertiary">{x.hint}</span> : null}
                </span>
              </label>
            ))}
          </div>
        ) : null}

        <p className="rounded-sm bg-surface-sunken px-3 py-2 text-micro text-ink-secondary">
          Recorded with your name, the reason and the effective date, and reversible by reactivating.
          Nothing is deleted: bills, reads and the ledger stay on the record. Kept in this browser until
          the API exists.
        </p>
        <button type="submit" className="hidden" aria-hidden tabIndex={-1} />
      </form>
    </Dialog>
  )
}

/** The header button that opens the dialog, shown disabled to a role that cannot use it. */
export function StatusButton({ verb, onClick }: { verb: 'Inactivate' | 'Reactivate'; onClick: () => void }) {
  const { can, holders } = useAccess()
  const allowed = can('customer.edit')
  return (
    <Button
      variant={verb === 'Inactivate' ? 'danger' : 'default'}
      onClick={onClick}
      disabled={!allowed}
      title={
        allowed
          ? undefined
          : `Your role can’t change account or meter status. Ask someone with ${holders('customer.edit')
              .map((r) => r.name)
              .join(', ')}.`
      }
    >
      {verb}
    </Button>
  )
}
