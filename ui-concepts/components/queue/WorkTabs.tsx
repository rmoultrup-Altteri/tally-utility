import Link from 'next/link'
import type { Route } from 'next'
import { openExceptions } from '@/fixtures/exceptions'
import { transfersNeedingAttention } from '@/lib/transfers'

/**
 * The work queues that sit under Exceptions: the pre-mail exceptions that
 * hold the run, and the transfers of service waiting on a decision. One strip
 * on both pages, so the analyst clearing the morning's work sees both counts
 * from either side.
 */
export function WorkTabs({ current }: { current: 'exceptions' | 'transfers' }) {
  const tabs = [
    { key: 'exceptions', href: '/', label: 'Pre-mail exceptions', count: openExceptions.length, title: 'Open exceptions on this cycle' },
    { key: 'transfers', href: '/transfers', label: 'Transfers', count: transfersNeedingAttention(), title: 'Transfers blocked or waiting on a review' },
  ] as const
  return (
    <nav aria-label="Work queues" className="flex gap-1 border-b border-rule-hair bg-surface-raised px-5">
      {tabs.map((t) => {
        const on = t.key === current
        return (
          <Link
            key={t.key}
            href={t.href as Route}
            aria-current={on ? 'page' : undefined}
            title={t.title}
            className={`-mb-px flex items-center gap-2 border-b-2 px-2.5 py-2 text-data transition-colors duration-fast ${
              on ? 'border-accent text-ink-primary font-medium' : 'border-transparent text-ink-secondary hover:text-ink-primary'
            }`}
          >
            {t.label}
            {t.count > 0 ? (
              <span className="figures rounded-full bg-surface-inset px-1.5 text-micro text-ink-secondary">{t.count}</span>
            ) : null}
          </Link>
        )
      })}
    </nav>
  )
}
