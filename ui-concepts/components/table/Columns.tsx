'use client'

import { Fragment, useEffect, useMemo, useRef, useState, type DragEvent, type ReactNode } from 'react'
import { HeadRow, RailCell, Row, Table, Td, Th } from '@/components/table/Table'
import type { Sort } from '@/components/table/Sort'
import { setColumnLayout, useColumnLayout } from '@/lib/columns-store'

/**
 * Columns the operator arranges: every list's columns can be dragged into a
 * new order by their headers, and shown or hidden from the Columns menu. The
 * layout is kept per list and per browser, and Reset puts the list back the
 * way it shipped.
 *
 * A column marked `fixed` — a status rail, a selection box, a drill arrow —
 * stays where it is and cannot be hidden: those are part of how the row
 * works, not data a person might not want to see.
 *
 * Client lists use `useColumns` with `ColumnHead` and `ColumnsMenu` and render
 * their own rows. Server-rendered lists hand their cells, already rendered,
 * to `ColumnTable`, which does the rest.
 */

export type ColumnDef<K extends string = string> = {
  key: K
  label: string
  width?: string
  align?: 'left' | 'right' | 'center'
  /** Pinned where it is and always shown. */
  fixed?: boolean
  /** Off until the operator turns it on. */
  hidden?: boolean
  /** Name in the Columns menu when the header itself is blank or terse. */
  menuLabel?: string
  /** Set false on a column that has nothing meaningful to sort by. */
  sortable?: boolean
  /** A 3px status rail rather than a data cell (ColumnTable only). */
  rail?: boolean
  /** Extra classes on this column's body cells (ColumnTable only). */
  cellClassName?: string
}

export type Columns<C extends ColumnDef> = {
  listId: string
  /** What to render, in order: pinned columns at their ends, the rest as arranged. */
  visible: C[]
  /** Every movable column in its arranged order, shown or not — what the menu lists. */
  arranged: C[]
  isHidden: (key: string) => boolean
  toggle: (key: string) => void
  /** Move a column to a position in `arranged`. */
  move: (key: string, to: number) => void
  reset: () => void
  customized: boolean
}

export function useColumns<C extends ColumnDef>(listId: string, columns: C[]): Columns<C> {
  const stored = useColumnLayout(listId)
  return useMemo(() => {
    const movable = columns.filter((c) => !c.fixed)
    const first = columns.findIndex((c) => !c.fixed)
    const last = columns.length - 1 - [...columns].reverse().findIndex((c) => !c.fixed)
    const lead = first < 0 ? columns : columns.filter((c, i) => c.fixed && i < first)
    const trail = first < 0 ? [] : columns.filter((c, i) => c.fixed && i > last)

    /* Stored keys that still exist; a column the stored layout has never seen lands at its shipped position. */
    const order = (stored?.order ?? []).filter((k) => movable.some((c) => c.key === k))
    movable.forEach((c, i) => {
      if (!order.includes(c.key)) order.splice(Math.min(i, order.length), 0, c.key)
    })
    const hidden = new Set(
      movable
        .filter((c) => (stored && stored.order.includes(c.key) ? stored.hidden.includes(c.key) : !!c.hidden))
        .map((c) => c.key),
    )
    const arranged = order.map((k) => movable.find((c) => c.key === k)!)
    const save = (nextOrder: string[], nextHidden: Set<string>) =>
      setColumnLayout(listId, { order: nextOrder, hidden: [...nextHidden] })

    return {
      listId,
      visible: [...lead, ...arranged.filter((c) => !hidden.has(c.key)), ...trail],
      arranged,
      isHidden: (key) => hidden.has(key),
      toggle: (key) => {
        const next = new Set(hidden)
        if (next.has(key)) next.delete(key)
        /* A list with no data columns left is not a layout anyone wants. */
        else if (arranged.filter((c) => !next.has(c.key)).length > 1) next.add(key)
        save(order, next)
      },
      move: (key, to) => {
        const next = order.filter((k) => k !== key)
        next.splice(Math.max(0, Math.min(to, next.length)), 0, key)
        save(next, hidden)
      },
      reset: () => setColumnLayout(listId, null),
      customized: stored !== null,
    }
  }, [listId, columns, stored])
}

