import type { Tone } from '@/components/ui/State'

/**
 * Meter and account lifecycle words, with the tone each one wears.
 *
 * An inactive meter is still set at its premise — shut off, not pulled. A
 * removed meter has left the premise; one in stock has never been set, or has
 * been tested and racked again. Only an active meter can be inactivated, and
 * only an inactive one reactivated: setting or pulling a meter is a field
 * service order, not a status toggle.
 */

export type MeterStatus = 'active' | 'inactive' | 'in_stock' | 'removed'

export const METER_STATUS: Record<MeterStatus, { label: string; tone: Tone; rank: number }> = {
  active: { label: 'Active', tone: 'approved', rank: 1 },
  inactive: { label: 'Inactive', tone: 'void', rank: 2 },
  in_stock: { label: 'In stock', tone: 'draft', rank: 3 },
  removed: { label: 'Removed', tone: 'superseded', rank: 4 },
}

export const meterStatus = (s: string) => METER_STATUS[s as MeterStatus] ?? { label: s, tone: 'draft' as Tone, rank: 9 }

export function accountTone(status: string): Tone {
  switch (status) {
    case 'active':
      return 'approved'
    case 'inactive':
      return 'void'
    case 'final_billed':
      return 'superseded'
    default:
      return 'failed'
  }
}

/** `3/4_inch` as a meter shop writes it: ¾″. */
export function sizeLabel(size: string | null | undefined): string {
  if (!size) return '—'
  return size
    .replace(/_inch$/, '″')
    .replace(/^3\/4/, '¾')
    .replace(/^1\.5/, '1½')
}

export const METER_INACTIVATE_REASONS = [
  'Premise vacant — service off',
  'Customer request — seasonal shut-off',
  'Safety shut-off — leak or red tag',
  'Disconnected for non-payment',
  'Awaiting meter exchange',
]

export const METER_REACTIVATE_REASONS = [
  'New occupant — service on',
  'Customer request — service restored',
  'Safety repair cleared — relit',
  'Reconnected after payment',
]

export const ACCOUNT_INACTIVATE_REASONS = [
  'Customer moved out',
  'Service transferred to a new account',
  'Duplicate account',
  'Premise demolished',
]

export const ACCOUNT_REACTIVATE_REASONS = [
  'Customer returned to the premise',
  'Inactivated in error',
  'Transfer reversed',
]
