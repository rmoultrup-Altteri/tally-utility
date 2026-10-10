/**
 * Roles and capabilities, built to the D-1 ruling (2026-08-18).
 *
 * Two layers. The **system tier** is immutable and platform-defined — the
 * only role concept the database recognises, and the one RLS enforces. A
 * **tenant role** is the utility's own name for a job, composed from a
 * platform-seeded capability catalog and inheriting exactly one tier. The
 * composition is the tenant's; the vocabulary is the platform's.
 *
 * Three rules from the ruling shape the editor:
 * - a `viewer`-tier role can hold no write capability;
 * - assigning roles requires the `tenant_admin` tier, and nobody changes
 *   their own role — that is the self-escalation the ruling closes;
 * - a `tenant_admin`-tier role always keeps Change settings, so the tenant
 *   can never lock itself out of its own configuration.
 *
 * Only `settings.edit` is enforced by these concepts so far. The rest are
 * recorded and shown so the matrix reads as the real thing will.
 */

export type Tier = 'tenant_admin' | 'operator' | 'viewer'

export const TIER_LABEL: Record<Tier, string> = {
  tenant_admin: 'Administrator',
  operator: 'Operator',
  viewer: 'Read only',
}

export type Capability =
  | 'settings.edit'
  | 'billing_run.execute'
  | 'billing_run.dry_run'
  | 'invoice.void'
  | 'invoice.approve_correction'
  | 'rate.edit'
  | 'read.approve'
  | 'payment.post'
  | 'refund.issue'
  | 'adhoc.create'
  | 'adhoc.approve'
  | 'customer.edit'
  | 'import.commit'

/** The platform catalog, in the order the matrix shows it. Not tenant-editable. */
export const CAPABILITIES: { key: Capability; label: string; hint: string }[] = [
  { key: 'settings.edit', label: 'Change settings', hint: 'Open Settings and change tenant configuration, including dunning' },
  { key: 'billing_run.execute', label: 'Post billing runs', hint: 'Approve and post a run' },
  { key: 'billing_run.dry_run', label: 'Dry-run billing', hint: 'Start a run that posts nothing' },
  { key: 'invoice.void', label: 'Void bills', hint: 'Void an issued bill' },
  { key: 'invoice.approve_correction', label: 'Approve corrections', hint: 'Approve a void and rebill' },
  { key: 'rate.edit', label: 'Edit rates', hint: 'Record a rate change' },
  { key: 'read.approve', label: 'Approve reads', hint: 'Clear reads held for review' },
  { key: 'payment.post', label: 'Take payments', hint: 'Record a payment' },
  { key: 'refund.issue', label: 'Issue refunds', hint: 'Refund a credit balance' },
  { key: 'adhoc.create', label: 'Add one-off charges', hint: 'Add a fee or charge to an account' },
  { key: 'adhoc.approve', label: 'Approve one-off charges', hint: 'Approve a charge someone else added' },
  { key: 'customer.edit', label: 'Edit accounts', hint: 'Change account details and protections, and inactivate or reactivate accounts and meters' },
  { key: 'import.commit', label: 'Commit imports', hint: 'Apply a staged import' },
]

export const capabilityLabel = new Map(CAPABILITIES.map((c) => [c.key, c.label]))

export type TenantRole = {
  id: string
  name: string
  tier: Tier
  capabilities: Capability[]
}

export type Member = { userId: string; roleId: string }

export type User = { id: string; name: string; initials: string; email: string }

const ALL = CAPABILITIES.map((c) => c.key)

export const DEFAULT_ROLES: TenantRole[] = [
  { id: 'role-admin', name: 'Administrator', tier: 'tenant_admin', capabilities: ALL },
  {
    id: 'role-supervisor',
    name: 'Billing supervisor',
    tier: 'operator',
    capabilities: ALL.filter((c) => c !== 'import.commit'),
  },
  /* A small system: the analyst also maintains rates and the configuration. */
  {
    id: 'role-analyst',
    name: 'Billing analyst',
    tier: 'operator',
    capabilities: ['settings.edit', 'billing_run.dry_run', 'rate.edit', 'read.approve', 'payment.post', 'adhoc.create', 'customer.edit', 'import.commit'],
  },
  { id: 'role-csr', name: 'Customer service rep', tier: 'operator', capabilities: ['payment.post', 'adhoc.create', 'customer.edit'] },
  { id: 'role-auditor', name: 'Auditor', tier: 'viewer', capabilities: [] },
]

export const USERS: User[] = [
  { id: 'usr-gwhitfield', name: 'Gail Whitfield', initials: 'GW', email: 'gwhitfield@brazosvalleygas.example' },
  { id: 'usr-ralvarado', name: 'Renee Alvarado', initials: 'RA', email: 'ralvarado@brazosvalleygas.example' },
  { id: 'usr-dpearce', name: 'Dana Pearce', initials: 'DP', email: 'dpearce@brazosvalleygas.example' },
  { id: 'usr-thadley', name: 'Tom Hadley', initials: 'TH', email: 'thadley@brazosvalleygas.example' },
  { id: 'usr-plindqvist', name: 'Pat Lindqvist', initials: 'PL', email: 'plindqvist@brazosvalleygas.example' },
]

export const DEFAULT_MEMBERS: Member[] = [
  { userId: 'usr-gwhitfield', roleId: 'role-admin' },
  { userId: 'usr-ralvarado', roleId: 'role-supervisor' },
  { userId: 'usr-dpearce', roleId: 'role-analyst' },
  { userId: 'usr-thadley', roleId: 'role-csr' },
  { userId: 'usr-plindqvist', roleId: 'role-auditor' },
]

/** Capabilities a role actually holds once the tier rules are applied. */
export function effectiveCapabilities(role: TenantRole): Capability[] {
  if (role.tier === 'viewer') return []
  if (role.tier === 'tenant_admin' && !role.capabilities.includes('settings.edit')) return [...role.capabilities, 'settings.edit']
  return role.capabilities
}

/** Why a capability cannot be toggled on a role, if it cannot. */
export function lockedBecause(role: TenantRole, cap: Capability): string | null {
  if (role.tier === 'viewer') return 'A read-only role cannot hold a write capability.'
  if (role.tier === 'tenant_admin' && cap === 'settings.edit') return 'Administrator roles always keep Change settings, so the tenant can never lock itself out.'
  return null
}
