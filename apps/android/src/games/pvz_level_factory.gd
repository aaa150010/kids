class_name PvZLevelFactory
extends RefCounted

## 将童心游乐场的 50 关内容转换为 PVZ-Godot-Dream 的关卡资源。
## 上游负责植物、僵尸、弹道、波次、卡槽和小游戏规则；这里只做内容与难度适配。

const PLANT_MAP := {
	"peashooter": CharacterRegistry.PlantType.P001PeaShooterSingle,
	"sunflower": CharacterRegistry.PlantType.P002SunFlower,
	"cherrybomb": CharacterRegistry.PlantType.P003CherryBomb,
	"wallnut": CharacterRegistry.PlantType.P004WallNut,
	"potatomine": CharacterRegistry.PlantType.P005PotatoMine,
	"snowpea": CharacterRegistry.PlantType.P006SnowPea,
	"chomper": CharacterRegistry.PlantType.P007Chomper,
	"repeater": CharacterRegistry.PlantType.P008PeaShooterDouble,
	"puffshroom": CharacterRegistry.PlantType.P009PuffShroom,
	"sunshroom": CharacterRegistry.PlantType.P010SunShroom,
	"fumeshroom": CharacterRegistry.PlantType.P011FumeShroom,
	"gravebuster": CharacterRegistry.PlantType.P012GraveBuster,
	"hypnoshroom": CharacterRegistry.PlantType.P013HypnoShroom,
	"scaredyshroom": CharacterRegistry.PlantType.P014ScaredyShroom,
	"iceshroom": CharacterRegistry.PlantType.P015IceShroom,
	"doomshroom": CharacterRegistry.PlantType.P016DoomShroom,
	"lilypad": CharacterRegistry.PlantType.P017LilyPad,
	"squash": CharacterRegistry.PlantType.P018Squash,
	"threepeater": CharacterRegistry.PlantType.P019ThreePeater,
	"tanglekelp": CharacterRegistry.PlantType.P020TangleKelp,
	"jalapeno": CharacterRegistry.PlantType.P021Jalapeno,
	"spikeweed": CharacterRegistry.PlantType.P022Caltrop,
	"torchwood": CharacterRegistry.PlantType.P023TorchWood,
	"tallnut": CharacterRegistry.PlantType.P024TallNut,
	"seashroom": CharacterRegistry.PlantType.P025SeaShroom,
	"plantern": CharacterRegistry.PlantType.P026Plantern,
	"cactus": CharacterRegistry.PlantType.P027Cactus,
	"blover": CharacterRegistry.PlantType.P028Blover,
	"splitpea": CharacterRegistry.PlantType.P029SplitPea,
	"starfruit": CharacterRegistry.PlantType.P030StarFruit,
	"pumpkin": CharacterRegistry.PlantType.P031Pumpkin,
	"magnetshroom": CharacterRegistry.PlantType.P032MagnetShroom,
	"cabbagepult": CharacterRegistry.PlantType.P033CabbagePult,
	"flowerpot": CharacterRegistry.PlantType.P034FlowerPot,
	"kernelpult": CharacterRegistry.PlantType.P035CornPult,
	"coffeebean": CharacterRegistry.PlantType.P036CoffeeBean,
	"garlic": CharacterRegistry.PlantType.P037Garlic,
	"umbrella": CharacterRegistry.PlantType.P038UmbrellaLeaf,
	"marigold": CharacterRegistry.PlantType.P039MariGold,
	"melonpult": CharacterRegistry.PlantType.P040MelonPult,
	"gatlingpea": CharacterRegistry.PlantType.P041GatlingPea,
	"twinsunflower": CharacterRegistry.PlantType.P042TwinSunFlower,
	"gloomshroom": CharacterRegistry.PlantType.P043GloomShroom,
	"cattail": CharacterRegistry.PlantType.P044Cattail,
	"wintermelon": CharacterRegistry.PlantType.P045WinterMelon,
	"goldmagnet": CharacterRegistry.PlantType.P046GoldMagnet,
	"spikerock": CharacterRegistry.PlantType.P047SpikeRock,
	"cobcannon": CharacterRegistry.PlantType.P048CobCannon,
}

