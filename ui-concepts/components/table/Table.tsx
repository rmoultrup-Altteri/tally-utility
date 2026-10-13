import type { ReactNode, ThHTMLAttributes } from 'react'

/**
 * Dense table primitives.
 *
 * No zebra striping — hairlines and the rounded status rail do the row-tracking work,
 * and stripes fight every tint needed for state. Column groups carry a label
 * row above the header, because twenty undifferentiated columns are not
 * navigable and six labelled groups are.
 */

export function Table({ children, caption, className = 'overflow-x-auto' }: { children: ReactNode; caption: string; className?: string }) {
  return (
    <div className={className}>
      <table className="w-full text-data">
        <caption className="sr-only">{caption}</caption>
        {children}
      </table>
    </div>
  )
}

/** The group label row that sits above the column headers. */
export function GroupRow({ groups }: { groups: { label: string; span: number }[] }) {
  return (
    <tr>
      {groups.map((g, i) => (
        <th
          key={g.label + i}
          colSpan={g.span}
          scope="colgroup"
          className={`field-label bg-surface-sunken px-cell-x py-1 text-left ${
            i > 0 ? 'border-l border-rule-solid' : ''
          }`}
        >
          {g.label}
        </th>
      ))}
    </tr>
  )
}

export function HeadRow({ children }: { children: ReactNode }) {
  return <tr className="border-b border-rule-solid">{children}</tr>
}

export function Th({
  children,
  align = 'left',
  width,
  groupStart = false,
  sort,
  className = '',
  ...rest
}: {
  children: ReactNode
  align?: 'left' | 'right' | 'center'
  width?: string
  groupStart?: boolean
  sort?: 'ascending' | 'descending' | 'none'
  className?: string
} & Omit<ThHTMLAttributes<HTMLTableCellElement>, 'align' | 'children' | 'className' | 'style'>) {
  const alignment =
    align === 'right' ? 'text-right' : align === 'center' ? 'text-center' : 'text-left'
  return (
    <th
      scope="col"
      {...rest}
      style={width ? { width } : undefined}
      aria-sort={sort}
      className={`field-label bg-surface-sunken px-cell-x py-2 ${alignment} ${
        groupStart ? 'border-l border-rule-solid' : ''
      } ${className}`}
    >
      {children}
    </th>
  )
}

export function Row({
  children,
  selected = false,
  muted = false,
}: {
  children: ReactNode
  selected?: boolean
  muted?: boolean
}) {
  const ground = selected
    ? 'bg-accent-wash hover:bg-accent-wash-hover'
    : 'bg-surface-raised hover:bg-surface-sunken'
  return (
    <tr className={`border-b border-rule-hair ${ground} ${muted ? 'opacity-60' : ''}`}>
      {children}
    </tr>
  )
}

export function Td({
  children,
  align = 'left',
  groupStart = false,
  className = '',
  title,
  colSpan,
}: {
  children: ReactNode
  align?: 'left' | 'right' | 'center'
  groupStart?: boolean
  className?: string
  title?: string
  colSpan?: number
}) {
  const alignment =
    align === 'right' ? 'text-right' : align === 'center' ? 'text-center' : 'text-left'
  return (
    <td
      title={title}
      colSpan={colSpan}
      className={`px-cell-x py-cell-y-compact align-middle ${alignment} ${
        groupStart ? 'border-l border-rule-solid' : ''
      } ${className}`}
    >
      {children}
    </td>
  )
}

/** The rail cell — a 3px status edge in place of a whole status column. */
export function RailCell({ children }: { children: ReactNode }) {
  return <td className="w-rail p-0">{children}</td>
}

/**
 * Stable, exact pagination. Never infinite scroll in a financial list —
 * reconciliation needs "1–100 of 3,412" to be true and repeatable.
 */
export function TableFooter({
  shown,
  total,
  noun,
}: {
  shown: number
  total: number
  noun: string
}) {
  return (
    <div className="flex items-center justify-between border-t border-rule-solid bg-surface-sunken px-cell-x py-2">
      <p className="text-micro text-ink-secondary">
        1–{shown} of {total.toLocaleString('en-US')} {noun}
      </p>
    </div>
  )
}
