'use client'

import { useMemo, useState, type ReactNode } from 'react'
import Link from 'next/link'
import type { Route } from 'next'
import { Panel, PanelHeader } from '@/components/ui/Panel'
import { Chip } from '@/components/ui/Chip'
import { StateBlock } from '@/components/ui/State'
import {
  ALWAYS_CHECKED,
  ASSUMED_TRANSIT_DAYS,
  DEFAULT_DUNNING,
  DISCONNECT_MIN_LEAD,
  DISCONNECT_NEVER,
  NOTICE_MIN_DAYS,
  NOTICE_RULES,
  PRESETS,
  applyPreset,
  matchPreset,
  validateDunning,
  type DunningConfig,
  type DunningMode,
  type ReminderChannel,
} from '@/fixtures/dunning'
import { cycle } from '@/fixtures/tenant'
import { date, money } from '@/lib/format'
import { saveSettings, useSettings } from '@/lib/settings-store'
import { HOLIDAYS_2026, addWorkingDays, disconnectBlockedBecause, nextDisconnectDay, weekday } from '@/lib/working-days'
import { Switch, controlClass, type ChangeLine } from './fields'
import { SaveBar } from './SaveFlow'

const KEY = 'dunning'

/**
 * Setting up automatic dunning.
 *
 * Built to be done in a minute by someone who is not a collections expert:
 * choose how dunning runs, pick a schedule, adjust a step if needed, and the
 * right-hand column shows exactly what happens to a real bill — with dates,
 * counted in working days around the holiday calendar. The statutory floors
 * are enforced in the form, and everything the engine checks before any step
 * is listed beneath it, so the administrator can see what dunning will never
 * do as plainly as what it will.
 */
