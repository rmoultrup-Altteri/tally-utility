import Link from 'next/link'
import { AppShell, PageHeader } from '@/components/shell/AppShell'
import { Button, Field, FieldGrid, Panel, PanelHeader } from '@/components/ui/Panel'
import { StateBlock, StateFlag, humanize } from '@/components/ui/State'
import { Table, HeadRow, Th, Row, Td, RailCell } from '@/components/table/Table'
import { Rail } from '@/components/ui/State'
import { RateItemsEditor } from '@/components/rates/RateItemsEditor'
import { g1Items, pgaVersions, priorVersions, r1Items, rateSchedules, versionAsOf } from '@/fixtures/rates'
import { invoices, linesByInvoiceId } from '@/fixtures/billing'
import { asOf, currentUser } from '@/fixtures/tenant'
import type { RateItemVersion } from '@/schemas/models'
import type { BilledRates, CatalogItem } from '@/lib/rate-changes'
import { date, money, rate as fmtRate, stamp } from '@/lib/format'

/**
 * Rates and tariffs.
 *
 * The screen that has to make "change your own rates" credible. Reference data
 * is close-then-insert, so this is a version timeline rather than an edit form:
 * every value on it is a row that was recorded at an instant, by a person, for
 * a stated reason, against a regulatory citation.
 *
 * Future segments are outlined, never filled. A scheduled rate is not an active
 * rate, and conflating the two is how next month's PGA gets billed today.
 */

/**
 * Items every class pays on the same row. The franchise fees follow the
 * premise's city, not the schedule, so they apply wherever the premise is in town.
 */
const CLASS_INDEPENDENT = ['PGA-GAS', 'PSF-TX', 'GRIP-2025', 'FRAN-BRYAN', 'FRAN-CSTAT']

/** One row per item code, carrying its whole version chain and the schedules that bill it. */
function catalog(): CatalogItem[] {
  const all = [...pgaVersions, ...r1Items, ...g1Items, ...priorVersions]
  const byCode = new Map<string, RateItemVersion[]>()
  for (const v of all) {
    const chain = byCode.get(v.item_code) ?? []
    if (!chain.some((x) => x.id === v.id)) chain.push(v)
    byCode.set(v.item_code, chain)
  }
  return [...byCode.entries()].map(([code, versions]) => {
    const latest = versions.reduce((a, v) => (v.effective_from > a.effective_from ? v : a))
    const on = new Set<string>()
    if (r1Items.some((v) => v.item_code === code)) on.add('R-1')
    if (g1Items.some((v) => v.item_code === code)) on.add('G-1')
    if (CLASS_INDEPENDENT.includes(code)) ['R-1', 'G-1'].forEach((s) => on.add(s))
    return {
      key: code,
      code,
      name: latest.item_name,
      group: latest.display_group,
      calculation: latest.calculation_type,
      unit: latest.rate_unit,
      schedules: rateSchedules.map((s) => s.code).filter((s) => on.has(s)),
      versions,
    }
  })
}

/** Every rate a non-void bill carried, by item and the month its service period ends. */
function billedRates(): BilledRates {
  const out: BilledRates = {}
  for (const inv of invoices) {
    if (inv.status === 'void') continue
    const month = inv.period_end.slice(0, 7)
    for (const l of linesByInvoiceId(inv.id)) {
      if (!l.rate_item_code || l.rate === null) continue
      const cell = ((out[l.rate_item_code] ??= {})[month] ??= [])
      const hit = cell.find((c) => c.rate === l.rate)
      if (hit) hit.bills += 1
      else cell.push({ rate: l.rate, bills: 1 })
    }
  }
  return out
}

