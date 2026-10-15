import Link from 'next/link'
import type { Route } from 'next'
import { AppShell, PageHeader } from '@/components/shell/AppShell'
import { Button, Field, FieldGrid, Panel, PanelHeader } from '@/components/ui/Panel'
import { StateBlock, StateFlag, humanize } from '@/components/ui/State'
import { ColumnTable, type ColumnDef } from '@/components/table/Columns'
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

/**
 * The PGA's version history. The rail stays pinned; the last three are off
 * until an operator adds them — the ids an auditor quotes, and when each
 * record stopped being what the system believed.
 */
const VERSION_COLUMNS: ColumnDef[] = [
  { key: 'rail', label: '', menuLabel: 'Status rail', width: '3px', fixed: true, rail: true },
  { key: 'validFrom', label: 'Valid from' },
  { key: 'validTo', label: 'Valid to' },
  { key: 'rate', label: 'Rate', align: 'right' },
  { key: 'change', label: 'Change', align: 'right' },
  { key: 'recorded', label: 'Recorded' },
  { key: 'type', label: 'Type' },
  { key: 'reason', label: 'Reason', cellClassName: 'max-w-72' },
  { key: 'citation', label: 'Citation' },
  { key: 'by', label: 'By' },
  { key: 'id', label: 'Version ID', hidden: true },
  { key: 'supersedes', label: 'Supersedes', hidden: true },
  { key: 'recordedUntil', label: 'Recorded until', hidden: true },
]

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
            <Link href={'/rates/rate-case' as Route}>
              <Button>Rate case toolkit</Button>
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
            <ColumnTable
              listId="rates"
              caption="Every recorded version of the purchased gas adjustment"
              columns={VERSION_COLUMNS}
              rows={[...pgaVersions].reverse().map((v, i, arr) => {
                const prior = arr[i + 1]
                const future = v.effective_from > asOf.validAt
                const standingNow = v.id === standing?.id
                const late = v.change_type === 'backfill'
                return {
                  key: v.id,
                  selected: standingNow,
                  muted: future,
                  cells: {
                    rail: <Rail tone={late ? 'warning' : standingNow ? 'approved' : future ? 'draft' : 'superseded'} />,
                    validFrom: date(v.effective_from),
                    validTo: v.effective_to ? date(v.effective_to) : <span className="text-ink-tertiary">open</span>,
                    rate: <span className="figures text-ink-primary">{fmtRate(v.rate)}</span>,
                    change: prior ? <Delta from={prior.rate} to={v.rate} /> : <span className="text-ink-tertiary">—</span>,
                    recorded: (
                      <span
                        className={`text-micro ${late ? 'text-exception-warning-text' : 'text-ink-secondary'}`}
                        title={late ? 'Recorded after the period it applies to' : undefined}
                      >
                        {stamp(v.recorded_from)}
                      </span>
                    ),
                    type: <StateFlag tone={late ? 'warning' : 'cleared'}>{humanize(v.change_type)}</StateFlag>,
                    reason: <span className="text-micro text-ink-secondary">{v.change_reason}</span>,
                    citation: <span className="ident text-ink-secondary">{v.regulatory_reference}</span>,
                    by: <span className="text-micro text-ink-tertiary">{v.changed_by}</span>,
                    id: <span className="ident text-micro text-ink-tertiary">{v.id}</span>,
                    supersedes: v.supersedes_id ? (
                      <span className="ident text-micro text-ink-secondary">{v.supersedes_id}</span>
                    ) : (
                      <span className="text-ink-tertiary">—</span>
                    ),
                    recordedUntil: v.recorded_until ? (
                      <span className="text-micro text-ink-secondary">{stamp(v.recorded_until)}</span>
                    ) : (
                      <span className="text-micro text-ink-tertiary">still current</span>
                    ),
                  },
                }
              })}
            />
          </Panel>

          <Panel>
            <PanelHeader title="Schedules" meta="Every schedule is date-effective" />
            <div className="px-4 py-4 grid grid-cols-1 md:grid-cols-3 gap-5">
              {rateSchedules.map((s) => (
                <div key={s.id} id={`schedule-${s.code}`} className="scroll-mt-4 rounded-sm border border-rule-hair px-3 py-3">
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
