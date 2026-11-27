import { createHash } from 'node:crypto'
import { readFile, writeFile } from 'node:fs/promises'
import { resolve } from 'node:path'

const root = resolve(import.meta.dirname, '../..')
const triviaPath = resolve(root, 'content-src/data/trivia.json')
const expectedTotal = 160
const expectedExtraPerAge = 12
const expectedAges = [8, 9, 10, 11, 12]
const requiredFields = ['id', 'age', 'prompt', 'options', 'answer', 'explanation', 'narration', 'skill']
const allowedSkills = new Set([
  '科学启蒙',
  '中国文化',
  '地理天气',
  '安全健康',
  '动物朋友',
  '自然观察',
  '生活常识'
])
const baselineCount = 100
const baselineSha256 = 'b882c5cf6a91e09c5502a03cb656bfae7beeba1f0867b56d90cf4896542c94a8'

const extraQuestions = [
  {
    id: 'trivia8-013',
    age: 8,
    prompt: '手被热汤烫到后，第一步应该怎样做？',
    options: ['马上涂上牙膏', '用力揉搓烫伤处', '立即用流动的凉水冲洗'],
    answer: 2,
    explanation: '应先用流动的凉水持续降温，再请大人查看。不要涂牙膏，也不要揉搓伤处。',
    narration: '手被热汤烫到后，第一步应该怎样做？',
    skill: '安全健康'
  },
  {
    id: 'trivia8-014',
    age: 8,
    prompt: '大多数种子发芽需要水分和空气，还通常需要什么？',
    options: ['适宜的温度', '强烈的阳光', '浓盐水'],
    answer: 0,
    explanation: '大多数种子在水分、空气和适宜温度下就能发芽，不一定需要强光。',
    narration: '大多数种子发芽需要水分和空气，还通常需要什么？',
    skill: '科学启蒙'
  },
  {
    id: 'trivia8-015',
    age: 8,
    prompt: '清晨草叶上的小水珠通常是怎样形成的？',
    options: ['植物从叶尖挤出水分', '空气中的水汽遇冷凝成', '水珠从云里直接落下'],
    answer: 1,
    explanation: '夜晚气温下降，空气中的水汽在草叶表面凝结，形成露水。',
    narration: '清晨草叶上的小水珠通常是怎样形成的？',
    skill: '自然观察'
  },
  {
    id: 'trivia8-016',
    age: 8,
    prompt: '看地图时，通常把哪个方向画在上方？',
    options: ['南方', '西方', '北方'],
    answer: 2,
    explanation: '地图通常采用上北下南、左西右东的方向约定。',
    narration: '看地图时，通常把哪个方向画在上方？',
    skill: '地理天气'
  },
  {
    id: 'trivia8-017',
    age: 8,
    prompt: '北宋时期发明活字印刷术的是谁？',
    options: ['蔡伦', '毕昇', '张衡'],
    answer: 1,
    explanation: '北宋的毕昇发明了泥活字印刷术，蔡伦改进的是造纸术。',
    narration: '北宋时期发明活字印刷术的是谁？',
    skill: '中国文化'
  },
  {
    id: 'trivia8-018',
    age: 8,
    prompt: '发现买来的面包已经过期，最合适的做法是什么？',
    options: ['保留购物凭证，请家长联系商家处理', '闻起来没坏就继续吃', '悄悄放回货架'],
    answer: 0,
    explanation: '过期食品不应继续食用，应保留凭证并请家长联系商家处理。',
    narration: '发现买来的面包已经过期，最合适的做法是什么？',
    skill: '生活常识'
  },
  {
    id: 'trivia8-019',
    age: 8,
    prompt: '哪种动物小时候叫蝌蚪？',
    options: ['蝴蝶', '青蛙', '麻雀'],
    answer: 1,
    explanation: '青蛙的幼体叫蝌蚪，蝌蚪长大后长出四肢，变成青蛙。',
    narration: '哪种动物小时候叫蝌蚪？',
    skill: '动物朋友'
  },
  {
    id: 'trivia8-020',
    age: 8,
    prompt: '中国大部分地区位于哪个温度带？',
    options: ['热带', '南温带', '北温带'],
    answer: 2,
    explanation: '中国大部分地区位于北温带，南部部分地区位于热带，没有寒带。',
    narration: '中国大部分地区位于哪个温度带？',
    skill: '地理天气'
  },
  {
    id: 'trivia8-021',
    age: 8,
    prompt: '把食盐放进水里搅拌后，盐粒看不见了，这是为什么？',
    options: ['食盐溶解在水里', '食盐完全消失了', '食盐变成了空气'],
    answer: 0,
    explanation: '食盐溶解后变成肉眼看不见的微粒，均匀分散在水里，并没有消失。',
    narration: '把食盐放进水里搅拌后，盐粒看不见了，这是为什么？',
    skill: '科学启蒙'
  },
  {
    id: 'trivia8-022',
    age: 8,
    prompt: '骑自行车时，保护头部最有效的做法是什么？',
    options: ['戴普通遮阳帽', '佩戴大小合适的安全头盔', '骑得越快越安全'],
    answer: 1,
    explanation: '安全头盔能缓冲撞击，保护头部。普通帽子不能代替头盔。',
    narration: '骑自行车时，保护头部最有效的做法是什么？',
    skill: '安全健康'
  },
  {
    id: 'trivia8-023',
    age: 8,
    prompt: '“床前明月光，疑是地上霜”的作者是谁？',
    options: ['杜甫', '王维', '李白'],
    answer: 2,
    explanation: '这两句出自李白的《静夜思》。',
    narration: '床前明月光，疑是地上霜的作者是谁？',
    skill: '中国文化'
  },
  {
    id: 'trivia8-024',
    age: 8,
    prompt: '正在生长的向日葵花盘，白天通常会朝哪个方向转动？',
    options: ['太阳', '月亮', '背光处'],
    answer: 0,
    explanation: '幼嫩的花盘会随太阳方向转动，成熟后通常会固定朝向东方。',
    narration: '正在生长的向日葵花盘，白天通常会朝哪个方向转动？',
    skill: '自然观察'
  },
  {
    id: 'trivia9-012',
    age: 9,
    prompt: '在京剧中，红脸脸谱通常用来表现怎样的人物？',
    options: ['阴险狡猾', '胆小糊涂', '忠勇正直'],
    answer: 2,
    explanation: '京剧红脸多象征忠勇、正直；脸谱含义会因剧目和角色而略有不同。',
    narration: '在京剧中，红脸脸谱通常用来表现怎样的人物？',
    skill: '中国文化'
  },
  {
    id: 'trivia9-013',
    age: 9,
    prompt: '发生日食时，哪个天体挡住了太阳射向地球的光？',
    options: ['月球', '地球', '火星'],
    answer: 0,
    explanation: '月球运行到太阳和地球之间，挡住一部分或全部阳光，就形成日食。',
    narration: '发生日食时，哪个天体挡住了太阳射向地球的光？',
    skill: '科学启蒙'
  },
  {
    id: 'trivia9-014',
    age: 9,
    prompt: '长江最终注入哪个海？',
    options: ['黄海', '东海', '南海'],
    answer: 1,
    explanation: '长江自西向东流，在上海附近注入东海。',
    narration: '长江最终注入哪个海？',
    skill: '地理天气'
  },
  {
    id: 'trivia9-015',
    age: 9,
    prompt: '发现有人触电时，孩子首先应该怎么做？',
    options: ['直接用手把触电者拉开', '往触电者身上泼水', '大声呼救并请大人断开电源'],
    answer: 2,
    explanation: '不要直接接触触电者或泼水，应立即呼救，请大人安全切断电源。',
    narration: '发现有人触电时，孩子首先应该怎么做？',
    skill: '安全健康'
  },
  {
    id: 'trivia9-016',
    age: 9,
    prompt: '蝴蝶的一生通常会经历哪几个阶段？',
    options: ['卵、雏鸟、成虫', '卵、幼虫、蛹、成虫', '幼虫、蛹、种子'],
    answer: 1,
    explanation: '蝴蝶经历卵、幼虫、蛹、成虫四个阶段，属于完全变态发育。',
    narration: '蝴蝶的一生通常会经历哪几个阶段？',
    skill: '动物朋友'
  },
  {
    id: 'trivia9-017',
    age: 9,
    prompt: '使用燃气灶时闻到燃气味，首先应该怎样做？',
    options: ['不碰电器开关，关闭阀门并请大人处理', '马上点火检查漏气位置', '先打开油烟机再找原因'],
    answer: 0,
    explanation: '不要开关电器或点火，应先关闭燃气阀门、开窗通风，并请大人处理。',
    narration: '使用燃气灶时闻到燃气味，首先应该怎样做？',
    skill: '生活常识'
  },
  {
    id: 'trivia9-018',
    age: 9,
    prompt: '秋天许多树叶变黄，主要是因为叶片中的什么减少了？',
    options: ['水分', '叶绿素', '纤维'],
    answer: 1,
    explanation: '气温降低、日照变短后，叶绿素逐渐减少，其他色素显现出来，叶片便发黄。',
    narration: '秋天许多树叶变黄，主要是因为叶片中的什么减少了？',
    skill: '自然观察'
  },
  {
    id: 'trivia9-019',
    age: 9,
    prompt: '农历九月初九是哪个传统节日？',
    options: ['元宵节', '七夕节', '重阳节'],
    answer: 2,
    explanation: '重阳节在农历九月初九，民间有登高、赏菊等习俗。',
    narration: '农历九月初九是哪个传统节日？',
    skill: '中国文化'
  },
  {
    id: 'trivia9-020',
    age: 9,
    prompt: '京杭大运河南北两端通常指哪两座城市？',
    options: ['北京和杭州', '西安和洛阳', '南京和上海'],
    answer: 0,
    explanation: '京杭大运河北起北京，南到杭州，是中国古代重要的运河。',
    narration: '京杭大运河南北两端通常指哪两座城市？',
    skill: '中国文化'
  },
  {
    id: 'trivia9-021',
    age: 9,
    prompt: '风通常是由什么引起的？',
    options: ['月亮推动空气', '空气受热不均形成流动', '树木摇晃产生'],
    answer: 1,
    explanation: '不同地方空气受热程度不同，气压有高有低，空气流动起来就形成了风。',
    narration: '风通常是由什么引起的？',
    skill: '科学启蒙'
  },
  {
    id: 'trivia9-022',
    age: 9,
    prompt: '剧烈运动前，怎样做有助于减少受伤？',
    options: ['直接全力冲刺', '完全屏住呼吸', '先做充分热身'],
    answer: 2,
    explanation: '充分热身能让身体逐渐进入运动状态，降低拉伤等风险。',
    narration: '剧烈运动前，怎样做有助于减少受伤？',
    skill: '安全健康'
  },
  {
    id: 'trivia9-023',
    age: 9,
    prompt: '海龟生活在海里，它主要用什么呼吸？',
    options: ['肺', '鳃', '吸盘'],
    answer: 0,
    explanation: '海龟是爬行动物，用肺呼吸，需要浮到水面换气。',
    narration: '海龟生活在海里，它主要用什么呼吸？',
    skill: '动物朋友'
  },
  {
    id: 'trivia10-012',
    age: 10,
    prompt: '在大人指导下使用灭火器时，喷嘴应该对准火焰的哪里？',
    options: ['火焰顶部', '火焰根部', '烟雾最浓处'],
    answer: 1,
    explanation: '灭火时通常对准燃烧物根部左右扫射，同时要确保自己处在安全位置。',
    narration: '在大人指导下使用灭火器时，喷嘴应该对准火焰的哪里？',
    skill: '安全健康'
  },
  {
    id: 'trivia10-013',
    age: 10,
    prompt: '帝企鹅在南极冬季常用什么方法抵御严寒？',
    options: ['挖洞冬眠', '潜入深海睡觉', '挤在一起互相取暖'],
    answer: 2,
    explanation: '帝企鹅会聚成密集的群体，轮流移动到较暖的内侧。',
    narration: '帝企鹅在南极冬季常用什么方法抵御严寒？',
    skill: '动物朋友'
  },
  {
    id: 'trivia10-014',
    age: 10,
    prompt: '切过生肉的菜板，使用后应该怎样处理？',
    options: ['与熟食分开并清洗晾干', '直接接着切水果', '用抹布擦一下收起来'],
    answer: 0,
    explanation: '生肉可能带有细菌，生熟菜板应分开，使用后要清洗并晾干。',
    narration: '切过生肉的菜板，使用后应该怎样处理？',
    skill: '生活常识'
  },
  {
    id: 'trivia10-015',
    age: 10,
    prompt: '《西游记》中孙悟空最常使用的兵器是什么？',
    options: ['九齿钉耙', '金箍棒', '青龙偃月刀'],
    answer: 1,
    explanation: '孙悟空使用金箍棒；九齿钉耙是猪八戒的兵器。',
    narration: '西游记中孙悟空最常使用的兵器是什么？',
    skill: '中国文化'
  },
  {
    id: 'trivia10-016',
    age: 10,
    prompt: '汽车后视镜让我们看到车后的景象，主要利用了光的什么现象？',
    options: ['折射', '蒸发', '反射'],
    answer: 2,
    explanation: '平面镜通过反射光线成像，所以后视镜能让我们看到后方。',
    narration: '汽车后视镜让我们看到车后的景象，主要利用了光的什么现象？',
    skill: '科学启蒙'
  },
  {
    id: 'trivia10-017',
    age: 10,
    prompt: '大雁排成“人”字形飞行，主要有什么好处？',
    options: ['减少空气阻力，节省体力', '让叫声传得更远', '避免被云挡住'],
    answer: 0,
    explanation: '排成队形飞行可以减少空气阻力，后面的鸟也能借助前方产生的上升气流。',
    narration: '大雁排成人字形飞行，主要有什么好处？',
    skill: '自然观察'
  },
  {
    id: 'trivia10-018',
    age: 10,
    prompt: '中国地势的总体特征通常怎样描述？',
    options: ['东高西低，呈阶梯状分布', '西高东低，呈阶梯状分布', '南高北低，完全平坦'],
    answer: 1,
    explanation: '中国地势西高东低，大致呈三级阶梯分布。',
    narration: '中国地势的总体特征通常怎样描述？',
    skill: '地理天气'
  },
  {
    id: 'trivia10-019',
    age: 10,
    prompt: '《三国演义》的作者通常认为是哪位？',
    options: ['施耐庵', '吴承恩', '罗贯中'],
    answer: 2,
    explanation: '《三国演义》通常署名罗贯中；施耐庵写《水浒传》，吴承恩写《西游记》。',
    narration: '三国演义的作者通常认为是哪位？',
    skill: '中国文化'
  },
  {
    id: 'trivia10-020',
    age: 10,
    prompt: '夏天运动出汗后，补充水分较合适的做法是什么？',
    options: ['少量多次喝白开水', '一次喝很多冰水', '一直忍着不喝水'],
    answer: 0,
    explanation: '出汗后应少量多次补水，避免一次大量喝冰水。',
    narration: '夏天运动出汗后，补充水分较合适的做法是什么？',
    skill: '安全健康'
  },
  {
    id: 'trivia10-021',
    age: 10,
    prompt: '蜜蜂发现蜜源后，常用什么方式告诉同伴位置？',
    options: ['发出闪光', '跳舞蹈', '敲击蜂巢'],
    answer: 1,
    explanation: '蜜蜂会用不同的舞蹈方向和摆动方式传递蜜源位置的信息。',
    narration: '蜜蜂发现蜜源后，常用什么方式告诉同伴位置？',
    skill: '动物朋友'
  },
  {
    id: 'trivia10-022',
    age: 10,
    prompt: '水在自然界常见的三种状态是什么？',
    options: ['红色、蓝色、绿色', '甜、咸、酸', '固态、液态、气态'],
    answer: 2,
    explanation: '水可以是冰这样的固态、水这样的液态，也可以是水蒸气这样的气态。',
    narration: '水在自然界常见的三种状态是什么？',
    skill: '科学启蒙'
  },
  {
    id: 'trivia10-023',
    age: 10,
    prompt: '为什么不能用湿手插拔电源插头？',
    options: ['水会导电，容易发生触电', '插头会变得更快', '电器会多用一度电'],
    answer: 0,
    explanation: '水能导电，湿手接触插头或插座会增加触电危险。',
    narration: '为什么不能用湿手插拔电源插头？',
    skill: '生活常识'
  },
  {
    id: 'trivia11-011',
    age: 11,
    prompt: '《本草纲目》的作者是谁？',
    options: ['祖冲之', '李时珍', '徐霞客'],
    answer: 1,
    explanation: '《本草纲目》是明代医药学家李时珍编著的药物学著作。',
    narration: '本草纲目的作者是谁？',
    skill: '中国文化'
  },
  {
    id: 'trivia11-012',
    age: 11,
    prompt: '空气中体积占比最大的气体是什么？',
    options: ['氧气', '二氧化碳', '氮气'],
    answer: 2,
    explanation: '氮气约占空气体积的五分之四，是空气里含量最多的气体。',
    narration: '空气中体积占比最大的气体是什么？',
    skill: '科学启蒙'
  },
  {
    id: 'trivia11-013',
    age: 11,
    prompt: '长江发源于哪个高原？',
    options: ['青藏高原', '黄土高原', '云贵高原'],
    answer: 0,
    explanation: '长江发源于青藏高原的唐古拉山脉一带。',
    narration: '长江发源于哪个高原？',
    skill: '地理天气'
  },
  {
    id: 'trivia11-014',
    age: 11,
    prompt: '发现有人出现轻度中暑，首先应该怎样做？',
    options: ['让他继续晒太阳', '移到阴凉通风处并请大人帮忙', '给他盖上厚被子'],
    answer: 1,
    explanation: '应尽快移到阴凉通风处，少量补水并请大人帮助；情况严重时及时就医。',
    narration: '发现有人出现轻度中暑，首先应该怎样做？',
    skill: '安全健康'
  },
  {
    id: 'trivia11-015',
    age: 11,
    prompt: '含羞草的叶片被触碰后会合拢，这说明植物能够怎样？',
    options: ['进行光合作用', '像动物一样行走', '对外界刺激作出反应'],
    answer: 2,
    explanation: '植物也能感受外界刺激并作出反应，含羞草合拢叶片就是常见例子。',
    narration: '含羞草的叶片被触碰后会合拢，这说明植物能够怎样？',
    skill: '自然观察'
  },
  {
    id: 'trivia11-016',
    age: 11,
    prompt: '珊瑚礁主要由哪种生物分泌的石灰质骨骼长期堆积形成？',
    options: ['珊瑚虫', '海星', '水母'],
    answer: 0,
    explanation: '珊瑚虫分泌石灰质骨骼，经过漫长岁月堆积成珊瑚礁。',
    narration: '珊瑚礁主要由哪种生物分泌的石灰质骨骼长期堆积形成？',
    skill: '动物朋友'
  },
  {
    id: 'trivia11-017',
    age: 11,
    prompt: '拨打119报警时，最重要是说清哪些信息？',
    options: ['自己的星座和爱好', '详细地址和火情', '当天的风速预报'],
    answer: 1,
    explanation: '报警要讲清失火地点、火势和是否有人员被困等信息，并听从接线员指引。',
    narration: '拨打119报警时，最重要是说清哪些信息？',
    skill: '生活常识'
  },
  {
    id: 'trivia11-018',
    age: 11,
    prompt: '《天工开物》的作者是谁？',
    options: ['明成祖', '郑和', '宋应星'],
    answer: 2,
    explanation: '《天工开物》是明代宋应星编著的科学技术著作。',
    narration: '天工开物的作者是谁？',
    skill: '中国文化'
  },
  {
    id: 'trivia11-019',
    age: 11,
    prompt: '把小苏打加入白醋会冒泡，这些气泡主要是什么气体？',
    options: ['二氧化碳', '氧气', '氮气'],
    answer: 0,
    explanation: '小苏打和白醋反应会产生二氧化碳，所以看到气泡。',
    narration: '把小苏打加入白醋会冒泡，这些气泡主要是什么气体？',
    skill: '科学启蒙'
  },
  {
    id: 'trivia11-020',
    age: 11,
    prompt: '大风把大量沙尘卷到空中、使能见度明显下降的天气现象叫什么？',
    options: ['大雾', '沙尘暴', '霜冻'],
    answer: 1,
    explanation: '沙尘暴会带来大量沙尘，使空气浑浊、能见度降低。',
    narration: '大风把大量沙尘卷到空中、使能见度明显下降的天气现象叫什么？',
    skill: '地理天气'
  },
  {
    id: 'trivia11-021',
    age: 11,
    prompt: '发现同伴落水，未成年人最合适的做法是什么？',
    options: ['立即跳下水把他拉上岸', '独自离开不告诉任何人', '大声呼救并寻找成年人或漂浮物帮助'],
    answer: 2,
    explanation: '未成年人不要贸然下水，应大声呼救、寻找成年人帮助，并可在岸上递漂浮物。',
    narration: '发现同伴落水，未成年人最合适的做法是什么？',
    skill: '安全健康'
  },
  {
    id: 'trivia11-022',
    age: 11,
    prompt: '蝙蝠在黑暗环境中主要依靠什么判断前方障碍和猎物位置？',
    options: ['回声定位', '靠眼睛看很远', '靠地面震动'],
    answer: 0,
    explanation: '蝙蝠发出超声波，再根据回声判断物体位置和距离，这叫回声定位。',
    narration: '蝙蝠在黑暗环境中主要依靠什么判断前方障碍和猎物位置？',
    skill: '动物朋友'
  },
  {
    id: 'trivia12-011',
    age: 12,
    prompt: '光从空气斜射入水中时，传播方向通常会怎样？',
    options: ['完全停止', '沿原方向不变', '发生偏折'],
    answer: 2,
    explanation: '光从一种介质斜射入另一种介质时通常会发生折射，传播方向改变。',
    narration: '光从空气斜射入水中时，传播方向通常会怎样？',
    skill: '科学启蒙'
  },
  {
    id: 'trivia12-012',
    age: 12,
    prompt: '被狗咬伤后，正确的初步处理是什么？',
    options: ['用流动清水和肥皂水冲洗，并尽快告诉大人就医', '用嘴把伤口里的血吸出来', '不处理，等它自己好'],
    answer: 0,
    explanation: '应立即用流动清水和肥皂水充分冲洗，尽快告诉大人并到医院处理。',
    narration: '被狗咬伤后，正确的初步处理是什么？',
    skill: '安全健康'
  },
  {
    id: 'trivia12-013',
    age: 12,
    prompt: '下列哪种动物属于两栖动物？',
    options: ['扬子鳄', '大鲵', '乌龟'],
    answer: 1,
    explanation: '大鲵是两栖动物；扬子鳄和乌龟都是爬行动物。',
    narration: '下列哪种动物属于两栖动物？',
    skill: '动物朋友'
  },
  {
    id: 'trivia12-014',
    age: 12,
    prompt: '黄河下游形成“地上河”，主要原因是什么？',
    options: ['降水太少使河水结冰', '海水倒灌淹没河谷', '泥沙淤积使河床不断抬高'],
    answer: 2,
    explanation: '黄河携带大量泥沙，下游地势平缓、泥沙淤积，河床逐渐抬高，形成地上河。',
    narration: '黄河下游形成地上河，主要原因是什么？',
    skill: '地理天气'
  },
  {
    id: 'trivia12-015',
    age: 12,
    prompt: '电器起火时，在确保安全的情况下首先应该怎样做？',
    options: ['切断电源，再用合适的灭火器', '直接用水浇灭', '把电器搬到床上'],
    answer: 0,
    explanation: '应先切断电源，再使用适合电器火灾的灭火器；不要直接用水灭火。',
    narration: '电器起火时，在确保安全的情况下首先应该怎样做？',
    skill: '安全健康'
  },
  {
    id: 'trivia12-016',
    age: 12,
    prompt: '在北半球夜空中，北斗七星常用来帮助辨认哪个方向？',
    options: ['东方', '北方', '南方'],
    answer: 1,
    explanation: '沿着北斗七星斗口两星连线延长，可以找到北极星，从而辨认北方。',
    narration: '在北半球夜空中，北斗七星常用来帮助辨认哪个方向？',
    skill: '自然观察'
  },
  {
    id: 'trivia12-017',
    age: 12,
    prompt: '《清明上河图》的作者是谁？',
    options: ['顾恺之', '吴道子', '张择端'],
    answer: 2,
    explanation: '《清明上河图》是北宋画家张择端创作的风俗画。',
    narration: '清明上河图的作者是谁？',
    skill: '中国文化'
  },
  {
    id: 'trivia12-018',
    age: 12,
    prompt: '电脑中负责执行运算和指令控制的核心部件通常叫什么？',
    options: ['中央处理器', '显示器', '键盘'],
    answer: 0,
    explanation: '中央处理器负责运算和控制；显示器负责显示，键盘用于输入。',
    narration: '电脑中负责执行运算和指令控制的核心部件通常叫什么？',
    skill: '生活常识'
  },
  {
    id: 'trivia12-019',
    age: 12,
    prompt: '秦岭—淮河一线大致是我国哪一条重要地理分界线？',
    options: ['东半球与西半球', '南方地区与北方地区', '热带与寒带'],
    answer: 1,
    explanation: '秦岭—淮河一线大致是我国南方地区和北方地区的分界线。',
    narration: '秦岭、淮河一线大致是我国哪一条重要地理分界线？',
    skill: '地理天气'
  },
  {
    id: 'trivia12-020',
    age: 12,
    prompt: '发生火灾逃生时为什么不能乘坐电梯？',
    options: ['电梯速度太慢', '电梯按键会变热', '可能断电停运，还可能因烟囱效应进入烟雾'],
    answer: 2,
    explanation: '火灾中电梯可能断电或故障，电梯井还可能形成烟囱效应，十分危险。',
    narration: '发生火灾逃生时为什么不能乘坐电梯？',
    skill: '安全健康'
  },
  {
    id: 'trivia12-021',
    age: 12,
    prompt: '《史记》的作者是谁？',
    options: ['司马迁', '班固', '司马光'],
    answer: 0,
    explanation: '《史记》由西汉司马迁撰写；班固写《汉书》，司马光主持编写《资治通鉴》。',
    narration: '史记的作者是谁？',
    skill: '中国文化'
  },
  {
    id: 'trivia12-022',
    age: 12,
    prompt: '绿色植物光合作用把光能主要转化为什么形式储存？',
    options: ['电能', '有机物中的化学能', '声能'],
    answer: 1,
    explanation: '光合作用把光能转化为化学能，储存在葡萄糖等有机物中。',
    narration: '绿色植物光合作用把光能主要转化为什么形式储存？',
    skill: '科学启蒙'
  }
]

