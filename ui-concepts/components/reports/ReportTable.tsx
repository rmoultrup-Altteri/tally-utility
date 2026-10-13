import type { ReactNode } from 'react'
import { ArrangedReportGrid, ReportGrid } from '@/components/reports/ReportGrid'
import type { Cell, Column, ReportRow } from '@/fixtures/reports'

/**
 * The table every report and every drilldown renders through.
 *
 * Footer totals are taken over `allRows`, not the page being shown, so a
 * paginated drilldown still sums back to the line it came from. When `hrefFor`
 * is given, each line's first cell links to that line's drilldown.
 *
 * With a `listId`, the operator can move and hide its columns, and the layout
 * is kept per report. Without one — the custom report builder, which has its
 * own column picker — the columns stay exactly as given. `toolbar` sits in a
 * strip above the table, where the Columns button joins it.
 *
 * This part runs wherever its caller does: it turns `hrefFor` into links and
 * sums the totals here, so only plain values cross to the client grid.
 */
export function ReportTable({
  caption,
  columns,
  rows,
  allRows = rows,
  offset = 0,
  hrefFor,
  listId,
  toolbar,
}: {
  caption: string
  columns: Column[]
  rows: ReportRow[]
  allRows?: ReportRow[]
  offset?: number
  hrefFor?: (index: number) => string
  listId?: string
  toolbar?: ReactNode
}) {
  const hrefs = hrefFor ? rows.map((_, i) => hrefFor(offset + i)) : undefined
  const totals = Object.fromEntries(columns.filter((c) => c.total).map((c) => [c.key, totalOf(allRows, c)]))
  const grid = { caption, rows, offset, hrefs, totals }

  if (listId) return <ArrangedReportGrid {...grid} listId={listId} columns={columns} toolbar={toolbar} />
  return (
    <>
      {toolbar ? <div className="border-b border-rule-hair px-4 py-2.5">{toolbar}</div> : null}
      <ReportGrid {...grid} columns={columns} />
    </>
  )
}

function totalOf(rows: ReportRow[], c: Column): Cell {
  if (c.kind === 'money') {
    const cents = rows.reduce((n, r) => n + Math.round(Number(r[c.key] ?? 0) * 100), 0)
    return (cents / 100).toFixed(2)
  }
  return rows.reduce((n, r) => n + Number(r[c.key] ?? 0), 0)
}
