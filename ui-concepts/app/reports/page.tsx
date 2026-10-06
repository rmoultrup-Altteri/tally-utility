import Link from 'next/link'
import type { Route } from 'next'
import { AppShell, PageHeader } from '@/components/shell/AppShell'
import { Panel, PanelHeader } from '@/components/ui/Panel'
import { CATEGORIES, reports } from '@/fixtures/reports'
import { cycle, tenant } from '@/fixtures/tenant'

/**
 * The report library. Reports are grouped by who reads them — collections,
 * accounting, field operations, tax and the regulator — and each one can be
 * starred into the sidebar favorites.
 */
export default function ReportsPage() {
  return (
    <AppShell current="Reports">
      <PageHeader
        title="Reports"
        meta={
          <>
            {tenant.name} · {reports.length} reports · {cycle.label} in flight
          </>
        }
      />

      <div className="flex-1 overflow-auto">
        <div className="px-5 py-5 grid grid-cols-1 lg:grid-cols-2 gap-5">
          {CATEGORIES.map((category) => {
            const inCategory = reports.filter((r) => r.category === category)
            if (!inCategory.length) return null
            return (
              <Panel key={category}>
                <PanelHeader title={category} meta={`${inCategory.length} ${inCategory.length === 1 ? 'report' : 'reports'}`} />
                <ul className="divide-y divide-rule-hair">
                  {inCategory.map((r) => (
                    <li key={r.id}>
                      <Link
                        href={`/reports/${r.id}` as Route}
                        className="block px-4 py-2.5 hover:bg-surface-sunken transition-colors duration-fast"
                      >
                        <span className="flex items-baseline justify-between gap-3">
                          <span className="text-data text-accent-text">{r.title}</span>
                          <span className="text-micro text-ink-tertiary whitespace-nowrap">{r.period}</span>
                        </span>
                        <span className="block text-micro text-ink-secondary mt-0.5">{r.description}</span>
                      </Link>
                    </li>
                  ))}
                </ul>
              </Panel>
            )
          })}
        </div>
      </div>
    </AppShell>
  )
}
