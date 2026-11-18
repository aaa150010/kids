import { mkdir, writeFile } from 'node:fs/promises'
import { resolve } from 'node:path'

const questions = []
const number = (value) => String(Math.round(value * 10000) / 10000)
function add(age, family, index, prompt, visual, correct, explanation, topic, axis = 'math', alternatives) {
  const text = String(correct)
  const distractors = alternatives ?? [number(Number(correct) + 1), number(Number(correct) + 2)]
  const values = [text, ...distractors]
  const offset = (index + age) % 3
  const options = [...values.slice(offset), ...values.slice(0, offset)]
  questions.push({ id: `wb-${age}-${family}-${String(index + 1).padStart(3, '0')}`, age, family, topic, axis, prompt, visual, options, answer: (3 - offset) % 3, explanation, narration: prompt })
}

for (let age = 4; age <= 12; age += 1) {
  const max = age <= 5 ? 10 : age === 6 ? 20 : 100
  const pairs = []
  for (let total = 2; total <= max; total += 1) for (let right = 1; right < total; right += 1) pairs.push([total - right, right])
  for (let index = 0; index < 60; index += 1) {
    const type = index % 3
    const pairIndex = Math.floor(index / 3)
    const [left, right] = pairs[(pairIndex * (age <= 5 ? 2 : 29)) % pairs.length]
    if (age <= 7) {
      if (type === 0) add(age, 'calculation', index, `${left} 加 ${right} 等于多少？`, `${left} + ${right} = ?`, left + right, `${left} 和 ${right} 合起来是 ${left + right}，所以 ${left} + ${right} = ${left + right}。`, '加法')
      else if (type === 1) add(age, 'calculation', index, `${left + right} 减 ${right} 等于多少？`, `${left + right} − ${right} = ?`, left, `从 ${left + right} 里拿走 ${right}，还剩 ${left}。`, '减法')
      else add(age, 'calculation', index, `方框里应该填几？`, `□ + ${right} = ${left + right}`, left, `用总数减去已经知道的数：${left + right} − ${right} = ${left}。`, '填空计算')
    } else if (age <= 9) {
      const factor = 2 + pairIndex % 8, count = 2 + Math.floor(pairIndex / 8) + (age - 8) * 4
      if (type === 0) add(age, 'calculation', index, `${factor} 乘 ${count} 等于多少？`, `${factor} × ${count} = ?`, factor * count, `${count} 个 ${factor} 相加，得到 ${factor * count}。`, '乘法')
      else if (type === 1) add(age, 'calculation', index, `${factor * count} 除以 ${factor} 等于多少？`, `${factor * count} ÷ ${factor} = ?`, count, `因为 ${factor} × ${count} = ${factor * count}，所以商是 ${count}。`, '除法')
      else add(age, 'calculation', index, `先乘后加，结果是多少？`, `${factor} × ${count} + ${pairIndex + 1} = ?`, factor * count + pairIndex + 1, `先算 ${factor} × ${count} = ${factor * count}，再加 ${pairIndex + 1}，得到 ${factor * count + pairIndex + 1}。`, '混合运算')
    } else {
      const numerator = 1 + pairIndex % 7, denominator = 3 + Math.floor(pairIndex / 7) + age - 9
      if (type === 0) add(age, 'calculation', index, `同分母分数相加，结果是哪一个？`, `${numerator}/${denominator} + 1/${denominator} = ?`, `${numerator + 1}/${denominator}`, `分母相同，只把分子相加：${numerator} + 1 = ${numerator + 1}，分母仍是 ${denominator}。`, '分数', 'math', [`${numerator + 2}/${denominator}`, `${numerator}/${denominator}`])
      else if (type === 1) {
        const cents = 125 + pairIndex * 17, extra = 35 + age * 3
        add(age, 'calculation', index, `小数相加，结果是多少？`, `${number(cents / 100)} + ${number(extra / 100)} = ?`, number((cents + extra) / 100), `小数点对齐相加，相当于 ${cents} 个百分之一加 ${extra} 个百分之一，结果是 ${number((cents + extra) / 100)}。`, '小数', 'math', [number((cents + extra + 10) / 100), number((cents + extra - 10) / 100)])
      } else {
        const whole = 40 + pairIndex * 10, percent = [10, 20, 25, 50][pairIndex % 4]
        add(age, 'calculation', index, `${whole} 的 ${percent}% 是多少？`, `${whole} × ${percent}% = ?`, number(whole * percent / 100), `${percent}% 表示一百分之 ${percent}，${whole} × ${percent} ÷ 100 = ${number(whole * percent / 100)}。`, '百分数')
      }
    }
  }
  for (let index = 0; index < 40; index += 1) {
    if (age <= 5) {
      const [left, right] = pairs[index]
      const subtraction = index % 2 === 1
      const total = subtraction ? left : left + right
      add(age, 'application', index, subtraction ? `盒里有 ${left + right} 块积木，拿走 ${right} 块，还剩几块？` : `小熊有 ${left} 块积木，朋友又送来 ${right} 块，现在一共有几块？`, subtraction ? `🧱 ${left + right} − ${right}` : `🧱 ${left} + ${right}`, total, subtraction ? `原来有 ${left + right} 块，拿走 ${right} 块，${left + right} − ${right} = ${left}。` : `把两部分合起来：${left} + ${right} = ${left + right} 块。`, '分物品')
    } else if (age <= 7) {
      const cost = 2 + index % 9, extra = 1 + Math.floor(index / 9)
      if (index % 2 === 0) add(age, 'application', index, `铅笔 ${cost} 元，橡皮 ${extra} 元，两样一共多少元？`, `✏️ ${cost} 元 + 🧽 ${extra} 元`, cost + extra, `把两件文具的价格相加：${cost} + ${extra} = ${cost + extra} 元。`, '购物钱币')
      else {
        const paid = cost + extra + 5
        add(age, 'application', index, `一本本子 ${cost} 元，付了 ${paid} 元，应找回多少元？`, `📒 ${cost} 元 · 付 ${paid} 元`, paid - cost, `付的钱减去价格就是找零：${paid} − ${cost} = ${paid - cost} 元。`, '购物找零')
      }
    } else if (age <= 9) {
      const each = 2 + index % 8, groups = 2 + Math.floor(index / 8), extra = age - 6
      if (index % 2 === 0) add(age, 'application', index, `每盒有 ${each} 支笔，买了 ${groups} 盒，又拿了 ${extra} 支，一共有几支？`, `📦 ${groups} 盒 × ${each} 支 + ${extra} 支`, each * groups + extra, `先算整盒：${each} × ${groups} = ${each * groups}；再加零散的 ${extra} 支，一共 ${each * groups + extra} 支。`, '多步应用')
      else add(age, 'application', index, `${each * groups} 颗糖平均分给 ${groups} 位小朋友，每人几颗？`, `🍬 ${each * groups} 颗 ÷ ${groups} 人`, each, `平均分用除法：${each * groups} ÷ ${groups} = ${each} 颗。`, '平均分')
    } else {
      const length = 4 + Math.floor(index / 4), width = 2 + index % 4
      if (index % 4 === 0) add(age, 'application', index, `长方形花圃长 ${length} 米、宽 ${width} 米，面积是多少平方米？`, `▭ 长 ${length} 米 · 宽 ${width} 米`, length * width, `长方形面积等于长乘宽：${length} × ${width} = ${length * width} 平方米。`, '面积')
      else if (index % 4 === 1) add(age, 'application', index, `长方形相框长 ${length} 厘米、宽 ${width} 厘米，一圈是多少厘米？`, `▭ 长 ${length} 厘米 · 宽 ${width} 厘米`, (length + width) * 2, `周长等于两条长和两条宽的总和：（${length} + ${width}）× 2 = ${(length + width) * 2} 厘米。`, '周长')
      else if (index % 4 === 2) add(age, 'application', index, `一根彩带长 ${number(length / 10)} 米，是多少厘米？`, `📏 ${number(length / 10)} 米 = ? 厘米`, length * 10, `1 米等于 100 厘米，所以 ${number(length / 10)} × 100 = ${length * 10} 厘米。`, '单位换算')
      else {
        const price = length * 20, discount = 10 + width * 5
        add(age, 'application', index, `玩具原价 ${price} 元，优惠 ${discount}%，便宜了多少元？`, `🧸 ${price} 元 · 优惠 ${discount}%`, number(price * discount / 100), `便宜的钱等于原价乘优惠比例：${price} × ${discount}% = ${number(price * discount / 100)} 元。`, '百分数应用')
      }
    }
  }
  const shapes = ['🔺', '🟦', '🟢', '🔶', '⭐']
  for (let index = 0; index < 10; index += 1) {
    const first = shapes[index % 5], second = shapes[(index % 5 + 1 + Math.floor(index / 5)) % 5]
    const third = shapes.find((shape) => shape !== first && shape !== second)
    const visual = age >= 8 ? `${first} ${first} ${second} ${second} ${first} ${first} □` : `${first} ${second} ${first} □`
    add(age, 'foundation', index + 30, '看看图形怎样重复，方框里应该放哪一个？', visual, second, age >= 8 ? `两个 ${first}、两个 ${second} 为一组重复。已经有两个 ${first}，接着应该是 ${second}。` : `${first} 和 ${second} 交替出现，所以下一个是 ${second}。`, '图形规律', 'logic', [first, third])
  }
  for (let index = 0; index < 30; index += 1) {
    const group = Math.floor(index / 3)
    if (index % 3 === 0) {
      const left = age <= 5 ? group + 1 : age <= 7 ? group * 7 + 12 : age <= 9 ? group * 13 + 51 : number((group * 17 + 31) / 10)
      const right = Number(left) + (group % 3 - 1) * (age <= 7 ? 1 : 3)
      const symbol = Number(left) > right ? '>' : Number(left) < right ? '<' : '='
      add(age, 'foundation', index, `比较两个数，方框里应该填什么符号？`, `${left} □ ${number(right)}`, symbol, `${left} ${symbol === '>' ? '大于' : symbol === '<' ? '小于' : '等于'} ${number(right)}，所以填 ${symbol}。`, '比较大小', 'math', ['>', '<', '='].filter((item) => item !== symbol))
    } else if (index % 3 === 1) {
      const start = age <= 5 ? group < 5 ? group : 15 - group : group + age
      const step = age <= 5 ? group < 5 ? 1 : -1 : group % 2 === 0 ? 2 : 5
      const values = [0, 1, 2].map((offset) => start + step * offset)
      const correct = start + step * 3
      add(age, 'foundation', index, '找一找，每次怎样变化？下一个数是多少？', `${values.join('、')}、□`, correct, `每次${step > 0 ? '增加' : '减少'} ${Math.abs(step)}，所以下一个数是 ${correct}。`, '数字规律', 'logic')
    } else if (age <= 5) {
      const count = group + 1
      add(age, 'foundation', index, '数一数，纸上有几颗星星？', '⭐'.repeat(count), count, `从 1 开始，一个一个数，一共有 ${count} 颗星星。`, '数数')
    } else if (age <= 7) {
      const start = group + 1
      add(age, 'foundation', index, `现在 ${start} 点，过 1 小时是几点？`, `🕐 ${start}:00 + 1 小时`, start + 1, `时针向前走一大格，${start} 点再过 1 小时是 ${start + 1} 点。`, '认识时间')
    } else {
      const hours = group + 1
      add(age, 'foundation', index, `${hours} 小时等于多少分钟？`, `🕐 ${hours} 小时 = ? 分钟`, hours * 60, `1 小时等于 60 分钟，所以 ${hours} × 60 = ${hours * 60} 分钟。`, '时间单位')
    }
  }
}
const output = resolve(import.meta.dirname, '../apps/workbook/src/data')
await mkdir(output, { recursive: true })
await writeFile(resolve(output, 'questions.json'), JSON.stringify(questions, null, 2) + '\n')
console.log(`Created ${questions.length} static workbook questions.`)
