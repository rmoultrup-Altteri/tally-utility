'use client'

import { useRouter } from 'next/navigation'
import type { Route } from 'next'
import { Chip, Group } from '@/components/ui/Chip'
import type { Tier } from '@/fixtures/dashboard-items'

/**
 * Filter bar for the dashboard drilldown.
 *
 * State lives in the URL, as on the exception queue, so every portlet line on
 * the dashboard is just a link to a pre-filtered view of this list. A tier
 * narrows the type chips to that tier's types; picking a type implies its tier.
 */
export function ItemFilterBar({
  tier,
  type,
  tiers,
  types,
  shown,
  total,
}: {
  tier: Tier | null
  type: string | null
  tiers: readonly Tier[]
  types: { itemType: string; label: string; count: number }[]
  shown: number
  total: number
}) {
  const router = useRouter()
  const go = (next: { tier?: Tier | null; type?: string | null }) => {
    const p = new URLSearchParams()
    if (next.tier) p.set('tier', next.tier)
    if (next.type) p.set('type', next.type)
    const q = p.toString()
    router.push(`/dashboard/items${q ? `?${q}` : ''}` as Route, { scroll: false })
  }
  const filtered = tier !== null || type !== null

  return (
    <div className="flex flex-wrap items-center gap-x-5 gap-y-2 border-b border-rule-hair bg-surface px-cell-x py-2">
      <Group label="Tier">
        {tiers.map((t) => (
          <Chip key={t} on={tier === t} onClick={() => go({ tier: tier === t ? null : t })}>
            {t}
          </Chip>
        ))}
      </Group>

      <div className="flex flex-wrap items-center gap-1.5">
        <span className="field-label">Type</span>
        {types.map((t) => (
          <Chip
            key={t.itemType}
            on={type === t.itemType}
            onClick={() => go({ tier, type: type === t.itemType ? null : t.itemType })}
          >
            {t.label}
            <span className="figures opacity-70">{t.count}</span>
          </Chip>
        ))}
      </div>

      <div className="ml-auto flex items-center gap-3">
        <span className="text-micro text-ink-tertiary">
          {filtered ? `${shown} of ${total} shown` : `${total} items`}
        </span>
        {filtered ? (
          <button
            type="button"
            onClick={() => go({})}
            className="text-micro text-ink-secondary underline hover:text-ink-primary"
          >
            Clear
          </button>
        ) : null}
      </div>
    </div>
  )
}
