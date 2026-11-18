import { readFile, writeFile } from 'node:fs/promises'
import { resolve } from 'node:path'

const root = resolve(import.meta.dirname, '../..')
const content = resolve(root, 'content-src/data')
const garden = JSON.parse(await readFile(resolve(content, 'garden.json'), 'utf8'))
const playable = Object.keys(garden.plants).filter(kind => !['imitater', 'explodenut'].includes(kind))
const speeds = { normal: .23, flag: .30, cone: .23, bucket: .23, door: .23, newspaper: .23, football: .66, pole: .66, dancer: .30, backup: .30, ducky: .23, snorkel: .30, zomboni: .25, bobsled: .60, dolphin: .66, jack: .30, balloon: .32, digger: .40, pogo: .45, bungee: 0, ladder: .50, catapult: .15, gargantuar: .16, imp: .40, yeti: .40, boss: 0 }
const body = { pole: 500, dancer: 500, dolphin: 500, jack: 500, ladder: 500, gargantuar: 3000, catapult: 850, bungee: 450, zomboni: 1350, yeti: 1350, boss: 40000 }
const armor = { cone: 370, bucket: 1100, football: 1400, digger: 100, bobsled: 300 }
const shields = { door: 1100, newspaper: 150, ladder: 500 }
const zombies = Object.fromEntries(Object.keys(speeds).map(kind => [kind, { body: body[kind] || 270, armor: armor[kind] || 0, shield: shields[kind] || 0, speed: speeds[kind], biteDamage: kind === 'gargantuar' ? 1800 : 20, biteInterval: .2, canLoseParts: !['zomboni', 'catapult', 'gargantuar', 'boss', 'bobsled'].includes(kind) }]))
const plants = Object.fromEntries(Object.entries(garden.plants).map(([kind, definition]) => [kind, { ...definition, cooldownSeconds: definition.cooldown / 100, intervalSeconds: (definition.interval || 150) / 100, damage: 20, range: 9 }]))
for (const kind of ['sunflower', 'twinsunflower', 'sunshroom', 'marigold']) plants[kind].intervalSeconds = 24
for (const kind of ['peashooter', 'repeater', 'gatlingpea', 'snowpea', 'threepeater', 'splitpea', 'cactus', 'seashroom', 'puffshroom', 'scaredyshroom']) plants[kind].intervalSeconds = 1.45
for (const kind of ['cabbagepult', 'kernelpult', 'melonpult', 'wintermelon']) plants[kind].intervalSeconds = 2.85
Object.assign(plants.puffshroom, { range: 3 })
Object.assign(plants.fumeshroom, { range: 3, intervalSeconds: 1.45 })
Object.assign(plants.gloomshroom, { range: 1.5, intervalSeconds: 2 })
Object.assign(plants.cattail, { intervalSeconds: 1.45 })
Object.assign(plants.cobcannon, { intervalSeconds: 34.75 })
Object.assign(plants.potatomine, { armSeconds: 15 })
Object.assign(plants.chomper, { digestSeconds: 40 })
const rules = {
  schemaVersion: 2, playable, plants, zombies,
  board: { width: 800, height: 600, left: 40, top: 80, cellWidth: 80, landCellHeight: 100, waterCellHeight: 83.333333, columns: 9 },
  timing: { firstWave: 18, waveInterval: 22, skySun: 9, sunLifetime: 10, headlessLifetime: 3, mowerSpeed: 7, projectileSpeed: 4.1, graveInterval: 35, conveyorInterval: 5 },
  upgrades: { gatlingpea: 'repeater', twinsunflower: 'sunflower', wintermelon: 'melonpult', gloomshroom: 'fumeshroom', cattail: 'lilypad', goldmagnet: 'magnetshroom', spikerock: 'spikeweed', cobcannon: 'kernelpult' },
  mushrooms: ['puffshroom', 'sunshroom', 'fumeshroom', 'hypnoshroom', 'scaredyshroom', 'iceshroom', 'doomshroom', 'seashroom', 'magnetshroom', 'gloomshroom'],
  decks: {
    day: ['peashooter', 'sunflower', 'wallnut', 'cherrybomb', 'potatomine', 'snowpea', 'repeater', 'chomper'],
    night: ['puffshroom', 'sunshroom', 'fumeshroom', 'gravebuster', 'hypnoshroom', 'scaredyshroom', 'wallnut', 'cherrybomb'],
    pool: ['lilypad', 'sunflower', 'peashooter', 'wallnut', 'seashroom', 'tanglekelp', 'snowpea', 'cherrybomb'],
    fog: ['lilypad', 'puffshroom', 'sunshroom', 'seashroom', 'plantern', 'blover', 'cactus', 'wallnut'],
    roof: ['flowerpot', 'sunflower', 'cabbagepult', 'kernelpult', 'melonpult', 'wallnut', 'umbrella', 'cherrybomb'],
  },
}
for (const [levelId, level] of Object.entries(garden.levels)) {
  level.allowedPlants = playable.filter(kind => {
    if (['lilypad', 'tanglekelp', 'seashroom', 'cattail'].includes(kind)) return ['pool', 'fog'].includes(level.environment)
    if (kind === 'gravebuster') return level.environment === 'night'
    if (kind === 'plantern') return level.environment === 'fog'
    if (kind === 'flowerpot') return level.environment === 'roof'
    if (['spikeweed', 'spikerock'].includes(kind)) return level.environment !== 'roof'
    return true
  })
  level.levelId = Number(levelId)
}
await writeFile(resolve(content, 'garden-rules.json'), JSON.stringify(rules) + '\n')
await writeFile(resolve(content, 'garden.json'), JSON.stringify(garden) + '\n')
console.log(`Authored ${playable.length} plant rules, ${Object.keys(zombies).length} zombie rules and 50 allowed-plant sets.`)
