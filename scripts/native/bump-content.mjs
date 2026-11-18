import { readFile, writeFile } from 'node:fs/promises'
import { resolve } from 'node:path'

const path = resolve(import.meta.dirname, '../../content-src/data/version.json')
const current = JSON.parse(await readFile(path, 'utf8'))
const next = { ...current, version: Number(current.version || 0) + 1 }
await writeFile(path, JSON.stringify(next) + '\n')
console.log(`内容版本已更新为 ${next.version}`)
