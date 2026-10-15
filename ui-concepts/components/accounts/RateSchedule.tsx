'use client'

import { useState } from 'react'
import Link from 'next/link'
import type { Route } from 'next'
import { Button, Field, Panel, PanelHeader } from '@/components/ui/Panel'
import { Rail, StateFlag } from '@/components/ui/State'
import { Dialog, FormField, fieldClass } from '@/components/ui/Dialog'
import { Table, HeadRow, Th, Row, Td, RailCell } from '@/components/table/Table'
import { useAccess } from '@/lib/access'
import { addRateAssignment, useRateAssignments } from '@/lib/rate-assignments-store'
import { byStartDesc, currentAssignment, overlapProblem, pendingEnd } from '@/lib/rate-assignments'
import { addCalendarDays } from '@/lib/working-days'
import { rateSchedules } from '@/fixtures/rates'
import { asOf, cycle } from '@/fixtures/tenant'
import { customerName, type Customer, type Exception } from '@/schemas/models'
import { date, stamp } from '@/lib/format'

/**
 * The account's rate schedule and the history of it (R-09).
 *
 * Separate from the Rate History tab, which versions each rate item. This is
 * which schedule the customer was on, and when: add-only, no overlaps, the
 * standing row highlighted.
 */

/** The first day of the cycle after the one on screen — where a reclassification takes effect. */
export const NEXT_CYCLE_START = addCalendarDays(cycle.periodEnd, 1)

const scheduleByCode = new Map(rateSchedules.map((s) => [s.code, s]))

function ScheduleLink({ code }: { code: string }) {
  const schedule = scheduleByCode.get(code)
  return schedule ? (
    <Link
      href={`/rates#schedule-${code}` as Route}
      title={schedule.name}
      className="ident text-accent-text hover:text-accent-text-hover underline"
    >
      {code}
    </Link>
  ) : (
    <span className="ident">{code}</span>
  )
}

/** The "Rate schedule" field on the Account panel. */
export function RateScheduleField({ customerId }: { customerId: string }) {
  const rows = useRateAssignments(customerId)
  const now = currentAssignment(rows, asOf.validAt)
  const waiting = rows.find((r) => r.pending)
  return (
    <Field
      label="Rate schedule"
      hint={waiting ? `${waiting.schedule_code} from ${date(waiting.start_date)}, pending approval` : now ? `Since ${date(now.start_date)}` : undefined}
    >
      {now ? (
        <>
          <ScheduleLink code={now.schedule_code} />
          <span className="text-ink-secondary"> · {scheduleByCode.get(now.schedule_code)?.name ?? 'Not on the rate card'}</span>
        </>
      ) : (
        '—'
      )}
    </Field>
  )
}

