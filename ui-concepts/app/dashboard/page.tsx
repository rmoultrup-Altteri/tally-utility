import Link from 'next/link'
import { AppShell, PageHeader } from '@/components/shell/AppShell'
import { Button, Panel, PanelHeader } from '@/components/ui/Panel'
import { Rail, StateFlag } from '@/components/ui/State'
import type { Tone } from '@/components/ui/State'
import { Money } from '@/components/ui/Money'
import { arAging, portlets, rateCard, revenue } from '@/fixtures/billing'
import type { PortletRow, RateCardRow } from '@/fixtures/billing'
import { cycle, tenant } from '@/fixtures/tenant'
import { count, money, rateInUnit } from '@/lib/format'
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
            {tenant.name} · {count(tenant.meters)} meters · {cycle.label} in flight
          </>
        }
        actions={<Button>Configure portlets</Button>}
      />

      <div className="flex-1 overflow-auto">
        <div className="px-5 py-5 space-y-5">
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
                  meta={`${count(p.rows.reduce((n, r) => n + r.count, 0))} items`}
                />
                <ul className="divide-y divide-rule-hair">
                  {p.rows.map((row) => (
                    <PortletLine key={row.itemType} row={row} />
                  ))}
                  {p.more > 0 ? (
                    <li className="px-4 py-1.5">
                      <Link href="/" className="text-micro text-accent-text hover:text-accent-text-hover underline">
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
              <div className="grid grid-cols-2 divide-x divide-rule-solid">
                <RevenueFigure
                  label="Billed, net of voids"
                  value={revenue.billedNetOfVoids}
                  prior={revenue.billedPriorMonthSameDay}
                  note="Voids subtract at their void date, so closed months never restate."
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
              <PanelHeader title="Accounts receivable" meta="Aged by invoice · click a bucket to drill in" />
              <div className="grid grid-cols-4 divide-x divide-rule-solid">
                {arAging.map((b) => {
                  const flagged = b.bucket === '90+ days'
                  return (
                    <Link
                      key={b.bucket}
                      href="/"
                      className={`block px-3 py-3 transition-colors duration-fast hover:bg-surface-sunken ${
                        flagged ? 'bg-exception-critical-wash' : ''
                      }`}
                    >
                      <p className="label-caps">{b.bucket}</p>
                      <p
                        className={`text-h2 mt-1 figures ${
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
              <div className="border-t border-rule-hair px-4 py-2.5">
                <p className="text-micro text-ink-tertiary">
                  A customer with unpaid bills of different ages appears in more than one bucket, and
                  the drilldown says so. Each list sums back to its bucket — that reconciliation is
                  the acceptance test.
                </p>
              </div>
            </Panel>
          </div>

          {/* T8-8 — as-billed, with drift. The point of the tile. */}
          <Panel>
            <PanelHeader
              title="Tariff rate card"
              meta={`As billed on ${rateCard.lastPostedRun}`}
              actions={
                <>
                  <select
                    aria-label="Rate schedule"
                    className="h-7 rounded-xs border border-rule-solid bg-surface-raised px-2 text-data text-ink-primary"
                    defaultValue={rateCard.scheduleCode}
                  >
                    <option value="R-1">R-1 · Residential Firm Gas Service</option>
                    <option value="G-1">G-1 · General Service — Small Commercial</option>
                    <option value="G-2">G-2 · General Service — Large Commercial</option>
                  </select>
                  <Link href="/rates">
                    <Button>Full rate card</Button>
                  </Link>
                </>
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
                    <th className="label-caps px-cell-x py-1.5 text-left">Charge</th>
                    <th className="label-caps px-cell-x py-1.5 text-right">As billed</th>
                    <th className="label-caps px-cell-x py-1.5 text-right border-l border-rule-solid">
                      Current effective
                    </th>
                    <th className="label-caps px-cell-x py-1.5 text-left">Drift</th>
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
        href="/"
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
  return (
    <div className="px-4 py-3">
      <p className="label-caps">{label}</p>
      <p className="text-figure mt-1 figures text-ink-primary">{money(value)}</p>
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
