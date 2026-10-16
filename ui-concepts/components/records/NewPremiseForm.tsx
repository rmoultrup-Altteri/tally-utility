'use client'

import { useState, type FormEvent } from 'react'
import Link from 'next/link'
import type { Route } from 'next'
import { Button, Panel } from '@/components/ui/Panel'
import { cycle, tenant } from '@/fixtures/tenant'
import { createRecord, type Created } from '@/lib/new-records'
import type { ImportIssue } from '@/lib/assistant/protocol'
import { CheckField, ErrorSummary, Section, SelectField, TextField, useValues } from '@/components/records/RecordForm'

/**
 * A new premise, by hand — a service address with nobody and nothing at it
 * yet: a new build, a lot just tapped, an address ahead of its move-in.
 *
 * The saved page leads straight on to the two things a premise waits for, a
 * meter and an account, carrying the premise number so nobody retypes it.
 */

const INITIAL = {
  state: 'TX',
  inside_city_limits: 'yes',
  franchise_city: tenant.franchiseCities[0],
  billing_cycle: cycle.code,
}

const KEYS = ['location_number', 'address', 'city', 'state', 'zip', 'inside_city_limits', 'billing_cycle']

const primaryLink =
  'inline-flex h-8 items-center rounded-sm border border-accent bg-accent px-3.5 text-data font-medium text-ink-inverse hover:bg-accent-hover'
const secondaryLink =
  'inline-flex h-8 items-center rounded-sm border border-rule-solid bg-surface-raised px-3.5 text-data font-medium text-ink-primary hover:border-rule-heavy hover:bg-surface-sunken'

export function NewPremiseForm() {
  const { values, set, reset } = useValues(INITIAL)
  const [errors, setErrors] = useState<ImportIssue[]>([])
  const [done, setDone] = useState<Extract<Created, { ok: true }> | null>(null)
  const inside = values.inside_city_limits === 'yes'

  function submit(e: FormEvent) {
    e.preventDefault()
    const keys = [...KEYS, ...(inside ? ['franchise_city'] : [])]
    const result = createRecord('locations', Object.fromEntries(keys.map((k) => [k, values[k] ?? ''])))
    if (!result.ok) {
      setErrors(result.errors)
      return
    }
    setErrors([])
    setDone(result)
  }

  if (done) {
    const loc = done.records.locations[0]
    const q = `?address=${encodeURIComponent(loc.location_number)}`
    return (
      <Panel>
        <div className="space-y-3 px-5 py-5">
          <p className="text-h3 text-ink-primary">
            Service address <span className="ident">{loc.location_number}</span> added
          </p>
          <p className="text-data text-ink-secondary">
            {loc.address}, {loc.city} {loc.zip} · no meter set, nobody taking service yet.
          </p>
          {done.warnings.map((w, i) => (
            <p key={i} className="text-data text-exception-warning-text">
              {w.message}
            </p>
          ))}
          <p className="text-micro text-ink-tertiary">Kept in this browser until the API exists, alongside anything imported through the assistant.</p>
          <div className="flex flex-wrap gap-2 pt-1">
            <Link href={`/customers/new${q}` as Route} className={primaryLink}>
              Open an account here
            </Link>
            <Link href={`/meters/new${q}` as Route} className={secondaryLink}>
              Set a meter here
            </Link>
            <Button
              variant="quiet"
              onClick={() => {
                reset()
                setDone(null)
              }}
            >
              Add another service address
            </Button>
          </div>
        </div>
      </Panel>
    )
  }

  const field = { values, set, errors }
  return (
    <form onSubmit={submit} className="space-y-5" noValidate>
      <ErrorSummary errors={errors} />

      <Section title="Service address" meta="where the gas is delivered">
        <TextField name="address" label="Street address" required className="sm:col-span-2" {...field} />
        <TextField name="city" label="City" required {...field} />
        <TextField name="state" label="State" {...field} />
        <TextField name="zip" label="ZIP" required {...field} />
        <TextField name="location_number" label="Service address number" placeholder="Assigned if blank" {...field} />
        <CheckField name="inside_city_limits" label="Inside city limits" hint="Franchise fees follow it" values={values} set={set} />
        {inside ? <SelectField name="franchise_city" label="Franchise city" options={tenant.franchiseCities} {...field} /> : null}
        <TextField name="billing_cycle" label="Billing cycle" {...field} />
      </Section>

      <div className="flex items-center gap-2">
        <Button type="submit" variant="primary">
          Add service address
        </Button>
        <Link href={'/customers' as Route} className="px-2 text-data text-ink-secondary hover:text-ink-primary">
          Cancel
        </Link>
      </div>
    </form>
  )
}
