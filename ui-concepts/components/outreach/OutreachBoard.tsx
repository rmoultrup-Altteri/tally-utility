'use client'

import { useEffect, useMemo, useState, type ReactNode } from 'react'
import Link from 'next/link'
import type { Route } from 'next'
import {
  OUTREACH_POLICY,
  candidates,
  excluded,
  outreachSummary,
  type Candidate,
  type Plan,
} from '@/fixtures/outreach'
import { templateById, type Channel } from '@/fixtures/templates'
import { tenant } from '@/fixtures/tenant'
import { REASON, REASON_SHORT, type Verdict } from '@/lib/bill-explain'
import { contextFor } from '@/lib/templates'
import { useTemplate } from '@/lib/templates-store'
import { latestBy, logOutreach, useOutreachLog, type OutreachAction } from '@/lib/outreach-store'
import { useAccess } from '@/lib/access'
import { activeUserName } from '@/lib/session'
import { MessagePreview } from '@/components/communications/MessagePreview'
import { Waterfall } from '@/components/charts/Waterfall'
import { Panel, PanelHeader, Button } from '@/components/ui/Panel'
import { Rail, StateBlock, StateFlag, type Tone } from '@/components/ui/State'
import { Chip, Group } from '@/components/ui/Chip'
import { AccountNumber } from '@/components/ui/RecordLink'
import { Table, HeadRow, Th, Row, Td, RailCell } from '@/components/table/Table'
import { date, money, percent, stamp } from '@/lib/format'

/**
 * The outreach board.
 *
 * Laid out like the exception queue it grows out of — the list ranked by how
 * much the bill moved, the selected customer beside it — because the person
 * working it is the same analyst, in the same hour before the run posts.
 *
 * Sending is the only write, and it is gated twice: the role must hold Send
 * outreach, and a text goes only to a number with consent on file. Calls are
 * never automated; they land on a CSR's list with the talking points.
 */

const PLAN_LABEL: Record<Plan, string> = {
  text_email: 'Text and email',
  email: 'Email',
  text: 'Text',
  call: 'Call',
  bill_message: 'On the bill',
}

type Filter = 'all' | 'unsent' | 'usage' | 'calls' | 'spanish'

const verdictOf = (c: Candidate): Verdict => {
  const d = c.drivers
  const ranked: [Verdict, number][] = [
    ['weather', d.weather],
    ['usage', d.usage],
    ['gas_cost', d.gasCost],
    ['rates', d.other],
  ]
  ranked.sort((a, b) => b[1] - a[1])
  return ranked[0][0]
}

const dollars = (c: number) => money(c / 100)

const INTRO_KEY = 'tu-outreach-intro'

/*
 * Decided once per page load and remembered here, so an effect that runs
 * twice (React's development double-mount) cannot mark the visit seen before
 * the intro has been shown.
 */
let firstVisitThisLoad: boolean | null = null
function firstVisit(): boolean {
  if (firstVisitThisLoad !== null) return firstVisitThisLoad
  try {
    firstVisitThisLoad = window.localStorage.getItem(INTRO_KEY) !== 'seen'
    window.localStorage.setItem(INTRO_KEY, 'seen')
  } catch {
    firstVisitThisLoad = false
  }
  return firstVisitThisLoad
}

function Summary({ n, label, warn = false }: { n: number; label: string; warn?: boolean }) {
  return (
    <span className="text-micro text-ink-secondary">
      <span className={`figures font-medium ${warn && n > 0 ? 'text-exception-warning-text' : 'text-ink-primary'}`}>{n}</span> {label}
    </span>
  )
}

/** A detail-pane section that shows its gist until opened. */
function Fold({ title, gist, open = false, children }: { title: string; gist: ReactNode; open?: boolean; children: ReactNode }) {
  return (
    <details open={open} className="group border-b border-rule-hair">
      <summary className="flex cursor-pointer list-none items-baseline gap-2 px-4 py-2.5 hover:bg-surface-sunken [&::-webkit-details-marker]:hidden">
        <span aria-hidden className="inline-block w-2.5 text-[9px] text-ink-tertiary transition-transform duration-fast group-open:rotate-90">
          ▸
        </span>
        <span className="field-label shrink-0">{title}</span>
        <span className="min-w-0 truncate text-micro text-ink-secondary">{gist}</span>
      </summary>
      <div className="px-4 pb-4 pt-1">{children}</div>
    </details>
  )
}