export function DunningSetup() {
  const store = useSettings()
  const inForce: DunningConfig = useMemo(
    () => ({ ...DEFAULT_DUNNING, ...((store.values[KEY] as Partial<DunningConfig> | undefined) ?? {}) }),
    [store.values],
  )
  const [draft, setDraft] = useState<DunningConfig | null>(null)
  const c = draft ?? inForce
  const set = (next: DunningConfig) => setDraft({ ...next, preset: matchPreset(next) })

  const errors = validateDunning(c)
  const lines = draft ? describeChanges(inForce, draft) : []

  return (
    <div className="space-y-5">
      <ModePanel mode={c.mode} saved={inForce.mode} onChange={(mode) => set({ ...c, mode })} />

      <Panel>
        <PanelHeader title="Start from a schedule" meta="Every step stays editable below" />
        <div className="grid grid-cols-1 gap-3 p-4 md:grid-cols-3">
          {PRESETS.map((p) => {
            const on = c.preset === p.key
            return (
              <button
                key={p.key}
                type="button"
                aria-pressed={on}
                onClick={() => set(applyPreset(c, p.key))}
                className={`rounded-md border p-3 text-left transition-colors duration-fast ${
                  on ? 'border-accent bg-accent-wash' : 'border-rule-solid bg-surface-raised hover:border-rule-heavy hover:bg-surface-sunken'
                }`}
              >
                <span className="flex items-center gap-2">
                  <span className="text-data font-semibold text-ink-primary">{p.title}</span>
                  {p.recommended ? (
                    <span className="rounded-full bg-state-approved-rail/15 px-1.5 text-label leading-4 text-state-approved-text">Recommended</span>
                  ) : null}
                </span>
                <span className="mt-1 block text-micro text-ink-secondary">{p.summary}</span>
                <span className="mt-2 block text-micro text-ink-tertiary figures">
                  Day {p.timing.reminder} · {p.timing.lateFee} · {p.timing.notice} · +{p.timing.lead}
                </span>
              </button>
            )
          })}
        </div>
        {c.preset === 'custom' ? (
          <p className="px-4 pb-3 -mt-1 text-micro text-ink-tertiary">Custom — you have adjusted the timing below.</p>
        ) : null}
      </Panel>

      <div className="grid grid-cols-1 gap-5 xl:grid-cols-[minmax(0,1fr)_300px]">
        <Steps c={c} set={set} errors={errors} />
        <Preview c={c} />
      </div>

      <Panel>
        <PanelHeader title="Small balances and partial payments" />
        <div className="divide-y divide-rule-hair">
          <Row label="Never dun a balance under" hint="Below this, nothing happens at all — no reminder, no fee, no notice.">
            <MoneyInput value={c.minBalance} invalid={Boolean(errors.minBalance)} onChange={(v) => set({ ...c, minBalance: v })} label="Minimum balance" />
            {errors.minBalance ? <Err>{errors.minBalance}</Err> : null}
          </Row>
          <Row
            label="When a customer pays part of the balance"
            hint="The domain expert has not ruled. Holding is the cautious choice until they do."
            badge={<span className="rounded-full border border-exception-warning-rail/50 bg-exception-warning-wash px-2 text-label leading-5 text-exception-warning-text">Open question</span>}
          >
            <select
              aria-label="Partial payment"
              className={`${controlClass} w-full max-w-sm`}
              value={c.partialPayment}
              onChange={(e) => set({ ...c, partialPayment: e.target.value as DunningConfig['partialPayment'] })}
            >
              <option value="hold">Hold at the current step for one cycle</option>
              <option value="continue">Continue on the remaining balance</option>
              <option value="reset">Start over from the reminder</option>
            </select>
          </Row>
          <Row label="Run every morning at" hint="After the protection check, which always runs first.">
            <input
              type="time"
              aria-label="Run time"
              className={`${controlClass} w-32`}
              value={c.runTime}
              onChange={(e) => set({ ...c, runTime: e.target.value })}
            />
          </Row>
        </div>
      </Panel>

      <Guardrails />

      <Panel>
        <PanelHeader
          title="Working-day calendar"
          meta="Every dunning clock counts these out"
          actions={
            <span className="rounded-full border border-exception-warning-rail/50 bg-exception-warning-wash px-2 text-label leading-5 text-exception-warning-text">
              Open question
            </span>
          }
        />
        <p className="px-4 pt-3 text-micro text-ink-secondary">
          Weekends and Texas state and national holidays. Whether the partial-staffing state holidays count, and whether you may add your own
          closures, is still with the domain expert.
        </p>
        <ul className="grid grid-cols-1 gap-x-6 px-4 py-3 sm:grid-cols-2">
          {HOLIDAYS_2026.map((h) => (
            <li key={h.date} className="flex items-baseline justify-between gap-3 border-b border-rule-hair py-1 text-micro last:border-0">
              <span className="text-ink-primary">{h.name}</span>
              <span className="whitespace-nowrap text-ink-tertiary figures">
                {weekday(h.date)} {date(h.date)}
                {h.kind === 'state' ? ' · state' : ''}
              </span>
            </li>
          ))}
        </ul>
      </Panel>

      <SaveBar
        lines={lines}
        blocked={Object.keys(errors).length ? 'Fix the highlighted steps first.' : null}
        onDiscard={() => setDraft(null)}
        onSave={(r) => {
          if (!draft) return
          saveSettings({ [KEY]: inForce }, { [KEY]: draft }, r.effectiveFrom, r.reason)
          setDraft(null)
        }}
      />
    </div>
  )
}

/* ---- Mode ------------------------------------------------------------- */

const MODES: { value: DunningMode; title: string; body: string }[] = [
  { value: 'off', title: 'Off', body: 'Nothing moves on its own. Collections works the worklist by hand.' },
  {
    value: 'preview',
    title: 'Preview',
    body: 'Runs every morning and shows on the Collections worklist what it would have done. Sends nothing, charges nothing.',
  },
  { value: 'on', title: 'On', body: 'Runs every morning and takes each past-due bill at most one step per day.' },
]

