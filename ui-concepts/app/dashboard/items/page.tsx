import type { ReactNode } from 'react'
import { AppShell, PageHeader } from '@/components/shell/AppShell'
import { ItemFilterBar } from '@/components/dashboard/ItemFilters'
import { Rail, StateFlag } from '@/components/ui/State'
import type { Tone } from '@/components/ui/State'
import { Money } from '@/components/ui/Money'
import { AccountNumber } from '@/components/ui/RecordLink'
import { TableFooter } from '@/components/table/Table'
import { ColumnTable, type ColumnDef } from '@/components/table/Columns'
import { dashboardItems, TIERS, typesByTier } from '@/fixtures/dashboard-items'
import type { DashboardItem, Tier } from '@/fixtures/dashboard-items'
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

/**
 * The shipped five after the rail. Tier, type and reference already ride
 * inside the Item and Source cells; as their own columns they can be read
 * down the page at a glance, so they wait in the Columns menu.
 */
const COLUMNS: ColumnDef[] = [
  { key: 'rail', label: '', menuLabel: 'Tier rail', width: '3px', rail: true, fixed: true },
  { key: 'item', label: 'Item', width: '34%' },
  { key: 'account', label: 'Account', width: '20%' },
  { key: 'source', label: 'Source', width: '16%' },
  { key: 'amount', label: 'Amount', width: '10%', align: 'right' },
  { key: 'detected', label: 'Detected', width: '10%' },
  { key: 'tier', label: 'Tier', hidden: true },
  { key: 'type', label: 'Type', hidden: true },
  { key: 'reference', label: 'Reference', hidden: true },
]

/** One item's cells, rendered here on the server and arranged by `ColumnTable`. */
function itemCells(item: DashboardItem): Record<string, ReactNode> {
  return {
    rail: <Rail tone={TIER_TONE[item.tier]} />,
    item: (
      <>
        <div className="flex items-center gap-2">
          <StateFlag tone={TIER_TONE[item.tier]}>{item.tier}</StateFlag>
          <span className="field-label">{item.typeLabel}</span>
        </div>
        <p className="text-data text-ink-primary mt-0.5">{item.detail}</p>
      </>
    ),
    account: (
      <>
        <p className="text-data text-ink-primary truncate">{item.accountName}</p>
        <p>
          <AccountNumber number={item.accountNumber} plainClassName="text-ink-tertiary" />
        </p>
      </>
    ),
    source: (
      <>
        <p className="text-micro text-ink-secondary">{item.source}</p>
        <p className="ident text-ink-tertiary">{item.reference}</p>
      </>
    ),
    amount: item.amount ? <Money value={item.amount} /> : <span className="text-ink-tertiary">—</span>,
    detected: <span className="text-micro text-ink-tertiary whitespace-nowrap">{dateShort(item.detectedAt)}</span>,
    tier: <StateFlag tone={TIER_TONE[item.tier]}>{item.tier}</StateFlag>,
    type: <span className="text-micro text-ink-secondary">{item.typeLabel}</span>,
    reference: <span className="ident text-ink-tertiary">{item.reference}</span>,
  }
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

        {/* The table's own frame scrolls, so the Columns strip stays put and
            the header sticks above the rows. */}
        <ColumnTable
          fill
          listId="dashboard-items"
          caption="Items behind the dashboard portlet counts"
          columns={COLUMNS}
          rows={rows.map((item) => ({ key: item.id, cells: itemCells(item) }))}
          empty={<span className="text-micro">Nothing of this type is open.</span>}
        />
        <TableFooter shown={rows.length} total={rows.length} noun="items" />
      </div>
    </AppShell>
  )
}
