'use client'

import { useState, type ReactNode } from 'react'
import Link from 'next/link'
import type { Route } from 'next'
import { Button, Panel, PanelHeader } from '@/components/ui/Panel'
import { StateFlag, humanize, severityTone } from '@/components/ui/State'
import { moveTo, setConfiguring, setPortletOrder, setTaskOrder, useConfiguring, usePortletOrder, useTaskOrder } from '@/lib/dashboard-store'
import { removeFavorite, useFavorites } from '@/lib/favorites-store'
import { favoriteHint, favoriteHref, favoriteLabel } from '@/lib/views'
import { useActiveUserId, userById } from '@/lib/session'
import { byConsequence, openExceptions } from '@/fixtures/exceptions'
import { customerById } from '@/fixtures/accounts'
import { customerName } from '@/schemas/models'
import { dateShort } from '@/lib/format'

/**
 * The dashboard's portlets, arranged by the operator.
 *
 * The shipped layout is the locked composition (T8-4 … T8-8) in its order,
 * followed by the operator's own two: tasks assigned to them and their
 * favorites. Configure portlets lets each operator remove, move and add
 * portlets back. What a portlet counts never changes — the severity portlets
 * still place by item type — only where it sits and whether it shows.
 */

type Span = 2 | 3 | 4 | 6

export type PortletDef = { id: string; title: string; description: string; span: Span }

export const PORTLETS: PortletDef[] = [
  { id: 'tier-Critical', title: 'Critical', description: 'Critical item types, six rows and a “+N more”', span: 2 },
  { id: 'tier-Medium', title: 'Medium', description: 'Medium item types, six rows and a “+N more”', span: 2 },
  { id: 'tier-Low', title: 'Low', description: 'Low item types, six rows and a “+N more”', span: 2 },
  { id: 'revenue', title: 'Revenue', description: 'Billed net of voids and collected, with no ratio between them', span: 3 },
  { id: 'ar', title: 'Accounts receivable', description: 'Aged by invoice, each bucket opening the AR aging report', span: 3 },
  { id: 'rate-card', title: 'Tariff rate card', description: 'What the last posted run billed at, with drift', span: 6 },
  { id: 'my-tasks', title: 'My open tasks', description: 'Open exceptions assigned to you, in the order you arrange them', span: 4 },
  { id: 'favorites', title: 'Favorites', description: 'Your starred lists and saved views', span: 2 },
]

const DEFAULT_ORDER = PORTLETS.map((p) => p.id)
const byId = new Map(PORTLETS.map((p) => [p.id, p]))

/* Literal classes, so Tailwind sees each one. */
const SPAN: Record<Span, string> = {
  2: 'lg:col-span-2',
  3: 'lg:col-span-3',
  4: 'lg:col-span-4',
  6: 'lg:col-span-6',
}

/** The header button. "Done" while configuring. */
export function ConfigurePortletsButton() {
  const on = useConfiguring()
  return (
    <Button variant={on ? 'primary' : 'default'} onClick={() => setConfiguring(!on)}>
      {on ? 'Done' : 'Configure portlets'}
    </Button>
  )
}

/**
 * The board. `rendered` holds the portlets drawn on the server, keyed by id;
 * the operator's own portlets are drawn here, since they read this browser.
 */