function ModePanel({ mode, saved, onChange }: { mode: DunningMode; saved: DunningMode; onChange: (m: DunningMode) => void }) {
  return (
    <Panel>
      <PanelHeader
        title="Automatic dunning"
        meta={saved === 'on' ? 'Running' : saved === 'preview' ? 'In preview' : 'Off'}
      />
      <div role="radiogroup" aria-label="Automatic dunning" className="grid grid-cols-1 gap-3 p-4 md:grid-cols-3">
        {MODES.map((m) => {
          const on = mode === m.value
          return (
            <button
              key={m.value}
              type="button"
              role="radio"
              aria-checked={on}
              onClick={() => onChange(m.value)}
              className={`flex items-start gap-2.5 rounded-md border p-3 text-left transition-colors duration-fast ${
                on ? 'border-accent bg-accent-wash' : 'border-rule-solid bg-surface-raised hover:border-rule-heavy hover:bg-surface-sunken'
              }`}
            >
              <span
                aria-hidden
                className={`mt-0.5 flex h-3.5 w-3.5 shrink-0 items-center justify-center rounded-full border ${on ? 'border-accent' : 'border-rule-heavy'}`}
              >
                {on ? <span className="h-1.5 w-1.5 rounded-full bg-accent" /> : null}
              </span>
              <span>
                <span className="block text-data font-semibold text-ink-primary">{m.title}</span>
                <span className="mt-0.5 block text-micro text-ink-secondary">{m.body}</span>
              </span>
            </button>
          )
        })}
      </div>
      {saved === 'off' && mode !== 'on' ? (
        <p className="px-4 pb-3 -mt-1 text-micro text-ink-tertiary">
          New to this? Run it in Preview for one cycle and check the worklist before switching it on.
        </p>
      ) : null}
      {saved !== 'on' && mode === 'on' ? (
        <StateBlock tone="warning" className="mx-4 mb-4 !py-2.5">
          <p className="text-micro text-exception-warning-text">
            {saved === 'off'
              ? 'Going straight to On skips the preview. Reminders, late fees and termination notices will start going out on the next run.'
              : 'From the next run, reminders, late fees and termination notices go out for real.'}
          </p>
        </StateBlock>
      ) : null}
    </Panel>
  )
}

/* ---- Steps ------------------------------------------------------------ */

