import { createHash } from 'node:crypto'
import { readFile, writeFile } from 'node:fs/promises'
import { resolve } from 'node:path'

const root = resolve(import.meta.dirname, '../..')
const storyRoot = resolve(root, 'content-src/stories')
const output = resolve(storyRoot, 'story-layout.json')
const categories = ['idiom', 'myth', 'folk', 'fable', 'history', 'fairy']
const counts = { idiom: 200, myth: 80, folk: 80, fable: 80, history: 60, fairy: 100 }
const digest = (text) => createHash('sha256').update(text).digest('hex')
const strOrFallback = (value, fallback) => typeof value === 'string' && value ? value : fallback
let existingLayouts = {}
try {
  existingLayouts = JSON.parse(await readFile(output, 'utf8'))
} catch (error) {
  if (error.code !== 'ENOENT') throw error
}

function shortScene(paragraph) {
  const firstSentence = paragraph.split(/(?<=[。！？])/u).find(Boolean) ?? paragraph
  return firstSentence.slice(0, 42).replace(/[。！？]$/u, '')
}

const layouts = {}
for (const category of categories) {
  const raw = await readFile(resolve(storyRoot, `${category}.stories`), 'utf8')
  const rows = raw.split('\n').filter((line) => line.trim() && !line.startsWith('#'))
  if (rows.length !== counts[category]) {
    throw new Error(`${category} 应有 ${counts[category]} 篇，实际 ${rows.length} 篇`)
  }
  for (const row of rows) {
    const fields = row.split('|')
    if (fields.length < 4) throw new Error(`${category} 故事字段不足：${fields[0] ?? '未知'}`)
    const title = fields[0]
    const paragraphs = fields[3].split('~').filter(Boolean)
    const storyId = `${category}-${digest(title).slice(0, 12)}`
    const previous = existingLayouts[storyId] ?? {}
    const previousIds = Array.isArray(previous.paragraphIds) ? previous.paragraphIds : []
    const paragraphIds = paragraphs.map((paragraph, index) =>
      strOrFallback(previousIds[index], `${digest(`${storyId}:${paragraph}`).slice(0, 10)}-${index + 1}`)
    )
    if (new Set(paragraphIds).size !== paragraphIds.length) throw new Error(`稳定段落 ID 重复：${title}`)
    const requestedCount = paragraphs.length <= 4 ? 2 : 3
    const candidateAnchors = [1, Math.max(2, Math.floor(paragraphs.length / 2)), Math.max(3, paragraphs.length - 2)]
    const anchors = [...new Set(candidateAnchors.map((index) => Math.min(index, paragraphs.length - 1)))].slice(0, requestedCount)
    while (anchors.length < requestedCount) {
      anchors.push(anchors.length)
    }
    const validIds = new Set(paragraphIds)
    const previousIllustrations = Array.isArray(previous.illustrations)
      ? previous.illustrations.filter((illustration) => validIds.has(strOrFallback(illustration.paragraphId, '')))
      : []
    const previousLegacyMap = Array.isArray(previous.legacyParagraphMap)
      ? previous.legacyParagraphMap.filter((identifier) => validIds.has(identifier))
      : []
    layouts[storyId] = {
      revision: 2,
      paragraphIds,
      illustrations: previousIllustrations.length >= 2
        ? previousIllustrations.slice(0, 3)
        : anchors.map((paragraphIndex, artworkIndex) => ({
            id: `scene-${artworkIndex + 1}`,
            paragraphId: paragraphIds[paragraphIndex],
            asset: `res://assets/stories/${storyId}/${String(artworkIndex + 1).padStart(2, '0')}.webp`,
            side: artworkIndex % 2 === 0 ? 'right' : 'left',
            alt: `《${title}》第 ${artworkIndex + 1} 幅情节插图：${shortScene(paragraphs[paragraphIndex])}。`,
          })),
      legacyParagraphMap: previousLegacyMap.length
        ? previousLegacyMap
        : title === '守株待兔'
          ? [paragraphIds[0], paragraphIds[1], paragraphIds[4], paragraphIds[5]]
          : paragraphIds.slice(),
    }
  }
}
for (const [storyId, layout] of Object.entries(layouts)) {
  if (layout.illustrations.length < 2 || layout.illustrations.length > 3) {
    throw new Error(`${storyId} 的插画数量应为 2–3`)
  }
  const ids = new Set(layout.paragraphIds)
  for (const illustration of layout.illustrations) {
    if (!ids.has(illustration.paragraphId)) throw new Error(`${storyId} 的插画段落不存在`)
  }
}
await writeFile(output, `${JSON.stringify(layouts, null, 2)}\n`)
console.log(`已生成 ${Object.keys(layouts).length} 篇故事的稳定段落与插画元数据。`)
