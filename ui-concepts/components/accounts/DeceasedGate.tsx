'use client'

import type { ReactNode } from 'react'
import { StateFlag } from '@/components/ui/State'
import { useDeceased } from '@/lib/deceased-store'
import { BYPASSES } from '@/fixtures/collections'

/**
 * Overrides a collections verdict when a death has been recorded on the
 * account in this browser. The worklist is evaluated on the server from the
 * fixtures, so without this a death recorded here would not stop anything
 * there until the API exists.
 */
export function DeceasedGate({ customerId, children }: { customerId?: string; children: ReactNode }) {
  const state = useDeceased(customerId ?? '')
  if (!customerId || !state?.holdActive) return <>{children}</>
  return (
    <>
      <StateFlag tone="critical">No</StateFlag>
      <p className="text-micro text-ink-secondary mt-0.5">{BYPASSES.deceased_hold.label}</p>
    </>
  )
}