function Steps({ c, set, errors }: { c: DunningConfig; set: (c: DunningConfig) => void; errors: Record<string, string> }) {
  const channels: { value: ReminderChannel; label: string }[] = [
    { value: 'email', label: 'Email' },
    { value: 'mail', label: 'Mail' },
    { value: 'sms', label: 'Text message' },
  ]
  return (
    <Panel>
      <PanelHeader title="Steps" meta="Working days after the due date" />
      <ol className="relative">
        <Step
          n={1}
          title="Reminder"
          toggle={<Switch on={c.reminder.enabled} label="Send a reminder" onChange={(v) => set({ ...c, reminder: { ...c.reminder, enabled: v } })} />}
          off={!c.reminder.enabled}
          error={errors.reminder}
        >
          <When value={c.reminder.days} onChange={(v) => set({ ...c, reminder: { ...c.reminder, days: v } })} label="Reminder" />
          <div className="mt-2 flex flex-wrap items-center gap-1.5">
            <span className="field-label mr-1">Send by</span>
            {channels.map((ch) => {
              const on = c.reminder.channels.includes(ch.value)
              return (
                <Chip
                  key={ch.value}
                  on={on}
                  onClick={() =>
                    set({
                      ...c,
                      reminder: {
                        ...c.reminder,
                        channels: on ? c.reminder.channels.filter((x) => x !== ch.value) : [...c.reminder.channels, ch.value],
                      },
                    })
                  }
                >
                  {ch.label}
                </Chip>
              )
            })}
          </div>
          <p className="mt-1 text-micro text-ink-tertiary">Email and text go only to customers who consented to them; everyone else gets mail.</p>
        </Step>

        <Step
          n={2}
          title="Late fee"
          badge="Tariff-bound"
          toggle={<Switch on={c.lateFee.enabled} label="Charge a late fee" onChange={(v) => set({ ...c, lateFee: { ...c.lateFee, enabled: v } })} />}
          off={!c.lateFee.enabled}
          error={errors.lateFee}
        >
          <When value={c.lateFee.days} onChange={(v) => set({ ...c, lateFee: { ...c.lateFee, days: v } })} label="Late fee" />
          <div className="mt-2 flex flex-wrap items-center gap-2">
            <select
              aria-label="Fee basis"
              className={`${controlClass} w-auto`}
              value={c.lateFee.basis}
              onChange={(e) => set({ ...c, lateFee: { ...c.lateFee, basis: e.target.value as 'percent' | 'flat' } })}
            >
              <option value="percent">Percent of the past-due gas charges</option>
              <option value="flat">Flat amount</option>
            </select>
            {c.lateFee.basis === 'percent' ? (
              <span className="flex items-center gap-1.5">
                <input
                  aria-label="Late fee percent"
                  inputMode="decimal"
                  className={`${controlClass} w-20 text-right figures`}
                  value={c.lateFee.amount}
                  onChange={(e) => set({ ...c, lateFee: { ...c.lateFee, amount: e.target.value } })}
                />
                <span className="text-micro text-ink-tertiary">%</span>
              </span>
            ) : (
              <MoneyInput value={c.lateFee.amount} label="Late fee amount" onChange={(v) => set({ ...c, lateFee: { ...c.lateFee, amount: v } })} />
            )}
            <select
              aria-label="How often"
              className={`${controlClass} w-auto`}
              value={c.lateFee.recurring ? 'monthly' : 'once'}
              onChange={(e) => set({ ...c, lateFee: { ...c.lateFee, recurring: e.target.value === 'monthly' } })}
            >
              <option value="once">Once per bill</option>
              <option value="monthly">Each month it stays unpaid</option>
            </select>
          </div>
          <label className="mt-2 flex items-center gap-2 text-micro text-ink-secondary">
            <Switch
              on={c.lateFee.exemptPrograms}
              label="Exempt customers in assistance programs"
              onChange={(v) => set({ ...c, lateFee: { ...c.lateFee, exemptPrograms: v } })}
            />
            Exempt customers enrolled in an assistance program
          </label>
          <p className="mt-1 text-micro text-ink-tertiary">
            Never charged on a disputed amount or inside a payment agreement’s grace. Figured on each service’s own subtotal, never the bill total.
          </p>
        </Step>

        <Step n={3} title="Termination notice" required error={errors.notice}>
          <When value={c.notice.days} min={NOTICE_MIN_DAYS} onChange={(v) => set({ ...c, notice: { ...c.notice, days: v } })} label="Termination notice" />
          <p className="mt-1 text-micro text-ink-tertiary">
            No sooner than {NOTICE_MIN_DAYS} working days past due, with no payment agreement in place.
          </p>
          <div className="mt-2 space-y-1.5">
            <label className="flex items-center gap-2 text-micro text-ink-secondary">
              <Switch on label="Send by U.S. mail" disabled onChange={() => {}} />
              By U.S. mail — always
            </label>
            <label className="flex items-center gap-2 text-micro text-ink-secondary">
              <Switch on={c.notice.handDelivery} label="Also hand-deliver" onChange={(v) => set({ ...c, notice: { ...c.notice, handDelivery: v } })} />
              Also hand-deliver at the premise
            </label>
            <label className="flex items-center gap-2 text-micro text-ink-secondary">
              <Switch on={c.notice.emailCopy} label="Email a courtesy copy" onChange={(v) => set({ ...c, notice: { ...c.notice, emailCopy: v } })} />
              Email a courtesy copy to paperless customers
            </label>
          </div>
        </Step>

        <Step n={4} title="Disconnect" required error={errors.disconnect} last>
          <div className="flex flex-wrap items-center gap-2">
            <span className="text-data text-ink-secondary">Earliest</span>
            <input
              type="number"
              aria-label="Disconnect lead days"
              min={DISCONNECT_MIN_LEAD}
              className={`${controlClass} w-20 text-right figures`}
              value={c.disconnect.leadDays}
              aria-invalid={Boolean(errors.disconnect) || undefined}
              onChange={(e) => set({ ...c, disconnect: { ...c.disconnect, leadDays: Math.trunc(Number(e.target.value)) } })}
            />
            <span className="text-data text-ink-secondary">working days after the notice is delivered</span>
          </div>
          <div className="mt-2 flex flex-wrap items-center gap-2">
            <span className="field-label">Then</span>
            <select
              aria-label="Scheduling"
              className={`${controlClass} w-auto`}
              value={c.disconnect.scheduling}
              onChange={(e) => set({ ...c, disconnect: { ...c.disconnect, scheduling: e.target.value as 'worklist' | 'automatic' } })}
            >
              <option value="worklist">Put it on the Collections worklist for a person to schedule</option>
              <option value="automatic">Create the field order automatically</option>
            </select>
          </div>
          {c.disconnect.scheduling === 'automatic' ? (
            <p className="mt-1 text-micro text-exception-warning-text">
              Eligibility is checked again on the day of the order either way, and a site without a meter photo still needs a supervisor.
            </p>
          ) : null}
        </Step>
      </ol>
      <div className="border-t border-rule-hair bg-surface px-4 py-2.5 text-micro text-ink-secondary">
        At any step: a payment that clears the balance ends dunning, and entering a payment agreement moves the bill to the plan.
      </div>
    </Panel>
  )
}

