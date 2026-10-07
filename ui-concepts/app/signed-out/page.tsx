import Link from 'next/link'
import type { Route } from 'next'
import { currentUser, tenant } from '@/fixtures/tenant'

/**
 * Where Log out lands. There is no session behind the concepts, so this only
 * shows the shape: outside the shell, the tenant named, and one way back in.
 */
export default function SignedOutPage() {
  return (
    <main className="flex min-h-dvh items-center justify-center bg-surface-inset p-4">
      <div className="w-[min(380px,100%)] rounded-lg border border-rule-hair bg-surface-raised p-6 shadow-panel">
        <p className="text-h3 font-semibold tracking-tight text-ink-primary">Tally Utility</p>
        <p className="mt-0.5 text-micro text-ink-tertiary">{tenant.name}</p>
        <h1 className="mt-5 text-h2 text-ink-primary">You are signed out</h1>
        <p className="mt-1 text-data text-ink-secondary">
          {currentUser.name}’s session has ended. Close this tab on a shared machine.
        </p>
        <Link
          href={'/dashboard' as Route}
          className="mt-5 inline-flex h-8 items-center justify-center rounded-sm border border-accent bg-accent px-3.5 text-data font-medium text-ink-inverse hover:bg-accent-hover"
        >
          Sign in again
        </Link>
      </div>
    </main>
  )
}
