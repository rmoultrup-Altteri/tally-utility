'use client'

import { useEffect, useId, useRef, useState, type ReactNode } from 'react'
import Link from 'next/link'
import type { Route } from 'next'
import { USERS } from '@/fixtures/roles'
import { useAccess } from '@/lib/access'
import { isViewingAs, setActiveUser } from '@/lib/session'

/**
 * The operator's name, top right, opens a small menu: who is signed in and
 * in what role, Settings, and Log out.
 *
 * Settings appears only for a role holding Change settings. Everyone else
 * gets Preferences — their own appearance and notifications, which are not
 * tenant configuration and need no permission.
 *
 * It is a disclosure rather than an ARIA menu — a few links do not need
 * roving focus — so Tab moves through it and Escape or a click elsewhere
 * closes it, returning focus to the button.
 */
export function UserMenu() {
  const { user, role, members, roles, can } = useAccess()
  const [open, setOpen] = useState(false)
  const root = useRef<HTMLDivElement>(null)
  const button = useRef<HTMLButtonElement>(null)
  const id = useId()
  const viewingAs = isViewingAs(user.id)

  useEffect(() => {
    if (!open) return
    const onPointer = (e: PointerEvent) => {
      if (!root.current?.contains(e.target as Node)) setOpen(false)
    }
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') {
        setOpen(false)
        button.current?.focus()
      }
    }
    document.addEventListener('pointerdown', onPointer)
    document.addEventListener('keydown', onKey)
    return () => {
      document.removeEventListener('pointerdown', onPointer)
      document.removeEventListener('keydown', onKey)
    }
  }, [open])

  const roleName = (userId: string) => roles.find((r) => r.id === members.find((m) => m.userId === userId)?.roleId)?.name ?? 'No role'

  return (
    <div ref={root} className="relative">
      <button
        ref={button}
        type="button"
        aria-expanded={open}
        aria-controls={id}
        onClick={() => setOpen((o) => !o)}
        className="flex items-center gap-2 rounded-full py-0.5 pl-0.5 pr-2.5 text-micro text-ink-inverse transition-colors duration-fast hover:bg-white/10 aria-expanded:bg-white/10"
      >
        <span
          className={`flex h-6 w-6 items-center justify-center rounded-full text-ink-primary font-semibold ${
            viewingAs ? 'bg-state-dryrun-wash ring-2 ring-state-dryrun-rail' : 'bg-surface-raised'
          }`}
        >
          {user.initials}
        </span>
        <span className="hidden md:flex flex-col items-start whitespace-nowrap text-left">
          <span className="leading-tight">{user.name}</span>
          {/* The role decides what this person may do, so it sits with the name, not only inside the menu. */}
          <span className="text-[10px] leading-tight opacity-70">{role?.name ?? 'No role'}</span>
        </span>
        <svg width="10" height="10" viewBox="0 0 12 12" fill="none" aria-hidden className="opacity-70">
          <path d="M3 4.5l3 3 3-3" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" />
        </svg>
      </button>

      {open ? (
        <div
          id={id}
          className="absolute right-0 top-[calc(100%+6px)] z-50 w-72 overflow-clip rounded-md border border-rule-hair bg-surface-raised text-ink-primary shadow-modal"
        >
          <div className="border-b border-rule-hair px-3.5 py-3">
            <p className="text-data font-medium">{user.name}</p>
            <p className="text-micro text-ink-tertiary">{role?.name ?? 'No role assigned'}</p>
            <p className="mt-0.5 truncate text-micro text-ink-tertiary">{user.email}</p>
          </div>
          <ul className="py-1">
            <li>
              {can('settings.edit') ? (
                <Item href="/settings" onClick={() => setOpen(false)} icon={<GearIcon />}>
                  Settings
                </Item>
              ) : (
                <Item href="/settings/personal" onClick={() => setOpen(false)} icon={<GearIcon />}>
                  Preferences
                </Item>
              )}
            </li>
            <li>
              <Item
                href="/signed-out"
                onClick={() => {
                  setOpen(false)
                  /* The assistant conversation is this operator's; it should not greet the next one. */
                  try {
                    window.sessionStorage.removeItem('tu-assistant')
                  } catch {
                    /* Storage denied — nothing was kept to clear. */
                  }
                }}
                icon={
                  <svg width="14" height="14" viewBox="0 0 16 16" fill="none" aria-hidden className="text-ink-secondary">
                    <path d="M6 2.5H3.5v11H6M10 5l3 3-3 3M13 8H6.5" stroke="currentColor" strokeWidth="1.4" strokeLinecap="round" strokeLinejoin="round" />
                  </svg>
                }
              >
                Log out
              </Item>
            </li>
          </ul>

          {/* Concepts only: there is no sign-in, so this is how a role-gated screen is seen from both sides. */}
          <div className="border-t border-rule-hair bg-surface px-3.5 py-2.5">
            <p className="field-label mb-1">View as · concept only</p>
            <ul className="space-y-0.5">
              {USERS.map((u) => {
                const on = u.id === user.id
                return (
                  <li key={u.id}>
                    <button
                      type="button"
                      aria-pressed={on}
                      onClick={() => setActiveUser(u.id)}
                      className={`flex w-full items-baseline justify-between gap-2 rounded-sm px-2 py-1 text-left text-micro ${
                        on ? 'bg-state-dryrun-wash text-state-dryrun-text font-medium' : 'text-ink-secondary hover:bg-surface-sunken hover:text-ink-primary'
                      }`}
                    >
                      <span>{u.name}</span>
                      <span className="text-ink-tertiary">{roleName(u.id)}</span>
                    </button>
                  </li>
                )
              })}
            </ul>
          </div>
        </div>
      ) : null}
    </div>
  )
}

function Item({ href, onClick, icon, children }: { href: string; onClick: () => void; icon: ReactNode; children: ReactNode }) {
  return (
    <Link href={href as Route} onClick={onClick} className="flex items-center gap-2.5 px-3.5 py-2 text-data text-ink-primary hover:bg-surface-sunken">
      {icon}
      {children}
    </Link>
  )
}

function GearIcon() {
  return (
    <svg width="14" height="14" viewBox="0 0 16 16" fill="none" aria-hidden className="text-ink-secondary">
      <circle cx="8" cy="8" r="2.2" stroke="currentColor" strokeWidth="1.4" />
      <path
        d="M8 1.5v2M8 12.5v2M1.5 8h2M12.5 8h2M3.4 3.4l1.4 1.4M11.2 11.2l1.4 1.4M3.4 12.6l1.4-1.4M11.2 4.8l1.4-1.4"
        stroke="currentColor"
        strokeWidth="1.4"
        strokeLinecap="round"
      />
    </svg>
  )
}
