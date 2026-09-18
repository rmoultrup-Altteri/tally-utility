import Link from 'next/link'
import type { Route } from 'next'
import { AppShell, PageHeader } from '@/components/shell/AppShell'
import { Button } from '@/components/ui/Panel'
import { StateBlock } from '@/components/ui/State'
import { TariffSandbox } from '@/components/rates/TariffSandbox'
import { baseline } from '@/fixtures/tariff'
import { count } from '@/lib/format'

/**
 * Tariff sandbox.
 *
 * The product's stated differentiator is that a rate change is an afternoon
 * rather than a three-week vendor engagement. Nothing else on the site makes
 * that claim testable: every other screen shows rates that have already been
 * applied. This one lets an analyst move a rate and see, before committing
 * anything, which customers it moves and by how much.
 *
 * It rehearses against a closed cycle's actual metered volumes rather than a
 * forecast, because the objection a rate change has to survive is not "what
 * does this do on average" — it is "what does this do to the widow on Cavitt
 * Avenue who burns forty therms a month".
 */

export default function TariffSandboxPage() {
  return (
    <AppShell current="Tariff sandbox">
      <PageHeader
        title="Tariff sandbox"
        meta={
          <>
            R-1 · Residential Firm Gas Service ·{' '}
            <Link href={'/rates' as Route} className="underline hover:text-ink-secondary">
              Rate versions
            </Link>{' '}
            ·{' '}
            <Link href={'/rates/pga' as Route} className="underline hover:text-ink-secondary">
              PGA console
            </Link>
          </>
        }
        actions={<Button>Export impact analysis</Button>}
      />

      <div className="flex-1 overflow-auto">
        <div className="px-5 py-5 space-y-5">
          <StateBlock tone="info">
            <p className="text-data text-ink-primary">
              <strong className="font-semibold">Nothing here is committed.</strong> Every figure below
              is a rehearsal against {count(baseline.accountsOnSchedule)} accounts of closed, locked
              consumption from {baseline.cycleLabel} — the same volumes the cycle actually billed, run
              through a card that does not exist yet. No invoice, ledger entry or rate version is
              written until the gate at the bottom is passed.
            </p>
          </StateBlock>

          <TariffSandbox />
        </div>
      </div>
    </AppShell>
  )
}
