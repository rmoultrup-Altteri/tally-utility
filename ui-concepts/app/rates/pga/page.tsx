import Link from 'next/link'
import type { Route } from 'next'
import { AppShell, PageHeader } from '@/components/shell/AppShell'
import { Button, Panel, PanelHeader } from '@/components/ui/Panel'
import { StateBlock, StateFlag, Rail, humanize } from '@/components/ui/State'
import { Table, HeadRow, Th, Row, Td, RailCell } from '@/components/table/Table'
import { Money } from '@/components/ui/Money'
import { PgaLattice } from '@/components/rates/PgaLattice'
import { pgaVersions, versionAsOf } from '@/fixtures/rates'
import { backfillExposure, exposureSample, filingLagDays } from '@/fixtures/pga'
import { asOf } from '@/fixtures/tenant'
import { correctionRun } from '@/fixtures/billing'
import { count, date, rate as fmtRate, stamp, therms } from '@/lib/format'

/**
 * The PGA console.
 *
 * The purchased gas adjustment is a pass-through: the utility earns nothing on
 * it and is obliged to bill exactly what it paid. That makes it the rate item
 * with the least discretion and the most audit exposure, and it is the one
 * that most often arrives late — gas costs settle after the month they apply
 * to, so the filing chases the service period rather than leading it.
 *
 * Everything on this screen exists to answer one question an operator asks in
 * two different moods: "what is the factor" on a calm day, and "what did we
 * think the factor was when we billed this" on a bad one.
 */

