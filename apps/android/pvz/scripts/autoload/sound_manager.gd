extends Node
class_name SoundManagerClass

enum Bus {MASTER, BGM, SFX}

@onready var bgm_play: AudioStreamPlayer = $BGMPlay
@onready var sfx_all: Node = $SFXAll
@onready var crazy_dave_player: AudioStreamPlayer = $SFXAll/CrazyDavePlayer
@onready var rain_player: AudioStreamPlayer = $SFXAll/RainPlayer

## 当前帧播放的音效(每隔25物理帧清除一次)
## 音效每25物理帧内不可以重复播放
var curr_frame_sfx:Array[AudioStream] = []
var frame_num:=0
var _muted_sfx_player := AudioStreamPlayer.new()
var kids_audio: Dictionary = {}

func _ready() -> void:
	kids_audio = _load_audio_map()
	SaveStore.changed.connect(_apply_kids_audio_settings)
	_apply_kids_audio_settings()

func _load_audio_map() -> Dictionary:
	if not FileAccess.file_exists("res://pvz/data/kids_audio_map.json"):
		return {}
	var file := FileAccess.open("res://pvz/data/kids_audio_map.json", FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed if parsed is Dictionary else {}

func _kids_audio_stream(group: String, key: String) -> AudioStream:
	var options: Variant = kids_audio.get(group, {}).get(key, [])
	if not options is Array or options.is_empty():
		return null
	var path := str(options.pick_random())
	return load(path) as AudioStream if ResourceLoader.exists(path) else null

func _apply_kids_audio_settings() -> void:
	if not is_instance_valid(bgm_play):
		return
	if not bool(SaveStore.settings().get("musicOn", true)):
		bgm_play.stop()
	elif not bgm_play.playing and bgm_play.stream != null:
		bgm_play.play()

@warning_ignore("unused_parameter")
func _physics_process(delta: float) -> void:
	frame_num = wrapi(frame_num + 1, 0, 25)
	if frame_num == 0:
		curr_frame_sfx.clear()

#region 播放音乐和音效
func play_bgm(stream: AudioStream):
	if not bool(SaveStore.settings().get("musicOn", true)):
		bgm_play.stop()
		return
	bgm_play.stream = stream
	bgm_play.play()

## 播放 [param stream] 指定的背景音乐；相同曲目正在播放时保持进度，避免从头重播。
func play_bgm_if_changed(stream: AudioStream) -> void:
	if bgm_play.stream == stream and bgm_play.playing:
		return
	play_bgm(stream)

func stop_bgm() -> void:
	if is_instance_valid(bgm_play):
		bgm_play.stop()

func resume_bgm() -> void:
	if bool(SaveStore.settings().get("musicOn", true)) and bgm_play.stream != null and not bgm_play.playing:
		bgm_play.play()

func stop_sfx() -> void:
	if is_instance_valid(crazy_dave_player):
		crazy_dave_player.stop()
	if is_instance_valid(rain_player):
		rain_player.stop()
	for player in sfx_bullet_pool:
		if is_instance_valid(player):
			player.stop()

func stop_all_audio() -> void:
	stop_bgm()
	stop_sfx()

#region 植物和僵尸有关音效(植物、僵尸、子弹、受击)
"""
 音效分为 僵尸受击 子弹音效 角色(植物僵尸) 戴夫 和其他音效
"""

## 僵尸受击音效种类
enum TypeBeAttackSFX{
	Null,		## 无声音
	Plastic,	## 塑料
	Shield		## 铁器
}

## 僵尸受击音效资源字典
const SFXBeAttackMap := {
	TypeBeAttackSFX.Null: null,
	TypeBeAttackSFX.Plastic: [
		preload("res://pvz/assets/audio-placeholder.wav"),
		preload("res://pvz/assets/audio-placeholder.wav")
	],
	TypeBeAttackSFX.Shield: [
		preload("res://pvz/assets/audio-placeholder.wav"),
		preload("res://pvz/assets/audio-placeholder.wav")
	],
}

## 子弹音效种类
enum TypeBulletSFX{
	Null,		## 无声音
	Pea,		## 豌豆
	PeaFire,	## 火焰豌豆
	Corn,		## 玉米粒
	Butter,		## 黄油
	Melon,		## 西瓜
	Bowling = 1001,		## 保龄球
}

## 子弹音效资源字典
const SFXBulletMap := {
	TypeBulletSFX.Null: null,
	TypeBulletSFX.Pea: [
		preload("res://pvz/assets/audio-placeholder.wav"),
		preload("res://pvz/assets/audio-placeholder.wav"),
		preload("res://pvz/assets/audio-placeholder.wav")
	],
	TypeBulletSFX.PeaFire: [
		preload("res://pvz/assets/audio-placeholder.wav"),
	],
	TypeBulletSFX.Corn:[
		preload("res://pvz/assets/audio-placeholder.wav"),
		preload("res://pvz/assets/audio-placeholder.wav")
	],
	TypeBulletSFX.Butter:[
		preload("res://pvz/assets/audio-placeholder.wav")
	],
	TypeBulletSFX.Melon:[
		preload("res://pvz/assets/audio-placeholder.wav"),
		preload("res://pvz/assets/audio-placeholder.wav")
	],

	TypeBulletSFX.Bowling: [
		preload("res://pvz/assets/audio-placeholder.wav"),
		preload("res://pvz/assets/audio-placeholder.wav"),
	],

}

## 植物\僵尸音效字典
const SFXCharacterMap := {
	## -------------------------------植物-------------------------------
	## 豌豆射手发射字典
	&"Throw":[
		preload("res://pvz/assets/audio-placeholder.wav"),
		preload("res://pvz/assets/audio-placeholder.wav")
	],
	## 向日葵发射阳光
	&"Throw1":preload("res://pvz/assets/audio-placeholder.wav"),
	## 樱桃炸弹爆炸
	&"CherryBomb":preload("res://assets/garden/original/cherrybomb.mp3"),
	## 土豆雷爆炸
	&"PotatoMine": preload("res://pvz/assets/audio-placeholder.wav"),
	## 大嘴花
	&"BigChomp": preload("res://pvz/assets/audio-placeholder.wav"),
	## 小喷菇发射子弹
	&"Puff": preload("res://pvz/assets/audio-placeholder.wav"),
	## 阳光菇长大
	&"PlantGrow": preload("res://pvz/assets/audio-placeholder.wav"),
	## 大喷菇发射子弹
	&"Fume": preload("res://assets/garden/original/fume.mp3"),
	## 墓碑吞噬者
	&"GraveBusterChomp":preload("res://pvz/assets/audio-placeholder.wav"),
	## 魅惑菇
	&"MindControlled": preload("res://assets/garden/original/mindcontrolled.mp3"),
	## 寒冰菇
	&"Frozen": preload("res://assets/garden/original/frozen.mp3"),
	## 毁灭菇
	&"DoomShroom": preload("res://pvz/assets/audio-placeholder.wav"),
	## 倭瓜发现敌人
	&"SquashHmm":[
		preload("res://pvz/assets/audio-placeholder.wav"),
		preload("res://pvz/assets/audio-placeholder.wav")
	],
	## 火爆辣椒
	&"Jalapeno": preload("res://pvz/assets/audio-placeholder.wav"),
	## 三叶草
	&"blover": preload("res://assets/garden/original/blover.mp3"),
	## 磁力菇
	&"magnetshroom": preload("res://pvz/assets/audio-placeholder.wav"),
	## 磁力菇
	&"coblaunch": preload("res://pvz/assets/audio-placeholder.wav"),




	## -------------------------------僵尸-------------------------------
	## 通用音效
	## 掉头
	&"limbs_pop": preload("res://pvz/assets/audio-placeholder.wav"),

	## 啃食
	&"Chomp":[
		preload("res://assets/garden/original/chomp.mp3"),
		preload("res://pvz/assets/audio-placeholder.wav"),
		preload("res://pvz/assets/audio-placeholder.wav")
	],
	## 掉头
	&"Shoop":preload("res://pvz/assets/audio-placeholder.wav"),
	## 啃食大蒜
	&"yuck":[
		preload("res://pvz/assets/audio-placeholder.wav"),
		preload("res://pvz/assets/audio-placeholder.wav")
	],
	## 撑杆跳
	&"Polevault":preload("res://pvz/assets/audio-placeholder.wav"),
	## 读报僵尸愤怒
	&"Rarrgh":[
		preload("res://pvz/assets/audio-placeholder.wav"),
		preload("res://pvz/assets/audio-placeholder.wav")
	],
	## 读报僵尸报纸掉落
	&"Rip":	preload("res://pvz/assets/audio-placeholder.wav"),
	## 舞王入场
	&"Dancer":preload("res://pvz/assets/audio-placeholder.wav"),
	## 冰车僵尸入场
	&"zamboni":preload("res://pvz/assets/audio-placeholder.wav"),
	## 冰车僵尸爆炸\小丑僵尸爆炸
	&"explosion":preload("res://pvz/assets/audio-placeholder.wav"),
	## 海豚僵尸入场
	&"dolphin_appears":preload("res://pvz/assets/audio-placeholder.wav"),
	## 海豚僵尸跳跃
	&"dolphin_before_jumping":preload("res://pvz/assets/audio-placeholder.wav"),
	## 小丑僵尸入场
	&"jackinthebox":preload("res://pvz/assets/audio-placeholder.wav"),
	## 小丑僵尸爆炸惊讶
	&"jack_suprise":[
		preload("res://pvz/assets/audio-placeholder.wav"),
		preload("res://pvz/assets/audio-placeholder.wav"),
	],
	## 小丑僵尸盒子打开
	&"boing":preload("res://pvz/assets/audio-placeholder.wav"),
	## 气球僵尸入场
	&"ballooninflate":preload("res://pvz/assets/audio-placeholder.wav"),
	## 气球爆炸
	&"balloon_pop":preload("res://pvz/assets/audio-placeholder.wav"),
	## 矿工僵尸绝地
	&"digger_zombie": preload("res://pvz/assets/audio-placeholder.wav"),
	## 跳跳僵尸跳跃
	&"pogo_zombie": preload("res://pvz/assets/audio-placeholder.wav"),
	## 蹦极僵尸入场
	&"bungee_scream":[
		preload("res://assets/garden/original/bungee_scream.mp3"),
		preload("res://pvz/assets/audio-placeholder.wav"),
		preload("res://pvz/assets/audio-placeholder.wav")
	],
	## 扶梯僵尸放置梯子
	&"ladder_zombie": preload("res://pvz/assets/audio-placeholder.wav"),
	## 篮球僵尸发射篮球子弹
	&"basketball": preload("res://pvz/assets/audio-placeholder.wav"),
	## 僵王吐出冰火球。
	&"bossboulderattack": preload("res://pvz/assets/audio-placeholder.wav"),
	## 僵王机甲死亡爆炸。
	&"bossexplosion": preload("res://pvz/assets/audio-placeholder.wav"),
	## 僵王低头、抬头的液压动作。
	&"hydraulic": preload("res://pvz/assets/audio-placeholder.wav"),
	## 僵王放置僵尸及蹦极时的手臂动作。
	&"hydraulic_short": preload("res://pvz/assets/audio-placeholder.wav"),
	## 僵王丢车时的投掷动作。
	&"RVthrow": preload("res://pvz/assets/audio-placeholder.wav"),

	## 巨人僵尸攻击\倭瓜
	&"gargantuar_thump": preload("res://pvz/assets/audio-placeholder.wav"),
	## 巨人僵尸死亡
	&"gargantudeath": preload("res://pvz/assets/audio-placeholder.wav"),
	## 小鬼被抛射
	&"imp":[
		preload("res://pvz/assets/audio-placeholder.wav"),
		preload("res://pvz/assets/audio-placeholder.wav")
	]
}

## 戴夫音效字典
const SFXCarzyDaveMap := {
	## 一秒左右
	&"crazydaveshort" : [
		preload("res://pvz/assets/audio-placeholder.wav"),
		preload("res://pvz/assets/audio-placeholder.wav"),
		preload("res://pvz/assets/audio-placeholder.wav")
	],
	## 两秒左右
	&"crazydavelong" : [
		preload("res://pvz/assets/audio-placeholder.wav"),
		preload("res://pvz/assets/audio-placeholder.wav"),
		preload("res://pvz/assets/audio-placeholder.wav")
	],
	## 三秒左右
	&"crazydaveextralong" : [
		preload("res://pvz/assets/audio-placeholder.wav"),
		preload("res://pvz/assets/audio-placeholder.wav"),
		preload("res://pvz/assets/audio-placeholder.wav")
	],
	&"crazydavecrazy" : [
		preload("res://pvz/assets/audio-placeholder.wav")
	],
	&"crazydavescream" : [
		preload("res://pvz/assets/audio-placeholder.wav"),
		preload("res://pvz/assets/audio-placeholder.wav")
	],
}

## 音效对象池实现
var sfx_bullet_pool = []

func play_sfx_with_pool(sfx_resource: AudioStream) -> AudioStreamPlayer:
	if not bool(SaveStore.settings().get("soundOn", true)):
		return _muted_sfx_player
	if sfx_resource in curr_frame_sfx:
		return _muted_sfx_player
	curr_frame_sfx.append(sfx_resource)

	var player: AudioStreamPlayer
	# 从池中获取可用播放器
	for p in sfx_bullet_pool:
		if not p.playing:
			player = p
			break

	# 如果没有可用播放器，创建新的
	if not player:
		player = AudioStreamPlayer.new()
		player.bus = AudioServer.get_bus_name(Bus.SFX)
		player.finished.connect(_on_sfx_finished.bind(player))
		sfx_all.add_child(player)
		sfx_bullet_pool.append(player)

	## 配置播放器
	player.stream = sfx_resource
	player.play()
	return player

#TODO: 好像没什么用,后续会删掉
@warning_ignore("unused_parameter")
func _on_sfx_finished(player: AudioStreamPlayer):
	# 播放完成后自动停止，保留在池中
	#player.stop()
	pass

## 播放僵尸受击音效
func play_be_attack_SFX(type_bullet_zombie_sfx:TypeBeAttackSFX):
	var mapped: String = {
		TypeBeAttackSFX.Plastic: "Plastic",
		TypeBeAttackSFX.Shield: "Shield",
	}.get(type_bullet_zombie_sfx, "") as String
	if not str(mapped).is_empty():
		var upstream_stream := _kids_audio_stream("be_attack", str(mapped))
		if upstream_stream != null:
			play_sfx_with_pool(upstream_stream)
			return
	var sfx_array: Array = SFXBeAttackMap[type_bullet_zombie_sfx]

	var sfx_selected = sfx_array.pick_random()
	play_sfx_with_pool(sfx_selected)

## 播放子弹攻击音效
func play_bullet_attack_SFX(type_bullet_sfx:TypeBulletSFX):
	var mapped: String = {
		TypeBulletSFX.Pea: "Pea",
		TypeBulletSFX.PeaFire: "PeaFire",
		TypeBulletSFX.Bowling: "Bowling",
	}.get(type_bullet_sfx, "") as String
	if not str(mapped).is_empty():
		var upstream_stream := _kids_audio_stream("bullet", str(mapped))
		if upstream_stream != null:
			play_sfx_with_pool(upstream_stream)
			return
	var sfx_array: Array = SFXBulletMap[type_bullet_sfx]

	var sfx_selected = sfx_array.pick_random()
	play_sfx_with_pool(sfx_selected)

## 播放植物\僵尸相关音效
func play_character_SFX(option:StringName):
	var upstream_stream := _kids_audio_stream("character", str(option))
	if upstream_stream != null:
		return play_sfx_with_pool(upstream_stream)
	var sfx_resource:AudioStream
	if SFXCharacterMap[option] is Array:
		sfx_resource = SFXCharacterMap[option].pick_random()
	else:
		sfx_resource = SFXCharacterMap[option]
	var player: AudioStreamPlayer = play_sfx_with_pool(sfx_resource)
	return player


## 播放戴夫音效
func play_crazy_dave_SFX(option:StringName):
	var upstream_stream := _kids_audio_stream("dave", str(option))
	if upstream_stream != null:
		crazy_dave_player.stream = upstream_stream
		crazy_dave_player.play()
		return
	var sfx_array: Array = SFXCarzyDaveMap[option]

	var sfx_selected = sfx_array.pick_random()
	crazy_dave_player.stream = sfx_selected
	crazy_dave_player.play()

func play_rain_SFX():
	var RAIN = load("uid://dmjld1k8ieh1g")
	rain_player.stream = RAIN
	rain_player.play()

func stop_rain_SFX():
	rain_player.stop()
#endregion

#region 其余音效
const SFXOtherMap := {
	##-------------------------- 按钮相关 --------------------------
	## 开始菜单点击
	&"gravebutton": preload("res://pvz/assets/audio-placeholder.wav"),
	## 鼠标进入开始菜单
	&"bleep":preload("res://pvz/assets/audio-placeholder.wav"),
	##
	&"tap":preload("res://pvz/assets/audio-placeholder.wav"),
	## 选项按钮
	&"buttonclick":preload("res://assets/garden/original/buttonclick.mp3"),
	## 暂停
	&"pause": preload("res://pvz/assets/audio-placeholder.wav"),
	## 点击阳光
	&"points": preload("res://assets/garden/original/points.mp3"),
	## 点击金币
	&"coin":preload("res://pvz/assets/audio-placeholder.wav"),
	## 掉落花园植物
	&"chime":preload("res://pvz/assets/audio-placeholder.wav"),
	##-------------------------- 卡片相关 --------------------------
	&"buzzer":preload("res://pvz/assets/audio-placeholder.wav"),
	&"seedlift":preload("res://pvz/assets/audio-placeholder.wav"),
	&"shovel":preload("res://pvz/assets/audio-placeholder.wav"),
	&"tap2":preload("res://pvz/assets/audio-placeholder.wav"),

	##-------------------------- 进度相关 --------------------------
	## 汽笛音效
	&"siren": preload("res://pvz/assets/audio-placeholder.wav"),
	## TODO :这个也是汽笛音效？
	&"awooga":preload("res://pvz/assets/audio-placeholder.wav"),
	## 最后一波
	&"finalwave":preload("res://assets/garden/original/finalwave.mp3"),
	## 大波僵尸
	&"hugewave":preload("res://assets/garden/original/hugewave.mp3"),
	## 失败
	&"losemusic":preload("res://assets/garden/original/losemusic.mp3"),
	## 准备安放植物
	&"readysetplant":preload("res://pvz/assets/audio-placeholder.wav"),
	## 戴夫尖叫
	&"scream":preload("res://pvz/assets/audio-placeholder.wav"),
	## 获胜音效
	&"winmusic":preload("res://assets/garden/original/winmusic.mp3"),


	##-------------------------- 主游戏场景物品相关 --------------------------
	## 墓碑生成
	&"gravestone_rumble":preload("res://pvz/assets/audio-placeholder.wav"),
	## 植物种植音效
	&"plant1": preload("res://pvz/assets/audio-placeholder.wav"),
	## 植物铲除音效
	&"plant2":preload("res://pvz/assets/audio-placeholder.wav"),
	## 植物种植在水上
	&"plant_water": preload("res://assets/garden/original/plant_water.mp3"),
	## 僵尸入水音效、水花音效
	&"zombie_entering_water": preload("res://pvz/assets/audio-placeholder.wav"),
	## -------- 小推车 --------
	&"lawnmower": preload("res://assets/garden/original/lawnmower.mp3"),
	&"pool_cleaner": preload("res://pvz/assets/audio-placeholder.wav"),
	## -------- 锤子 --------
	&"swing": preload("res://pvz/assets/audio-placeholder.wav"),
	&"bonk": preload("res://assets/garden/original/bonk.mp3"),
	## -------- 花园 -----------
	&"prize": preload("res://pvz/assets/audio-placeholder.wav"),
	## -------- 僵尸出土 ------------
	&"dirt_rise": preload("res://pvz/assets/audio-placeholder.wav"),
	## --------- 花瓶破碎     -------------
	&"vase_breaking": preload("res://assets/garden/original/vase_breaking.mp3"),


	##-------------------------- 花园相关 --------------------------
	&"watering":preload("res://pvz/assets/audio-placeholder.wav"),
	&"fertilizer":preload("res://pvz/assets/audio-placeholder.wav"),
	&"bugspray":preload("res://pvz/assets/audio-placeholder.wav"),
	&"phonograph":preload("res://pvz/assets/audio-placeholder.wav"),
	&"wakeup": preload("res://pvz/assets/audio-placeholder.wav"),

}
## 播放其它相关音效
func play_other_SFX(option:StringName):
	var upstream_stream := _kids_audio_stream("other", str(option))
	if upstream_stream != null:
		play_sfx_with_pool(upstream_stream)
		return
	var sfx_resource: AudioStream
	if SFXOtherMap[option] is Array:
		sfx_resource = SFXOtherMap[option].pick_random()
	else:
		sfx_resource = SFXOtherMap[option]
	play_sfx_with_pool(sfx_resource)


#endregion

#endregion

#region 按钮信号连接辅助函数
## 更新开始菜单的UI音效
func setup_ui_start_menu_sound(node:Node, is_menu_button:=false):
	if node is BaseButton:
		var button := node
		button.mouse_entered.connect(play_other_SFX.bind("bleep"))

		if is_menu_button:
			button.button_down.connect(play_other_SFX.bind("gravebutton"))
		else:
			if not button.button_down.is_connected(play_other_SFX):
				button.button_down.connect(play_other_SFX.bind("tap"))


	for child in node.get_children():
		## 如果是Menu或者其上面的节点为Menu
		if child.name == "Menu" or is_menu_button:
			setup_ui_start_menu_sound(child, true)
		else:
			setup_ui_start_menu_sound(child, false)


## 更新主游戏按钮的UI音效
func setup_ui_main_game_sound(node:Node):
	if node is BaseButton:
		if node is CheckButton:
			node.pressed.connect(play_other_SFX.bind("buttonclick"))
		else:
			node.button_down.connect(play_other_SFX.bind("gravebutton"))

			if node.name == "Return":
				node.pressed.connect(play_other_SFX.bind("buttonclick"))


	for child in node.get_children():
		setup_ui_main_game_sound(child)
#endregion

#region 音量大小调整
func get_volum(bus_index:int):
	if bus_index < 0 or bus_index >= AudioServer.bus_count:
		return 1.0
	var db := AudioServer.get_bus_volume_db(bus_index)
	return db_to_linear(db)

func set_volume(bus_index:int, v:float) ->void:
	if bus_index < 0 or bus_index >= AudioServer.bus_count:
		return
	var db := linear_to_db(v)
	AudioServer.set_bus_volume_db(bus_index, db)
#endregion
