'use client'

import { useMemo, useState, type ReactNode } from 'react'
import Link from 'next/link'
import type { Route } from 'next'
import { useRouter } from 'next/navigation'
import { Button, Field, FieldGrid, Key } from '@/components/ui/Panel'
import { StateBlock, StateFlag, humanize, invoiceTone } from '@/components/ui/State'
import { Money } from '@/components/ui/Money'
import { HeadRow, Row, Table, Td, Th } from '@/components/table/Table'
import { runs } from '@/fixtures/billing'
import { customerById } from '@/fixtures/accounts'
import { USERS } from '@/fixtures/roles'
import { customerName } from '@/schemas/models'
import { VoidReasonCode } from '@/schemas/enums'
import { useAccess } from '@/lib/access'
import { count, date, rate as fmtRate, stamp } from '@/lib/format'
import {
  nextCorrectionNumber,
  rateChanges,
  reprice,
  runEligibility,
  runTargets,
  type BatchMode,
} from '@/lib/run-corrections'
import { openFor, openReason, requestBatchCorrection, useBatchCorrections } from '@/lib/run-corrections-store'

/**
 * Void and rebill a whole run — the batch form of the single-bill election.
 *
 * It asks the same four questions as `/invoices/…/rebill` (which bills, why,
 * at which rates, on which correction run) plus the two that only matter at
 * scale: what happens to customers already in dunning, and who approves it.
 * The preview reprices every bill shown here to the cent, so the operator sees
 * what the election does before anything is voided.
 */

const money = (c: number) => (c / 100).toFixed(2)
const nameOf = (id: string) => USERS.find((u) => u.id === id)?.name ?? id
const IN_DUNNING = new Set(['reminder_sent', 'late_fee_assessed', 'shutoff_warning', 'shutoff_scheduled', 'collections'])

