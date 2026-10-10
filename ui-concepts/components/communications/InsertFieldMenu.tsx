'use client'

import { useEffect, useRef, useState } from 'react'
import { MERGE_FIELDS, MERGE_GROUPS, type MergeContext } from '@/lib/templates'

/**
 * Insert field — one button, a searchable list behind it.
 *
 * Thirty-seven fields laid out as buttons is a wall a writer has to read past
 * every time they look at their own words. Behind a menu, the editor is the
 * words, and the fields are one keystroke away: type to filter, arrows to
 * move, Enter to insert at the cursor. Each row shows what the field will say
 * for the account being previewed, which is how a writer knows they picked
 * "amount due" and not "this period's charges".
 */
export function InsertFieldMenu({
  ctx,
  disabled,
  onInsert,
}: {
  ctx: MergeContext
  disabled?: boolean
  onInsert: (token: string) => void
}) {
  const [open, setOpen] = useState(false)
  const [q, setQ] = useState('')
  const [at, setAt] = useState(0)
  const box = useRef<HTMLDivElement>(null)
  const search = useRef<HTMLInputElement>(null)

  const terms = q.trim().toLowerCase().split(/\s+/).filter(Boolean)
  const matches = MERGE_FIELDS.filter((f) => {
    const hay = `${f.label} ${f.key} ${f.group}`.toLowerCase()
    return terms.every((t) => hay.includes(t))
  })

  useEffect(() => {
    if (!open) return
    search.current?.focus()
    const onDown = (e: MouseEvent) => {
      if (box.current && !box.current.contains(e.target as Node)) setOpen(false)
    }
    window.addEventListener('mousedown', onDown)
    return () => window.removeEventListener('mousedown', onDown)
  }, [open])

  function pick(key: string) {
    onInsert(`{{${key}}}`)
    setOpen(false)
    setQ('')
    setAt(0)
  }

  return (
    <div ref={box} className="relative">
      <button
        type="button"
        disabled={disabled}
        aria-haspopup="listbox"
        aria-expanded={open}
        /* Keep the textarea's cursor where it was: a mousedown here would otherwise blur it first. */
        onMouseDown={(e) => e.preventDefault()}
        onClick={() => setOpen((o) => !o)}
        className="inline-flex h-6 items-center gap-1 rounded-full border border-rule-solid bg-surface-raised px-2.5 text-micro text-ink-secondary hover:border-accent hover:text-accent-text disabled:opacity-45"
      >
        <span aria-hidden className="ident">{'{ }'}</span> Insert field
      </button>
      {open ? (
        <div className="absolute right-0 z-30 mt-1 w-80 overflow-clip rounded-md border border-rule-hair bg-surface-raised shadow-overlay">
          <div className="border-b border-rule-hair p-2">
            <label htmlFor="field-search" className="sr-only">
              Search merge fields
            </label>
            <input
              id="field-search"
              ref={search}
              value={q}
              placeholder="Search fields — amount, due, name…"
              onChange={(e) => {
                setQ(e.target.value)
                setAt(0)
              }}
              onKeyDown={(e) => {
                if (e.key === 'ArrowDown') {
                  e.preventDefault()
                  setAt((i) => Math.min(i + 1, matches.length - 1))
                } else if (e.key === 'ArrowUp') {
                  e.preventDefault()
                  setAt((i) => Math.max(i - 1, 0))
                } else if (e.key === 'Enter' && matches[at]) {
                  e.preventDefault()
                  pick(matches[at].key)
                } else if (e.key === 'Escape') setOpen(false)
              }}
              className="h-7 w-full rounded-full border border-rule-solid bg-surface px-3 text-data text-ink-primary placeholder:text-ink-muted"
            />
          </div>
          <ul role="listbox" aria-label="Merge fields" className="max-h-72 overflow-y-auto py-1">
            {MERGE_GROUPS.map((g) => {
              const inGroup = matches.filter((f) => f.group === g)
              if (!inGroup.length) return null
              return (
                <li key={g}>
                  <p className="field-label px-3 pt-2 pb-0.5">{g}</p>
                  <ul>
                    {inGroup.map((f) => {
                      const active = matches[at]?.key === f.key
                      return (
                        <li key={f.key} role="option" aria-selected={active}>
                          <button
                            type="button"
                            onMouseDown={(e) => e.preventDefault()}
                            onMouseEnter={() => setAt(matches.indexOf(f))}
                            onClick={() => pick(f.key)}
                            className={`flex w-full items-baseline justify-between gap-3 px-3 py-1 text-left ${active ? 'bg-accent-wash' : ''}`}
                          >
                            <span className="text-data text-ink-primary">{f.label}</span>
                            <span className="min-w-0 truncate text-micro text-ink-tertiary">{ctx[f.key]}</span>
                          </button>
                        </li>
                      )
                    })}
                  </ul>
                </li>
              )
            })}
            {matches.length === 0 ? <li className="px-3 py-3 text-micro text-ink-tertiary">No field matches “{q}”.</li> : null}
          </ul>
          <p className="border-t border-rule-hair px-3 py-1.5 text-micro text-ink-tertiary">↑↓ to move · Enter to insert · Esc to close</p>
        </div>
      ) : null}
    </div>
  )
}
