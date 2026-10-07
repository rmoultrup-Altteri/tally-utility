'use client'

import { useState } from 'react'
import { Button, Panel, PanelHeader } from '@/components/ui/Panel'
import { StateBlock } from '@/components/ui/State'
import {
  CAPABILITIES,
  TIER_LABEL,
  USERS,
  capabilityLabel,
  effectiveCapabilities,
  lockedBecause,
  type Capability,
  type Member,
  type TenantRole,
  type Tier,
} from '@/fixtures/roles'
import { asOf } from '@/fixtures/tenant'
import { useAccess } from '@/lib/access'
import { saveSettings, type SettingValue } from '@/lib/settings-store'
import { userById } from '@/lib/session'
import { controlClass, type ChangeLine } from './fields'
import { SaveBar } from './SaveFlow'

/**
 * Roles and access.
 *
 * Who holds which role, and what each role may do, composed from the
 * platform's capability catalog. Change settings is the row that decides who
 * reaches this page at all, so it leads the matrix.
 *
 * Holding Change settings lets someone see this page; changing it takes an
 * administrator-tier role, and nobody may change their own. Access changes
 * apply at once rather than from a date — a revoked permission that lingers
 * until next period is not revoked.
 */
export function RolesAccess() {
  const access = useAccess()
  const [roles, setRoles] = useState<TenantRole[] | null>(null)
  const [members, setMembers] = useState<Member[] | null>(null)
  const [newName, setNewName] = useState('')
  const [newTier, setNewTier] = useState<Tier>('operator')

  const r = roles ?? access.roles
  const m = members ?? access.members
  const editable = access.canAssignRoles
  const roleName = (id: string | undefined) => r.find((x) => x.id === id)?.name ?? 'No role'

  const lines = describe(access.roles, r, access.members, m)
  const adminsLeft = m.filter((x) => r.find((y) => y.id === x.roleId)?.tier === 'tenant_admin').length
  const names = r.map((x) => x.name.trim().toLowerCase())
  const blocked = !adminsLeft
    ? 'Someone must keep an Administrator role.'
    : names.some((n, i) => !n || names.indexOf(n) !== i)
      ? 'Every role needs its own name.'
      : null

  function toggle(role: TenantRole, cap: Capability) {
    const has = role.capabilities.includes(cap)
    setRoles(r.map((x) => (x.id === role.id ? { ...x, capabilities: has ? x.capabilities.filter((c) => c !== cap) : [...x.capabilities, cap] } : x)))
  }

  function addRole() {
    const name = newName.trim()
    if (!name || names.includes(name.toLowerCase())) return
    const id = `role-${name.toLowerCase().replace(/[^a-z0-9]+/g, '-')}-${r.length + 1}`
    setRoles([...r, { id, name, tier: newTier, capabilities: [] }])
    setNewName('')
  }

  return (
    <div className="space-y-5">
      {editable ? null : (
        <StateBlock tone="info">
          <p className="text-data text-exception-info-text">
            You can see roles because yours includes Change settings. Changing them — or who holds them — takes an Administrator role.
          </p>
        </StateBlock>
      )}

      <Panel>
        <PanelHeader title="People" meta={`${m.length} people`} />
        <ul className="divide-y divide-rule-hair">
          {USERS.map((u) => {
            const mine = u.id === access.user.id
            const roleId = m.find((x) => x.userId === u.id)?.roleId
            return (
              <li key={u.id} className="flex flex-wrap items-center justify-between gap-3 px-4 py-2.5">
                <div className="min-w-0">
                  <p className="text-data text-ink-primary">
                    {u.name}
                    {mine ? <span className="ml-1.5 text-micro text-ink-tertiary">you</span> : null}
                  </p>
                  <p className="text-micro text-ink-tertiary">{u.email}</p>
                </div>
                {editable && !mine ? (
                  <select
                    aria-label={`Role for ${u.name}`}
                    className={`${controlClass} w-56`}
                    value={roleId ?? ''}
                    onChange={(e) => setMembers(m.map((x) => (x.userId === u.id ? { ...x, roleId: e.target.value } : x)))}
                  >
                    {r.map((x) => (
                      <option key={x.id} value={x.id}>
                        {x.name}
                      </option>
                    ))}
                  </select>
                ) : (
                  <span className="text-data text-ink-secondary" title={mine && editable ? 'Nobody changes their own role. Ask another administrator.' : undefined}>
                    {roleName(roleId)}
                  </span>
                )}
              </li>
            )
          })}
        </ul>
      </Panel>

      <Panel>
        <PanelHeader title="What each role may do" meta="Capabilities come from the platform catalog" />
        <div className="overflow-x-auto">
          <table className="w-full text-data">
            <thead>
              <tr className="border-b border-rule-hair bg-surface-sunken">
                <th scope="col" className="sticky left-0 min-w-56 bg-surface-sunken px-4 py-2 text-left text-label font-medium text-ink-tertiary">
                  Capability
                </th>
                {r.map((role) => {
                  const held = m.some((x) => x.roleId === role.id)
                  return (
                    <th key={role.id} scope="col" className="min-w-28 px-2 py-2 text-center align-bottom">
                      {editable && !access.roles.some((x) => x.id === role.id) ? (
                        <input
                          aria-label="Role name"
                          className={`${controlClass} h-7 w-28 text-center`}
                          value={role.name}
                          onChange={(e) => setRoles(r.map((x) => (x.id === role.id ? { ...x, name: e.target.value } : x)))}
                        />
                      ) : (
                        <span className="block text-label font-medium text-ink-primary">{role.name}</span>
                      )}
                      <span className="block text-label font-normal text-ink-tertiary">{TIER_LABEL[role.tier]}</span>
                      {editable && !held ? (
                        <button
                          type="button"
                          onClick={() => setRoles(r.filter((x) => x.id !== role.id))}
                          className="text-label text-exception-critical-text hover:underline"
                        >
                          Remove
                        </button>
                      ) : null}
                    </th>
                  )
                })}
              </tr>
            </thead>
            <tbody className="divide-y divide-rule-hair">
              {CAPABILITIES.map((c) => (
                <tr key={c.key} className={c.key === 'settings.edit' ? 'bg-accent-wash/50' : undefined}>
                  <th scope="row" className="sticky left-0 min-w-56 bg-inherit px-4 py-2 text-left font-normal">
                    <span className={`block ${c.key === 'settings.edit' ? 'font-medium text-ink-primary' : 'text-ink-primary'}`}>{c.label}</span>
                    <span className="block text-micro text-ink-tertiary">{c.hint}</span>
                  </th>
                  {r.map((role) => {
                    const lock = lockedBecause(role, c.key)
                    const on = effectiveCapabilities(role).includes(c.key)
                    return (
                      <td key={role.id} className="px-2 py-2 text-center">
                        <input
                          type="checkbox"
                          aria-label={`${role.name}: ${c.label}`}
                          title={lock ?? undefined}
                          className="h-4 w-4 accent-[var(--color-accent)] disabled:opacity-50"
                          checked={on}
                          disabled={!editable || lock !== null}
                          onChange={() => toggle(role, c.key)}
                        />
                      </td>
                    )
                  })}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
        {editable ? (
          <div className="flex flex-wrap items-center gap-2 border-t border-rule-hair bg-surface px-4 py-2.5">
            <input
              aria-label="New role name"
              placeholder="New role, e.g. Meter services lead"
              className={`${controlClass} w-64`}
              value={newName}
              onChange={(e) => setNewName(e.target.value)}
              onKeyDown={(e) => e.key === 'Enter' && addRole()}
            />
            <select aria-label="New role tier" className={`${controlClass} w-auto`} value={newTier} onChange={(e) => setNewTier(e.target.value as Tier)}>
              <option value="operator">Operator</option>
              <option value="viewer">Read only</option>
              <option value="tenant_admin">Administrator</option>
            </select>
            <Button onClick={addRole} disabled={!newName.trim()}>
              Add role
            </Button>
          </div>
        ) : null}
        <div className="border-t border-rule-hair bg-surface px-4 py-3">
          <ul className="list-disc space-y-0.5 pl-4 text-micro text-ink-secondary">
            <li>A role’s tier is fixed when it is created. The database enforces the tier; the application enforces the capabilities.</li>
            <li>Read-only roles can hold no capability that changes anything.</li>
            <li>Administrator roles always keep Change settings, so the utility can never lock itself out.</li>
            <li>Nobody changes their own role, and only an Administrator role can change anyone’s.</li>
          </ul>
        </div>
      </Panel>

      {editable ? (
        <SaveBar
          lines={lines}
          blocked={blocked}
          mode="immediate"
          onDiscard={() => {
            setRoles(null)
            setMembers(null)
          }}
          onSave={(req) => {
            const next: Record<string, SettingValue> = {}
            if (roles) next['org.roles'] = roles
            if (members) next['org.members'] = members
            saveSettings({ 'org.roles': access.roles, 'org.members': access.members }, next, asOf.validAt, req.reason)
            setRoles(null)
            setMembers(null)
          }}
        />
      ) : null}
    </div>
  )
}

function describe(ra: TenantRole[], rb: TenantRole[], ma: Member[], mb: Member[]): ChangeLine[] {
  const out: ChangeLine[] = []
  const line = (label: string, from: string, to: string) => out.push({ key: 'org.roles', label, from, to, tariff: false })
  const nameIn = (rs: TenantRole[], id: string | undefined) => rs.find((x) => x.id === id)?.name ?? 'No role'
  for (const b of mb) {
    const a = ma.find((x) => x.userId === b.userId)
    if (a?.roleId !== b.roleId) line(userById(b.userId).name, nameIn(ra, a?.roleId), nameIn(rb, b.roleId))
  }
  for (const a of ra) if (!rb.some((x) => x.id === a.id)) line(`Role · ${a.name}`, 'Present', 'Removed')
  for (const b of rb) {
    const a = ra.find((x) => x.id === b.id)
    if (!a) {
      line(`Role · ${b.name}`, '—', `Added, ${TIER_LABEL[b.tier]}`)
      continue
    }
    if (a.name !== b.name) line(`Role · ${a.name}`, a.name, b.name)
    const ea = effectiveCapabilities(a)
    const eb = effectiveCapabilities(b)
    for (const c of CAPABILITIES)
      if (ea.includes(c.key) !== eb.includes(c.key))
        line(`${b.name} · ${capabilityLabel.get(c.key)}`, ea.includes(c.key) ? 'Allowed' : 'Not allowed', eb.includes(c.key) ? 'Allowed' : 'Not allowed')
  }
  for (const b of rb) {
    const a = ra.find((x) => x.id === b.id)
    if (!a) for (const c of effectiveCapabilities(b)) line(`${b.name} · ${capabilityLabel.get(c)}`, 'Not allowed', 'Allowed')
  }
  return out
}