function canonicalQuestion(question) {
  return Object.fromEntries(requiredFields.map(field => [field, question[field]]))
}

function validateQuestion(question, label) {
  if (!question || typeof question !== 'object' || Array.isArray(question)) {
    throw new Error(`${label} 不是题目对象`)
  }
  const unknownFields = Object.keys(question).filter(field => !requiredFields.includes(field))
  if (unknownFields.length) throw new Error(`${label} 含有未约定字段：${unknownFields.join('、')}`)
  for (const field of requiredFields) {
    if (!(field in question)) throw new Error(`${label} 缺少字段 ${field}`)
  }
  if (typeof question.id !== 'string' || !/^trivia(?:[4-9]|1[0-2])-\d{3}$/.test(question.id)) {
    throw new Error(`${label} 的 id 格式无效：${question.id}`)
  }
  if (!Number.isInteger(question.age) || question.age < 4 || question.age > 12) {
    throw new Error(`${label} 的 age 必须是 4–12 的整数`)
  }
  if (question.id !== `trivia${question.age}-${question.id.slice(-3)}`) {
    throw new Error(`${label} 的 id 与 age 不一致`)
  }
  if (typeof question.prompt !== 'string' || !question.prompt.trim()) {
    throw new Error(`${label} 的 prompt 不能为空`)
  }
  if (!Array.isArray(question.options) || question.options.length !== 3) {
    throw new Error(`${label} 的 options 必须恰好有 3 项`)
  }
  if (question.options.some(option => typeof option !== 'string' || !option.trim())) {
    throw new Error(`${label} 的 options 不能有空项`)
  }
  const normalizedOptions = question.options.map(option => option.trim().toLowerCase())
  if (new Set(normalizedOptions).size !== 3) {
    throw new Error(`${label} 的 options 有重复项`)
  }
  if (!Number.isInteger(question.answer) || question.answer < 0 || question.answer > 2) {
    throw new Error(`${label} 的 answer 必须位于 0–2`)
  }
  if (typeof question.explanation !== 'string' || !question.explanation.trim()) {
    throw new Error(`${label} 的 explanation 不能为空`)
  }
  if (typeof question.narration !== 'string' || !question.narration.trim()) {
    throw new Error(`${label} 的 narration 不能为空`)
  }
  if (!allowedSkills.has(question.skill)) {
    throw new Error(`${label} 的 skill 无效：${question.skill}`)
  }
}

