'use client'

import { useEffect, useMemo, useState, type FormEvent } from 'react'
import Link from 'next/link'
import type { Route } from 'next'
import { Button, Panel } from '@/components/ui/Panel'
import { useImported } from '@/lib/imports-store'
import { createRecord, premiseOnFile, premisesAwaitingMeter, type Created } from '@/lib/new-records'
import type { ImportIssue } from '@/lib/assistant/protocol'
import { ErrorSummary, Section, SelectField, TextField, useValues } from '@/components/records/RecordForm'

/**
 * A new meter, by hand — received into stock, or set straight away at a
 * premise that has none. Setting one at an occupied premise with a meter
 * already on the wall is an exchange, which is not this form.
 *
 * Opened from a premise (`?address=` from New premise or New account), that
 * premise is picked once the browser's records load, if it still has no meter.
 */

const INITIAL = { read_type: 'amr', multiplier: '1.0000', meter_status: 'in_stock', location_number: '' }

const primaryLink =
  'inline-flex h-8 items-center rounded-sm border border-accent bg-accent px-3.5 text-data font-medium text-ink-inverse hover:bg-accent-hover'
const secondaryLink =
  'inline-flex h-8 items-center rounded-sm border border-rule-solid bg-surface-raised px-3.5 text-data font-medium text-ink-primary hover:border-rule-heavy hover:bg-surface-sunken'

export function NewMeterForm({ premise = null }: { premise?: string | null }) {
  const { values, set, reset } = useValues(INITIAL)
  const [errors, setErrors] = useState<ImportIssue[]>([])
  const [done, setDone] = useState<Extract<Created, { ok: true }> | null>(null)
  const [at, setAt] = useState<{ number: string; label: string } | null>(null)
  const [carried, setCarried] = useState(premise)
  const imported = useImported()
  /* Recomputed when something is added, so a premise just given a meter drops off the list. */
  const premises = useMemo(() => premisesAwaitingMeter(imported), [imported])
  const setting = values.location_number !== ''

  /* A premise added in this browser is only listed once the store hydrates; pick it then, once. */
  useEffect(() => {
    if (!carried || !premises.some((p) => p.location_number === carried)) return
    pickPremise(carried)
    setCarried(null)
  }, [carried, premises])

  function pickPremise(v: string) {
    set('location_number', v)
    /* A meter set at a premise is in service; one that is not is on the shelf. */
    if (v && values.meter_status === 'in_stock') set('meter_status', 'active')
    if (!v && values.meter_status === 'active') set('meter_status', 'in_stock')
  }

  function submit(e: FormEvent) {
    e.preventDefault()
    /* Read before saving: once the meter is set, its premise leaves the list. */
    const target = premises.find((p) => p.location_number === values.location_number)
    const result = createRecord('meters', values)
    if (!result.ok) {
      setErrors(result.errors)
      return
    }
    setErrors([])
    setAt(target ? { number: target.location_number, label: `${target.address}, ${target.city}` } : null)
    setDone(result)
  }

  if (done) {
    const m = done.records.meters[0]
    /* Set at a premise nobody takes service at yet: the account is the next thing it waits for. */
    const vacant = at ? !premiseOnFile(imported, at.number)?.customer : false
    return (
      <Panel>
        <div className="space-y-3 px-5 py-5">
          <p className="text-h3 text-ink-primary">
            Meter <span className="ident">{m.meter_number}</span> added
          </p>
          <p className="text-data text-ink-secondary">
            {at ? `Set at ${at.label}${vacant ? ' — nobody taking service there yet.' : '.'}` : 'Not set at a service address.'}
          </p>
          {done.warnings.map((w, i) => (
            <p key={i} className="text-data text-exception-warning-text">
              {w.message}
            </p>
          ))}
          <p className="text-micro text-ink-tertiary">Kept in this browser until the API exists, alongside anything imported through the assistant.</p>
          <div className="flex flex-wrap gap-2 pt-1">
            {vacant && at ? (
              <Link href={`/customers/new?address=${encodeURIComponent(at.number)}` as Route} className={primaryLink}>
                Open an account here
              </Link>
            ) : null}
            <Link href={'/meters' as Route} className={vacant ? secondaryLink : primaryLink}>
              Back to Meters
            </Link>
            <Button
              variant="quiet"
              onClick={() => {
                reset()
                setDone(null)
              }}
            >
              Add another meter
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

      <Section title="Meter">
        <TextField name="meter_number" label="Meter number" placeholder="Assigned if blank" {...field} />
        <TextField name="serial_number" label="Serial number" {...field} />
        <SelectField name="meter_status" label="Status" options={['in_stock', 'active', 'inactive']} {...field} />
        <TextField name="manufacturer" label="Manufacturer" {...field} />
        <TextField name="model" label="Model" {...field} />
        <TextField name="size" label="Size" placeholder="250" {...field} />
      </Section>

      <Section title="Reading">
        <SelectField name="read_type" label="Read type" options={['amr', 'ami', 'manual']} {...field} />
        <TextField name="ami_endpoint_id" label="AMR / AMI endpoint ID" hint={values.read_type === 'manual' ? 'None for a manually read meter' : undefined} {...field} />
        <TextField name="multiplier" label="Multiplier" {...field} />
        <TextField name="gas_btu_factor" label="BTU factor" placeholder="1.0350" {...field} />
        <TextField name="rollover_point" label="Rollover point" placeholder="10000" {...field} />
        <TextField name="route_id" label="Route" placeholder="RT-14" {...field} />
        <TextField name="route_sequence" label="Route sequence" type="number" {...field} />
      </Section>

      <Section title="Service address" meta="optional — where it is set">
        <SelectField
          name="location_number"
          label="Set at service address"
          blank="Not set — in stock"
          options={premises.map((p) => ({ value: p.location_number, label: `${p.address}, ${p.city} · ${p.location_number}` }))}
          hint={premises.length ? 'Service addresses with no meter set' : 'Every service address on file already has a meter set'}
          className="sm:col-span-2"
          values={values}
          set={(_, v) => pickPremise(v)}
          errors={errors}
        />
        {setting ? null : <p className="self-end pb-1.5 text-micro text-ink-tertiary">A meter on the shelf has no service address; set it from the meter later.</p>}
        <p className="sm:col-span-2 lg:col-span-3 text-micro text-ink-tertiary">
          Address not listed?{' '}
          <Link href={'/service-addresses/new' as Route} className="text-accent-text hover:text-accent-text-hover underline-offset-2 hover:underline">
            Add a service address
          </Link>{' '}
          first.
        </p>
      </Section>

      <div className="flex items-center gap-2">
        <Button type="submit" variant="primary">
          Add meter
        </Button>
        <Link href={'/meters' as Route} className="px-2 text-data text-ink-secondary hover:text-ink-primary">
          Cancel
        </Link>
      </div>
    </form>
  )
}
