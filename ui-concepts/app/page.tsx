import Link from 'next/link'
import { AppShell, PageHeader } from '@/components/shell/AppShell'
import { Panel, PanelHeader, Field, FieldGrid, Button, Key } from '@/components/ui/Panel'
import { Rail, StateFlag, StateBlock, severityTone, humanize } from '@/components/ui/State'
import { Confidence } from '@/components/ui/Flags'
import { Money } from '@/components/ui/Money'
import { Table, HeadRow, Th, Row, Td, RailCell, TableFooter } from '@/components/table/Table'
import { byConsequence, openExceptions, exceptions, blockingCount } from '@/fixtures/exceptions'
import { customerById, meterById } from '@/fixtures/accounts'
import { currentRun } from '@/fixtures/billing'
import { cycle } from '@/fixtures/tenant'
import { customerName } from '@/schemas/models'
import { stamp, date, dateShort } from '@/lib/format'

/**
 * The pre-mail exception queue — the home surface of the product.
 *
 * Not a dashboard. The analyst logs in at 7:40 to clear work, and the run
 * cannot post until everything that blocks delivery is resolved. Ranked by
 * consequence rather than recency, and the detail pane sits beside the list so
 * the surrounding rows stay visible: judging whether this is one bad read or a
 * whole route gone wrong requires seeing its neighbours.
 */

export default function ExceptionQueuePage() {
  const rows = byConsequence(openExceptions)
  const selected = rows[0]
  const cleared = exceptions.length - openExceptions.length

  return (
    <AppShell current="Exceptions">
      <PageHeader
        title="Pre-mail exceptions"
        meta={
          <>
            {cycle.label} · {cycle.periodLabel} · run {currentRun.run_number} · bills dated{' '}
            {date(cycle.billDate)}
          </>
        }
        actions={
          <>
            <Button>Assign selected</Button>
            <Button variant="primary" disabled title={`${blockingCount} exceptions still block delivery`}>
              Post run
            </Button>
          </>
        }
      />

      <div className="px-5 py-3 border-b border-rule-solid bg-surface">
        <StateBlock tone="critical">
          <p className="text-data text-ink-primary">
            <strong className="font-semibold">{blockingCount} exceptions block delivery.</strong>{' '}
            Bills on these accounts cannot reach <em>pending</em> or <em>sent</em> until each one is
            resolved, and the run cannot post while any remain.
          </p>
        </StateBlock>
      </div>

      <div className="flex-1 min-h-0 grid grid-cols-1 lg:grid-cols-[minmax(0,1fr)_26rem]">
        <section className="min-w-0 border-r border-rule-solid flex flex-col">
          <div className="flex items-center justify-between gap-4 px-cell-x py-2 border-b border-rule-hair bg-surface">
            <p className="text-micro text-ink-secondary">
              <strong className="text-ink-primary font-semibold">{rows.length} remaining</strong> ·{' '}
              {cleared} cleared today
            </p>
            <p className="text-micro text-ink-tertiary flex items-center gap-1.5">
              <Key>j</Key>
              <Key>k</Key> move · <Key>r</Key> resolve · <Key>s</Key> snooze · <Key>a</Key> assign
            </p>
          </div>

          <div className="flex-1 min-h-0 overflow-auto">
            <Table caption="Open pre-mail exceptions for cycle 04, ranked by consequence">
              <thead className="sticky top-0 z-10">
                <HeadRow>
                  <Th width="3px"> </Th>
                  <Th width="38%">Exception</Th>
                  <Th width="16%">Account</Th>
                  <Th width="8%">Meter</Th>
                  <Th width="7%" align="center">Conf.</Th>
                  <Th width="10%" align="right">At risk</Th>
                  <Th width="11%">Assigned</Th>
                  <Th width="10%">Detected</Th>
                </HeadRow>
              </thead>
              <tbody>
                {rows.map((e) => {
                  const tone = severityTone(e.severity, e.status)
                  const customer = e.customer_id ? customerById.get(e.customer_id) : undefined
                  const meter = e.meter_id ? meterById.get(e.meter_id) : undefined
                  return (
                    <Row key={e.id} selected={e.id === selected?.id}>
                      <RailCell>
                        <Rail tone={tone} />
                      </RailCell>
                      <Td>
                        <div className="flex items-center gap-2">
                          <StateFlag tone={tone}>{e.severity}</StateFlag>
                          {e.blocks_delivery ? (
                            <span
                              className="label-caps text-exception-critical-text"
                              title="This exception stops the bill from being delivered"
                            >
                              Blocks
                            </span>
                          ) : null}
                        </div>
                        <p className="text-data text-ink-primary mt-0.5">{e.description}</p>
                        <p className="text-micro text-ink-tertiary">
                          {humanize(e.anomaly_type)}
                          {e.recurrence_count > 1
                            ? ` · ${ordinal(e.recurrence_count)} occurrence since ${date(e.first_detected_at)}`
                            : ''}
                        </p>
                      </Td>
                      <Td>
                        {customer ? (
                          <>
                            <p className="text-data text-ink-primary truncate">
                              {customerName(customer)}
                            </p>
                            <p className="ident text-ink-tertiary">{customer.customer_number}</p>
                          </>
                        ) : (
                          <span className="text-ink-muted">—</span>
                        )}
                      </Td>
                      <Td>
                        {meter ? (
                          <span className="ident text-ink-secondary">{meter.meter_number}</span>
                        ) : (
                          <span className="text-ink-muted">—</span>
                        )}
                      </Td>
                      <Td align="center">
                        <Confidence value={e.confidence} />
                      </Td>
                      <Td align="right">
                        {e.estimated_impact ? (
                          <Money value={e.estimated_impact} />
                        ) : (
                          <span className="text-ink-muted">—</span>
                        )}
                      </Td>
                      <Td>
                        <span className="text-micro text-ink-secondary">
                          {e.assigned_to ?? <span className="text-ink-muted">Unassigned</span>}
                        </span>
                      </Td>
                      <Td>
                        <span className="text-micro text-ink-tertiary whitespace-nowrap">
                          {dateShort(e.detected_at)}
                        </span>
                      </Td>
                    </Row>
                  )
                })}
              </tbody>
            </Table>
          </div>
          <TableFooter shown={rows.length} total={currentRun.total_exceptions} noun="exceptions" />
        </section>

        {selected ? <ExceptionDetail exception={selected} /> : null}
      </div>
    </AppShell>
  )
}

