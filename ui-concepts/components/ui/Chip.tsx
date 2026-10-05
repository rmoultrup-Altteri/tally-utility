import type { ReactNode } from 'react'

/** A labelled run of filter chips on a record list's filter bar. */
export function Group({ label, children }: { label: string; children: ReactNode }) {
  return (
    <div className="flex items-center gap-1.5">
      <span className="field-label">{label}</span>
      {children}
    </div>
  )
}

export function Chip({ on, onClick, children }: { on: boolean; onClick: () => void; children: ReactNode }) {
  return (
    <button
      type="button"
      onClick={onClick}
      aria-pressed={on}
      className={`inline-flex h-6 items-center gap-1 rounded-full border px-2.5 text-micro transition-colors duration-fast ${
        on
          ? 'border-accent/50 bg-accent-wash text-accent-text font-medium'
          : 'border-rule-solid bg-surface-raised text-ink-secondary hover:bg-surface-sunken hover:text-ink-primary'
      }`}
    >
      {on ? (
        <svg width="10" height="10" viewBox="0 0 12 12" fill="none" aria-hidden>
          <path d="M2.5 6.5l2.5 2.5 4.5-5.5" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" />
        </svg>
      ) : null}
      {children}
    </button>
  )
}
