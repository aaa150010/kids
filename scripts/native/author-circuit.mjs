import { copyFile, mkdir, readFile, writeFile } from 'node:fs/promises'
import { resolve } from 'node:path'

const root = resolve(import.meta.dirname, '../..')
const outputs = [
  resolve(root, 'content-src/data/circuit.json'),
  resolve(root, 'apps/android/content/circuit.json'),
]
const coverSource = resolve(root, 'content-src/assets/covers/circuit.svg')
const coverTarget = resolve(root, 'apps/android/assets/covers/circuit.svg')

const DIRS = [[0, -1], [1, 0], [0, 1], [-1, 0]]
const OPPOSITE = [2, 3, 0, 1]
const TYPE_NAMES = {
  battery: '低压电池',
  wire: '导线',
  switch: '开关',
  bulb: '小灯泡',
  fan: '小风扇',
  buzzer: '蜂鸣器',
  terminal: '接线端子',
  resistor: '电阻',
}
const GOAL_TYPES = new Set(['bulb', 'fan', 'buzzer'])
const VALID_TYPES = new Set(Object.keys(TYPE_NAMES))
const BANDS = new Set(['easy', 'normal', 'challenge'])
const SINGLE_COUNT = 24
const COOP_COUNT = 8

const SINGLE_TITLES = [
  '小灯泡醒来',
  '风扇转一转',
  '会唱歌的门铃',
  '两盏小夜灯',
  '弯弯的铜线',
  '小熊的电风扇',
  '蜂鸣器报时',
  '灯泡和风扇',
  '蘑菇屋门灯',
  '玩具车充电线',
  '双开关小台灯',
  '小火车信号灯',
  '电阻守门员',
  '分叉小彩灯',
  '音乐盒的电线',
  '三个小电器',
  '纸板城夜灯',
  '风车与铃声',
  '双路玩具台',
  '分岔生日灯',
  '电阻小花园',
  '维修台总闸',
  '彩灯总控板',
  '小工坊毕业照',
]

const COOP_TITLES = [
  '一起点亮纸灯笼',
  '你合闸我检查',
  '双人小风扇',
  '分叉彩线',
  '灯泡蜂鸣二重奏',
  '两个开关一条线',
  '玩具城检修路',
  '童心电路大合奏',
]

