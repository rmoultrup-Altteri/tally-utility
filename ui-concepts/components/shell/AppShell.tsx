import Link from 'next/link'
import type { Route } from 'next'
import type { ReactNode } from 'react'
import { asOf, currentUser, cycle, tenant } from '@/fixtures/tenant'
import { blockingCount, openExceptions } from '@/fixtures/exceptions'
import { date } from '@/lib/format'
import { QuickFind } from '@/components/shell/QuickFind'
import { ThemeControl } from '@/components/shell/ThemeControl'

/**
 * The application frame.
 *
 * Two pieces of persistent chrome matter more than the navigation itself:
 * the as-of coordinate, which must be impossible to mistake for live when it
 * is not, and the cycle the operator is standing in.
 */

type NavItem = { href: Route; label: string; badge?: 'open' }

const NAV: NavItem[] = [
  { href: '/dashboard', label: 'Dashboard' },
  { href: '/', label: 'Exceptions', badge: 'open' },
  { href: '/reads', label: 'Read validation' },
  { href: '/runs/run-2026-02-04' as Route, label: 'Billing run' },
  { href: '/invoices/inv-0001' as Route, label: 'Bills' },
  { href: '/collections', label: 'Collections' },
  { href: '/rates', label: 'Rates & tariffs' },
  { href: '/rates/pga', label: 'PGA console' },
  { href: '/rates/sandbox', label: 'Tariff sandbox' },
  { href: '/customers/cus-0001' as Route, label: 'Accounts' },
]

export function AppShell({
  children,
  current,
}: {
  children: ReactNode
  current: string
}) {
  return (
    <div className="min-h-screen flex flex-col">
      <AsOfBand />
      <div className="flex flex-1 min-h-0">
        <Sidebar current={current} />
        <div className="flex-1 min-w-0 flex flex-col">{children}</div>
      </div>
    </div>
  )
}

/**
 * When the as-of coordinate is anything but today, the whole application must
 * change appearance. A historical view mistaken for a live one is a billing
 * error, and the database's own as-of functions refuse to fall back to current
 * values for the same reason — the UI carries the same discipline.
 */
function AsOfBand() {
  if (asOf.isToday) {
    return (
      <div className="flex items-center justify-between gap-4 border-b border-rule-solid bg-surface-ink px-4 py-1.5 text-ink-inverse">
        <div className="flex items-baseline gap-3">
          <span className="text-h3 tracking-tight">{tenant.name}</span>
          <span className="text-micro opacity-70">{tenant.jurisdiction}</span>
        </div>
        <div className="flex items-center gap-4 text-micro">
          <span className="opacity-70 hidden lg:inline">
            {cycle.label} · {cycle.periodLabel} · {date(cycle.periodStart)} → {date(cycle.periodEnd)}
          </span>
          <QuickFind />
          <span className="flex h-5 w-5 items-center justify-center rounded-xs bg-surface-raised text-ink-primary text-micro font-semibold">
            {currentUser.initials}
          </span>
        </div>
      </div>
    )
  }
  return (
    <div className="border-b border-exception-info-rail bg-exception-info-wash px-4 py-1.5">
      <p className="text-micro text-exception-info-text">
        Viewing as of {date(asOf.validAt)} · <Link href="/" className="underline">Return to today</Link>
      </p>
    </div>
  )
}

function Sidebar({ current }: { current: string }) {
  return (
    <nav
      aria-label="Main"
      className="w-52 shrink-0 border-r border-rule-solid bg-surface flex flex-col"
    >
      <div className="px-3 py-3 border-b border-rule-hair">
        <p className="label-caps">As of</p>
        <p className="text-data text-ink-primary mt-0.5">{date(asOf.validAt)}</p>
        <p className="text-micro text-ink-tertiary mt-0.5">
          recorded {new Date(asOf.recordedAt).toLocaleTimeString('en-US', {
            hour: 'numeric',
            minute: '2-digit',
          })}
        </p>
      </div>

      <ul className="py-2 flex-1">
        {NAV.map((item) => {
          const active = item.label === current
          return (
            <li key={item.href}>
              <Link
                href={item.href}
                aria-current={active ? 'page' : undefined}
                className={`flex items-center justify-between gap-2 px-3 py-1.5 text-data border-l-[3px] transition-colors duration-fast ${
                  active
                    ? 'border-accent bg-accent-wash text-ink-primary font-medium'
                    : 'border-transparent text-ink-secondary hover:bg-surface-sunken hover:text-ink-primary'
                }`}
              >
                <span>{item.label}</span>
                {item.badge === 'open' && openExceptions.length > 0 ? (
                  <span
                    className="ident text-exception-critical-text"
                    title={`${blockingCount} of these block delivery`}
                  >
                    {openExceptions.length}
                  </span>
                ) : null}
              </Link>
            </li>
          )
        })}
      </ul>

      <div className="border-t border-rule-hair px-3 py-2.5">
        <ThemeControl />
      </div>

      <div className="border-t border-rule-hair px-3 py-2.5">
        <p className="text-micro text-ink-primary">{currentUser.name}</p>
        <p className="text-micro text-ink-tertiary">{currentUser.role}</p>
      </div>
    </nav>
  )
}

/** The page header strip that sits under the shell chrome. */
export function PageHeader({
  title,
  meta,
  actions,
}: {
  title: ReactNode
  meta?: ReactNode
  actions?: ReactNode
}) {
  return (
    <header className="flex items-start justify-between gap-6 border-b border-rule-solid bg-surface-raised px-5 py-3">
      <div className="min-w-0">
        <h1 className="text-h1 text-ink-primary">{title}</h1>
        {meta ? <div className="mt-1 text-micro text-ink-tertiary">{meta}</div> : null}
      </div>
      {actions ? <div className="flex items-center gap-2 shrink-0">{actions}</div> : null}
    </header>
  )
}
