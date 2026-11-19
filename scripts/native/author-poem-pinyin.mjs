import { readFile, writeFile } from 'node:fs/promises'
import { resolve } from 'node:path'
import { pinyin } from 'pinyin-pro'

const path = resolve(import.meta.dirname, '../../content-src/data/poems.json')
const poems = JSON.parse(await readFile(path, 'utf8'))
const punctuation = /[，。！？；：、,.!?;:]/

function annotate(line) {
  const units = pinyin(line, {
    type: 'all',
    toneType: 'symbol',
    toneSandhi: false,
  })
  let result = ''
  for (const unit of units) {
    const origin = String(unit.origin || '')
    if (/\p{Script=Han}/u.test(origin)) {
      if (result && !result.endsWith(' ')) result += ' '
      result += String(unit.pinyin || origin)
    } else if (punctuation.test(origin)) {
      result = result.replace(/ +$/, '') + origin + ' '
    } else if (origin.trim()) {
      if (result && !result.endsWith(' ')) result += ' '
      result += origin
    }
  }
  return result.trim()
}

let lineCount = 0
for (const poem of poems) {
  if (!Array.isArray(poem.lines)) continue
  poem.linesPinyin = poem.lines.map(line => {
    lineCount += 1
    return annotate(String(line))
  })
}

await writeFile(path, JSON.stringify(poems) + '\n')
console.log(`已为 ${poems.length} 首古诗生成 ${lineCount} 行拼音。`)
