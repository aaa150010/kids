import { createHash } from 'node:crypto'
import { readFile } from 'node:fs/promises'
import { resolve } from 'node:path'

const root = resolve(import.meta.dirname, '../..')
const storyRoot = resolve(root, 'content-src/stories')
const categories = ['idiom', 'myth', 'folk', 'fable', 'history', 'fairy']
const counts = { idiom: 200, myth: 80, folk: 80, fable: 80, history: 60, fairy: 100 }
const lengthRanges = {
  idiom: [220, 560],
  myth: [300, 800],
  folk: [300, 800],
  fable: [320, 520],
  history: [110, 800],
  fairy: [700, 1500],
}
const digest = (text) => createHash('sha256').update(text).digest('hex')
const normalize = (text) => text
  .replace(/\s+/gu, '')
  .replace(/[“”‘’"'《》〈〉（）()【】\[\]…—…·,.，。！？；：、]/gu, '')
const sentences = (text) => text
  .split(/(?<=[。！？])/u)
  .map(normalize)
  .filter((sentence) => sentence.length >= 10)

const errors = []
const stories = []
const titles = new Set()
const bodies = new Set()
const allSentences = new Map()

for (const category of categories) {
  const raw = await readFile(resolve(storyRoot, `${category}.stories`), 'utf8')
  const rows = raw.split('\n').filter((line) => line.trim() && !line.startsWith('#'))
  if (rows.length !== counts[category]) {
    errors.push(`${category} 应有 ${counts[category]} 篇，实际 ${rows.length} 篇`)
  }
  for (const [index, row] of rows.entries()) {
    const [title, age, sourceLabel, body, meaning = '', example = ''] = row.split('|')
    const label = `${category} 第 ${index + 1} 行《${title ?? '未知'}》`
    if (!title || !body || !sourceLabel || ![4, 7, 10].includes(Number(age))) {
      errors.push(`${label} 字段不完整`)
      continue
    }
    if (titles.has(title)) errors.push(`${label} 标题重复`)
    if (bodies.has(body)) errors.push(`${label} 正文与另一篇完全相同`)
    titles.add(title)
    bodies.add(body)
    if (category === 'idiom' && (!meaning || !example)) {
      errors.push(`${label} 缺少释义或例句`)
    }
    const [minimum, maximum] = lengthRanges[category]
    if (body.length < minimum || body.length > maximum) {
      errors.push(`${label} 正文长度 ${body.length}，应在 ${minimum}–${maximum} 字之间`)
    }

    const paragraphs = body.split('~').filter(Boolean)
    const seenParagraphs = new Set()
    const seenSentences = new Set()
    for (const paragraph of paragraphs) {
      const normalized = normalize(paragraph)
      if (seenParagraphs.has(normalized)) errors.push(`${label} 有重复段落`)
      seenParagraphs.add(normalized)
      if (paragraph.length > 180) errors.push(`${label} 有一段超过 180 字，滚动阅读会过于沉重`)
      for (const sentence of sentences(paragraph)) {
        if (seenSentences.has(sentence)) errors.push(`${label} 篇内重复句子：${sentence.slice(0, 28)}`)
        seenSentences.add(sentence)
        if (!allSentences.has(sentence)) allSentences.set(sentence, [])
        allSentences.get(sentence).push(title)
      }
    }
    stories.push({ category, title, body, paragraphs })
  }
}

for (const [sentence, storyTitles] of allSentences) {
  const uniqueTitles = [...new Set(storyTitles)]
  if (uniqueTitles.length > 1) {
    errors.push(`跨篇重复句子（${uniqueTitles.slice(0, 3).join('、')}）：${sentence.slice(0, 32)}`)
  }
}

const manifest = stories.map(({ category, title, body, paragraphs }) => ({
  id: `${category}-${digest(title).slice(0, 12)}`,
  category,
  title,
  sha256: digest(body),
  paragraphs: paragraphs.length,
}))

if (errors.length) {
  console.error(`故事质量审计失败，共 ${errors.length} 项：`)
  for (const error of errors.slice(0, 120)) console.error(`- ${error}`)
  if (errors.length > 120) console.error(`- 其余 ${errors.length - 120} 项省略`)
  process.exit(1)
}

console.log(`故事质量审计通过：${stories.length} 篇，${allSentences.size} 个独立句子。`)
if (process.argv.includes('--json')) {
  console.log(JSON.stringify(manifest))
}