export default function RatesPage() {
  const standing = versionAsOf(pgaVersions, asOf.validAt, asOf.recordedAt)

  return (
    <AppShell current="Rates & tariffs">
      <PageHeader
        title="Rates &amp; tariffs"
        meta={`${rateSchedules.map((s) => s.code).join(' · ')} · RRC tariff GUD-10928`}
        actions={
          <>
            <Link href="/rates/sandbox">
              <Button>Rehearse against last cycle</Button>
            </Link>
          </>
        }
      />

      <div className="flex-1 overflow-auto">
        <div className="px-5 py-5 space-y-5">
          {/* ==== Where rates are changed ==== */}
          <RateItemsEditor
            catalog={catalog()}
            schedules={rateSchedules.map((s) => s.code)}
            billed={billedRates()}
            at={{ validAt: asOf.validAt, recordedAt: asOf.recordedAt }}
            by={currentUser.name}
          />

          {/* The bi-temporal lesson, told with a real row. */}
          <StateBlock tone="info">
            <p className="text-data text-ink-primary">
              <strong className="font-semibold">
                The January 2026 PGA factor was recorded six weeks late.
              </strong>{' '}
              Bills issued for January before 16 Feb used the December factor and were correct when
              computed. That is why INV-2026-01-004913 was voided and rebilled rather than quietly
              edited — the arithmetic was never wrong, the world it ran in was.
            </p>
          </StateBlock>

          <Panel>
            <PanelHeader
              title="Purchased gas adjustment"
              meta="PGA-GAS · per therm · pass-through, no markup"
              actions={
                <>
                  {standing ? (
                    <span className="text-data text-ink-secondary">
                      Standing at {date(asOf.validAt)}:{' '}
                      <span className="figures text-ink-primary font-medium">
                        {fmtRate(standing.rate)}
                      </span>
                    </span>
                  ) : null}
                  <Link href="/rates/pga" className="text-data text-accent-text hover:underline">
                    Open PGA console
                  </Link>
                </>
              }
            />
            <Timeline versions={pgaVersions} standingId={standing?.id} />
          </Panel>

          <Panel>
            <PanelHeader
              title="Version history"
              meta="Nothing is edited in place; nothing is deleted"
            />
            <Table caption="Every recorded version of the purchased gas adjustment">
              <thead>
                <HeadRow>
                  <Th width="3px"> </Th>
                  <Th>Valid from</Th>
                  <Th>Valid to</Th>
                  <Th align="right">Rate</Th>
                  <Th align="right">Change</Th>
                  <Th>Recorded</Th>
                  <Th>Type</Th>
                  <Th>Reason</Th>
                  <Th>Citation</Th>
                  <Th>By</Th>
                </HeadRow>
              </thead>
              <tbody>
                {[...pgaVersions].reverse().map((v, i, arr) => {
                  const prior = arr[i + 1]
                  const future = v.effective_from > asOf.validAt
                  const standingNow = v.id === standing?.id
                  const late = v.change_type === 'backfill'
                  return (
                    <Row key={v.id} selected={standingNow} muted={future}>
                      <RailCell>
                        <Rail tone={late ? 'warning' : standingNow ? 'approved' : future ? 'draft' : 'superseded'} />
                      </RailCell>
                      <Td>{date(v.effective_from)}</Td>
                      <Td>
                        {v.effective_to ? (
                          date(v.effective_to)
                        ) : (
                          <span className="text-ink-tertiary">open</span>
                        )}
                      </Td>
                      <Td align="right">
                        <span className="figures text-ink-primary">{fmtRate(v.rate)}</span>
                      </Td>
                      <Td align="right">
                        {prior ? (
                          <Delta from={prior.rate} to={v.rate} />
                        ) : (
                          <span className="text-ink-tertiary">—</span>
                        )}
                      </Td>
                      <Td>
                        <span
                          className={`text-micro ${late ? 'text-exception-warning-text' : 'text-ink-secondary'}`}
                          title={late ? 'Recorded after the period it applies to' : undefined}
                        >
                          {stamp(v.recorded_from)}
                        </span>
                      </Td>
                      <Td>
                        <StateFlag tone={late ? 'warning' : 'cleared'}>
                          {humanize(v.change_type)}
                        </StateFlag>
                      </Td>
                      <Td className="max-w-72">
                        <span className="text-micro text-ink-secondary">{v.change_reason}</span>
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

          <Panel>
            <PanelHeader title="Schedules" meta="Every schedule is date-effective" />
            <div className="px-4 py-4 grid grid-cols-1 md:grid-cols-3 gap-5">
              {rateSchedules.map((s) => (
                <div key={s.id} className="border border-rule-hair px-3 py-3">
                  <p className="ident text-data text-ink-primary">{s.code}</p>
                  <p className="text-data text-ink-secondary mt-0.5">{s.name}</p>
                  <FieldGrid cols={2}>
                    <Field label="Minimum bill">{s.minimum_bill_amount ? money(s.minimum_bill_amount) : '—'}</Field>
                    <Field label="Partial period">{humanize(s.partial_period_policy ?? '')}</Field>
                  </FieldGrid>
                </div>
              ))}
            </div>
          </Panel>
        </div>
      </div>
    </AppShell>
  )
}

/**
 * The version band. Segments are proportional to their span but hold a minimum
 * width, so a one-day PGA correction stays clickable.
 */
function Timeline({
  versions,
  standingId,
}: {
  versions: RateItemVersion[]
  standingId?: string
}) {
  return (
    <div className="px-4 py-5">
      <div className="flex gap-px">
        {versions.map((v) => {
          const future = v.effective_from > asOf.validAt
          const standing = v.id === standingId
          return (
            <div key={v.id} className="flex-1 min-w-20">
              <div
                className={`h-9 border ${
                  future
                    ? 'border-dashed border-state-draft-rail bg-transparent'
                    : standing
                      ? 'border-state-approved-rail bg-exception-cleared-wash'
                      : 'border-rule-solid bg-surface-inset'
                }`}
                title={`${date(v.effective_from)} → ${v.effective_to ? date(v.effective_to) : 'open'}`}
              >
                <div className="flex h-full items-center justify-center">
                  <span
                    className={`figures text-data ${
                      future ? 'text-ink-tertiary' : standing ? 'text-ink-primary font-medium' : 'text-ink-secondary'
                    }`}
                  >
                    {fmtRate(v.rate)}
                  </span>
                </div>
              </div>
              <p className="text-micro text-ink-tertiary mt-1 text-center">
                {new Date(`${v.effective_from}T00:00:00Z`).toLocaleDateString('en-US', {
                  month: 'short',
                  year: '2-digit',
                  timeZone: 'UTC',
                })}
              </p>
            </div>
          )
        })}
      </div>
      <p className="text-micro text-ink-tertiary mt-3">
        Filled segments are in effect. Outlined segments are scheduled and not yet active — a
        scheduled rate is never used to price a bill.
      </p>
    </div>
  )
}

function Delta({ from, to }: { from: string; to: string }) {
  const diff = Number(to) - Number(from)
  const up = diff > 0
  return (
    <span className={`figures ${up ? 'text-exception-warning-text' : 'text-money-credit'}`}>
      {up ? '+' : '−'}
      {fmtRate(String(Math.abs(diff))).replace('$', '')}
    </span>
  )
}
