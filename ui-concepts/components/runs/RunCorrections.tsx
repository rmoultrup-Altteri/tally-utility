'use client'

import { useState } from 'react'
import Link from 'next/link'
import type { Route } from 'next'
import { Button, Panel, PanelHeader } from '@/components/ui/Panel'
import { Dialog, FormField, fieldClass } from '@/components/ui/Dialog'
import { StateFlag, humanize, type Tone } from '@/components/ui/State'
import { Money } from '@/components/ui/Money'
import { useAccess } from '@/lib/access'
import { count, stamp } from '@/lib/format'
import {
  decideBatchCorrection,
  openFor,
  openReason,
  useBatchCorrections,
  type BatchCorrection,
} from '@/lib/run-corrections-store'

/**
 * The run page's two halves of void-and-rebill: the button that starts one,
 * and the record of every correction made against the run.
 *
 * The record is the audit: posted correction runs that replaced bills from
 * this run, then batch requests in the order they were made — awaiting
 * approval, approved or withdrawn, never removed.
 */

export function RebillRunButton({ runId, eligible, reason }: { runId: string; eligible: boolean; reason: string }) {
  const access = useAccess()
  const requests = useBatchCorrections()
  const open = openFor(requests, runId)
  const why = !eligible
    ? reason
    : !access.can('invoice.void')
      ? 'Voiding bills needs the Void bills capability'
      : open.length
        ? openReason(open[0])
        : reason
  if (!eligible || !access.can('invoice.void') || open.length) {
    return (
      <Button variant="danger" disabled title={why}>
        Void and rebill run
      </Button>
    )
  }
  return (
    <Link href={`/runs/${runId}/rebill` as Route} title={why}>
      <Button variant="danger">Void and rebill run</Button>
    </Link>
  )
}

export type PostedCorrection = {
  runId: string
  runNumber: string
  postedAt: string | null
  bills: { id: string; number: string; replaces: string; amount: string }[]
}

export const requestTone = (s: BatchCorrection['status']): Tone =>
  s === 'approved' ? 'approved' : s === 'withdrawn' ? 'void' : 'pending'

