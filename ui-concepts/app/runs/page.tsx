import { AppShell, PageHeader } from '@/components/shell/AppShell'
import { RunHistory, type RunRow } from '@/components/runs/RunHistory'
import { runs } from '@/fixtures/billing'
import { correctedRuns, correctionsOf, runEligibility } from '@/lib/run-corrections'

/**
 * Billing run history: every run this utility has made, newest first.
 *
 * It is the audit view of the cycle — each run with the coordinate it priced
 * at, who approved it and when it posted, and the corrections made against
 * it in both directions — and the quickest way to a run's Void and rebill.
 */

export default function RunHistoryPage() {
  const rows: RunRow[] = runs.map((r) => {
    const eligibility = runEligibility(r)
    return {
      id: r.id,
      number: r.run_number,
      period: r.billing_period,
      periodStart: r.period_start,
      periodEnd: r.period_end,
      type: r.is_dry_run ? 'dry_run' : r.run_type,
      isDryRun: r.is_dry_run,
      status: r.status,
      bills: r.total_invoices,
      amount: r.total_amount,
      exceptions: r.total_exceptions,
      estimated: r.total_estimated_reads,
      startedAt: r.started_at,
      approvedAt: r.approved_at,
      postedAt: r.posted_at,
      validAt: r.valid_at,
      recordedAt: r.recorded_at,
      corrects: correctedRuns(r.id).map((c) => ({ id: c.id, number: c.run_number })),
      correctedBy: correctionsOf(r.id).map((c) => ({ id: c.run.id, number: c.run.run_number, bills: c.bills.length })),
      eligible: eligibility.ok,
      eligibilityReason: eligibility.reason,
    }
  })

  return (
    <AppShell current="Run history">
      <PageHeader
        title="Run history"
        meta="Every billing run, with the coordinate it priced at and every correction made against it"
      />
      <RunHistory rows={rows} />
    </AppShell>
  )
}