/* ---- Header ------------------------------------------------------------ */

/**
 * The header row. Movable headers drag onto one another to reorder; with a
 * `sort`, sortable headers also sort on click, the way `SortHeader` does.
 */
export function ColumnHead<C extends ColumnDef, K extends string>({
  cols,
  sort,
  onSort,
}: {
  cols: Columns<C>
  sort?: Sort<K>
  onSort?: (key: K) => void
}) {
  const [dragging, setDragging] = useState<string | null>(null)
  const [over, setOver] = useState<string | null>(null)

  const end = () => {
    setDragging(null)
    setOver(null)
  }

  return (
    <HeadRow>
      {cols.visible.map((col) => {
        const movable = !col.fixed
        const active = sort?.key === col.key
        const canSort = !!sort && !!onSort && col.sortable !== false && !col.rail
        const target = over === col.key && dragging && dragging !== col.key
        /* Drop on a header to its left places the column before it; to its right, after it. */
        const from = cols.arranged.findIndex((c) => c.key === dragging)
        const to = cols.arranged.findIndex((c) => c.key === col.key)
        const marker = target ? (from > to ? 'shadow-[inset_2px_0_0_var(--color-accent)]' : 'shadow-[inset_-2px_0_0_var(--color-accent)]') : ''
        return (
          <Th
            key={col.key}
            width={col.width}
            align={col.align}
            sort={canSort ? (active ? sort!.dir : 'none') : undefined}
            className={`${movable ? 'cursor-grab active:cursor-grabbing' : ''} ${dragging === col.key ? 'opacity-50' : ''} ${marker}`}
            title={movable ? 'Drag to move this column' : undefined}
            draggable={movable}
            onDragStart={
              movable
                ? (e: DragEvent) => {
                    e.dataTransfer.effectAllowed = 'move'
                    e.dataTransfer.setData('text/plain', col.key)
                    setDragging(col.key)
                  }
                : undefined
            }
            onDragOver={
              movable && dragging
                ? (e: DragEvent) => {
                    e.preventDefault()
                    e.dataTransfer.dropEffect = 'move'
                    if (over !== col.key) setOver(col.key)
                  }
                : undefined
            }
            onDrop={
              movable && dragging
                ? (e: DragEvent) => {
                    e.preventDefault()
                    if (dragging !== col.key) cols.move(dragging, to)
                    end()
                  }
                : undefined
            }
            onDragEnd={end}
          >
            {canSort ? (
              <button
                type="button"
                onClick={() => onSort!(col.key as unknown as K)}
                className={`inline-flex items-center gap-1 whitespace-nowrap hover:text-ink-primary ${
                  col.align === 'right' ? 'flex-row-reverse' : ''
                } ${active ? 'text-ink-primary' : ''}`}
              >
                {col.label}
                <span aria-hidden className={active ? '' : 'opacity-30'}>
                  {active && sort!.dir === 'descending' ? '▼' : '▲'}
                </span>
              </button>
            ) : (
              col.label || ' '
            )}
          </Th>
        )
      })}
    </HeadRow>
  )
}

/* ---- Menu -------------------------------------------------------------- */

