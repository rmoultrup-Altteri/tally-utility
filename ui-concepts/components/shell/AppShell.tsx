import { Suspense } from 'react'
import Link from 'next/link'
import type { ReactNode } from 'react'
import { asOf, cycle, tenant } from '@/fixtures/tenant'
import { blockingCount, openExceptions } from '@/fixtures/exceptions'
import { outreachSummary } from '@/fixtures/outreach'
import { date } from '@/lib/format'
import { QuickFind } from '@/components/shell/QuickFind'
import { DensityControl, ThemeControl } from '@/components/shell/ThemeControl'
import { SidebarNav, type NavGroup } from '@/components/shell/SidebarNav'
import { Favorites } from '@/components/shell/Favorites'
import { TallyLogo } from '@/components/shell/TallyLogo'
import { TenantLogo } from '@/components/shell/TenantLogo'
import { UserMenu } from '@/components/shell/UserMenu'

/**
 * The application frame.
 *
 * The frame is exactly one viewport tall and never scrolls: the as-of band,
 * the page header and the sidebar stay put, and only the page body beneath the
 * header scrolls. Navigation and favorites are always where the hand expects.
 *
 * The band, the sidebar and the page sit as three rounded cards on an inset
 * ground, with a small gutter between them.
 *
 * Two pieces of persistent chrome matter more than the navigation itself:
 * the as-of coordinate, which must be impossible to mistake for live when it
 * is not, and the cycle the operator is standing in.
 */

/**
 * Navigation by job, not by table. The groups are the questions an operator
 * arrives with: what needs doing today, who is this customer, where is the
 * cycle, what are we charging, and where is the reference material.
 */
function navGroups(): NavGroup[] {
  return [
    {
      key: 'today',
      pinned: true,
      label: 'Today',
      items: [
        { href: '/dashboard', label: 'Dashboard' },
        {
          href: '/',
          label: 'Exceptions',
          badge: { count: openExceptions.length, tone: 'critical', title: `${blockingCount} of these block delivery` },
        },
        {
          href: '/outreach',
          label: 'High-bill outreach',
          badge: { count: outreachSummary.toContact, tone: 'warning', title: `${outreachSummary.toContact} customers to tell before bills post` },
        },
      ],
    },
    {
      key: 'customers',
      label: 'Customers',
      items: [
        { href: '/customers', label: 'Accounts' },
        { href: '/meters', label: 'Meters' },
        { href: '/payments', label: 'Payments' },
        { href: '/collections', label: 'Collections' },
      ],
    },
    {
      key: 'billing',
      label: 'Billing',
      items: [
        { href: '/invoices', label: 'Bills' },
        { href: '/runs/run-2026-02-04', label: 'Billing run' },
        { href: '/reads', label: 'Read validation' },
      ],
    },
    {
      key: 'rates',
      label: 'Rates',
      items: [
        { href: '/rates', label: 'Rates & tariffs' },
        { href: '/rates/pga', label: 'PGA console' },
        { href: '/rates/rate-case', label: 'Rate case toolkit' },
      ],
    },
    {
      key: 'library',
      label: 'Library',
      items: [
        { href: '/reports', label: 'Reports' },
        /* Every message a customer receives — every screen above sends from it. */
        { href: '/communications', label: 'Communications' },
      ],
    },
  ]
}

export function AppShell({
  children,
  current,
}: {
  children: ReactNode
  current: string
}) {
  return (
    <div className="relative h-dvh flex flex-col gap-2 overflow-clip bg-surface-inset p-2">
      <AsOfBand />
      <div className="flex flex-1 min-h-0 gap-2">
        <Sidebar current={current} />
        <div className="relative flex-1 min-w-0 min-h-0 flex flex-col overflow-clip rounded-md border border-rule-hair bg-surface-sunken shadow-panel">
          {children}
        </div>
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
      <div className="flex items-center justify-between gap-4 rounded-md border border-rule-hair bg-surface-ink px-4 py-2 text-ink-inverse">
        <div className="flex items-center gap-3">
          <TallyLogo />
          <span aria-hidden className="h-4 w-px bg-current opacity-30" />
          <span className="flex items-center gap-2">
            <TenantLogo name={tenant.name} />
            <span className="text-h3 tracking-tight">{tenant.name}</span>
          </span>
        </div>
        <div className="flex items-center gap-4 text-micro">
          <span className="opacity-70 hidden lg:inline">
            {cycle.label} · {cycle.periodLabel} · {date(cycle.periodStart)} → {date(cycle.periodEnd)}
          </span>
          <QuickFind />
          <UserMenu />
        </div>
      </div>
    )
  }
  return (
    <div className="rounded-md border border-exception-info-rail bg-exception-info-wash px-4 py-2">
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
      className="w-52 shrink-0 overflow-clip rounded-md border border-rule-hair bg-surface shadow-panel flex flex-col"
    >
      <div className="px-3 py-3 border-b border-rule-hair">
        <p className="field-label">As of</p>
        <p className="text-data text-ink-primary mt-0.5">{date(asOf.validAt)}</p>
        <p className="text-micro text-ink-tertiary mt-0.5">
          recorded {new Date(asOf.recordedAt).toLocaleTimeString('en-US', {
            hour: 'numeric',
            minute: '2-digit',
          })}
        </p>
      </div>

      <SidebarNav groups={navGroups()} current={current} />

      {/* The rail reads the query string to mark the active saved view, which
          would otherwise opt every prerendered page into client rendering.
          The boundary keeps the rest of the shell static. */}
      <Suspense fallback={<div className="border-t border-rule-hair px-3 py-2.5 h-24" />}>
        <Favorites />
      </Suspense>

      <div className="border-t border-rule-hair px-3 py-2.5 space-y-1.5">
        <p className="field-label">Display</p>
        <ThemeControl bare />
        <DensityControl bare />
      </div>
    </nav>
  )
}

/* The page header lives in its own module so client screens can render it too. */
export { PageHeader } from '@/components/shell/PageHeader'
