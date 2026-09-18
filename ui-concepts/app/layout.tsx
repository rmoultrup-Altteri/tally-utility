import type { Metadata } from 'next'
import { Inter, Source_Serif_4, IBM_Plex_Mono } from 'next/font/google'
import { THEME_BOOTSTRAP } from '@/components/shell/ThemeControl'
import './globals.css'

/* The instrument. */
const grotesque = Inter({
  variable: '--font-grotesque',
  subsets: ['latin'],
  display: 'swap',
})

/* The artifact: bills, notices, anything a regulator might read. */
const record = Source_Serif_4({
  variable: '--font-record',
  subsets: ['latin'],
  display: 'swap',
})

/* Identifiers only — account numbers, meter serials, dial readings. */
const numeric = IBM_Plex_Mono({
  variable: '--font-numeric',
  weight: ['400', '500', '600'],
  subsets: ['latin'],
  display: 'swap',
})

export const metadata: Metadata = {
  title: 'TallyUtility',
  description: 'Meter-to-cash for natural gas distribution',
}

export default function RootLayout({ children }: LayoutProps<'/'>) {
  return (
    <html
      lang="en"
      className={`${grotesque.variable} ${record.variable} ${numeric.variable}`}
      /* The bootstrap script below stamps `data-theme` before React hydrates,
         so the server markup and the live DOM differ on this element by
         design. Scoped to <html> only — nothing inside it is exempted. */
      suppressHydrationWarning
    >
      <head>
        {/* Before first paint, so a pinned theme never flashes the other one. */}
        <script dangerouslySetInnerHTML={{ __html: THEME_BOOTSTRAP }} />
      </head>
      <body>{children}</body>
    </html>
  )
}