export function OutreachBoard({ initialId }: { initialId?: string }) {
  const log = useOutreachLog()
  const latest = useMemo(() => latestBy(log), [log])
  const { can } = useAccess()
  const mayContact = can('outreach.send')
  const [filter, setFilter] = useState<Filter>('all')
  const [selectedId, setSelectedId] = useState(
    initialId && candidates.some((c) => c.id === initialId) ? initialId : candidates[0]?.id,
  )
  const [checked, setChecked] = useState<Set<string>>(new Set())
  /*
   * The banner and five tiles teach the board on a first visit. After that
   * they are a line: the analyst knows the rules, and the list is the work.
   * Null until mounted, so a returning visitor never sees the full block flash.
   */
  const [intro, setIntroState] = useState<boolean | null>(null)
  useEffect(() => {
    setIntroState(firstVisit())
    /* Leaving the board ends the first visit; the deferral lets a development double-mount see it first. */
    return () => {
      setTimeout(() => (firstVisitThisLoad = false), 0)
    }
  }, [])
  const setIntro = (v: boolean) => setIntroState(v)

  const rows = candidates.filter((c) => {
    switch (filter) {
      case 'unsent':
        return !latest.has(c.id)
      case 'usage':
        return c.usageFlag
      case 'calls':
        return c.plan === 'call'
      case 'spanish':
        return c.lang === 'es'
      default:
        return true
    }
  })
  const selected = candidates.find((c) => c.id === selectedId) ?? rows[0]

  const ready = candidates.filter((c) => !latest.has(c.id) && ['text_email', 'email', 'text'].includes(c.plan))
  const sentCount = candidates.filter((c) => latest.has(c.id)).length

  function send(list: Candidate[]) {
    if (!mayContact) return
    logOutreach(
      list.map((c) => ({
        candidateId: c.id,
        kind: c.plan === 'bill_message' ? 'bill_message' : outreachSummary.sendsNow ? 'sent' : 'scheduled',
        channels:
          c.plan === 'text_email' ? ['text', 'email'] : c.plan === 'email' ? ['email'] : c.plan === 'text' ? ['text'] : ['bill'],
        note: null,
        by: activeUserName(),
      })),
    )
    setChecked(new Set())
  }

  const toggle = (id: string) =>
    setChecked((s) => {
      const n = new Set(s)
      if (n.has(id)) n.delete(id)
      else n.add(id)
      return n
    })
  const checkedRows = candidates.filter((c) => checked.has(c.id) && !latest.has(c.id) && c.plan !== 'call')

  return (
    <>
      {intro ? (
        <div className="px-5 py-4 border-b border-rule-solid bg-surface space-y-3">
          <StateBlock tone="info">
            <p className="text-data text-ink-primary">
              <strong className="font-semibold">
                {outreachSummary.overThreshold} draft bills rose {OUTREACH_POLICY.swingPct}% and{' '}
                {dollars(OUTREACH_POLICY.minIncreaseCents)} or more over the {OUTREACH_POLICY.basisLabel}.
              </strong>{' '}
              Tell them before the bills are dated {date(OUTREACH_POLICY.sendBefore)}, with the reason in one line. A heads-up is a
              courtesy: it is not a notice under 16 TAC §7.460 and does not start dunning. Texts go only to customers who opted in,
              between {OUTREACH_POLICY.quietStart} a.m. and {OUTREACH_POLICY.quietEnd - 12} p.m.
            </p>
          </StateBlock>
          <div className="grid grid-cols-2 lg:grid-cols-5 gap-px overflow-clip rounded-md bg-rule-hair border border-rule-hair shadow-panel">
            <Stat label="To contact" sub={`${excluded.length} more over the line, deliberately not`}>
              {outreachSummary.toContact}
            </Stat>
            <Stat label="Mostly weather" sub="Colder than last February explains most of it">
              {outreachSummary.mostlyWeather}
            </Stat>
            <Stat label="Usage beyond the weather" sub="Offer a free safety check">
              {outreachSummary.usageBeyondWeather}
            </Stat>
            <Stat label="In Spanish" sub="Sent from the Spanish template">
              {outreachSummary.spanish}
            </Stat>
            <Stat label="Contacted" sub={sentCount ? 'From this board, in this browser' : 'Nothing sent yet'}>
              {sentCount}
            </Stat>
          </div>
          <div className="flex justify-end">
            <Button variant="quiet" onClick={() => setIntro(false)}>
              Just the summary from now on
            </Button>
          </div>
        </div>
      ) : (
        <div className="flex flex-wrap items-center gap-x-4 gap-y-1 border-b border-rule-solid bg-surface px-5 py-2.5 text-data">
          <span className="text-ink-primary">
            <strong className="font-semibold">{outreachSummary.toContact} to contact</strong> before bills are dated{' '}
            {date(OUTREACH_POLICY.sendBefore)}
          </span>
          <Summary n={outreachSummary.mostlyWeather} label="mostly weather" />
          <Summary n={outreachSummary.usageBeyondWeather} label="usage beyond weather" warn />
          <Summary n={outreachSummary.spanish} label="in Spanish" />
          <Summary n={sentCount} label="contacted" />
          <Summary n={excluded.length} label="not contacted, with reasons" />
          <button type="button" onClick={() => setIntro(true)} className="ml-auto text-micro text-accent-text underline">
            Show the rules and figures
          </button>
        </div>
      )}

      <div className="flex-1 min-h-0 overflow-auto lg:overflow-hidden grid grid-cols-1 lg:grid-cols-[minmax(0,1fr)_30rem] lg:grid-rows-[minmax(0,1fr)]">
        <section className="min-w-0 min-h-0 border-r border-rule-solid flex flex-col">
          <div className="flex flex-wrap items-center justify-between gap-3 border-b border-rule-hair bg-surface px-cell-x py-2">
            <Group label="Show">
              {(
                [
                  ['all', 'All'],
                  ['unsent', 'Not contacted'],
                  ['usage', 'Usage beyond weather'],
                  ['calls', 'Calls'],
                  ['spanish', 'Spanish'],
                ] as [Filter, string][]
              ).map(([f, l]) => (
                <Chip key={f} on={filter === f} onClick={() => setFilter(f)}>
                  {l}
                </Chip>
              ))}
            </Group>
            <div className="flex items-center gap-2">
              {checkedRows.length ? (
                <Button disabled={!mayContact} onClick={() => send(checkedRows)}>
                  Send to {checkedRows.length} selected
                </Button>
              ) : null}
              <Button
                variant="primary"
                disabled={!mayContact || ready.length === 0}
                title={!mayContact ? 'Your role cannot send outreach' : undefined}
                onClick={() => send(ready)}
              >
                Send all ready · {ready.length}
              </Button>
            </div>
          </div>

          <div className="flex-1 min-h-0 overflow-auto">
            <Table caption="Customers whose draft bill rose past the outreach threshold, largest increase first">
              <thead className="sticky top-0 z-10">
                <HeadRow>
                  <Th width="3px"> </Th>
                  <Th width="3%"> </Th>
                  <Th width="27%">Customer</Th>
                  <Th width="17%" align="right">
                    Last Feb → this Feb
                  </Th>
                  <Th width="12%" align="right">
                    Change
                  </Th>
                  <Th width="17%">Mostly</Th>
                  <Th width="11%">Reach by</Th>
                  <Th width="13%">Status</Th>
                </HeadRow>
              </thead>
              <tbody>
                {rows.map((c) => {
                  const v = verdictOf(c)
                  const tone: Tone = c.usageFlag || v === 'usage' ? 'warning' : 'info'
                  const done = latest.get(c.id)
                  const delta = c.draftCents - c.priorCents
                  return (
                    <Row key={c.id} selected={c.id === selected?.id}>
                      <RailCell>
                        <Rail tone={done ? 'cleared' : tone} />
                      </RailCell>
                      <Td>
                        <input
                          type="checkbox"
                          aria-label={`Select ${c.name}`}
                          checked={checked.has(c.id)}
                          disabled={!!done || c.plan === 'call'}
                          onChange={() => toggle(c.id)}
                        />
                      </Td>
                      <Td>
                        <button
                          type="button"
                          onClick={() => setSelectedId(c.id)}
                          className="text-left text-data text-ink-primary hover:text-accent-text"
                        >
                          {c.name}
                        </button>
                        <p className="flex items-center gap-1.5">
                          {c.customerId ? (
                            <AccountNumber number={c.accountNumber} id={c.customerId} />
                          ) : (
                            <span className="ident text-ink-tertiary">{c.accountNumber}</span>
                          )}
                          {c.lang === 'es' ? <span className="ident text-ink-tertiary">· ES</span> : null}
                        </p>
                      </Td>
                      <Td align="right">
                        <span className="figures text-ink-tertiary">{dollars(c.priorCents)}</span>
                        <span className="text-ink-muted" aria-hidden>
                          {' '}→{' '}
                        </span>
                        <span className="figures text-ink-primary">{dollars(c.draftCents)}</span>
                      </Td>
                      <Td align="right">
                        <span className="figures text-exception-warning-text">+{dollars(delta)}</span>
                        <p className="text-micro text-ink-tertiary figures">{percent(delta / c.priorCents, 0)}</p>
                      </Td>
                      <Td>
                        <StateFlag tone={v === 'usage' ? 'warning' : 'info'}>{REASON_SHORT.en[v]}</StateFlag>
                        {c.usageFlag && v !== 'usage' ? (
                          <p className="mt-0.5 text-micro text-exception-warning-text">+ usage beyond weather</p>
                        ) : null}
                      </Td>
                      <Td>
                        <span className="text-micro text-ink-secondary">{PLAN_LABEL[c.plan]}</span>
                      </Td>
                      <Td>
                        <Status action={done} />
                      </Td>
                    </Row>
                  )
                })}
              </tbody>
            </Table>

            <Panel className="m-cell-x my-4">
              <PanelHeader title="Over the line, and not contacted" meta="Each with its reason — nothing is dropped silently" />
              <ul className="divide-y divide-rule-hair">
                {excluded.map((x) => (
                  <li key={x.accountNumber + x.name} className="flex items-baseline gap-3 px-4 py-2">
                    <span className="w-44 shrink-0 text-data text-ink-primary">
                      {x.name}
                      <span className="block">
                        {x.customerId ? (
                          <AccountNumber number={x.accountNumber} id={x.customerId} />
                        ) : (
                          <span className="ident text-ink-tertiary">{x.accountNumber}</span>
                        )}
                      </span>
                    </span>
                    <span className="w-14 shrink-0 figures text-micro text-ink-tertiary">+{percent(x.changePct, 0)}</span>
                    <span className="text-micro text-ink-secondary">{x.reason}</span>
                  </li>
                ))}
              </ul>
            </Panel>
          </div>
        </section>

        {selected ? (
          <Detail key={selected.id} c={selected} done={latest.get(selected.id)} mayContact={mayContact} onSend={() => send([selected])} />
        ) : null}
      </div>
    </>
  )
}

