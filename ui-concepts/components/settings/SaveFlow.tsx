'use client'

import { useEffect, useState } from 'react'
import { Button } from '@/components/ui/Panel'
import { Dialog, FormField, fieldClass } from '@/components/ui/Dialog'
import { asOf, cycle } from '@/fixtures/tenant'
import { date } from '@/lib/format'
import { addCalendarDays } from '@/lib/working-days'
import { controlClass, type ChangeLine } from './fields'

/**
 * Saving tenant settings.
 *
 * A tenant setting is history, not a field: a new value takes effect from a
 * date and the old one stays on record, so a bill issued last month can
 * still be explained by the settings in force when it was made. Saving
 * therefore asks two things — from when, and why. It never backdates:
 * bills already issued were made under the old values.
 *
 * A change to a tariff-bound value also asks for the filing it matches.
 *
 * Access changes are the exception to dating: who may do what applies at
 * once, so `immediate` asks only why. Personal preferences ask nothing.
 */

export type SaveRequest = { effectiveFrom: string; reason: string }

const NEXT_PERIOD = addCalendarDays(cycle.periodEnd, 1)

export function SaveBar({
  lines,
  blocked,
  mode = 'dated',
  onDiscard,
  onSave,
}: {
  lines: ChangeLine[]
  /** Why saving is not possible yet, if it is not. */
  blocked: string | null
  mode?: 'dated' | 'immediate' | 'personal'
  onDiscard: () => void
  onSave: (r: SaveRequest) => void
}) {
  const [open, setOpen] = useState(false)
  const [saved, setSaved] = useState<string | null>(null)

  useEffect(() => {
    if (!saved) return
    const t = setTimeout(() => setSaved(null), 4000)
    return () => clearTimeout(t)
  }, [saved])

  const n = lines.length
  const personal = mode === 'personal'
  if (!n && !saved) return null

  function commit(r: SaveRequest) {
    onSave(r)
    setOpen(false)
    setSaved(
      personal
        ? `Saved ${n} ${n === 1 ? 'preference' : 'preferences'}.`
        : mode === 'immediate'
          ? `Saved ${n} ${n === 1 ? 'change' : 'changes'}. In force now.`
          : `Saved ${n} ${n === 1 ? 'change' : 'changes'}, in force from ${date(r.effectiveFrom)}.`,
    )
  }

  return (
    <>
      <div className="sticky bottom-4 z-10 mt-5 rounded-md border border-rule-solid bg-surface-raised px-4 py-2.5 shadow-overlay">
        <div className="flex flex-wrap items-center justify-between gap-x-4 gap-y-2">
          {n ? (
            <>
              <p className="text-data text-ink-primary" role="status">
                {n} unsaved {n === 1 ? 'change' : 'changes'}
                {blocked ? <span className="ml-2 text-micro text-exception-critical-text">{blocked}</span> : null}
              </p>
              <div className="flex items-center gap-2">
                <Button variant="quiet" onClick={onDiscard}>
                  Discard
                </Button>
                <Button
                  variant="primary"
                  disabled={blocked !== null}
                  onClick={() => (personal ? commit({ effectiveFrom: asOf.validAt, reason: 'Personal preference' }) : setOpen(true))}
                >
                  {personal ? 'Save' : 'Review and save'}
                </Button>
              </div>
            </>
          ) : (
            <p className="text-data text-state-approved-text" role="status">
              {saved}
            </p>
          )}
        </div>
      </div>
      {personal ? null : <SaveDialog open={open} lines={lines} immediate={mode === 'immediate'} onClose={() => setOpen(false)} onSave={commit} />}
    </>
  )
}

