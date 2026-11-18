class_name GardenBattleEngine
extends RefCounted

const COLS := 9


func create(player: Dictionary, level_id: int, mode: String, seeds: Array, tutorial: bool = false, difficulty: String = "auto") -> Dictionary:
	var level: Dictionary = ContentDB.garden_levels().get(str(level_id), {})
	var environment := str(level.get("environment", "day")) if mode != "endless" else "day"
	if tutorial:
		environment = "day"
	var rows := 6 if environment in ["pool", "fog"] else 5
	var resolved := GameTuning.resolve(difficulty, [player])
	var grid: Array = []
	var bases: Array = []
	var shells: Array = []
	var mowers: Array = []
	for index in rows * COLS:
		grid.append({})
		bases.append({})
		shells.append({})
	var active_rows: Array = range(rows) if tutorial or mode == "endless" else level.get("rows", range(rows)).duplicate()
	active_rows = active_rows.map(func(value): return int(value))
	for row in rows:
		mowers.append({"row": row, "x": GardenLayout.MOWER_START_COLUMN, "previousX": GardenLayout.MOWER_START_COLUMN, "state": "ready", "age": 0.0})
	var special := str(level.get("mode", "lawn")) if not tutorial and mode != "endless" else "lawn"
	var cards: Array = level.get("seeds", seeds).duplicate() if special != "lawn" else seeds.duplicate()
	var state := {
		"version": 2, "playerId": str(player.id), "player": player.duplicate(true), "levelId": level_id,
		"mode": mode, "environment": environment, "rows": rows, "cols": COLS, "activeRows": active_rows, "special": special,
		"tutorial": tutorial, "tutorialStep": 0, "tutorialZombieSpawned": false, "difficulty": resolved,
		"sun": 150 if tutorial or mode == "endless" else int(level.get("initialSun", 150)), "seeds": cards,
		"selectedSeed": "", "shovel": false, "aimingCannon": -1,
		"grid": grid, "bases": bases, "shells": shells, "zombies": [], "projectiles": [], "suns": [], "coins": [],
		"mowers": mowers, "cooldowns": {}, "graves": [], "craters": [], "ladders": [], "iceTrails": [], "totalSkySun": 0,
		"deaths": [], "debris": [], "packets": [], "rollers": [], "vases": [], "boss": {},
		"phase": "playing", "time": 0.0, "waveIndex": 0, "waveCount": 2147483647 if mode == "endless" else int(level.get("waveCount", 10)),
		"waveTimer": _timing("firstWave", 18.0), "sunTimer": 6.0, "conveyorTimer": .5, "graveTimer": 35.0,
		"fogCleared": 0.0, "stormTimer": 7.0, "lightning": 0.0, "score": 0, "vaseStage": 0,
		"nextUid": 1, "eventUid": 1, "rngState": (Time.get_ticks_usec() ^ int(Time.get_unix_time_from_system())) & 0x7fffffff,
		"waveProgressAt": 0.0, "waveDuration": 1.0, "introStep": 0, "introAge": 0.0,
		"usedMowers": 0, "flags": 0, "bestFlags": 0, "bossSpawned": false, "events": [], "resultStars": 0, "renderPreviousX": {},
		"zombieSpeedMultiplier": float(GameTuning.value("garden", resolved, "zombieSpeed", 1.0)),
		"zombieHealthMultiplier": float(GameTuning.value("garden", resolved, "zombieHealth", 1.0)),
		"sunMultiplier": float(GameTuning.value("garden", resolved, "sunMultiplier", 1.0)),
		"spawnDelta": int(GameTuning.value("garden", resolved, "spawnDelta", 0)),
		"waveIntervalMultiplier": float(GameTuning.value("garden", resolved, "waveInterval", 1.0)), "logicAccumulator": 0.0,
	}
	if environment == "night":
		for column in [5, 7, 8]:
			state.graves.append({"row": _random_row(state, false), "col": column})
	if environment == "roof":
		for row in rows:
			for column in 3:
				state.bases[row * COLS + column] = _new_plant(state, "flowerpot", row, column)
	if special == "vase":
		_prepare_vases(state)
	if level_id == 50 and not tutorial and mode != "endless":
		state.boss = {"health": 40000.0, "maxHealth": 40000.0, "phase": "idle", "timer": 8.0, "row": 2, "age": 0.0, "damageStage": 0, "attack": 0, "ball": {}}
		state.bossSpawned = true
	return state


func _timing(key: String, fallback: float) -> float:
	return float(ContentDB.garden_rules.get("timing", {}).get(key, fallback))


func _definition(kind: String) -> Dictionary:
	return ContentDB.garden_rules.get("plants", {}).get(kind, ContentDB.garden_plants().get(kind, {}))


func _emit(state: Dictionary, kind: String, values: Dictionary = {}) -> void:
	var event := values.duplicate()
	event.type = kind
	event.uid = int(state.eventUid)
	event.time = float(state.time)
	state.eventUid = int(state.eventUid) + 1
	state.events.append(event)


func tick(state: Dictionary, delta: float) -> Array:
	if state.get("phase", "") != "playing":
		return []
	state.events = []
	state.time = float(state.time) + delta
	state.renderPreviousX = {}
	for zombie in state.zombies:
		state.renderPreviousX[str(zombie.uid)] = float(zombie.x)
		zombie.previousX = float(zombie.x)
	for projectile in state.projectiles:
		projectile.previousX = float(projectile.x)
		projectile.previousY = float(projectile.y)
	for key in state.cooldowns.keys():
		state.cooldowns[key] = maxf(0.0, float(state.cooldowns[key]) - delta)
	if int(state.get("introStep", -1)) >= 0:
		state.introAge = clampf(float(state.get("introAge", 0.0)) + delta / 0.6, 0.0, 1.0)
		if float(state.introAge) >= 1.0:
			state.introAge = 0.0
			state.introStep = int(state.introStep) + 1
			if int(state.introStep) >= 3:
				state.introStep = -1
			else:
				AudioFX.play("tap")
	for key in ["waveTimer", "sunTimer", "conveyorTimer", "graveTimer", "fogCleared", "stormTimer", "lightning"]:
		state[key] = maxf(0.0, float(state[key]) - delta)
	if float(state.get("waveDuration", 1.0)) > 0.0:
		state.waveProgressAt = clampf(float(state.get("waveProgressAt", 0.0)) + delta / float(state.waveDuration), 0.0, 1.0)
	if bool(state.get("bannerVisible", false)):
		state.banner.age = clampf(float(state.get("banner", {}).get("age", 0.0)) + delta, 0.0, 1.0)
		if float(state.banner.age) >= 1.0:
			state.bannerVisible = false
	_update_environment(state, delta)
	if bool(state.tutorial):
		if int(state.tutorialStep) == 0 and state.suns.is_empty():
			_spawn_sun(state, 4.5, 25)
		if int(state.tutorialStep) == 5 and not bool(state.tutorialZombieSpawned):
			_spawn_zombie(state, "normal", 2).x = .8
			state.tutorialZombieSpawned = true
	elif str(state.special) != "vase":
		_spawn_logic(state)
	_update_plants(state, delta)
	_update_zombies(state, delta)
	_update_projectiles(state, delta)
	_update_mowers(state, delta)
	_update_collectibles(state, delta)
	_update_rollers(state, delta)
	_update_boss(state, delta)
	for object in state.deaths:
		object.age = float(object.age) + delta
	for object in state.debris:
		object.age = float(object.age) + delta
	state.deaths = state.deaths.filter(func(item): return float(item.age) < 2.2)
	state.debris = state.debris.filter(func(item): return float(item.age) < 1.8)
	if not bool(state.tutorial) and str(state.special) == "vase" and state.vases.is_empty() and state.zombies.is_empty():
		if int(state.vaseStage) < 2:
			state.vaseStage = int(state.vaseStage) + 1
			_prepare_vases(state)
		else:
			_win(state)
	elif not bool(state.tutorial) and state.boss.is_empty() and int(state.waveIndex) >= int(state.waveCount) and state.zombies.is_empty() and str(state.phase) == "playing":
		_win(state)
	return state.events.duplicate(true)


func _win(state: Dictionary) -> void:
	state.phase = "won"
	state.resultStars = 3 if int(state.usedMowers) == 0 else 2 if int(state.usedMowers) == 1 else 1
	_emit(state, "win", {"stars": state.resultStars})


