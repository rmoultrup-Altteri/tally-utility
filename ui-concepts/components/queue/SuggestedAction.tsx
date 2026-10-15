import Link from 'next/link'
import type { Route } from 'next'
import { Button } from '@/components/ui/Panel'
import { ProposeReclassification } from '@/components/accounts/RateSchedule'
import type { Exception } from '@/schemas/models'

/**
 * The suggested action's button on the exception detail. Two are wired: the
 * rate-schedule reclassification adds a pending history row, and the
 * deceased-account review opens the account. The rest are still presented
 * and not applied.
 */
export function SuggestedAction({ exception: e }: { exception: Exception }) {
  if (!e.suggested_action) return null
  if (e.anomaly_type === 'rate_schedule_mismatch') return <ProposeReclassification exception={e} />
  if (e.anomaly_type === 'deceased_account_review' && e.customer_id)
    return (
      <Link href={`/customers/${e.customer_id}` as Route}>
        <Button variant="primary">{e.suggested_action.label}</Button>
      </Link>
    )
  return <Button variant="primary">{e.suggested_action.label}</Button>
}
