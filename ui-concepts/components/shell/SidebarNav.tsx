'use client'

import { useState } from 'react'
import Link from 'next/link'
import type { Route } from 'next'

/**
 * The main navigation: Today always open, the rest as an accordion.
 *
 * Fifteen flat links is how CC&B got its reputation. Grouped by the job, the
 * list reads in five words instead of fifteen. Today — the queue and what
 * needs doing before the run posts — is always showing. Of the other groups
 * only one is open at a time: opening Rates folds Billing, so the sidebar
 * never grows past one group's worth of links.
 *
 * Each page opens on the group that holds it, so arriving on Accounts shows
 * Customers. A folded group still shows its badges, so folding never hides
 * that something needs attention.
 */

export type NavBadge = { count: number; tone: 'critical' | 'warning'; title: string }
export type NavLink = { href: string; label: string; badge?: NavBadge }
/** `pinned` groups are always open and sit outside the accordion. */
export type NavGroup = { key: string; label: string; items: NavLink[]; pinned?: boolean }

const BADGE: Record<NavBadge['tone'], string> = {
  critical: 'bg-exception-critical-wash text-exception-critical-text',
  warning: 'bg-exception-warning-wash text-exception-warning-text',
}

function Badge({ b }: { b: NavBadge }) {
  return (
    <span className={`ident rounded-full px-1.5 ${BADGE[b.tone]}`} title={b.title}>
      {b.count}
    </span>
  )
}

export function SidebarNav({ groups, current }: { groups: NavGroup[]; current: string }) {
  const home = groups.find((g) => !g.pinned && g.items.some((i) => i.label === current))
  const [openKey, setOpenKey] = useState<string | null>(home?.key ?? null)

  return (
    <div className="flex-1 min-h-0 overflow-y-auto px-2 py-1.5">
      {groups.map((g) => {
        const open = g.pinned || openKey === g.key
        const badges = g.items.filter((i) => i.badge && i.badge.count > 0).map((i) => i.badge!)
        const panelId = `nav-${g.key}`
        return (
          <section key={g.key} className="mb-1">
            {g.pinned ? (
              <p className="field-label px-2 pt-2 pb-1 pl-6">{g.label}</p>
            ) : (
              <button
                type="button"
                onClick={() => setOpenKey(open ? null : g.key)}
                aria-expanded={open}
                aria-controls={panelId}
                className="group flex w-full items-center gap-1.5 rounded-sm px-2 pt-2 pb-1 text-left"
              >
                <span
                  aria-hidden
                  className={`inline-block w-2.5 text-[9px] text-ink-tertiary transition-transform duration-fast group-hover:text-ink-primary ${open ? 'rotate-90' : ''}`}
                >
                  ▸
                </span>
                <span className={`field-label flex-1 group-hover:text-ink-secondary ${open ? 'text-ink-secondary' : ''}`}>{g.label}</span>
                {!open ? badges.map((b, i) => <Badge key={i} b={b} />) : null}
              </button>
            )}
            {open ? (
              <ul id={panelId} className="space-y-0.5">
                {g.items.map((item) => {
                  const active = item.label === current
                  return (
                    <li key={item.href}>
                      <Link
                        href={item.href as Route}
                        aria-current={active ? 'page' : undefined}
                        className={`flex items-center justify-between gap-2 rounded-sm px-2.5 py-1.5 text-data transition-colors duration-fast ${
                          active ? 'bg-accent-wash text-accent-text font-medium' : 'text-ink-secondary hover:bg-surface-sunken hover:text-ink-primary'
                        }`}
                      >
                        <span>{item.label}</span>
                        {item.badge && item.badge.count > 0 ? <Badge b={item.badge} /> : null}
                      </Link>
                    </li>
                  )
                })}
              </ul>
            ) : null}
          </section>
        )
      })}
    </div>
  )
}