func _spawn_logic(state: Dictionary) -> void:
	if not state.boss.is_empty() or float(state.waveTimer) > 0.0 or int(state.waveIndex) >= int(state.waveCount):
		return
	state.waveIndex = int(state.waveIndex) + 1
	var wave := int(state.waveIndex)
	var amount := maxi(1, mini(12, 1 + wave / 2 + int(state.levelId) / 12 + int(state.spawnDelta)))
	if wave % 10 == 0:
		amount += 3
		_spawn_zombie(state, "flag", _random_row(state, false))
	var candidates: Array = []
	var zombie_data: Dictionary = ContentDB.garden_adventure.get("zombies", {})
	for kind in zombie_data:
		var entry: Dictionary = zombie_data[kind]
		var permitted: Array = entry.get("allowedLevels", [])
		var permitted_level := int(state.levelId) - 1
		if float(entry.get("weight", 0)) <= 0 or int(entry.get("firstAllowedWave", 1)) > wave:
			continue
		if str(state.mode) != "endless" and (permitted_level >= permitted.size() or int(permitted[permitted_level]) == 0):
			continue
		if str(state.mode) == "endless" and int(entry.get("startingLevel", 1)) > wave * 2:
			continue
		if kind in ["snorkel", "dolphin"] and str(state.environment) not in ["pool", "fog"]:
			continue
		candidates.append(kind)
	if candidates.is_empty():
		candidates = ["normal"]
	for offset in amount:
		var kind := str(candidates[_random_int(state, candidates.size())])
		var aquatic := kind in ["snorkel", "dolphin", "ducky"] or str(state.environment) in ["pool", "fog"] and kind in ["normal", "cone", "bucket", "flag"] and _random_int(state, 3) == 0
		var row := _random_row(state, aquatic)
		var zombie := _spawn_zombie(state, kind, row)
		zombie.x = float(zombie.x) + offset * .2
		if str(state.special) == "whack":
			zombie.x = 3.5 + _random_float(state) * 5
			zombie.phase = "rise"
		if int(state.levelId) == 25:
			zombie.mini = true
			for key in ["health", "maxHealth", "armor", "maxArmor", "shield", "maxShield"]:
				zombie[key] = float(zombie[key]) * .25
	if wave % 10 == 0 or wave == int(state.waveCount):
		state.flags = int(state.flags) + 1
		state.bestFlags = maxi(int(state.bestFlags), int(state.flags))
		_emit(state, "flag", {"wave": wave})
		state.banner = {"text": "最后一波！" if wave == int(state.waveCount) else "一大波僵尸正在接近！", "age": 0.0}
		state.bannerVisible = true
	state.waveTimer = maxf(8.0, _timing("waveInterval", 22) - int(state.levelId) * .12) * float(state.waveIntervalMultiplier)
	state.waveDuration = maxf(1.0, float(state.waveTimer))
	state.waveProgressAt = clampf(float(wave - 1) / maxf(1.0, float(state.waveCount)), 0.0, 1.0)


func _spawn_zombie(state: Dictionary, kind: String, row: int, custom_health: float = 0.0, boss: bool = false, spawn_group: bool = true) -> Dictionary:
	var stats: Dictionary = ContentDB.garden_rules.get("zombies", {}).get(kind, ContentDB.garden_rules.get("zombies", {}).get("normal", {}))
	var health := (custom_health if custom_health > 0 else float(stats.get("body", 270))) * float(state.zombieHealthMultiplier)
	var zombie := {
		"uid": int(state.nextUid), "kind": kind, "row": row, "x": 9.45 + _random_float(state) * .5, "previousX": 9.45,
		"health": health, "maxHealth": health, "armor": float(stats.get("armor", 0)) * float(state.zombieHealthMultiplier),
		"maxArmor": float(stats.get("armor", 0)) * float(state.zombieHealthMultiplier), "shield": float(stats.get("shield", 0)) * float(state.zombieHealthMultiplier),
		"maxShield": float(stats.get("shield", 0)) * float(state.zombieHealthMultiplier), "speed": float(stats.get("speed", .23)) * float(state.zombieSpeedMultiplier),
		"damage": float(stats.get("biteDamage", 20)), "attackTimer": .2, "slowTimer": 0.0, "frozenTimer": 0.0, "butterTimer": 0.0,
		"age": 0.0, "animationTime": _random_float(state) * 1.5, "actionAge": 0.0, "phase": "walk", "eating": false, "hasArm": true, "hasHead": true,
		"hypnotized": false, "backwards": false, "flying": kind == "balloon", "underground": kind == "digger", "jumped": false,
		"hasPole": kind == "pole", "hasDolphin": kind == "dolphin", "hasPogo": kind == "pogo", "metalRemoved": false,
		"summonTimer": 2.0, "specialTimer": 12.0 + _random_float(state) * 10, "thrown": false, "target": -1, "hitAt": -10.0, "boss": boss,
	}
	state.nextUid = int(state.nextUid) + 1
	state.zombies.append(zombie)
	if kind == "bungee":
		zombie.phase = "down"
		zombie.x = float(1 + _random_int(state, 7)) + .5
		zombie.target = int(zombie.row) * COLS + int(zombie.x)
	if kind == "bobsled" and spawn_group:
		zombie.sledUid = int(zombie.uid)
		zombie.sledActive = state.iceTrails.any(func(trail): return int(trail.row) == row)
		for offset in range(1, 4):
			var follower := _spawn_zombie(state, "bobsled", row, 0, false, false)
			follower.sledUid = int(zombie.uid)
			follower.sledActive = bool(zombie.sledActive)
			follower.x = float(zombie.x) + float(offset) * .42
			follower.armor = 0.0
			follower.maxArmor = 0.0
	zombie.ammo = 20
	return zombie


func _update_environment(state: Dictionary, delta: float) -> void:
	if str(state.environment) in ["day", "pool"] and float(state.sunTimer) <= 0 and str(state.special) == "lawn":
		_spawn_sun(state, _random_float(state) * 7.8, roundi(25.0 * float(state.sunMultiplier)))
		state.sunTimer = _timing("skySun", 9.0) + _random_float(state) * 3.0
		state.totalSkySun = int(state.get("totalSkySun", 0)) + 1
	if str(state.special) in ["conveyor", "bowling"] and float(state.conveyorTimer) <= 0.0 and state.packets.size() < 10:
		var cards: Array = state.seeds
		if not cards.is_empty():
			state.packets.append({"uid": int(state.nextUid), "kind": str(cards[_random_int(state, cards.size())]), "age": 0.0})
			state.nextUid = int(state.nextUid) + 1
		state.conveyorTimer = _timing("conveyorInterval", 5.0)
	if int(state.levelId) == 40 and float(state.stormTimer) <= 0:
		state.lightning = .45
		state.stormTimer = 5.0 + _random_float(state) * 4
		_emit(state, "thunder")
	if str(state.environment) == "night" and float(state.graveTimer) <= 0.0 and state.graves.size() < 12:
		var column := 4 + _random_int(state, 5)
		var row := _random_row(state, false)
		var index := row * COLS + column
		if state.grid[index].is_empty() and state.bases[index].is_empty():
			state.graves.append({"row": row, "col": column})
		state.graveTimer = _timing("graveInterval", 35.0)
	for crater in state.craters:
		crater.remaining = float(crater.remaining) - delta
	state.craters = state.craters.filter(func(item): return float(item.remaining) > 0)
	for trail in state.iceTrails:
		trail.remaining = float(trail.remaining) - delta
	state.iceTrails = state.iceTrails.filter(func(item): return float(item.remaining) > 0)
	for packet in state.packets:
		packet.age = float(packet.age) + delta


func _water_row(state: Dictionary, row: int) -> bool:
	return str(state.environment) in ["pool", "fog"] and row in [2, 3]


func _random_row(state: Dictionary, water: bool) -> int:
	var rows: Array = state.activeRows.filter(func(row): return _water_row(state, int(row)) == water)
	if rows.is_empty():
		rows = state.activeRows
	return int(rows[_random_int(state, maxi(1, rows.size()))])


func _new_plant(state: Dictionary, kind: String, row: int, column: int) -> Dictionary:
	var definition := _definition(kind)
	var plant := {"uid": int(state.nextUid), "kind": kind, "row": row, "col": column, "health": float(definition.get("health", 300)), "maxHealth": float(definition.get("health", 300)), "age": 0.0, "timer": 0.0, "attackTimer": .7, "actionAge": 0.0, "phase": "idle", "shotAt": -10.0, "hitAt": -10.0, "awake": false, "target": -1, "remaining": 0.0, "tall": false, "aimRow": row, "aimX": 8.0, "burst": []}
	state.nextUid = int(state.nextUid) + 1
	if kind == "potatomine":
		plant.phase = "unarmed"
		plant.remaining = float(definition.get("armSeconds", 15))
	if kind == "sunshroom":
		plant.remaining = 120.0
	return plant


func sleeping(state: Dictionary, plant: Dictionary) -> bool:
	return str(plant.get("kind", "")) in ContentDB.garden_rules.get("mushrooms", []) and str(state.environment) in ["day", "pool", "roof"] and not bool(plant.get("awake", false))


