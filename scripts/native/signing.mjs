import { execFileSync } from 'node:child_process'
import { chmod, mkdir, readFile, writeFile } from 'node:fs/promises'
import { existsSync } from 'node:fs'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { generateKeyPairSync, randomBytes } from 'node:crypto'

const root = resolve(dirname(fileURLToPath(import.meta.url)), '../..')
export const androidRoot = resolve(root, 'apps/android')
const support = process.env.KIDS_PLAYGROUND_KEYS
  ? resolve(process.env.KIDS_PLAYGROUND_KEYS)
  : join(process.env.HOME, 'Library/Application Support/KidsPlayground/keys')
const updatePrivate = join(support, 'update-private.pem')
const updatePublic = resolve(androidRoot, 'trust/update_public_key.pem')
const keystore = join(support, 'kids-playground-release.keystore')
const credentials = join(support, 'release.env')

async function ensureUpdateKey() {
  await mkdir(support, { recursive: true })
  await mkdir(dirname(updatePublic), { recursive: true })
  if (!existsSync(updatePrivate)) {
    const pair = generateKeyPairSync('rsa', {
      modulusLength: 3072,
      privateKeyEncoding: { type: 'pkcs8', format: 'pem' },
      publicKeyEncoding: { type: 'spki', format: 'pem' },
    })
    await writeFile(updatePrivate, pair.privateKey, { mode: 0o600 })
    await chmod(updatePrivate, 0o600)
    await writeFile(updatePublic, pair.publicKey)
  } else {
    const privateKey = await readFile(updatePrivate, 'utf8')
    const { createPublicKey } = await import('node:crypto')
    const publicKey = createPublicKey(privateKey).export({ type: 'spki', format: 'pem' })
    await writeFile(updatePublic, publicKey)
  }
}

async function ensureKeystore() {
  if (existsSync(keystore) && existsSync(credentials)) return
  await mkdir(support, { recursive: true })
  const password = randomBytes(24).toString('base64url')
  const alias = 'kids-playground'
  execFileSync('keytool', [
    '-genkeypair',
    '-keystore', keystore,
    '-storepass', password,
    '-keypass', password,
    '-alias', alias,
    '-keyalg', 'RSA',
    '-keysize', '3072',
    '-validity', '10000',
    '-dname', 'CN=Kids Playground, OU=Local, O=Lynote, L=Shanghai, ST=Shanghai, C=CN',
  ], { stdio: 'inherit' })
  await chmod(keystore, 0o600)
  await writeFile(credentials, [
    `KEYSTORE="${keystore}"`,
    `KEY_ALIAS="${alias}"`,
    `KEYSTORE_PASSWORD="${password}"`,
    `KEY_PASSWORD="${password}"`,
  ].join('\n') + '\n', { mode: 0o600 })
  await chmod(credentials, 0o600)
}

async function ensureKeystoreCredentialsOnly() {
  if (existsSync(credentials)) return
  await mkdir(support, { recursive: true })
  const password = randomBytes(24).toString('base64url')
  await writeFile(credentials, [
    `KEYSTORE="${keystore}"`,
    'KEY_ALIAS="kids-playground"',
    `KEYSTORE_PASSWORD="${password}"`,
    `KEY_PASSWORD="${password}"`,
  ].join('\n') + '\n', { mode: 0o600 })
  await chmod(credentials, 0o600)
}

export async function prepareSigning() {
  await ensureUpdateKey()
  if (process.env.SKIP_KEYTOOL === '1') {
    await ensureKeystoreCredentialsOnly()
  } else {
    await ensureKeystore()
  }
  return { support, updatePrivate, updatePublic, keystore, credentials }
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const result = await prepareSigning()
  console.log(`签名材料已准备：${result.support}`)
}
