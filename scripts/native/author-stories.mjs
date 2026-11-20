import { createHash } from 'node:crypto'
import { mkdir, readFile, writeFile, copyFile } from 'node:fs/promises'
import { resolve } from 'node:path'
import { pinyin, customPinyin } from 'pinyin-pro'

const root = resolve(import.meta.dirname, '../..')
const source = resolve(root, 'content-src/stories')
const counts = { idiom: 200, myth: 80, folk: 80, fable: 80, history: 60, fairy: 100 }
const draft = process.argv.includes('--draft')
const textOnly = process.argv.includes('--text-only')
const sha = text => createHash('sha256').update(text).digest('hex')
const bookNames = { '史记':'史記', '左传':'春秋左氏傳', '汉书':'漢書', '后汉书':'後漢書', '晋书':'晉書', '宋史':'宋史', '列子':'列子', '庄子':'莊子', '韩非子':'韓非子', '战国策':'戰國策', '淮南子':'淮南子', '山海经':'山海經', '世说新语':'世說新語', '说苑':'說苑', '吕氏春秋':'呂氏春秋', '论语':'論語', '孟子':'孟子', '荀子':'荀子', '礼记':'禮記', '尚书':'尚書', '周易':'周易', '资治通鉴':'資治通鑑', '西游记':'西遊記', '封神演义':'封神演義', '梦溪笔谈':'夢溪筆談', '天工开物':'天工開物', '徐霞客游记':'徐霞客遊記', '本草纲目':'本草綱目', '竹取物语':'竹取物語' }
const overrides = JSON.parse(await readFile(resolve(source, 'pronunciation.json'), 'utf8'))
customPinyin(overrides)

function annotate(text) {
  const units = pinyin(text, { type: 'all', toneSandhi: false })
  const result = []
  for (const unit of units) {
    for (const character of [...unit.origin]) {
      result.push(/\p{Script=Han}/u.test(character) ? unit.pinyin : '')
    }
  }
  if (result.length !== [...text].length) throw new Error(`拼音与正文没有对齐：${text.slice(0, 24)}`)
  return result
}

const stories = []
const titles = new Set()
const bodies = new Set()
for (const [category, expected] of Object.entries(counts)) {
  let raw
  try { raw = await readFile(resolve(source, `${category}.stories`), 'utf8') }
  catch (error) { if (draft && error.code === 'ENOENT') continue; throw error }
  const rows = raw.split('\n').filter(line => line.trim() && !line.startsWith('#'))
  if (!draft && rows.length !== expected) throw new Error(`${category} 应有 ${expected} 篇，实际 ${rows.length} 篇`)
  for (const [index, line] of rows.entries()) {
    const [title, age, sourceLabel, body, meaning = '', example = ''] = line.split('|')
    if (!title || !body || !sourceLabel || ![4, 7, 10].includes(Number(age))) throw new Error(`${category} 第 ${index + 1} 行不完整`)
    if (titles.has(title) || bodies.has(body)) throw new Error(`故事重复：${title}`)
    titles.add(title); bodies.add(body)
    if (category === 'idiom' && (!meaning || !example)) throw new Error(`成语缺少释义或例句：${title}`)
    const paragraphs = body.split('~').filter(Boolean).map(text => ({ text, role: 'story' }))
    if (meaning) paragraphs.push({ text: `词语小口袋：${meaning}`, role: 'meaning' })
    if (example) paragraphs.push({ text: `试着用一用：${example}`, role: 'example' })
    for (const paragraph of paragraphs) paragraph.pinyin = annotate(paragraph.text)
    const narration = [title + '。', ...paragraphs.map(paragraph => paragraph.text)].join('\n')
    const book = sourceLabel.match(/《([^》]+)》/)?.[1]
    let sourceUrl = bookNames[book] ? 'https://zh.wikisource.org/wiki/' + encodeURIComponent(bookNames[book]) : ''
    if (sourceLabel.includes('伊索')) sourceUrl = 'https://www.gutenberg.org/ebooks/21'
    if (sourceLabel.includes('格林')) sourceUrl = 'https://www.gutenberg.org/ebooks/2591'
    if (sourceLabel.includes('安徒生')) sourceUrl = 'https://www.gutenberg.org/ebooks/1597'
    if (sourceLabel.includes('原创')) sourceUrl = ''
    stories.push({
      id: `${category}-${sha(title).slice(0, 12)}`, category, title, titlePinyin: annotate(title),
      minAge: Number(age), origin: sourceLabel.includes('原创') ? '童心原创' : '经典故事·儿童改写',
      sourceLabel, sourceUrl, editorialNote: sourceLabel.includes('原创') ? '本项目原创故事。' : category === 'idiom' ? '词语出处与释义参考上列来源，叙事情境为儿童改写或新编。' : category === 'history' ? '依据史传或流传轶事改写；传说与史实请结合出处阅读。' : category === 'myth' ? '神话是古人想象世界的故事。' : '依据传统情节重新编写的儿童中文版本。',
      paragraphs, narration, narrationSha256: sha(narration),
      searchText: [title, sourceLabel, body, meaning].join(' '),
    })
  }
}
await mkdir(resolve(root, 'apps/android/content'), { recursive: true })
await writeFile(resolve(root, 'content-src/data/stories.json'), JSON.stringify(stories) + '\n')
await copyFile(resolve(root, 'content-src/data/stories.json'), resolve(root, 'apps/android/content/stories.json'))
console.log(`已制作 ${stories.length} 篇故事的原生文字与逐字拼音${draft ? '（制作中）' : ''}。`)
