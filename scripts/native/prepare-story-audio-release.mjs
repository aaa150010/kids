import { createHash } from 'node:crypto'
import { copyFile, mkdir, readFile, rm, writeFile } from 'node:fs/promises'
import { resolve } from 'node:path'

const root = resolve(import.meta.dirname, '../..')
const source = resolve(root, 'content-src/story-audio')
const output = resolve(root, 'build/story-audio-release')
const stories = JSON.parse(await readFile(resolve(root, 'content-src/data/stories.json'), 'utf8'))
const manifest = JSON.parse(await readFile(resolve(root, 'content-src/data/story-audio.json'), 'utf8'))
if (stories.length !== 600) throw new Error('发布音频前需要完成 600 篇正文。')
await rm(output, { recursive: true, force: true })
await mkdir(resolve(output, 'audio'), { recursive: true })
let totalBytes = 0
for (const story of stories) {
  const entry = manifest.assets[story.id]
  if (!entry || entry.textSha256 !== story.narrationSha256 || !/^audio\/[a-f0-9]{64}\.mp3$/.test(entry.url)) throw new Error(`缺少与正文配套的音频：${story.title}`)
  const bytes = await readFile(resolve(source, entry.url))
  if (bytes.length !== entry.size || createHash('sha256').update(bytes).digest('hex') !== entry.sha256) throw new Error(`音频不完整：${story.title}`)
  await copyFile(resolve(source, entry.url), resolve(output, entry.url))
  totalBytes += entry.size
}
await writeFile(resolve(output, 'inventory.json'), JSON.stringify({ schema: 1, count: stories.length, totalBytes }, null, 2) + '\n')
console.log(`600 篇音频发布文件已准备到 ${output}；尚未上传。`)