function ExceptionDetail({ exception: e }: { exception: (typeof exceptions)[number] }) {
  const tone = severityTone(e.severity, e.status)
  const customer = e.customer_id ? customerById.get(e.customer_id) : undefined
  const meter = e.meter_id ? meterById.get(e.meter_id) : undefined

  return (
    <aside className="min-w-0 overflow-auto bg-surface">
      <div className="px-4 py-3 border-b border-rule-solid bg-surface-raised">
        <StateFlag tone={tone}>{e.severity}</StateFlag>
        <h2 className="text-h2 text-ink-primary mt-1.5">{e.description}</h2>
        <p className="text-micro text-ink-tertiary mt-1">
          {humanize(e.anomaly_type)} · detected by {e.detector_name} ({humanize(e.detection_method)})
        </p>
      </div>

      <div className="px-4 py-4 border-b border-rule-hair">
        <FieldGrid cols={2}>
          <Field label="Account">
            {customer ? (
              <Link
                href={`/customers/${customer.id}`}
                className="text-accent hover:text-accent-hover underline"
              >
                {customerName(customer)}
              </Link>
            ) : (
              '—'
            )}
          </Field>
          <Field label="Meter">
            {meter ? <span className="ident">{meter.meter_number}</span> : '—'}
          </Field>
          <Field label="Amount at risk">
            {e.estimated_impact ? <Money value={e.estimated_impact} /> : '—'}
          </Field>
          <Field label="First detected">{stamp(e.first_detected_at)}</Field>
        </FieldGrid>
      </div>

      <div className="px-4 py-4 border-b border-rule-hair">
        <p className="label-caps mb-2">Detector findings</p>
        <dl className="divide-y divide-rule-hair border-y border-rule-hair">
          {Object.entries(e.details).map(([k, v]) => (
            <div key={k} className="flex items-baseline justify-between gap-4 py-1.5">
              <dt className="text-micro text-ink-secondary">{humanize(k)}</dt>
              <dd className="text-data text-ink-primary figures">{String(v)}</dd>
            </div>
          ))}
        </dl>
      </div>

      {e.suggested_action ? (
        <div className="px-4 py-4 border-b border-rule-hair">
          <p className="label-caps mb-2">Suggested action</p>
          {/* Presented, never applied. This is the trust boundary for the AI
              features — a wrong default here becomes a wrong bill. */}
          <Button variant="primary">{e.suggested_action.label}</Button>
          <p className="text-micro text-ink-secondary mt-2 leading-relaxed">
            {e.suggested_action.explanation}
          </p>
          <p className="text-micro text-ink-tertiary mt-1.5">
            You will see the resulting numbers before anything is committed.
          </p>
        </div>
      ) : null}

      <div className="px-4 py-4">
        <p className="label-caps mb-2">Resolve</p>
        <label className="block text-micro text-ink-secondary mb-1" htmlFor="reason">
          Resolution reason <span className="text-exception-critical-text">required</span>
        </label>
        <textarea
          id="reason"
          rows={3}
          placeholder="What did you find, and what did you do about it?"
          className="w-full rounded-xs border border-rule-solid bg-surface-raised px-2 py-1.5 text-data text-ink-primary placeholder:text-ink-muted"
        />
        <p className="text-micro text-ink-tertiary mt-1">
          Recorded against this exception permanently, with your name and the time.
        </p>
        <div className="flex items-center gap-2 mt-3">
          <Button variant="primary">Resolve</Button>
          <Button>Snooze</Button>
          <Button variant="quiet">Mark false positive</Button>
        </div>
      </div>
    </aside>
  )
}

function ordinal(n: number): string {
  const suffix = n % 10 === 1 && n !== 11 ? 'st' : n % 10 === 2 && n !== 12 ? 'nd' : n % 10 === 3 && n !== 13 ? 'rd' : 'th'
  return `${n}${suffix}`
}
