import type { Favorite } from '@/lib/views'

/**
 * Dana Pearce's pinned destinations.
 *
 * Per-user and tenant-scoped. Small by construction — the ruling's whole point
 * is that a list restricted to durable destinations never needs a maintenance
 * screen, because nothing in it goes stale. Three saved views and two record
 * lists is what a real analyst's list looks like after a year.
 */
export const seedFavorites: Favorite[] = [
  {
    id: 'fav-blocking',
    kind: 'named_view',
    list: 'exceptions',
    name: 'Blocking, unassigned',
    filters: { severity: [], status: [], blocking: true, assignee: 'unassigned' },
  },
  {
    id: 'fav-mine',
    kind: 'named_view',
    list: 'exceptions',
    name: 'Mine, in progress',
    filters: { severity: [], status: ['acknowledged', 'investigating'], assignee: 'me' },
  },
  {
    id: 'fav-critical',
    kind: 'named_view',
    list: 'exceptions',
    name: 'Critical, any owner',
    filters: { severity: ['critical'], status: [], assignee: 'anyone' },
  },
  { id: 'list:reads', kind: 'record_list', list: 'reads' },
  { id: 'list:collections', kind: 'record_list', list: 'collections' },
]
