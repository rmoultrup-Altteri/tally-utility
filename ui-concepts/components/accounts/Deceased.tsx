'use client'

import { useState, type ReactNode } from 'react'
import Link from 'next/link'
import { Button, Panel, PanelHeader } from '@/components/ui/Panel'
import { StateBlock, StateFlag } from '@/components/ui/State'
import { Dialog, FormField, fieldClass } from '@/components/ui/Dialog'
import type { Consequence } from '@/components/ui/StatusChange'
import { useAccess } from '@/lib/access'
import { changeStatus } from '@/lib/edits-store'
import { recordDeceasedStep, useDeceased } from '@/lib/deceased-store'
import { PROOFS, proofLabel, reviewOverdue, type DeceasedState, type DeceasedStep, type ProofKind } from '@/lib/deceased'
import { customers } from '@/fixtures/accounts'
import { asOf } from '@/fixtures/tenant'
import { customerName, type Customer } from '@/schemas/models'
import { date, money, stamp } from '@/lib/format'

/**
 * Recording a death, and the hold that follows it (R-08).
 *
 * Recording the death is a status change, so it goes through `changeStatus`
 * like an inactivation and lands in the same log with who, when and why. The
 * proof, notes and the change-over are steps on the deceased record, each
 * stamped the same way. Any step restarts the one-month review clock.
 */

const RELATIONSHIPS = ['Spouse', 'Child', 'Parent', 'Sibling', 'Executor or administrator', 'Conservator', 'Other family']

/** A header button gated on `customer.edit`, as the status button is. */
function GatedButton({
  children,
  onClick,
  variant = 'default',
  blockedBecause,
}: {
  children: ReactNode
  onClick: () => void
  variant?: 'default' | 'danger' | 'primary'
  blockedBecause?: string | null
}) {
  const { can, holders } = useAccess()
  const allowed = can('customer.edit')
  return (
    <Button
      variant={variant}
      onClick={onClick}
      disabled={!allowed || !!blockedBecause}
      title={
        !allowed
          ? `Your role can’t change account status. Ask someone with ${holders('customer.edit')
              .map((r) => r.name)
              .join(', ')}.`
          : (blockedBecause ?? undefined)
      }
    >
      {children}
    </Button>
  )
}

/**
 * The header action: "Record death" on a living account, then "Transfer to
 * family member" while the hold stands. Nothing once it has been changed over.
 */
export function DeceasedAction({ base, current }: { base: Customer; current: Customer }) {
  const state = useDeceased(base.id)
  const [recordOpen, setRecordOpen] = useState(false)
  const [transferOpen, setTransferOpen] = useState(false)

  if (state?.transfer) return null
  if (state)
    return (
      <>
        <GatedButton
          onClick={() => setTransferOpen(true)}
          blockedBecause={
            state.allProofs
              ? null
              : `Needs all three proofs first. Still outstanding: ${PROOFS.filter((p) => !state.proofs[p.kind])
                  .map((p) => p.label.toLowerCase())
                  .join('; ')}.`
          }
        >
          Transfer to family member
        </GatedButton>
        <TransferToFamily base={base} current={current} state={state} open={transferOpen} onClose={() => setTransferOpen(false)} />
      </>
    )
  if (current.status === 'inactive') return null
  return (
    <>
      <GatedButton onClick={() => setRecordOpen(true)}>Record death</GatedButton>
      <RecordDeath base={base} current={current} open={recordOpen} onClose={() => setRecordOpen(false)} />
    </>
  )
}

/* ---- Record death ---------------------------------------------------- */