func can_plant(state: Dictionary, row: int, column: int, kind: String) -> String:
	if str(state.phase) != "playing":
		return "战斗已经结束"
	if row not in state.activeRows or column < 0 or column >= COLS:
		return "这里不能种植"
	if not ContentDB.garden_plants().has(kind):
		return "先选一张植物卡"
	var free_card := str(state.special) in ["conveyor", "bowling", "vase"]
	if not free_card and kind not in state.seeds:
		return "这张卡不在本局卡组里"
	if free_card and not state.packets.any(func(packet): return str(packet.kind) == kind):
		return "先等植物卡到达"
	if not free_card and int(state.sun) < int(_definition(kind).get("cost", 0)):
		return "阳光不够"
	if not free_card and float(state.cooldowns.get(kind, 0)) > 0:
		return "卡片还在准备"
	if str(state.special) == "bowling":
		return "请在红线左侧放出坚果" if column > 2 else ""
	var index := row * COLS + column
	var existing: Dictionary = state.grid[index]
	var base: Dictionary = state.bases[index]
	var shell: Dictionary = state.shells[index]
	if state.craters.any(func(item): return int(item.row) == row and int(item.col) == column):
		return "弹坑还没有恢复"
	if state.iceTrails.any(func(item): return int(item.row) == row and float(item.x) <= column):
		return "冰道上不能种植"
	var grave: bool = state.graves.any(func(item): return int(item.row) == row and int(item.col) == column)
	if kind == "gravebuster":
		return "" if grave else "吞噬者要种在墓碑上"
	if grave:
		return "先清理墓碑"
	var water := _water_row(state, row)
	var aquatic := kind in ["lilypad", "tanglekelp", "seashroom"]
	if water and aquatic:
		if not base.is_empty() or not existing.is_empty() or not shell.is_empty():
			return "请种在空的水面上"
		return ""
	if water and not aquatic:
		if kind == "cattail":
			if base.is_empty() or str(base.get("kind", "")) != "lilypad":
				return "香蒲需要一片空睡莲"
			if not existing.is_empty():
				return "香蒲需要一片空睡莲"
		elif kind in ["potatomine", "spikeweed", "spikerock"]:
			return "这种植物不能种在水上"
		elif base.is_empty():
			return "水面要先种睡莲"
	if aquatic and not water:
		return "这种植物只能种在水面"
	if kind == "flowerpot":
		if str(state.environment) != "roof":
			return "花盆只能种在屋顶"
		return "这里已经有承托植物" if not base.is_empty() or not existing.is_empty() else ""
	if str(state.environment) == "roof":
		if kind in ["spikeweed", "spikerock", "lilypad", "seashroom", "tanglekelp", "gravebuster"]:
			return "这种植物不能种在屋顶"
		if kind != "flowerpot" and base.is_empty():
			return "屋顶要先放花盆"
	if kind == "coffeebean":
		return "" if not existing.is_empty() and sleeping(state, existing) else "咖啡豆用来唤醒蘑菇"
	if kind == "pumpkin":
		return "这里已经有南瓜" if not shell.is_empty() else ""
	if kind == "cattail":
		if base.is_empty() or str(base.get("kind", "")) != "lilypad":
			return "香蒲需要一片空睡莲"
		return "" if existing.is_empty() else "香蒲需要一片空睡莲"
	var upgrades: Dictionary = ContentDB.garden_rules.get("upgrades", {})
	if upgrades.has(kind):
		var required := str(upgrades[kind])
		if existing.is_empty() or str(existing.kind) != required:
			return "要先种下" + str(_definition(required).get("name", required))
		if kind == "cobcannon" and (column >= 8 or state.grid[index + 1].is_empty() or str(state.grid[index + 1].get("kind", "")) != "kernelpult" or not shell.is_empty()):
			return "需要左右相邻的两株玉米投手"
		return ""
	if not existing.is_empty():
		return "这一格已经有植物"
	if column > 0 and str(state.grid[index - 1].get("kind", "")) == "cobcannon":
		return "玉米加农炮占用两格"
	return ""


func plant(state: Dictionary, row: int, col: int, kind: String) -> Dictionary:
	if bool(state.get("shovel", false)):
		return shovel(state, row, col)
	var reason := can_plant(state, row, col, kind)
	if not reason.is_empty():
		return {"ok": false, "reason": reason}
	var index := row * COLS + col
	var free_card := str(state.special) in ["conveyor", "bowling", "vase"]
	if free_card:
		for packet in state.packets:
			if str(packet.kind) == kind:
				state.packets.erase(packet)
				break
	else:
		state.sun = int(state.sun) - int(_definition(kind).get("cost", 0))
		state.cooldowns[kind] = float(_definition(kind).get("cooldownSeconds", 7.5))
	if str(state.special) == "bowling":
		state.rollers.append({"uid": int(state.nextUid), "kind": kind, "row": row, "x": float(col), "previousX": float(col), "direction": 0, "hits": [], "age": 0.0})
		state.nextUid = int(state.nextUid) + 1
	elif kind == "coffeebean":
		state.grid[index].awake = true
		state.grid[index].phase = "wake"
		state.grid[index].remaining = 1.0
		_emit(state, "coffee", {"row": row, "col": col})
	else:
		var planted := _new_plant(state, kind, row, col)
		if kind in ["lilypad", "flowerpot"]:
			state.bases[index] = planted
		elif kind == "pumpkin":
			state.shells[index] = planted
		else:
			if kind == "cobcannon":
				state.grid[index + 1] = {}
			state.grid[index] = planted
	state.selectedSeed = ""
	_emit(state, "plant", {"row": row, "col": col, "kind": kind, "water": _water_row(state, row)})
	return {"ok": true, "kind": kind, "row": row, "col": col}


func shovel(state: Dictionary, row: int, col: int, target_uid: int = -1) -> Dictionary:
	if row < 0 or row >= int(state.rows) or col < 0 or col >= COLS:
		return {"ok": false, "reason": "这里不能铲除"}
	var index := row * COLS + col
	if col > 0 and state.grid[index].is_empty() and str(state.grid[index - 1].get("kind", "")) == "cobcannon":
		index -= 1
	for layer in ["bases", "shells", "grid"]:
		if not state[layer][index].is_empty() and (target_uid < 0 or int(state[layer][index].get("uid", -1)) == target_uid):
			state[layer][index] = {}
			state.shovel = false
			_emit(state, "shovel", {"row": row, "col": col})
			return {"ok": true}
	state.shovel = false
	return {"ok": false, "reason": "这里没有植物"}


func _spawn_sun(state: Dictionary, x: float, value: int, row: float = -0.3) -> void:
	state.suns.append({"uid": int(state.nextUid), "x": x, "y": row, "targetY": 1.0 + _random_float(state) * maxf(1, int(state.rows) - 2), "value": value, "ttl": _timing("sunLifetime", 10), "age": 0.0, "collecting": false, "collectAge": 0.0})
	state.nextUid = int(state.nextUid) + 1


func collect_sun(state: Dictionary, uid: int) -> Dictionary:
	for sun in state.suns:
		if int(sun.uid) == uid and not bool(sun.collecting):
			state.sun = int(state.sun) + int(sun.value)
			sun.collecting = true
			var collect_from := GardenLayout.point(state, float(sun.x) + .5, float(sun.y) + .2)
			sun.collectX = collect_from.x
			sun.collectY = collect_from.y
			sun.collectAge = 0.0
			_emit(state, "sun", {"row": int(sun.y), "col": int(sun.x)})
			return {"ok": true, "value": int(sun.value)}
	return {"ok": false}


func _update_collectibles(state: Dictionary, delta: float) -> void:
	for sun in state.suns:
		sun.age = float(sun.age) + delta
		sun.y = minf(float(sun.targetY), float(sun.y) + delta * 1.2)
		sun.ttl = float(sun.ttl) - delta
		if bool(sun.collecting):
			sun.collectAge = float(sun.collectAge) + delta
	state.suns = state.suns.filter(func(sun): return float(sun.ttl) > 0 and (not bool(sun.collecting) or float(sun.collectAge) < .35))
	for coin in state.coins:
		coin.age = float(coin.age) + delta
	state.coins = state.coins.filter(func(coin): return float(coin.age) < 12.0)


func collect_coin(state: Dictionary, uid: int) -> bool:
	for coin in state.coins:
		if int(coin.uid) == uid:
			state.score = int(state.score) + int(coin.value)
			state.coins.erase(coin)
			_emit(state, "coin")
			return true
	return false


func _targets(state: Dictionary, row: int, column: float, distance: float = 10.0, direction: int = 1, aerial: bool = false) -> Array:
	var found: Array = []
	for zombie in state.zombies:
		if int(zombie.row) != row or bool(zombie.hypnotized) or float(zombie.health) <= 0 or bool(zombie.underground):
			continue
		if bool(zombie.flying) != aerial:
			continue
		if str(zombie.kind) == "snorkel" and not bool(zombie.eating) and float(zombie.x) < 9.0:
			continue
		var gap := (float(zombie.x) - column) * direction
		if gap >= -.35 and gap <= distance:
			found.append(zombie)
	found.sort_custom(func(left, right): return float(left.x) * direction < float(right.x) * direction)
	return found


