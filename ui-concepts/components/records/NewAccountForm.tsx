'use client'

import { useState, type FormEvent } from 'react'
import Link from 'next/link'
import type { Route } from 'next'
import { Button, Panel } from '@/components/ui/Panel'
import { CustomerType } from '@/schemas/enums'
import { customerName } from '@/schemas/models'
import { cycle, tenant } from '@/fixtures/tenant'
import { createRecord, type Created } from '@/lib/new-records'
import type { ImportIssue } from '@/lib/assistant/protocol'
import { CheckField, ErrorSummary, Section, SelectField, TextField, useValues } from '@/components/records/RecordForm'

/**
 * A new account, by hand: the customer, the premise they take service at,
 * and the meter on it if one is set. The same three halves an accounts import
 * row has, validated by the same rules.
 *
 * Disconnect protections, billing holds and an opening balance are not here
 * for the same reason they are not in an import: each is set on the account
 * afterwards, with a reason, through the events that record it.
 */

const INITIAL = {
  customer_type: 'residential',
  state: 'TX',
  inside_city_limits: 'yes',
  franchise_city: tenant.franchiseCities[0],
  billing_cycle: cycle.code,
  read_type: 'amr',
  is_tax_exempt: 'no',
}

const CUSTOMER_KEYS = ['customer_number', 'customer_type', 'email', 'phone', 'move_in_date', 'deposit_amount', 'is_tax_exempt']
const PREMISE_KEYS = ['location_number', 'address', 'city', 'state', 'zip', 'inside_city_limits', 'billing_cycle']
const METER_KEYS = ['meter_number', 'serial_number', 'manufacturer', 'model', 'size', 'read_type', 'ami_endpoint_id', 'route_id', 'route_sequence']

export function NewAccountForm() {
  const { values, set, reset } = useValues(INITIAL)
  const [errors, setErrors] = useState<ImportIssue[]>([])
  const [done, setDone] = useState<Extract<Created, { ok: true }> | null>(null)
  const person = values.customer_type === 'residential'
  const inside = values.inside_city_limits === 'yes'
  const withMeter = (values.meter_number ?? '').trim() !== ''

  function submit(e: FormEvent) {
    e.preventDefault()
    /* Only the fields this kind of account uses: a company's account carries no first and last name. */
    const keys = [
      ...CUSTOMER_KEYS,
      ...(person ? ['first_name', 'last_name'] : ['company_name']),
      ...PREMISE_KEYS,
      ...(inside ? ['franchise_city'] : []),
      ...(withMeter ? METER_KEYS : []),
    ]
    const result = createRecord('accounts', Object.fromEntries(keys.map((k) => [k, values[k] ?? ''])))
    if (!result.ok) {
      setErrors(result.errors)
      return
    }
    setErrors([])
    setDone(result)
  }

  if (done) {
    const c = done.records.customers[0]
    const loc = done.records.locations[0]
    const mtr = done.records.meters[0]
    return (
      <Panel>
        <div className="space-y-3 px-5 py-5">
          <p className="text-h3 text-ink-primary">Account {c.customer_number} opened for {customerName(c)}</p>
          <ul className="space-y-1 text-data text-ink-secondary">
            {loc ? (
              <li>
                Premise <span className="ident">{loc.location_number}</span> · {loc.address}, {loc.city} {loc.zip}
              </li>
            ) : (
              <li>Linked to the premise already on file.</li>
            )}
            <li>{mtr ? <>Meter <span className="ident">{mtr.meter_number}</span> set at the premise.</> : 'No meter set yet.'}</li>
            {done.warnings.map((w, i) => (
              <li key={i} className="text-exception-warning-text">
                {w.message}
              </li>
            ))}
          </ul>
          <p className="text-micro text-ink-tertiary">Kept in this browser until the API exists, alongside anything imported through the assistant.</p>
          <div className="flex gap-2 pt-1">
            <Link
              href={'/customers' as Route}
              className="inline-flex h-8 items-center rounded-sm border border-accent bg-accent px-3.5 text-data font-medium text-ink-inverse hover:bg-accent-hover"
            >
              Back to Accounts
            </Link>
            <Button
              onClick={() => {
                reset()
                setDone(null)
              }}
            >
              Add another account
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

      <Section title="Customer">
        <SelectField name="customer_type" label="Customer type" options={CustomerType.options} {...field} />
        {person ? (
          <>
            <TextField name="first_name" label="First name" {...field} />
            <TextField name="last_name" label="Last name" required {...field} />
          </>
        ) : (
          <TextField name="company_name" label="Company or agency name" required className="sm:col-span-2" {...field} />
        )}
        <TextField name="phone" label="Phone" type="tel" placeholder="(979) 555-0100" {...field} />
        <TextField name="email" label="Email" type="email" {...field} />
        <TextField name="move_in_date" label="Move-in date" type="date" {...field} />
        <TextField name="deposit_amount" label="Deposit" placeholder="0.00" hint="Held, not billed" {...field} />
        <TextField name="customer_number" label="Account number" placeholder="Assigned if blank" {...field} />
        <CheckField name="is_tax_exempt" label="Tax exempt" hint="Certificate on file" values={values} set={set} />
      </Section>

      <Section title="Service address" meta="the premise the gas is delivered to">
        <TextField name="address" label="Street address" required className="sm:col-span-2" {...field} />
        <TextField name="city" label="City" required {...field} />
        <TextField name="state" label="State" {...field} />
        <TextField name="zip" label="ZIP" required {...field} />
        <TextField
          name="location_number"
          label="Premise number"
          placeholder="Assigned if blank"
          hint="Enter an existing premise to move this customer in"
          {...field}
        />
        <CheckField name="inside_city_limits" label="Inside city limits" hint="Franchise fees follow it" values={values} set={set} />
        {inside ? <SelectField name="franchise_city" label="Franchise city" options={tenant.franchiseCities} {...field} /> : null}
        <TextField name="billing_cycle" label="Billing cycle" {...field} />
      </Section>

      <Section title="Meter" meta="optional — leave the number blank if none is set yet">
        <TextField name="meter_number" label="Meter number" {...field} />
        {withMeter ? (
          <>
            <TextField name="serial_number" label="Serial number" {...field} />
            <SelectField name="read_type" label="Read type" options={['amr', 'ami', 'manual']} {...field} />
            <TextField name="ami_endpoint_id" label="AMR / AMI endpoint ID" {...field} />
            <TextField name="manufacturer" label="Manufacturer" {...field} />
            <TextField name="model" label="Model" {...field} />
            <TextField name="size" label="Size" {...field} />
            <TextField name="route_id" label="Route" placeholder="RT-14" {...field} />
            <TextField name="route_sequence" label="Route sequence" type="number" {...field} />
          </>
        ) : null}
      </Section>

      <div className="flex items-center gap-2">
        <Button type="submit" variant="primary">
          Open account
        </Button>
        <Link href={'/customers' as Route} className="px-2 text-data text-ink-secondary hover:text-ink-primary">
          Cancel
        </Link>
      </div>
    </form>
  )
}
