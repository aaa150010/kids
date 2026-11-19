import { mkdir, readFile, writeFile } from 'node:fs/promises'
import { resolve } from 'node:path'

const root = resolve(import.meta.dirname, '../..')
const directory = resolve(root,'content-src/assets/icons')
await mkdir(directory,{recursive:true})
const headers = {'User-Agent':'kids-playground-content-import'}
const commitResponse = await fetch('https://api.github.com/repos/hfg-gmuend/openmoji/commits/master',{headers})
if (!commitResponse.ok) throw new Error(`OpenMoji source: ${commitResponse.status}`)
const { sha } = await commitResponse.json()
const segments = new Intl.Segmenter('zh',{granularity:'grapheme'})
const tokens = new Set()
for (const name of ['quizzes','memory','workbook']) {
  const text = await readFile(resolve(root,'content-src/data',name+'.json'),'utf8')
  for (const {segment} of segments.segment(text)) if (/\p{Extended_Pictographic}/u.test(segment)) tokens.add(segment)
}
for (const token of ['⛵','🏝️','🦁','🐯','🐺','🐶','🐱','🐭','🌲','🌳','🐢','🚩','🎲','🏠','🌙','🏮','🧩','✏️','🔍','☀️','⭐','🎓','🎯','💡','📖','💣','🛡️','🌊','📒','🐘','🏆','🦊','🐼','🐰','🐻','🐧','🐨','🦉','🐬','🥷','🌸','🏹','🪙','☁️']) tokens.add(token)
const downloaded = []
const missing = []
const queue = [...tokens]
async function worker() {
  while(queue.length) {
    const token = queue.shift()
    const code = [...token].map(character=>character.codePointAt(0).toString(16).toUpperCase()).join('-')
    const variants = [code,code.replaceAll('-FE0F','')]
    let found = false
    for (const variant of new Set(variants)) {
      const response = await fetch(`https://raw.githubusercontent.com/hfg-gmuend/openmoji/${sha}/color/svg/${variant}.svg`,{headers})
      if (!response.ok) continue
      await writeFile(resolve(directory,code+'.svg'), await response.text())
      downloaded.push({token,file:code+'.svg'})
      found = true
      break
    }
    if (!found) missing.push(token)
  }
}
await Promise.all(Array.from({length:6},worker))
const license = await fetch(`https://raw.githubusercontent.com/hfg-gmuend/openmoji/${sha}/LICENSE.txt`,{headers})
if (!license.ok) throw new Error('OpenMoji license download failed')
await writeFile(resolve(root,'content-src/licenses/openmoji.txt'),await license.text())
await writeFile(resolve(root,'content-src/data/art.json'),JSON.stringify({source:'https://github.com/hfg-gmuend/openmoji',commit:sha,license:'CC-BY-SA-4.0',downloaded,missing},null,2)+'\n')
console.log(`已导入 ${downloaded.length} 个离线矢量图案；无对应资源 ${missing.length} 个。`)