func _update_plants(state: Dictionary, delta: float) -> void:
	for layer in ["bases", "grid", "shells"]:
		for index in state[layer].size():
			var plant: Dictionary = state[layer][index]
			if plant.is_empty():
				continue
			plant.age = float(plant.age) + delta
			plant.actionAge = float(plant.actionAge) + delta
			plant.attackTimer = maxf(0.0, float(plant.attackTimer) - delta)
			plant.timer = float(plant.timer) + delta
			plant.remaining = maxf(0.0, float(plant.remaining) - delta)
			if float(plant.health) <= 0:
				state[layer][index] = {}
				continue
			if layer != "grid" or sleeping(state, plant):
				continue
			var kind := str(plant.kind)
			var row := int(plant.row)
			var column := int(plant.col)
			if str(plant.phase) == "wake" and float(plant.remaining) > 0:
				continue
			if not plant.burst.is_empty():
				for shot in plant.burst.duplicate():
					if float(state.time) >= float(shot.at):
						_fire(state, plant, str(shot.kind), int(shot.row), int(shot.direction))
						plant.burst.erase(shot)
			if kind in ["sunflower", "twinsunflower", "sunshroom", "marigold"]:
				var interval := 7.0 if float(plant.age) < 12.0 else float(_definition(kind).intervalSeconds)
				if float(plant.timer) >= interval:
					plant.timer = 0.0
					plant.shotAt = float(state.time)
					if kind == "marigold":
						state.coins.append({"uid": int(state.nextUid), "x": float(column) + .5, "row": row, "age": 0.0, "value": 50})
						state.nextUid = int(state.nextUid) + 1
					else:
						var amount := 50 if kind == "twinsunflower" else 15 if kind == "sunshroom" and float(plant.age) < 120 else 25
						_spawn_sun(state, float(column), roundi(amount * float(state.sunMultiplier)), float(row) + .2)
						state.suns[-1].targetY = float(row) + .55
				continue
			if kind in ["cherrybomb", "jalapeno", "iceshroom", "doomshroom"]:
				if float(plant.age) >= 1.0:
					_explode_plant(state, plant)
					state.grid[index] = {}
				continue
			if kind == "potatomine":
				if float(plant.remaining) <= 0:
					plant.phase = "idle"
					if not _nearby(state, row, column + .5, .7, 0).is_empty():
						_area_damage(state, row, column + .5, .8, 1800, "explode", false)
						state.grid[index] = {}
				continue
			if kind == "gravebuster":
				if float(plant.age) >= 4.0:
					state.graves = state.graves.filter(func(grave): return int(grave.row) != row or int(grave.col) != column)
					state.grid[index] = {}
				continue
			if kind == "chomper":
				if str(plant.phase) == "digest":
					if float(plant.remaining) <= 0:
						plant.phase = "idle"
					continue
				if str(plant.phase) == "bite":
					if float(plant.remaining) <= 0:
						var victim := _zombie_by_id(state, int(plant.target))
						if not victim.is_empty():
							_damage_zombie(state, victim, 99999, "swallow", true)
						plant.phase = "digest"
						plant.remaining = float(_definition(kind).digestSeconds)
					continue
				var close := _targets(state, row, column + .5, 1.0)
				if not close.is_empty():
					plant.phase = "bite"
					plant.actionAge = 0.0
					plant.remaining = .7
					plant.target = int(close[0].uid)
				continue
			if kind in ["squash", "tanglekelp"]:
				if str(plant.phase) == "attack":
					if float(plant.remaining) <= 0:
						var victim := _zombie_by_id(state, int(plant.target))
						if not victim.is_empty():
							if kind == "squash":
								_area_damage(state, row, float(victim.x), .8, 1800, "squash", false)
							else:
								_damage_zombie(state, victim, 99999, "drown", true)
						state.grid[index] = {}
					continue
				var close := _nearby(state, row, column + .5, 1.15, 0)
				if not close.is_empty():
					plant.phase = "attack"
					plant.actionAge = 0.0
					plant.target = int(close[0].uid)
					plant.remaining = 1.0
					if kind == "tanglekelp":
						close[0].frozenTimer = 1.0
				continue
			if kind in ["spikeweed", "spikerock"]:
				if float(plant.attackTimer) <= 0:
					for zombie in _nearby(state, row, column + .5, .65, 0):
						var vehicle: bool = str(zombie.kind) in ["zomboni", "catapult", "bobsled"]
						_damage_zombie(state, zombie, 1800 if vehicle else 40 if kind == "spikerock" else 20, "spike", true)
						if vehicle:
							plant.health = float(plant.health) - (50 if kind == "spikerock" else float(plant.maxHealth))
					plant.attackTimer = 1.0
				continue
			if kind == "blover":
				if float(plant.age) >= .5:
					state.fogCleared = 24.0
					for zombie in state.zombies:
						if bool(zombie.flying):
							_damage_zombie(state, zombie, 99999, "blown", true)
					if float(plant.age) >= 2.0:
						state.grid[index] = {}
				continue
			if kind in ["magnetshroom", "goldmagnet"]:
				if float(plant.attackTimer) <= 0:
					if kind == "goldmagnet":
						for coin in state.coins.duplicate():
							collect_coin(state, int(coin.uid))
					else:
						for zombie in state.zombies:
							if absf(float(zombie.x) - column - .5) < 3 and absi(int(zombie.row) - row) <= 1 and not bool(zombie.metalRemoved) and str(zombie.kind) in ["bucket", "football", "door", "ladder", "pogo", "digger", "jack"]:
								_drop_part(state, zombie, "metal")
								zombie.armor = 0.0
								zombie.shield = 0.0
								zombie.metalRemoved = true
								zombie.hasPogo = false
								zombie.underground = false
								plant.shotAt = float(state.time)
								break
					plant.attackTimer = 15.0 if kind == "magnetshroom" else 2.5
				continue
			if kind in ["wallnut", "tallnut", "pumpkin", "garlic", "hypnoshroom", "lilypad", "flowerpot", "torchwood", "plantern", "umbrella"]:
				continue
			if kind == "cobcannon":
				continue
			if kind == "scaredyshroom":
				var scared := not _nearby(state, row, column + .5, 1.6, 1).is_empty()
				plant.phase = "scared" if scared else "idle"
				if scared:
					continue
			if float(plant.attackTimer) > 0:
				continue
			var distance := float(_definition(kind).get("range", 9))
			var front := _targets(state, row, column + .5, distance)
			var aerial := _targets(state, row, column + .5, distance, 1, true)
			plant.tall = kind == "cactus" and not aerial.is_empty()
			if kind == "cattail":
				var all_targets: Array = state.zombies.filter(func(zombie): return not bool(zombie.hypnotized) and not bool(zombie.underground) and float(zombie.health) > 0)
				if not all_targets.is_empty():
					_fire(state, plant, "homing", int(all_targets[0].row), 1, all_targets[0])
			elif kind == "starfruit":
				if not state.zombies.is_empty():
					for direction in [Vector2(-1, 0), Vector2(0, -1), Vector2(0, 1), Vector2(1, -.7), Vector2(1, .7)]:
						var projectile := _fire(state, plant, "star", row)
						projectile.vx = direction.x * 4.0
						projectile.vy = direction.y * 4.0
			elif kind in ["fumeshroom", "gloomshroom"]:
				var nearby := _nearby(state, row, column + .5, 1.5 if kind == "gloomshroom" else 3.0, 1 if kind == "gloomshroom" else 0)
				for zombie in nearby:
					if kind == "gloomshroom" or float(zombie.x) >= column + .2:
						_damage_zombie(state, zombie, 80 if kind == "gloomshroom" else 20, "fume", true)
				if not nearby.is_empty():
					_emit(state, "fume", {"row": row, "col": column, "kind": kind})
					plant.shotAt = float(state.time)
			elif kind == "threepeater":
				for target_row in range(maxi(0, row - 1), mini(int(state.rows), row + 2)):
					if not _targets(state, target_row, column + .5).is_empty():
						_fire(state, plant, "pea", target_row)
			else:
				if kind == "splitpea" and not _targets(state, row, column + .5, 9, -1).is_empty():
					_fire(state, plant, "pea", row, -1)
				if kind == "cactus" and not aerial.is_empty():
					_fire(state, plant, "spike", row, 1, aerial[0]).high = true
				elif not front.is_empty():
					var projectile_kind := "ice" if kind == "snowpea" else "puff" if kind in ["puffshroom", "scaredyshroom", "seashroom"] else "spike" if kind == "cactus" else "pea"
					if kind in ["cabbagepult", "kernelpult", "melonpult", "wintermelon"]:
						projectile_kind = {"cabbagepult": "cabbage", "kernelpult": "kernel", "melonpult": "melon", "wintermelon": "wintermelon"}[kind]
						if kind == "kernelpult" and _random_int(state, 4) == 0:
							projectile_kind = "butter"
					_fire(state, plant, projectile_kind, row, 1, front[0])
					var repeats := 3 if kind == "gatlingpea" else 1 if kind == "repeater" else 0
					for repeat in repeats:
						plant.burst.append({"at": float(state.time) + (repeat + 1) * .12, "kind": projectile_kind, "row": row, "direction": 1})
			plant.attackTimer = float(_definition(kind).get("intervalSeconds", 1.45))


func _nearby(state: Dictionary, row: int, column: float, radius: float, row_radius: int) -> Array:
	return state.zombies.filter(func(zombie): return float(zombie.health) > 0 and not bool(zombie.hypnotized) and not bool(zombie.flying) and not bool(zombie.underground) and absi(int(zombie.row) - row) <= row_radius and absf(float(zombie.x) - column) <= radius)


func _zombie_by_id(state: Dictionary, uid: int) -> Dictionary:
	for zombie in state.zombies:
		if int(zombie.uid) == uid and float(zombie.health) > 0:
			return zombie
	return {}


func _fire(state: Dictionary, plant: Dictionary, kind: String, row: int, direction: int = 1, target: Dictionary = {}) -> Dictionary:
	var start_x := float(plant.col) + .8
	var projectile := {"uid": int(state.nextUid), "kind": kind, "row": row, "x": start_x, "previousX": start_x, "y": float(row) + .42, "previousY": float(row) + .42, "vx": _timing("projectileSpeed", 4.1) * direction, "vy": 0.0, "age": 0.0, "life": 4.0, "damage": 20.0, "high": false, "target": int(target.get("uid", -1)), "lob": kind in ["cabbage", "kernel", "butter", "melon", "wintermelon", "basketball", "cannon"], "startX": start_x, "startY": float(row) + .35, "endX": float(target.get("x", 8.0)), "endY": float(row) + .45, "duration": 1.2, "hit": false, "torch": -1}
	if kind in ["melon", "wintermelon"]:
		projectile.damage = 80.0
	elif kind == "cabbage":
		projectile.damage = 40.0
	elif kind == "butter":
		projectile.damage = 40.0
	if kind == "puff":
		projectile.life = .8
	if bool(projectile.lob):
		projectile.startY = float(plant.get("row", row)) + .35
		projectile.y = float(projectile.startY)
		projectile.previousY = float(projectile.startY)
	state.nextUid = int(state.nextUid) + 1
	state.projectiles.append(projectile)
	plant.shotAt = float(state.time)
	_emit(state, "shoot", {"row": row, "col": int(plant.col), "kind": kind})
	return projectile


func aim_cannon(state: Dictionary, index: int, row: int, column: int) -> bool:
	if index < 0 or index >= state.grid.size():
		return false
	var plant: Dictionary = state.grid[index]
	if str(plant.get("kind", "")) != "cobcannon" or float(plant.attackTimer) > 0:
		return false
	var projectile := _fire(state, plant, "cannon", row)
	projectile.endX = float(column) + .5
	projectile.endY = float(row) + .5
	projectile.duration = 2.0
	projectile.damage = 1800.0
	plant.attackTimer = float(_definition("cobcannon").intervalSeconds)
	state.aimingCannon = -1
	return true


