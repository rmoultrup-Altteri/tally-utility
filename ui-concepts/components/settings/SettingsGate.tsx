'use client'

import { useSyncExternalStore, type ReactNode } from 'react'
import Link from 'next/link'
import type { Route } from 'next'
import { Panel } from '@/components/ui/Panel'
import { useAccess } from '@/lib/access'
import { userById } from '@/lib/session'

/**
 * Tenant settings are for roles holding Change settings (`settings.edit`).
 * Anyone else reaching a settings URL — a pasted link, an old bookmark — gets
 * a plain explanation and the way to get access, never a half-rendered form.
 * Their own preferences stay open to them.
 */
export function SettingsGate({ children }: { children: ReactNode }) {
  const { can } = useAccess()
  /* The static page is rendered for the default user. Until this browser's
     session is known, show nothing rather than flash a form at someone who
     may not be allowed it. */
  const known = useSyncExternalStore(
    noop,
    () => true,
    () => false,
  )
  if (!known) return null
  return can('settings.edit') ? <>{children}</> : <NoAccess />
}

const noop = () => () => {}

function NoAccess() {
  const { user, role, roles, members, holders } = useAccess()
  const admins = members
    .filter((m) => roles.find((r) => r.id === m.roleId)?.tier === 'tenant_admin')
    .map((m) => userById(m.userId).name)
  const withAccess = holders('settings.edit').map((r) => r.name)

  return (
    <Panel className="max-w-xl">
      <div className="px-5 py-5">
        <div className="flex items-center gap-2">
          <svg width="16" height="16" viewBox="0 0 12 12" fill="none" aria-hidden className="text-ink-tertiary">
            <rect x="2" y="5.5" width="8" height="5.5" rx="1" stroke="currentColor" strokeWidth="1.1" />
            <path d="M4 5.5V4a2 2 0 014 0v1.5" stroke="currentColor" strokeWidth="1.1" />
          </svg>
          <h2 className="text-h2 text-ink-primary">You don’t have settings access</h2>
        </div>
        <p className="mt-2 text-data text-ink-secondary">
          Tenant settings are limited to roles that include <span className="font-medium text-ink-primary">Change settings</span>.{' '}
          {role ? (
            <>
              You are signed in as {user.name}, <span className="font-medium text-ink-primary">{role.name}</span>, which doesn’t include it.
            </>
          ) : (
            <>You are signed in as {user.name}, with no role assigned.</>
          )}
        </p>
        {withAccess.length ? <p className="mt-2 text-data text-ink-secondary">Roles that do: {withAccess.join(', ')}.</p> : null}
        {admins.length ? (
          <p className="mt-2 text-data text-ink-secondary">
            To change your role, ask an administrator — {admins.join(', ')}.
          </p>
        ) : null}
        <Link
          href={'/settings/personal' as Route}
          className="mt-4 inline-flex h-8 items-center justify-center rounded-sm border border-rule-solid bg-surface-raised px-3.5 text-data font-medium text-ink-primary hover:border-rule-heavy hover:bg-surface-sunken"
        >
          Your preferences
        </Link>
      </div>
    </Panel>
  )
}
