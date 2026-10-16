'use client'

import { useState, type FormEvent } from 'react'
import Link from 'next/link'
import type { Route } from 'next'
import { Button, Panel } from '@/components/ui/Panel'
import { CustomerType } from '@/schemas/enums'
import { billingAddressLines, customerName } from '@/schemas/models'
import { cycle, tenant } from '@/fixtures/tenant'
import { useImported } from '@/lib/imports-store'
import { createRecord, premiseOnFile, type Created } from '@/lib/new-records'
import type { ImportIssue } from '@/lib/assistant/protocol'
import { CheckField, ErrorSummary, Section, SelectField, TextField, useValues } from '@/components/records/RecordForm'

/**
 * A new account, by hand: the customer, the premise they take service at,
 * and the meter on it if one is set. The same three halves an accounts import
 * row has, validated by the same rules.
 *
 * Opened from a premise (`?address=` from New premise or New meter), the
 * address is already on file: the form shows it rather than asking for it
 * again, and shows the meter set there if there is one.
 *
 * Bills and letters go to the service address unless "Same as service
 * address" is unticked; then the billing address is asked for and kept on the
 * customer.
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
  billing_same: 'yes',
  billing_state: 'TX',
}

const CUSTOMER_KEYS = ['customer_number', 'customer_type', 'email', 'phone', 'move_in_date', 'deposit_amount', 'is_tax_exempt']
const PREMISE_KEYS = ['location_number', 'address', 'city', 'state', 'zip', 'inside_city_limits', 'billing_cycle']
const BILLING_KEYS = ['billing_address_line1', 'billing_address_line2', 'billing_city', 'billing_state', 'billing_zip']
const METER_KEYS = ['meter_number', 'serial_number', 'manufacturer', 'model', 'size', 'read_type', 'ami_endpoint_id', 'route_id', 'route_sequence']

const primaryLink =
  'inline-flex h-8 items-center rounded-sm border border-accent bg-accent px-3.5 text-data font-medium text-ink-inverse hover:bg-accent-hover'
const secondaryLink =
  'inline-flex h-8 items-center rounded-sm border border-rule-solid bg-surface-raised px-3.5 text-data font-medium text-ink-primary hover:border-rule-heavy hover:bg-surface-sunken'

export function NewAccountForm({ premise = null }: { premise?: string | null }) {
  const { values, set, reset } = useValues(INITIAL)
  const [errors, setErrors] = useState<ImportIssue[]>([])
  const [done, setDone] = useState<{ result: Extract<Created, { ok: true }>; premise: string } | null>(null)
  const [carried, setCarried] = useState(premise ?? '')
  const imported = useImported()
  /* Null until the store hydrates, and for a number not on file: then the form asks for the address as usual. */
  const known = carried ? premiseOnFile(imported, carried) : null
  const person = values.customer_type === 'residential'
  const inside = values.inside_city_limits === 'yes'
  const withMeter = !known?.meter && (values.meter_number ?? '').trim() !== ''
  const sameAddress = values.billing_same === 'yes'

  function submit(e: FormEvent) {
    e.preventDefault()
    /* Only the fields this kind of account uses: a company's account carries no first and last name. */
    const keys = [
      ...CUSTOMER_KEYS,
      ...(person ? ['first_name', 'last_name'] : ['company_name']),
      ...(known ? [] : PREMISE_KEYS),
      ...(!known && inside ? ['franchise_city'] : []),
      ...(withMeter ? METER_KEYS : []),
      ...(sameAddress ? [] : BILLING_KEYS),
    ]
    const fields = Object.fromEntries(keys.map((k) => [k, values[k] ?? '']))
    if (known) fields.location_number = known.location.location_number
    const result = createRecord('accounts', fields)
    if (!result.ok) {
      setErrors(result.errors)
      return
    }
    setErrors([])
    setDone({ result, premise: result.records.locations[0]?.location_number ?? known?.location.location_number ?? fields.location_number })
  }

  if (done) {
    const c = done.result.records.customers[0]
    /* Read after saving, so a meter already set at a premise moved into shows as this account's. */
    const at = premiseOnFile(imported, done.premise)
    const mtr = done.result.records.meters[0] ?? at?.meter ?? null
    const billTo = billingAddressLines(c)
    return (
      <Panel>
        <div className="space-y-3 px-5 py-5">
          <p className="text-h3 text-ink-primary">Account {c.customer_number} opened for {customerName(c)}</p>
          <ul className="space-y-1 text-data text-ink-secondary">
            {at ? (
              <li>
                Service address <span className="ident">{at.location.location_number}</span> · {at.location.address}, {at.location.city} {at.location.zip}
              </li>
            ) : null}
            <li>{billTo ? <>Bills mailed to {billTo.join(', ')}.</> : 'Bills mailed to the service address.'}</li>
            <li>{mtr ? <>Meter <span className="ident">{mtr.meter_number}</span> set at the service address.</> : 'No meter set yet — set one when it goes in.'}</li>
            {done.result.warnings.map((w, i) => (
              <li key={i} className="text-exception-warning-text">
                {w.message}
              </li>
            ))}
          </ul>
          <p className="text-micro text-ink-tertiary">Kept in this browser until the API exists, alongside anything imported through the assistant.</p>
          <div className="flex flex-wrap gap-2 pt-1">
            {mtr ? null : (
              <Link href={`/meters/new?address=${encodeURIComponent(done.premise)}` as Route} className={primaryLink}>
                Set a meter here
              </Link>
            )}
            <Link href={'/customers' as Route} className={mtr ? primaryLink : secondaryLink}>
              Back to Accounts
            </Link>
            <Button
              variant="quiet"
              onClick={() => {
                reset()
                setCarried('')
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

      {known ? (
        <Section title="Service address" meta={<span className="ident">{known.location.location_number}</span>}>
          <div className="sm:col-span-2 lg:col-span-3 space-y-1">
            <p className="text-data text-ink-primary">
              {known.location.address}, {known.location.city}, {known.location.state} {known.location.zip}
            </p>
            {known.customer ? (
              <p className="text-micro text-exception-warning-text">
                {customerName(known.customer)} already takes service here; this opens a second account at the service address.
              </p>
            ) : (
              <p className="text-micro text-ink-tertiary">On file, nobody taking service yet.</p>
            )}
            <Button variant="quiet" onClick={() => setCarried('')}>
              Use a different address
            </Button>
          </div>
        </Section>
      ) : (
        <Section title="Service address" meta="where the gas is delivered">
          <TextField name="address" label="Street address" required className="sm:col-span-2" {...field} />
          <TextField name="city" label="City" required {...field} />
          <TextField name="state" label="State" {...field} />
          <TextField name="zip" label="ZIP" required {...field} />
          <TextField
            name="location_number"
            label="Service address number"
            placeholder="Assigned if blank"
            hint="Enter an existing service address to move this customer in"
            {...field}
          />
          <CheckField name="inside_city_limits" label="Inside city limits" hint="Franchise fees follow it" values={values} set={set} />
          {inside ? <SelectField name="franchise_city" label="Franchise city" options={tenant.franchiseCities} {...field} /> : null}
          <TextField name="billing_cycle" label="Billing cycle" {...field} />
        </Section>
      )}

      <Section title="Billing address" meta="where bills and letters are mailed">
        <div className="sm:col-span-2 lg:col-span-3">
          <CheckField
            name="billing_same"
            label="Same as service address"
            hint="Untick for a landlord, a P.O. box or an office that pays the bill"
            values={values}
            set={set}
          />
        </div>
        {sameAddress ? null : (
          <>
            <TextField name="billing_address_line1" label="Street address or P.O. box" required className="sm:col-span-2" {...field} />
            <TextField name="billing_address_line2" label="Line 2" placeholder="Attn, suite or unit" {...field} />
            <TextField name="billing_city" label="City" required {...field} />
            <TextField name="billing_state" label="State" {...field} />
            <TextField name="billing_zip" label="ZIP" required {...field} />
          </>
        )}
      </Section>

      {known?.meter ? (
        <Section title="Meter" meta={<span className="ident">{known.meter.meter_number}</span>}>
          <p className="sm:col-span-2 lg:col-span-3 text-data text-ink-secondary">Already set at this service address; it serves the new account.</p>
        </Section>
      ) : (
        <Section title="Meter" meta="optional — leave blank if none is set yet; you can set one after">
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
      )}

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
