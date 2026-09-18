/**
 * Resolves the project's `@/` path alias for scripts run directly on Node.
 *
 * Node strips TypeScript types natively but knows nothing about tsconfig
 * paths, and the fixtures import each other through the alias. Fifteen lines
 * here beats a build-step dependency for a script that only reads data.
 */
import { pathToFileURL } from 'node:url'
import { dirname, resolve as resolvePath } from 'node:path'
import { fileURLToPath } from 'node:url'
import { existsSync } from 'node:fs'

const root = resolvePath(dirname(fileURLToPath(import.meta.url)), '..')

/* TypeScript imports are extensionless; Node's resolver is not. */
const EXTENSIONS = ['', '.ts', '.tsx', '/index.ts']

export function resolve(specifier, context, next) {
  if (!specifier.startsWith('@/')) return next(specifier, context)
  const base = resolvePath(root, specifier.slice(2))
  for (const ext of EXTENSIONS) {
    if (existsSync(base + ext)) return next(pathToFileURL(base + ext).href, context)
  }
  return next(pathToFileURL(base).href, context)
}