export function PortletBoard({ rendered }: { rendered: Record<string, ReactNode> }) {
  const stored = usePortletOrder()
  const configuring = useConfiguring()
  const [dragging, setDragging] = useState<string | null>(null)
  const [over, setOver] = useState<string | null>(null)

  const order = (stored ?? DEFAULT_ORDER).filter((id) => byId.has(id))
  const available = PORTLETS.filter((p) => !order.includes(p.id))
  const customized = stored !== null

  const content = (id: string): ReactNode =>
    id === 'my-tasks' ? <MyTasksPortlet /> : id === 'favorites' ? <FavoritesPortlet /> : rendered[id]

  const move = (id: string, to: number) => setPortletOrder(moveTo(order, id, to))
  const remove = (id: string) => setPortletOrder(order.filter((x) => x !== id))
  const add = (id: string) => setPortletOrder([...order, id])
  const end = () => {
    setDragging(null)
    setOver(null)
  }

  return (
    <div className="space-y-4">
      {configuring ? (
        <Panel>
          <PanelHeader
            title="Configure portlets"
            meta={`${order.length} showing · drag a portlet, or use its arrows, to move it`}
            actions={
              <Button variant="quiet" onClick={() => setPortletOrder(null)} disabled={!customized}>
                Reset to default
              </Button>
            }
          />
          <div className="px-4 py-3">
            <p className="field-label mb-2">Add a portlet</p>
            {available.length === 0 ? (
              <p className="text-micro text-ink-tertiary">Every portlet is on the dashboard. Remove one to add it back here.</p>
            ) : (
              <ul className="grid grid-cols-1 sm:grid-cols-2 xl:grid-cols-3 gap-2">
                {available.map((p) => (
                  <li key={p.id} className="flex items-start justify-between gap-3 rounded-sm border border-dashed border-rule-solid px-3 py-2">
                    <div className="min-w-0">
                      <p className="text-data text-ink-primary">{p.title}</p>
                      <p className="text-micro text-ink-tertiary">{p.description}</p>
                    </div>
                    <Button onClick={() => add(p.id)}>Add</Button>
                  </li>
                ))}
              </ul>
            )}
          </div>
        </Panel>
      ) : null}

      {order.length === 0 ? (
        <div className="rounded-md border border-dashed border-rule-solid px-4 py-8 text-center">
          <p className="text-data text-ink-secondary">No portlets on the dashboard.</p>
          {!configuring ? (
            <button type="button" onClick={() => setConfiguring(true)} className="mt-1 text-micro text-accent-text underline">
              Configure portlets to add some
            </button>
          ) : null}
        </div>
      ) : null}

      <div className="grid grid-cols-1 lg:grid-cols-6 gap-5">
        {order.map((id, i) => {
          const def = byId.get(id)!
          const target = configuring && dragging && over === id && dragging !== id
          return (
            <div
              key={id}
              className={`flex min-w-0 flex-col ${SPAN[def.span]} ${dragging === id ? 'opacity-50' : ''} ${
                target ? 'rounded-md outline-2 outline-offset-2 outline-accent' : ''
              }`}
              draggable={configuring}
              onDragStart={
                configuring
                  ? (e) => {
                      e.dataTransfer.effectAllowed = 'move'
                      e.dataTransfer.setData('text/plain', id)
                      setDragging(id)
                    }
                  : undefined
              }
              onDragOver={
                configuring && dragging
                  ? (e) => {
                      e.preventDefault()
                      e.dataTransfer.dropEffect = 'move'
                      if (over !== id) setOver(id)
                    }
                  : undefined
              }
              onDrop={
                configuring && dragging
                  ? (e) => {
                      e.preventDefault()
                      if (dragging !== id) move(dragging, i)
                      end()
                    }
                  : undefined
              }
              onDragEnd={end}
            >
              {configuring ? (
                <div className="mb-1.5 flex items-center gap-1 rounded-sm border border-dashed border-rule-solid bg-surface-sunken px-2 py-1">
                  <span aria-hidden className="cursor-grab select-none text-ink-muted" title="Drag to move this portlet">
                    ⋮⋮
                  </span>
                  <span className="min-w-0 flex-1 truncate text-micro font-medium text-ink-primary">{def.title}</span>
                  <MiniButton label={`Move ${def.title} earlier`} onClick={() => move(id, i - 1)} disabled={i === 0}>
                    ←
                  </MiniButton>
                  <MiniButton label={`Move ${def.title} later`} onClick={() => move(id, i + 1)} disabled={i === order.length - 1}>
                    →
                  </MiniButton>
                  <MiniButton label={`Remove ${def.title}`} onClick={() => remove(id)} danger>
                    Remove
                  </MiniButton>
                </div>
              ) : null}
              {/* Inert while configuring, so a drag never follows a link inside. */}
              <div className={`flex-1 *:h-full ${configuring ? 'pointer-events-none select-none' : ''}`}>{content(id)}</div>
            </div>
          )
        })}
      </div>
    </div>
  )
}

function MiniButton({
  children,
  label,
  onClick,
  disabled = false,
  danger = false,
}: {
  children: ReactNode
  label: string
  onClick: () => void
  disabled?: boolean
  danger?: boolean
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      disabled={disabled}
      aria-label={label}
      title={label}
      className={`h-6 min-w-6 rounded-xs px-1.5 text-micro transition-colors duration-fast disabled:opacity-30 ${
        danger
          ? 'text-exception-critical-text hover:bg-exception-critical-wash'
          : 'text-ink-secondary hover:bg-surface-inset hover:text-ink-primary'
      }`}
    >
      {children}
    </button>
  )
}

/* ---- My open tasks ----------------------------------------------------- */

/**
 * Open exceptions assigned to the active user, in the order they arrange.
 * New assignments join at the bottom in consequence order; a task that is
 * resolved or reassigned simply drops out of the stored order.
 */
