'use client'

import { useEffect, useState } from 'react'
import Link from 'next/link'
import type { Route } from 'next'
import { usePathname, useRouter } from 'next/navigation'

/**
 * The back arrow on a detail screen.
 *
 * Back means "where I just was", which is not always the parent: a bill
 * opened from an account goes back to the account, the same bill opened from
 * the Bills list goes back to the list. When there is no in-app page behind
 * this one — a pasted link, a fresh tab — it falls back to the screen's
 * parent, so the arrow never leaves the application.
 */

const KEY = 'tu-nav'

/** Screen names for the tooltip, by route shape. Most specific first. */
const NAMES: [RegExp, string][] = [
  [/^\/invoices\/[^/]+\/diff/, 'the comparison'],
  [/^\/invoices\/[^/]+\/rebill/, 'the rebill'],
  [/^\/invoices\/[^/]+/, 'the bill'],
  [/^\/invoices/, 'Bills'],
  [/^\/customers\/[^/]+/, 'the account'],
  [/^\/customers/, 'Accounts'],
  [/^\/payments\/new/, 'Add payment'],
  [/^\/payments/, 'Payments'],
  [/^\/runs\//, 'the billing run'],
  [/^\/rates\/pga/, 'the PGA console'],
  [/^\/rates\/sandbox/, 'the tariff sandbox'],
  [/^\/rates/, 'Rates & tariffs'],
  [/^\/reads/, 'Read validation'],
  [/^\/collections/, 'Collections'],
  [/^\/dashboard/, 'the dashboard'],
  [/^\/$/, 'Exceptions'],
]

const nameOf = (path: string) => NAMES.find(([re]) => re.test(path.split('?')[0]))?.[1] ?? 'the previous page'

function readStack(): string[] {
  try {
    const raw = window.sessionStorage.getItem(KEY)
    const parsed = raw ? JSON.parse(raw) : []
    return Array.isArray(parsed) ? parsed : []
  } catch {
    return []
  }
}

/**
 * Records in-app navigation so the arrow knows whether there is somewhere to
 * go back to. Mounted once, in the root layout. Going back pops rather than
 * pushes, so the stack follows the browser's own history.
 */
export function NavTracker() {
  const pathname = usePathname()
  useEffect(() => {
    const here = pathname + window.location.search
    const stack = readStack()
    const top = stack[stack.length - 1]
    if (top?.split('?')[0] === pathname) stack[stack.length - 1] = here
    else if (stack[stack.length - 2]?.split('?')[0] === pathname) stack.pop()
    else stack.push(here)
    try {
      window.sessionStorage.setItem(KEY, JSON.stringify(stack.slice(-50)))
    } catch {
      /* Storage denied: the arrow falls back to the parent screen. */
    }
  }, [pathname])
  return null
}

export function BackLink({ href, label }: { href: string; label: string }) {
  const router = useRouter()
  const pathname = usePathname()
  const [previous, setPrevious] = useState<string | null>(null)

  /* Page effects run before the layout's tracker, so the stack may not hold
     this page yet. Work out the page behind this one either way: already
     recorded, about to be popped (we came back here), or about to be pushed. */
  useEffect(() => {
    const stack = readStack().map((p) => ({ full: p, path: p.split('?')[0] }))
    const n = stack.length
    const prev =
      stack[n - 1]?.path === pathname
        ? stack[n - 2]
        : stack[n - 2]?.path === pathname
          ? stack[n - 3]
          : stack[n - 1]
    setPrevious(prev && prev.path !== pathname ? prev.full : null)
  }, [pathname])

  const cls =
    'mt-0.5 flex h-7 w-7 shrink-0 items-center justify-center rounded-full border border-rule-solid bg-surface-raised text-ink-secondary transition-colors duration-fast hover:border-rule-heavy hover:bg-surface-sunken hover:text-ink-primary'
  const arrow = (
    <svg width="14" height="14" viewBox="0 0 16 16" fill="none" aria-hidden>
      <path d="M9.5 3.5L5 8l4.5 4.5M5.5 8H13" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  )

  if (previous) {
    const to = `Back to ${nameOf(previous)}`
    return (
      <button type="button" onClick={() => router.back()} aria-label={to} title={to} className={cls}>
        {arrow}
      </button>
    )
  }
  return (
    <Link href={href as Route} aria-label={`Back to ${label}`} title={`Back to ${label}`} className={cls}>
      {arrow}
    </Link>
  )
}
