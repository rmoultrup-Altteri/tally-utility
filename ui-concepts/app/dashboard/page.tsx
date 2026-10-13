import Link from 'next/link'
import type { Route } from 'next'
import { AppShell, PageHeader } from '@/components/shell/AppShell'
import { Button, Panel, PanelHeader } from '@/components/ui/Panel'
import { StateBlock, StateFlag, toneRail } from '@/components/ui/State'
import type { Tone } from '@/components/ui/State'
import { Money } from '@/components/ui/Money'
import { arAging, currentRun, portlets, rateCard, revenue } from '@/fixtures/billing'
import { blockingCount, openExceptions } from '@/fixtures/exceptions'
import { evaluate, worklist } from '@/fixtures/collections'
import { transfersNeedingAttention } from '@/lib/transfers'
import type { PortletRow, RateCardRow } from '@/fixtures/billing'
import { asOf, cycle, tenant } from '@/fixtures/tenant'
import { count, date, money, rateInUnit, stamp } from '@/lib/format'
import { rateUnitLabel } from '@/lib/vocabulary'

/**
 * Billing operations dashboard.
 *
 * Built to the locked composition (T8-4 … T8-8). Four elements, in this order:
 * severity portlets placed by item type, a revenue pair with no ratio between
 * the figures, an AR aging strip aged by invoice, and a tariff rate card strip
 * showing what the last posted run actually billed at.
 *
 * The rate card is the load-bearing one. It reads as-billed values rather than
 * live configuration, because those are different datasets that agree only if
 * nothing changed since the run posted — and for a gas tenant they routinely
 * will not.
 */

const TIER_TONE: Record<string, Tone> = {
  Critical: 'critical',
  Medium: 'warning',
  Low: 'info',
}