export function RunCorrections({ runId, posted }: { runId: string; posted: PostedCorrection[] }) {
  const access = useAccess()
  const requests = useBatchCorrections().filter((r) => r.targetRunId === runId)
  const [withdrawing, setWithdrawing] = useState<BatchCorrection | null>(null)

  if (!posted.length && !requests.length) return null

  return (
    <div id="corrections" className="scroll-mt-5">
      <Panel>
        <PanelHeader
          title="Corrections"
          meta={`${posted.length + requests.length} against this run · nothing is removed from this list`}
        />
        <ol className="divide-y divide-rule-hair">
          {posted.map((c) => (
            <li key={c.runId} className="flex flex-wrap items-start gap-x-4 gap-y-1 px-4 py-3">
              <div className="min-w-0 flex-1">
                <p className="text-data text-ink-primary">
                  <Link href={`/runs/${c.runId}` as Route} className="ident text-accent-text hover:text-accent-text-hover underline">
                    {c.runNumber}
                  </Link>{' '}
                  replaced {c.bills.length} bill{c.bills.length === 1 ? '' : 's'}
                  {c.postedAt ? <span className="text-ink-tertiary"> · posted {stamp(c.postedAt)}</span> : null}
                </p>
                <ul className="mt-1 space-y-0.5 text-micro text-ink-secondary">
                  {c.bills.map((b) => (
                    <li key={b.id}>
                      <span className="ident line-through">{b.replaces}</span> →{' '}
                      <Link href={`/invoices/${b.id}/diff` as Route} className="ident text-accent-text hover:text-accent-text-hover underline">
                        {b.number}
                      </Link>{' '}
                      <Money value={b.amount} />
                    </li>
                  ))}
                </ul>
              </div>
              <StateFlag tone="posted">Posted</StateFlag>
            </li>
          ))}
          {requests.map((r) => {
            const mine = r.requestedBy === access.user.name
            const canApprove = r.status === 'awaiting_approval' && access.can('invoice.approve_correction') && !mine
            const canWithdraw = r.status === 'awaiting_approval' && (mine || access.can('invoice.void'))
            const delta = r.afterCents - r.beforeCents
            return (
              <li key={r.id} className="flex flex-wrap items-start gap-x-4 gap-y-2 px-4 py-3">
                <div className="min-w-0 flex-1">
                  <p className="text-data text-ink-primary">
                    <span className={`ident ${r.status === 'withdrawn' ? 'line-through' : ''}`}>{r.runNumber}</span> — void
                    and rebill {r.scope === 'all' ? 'every bill' : 'selected bills'}, {count(r.billCount)} in all, at{' '}
                    {r.mode} rates
                  </p>
                  <p className="mt-0.5 text-micro text-ink-secondary">
                    {humanize(r.reasonCode)} · “{r.notes}”
                  </p>
                  <p className="mt-0.5 text-micro text-ink-tertiary">
                    Requested by {r.requestedBy} {stamp(r.requestedAt)} ·{' '}
                    {r.dueDate === 'reset' ? 'new due dates' : 'original due dates'} ·{' '}
                    {r.holdDunning ? 'dunning held' : 'dunning continues'} · {r.notify ? 'Corrected bill notice' : 'no notice'} ·
                    preview change{' '}
                    <span className="figures">
                      {delta === 0 ? 'none' : `${delta < 0 ? '−' : '+'}$${(Math.abs(delta) / 100).toFixed(2)}`}
                    </span>{' '}
                    on the bills shown
                  </p>
                  {r.decidedBy ? (
                    <p className="mt-0.5 text-micro text-ink-tertiary">
                      {r.status === 'approved' ? 'Approved' : 'Withdrawn'} by {r.decidedBy} {stamp(r.decidedAt)}
                      {r.decisionNote ? ` — “${r.decisionNote}”` : ''}
                    </p>
                  ) : null}
                </div>
                <div className="flex shrink-0 items-center gap-2">
                  <StateFlag tone={requestTone(r.status)}>{humanize(r.status)}</StateFlag>
                  {r.status === 'awaiting_approval' ? (
                    <>
                      <Button variant="quiet" disabled={!canWithdraw} onClick={() => setWithdrawing(r)}>
                        Withdraw
                      </Button>
                      <Button
                        variant="primary"
                        disabled={!canApprove}
                        title={
                          mine
                            ? 'A second person must approve — you requested this'
                            : !access.can('invoice.approve_correction')
                              ? 'Approving needs the Approve corrections capability'
                              : 'Approve: the voids and rebills post together'
                        }
                        onClick={() => decideBatchCorrection(r.id, 'approved', null)}
                      >
                        Approve
                      </Button>
                    </>
                  ) : null}
                </div>
              </li>
            )
          })}
        </ol>
      </Panel>
      <WithdrawDialog request={withdrawing} onClose={() => setWithdrawing(null)} />
    </div>
  )
}

function WithdrawDialog({ request, onClose }: { request: BatchCorrection | null; onClose: () => void }) {
  const [note, setNote] = useState('')
  const [error, setError] = useState<string | null>(null)
  const [last, setLast] = useState(request)
  if (request !== last) {
    setLast(request)
    setNote('')
    setError(null)
  }
  function save() {
    if (!note.trim()) return setError('Say why — it stays on the request')
    decideBatchCorrection(request!.id, 'withdrawn', note.trim())
    onClose()
  }
  return (
    <Dialog
      open={!!request}
      onClose={onClose}
      title="Withdraw this correction?"
      meta={request ? `${request.runNumber} · ${count(request.billCount)} bills` : undefined}
      footer={
        <>
          <Button variant="quiet" onClick={onClose}>
            Keep it
          </Button>
          <Button variant="danger" onClick={save}>
            Withdraw
          </Button>
        </>
      }
    >
      <form
        onSubmit={(e) => {
          e.preventDefault()
          save()
        }}
        className="space-y-3"
      >
        <p className="text-data text-ink-secondary">
          Nothing has been voided, so withdrawing changes no bill. The request stays in the run’s history, struck, with
          your reason.
        </p>
        <FormField label="Reason" htmlFor="withdraw-reason" error={error ?? undefined}>
          <input
            id="withdraw-reason"
            value={note}
            onChange={(e) => {
              setNote(e.target.value)
              setError(null)
            }}
            aria-invalid={!!error}
            className={fieldClass}
            autoFocus
          />
        </FormField>
      </form>
    </Dialog>
  )
}
