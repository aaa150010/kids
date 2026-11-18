import { createHash } from 'node:crypto'
import { readFile, writeFile, mkdir } from 'node:fs/promises'
import { dirname, resolve } from 'node:path'

const root = resolve(import.meta.dirname, '../..')
const provenance = JSON.parse(await readFile(resolve(root, 'content-src/licenses/garden-source.json'), 'utf8'))
const target = resolve(root, 'content-src/assets/garden')
const base = `https://raw.githubusercontent.com/xyxiao001/pvz-web/${provenance.revision}/public/assets/`
const hash = (bytes) => createHash('sha1').update(`blob ${bytes.length}\0`).update(bytes).digest('hex')
const inventory = []
let cursor = 0
let completed = 0
const failed = []
async function download() {
  while (cursor < provenance.assetEntries.length) {
    const entry = provenance.assetEntries[cursor++]
    if (!/^(runtime|music|original)\/[\w./-]+$/.test(entry.path) || entry.path.includes('..')) throw new Error(`Invalid asset path: ${entry.path}`)
    const path = resolve(target, entry.path)
    let bytes
    try { bytes = await readFile(path) } catch {}
    if (!bytes || hash(bytes) !== entry.sha) {
      for (let attempt = 0; attempt < 4; attempt++) {
        try {
          const response = await fetch(base + entry.path, { signal: AbortSignal.timeout(45000) })
          if (!response.ok) throw new Error(`${response.status} ${entry.path}`)
          bytes = Buffer.from(await response.arrayBuffer())
          if (hash(bytes) !== entry.sha) throw new Error(`Hash mismatch: ${entry.path}`)
          await mkdir(dirname(path), { recursive: true })
          await writeFile(path, bytes)
          break
        } catch (error) {
          if (attempt === 3) {
            console.error(`Asset failed: ${entry.path}: ${error.message}`)
            failed.push(entry.path)
            bytes = null
            break
          }
          await new Promise(resolveDelay => setTimeout(resolveDelay, (attempt + 1) * 800))
        }
      }
    }
    if (bytes) inventory.push({ path: entry.path, bytes: bytes.length, gitBlob: entry.sha, sha256: createHash('sha256').update(bytes).digest('hex'), source: base + entry.path })
    completed++
    if (completed % 50 === 0) console.log(`Garden assets: ${completed}/${provenance.assetEntries.length}`)
  }
}
await Promise.all(Array.from({ length: 3 }, download))
if (failed.length) throw new Error(`Run again to resume ${failed.length} assets: ${failed.join(', ')}`)
inventory.sort((left, right) => left.path.localeCompare(right.path))
const readJson = async path => JSON.parse(await readFile(resolve(target, path), 'utf8'))
const animationIndex = await readJson('runtime/animations.json')
const actors = {}
const plants = {}
for (const entry of inventory) {
  if (/^runtime\/actor-motion\/.+\.json$/.test(entry.path)) {
    const definition = await readJson(entry.path)
    const family = entry.path.split('/').at(-1).replace('.json', '')
    for (const clip of Object.keys(definition.clips)) actors[clip] = family
  }
  if (/^runtime\/plant-motion\/.+\.json$/.test(entry.path)) plants[entry.path.split('/').at(-1).replace('.json', '')] = entry.path
}
const presentation = {
  schemaVersion: 2, sourceRevision: provenance.revision, localPersonalUseOnly: true,
  actors, plants, animations: animationIndex.animations,
  scenes: Object.fromEntries(['day', 'night', 'pool', 'fog', 'roof'].map(scene => [scene, `hd4/scenery/${scene}.webp`])),
  audio: Object.fromEntries(inventory.filter(entry => entry.path.endsWith('.mp3')).map(entry => [entry.path.replace(/^(music|original)\//, '').replace('.mp3', ''), entry.path])),
  missing: [],
}
await writeFile(resolve(root, 'content-src/data/garden-presentation.json'), JSON.stringify(presentation) + '\n')
await writeFile(resolve(root, 'content-src/licenses/garden-assets.json'), JSON.stringify({ repository: provenance.repository, revision: provenance.revision, usage: 'Local personal edition; artwork and audio provenance does not grant redistribution rights.', files: inventory }, null, 2) + '\n')
console.log(`Imported ${inventory.length} verified assets, ${Object.keys(actors).length} actor clips, ${Object.keys(plants).length} plant rigs.`)
