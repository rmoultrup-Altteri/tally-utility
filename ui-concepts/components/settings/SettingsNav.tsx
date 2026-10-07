'use client'

import Link from 'next/link'
import type { Route } from 'next'
import { AREAS, SECTIONS, type SectionKey } from '@/fixtures/settings'
import { useAccess } from '@/lib/access'

/**
 * The section list down the left of every settings page, grouped by area.
 * Without Change settings it lists only the operator's own preferences —
 * the rest would only lead to a locked door.
 */
export function SettingsNav({ current }: { current?: SectionKey }) {
  const allowed = useAccess().can('settings.edit')
  const sections = SECTIONS.filter((s) => allowed || s.personal)
  return (
    <nav aria-label="Settings sections" className="space-y-4">
      {allowed ? (
        <Link
          href={'/settings' as Route}
          aria-current={current ? undefined : 'page'}
          className={`block rounded-sm px-2.5 py-1.5 text-data ${
            current ? 'text-ink-secondary hover:bg-surface hover:text-ink-primary' : 'bg-accent-wash font-medium text-accent-text'
          }`}
        >
          Overview
        </Link>
      ) : null}
      {AREAS.map((area) => {
        const inArea = sections.filter((s) => s.area === area)
        if (!inArea.length) return null
        return (
          <div key={area}>
            <p className="field-label px-2.5 pb-1">{area}</p>
            <ul className="space-y-0.5">
              {inArea.map((s) => {
                const on = s.key === current
                return (
                  <li key={s.key}>
                    <Link
                      href={`/settings/${s.key}` as Route}
                      aria-current={on ? 'page' : undefined}
                      className={`block rounded-sm px-2.5 py-1.5 text-data transition-colors duration-fast ${
                        on ? 'bg-accent-wash font-medium text-accent-text' : 'text-ink-secondary hover:bg-surface hover:text-ink-primary'
                      }`}
                    >
                      {s.title}
                    </Link>
                  </li>
                )
              })}
            </ul>
          </div>
        )
      })}
    </nav>
  )
}
