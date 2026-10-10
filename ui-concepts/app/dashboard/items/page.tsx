import { AppShell, PageHeader } from '@/components/shell/AppShell'
import { ItemFilterBar } from '@/components/dashboard/ItemFilters'
import { Rail, StateFlag } from '@/components/ui/State'
import type { Tone } from '@/components/ui/State'
import { Money } from '@/components/ui/Money'
import { AccountNumber } from '@/components/ui/RecordLink'
import { Table, HeadRow, Th, Row, Td, RailCell, TableFooter } from '@/components/table/Table'
import { dashboardItems, TIERS, typesByTier } from '@/fixtures/dashboard-items'
import type { Tier } from '@/fixtures/dashboard-items'
import { cycle } from '@/fixtures/tenant'
import { dateShort } from '@/lib/format'

/**
 * The dashboard drilldown — what a portlet count is made of.
 *
 * Every line on a dashboard portlet links here with its item type set, and
 * each portlet's total links here with its tier set. The list must come back
 * with exactly the number the dashboard showed; that is the whole contract.
 */

const TIER_TONE: Record<Tier, Tone> = {
  Critical: 'critical',
  Medium: 'warning',
  Low: 'info',
}

export default async function DashboardItemsPage({ searchParams }: PageProps<'/dashboard/items'>) {
  const params = await searchParams
  const one = (k: string) => {
    const v = params[k]
    return Array.isArray(v) ? v[0] : v
  }

  const type = typesByTier.some((g) => g.types.some((t) => t.itemType === one('type')))
    ? one('type')!
    : null
  /* A type belongs to exactly one tier, so selecting it implies that tier. */
  const tierOfType = typesByTier.find((g) => g.types.some((t) => t.itemType === type))?.tier ?? null
  const tier = tierOfType ?? (TIERS.find((t) => t === one('tier')) ?? null)

  const rows = dashboardItems.filter(
    (item) => (!tier || item.tier === tier) && (!type || item.itemType === type),
  )
  const types = typesByTier.filter((g) => !tier || g.tier === tier).flatMap((g) => g.types)
  const typeLabel = types.find((t) => t.itemType === type)?.label

  return (
    <AppShell current="Dashboard">
      <PageHeader
        back={{ href: '/dashboard', label: 'the dashboard' }}
        title={typeLabel ?? (tier ? `${tier} items` : 'Dashboard items')}
        meta={
          <>
            {cycle.label} · {rows.length} {rows.length === 1 ? 'item' : 'items'}
            {tier ? ` · ${tier} tier` : ''}
          </>
        }
      />

      <div className="flex-1 min-h-0 flex flex-col">
        <ItemFilterBar
          tier={tier}
          type={type}
          tiers={TIERS}
          types={types}
          shown={rows.length}
          total={dashboardItems.length}
        />

        <div className="flex-1 min-h-0 overflow-auto">
          <Table caption="Items behind the dashboard portlet counts">
            <thead className="sticky top-0 z-10">
              <HeadRow>
                <Th width="3px"> </Th>
                <Th width="34%">Item</Th>
                <Th width="20%">Account</Th>
                <Th width="16%">Source</Th>
                <Th width="10%" align="right">Amount</Th>
                <Th width="10%">Detected</Th>
              </HeadRow>
            </thead>
            <tbody>
              {rows.map((item) => (
                <Row key={item.id}>
                  <RailCell>
                    <Rail tone={TIER_TONE[item.tier]} />
                  </RailCell>
                  <Td>
                    <div className="flex items-center gap-2">
                      <StateFlag tone={TIER_TONE[item.tier]}>{item.tier}</StateFlag>
                      <span className="field-label">{item.typeLabel}</span>
                    </div>
                    <p className="text-data text-ink-primary mt-0.5">{item.detail}</p>
                  </Td>
                  <Td>
                    <p className="text-data text-ink-primary truncate">{item.accountName}</p>
                    <p>
                      <AccountNumber number={item.accountNumber} plainClassName="text-ink-tertiary" />
                    </p>
                  </Td>
                  <Td>
                    <p className="text-micro text-ink-secondary">{item.source}</p>
                    <p className="ident text-ink-tertiary">{item.reference}</p>
                  </Td>
                  <Td align="right">
                    {item.amount ? <Money value={item.amount} /> : <span className="text-ink-tertiary">—</span>}
                  </Td>
                  <Td>
                    <span className="text-micro text-ink-tertiary whitespace-nowrap">
                      {dateShort(item.detectedAt)}
                    </span>
                  </Td>
                </Row>
              ))}
              {rows.length === 0 ? (
                <tr>
                  <td colSpan={6} className="px-cell-x py-6 text-center text-micro text-ink-tertiary">
                    Nothing of this type is open.
                  </td>
                </tr>
              ) : null}
            </tbody>
          </Table>
        </div>
        <TableFooter shown={rows.length} total={rows.length} noun="items" />
      </div>
    </AppShell>
  )
}