const ZOMBIE_MAP := {
	"normal": CharacterRegistry.ZombieType.Z001Norm,
	"flag": CharacterRegistry.ZombieType.Z002Flag,
	"cone": CharacterRegistry.ZombieType.Z003Cone,
	"pole": CharacterRegistry.ZombieType.Z004PoleVaulter,
	"bucket": CharacterRegistry.ZombieType.Z005Bucket,
	"newspaper": CharacterRegistry.ZombieType.Z006Paper,
	"door": CharacterRegistry.ZombieType.Z007ScreenDoor,
	"football": CharacterRegistry.ZombieType.Z008Football,
	"dancer": CharacterRegistry.ZombieType.Z009Jackson,
	"backup": CharacterRegistry.ZombieType.Z010Dancer,
	"ducky": CharacterRegistry.ZombieType.Z011Duckytube,
	"snorkel": CharacterRegistry.ZombieType.Z012Snorkle,
	"zomboni": CharacterRegistry.ZombieType.Z013Zamboni,
	"bobsled": CharacterRegistry.ZombieType.Z014Bobsled,
	"dolphin": CharacterRegistry.ZombieType.Z015Dolphinrider,
	"jack": CharacterRegistry.ZombieType.Z016Jackbox,
	"balloon": CharacterRegistry.ZombieType.Z017Balloon,
	"digger": CharacterRegistry.ZombieType.Z018Digger,
	"pogo": CharacterRegistry.ZombieType.Z019Pogo,
	"yeti": CharacterRegistry.ZombieType.Z020Yeti,
	"bungee": CharacterRegistry.ZombieType.Z021Bungi,
	"ladder": CharacterRegistry.ZombieType.Z022Ladder,
	"catapult": CharacterRegistry.ZombieType.Z023Catapult,
	"gargantuar": CharacterRegistry.ZombieType.Z024Gargantuar,
	"imp": CharacterRegistry.ZombieType.Z025Imp,
}

const ENVIRONMENT_BG := {
	"day": ConstLevelData.GameBg.FrontDay,
	"night": ConstLevelData.GameBg.FrontNight,
	"pool": ConstLevelData.GameBg.Pool,
	"fog": ConstLevelData.GameBg.Fog,
	"roof": ConstLevelData.GameBg.Roof,
}

const ENVIRONMENT_BGM := {
	"day": ConstLevelData.GameBGM.FrontDay,
	"night": ConstLevelData.GameBGM.FrontNight,
	"pool": ConstLevelData.GameBGM.Pool,
	"fog": ConstLevelData.GameBGM.Fog,
	"roof": ConstLevelData.GameBGM.Roof,
}

const ENVIRONMENT_SCENE := {
	"day": MainSceneRegistry.MainScenes.MainGameFront,
	"night": MainSceneRegistry.MainScenes.MainGameFront,
	"pool": MainSceneRegistry.MainScenes.MainGameBack,
	"fog": MainSceneRegistry.MainScenes.MainGameBack,
	"roof": MainSceneRegistry.MainScenes.MainGameRoof,
}

const ENVIRONMENT_PATH := {
	"day": "res://pvz/scenes/main/MainGame01Front.tscn",
	"night": "res://pvz/scenes/main/MainGame01Front.tscn",
	"pool": "res://pvz/scenes/main/MainGame02Back.tscn",
	"fog": "res://pvz/scenes/main/MainGame02Back.tscn",
	"roof": "res://pvz/scenes/main/MainGame03Roof.tscn",
}


