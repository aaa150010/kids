import { cp, mkdir, readdir, readFile, rm } from 'node:fs/promises'
import { resolve } from 'node:path'

const root = resolve(import.meta.dirname, '../..')
const source = resolve(root, 'content-src')
const target = resolve(root, 'apps/android')

await mkdir(resolve(target, 'content'), { recursive: true })
for (const file of await readdir(resolve(source, 'data'))) {
  if (file.endsWith('.json')) await cp(resolve(source, 'data', file), resolve(target, 'content', file))
}
let excluded = new Set()
try {
  const report = JSON.parse(await readFile(resolve(source, 'licenses/asset-optimization.json'), 'utf8'))
  excluded = new Set(report.excludedAssets.map(path => resolve(source, 'assets', path)))
} catch (error) {
  if (error.code !== 'ENOENT') throw error
}
await rm(resolve(target, 'assets'), { recursive: true, force: true })
await cp(resolve(source, 'assets'), resolve(target, 'assets'), {
  recursive: true,
  filter: path => !excluded.has(path) && !excluded.has(path.replace(/\.import$/, '')),
})
await cp(resolve(source, 'licenses'), resolve(target, 'assets/licenses'), { recursive: true })
console.log('已从独立内容源生成安卓题库与资源。')
