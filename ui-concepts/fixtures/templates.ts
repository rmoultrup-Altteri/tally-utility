/**
 * Every message the utility sends a customer, as editable templates.
 *
 * One catalog, not one per feature: the dunning engine, high-bill outreach,
 * the bill explanation, the rate case and the service-order desk all send from
 * here, so a change to the wording of a reminder is made once and seen
 * everywhere it goes out.
 *
 * Three kinds of text live in a template, and the editor treats them
 * differently:
 * - the utility's own words, which anyone with Edit communications may change;
 * - merge fields (`{{bill.amount_due}}`), filled from the account at send time;
 * - required text (`{{required.…}}`) that a rule prescribes. It is shown, cited
 *   and placed, but not edited here — removing the token is refused, because a
 *   termination notice without the customer's rights on it is not a notice.
 *
 * In the schema this is a target table (`communication_templates`, versioned
 * close-then-insert like every other reference record). Nothing here is a
 * column yet; the concept is built to that spec.
 */

export type Channel = 'email' | 'sms' | 'letter'
export type Lang = 'en' | 'es'
export type Category = 'Billing' | 'Payments' | 'Collections' | 'Service' | 'Safety' | 'Regulatory'

export const CATEGORIES: Category[] = ['Billing', 'Payments', 'Collections', 'Service', 'Safety', 'Regulatory']

export const CHANNEL_LABEL: Record<Channel, string> = { email: 'Email', sms: 'Text message', letter: 'Letter' }
export const LANG_LABEL: Record<Lang, string> = { en: 'English', es: 'Spanish' }

/** Subject is the email subject or the letter's heading; SMS has none. */
export type ChannelContent = { subject?: string; body: string }
export type TemplateContent = Partial<Record<Channel, Partial<Record<Lang, ChannelContent>>>>

export type RequiredBlock = {
  key: string
  label: string
  citation: string
  text: Record<Lang, string>
}

export type Template = {
  id: string
  name: string
  category: Category
  purpose: string
  /** What sends it. A template nothing sends is a draft. */
  trigger: string
  channels: Channel[]
  /** Regulatory text, or a message a customer must receive whatever their preferences. */
  kind: 'transactional' | 'regulatory' | 'courtesy'
  required?: RequiredBlock[]
  usedBy?: { href: string; label: string }
  content: TemplateContent
  updatedAt: string
  updatedBy: string
}

const TERMINATION_RIGHTS: RequiredBlock = {
  key: 'termination_rights',
  label: 'Customer rights before disconnection',
  citation: '16 TAC §7.460',
  text: {
    en: 'You may avoid disconnection by paying the past-due amount, by entering a payment agreement, or if a physician certifies that disconnection would make someone in your home seriously ill. We will not disconnect service on a weekend or holiday or the day before one, or when the temperature is forecast to be at or below freezing. If you dispute this bill, call {{utility.phone}}. You may also contact the Railroad Commission of Texas.',
    es: 'Puede evitar la desconexión pagando el saldo vencido, haciendo un acuerdo de pago, o si un médico certifica que la desconexión enfermaría gravemente a alguien en su hogar. No desconectaremos el servicio en fin de semana o día festivo ni el día anterior, ni cuando se pronostique una temperatura igual o menor al punto de congelación. Si disputa esta factura, llame al {{utility.phone}}. También puede comunicarse con la Comisión de Ferrocarriles de Texas.',
  },
}

const RATE_NOTICE: RequiredBlock = {
  key: 'rate_notice',
  label: 'Statement of intent notice',
  citation: 'Tex. Util. Code §104.103',
  text: {
    en: 'The proposed rates are subject to review by the Railroad Commission of Texas and may change. A complete copy of the statement of intent is available at our office and at {{utility.portal_url}}. To comment or intervene, contact the Railroad Commission of Texas and refer to {{rate.docket}}.',
    es: 'Las tarifas propuestas están sujetas a revisión por la Comisión de Ferrocarriles de Texas y pueden cambiar. Una copia completa de la declaración de intención está disponible en nuestra oficina y en {{utility.portal_url}}. Para comentar o intervenir, comuníquese con la Comisión de Ferrocarriles de Texas y mencione {{rate.docket}}.',
  },
}

const LEAK_STEPS: RequiredBlock = {
  key: 'leak_steps',
  label: 'What to do if you smell gas',
  citation: '49 CFR §192.616',
  text: {
    en: 'If you smell gas — a rotten-egg odor — leave right away. Do not use light switches, phones, or anything that could make a spark. From a safe distance, call {{utility.emergency_phone}} or 911. We respond 24 hours a day at no charge.',
    es: 'Si huele a gas — un olor a huevo podrido — salga de inmediato. No use interruptores, teléfonos ni nada que pueda causar una chispa. Desde un lugar seguro, llame al {{utility.emergency_phone}} o al 911. Respondemos las 24 horas, sin costo.',
  },
}

const by = 'Dana Pearce'

