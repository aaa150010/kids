import { mkdir, writeFile } from 'node:fs/promises'
import { resolve } from 'node:path'

const root = resolve(import.meta.dirname, '../..')
const outputPaths = [
  resolve(root, 'content-src/data/pipes.json'),
  resolve(root, 'apps/android/content/pipes.json'),
]

const DIRECTIONS = [
  [0, -1],
  [1, 0],
  [0, 1],
  [-1, 0],
]
const OPPOSITE = [2, 3, 0, 1]
const TYPE_BASE = {
  straight: [0, 2],
  elbow: [0, 1],
  tee: [0, 1, 2],
  cross: [0, 1, 2, 3],
  source: [1],
  goal: [3],
}
const TITLES = [
  '小水壶醒了',
  '绕过蘑菇石',
  '草莓圃送水',
  '弯弯小水渠',
  '向日葵的第一桶水',
  '薄荷叶清凉路',
  '南瓜苗喝饱啦',
  '两朵雏菊',
  '小桥边的花盆',
  '三叶草分岔',
  '葡萄架下',
  '雨后小池塘',
  '玫瑰园早班',
  '风车磨坊引水',
  '竹林三岔口',
  '香草迷宫',
  '菜畦环游记',
  '橘子园巡水',
  '石阶上的水声',
  '番茄架接力',
  '月季花廊',
  '小木屋后院',
  '蓝莓坡浇水',
  '向日葵方阵',
  '老磨坊总闸',
  '迷雾温室',
  '四角花园',
  '石板迷宫',
  '上下双渠',
  '喷泉庭院',
  '葡萄园水道',
  '苔藓水闸',
  '花园十字路',
  '水车大回环',
  '古井引水图',
  '童心大花园',
]
const EASY_SIZES = [
  [4, 3], [4, 3], [5, 3], [5, 4], [5, 4], [6, 4],
  [5, 4], [6, 4], [6, 4], [6, 4], [6, 4], [6, 4],
]
const NORMAL_SIZES = [
  [5, 4], [6, 4], [6, 5], [6, 5], [7, 5], [7, 5],
  [6, 5], [7, 5], [7, 5], [7, 5], [7, 5], [7, 5],
]
const CHALLENGE_SIZES = [
  [6, 5], [7, 5], [7, 5], [7, 6], [7, 6], [8, 6],
  [8, 6], [7, 6], [8, 6], [8, 6], [8, 6], [8, 6],
]
const EASY_GOALS = [1, 2, 1, 2, 2, 2, 2, 3, 2, 3, 3, 3]
const NORMAL_GOALS = [2, 2, 3, 2, 3, 3, 2, 3, 3, 3, 3, 3]
const CHALLENGE_GOALS = [3, 3, 3, 4, 3, 4, 3, 4, 4, 3, 4, 4]

function key(x, y) {
  return `${x},${y}`
}

function pointFromKey(value) {
  const [x, y] = value.split(',').map(Number)
  return { x, y }
}

function makeRng(seedValue) {
  let state = seedValue >>> 0
  return () => {
    state = (state * 1664525 + 1013904223) >>> 0
    return state / 0x100000000
  }
}

function shuffled(values, rng) {
  const result = values.slice()
  for (let index = result.length - 1; index > 0; index -= 1) {
    const target = Math.floor(rng() * (index + 1))
    ;[result[index], result[target]] = [result[target], result[index]]
  }
  return result
}

function maskFor(type, rotation) {
  const base = TYPE_BASE[type]
  if (!base) return 0
  let mask = 0
  for (const direction of base) {
    mask |= 1 << ((direction + rotation) % 4)
  }
  return mask
}

function directionsOf(mask) {
  const result = []
  for (let direction = 0; direction < 4; direction += 1) {
    if (mask & (1 << direction)) result.push(direction)
  }
  return result
}

function solutionRotation(type, mask) {
  for (let rotation = 0; rotation < 4; rotation += 1) {
    if (maskFor(type, rotation) === mask) return rotation
  }
  throw new Error(`没有匹配朝向：${type} / ${mask}`)
}

function typeForMask(mask) {
  const count = directionsOf(mask).length
  if (count === 1) throw new Error('普通管件不能只有一个接口')
  if (count === 2) {
    const directions = directionsOf(mask)
    const opposite = directions[1] === OPPOSITE[directions[0]]
    return opposite ? 'straight' : 'elbow'
  }
  if (count === 3) return 'tee'
  if (count === 4) return 'cross'
  throw new Error(`非法管件接口数量：${count}`)
}

