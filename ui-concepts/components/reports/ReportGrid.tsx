'use client'

import { Fragment, useMemo, type ReactNode } from 'react'
import Link from 'next/link'
import type { Route } from 'next'
import { StateFlag } from '@/components/ui/State'
import { AccountNumber, MeterNumber } from '@/components/ui/RecordLink'
import { Table, HeadRow, Th, Row, Td } from '@/components/table/Table'
import { ColumnHead, ColumnsMenu, useColumns, type ColumnDef } from '@/components/table/Columns'
import type { Cell, Column, ReportRow } from '@/fixtures/reports'
import { count, dateShort, money, percent } from '@/lib/format'

/**
 * The rendering half of `ReportTable`, on the client so a report's columns
 * can be arranged. It takes everything already worked out — each line's
 * drilldown link and the footer totals — because a server page can hand a
 * client component strings and numbers, but not the function that makes them.
 */

export type GridProps = {
  caption: string
  rows: ReportRow[]
  offset: number
  /** One per row on this page. Present means the table has a drill column, even where a row's link is missing. */
  hrefs?: (string | undefined)[]
  /** Footer totals by column key, already summed over every row rather than this page. */
  totals: Record<string, Cell>
}

/** The table itself, in whatever column order it is given. `head` replaces the plain header row. */
export function ReportGrid({ caption, columns, head, rows, offset, hrefs, totals }: GridProps & { columns: Column[]; head?: ReactNode }) {
  const drill = !!hrefs
  const totalled = columns.some((c) => c.total)
  return (
    <Table caption={caption}>
      <thead>
        {head ?? (
          <HeadRow>
            {columns.map((c) => (
              <Th key={c.key} align={alignOf(c)}>
                {c.label}
              </Th>
            ))}
            {drill ? <Th width="2rem"> </Th> : null}
          </HeadRow>
        )}
      </thead>
      <tbody>
        {rows.map((row, i) => {
          const group = row._group
          const newGroup = group && group !== rows[i - 1]?._group
          const href = hrefs?.[i]
          return (
            <Fragment key={offset + i}>
              {newGroup ? (
                <tr className="border-b border-rule-solid bg-surface-sunken">
                  <td colSpan={columns.length + (drill ? 1 : 0)} className="px-cell-x py-1.5 field-label">
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
      {totalled ? (
        <tfoot>
          <tr className="border-t border-rule-heavy bg-surface-sunken font-semibold">
            {columns.map((c, i) => (
              <td key={c.key} className={`px-cell-x py-2 ${alignOf(c) === 'right' ? 'text-right' : ''}`}>
                {c.total ? (
                  <CellValue column={c} value={totals[c.key] ?? null} />
                ) : i === 0 ? (
                  <span className="field-label">Total</span>
                ) : null}
              </td>
            ))}
            {drill ? <td /> : null}
          </tr>
        </tfoot>
      ) : null}
    </Table>
  )
}

const DRILL = '__drill'

type ReportColumn = ColumnDef & { column?: Column }

/**
 * A report whose columns the operator can move and hide. The drill arrow
 * stays pinned at the right; whichever data column is first carries the
 * line's link, and the footer and group rows follow what is showing. The
 * Columns button sits at the right of a strip above the table, beside
 * anything in `toolbar` — on a report, its description and source.
 */
export function ArrangedReportGrid({
  listId,
  columns,
  toolbar,
  ...grid
}: GridProps & { listId: string; columns: Column[]; toolbar?: ReactNode }) {
  const drill = !!grid.hrefs
  const defs = useMemo<ReportColumn[]>(
    () => [
      ...columns.map((c) => ({ key: c.key, label: c.label, align: alignOf(c), column: c })),
      ...(drill ? [{ key: DRILL, label: '', menuLabel: 'Open line', width: '2rem', fixed: true }] : []),
    ],
    [columns, drill],
  )
  const cols = useColumns(listId, defs)
  const shown = cols.visible.flatMap((c) => (c.column ? [c.column] : []))

  return (
    <>
      {toolbar ? (
        <div className="flex flex-wrap items-start gap-x-4 gap-y-2 border-b border-rule-hair px-4 py-2.5">
          <div className="min-w-0 flex-1">{toolbar}</div>
          <ColumnsMenu cols={cols} />
        </div>
      ) : (
        <div className="flex justify-end border-b border-rule-hair bg-surface px-cell-x py-1.5">
          <ColumnsMenu cols={cols} />
        </div>
      )}
      <ReportGrid {...grid} columns={shown} head={<ColumnHead cols={cols} />} />
    </>
  )
}

const NUMERIC = new Set(['money', 'number', 'percent', 'factor'])
const alignOf = (c: Column): 'left' | 'right' => (NUMERIC.has(c.kind ?? 'text') ? 'right' : 'left')

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
      /* An account or meter number opens its record — unless the whole cell is already the drilldown link. */
      if (!plain && column.key === 'account')
        return <AccountNumber number={String(value)} className="whitespace-nowrap" plainClassName="text-ink-secondary" />
      if (!plain && column.key === 'meter')
        return <MeterNumber number={String(value)} className="whitespace-nowrap" plainClassName="text-ink-secondary" />
      return <span className={`ident ${ink('text-ink-secondary')} whitespace-nowrap`}>{value}</span>
    case 'status':
      return <StateFlag tone={column.tones?.[String(value)] ?? 'draft'}>{value}</StateFlag>
    default:
      return <span className={ink('text-ink-primary')}>{value}</span>
  }
}
