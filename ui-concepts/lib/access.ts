'use client'

import { useMemo } from 'react'
import {
  DEFAULT_MEMBERS,
  DEFAULT_ROLES,
  effectiveCapabilities,
  type Capability,
  type Member,
  type TenantRole,
} from '@/fixtures/roles'
import { useSettings } from '@/lib/settings-store'
import { useActiveUserId, userById } from '@/lib/session'

/**
 * What the active user may do.
 *
 * Roles and role assignments are tenant settings (`org.roles`,
 * `org.members`), so they overlay the fixture defaults the same way every
 * other setting does, and a change takes effect on the next render.
 *
 * This is the application-layer check D-1 assigns to tenant permission sets.
 * In the concepts it gates what is shown; the real check belongs on the
 * server, where hiding a link is not mistaken for enforcing a rule.
 */
export function useAccess() {
  const { values } = useSettings()
  const userId = useActiveUserId()

  return useMemo(() => {
    const roles = (values['org.roles'] as TenantRole[] | undefined) ?? DEFAULT_ROLES
    const members = (values['org.members'] as Member[] | undefined) ?? DEFAULT_MEMBERS
    const user = userById(userId)
    const roleId = members.find((m) => m.userId === user.id)?.roleId
    /* No role resolves to no capabilities: the model fails closed. */
    const role = roles.find((r) => r.id === roleId) ?? null
    const caps = new Set<Capability>(role ? effectiveCapabilities(role) : [])
    const can = (c: Capability) => caps.has(c)
    const holders = (c: Capability) => roles.filter((r) => effectiveCapabilities(r).includes(c))
    return {
      user,
      role,
      roles,
      members,
      can,
      holders,
      /** Assigning roles needs the administrator tier, not just a capability. */
      canAssignRoles: role?.tier === 'tenant_admin',
    }
  }, [values, userId])
}