function addUndirectedEdge(edges, first, second) {
  if (!edges.has(first)) edges.set(first, new Set())
  if (!edges.has(second)) edges.set(second, new Set())
  edges.get(first).add(second)
  edges.get(second).add(first)
}

function pathBetween(start, end) {
  const result = [start]
  let current = { ...start }
  while (current.x !== end.x || current.y !== end.y) {
    if (current.x !== end.x) current.x += Math.sign(end.x - current.x)
    else current.y += Math.sign(end.y - current.y)
    result.push({ ...current })
  }
  return result
}

function buildTrunk(width, height, mirrored, rng) {
  const rows = shuffled([...Array(height).keys()], rng)
  let sy = rows[0]
  let mid = rows[1]
  let ey = rows[2]
  const ordered = [sy, mid, ey].sort((a, b) => a - b)
  sy = ordered[0]
  mid = ordered[1]
  ey = ordered[2]
  const x1 = Math.max(1, Math.floor(width * 0.34))
  const x2 = Math.min(width - 2, Math.max(x1 + 1, Math.floor(width * 0.68)))
  const waypoints = [
    { x: 0, y: sy },
    { x: x1, y: sy },
    { x: x1, y: mid },
    { x: x2, y: mid },
    { x: x2, y: ey },
    { x: width - 1, y: ey },
  ]
  const cells = []
  const seen = new Set()
  for (let index = 0; index < waypoints.length - 1; index += 1) {
    const segment = pathBetween(waypoints[index], waypoints[index + 1])
    for (const cell of segment) {
      const keyValue = key(cell.x, cell.y)
      if (!seen.has(keyValue)) {
        seen.add(keyValue)
        cells.push(cell)
      }
    }
  }
  if (mirrored) {
    for (const cell of cells) cell.x = width - 1 - cell.x
  }
  return cells
}

function branchCandidates(cells, occupiedKeys, edges) {
  const candidates = []
  for (let index = 1; index < cells.length - 1; index += 1) {
    const cell = cells[index]
    const keyValue = key(cell.x, cell.y)
    const neighbors = []
    for (let direction = 0; direction < 4; direction += 1) {
      const [dx, dy] = DIRECTIONS[direction]
      const next = { x: cell.x + dx, y: cell.y + dy }
      if (!occupiedKeys.has(key(next.x, next.y))) {
        neighbors.push({ cell: next, direction, start: cell })
      }
    }
    if (!neighbors.length) continue
    candidates.push({ index, cell, neighbors, degree: (edges.get(keyValue) || new Set()).size })
  }
  return candidates
}

