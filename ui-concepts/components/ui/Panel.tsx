import type { ReactNode } from 'react'

/**
 * Panels sit on rules, never on shadows. A panel is white stock on the warm
 * paper ground, which reads as raised without any elevation trick.
 */
export function Panel({
  children,
  className = '',
}: {
  children: ReactNode
  className?: string
}) {
  return (
    <section className={`bg-surface-raised border border-rule-solid ${className}`}>
      {children}
    </section>
  )
}

export function PanelHeader({
  title,
  meta,
  actions,
}: {
  title: ReactNode
  meta?: ReactNode
  actions?: ReactNode
}) {
  return (
    <header className="flex items-baseline justify-between gap-4 border-b border-rule-solid px-4 py-2.5">
      <div className="flex items-baseline gap-3 min-w-0">
        <h2 className="text-h3 text-ink-primary truncate">{title}</h2>
        {meta ? <span className="text-micro text-ink-tertiary truncate">{meta}</span> : null}
      </div>
      {actions ? <div className="flex items-center gap-2 shrink-0">{actions}</div> : null}
    </header>
  )
}

/** A labelled value in a definition grid. The label is always present. */
export function Field({
  label,
  children,
  hint,
}: {
  label: string
  children: ReactNode
  hint?: string
}) {
  return (
    <div className="min-w-0">
      <dt className="label-caps mb-0.5">{label}</dt>
      <dd className="text-data text-ink-primary break-words">{children}</dd>
      {hint ? <p className="text-micro text-ink-tertiary mt-0.5">{hint}</p> : null}
    </div>
  )
}

export function FieldGrid({
  children,
  cols = 3,
}: {
  children: ReactNode
  cols?: 2 | 3 | 4
}) {
  const grid = cols === 2 ? 'sm:grid-cols-2' : cols === 4 ? 'sm:grid-cols-4' : 'sm:grid-cols-3'
  return <dl className={`grid grid-cols-1 ${grid} gap-x-6 gap-y-4`}>{children}</dl>
}

/** Buttons. Primary is the single accent; everything else is a ruled surface. */
export function Button({
  children,
  variant = 'default',
  disabled = false,
  title,
  type = 'button',
  onClick,
}: {
  children: ReactNode
  variant?: 'default' | 'primary' | 'danger' | 'quiet'
  disabled?: boolean
  title?: string
  type?: 'button' | 'submit'
  onClick?: () => void
}) {
  const base =
    'inline-flex items-center gap-1.5 px-3 h-7 text-data rounded-xs border transition-colors duration-fast disabled:opacity-45 disabled:cursor-not-allowed'
  const styles = {
    default:
      'bg-surface-raised border-rule-solid text-ink-primary hover:bg-surface-sunken hover:border-rule-heavy',
    primary:
      'bg-accent border-accent text-ink-inverse hover:bg-accent-hover hover:border-accent-hover',
    danger:
      'bg-surface-raised border-exception-critical-rail text-exception-critical-text hover:bg-exception-critical-wash',
    quiet:
      'bg-transparent border-transparent text-ink-secondary hover:bg-surface-sunken hover:text-ink-primary',
  }[variant]
  return (
    <button
      type={type}
      disabled={disabled}
      title={title}
      onClick={onClick}
      className={`${base} ${styles}`}
    >
      {children}
    </button>
  )
}

/** A keyboard hint. These users work by keyboard; the affordance should show. */
export function Key({ children }: { children: ReactNode }) {
  return (
    <kbd className="ident inline-flex h-4 min-w-4 items-center justify-center rounded-xs border border-rule-solid bg-surface-inset px-1 text-ink-secondary">
      {children}
    </kbd>
  )
}
