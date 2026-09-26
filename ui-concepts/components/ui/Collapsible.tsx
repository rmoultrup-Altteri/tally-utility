import type { ReactNode } from 'react'

/**
 * A panel that shows only its title, a count and a one-line summary until it
 * is opened.
 *
 * Built on <details>, so it opens and closes without client JavaScript, is
 * keyboard-operable as-is, and the browser's find-in-page still reaches the
 * rows inside a closed section.
 */
export function Collapsible({
  title,
  n,
  tone = 'neutral',
  summary,
  actions,
  defaultOpen = false,
  children,
}: {
  title: ReactNode
  /** The number after the title — what this section is holding right now. */
  n: number
  /** `alert` colours the count when it is something an operator must act on. */
  tone?: 'neutral' | 'alert'
  summary?: ReactNode
  /** Controls that belong to the open section. Kept out of the summary so clicking them never toggles it. */
  actions?: ReactNode
  defaultOpen?: boolean
  children: ReactNode
}) {
  return (
    <details open={defaultOpen} className="group bg-surface-raised border border-rule-solid">
      <summary className="flex cursor-pointer list-none items-baseline gap-3 px-4 py-2.5 hover:bg-surface-sunken [&::-webkit-details-marker]:hidden">
        <span
          aria-hidden
          className="inline-block w-3 text-ink-tertiary transition-transform duration-fast group-open:rotate-90"
        >
          ▸
        </span>
        <h2 className="text-h3 text-ink-primary">{title}</h2>
        <span
          className={`ident rounded-xs px-1.5 ${
            tone === 'alert' && n > 0
              ? 'bg-exception-critical-wash text-exception-critical-text'
              : 'bg-surface-sunken text-ink-primary'
          }`}
        >
          {n}
        </span>
        {summary ? <span className="min-w-0 truncate text-micro text-ink-tertiary">{summary}</span> : null}
        <span className="ml-auto shrink-0 text-micro text-ink-secondary">
          <span className="group-open:hidden">Expand</span>
          <span className="hidden group-open:inline">Collapse</span>
        </span>
      </summary>
      <div className="border-t border-rule-solid">
        {actions ? (
          <div className="flex items-center justify-end gap-2 border-b border-rule-hair bg-surface px-4 py-2">
            {actions}
          </div>
        ) : null}
        {children}
      </div>
    </details>
  )
}