function makeLevel(number, band, width, height, goalCount, fixedCount, branchLimit, seed) {
  const rng = makeRng(seed)
  const mirrored = number % 2 === 0
  const trunk = buildTrunk(width, height, mirrored, rng)
  const pathKeys = new Set(trunk.map((cell) => key(cell.x, cell.y)))
  const edges = new Map()
  for (let index = 0; index < trunk.length - 1; index += 1) {
    addUndirectedEdge(edges, key(trunk[index].x, trunk[index].y), key(trunk[index + 1].x, trunk[index + 1].y))
  }
  const source = { ...trunk[0] }
  const goals = [{ ...trunk[trunk.length - 1] }]
  const branchCells = new Set()
  const occupiedKeys = new Set([...pathKeys, key(goals[0].x, goals[0].y)])
  let crossPlaced = false

  for (let attempt = 0; attempt < 80 && goals.length < goalCount; attempt += 1) {
    const candidates = branchCandidates(trunk, occupiedKeys, edges)
    if (!candidates.length) break
    const preferred = !crossPlaced ? candidates.filter((entry) => entry.degree >= 2) : []
    const pool = preferred.length && rng() < 0.72 ? preferred : candidates
    const candidate = pool[Math.floor(rng() * pool.length)]
    const orderedNeighbors = shuffled(candidate.neighbors, rng)
    let branch = null
    for (const neighbor of orderedNeighbors) {
      let length = 1 + Math.floor(rng() * Math.max(1, branchLimit))
      length = Math.min(length, branchLimit)
      const cells = []
      let valid = true
      let cursor = candidate.cell
      for (let step = 0; step < length; step += 1) {
        const next = {
          x: cursor.x + DIRECTIONS[neighbor.direction][0],
          y: cursor.y + DIRECTIONS[neighbor.direction][1],
        }
        const nextKey = key(next.x, next.y)
        if (
          next.x < 0 || next.x >= width || next.y < 0 || next.y >= height ||
          occupiedKeys.has(nextKey) ||
          cells.some((cell) => key(cell.x, cell.y) === nextKey)
        ) {
          valid = false
          break
        }
        cells.push(next)
        cursor = next
      }
      if (!valid) continue
      branch = { start: candidate.cell, direction: neighbor.direction, cells }
      break
    }
    if (!branch) continue
    let prior = candidate.cell
    for (const cell of branch.cells) {
      branchCells.add(key(cell.x, cell.y))
      occupiedKeys.add(key(cell.x, cell.y))
      addUndirectedEdge(edges, key(prior.x, prior.y), key(cell.x, cell.y))
      prior = cell
    }
    goals.push({ ...branch.cells[branch.cells.length - 1] })
    if (branch.cells.length === 0) throw new Error('花圃支路不能为空')
    const startKey = key(candidate.cell.x, candidate.cell.y)
    const startDegree = edges.get(startKey).size
    if (startDegree === 4) crossPlaced = true
  }
  if (goals.length !== goalCount) {
    throw new Error(`第 ${number} 关只放下 ${goals.length}/${goalCount} 个花圃`)
  }

  const allCellKeys = new Set([
    ...pathKeys,
    ...branchCells,
    ...goals.map((goal) => key(goal.x, goal.y)),
  ])
  const pieces = []
  const fixed = []
  const lockedIntermediates = new Set()
  const intermediateCells = [...allCellKeys].filter(
    (cellKey) => cellKey !== key(source.x, source.y) && !goals.some((goal) => key(goal.x, goal.y) === cellKey),
  )
  for (const fixedKey of shuffled(intermediateCells, rng).slice(0, fixedCount)) {
    lockedIntermediates.add(fixedKey)
  }
  const wallCandidates = []
  for (let y = 0; y < height; y += 1) {
    for (let x = 0; x < width; x += 1) {
      if (!allCellKeys.has(key(x, y))) wallCandidates.push({ x, y })
    }
  }
  const wallCount = Math.min(wallCandidates.length, 2 + Math.floor(rng() * Math.max(1, height)))
  const walls = shuffled(wallCandidates, rng).slice(0, wallCount)
  const wallKeys = new Set(walls.map((wall) => key(wall.x, wall.y)))

  for (const cellKey of allCellKeys) {
    const cell = pointFromKey(cellKey)
    const connected = [...(edges.get(cellKey) || [])]
    if (!connected.length) throw new Error(`第 ${number} 关存在孤立管件 ${cellKey}`)
    const isSource = cellKey === key(source.x, source.y)
    const isGoal = goals.some((goal) => key(goal.x, goal.y) === cellKey)
    let type
    if (isSource) type = 'source'
    else if (isGoal) type = 'goal'
    else type = typeForMask(connected.reduce((mask, neighborKey) => {
      const neighbor = pointFromKey(neighborKey)
      const dx = neighbor.x - cell.x
      const dy = neighbor.y - cell.y
      const direction = DIRECTIONS.findIndex(([cx, cy]) => cx === dx && cy === dy)
      if (direction < 0) throw new Error(`第 ${number} 关非相邻连接 ${cellKey} -> ${neighborKey}`)
      return mask | (1 << direction)
    }, 0))
    const solutionMask = connected.reduce((mask, neighborKey) => {
      const neighbor = pointFromKey(neighborKey)
      const dx = neighbor.x - cell.x
      const dy = neighbor.y - cell.y
      const direction = DIRECTIONS.findIndex(([cx, cy]) => cx === dx && cy === dy)
      return mask | (1 << direction)
    }, 0)
    const rotation = solutionRotation(type, solutionMask)
    const locked = isSource || isGoal || lockedIntermediates.has(cellKey) || type === 'cross'
    let initialRotation = rotation
    if (!locked) {
      const wrongRotations = [1, 2, 3]
        .map((offset) => (rotation + offset) % 4)
        .filter((candidateRotation) => maskFor(type, candidateRotation) !== solutionMask)
      if (!wrongRotations.length) throw new Error(`第 ${number} 关管件无法打乱 ${cellKey}`)
      initialRotation = wrongRotations[Math.floor(rng() * wrongRotations.length)]
    }
    if (!locked && maskFor(type, initialRotation) === solutionMask) {
      throw new Error(`第 ${number} 关初始朝向已经正确 ${cellKey}`)
    }
    if (wallKeys.has(cellKey)) throw new Error(`第 ${number} 关墙下压着管件 ${cellKey}`)
    pieces.push({
      x: cell.x,
      y: cell.y,
      type,
      rotation: initialRotation,
      solutionRotation: rotation,
      locked,
    })
    if (locked) fixed.push({ x: cell.x, y: cell.y })
  }
  if (!fixed.length) throw new Error(`第 ${number} 关 fixed 不能为空`)
  pieces.sort((first, second) => first.y - second.y || first.x - second.x)
  fixed.sort((first, second) => first.y - second.y || first.x - second.x)
  walls.sort((first, second) => first.y - second.y || first.x - second.x)

  return {
    id: `pipes-${String(number).padStart(2, '0')}`,
    band,
    minAge: band === 'easy' ? 4 + ((number - 1) % 3) : band === 'normal' ? 7 + ((number - 1) % 3) : 10 + ((number - 1) % 3),
    title: TITLES[number - 1],
    width,
    height,
    source,
    goals,
    fixed,
    walls,
    pieces,
  }
}