export default function DashboardPage() {
  return (
    <AppShell current="Dashboard">
      <PageHeader
        title="Billing operations"
        meta={
          <>
            {tenant.name} · {count(tenant.meters)} meters · as of {stamp(asOf.recordedAt)}
          </>
        }
        actions={<Button>Configure portlets</Button>}
      />

      <div className="flex-1 overflow-auto">
        <div className="px-5 py-5 space-y-5">
          <CycleStatus />
          {/* T8-4 — placement by item type, six rows plus a "+N more". */}
          <div className="grid grid-cols-1 lg:grid-cols-3 gap-5">
            {portlets.map((p) => (
              <Panel key={p.tier}>
                <PanelHeader
                  title={
                    <span className="flex items-center gap-2">
                      <span className={`inline-block h-3 w-rail ${railFor(p.tier)}`} aria-hidden />
                      {p.tier}
                    </span>
                  }
                  meta={
                    <Link
                      href={`/dashboard/items?tier=${p.tier}` as Route}
                      className="text-accent-text hover:text-accent-text-hover underline"
                    >
                      {count(p.rows.reduce((n, r) => n + r.count, 0))} items
                    </Link>
                  }
                />
                <ul className="divide-y divide-rule-hair">
                  {p.rows.map((row) => (
                    <PortletLine key={row.itemType} row={row} />
                  ))}
                  {p.more > 0 ? (
                    <li className="px-4 py-1.5">
                      <Link
                        href={`/dashboard/items?tier=${p.tier}` as Route}
                        className="text-micro text-accent-text hover:text-accent-text-hover underline"
                      >
                        +{p.more} more types
                      </Link>
                    </li>
                  ) : null}
                </ul>
              </Panel>
            ))}
          </div>

          <div className="grid grid-cols-1 lg:grid-cols-2 gap-5">
            {/* T8-5 — two figures, a prior-month comparator, and no ratio. */}
            <Panel>
              <PanelHeader title="Revenue" meta={revenue.windowLabel} />
              <div className="grid grid-cols-1 sm:grid-cols-2 divide-y sm:divide-y-0 sm:divide-x divide-rule-solid">
                <RevenueFigure
                  label="Billed, net of voids"
                  value={revenue.billedNetOfVoids}
                  prior={revenue.billedPriorMonthSameDay}
                  note={`Posted runs only — ${currentRun.run_number} counts once it posts. Voids subtract at their void date, so closed months never restate.`}
                />
                <RevenueFigure
                  label="Collected"
                  value={revenue.collected}
                  prior={revenue.collectedPriorMonthSameDay}
                  note="Posting date. Mostly against last month's invoices."
                />
              </div>
              <div className="border-t border-rule-hair px-4 py-2.5">
                <p className="text-micro text-ink-tertiary">
                  No percentage is shown between these two. They are not a collection rate — the
                  payments arriving this month are largely against last month&rsquo;s bills, and any
                  ratio here would be read as one.
                </p>
              </div>
            </Panel>

            {/* T8-6 / T8-7 — aged by invoice; buckets must sum to the drilldowns. */}
            <Panel>
              <PanelHeader
                title="Accounts receivable"
                meta={`Aged by invoice · ${money(String(arAging.reduce((a, b) => a + Number(b.amount), 0)))} open`}
              />
              <div className="@container">
                <div className="grid grid-cols-2 @[30rem]:grid-cols-4 gap-px bg-rule-hair">
                  {arAging.map((b) => {
                    const flagged = b.bucket === '90+ days'
                    return (
                      <Link
                        key={b.bucket}
                        href="/reports/ar_aging"
                        title={`Open the AR aging report — ${b.bucket} by customer type, each line drilling to its invoices`}
                        className={`block min-w-0 px-3 py-3 transition-colors duration-fast hover:bg-surface-sunken ${
                          flagged ? 'bg-exception-critical-wash' : 'bg-surface-raised'
                        }`}
                      >
                        <p className="field-label">{b.bucket}</p>
                        <p
                          className={`text-h3 @[36rem]:text-h2 mt-1 figures whitespace-nowrap ${
                            flagged ? 'text-exception-critical-text' : 'text-ink-primary'
                          }`}
                        >
                          {money(b.amount)}
                        </p>
                        <p className="text-micro text-ink-tertiary mt-0.5">
                          {count(b.accounts)} accounts
                        </p>
                      </Link>
                    )
                  })}
                </div>
              </div>
              <div className="border-t border-rule-hair px-4 py-2.5">
                <p className="text-micro text-ink-tertiary">
                  A customer with unpaid bills of different ages appears in more than one bucket. Each
                  bucket opens the AR aging report, where every line drills to its invoices and sums
                  back to it — the same figures Collections shows.
                </p>
              </div>
            </Panel>
          </div>

          {/* T8-8 — as-billed, with drift. The point of the tile. */}
          <Panel>
            <PanelHeader
              title="Tariff rate card"
              meta={`${rateCard.scheduleCode} · ${rateCard.scheduleName} · as billed on ${rateCard.lastPostedRun}`}
              actions={
                <Link
                  href="/rates"
                  className="inline-flex items-center h-8 px-3.5 rounded-sm border border-rule-solid bg-surface-raised text-data font-medium text-ink-primary hover:bg-surface-sunken hover:border-rule-heavy transition-colors duration-fast"
                >
                  Full rate card
                </Link>
              }
            />
            <div className="overflow-x-auto">
              <table className="w-full text-data">
                <caption className="sr-only">
                  Rates the last posted run actually billed at, with drift against the current
                  effective rate
                </caption>
                <thead>
                  <tr className="border-b border-rule-heavy">
                    <th className="field-label px-cell-x py-1.5 text-left">Charge</th>
                    <th className="field-label px-cell-x py-1.5 text-right">As billed</th>
                    <th className="field-label px-cell-x py-1.5 text-right border-l border-rule-solid">
                      Current effective
                    </th>
                    <th className="field-label px-cell-x py-1.5 text-left">Drift</th>
                  </tr>
                </thead>
                <tbody>
                  {rateCard.rows.map((row) => (
                    <RateCardLine key={row.itemCode} row={row} />
                  ))}
                </tbody>
              </table>
            </div>
            <div className="border-t border-rule-hair px-4 py-2.5">
              <p className="text-micro text-ink-secondary leading-relaxed">
                These are the rates the last posted run <em>used</em>, read from the bill lines
                themselves — not from current configuration. The two agree only while nothing has
                changed since the run posted, and PGA and WNA reload monthly. A drift marker is not a
                warning about this tile; it is a correction-run trigger.
              </p>
            </div>
          </Panel>
        </div>
      </div>
    </AppShell>
  )
}

/**
 * What stands between today and the cycle closing, each linked to where it is
 * worked. Not a portlet — the portlets below count items by type; this says
 * whether the run can post and what else is waiting on a person.
 */
function CycleStatus() {
  const eligible = worklist.filter((w) => evaluate(w).eligible).length
  const transfers = transfersNeedingAttention()
  const blocked = blockingCount > 0
  const items: { label: string; value: string; href: string; tone: Tone }[] = [
    {
      label: `${currentRun.run_number} · ${STATE_WORD[currentRun.status] ?? currentRun.status}`,
      value: blocked ? `${blockingCount} exceptions block posting` : 'Clear to post',
      href: '/',
      tone: blocked ? 'critical' : 'cleared',
    },
    { label: 'Open exceptions', value: `${openExceptions.length} on the queue`, href: '/', tone: 'info' },
    { label: 'Transfers of service', value: transfers ? `${transfers} need a decision` : 'None waiting', href: '/transfers', tone: transfers ? 'warning' : 'cleared' },
    { label: 'Disconnects', value: `${eligible} eligible today`, href: '/collections', tone: 'info' },
  ]
  return (
    <StateBlock tone={blocked ? 'warning' : 'cleared'} className="!px-0 !py-0">
      <div className="flex flex-wrap items-stretch">
        <div className="px-4 py-2.5 min-w-[12rem]">
          <p className="field-label">{cycle.label} · {cycle.periodLabel}</p>
          <p className="text-data text-ink-primary mt-0.5">Bills dated {date(cycle.billDate)}</p>
        </div>
        {items.map((i) => (
          <Link
            key={i.label}
            href={i.href as Route}
            className="flex-1 min-w-[11rem] border-l border-rule-hair px-4 py-2.5 hover:bg-surface-raised/60 transition-colors duration-fast"
          >
            <p className="field-label">{i.label}</p>
            <p className="mt-0.5 flex items-center gap-1.5 text-data text-ink-primary">
              <span aria-hidden className={`inline-block h-1.5 w-1.5 rounded-full ${toneRail(i.tone)}`} />
              {i.value}
            </p>
          </Link>
        ))}
      </div>
    </StateBlock>
  )
}