export function BatchRebill({ runId }: { runId: string }) {
  const run = runs.find((r) => r.id === runId)!
  const router = useRouter()
  const access = useAccess()
  const requests = useBatchCorrections()
  const eligibility = runEligibility(run)
  const targets = useMemo(() => runTargets(run), [run])
  const open = openFor(requests, run.id)

  const eligible = useMemo(() => targets.filter((t) => !t.excluded), [targets])
  const excludedCount = targets.length - eligible.length
  /* Every bill the run issued, less the ones known to be out already. */
  const runEligible = run.total_invoices - excludedCount

  const [scope, setScope] = useState<'all' | 'selected'>('all')
  const [picked, setPicked] = useState<string[]>(() => eligible.map((t) => t.invoice.id))
  const [reason, setReason] = useState<VoidReasonCode>('wrong_rate')
  const [notes, setNotes] = useState('')
  const [mode, setMode] = useState<BatchMode>('historical')
  const [dueDate, setDueDate] = useState<'reset' | 'original'>('reset')
  const [holdDunning, setHoldDunning] = useState(true)
  const [notify, setNotify] = useState(true)
  const [errors, setErrors] = useState<{ notes?: string; picked?: string }>({})

  const chosen = scope === 'all' ? eligible.map((t) => t.invoice.id) : picked
  const priced = useMemo(() => {
    const byMode = (m: BatchMode) => new Map(eligible.map((t) => [t.invoice.id, reprice(t.invoice, m)]))
    return { historical: byMode('historical'), current: byMode('current') }
  }, [eligible])
  const rows = priced[mode]
  const selectedPriced = chosen.map((id) => rows.get(id)!).filter(Boolean)
  const stopped = selectedPriced.filter((p) => p.after === null)
  const ok = selectedPriced.filter((p) => p.after !== null)
  const before = ok.reduce((a, p) => a + p.before, 0)
  const after = ok.reduce((a, p) => a + p.after!, 0)
  const credits = ok.filter((p) => p.newBalance! < 0)
  const creditTotal = credits.reduce((a, p) => a + -p.newBalance!, 0)
  const dunning = selectedPriced.filter((p) => IN_DUNNING.has(p.invoice.dunning_stage))
  const changes = rateChanges(selectedPriced.length ? selectedPriced : [...rows.values()])
  const unchanged = ok.length > 0 && ok.every((p) => p.after === p.before)
  const billCount = scope === 'all' ? runEligible : picked.length

  const approvers = access
    .holders('invoice.approve_correction')
    .flatMap((r) => access.members.filter((m) => m.roleId === r.id).map((m) => m.userId))
    .filter((id) => id !== access.user.id)
  const runNumber = nextCorrectionNumber(requests.map((r) => r.runNumber))

  const blocked = !eligibility.ok
    ? eligibility.reason
    : !access.can('invoice.void')
      ? 'Voiding bills needs the Void bills capability'
      : open.length
        ? openReason(open[0])
        : null

  function submit() {
    const e: typeof errors = {}
    if (!notes.trim()) e.notes = 'Say what went wrong — it is stored on every void'
    if (scope === 'selected' && picked.length === 0) e.picked = 'Tick at least one bill'
    setErrors(e)
    if (Object.keys(e).length || blocked) return
    requestBatchCorrection({
      runNumber,
      targetRunId: run.id,
      scope,
      invoiceIds: chosen,
      billCount,
      reasonCode: reason,
      notes: notes.trim(),
      mode,
      dueDate,
      holdDunning,
      notify,
      beforeCents: before,
      afterCents: after,
    })
    router.push(`/runs/${run.id}#corrections` as Route)
  }

  if (!eligibility.ok) {
    return (
      <div className="max-w-3xl mx-auto px-6 py-6 space-y-4">
        <StateBlock tone="info">
          <p className="text-data text-ink-primary">
            <strong className="font-semibold">{run.run_number} can’t be voided.</strong> {eligibility.reason}
          </p>
        </StateBlock>
        <Link href={`/runs/${run.id}` as Route} className="text-data text-accent-text hover:text-accent-text-hover underline">
          Back to the run
        </Link>
      </div>
    )
  }

  return (
    <div className="max-w-5xl mx-auto px-6 py-6 space-y-7">
      <StateBlock tone="warning">
        <p className="text-data text-ink-primary">
          No bill is edited. Each one is voided and stays on its account permanently, and a correction bill replaces it.
          Nothing is voided until someone else approves this; then the voids and the rebills post together, so no
          customer is left holding a voided bill without its replacement.
        </p>
      </StateBlock>

      {open.length ? (
        <StateBlock tone="pending">
          <p className="text-data text-ink-primary">
            <strong className="font-semibold">{openReason(open[0])}</strong>, requested by {open[0].requestedBy}{' '}
            {stamp(open[0].requestedAt)}. See it on{' '}
            <Link href={`/runs/${run.id}#corrections` as Route} className="text-accent-text hover:text-accent-text-hover underline">
              the run
            </Link>
            . Another batch can start once it posts or is withdrawn — two batches on the same bills would void them twice.
          </p>
        </StateBlock>
      ) : null}

      {/* Step 1 — which bills. */}
      <Step n={1} title="Which bills?">
        <div className="space-y-2">
          <Choice
            name="scope"
            checked={scope === 'all'}
            onChange={() => setScope('all')}
            title={`Every bill this run issued — ${count(runEligible)}`}
            detail={
              excludedCount
                ? `${count(run.total_invoices)} issued, less ${excludedCount} already voided`
                : `All ${count(run.total_invoices)} bills on ${run.run_number}`
            }
          />
          <Choice
            name="scope"
            checked={scope === 'selected'}
            onChange={() => setScope('selected')}
            title="Only the bills I pick"
            detail="For a mistake confined to some accounts — one rate schedule, one route, one meter size"
          />
        </div>

        <div className="mt-4 rounded-md border border-rule-hair bg-surface-raised shadow-panel overflow-clip">
          {scope === 'selected' ? (
            <div className="flex flex-wrap items-center gap-x-3 gap-y-1 border-b border-rule-hair bg-surface px-cell-x py-1.5 text-micro">
              <span className="field-label">Select</span>
              {[
                ['All', () => setPicked(eligible.map((t) => t.invoice.id))],
                ['R-1 only', () => setPicked(eligible.filter((t) => rows.get(t.invoice.id)?.schedule === 'R-1').map((t) => t.invoice.id))],
                ['G-1 only', () => setPicked(eligible.filter((t) => rows.get(t.invoice.id)?.schedule === 'G-1').map((t) => t.invoice.id))],
                ['None', () => setPicked([])],
              ].map(([label, fn]) => (
                <button key={label as string} type="button" onClick={fn as () => void} className="text-accent-text hover:text-accent-text-hover underline">
                  {label as string}
                </button>
              ))}
              {errors.picked ? <span className="text-exception-critical-text">{errors.picked}</span> : null}
            </div>
          ) : null}
          <Table caption="Bills on this run, as billed and as they would be rebilled">
            <thead>
              <HeadRow>
                <Th width="2rem">
                  <span className="sr-only">Include</span>
                </Th>
                <Th>Invoice</Th>
                <Th>Account</Th>
                <Th>Schedule</Th>
                <Th>Status</Th>
                <Th align="right">Billed</Th>
                <Th align="right">Rebill</Th>
                <Th align="right">Change</Th>
                <Th align="right">Paid</Th>
                <Th align="right">Leaves owing</Th>
              </HeadRow>
            </thead>
            <tbody>
              {targets.map(({ invoice, excluded }) => {
                const customer = customerById.get(invoice.customer_id)
                const p = rows.get(invoice.id)
                const included = !excluded && chosen.includes(invoice.id)
                return (
                  <Row key={invoice.id} selected={included && scope === 'selected'}>
                    <Td>
                      <input
                        type="checkbox"
                        aria-label={`Include ${invoice.invoice_number}`}
                        checked={included}
                        disabled={!!excluded || scope === 'all'}
                        onChange={() =>
                          setPicked((xs) => (xs.includes(invoice.id) ? xs.filter((x) => x !== invoice.id) : [...xs, invoice.id]))
                        }
                        className="h-4 w-4 accent-accent"
                      />
                    </Td>
                    <Td>
                      <Link
                        href={`/invoices/${invoice.id}` as Route}
                        className={`ident text-accent-text hover:text-accent-text-hover underline ${excluded ? 'line-through' : ''}`}
                      >
                        {invoice.invoice_number}
                      </Link>
                    </Td>
                    <Td>{customer ? customerName(customer) : '—'}</Td>
                    {excluded || !p ? (
                      <Td colSpan={7} className="text-micro text-ink-tertiary">
                        {excluded}
                      </Td>
                    ) : (
                      <>
                        <Td className="ident">{p.schedule}</Td>
                        <Td>
                          <span className="inline-flex flex-wrap items-center gap-1">
                            <StateFlag tone={invoiceTone(invoice.status)}>{humanize(invoice.status)}</StateFlag>
                            {IN_DUNNING.has(invoice.dunning_stage) ? (
                              <span className="text-micro text-exception-warning-text">{humanize(invoice.dunning_stage)}</span>
                            ) : null}
                          </span>
                        </Td>
                        <Td align="right">
                          <Money value={money(p.before)} />
                        </Td>
                        <Td align="right">
                          {p.after === null ? (
                            <span className="text-micro text-exception-critical-text">Stops — no PGA</span>
                          ) : (
                            <Money value={money(p.after)} />
                          )}
                        </Td>
                        <Td align="right">{p.after === null ? null : <Signed cents={p.after - p.before} />}</Td>
                        <Td align="right">
                          <Money value={money(p.paid)} />
                        </Td>
                        <Td align="right">{p.newBalance === null ? null : <Money value={money(p.newBalance)} />}</Td>
                      </>
                    )}
                  </Row>
                )
              })}
            </tbody>
          </Table>
          <p className="border-t border-rule-hair bg-surface-sunken px-cell-x py-2 text-micro text-ink-secondary">
            {targets.length} of {count(run.total_invoices)} bills shown, repriced to the cent. The correction run prices
            every bill it targets the same way before anything posts.
          </p>
        </div>
      </Step>

      {/* Step 2 — why. */}
      <Step n={2} title="Why are they being voided?">
        <fieldset>
          <legend className="sr-only">Void reason code</legend>
          <div className="grid grid-cols-2 sm:grid-cols-3 gap-x-6 gap-y-2">
            {VoidReasonCode.options.map((code) => (
              <label key={code} className="flex items-center gap-2 text-data text-ink-primary">
                <input
                  type="radio"
                  name="void_reason_code"
                  value={code}
                  checked={reason === code}
                  onChange={() => setReason(code)}
                  className="accent-accent"
                />
                {humanize(code)}
              </label>
            ))}
          </div>
        </fieldset>
        <label className="block mt-3">
          <span className="text-micro text-ink-secondary">
            Notes <span className="text-exception-critical-text">required</span>
          </span>
          <textarea
            rows={3}
            value={notes}
            aria-invalid={!!errors.notes}
            onChange={(e) => {
              setNotes(e.target.value)
              setErrors((x) => ({ ...x, notes: undefined }))
            }}
            placeholder="What went wrong, and how you found it. For example: January PGA billed at the December factor; the January filing was recorded after the run."
            className="mt-1 w-full rounded-sm border border-rule-solid bg-surface-raised px-2 py-1.5 text-data text-ink-primary placeholder:text-ink-muted aria-invalid:border-exception-critical-rail"
          />
        </label>
        {errors.notes ? <p className="text-micro text-exception-critical-text mt-1">{errors.notes}</p> : null}
        <p className="text-micro text-ink-tertiary mt-1">
          Stored on every void in the batch, with your name and the time the database stamps it.
        </p>
      </Step>

      {/* Step 3 — the election. */}
      <Step n={3} title="Which rates should the rebills use?">
        <p className="text-data text-ink-secondary mb-3">
          One election for the whole run. A specific date is only offered bill by bill, from the bill’s own Void and
          rebill.
        </p>
        <div className="space-y-2">
          <Choice
            name="rate_mode"
            checked={mode === 'historical'}
            onChange={() => setMode('historical')}
            title="Historical — the original period’s world"
            detail={`Each bill priced at its own period end (${date(run.valid_at)}), with everything recorded since`}
            explanation="Reproduces the bills as they should have been. The default, and what a PUC expects for a utility error."
          />
          <Choice
            name="rate_mode"
            checked={mode === 'current'}
            onChange={() => setMode('current')}
            title="Current — today’s rates"
            detail="Each bill priced at today’s tariff"
            explanation="Rarely correct for a utility error; used when an order directs it."
          />
        </div>

        <div className="mt-3 rounded-md border border-rule-hair bg-surface-raised shadow-panel overflow-clip">
          <Table caption="Rates the election changes">
            <thead>
              <HeadRow>
                <Th>Rate</Th>
                <Th align="right">As billed</Th>
                <Th align="right">Rebill</Th>
                <Th>Version</Th>
              </HeadRow>
            </thead>
            <tbody>
              {changes.map((c) => (
                <Row key={`${c.item}-${c.schedule}`}>
                  <Td>
                    {c.item}
                    {c.item === 'WNA' ? <span className="ident text-ink-tertiary"> · {c.schedule}</span> : null}
                  </Td>
                  <Td align="right" className="figures">
                    {fmtRate(String(c.from))}
                  </Td>
                  <Td align="right" className={`figures ${c.to !== null && c.to !== c.from ? 'font-medium text-ink-primary' : ''}`}>
                    {c.to === null ? <span className="text-exception-critical-text">None recorded</span> : fmtRate(String(c.to))}
                  </Td>
                  <Td className="text-micro text-ink-secondary">
                    {c.version ? (
                      <>
                        <span className="ident">{c.version.id}</span> · in effect {date(c.version.effective_from)} · recorded{' '}
                        {stamp(c.version.recorded_from)}
                        {c.version.recorded_from > run.recorded_at ? (
                          <span className="text-exception-warning-text"> — after this run</span>
                        ) : null}
                      </>
                    ) : c.item === 'WNA' ? (
                      'Out of season'
                    ) : (
                      'A lookup that finds nothing stops the bill; it never borrows a neighbouring month'
                    )}
                  </Td>
                </Row>
              ))}
            </tbody>
          </Table>
        </div>

        {unchanged ? (
          <StateBlock tone="info" className="mt-3">
            <p className="text-data text-ink-primary">
              <strong className="font-semibold">This election produces the same bills.</strong> A rebill can only price
              at what the rate history says. If a rate itself was wrong, record the corrected version in{' '}
              <Link href={'/rates' as Route} className="text-accent-text hover:text-accent-text-hover underline">
                Rates &amp; tariffs
              </Link>{' '}
              first, then come back. If a read or a meter factor was wrong, correct it in Read validation — the
              correction run picks up anything released since.
            </p>
          </StateBlock>
        ) : null}
        {stopped.length ? (
          <StateBlock tone="critical" className="mt-3">
            <p className="text-data text-ink-primary">
              {stopped.length} bill{stopped.length === 1 ? '' : 's'} would stop: no PGA version is recorded for the
              period. Record the factor in{' '}
              <Link href={'/rates/pga' as Route} className="text-accent-text hover:text-accent-text-hover underline">
                the PGA console
              </Link>{' '}
              before requesting this.
            </p>
          </StateBlock>
        ) : null}
      </Step>

      {/* Step 4 — what customers experience. */}
      <Step n={4} title="What happens to customers?">
        <div className="space-y-2">
          <Choice
            name="due_date"
            checked={dueDate === 'reset'}
            onChange={() => setDueDate('reset')}
            title="New due date — 20 days from the rebill"
            detail="Late fees already assessed on the voided bills are reversed"
          />
          <Choice
            name="due_date"
            checked={dueDate === 'original'}
            onChange={() => setDueDate('original')}
            title="Keep each bill’s original due date"
            detail="Only when the correction lands well before the bills fall due"
          />
        </div>
        <div className="mt-3 space-y-2">
          <Tick checked={holdDunning} onChange={setHoldDunning}>
            Hold dunning on these bills until the correction posts
            {dunning.length ? (
              <span className="text-ink-secondary">
                {' '}
                — {dunning.length} shown {dunning.length === 1 ? 'is' : 'are'} in dunning now (
                {dunning
                  .map((p) => `${customerName(customerById.get(p.invoice.customer_id)!)}, ${humanize(p.invoice.dunning_stage).toLowerCase()}`)
                  .join('; ')}
                )
              </span>
            ) : null}
          </Tick>
          <Tick checked={notify} onChange={setNotify}>
            Send the{' '}
            <Link href={'/communications/corrected-bill' as Route} className="text-accent-text hover:text-accent-text-hover underline">
              Corrected bill
            </Link>{' '}
            letter or email with each rebill
          </Tick>
        </div>
        <p className="text-micro text-ink-tertiary mt-2">
          Payments already made stay with the customer and move to the replacement bill. Where a replacement is smaller
          than what was paid, the difference becomes a credit on the account
          {credits.length ? (
            <>
              {' '}
              — <span className="figures">{credits.length}</span> shown, <Money value={money(creditTotal)} />
            </>
          ) : null}
          .
        </p>
      </Step>

      {/* Step 5 — the correction run and its approval. */}
      <Step n={5} title="Correction run">
        <div className="rounded-md border border-rule-hair bg-surface-raised px-4 py-3 shadow-panel">
          <FieldGrid cols={4}>
            <Field label="Run">
              <span className="ident">{runNumber}</span>
            </Field>
            <Field label="Corrects">
              <span className="ident">{run.run_number}</span>
            </Field>
            <Field label="Bills">{count(billCount)}</Field>
            <Field label="Rate mode">{humanize(mode)}</Field>
          </FieldGrid>
          <div className="mt-4 grid grid-cols-3 gap-px overflow-clip rounded-sm border border-rule-hair bg-rule-hair">
            <Figure label={`Billed · ${ok.length} shown`} value={<Money value={money(before)} />} />
            <Figure label="Rebilled" value={<Money value={money(after)} />} />
            <Figure label="Change" value={<Signed cents={after - before} />} />
          </div>
        </div>
        <p className="text-micro text-ink-tertiary mt-2">
          Requesting queues the correction run; nothing is voided yet. Posting needs a second person with{' '}
          <em>Approve corrections</em>
          {approvers.length ? <> — {approvers.map(nameOf).join(', ')}</> : null}. You
          can’t approve your own request.
        </p>
      </Step>

      <div className="flex items-center justify-between gap-4 border-t border-rule-heavy pt-4">
        <p className="text-micro text-ink-tertiary">
          {blocked ?? (
            <>
              Press <Key>⌘</Key>
              <Key>↵</Key> to request, or <Key>Esc</Key> to cancel.
            </>
          )}
        </p>
        <div className="flex items-center gap-2">
          <Link href={`/runs/${run.id}` as Route}>
            <Button variant="quiet">Cancel</Button>
          </Link>
          <Button variant="danger" disabled={!!blocked} title={blocked ?? undefined} onClick={submit}>
            Request void and rebill · {count(billCount)} bills
          </Button>
        </div>
      </div>
    </div>
  )
}

