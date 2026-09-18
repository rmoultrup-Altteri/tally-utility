import { chromium } from 'playwright'
const pages = [
  ['dashboard', '/dashboard'],
  ['queue', '/'],
  ['reads', '/reads'],
  ['run', '/runs/run-2026-02-04'],
  ['dryrun', '/runs/run-2026-02-sbx'],
  ['bill', '/invoices/inv-0001'],
  ['void', '/invoices/inv-0003'],
  ['rebill', '/invoices/inv-0003/rebill'],
  ['diff', '/invoices/inv-0004/diff'],
  ['collections', '/collections'],
  ['rates', '/rates'],
  ['pga', '/rates/pga'],
  ['customer', '/customers/cus-0001'],
]
const BASE = process.env.BASE_URL ?? 'http://localhost:4182'

const b = await chromium.launch()
const p = await b.newPage({ viewport: { width: 1440, height: 950 } })
const errs = []
p.on('console', (m) => { if (m.type() === 'error') errs.push(m.text()) })
p.on('pageerror', (e) => errs.push(String(e)))
for (const [name, path] of pages) {
  await p.goto(BASE + path, { waitUntil: 'networkidle' })
  await p.screenshot({ path: `/tmp/tu-shots/${name}.png`, fullPage: true })
  console.log('shot', name)
}
await b.close()
console.log(errs.length ? 'CONSOLE ERRORS:\n' + errs.join('\n') : 'no console errors')
