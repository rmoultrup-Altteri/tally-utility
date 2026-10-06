import Link from 'next/link'
import type { Route } from 'next'
import { notFound } from 'next/navigation'
import { AppShell, PageHeader } from '@/components/shell/AppShell'
import { Panel } from '@/components/ui/Panel'
import { ExportCsv } from '@/components/reports/ReportActions'
import { ReportTable } from '@/components/reports/ReportTable'
import { drillFor, reportById } from '@/fixtures/reports'
import type { ReportKey } from '@/lib/views'
import { count } from '@/lib/format'

/**
 * The records behind one report line.
 *
 * Paginated at a fixed page size — never infinite scroll in a financial list —
 * with the footer totals taken over every record, so the figure at the bottom
 * is the figure that was clicked no matter which page is showing.
 */

const PAGE = 100

export default async function ReportLinePage({ params, searchParams }: PageProps<'/reports/[reportId]/[line]'>) {
  const { reportId, line } = await params
  const report = reportById.get(reportId as ReportKey)
  const index = Number(line)
  const drill = report && Number.isInteger(index) ? drillFor(report.id, index) : null
  if (!report || !drill) notFound()

  const sp = await searchParams
  const pages = Math.max(1, Math.ceil(drill.rows.length / PAGE))
  const page = Math.min(pages, Math.max(1, Number(Array.isArray(sp.page) ? sp.page[0] : sp.page) || 1))
  const offset = (page - 1) * PAGE
  const shown = drill.rows.slice(offset, offset + PAGE)
  const here = `/reports/${report.id}/${index}`

  return (
    <AppShell current="Reports">
      <PageHeader
        back={{ href: `/reports/${report.id}`, label: report.title }}
        title={drill.title}
        meta={
          <>
            <Link href={`/reports/${report.id}` as Route} className="underline hover:text-ink-primary">
              {report.title}
            </Link>{' '}
            · {drill.subtitle}
          </>
        }
        actions={
          <ExportCsv
            filename={`${report.id}-line-${index + 1}`}
            header={drill.columns.map((c) => c.label)}
            rows={drill.rows.map((r) => drill.columns.map((c) => r[c.key] ?? null))}
          />
        }
      />

      <div className="flex-1 overflow-auto">
        <div className="px-5 py-5 space-y-5">
          <div className="grid grid-cols-1 sm:grid-cols-3 gap-5">
            {drill.ties.map((t) => (
              <Panel key={t.label}>
                <div className="px-4 py-3">
                  <p className="field-label">{t.label}</p>
                  <p className="text-h2 mt-1 figures text-ink-primary">{t.value}</p>
                </div>
              </Panel>
            ))}
          </div>

          <Panel>
            <ReportTable caption={drill.title} columns={drill.columns} rows={shown} allRows={drill.rows} offset={offset} />
            <div className="flex items-center justify-between gap-4 border-t border-rule-solid bg-surface-sunken px-cell-x py-2">
              <p className="text-micro text-ink-secondary">
                {drill.rows.length ? `${count(offset + 1)}–${count(offset + shown.length)}` : '0'} of{' '}
                {count(drill.rows.length)} · totals cover every record · sample data
              </p>
              {pages > 1 ? (
                <div className="flex items-center gap-3 text-micro">
                  {page > 1 ? (
                    <Link href={`${here}?page=${page - 1}` as Route} className="text-accent-text hover:underline">
                      ‹ Previous
                    </Link>
                  ) : (
                    <span className="text-ink-muted">‹ Previous</span>
                  )}
                  <span className="text-ink-tertiary">
                    Page {page} of {pages}
                  </span>
                  {page < pages ? (
                    <Link href={`${here}?page=${page + 1}` as Route} className="text-accent-text hover:underline">
                      Next ›
                    </Link>
                  ) : (
                    <span className="text-ink-muted">Next ›</span>
                  )}
                </div>
              ) : null}
            </div>
          </Panel>
        </div>
      </div>
    </AppShell>
  )
}
