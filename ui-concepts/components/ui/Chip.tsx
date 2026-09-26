import type { ReactNode } from 'react'

/** A labelled run of filter chips on a record list's filter bar. */
export function Group({ label, children }: { label: string; children: ReactNode }) {
  return (
    <div className="flex items-center gap-1.5">
      <span className="label-caps">{label}</span>
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
      className={`h-5 rounded-xs border px-1.5 text-micro transition-colors duration-fast ${
        on
          ? 'border-accent bg-accent-wash text-ink-primary font-medium'
          : 'border-rule-solid bg-surface-raised text-ink-secondary hover:bg-surface-sunken hover:text-ink-primary'
      }`}
    >
      {children}
    </button>
  )
}