func _explode_plant(state: Dictionary, plant: Dictionary) -> void:
	var kind := str(plant.kind)
	var row := int(plant.row)
	var column := float(plant.col) + .5
	if kind == "iceshroom":
		for zombie in state.zombies:
			zombie.frozenTimer = 4.0
			zombie.slowTimer = 20.0
			_damage_zombie(state, zombie, 20, "ice", true)
		if not state.boss.is_empty():
			state.boss.frozenTimer = 4.0
			if str(state.boss.ball.get("kind", "")) == "fire":
				state.boss.ball = {}
	elif kind == "jalapeno":
		for zombie in state.zombies:
			if int(zombie.row) == row:
				_damage_zombie(state, zombie, 1800, "burn", true)
		state.iceTrails = state.iceTrails.filter(func(trail): return int(trail.row) != row)
		if not state.boss.is_empty() and int(state.boss.ball.get("row", -1)) == row and str(state.boss.ball.get("kind", "")) == "ice":
			state.boss.ball = {}
	else:
		_area_damage(state, row, column, 3.0 if kind == "doomshroom" else 1.5, 1800, "burn", true)
		if kind == "doomshroom":
			state.craters.append({"row": row, "col": int(plant.col), "remaining": 180.0})
	if not state.boss.is_empty() and str(state.boss.phase) == "head":
		state.boss.health = float(state.boss.health) - 1800
	_emit(state, "freeze" if kind == "iceshroom" else "explode", {"row": row, "col": int(plant.col), "kind": kind})


func _area_damage(state: Dictionary, row: int, column: float, radius: float, damage: float, reason: String, adjacent: bool) -> void:
	for zombie in state.zombies:
		if bool(zombie.hypnotized) or float(zombie.health) <= 0:
			continue
		if absf(float(zombie.x) - column) <= radius and absi(int(zombie.row) - row) <= (int(floor(radius)) if adjacent else 0):
			_damage_zombie(state, zombie, damage, reason, true)


func _damage_zombie(state: Dictionary, zombie: Dictionary, damage: float, reason: String = "pea", bypass: bool = false) -> void:
	if float(zombie.health) <= 0:
		return
	var remaining := damage
	if not bypass and float(zombie.shield) > 0:
		var shield_damage := minf(float(zombie.shield), remaining)
		zombie.shield = float(zombie.shield) - shield_damage
		remaining -= shield_damage
		if float(zombie.shield) <= 0:
			_drop_part(state, zombie, "shield")
			if str(zombie.kind) == "newspaper":
				zombie.phase = "rage"
				zombie.actionAge = 0.0
	if float(zombie.armor) > 0 and remaining > 0:
		var armor_damage := minf(float(zombie.armor), remaining)
		zombie.armor = float(zombie.armor) - armor_damage
		remaining -= armor_damage
		if float(zombie.armor) <= 0:
			_drop_part(state, zombie, "helmet")
	zombie.health = float(zombie.health) - remaining
	zombie.hitAt = float(state.time)
	var can_lose: bool = ContentDB.garden_rules.get("zombies", {}).get(str(zombie.kind), {}).get("canLoseParts", false)
	if can_lose and float(zombie.health) > 0 and reason not in ["burn", "mower", "swallow", "drown"]:
		if bool(zombie.hasArm) and float(zombie.health) < float(zombie.maxHealth) * 2.0 / 3.0:
			zombie.hasArm = false
			_drop_part(state, zombie, "arm")
		if bool(zombie.hasHead) and float(zombie.health) < float(zombie.maxHealth) / 3.0:
			zombie.hasHead = false
			zombie.actionAge = 0.0
			_drop_part(state, zombie, "head")
	if float(zombie.health) <= 0:
		_kill_zombie(state, zombie, reason)
	_emit(state, "hit", {"row": int(zombie.row), "col": float(zombie.x), "kind": reason})


func _drop_part(state: Dictionary, zombie: Dictionary, part: String) -> void:
	state.debris.append({"uid": int(state.nextUid), "kind": str(zombie.kind), "part": part, "row": int(zombie.row), "x": float(zombie.x), "age": 0.0, "poseTime": float(zombie.animationTime)})
	state.nextUid = int(state.nextUid) + 1
	_emit(state, "part", {"row": int(zombie.row), "col": float(zombie.x), "part": part})


func _kill_zombie(state: Dictionary, zombie: Dictionary, reason: String) -> void:
	if bool(zombie.get("deadRecorded", false)):
		return
	zombie.health = 0.0
	zombie.deadRecorded = true
	var corpse := zombie.duplicate(true)
	corpse.age = 0.0
	corpse.reason = reason
	if reason != "swallow":
		state.deaths.append(corpse)
	state.score = int(state.score) + 10
	if str(zombie.kind) == "yeti":
		state.coins.append({"uid": int(state.nextUid), "x": float(zombie.x), "row": int(zombie.row), "age": 0.0, "value": 1000})
		state.nextUid = int(state.nextUid) + 1


func _food(state: Dictionary, row: int, position: float) -> Dictionary:
	for layer in ["shells", "grid", "bases"]:
		for column in COLS:
			var plant: Dictionary = state[layer][row * COLS + column]
			if plant.is_empty() or float(plant.health) <= 0 or str(plant.kind) in ["spikeweed", "spikerock", "tanglekelp"]:
				continue
			if state.ladders.any(func(ladder): return int(ladder.row) == row and int(ladder.col) == column):
				continue
			var extent := 1.15 if str(plant.kind) == "cobcannon" else .65
			if absf(position - float(column) - .5) < extent:
				return {"plant": plant, "layer": layer, "index": row * COLS + column}
	return {}


func _umbrella(state: Dictionary, row: int, column: float) -> bool:
	for plant in state.grid:
		if not plant.is_empty() and str(plant.kind) == "umbrella" and absi(int(plant.row) - row) <= 1 and absf(float(plant.col) + .5 - column) <= 1.5:
			plant.shotAt = float(state.time)
			return true
	return false