function countByAge(questions) {
  const counts = new Map()
  for (const question of questions) counts.set(question.age, (counts.get(question.age) || 0) + 1)
  return counts
}

function validateBank(questions) {
  for (const [index, question] of questions.entries()) {
    validateQuestion(question, `第 ${index + 1} 题`)
  }
  const idSet = new Set()
  for (const question of questions) {
    if (idSet.has(question.id)) throw new Error(`题目 id 重复：${question.id}`)
    idSet.add(question.id)
  }
  if (questions.length !== expectedTotal) {
    throw new Error(`题库应有 ${expectedTotal} 题，实际有 ${questions.length} 题`)
  }
  const baseline = questions.slice(0, baselineCount)
  const baselineHash = createHash('sha256').update(JSON.stringify(baseline)).digest('hex')
  if (baselineHash !== baselineSha256) {
    throw new Error('原 100 题的内容或顺序已被改动')
  }
  const counts = countByAge(questions)
  for (const age of expectedAges) {
    const count = counts.get(age) || 0
    if (count < expectedExtraPerAge) throw new Error(`${age} 岁题目不足 ${expectedExtraPerAge} 题，实际 ${count} 题`)
  }
  return counts
}

function validateExtraSet() {
  for (const [index, question] of extraQuestions.entries()) {
    validateQuestion(question, `新增题第 ${index + 1} 题`)
  }
  const declaredCounts = countByAge(extraQuestions)
  for (const age of expectedAges) {
    const count = declaredCounts.get(age) || 0
    if (count !== expectedExtraPerAge) {
      throw new Error(`新增题中 ${age} 岁应有 ${expectedExtraPerAge} 题，实际 ${count} 题`)
    }
  }
  const ids = new Set()
  const prompts = new Set()
  for (const question of extraQuestions) {
    if (ids.has(question.id)) throw new Error(`新增题 id 重复：${question.id}`)
    if (prompts.has(question.prompt)) throw new Error(`新增题 prompt 重复：${question.prompt}`)
    ids.add(question.id)
    prompts.add(question.prompt)
  }
}