/** The add-only history panel on the customer page. */
export function RateScheduleHistory({ customer }: { customer: Customer }) {
  const rows = useRateAssignments(customer.id)
  const ordered = byStartDesc(rows)
  const now = currentAssignment(rows, asOf.validAt)
  const [open, setOpen] = useState(false)
  const { can, holders } = useAccess()
  const allowed = can('customer.edit')

  return (
    <Panel>
      <PanelHeader
        title="Rate schedule history"
        meta="Add-only · a change closes the standing row · rows never overlap"
        actions={
          <Button
            onClick={() => setOpen(true)}
            disabled={!allowed}
            title={
              allowed
                ? undefined
                : `Your role can’t change a rate schedule. Ask someone with ${holders('customer.edit')
                    .map((r) => r.name)
                    .join(', ')}.`
            }
          >
            Change schedule
          </Button>
        }
      />
      <Table caption="Rate schedules this account has been assigned, newest first">
        <thead>
          <HeadRow>
            <Th width="3px"> </Th>
            <Th>Schedule</Th>
            <Th>Start</Th>
            <Th>End</Th>
            <Th>Reason</Th>
            <Th>Recorded</Th>
          </HeadRow>
        </thead>
        <tbody>
          {ordered.map((r) => {
            const current = r.id === now?.id
            const provisional = pendingEnd(rows, r)
            return (
              <Row key={r.id} selected={current}>
                <RailCell>
                  <Rail tone={r.pending ? 'pending' : current ? 'approved' : 'superseded'} />
                </RailCell>
                <Td>
                  <ScheduleLink code={r.schedule_code} />
                  {current ? (
                    <span className="ml-2">
                      <StateFlag tone="approved">Current</StateFlag>
                    </span>
                  ) : null}
                  {r.pending ? (
                    <span className="ml-2">
                      <StateFlag tone="pending" title="Takes effect only once a supervisor approves it">
                        Pending approval
                      </StateFlag>
                    </span>
                  ) : null}
                  <p className="text-micro text-ink-tertiary">{scheduleByCode.get(r.schedule_code)?.name ?? 'Not on the rate card'}</p>
                </Td>
                <Td>{date(r.start_date)}</Td>
                <Td>
                  {r.end_date ? (
                    date(r.end_date)
                  ) : provisional ? (
                    <span className="text-micro text-ink-tertiary">
                      {date(provisional.end_date)} if {provisional.successor.schedule_code} is approved
                    </span>
                  ) : null}
                </Td>
                <Td>
                  <span className="text-micro text-ink-secondary">{r.reason}</span>
                  {r.source_exception_id ? (
                    <p className="text-micro text-ink-tertiary">
                      From exception <span className="ident">{r.source_exception_id}</span>
                    </p>
                  ) : null}
                </Td>
                <Td>
                  <span className="text-micro text-ink-secondary whitespace-nowrap">{stamp(r.recorded_at)}</span>
                  <p className="text-micro text-ink-tertiary">by {r.recorded_by}</p>
                </Td>
              </Row>
            )
          })}
        </tbody>
      </Table>
      <div className="border-t border-rule-hair px-4 py-2.5">
        <p className="text-micro text-ink-tertiary">
          A row is never edited or deleted. A correction is a new row with its reason; the row before it
          closes the day before the new one starts. Issued bills keep the schedule they were priced on.
        </p>
      </div>
      <ChangeSchedule customer={customer} current={now?.schedule_code ?? null} open={open} onClose={() => setOpen(false)} />
    </Panel>
  )
}

