'use client'

import { customers, locations, meters, serviceLinks } from '@/fixtures/accounts'
import type { ImportedData, ImportedLink } from '@/lib/assistant/protocol'
import { useImported } from '@/lib/imports-store'
import type { Customer, Meter, ServiceLocation } from '@/schemas/models'

/**
 * Accounts, premises and meters as this browser knows them: the fixtures plus
 * whatever has been added by hand or through the assistant. Record pages and
 * panels look things up here, so a record added in this browser opens, edits
 * and links like one from the fixtures.
 */

export type Records = {
  customerById: Map<string, Customer>
  locationById: Map<string, ServiceLocation>
  meterById: Map<string, Meter>
  customerIdByNumber: Map<string, string>
  meterIdByNumber: Map<string, string>
  links: readonly ImportedLink[]
}

/* One set of lookups per state of the store, shared by every panel on the page. */
const cache = new WeakMap<ImportedData, Records>()

export function recordsFor(imported: ImportedData): Records {
  let r = cache.get(imported)
  if (!r) {
    const allCustomers = [...customers, ...imported.customers]
    const allMeters = [...meters, ...imported.meters]
    r = {
      customerById: new Map(allCustomers.map((c) => [c.id, c])),
      locationById: new Map([...locations, ...imported.locations].map((l) => [l.id, l])),
      meterById: new Map(allMeters.map((m) => [m.id, m])),
      customerIdByNumber: new Map(allCustomers.map((c) => [c.customer_number, c.id])),
      meterIdByNumber: new Map(allMeters.map((m) => [m.meter_number, m.id])),
      links: [...serviceLinks, ...imported.links],
    }
    cache.set(imported, r)
  }
  return r
}

export function useRecords(): Records {
  return recordsFor(useImported())
}
