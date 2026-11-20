import { writeFile } from 'node:fs/promises'
import { resolve } from 'node:path'

const output = resolve(import.meta.dirname, '../../content-src/data/sudoku.json')

const MINI_SEED = 0x4d494e49
const CLASSIC_SEED = 0x434c4153
const GOLDEN_RATIO = 0x9e3779b9
const CARVE_SEED = 0x85ebca6b

const MINI_TARGET_GIVENS = 10
const CLASSIC_TARGET_GIVENS = {
  easy: 44,
  normal: 36,
  challenge: 30,
}
const CLASSIC_DIFFICULTIES = ['normal', 'challenge', 'easy']

function random32(seed) {
  let value = seed >>> 0
  return () => {
    value = (value + 0x6d2b79f5) >>> 0
    let result = value
    result = Math.imul(result ^ (result >>> 15), result | 1)
    result ^= result + Math.imul(result ^ (result >>> 7), result | 61)
    return ((result ^ (result >>> 14)) >>> 0) / 0x100000000
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

function range(length) {
  return Array.from({ length }, (_, index) => index)
}

function makeBaseSolution(size, boxRows) {
  return Array.from({ length: size }, (_, row) =>
    Array.from(
      { length: size },
      (_, col) => (((row % boxRows) * boxRows + Math.floor(row / boxRows) + col) % size) + 1,
    ),
  )
}

function shuffledGroups(size, groupSize, random) {
  const groupCount = size / groupSize
  const result = []
  for (const group of shuffled(range(groupCount), random)) {
    result.push(...shuffled(range(groupSize).map(offset => group * groupSize + offset), random))
  }
  return result
}

function makeSolution(base, size, boxRows, boxCols, seed) {
  const random = random32(seed)
  const rowOrder = shuffledGroups(size, boxRows, random)
  const colOrder = shuffledGroups(size, boxCols, random)
  const digits = shuffled(range(size).map(index => index + 1), random)
  const transpose = random() < 0.5
  const rows = rowOrder.map(row => colOrder.map(col => base[row][col]))
  const arranged = transpose
    ? rows.map((_, row) => rows.map(cells => cells[row]))
    : rows
  return arranged.map(cells => cells.map(value => String(digits[value - 1]))).map(cells => cells.join('')).join('')
}

function boxIndex(row, col, boxRows, boxCols) {
  return Math.floor(row / boxRows) * boxCols + Math.floor(col / boxCols)
}

function countBits(value) {
  let count = 0
  while (value !== 0) {
    value &= value - 1
    count += 1
  }
  return count
}

function countSolutions(givens, size, boxRows, boxCols, limit = 2) {
  const fullMask = (1 << size) - 1
  const rowMasks = Array(size).fill(0)
  const colMasks = Array(size).fill(0)
  const boxMasks = Array(size).fill(0)
  const cells = Array(size * size).fill(0)

  for (let index = 0; index < givens.length; index += 1) {
    const char = givens[index]
    if (char === '0') continue
    const digit = Number(char)
    if (!Number.isInteger(digit) || digit < 1 || digit > size) return 0
    const row = Math.floor(index / size)
    const col = index % size
    const box = boxIndex(row, col, boxRows, boxCols)
    const bit = 1 << (digit - 1)
    if ((rowMasks[row] & bit) !== 0 || (colMasks[col] & bit) !== 0 || (boxMasks[box] & bit) !== 0) return 0
    cells[index] = digit
    rowMasks[row] |= bit
    colMasks[col] |= bit
    boxMasks[box] |= bit
  }

  let solutions = 0
  const solve = () => {
    if (solutions >= limit) return
    let bestIndex = -1
    let bestMask = 0
    let bestChoices = size + 1
    for (let index = 0; index < cells.length; index += 1) {
      if (cells[index] !== 0) continue
      const row = Math.floor(index / size)
      const col = index % size
      const box = boxIndex(row, col, boxRows, boxCols)
      const mask = fullMask & ~(rowMasks[row] | colMasks[col] | boxMasks[box])
      const choices = countBits(mask)
      if (choices === 0) return
      if (choices < bestChoices) {
        bestIndex = index
        bestMask = mask
        bestChoices = choices
        if (choices === 1) break
      }
    }
    if (bestIndex === -1) {
      solutions += 1
      return
    }
    const row = Math.floor(bestIndex / size)
    const col = bestIndex % size
    const box = boxIndex(row, col, boxRows, boxCols)
    let candidates = bestMask
    while (candidates !== 0 && solutions < limit) {
      const bit = candidates & -candidates
      const digit = 32 - Math.clz32(bit)
      cells[bestIndex] = digit
      rowMasks[row] |= bit
      colMasks[col] |= bit
      boxMasks[box] |= bit
      solve()
      rowMasks[row] ^= bit
      colMasks[col] ^= bit
      boxMasks[box] ^= bit
      cells[bestIndex] = 0
      candidates ^= bit
    }
  }
  solve()
  return solutions
}

function validateSolution(solution, size, boxRows, boxCols) {
  if (solution.length !== size * size) throw new Error('解答长度不正确')
  const fullMask = (1 << size) - 1
  const rowMasks = Array(size).fill(0)
  const colMasks = Array(size).fill(0)
  const boxMasks = Array(size).fill(0)
  for (let index = 0; index < solution.length; index += 1) {
    const digit = Number(solution[index])
    if (!Number.isInteger(digit) || digit < 1 || digit > size) throw new Error('解答包含非法数字')
    const row = Math.floor(index / size)
    const col = index % size
    const box = boxIndex(row, col, boxRows, boxCols)
    const bit = 1 << (digit - 1)
    if ((rowMasks[row] & bit) !== 0 || (colMasks[col] & bit) !== 0 || (boxMasks[box] & bit) !== 0) {
      throw new Error('解答违反行、列或宫规则')
    }
    rowMasks[row] |= bit
    colMasks[col] |= bit
    boxMasks[box] |= bit
  }
  if ([...rowMasks, ...colMasks, ...boxMasks].some(mask => mask !== fullMask)) {
    throw new Error('解答不完整')
  }
}

function validatePuzzle(puzzle) {
  const { size, boxRows, boxCols, givens, solution } = puzzle
  validateSolution(solution, size, boxRows, boxCols)
  if (givens.length !== size * size) throw new Error(`${puzzle.id} 的提示盘长度不正确`)
  for (let index = 0; index < givens.length; index += 1) {
    if (givens[index] !== '0' && givens[index] !== solution[index]) {
      throw new Error(`${puzzle.id} 的提示与解答不一致`)
    }
  }
  const solutions = countSolutions(givens, size, boxRows, boxCols, 2)
  if (solutions !== 1) throw new Error(`${puzzle.id} 的解数量为 ${solutions}`)
}

function carve(solution, targetGivens, size, boxRows, boxCols, seed) {
  const total = size * size
  for (let attempt = 0; attempt < 128; attempt += 1) {
    const random = random32((seed + attempt * GOLDEN_RATIO) >>> 0)
    const order = shuffled(range(total), random)
    const cells = solution.split('')
    let givenCount = total
    for (const index of order) {
      if (givenCount === targetGivens) break
      const digit = cells[index]
      cells[index] = '0'
      if (countSolutions(cells.join(''), size, boxRows, boxCols, 2) === 1) givenCount -= 1
      else cells[index] = digit
    }
    if (givenCount === targetGivens) return cells.join('')
  }
  throw new Error(`无法在 ${seed} 下挖出 ${targetGivens} 个提示的唯一解题目`)
}

function createPuzzle({ id, title, size, boxRows, boxCols, difficulty, targetGivens, seed, base }, usedSolutions) {
  for (let attempt = 0; attempt < 256; attempt += 1) {
    const attemptSeed = (seed + attempt * GOLDEN_RATIO) >>> 0
    const solution = makeSolution(base, size, boxRows, boxCols, attemptSeed)
    if (usedSolutions.has(solution)) continue
    const givens = carve(
      solution,
      targetGivens,
      size,
      boxRows,
      boxCols,
      (attemptSeed ^ CARVE_SEED) >>> 0,
    )
    const puzzle = {
      id,
      title,
      size,
      boxRows,
      boxCols,
      difficulty,
      givens,
      solution,
    }
    validatePuzzle(puzzle)
    usedSolutions.add(solution)
    return puzzle
  }
  throw new Error(`${id} 无法生成不重复的解答`)
}

const miniBase = makeBaseSolution(4, 2)
const classicBase = makeBaseSolution(9, 3)
const usedSolutions = new Set()
const puzzles = []

for (let index = 0; index < 8; index += 1) {
  puzzles.push(createPuzzle({
    id: `mini-${String(index + 1).padStart(2, '0')}`,
    title: `四宫格入门 ${index + 1}`,
    size: 4,
    boxRows: 2,
    boxCols: 2,
    difficulty: 'easy',
    targetGivens: MINI_TARGET_GIVENS,
    seed: (MINI_SEED + index * 7919) >>> 0,
    base: miniBase,
  }, usedSolutions))
}

for (let index = 0; index < 24; index += 1) {
  const difficulty = CLASSIC_DIFFICULTIES[index % CLASSIC_DIFFICULTIES.length]
  puzzles.push(createPuzzle({
    id: `classic-${String(index + 1).padStart(2, '0')}`,
    title: `标准数独 ${index + 1}`,
    size: 9,
    boxRows: 3,
    boxCols: 3,
    difficulty,
    targetGivens: CLASSIC_TARGET_GIVENS[difficulty],
    seed: (CLASSIC_SEED + index * 7919) >>> 0,
    base: classicBase,
  }, usedSolutions))
}

const data = { version: 1, puzzles }
await writeFile(output, `${JSON.stringify(data, null, 2)}\n`)

const classicCounts = Object.fromEntries(
  Object.keys(CLASSIC_TARGET_GIVENS).map(difficulty => [
    difficulty,
    puzzles.filter(puzzle => puzzle.size === 9 && puzzle.difficulty === difficulty).length,
  ]),
)
console.log(
  `已生成 ${puzzles.length} 道数独题：四宫格 8 道，标准数独 easy ${classicCounts.easy}、normal ${classicCounts.normal}、challenge ${classicCounts.challenge}；逐题校验行列宫与唯一解。`,
)