func _update_zombies(state: Dictionary, delta: float) -> void:
	for zombie in state.zombies.duplicate():
		if float(zombie.health) <= 0:
			continue
		zombie.age = float(zombie.age) + delta
		zombie.actionAge = float(zombie.actionAge) + delta
		zombie.specialTimer = float(zombie.specialTimer) - delta
		zombie.summonTimer = float(zombie.summonTimer) - delta
		for key in ["slowTimer", "frozenTimer", "butterTimer", "attackTimer"]:
			zombie[key] = maxf(0.0, float(zombie[key]) - delta)
		var slowed := .45 if float(zombie.slowTimer) > 0 else 1.0
		if float(zombie.frozenTimer) > 0 or float(zombie.butterTimer) > 0:
			continue
		zombie.animationTime = float(zombie.animationTime) + delta * slowed
		var row := int(zombie.row)
		var kind := str(zombie.kind)
		var direction := 1.0 if bool(zombie.hypnotized) or bool(zombie.backwards) else -1.0
		if not bool(zombie.hasHead):
			zombie.eating = false
			zombie.x = float(zombie.x) + direction * float(zombie.speed) * delta * slowed
			zombie.health = float(zombie.health) - float(zombie.maxHealth) / 9.0 * delta
			if float(zombie.health) <= 0:
				_kill_zombie(state, zombie, "normal")
			continue
		if kind == "bungee":
			if _umbrella(state, row, float(zombie.x)):
				_damage_zombie(state, zombie, 99999, "blocked", true)
			elif str(zombie.phase) == "down" and float(zombie.actionAge) >= 2.0:
				zombie.phase = "wait"
				zombie.actionAge = 0.0
			elif str(zombie.phase) == "wait" and float(zombie.actionAge) >= 1.0:
				var index := clampi(int(zombie.target), 0, state.grid.size() - 1)
				state.grid[index] = {}
				zombie.phase = "up"
				zombie.actionAge = 0.0
			elif str(zombie.phase) == "up" and float(zombie.actionAge) >= 2.0:
				zombie.health = 0.0
			continue
		if bool(zombie.underground):
			zombie.x = float(zombie.x) - float(zombie.speed) * delta
			if float(zombie.x) < .5:
				zombie.underground = false
				zombie.backwards = true
				zombie.phase = "rise"
				zombie.actionAge = 0.0
			continue
		if str(zombie.phase) in ["jump", "rise", "land", "thrown", "rage", "place", "smash", "throw", "garlic"]:
			if str(zombie.phase) == "jump":
				zombie.x = float(zombie.x) - delta * 1.8
			elif str(zombie.phase) == "thrown":
				zombie.x = float(zombie.x) - delta * 2
			var duration := 2.0 if str(zombie.phase) == "thrown" else 1.0
			if float(zombie.actionAge) >= duration:
				match str(zombie.phase):
					"jump":
						zombie.speed = (.3 if kind == "dolphin" else .23) * float(state.zombieSpeedMultiplier)
					"rage":
						zombie.speed = .66 * float(state.zombieSpeedMultiplier)
					"place":
						state.ladders.append({"row": row, "col": int(zombie.target) % COLS})
						zombie.shield = 0.0
					"smash":
						var target := _food(state, row, float(zombie.x))
						if not target.is_empty():
							target.plant.health = 0.0
							_emit(state, "smash", {"row": row, "col": int(target.plant.col)})
					"throw":
						var imp := _spawn_zombie(state, "imp", row)
						imp.x = float(zombie.x) - .2
						imp.phase = "thrown"
					"garlic":
						zombie.row = int(zombie.get("nextRow", row))
				zombie.phase = "walk"
				zombie.actionAge = 0.0
			continue
		if kind == "yeti" and float(zombie.age) > 12:
			zombie.backwards = true
			direction = 1.0
		if kind == "gargantuar" and not bool(zombie.thrown) and float(zombie.health) < float(zombie.maxHealth) * .5:
			zombie.thrown = true
			zombie.phase = "throw"
			zombie.actionAge = 0.0
			continue
		if kind == "jack" and not bool(zombie.metalRemoved) and float(zombie.specialTimer) <= 0:
			for layer in ["grid", "shells", "bases"]:
				for plant in state[layer]:
					if not plant.is_empty() and absi(int(plant.row) - row) <= 1 and absf(float(plant.col) + .5 - float(zombie.x)) < 1.3:
						plant.health = 0.0
			_damage_zombie(state, zombie, 99999, "burn", true)
			_emit(state, "explode", {"row": row, "col": float(zombie.x), "kind": "jack"})
			continue
		if kind == "jack" and not bool(zombie.metalRemoved) and float(zombie.specialTimer) <= 1.1:
			if str(zombie.phase) != "open":
				zombie.phase = "open"
				zombie.actionAge = 0.0
			continue
		if kind == "bobsled" and bool(zombie.get("sledActive", false)):
			var leader := _zombie_by_id(state, int(zombie.get("sledUid", zombie.uid)))
			var has_ice: bool = state.iceTrails.any(func(trail): return int(trail.row) == row and float(trail.x) <= float(zombie.x))
			var obstruction := _food(state, row, float(zombie.x))
			if leader.is_empty() or float(leader.armor) <= 0 or not has_ice or not obstruction.is_empty():
				for member in state.zombies:
					if int(member.get("sledUid", -1)) == int(zombie.get("sledUid", zombie.uid)):
						member.sledActive = false
						member.phase = "land"
						member.actionAge = 0.0
			else:
				zombie.x = float(zombie.x) - .6 * delta
			continue
		if kind == "dancer" and float(zombie.summonTimer) <= 0 and float(zombie.x) < 8.5:
			for offset in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]:
				var next_row := row + int(offset.y)
				if next_row in state.activeRows and not _water_row(state, next_row):
					var follower := _spawn_zombie(state, "backup", next_row)
					follower.x = float(zombie.x) + offset.x
					follower.phase = "rise"
					follower.leader = int(zombie.uid)
			zombie.summonTimer = 12.0
			zombie.phase = "summon"
			zombie.actionAge = 0.0
		if kind == "dancer" and str(zombie.phase) == "summon" and float(zombie.actionAge) < 2:
			continue
		if kind == "backup" and zombie.has("leader"):
			var leader := _zombie_by_id(state, int(zombie.leader))
			if not leader.is_empty() and (bool(leader.eating) or float(leader.frozenTimer) > 0 or str(leader.phase) == "summon" and float(leader.actionAge) < 2):
				continue
		if kind == "catapult" and float(zombie.x) < 8.6 and int(zombie.get("ammo", 20)) > 0:
			if float(zombie.attackTimer) <= 0:
				var victim: Dictionary = {}
				for plant in state.grid:
					if not plant.is_empty() and int(plant.row) == row:
						victim = plant
						break
				if not victim.is_empty():
					var launcher := {"row": row, "col": float(zombie.x) - .8, "shotAt": float(state.time)}
					var shot := _fire(state, launcher, "basketball", row)
					shot.endX = float(victim.col) + .5
					shot.vx = -4.0
					zombie.ammo = int(zombie.get("ammo", 20)) - 1
				zombie.attackTimer = 3.0
				zombie.phase = "shoot"
				zombie.actionAge = 0.0
			continue
		if bool(zombie.hypnotized):
			var rival: Dictionary = {}
			for other in state.zombies:
				if not bool(other.hypnotized) and int(other.row) == row and float(other.health) > 0 and absf(float(other.x) - float(zombie.x)) < .6:
					rival = other
					break
			if not rival.is_empty():
				zombie.eating = true
				if float(zombie.attackTimer) <= 0:
					_damage_zombie(state, rival, 20, "bite", true)
					zombie.attackTimer = .2
				continue
		var target := {} if bool(zombie.flying) or bool(zombie.hypnotized) else _food(state, row, float(zombie.x))
		if not target.is_empty():
			var food: Dictionary = target.plant
			if kind in ["pole", "dolphin"] and not bool(zombie.jumped) and str(food.kind) != "tallnut":
				zombie.jumped = true
				zombie.hasPole = false
				zombie.hasDolphin = false
				zombie.phase = "jump"
				zombie.actionAge = 0.0
				continue
			if kind == "pogo" and bool(zombie.hasPogo) and str(food.kind) != "tallnut":
				zombie.x = float(zombie.x) - .9
				continue
			if kind == "ladder" and float(zombie.shield) > 0 and str(food.kind) in ["wallnut", "tallnut", "pumpkin"]:
				zombie.phase = "place"
				zombie.actionAge = 0.0
				zombie.target = int(target.index)
				continue
			if kind == "gargantuar":
				zombie.phase = "smash"
				zombie.actionAge = 0.0
				continue
			if kind == "zomboni":
				food.health = 0.0
				zombie.x = float(zombie.x) - float(zombie.speed) * delta
			else:
				zombie.eating = true
				if float(zombie.attackTimer) <= 0:
					if str(food.kind) == "hypnoshroom" and not sleeping(state, food):
						zombie.hypnotized = true
						food.health = 0.0
						_emit(state, "hypnotize", {"row": row, "col": int(food.col)})
					else:
						food.health = float(food.health) - float(zombie.damage)
						food.hitAt = float(state.time)
						_emit(state, "eat", {"row": row, "col": int(food.col)})
						if str(food.kind) == "garlic":
							var choices: Array = state.activeRows.filter(func(candidate): return absi(int(candidate) - row) == 1 and _water_row(state, int(candidate)) == _water_row(state, row))
							if not choices.is_empty():
								zombie.nextRow = int(choices[_random_int(state, choices.size())])
								zombie.phase = "garlic"
								zombie.actionAge = 0.0
					zombie.attackTimer = .2 / slowed
		else:
			zombie.eating = false
			zombie.x = float(zombie.x) + direction * float(zombie.speed) * delta * slowed
		if kind == "zomboni":
			var found := false
			for trail in state.iceTrails:
				if int(trail.row) == row:
					trail.x = minf(float(trail.x), float(zombie.x))
					trail.remaining = 30.0
					found = true
			if not found:
				state.iceTrails.append({"row": row, "x": float(zombie.x), "remaining": 30.0})
		if float(zombie.x) > 10.5 and (bool(zombie.backwards) or bool(zombie.hypnotized)):
			zombie.health = 0.0
		if float(zombie.x) < -.6 and not bool(zombie.hypnotized) and not bool(zombie.backwards):
			state.phase = "lost"
			_emit(state, "lost")
	state.zombies = state.zombies.filter(func(zombie): return float(zombie.health) > 0)


func _update_projectiles(state: Dictionary, delta: float) -> void:
	for projectile in state.projectiles:
		projectile.age = float(projectile.age) + delta
		if bool(projectile.lob):
			var ratio := minf(1, float(projectile.age) / float(projectile.duration))
			projectile.x = lerpf(float(projectile.startX), float(projectile.endX), ratio)
			projectile.y = lerpf(float(projectile.startY), float(projectile.endY), ratio) - sin(ratio * PI) * 1.5
			if ratio >= 1:
				_lob_impact(state, projectile)
				projectile.hit = true
			continue
		if str(projectile.kind) == "homing":
			var target := _zombie_by_id(state, int(projectile.target))
			if target.is_empty():
				projectile.hit = true
				continue
			var direction := (Vector2(float(target.x), float(target.row) + .4) - Vector2(float(projectile.x), float(projectile.y))).normalized()
			projectile.vx = direction.x * 4.5
			projectile.vy = direction.y * 4.5
		projectile.x = float(projectile.x) + float(projectile.vx) * delta
		projectile.y = float(projectile.y) + float(projectile.vy) * delta
		if str(projectile.kind) in ["pea", "ice"]:
			for plant in state.grid:
				if not plant.is_empty() and str(plant.kind) == "torchwood" and int(plant.row) == int(projectile.row) and int(plant.uid) != int(projectile.torch) and _crossed(float(projectile.previousX), float(projectile.x), float(plant.col) + .5, .2):
					projectile.kind = "pea" if str(projectile.kind) == "ice" else "fire"
					projectile.damage = 40.0 if str(projectile.kind) == "fire" else 20.0
					projectile.torch = int(plant.uid)
		var hit_target: Dictionary = {}
		for zombie in state.zombies:
			if bool(zombie.hypnotized) or bool(zombie.underground) or float(zombie.health) <= 0:
				continue
			if bool(zombie.flying) != bool(projectile.high) and str(projectile.kind) != "homing":
				continue
			if str(zombie.kind) == "snorkel" and not bool(zombie.eating) and float(zombie.x) < 9:
				continue
			if absf(float(projectile.y) - float(zombie.row) - .42) > .4:
				continue
			if str(state.environment) == "roof" and float(projectile.x) < 4 and str(projectile.kind) in ["pea", "ice", "fire", "puff"] and float(projectile.age) > .35:
				projectile.hit = true
				break
			if _crossed(float(projectile.previousX), float(projectile.x), float(zombie.x), .28):
				if hit_target.is_empty() or absf(float(zombie.x) - float(projectile.previousX)) < absf(float(hit_target.x) - float(projectile.previousX)):
					hit_target = zombie
		if not hit_target.is_empty():
			if bool(hit_target.flying):
				hit_target.flying = false
				hit_target.phase = "land"
				hit_target.actionAge = 0.0
				if _water_row(state, int(hit_target.row)):
					_damage_zombie(state, hit_target, 99999, "drown", true)
			if str(projectile.kind) == "fire":
				_area_damage(state, int(hit_target.row), float(hit_target.x), .65, float(projectile.damage), "fire", false)
			else:
				_damage_zombie(state, hit_target, float(projectile.damage), str(projectile.kind))
			if str(projectile.kind) == "ice" and float(hit_target.shield) <= 0:
				hit_target.slowTimer = 10.0
			projectile.hit = true
		if not state.boss.is_empty() and str(state.boss.phase) == "head" and int(projectile.row) == int(state.boss.row) and float(projectile.x) > 8:
			state.boss.health = float(state.boss.health) - float(projectile.damage)
			projectile.hit = true
	state.projectiles = state.projectiles.filter(func(projectile): return not bool(projectile.hit) and float(projectile.age) < float(projectile.life) and float(projectile.x) > -1 and float(projectile.x) < 11 and float(projectile.y) > -2 and float(projectile.y) < int(state.rows) + 1)


