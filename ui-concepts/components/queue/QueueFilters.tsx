'use client'

import { useRouter } from 'next/navigation'
import type { Route } from 'next'
import { SaveView } from '@/components/shell/Favorites'
import {
  EMPTY_FILTERS,
  SEVERITIES,
  STATUSES,
  isFiltered,
  serializeFilters,
  type QueueFilters as Filters,
  type Severity,
  type Status,
} from '@/lib/views'
import { humanize } from '@/components/ui/State'
import { Chip, Group } from '@/components/ui/Chip'

/**
 * Column filters for the exception queue.
 *
 * T8-1 puts filtering on the record list rather than in a standalone advanced
 * search, so this bar IS the search interface — and because its state lives in
 * the URL, a filtered queue is already a shareable link. That is what makes
 * "save this view" a one-line operation rather than a serialisation problem.
 */
export function QueueFilterBar({
  filters,
  shown,
  total,
}: {
  filters: Filters
  shown: number
  total: number
}) {
  const router = useRouter()
  const go = (next: Filters) => router.push(`/${serializeFilters(next)}` as Route, { scroll: false })
  const toggle = <T extends string>(arr: T[], v: T): T[] =>
    arr.includes(v) ? arr.filter((x) => x !== v) : [...arr, v]

  return (
    <div className="flex flex-wrap items-center gap-x-5 gap-y-2 border-b border-rule-hair bg-surface px-cell-x py-2">
      <Group label="Severity">
        {SEVERITIES.map((s) => (
          <Chip
            key={s}
            on={filters.severity.includes(s)}
            onClick={() => go({ ...filters, severity: toggle<Severity>(filters.severity, s) })}
          >
            {humanize(s)}
          </Chip>
        ))}
      </Group>

      <Group label="Status">
        {STATUSES.map((s) => (
          <Chip
            key={s}
            on={filters.status.includes(s)}
            onClick={() => go({ ...filters, status: toggle<Status>(filters.status, s) })}
          >
            {humanize(s)}
          </Chip>
        ))}
      </Group>

      <Group label="Delivery">
        <Chip
          on={filters.blocking === true}
          onClick={() => go({ ...filters, blocking: filters.blocking === true ? undefined : true })}
        >
          Blocking
        </Chip>
        <Chip
          on={filters.blocking === false}
          onClick={() => go({ ...filters, blocking: filters.blocking === false ? undefined : false })}
        >
          Not blocking
        </Chip>
      </Group>

      <Group label="Owner">
        <Chip
          on={filters.assignee === 'unassigned'}
          onClick={() =>
            go({ ...filters, assignee: filters.assignee === 'unassigned' ? 'anyone' : 'unassigned' })
          }
        >
          Unassigned
        </Chip>
        <Chip
          on={filters.assignee === 'me'}
          onClick={() => go({ ...filters, assignee: filters.assignee === 'me' ? 'anyone' : 'me' })}
        >
          Mine
        </Chip>
      </Group>

      <div className="ml-auto flex items-center gap-3">
        <span className="text-micro text-ink-tertiary">
          {isFiltered(filters) ? `${shown} of ${total} shown` : `${total} open`}
        </span>
        {isFiltered(filters) ? (
          <>
            <SaveView list="exceptions" filters={filters} />
            <button
              type="button"
              onClick={() => go(EMPTY_FILTERS)}
              className="text-micro text-ink-secondary underline hover:text-ink-primary"
            >
              Clear
            </button>
          </>
        ) : null}
      </div>
    </div>
  )
}
