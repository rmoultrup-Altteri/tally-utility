'use client'

import { customers, locations, meters, serviceLinks } from '@/fixtures/accounts'
import { stage } from '@/lib/assistant/imports'
import type { ImportIssue, ImportedData } from '@/lib/assistant/protocol'
import type { TenantView } from '@/lib/assistant/tenant-data'
import { applyProposal, getImported } from '@/lib/imports-store'

/**
 * One account, meter or premise, entered by hand.
 *
 * A one-off record is an import of one row: it goes through the same
 * validator the assistant's imports do — the schema's types and enums, unique
 * account, premise and meter numbers, a person or company name — and lands in
 * the same browser store, so every list that shows imported records shows
 * these too. Numbers left blank are assigned, as an import would.
 */

export type Created = { ok: true; records: ImportedData; warnings: ImportIssue[] } | { ok: false; errors: ImportIssue[] }

/** Fixtures plus whatever this browser has added — the records a new number must not collide with. */
function currentView(): TenantView {
  const imported = getImported()
  return {
    customers: [...customers, ...imported.customers],
    locations: [...locations, ...imported.locations],
    meters: [...meters, ...imported.meters],
    links: [...serviceLinks, ...imported.links],
    invoices: [],
    rateVersions: [],
    imported,
  }
}

export function createRecord(entity: 'accounts' | 'meters' | 'locations', fields: Record<string, string>): Created {
  const row = Object.fromEntries(Object.entries(fields).filter(([, v]) => v.trim() !== ''))
  let proposal
  try {
    proposal = stage({ entity, rows: [row], assign_numbers: true }, new Map(), currentView())
  } catch (e) {
    return { ok: false, errors: [{ row: 1, field: null, message: e instanceof Error ? e.message : String(e) }] }
  }
  if (proposal.errors.length) return { ok: false, errors: proposal.errors }
  applyProposal(proposal)
  return { ok: true, records: proposal.records, warnings: proposal.warnings }
}

/** Premises with no meter set — where a new meter can go. */
export function premisesAwaitingMeter(imported: ImportedData) {
  const links = [...serviceLinks, ...imported.links]
  return [...locations, ...imported.locations].filter((l) => !links.some((k) => k.locationId === l.id && k.meterId))
}

/** A premise already on file, by number, with who takes service there and the meter set at it, if any. */
export function premiseOnFile(imported: ImportedData, number: string) {
  const location = [...locations, ...imported.locations].find((l) => l.location_number === number.trim())
  if (!location) return null
  const links = [...serviceLinks, ...imported.links].filter((k) => k.locationId === location.id)
  const customerId = links.find((k) => k.customerId)?.customerId
  const meterId = links.find((k) => k.meterId)?.meterId
  return {
    location,
    customer: customerId ? ([...customers, ...imported.customers].find((c) => c.id === customerId) ?? null) : null,
    meter: meterId ? ([...meters, ...imported.meters].find((m) => m.id === meterId) ?? null) : null,
  }
}