function RecordDeath({ base, current, open, onClose }: { base: Customer; current: Customer; open: boolean; onClose: () => void }) {
  const [died, setDied] = useState('')
  const [notes, setNotes] = useState('')
  const [acked, setAcked] = useState<string[]>([])
  const [errors, setErrors] = useState<{ died?: string; ack?: string }>({})
  const [lastOpen, setLastOpen] = useState(open)

  /* Each opening starts blank. */
  if (open !== lastOpen) {
    setLastOpen(open)
    if (open) {
      setDied('')
      setNotes('')
      setAcked([])
      setErrors({})
    }
  }

  const balance = Number(current.balance)
  const consequences: Consequence[] = [
    {
      id: 'hold',
      tone: 'held',
      text: 'The account goes on hold: no shutoff and no collections activity until it is changed over to a family member.',
    },
  ]
  if (balance > 0)
    consequences.push({
      id: 'balance',
      tone: 'warning',
      acknowledge: true,
      text: (
        <>
          A balance of <strong className="font-semibold">{money(balance)}</strong> stays on the account. It
          isn’t written off; collections on it stop while the hold stands.
        </>
      ),
    })
  if (current.status === 'collections')
    consequences.push({
      id: 'collections',
      tone: 'warning',
      acknowledge: true,
      text: 'The account is in collections. Every notice, call and field order on it stops today.',
    })
  consequences.push({
    id: 'proof',
    tone: 'info',
    text: 'Changing the account over needs a death certificate, an obituary, and a will, conservatorship or spouse documentation. Record each as it comes in.',
  })
  consequences.push({
    id: 'review',
    tone: 'info',
    text: 'If nothing is recorded on the account for one month, a review exception goes on the queue.',
  })
  const required = consequences.filter((c) => c.acknowledge)

  function save() {
    const e: typeof errors = {}
    if (!died) e.died = 'Enter the date of death'
    else if (died > asOf.validAt) e.died = `Can’t be after ${date(asOf.validAt)}`
    if (required.some((c) => !acked.includes(c.id))) e.ack = 'Tick each item above to confirm you’ve read it'
    setErrors(e)
    if (Object.keys(e).length) return
    const note = notes.trim() || null
    changeStatus('customer', base, 'deceased', note ? `Death recorded: ${note}` : 'Death recorded', died)
    recordDeceasedStep({ customer_id: base.id, kind: 'death_recorded', date_of_death: died, notes: note })
    onClose()
  }

  return (
    <Dialog
      open={open}
      onClose={onClose}
      title="Record death"
      meta={
        <>
          <span className="ident">{base.customer_number}</span> · {customerName(current)}
        </>
      }
      footer={
        <>
          <Button variant="quiet" onClick={onClose}>
            Cancel
          </Button>
          <Button variant="primary" onClick={save}>
            Record death
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
        <div className="space-y-2">
          {consequences.map((c) => (
            <StateBlock key={c.id} tone={c.tone} className="px-3! py-2.5!">
              {c.acknowledge ? (
                <label className="flex cursor-pointer items-start gap-2.5 text-data text-ink-primary">
                  <input
                    type="checkbox"
                    checked={acked.includes(c.id)}
                    onChange={() => {
                      setAcked((xs) => (xs.includes(c.id) ? xs.filter((x) => x !== c.id) : [...xs, c.id]))
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
        <FormField label="Date of death" htmlFor="death-date" error={errors.died}>
          <input
            id="death-date"
            type="date"
            value={died}
            max={asOf.validAt}
            onChange={(e) => {
              setDied(e.target.value)
              setErrors((x) => ({ ...x, died: undefined }))
            }}
            aria-invalid={errors.died ? true : undefined}
            className={fieldClass}
          />
        </FormField>
        <FormField label="Notes" htmlFor="death-notes" hint="Who reported it, and anything they said about the family or the estate.">
          <textarea id="death-notes" rows={3} value={notes} onChange={(e) => setNotes(e.target.value)} className={`${fieldClass} h-auto py-1.5`} />
        </FormField>
        <p className="rounded-sm bg-surface-sunken px-3 py-2 text-micro text-ink-secondary">
          Recorded with your name and the date of death. Nothing is deleted: bills, payments and the
          ledger stay on the account. Kept in this browser until the API exists.
        </p>
        <button type="submit" className="hidden" aria-hidden tabIndex={-1} />
      </form>
    </Dialog>
  )
}

/* ---- Transfer to a family member ------------------------------------- */

const byNumber = new Map(customers.map((c) => [c.customer_number, c]))

function TransferToFamily({
  base,
  current,
  state,
  open,
  onClose,
}: {
  base: Customer
  current: Customer
  state: DeceasedState
  open: boolean
  onClose: () => void
}) {
  const blank = { name: '', relationship: '', account: '', phone: '', effective: asOf.validAt as string, notes: '' }
  const [draft, setDraft] = useState(blank)
  const [errors, setErrors] = useState<Partial<Record<keyof typeof blank, string>>>({})
  const [lastOpen, setLastOpen] = useState(open)

  if (open !== lastOpen) {
    setLastOpen(open)
    if (open) {
      setDraft(blank)
      setErrors({})
    }
  }

  const set = (k: keyof typeof blank, v: string) => {
    setDraft((d) => ({ ...d, [k]: v }))
    setErrors((e) => ({ ...e, [k]: undefined }))
  }

  function save() {
    const e: typeof errors = {}
    if (!draft.name.trim()) e.name = 'Enter the new account holder'
    if (!draft.relationship) e.relationship = 'Choose how they are related'
    if (!draft.effective) e.effective = 'Enter the date the change-over takes effect'
    else if (draft.effective < state.dateOfDeath) e.effective = `Can’t be before the date of death, ${date(state.dateOfDeath)}`
    const acct = draft.account.trim()
    if (acct && !byNumber.has(acct)) e.account = 'No account with that number. Leave it blank, or open their account first'
    else if (acct === base.customer_number) e.account = 'That is the deceased’s own account'
    setErrors(e)
    if (Object.keys(e).length) return
    const holder = {
      name: draft.name.trim(),
      relationship: draft.relationship,
      account_number: acct || null,
      phone: draft.phone.trim() || null,
    }
    recordDeceasedStep({
      customer_id: base.id,
      kind: 'transferred',
      new_holder: holder,
      effective: draft.effective,
      notes: draft.notes.trim() || null,
    })
    changeStatus('customer', base, 'inactive', `Changed over to ${holder.name} (${holder.relationship.toLowerCase()}) after death`, draft.effective)
    onClose()
  }

  const input = (k: keyof typeof blank, props: React.InputHTMLAttributes<HTMLInputElement> = {}) => (
    <input
      id={`xfer-${k}`}
      value={draft[k]}
      onChange={(e) => set(k, e.target.value)}
      aria-invalid={errors[k] ? true : undefined}
      className={fieldClass}
      {...props}
    />
  )

  return (
    <Dialog
      open={open}
      onClose={onClose}
      title="Transfer to family member"
      meta={
        <>
          <span className="ident">{base.customer_number}</span> · {customerName(current)} · died {date(state.dateOfDeath)}
        </>
      }
      footer={
        <>
          <Button variant="quiet" onClick={onClose}>
            Cancel
          </Button>
          <Button variant="primary" onClick={save}>
            Transfer and end the hold
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
        <StateBlock tone="info" className="px-3! py-2.5!">
          <p className="text-data text-ink-primary">
            All three proofs are on file. This records the new account holder, ends the hold and
            inactivates this account from the effective date. The balance stays on this account.
          </p>
        </StateBlock>
        <div className="grid grid-cols-2 gap-3">
          <FormField label="New account holder" htmlFor="xfer-name" error={errors.name}>
            {input('name', { autoComplete: 'off' })}
          </FormField>
          <FormField label="Relationship" htmlFor="xfer-relationship" error={errors.relationship}>
            <select
              id="xfer-relationship"
              value={draft.relationship}
              onChange={(e) => set('relationship', e.target.value)}
              aria-invalid={errors.relationship ? true : undefined}
              className={fieldClass}
            >
              <option value="">Choose…</option>
              {RELATIONSHIPS.map((r) => (
                <option key={r} value={r}>
                  {r}
                </option>
              ))}
            </select>
          </FormField>
          <FormField
            label="Their account number"
            htmlFor="xfer-account"
            error={errors.account}
            hint="If they already have an account here"
          >
            {input('account', { placeholder: '100-000000', autoComplete: 'off' })}
          </FormField>
          <FormField label="Phone" htmlFor="xfer-phone">
            {input('phone', { type: 'tel', autoComplete: 'off' })}
          </FormField>
          <FormField label="Effective" htmlFor="xfer-effective" error={errors.effective} hint={`On or after ${date(state.dateOfDeath)}`}>
            {input('effective', { type: 'date', min: state.dateOfDeath })}
          </FormField>
        </div>
        <FormField label="Notes" htmlFor="xfer-notes">
          <textarea id="xfer-notes" rows={2} value={draft.notes} onChange={(e) => set('notes', e.target.value)} className={`${fieldClass} h-auto py-1.5`} />
        </FormField>
        <p className="rounded-sm bg-surface-sunken px-3 py-2 text-micro text-ink-secondary">
          Not a customer yet? Open their account with{' '}
          <Link href="/customers/new" target="_blank" className="text-accent-text underline">
            New account
          </Link>{' '}
          at this service address first, then enter its number here. Recorded with your name. Kept in this browser
          until the API exists.
        </p>
        <button type="submit" className="hidden" aria-hidden tabIndex={-1} />
      </form>
    </Dialog>
  )
}

/* ---- The deceased-account panel -------------------------------------- */

const STEP_WORD: Record<DeceasedStep['kind'], string> = {
  death_recorded: 'Death recorded',
  proof: 'Proof received',
  note: 'Note',
  transferred: 'Changed over',
}

function stepSummary(s: DeceasedStep): string {
  switch (s.kind) {
    case 'death_recorded':
      return `Died ${date(s.date_of_death)}`
    case 'proof':
      return `${proofLabel(s.proof)}, received ${date(s.received)}`
    case 'note':
      return ''
    case 'transferred':
      return `To ${s.new_holder.name} (${s.new_holder.relationship.toLowerCase()})${s.new_holder.account_number ? `, account ${s.new_holder.account_number}` : ''}, effective ${date(s.effective)}`
  }
}

/** The proof checklist, the review clock and every step, on the customer page. */
export function DeceasedPanel({ customer }: { customer: Customer }) {
  const state = useDeceased(customer.id)
  const [proofOpen, setProofOpen] = useState<ProofKind | null>(null)
  const [noteOpen, setNoteOpen] = useState(false)
  const { can } = useAccess()
  const allowed = can('customer.edit')
  if (!state) return null
  const overdue = reviewOverdue(state, asOf.validAt)

  return (
    <Panel>
      <PanelHeader
        title="Deceased account"
        meta={`Died ${date(state.dateOfDeath)} · recorded ${date(state.recordedOn)} by ${state.recordedBy}`}
        actions={
          state.holdActive ? (
            <Button onClick={() => setNoteOpen(true)} disabled={!allowed}>
              Add note
            </Button>
          ) : null
        }
      />
      <div className="grid grid-cols-1 lg:grid-cols-2 divide-y lg:divide-y-0 lg:divide-x divide-rule-hair">
        <div className="px-4 py-3">
          <p className="field-label mb-2">Proof to change the account over</p>
          <ul className="space-y-2">
            {PROOFS.map((p) => {
              const got = state.proofs[p.kind]
              return (
                <li key={p.kind} className="flex items-start gap-2.5">
                  <span
                    aria-hidden
                    className={`mt-0.5 flex h-4 w-4 shrink-0 items-center justify-center rounded-xs border text-[10px] ${
                      got ? 'border-accent bg-accent text-ink-inverse' : 'border-rule-solid bg-surface-raised'
                    }`}
                  >
                    {got ? '✓' : ''}
                  </span>
                  <div className="min-w-0 flex-1">
                    <p className="text-data text-ink-primary">
                      {p.label}
                      <span className="sr-only">{got ? ', received' : ', not received'}</span>
                    </p>
                    {got ? (
                      <p className="text-micro text-ink-tertiary">
                        Received {date(got.received)} · recorded {stamp(got.at)} by {got.by}
                      </p>
                    ) : (
                      <p className="text-micro text-ink-tertiary">Not received</p>
                    )}
                  </div>
                  {!got && state.holdActive ? (
                    <Button variant="quiet" onClick={() => setProofOpen(p.kind)} disabled={!allowed}>
                      Record received
                    </Button>
                  ) : null}
                </li>
              )
            })}
          </ul>
        </div>
        <div className="px-4 py-3">
          <p className="field-label mb-2">Review clock</p>
          {state.transfer ? (
            <p className="text-data text-ink-primary">
              Changed over to <strong className="font-semibold">{state.transfer.new_holder.name}</strong> (
              {state.transfer.new_holder.relationship.toLowerCase()}) effective {date(state.transfer.effective)}. The
              hold has ended.
            </p>
          ) : (
            <>
              <p className="text-data text-ink-primary">
                {overdue ? (
                  <StateFlag tone="warning">Review overdue</StateFlag>
                ) : (
                  <StateFlag tone="info">Review due {date(state.reviewDueOn)}</StateFlag>
                )}
              </p>
              <p className="text-micro text-ink-secondary mt-1.5 leading-relaxed">
                Last update {date(state.lastUpdateOn)}. {overdue ? 'A month has passed with nothing recorded, so the account is on the exception queue for review.' : 'If nothing is recorded by then, a review exception goes on the queue.'}{' '}
                Any proof, note or change-over step restarts the clock.
              </p>
            </>
          )}
        </div>
      </div>
      <div className="border-t border-rule-hair">
        <p className="field-label px-4 pt-3 pb-1">Steps on record</p>
        <ul className="divide-y divide-rule-hair">
          {[...state.steps].reverse().map((s) => (
            <li key={s.id} className="px-4 py-2">
              <p className="text-data text-ink-primary">
                <strong className="font-semibold">{STEP_WORD[s.kind]}</strong>
                {stepSummary(s) ? <> · {stepSummary(s)}</> : null}
              </p>
              {s.notes ? <p className="text-micro text-ink-secondary">{s.notes}</p> : null}
              <p className="text-micro text-ink-tertiary">
                {stamp(s.at)} by {s.by}
              </p>
            </li>
          ))}
        </ul>
      </div>
      <RecordProof customer={customer} kind={proofOpen} onClose={() => setProofOpen(null)} />
      <AddNote customer={customer} open={noteOpen} onClose={() => setNoteOpen(false)} />
    </Panel>
  )
}

function RecordProof({ customer, kind, onClose }: { customer: Customer; kind: ProofKind | null; onClose: () => void }) {
  const [received, setReceived] = useState<string>(asOf.validAt)
  const [notes, setNotes] = useState('')
  const [error, setError] = useState<string | null>(null)
  const [lastKind, setLastKind] = useState(kind)

  if (kind !== lastKind) {
    setLastKind(kind)
    if (kind) {
      setReceived(asOf.validAt)
      setNotes('')
      setError(null)
    }
  }

  function save() {
    if (!kind) return
    if (!received) return setError('Enter the date it came in')
    if (received > asOf.validAt) return setError(`Can’t be after ${date(asOf.validAt)}`)
    recordDeceasedStep({ customer_id: customer.id, kind: 'proof', proof: kind, received, notes: notes.trim() || null })
    onClose()
  }

  return (
    <Dialog
      open={kind !== null}
      onClose={onClose}
      title={kind ? `${proofLabel(kind)} received` : ''}
      meta={
        <>
          <span className="ident">{customer.customer_number}</span> · {customerName(customer)}
        </>
      }
      footer={
        <>
          <Button variant="quiet" onClick={onClose}>
            Cancel
          </Button>
          <Button variant="primary" onClick={save}>
            Record
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
        <FormField label="Date received" htmlFor="proof-received" error={error}>
          <input
            id="proof-received"
            type="date"
            value={received}
            max={asOf.validAt}
            onChange={(e) => {
              setReceived(e.target.value)
              setError(null)
            }}
            aria-invalid={error ? true : undefined}
            className={fieldClass}
          />
        </FormField>
        <FormField label="Notes" htmlFor="proof-notes" hint="Where it came from and where the copy is filed.">
          <textarea id="proof-notes" rows={2} value={notes} onChange={(e) => setNotes(e.target.value)} className={`${fieldClass} h-auto py-1.5`} />
        </FormField>
        <p className="rounded-sm bg-surface-sunken px-3 py-2 text-micro text-ink-secondary">
          Recorded with your name, and restarts the one-month review clock. Kept in this browser until the API exists.
        </p>
        <button type="submit" className="hidden" aria-hidden tabIndex={-1} />
      </form>
    </Dialog>
  )
}

function AddNote({ customer, open, onClose }: { customer: Customer; open: boolean; onClose: () => void }) {
  const [notes, setNotes] = useState('')
  const [error, setError] = useState<string | null>(null)
  const [lastOpen, setLastOpen] = useState(open)

  if (open !== lastOpen) {
    setLastOpen(open)
    if (open) {
      setNotes('')
      setError(null)
    }
  }

  function save() {
    if (!notes.trim()) return setError('Write what happened')
    recordDeceasedStep({ customer_id: customer.id, kind: 'note', notes: notes.trim() })
    onClose()
  }

  return (
    <Dialog
      open={open}
      onClose={onClose}
      title="Add a note"
      meta={
        <>
          <span className="ident">{customer.customer_number}</span> · {customerName(customer)}
        </>
      }
      footer={
        <>
          <Button variant="quiet" onClick={onClose}>
            Cancel
          </Button>
          <Button variant="primary" onClick={save}>
            Add note
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
        <FormField label="Note" htmlFor="dec-note" error={error} hint="A call with the family, a letter from the estate, anything that moves the account on.">
          <textarea
            id="dec-note"
            rows={3}
            value={notes}
            onChange={(e) => {
              setNotes(e.target.value)
              setError(null)
            }}
            aria-invalid={error ? true : undefined}
            className={`${fieldClass} h-auto py-1.5`}
          />
        </FormField>
        <p className="rounded-sm bg-surface-sunken px-3 py-2 text-micro text-ink-secondary">
          Recorded with your name, and restarts the one-month review clock.
        </p>
        <button type="submit" className="hidden" aria-hidden tabIndex={-1} />
      </form>
    </Dialog>
  )
}