function appendQuestions(source, questions) {
  const trimmed = source.trimEnd()
  if (!trimmed.endsWith(']')) throw new Error('trivia.json 不是完整 JSON 数组')
  const closingIndex = trimmed.lastIndexOf(']')
  const body = trimmed.slice(0, closingIndex).trimEnd()
  if (!body.endsWith('}') && !body.endsWith(']')) throw new Error('无法定位题库插入位置')
  const ordered = []
  for (const age of expectedAges) {
    ordered.push(
      ...questions
        .filter(question => question.age === age)
        .sort((left, right) => left.id.localeCompare(right.id))
    )
  }
  const lines = []
  let previousAge = null
  for (const question of ordered) {
    if (previousAge !== null && question.age !== previousAge) lines.push('')
    lines.push(`  ${JSON.stringify(question)},`)
    previousAge = question.age
  }
  lines[lines.length - 1] = lines[lines.length - 1].slice(0, -1)
  return `${body},\n\n${lines.join('\n')}\n]\n`
}

function printDistribution(questions) {
  const counts = countByAge(questions)
  const ages = [...counts.keys()].sort((left, right) => left - right)
  console.log(`总题数：${questions.length}`)
  console.log(`年龄分布：${ages.map(age => `${age}岁 ${counts.get(age)}题`).join('，')}`)
}

