import Link from 'next/link'
import type { Route } from 'next'
import { AppShell, PageHeader } from '@/components/shell/AppShell'
import { Button, Panel, PanelHeader } from '@/components/ui/Panel'
import { Rail, StateBlock, StateFlag, humanize, type Tone } from '@/components/ui/State'
import { Table, HeadRow, Th, Row, Td, RailCell, TableFooter } from '@/components/table/Table'
import { Money } from '@/components/ui/Money'
import {
  BYPASSES,
  auditTrail,
  conditionsToday,
  evaluate,
  evaluatedAt,
  holdClearsOn,
  pipeline,
  reconnectQueue,
  stayedAccounts,
  worklist,
  type BypassCategory,
  type WorklistRow,
} from '@/fixtures/collections'
import { count, date, dateShort, days, stamp } from '@/lib/format'
import { asOf } from '@/fixtures/tenant'

/**
 * Collections and disconnect worklist.
 *
 * The highest-consequence error in this module is disconnecting someone who
 * was protected, so the screen is not organised by who owes the most. It is
 * organised by what an operator may lawfully do today, and every row states
 * the rule that produced its answer.
 *
 * The groups run in the order work actually gets done: what is actionable now,
 * what this office can unblock today, what the weather is holding, and what
 * belongs to the customer and must simply be left alone.
 */

type Group = {
  key: BypassCategory | 'eligible'
  title: string
  note: string
  tone: Tone
}

const GROUPS: Group[] = [
  {
    key: 'eligible',
    title: 'Eligible for disconnect today',
    note: 'Every condition evaluated and none in force. These are the only accounts field work may proceed on.',
    tone: 'approved',
  },
  {
    key: 'process',
    title: 'Our work outstanding — due before the hold lifts',
    note: 'Each of these also carries the temperature hold, so nothing happens today either way. They are called out separately because the block is the utility’s own unfinished work, and it does not clear on a forecast.',
    tone: 'warning',
  },
  {
    key: 'weather',
    title: 'Blocked by the temperature hold alone',
    note: 'Otherwise eligible. These return to the top of the list when the forecast clears.',
    tone: 'info',
  },
  {
    key: 'protection',
    title: 'Protected — leave alone',
    note: 'The protection sits with the customer and outlasts the weather. Collections activity short of disconnect may continue where the rule allows it.',
    tone: 'held',
  },
]

const CATEGORY_TONE: Record<BypassCategory | 'eligible', Tone> = {
  eligible: 'approved',
  process: 'warning',
  weather: 'info',
  protection: 'held',
  absolute: 'critical',
}