static func build(level_id: int, mode: String, seeds: Array, difficulty: String = "auto") -> Dictionary:
	var source: Dictionary = {}
	if mode == "endless":
		source = ContentDB.garden.get("endless", {}).duplicate(true)
	elif mode == "tutorial":
		source = ContentDB.garden_levels().get("1", {}).duplicate(true)
		source["waveCount"] = 3
		source["initialSun"] = 150
		source["mode"] = "lawn"
	else:
		source = ContentDB.garden_levels().get(str(level_id), {}).duplicate(true)
	if source.is_empty():
		source = ContentDB.garden_levels().get("1", {}).duplicate(true)
		level_id = 1

	var environment := str(source.get("environment", "day"))
	var special := str(source.get("mode", "lawn"))
	var resolved_difficulty := difficulty if difficulty in ["easy", "normal", "challenge"] else "normal"
	var level := ResourceLevelData.new()
	var save_key := "kids_%s_%s_%s" % [mode, level_id, environment]
	level.set_choose_level(MainSceneRegistry.MainScenes.ChooseLevelAdventure, 0, save_key)
	level.game_round = -1 if mode == "endless" else 1
	level.game_sences = ENVIRONMENT_SCENE.get(environment, MainSceneRegistry.MainScenes.MainGameFront)
	level.game_BG = ENVIRONMENT_BG.get(environment, ConstLevelData.GameBg.FrontDay)
	var bgm: ConstLevelData.GameBGM = ENVIRONMENT_BGM.get(environment, ConstLevelData.GameBGM.FrontDay)
	if special == "conveyor" or special == "bowling" or special == "whack" or special == "vase":
		bgm = ConstLevelData.GameBGM.MiniGame
	if level_id == 50:
		bgm = ConstLevelData.GameBGM.Boss
	level.game_BGM = bgm
	level.is_fog = environment == "fog"
	level.is_rain = level_id == 40
	level.is_day = environment not in ["night", "fog"]
	level.is_day_sun = special == "lawn" and environment != "night" and environment != "fog"
	level.is_lawn_mover = special != "vase"
	level.is_zombie_can_home = true
	level.look_show_zombie = false
	level.can_choosed_card = false
	level.max_choosed_card_num = 10
	level.start_sun = _difficulty_sun(int(source.get("initialSun", 50)), resolved_difficulty)
	level.card_mode = ConstLevelData.E_CardMode.Norm
	level.is_shovel = true
	level.max_wave = maxi(10, int(ceil(float(source.get("waveCount", 10)) / 10.0)) * 10)
	level.monster_mode = ConstLevelData.E_MonsterMode.Norm
	level.zombie_multy = 1
	level.is_mini_zombie = level_id == 25
	level.zombie_refresh_types = _zombies_for_level(level_id)
	level.is_bungi = _level_has_zombie(level_id, "bungee")
	level.is_have_tombston = false
	level.init_tombstone_num = 0
	_init_tombstones(level, level_id)
	if environment == "roof":
		_init_roof_pots(level)

	match special:
		"conveyor":
			_configure_conveyor(level, level_id)
		"bowling":
			_configure_bowling(level)
		"whack":
			_configure_whack(level, seeds)
		"vase":
			_configure_vase(level)
		_:
			_configure_normal(level, seeds)

	if module_is_boss(level_id):
		level.game_sences = MainSceneRegistry.MainScenes.MainGameRoof
		level.game_BG = ConstLevelData.GameBg.Roof
		level.game_BGM = ConstLevelData.GameBGM.Boss
		level.is_day = false
		level.is_day_sun = false
		level.is_bungi = true
		level.monster_mode = ConstLevelData.E_MonsterMode.Norm
		level.max_wave = 20
		level.boss_type = CharacterRegistry.ZombieBossType.ZB001Doctor
		level.boss_spawn_wave = 0
		level.boss_spawn_position = Vector2(690, 280)
		level.win_on_boss_death = true
		level.card_mode = ConstLevelData.E_CardMode.ConveyorBelt
		level.conveyor_weights = _weights_from_content("conveyorFifty")
		level.conveyor_order.clear()
		level.can_choosed_card = false
		level.is_shovel = true

	level.save_game_name = save_key
	return {
		"level": level,
		"environment": environment,
		"special": special,
		"scene": ENVIRONMENT_PATH.get(environment, ENVIRONMENT_PATH["day"]),
		"difficulty": resolved_difficulty,
	}


static func plant_type(kind: String) -> int:
	return int(PLANT_MAP.get(kind, CharacterRegistry.PlantType.Null))


static func plant_kind(content_id: int) -> String:
	for kind in PLANT_MAP:
		if int(PLANT_MAP[kind]) == content_id:
			return str(kind)
	return ""


