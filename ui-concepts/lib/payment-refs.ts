import { customers, locationById, serviceLinks } from '@/fixtures/accounts'
import { invoices } from '@/fixtures/billing'
import { customerName, isIssued } from '@/schemas/models'
import type { CustomerRef, InvoiceRef } from '@/components/payments/vocabulary'

/** The customer and invoice facts both payment pages need, keyed by id. */

export function customerRefs(): Record<string, CustomerRef> {
  return Object.fromEntries(
    customers.map((c) => {
      const link = serviceLinks.find((l) => l.customerId === c.id)
      const loc = link ? locationById.get(link.locationId) : undefined
      return [
        c.id,
        {
          id: c.id,
          name: customerName(c),
          number: c.customer_number,
          street: loc?.address ?? null,
          cityLine: loc ? `${loc.city}, ${loc.state} ${loc.zip}` : null,
        },
      ]
    }),
  )
}

/** Every issued invoice — search by any of them finds its customer, paid or not. */
export function invoiceRefs(): Record<string, InvoiceRef> {
  return Object.fromEntries(
    invoices.filter(isIssued).map((i) => [i.id, { id: i.id, number: i.invoice_number, customerId: i.customer_id }]),
  )
}
