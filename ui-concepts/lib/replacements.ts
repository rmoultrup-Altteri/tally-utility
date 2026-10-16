'use client'

import { useEdits, type Replacement } from '@/lib/edits-store'
import { customerById, locationById, meterById, serviceLinks } from '@/fixtures/accounts'
import type { Customer, Meter, ServiceLocation } from '@/schemas/models'

/**
 * Where meters stand once exchanges made in this browser are laid over the
 * fixtures. The fixtures say which meter serves which premise; an exchange
 * moves the premise to the incoming meter and leaves the old one unset.
 */

const NONE: Replacement[] = []

export function useReplacements(): Replacement[] {
  return useEdits().replacements ?? NONE
}

/** The exchange that took this meter out, if any. */
export function replacedBy(meterId: string, reps: Replacement[]): Replacement | null {
  return reps.findLast((r) => r.oldMeterId === meterId) ?? null
}

/** The exchange that set this meter, if any. */
export function replacing(meterId: string, reps: Replacement[]): Replacement | null {
  return reps.findLast((r) => r.newMeterId === meterId) ?? null
}

/** The premise and account a meter serves now, or null when it is not set anywhere. */
export function servedLink(
  meterId: string,
  reps: Replacement[],
): { customerId: string | null; locationId: string } | null {
  if (replacedBy(meterId, reps)) return null
  const set = replacing(meterId, reps)
  if (set) return { customerId: set.customerId, locationId: set.locationId }
  const link = serviceLinks.find((l) => l.meterId === meterId)
  return link ? { customerId: link.customerId, locationId: link.locationId } : null
}

export function useServed(meterId: string): { customer: Customer; location: ServiceLocation } | null {
  const link = servedLink(meterId, useReplacements())
  const customer = link?.customerId ? customerById.get(link.customerId) : undefined
  const location = link ? locationById.get(link.locationId) : undefined
  return customer && location ? { customer, location } : null
}

/** The meter set at the premise now, following every exchange from the one the fixtures name. */
export function meterNowAfter(meterId: string, reps: Replacement[]): string {
  let id = meterId
  for (let r = replacedBy(id, reps); r; r = replacedBy(id, reps)) id = r.newMeterId
  return id
}

/** The fixture row of the meter set at the premise now. Pass it through `useMeter` for its edits. */
export function useMeterNow(base: Meter): Meter
export function useMeterNow(base: Meter | undefined): Meter | undefined
export function useMeterNow(base: Meter | undefined): Meter | undefined {
  const reps = useReplacements()
  if (!base) return undefined
  return meterById.get(meterNowAfter(base.id, reps)) ?? base
}

/**
 * The newest read on a meter: the fixture's, unless an exchange since then
 * took a removal read (old meter) or a set read (new meter).
 */
export function useLastRead(
  meterId: string,
  fixture: { value: string | null; date: string | null },
): { value: string | null; date: string | null } {
  const reps = useReplacements()
  const out = replacedBy(meterId, reps)
  const set = replacing(meterId, reps)
  const swap = out ? { value: out.removalRead, date: out.swapDate } : set ? { value: set.installRead, date: set.swapDate } : null
  if (swap && (!fixture.date || swap.date >= fixture.date)) return swap
  return fixture
}