export const templates: Template[] = [
  /* ---- Billing ------------------------------------------------------- */
  {
    id: 'bill-ready',
    name: 'Your bill is ready',
    category: 'Billing',
    purpose: 'Tells a paperless customer their statement is posted.',
    trigger: 'A bill is issued to a paperless account',
    channels: ['email', 'sms'],
    kind: 'transactional',
    updatedAt: '2026-01-08T10:02:00-06:00',
    updatedBy: by,
    content: {
      email: {
        en: {
          subject: 'Your {{utility.name}} bill for {{bill.period}} is ready',
          body: 'Hi {{customer.first_name}},\n\nYour bill for {{bill.period}} is ready. The amount due is {{bill.amount_due}}, due {{bill.due_date}}.\n\nView or pay it at {{utility.portal_url}}. If you are on AutoPay, there is nothing to do.\n\nQuestions? Call {{utility.phone}}.\n\n{{utility.name}}',
        },
        es: {
          subject: 'Su factura de {{utility.name}} de {{bill.period}} está lista',
          body: 'Hola {{customer.first_name}}:\n\nSu factura de {{bill.period}} está lista. El monto a pagar es {{bill.amount_due}}, con vencimiento el {{bill.due_date}}.\n\nVéala o páguela en {{utility.portal_url}}. Si tiene pago automático, no tiene que hacer nada.\n\n¿Preguntas? Llame al {{utility.phone}}.\n\n{{utility.name}}',
        },
      },
      sms: {
        en: { body: '{{utility.name}}: your {{bill.period}} bill of {{bill.amount_due}} is due {{bill.due_date}}. View or pay: {{utility.portal_url}}' },
        es: { body: '{{utility.name}}: su factura de {{bill.period}} por {{bill.amount_due}} vence el {{bill.due_date}}. Vea o pague: {{utility.portal_url}}' },
      },
    },
  },
  {
    id: 'high-bill-heads-up',
    name: 'High-bill heads-up',
    category: 'Billing',
    purpose: 'Warns a customer before a bill that jumped lands, with the reason in one line.',
    trigger: 'High-bill outreach, before the bill posts',
    channels: ['email', 'sms'],
    kind: 'courtesy',
    usedBy: { href: '/outreach', label: 'High-bill outreach' },
    updatedAt: '2026-02-12T16:40:00-06:00',
    updatedBy: by,
    content: {
      email: {
        en: {
          subject: 'A heads-up about your {{bill.period}} gas bill',
          body: 'Hi {{customer.first_name}},\n\nWe wanted you to hear it from us first: your {{bill.period}} bill will be about {{bill.current_charges}}, which is {{bill.change_amount}} more than {{bill.compare_label}}.\n\n{{bill.main_reason}}\n\nYou can see exactly what changed, line by line, at {{bill.explain_link}}.\n\nIf a bigger bill is hard right now, we can help. Budget billing evens your payments across the year, and we can set up a payment arrangement or refer you to energy assistance. Just call {{utility.phone}}.\n\n{{utility.name}}',
        },
        es: {
          subject: 'Un aviso sobre su factura de gas de {{bill.period}}',
          body: 'Hola {{customer.first_name}}:\n\nQueríamos que lo supiera primero por nosotros: su factura de {{bill.period}} será de aproximadamente {{bill.current_charges}}, es decir {{bill.change_amount}} más que {{bill.compare_label}}.\n\n{{bill.main_reason}}\n\nPuede ver exactamente qué cambió, línea por línea, en {{bill.explain_link}}.\n\nSi una factura más alta es difícil ahora, podemos ayudar. La facturación nivelada reparte sus pagos durante el año, y podemos hacer un acuerdo de pago o referirle a asistencia de energía. Llame al {{utility.phone}}.\n\n{{utility.name}}',
        },
      },
      sms: {
        en: { body: '{{utility.name}}: heads-up, your {{bill.period}} bill will be about {{bill.current_charges}} ({{bill.change_amount}} more than {{bill.compare_label}}), mostly from {{bill.main_reason_short}}. Why: {{bill.explain_link}}' },
        es: { body: '{{utility.name}}: aviso, su factura de {{bill.period}} será de unos {{bill.current_charges}} ({{bill.change_amount}} más que {{bill.compare_label}}), sobre todo por {{bill.main_reason_short}}. Detalles: {{bill.explain_link}}' },
      },
    },
  },
  {
    id: 'bill-explained',
    name: 'Why your bill changed',
    category: 'Billing',
    purpose: 'The bill explanation, sent after a call or printed with a disputed bill.',
    trigger: 'A CSR sends it from a bill’s explanation',
    channels: ['email', 'letter'],
    kind: 'courtesy',
    usedBy: { href: '/invoices/inv-0001/explain', label: 'Bill explanation' },
    updatedAt: '2026-02-03T09:15:00-06:00',
    updatedBy: by,
    content: {
      email: {
        en: {
          subject: 'Why your {{bill.period}} bill changed',
          body: 'Hi {{customer.first_name}},\n\nThanks for calling about your {{bill.period}} bill. Here is the short version: your bill is {{bill.change_amount}} more than {{bill.compare_label}}. {{bill.main_reason}}\n\nThe full breakdown — weather, usage, gas cost and every rate — is at {{bill.explain_link}}. Each step adds up to the exact difference.\n\nIf anything still looks wrong, reply to this email or call {{utility.phone}} and we will look again.\n\n{{utility.name}}',
        },
        es: {
          subject: 'Por qué cambió su factura de {{bill.period}}',
          body: 'Hola {{customer.first_name}}:\n\nGracias por llamar sobre su factura de {{bill.period}}. En resumen: su factura es {{bill.change_amount}} más que {{bill.compare_label}}. {{bill.main_reason}}\n\nEl desglose completo — clima, uso, costo del gas y cada tarifa — está en {{bill.explain_link}}. Cada paso suma la diferencia exacta.\n\nSi algo todavía parece incorrecto, responda a este correo o llame al {{utility.phone}} y lo revisaremos de nuevo.\n\n{{utility.name}}',
        },
      },
      letter: {
        en: {
          subject: 'Why your {{bill.period}} bill changed',
          body: 'Dear {{customer.name}},\n\nThis letter explains your bill for {{bill.period}}, account {{account.number}}. Your current charges are {{bill.change_amount}} more than {{bill.compare_label}}.\n\n{{bill.main_reason}}\n\nA line-by-line breakdown is enclosed. If you have questions, call {{utility.phone}}, Monday through Friday, 8 a.m. to 5 p.m.\n\nSincerely,\nCustomer Service\n{{utility.name}}',
        },
      },
    },
  },
  {
    id: 'estimated-read',
    name: 'We estimated your reading',
    category: 'Billing',
    purpose: 'Explains an estimated read and asks for access to the meter.',
    trigger: 'A bill is issued on an estimated read',
    channels: ['email', 'letter'],
    kind: 'transactional',
    updatedAt: '2025-11-20T14:22:00-06:00',
    updatedBy: 'Renee Alvarado',
    content: {
      email: {
        en: {
          subject: 'Your {{bill.period}} reading was estimated',
          body: 'Hi {{customer.first_name}},\n\nWe could not reach your meter this month, so your {{bill.period}} bill uses an estimated reading. Your next actual reading will true up the difference automatically — you will never pay twice for the same gas.\n\nIf a gate, dog or lock keeps us out, call {{utility.phone}} and we will set up access that works for you.\n\n{{utility.name}}',
        },
      },
      letter: {
        en: {
          subject: 'Access to your gas meter',
          body: 'Dear {{customer.name}},\n\nWe have not been able to read the gas meter at {{service.address}}. Texas rules limit how many bills in a row may be estimated, so we need an actual reading soon.\n\nPlease call {{utility.phone}} to arrange access. A reading takes a few minutes and does not interrupt your service.\n\nSincerely,\nMeter Services\n{{utility.name}}',
        },
      },
    },
  },
  {
    id: 'corrected-bill',
    name: 'Corrected bill',
    category: 'Billing',
    purpose: 'Sent with a rebill after a bill is voided and corrected.',
    trigger: 'A correction run issues a rebill',
    channels: ['email', 'letter'],
    kind: 'transactional',
    updatedAt: '2026-01-29T11:05:00-06:00',
    updatedBy: by,
    content: {
      email: {
        en: {
          subject: 'A corrected bill for {{bill.period}}',
          body: 'Hi {{customer.first_name}},\n\nWe found an error on your {{bill.period}} bill and have replaced it with a corrected one, {{bill.number}}. The original is cancelled — you do not need to pay it.\n\nThe corrected amount due is {{bill.amount_due}}, due {{bill.due_date}}. Any payment you already made has been applied.\n\nWe are sorry for the trouble. Questions? Call {{utility.phone}}.\n\n{{utility.name}}',
        },
      },
      letter: {
        en: {
          subject: 'Corrected statement',
          body: 'Dear {{customer.name}},\n\nEnclosed is a corrected statement, {{bill.number}}, which replaces your earlier bill for {{bill.period}}. The earlier bill is cancelled.\n\nAmount due: {{bill.amount_due}}, by {{bill.due_date}}. Payments already received have been applied.\n\nSincerely,\nBilling Office\n{{utility.name}}',
        },
      },
    },
  },

  /* ---- Payments ------------------------------------------------------ */
  {
    id: 'payment-received',
    name: 'Payment received',
    category: 'Payments',
    purpose: 'Confirms a payment posted to the account.',
    trigger: 'A payment posts',
    channels: ['email', 'sms'],
    kind: 'transactional',
    updatedAt: '2025-12-02T08:40:00-06:00',
    updatedBy: by,
    content: {
      email: {
        en: {
          subject: 'We received your payment of {{payment.amount}}',
          body: 'Hi {{customer.first_name}},\n\nThank you — we received your payment of {{payment.amount}} on {{payment.date}}. Your remaining balance is {{account.balance}}.\n\n{{utility.name}}',
        },
        es: {
          subject: 'Recibimos su pago de {{payment.amount}}',
          body: 'Hola {{customer.first_name}}:\n\nGracias — recibimos su pago de {{payment.amount}} el {{payment.date}}. Su saldo restante es {{account.balance}}.\n\n{{utility.name}}',
        },
      },
      sms: {
        en: { body: '{{utility.name}}: payment of {{payment.amount}} received {{payment.date}}. Balance now {{account.balance}}. Thank you!' },
        es: { body: '{{utility.name}}: recibimos su pago de {{payment.amount}} el {{payment.date}}. Saldo: {{account.balance}}. ¡Gracias!' },
      },
    },
  },
  {
    id: 'autopay-enrolled',
    name: 'AutoPay confirmation',
    category: 'Payments',
    purpose: 'Confirms enrollment in AutoPay and when the first draft happens.',
    trigger: 'A customer enrolls in AutoPay',
    channels: ['email'],
    kind: 'transactional',
    updatedAt: '2025-10-14T13:00:00-05:00',
    updatedBy: 'Renee Alvarado',
    content: {
      email: {
        en: {
          subject: 'You are enrolled in AutoPay',
          body: 'Hi {{customer.first_name}},\n\nYou are set up for AutoPay. Each bill will be paid automatically on its due date from the account you chose. We will still email you when each bill is ready, so you always know the amount before it is drafted.\n\nTo change or cancel AutoPay, visit {{utility.portal_url}} at least three days before a due date.\n\n{{utility.name}}',
        },
      },
    },
  },
  {
    id: 'returned-payment',
    name: 'Returned payment',
    category: 'Payments',
    purpose: 'Tells the customer a payment was returned by their bank.',
    trigger: 'A payment is returned NSF',
    channels: ['email', 'letter'],
    kind: 'transactional',
    updatedAt: '2025-09-30T15:10:00-05:00',
    updatedBy: by,
    content: {
      email: {
        en: {
          subject: 'Your payment of {{payment.amount}} was returned',
          body: 'Hi {{customer.first_name}},\n\nYour bank returned your payment of {{payment.amount}} from {{payment.date}}, so it has been reversed and your balance is {{account.balance}}. A returned-payment fee may apply under our tariff.\n\nPlease pay by another method at {{utility.portal_url}} or call {{utility.phone}}.\n\n{{utility.name}}',
        },
      },
      letter: {
        en: {
          subject: 'Returned payment',
          body: 'Dear {{customer.name}},\n\nYour payment of {{payment.amount}} dated {{payment.date}} was returned unpaid by your bank. The amount has been added back to account {{account.number}}, which now has a balance of {{account.balance}}.\n\nPlease make a replacement payment by cash, money order or card. Call {{utility.phone}} with any questions.\n\nSincerely,\nBilling Office\n{{utility.name}}',
        },
      },
    },
  },
  {
    id: 'payment-arrangement',
    name: 'Payment arrangement confirmation',
    category: 'Payments',
    purpose: 'Puts the terms of a payment arrangement in writing.',
    trigger: 'A CSR sets up a payment arrangement',
    channels: ['email', 'letter'],
    kind: 'transactional',
    updatedAt: '2026-01-21T10:30:00-06:00',
    updatedBy: 'Tom Hadley',
    content: {
      email: {
        en: {
          subject: 'Your payment arrangement',
          body: 'Hi {{customer.first_name}},\n\nHere are the terms we agreed: {{arrangement.installments}} installments of {{arrangement.amount}}, starting {{arrangement.first_date}}, on top of each new bill. As long as installments arrive on time, collection activity on this balance stays paused.\n\nIf something changes, call {{utility.phone}} before a payment is missed — we can usually adjust.\n\n{{utility.name}}',
        },
        es: {
          subject: 'Su acuerdo de pago',
          body: 'Hola {{customer.first_name}}:\n\nEstos son los términos acordados: {{arrangement.installments}} pagos de {{arrangement.amount}}, a partir del {{arrangement.first_date}}, además de cada factura nueva. Mientras los pagos lleguen a tiempo, la cobranza de este saldo queda en pausa.\n\nSi algo cambia, llame al {{utility.phone}} antes de atrasarse — normalmente podemos ajustarlo.\n\n{{utility.name}}',
        },
      },
      letter: {
        en: {
          subject: 'Payment arrangement',
          body: 'Dear {{customer.name}},\n\nThis confirms a payment arrangement on account {{account.number}}: {{arrangement.installments}} installments of {{arrangement.amount}} beginning {{arrangement.first_date}}, in addition to current bills.\n\nSincerely,\nCustomer Service\n{{utility.name}}',
        },
      },
    },
  },
  {
    id: 'budget-billing-offer',
    name: 'Budget billing offer',
    category: 'Payments',
    purpose: 'Offers level monthly payments, with the customer’s own estimate.',
    trigger: 'Offered from outreach or a bill explanation',
    channels: ['email', 'letter'],
    kind: 'courtesy',
    updatedAt: '2025-10-01T09:00:00-05:00',
    updatedBy: by,
    content: {
      email: {
        en: {
          subject: 'Make your gas bill the same every month',
          body: 'Hi {{customer.first_name}},\n\nWinter gas bills can be two or three times summer ones. With budget billing, you pay about {{budget.monthly}} every month instead, based on your last twelve months. Once a year we settle up the difference.\n\nThere is no fee. Sign up at {{utility.portal_url}} or call {{utility.phone}}.\n\n{{utility.name}}',
        },
      },
      letter: {
        en: {
          subject: 'Budget billing',
          body: 'Dear {{customer.name}},\n\nBased on your usage over the last year, budget billing would set your monthly payment at about {{budget.monthly}}. There is no cost to enroll, and you may leave at any time.\n\nSincerely,\nCustomer Service\n{{utility.name}}',
        },
      },
    },
  },

  /* ---- Collections --------------------------------------------------- */
  {
    id: 'past-due-reminder',
    name: 'Past-due reminder',
    category: 'Collections',
    purpose: 'The first, friendly dunning step.',
    trigger: 'Dunning step 1 — the reminder',
    channels: ['email', 'sms', 'letter'],
    kind: 'transactional',
    usedBy: { href: '/settings/dunning', label: 'Automatic dunning' },
    updatedAt: '2026-01-06T09:20:00-06:00',
    updatedBy: by,
    content: {
      email: {
        en: {
          subject: 'Reminder: {{balance.past_due}} is past due',
          body: 'Hi {{customer.first_name}},\n\nOur records show {{balance.past_due}} past due on account {{account.number}}. If you have already paid, thank you — please disregard this.\n\nPay at {{utility.portal_url}}. If you need more time, call {{utility.phone}}; we offer payment arrangements and can refer you to energy assistance.\n\n{{utility.name}}',
        },
        es: {
          subject: 'Recordatorio: {{balance.past_due}} está vencido',
          body: 'Hola {{customer.first_name}}:\n\nNuestros registros muestran {{balance.past_due}} vencido en la cuenta {{account.number}}. Si ya pagó, gracias — ignore este mensaje.\n\nPague en {{utility.portal_url}}. Si necesita más tiempo, llame al {{utility.phone}}; ofrecemos acuerdos de pago y podemos referirle a asistencia de energía.\n\n{{utility.name}}',
        },
      },
      sms: {
        en: { body: '{{utility.name}}: {{balance.past_due}} is past due on acct {{account.number}}. Pay: {{utility.portal_url}} or call {{utility.phone}} for options.' },
        es: { body: '{{utility.name}}: {{balance.past_due}} vencido en la cuenta {{account.number}}. Pague: {{utility.portal_url}} o llame al {{utility.phone}}.' },
      },
      letter: {
        en: {
          subject: 'Payment reminder',
          body: 'Dear {{customer.name}},\n\nThis is a reminder that {{balance.past_due}} is past due on account {{account.number}}. Please pay promptly, or call {{utility.phone}} to discuss a payment arrangement.\n\nSincerely,\nBilling Office\n{{utility.name}}',
        },
      },
    },
  },
  {
    id: 'late-fee-notice',
    name: 'Late fee applied',
    category: 'Collections',
    purpose: 'Tells the customer a tariff late fee was added.',
    trigger: 'Dunning step 2 — the late fee',
    channels: ['email'],
    kind: 'transactional',
    usedBy: { href: '/settings/dunning', label: 'Automatic dunning' },
    updatedAt: '2025-11-04T16:00:00-06:00',
    updatedBy: by,
    content: {
      email: {
        en: {
          subject: 'A late fee was added to your account',
          body: 'Hi {{customer.first_name}},\n\nBecause {{balance.past_due}} remained unpaid after the due date, a late fee of {{fee.amount}} was added as our tariff provides. Your balance is now {{account.balance}}.\n\nCall {{utility.phone}} if you would like to set up a payment arrangement.\n\n{{utility.name}}',
        },
      },
    },
  },
  {
    id: 'termination-notice',
    name: 'Termination Notice',
    category: 'Collections',
    purpose: 'The written notice that must precede any disconnection for non-payment.',
    trigger: 'Dunning step 3 — mailed or hand-delivered, even to paperless customers',
    channels: ['letter'],
    kind: 'regulatory',
    required: [TERMINATION_RIGHTS],
    usedBy: { href: '/settings/dunning', label: 'Automatic dunning' },
    updatedAt: '2025-08-19T10:00:00-05:00',
    updatedBy: 'Gail Whitfield',
    content: {
      letter: {
        en: {
          subject: 'Termination Notice',
          body: 'Dear {{customer.name}},\n\nYour gas service at {{service.address}} is scheduled for disconnection on or after {{notice.disconnect_date}} because {{balance.past_due}} is past due on account {{account.number}}.\n\nTo keep your service on, pay {{balance.past_due}} by {{notice.pay_by}} or call {{utility.phone}} before that date.\n\n{{required.termination_rights}}\n\n{{utility.name}}',
        },
        es: {
          subject: 'Aviso de Terminación',
          body: 'Estimado(a) {{customer.name}}:\n\nSu servicio de gas en {{service.address}} está programado para desconexión a partir del {{notice.disconnect_date}} porque tiene {{balance.past_due}} vencido en la cuenta {{account.number}}.\n\nPara mantener su servicio, pague {{balance.past_due}} antes del {{notice.pay_by}} o llame al {{utility.phone}} antes de esa fecha.\n\n{{required.termination_rights}}\n\n{{utility.name}}',
        },
      },
    },
  },
  {
    id: 'disconnect-scheduled',
    name: 'Disconnection scheduled',
    category: 'Collections',
    purpose: 'Last-chance message the working day before a scheduled disconnect.',
    trigger: 'Dunning step 4 — a disconnect order is scheduled',
    channels: ['sms', 'email'],
    kind: 'transactional',
    usedBy: { href: '/collections', label: 'Collections & disconnect' },
    updatedAt: '2026-01-06T09:24:00-06:00',
    updatedBy: by,
    content: {
      sms: {
        en: { body: '{{utility.name}}: gas service at {{service.address}} is scheduled for disconnection {{notice.disconnect_date}}. Pay {{balance.past_due}} or call {{utility.phone}} today.' },
        es: { body: '{{utility.name}}: el servicio de gas en {{service.address}} se desconectará el {{notice.disconnect_date}}. Pague {{balance.past_due}} o llame al {{utility.phone}} hoy.' },
      },
      email: {
        en: {
          subject: 'Action needed: disconnection scheduled for {{notice.disconnect_date}}',
          body: 'Hi {{customer.first_name}},\n\nYour gas service is scheduled for disconnection on {{notice.disconnect_date}} for a past-due balance of {{balance.past_due}}. A payment or a payment arrangement today will stop it.\n\nPay at {{utility.portal_url}} or call {{utility.phone}}.\n\n{{utility.name}}',
        },
      },
    },
  },
  {
    id: 'reconnect-relight',
    name: 'Reconnection and relight appointment',
    category: 'Collections',
    purpose: 'Confirms the window for restoring service and relighting appliances.',
    trigger: 'A reconnect order is scheduled',
    channels: ['sms', 'email'],
    kind: 'transactional',
    usedBy: { href: '/collections', label: 'Reconnect & relight queue' },
    updatedAt: '2025-12-15T12:00:00-06:00',
    updatedBy: 'Tom Hadley',
    content: {
      sms: {
        en: { body: '{{utility.name}}: a technician will restore your gas and relight appliances {{appointment.date}}, {{appointment.window}}. An adult must be home to let us in.' },
      },
      email: {
        en: {
          subject: 'Your service is being restored {{appointment.date}}',
          body: 'Hi {{customer.first_name}},\n\nA technician will restore your gas service and relight your pilot lights on {{appointment.date}} between {{appointment.window}}. Gas cannot be turned on without someone 18 or older at home, because we check every appliance before we leave.\n\n{{utility.name}}',
        },
      },
    },
  },

  /* ---- Service ------------------------------------------------------- */
  {
    id: 'welcome-start-service',
    name: 'Welcome — service started',
    category: 'Service',
    purpose: 'First message to a new customer: account, billing dates, how to pay.',
    trigger: 'A start-service order completes',
    channels: ['email'],
    kind: 'transactional',
    updatedAt: '2025-09-02T09:00:00-05:00',
    updatedBy: 'Renee Alvarado',
    content: {
      email: {
        en: {
          subject: 'Welcome to {{utility.name}}',
          body: 'Hi {{customer.first_name}},\n\nWelcome! Gas service at {{service.address}} is on, and your account number is {{account.number}}. Your first bill will arrive after your next meter reading.\n\nSet up paperless billing and AutoPay at {{utility.portal_url}}. Keep {{utility.emergency_phone}} handy — it is our 24-hour gas emergency line.\n\n{{utility.name}}',
        },
      },
    },
  },
  {
    id: 'final-bill',
    name: 'Final bill — service stopped',
    category: 'Service',
    purpose: 'Closes the account with the final bill and any deposit applied.',
    trigger: 'A stop-service order completes',
    channels: ['email', 'letter'],
    kind: 'transactional',
    updatedAt: '2025-09-02T09:10:00-05:00',
    updatedBy: 'Renee Alvarado',
    content: {
      email: {
        en: {
          subject: 'Your final bill from {{utility.name}}',
          body: 'Hi {{customer.first_name}},\n\nService at {{service.address}} has been stopped. Your final bill is {{bill.amount_due}}, due {{bill.due_date}}, after applying your deposit of {{deposit.amount}}.\n\nThank you for being our customer.\n\n{{utility.name}}',
        },
      },
      letter: {
        en: {
          subject: 'Final statement',
          body: 'Dear {{customer.name}},\n\nEnclosed is your final statement for {{service.address}}. Your deposit of {{deposit.amount}} has been applied. Amount due: {{bill.amount_due}}, by {{bill.due_date}}.\n\nSincerely,\nBilling Office\n{{utility.name}}',
        },
      },
    },
  },
  {
    id: 'deposit-request',
    name: 'Deposit request',
    category: 'Service',
    purpose: 'Asks a new or returning customer for a security deposit.',
    trigger: 'Credit check at start of service',
    channels: ['letter', 'email'],
    kind: 'transactional',
    updatedAt: '2025-08-12T14:00:00-05:00',
    updatedBy: 'Gail Whitfield',
    content: {
      letter: {
        en: {
          subject: 'Security deposit',
          body: 'Dear {{customer.name}},\n\nA security deposit of {{deposit.amount}} is required for service at {{service.address}}. The deposit earns interest and is refunded after twelve months of on-time payments, or applied to your final bill.\n\nYou may pay it in installments; call {{utility.phone}}.\n\nSincerely,\nCustomer Service\n{{utility.name}}',
        },
      },
      email: {
        en: {
          subject: 'A deposit is due for your new service',
          body: 'Hi {{customer.first_name}},\n\nA deposit of {{deposit.amount}} is due for service at {{service.address}}. It earns interest and comes back to you after twelve months of on-time payments. Pay at {{utility.portal_url}}, or call {{utility.phone}} to pay in installments.\n\n{{utility.name}}',
        },
      },
    },
  },
  {
    id: 'deposit-refund',
    name: 'Deposit refunded',
    category: 'Service',
    purpose: 'Tells the customer their deposit and interest were refunded.',
    trigger: 'Twelve months of on-time payment reached',
    channels: ['email'],
    kind: 'transactional',
    updatedAt: '2025-08-12T14:05:00-05:00',
    updatedBy: 'Gail Whitfield',
    content: {
      email: {
        en: {
          subject: 'Your deposit is coming back',
          body: 'Hi {{customer.first_name}},\n\nThanks to a year of on-time payments, we have refunded your deposit of {{deposit.amount}} plus interest as a credit on your account. It will reduce your next bill.\n\n{{utility.name}}',
        },
      },
    },
  },
  {
    id: 'service-appointment',
    name: 'Service appointment',
    category: 'Service',
    purpose: 'Confirms a field visit window, with a reminder the day before.',
    trigger: 'A service order is scheduled',
    channels: ['sms', 'email'],
    kind: 'transactional',
    updatedAt: '2025-12-15T12:10:00-06:00',
    updatedBy: 'Tom Hadley',
    content: {
      sms: {
        en: { body: '{{utility.name}}: your service visit is {{appointment.date}}, {{appointment.window}} (order {{service_order.number}}). Reply C to confirm or call {{utility.phone}} to reschedule.' },
        es: { body: '{{utility.name}}: su visita de servicio es el {{appointment.date}}, {{appointment.window}} (orden {{service_order.number}}). Responda C para confirmar o llame al {{utility.phone}}.' },
      },
      email: {
        en: {
          subject: 'Your service visit on {{appointment.date}}',
          body: 'Hi {{customer.first_name}},\n\nA technician will visit {{service.address}} on {{appointment.date}} between {{appointment.window}}. Every technician carries a photo ID — ask to see it.\n\nTo reschedule, call {{utility.phone}}.\n\n{{utility.name}}',
        },
      },
    },
  },
  {
    id: 'meter-exchange',
    name: 'Meter exchange notice',
    category: 'Service',
    purpose: 'Notice of a scheduled meter change-out and a short interruption.',
    trigger: 'A meter is selected for testing or replacement',
    channels: ['letter', 'sms'],
    kind: 'transactional',
    updatedAt: '2025-07-22T10:00:00-05:00',
    updatedBy: 'Gail Whitfield',
    content: {
      letter: {
        en: {
          subject: 'We are replacing your gas meter',
          body: 'Dear {{customer.name}},\n\nAs part of our meter testing program, we will replace the gas meter at {{service.address}} during the week of {{appointment.date}}. Service will be off for about 30 minutes. If we need to relight appliances, we will knock first; if no one is home, we will leave a door tag.\n\nSincerely,\nMeter Services\n{{utility.name}}',
        },
      },
      sms: {
        en: { body: '{{utility.name}}: we are replacing your gas meter the week of {{appointment.date}}. Service will be off about 30 min. Questions: {{utility.phone}}' },
      },
    },
  },

  /* ---- Safety -------------------------------------------------------- */
  {
    id: 'gas-safety',
    name: 'Gas safety — if you smell gas',
    category: 'Safety',
    purpose: 'The annual public-awareness message every customer receives.',
    trigger: 'Annual, and with every welcome message',
    channels: ['letter', 'email', 'sms'],
    kind: 'regulatory',
    required: [LEAK_STEPS],
    updatedAt: '2025-06-01T09:00:00-05:00',
    updatedBy: 'Gail Whitfield',
    content: {
      letter: {
        en: {
          subject: 'Natural gas safety',
          body: 'Dear {{customer.name}},\n\nNatural gas is one of the safest ways to heat your home, and we work every day to keep it that way. Please take a minute to read how to recognize and report a leak.\n\n{{required.leak_steps}}\n\nCall 811 before you dig — it is free, and it keeps you and your neighbors safe.\n\n{{utility.name}}',
        },
        es: {
          subject: 'Seguridad del gas natural',
          body: 'Estimado(a) {{customer.name}}:\n\nEl gas natural es una de las formas más seguras de calentar su hogar, y trabajamos todos los días para mantenerlo así. Tómese un minuto para leer cómo reconocer y reportar una fuga.\n\n{{required.leak_steps}}\n\nLlame al 811 antes de excavar — es gratis y protege a usted y a sus vecinos.\n\n{{utility.name}}',
        },
      },
      email: {
        en: {
          subject: 'Know what to do if you smell gas',
          body: 'Hi {{customer.first_name}},\n\nA quick safety reminder from {{utility.name}}.\n\n{{required.leak_steps}}\n\nCall 811 before you dig.\n\n{{utility.name}}',
        },
        es: {
          subject: 'Sepa qué hacer si huele a gas',
          body: 'Hola {{customer.first_name}}:\n\nUn recordatorio de seguridad de {{utility.name}}.\n\n{{required.leak_steps}}\n\nLlame al 811 antes de excavar.\n\n{{utility.name}}',
        },
      },
      sms: {
        en: { body: '{{utility.name}}: smell gas? Leave now, then call {{utility.emergency_phone}} or 911 from outside. No sparks, no switches.' },
        es: { body: '{{utility.name}}: ¿huele a gas? Salga ya y llame al {{utility.emergency_phone}} o al 911 desde afuera. Sin chispas ni interruptores.' },
      },
    },
  },
  {
    id: 'planned-outage',
    name: 'Planned service interruption',
    category: 'Safety',
    purpose: 'Advance notice of pipeline work that interrupts service.',
    trigger: 'A planned main or service-line job is scheduled',
    channels: ['sms', 'email', 'letter'],
    kind: 'transactional',
    updatedAt: '2025-10-09T09:00:00-05:00',
    updatedBy: 'Gail Whitfield',
    content: {
      sms: {
        en: { body: '{{utility.name}}: planned gas work on your street {{appointment.date}}, {{appointment.window}}. Service will be off; we will relight appliances after.' },
      },
      email: {
        en: {
          subject: 'Planned gas work on {{appointment.date}}',
          body: 'Hi {{customer.first_name}},\n\nWe will be upgrading the gas line near {{service.address}} on {{appointment.date}} between {{appointment.window}}. Your service will be interrupted, and a technician will relight your appliances when it is restored. If no one is home, we will leave a door tag with a number to call.\n\n{{utility.name}}',
        },
      },
      letter: {
        en: {
          subject: 'Planned service interruption',
          body: 'Dear {{customer.name}},\n\nGas service at {{service.address}} will be interrupted on {{appointment.date}}, {{appointment.window}}, for pipeline improvements. We will relight appliances when service is restored.\n\nSincerely,\nOperations\n{{utility.name}}',
        },
      },
    },
  },

  /* ---- Regulatory ---------------------------------------------------- */
  {
    id: 'rate-change-notice',
    name: 'Notice of proposed rate change',
    category: 'Regulatory',
    purpose: 'The public notice of a statement of intent, with the typical-bill effect.',
    trigger: 'Generated from the rate case toolkit',
    channels: ['letter', 'email'],
    kind: 'regulatory',
    required: [RATE_NOTICE],
    usedBy: { href: '/rates/rate-case', label: 'Rate case toolkit' },
    updatedAt: '2026-01-09T08:00:00-06:00',
    updatedBy: 'Gail Whitfield',
    content: {
      letter: {
        en: {
          subject: 'Notice of proposed change in gas rates',
          body: 'Dear {{customer.name}},\n\n{{utility.name}} has filed to change its gas rates effective {{rate.effective_date}}. For a typical residential customer, the change is about {{rate.typical_change}} a month. Gas cost, which we pass through at no markup, is not affected.\n\nThe new rates fund pipeline replacement and the cost of operating a safe system.\n\n{{required.rate_notice}}\n\n{{utility.name}}',
        },
        es: {
          subject: 'Aviso de cambio propuesto en las tarifas de gas',
          body: 'Estimado(a) {{customer.name}}:\n\n{{utility.name}} ha presentado una solicitud para cambiar sus tarifas de gas a partir del {{rate.effective_date}}. Para un cliente residencial típico, el cambio es de aproximadamente {{rate.typical_change}} al mes. El costo del gas, que trasladamos sin ganancia, no cambia.\n\nLas nuevas tarifas financian el reemplazo de tuberías y el costo de operar un sistema seguro.\n\n{{required.rate_notice}}\n\n{{utility.name}}',
        },
      },
      email: {
        en: {
          subject: 'Proposed gas rate change effective {{rate.effective_date}}',
          body: 'Hi {{customer.first_name}},\n\nWe have filed to change our gas rates effective {{rate.effective_date}}. For a typical home, that is about {{rate.typical_change}} a month.\n\n{{required.rate_notice}}\n\n{{utility.name}}',
        },
      },
    },
  },
  {
    id: 'pga-change',
    name: 'Gas cost change',
    category: 'Regulatory',
    purpose: 'Explains a monthly PGA movement to customers who opt in.',
    trigger: 'A new PGA factor is filed',
    channels: ['email'],
    kind: 'courtesy',
    usedBy: { href: '/rates/pga', label: 'PGA console' },
    updatedAt: '2026-02-02T08:30:00-06:00',
    updatedBy: by,
    content: {
      email: {
        en: {
          subject: 'This month’s natural gas cost',
          body: 'Hi {{customer.first_name}},\n\nThe cost of natural gas on your bill — the purchased gas adjustment — is {{pga.rate}} a therm this month. We pass it through exactly as we pay it, with no markup, and it moves with the wholesale market.\n\n{{utility.name}}',
        },
      },
    },
  },
  {
    id: 'cold-weather-protections',
    name: 'Cold-weather protections',
    category: 'Regulatory',
    purpose: 'The annual notice of winter disconnection protections and assistance.',
    trigger: 'Each November, to every residential customer',
    channels: ['letter'],
    kind: 'regulatory',
    updatedAt: '2025-10-28T09:00:00-05:00',
    updatedBy: 'Gail Whitfield',
    content: {
      letter: {
        en: {
          subject: 'Your protections this winter',
          body: 'Dear {{customer.name}},\n\nWe will not disconnect residential gas service for non-payment when the temperature is forecast to be at or below freezing. If someone in your home is seriously ill, a physician’s statement can delay disconnection while you set up a payment agreement.\n\nEnergy assistance is available through local agencies. Call {{utility.phone}} and we will help you apply.\n\n{{utility.name}}',
        },
      },
    },
  },
]

export const templateById = new Map(templates.map((t) => [t.id, t]))