function validateLevel(level) {
  if (!level || typeof level !== 'object') throw new Error('关卡不是对象')
  if (!/^pipes-\d{2}$/.test(String(level.id))) throw new Error(`关卡 ID 非法：${level.id}`)
  if (!['easy', 'normal', 'challenge'].includes(level.band)) throw new Error(`${level.id} band 非法`)
  if (!Number.isInteger(level.minAge) || level.minAge < 4 || level.minAge > 12) throw new Error(`${level.id} minAge 非法`)
  if (typeof level.title !== 'string' || !level.title.trim()) throw new Error(`${level.id} 缺少标题`)
  if (!Number.isInteger(level.width) || !Number.isInteger(level.height) || level.width < 3 || level.height < 3) {
    throw new Error(`${level.id} 尺寸非法`)
  }
  if (!level.source || !Number.isInteger(level.source.x) || !Number.isInteger(level.source.y)) throw new Error(`${level.id} source 非法`)
  if (!Array.isArray(level.goals) || !level.goals.length) throw new Error(`${level.id} 没有花圃`)
  const wallKeys = new Set()
  for (const wall of level.walls || []) {
    const wallKey = key(wall.x, wall.y)
    if (!Number.isInteger(wall.x) || !Number.isInteger(wall.y) || wall.x < 0 || wall.x >= level.width || wall.y < 0 || wall.y >= level.height) {
      throw new Error(`${level.id} wall 越界`)
    }
    if (wallKeys.has(wallKey)) throw new Error(`${level.id} wall 重复`)
    wallKeys.add(wallKey)
  }
  if (!Array.isArray(level.pieces) || !level.pieces.length) throw new Error(`${level.id} 没有管件`)
  const pieceByKey = new Map()
  for (const piece of level.pieces) {
    const pieceKey = key(piece.x, piece.y)
    if (pieceByKey.has(pieceKey)) throw new Error(`${level.id} 管件重复 ${pieceKey}`)
    if (!Number.isInteger(piece.x) || !Number.isInteger(piece.y) || piece.x < 0 || piece.x >= level.width || piece.y < 0 || piece.y >= level.height) {
      throw new Error(`${level.id} 管件越界 ${pieceKey}`)
    }
    if (!TYPE_BASE[piece.type]) throw new Error(`${level.id} 类型非法 ${piece.type}`)
    for (const field of ['rotation', 'solutionRotation']) {
      if (!Number.isInteger(piece[field]) || piece[field] < 0 || piece[field] > 3) throw new Error(`${level.id} ${field} 非法`)
    }
    if (typeof piece.locked !== 'boolean') throw new Error(`${level.id} locked 非法`)
    if (wallKeys.has(pieceKey)) throw new Error(`${level.id} 管件压在墙下 ${pieceKey}`)
    if (piece.locked && maskFor(piece.type, piece.rotation) !== maskFor(piece.type, piece.solutionRotation)) {
      throw new Error(`${level.id} 固定管件朝向错误 ${pieceKey}`)
    }
    pieceByKey.set(pieceKey, piece)
  }
  const sourcePiece = pieceByKey.get(key(level.source.x, level.source.y))
  if (!sourcePiece || sourcePiece.type !== 'source') throw new Error(`${level.id} 水源缺少 source 管件`)
  const goalKeys = new Set()
  for (const goal of level.goals) {
    const goalKey = key(goal.x, goal.y)
    if (goalKeys.has(goalKey)) throw new Error(`${level.id} 花圃重复`)
    goalKeys.add(goalKey)
    const goalPiece = pieceByKey.get(goalKey)
    if (!goalPiece || goalPiece.type !== 'goal') throw new Error(`${level.id} 花圃缺少 goal 管件 ${goalKey}`)
  }
  const fixedKeys = new Set()
  for (const fixed of level.fixed || []) {
    const fixedKey = key(fixed.x, fixed.y)
    if (fixedKeys.has(fixedKey)) throw new Error(`${level.id} fixed 重复`)
    fixedKeys.add(fixedKey)
    const piece = pieceByKey.get(fixedKey)
    if (!piece || !piece.locked) throw new Error(`${level.id} fixed 与 locked 不一致 ${fixedKey}`)
  }
  if (!fixedKeys.size && !wallKeys.size) throw new Error(`${level.id} fixed/walls 都为空`)
  const reached = new Set()
  const queue = [key(level.source.x, level.source.y)]
  reached.add(queue[0])
  while (queue.length) {
    const currentKey = queue.shift()
    if (wallKeys.has(currentKey)) continue
    const piece = pieceByKey.get(currentKey)
    if (!piece) continue
    const mask = maskFor(piece.type, piece.solutionRotation)
    for (const direction of directionsOf(mask)) {
      const [dx, dy] = DIRECTIONS[direction]
      const nextKey = key(piece.x + dx, piece.y + dy)
      if (wallKeys.has(nextKey)) continue
      const nextPiece = pieceByKey.get(nextKey)
      if (!nextPiece) continue
      if (!(maskFor(nextPiece.type, nextPiece.solutionRotation) & (1 << OPPOSITE[direction]))) continue
      if (!reached.has(nextKey)) {
        reached.add(nextKey)
        queue.push(nextKey)
      }
    }
  }
  for (const goalKey of goalKeys) {
    if (!reached.has(goalKey)) throw new Error(`${level.id} 花圃不可达 ${goalKey}`)
  }
  return {
    id: level.id,
    band: level.band,
    goals: goalKeys.size,
    pieces: level.pieces.length,
    locked: level.pieces.filter((piece) => piece.locked).length,
    reachable: goalKeys.size,
  }
}