static func zombie_type(kind: String) -> int:
	return int(ZOMBIE_MAP.get(kind, CharacterRegistry.ZombieType.Null))


static func module_is_boss(level_id: int) -> bool:
	return level_id == 50


static func _difficulty_sun(base_sun: int, difficulty: String) -> int:
	if base_sun <= 0:
		return base_sun
	match difficulty:
		"easy":
			return roundi(base_sun * 1.25)
		"challenge":
			return roundi(base_sun * 0.9)
		_:
			return base_sun


static func _configure_normal(level: ResourceLevelData, seeds: Array) -> void:
	level.card_mode = ConstLevelData.E_CardMode.Norm
	level.prechosen_cards = _card_array(seeds)


static func _configure_conveyor(level: ResourceLevelData, level_id: int) -> void:
	level.card_mode = ConstLevelData.E_CardMode.ConveyorBelt
	level.start_sun = 0
	level.is_day_sun = false
	level.conveyor_weights = _weights_for_conveyor(level_id)
	level.create_new_card_speed = 1.0
	level.is_shovel = true


static func _configure_bowling(level: ResourceLevelData) -> void:
	level.card_mode = ConstLevelData.E_CardMode.ConveyorBelt
	level.start_sun = 0
	level.is_day_sun = false
	level.is_shovel = false
	level.zombie_multy = 3
	level.max_wave = 20
	level.is_bowling_stripe = true
	level.plant_cell_can_use = {
		"left_can_plant": true,
		"left_can_zombie": true,
		"right_can_plant": false,
		"right_can_zombie": true,
	}
	level.conveyor_weights = _weighted_cards([
		["bowling_wallnut", 2],
		["bowling_explode", 1],
		["bowling_big", 1],
	])
	var order: Dictionary[int, ResourceCardReference] = {
		0: ResourceCardReference.create(ResourceCardReference.CardType.Plant, CharacterRegistry.PlantType.P1001WallNutBowling),
		1: ResourceCardReference.create(ResourceCardReference.CardType.Plant, CharacterRegistry.PlantType.P1002WallNutBowlingBomb),
		2: ResourceCardReference.create(ResourceCardReference.CardType.Plant, CharacterRegistry.PlantType.P1003WallNutBowlingBig),
	}
	level.conveyor_order = order


static func _configure_whack(level: ResourceLevelData, seeds: Array) -> void:
	level.monster_mode = ConstLevelData.E_MonsterMode.HammerZombie
	level.zombie_multy_hammer = 1
	level.max_wave_hammer_zombie = maxi(4, level.max_wave)
	level.is_hammer = true
	level.is_have_tombston = true
	level.init_tombstone_num = 9
	level.is_day_sun = false
	level.start_sun = 0
	level.prechosen_cards = _card_array(seeds)


static func _configure_vase(level: ResourceLevelData) -> void:
	level.card_mode = ConstLevelData.E_CardMode.Null
	level.monster_mode = ConstLevelData.E_MonsterMode.Null
	level.is_pot_mode = true
	level.pot_mode = ConstLevelData.E_PotMode.Weight
	level.pot_col_range = Vector2i(6, 9)
	level.is_lawn_mover = false
	level.is_day_sun = false
	level.start_sun = 0
	level.weight_res_fiexd = 1.0
	level.weight_pot_type = Vector3i(6, 2, 2)
	level.is_can_look_random_res_pot = false
	level.is_save_plant_on_pot_mode = false
	var plants: Dictionary[CharacterRegistry.PlantType, int] = {}
	for kind in ["peashooter", "snowpea", "squash", "hypnoshroom"]:
		plants[plant_type(kind)] = 1
	level.candidate_plant_pot = plants
	var zombies: Dictionary[CharacterRegistry.ZombieType, int] = {}
	for kind in ["normal", "bucket"]:
		zombies[zombie_type(kind)] = 1
	level.candidate_zombie_pot = zombies