async function main() {
  const mode = process.argv[2]
  if (mode !== '--check' && mode !== '--write') {
    console.error('用法：node scripts/native/author-trivia-extra.mjs --check | --write')
    process.exitCode = 1
    return
  }

  validateExtraSet()
  const source = await readFile(triviaPath, 'utf8')
  const questions = JSON.parse(source)
  if (!Array.isArray(questions)) throw new Error('trivia.json 顶层必须是数组')
  for (const [index, question] of questions.entries()) {
    validateQuestion(question, `现有题第 ${index + 1} 题`)
  }

  if (mode === '--check') {
    const counts = validateBank(questions)
    printDistribution(questions)
    console.log(`校验通过：${expectedAges.map(age => `${age}岁至少${counts.get(age) || 0}题`).join('，')}`)
    return
  }

  const byId = new Map(questions.map(question => [question.id, question]))
  const missing = []
  for (const question of extraQuestions) {
    const existing = byId.get(question.id)
    if (!existing) {
      missing.push(question)
      continue
    }
    if (JSON.stringify(canonicalQuestion(existing)) !== JSON.stringify(question)) {
      throw new Error(`新增题 ${question.id} 已存在但与生成数据不一致`)
    }
  }

  if (!missing.length) {
    validateBank(questions)
    printDistribution(questions)
    console.log('60 道新增题均已存在，无需写入。')
    return
  }

  const merged = [...questions, ...missing]
  validateBank(merged)
  const nextSource = appendQuestions(source, missing)
  await writeFile(triviaPath, nextSource)
  const written = JSON.parse(await readFile(triviaPath, 'utf8'))
  validateBank(written)
  printDistribution(written)
  console.log(`已追加 ${missing.length} 道新增题。`)
}

main().catch(error => {
  console.error(`知识竞赛题库校验失败：${error.message}`)
  process.exitCode = 1
})