function Step({
  n,
  title,
  toggle,
  off = false,
  required = false,
  badge,
  error,
  last = false,
  children,
}: {
  n: number
  title: string
  toggle?: ReactNode
  off?: boolean
  required?: boolean
  badge?: string
  error?: string
  last?: boolean
  children: ReactNode
}) {
  return (
    <li className="relative flex gap-3 px-4 py-3.5">
      {last ? null : <span aria-hidden className="absolute left-[29px] top-10 bottom-0 w-px bg-rule-solid" />}
      <span
        aria-hidden
        className={`relative z-[1] flex h-6 w-6 shrink-0 items-center justify-center rounded-full text-micro font-semibold ${
          off ? 'border border-rule-solid bg-surface-sunken text-ink-tertiary' : 'bg-accent text-ink-inverse'
        }`}
      >
        {n}
      </span>
      <div className="min-w-0 flex-1">
        <div className="flex flex-wrap items-center gap-2">
          <h3 className={`text-h3 ${off ? 'text-ink-tertiary' : 'text-ink-primary'}`}>{title}</h3>
          {required ? <span className="rounded-full bg-surface-sunken px-2 text-label leading-5 text-ink-secondary">Required by rule</span> : null}
          {badge ? (
            <span className="rounded-full border border-exception-info-rail/40 bg-exception-info-wash px-2 text-label leading-5 text-exception-info-text">{badge}</span>
          ) : null}
          {toggle ? <span className="ml-auto">{toggle}</span> : null}
        </div>
        {off ? <p className="mt-1 text-micro text-ink-tertiary">Skipped.</p> : <div className="mt-2">{children}</div>}
        {!off && error ? <Err>{error}</Err> : null}
      </div>
    </li>
  )
}

function When({ value, onChange, label, min = 1 }: { value: number; onChange: (v: number) => void; label: string; min?: number }) {
  return (
    <div className="flex flex-wrap items-center gap-2">
      <span className="text-data text-ink-secondary">Day</span>
      <input
        type="number"
        aria-label={`${label}, working days after the due date`}
        min={min}
        max={60}
        className={`${controlClass} w-20 text-right figures`}
        value={Number.isFinite(value) ? value : ''}
        onChange={(e) => onChange(Math.trunc(Number(e.target.value)))}
      />
      <span className="text-data text-ink-secondary">working days after the due date</span>
    </div>
  )
}

/* ---- Preview ---------------------------------------------------------- */

