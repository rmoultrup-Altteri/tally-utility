'use client'

import { useMemo, useState } from 'react'
import {
  LEVERS,
  authorised,
  baseline,
  billFor,
  currentCard,
  openingProposal,
  population,
  type Lever,
  type RateCard,
} from '@/fixtures/tariff'
import { Panel, PanelHeader, Button } from '@/components/ui/Panel'
import { StateBlock, StateFlag } from '@/components/ui/State'
import { Table, HeadRow, Th, Row, Td } from '@/components/table/Table'
import { Money } from '@/components/ui/Money'
import { count, date, money, rate as fmtRate, therms as fmtTherms } from '@/lib/format'

/**
 * The tariff sandbox.
 *
 * The competitive claim behind this product is that a rate change is an
 * afternoon rather than a three-week vendor engagement. That claim is only
 * credible if an analyst can see the consequence of a change before committing
 * it, so this screen rehearses a proposed card against a real, closed cycle's
 * actual consumption and reports the distribution.
 *
 * The distribution is the point. A single "average bill impact" figure is the
 * number that gets a utility into trouble at a rate hearing, because a change
 * that averages to nothing can still move a quarter of the class by five
 * dollars in each direction.
 */

const BUCKETS = [
  { label: 'down over $5', test: (d: number) => d <= -5 },
  { label: '−$5 to −$1', test: (d: number) => d < -1 && d > -5 },
  { label: 'within ±$1', test: (d: number) => d >= -1 && d <= 1 },
  { label: '+$1 to +$5', test: (d: number) => d > 1 && d < 5 },
  { label: '+$5 to +$10', test: (d: number) => d >= 5 && d < 10 },
  { label: 'up over $10', test: (d: number) => d >= 10 },
]

const BANDS = [
  { label: 'No usage', min: 0, max: 0 },
  { label: '1–49 th', min: 0.01, max: 49.99 },
  { label: '50–99 th', min: 50, max: 99.99 },
  { label: '100–199 th', min: 100, max: 199.99 },
  { label: '200–349 th', min: 200, max: 349.99 },
  { label: '350+ th', min: 350, max: Infinity },
]

const median = (xs: number[]) => {
  if (!xs.length) return 0
  const s = [...xs].sort((a, b) => a - b)
  const m = Math.floor(s.length / 2)
  return s.length % 2 ? s[m] : (s[m - 1] + s[m]) / 2
}