export default function CollectionsPage() {
  const rows = worklist.map((row) => ({ row, verdict: evaluate(row) }))
  const eligible = rows.filter((r) => r.verdict.eligible)

  return (
    <AppShell current="Collections">
      <PageHeader
        title="Collections &amp; disconnect"
        meta={`Evaluated ${stamp(evaluatedAt)} · ${count(pipeline.total)} accounts in the dunning pipeline · Railroad Commission of Texas rules`}
        actions={
          <>
            <Button>Re-run evaluation</Button>
            <Button variant="primary" disabled={eligible.length === 0}>
              Create {count(eligible.length)} disconnect orders
            </Button>
          </>
        }
      />

      <div className="flex-1 overflow-auto">
        <div className="px-5 py-5 space-y-5">
          {/* ==== What the engine decided before it looked at anyone ==== */}
          <Panel>
            <PanelHeader
              title="Conditions in force today"
              meta="Jurisdiction rules evaluated once, then applied to every account"
              actions={
                <span className="text-micro text-ink-tertiary">
                  Forecast clears {date(holdClearsOn)}
                </span>
              }
            />
            <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-4 gap-px bg-rule-hair">
              {conditionsToday.map((c) => (
                <div key={c.code} className="bg-surface-raised px-4 py-3">
                  <div className="flex items-baseline justify-between gap-3">
                    <p className="text-data text-ink-primary">{c.label}</p>
                    <StateFlag
                      tone={
                        c.state === 'in_force' ? 'critical' : c.state === 'clear' ? 'approved' : 'snoozed'
                      }
                    >
                      {c.state === 'not_adopted' ? 'N/A' : humanize(c.state)}
                    </StateFlag>
                  </div>
                  <p className="text-micro text-ink-secondary mt-1">{c.detail}</p>
                  <p className="text-micro text-ink-tertiary mt-1">
                    {c.scope} · <span className="ident">{c.citation}</span>
                  </p>
                </div>
              ))}
            </div>
          </Panel>

          <StateBlock tone="critical">
            <p className="text-data text-ink-primary">
              <strong className="font-semibold">
                The temperature hold covers residential service only.
              </strong>{' '}
              Texas has no calendar winter moratorium — 16 TAC §7.460 turns on a National Weather
              Service forecast, and it protects homes, not businesses. That single clause is why{' '}
              {count(eligible.length)} accounts remain actionable this morning while every
              residential account on the list is held. Getting that scope wrong in either direction
              is a wrongful disconnect or an uncollected month.
            </p>
          </StateBlock>

          {/* ==== The worklist ==== */}
          <Panel>
            <PanelHeader
              title="Disconnect worklist"
              meta={`${count(pipeline.modelled)} of ${count(pipeline.total)} accounts modelled · ${count(pipeline.eligibleWhenHoldLifts)} become eligible when the hold lifts`}
            />
            <Table caption="Accounts in the dunning pipeline with every bypass condition evaluated">
              <thead>
                <HeadRow>
                  <Th width="3px"> </Th>
                  <Th width="16%">Account</Th>
                  <Th width="14%">Service address</Th>
                  <Th align="right" width="9%">
                    Balance
                  </Th>
                  <Th align="right" width="5%">
                    Past due
                  </Th>
                  <Th width="10%">Stage</Th>
                  <Th width="13%">Last notice</Th>
                  <Th width="16%">Conditions evaluated</Th>
                  <Th width="12%">Disconnect eligible</Th>
                  <Th align="right" width="5%">
                    Deposit
                  </Th>
                </HeadRow>
              </thead>
              <tbody>
                {GROUPS.map((group) => {
                  const inGroup = rows.filter((r) => r.verdict.category === group.key)
                  if (inGroup.length === 0 && group.key !== 'eligible') return null
                  return (
                    <SectionGroup key={group.key} group={group} n={inGroup.length}>
                      {inGroup.map(({ row, verdict }) => (
                        <WorklistLine key={row.id} row={row} category={verdict.category} />
                      ))}
                    </SectionGroup>
                  )
                })}
              </tbody>
            </Table>
            <TableFooter shown={pipeline.modelled} total={pipeline.total} noun="accounts past due" />
          </Panel>

          {/* ==== Not "blocked" — removed from collections entirely ==== */}
          <Panel>
            <PanelHeader
              title="Excluded from all collections activity"
              meta="Automatic stay — not a bypass condition"
            />
            <div className="px-4 py-3 border-b border-rule-hair">
              <p className="text-data text-ink-primary">
                A bankruptcy stay is not a reason a disconnect is held today. It bars every
                collections action — notices, calls, field work — from the petition date, and the
                ledger splits there. These accounts are kept off the worklist rather than shown on
                it with a flag, because a flag is something an operator can talk themselves past.
              </p>
            </div>
            <Table caption="Accounts under an automatic stay">
              <thead>
                <HeadRow>
                  <Th width="3px"> </Th>
                  <Th>Account</Th>
                  <Th>Case</Th>
                  <Th>Petition date</Th>
                  <Th align="right">Pre-petition</Th>
                  <Th align="right">Post-petition</Th>
                  <Th>Adequate assurance</Th>
                  <Th>Stopped at</Th>
                </HeadRow>
              </thead>
              <tbody>
                {stayedAccounts.map((s) => {
                  const remaining = days(asOf.validAt, s.assuranceDeadline)
                  return (
                    <Row key={s.id}>
                      <RailCell>
                        <Rail tone="critical" />
                      </RailCell>
                      <Td>
                        <p className="text-data text-ink-primary">{s.name}</p>
                        <p className="ident text-ink-tertiary">{s.accountNumber}</p>
                      </Td>
                      <Td>
                        <p className="text-data">{s.chapter}</p>
                        <p className="ident text-ink-tertiary">{s.caseNumber}</p>
                      </Td>
                      <Td>{date(s.petitionDate)}</Td>
                      <Td align="right">
                        <Money value={s.prePetitionBalance} />
                      </Td>
                      <Td align="right">
                        <Money value={s.postPetitionBalance} />
                      </Td>
                      <Td>
                        <span className="text-data text-exception-warning-text">
                          {date(s.assuranceDeadline)} · {remaining} days left
                        </span>
                        <p className="text-micro text-ink-tertiary">
                          11 USC §366(b) — request within 20 days or lose the right
                        </p>
                      </Td>
                      <Td>
                        <span className="text-micro text-ink-secondary">{stamp(s.noticedAt)}</span>
                      </Td>
                    </Row>
                  )
                })}
              </tbody>
            </Table>
          </Panel>

          {/* ==== The other half of the truck roll ==== */}
          <Panel>
            <PanelHeader
              title="Reconnect &amp; relight queue"
              meta="Every reconnect is a scheduled visit — the meter is not simply re-energised"
              actions={<Button>Build tomorrow&rsquo;s route</Button>}
            />
            <Table caption="Accounts awaiting reconnection">
              <thead>
                <HeadRow>
                  <Th width="3px"> </Th>
                  <Th>Account</Th>
                  <Th>Disconnected</Th>
                  <Th>Paid</Th>
                  <Th>SLA due</Th>
                  <Th>Priority</Th>
                  <Th align="right">Fee</Th>
                  <Th>Relight readiness</Th>
                </HeadRow>
              </thead>
              <tbody>
                {reconnectQueue.map((r) => {
                  const overdue = Date.parse(r.slaDueAt) <= Date.parse(asOf.recordedAt)
                  return (
                    <Row key={r.id}>
                      <RailCell>
                        <Rail tone={overdue ? 'failed' : r.priority === 'standard' ? 'pending' : 'held'} />
                      </RailCell>
                      <Td>
                        <p className="text-data text-ink-primary">{r.name}</p>
                        <p className="text-micro text-ink-tertiary">{r.address}</p>
                      </Td>
                      <Td>
                        <span className="text-micro text-ink-secondary">{stamp(r.disconnectedAt)}</span>
                      </Td>
                      <Td>
                        <span className="text-micro text-ink-secondary">
                          {r.paidAt ? stamp(r.paidAt) : '—'}
                        </span>
                      </Td>
                      <Td>
                        <span
                          className={`text-micro ${overdue ? 'text-exception-critical-text font-medium' : 'text-ink-secondary'}`}
                        >
                          {stamp(r.slaDueAt)}
                          {overdue ? ' · breached' : ''}
                        </span>
                      </Td>
                      <Td>
                        <StateFlag
                          tone={r.priority === 'medical' ? 'critical' : r.priority === 'temperature' ? 'warning' : 'snoozed'}
                          title={r.priorityReason}
                        >
                          {humanize(r.priority)}
                        </StateFlag>
                        <p className="text-micro text-ink-tertiary mt-0.5">{r.priorityReason}</p>
                      </Td>
                      <Td align="right">
                        <span className={r.feeWaived ? 'struck' : ''}>
                          <Money value={r.fee} />
                        </span>
                        <p className="text-micro text-ink-tertiary">{r.feeNote}</p>
                      </Td>
                      <Td>
                        <StateFlag tone={r.customerConfirmed ? 'approved' : 'warning'}>
                          {r.customerConfirmed ? 'Customer confirmed' : 'Access not confirmed'}
                        </StateFlag>
                        <p className="text-micro text-ink-tertiary mt-0.5">
                          Pressure test, then relight every pilot. Customer must be on site.
                        </p>
                      </Td>
                    </Row>
                  )
                })}
              </tbody>
            </Table>
          </Panel>

          {/* ==== Subpoena-ready means the rationale is on the record ==== */}
          <Panel>
            <PanelHeader
              title="Decision log"
              meta="Every action with its rule, its input value, and whether a person or the engine made it"
            />
            <Table caption="Collections decision audit trail">
              <thead>
                <HeadRow>
                  <Th width="3px"> </Th>
                  <Th width="14%">When</Th>
                  <Th width="12%">Account</Th>
                  <Th width="20%">Action</Th>
                  <Th>Rationale</Th>
                  <Th width="12%">Source</Th>
                </HeadRow>
              </thead>
              <tbody>
                {auditTrail.map((e) => (
                  <Row key={e.id}>
                    <RailCell>
                      <Rail tone={e.source === 'operator' ? 'pending' : 'snoozed'} />
                    </RailCell>
                    <Td>
                      <span className="text-micro text-ink-secondary">{stamp(e.at)}</span>
                    </Td>
                    <Td>
                      <span className="ident text-ink-secondary">{e.account}</span>
                    </Td>
                    <Td>{e.action}</Td>
                    <Td>
                      <span className="text-micro text-ink-secondary">{e.rationale}</span>
                    </Td>
                    <Td>
                      <StateFlag tone={e.source === 'operator' ? 'pending' : 'snoozed'}>
                        {humanize(e.source)}
                      </StateFlag>
                      <p className="text-micro text-ink-tertiary mt-0.5">{e.actor}</p>
                    </Td>
                  </Row>
                ))}
              </tbody>
            </Table>
          </Panel>
        </div>
      </div>
    </AppShell>
  )
}

