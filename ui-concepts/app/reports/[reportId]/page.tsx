import { notFound } from 'next/navigation'
import { AppShell, PageHeader } from '@/components/shell/AppShell'
import { Panel } from '@/components/ui/Panel'
import { ExportCsv, ReportStar } from '@/components/reports/ReportActions'
import { ReportTable } from '@/components/reports/ReportTable'
import { reportById, reports } from '@/fixtures/reports'
import type { ReportKey } from '@/lib/views'
import { count } from '@/lib/format'

/**
 * One report. Every report shares this layout: period and source up top, the
 * headline figures, the table with its footer totals, then the notes that
 * say what the numbers do and do not mean. Each line opens the records
 * behind it.
 */

export function generateStaticParams() {
  return reports.map((r) => ({ reportId: r.id }))
}

export default async function ReportPage({ params }: PageProps<'/reports/[reportId]'>) {
  const { reportId } = await params
  const report = reportById.get(reportId as ReportKey)
  if (!report) notFound()

  return (
    <AppShell current="Reports">
      <PageHeader
        back={{ href: '/reports', label: 'Reports' }}
        title={report.title}
        meta={
          <>
            {report.category} · {report.period}
          </>
        }
        actions={
          <>
            <ReportStar report={report.id} />
            <ExportCsv
              filename={report.id}
              header={report.columns.map((c) => c.label)}
              rows={report.rows.map((r) => report.columns.map((c) => r[c.key] ?? null))}
            />
          </>
        }
      />

      <div className="flex-1 overflow-auto">
        <div className="px-5 py-5 space-y-5">
          <div className="grid grid-cols-1 sm:grid-cols-3 gap-5">
            {report.summary.map((s) => (
              <Panel key={s.label}>
                <div className="px-4 py-3">
                  <p className="field-label">{s.label}</p>
                  <p className="text-h2 mt-1 figures text-ink-primary">{s.value}</p>
                  {s.note ? <p className="text-micro text-ink-tertiary mt-0.5">{s.note}</p> : null}
                </div>
              </Panel>
            ))}
          </div>

          <Panel>
            <div className="border-b border-rule-hair px-4 py-2.5">
              <p className="text-micro text-ink-secondary">{report.description}</p>
              <p className="text-micro text-ink-tertiary mt-0.5">Source: {report.source}</p>
            </div>
            <ReportTable
              caption={report.title}
              columns={report.columns}
              rows={report.rows}
              hrefFor={(i) => `/reports/${report.id}/${i}`}
            />
            <div className="border-t border-rule-hair px-4 py-2 text-micro text-ink-tertiary">
              {count(report.rows.length)} {report.rows.length === 1 ? 'line' : 'lines'} · click a line for the
              records behind it · sample data
            </div>
          </Panel>

          {report.notes.length ? (
            <Panel>
              <ul className="px-4 py-3 space-y-1.5 list-disc list-inside">
                {report.notes.map((n) => (
                  <li key={n} className="text-micro text-ink-secondary leading-relaxed">
                    {n}
                  </li>
                ))}
              </ul>
            </Panel>
          ) : null}
        </div>
      </div>
    </AppShell>
  )
}