function ChangeSchedule({
  customer,
  current,
  open,
  onClose,
}: {
  customer: Customer
  current: string | null
  open: boolean
  onClose: () => void
}) {
  const rows = useRateAssignments(customer.id)
  const [code, setCode] = useState('')
  const [start, setStart] = useState<string>(NEXT_CYCLE_START)
  const [reason, setReason] = useState('')
  const [errors, setErrors] = useState<{ code?: string; start?: string; reason?: string }>({})
  const [lastOpen, setLastOpen] = useState(open)

  /* Each opening starts blank. */
  if (open !== lastOpen) {
    setLastOpen(open)
    if (open) {
      setCode('')
      setStart(NEXT_CYCLE_START)
      setReason('')
      setErrors({})
    }
  }

  /* Checked as the date is keyed, so the overlap shows before Save. */
  const overlap = start ? overlapProblem(rows, start) : null

  function save() {
    const e: typeof errors = {}
    if (!code) e.code = 'Choose a schedule'
    else if (code === current) e.code = `The account is already on ${code}`
    if (!start) e.start = 'Enter the date the schedule starts'
    if (!reason.trim()) e.reason = 'Say why. The reason is kept with the row'
    setErrors(e)
    if (Object.keys(e).length) return
    const problem = addRateAssignment(customer.id, {
      schedule_code: code,
      start_date: start,
      reason: reason.trim(),
      pending: false,
      source_exception_id: null,
    })
    if (problem) {
      setErrors({ start: problem })
      return
    }
    onClose()
  }

  return (
    <Dialog
      open={open}
      onClose={onClose}
      title="Change rate schedule"
      meta={
        <>
          <span className="ident">{customer.customer_number}</span> · {customerName(customer)}
          {current ? <> · on {current} now</> : null}
        </>
      }
      footer={
        <>
          <Button variant="quiet" onClick={onClose}>
            Cancel
          </Button>
          <Button variant="primary" onClick={save} disabled={!!overlap}>
            Add row
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
          <FormField label="Schedule" htmlFor="ra-code" error={errors.code}>
            <select
              id="ra-code"
              value={code}
              onChange={(e) => {
                setCode(e.target.value)
                setErrors((x) => ({ ...x, code: undefined }))
              }}
              aria-invalid={errors.code ? true : undefined}
              className={fieldClass}
            >
              <option value="">Choose…</option>
              {rateSchedules.map((s) => (
                <option key={s.code} value={s.code}>
                  {s.code} · {s.name}
                </option>
              ))}
            </select>
          </FormField>
          <FormField
            label="Starts"
            htmlFor="ra-start"
            error={errors.start ?? overlap}
            hint={`The next cycle starts ${date(NEXT_CYCLE_START)}`}
          >
            <input
              id="ra-start"
              type="date"
              value={start}
              onChange={(e) => {
                setStart(e.target.value)
                setErrors((x) => ({ ...x, start: undefined }))
              }}
              aria-invalid={errors.start || overlap ? true : undefined}
              className={fieldClass}
            />
          </FormField>
        </div>
        <FormField label="Reason" htmlFor="ra-reason" error={errors.reason} hint="For a correction, say what the earlier row got wrong.">
          <textarea
            id="ra-reason"
            rows={2}
            value={reason}
            onChange={(e) => {
              setReason(e.target.value)
              setErrors((x) => ({ ...x, reason: undefined }))
            }}
            aria-invalid={errors.reason ? true : undefined}
            className={`${fieldClass} h-auto py-1.5`}
          />
        </FormField>
        <p className="rounded-sm bg-surface-sunken px-3 py-2 text-micro text-ink-secondary">
          Adds a row and closes the standing one the day before this starts. Nothing already on the
          history changes, and no issued bill is repriced. Recorded with your name. Kept in this browser
          until the API exists.
        </p>
        <button type="submit" className="hidden" aria-hidden tabIndex={-1} />
      </form>
    </Dialog>
  )
}

/**
 * The suggested action on a `rate_schedule_mismatch` exception: propose the
 * candidate schedule as a pending row from the next cycle. Nothing issued
 * changes, and nothing bills on the new schedule until it is approved.
 */
export function ProposeReclassification({ exception: e }: { exception: Exception }) {
  const customerId = e.customer_id ?? ''
  const rows = useRateAssignments(customerId)
  const [problem, setProblem] = useState<string | null>(null)
  const candidate = typeof e.details.candidate_schedule === 'string' ? e.details.candidate_schedule : null
  const proposed = rows.find((r) => r.source_exception_id === e.id)
  if (!candidate || !e.suggested_action || !customerId) return null

  if (proposed)
    return (
      <p className="text-micro text-ink-secondary">
        <StateFlag tone="pending">Proposed</StateFlag> {proposed.schedule_code} from {date(proposed.start_date)},
        pending approval, by {proposed.recorded_by} ·{' '}
        <Link href={`/customers/${customerId}` as Route} className="text-accent-text underline">
          See the rate schedule history
        </Link>
      </p>
    )

  return (
    <>
      <Button
        variant="primary"
        onClick={() =>
          setProblem(
            addRateAssignment(customerId, {
              schedule_code: candidate,
              start_date: NEXT_CYCLE_START,
              reason: `${e.description}. Proposed from the exception queue for supervisor approval.`,
              pending: true,
              source_exception_id: e.id,
            }),
          )
        }
      >
        {e.suggested_action.label}
      </Button>
      {problem ? <p className="mt-1 text-micro text-exception-critical-text">{problem}</p> : null}
    </>
  )
}