func _crossed(start: float, finish: float, target: float, radius: float) -> bool:
	return minf(start, finish) - radius <= target and maxf(start, finish) + radius >= target


func _lob_impact(state: Dictionary, projectile: Dictionary) -> void:
	var row := int(projectile.row)
	var column := float(projectile.endX)
	var kind := str(projectile.kind)
	if kind == "basketball":
		if not _umbrella(state, row, column):
			var target := _food(state, row, column)
			if not target.is_empty():
				target.plant.health = float(target.plant.health) - 75
		return
	var radius := 1.5 if kind == "cannon" else 1.1 if kind in ["melon", "wintermelon"] else .6
	for zombie in state.zombies:
		if not bool(zombie.hypnotized) and not bool(zombie.flying) and not bool(zombie.underground) and absi(int(zombie.row) - row) <= (1 if kind in ["melon", "wintermelon", "cannon"] else 0) and absf(float(zombie.x) - column) <= radius:
			_damage_zombie(state, zombie, float(projectile.damage), "explode" if kind == "cannon" else kind, true)
			if kind == "butter":
				zombie.butterTimer = 4.0
			if kind == "wintermelon":
				zombie.slowTimer = 10.0
	if not state.boss.is_empty() and str(state.boss.phase) == "head" and column > 7:
		state.boss.health = float(state.boss.health) - float(projectile.damage)
	_emit(state, "explode" if kind == "cannon" else "hit", {"row": row, "col": column, "kind": kind})


func trigger_mower(state: Dictionary, row: int) -> void:
	if row < 0 or row >= state.mowers.size():
		return
	var mower: Dictionary = state.mowers[row]
	if str(mower.state) == "ready":
		mower.state = "moving"
		mower.age = 0.0
		state.usedMowers = int(state.usedMowers) + 1
		_emit(state, "mower", {"row": row, "col": float(mower.x)})


func _update_mowers(state: Dictionary, delta: float) -> void:
	for mower in state.mowers:
		var row := int(mower.row)
		if str(mower.state) == "ready":
			for zombie in state.zombies:
				if int(zombie.row) == row and float(zombie.x) < .12 and not bool(zombie.flying) and not bool(zombie.underground) and not bool(zombie.hypnotized) and str(zombie.kind) != "bungee":
					trigger_mower(state, row)
		if str(mower.state) != "moving":
			continue
		mower.previousX = float(mower.x)
		mower.x = float(mower.x) + _timing("mowerSpeed", 7) * delta
		mower.age = float(mower.age) + delta
		for zombie in state.zombies:
			if int(zombie.row) == row and not bool(zombie.flying) and not bool(zombie.underground) and not bool(zombie.hypnotized) and _crossed(float(mower.previousX), float(mower.x), float(zombie.x), .55):
				_damage_zombie(state, zombie, 99999, "mower", true)
		if float(mower.x) > 10:
			mower.state = "spent"


func _prepare_vases(state: Dictionary) -> void:
	state.vases = []
	var stages: Array = ContentDB.garden_adventure.get("vaseStages", [])
	var stage: Dictionary = stages[mini(stages.size() - 1, int(state.vaseStage))] if not stages.is_empty() else {}
	var contents: Array = []
	for entry in stage.get("contents", []):
		for amount in int(entry.get("count", 1)):
			contents.append(entry.duplicate(true))
	for index in range(contents.size() - 1, 0, -1):
		var chosen := _random_int(state, index + 1)
		var previous: Dictionary = contents[index]
		contents[index] = contents[chosen]
		contents[chosen] = previous
	var count := 0
	for row in int(state.rows):
		for column in range(int(stage.get("firstColumn", 3)), 9):
			var content: Dictionary = contents[count % contents.size()].duplicate(true) if not contents.is_empty() else {"type": "seed", "kind": "peashooter"}
			state.vases.append({"row": row, "col": column, "content": content, "green": str(content.get("type", "")) == "seed" and count < int(stage.get("green", 0))})
			count += 1


func handle_cell(state: Dictionary, row: int, column: int) -> Dictionary:
	if str(state.special) == "vase":
		for vase in state.vases:
			if int(vase.row) == row and int(vase.col) == column:
				var content: Dictionary = vase.content
				if str(content.get("type", "")) == "zombie":
					_spawn_zombie(state, str(content.kind), row).x = float(column) + .5
				else:
					state.packets.append({"uid": int(state.nextUid), "kind": str(content.get("kind", "peashooter")), "age": 0.0})
					state.nextUid = int(state.nextUid) + 1
				state.vases.erase(vase)
				_emit(state, "vase", {"row": row, "col": column})
				return {"ok": true}
	if str(state.special) == "whack":
		for zombie in state.zombies:
			if int(zombie.row) == row and absf(float(zombie.x) - column - .5) < .7:
				_damage_zombie(state, zombie, 900, "hammer")
				if float(zombie.health) <= 0:
					_spawn_sun(state, float(column), 25, float(row))
				return {"ok": true}
	if int(state.aimingCannon) >= 0:
		return {"ok": aim_cannon(state, int(state.aimingCannon), row, column)}
	var index := row * COLS + column
	if index >= 0 and index < state.grid.size() and str(state.grid[index].get("kind", "")) == "cobcannon" and float(state.grid[index].get("attackTimer", 1)) <= 0:
		state.aimingCannon = index
		return {"ok": true}
	return plant(state, row, column, str(state.selectedSeed))


func _update_rollers(state: Dictionary, delta: float) -> void:
	for roller in state.rollers:
		roller.previousX = float(roller.x)
		roller.x = float(roller.x) + delta * 3.2
		roller.age = float(roller.age) + delta
		for zombie in state.zombies:
			if int(zombie.row) == int(roller.row) and int(zombie.uid) not in roller.hits and _crossed(float(roller.previousX), float(roller.x), float(zombie.x), .4):
				roller.hits.append(int(zombie.uid))
				if str(roller.kind) == "explodenut":
					_area_damage(state, int(roller.row), float(roller.x), 1.5, 1800, "burn", true)
					roller.x = 12.0
				else:
					_damage_zombie(state, zombie, 900 if float(zombie.armor) > 0 else 1800, "roller", true)
					var direction := 1 if int(roller.row) == 0 else -1 if int(roller.row) == int(state.rows) - 1 else (1 if _random_int(state, 2) == 0 else -1)
					roller.row = clampi(int(roller.row) + direction, 0, int(state.rows) - 1)
	state.rollers = state.rollers.filter(func(roller): return float(roller.x) < 11)


func _update_boss(state: Dictionary, delta: float) -> void:
	if state.boss.is_empty():
		return
	var boss: Dictionary = state.boss
	if float(boss.health) <= 0:
		state.zombies = []
		_win(state)
		return
	boss.frozenTimer = maxf(0, float(boss.get("frozenTimer", 0)) - delta)
	if float(boss.frozenTimer) > 0:
		return
	boss.actionAge = float(boss.get("actionAge", 0)) + delta
	boss.age = float(boss.age) + delta
	boss.timer = float(boss.timer) - delta
	boss.damageStage = 2 if float(boss.health) < float(boss.maxHealth) * .5 else 1 if float(boss.health) < float(boss.maxHealth) * .8 else 0
	if not boss.ball.is_empty():
		boss.ball.age = float(boss.ball.get("age", 0)) + delta
		if _umbrella(state, int(boss.ball.row), float(boss.ball.x)):
			boss.ball = {}
			_emit(state, "explode", {"row": int(boss.row), "col": 7.0, "kind": "umbrella"})
			return
		boss.ball.x = float(boss.ball.x) - delta * 1.5
		var target := _food(state, int(boss.ball.row), float(boss.ball.x))
		if not target.is_empty():
			target.plant.health = 0.0
		if float(boss.ball.x) < -.5:
			state.phase = "lost"
			_emit(state, "lost")
	if float(boss.timer) > 0:
		return
	boss.actionAge = 0.0
	boss.attack = int(boss.attack) + 1
	var action := int(boss.attack) % 4
	if action == 0:
		boss.phase = "head"
		boss.row = _random_row(state, false)
		boss.timer = 12.0
		boss.ball = {"kind": "fire" if _random_int(state, 2) == 0 else "ice", "row": int(boss.row), "x": 8.8, "age": 0.0}
	elif action == 1:
		boss.phase = "idle"
		boss.timer = 8.0
		for offset in 3:
			_spawn_zombie(state, ["normal", "cone", "bucket"][_random_int(state, 3)], _random_row(state, false))
	elif action == 2:
		boss.phase = "stomp"
		boss.timer = 8.0
		var target_row := _random_row(state, false)
		for plant in state.grid:
			if not plant.is_empty() and int(plant.row) == target_row and int(plant.col) >= 5:
				plant.health = 0
		for offset in 2:
			_spawn_zombie(state, "bungee", _random_row(state, false))
	else:
		boss.phase = "head"
		boss.row = _random_row(state, false)
		boss.timer = 15.0
	state.waveIndex = int(state.waveIndex) + 1
	_emit(state, "boss", {"row": int(boss.row), "col": 8})