const SINGLE_SPECS = [
  { band: 'easy', minAge: 4, width: 4, height: 3, goals: 1, switches: 0, resistors: 0, inter: 2, types: ['bulb'] },
  { band: 'easy', minAge: 4, width: 4, height: 3, goals: 1, switches: 1, resistors: 0, inter: 2, types: ['fan'] },
  { band: 'easy', minAge: 5, width: 5, height: 3, goals: 1, switches: 1, resistors: 0, inter: 2, types: ['buzzer'] },
  { band: 'easy', minAge: 5, width: 5, height: 3, goals: 2, switches: 1, resistors: 0, inter: 3, types: ['bulb', 'bulb'] },
  { band: 'easy', minAge: 5, width: 5, height: 4, goals: 2, switches: 1, resistors: 0, inter: 3, types: ['buzzer', 'bulb'] },
  { band: 'easy', minAge: 6, width: 6, height: 4, goals: 2, switches: 2, resistors: 0, inter: 3, types: ['fan', 'bulb'] },
  { band: 'easy', minAge: 6, width: 6, height: 4, goals: 2, switches: 2, resistors: 0, inter: 4, types: ['bulb', 'buzzer'] },
  { band: 'easy', minAge: 6, width: 6, height: 4, goals: 2, switches: 2, resistors: 0, inter: 4, types: ['bulb', 'fan'] },
  { band: 'normal', minAge: 7, width: 5, height: 4, goals: 2, switches: 1, resistors: 0, inter: 3, types: ['bulb', 'buzzer'] },
  { band: 'normal', minAge: 7, width: 6, height: 4, goals: 2, switches: 1, resistors: 1, inter: 4, types: ['fan', 'bulb'] },
  { band: 'normal', minAge: 7, width: 6, height: 4, goals: 3, switches: 1, resistors: 0, inter: 4, types: ['bulb', 'fan', 'buzzer'] },
  { band: 'normal', minAge: 8, width: 6, height: 5, goals: 2, switches: 2, resistors: 1, inter: 4, types: ['bulb', 'buzzer'] },
  { band: 'normal', minAge: 8, width: 7, height: 5, goals: 3, switches: 2, resistors: 1, inter: 5, types: ['bulb', 'fan', 'buzzer'] },
  { band: 'normal', minAge: 8, width: 7, height: 5, goals: 2, switches: 2, resistors: 1, inter: 5, types: ['bulb', 'fan'] },
  { band: 'normal', minAge: 9, width: 7, height: 5, goals: 3, switches: 2, resistors: 1, inter: 5, types: ['bulb', 'fan', 'buzzer'] },
  { band: 'normal', minAge: 9, width: 7, height: 5, goals: 3, switches: 3, resistors: 1, inter: 6, types: ['bulb', 'buzzer', 'fan'] },
  { band: 'challenge', minAge: 10, width: 6, height: 5, goals: 2, switches: 2, resistors: 1, inter: 5, types: ['bulb', 'bulb'] },
  { band: 'challenge', minAge: 10, width: 7, height: 5, goals: 3, switches: 2, resistors: 1, inter: 6, types: ['bulb', 'buzzer', 'fan'] },
  { band: 'challenge', minAge: 10, width: 7, height: 5, goals: 3, switches: 3, resistors: 1, inter: 6, types: ['fan', 'bulb', 'buzzer'] },
  { band: 'challenge', minAge: 11, width: 7, height: 6, goals: 3, switches: 3, resistors: 1, inter: 7, types: ['bulb', 'fan', 'bulb'] },
  { band: 'challenge', minAge: 11, width: 8, height: 5, goals: 3, switches: 3, resistors: 1, inter: 7, types: ['buzzer', 'bulb', 'fan'] },
  { band: 'challenge', minAge: 11, width: 8, height: 6, goals: 3, switches: 3, resistors: 1, inter: 7, types: ['fan', 'buzzer', 'bulb'] },
  { band: 'challenge', minAge: 12, width: 8, height: 6, goals: 3, switches: 3, resistors: 1, inter: 8, types: ['bulb', 'fan', 'buzzer'] },
  { band: 'challenge', minAge: 12, width: 8, height: 6, goals: 3, switches: 3, resistors: 1, inter: 8, types: ['bulb', 'buzzer', 'fan'] },
]

const COOP_SPECS = [
  { band: 'easy', minAge: 4, width: 4, height: 3, goals: 1, switches: 0, resistors: 0, inter: 2, types: ['bulb'] },
  { band: 'easy', minAge: 5, width: 5, height: 3, goals: 1, switches: 1, resistors: 0, inter: 3, types: ['fan'] },
  { band: 'normal', minAge: 7, width: 5, height: 4, goals: 2, switches: 1, resistors: 0, inter: 3, types: ['fan', 'fan'] },
  { band: 'normal', minAge: 7, width: 6, height: 4, goals: 2, switches: 1, resistors: 0, inter: 4, types: ['bulb', 'fan'] },
  { band: 'normal', minAge: 8, width: 6, height: 4, goals: 2, switches: 2, resistors: 1, inter: 4, types: ['bulb', 'buzzer'] },
  { band: 'normal', minAge: 8, width: 6, height: 5, goals: 3, switches: 2, resistors: 1, inter: 5, types: ['bulb', 'fan', 'buzzer'] },
  { band: 'challenge', minAge: 10, width: 7, height: 5, goals: 3, switches: 2, resistors: 1, inter: 5, types: ['fan', 'bulb', 'buzzer'] },
  { band: 'challenge', minAge: 11, width: 7, height: 5, goals: 3, switches: 3, resistors: 1, inter: 6, types: ['bulb', 'buzzer', 'fan'] },
]

