import { readFile, writeFile } from 'node:fs/promises'
import { resolve } from 'node:path'

const directory = resolve(import.meta.dirname, '../../content-src/data')
const read = async (name) => JSON.parse(await readFile(resolve(directory, name + '.json'), 'utf8'))
const write = async (name, value) => writeFile(resolve(directory, name + '.json'), JSON.stringify(value, null, 2) + '\n')
const games = await read('games')
const mode = (id, name, minimum, maximum, description) => ({ id, name, player_range: [minimum, maximum], description })
const chapters = {}
for (const game of games) {
  const modes = []
  if (game.id === 'garden') modes.push(mode('classic', '花园守家', 1, 1, '冒险、无尽、图鉴与花园小课堂'))
  else if (game.id === 'poetry') modes.push(mode('classic', '亲子抽背', 1, 1, '随机抽背、背诵路线、待复习与全库浏览'))
  else if (game.id === 'island') modes.push(mode('classic', '自由冒险', 2, 4, '掷骰子、答题、建房，点亮岛心'), mode('adventure', '章节冒险', 2, 4, '十二个短章节，每章三轮'))
  else if (['jungle', 'gomoku', 'military'].includes(game.id)) modes.push(mode('classic', '双人对弈', 2, 2, '面对面轮流下棋，支持回放'), mode('puzzle', '单人闯关', 1, 1, '预设局面、目标步数与清楚的讲解'))
  else if (game.id === 'workbook') modes.push(mode('classic', '自由练习', 1, 2, '一人练习或两人轮流，保留错题'), mode('adventure', '单元闯关', 1, 1, '基础、计算、应用三个单元'), mode('review', '错题复习', 1, 1, '复习自己的错题，不重复计入原局'))
  else if (game.id === 'memory') modes.push(mode('classic', '双人翻牌', 2, 2, '四个主题，轮流找到成对卡片'), mode('adventure', '单人闯关', 1, 1, '四个主题，各十二关，没有倒计时'))
  else modes.push(mode('classic', '双人挑战', 2, 2, '每人八题，看完讲解再换人'), mode('adventure', '单人闯关', 1, 1, '六段路线，每段四关'), mode('practice', '自由练习', 1, 1, '按自己的年龄慢慢练习'), mode('review', '错题复习', 1, 1, '把不熟悉的知识再学一遍'))
  game.modes = modes
  game.player_range = [Math.min(...modes.map(item => item.player_range[0])), Math.max(...modes.map(item => item.player_range[1]))]
  game.players = game.id === 'island' ? '2–4 人' : game.id === 'poetry' || game.id === 'garden' ? (game.id === 'poetry' ? '亲子' : '1 人') : game.player_range[1] > 1 ? '1–2 人' : '1 人'
  if (game.id === 'garden' || game.id === 'poetry') continue
  const count = { island:12, jungle:24, gomoku:30, military:24, memory:48, workbook:30 }[game.id] ?? 24
  chapters[game.id] = Array.from({ length: count }, (_, index) => ({
    id: index + 1,
    title: game.id === 'memory' ? `${['动物朋友','水果篮子','出行工具','生活用品'][Math.floor(index / 12)]} ${index % 12 + 1}` : game.id === 'workbook' ? `${['基础','计算','应用'][Math.floor(index / 10)]}练习 ${index % 10 + 1}` : `${['初次发现','熟练小能手','动脑想一想','勇敢试一试','新的发现','最后的挑战'][Math.floor(index / Math.ceil(count / 6))]} ${index % Math.ceil(count / 6) + 1}`,
    theme: game.id === 'memory' ? ['animals','fruits','vehicles','objects'][Math.floor(index / 12)] : '',
    family: game.id === 'workbook' ? ['foundation','calculation','application'][Math.floor(index / 10)] : '',
    seed: 1019 + index * 7919,
  }))
}
const pieces = (entries) => entries.map(([kind, side, position], index) => ({ id: `piece-${index}`, kind, side, position, revealed:true }))
const islandGoals = [['第一次环岛','turns',3],['答题小能手','correct',1],['建起第一套房子','houses',1],['知识小伙伴','correct',2],['欢迎新邻居','houses',2],['给房子升一级','upgrades',1],['收集岛心能量','correct',3],['一起挑战岛心','challenges',1],['热闹的小岛','houses',3],['知识大收获','correct',4],['建筑小达人','upgrades',2],['点亮智慧岛心','islandLevel',1]]
chapters.island = islandGoals.map(([title,goal,target],index)=>({id:index+1,title,goal,target,seed:2047+index*7919}))
const puzzles = { gomoku:[], jungle:[], military:[] }
for (let index = 0; index < 30; index++) {
  const direction = [[1,0],[0,1],[1,1],[1,-1]][index % 4]
  const origin = [3 + Math.floor(index / 4) % 5, direction[1] < 0 ? 10 : 3 + Math.floor(index / 8)]
  const cells = Array(225).fill(-1)
  const point = (step) => (origin[1] + direction[1] * step) * 15 + origin[0] + direction[0] * step
  const gap = index % 5
  for (let step = 0; step < 5; step++) if (step !== gap) cells[point(step)] = 0
  cells[point(-1)] = 1
  puzzles.gomoku.push({ id:index+1, title:'找到连成五颗的交叉点', hint:'沿着已有的四颗黑棋观察横、竖和斜线。', board:cells, goal:'win', targetSteps:1, line:[{to:point(gap)}] })
}
for (let index = 0; index < 24; index++) {
  const offset = Math.floor(index / 4)
  const kind = index % 4
  let entries, from, to, goal, hint
  if (kind === 0) {
    from = (offset % 2 ? 4 : 2) * 9 + 6; to = from + 1
    entries = [['rat',0,from],['elephant',1,to],['cat',1,8]]
    goal = 'capture'; hint = '在陆地上，老鼠可以吃大象。'
  } else if (kind === 1) {
    const row = [1,2,4,5,1,4][offset]; from = row * 9 + 2; to = row * 9 + 6
    entries = [[offset % 2 ? 'tiger':'lion',0,from],['cat',1,to],['elephant',1,8]]
    goal = 'capture'; hint = '河里没有老鼠时，狮子和老虎可以沿直线跳河。'
  } else if (kind === 2) {
    from = [19,9,37,45,19,29][offset]; to = [18,18,36,36,28,28][offset]
    entries = [['cat',0,from],['elephant',1,to],['lion',1,8]]
    goal = 'capture'; hint = '对方进入你的陷阱后，战力归零。'
  } else {
    from = [26,34,44,26,34,44][offset]; to = 35
    entries = [['dog',0,from],['rat',1,0]]
    goal = 'den'; hint = '点选自己的动物，走进右边的兽穴。'
  }
  puzzles.jungle.push({id:index+1,title:['小鼠的本领','跳过小河','陷阱帮帮忙','向兽穴出发'][kind],hint, pieces:pieces(entries),goal,targetSteps:1,line:[{from,to}]})
  const start = [5,15,25,30,40,50][offset]
  const targets = [start+1,start+1,start+1, start+5]
  const ranks = [['engineer','mine'],['bomb','commander'],['commander','general'],['engineer','flag']][kind]
  const armyEntries = pieces([[ranks[0],0,start],[ranks[1],1,targets[kind]],['flag',0,1],['engineer',1,58]])
  puzzles.military.push({id:index+1,title:['工兵排雷','炸弹的力量','认识棋子等级','夺取军旗'][kind],hint:['工兵可以排掉地雷。','炸弹与碰到的棋子一起离场。','司令比军长大。','走到对方军旗的位置就能获胜。'][kind],pieces:armyEntries,goal:kind===3?'flag':'capture',targetSteps:1,line:[{from:start,to:targets[kind]}]})
}
await write('games', games)
await write('chapters', chapters)
await write('puzzles', puzzles)
await write('version', { version:2, minAppVersionCode:2, maxAppVersionCode:2147483647 })
console.log('已写入模式、章节与固定局面内容。')