export function TariffSandbox() {
  const [proposed, setProposed] = useState<RateCard>({ ...currentCard, ...openingProposal })
  const [effectiveFrom, setEffectiveFrom] = useState('2026-04-01')
  const [reason, setReason] = useState('')
  const [docket, setDocket] = useState<string>(authorised.docket)

  const moved = LEVERS.filter((l) => proposed[l.key] !== currentCard[l.key])

  const impact = useMemo(() => {
    const deltas: number[] = []
    let totalDelta = 0
    let taxDelta = 0
    let up = 0
    let down = 0
    let same = 0
    let floored = 0
    for (const t of population) {
      const a = billFor(t, currentCard)
      const b = billFor(t, proposed)
      const d = b.total - a.total
      deltas.push(d)
      totalDelta += d
      taxDelta += b.tax - a.tax
      if (d > 0.005) up += 1
      else if (d < -0.005) down += 1
      else same += 1
      if (b.floored) floored += 1
    }
    const buckets = BUCKETS.map((b) => ({ label: b.label, n: deltas.filter((d) => b.test(d)).length }))
    const bands = BANDS.map((band) => {
      const idx = population
        .map((t, i) => ({ t, i }))
        .filter(({ t }) => t >= band.min && t <= band.max)
      return {
        label: band.label,
        n: idx.length,
        medianBase: median(idx.map(({ t }) => billFor(t, currentCard).total)),
        medianProp: median(idx.map(({ t }) => billFor(t, proposed).total)),
        medianDelta: median(idx.map(({ i }) => deltas[i])),
      }
    }).filter((b) => b.n > 0)

    /* Where the proposal stops costing a customer money and starts saving it. */
    let breakEven: number | null = null
    if (moved.length) {
      const sign = (t: number) => billFor(t, proposed).total - billFor(t, currentCard).total
      const start = sign(0)
      for (let t = 0; t <= 800; t += 0.5) {
        if (start > 0 ? sign(t) <= 0 : sign(t) >= 0) {
          breakEven = t
          break
        }
      }
    }
    return {
      deltas, totalDelta, taxDelta, up, down, same, floored, buckets, bands, breakEven,
      medianDelta: median(deltas),
      zeroUsage: billFor(0, proposed).total - billFor(0, currentCard).total,
      peak: Math.max(...buckets.map((b) => b.n)),
    }
  }, [proposed, moved.length])

  const committable = moved.length > 0 && reason.trim().length >= 12 && docket.trim().length > 0

  return (
    <div className="space-y-5">
      {/* ==== What the rehearsal stands on ==== */}
      <Panel>
        <PanelHeader
          title="Baseline"
          meta="Rehearsed against actual consumption, not a model"
          actions={
            <Button
              title="Reset every lever to the standing card"
              onClick={() => setProposed(currentCard)}
            >
              Reset to standing card
            </Button>
          }
        />
        <dl className="grid grid-cols-2 md:grid-cols-5 gap-x-6 gap-y-3 px-4 py-3">
          <Fact label="Cycle">{baseline.cycleLabel}</Fact>
          <Fact label="Period">
            {date(baseline.periodStart)} → {date(baseline.periodEnd)}
          </Fact>
          <Fact label="Accounts on R-1">{count(baseline.accountsOnSchedule)}</Fact>
          <Fact label="Out of scope" hint="Other schedules are untouched by this proposal">
            {count(baseline.accountsOtherSchedules)}
          </Fact>
          <Fact label="Reads locked" hint="A cycle still taking corrections would move mid-review">
            {date(baseline.readsLockedAt.slice(0, 10))}
          </Fact>
        </dl>
      </Panel>

      {/* ==== The proposal ==== */}
      <Panel>
        <PanelHeader
          title="Proposed card"
          meta="R-1 · every change becomes a new version; nothing is edited in place"
        />
        <Table caption="Rate items available to this proposal">
          <thead>
            <HeadRow>
              <Th width="34%">Item</Th>
              <Th align="right" width="14%">Standing</Th>
              <Th align="right" width="18%">Proposed</Th>
              <Th align="right" width="14%">Change</Th>
              <Th width="20%">Effect</Th>
            </HeadRow>
          </thead>
          <tbody>
            {LEVERS.map((lever) => {
              const now = currentCard[lever.key]
              const next = proposed[lever.key]
              const diff = next - now
              return (
                <Row key={lever.key} selected={Math.abs(diff) > 1e-9}>
                  <Td>
                    <p className="text-data text-ink-primary">{lever.label}</p>
                    <p className="ident text-ink-tertiary">{lever.code}</p>
                  </Td>
                  <Td align="right">
                    <span className="ident text-ink-secondary">
                      {lever.unit === '/month' ? money(now) : fmtRate(now)}
                    </span>
                  </Td>
                  <Td align="right">
                    <label className="sr-only" htmlFor={`lever-${lever.key}`}>
                      {lever.label} proposed rate
                    </label>
                    <input
                      id={`lever-${lever.key}`}
                      type="number"
                      step={lever.step}
                      min={0}
                      value={next}
                      onChange={(e) =>
                        setProposed((p) => ({ ...p, [lever.key]: Number(e.target.value) }))
                      }
                      className="w-32 rounded-xs border border-rule-solid bg-surface-raised px-2 py-1 text-right text-data text-ink-primary"
                    />
                    <span className="text-micro text-ink-tertiary ml-1">{lever.unit}</span>
                  </Td>
                  <Td align="right">
                    {Math.abs(diff) < 1e-9 ? (
                      <span className="text-ink-tertiary">—</span>
                    ) : (
                      <span
                        className={`figures ${diff > 0 ? 'text-exception-warning-text' : 'text-money-credit'}`}
                      >
                        {diff > 0 ? '+' : '−'}
                        {lever.unit === '/month'
                          ? money(Math.abs(diff)).replace('$', '$')
                          : fmtRate(Math.abs(diff)).replace('$', '$')}
                      </span>
                    )}
                  </Td>
                  <Td>
                    <span className="text-micro text-ink-secondary">
                      {lever.key === 'customerCharge'
                        ? 'Every account, including zero-usage'
                        : lever.key === 'block1Rate'
                          ? 'First 50 therms only'
                          : lever.key === 'block2Rate'
                            ? 'Accounts over 50 therms only'
                            : 'All metered volume'}
                    </span>
                  </Td>
                </Row>
              )
            })}
          </tbody>
        </Table>
        <p className="px-4 py-3 border-t border-rule-hair text-micro text-ink-secondary">
          The purchased gas adjustment is deliberately not a lever here. It is a pass-through set by
          filing, not a rate-design choice — moving it in a sandbox would model revenue the utility
          is not permitted to keep.
        </p>
      </Panel>

      {moved.length === 0 ? (
        <StateBlock tone="info">
          <p className="text-data text-ink-primary">
            The proposed card matches the standing card. Move a rate above to rehearse it against{' '}
            {count(baseline.accountsOnSchedule)} accounts of actual consumption.
          </p>
        </StateBlock>
      ) : (
        <>
          {/* ==== The headline ==== */}
          <div className="grid grid-cols-2 lg:grid-cols-4 gap-px bg-rule-solid border border-rule-solid">
            <Stat label="Bills up" sub={`${pct(impact.up)} of the class`}>
              {count(impact.up)}
            </Stat>
            <Stat label="Bills down" sub={`${pct(impact.down)} of the class`}>
              {count(impact.down)}
            </Stat>
            <Stat label="Median change" sub="Half the class moves less than this">
              <Money value={impact.medianDelta.toFixed(2)} />
            </Stat>
            <Stat label="Cycle revenue change" sub="This cycle only — see the note below">
              <Money value={impact.totalDelta.toFixed(2)} />
            </Stat>
          </div>

          {impact.breakEven !== null ? (
            <StateBlock tone="warning">
              <p className="text-data text-ink-primary">
                <strong className="font-semibold">
                  The break-even is {fmtTherms(impact.breakEven)}.
                </strong>{' '}
                Accounts below it pay more and accounts above it pay less, because the proposal moves
                recovery from volume onto the fixed charge. {pct(impact.down)} of the class —{' '}
                {count(impact.down)} accounts — sits above that line. This is the sentence a
                commission will ask you to say out loud, and it is not visible in an average.
              </p>
            </StateBlock>
          ) : null}

          {/* ==== The distribution ==== */}
          <Panel>
            <PanelHeader
              title="Distribution of bill impact"
              meta={`${count(baseline.accountsOnSchedule)} accounts · one cycle of actual volumes`}
            />
            <div className="px-4 py-4 space-y-1.5">
              {impact.buckets.map((b) => (
                <div key={b.label} className="flex items-center gap-3">
                  <span className="w-28 shrink-0 text-micro text-ink-secondary text-right">
                    {b.label}
                  </span>
                  <div className="flex-1 h-5 bg-surface-inset">
                    <div
                      className={`h-full ${
                        b.label.startsWith('down')
                          ? 'bg-exception-cleared-rail'
                          : b.label.startsWith('within')
                            ? 'bg-exception-snoozed-rail'
                            : 'bg-exception-warning-rail'
                      }`}
                      style={{ width: `${impact.peak ? (b.n / impact.peak) * 100 : 0}%` }}
                    />
                  </div>
                  <span className="w-20 shrink-0 figures text-data text-ink-primary">
                    {count(b.n)}
                  </span>
                  <span className="w-14 shrink-0 text-micro text-ink-tertiary text-right">
                    {pct(b.n)}
                  </span>
                </div>
              ))}
            </div>
          </Panel>

          {/* ==== By usage band ==== */}
          <Panel>
            <PanelHeader title="By usage band" meta="Median bill, before and after" />
            <Table caption="Bill impact by usage band">
              <thead>
                <HeadRow>
                  <Th>Band</Th>
                  <Th align="right">Accounts</Th>
                  <Th align="right">Median bill now</Th>
                  <Th align="right">Median proposed</Th>
                  <Th align="right">Median change</Th>
                  <Th>Direction</Th>
                </HeadRow>
              </thead>
              <tbody>
                {impact.bands.map((b) => (
                  <Row key={b.label}>
                    <Td>{b.label}</Td>
                    <Td align="right">
                      <span className="figures">{count(b.n)}</span>
                    </Td>
                    <Td align="right">
                      <Money value={b.medianBase.toFixed(2)} />
                    </Td>
                    <Td align="right">
                      <Money value={b.medianProp.toFixed(2)} />
                    </Td>
                    <Td align="right">
                      <Money value={b.medianDelta.toFixed(2)} />
                    </Td>
                    <Td>
                      <StateFlag
                        tone={b.medianDelta > 0.005 ? 'warning' : b.medianDelta < -0.005 ? 'cleared' : 'snoozed'}
                      >
                        {b.medianDelta > 0.005 ? 'Up' : b.medianDelta < -0.005 ? 'Down' : 'Flat'}
                      </StateFlag>
                    </Td>
                  </Row>
                ))}
              </tbody>
            </Table>
          </Panel>

          {/* ==== What the rehearsal checked ==== */}
          <Panel>
            <PanelHeader title="What the rehearsal checked" meta="Including the checks that found nothing" />
            <div className="divide-y divide-rule-hair">
              <Check
                tone={impact.zeroUsage !== 0 ? 'warning' : 'cleared'}
                title="Zero-usage accounts"
                finding={
                  impact.zeroUsage !== 0
                    ? `${count(population.filter((t) => t === 0).length)} accounts drew no gas this cycle and still move by ${money(impact.zeroUsage)}, because the change touches the fixed charge.`
                    : `${count(population.filter((t) => t === 0).length)} accounts drew no gas this cycle and are unaffected — every moved lever is volumetric.`
                }
              />
              <Check
                tone="cleared"
                title="Minimum bill"
                finding={
                  impact.floored > 0
                    ? `${count(impact.floored)} bills land on the ${money(currentCard.minimumBill)} floor under the proposal and stop tracking the rate.`
                    : `The ${money(currentCard.minimumBill)} floor binds on no account, in either card — the customer charge alone already exceeds it. Nothing is being masked by the minimum.`
                }
              />
              <Check
                tone="warning"
                title="Tax and franchise ride-along"
                finding={`The rate movement itself is ${money(impact.totalDelta - impact.taxDelta)}. Franchise fee and gas utility tax ride on top of it at 4.5%, adding ${money(impact.taxDelta)} and bringing what customers actually see to ${money(impact.totalDelta)}. The city's franchise revenue moves with the rate, which is a conversation to have before the filing rather than after.`}
              />
              <Check
                tone={effectiveFrom.endsWith('-01') ? 'cleared' : 'critical'}
                title="Effective date"
                finding={
                  effectiveFrom.endsWith('-01')
                    ? `${date(effectiveFrom)} is a month boundary, so no bill straddles the change.`
                    : `${date(effectiveFrom)} falls mid-month. Cycles crossing it bill in two sub-segments at two different cards, prorated by days — correct, but every one of those bills will draw a call.`
                }
              />
              <Check
                tone="info"
                title="Annual revenue"
                finding={`This is one winter cycle. Multiplying ${money(impact.totalDelta)} by twelve would overstate the annual figure badly, because residential gas volume is seasonal — an annual number against the ${money(authorised.annualRevenueRequirement)} authorised under ${authorised.docket} needs twelve cycles of actual volumes, and the sandbox will not fabricate them.`}
              />
            </div>
          </Panel>

          {/* ==== The gate ==== */}
          <Panel>
            <PanelHeader
              title="Commit"
              meta={`${moved.length} rate version${moved.length === 1 ? '' : 's'} will be created`}
            />
            <div className="px-4 py-4 grid grid-cols-1 md:grid-cols-3 gap-4">
              <div>
                <label htmlFor="eff" className="label-caps mb-1 block">
                  Effective from
                </label>
                <input
                  id="eff"
                  type="date"
                  value={effectiveFrom}
                  onChange={(e) => setEffectiveFrom(e.target.value)}
                  className="w-full rounded-xs border border-rule-solid bg-surface-raised px-2 py-1 text-data text-ink-primary"
                />
              </div>
              <div>
                <label htmlFor="docket" className="label-caps mb-1 block">
                  Regulatory reference
                </label>
                <input
                  id="docket"
                  value={docket}
                  onChange={(e) => setDocket(e.target.value)}
                  className="w-full rounded-xs border border-rule-solid bg-surface-raised px-2 py-1 text-data text-ink-primary"
                />
              </div>
              <div>
                <label htmlFor="reason" className="label-caps mb-1 block">
                  Change reason
                </label>
                <input
                  id="reason"
                  value={reason}
                  onChange={(e) => setReason(e.target.value)}
                  placeholder="Required — recorded on every version"
                  className="w-full rounded-xs border border-rule-solid bg-surface-raised px-2 py-1 text-data text-ink-primary placeholder:text-ink-muted"
                />
              </div>
            </div>
            <div className="px-4 pb-4 flex items-center justify-between gap-4">
              <p className="text-micro text-ink-secondary max-w-3xl">
                Committing closes the standing versions and inserts successors carrying{' '}
                <span className="ident">supersedes_id</span>, the reason and the citation. The old
                rows stay readable at their own coordinates, so every bill already issued still
                reproduces against the card that priced it.
              </p>
              <Button variant="primary" disabled={!committable}>
                Submit for approval
              </Button>
            </div>
            {!committable ? (
              <p className="px-4 pb-4 text-micro text-exception-warning-text">
                {moved.length === 0
                  ? 'Nothing has changed.'
                  : reason.trim().length < 12
                    ? 'A change reason of at least a dozen characters is required — it is what a regulator reads first.'
                    : 'A regulatory reference is required.'}
              </p>
            ) : null}
          </Panel>
        </>
      )}
    </div>
  )
}

