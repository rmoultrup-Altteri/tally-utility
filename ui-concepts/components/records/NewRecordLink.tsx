import Link from 'next/link'
import type { Route } from 'next'

/** The "New …" button at the top right of a record list, as a link so it opens in a new tab too. */
export function NewRecordLink({ href, children }: { href: string; children: string }) {
  return (
    <Link
      href={href as Route}
      className="inline-flex h-8 items-center justify-center gap-1.5 rounded-sm border border-accent bg-accent px-3.5 text-data font-medium text-ink-inverse transition-colors duration-fast hover:border-accent-hover hover:bg-accent-hover"
    >
      <span aria-hidden className="text-[15px] leading-none">+</span>
      {children}
    </Link>
  )
}