const STATE_WORD: Record<string, string> = { review: 'in review', in_progress: 'running', approved: 'approved', posted: 'posted' }

function railFor(tier: string): string {
  return tier === 'Critical'
    ? 'bg-exception-critical-rail'
    : tier === 'Medium'
      ? 'bg-exception-warning-rail'
      : 'bg-exception-info-rail'
}

function PortletLine({ row }: { row: PortletRow }) {
  const empty = row.count === 0
  return (
    <li>
      <Link
        href={`/dashboard/items?type=${row.itemType}` as Route}
        className={`flex items-baseline justify-between gap-3 px-4 py-1.5 hover:bg-surface-sunken transition-colors duration-fast ${
          empty ? 'opacity-45' : ''
        }`}
      >
        <span className="text-data text-ink-primary">{row.label}</span>
        <span className="figures text-data text-ink-primary">{row.count}</span>
      </Link>
    </li>
  )
}

function RevenueFigure({
  label,
  value,
  prior,
  note,
}: {
  label: string
  value: string
  prior: string
  note: string
}) {
  const delta = Number(value) - Number(prior)
  /* The figure steps down a size when its half of the panel is narrow, rather than spilling over the rule. */
  return (
    <div className="@container min-w-0 px-4 py-3">
      <p className="field-label">{label}</p>
      <p className="text-h1 @[15rem]:text-figure mt-1 figures text-ink-primary whitespace-nowrap">{money(value)}</p>
      <p className="text-micro text-ink-tertiary mt-0.5">
        {delta >= 0 ? '▲' : '▼'} {money(String(Math.abs(delta)))} vs prior month, same day
      </p>
      <p className="text-micro text-ink-tertiary mt-1.5 leading-relaxed">{note}</p>
    </div>
  )
}

function RateCardLine({ row }: { row: RateCardRow }) {
  /* A tiered item holds its brackets in tier_config and has no single rate, so
     the row reads as a bracket count that links through to the full card. */
  if (row.brackets) {
    return (
      <tr className="border-b border-rule-hair bg-surface-raised">
        <td className="px-cell-x py-cell-y-compact">
          <p className="text-ink-primary">{row.label}</p>
          <p className="ident text-ink-tertiary">{row.itemCode}</p>
        </td>
        <td className="px-cell-x py-cell-y-compact text-right">
          <Link href="/rates" className="text-micro text-accent-text hover:text-accent-text-hover underline">
            {row.brackets} brackets
          </Link>
        </td>
        <td className="px-cell-x py-cell-y-compact border-l border-rule-solid" />
        <td className="px-cell-x py-cell-y-compact" />
      </tr>
    )
  }

  const drifted = row.asBilled !== row.currentEffective
  return (
    <tr className={`border-b border-rule-hair ${drifted ? 'bg-exception-warning-wash' : 'bg-surface-raised'}`}>
      <td className="px-cell-x py-cell-y-compact">
        <p className="text-ink-primary">{row.label}</p>
        <p className="ident text-ink-tertiary">{row.itemCode}</p>
      </td>
      <td className="px-cell-x py-cell-y-compact figures">
        {row.asBilled ? (
          <>
            {rateInUnit(row.asBilled, row.rateUnit)}
            <span className="text-ink-tertiary text-[0.85em]">{rateUnitLabel(row.rateUnit)}</span>
          </>
        ) : (
          <span className="text-ink-tertiary">—</span>
        )}
      </td>
      <td className="px-cell-x py-cell-y-compact figures border-l border-rule-solid">
        {/* Shown only where it differs. */}
        {drifted && row.currentEffective ? (
          <span className="text-exception-warning-text">
            {rateInUnit(row.currentEffective, row.rateUnit)}
            <span className="text-[0.85em]">{rateUnitLabel(row.rateUnit)}</span>
          </span>
        ) : (
          <>
            <span aria-hidden className="text-ink-muted">·</span>
            <span className="sr-only">No drift</span>
          </>
        )}
      </td>
      <td className="px-cell-x py-cell-y-compact">
        {drifted ? (
          <StateFlag tone="warning" title="This rate moved after the run posted — a correction-run trigger">
            Drift
          </StateFlag>
        ) : null}
      </td>
    </tr>
  )
}
