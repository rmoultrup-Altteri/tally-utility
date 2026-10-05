import type { ReactNode } from 'react'
import { BackLink } from '@/components/shell/BackLink'

/**
 * The page header strip that sits under the shell chrome.
 *
 * Detail screens pass `back`, the parent to return to when there is no
 * in-app page behind this one; the arrow otherwise goes wherever the operator
 * came from. Actions sit top right, the edit button last.
 */
export function PageHeader({
  title,
  meta,
  actions,
  back,
}: {
  title: ReactNode
  meta?: ReactNode
  actions?: ReactNode
  back?: { href: string; label: string }
}) {
  return (
    <header className="flex items-start justify-between gap-6 border-b border-rule-hair bg-surface-raised px-5 py-3.5">
      <div className="flex min-w-0 items-start gap-3">
        {back ? <BackLink href={back.href} label={back.label} /> : null}
        <div className="min-w-0">
          <h1 className="text-h1 text-ink-primary">{title}</h1>
          {meta ? <div className="mt-1 text-micro text-ink-tertiary">{meta}</div> : null}
        </div>
      </div>
      {actions ? <div className="flex items-center gap-2 shrink-0">{actions}</div> : null}
    </header>
  )
}