static func _init_tombstones(level: ResourceLevelData, level_id: int) -> void:
	var rows: Array = ContentDB.garden_adventure.get("graveColumns", [])
	if level_id < 1 or level_id > rows.size():
		return
	var count := 0
	for entry in rows[level_id - 1]:
		if entry is Array and entry.size() >= 2:
			count += int(entry[1])
	if count > 0:
		level.is_have_tombston = true
		level.init_tombstone_num = mini(count, 8)


static func _init_roof_pots(level: ResourceLevelData) -> void:
	var preplants: Array[PrePlantResource] = []
	for column in range(1, 6):
		var entry := PrePlantResource.new()
		entry.plant_type = CharacterRegistry.PlantType.P034FlowerPot
		entry.plant_cell_pos = Vector2i(0, column)
		preplants.append(entry)
	level.all_pre_plant_data = preplants


static func _card_array(seeds: Array) -> Array[ResourceCardReference]:
	var result: Array[ResourceCardReference] = []
	for kind in seeds:
		var id := plant_type(str(kind))
		if id == CharacterRegistry.PlantType.Null:
			continue
		result.append(ResourceCardReference.create(ResourceCardReference.CardType.Plant, id))
	return result


static func _weighted_cards(entries: Array) -> Array[ResourceCardWeight]:
	var result: Array[ResourceCardWeight] = []
	for entry in entries:
		var item := ResourceCardWeight.new()
		var kind := str(entry[0])
		var card_id := CharacterRegistry.PlantType.Null
		match kind:
			"bowling_wallnut":
				card_id = CharacterRegistry.PlantType.P1001WallNutBowling
			"bowling_explode":
				card_id = CharacterRegistry.PlantType.P1002WallNutBowlingBomb
			"bowling_big":
				card_id = CharacterRegistry.PlantType.P1003WallNutBowlingBig
			_:
				card_id = plant_type(kind)
		if card_id == CharacterRegistry.PlantType.Null:
			continue
		item.card_reference = ResourceCardReference.create(ResourceCardReference.CardType.Plant, card_id)
		item.weight = maxi(0, int(entry[1]))
		result.append(item)
	return result


static func _weights_for_conveyor(level_id: int) -> Array[ResourceCardWeight]:
	var key := ""
	match level_id:
		10:
			key = "conveyorTen"
		20:
			key = "conveyorTwenty"
		25:
			key = "conveyorTwentyFive"
		30:
			key = "conveyorThirty"
		40:
			key = "conveyorForty"
		45:
			key = "conveyorFortyFive"
		50:
			key = "conveyorFifty"
	return _weights_from_content(key)


static func _weights_from_content(key: String) -> Array[ResourceCardWeight]:
	var entries: Array = ContentDB.garden_adventure.get(key, [])
	var result: Array[ResourceCardWeight] = []
	for entry in entries:
		if not entry is Dictionary:
			continue
		var card_id := plant_type(str(entry.get("kind", "")))
		if card_id == CharacterRegistry.PlantType.Null:
			continue
		var weight := ResourceCardWeight.new()
		weight.card_reference = ResourceCardReference.create(ResourceCardReference.CardType.Plant, card_id)
		weight.weight = maxi(0, int(entry.get("weight", 1)))
		result.append(weight)
	return result


static func _zombies_for_level(level_id: int) -> Array[CharacterRegistry.ZombieType]:
	var result: Array[CharacterRegistry.ZombieType] = []
	var source: Dictionary = ContentDB.garden_adventure.get("zombies", {})
	for kind in source:
		if kind in ["flag", "backup", "ducky", "yeti", "imp", "bungee"]:
			continue
		if not _level_has_zombie(level_id, str(kind)):
			continue
		var id := zombie_type(str(kind))
		if id != CharacterRegistry.ZombieType.Null and not (id in result):
			result.append(id)
	if result.is_empty():
		result.append(CharacterRegistry.ZombieType.Z001Norm)
	return result


static func _level_has_zombie(level_id: int, kind: String) -> bool:
	var source: Dictionary = ContentDB.garden_adventure.get("zombies", {}).get(kind, {})
	var allowed: Array = source.get("allowedLevels", [])
	var index := level_id - 1
	return index >= 0 and index < allowed.size() and int(allowed[index]) > 0