function buildAll() {
  const levels = []
  const bands = [
    ['easy', EASY_SIZES, EASY_GOALS, 1, 1],
    ['normal', NORMAL_SIZES, NORMAL_GOALS, 1, 2],
    ['challenge', CHALLENGE_SIZES, CHALLENGE_GOALS, 2, 3],
  ]
  let number = 1
  for (const [band, sizes, goalCounts, fixedBase, branchLimit] of bands) {
    for (let index = 0; index < 12; index += 1) {
      const [width, height] = sizes[index]
      const fixedCount = Math.max(0, fixedBase + (number % 3 === 0 ? 1 : 0))
      const level = makeLevel(
        number,
        band,
        width,
        height,
        goalCounts[index],
        fixedCount,
        branchLimit,
        0x51a7 + number * 7919,
      )
      levels.push(level)
      number += 1
    }
  }
  return { version: 1, levels }
}

const data = buildAll()
const reports = data.levels.map(validateLevel)
const counts = Object.fromEntries(['easy', 'normal', 'challenge'].map((band) => [
  band,
  data.levels.filter((level) => level.band === band).length,
]))
if (counts.easy !== 12 || counts.normal !== 12 || counts.challenge !== 12) {
  throw new Error(`band 数量错误：${JSON.stringify(counts)}`)
}
if (data.levels.length !== 36) throw new Error(`关卡总数错误：${data.levels.length}`)
if (new Set(data.levels.map((level) => level.title)).size !== 36) throw new Error('标题重复')
const types = new Set(data.levels.flatMap((level) => level.pieces.map((piece) => piece.type)))
for (const type of Object.keys(TYPE_BASE)) {
  if (!types.has(type)) throw new Error(`36 关没有使用 ${type}`)
}

const serialized = `${JSON.stringify(data, null, 2)}\n`
for (const outputPath of outputPaths) {
  await mkdir(resolve(outputPath, '..'), { recursive: true })
  await writeFile(outputPath, serialized, 'utf8')
}

console.log(`已生成 ${data.levels.length} 关：easy=${counts.easy}, normal=${counts.normal}, challenge=${counts.challenge}`)
console.log(`管件类型：${[...types].sort().join(', ')}`)
for (const report of reports) {
  console.log(`${report.id} ${report.band} 花圃=${report.goals} 管件=${report.pieces} 固定=${report.locked} 可通水=${report.reachable}`)
}
