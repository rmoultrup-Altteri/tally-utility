import Link from 'next/link'
import type { Route } from 'next'

/**
 * The "New …" button at the top right of a record list, as a link so it opens in a new tab too.
 * `secondary` is for a less common way in that sits beside the main one.
 */
export function NewRecordLink({ href, children, variant = 'primary' }: { href: string; children: string; variant?: 'primary' | 'secondary' }) {
  const tone =
    variant === 'primary'
      ? 'border-accent bg-accent text-ink-inverse hover:border-accent-hover hover:bg-accent-hover'
      : 'border-rule-solid bg-surface-raised text-ink-primary hover:border-rule-heavy hover:bg-surface-sunken'
  return (
    <Link
      href={href as Route}
      className={`inline-flex h-8 items-center justify-center gap-1.5 rounded-sm border px-3.5 text-data font-medium transition-colors duration-fast ${tone}`}
    >
      <span aria-hidden className="text-[15px] leading-none">+</span>
      {children}
    </Link>
  )
}