/** The Columns button and its menu: show or hide each column, move it up or down, or reset. */
export function ColumnsMenu<C extends ColumnDef>({ cols, size = 'sm' }: { cols: Columns<C>; size?: 'sm' | 'md' }) {
  const [open, setOpen] = useState(false)
  const [dragging, setDragging] = useState<string | null>(null)
  const [at, setAt] = useState<{ top?: number; bottom?: number; right: number }>({ right: 0 })
  const box = useRef<HTMLDivElement>(null)
  const button = useRef<HTMLButtonElement>(null)

  /* Panels clip their contents, so the menu is placed against the viewport, not
     the panel: below the button, or above it when the space below is short. */
  function place() {
    const r = button.current?.getBoundingClientRect()
    if (!r) return
    const right = window.innerWidth - r.right
    setAt(window.innerHeight - r.bottom < 380 && r.top > window.innerHeight - r.bottom ? { bottom: window.innerHeight - r.top + 4, right } : { top: r.bottom + 4, right })
  }

  useEffect(() => {
    if (!open) return
    const onDown = (e: MouseEvent) => {
      if (box.current && !box.current.contains(e.target as Node)) setOpen(false)
    }
    const onKey = (e: KeyboardEvent) => e.key === 'Escape' && setOpen(false)
    /* A fixed menu follows its button when the page scrolls or resizes under it. */
    const onMove = (e: Event) => {
      if (!box.current?.contains(e.target as Node)) place()
    }
    window.addEventListener('mousedown', onDown)
    window.addEventListener('keydown', onKey)
    window.addEventListener('scroll', onMove, true)
    window.addEventListener('resize', onMove)
    return () => {
      window.removeEventListener('mousedown', onDown)
      window.removeEventListener('keydown', onKey)
      window.removeEventListener('scroll', onMove, true)
      window.removeEventListener('resize', onMove)
    }
  }, [open])

  const shown = cols.arranged.filter((c) => !cols.isHidden(c.key)).length
  const height = size === 'md' ? 'h-7 text-data' : 'h-6 text-micro'

  return (
    <div ref={box} className="relative">
      <button
        ref={button}
        type="button"
        onClick={() => {
          if (!open) place()
          setOpen((o) => !o)
        }}
        aria-expanded={open}
        aria-haspopup="dialog"
        className={`inline-flex ${height} items-center gap-1.5 rounded-sm border border-rule-solid bg-surface-raised px-2 text-ink-secondary hover:bg-surface-sunken hover:text-ink-primary ${
          cols.customized ? 'border-accent text-accent-text' : ''
        }`}
        title="Choose and arrange columns"
      >
        <svg width="12" height="12" viewBox="0 0 12 12" aria-hidden>
          <path d="M1.5 1.5h2.5v9H1.5zM4.75 1.5h2.5v9h-2.5zM8 1.5h2.5v9H8z" fill="none" stroke="currentColor" strokeWidth="1.1" />
        </svg>
        Columns
        {cols.customized ? <span className="sr-only">(customized)</span> : null}
      </button>
      {open ? (
        <div
          role="dialog"
          aria-label="Columns"
          style={{ position: 'fixed', ...at }}
          className="z-50 w-64 rounded-md border border-rule-hair bg-surface-raised shadow-modal"
        >
          <p className="border-b border-rule-hair px-3 py-2 text-micro text-ink-tertiary">
            {shown} of {cols.arranged.length} shown · drag a row or a header to move it
          </p>
          <ul className="max-h-80 overflow-y-auto py-1">
            {cols.arranged.map((c, i) => {
              const off = cols.isHidden(c.key)
              const id = `col-${cols.listId}-${c.key}`
              return (
                <li
                  key={c.key}
                  draggable
                  onDragStart={(e) => {
                    e.dataTransfer.effectAllowed = 'move'
                    e.dataTransfer.setData('text/plain', c.key)
                    setDragging(c.key)
                  }}
                  onDragOver={(e) => dragging && e.preventDefault()}
                  onDrop={(e) => {
                    e.preventDefault()
                    if (dragging && dragging !== c.key) cols.move(dragging, i)
                    setDragging(null)
                  }}
                  onDragEnd={() => setDragging(null)}
                  className={`flex items-center gap-2 px-2 py-1 hover:bg-surface-sunken ${dragging === c.key ? 'opacity-50' : ''}`}
                >
                  <span aria-hidden className="cursor-grab select-none text-ink-muted">⋮⋮</span>
                  <input
                    id={id}
                    type="checkbox"
                    checked={!off}
                    disabled={!off && shown === 1}
                    onChange={() => cols.toggle(c.key)}
                  />
                  <label htmlFor={id} className={`flex-1 truncate text-data ${off ? 'text-ink-tertiary' : 'text-ink-primary'}`}>
                    {c.menuLabel ?? c.label}
                  </label>
                  <button
                    type="button"
                    onClick={() => cols.move(c.key, i - 1)}
                    disabled={i === 0}
                    aria-label={`Move ${c.menuLabel ?? c.label} up`}
                    className="h-5 w-5 rounded-xs text-micro text-ink-tertiary hover:bg-surface-inset hover:text-ink-primary disabled:opacity-30"
                  >
                    ↑
                  </button>
                  <button
                    type="button"
                    onClick={() => cols.move(c.key, i + 1)}
                    disabled={i === cols.arranged.length - 1}
                    aria-label={`Move ${c.menuLabel ?? c.label} down`}
                    className="h-5 w-5 rounded-xs text-micro text-ink-tertiary hover:bg-surface-inset hover:text-ink-primary disabled:opacity-30"
                  >
                    ↓
                  </button>
                </li>
              )
            })}
          </ul>
          <div className="flex justify-end border-t border-rule-hair px-3 py-2">
            <button
              type="button"
              onClick={cols.reset}
              disabled={!cols.customized}
              className="text-micro text-accent-text underline hover:text-accent-text-hover disabled:text-ink-muted disabled:no-underline"
            >
              Reset to default
            </button>
          </div>
        </div>
      ) : null}
    </div>
  )
}