function Preview({ c }: { c: DunningConfig }) {
  const due = cycle.dueDate
  const rows: { label: string; on: string; note?: string; muted?: boolean }[] = [{ label: 'Due', on: due }]
  if (c.reminder.enabled && c.reminder.days > 0) rows.push({ label: 'Reminder', on: addWorkingDays(due, c.reminder.days) })
  if (c.lateFee.enabled && c.lateFee.days > 0) {
    const fee = c.lateFee.basis === 'percent' ? `${c.lateFee.amount}% of past-due gas` : money(c.lateFee.amount || '0')
    rows.push({ label: 'Late fee', on: addWorkingDays(due, c.lateFee.days), note: fee })
  }
  const noticeDays = Math.max(c.notice.days || 0, NOTICE_MIN_DAYS)
  const sent = addWorkingDays(due, noticeDays)
  const delivered = addWorkingDays(sent, ASSUMED_TRANSIT_DAYS)
  rows.push({ label: 'Termination notice mailed', on: sent })
  rows.push({ label: 'Delivered (assumed)', on: delivered, muted: true })
  const earliest = addWorkingDays(delivered, Math.max(c.disconnect.leadDays || 0, DISCONNECT_MIN_LEAD))
  const disconnect = nextDisconnectDay(earliest)
  const pushed = disconnect !== earliest ? disconnectBlockedBecause(earliest) : null
  rows.push({
    label: 'Earliest disconnect',
    on: disconnect,
    note: pushed ? `${weekday(earliest)} ${date(earliest)} is not allowed — ${pushed.toLowerCase()}` : undefined,
  })

  const span = Math.round((Date.parse(disconnect) - Date.parse(due)) / 86_400_000)

  return (
    <Panel className="self-start xl:sticky xl:top-4">
      <PanelHeader title="On a real bill" meta={`${cycle.label}, due ${date(due)}`} />
      <ol className="px-4 py-3">
        {rows.map((r, i) => (
          <li key={r.label} className="relative flex gap-3 pb-3 last:pb-0">
            {i < rows.length - 1 ? <span aria-hidden className="absolute left-[4px] top-3 bottom-0 w-px bg-rule-solid" /> : null}
            <span aria-hidden className={`relative mt-1.5 h-2.5 w-2.5 shrink-0 rounded-full ${r.muted ? 'border border-rule-heavy bg-surface-raised' : 'bg-accent'}`} />
            <div className="min-w-0">
              <p className={`text-data ${r.muted ? 'text-ink-tertiary' : 'text-ink-primary'}`}>{r.label}</p>
              <p className="text-micro text-ink-secondary figures">
                {weekday(r.on)} {date(r.on)}
              </p>
              {r.note ? <p className="text-micro text-ink-tertiary">{r.note}</p> : null}
            </div>
          </li>
        ))}
      </ol>
      <div className="border-t border-rule-hair bg-surface px-4 py-2.5 text-micro text-ink-secondary">
        <p>
          <span className="font-medium text-ink-primary">{span} calendar days</span> from due date to the earliest disconnect, if nothing
          protects the account and nobody pays.
        </p>
        <p className="mt-1 text-ink-tertiary">
          Assumes the notice is confirmed delivered {ASSUMED_TRANSIT_DAYS} working days after mailing. The real step waits for confirmation.
        </p>
      </div>
    </Panel>
  )
}

/* ---- Guardrails ------------------------------------------------------- */

function Guardrails() {
  return (
    <Panel>
      <PanelHeader title="What dunning will never do" meta="Rules, not settings — checked before every step" />
      <div className="grid grid-cols-1 gap-x-8 gap-y-4 px-4 py-4 lg:grid-cols-2">
        <div>
          <p className="field-label mb-1.5">Checked every morning, before any step</p>
          <ol className="space-y-1.5">
            {ALWAYS_CHECKED.map((b, i) => (
              <li key={b.title} className="flex gap-2 text-micro">
                <span className="w-4 shrink-0 text-right text-ink-tertiary figures">{i + 1}.</span>
                <span>
                  <span className="font-medium text-ink-primary">{b.title}.</span> <span className="text-ink-secondary">{b.detail}</span>
                  {b.citation ? <span className="ident ml-1 text-ink-tertiary">{b.citation}</span> : null}
                </span>
              </li>
            ))}
          </ol>
          <p className="mt-2 text-micro text-ink-tertiary">
            A bill held by any of these stays where it is, and the hold is recorded.{' '}
            <Link href={'/settings/disconnect' as Route} className="text-accent-text hover:text-accent-text-hover">
              Protection settings →
            </Link>
          </p>
        </div>
        <div className="space-y-4">
          <div>
            <p className="field-label mb-1.5">The termination notice is always</p>
            <ul className="list-disc space-y-0.5 pl-4 text-micro text-ink-secondary">
              {NOTICE_RULES.map((r) => (
                <li key={r}>{r}</li>
              ))}
            </ul>
          </div>
          <div>
            <p className="field-label mb-1.5">A disconnect never happens</p>
            <ul className="list-disc space-y-0.5 pl-4 text-micro text-ink-secondary">
              {DISCONNECT_NEVER.map((r) => (
                <li key={r}>{r}</li>
              ))}
            </ul>
          </div>
        </div>
      </div>
    </Panel>
  )
}

