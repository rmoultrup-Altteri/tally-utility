import { Fragment } from 'react'
import { Panel, PanelHeader } from '@/components/ui/Panel'
import { humanize } from '@/components/ui/State'
import { HeadRow, Th } from '@/components/table/Table'
import type { DisplayGroup } from '@/schemas/enums'
import { date, stamp } from '@/lib/format'
import { formatRate, monthStart, tariffOn, type BilledRates, type CatalogItem, type Coordinate } from '@/lib/rate-changes'

const GROUPS: DisplayGroup[] = ['base_charges', 'usage_charges', 'adjustments', 'riders', 'taxes_fees', 'other']

const monthLabel = (day: string) =>
  new Date(`${day}T00:00:00Z`).toLocaleDateString('en-US', { month: 'short', year: 'numeric', timeZone: 'UTC' })

/**
 * Each billed item across the last three months and this one.
 *
 * A cell is the tariff rate in effect on the 1st. Where that month's bills
 * were priced at something else — a factor recorded after the bills went out —
 * the cell says so, because "what the rate was" and "what we billed" are two
 * different questions and a correction run lives in the gap between them.
 */
export function RateHistory({
  items,
  billed,
  at,
}: {
  items: CatalogItem[]
  billed: BilledRates
  at: Coordinate
}) {
  const months = [-3, -2, -1, 0].map((offset) => monthStart(at.validAt, offset))

  return (
    <Panel>
      <PanelHeader
        title="Rates by month"
        meta={`Last three months and this month · tariff rate in effect on the 1st · ${date(months[0])} – today`}
      />
      <div className="overflow-x-auto">
        <table className="w-full text-data">
          <caption className="sr-only">Each rate item's rate over the last three months and this month</caption>
          <thead>
            <HeadRow>
              <Th>Item</Th>
              <Th width="6rem">Applies to</Th>
              {months.map((m, i) => (
                <Th key={m} align="right" width="12rem">
                  {monthLabel(m)}
                  {i === months.length - 1 ? ' · this month' : ''}
                </Th>
              ))}
            </HeadRow>
          </thead>
          <tbody>
            {GROUPS.map((group) => {
              const inGroup = items.filter((i) => i.group === group && i.code).sort((a, b) => a.name.localeCompare(b.name))
              if (inGroup.length === 0) return null
              return (
                <Fragment key={group}>
                  <tr>
                    <td colSpan={2 + months.length} className="label-caps border-y border-rule-solid bg-surface-sunken px-cell-x py-1">
                      {humanize(group)}
                    </td>
                  </tr>
                  {inGroup.map((item) => (
                    <tr key={item.key} className="border-b border-rule-hair bg-surface-raised hover:bg-surface-sunken">
                      <td className="px-cell-x py-cell-y-compact">
                        <p className="text-data text-ink-primary">{item.name}</p>
                        <p className="ident text-ink-tertiary">{item.code}</p>
                      </td>
                      <td className="px-cell-x py-cell-y-compact">
                        <span className="ident text-ink-secondary">{item.schedules.join(' ')}</span>
                      </td>
                      {months.map((m, i) => {
                        const v = tariffOn(item, m)
                        const prior = i > 0 ? tariffOn(item, months[i - 1]) : null
                        const diff = v && prior ? Number(v.rate) - Number(prior.rate) : 0
                        const onBills = billed[item.code]?.[m.slice(0, 7)] ?? []
                        const off = v ? onBills.filter((b) => b.rate !== v.rate) : []
                        const current = i === months.length - 1
                        return (
                          <td
                            key={m}
                            className={`px-cell-x py-cell-y-compact text-right align-top ${current ? 'bg-accent-wash' : ''}`}
                            title={v ? `${v.change_reason} · recorded ${stamp(v.recorded_from)}` : undefined}
                          >
                            {v ? (
                              <>
                                <span className="figures text-ink-primary">{formatRate(v.rate, item.unit)}</span>
                                {diff !== 0 ? (
                                  <span
                                    className={`block text-micro figures ${diff > 0 ? 'text-exception-warning-text' : 'text-money-credit'}`}
                                  >
                                    {diff > 0 ? '▲' : '▼'} {formatRate(String(Math.abs(diff)), item.unit).replace(/^−/, '')}
                                  </span>
                                ) : null}
                                {off.length > 0 ? (
                                  <span className="block text-micro text-exception-warning-text">
                                    Billed at{' '}
                                    {off.map((b) => `${formatRate(b.rate, item.unit)} on ${b.bills} ${b.bills === 1 ? 'bill' : 'bills'}`).join(', ')}
                                  </span>
                                ) : null}
                              </>
                            ) : (
                              <span className="text-micro text-ink-tertiary">Not in effect</span>
                            )}
                          </td>
                        )
                      })}
                    </tr>
                  ))}
                </Fragment>
              )
            })}
          </tbody>
        </table>
      </div>
      <p className="border-t border-rule-hair px-cell-x py-2 text-micro text-ink-tertiary">
        ▲▼ is the change from the month before. “Billed at” appears only where that month’s bills carried a different rate
        than the tariff — hover a cell for the version’s reason and when it was recorded.
      </p>
    </Panel>
  )
}
