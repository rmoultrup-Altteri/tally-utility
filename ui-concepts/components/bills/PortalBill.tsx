'use client'

import { useState } from 'react'
import { tenant } from '@/fixtures/tenant'
import { TenantLogo } from '@/components/shell/TenantLogo'
import { Waterfall } from '@/components/charts/Waterfall'
import { UsageWeather } from '@/components/charts/UsageWeather'
import { bridgeSteps } from '@/components/bills/ExplainView'
import { explanationCopy, formatCents, formatSigned, monthName, type Explanation, type Lang } from '@/lib/bill-explain'
import { longDate } from '@/lib/templates'

/**
 * The customer's bill page in the self-service portal.
 *
 * The same explanation the CSR reads, in the customer's language, on a phone.
 * The point of it is the call that never happens: a customer who opens the
 * bill, sees "it was 39% colder" next to their own usage tracking the cold,
 * and closes the app. Help is offered before they ask for it — budget billing,
 * an arrangement, assistance — and the gas emergency line is always on screen.
 */
export function PortalBill({
  e,
  firstName,
  amountDue,
  dueDate,
  previousBalance,
  points,
  budgetCents,
  invoiceNumber,
}: {
  e: Explanation | null
  firstName: string
  amountDue: string
  dueDate: string
  previousBalance: string
  points: { label: string; therms: number; hdd: number; estimated: boolean }[]
  budgetCents: number
  invoiceNumber: string
}) {
  const [lang, setLang] = useState<Lang>('en')
  const es = lang === 'es'
  const copy = e ? explanationCopy(e, lang) : null
  const prev = Number(previousBalance)
  const t = (en: string, sp: string) => (es ? sp : en)
  const usd = (v: string | number) => formatCents(Math.round(Number(v) * 100))

  return (
    <div className="mx-auto w-full max-w-[420px] space-y-3 pb-10">
      <header className="flex items-center justify-between px-1 pt-2">
        <div className="flex items-center gap-2">
          <TenantLogo name={tenant.name} size={26} />
          <span className="text-h3 text-ink-primary">{tenant.name}</span>
        </div>
        <div role="group" aria-label="Language" className="flex rounded-full border border-rule-solid bg-surface-raised p-0.5 text-micro">
          {(['en', 'es'] as Lang[]).map((l) => (
            <button
              key={l}
              type="button"
              aria-pressed={lang === l}
              onClick={() => setLang(l)}
              className={`rounded-full px-2.5 py-0.5 ${lang === l ? 'bg-surface-ink text-ink-inverse' : 'text-ink-secondary'}`}
            >
              {l === 'en' ? 'English' : 'Español'}
            </button>
          ))}
        </div>
      </header>

      <section className="rounded-lg border border-rule-hair bg-surface-raised px-5 py-5 shadow-panel">
        <p className="text-data text-ink-secondary">{t(`Hi ${firstName},`, `Hola ${firstName}:`)}</p>
        <p className="mt-3 field-label">{t('Amount due', 'Monto a pagar')}</p>
        <p className="text-[34px] leading-[40px] font-semibold text-ink-primary figures text-left">{usd(amountDue)}</p>
        <p className="text-data text-ink-secondary">
          {t('Due', 'Vence el')} {longDate(dueDate, lang)} · <span className="ident">{invoiceNumber}</span>
        </p>
        {prev > 0 ? (
          <p className="mt-2 text-micro text-ink-tertiary">
            {t(
              `Includes ${usd(prev)} from your last bill that is still unpaid.`,
              `Incluye ${usd(prev)} de su factura anterior que sigue pendiente.`,
            )}
          </p>
        ) : null}
        <button
          type="button"
          disabled
          title="Payments are not taken in the preview"
          className="mt-4 h-11 w-full rounded-md bg-accent text-body font-medium text-ink-inverse disabled:opacity-90"
        >
          {t('Pay now', 'Pagar ahora')}
        </button>
      </section>

      {e && copy ? (
        <section className="rounded-lg border border-rule-hair bg-surface-raised px-5 py-5 shadow-panel">
          <p className="field-label">{t('Why this bill is different', 'Por qué esta factura es diferente')}</p>
          <h1 className="mt-1 text-h2 text-ink-primary">{copy.headline}</h1>
          <p className="mt-1.5 text-data text-ink-secondary leading-relaxed">{copy.summary}</p>
          <div className="mt-4">
            <Waterfall
              compact
              start={{ label: cap(monthName(e.prior.billing_period, lang)) + ' ' + e.prior.billing_period.split(' ')[1], cents: e.priorCents }}
              steps={bridgeSteps(e, lang)}
              end={{ label: cap(monthName(e.period, lang)) + ' ' + e.period.split(' ')[1], cents: e.currentCents }}
            />
          </div>
          <ul className="mt-4 space-y-3">
            {copy.drivers.slice(0, 4).map((d) => (
              <li key={d.key} className="flex gap-3">
                <span className={`w-16 shrink-0 figures text-data font-medium ${d.cents > 0 ? 'text-exception-warning-text' : 'text-money-credit'}`}>
                  {formatSigned(d.cents)}
                </span>
                <div>
                  <p className="text-data font-medium text-ink-primary">{d.title}</p>
                  <p className="text-micro text-ink-secondary leading-relaxed mt-0.5">{d.body}</p>
                </div>
              </li>
            ))}
          </ul>
        </section>
      ) : null}

      <section className="rounded-lg border border-rule-hair bg-surface-raised px-5 py-5 shadow-panel">
        <p className="field-label mb-2">{t('Your gas use and the weather', 'Su consumo de gas y el clima')}</p>
        <UsageWeather
          height={110}
          points={points.map((p) => ({
            ...p,
            label: `${monthName(p.label, lang).slice(0, 3)} ${p.label.split(' ')[1]}`,
            mark: e && p.label === e.period ? 'current' : e && p.label === e.prior.billing_period ? 'compare' : undefined,
          }))}
          labels={{
            therms: t('Therms used', 'Termias usadas'),
            hdd: t('How cold it was', 'Qué tanto frío hizo'),
            current: t('This bill', 'Esta factura'),
            compare: t('Compared with', 'Comparada con'),
          }}
        />
      </section>

      <section className="rounded-lg border border-rule-hair bg-surface-raised shadow-panel divide-y divide-rule-hair">
        <p className="px-5 pt-4 pb-2 field-label">{t('We can help', 'Podemos ayudar')}</p>
        <Help
          title={t('Budget billing', 'Facturación nivelada')}
          body={t(
            `Pay about ${formatCents(budgetCents)} every month instead of more in winter and less in summer.`,
            `Pague unos ${formatCents(budgetCents)} cada mes en lugar de más en invierno y menos en verano.`,
          )}
          action={t('Sign up', 'Inscribirse')}
        />
        <Help
          title={t('Payment arrangement', 'Acuerdo de pago')}
          body={t('Spread this bill over the next few months.', 'Reparta esta factura en los próximos meses.')}
          action={t('Set one up', 'Solicitar')}
        />
        <Help
          title={t('Energy assistance', 'Asistencia de energía')}
          body={t('Local agencies can help pay heating bills. We will help you apply.', 'Agencias locales pueden ayudar a pagar la calefacción. Le ayudamos a solicitar.')}
          action={t('Learn more', 'Más información')}
        />
      </section>

      <section className="rounded-lg border border-exception-critical-rail/40 bg-exception-critical-wash px-5 py-4">
        <p className="text-data font-semibold text-exception-critical-text">{t('Smell gas?', '¿Huele a gas?')}</p>
        <p className="text-micro text-ink-primary mt-0.5">
          {t(
            `Leave right away, then call ${tenant.emergencyPhone} or 911 from outside. 24 hours, no charge.`,
            `Salga de inmediato y llame al ${tenant.emergencyPhone} o al 911 desde afuera. 24 horas, sin costo.`,
          )}
        </p>
      </section>

      <p className="px-1 text-center text-micro text-ink-tertiary">
        {t('Questions?', '¿Preguntas?')} {tenant.phone} · {tenant.portalUrl}
      </p>
    </div>
  )
}

const cap = (s: string) => s.charAt(0).toUpperCase() + s.slice(1)

function Help({ title, body, action }: { title: string; body: string; action: string }) {
  return (
    <div className="flex items-center justify-between gap-4 px-5 py-3">
      <div>
        <p className="text-data font-medium text-ink-primary">{title}</p>
        <p className="text-micro text-ink-secondary mt-0.5">{body}</p>
      </div>
      <span className="shrink-0 rounded-full border border-rule-solid px-3 py-1 text-micro text-accent-text">{action}</span>
    </div>
  )
}
