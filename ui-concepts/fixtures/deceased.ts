import type { DeceasedStep } from '@/lib/deceased'

/**
 * Wendell Fry (cus-0006) died on 2 January 2026.
 *
 * His son reported it on the 8th, and a certified copy of the death
 * certificate came in on the 13th. Nothing has come in since — no obituary,
 * nothing showing who may take the account over — so the one-month clock ran
 * out on 13 February and the review exception is on the queue.
 *
 * The account was already in collections. The hold froze it where it stood:
 * the last notice predates the death, and no shutoff or collections step has
 * been taken since.
 */
export const seedDeceasedSteps: DeceasedStep[] = [
  {
    id: 'dec-0006-1',
    customer_id: 'cus-0006',
    kind: 'death_recorded',
    date_of_death: '2026-01-02',
    on: '2026-01-08',
    at: '2026-01-08T10:41:00-06:00',
    by: 'Dana Pearce',
    notes: 'Son, Marcus Fry, called to report. Says a certified copy of the certificate is in the mail.',
  },
  {
    id: 'dec-0006-2',
    customer_id: 'cus-0006',
    kind: 'proof',
    proof: 'death_certificate',
    received: '2026-01-13',
    on: '2026-01-13',
    at: '2026-01-13T14:05:00-06:00',
    by: 'Renee Alvarado',
    notes: 'Certified copy received by mail. Scanned to the account.',
  },
]