function MyTasksPortlet() {
  const userId = useActiveUserId()
  const me = userById(userId).name
  const stored = useTaskOrder(userId)
  const [dragging, setDragging] = useState<string | null>(null)
  const [over, setOver] = useState<string | null>(null)

  const mine = byConsequence(openExceptions.filter((e) => e.assigned_to === me))
  const ids = mine.map((e) => e.id)
  const order = [...(stored ?? []).filter((id) => ids.includes(id)), ...ids.filter((id) => !(stored ?? []).includes(id))]
  const tasks = order.map((id) => mine.find((e) => e.id === id)!)
  const move = (id: string, to: number) => setTaskOrder(userId, moveTo(order, id, to))
  const end = () => {
    setDragging(null)
    setOver(null)
  }

  return (
    <Panel>
      <PanelHeader
        title="My open tasks"
        meta={`${tasks.length} assigned to ${me}`}
        actions={
          <>
            {stored ? (
              <button type="button" onClick={() => setTaskOrder(userId, null)} className="text-micro text-accent-text underline hover:text-accent-text-hover">
                Reset order
              </button>
            ) : null}
            <Link href={'/?assignee=me' as Route} className="text-micro text-accent-text underline hover:text-accent-text-hover">
              Open in queue
            </Link>
          </>
        }
      />
      {tasks.length === 0 ? (
        <p className="px-4 py-4 text-data text-ink-secondary">Nothing is assigned to you.</p>
      ) : (
        <ol className="divide-y divide-rule-hair" aria-label="Your open tasks, in your order">
          {tasks.map((e, i) => {
            const customer = e.customer_id ? customerById.get(e.customer_id) : undefined
            const target = dragging && over === e.id && dragging !== e.id
            return (
              <li
                key={e.id}
                draggable
                onDragStart={(ev) => {
                  ev.dataTransfer.effectAllowed = 'move'
                  ev.dataTransfer.setData('text/plain', e.id)
                  setDragging(e.id)
                }}
                onDragOver={(ev) => {
                  if (!dragging) return
                  ev.preventDefault()
                  ev.dataTransfer.dropEffect = 'move'
                  if (over !== e.id) setOver(e.id)
                }}
                onDrop={(ev) => {
                  ev.preventDefault()
                  if (dragging && dragging !== e.id) move(dragging, i)
                  end()
                }}
                onDragEnd={end}
                className={`flex items-center gap-2.5 px-3 py-2 bg-surface-raised hover:bg-surface-sunken ${
                  dragging === e.id ? 'opacity-50' : ''
                } ${target ? 'bg-accent-wash' : ''}`}
              >
                <span aria-hidden className="cursor-grab select-none text-ink-muted" title="Drag to reorder">
                  ⋮⋮
                </span>
                <span className="figures w-4 shrink-0 text-right text-micro text-ink-tertiary">{i + 1}</span>
                <div className="min-w-0 flex-1">
                  <p className="flex items-baseline gap-2">
                    <StateFlag tone={severityTone(e.severity, e.status)}>{e.severity}</StateFlag>
                    <span className="truncate text-data text-ink-primary">{e.description}</span>
                  </p>
                  <p className="truncate text-micro text-ink-tertiary">
                    {customer ? (
                      <Link href={`/customers/${customer.id}` as Route} className="hover:text-accent-text hover:underline">
                        {customerName(customer)}
                      </Link>
                    ) : (
                      humanize(e.entity_type)
                    )}{' '}
                    · {humanize(e.status)} · detected {dateShort(e.detected_at)}
                    {e.blocks_delivery ? <span className="text-exception-critical-text"> · blocks delivery</span> : null}
                  </p>
                </div>
                <MiniButton label={`Move ${e.description} up`} onClick={() => move(e.id, i - 1)} disabled={i === 0}>
                  ↑
                </MiniButton>
                <MiniButton label={`Move ${e.description} down`} onClick={() => move(e.id, i + 1)} disabled={i === tasks.length - 1}>
                  ↓
                </MiniButton>
              </li>
            )
          })}
        </ol>
      )}
      <div className="border-t border-rule-hair px-4 py-2">
        <p className="text-micro text-ink-tertiary">
          Your order is yours alone. The exception queue still ranks by consequence for everyone.
        </p>
      </div>
    </Panel>
  )
}

/* ---- Favorites ----------------------------------------------------------- */

/** The same list as the sidebar's favorites rail, at dashboard size. */
function FavoritesPortlet() {
  const favorites = useFavorites()
  return (
    <Panel>
      <PanelHeader title="Favorites" meta={`${favorites.length} pinned`} />
      {favorites.length === 0 ? (
        <p className="px-4 py-4 text-micro text-ink-tertiary">Star a list or save a filtered view to pin it here.</p>
      ) : (
        <ul className="divide-y divide-rule-hair">
          {favorites.map((f) => (
            <li key={f.id} className="group flex items-center gap-2 px-4 py-1.5 hover:bg-surface-sunken">
              <span aria-hidden className="text-micro text-ink-tertiary">
                {f.kind === 'named_view' ? '◫' : f.kind === 'report' ? '▦' : '▤'}
              </span>
              <Link href={favoriteHref(f) as Route} title={favoriteHint(f)} className="min-w-0 flex-1 truncate text-data text-ink-primary hover:text-accent-text">
                {favoriteLabel(f)}
              </Link>
              <button
                type="button"
                onClick={() => removeFavorite(f.id)}
                aria-label={`Remove ${favoriteLabel(f)} from favorites`}
                className="shrink-0 px-1 text-micro text-ink-muted opacity-0 transition-opacity duration-fast group-hover:opacity-100 focus-visible:opacity-100 hover:text-exception-critical-text"
              >
                ×
              </button>
            </li>
          ))}
        </ul>
      )}
    </Panel>
  )
}