/** A titled band inside the table body, with the group's rule stated once. */
function SectionGroup({
  group,
  n,
  children,
}: {
  group: Group
  n: number
  children: React.ReactNode
}) {
  return (
    <>
      <tr>
        <td colSpan={10} className="p-0">
          <div className="flex items-baseline gap-3 border-y border-rule-solid bg-surface-sunken px-cell-x py-2">
            <StateFlag tone={group.tone}>{group.title}</StateFlag>
            <span className="ident text-ink-primary">{count(n)}</span>
            <span className="text-micro text-ink-tertiary">{group.note}</span>
          </div>
        </td>
      </tr>
      {n === 0 ? (
        <tr>
          <td colSpan={10} className="px-cell-x py-4 bg-surface-raised border-b border-rule-hair">
            <p className="text-data text-ink-secondary">
              No account is eligible for disconnect today.
            </p>
          </td>
        </tr>
      ) : (
        children
      )}
    </>
  )
}

function WorklistLine({ row, category }: { row: WorklistRow; category: BypassCategory | 'eligible' }) {
  const verdict = evaluate(row)
  return (
    <Row>
      <RailCell>
        <Rail tone={CATEGORY_TONE[category]} />
      </RailCell>
      <Td>
        {row.customerId ? (
          <Link
            href={`/customers/${row.customerId}` as Route}
            className="text-data text-ink-primary hover:text-accent-text hover:underline"
          >
            {row.name}
          </Link>
        ) : (
          <span className="text-data text-ink-primary">{row.name}</span>
        )}
        <p className="ident text-ink-tertiary">
          {row.accountNumber} · {row.isResidential ? 'Residential' : 'Commercial'}
          {row.priorDisconnects > 0 ? ` · ${row.priorDisconnects} prior` : ''}
        </p>
      </Td>
      <Td>
        <span className="text-micro text-ink-secondary">
          {row.address}, {row.city}
        </span>
      </Td>
      <Td align="right">
        <Money value={row.balance} arrears={row.pastDueDays >= 60} />
        {row.disputed ? (
          <p className="text-micro text-exception-warning-text">
            <Money value={row.disputed} className="!text-exception-warning-text" /> disputed
          </p>
        ) : null}
      </Td>
      <Td align="right">
        <span className="figures text-ink-secondary">{row.pastDueDays}d</span>
      </Td>
      <Td>
        <span className="text-micro text-ink-secondary">{humanize(row.stage)}</span>
      </Td>
      <Td>
        {row.lastNotice ? (
          <>
            <p className="text-micro text-ink-primary">{row.lastNotice.type}</p>
            <p className="text-micro text-ink-tertiary">
              {dateShort(row.lastNotice.sentAt)} · {row.lastNotice.channel}
            </p>
          </>
        ) : (
          <span className="text-ink-tertiary">—</span>
        )}
      </Td>
      <Td>
        {row.bypasses.length === 0 ? (
          <span className="text-micro text-ink-tertiary">All clear</span>
        ) : (
          <div className="flex flex-wrap gap-x-3 gap-y-1">
            {row.bypasses.map((b) => {
              const meta = BYPASSES[b.code]
              return (
                <span
                  key={b.code}
                  title={`${meta.label} — ${b.detail} (${meta.citation})`}
                  className="inline-flex items-baseline gap-1"
                >
                  <StateFlag tone={CATEGORY_TONE[meta.category]}>{meta.short}</StateFlag>
                  {b.expires ? (
                    <span className="text-micro text-ink-tertiary">to {dateShort(b.expires)}</span>
                  ) : null}
                </span>
              )
            })}
          </div>
        )}
      </Td>
      <Td>
        <StateFlag tone={CATEGORY_TONE[category]}>{verdict.eligible ? 'Yes' : 'No'}</StateFlag>
        <p className="text-micro text-ink-secondary mt-0.5">{verdict.reason}</p>
        {row.nextAction ? (
          <p className="text-micro text-accent-text mt-0.5">{row.nextAction}</p>
        ) : null}
      </Td>
      <Td align="right">
        {Number(row.deposit) > 0 ? (
          <Money value={row.deposit} />
        ) : (
          <span className="text-ink-tertiary">—</span>
        )}
      </Td>
    </Row>
  )
}
