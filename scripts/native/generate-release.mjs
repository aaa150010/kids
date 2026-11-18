import { execFileSync } from 'node:child_process'
import { createHash, sign, verify } from 'node:crypto'
import { copyFile, mkdir, readFile, writeFile } from 'node:fs/promises'
import { basename, dirname, resolve } from 'node:path'
import { prepareSigning } from './signing.mjs'

const root = resolve(import.meta.dirname, '../..')
const output = resolve(root, 'build/native-release')
const version = JSON.parse(await readFile(resolve(root, 'apps/android/version.json'), 'utf8'))
const contentVersionFile = JSON.parse(await readFile(resolve(root, 'apps/android/content/version.json'), 'utf8'))
const signing = await prepareSigning()
const apk = process.env.APK_PATH ? resolve(process.env.APK_PATH) : resolve(root, 'apps/android/build/kids-playground.apk')
const pck = process.env.PCK_PATH ? resolve(process.env.PCK_PATH) : resolve(root, 'apps/android/build/content.pck')
const contentVersion = Number(process.env.CONTENT_VERSION ?? contentVersionFile.version)
const downloadTemplate = await readFile(resolve(root, 'scripts/native/download-page.template.html'), 'utf8')
const appIcon = resolve(root, 'apps/android/assets/branding/app-icon-1024.png')

async function hash(path) {
  const data = await readFile(path)
  return {
    bytes: data,
    sha256: createHash('sha256').update(data).digest('hex'),
    size: data.byteLength,
  }
}

// Read the trust root from the exported APK so a missing or stale key cannot ship.
let packagedPublicKey
try {
  packagedPublicKey = execFileSync('unzip', ['-p', apk, 'assets/trust/update_public_key.pem'], {
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'pipe'],
  })
} catch {
  throw new Error('APK 缺少更新校验公钥，拒绝生成发布清单。')
}
const expectedPublicKey = await readFile(signing.updatePublic, 'utf8')
if (packagedPublicKey.trim() !== expectedPublicKey.trim()) {
  throw new Error('APK 中的更新公钥与本次签名公钥不一致，拒绝发布。')
}

let reusedContent = null
if (process.env.REUSE_CONTENT_MANIFEST) {
  const previousPath = resolve(process.env.REUSE_CONTENT_MANIFEST)
  const previousBytes = await readFile(previousPath)
  const previousSignature = Buffer.from(
    (await readFile(resolve(dirname(previousPath), 'latest.sig'), 'utf8')).trim(), 'base64',
  )
  if (!verify('sha256', previousBytes, packagedPublicKey, previousSignature)) {
    throw new Error('原内容清单签名无效，拒绝复用。')
  }
  reusedContent = JSON.parse(previousBytes.toString('utf8')).content
  if (Number(reusedContent?.version) !== contentVersion ||
      !/^content-\d+\.pck$/.test(reusedContent?.url ?? '') ||
      !/^[a-f0-9]{64}$/.test(reusedContent?.sha256 ?? '') ||
      Number(reusedContent?.size) <= 0 ||
      Number(reusedContent?.minAppVersionCode) > version.versionCode ||
      Number(reusedContent?.maxAppVersionCode ?? 2147483647) < version.versionCode) {
    throw new Error('原内容包版本或兼容范围不符合本次 APK，拒绝复用。')
  }
}

const apkInfo = await hash(apk)
const pckInfo = reusedContent ?? await hash(pck)
await mkdir(output, { recursive: true })
const apkName = `kids-playground-${version.versionCode}.apk`
const pckName = reusedContent?.url ?? `content-${contentVersion}.pck`
const apkTarget = resolve(output, apkName)
const pckTarget = resolve(output, pckName)
if (apk !== apkTarget) {
  await copyFile(apk, apkTarget)
}
if (!reusedContent && pck !== pckTarget) {
  await copyFile(pck, pckTarget)
}
const payload = {
  schema: 1,
  publishedAt: new Date().toISOString(),
  apk: {
    versionCode: version.versionCode,
    versionName: version.versionName,
    url: apkName,
    sha256: apkInfo.sha256,
    size: apkInfo.size,
    notes: process.env.RELEASE_NOTES ?? '',
  },
  content: {
    version: contentVersion,
    url: pckName,
    sha256: pckInfo.sha256,
    size: pckInfo.size,
    minAppVersionCode: Number(process.env.MIN_APP_VERSION_CODE ?? reusedContent?.minAppVersionCode ?? contentVersionFile.minAppVersionCode ?? version.versionCode),
    maxAppVersionCode: Number(process.env.MAX_APP_VERSION_CODE ?? reusedContent?.maxAppVersionCode ?? contentVersionFile.maxAppVersionCode ?? 2147483647),
  },
}
const payloadBytes = Buffer.from(JSON.stringify(payload, null, 2))
const privateKey = await readFile(signing.updatePrivate, 'utf8')
const signatureBytes = sign('sha256', payloadBytes, privateKey)
if (!verify('sha256', payloadBytes, packagedPublicKey, signatureBytes)) {
  throw new Error('APK 内的公钥无法验证本次更新清单，拒绝发布。')
}
const signature = signatureBytes.toString('base64')
await writeFile(resolve(output, 'latest.json'), payloadBytes)
await writeFile(resolve(output, 'latest.sig'), signature)
await copyFile(appIcon, resolve(output, 'app-icon.png'))

function escapeHtml(value) {
  return String(value)
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;')
}

function formatSize(bytes) {
  const mib = Number(bytes) / 1024 / 1024
  return `${mib.toFixed(mib >= 100 ? 0 : 1)} MB`
}

const published = new Date(payload.publishedAt)
const publishedText = new Intl.DateTimeFormat('zh-CN', {
  timeZone: 'Asia/Shanghai',
  year: 'numeric',
  month: 'long',
  day: 'numeric',
  hour: '2-digit',
  minute: '2-digit',
  hour12: false,
}).format(published)
const downloadPage = downloadTemplate
  .replaceAll('{{VERSION_NAME}}', escapeHtml(payload.apk.versionName))
  .replaceAll('{{VERSION_CODE}}', escapeHtml(payload.apk.versionCode))
  .replaceAll('{{APK_SIZE}}', escapeHtml(formatSize(payload.apk.size)))
  .replaceAll('{{PUBLISHED_AT}}', escapeHtml(publishedText))
  .replaceAll('{{APK_NAME}}', escapeHtml(payload.apk.url))
  .replaceAll('{{APK_URL}}', escapeHtml(encodeURI(payload.apk.url)))
  .replaceAll('{{APK_SHA256}}', escapeHtml(payload.apk.sha256))
  .replaceAll('{{APP_ICON}}', `app-icon.png?v=${payload.apk.versionCode}`)
await writeFile(resolve(output, 'index.html'), downloadPage)

console.log(`更新清单已生成：${output}`)
console.log(`APK：${apkName} (${apkInfo.size} bytes)`)
console.log(`内容包：${pckName} (${pckInfo.size} bytes)${reusedContent ? '，复用已签名的线上版本' : ''}`)
console.log('APK 下载页：index.html')
