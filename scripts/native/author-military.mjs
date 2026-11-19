import { writeFile } from 'node:fs/promises'
import { resolve } from 'node:path'

const root = resolve(import.meta.dirname, '../..')
const output = resolve(root, 'content-src/data/military.json')
const nativeOutput = resolve(root, 'apps/android/content/military.json')

const camps = new Set([
  '2,1', '2,3', '3,2', '4,1', '4,3',
  '8,1', '8,3', '9,2', '10,1', '10,3',
])
const formationCells = []
for (let row = 0; row <= 5; row += 1) {
  for (let col = 0; col < 5; col += 1) {
    if (!camps.has(`${row},${col}`)) formationCells.push(row * 5 + col)
  }
}

const pieces = {
  flag: 1,
  mine: 3,
  bomb: 2,
  engineer: 3,
  platoon: 3,
  company: 3,
  battalion: 2,
  colonel: 2,
  brigade: 2,
  division: 2,
  corps: 1,
  commander: 1,
}

function rng(seed) {
  let value = seed >>> 0
  return () => {
    value = (value * 1664525 + 1013904223) >>> 0
    return value / 0x100000000
  }
}

function shuffled(values, random) {
  const result = values.slice()
  for (let index = result.length - 1; index > 0; index -= 1) {
    const swap = Math.floor(random() * (index + 1))
    ;[result[index], result[swap]] = [result[swap], result[index]]
  }
  return result
}

function makeFormation(seed) {
  const random = rng(seed)
  const available = formationCells.slice()
  const result = []
  const flagCell = shuffled([1, 3], random)[0]
  result.push([flagCell, 'flag'])
  let remaining = available.filter(index => index !== flagCell)
  const mineCells = shuffled(remaining.filter(index => Math.floor(index / 5) <= 1), random).slice(0, 3)
  for (const index of mineCells) result.push([index, 'mine'])
  remaining = remaining.filter(index => !mineCells.includes(index))
  const rest = []
  for (const [kind, count] of Object.entries(pieces)) {
    if (kind === 'flag' || kind === 'mine') continue
    for (let copy = 0; copy < count; copy += 1) rest.push(kind)
  }
  const shuffledRest = shuffled(rest, random)
  remaining.forEach((index, offset) => result.push([index, shuffledRest[offset]]))
  return result.sort((a, b) => a[0] - b[0])
}

const formations = [
  { id: 'balanced', name: '均衡', cells: makeFormation(1019) },
  { id: 'assault', name: '突击', cells: makeFormation(7919) },
  { id: 'defense', name: '防守', cells: makeFormation(15401) },
]

const flagTargets = [
  { from: 50, to: 55, title: '左侧铁路' },
  { from: 54, to: 59, title: '右侧铁路' },
  { from: 40, to: 45, title: '左上小路' },
  { from: 44, to: 49, title: '右上小路' },
  { from: 56, to: 61, title: '大本营左门' },
  { from: 58, to: 63, title: '大本营右门' },
]
const attackerKinds = [
  ['engineer', '工兵'],
  ['bomb', '炸弹'],
  ['commander', '司令'],
  ['platoon', '排长'],
]
const puzzles = []
let puzzleId = 0
for (const target of flagTargets) {
  for (const [kind, name] of attackerKinds) {
    puzzleId += 1
    puzzles.push({
      id: puzzleId,
      title: `${target.title} · ${name}`,
      hint: `点${name}，再点红色军旗；一步夺旗就能过关。`,
      goal: 'capture_flag',
      targetSteps: 1,
      revealAll: true,
      pieces: [
        { id: `puzzle-${puzzleId}-a`, kind, side: 0, position: target.from },
        { id: `puzzle-${puzzleId}-f`, kind: 'flag', side: 1, position: target.to },
      ],
    })
  }
}

const data = {
  schemaVersion: 1,
  source: {
    reference: 'code-fans/kriegspiel',
    commit: '8bf90e36839d53370d4fd73ad1f0320d491b527a',
    license: 'MIT (README)',
  },
  formations,
  puzzles,
}
const text = JSON.stringify(data, null, 2) + '\n'
await writeFile(output, text)
await writeFile(nativeOutput, text)
console.log(`已生成 ${formations.length} 套军棋阵法和 ${puzzles.length} 个固定残局。`)