const pct = (n: number) => `${((n / population.length) * 100).toFixed(1)}%`

function Fact({ label, hint, children }: { label: string; hint?: string; children: React.ReactNode }) {
  return (
    <div className="min-w-0">
      <dt className="label-caps mb-0.5">{label}</dt>
      <dd className="text-data text-ink-primary">{children}</dd>
      {hint ? <p className="text-micro text-ink-tertiary mt-0.5">{hint}</p> : null}
    </div>
  )
}

function Stat({
  label,
  sub,
  children,
}: {
  label: string
  sub: string
  children: React.ReactNode
}) {
  return (
    <div className="bg-surface-raised px-4 py-3">
      <p className="label-caps">{label}</p>
      <p className="text-figure text-ink-primary mt-1">{children}</p>
      <p className="text-micro text-ink-tertiary mt-0.5">{sub}</p>
    </div>
  )
}

function Check({
  tone,
  title,
  finding,
}: {
  tone: 'cleared' | 'warning' | 'critical' | 'info'
  title: string
  finding: string
}) {
  return (
    <div className="px-4 py-3 flex items-start gap-4">
      <span className="w-52 shrink-0">
        <StateFlag tone={tone}>{title}</StateFlag>
      </span>
      <p className="text-data text-ink-secondary">{finding}</p>
    </div>
  )
}
