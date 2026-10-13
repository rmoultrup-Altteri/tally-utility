'use client'

import Link from 'next/link'
import type { Route } from 'next'
import { Panel, PanelHeader } from '@/components/ui/Panel'
import { useCustomReports } from '@/lib/custom-reports-store'
import { describeReport } from '@/lib/report-builder'
import { date } from '@/lib/format'

/**
 * "Your reports" — the custom reports saved in this browser, at the head of
 * the library. Spans the grid's full width so it reads as the operator's own
 * shelf rather than one more category.
 */
export function CustomReportsPanel() {
  const saved = useCustomReports()
  const sorted = [...saved].sort((a, b) => a.title.localeCompare(b.title, 'en-US', { numeric: true }))
  return (
    <Panel className="lg:col-span-2">
      <PanelHeader
        title="Your reports"
        meta={saved.length ? `${saved.length} ${saved.length === 1 ? 'report' : 'reports'} · kept in this browser` : 'kept in this browser'}
        actions={
          <Link href={'/reports/builder' as Route} className="text-micro text-accent-text hover:underline">
            + New report
          </Link>
        }
      />
      {sorted.length ? (
        <ul className="divide-y divide-rule-hair">
          {sorted.map((r) => (
            <li key={r.id}>
              <Link
                href={`/reports/builder?id=${encodeURIComponent(r.id)}` as Route}
                className="block px-4 py-2.5 hover:bg-surface-sunken transition-colors duration-fast"
              >
                <span className="flex items-baseline justify-between gap-3">
                  <span className="text-data text-accent-text">{r.title}</span>
                  <span className="text-micro text-ink-tertiary whitespace-nowrap">Saved {date(r.updatedAt)}</span>
                </span>
                <span className="block text-micro text-ink-secondary mt-0.5">{describeReport(r)}</span>
              </Link>
            </li>
          ))}
        </ul>
      ) : (
        <p className="px-4 py-3 text-micro text-ink-secondary">
          Nothing saved yet.{' '}
          <Link href={'/reports/builder' as Route} className="text-accent-text hover:underline">
            Create your own report
          </Link>{' '}
          from accounts, bills, payments, meters, reads or exceptions — pick the columns, filter, group and sort, then
          save it here.
        </p>
      )}
    </Panel>
  )
}

/** The library header's count of saved custom reports; silent until there is one. */
export function CustomReportCount() {
  const n = useCustomReports().length
  return n ? <> · {n} of yours</> : null
}
