'use client'

import { useState } from 'react'
import { HeadRow, Th } from '@/components/table/Table'

/**
 * Click-to-sort column headers for the record lists.
 *
 * Blanks sort last in both directions, so flipping a column never buries the
 * populated rows under empty ones. Text compares in natural order — "907
 * Fairview" before "1418 Ashburn", meter 004182 before 119004 — and numbers
 * compare as numbers, so a money column must hand over a number, not "$1,052".
 */

export type SortDir = 'ascending' | 'descending'
export type Sort<K extends string> = { key: K; dir: SortDir }
export type SortValue = string | number | null

export type SortColumn<K extends string> = {
  key: K
  label: string
  width?: string
  align?: 'left' | 'right'
}

const collator = new Intl.Collator('en-US', { numeric: true, sensitivity: 'base' })

export function useSort<K extends string>(initial: Sort<K>) {
  const [sort, setSort] = useState(initial)
  const toggle = (key: K) =>
    setSort((s) =>
      s.key === key
        ? { key, dir: s.dir === 'ascending' ? 'descending' : 'ascending' }
        : { key, dir: 'ascending' },
    )
  return { sort, toggle }
}

export function sortRows<T, K extends string>(
  rows: T[],
  sort: Sort<K>,
  value: (row: T, key: K) => SortValue,
): T[] {
  const sign = sort.dir === 'ascending' ? 1 : -1
  return [...rows].sort((a, b) => {
    const x = value(a, sort.key)
    const y = value(b, sort.key)
    if (x === y) return 0
    if (x === null) return 1
    if (y === null) return -1
    if (typeof x === 'number' && typeof y === 'number') return sign * (x - y)
    return sign * collator.compare(String(x), String(y))
  })
}

export function SortHeader<K extends string>({
  columns,
  sort,
  onSort,
}: {
  columns: SortColumn<K>[]
  sort: Sort<K>
  onSort: (key: K) => void
}) {
  return (
    <HeadRow>
      {columns.map((col) => {
        const active = sort.key === col.key
        return (
          <Th key={col.key} width={col.width} align={col.align} sort={active ? sort.dir : 'none'}>
            <button
              type="button"
              onClick={() => onSort(col.key)}
              className={`inline-flex items-center gap-1 whitespace-nowrap uppercase hover:text-ink-primary ${
                col.align === 'right' ? 'flex-row-reverse' : ''
              } ${active ? 'text-ink-primary' : ''}`}
            >
              {col.label}
              <span aria-hidden className={active ? '' : 'opacity-30'}>
                {active && sort.dir === 'descending' ? '▼' : '▲'}
              </span>
            </button>
          </Th>
        )
      })}
    </HeadRow>
  )
}