function makeRng(seedValue) {
  let value = seedValue >>> 0
  return () => {
    value = (value * 1664525 + 1013904223) >>> 0
    return value / 0x100000000
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

function key(x, y) {
  return `${x},${y}`
}

function dirBetween(first, second) {
  const dx = second.x - first.x
  const dy = second.y - first.y
  const index = DIRS.findIndex(([x, y]) => x === dx && y === dy)
  if (index < 0 || Math.abs(dx) + Math.abs(dy) !== 1) {
    throw new Error(`格点不相邻：${key(first.x, first.y)} -> ${key(second.x, second.y)}`)
  }
  return index
}

function maskFromDirs(dirs) {
  return [...dirs].reduce((mask, direction) => mask | (1 << direction), 0)
}

function baseDirs(type, shape) {
  if (type === 'battery') return [1]
  if (GOAL_TYPES.has(type)) return [1]
  if (type === 'terminal') return [0, 1, 2, 3]
  if (type === 'wire' && shape === 'elbow') return [0, 1]
  if (type === 'wire' && shape === 'straight') return [1, 3]
  if (['switch', 'resistor'].includes(type)) return [1, 3]
  throw new Error(`没有接口定义：${type}/${shape}`)
}

function maskFor(type, shape, rotation) {
  let mask = 0
  for (const direction of baseDirs(type, shape)) {
    mask |= 1 << ((direction + rotation) % 4)
  }
  return mask
}

function rotationFor(type, shape, dirs) {
  const expected = maskFromDirs(dirs)
  for (let rotation = 0; rotation < 4; rotation += 1) {
    if (maskFor(type, shape, rotation) === expected) return rotation
  }
  throw new Error(`找不到朝向：${type}/${shape}/${expected.toString(2)}`)
}

function shapeForDirs(dirs) {
  const values = [...dirs]
  if (values.length !== 2) throw new Error(`普通元件需要两个接口：${values.join(',')}`)
  return values[1] === OPPOSITE[values[0]] ? 'straight' : 'elbow'
}

function goalRotation(incomingDirection) {
  return (incomingDirection - 1 + 4) % 4
}

function addNode(nodes, x, y) {
  const id = key(x, y)
  if (nodes.has(id)) return nodes.get(id)
  const node = { x, y, dirs: new Set(), branchCell: false, type: null, shape: '', goalOrder: -1 }
  nodes.set(id, node)
  return node
}

function connect(nodes, first, second) {
  const direction = dirBetween(first, second)
  first.dirs.add(direction)
  second.dirs.add(OPPOSITE[direction])
}

function addSegment(nodes, cells, first, second) {
  connect(nodes, cells.get(key(first.x, first.y)), cells.get(key(second.x, second.y)))
}

function buildTree(spec, rng) {
  const { width, height } = spec
  const nodes = new Map()
  const source = { x: 0, y: 1 + Math.floor(rng() * (height - 2)) }
  addNode(nodes, source.x, source.y)
  const mainGoalY = 1 + Math.floor(rng() * (height - 2))
  const x1 = 2 + Math.floor(rng() * Math.max(1, width - 3))
  const useDetour = width >= 6 && rng() < 0.52
  const x2 = Math.min(width - 2, x1 + 1 + Math.floor(rng() * Math.max(1, width - x1 - 2)))
  const midY = 1 + Math.floor(rng() * (height - 2))
  const points = useDetour
    ? [
        source,
        { x: x1, y: source.y },
        { x: x1, y: midY },
        { x: x2, y: midY },
        { x: x2, y: mainGoalY },
        { x: width - 1, y: mainGoalY },
      ]
    : [
        source,
        { x: x1, y: source.y },
        { x: x1, y: mainGoalY },
        { x: width - 1, y: mainGoalY },
      ]
  const cells = [addNode(nodes, source.x, source.y)]
  let cursor = source
  for (const point of points.slice(1)) {
    while (cursor.x !== point.x) {
      cursor = { x: cursor.x + Math.sign(point.x - cursor.x), y: cursor.y }
      cells.push(addNode(nodes, cursor.x, cursor.y))
      addSegment(nodes, nodes, cells[cells.length - 2], cursor)
    }
    while (cursor.y !== point.y) {
      cursor = { x: cursor.x, y: cursor.y + Math.sign(point.y - cursor.y) }
      cells.push(addNode(nodes, cursor.x, cursor.y))
      addSegment(nodes, nodes, cells[cells.length - 2], cursor)
    }
  }
  const goals = [nodes.get(key(width - 1, mainGoalY))]
  goals[0].goalOrder = 0

  while (goals.length < spec.goals) {
    const candidates = shuffled(
      [...nodes.values()].filter((node) => {
        if (node.goalOrder >= 0 || node.branchCell || (node.x === source.x && node.y === source.y)) return false
        for (let direction = 0; direction < 4; direction += 1) {
          if (node.dirs.has(direction)) continue
          const next = { x: node.x + DIRS[direction][0], y: node.y + DIRS[direction][1] }
          if (next.x < 0 || next.x >= width || next.y < 0 || next.y >= height) continue
          if (!nodes.has(key(next.x, next.y))) return true
        }
        return false
      }),
      rng,
    )
    let placed = false
    for (const candidate of candidates) {
      for (const direction of shuffled([0, 1, 2, 3], rng)) {
        if (candidate.dirs.has(direction)) continue
        let free = 0
        let scan = candidate
        const branch = []
        for (let step = 1; step <= 4; step += 1) {
          const next = {
            x: candidate.x + DIRS[direction][0] * step,
            y: candidate.y + DIRS[direction][1] * step,
          }
          if (next.x < 0 || next.x >= width || next.y < 0 || next.y >= height) break
          if (nodes.has(key(next.x, next.y))) break
          free += 1
          branch.push(next)
        }
        if (free < 1) continue
        const length = Math.min(free, 1 + Math.floor(rng() * Math.min(3, free)))
        const target = branch[length - 1]
        let previous = candidate
        for (let index = 0; index < length; index += 1) {
          const node = addNode(nodes, branch[index].x, branch[index].y)
          connect(nodes, previous, node)
          previous = node
        }
        candidate.branchCell = true
        previous.goalOrder = goals.length
        goals.push(previous)
        placed = true
        break
      }
      if (placed) break
    }
    if (!placed) return null
  }

  return { width, height, nodes, source, goals, cells }
}

function assignPieces(tree, spec, rng) {
  const { nodes, source, goals, width, height } = tree
  const ordered = [...nodes.values()].sort((first, second) => first.y - second.y || first.x - second.x)
  const goalByKey = new Map(goals.map((goal) => [key(goal.x, goal.y), goal.goalOrder]))
  const sourceKey = key(source.x, source.y)
  for (const node of ordered) {
    const nodeKey = key(node.x, node.y)
    if (nodeKey === sourceKey) {
      node.type = 'battery'
    } else if (goalByKey.has(nodeKey)) {
      node.type = spec.types[goalByKey.get(nodeKey) % spec.types.length]
    } else if (node.branchCell || node.dirs.size >= 3) {
      node.type = 'terminal'
    } else {
      node.type = 'wire'
      node.shape = shapeForDirs(node.dirs)
    }
  }

  const straightCandidates = shuffled(
    ordered.filter((node) => node.type === 'wire' && node.dirs.size === 2 && shapeForDirs(node.dirs) === 'straight'),
    rng,
  )
  let cursor = 0
  for (let index = 0; index < spec.switches && cursor < straightCandidates.length; index += 1) {
    const node = straightCandidates[cursor]
    cursor += 1
    node.type = 'switch'
    node.shape = 'straight'
  }
  for (let index = 0; index < spec.resistors && cursor < straightCandidates.length; index += 1) {
    const node = straightCandidates[cursor]
    cursor += 1
    node.type = 'resistor'
    node.shape = 'straight'
  }

  const wireNodes = shuffled(ordered.filter((node) => node.type === 'wire'), rng)
  const interactiveCount = Math.min(spec.inter, wireNodes.length)
  const interactive = new Set(wireNodes.slice(0, interactiveCount).map((node) => key(node.x, node.y)))

  const parts = ordered.map((node) => {
    const nodeKey = key(node.x, node.y)
    let rotation = 0
    if (node.type === 'battery' || GOAL_TYPES.has(node.type)) {
      if (node.dirs.size !== 1) throw new Error(`电源或目标接口不唯一：${nodeKey}`)
      rotation = goalRotation([...node.dirs][0])
    } else if (node.type === 'terminal') {
      rotation = 0
    } else {
      rotation = rotationFor(node.type, node.shape, node.dirs)
    }
    var solutionRotation = rotation
    const solutionClosed = node.type === 'switch'
    const locked = node.type !== 'switch' && !interactive.has(nodeKey)
    let initialRotation = rotation
    if (interactive.has(nodeKey) && node.type === 'wire') {
      const choices = [0, 1, 2, 3].filter((candidate) => maskFor('wire', node.shape, candidate) !== maskFor('wire', node.shape, rotation))
      initialRotation = choices[Math.floor(rng() * choices.length)]
      if (node.shape === 'straight' && initialRotation === (rotation + 1) % 4) {
        solutionRotation = (rotation + 2) % 4
      }
    }
    return {
      x: node.x,
      y: node.y,
      type: node.type,
      ...(node.type === 'wire' ? { shape: node.shape } : {}),
      rotation: initialRotation,
      closed: false,
      locked,
      solutionRotation,
      solutionClosed,
    }
  })

  const partByKey = new Map(parts.map((part) => [key(part.x, part.y), part]))
  const goalPoints = goals.map((goal) => {
    if (!partByKey.has(key(goal.x, goal.y))) throw new Error(`目标元件丢失：${key(goal.x, goal.y)}`)
    return { x: goal.x, y: goal.y }
  })
  const fixed = parts.filter((part) => part.locked).map((part) => ({ x: part.x, y: part.y }))
  const solution = []
  for (let index = 0; index < parts.length; index += 1) {
    const part = parts[index]
    if (part.locked) continue
    if (part.type === 'wire' && part.rotation !== part.solutionRotation) {
      solution.push({ index, rotation: part.solutionRotation })
    } else if (part.type === 'switch' && part.closed !== part.solutionClosed) {
      solution.push({ index, closed: part.solutionClosed })
    }
  }
  return {
    width,
    height,
    source: { x: source.x, y: source.y },
    fixed,
    parts,
    goals: goalPoints,
    solution,
    partByKey,
  }
}

function applySolution(built) {
  const pieces = built.parts.map((part) => ({ ...part }))
  for (const step of built.solution) {
    const piece = pieces[step.index]
    if (!piece) throw new Error(`solution 索引越界：${step.index}`)
    if (Object.hasOwn(step, 'rotation')) piece.rotation = step.rotation
    if (Object.hasOwn(step, 'closed')) piece.closed = step.closed
  }
  return pieces
}

function poweredGoals(built, pieces) {
  const byKey = new Map(pieces.map((piece) => [key(piece.x, piece.y), piece]))
  const powered = new Set()
  const sourceKey = key(built.source.x, built.source.y)
  if (!byKey.has(sourceKey)) return { powered, reached: 0, all: false }
  const queue = [sourceKey]
  powered.add(sourceKey)
  let cursor = 0
  while (cursor < queue.length) {
    const currentKey = queue[cursor]
    cursor += 1
    const piece = byKey.get(currentKey)
    if (!piece) continue
    if (piece.type === 'switch' && !piece.closed) continue
    for (let direction = 0; direction < 4; direction += 1) {
      if ((maskFor(piece.type, piece.shape, piece.rotation) & (1 << direction)) === 0) continue
      const nextX = piece.x + DIRS[direction][0]
      const nextY = piece.y + DIRS[direction][1]
      if (nextX < 0 || nextX >= built.width || nextY < 0 || nextY >= built.height) continue
      const nextKey = key(nextX, nextY)
      const next = byKey.get(nextKey)
      if (!next) continue
      if ((maskFor(next.type, next.shape, next.rotation) & (1 << OPPOSITE[direction])) === 0) continue
      if (!powered.has(nextKey)) {
        powered.add(nextKey)
        queue.push(nextKey)
      }
    }
  }
  let reached = 0
  for (const goal of built.goals) {
    if (powered.has(key(goal.x, goal.y))) reached += 1
  }
  return { powered, reached, all: reached === built.goals.length }
}

function parActions(built) {
  let total = 0
  for (const part of built.parts) {
    if (part.type === 'wire' && !part.locked) {
      total += (part.solutionRotation - part.rotation + 4) % 4
    } else if (part.type === 'switch' && !part.closed) {
      total += 1
    }
  }
  return total
}

function validateLevel(levelNumber, level) {
  if (!Number.isInteger(levelNumber) || levelNumber < 1) throw new Error('关卡序号非法')
  for (const field of ['id', 'band', 'minAge', 'title', 'width', 'height', 'source', 'fixed', 'parts', 'goals', 'hint', 'solution', 'narration', 'explanation']) {
    if (!Object.hasOwn(level, field)) throw new Error(`第 ${levelNumber} 关缺少字段：${field}`)
  }
  if (!BANDS.has(level.band)) throw new Error(`第 ${levelNumber} 关 band 非法`)
  if (!Number.isInteger(level.minAge) || level.minAge < 4 || level.minAge > 12) throw new Error(`第 ${levelNumber} 关 minAge 非法`)
  if (!Number.isInteger(level.width) || level.width < 4 || level.width > 9) throw new Error(`第 ${levelNumber} 关 width 非法`)
  if (!Number.isInteger(level.height) || level.height < 3 || level.height > 7) throw new Error(`第 ${levelNumber} 关 height 非法`)
  if (!Array.isArray(level.parts) || level.parts.length < 3) throw new Error(`第 ${levelNumber} 关 parts 非法`)
  if (!Array.isArray(level.goals) || level.goals.length < 1) throw new Error(`第 ${levelNumber} 关 goals 非法`)
  if (!Array.isArray(level.fixed) || !Array.isArray(level.solution) || !level.solution.length) throw new Error(`第 ${levelNumber} 关 fixed/solution 非法`)
  const partKeys = new Set()
  let batteryCount = 0
  for (const part of level.parts) {
    if (!Number.isInteger(part.x) || part.x < 0 || part.x >= level.width) throw new Error(`第 ${levelNumber} 关元件 x 越界`)
    if (!Number.isInteger(part.y) || part.y < 0 || part.y >= level.height) throw new Error(`第 ${levelNumber} 关元件 y 越界`)
    if (!VALID_TYPES.has(part.type)) throw new Error(`第 ${levelNumber} 关元件类型非法：${part.type}`)
    if (![0, 1, 2, 3].includes(part.rotation) || ![0, 1, 2, 3].includes(part.solutionRotation)) throw new Error(`第 ${levelNumber} 关 rotation 非法`)
    if (typeof part.closed !== 'boolean' || typeof part.solutionClosed !== 'boolean' || typeof part.locked !== 'boolean') throw new Error(`第 ${levelNumber} 关元件布尔字段非法`)
    if (part.type === 'wire' && !['straight', 'elbow'].includes(part.shape)) throw new Error(`第 ${levelNumber} 关导线形状非法`)
    const partKey = key(part.x, part.y)
    if (partKeys.has(partKey)) throw new Error(`第 ${levelNumber} 关元件重叠：${partKey}`)
    partKeys.add(partKey)
    if (part.type === 'battery') batteryCount += 1
    if (part.locked && part.rotation !== part.solutionRotation) throw new Error(`第 ${levelNumber} 关固定元件朝向不一致`)
    if (part.type === 'switch' && part.locked) throw new Error(`第 ${levelNumber} 关开关不能锁定`)
  }
  if (batteryCount !== 1) throw new Error(`第 ${levelNumber} 关必须有且只有一个电池`)
  if (!partKeys.has(key(level.source.x, level.source.y))) throw new Error(`第 ${levelNumber} 关电池坐标找不到元件`)
  const sourcePart = level.parts.find((part) => part.x === level.source.x && part.y === level.source.y)
  if (!sourcePart || sourcePart.type !== 'battery') throw new Error(`第 ${levelNumber} 关 source 不是电池`)
  for (const goal of level.goals) {
    const part = level.parts.find((candidate) => candidate.x === goal.x && candidate.y === goal.y)
    if (!part || !GOAL_TYPES.has(part.type)) throw new Error(`第 ${levelNumber} 关目标不是发光/发声元件`)
  }
  const fixedKeys = new Set(level.fixed.map((point) => key(point.x, point.y)))
  if (fixedKeys.size !== level.fixed.length) throw new Error(`第 ${levelNumber} 关 fixed 重复`)
  for (const part of level.parts) {
    if (part.locked !== fixedKeys.has(key(part.x, part.y))) throw new Error(`第 ${levelNumber} 关 fixed/locked 不一致`)
  }
  for (const step of level.solution) {
    if (!Number.isInteger(step.index) || step.index < 0 || step.index >= level.parts.length) throw new Error(`第 ${levelNumber} 关 solution 索引非法`)
    if (!Object.hasOwn(step, 'rotation') && !Object.hasOwn(step, 'closed')) throw new Error(`第 ${levelNumber} 关 solution 步骤为空`)
  }
  const built = {
    width: level.width,
    height: level.height,
    source: level.source,
    goals: level.goals,
    parts: level.parts,
  }
  const solutionPieces = applySolution({ ...built, parts: level.parts, solution: level.solution })
  for (const piece of solutionPieces) {
    if (piece.rotation !== piece.solutionRotation || piece.closed !== piece.solutionClosed) {
      throw new Error(`第 ${levelNumber} 关 solution 未到达目标状态：${piece.x},${piece.y}`)
    }
  }
  if (!poweredGoals(built, solutionPieces).all) throw new Error(`第 ${levelNumber} 关 solution 无法点亮全部目标`)
  if (poweredGoals(built, level.parts).all) throw new Error(`第 ${levelNumber} 关初始状态已经完成`)
  return true
}

function describeGoals(goals) {
  const measures = { bulb: '盏', fan: '台', buzzer: '个' }
  const numerals = { 1: '一', 2: '两', 3: '三', 4: '四' }
  const counts = new Map()
  for (const type of goals) counts.set(type, (counts.get(type) || 0) + 1)
  return [...counts.entries()].map(([type, count]) => {
    if (count === 1) return TYPE_NAMES[type]
    return `${numerals[count] || count}${measures[type]}${TYPE_NAMES[type]}`
  }).join('、')
}

function buildLevel(number, title, spec, seed) {
  const minActions = spec.band === 'easy' ? 2 : spec.band === 'normal' ? 3 : 5
  const minParts = spec.band === 'easy' ? 4 : spec.band === 'normal' ? 7 : 10
  for (let attempt = 0; attempt < 160; attempt += 1) {
    const rng = makeRng(seed + attempt * 7919)
    const tree = buildTree(spec, rng)
    if (!tree) continue
    let built
    try {
      built = assignPieces(tree, spec, rng)
    } catch {
      continue
    }
    if (poweredGoals(built, built.parts).all) continue
    const par = parActions(built)
    if (par < minActions || built.parts.length < minParts) continue
    const isCoop = number > SINGLE_COUNT
    const switchPart = built.parts.find((part) => part.type === 'switch')
    const wrongWire = built.solution.find((step) => Object.hasOwn(step, 'rotation'))
    const hintPart = switchPart || (wrongWire ? built.parts[wrongWire.index] : built.parts.find((part) => !part.locked))
    if (!hintPart) continue
    const goals = built.goals.map((goal) => built.partByKey.get(key(goal.x, goal.y)).type)
    const goalCopy = describeGoals(goals)
    const modeNumber = number - (isCoop ? SINGLE_COUNT : 0)
    const level = {
      id: isCoop ? `circuit-coop-${String(number - SINGLE_COUNT).padStart(2, '0')}` : `circuit-${String(number).padStart(2, '0')}`,
      mode: isCoop ? 'classic' : 'adventure',
      band: spec.band,
      minAge: spec.minAge,
      title,
      width: built.width,
      height: built.height,
      source: built.source,
      fixed: built.fixed,
      parts: built.parts,
      goals: built.goals,
      hint: switchPart
        ? `先合上第 ${switchPart.y + 1} 行第 ${switchPart.x + 1} 列的开关，再顺着铜线看看哪一段还没有接上。`
        : `先转动第 ${hintPart.y + 1} 行第 ${hintPart.x + 1} 列的导线，让接口朝着电池来的方向。`,
      solution: built.solution,
      narration: `${isCoop ? '协作' : '单人'}第${modeNumber}关，${title}。从 3 伏玩具电池出发，接通${goalCopy}。${isCoop ? '两个人轮流转动元件，一起完成。' : (spec.switches > 0 ? '点导线转一转，点开关合上闸刀。' : '点导线转一转，让接口对齐。')}`,
      explanation: `电流只沿着接口对上的铜件前进。${goalCopy}全部通电后，这一关就完成了。还有目标不亮时，看看提示指出的导线或开关；这里只使用安全的低压玩具电池，不碰家里的插座。`,
    }
    try {
      validateLevel(number, level)
      return level
    } catch {
      continue
    }
  }
  throw new Error(`第 ${number} 关生成失败：${title}`)
}

function buildAll() {
  const levels = []
  for (let index = 0; index < SINGLE_TITLES.length; index += 1) {
    const number = index + 1
    levels.push(buildLevel(number, SINGLE_TITLES[index], SINGLE_SPECS[index], 25000 + number * 101))
  }
  for (let index = 0; index < COOP_TITLES.length; index += 1) {
    const number = SINGLE_COUNT + index + 1
    levels.push(buildLevel(number, COOP_TITLES[index], COOP_SPECS[index], 27000 + number * 103))
  }
  if (levels.length !== SINGLE_COUNT + COOP_COUNT) throw new Error('关卡总数错误')
  const adventure = levels.slice(0, SINGLE_COUNT)
  for (const band of ['easy', 'normal', 'challenge']) {
    const count = adventure.filter((level) => level.band === band).length
    if (count !== 8) throw new Error(`单人 ${band} 关卡数必须为 8，实际 ${count}`)
  }
  return { version: 1, levels }
}

async function writeOutputs(data) {
  const text = `${JSON.stringify(data, null, 2)}\n`
  for (const output of outputs) {
    await mkdir(resolve(output, '..'), { recursive: true })
    await writeFile(output, text, 'utf8')
  }
  await mkdir(resolve(coverTarget, '..'), { recursive: true })
  await copyFile(coverSource, coverTarget)
  console.log(`已生成 ${data.levels.length} 关电路内容：${outputs.join(', ')}；封面已同步到安卓资源目录。`)
}

if (process.argv.includes('--check')) {
  const text = await readFile(outputs[0], 'utf8')
  const data = JSON.parse(text)
  if (data.version !== 1 || !Array.isArray(data.levels) || data.levels.length !== SINGLE_COUNT + COOP_COUNT) {
    throw new Error('电路内容版本或关卡总数错误')
  }
  data.levels.forEach((level, index) => validateLevel(index + 1, level))
  console.log(`已校验 ${data.levels.length} 关电路内容，solution 全部点亮目标。`)
} else {
  const data = buildAll()
  await writeOutputs(data)
  data.levels.forEach((level, index) => validateLevel(index + 1, level))
  console.log('全部 32 关通过结构、初始未完成与 solution 通电校验。')
}