function Signed({ cents }: { cents: number }) {
  if (cents === 0) return <span className="figures text-money-zero">—</span>
  const v = (Math.abs(cents) / 100).toLocaleString('en-US', { style: 'currency', currency: 'USD' })
  return <span className="figures text-money">{cents < 0 ? `−${v}` : `+${v}`}</span>
}

function Figure({ label, value }: { label: string; value: ReactNode }) {
  return (
    <div className="bg-surface-raised px-3 py-2">
      <p className="field-label">{label}</p>
      <p className="text-figure mt-0.5">{value}</p>
    </div>
  )
}

function Step({ n, title, children }: { n: number; title: string; children: ReactNode }) {
  return (
    <section>
      <div className="flex items-baseline gap-2.5 mb-2.5">
        <span className="ident flex h-5 w-5 items-center justify-center rounded-sm bg-surface-ink text-ink-inverse">{n}</span>
        <h2 className="text-h3 text-ink-primary">{title}</h2>
      </div>
      <div className="pl-[1.9rem]">{children}</div>
    </section>
  )
}

function Choice({
  name,
  checked,
  onChange,
  title,
  detail,
  explanation,
}: {
  name: string
  checked: boolean
  onChange: () => void
  title: string
  detail: string
  explanation?: string
}) {
  return (
    <label
      className={`flex gap-3 rounded-sm border px-4 py-3 cursor-pointer transition-colors duration-fast ${
        checked ? 'border-accent bg-accent-wash' : 'border-rule-solid bg-surface-raised hover:bg-surface-sunken'
      }`}
    >
      <input type="radio" name={name} checked={checked} onChange={onChange} className="mt-0.5 accent-accent" />
      <div className="min-w-0">
        <p className="text-data text-ink-primary font-medium">{title}</p>
        <p className="text-data text-ink-secondary mt-0.5">{detail}</p>
        {explanation ? <p className="text-micro text-ink-tertiary mt-1 leading-relaxed">{explanation}</p> : null}
      </div>
    </label>
  )
}

function Tick({ checked, onChange, children }: { checked: boolean; onChange: (v: boolean) => void; children: ReactNode }) {
  return (
    <label className="flex cursor-pointer items-start gap-2.5 text-data text-ink-primary">
      <input type="checkbox" checked={checked} onChange={(e) => onChange(e.target.checked)} className="mt-0.5 h-4 w-4 shrink-0 accent-accent" />
      <span>{children}</span>
    </label>
  )
}
