import { readFile, writeFile } from 'node:fs/promises'
import { resolve } from 'node:path'

const path = resolve(import.meta.dirname, '../../apps/android/version.json')
const projectPath = resolve(import.meta.dirname, '../../apps/android/project.godot')
const current = JSON.parse(await readFile(path, 'utf8'))
const requested = process.argv[2]
const next = {
  versionCode: Number(current.versionCode) + 1,
  versionName: requested || (() => {
    const parts = String(current.versionName).split('.').map(Number)
    while (parts.length < 3) parts.push(0)
    parts[2] += 1
    return parts.join('.')
  })(),
}
await writeFile(path, JSON.stringify(next, null, 2) + '\n')
const project = await readFile(projectPath, 'utf8')
await writeFile(projectPath, project.replace(/config\/version=\"[^\"]+\"/, `config/version=\"${next.versionName}\"`))
console.log(`安卓版本已更新为 ${next.versionName} (${next.versionCode})`)