function SaveDialog({
  open,
  lines,
  immediate,
  onClose,
  onSave,
}: {
  open: boolean
  lines: ChangeLine[]
  immediate: boolean
  onClose: () => void
  onSave: (r: SaveRequest) => void
}) {
  const [when, setWhen] = useState<'today' | 'next' | 'date'>('next')
  const [on, setOn] = useState(NEXT_PERIOD)
  const [reason, setReason] = useState('')
  const [filing, setFiling] = useState('')
  const [tried, setTried] = useState(false)

  useEffect(() => {
    if (open) {
      setReason('')
      setFiling('')
      setTried(false)
    }
  }, [open])

  const tariff = lines.some((l) => l.tariff)
  const effectiveFrom = immediate || when === 'today' ? asOf.validAt : when === 'next' ? NEXT_PERIOD : on
  const dateError = !immediate && when === 'date' && (!on || on < asOf.validAt) ? 'A setting cannot take effect before today.' : null
  const reasonError = reason.trim().length < 4 ? 'Say why — it is kept with the change.' : null
  const filingError = tariff && !filing.trim() ? 'Name the tariff sheet or ordinance this matches.' : null

  function submit() {
    setTried(true)
    if (dateError || reasonError || filingError) return
    onSave({ effectiveFrom, reason: tariff ? `${reason.trim()} · Filing: ${filing.trim()}` : reason.trim() })
  }

  const radio = 'flex items-start gap-2 rounded-sm px-2 py-1.5 hover:bg-surface-sunken cursor-pointer'

  return (
    <Dialog
      open={open}
      onClose={onClose}
      title="Save settings"
      meta={
        immediate
          ? 'Access changes apply at once. The previous assignment stays on record.'
          : 'The current values stay on record. Bills already made keep the values they were made under.'
      }
      footer={
        <>
          <Button variant="quiet" onClick={onClose}>
            Cancel
          </Button>
          <Button variant="primary" onClick={submit}>
            Save {lines.length} {lines.length === 1 ? 'change' : 'changes'}
          </Button>
        </>
      }
    >
      <div className="space-y-5">
        <div>
          <p className="field-label mb-1.5">Changes</p>
          <ul className="divide-y divide-rule-hair rounded-sm border border-rule-hair">
            {lines.map((l, i) => (
              <li key={i} className="px-3 py-2">
                <p className="text-micro text-ink-secondary">{l.label}</p>
                <p className="text-data">
                  <span className="text-ink-tertiary line-through decoration-ink-tertiary/60">{l.from}</span>
                  <span aria-hidden className="mx-1.5 text-ink-tertiary">→</span>
                  <span className="sr-only"> changes to </span>
                  <span className="font-medium text-ink-primary">{l.to}</span>
                </p>
              </li>
            ))}
          </ul>
        </div>

        {immediate ? null : (
        <fieldset>
          <legend className="field-label mb-1">In force from</legend>
          <label className={radio}>
            <input type="radio" name="when" className="mt-0.5" checked={when === 'next'} onChange={() => setWhen('next')} />
            <span className="text-data">
              The next billing period — {date(NEXT_PERIOD)}
              <span className="block text-micro text-ink-tertiary">Recommended. {cycle.label} finishes on the values it started with.</span>
            </span>
          </label>
          <label className={radio}>
            <input type="radio" name="when" className="mt-0.5" checked={when === 'today'} onChange={() => setWhen('today')} />
            <span className="text-data">
              Today — {date(asOf.validAt)}
              <span className="block text-micro text-ink-tertiary">Applies to anything evaluated from now, including the run in flight.</span>
            </span>
          </label>
          <label className={radio}>
            <input type="radio" name="when" className="mt-0.5" checked={when === 'date'} onChange={() => setWhen('date')} />
            <span className="text-data">A later date</span>
          </label>
          {when === 'date' ? (
            <div className="ml-7 mt-1">
              <input
                type="date"
                aria-label="Effective date"
                min={asOf.validAt}
                className={`${controlClass} w-44`}
                aria-invalid={(tried && dateError !== null) || undefined}
                value={on}
                onChange={(e) => setOn(e.target.value)}
              />
              {tried && dateError ? <p className="mt-1 text-micro text-exception-critical-text">{dateError}</p> : null}
            </div>
          ) : null}
        </fieldset>
        )}

        {tariff ? (
          <FormField
            label="Filing reference"
            htmlFor="filing"
            hint="Tariff-bound values must match what is on file."
            error={tried ? filingError : null}
          >
            <input
              id="filing"
              className={fieldClass}
              placeholder="e.g. RRC GUD 10928, Sheet 4"
              aria-invalid={(tried && filingError !== null) || undefined}
              value={filing}
              onChange={(e) => setFiling(e.target.value)}
            />
          </FormField>
        ) : null}

        <FormField label="Reason" htmlFor="reason" error={tried ? reasonError : null}>
          <textarea
            id="reason"
            rows={2}
            className={`${fieldClass} h-auto py-1.5`}
            placeholder="e.g. Board approved the 2026 collections policy"
            aria-invalid={(tried && reasonError !== null) || undefined}
            value={reason}
            onChange={(e) => setReason(e.target.value)}
          />
        </FormField>
      </div>
    </Dialog>
  )
}