/* ---- Server-rendered lists --------------------------------------------- */

export type ColumnRow =
  | { key: string; cells: Record<string, ReactNode>; selected?: boolean; muted?: boolean }
  /** A full-width row — a group heading, a note — that spans whatever columns are showing. */
  | { key: string; full: ReactNode; className?: string }

/**
 * A list whose rows are rendered on the server: the page passes each cell
 * already rendered, keyed by column, and this arranges them. The Columns
 * menu sits in a slim strip above the table, after anything in `toolbar`.
 */
export function ColumnTable({
  listId,
  caption,
  columns,
  rows,
  empty,
  toolbar,
  fill = false,
}: {
  listId: string
  caption: string
  columns: ColumnDef[]
  rows: ColumnRow[]
  empty?: ReactNode
  toolbar?: ReactNode
  /** Take the rest of a flex column: the strip stays put, the table scrolls under a sticky header. */
  fill?: boolean
}) {
  const cols = useColumns(listId, columns)
  const Wrap = fill ? 'div' : Fragment
  return (
    <Wrap {...(fill ? { className: 'flex min-h-0 flex-1 flex-col' } : {})}>
      <div className="flex flex-wrap items-center gap-x-3 gap-y-1.5 border-b border-rule-hair bg-surface px-cell-x py-1.5">
        {toolbar}
        <div className="ml-auto">
          <ColumnsMenu cols={cols} />
        </div>
      </div>
      <Table caption={caption} className={fill ? 'min-h-0 flex-1 overflow-auto [&_thead]:sticky [&_thead]:top-0 [&_thead]:z-10' : undefined}>
        <thead>
          <ColumnHead cols={cols} />
        </thead>
        <tbody>
          {rows.map((r) =>
            'full' in r ? (
              <tr key={r.key} className={r.className}>
                <td colSpan={cols.visible.length}>{r.full}</td>
              </tr>
            ) : (
              <Row key={r.key} selected={r.selected} muted={r.muted}>
                {cols.visible.map((c) =>
                  c.rail ? (
                    <RailCell key={c.key}>{r.cells[c.key]}</RailCell>
                  ) : (
                    <Td key={c.key} align={c.align} className={c.cellClassName}>
                      {r.cells[c.key] ?? null}
                    </Td>
                  ),
                )}
              </Row>
            ),
          )}
          {rows.length === 0 && empty ? (
            <Row>
              <Td colSpan={cols.visible.length} className="py-6 text-center text-ink-tertiary">
                {empty}
              </Td>
            </Row>
          ) : null}
        </tbody>
      </Table>
    </Wrap>
  )
}