export default function PgaConsolePage() {
  const standing = versionAsOf(pgaVersions, asOf.validAt, asOf.recordedAt)
  const scheduled = pgaVersions.filter((v) => v.effective_from > asOf.validAt)
  const lags = pgaVersions.map(filingLagDays)
  const ahead = lags.filter((d) => d < 0)
  const medianLead = median(ahead.map(Math.abs))
  const worst = Math.max(...lags)

  return (
    <AppShell current="PGA console">
      <PageHeader
        title="PGA console"
        meta={
          <>
            PGA-GAS · purchased gas adjustment · pass-through, no markup ·{' '}
            <Link href={'/rates' as Route} className="underline hover:text-ink-secondary">
              All rate items
            </Link>
          </>
        }
        actions={
          <>
            <Button>Export filing history</Button>
            <Button variant="primary">File a factor</Button>
          </>
        }
      />

      <div className="flex-1 overflow-auto">
        <div className="px-5 py-5 space-y-5">
          {/* ==== The four numbers worth reading before anything else ==== */}
          <div className="grid grid-cols-2 lg:grid-cols-4 gap-px bg-rule-solid border border-rule-solid">
            <Stat label="Standing factor" sub={`at ${date(asOf.validAt)}`}>
              <span className="ident text-figure text-ink-primary">
                {standing ? fmtRate(standing.rate) : '—'}
              </span>
            </Stat>
            <Stat
              label="Next scheduled"
              sub={
                scheduled.length
                  ? `from ${date(scheduled[0].effective_from)} · not yet pricing`
                  : 'none filed'
              }
            >
              <span className="ident text-figure text-ink-tertiary">
                {scheduled.length ? fmtRate(scheduled[0].rate) : '—'}
              </span>
            </Stat>
            <Stat
              label="Filing discipline"
              sub={`${ahead.length} of ${lags.length} filed ahead, median ${medianLead} days`}
            >
              <span className="text-figure text-exception-warning-text">
                {worst > 0 ? `+${worst}d` : `${worst}d`}
              </span>
            </Stat>
            <Stat
              label="Unrepriced exposure"
              sub={`${count(backfillExposure.remainingBills)} of ${count(backfillExposure.billsIssued)} bills await rebill`}
            >
              <span className="text-figure text-ink-primary">
                <Money value={backfillExposure.remainingCredit} />
              </span>
            </Stat>
          </div>

          {/* ==== The lattice ==== */}
          <Panel>
            <PanelHeader
              title="Factor by service month and recorded instant"
              meta="Valid time across, transaction time down"
              actions={
                <span className="text-micro text-ink-tertiary">
                  Select any cell to resolve that coordinate
                </span>
              }
            />
            <PgaLattice />
          </Panel>

          <StateBlock tone="warning">
            <p className="text-data text-ink-primary">
              <strong className="font-semibold">Read down the January column.</strong> The factor
              appears two rows below where the staircase puts every other month, because Gas Supply
              recorded it 46 days after the period opened. The cells above it are not stale values —
              they are empty. Nothing was knowable there, and 412 bills were issued out of that
              emptiness anyway.
            </p>
          </StateBlock>

          {/* ==== What the late filing actually costs ==== */}
          <Panel>
            <PanelHeader
              title="Late filing exposure"
              meta={`${backfillExposure.servicePeriod} · recorded ${stamp(backfillExposure.recordedAt)}`}
              actions={<Button variant="primary">Queue correction run</Button>}
            />
            <div className="grid grid-cols-2 md:grid-cols-5 gap-x-6 gap-y-4 px-4 py-4 border-b border-rule-hair">
              <Exposure label="Billed at">{fmtRate(backfillExposure.billedFactor)}</Exposure>
              <Exposure label="Should have been">{fmtRate(backfillExposure.filedFactor)}</Exposure>
              <Exposure label="Overcharge per therm">
                {fmtRate(backfillExposure.deltaFactor)}
              </Exposure>
              <Exposure label="Therms affected">{therms(backfillExposure.therms)}</Exposure>
              <Exposure label="Credit owed" hint="gas + franchise fee">
                <Money value={backfillExposure.totalCredit} />
              </Exposure>
            </div>
            <p className="px-4 py-3 text-micro text-ink-secondary border-b border-rule-hair">
              All {count(backfillExposure.billsOverThreshold)} bills exceed the{' '}
              <Money value={backfillExposure.thresholdAmount} /> de-minimis threshold, so every one
              requires void-and-rebill rather than a carried adjustment. The correction run elects{' '}
              <span className="text-ink-primary">
                {humanize(correctionRun.correction_rate_mode ?? '')}
              </span>{' '}
              rate dates — it reprices January in January&rsquo;s world, not today&rsquo;s.
            </p>
            <Table caption="Bills priced against the superseded factor">
              <thead>
                <HeadRow>
                  <Th width="3px"> </Th>
                  <Th>Account</Th>
                  <Th>Original</Th>
                  <Th align="right">Therms</Th>
                  <Th align="right">Billed</Th>
                  <Th>Rebill</Th>
                  <Th align="right">Rebilled</Th>
                  <Th align="right">Credit</Th>
                  <Th>Status</Th>
                </HeadRow>
              </thead>
              <tbody>
                <Row>
                  <RailCell>
                    <Rail tone="approved" />
                  </RailCell>
                  <Td>{exposureSample.accountName}</Td>
                  <Td>
                    <Link
                      href={`/invoices/${exposureSample.invoiceId}` as Route}
                      className="ident struck hover:text-ink-secondary"
                    >
                      {exposureSample.invoiceNumber}
                    </Link>
                  </Td>
                  <Td align="right">
                    <span className="figures">{therms(exposureSample.therms)}</span>
                  </Td>
                  <Td align="right">
                    <Money value={exposureSample.billedAmount} />
                  </Td>
                  <Td>
                    <Link
                      href={`/invoices/${exposureSample.rebillId}/diff` as Route}
                      className="ident text-accent-text hover:underline"
                    >
                      {exposureSample.rebillNumber}
                    </Link>
                  </Td>
                  <Td align="right">
                    <Money value={exposureSample.rebillAmount} />
                  </Td>
                  <Td align="right">
                    <Money value={`-${exposureSample.credit}`} />
                  </Td>
                  <Td>
                    <StateFlag tone="approved">Rebilled</StateFlag>
                  </Td>
                </Row>
                <Row muted>
                  <RailCell>
                    <Rail tone="pending" />
                  </RailCell>
                  <Td colSpan={8}>
                    <span className="text-micro text-ink-secondary">
                      {count(backfillExposure.remainingBills)} further bills in this exposure are queued
                      and not yet repriced. Only the account above is modelled line-by-line in this
                      prototype.
                    </span>
                  </Td>
                </Row>
              </tbody>
            </Table>
          </Panel>

          {/* ==== Filing history, read as discipline rather than values ==== */}
          <Panel>
            <PanelHeader
              title="Filing history"
              meta="How far ahead of its period each factor was recorded"
            />
            <Table caption="Purchased gas adjustment filings and their recording lag">
              <thead>
                <HeadRow>
                  <Th width="3px"> </Th>
                  <Th>Service period</Th>
                  <Th align="right">Factor</Th>
                  <Th>Recorded</Th>
                  <Th align="right">Lag</Th>
                  <Th>Change</Th>
                  <Th>Citation</Th>
                  <Th>By</Th>
                </HeadRow>
              </thead>
              <tbody>
                {[...pgaVersions].reverse().map((v) => {
                  const lag = filingLagDays(v)
                  const late = lag > 0
                  return (
                    <Row key={v.id}>
                      <RailCell>
                        <Rail tone={late ? 'failed' : 'approved'} />
                      </RailCell>
                      <Td>
                        {date(v.effective_from)} →{' '}
                        {v.effective_to ? (
                          date(v.effective_to)
                        ) : (
                          <span className="text-ink-tertiary">open</span>
                        )}
                      </Td>
                      <Td align="right">
                        <span className="ident">{fmtRate(v.rate)}</span>
                      </Td>
                      <Td>
                        <span className={`text-micro ${late ? 'text-exception-warning-text' : 'text-ink-secondary'}`}>
                          {stamp(v.recorded_from)}
                        </span>
                      </Td>
                      <Td align="right">
                        <span
                          className={`figures ${late ? 'text-exception-critical-text font-medium' : 'text-ink-secondary'}`}
                        >
                          {late ? `${lag} days late` : `${Math.abs(lag)} days ahead`}
                        </span>
                      </Td>
                      <Td>
                        <StateFlag tone={late ? 'warning' : 'cleared'}>
                          {humanize(v.change_type)}
                        </StateFlag>
                      </Td>
                      <Td>
                        <span className="ident text-ink-secondary">{v.regulatory_reference}</span>
                      </Td>
                      <Td>
                        <span className="text-micro text-ink-tertiary">{v.changed_by}</span>
                      </Td>
                    </Row>
                  )
                })}
              </tbody>
            </Table>
          </Panel>
        </div>
      </div>
    </AppShell>
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
      <p className="mt-1">{children}</p>
      <p className="text-micro text-ink-tertiary mt-0.5">{sub}</p>
    </div>
  )
}

function Exposure({
  label,
  hint,
  children,
}: {
  label: string
  hint?: string
  children: React.ReactNode
}) {
  return (
    <div className="min-w-0">
      <p className="label-caps mb-0.5">{label}</p>
      <p className="ident text-data text-ink-primary">{children}</p>
      {hint ? <p className="text-micro text-ink-tertiary mt-0.5">{hint}</p> : null}
    </div>
  )
}

function median(values: number[]): number {
  if (values.length === 0) return 0
  const sorted = [...values].sort((a, b) => a - b)
  const mid = Math.floor(sorted.length / 2)
  return sorted.length % 2 === 0 ? Math.round((sorted[mid - 1] + sorted[mid]) / 2) : sorted[mid]
}
