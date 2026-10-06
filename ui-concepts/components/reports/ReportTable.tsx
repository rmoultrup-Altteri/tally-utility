import { Fragment } from 'react'
import Link from 'next/link'
import type { Route } from 'next'
import { StateFlag } from '@/components/ui/State'
import { Table, HeadRow, Th, Row, Td } from '@/components/table/Table'
import type { Cell, Column, ReportRow } from '@/fixtures/reports'
import { count, dateShort, money, percent } from '@/lib/format'

/**
 * The table every report and every drilldown renders through.
 *
 * Footer totals are taken over `allRows`, not the page being shown, so a
 * paginated drilldown still sums back to the line it came from. When `hrefFor`
 * is given, each line's first cell links to that line's drilldown.
 */
export function ReportTable({
  caption,
  columns,
  rows,
  allRows = rows,
  offset = 0,
  hrefFor,
}: {
  caption: string
  columns: Column[]
  rows: ReportRow[]
  allRows?: ReportRow[]
  offset?: number
  hrefFor?: (index: number) => string
}) {
  const totalled = columns.filter((c) => c.total)
  return (
    <Table caption={caption}>
      <thead>
        <HeadRow>
          {columns.map((c) => (
            <Th key={c.key} align={alignOf(c)}>
              {c.label}
            </Th>
          ))}
          {hrefFor ? <Th width="2rem"> </Th> : null}
        </HeadRow>
      </thead>
      <tbody>
        {rows.map((row, i) => {
          const group = row._group
          const newGroup = group && group !== rows[i - 1]?._group
          const href = hrefFor?.(offset + i)
          return (
            <Fragment key={offset + i}>
              {newGroup ? (
                <tr className="border-b border-rule-solid bg-surface-sunken">
                  <td colSpan={columns.length + (hrefFor ? 1 : 0)} className="px-cell-x py-1.5 field-label">
                    {group}
                  </td>
                </tr>
              ) : null}
              <Row>
                {columns.map((c, j) => (
                  <Td key={c.key} align={alignOf(c)}>
                    {href && j === 0 ? (
                      <Link href={href as Route} className="text-accent-text hover:text-accent-text-hover underline-offset-2 hover:underline">
                        <CellValue column={c} value={row[c.key] ?? null} plain />
                      </Link>
                    ) : (
                      <CellValue column={c} value={row[c.key] ?? null} />
                    )}
                  </Td>
                ))}
                {href ? (
                  <Td align="right">
                    <Link
                      href={href as Route}
                      aria-label="Open the records behind this line"
                      title="Open the records behind this line"
                      className="text-ink-tertiary hover:text-accent-text"
                    >
                      ›
                    </Link>
                  </Td>
                ) : null}
              </Row>
            </Fragment>
          )
        })}
      </tbody>
      {totalled.length ? (
        <tfoot>
          <tr className="border-t border-rule-heavy bg-surface-sunken font-semibold">
            {columns.map((c, i) => (
              <td key={c.key} className={`px-cell-x py-2 ${alignOf(c) === 'right' ? 'text-right' : ''}`}>
                {c.total ? (
                  <CellValue column={c} value={totalOf(allRows, c)} />
                ) : i === 0 ? (
                  <span className="field-label">Total</span>
                ) : null}
              </td>
            ))}
            {hrefFor ? <td /> : null}
          </tr>
        </tfoot>
      ) : null}
    </Table>
  )
}

const NUMERIC = new Set(['money', 'number', 'percent', 'factor'])
const alignOf = (c: Column) => (NUMERIC.has(c.kind ?? 'text') ? 'right' : 'left')

function totalOf(rows: ReportRow[], c: Column): Cell {
  if (c.kind === 'money') {
    const cents = rows.reduce((n, r) => n + Math.round(Number(r[c.key] ?? 0) * 100), 0)
    return (cents / 100).toFixed(2)
  }
  return rows.reduce((n, r) => n + Number(r[c.key] ?? 0), 0)
}

/** `plain` drops the cell's own ink so a link colour can show through. */
function CellValue({ column, value, plain = false }: { column: Column; value: Cell; plain?: boolean }) {
  if (value === null || value === '') return <span className="text-ink-tertiary">—</span>
  const ink = (cls: string) => (plain ? '' : cls)
  switch (column.kind) {
    case 'money':
      return <span className="figures">{money(value)}</span>
    case 'number':
      return <span className="figures">{count(Number(value))}</span>
    case 'percent':
      return <span className="figures">{percent(Number(value), Math.abs(Number(value)) < 0.1 ? 2 : 1)}</span>
    case 'factor':
      return <span className="figures">{Number(value).toFixed(4)}</span>
    case 'date':
      return <span className={`${ink('text-ink-secondary')} whitespace-nowrap`}>{dateShort(String(value))}</span>
    case 'ident':
      return <span className={`ident ${ink('text-ink-secondary')} whitespace-nowrap`}>{value}</span>
    case 'status':
      return <StateFlag tone={column.tones?.[String(value)] ?? 'draft'}>{value}</StateFlag>
    default:
      return <span className={ink('text-ink-primary')}>{value}</span>
  }
}
