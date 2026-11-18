import { readFile, writeFile } from 'node:fs/promises'
import { resolve } from 'node:path'
import { prepareSigning } from './signing.mjs'

const root = resolve(import.meta.dirname, '../..')
const projectRoot = process.env.NATIVE_PROJECT_DIR
  ? resolve(process.env.NATIVE_PROJECT_DIR)
  : resolve(root, 'apps/android')
const presetPath = resolve(projectRoot, 'export_presets.cfg')
const versionPath = resolve(projectRoot, 'version.json')
const version = JSON.parse(await readFile(versionPath, 'utf8'))
const signing = await prepareSigning()
const values = await readFile(signing.credentials, 'utf8')
const env = Object.fromEntries(values.trim().split('\n').map((line) => {
  const split = line.indexOf('=')
  return [line.slice(0, split), line.slice(split + 1).replace(/^"|"$/g, '')]
}))
let preset = await readFile(presetPath, 'utf8')
const keystoreValue = process.env.NATIVE_KEYSTORE_PATH || env.KEYSTORE
preset = preset
  .replace(/version\/code=\d+/g, `version/code=${version.versionCode}`)
  .replace(/version\/name="[^"]+"/g, `version/name="${version.versionName}"`)
  .replace('keystore/release=""', `keystore/release="${keystoreValue}"`)
  .replace('keystore/release_user=""', `keystore/release_user="${env.KEY_ALIAS}"`)
  .replace('keystore/release_password=""', `keystore/release_password="${env.KEYSTORE_PASSWORD}"`)
await writeFile(presetPath, preset)
console.log(`临时导出配置已写入版本 ${version.versionName} (${version.versionCode})。`)