/* ---- Bits ------------------------------------------------------------- */

function Row({ label, hint, badge, children }: { label: string; hint?: string; badge?: ReactNode; children: ReactNode }) {
  return (
    <div className="px-4 py-3 sm:grid sm:grid-cols-[minmax(0,1fr)_minmax(0,1.1fr)] sm:gap-6">
      <div>
        <div className="flex flex-wrap items-center gap-1.5">
          <p className="text-data font-medium text-ink-primary">{label}</p>
          {badge}
        </div>
        {hint ? <p className="mt-0.5 text-micro text-ink-tertiary">{hint}</p> : null}
      </div>
      <div className="mt-2 sm:mt-0">{children}</div>
    </div>
  )
}

function MoneyInput({ value, onChange, label, invalid = false }: { value: string; onChange: (v: string) => void; label: string; invalid?: boolean }) {
  return (
    <div className="relative w-32">
      <span aria-hidden className="pointer-events-none absolute left-2.5 top-1/2 -translate-y-1/2 text-data text-ink-tertiary">$</span>
      <input
        aria-label={label}
        inputMode="decimal"
        className={`${controlClass} pl-5 text-right figures`}
        aria-invalid={invalid || undefined}
        value={value}
        onChange={(e) => onChange(e.target.value)}
      />
    </div>
  )
}

function Err({ children }: { children: ReactNode }) {
  return <p className="mt-1.5 text-micro text-exception-critical-text">{children}</p>
}

/* ---- Change lines ----------------------------------------------------- */

const MODE_LABEL: Record<DunningMode, string> = { off: 'Off', preview: 'Preview', on: 'On' }

function describeChanges(a: DunningConfig, b: DunningConfig): ChangeLine[] {
  const out: ChangeLine[] = []
  const add = (label: string, from: string, to: string, tariff = false) => {
    if (from !== to) out.push({ key: KEY, label: `Dunning · ${label}`, from, to, tariff })
  }
  const step = (enabled: boolean, days: number) => (enabled ? `Day ${days}` : 'Skipped')
  const fee = (c: DunningConfig) =>
    !c.lateFee.enabled
      ? 'None'
      : `${c.lateFee.basis === 'percent' ? `${c.lateFee.amount}%` : money(c.lateFee.amount || '0')}, ${c.lateFee.recurring ? 'monthly' : 'once'}${c.lateFee.exemptPrograms ? ', programs exempt' : ''}`
  add('Automatic dunning', MODE_LABEL[a.mode], MODE_LABEL[b.mode])
  add('Reminder', step(a.reminder.enabled, a.reminder.days), step(b.reminder.enabled, b.reminder.days))
  add('Reminder sent by', a.reminder.channels.join(', ') || 'none', b.reminder.channels.join(', ') || 'none')
  add('Late fee timing', step(a.lateFee.enabled, a.lateFee.days), step(b.lateFee.enabled, b.lateFee.days))
  add('Late fee', fee(a), fee(b), true)
  add('Termination notice', `Day ${a.notice.days}`, `Day ${b.notice.days}`)
  add('Hand delivery', a.notice.handDelivery ? 'Yes' : 'No', b.notice.handDelivery ? 'Yes' : 'No')
  add('Courtesy email of notice', a.notice.emailCopy ? 'Yes' : 'No', b.notice.emailCopy ? 'Yes' : 'No')
  add('Disconnect lead', `${a.disconnect.leadDays} working days`, `${b.disconnect.leadDays} working days`)
  add('Disconnect scheduling', a.disconnect.scheduling === 'worklist' ? 'Worklist' : 'Automatic', b.disconnect.scheduling === 'worklist' ? 'Worklist' : 'Automatic')
  add('Minimum balance', money(a.minBalance || '0'), money(b.minBalance || '0'))
  add('Partial payment', a.partialPayment, b.partialPayment)
  add('Run time', a.runTime, b.runTime)
  return out
}