func snapshot(state: Dictionary) -> Dictionary:
	var result := state.duplicate(true)
	result.events = []
	result.renderPreviousX = {}
	return result


func restore(raw: Variant, player: Dictionary = {}) -> Dictionary:
	if not raw is Dictionary or not raw.get("grid") is Array or not raw.get("zombies") is Array:
		return {}
	if not _numbers(raw, ["rows", "levelId"]) or not raw.get("seeds", []) is Array or not raw.get("player", player) is Dictionary:
		return {}
	var selected_player: Dictionary = raw.get("player", player)
	if selected_player.is_empty() or not selected_player.get("id") is String or not _numbers(selected_player, ["age"]) or int(raw.get("rows", 0)) not in [5, 6] or raw.grid.size() != int(raw.rows) * COLS:
		return {}
	var clean := create(selected_player, clampi(int(raw.get("levelId", 1)), 1, 50), str(raw.get("mode", "adventure")), raw.get("seeds", []), bool(raw.get("tutorial", false)), str(raw.get("difficulty", "auto")))
	if int(raw.get("version", 1)) >= 2:
		if int(raw.get("version", 0)) != 2:
			return {}
		clean.merge(raw.duplicate(true), true)
		if not clean.get("activeRows") is Array:
			return {}
		for value in clean.activeRows:
			if typeof(value) not in [TYPE_INT, TYPE_FLOAT]:
				return {}
		clean.activeRows = clean.activeRows.map(func(value): return int(value))
		if clean.activeRows.is_empty() or clean.activeRows.any(func(row): return int(row) < 0 or int(row) >= int(clean.rows)):
			return {}
		for layer in ["grid", "bases", "shells"]:
			if not clean.get(layer) is Array or clean[layer].size() != int(clean.rows) * COLS:
				return {}
			for plant in clean[layer]:
				if not plant is Dictionary:
					return {}
				if plant.is_empty():
					continue
				for key in ["uid", "kind", "row", "col", "health", "maxHealth", "age", "timer", "attackTimer", "actionAge", "phase", "shotAt", "hitAt", "awake", "remaining", "burst"]:
					if not plant.has(key):
						return {}
				if not ContentDB.garden_plants().has(str(plant.kind)) or not plant.burst is Array:
					return {}
				if not _numbers(plant, ["uid", "row", "col", "health", "maxHealth", "age", "timer", "attackTimer", "actionAge", "shotAt", "hitAt", "remaining"]) or int(plant.row) < 0 or int(plant.row) >= int(clean.rows) or int(plant.col) < 0 or int(plant.col) >= COLS:
					return {}
		if not clean.get("zombies") is Array:
			return {}
		for zombie in clean.zombies:
			if not zombie is Dictionary:
				return {}
			for key in ["uid", "kind", "row", "x", "health", "maxHealth", "armor", "maxArmor", "shield", "maxShield", "age", "animationTime", "phase", "eating", "flying", "underground", "hasHead", "hasArm", "previousX", "actionAge", "slowTimer", "frozenTimer", "butterTimer", "attackTimer", "speed", "damage", "specialTimer", "summonTimer", "hypnotized", "backwards", "jumped", "hasPole", "hasDolphin", "hasPogo", "metalRemoved", "thrown"]:
				if not zombie.has(key):
					return {}
			if int(zombie.row) < 0 or int(zombie.row) >= int(clean.rows) or not ContentDB.garden_rules.zombies.has(str(zombie.kind)):
				return {}
			if not _numbers(zombie, ["uid", "row", "x", "health", "maxHealth", "armor", "maxArmor", "shield", "maxShield", "age", "animationTime", "previousX", "actionAge", "slowTimer", "frozenTimer", "butterTimer", "attackTimer", "speed", "damage", "specialTimer", "summonTimer"]):
				return {}
		for key in ["projectiles", "mowers", "suns", "deaths", "debris", "packets", "vases"]:
			if not clean.get(key) is Array:
				return {}
			if clean[key].any(func(item): return not item is Dictionary):
				return {}
		if clean.mowers.size() != int(clean.rows):
			return {}
		for mower in clean.mowers:
			if not mower.has("state") or not mower.has("row") or not mower.has("x") or not mower.has("previousX") or not mower.has("age"):
				return {}
			if str(mower.state) == "ready":
				mower.x = GardenLayout.MOWER_START_COLUMN
				mower.previousX = GardenLayout.MOWER_START_COLUMN
		var collections := {
			"projectiles": ["uid", "kind", "row", "x", "previousX", "y", "previousY", "vx", "vy", "age", "life", "damage", "high", "target", "lob", "startX", "startY", "endX", "endY", "duration", "hit", "torch"],
			"suns": ["uid", "x", "y", "targetY", "value", "ttl", "age", "collecting", "collectAge"],
			"coins": ["uid", "x", "row", "age", "value"],
			"debris": ["uid", "kind", "part", "row", "x", "age"],
			"packets": ["uid", "kind", "age"],
			"vases": ["row", "col", "content", "green"],
			"rollers": ["uid", "kind", "row", "x", "previousX", "hits", "age"],
			"graves": ["row", "col"], "ladders": ["row", "col"], "iceTrails": ["row", "x", "remaining"], "craters": ["row", "col", "remaining"],
		}
		for collection in collections:
			if not clean.get(collection) is Array:
				return {}
			for item in clean[collection]:
				if not item is Dictionary:
					return {}
				for key in collections[collection]:
					if not item.has(key):
						return {}
		if not clean.get("boss") is Dictionary:
			return {}
		if not clean.get("cooldowns") is Dictionary or not _numbers(clean, ["time", "waveIndex", "waveTimer", "waveCount", "sunTimer", "eventUid", "rngState", "nextUid", "sun", "waveProgressAt", "waveDuration", "totalSkySun"]):
			return {}
		if not clean.get("banner", {}) is Dictionary:
			return {}
		if not clean.boss.is_empty():
			for key in ["health", "maxHealth", "phase", "timer", "row", "age", "damageStage", "attack", "ball"]:
				if not clean.boss.has(key):
					return {}
			if not clean.boss.ball is Dictionary:
				return {}
			if not _numbers(clean.boss, ["health", "maxHealth", "timer", "row", "age", "damageStage", "attack"]):
				return {}
		clean.events = []
		clean.renderPreviousX = {}
		return clean
	for key in ["sun", "time", "waveIndex", "waveTimer", "sunTimer", "cooldowns", "rngState", "sessionId", "tutorialStep", "usedMowers", "flags", "phase", "totalSkySun", "waveProgressAt", "waveDuration", "introStep", "introAge", "banner", "bannerVisible"]:
		if raw.has(key):
			clean[key] = raw[key]
	if raw.has("banner") and raw.banner is Dictionary:
		clean.banner = {"text": str(raw.banner.get("text", "")), "age": clampf(float(raw.banner.get("age", 0.0)), 0.0, 1.0)}
		clean.bannerVisible = bool(raw.get("bannerVisible", false)) and not str(clean.banner.text).is_empty()
	for index in raw.grid.size():
		if not raw.grid[index] is Dictionary or raw.grid[index].is_empty():
			continue
		var old: Dictionary = raw.grid[index]
		var kind := str(old.get("kind", ""))
		if not ContentDB.garden_plants().has(kind):
			continue
		var row := int(index / COLS)
		var column: int = index % COLS
		var plant := _new_plant(clean, kind, row, column)
		plant.merge(old, true)
		var layer := "bases" if kind in ["lilypad", "flowerpot"] else "shells" if kind == "pumpkin" else "grid"
		clean[layer][index] = plant
		if layer == "grid" and (_water_row(clean, row) or str(clean.environment) == "roof"):
			clean.bases[index] = _new_plant(clean, "lilypad" if _water_row(clean, row) else "flowerpot", row, column)
	clean.zombies = []
	for old in raw.zombies:
		if not old is Dictionary:
			continue
		var zombie := _spawn_zombie(clean, str(old.get("kind", "normal")), clampi(int(old.get("row", 0)), 0, int(clean.rows) - 1))
		zombie.x = float(old.get("x", 9.5))
		var ratio := clampf(float(old.get("health", 1)) / maxf(1, float(old.get("maxHealth", 1))), 0, 1)
		_damage_zombie(clean, zombie, (float(zombie.health) + float(zombie.armor) + float(zombie.shield)) * (1 - ratio))
	for row in mini(raw.get("mowers", []).size(), clean.mowers.size()):
		clean.mowers[row].state = "ready" if bool(raw.mowers[row]) else "spent"
	clean.events = []
	return clean


func _numbers(object: Dictionary, fields: Array) -> bool:
	for key in fields:
		if not object.has(key) or typeof(object[key]) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(object[key])):
			return false
	return true


func _random_int(state: Dictionary, maximum: int) -> int:
	state.rngState = (int(state.rngState) * 1103515245 + 12345) & 0x7fffffff
	return int(state.rngState) % maxi(1, maximum)


func _random_float(state: Dictionary) -> float:
	state.rngState = (int(state.rngState) * 1103515245 + 12345) & 0x7fffffff
	return float(int(state.rngState) & 0xffff) / 65535.0