function Status({ action }: { action: OutreachAction | undefined }) {
  if (!action) return <span className="text-micro text-ink-tertiary">Not contacted</span>
  const label = {
    sent: 'Sent',
    scheduled: 'Scheduled 8 a.m.',
    called: 'Called',
    bill_message: 'On the bill',
    skipped: 'Skipped',
  }[action.kind]
  return (
    <span className="text-micro">
      <StateFlag tone={action.kind === 'skipped' ? 'snoozed' : 'cleared'}>{label}</StateFlag>
    </span>
  )
}

function Detail({
  c,
  done,
  mayContact,
  onSend,
}: {
  c: Candidate
  done: OutreachAction | undefined
  mayContact: boolean
  onSend: () => void
}) {
  const template = templateById.get('high-bill-heads-up')!
  const { content } = useTemplate(template)
  const channels: Channel[] = c.plan === 'text' ? ['sms'] : c.plan === 'email' ? ['email'] : ['sms', 'email']
  const [channel, setChannel] = useState<Channel>(channels[0])
  const [note, setNote] = useState('')
  const v = verdictOf(c)
  const lang = content[channel]?.[c.lang] ? c.lang : 'en'
  const delta = c.draftCents - c.priorCents

  const ctx = useMemo(
    () =>
      contextFor('', lang, {
        'customer.first_name': c.firstName,
        'customer.name': c.name,
        'account.number': c.accountNumber,
        'service.address': c.address,
        'bill.period': lang === 'es' ? 'febrero' : 'February',
        'bill.amount_due': dollars(c.draftCents),
        'bill.current_charges': dollars(c.draftCents),
        'bill.change_amount': dollars(delta),
        'bill.compare_label': lang === 'es' ? 'febrero del año pasado' : 'last February',
        'bill.main_reason': REASON[lang][v],
        'bill.main_reason_short': REASON_SHORT[lang][v],
        'bill.explain_link': `${tenant.portalUrl}/b/${c.accountNumber.slice(-4)}`,
      }),
    [c, lang, v, delta],
  )

  const msg = content[channel]?.[lang]

  return (
    <aside className="min-w-0 overflow-auto bg-surface">
      <div className="px-4 py-3 border-b border-rule-solid bg-surface-raised">
        <div className="flex items-center gap-2">
          <StateFlag tone={v === 'usage' ? 'warning' : 'info'}>{`Mostly ${REASON_SHORT.en[v]}`}</StateFlag>
          {c.usageFlag ? <StateFlag tone="warning">Usage beyond weather</StateFlag> : null}
          {c.flags.map((f) => (
            <span key={f} className="text-micro text-ink-tertiary">
              {{ medical: 'Medical certificate', collections: 'In collections', payment_plan: 'Payment plan', autopay: 'AutoPay', paperless: 'Paperless', commercial: 'Commercial' }[f]}
            </span>
          ))}
        </div>
        <h2 className="text-h2 text-ink-primary mt-1.5">
          {c.customerId ? (
            <Link href={`/customers/${c.customerId}` as Route} className="hover:text-accent-text">
              {c.name}
            </Link>
          ) : (
            c.name
          )}
        </h2>
        <p className="text-micro text-ink-tertiary mt-0.5">
          {c.accountNumber} · {c.address}
          {c.invoiceId ? (
            <>
              {' · '}
              <Link href={`/invoices/${c.invoiceId}/explain` as Route} className="text-accent-text underline">
                Full explanation
              </Link>
            </>
          ) : null}
        </p>
      </div>

      <Fold title="Why it moved" gist={`+${money(delta / 100)} · mostly ${REASON_SHORT.en[v]}${c.usageFlag ? ' · usage beyond weather' : ''}`}>
        <Waterfall
          compact
          start={{ label: 'Last February', cents: c.priorCents }}
          steps={[
            { label: 'Colder weather', cents: c.drivers.weather },
            { label: 'Usage beyond weather', cents: c.drivers.usage },
            { label: 'Gas cost', cents: c.drivers.gasCost },
            { label: 'Rates, riders, tax', cents: c.drivers.other },
          ]}
          end={{ label: 'This February', cents: c.draftCents }}
        />
        {c.usageFlag ? (
          <p className="mt-3 text-micro text-exception-warning-text leading-relaxed">
            Usage beyond what the weather explains is {dollars(c.drivers.usage)}. Worth offering a free safety check — it is
            sometimes a leak, more often a thermostat or a new appliance.
          </p>
        ) : null}
      </Fold>

      <Fold
        title="How we reach them"
        gist={`${PLAN_LABEL[c.plan]}${c.reach.smsConsent ? ' · text consent on file' : ''}`}
      >
        <p className="text-micro text-ink-secondary leading-relaxed">{c.planWhy}</p>
        <dl className="mt-2 grid grid-cols-3 gap-2 text-micro">
          <div>
            <dt className="text-ink-tertiary">Email</dt>
            <dd className="text-ink-primary truncate">{c.reach.email ?? '—'}</dd>
          </div>
          <div>
            <dt className="text-ink-tertiary">Mobile</dt>
            <dd className="text-ink-primary">{c.reach.mobile ?? '—'}</dd>
          </div>
          <div>
            <dt className="text-ink-tertiary">Text consent</dt>
            <dd className={c.reach.smsConsent ? 'text-exception-cleared-text' : 'text-ink-secondary'}>
              {c.reach.smsConsent ? 'On file' : 'None'}
            </dd>
          </div>
        </dl>
      </Fold>

      {c.plan === 'call' ? (
        <div className="px-4 py-4 border-b border-rule-hair space-y-2">
          <p className="field-label">Talking points</p>
          <ul className="list-disc pl-4 space-y-1 text-data text-ink-secondary">
            <li>
              The February bill will be about <strong className="text-ink-primary">{dollars(c.draftCents)}</strong>,{' '}
              {dollars(delta)} more than last February. {REASON.en[v]}
            </li>
            <li>Budget billing would level the payments; an arrangement can spread this bill.</li>
            {c.flags.includes('medical') ? <li>Their medical certificate stays in force — this call is a courtesy, not a notice.</li> : null}
            {c.flags.includes('collections') ? <li>Offer an arrangement that covers the past-due balance and this bill together.</li> : null}
            {c.usageFlag ? <li>Offer a free safety check for the usage the weather does not explain.</li> : null}
          </ul>
          <label htmlFor="call-note" className="field-label block pt-1">
            Call notes
          </label>
          <textarea
            id="call-note"
            rows={2}
            value={note}
            onChange={(e) => setNote(e.target.value)}
            placeholder="What did they say? Recorded on the account."
            className="w-full rounded-sm border border-rule-solid bg-surface-raised px-2 py-1.5 text-data text-ink-primary placeholder:text-ink-muted"
          />
          <div className="flex gap-2">
            <Button
              variant="primary"
              disabled={!mayContact || !!done || note.trim().length < 4}
              onClick={() =>
                logOutreach([{ candidateId: c.id, kind: 'called', channels: ['phone'], note: note.trim(), by: activeUserName() }])
              }
            >
              Log the call
            </Button>
            <Button
              variant="quiet"
              disabled={!mayContact || !!done}
              onClick={() =>
                logOutreach([{ candidateId: c.id, kind: 'skipped', channels: [], note: 'No answer — left on the call list', by: activeUserName() }])
              }
            >
              No answer
            </Button>
          </div>
        </div>
      ) : (
        <div className="px-4 py-4 border-b border-rule-hair">
          <div className="flex items-center justify-between gap-2 mb-3">
            <p className="field-label">
              The message · {lang === 'es' ? 'Spanish' : 'English'}
              {c.lang === 'es' && lang === 'en' ? ' (no Spanish version yet)' : ''}
            </p>
            <div className="flex items-center gap-1">
              {channels.length > 1
                ? channels.map((ch) => (
                    <Chip key={ch} on={channel === ch} onClick={() => setChannel(ch)}>
                      {ch === 'sms' ? 'Text' : 'Email'}
                    </Chip>
                  ))
                : null}
            </div>
          </div>
          {c.plan === 'bill_message' ? (
            <p className="text-data text-ink-secondary">
              Prints as the bill message on the statement: “{ctx['bill.main_reason']} See {ctx['bill.explain_link']} for the
              details.”
            </p>
          ) : msg ? (
            <MessagePreview
              template={template}
              channel={channel}
              lang={lang}
              content={msg}
              ctx={ctx}
              to={{ name: c.name, email: c.reach.email, phone: c.reach.mobile, address: c.address }}
              marks={false}
            />
          ) : null}
          <p className="mt-3 text-micro text-ink-tertiary">
            From the{' '}
            <Link href={'/communications/high-bill-heads-up' as Route} className="text-accent-text underline">
              High-bill heads-up
            </Link>{' '}
            template — change the wording there and every heads-up uses it.
          </p>
        </div>
      )}

      <div className="px-4 py-4">
        {done ? (
          <StateBlock tone="cleared">
            <p className="text-data text-ink-primary">
              {{ sent: 'Sent', scheduled: 'Scheduled for 8 a.m.', called: 'Called', bill_message: 'Set to print on the bill', skipped: 'No answer' }[done.kind]}{' '}
              by {done.by}, {stamp(done.at)}.
              {done.note ? <span className="block text-micro text-ink-secondary mt-0.5">“{done.note}”</span> : null}
            </p>
          </StateBlock>
        ) : c.plan === 'call' ? null : (
          <Button variant="primary" disabled={!mayContact} onClick={onSend} title={mayContact ? undefined : 'Your role cannot send outreach'}>
            {c.plan === 'bill_message' ? 'Print on the bill' : outreachSummary.sendsNow ? 'Send heads-up now' : 'Schedule for 8 a.m.'}
          </Button>
        )}
      </div>
    </aside>
  )
}

function Stat({ label, sub, children }: { label: string; sub: string; children: React.ReactNode }) {
  return (
    <div className="bg-surface-raised px-4 py-3">
      <p className="field-label">{label}</p>
      <p className="text-figure text-ink-primary mt-1">{children}</p>
      <p className="text-micro text-ink-tertiary mt-0.5">{sub}</p>
    </div>
  )
}
