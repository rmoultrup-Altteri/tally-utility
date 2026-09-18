'use client'

import Link from 'next/link'
import type { Route } from 'next'
import { usePathname, useSearchParams } from 'next/navigation'
import { addFavorite, removeFavorite, useFavorites, viewId } from '@/lib/favorites-store'
import {
  describeFilters,
  favoriteHint,
  favoriteHref,
  favoriteLabel,
  listFavoriteId,
  parseFilters,
  serializeFilters,
  type ListKey,
  type QueueFilters,
} from '@/lib/views'

/**
 * The favorites rail in the sidebar.
 *
 * Deliberately short and unmanaged. There is no reorder, no folder, no edit
 * dialog — the ruling restricts favorites to destinations that stay useful for
 * years, which is what makes a maintenance UI unnecessary. If this list ever
 * needs grooming, the scope has drifted.
 */
export function Favorites() {
  const favorites = useFavorites()
  const pathname = usePathname()
  const params = useSearchParams()
  const here = `${pathname}${params.toString() ? `?${params.toString()}` : ''}`

  return (
    <div className="border-t border-rule-hair px-3 py-2.5">
      <p className="label-caps mb-1.5">Favorites</p>
      {favorites.length === 0 ? (
        <p className="text-micro text-ink-tertiary">
          Star a list or save a filtered view to pin it here.
        </p>
      ) : (
        <ul className="space-y-0.5">
          {favorites.map((f) => {
            const href = favoriteHref(f)
            const active = href === here
            return (
              <li key={f.id} className="group flex items-center gap-1">
                <Link
                  href={href as Route}
                  className={`min-w-0 flex-1 truncate py-0.5 text-micro transition-colors duration-fast ${
                    active ? 'text-ink-primary font-medium' : 'text-ink-secondary hover:text-ink-primary'
                  }`}
                  title={favoriteHint(f)}
                >
                  <span aria-hidden className="mr-1 text-ink-tertiary">
                    {f.kind === 'named_view' ? '◫' : '▤'}
                  </span>
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
            )
          })}
        </ul>
      )}
    </div>
  )
}

/**
 * The star on a record-list header. Toggles the plain list favorite — never a
 * record, because there is no variant that could hold one.
 */
export function ListStar({ list }: { list: ListKey }) {
  const favorites = useFavorites()
  const id = listFavoriteId(list)
  const on = favorites.some((f) => f.id === id)
  return (
    <button
      type="button"
      onClick={() => (on ? removeFavorite(id) : addFavorite({ id, kind: 'record_list', list }))}
      aria-pressed={on}
      title={on ? 'Remove this list from favorites' : 'Add this list to favorites'}
      className={`inline-flex h-7 items-center gap-1.5 rounded-xs border px-2 text-data transition-colors duration-fast ${
        on
          ? 'border-rule-solid bg-accent-wash text-ink-primary'
          : 'border-rule-solid bg-surface-raised text-ink-secondary hover:bg-surface-sunken hover:text-ink-primary'
      }`}
    >
      <span aria-hidden>{on ? '★' : '☆'}</span>
      {on ? 'Favorited' : 'Favorite'}
    </button>
  )
}

/**
 * Save the current filter state as a named view.
 *
 * A saved search and a saved filtered view are one object (T8-2), so this is
 * the only "save" in the product — there is no separate search to store.
 */
export function SaveView({ list, filters }: { list: ListKey; filters: QueueFilters }) {
  const favorites = useFavorites()
  const query = serializeFilters(filters)
  const id = viewId(list, query)
  const saved = favorites.some((f) => f.id === id)

  function save() {
    const suggested = describeFilters(filters)
    const name = window.prompt('Name this view', suggested.charAt(0).toUpperCase() + suggested.slice(1))
    if (!name?.trim()) return
    addFavorite({ id, kind: 'named_view', list, name: name.trim(), filters })
  }

  return (
    <button
      type="button"
      onClick={() => (saved ? removeFavorite(id) : save())}
      className="inline-flex h-6 items-center gap-1.5 rounded-xs border border-rule-solid bg-surface-raised px-2 text-micro text-ink-secondary transition-colors duration-fast hover:bg-surface-sunken hover:text-ink-primary"
    >
      <span aria-hidden>{saved ? '★' : '☆'}</span>
      {saved ? 'View saved' : 'Save this view'}
    </button>
  )
}

export { parseFilters }
