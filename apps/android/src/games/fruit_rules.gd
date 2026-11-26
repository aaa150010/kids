class_name FruitRules
extends GameSession

const NORMAL_RADIUS := 0.055
const BOMB_RADIUS := 0.06
const GRAVITY := 1.62
const MAX_ACTIVE := 12
const MAX_SPAWN_QUEUE := 24
const DEFAULT_BOMB_PENALTY := 5
const DEFAULT_BONUS_POINTS := 50

const FALLBACK_FRUITS := [
	{"id":"watermelon","name":"西瓜","color":"#58a85c","flesh":"#ee6f65","leaf":"#2f6d42","shape":"watermelon"},
	{"id":"apple","name":"苹果","color":"#d9534f","flesh":"#ffe0b8","leaf":"#4e8c48","shape":"apple"},
	{"id":"orange","name":"橙子","color":"#e99032","flesh":"#ffd18d","leaf":"#3f824d","shape":"orange"},
	{"id":"strawberry","name":"草莓","color":"#d84e62","flesh":"#ffd3d7","leaf":"#4a8a48","shape":"strawberry"},
	{"id":"banana","name":"香蕉","color":"#e5bb3d","flesh":"#fff1b5","leaf":"#8a7c31","shape":"banana"},
	{"id":"grape","name":"葡萄","color":"#82549b","flesh":"#d9b9e8","leaf":"#4c7c46","shape":"grape"},
	{"id":"pear","name":"梨","color":"#a6bf54","flesh":"#f5f2bd","leaf":"#4a8249","shape":"pear"},
	{"id":"peach","name":"桃子","color":"#e99a78","flesh":"#ffd6bd","leaf":"#4f8d4b","shape":"peach"},
	{"id":"pineapple","name":"菠萝","color":"#c99535","flesh":"#ffe092","leaf":"#3c7a43","shape":"pineapple"},
	{"id":"mango","name":"芒果","color":"#e8b83f","flesh":"#ffe7ab","leaf":"#4f8248","shape":"mango"},
	{"id":"kiwi","name":"奇异果","color":"#8c713a","flesh":"#a7d56d","leaf":"#4a7e43","shape":"kiwi"},
	{"id":"lemon","name":"柠檬","color":"#d8c43e","flesh":"#fff4b0","leaf":"#4d8247","shape":"lemon"},
]


func create_session(context: Dictionary) -> Dictionary:
	super.create_session(context)
	var mode := str(context.get("modeId", "practice"))
	if not mode in ["practice", "challenge"]:
		mode = "practice"
	var difficulty := str(context.get("difficulty", "normal"))
	if not difficulty in ["easy", "normal", "challenge"]:
		var context_players: Variant = context.get("players", [])
		difficulty = GameTuning.resolve("auto", context_players if context_players is Array else [])
	var content: Variant = context.get("fruitData")
	if not content is Dictionary:
		content = ContentDB.get("fruit_data")
	var content_data: Dictionary = content if content is Dictionary else {}
	var specials: Variant = content_data.get("specials", {})
	var config := _sanitize_config(context.get("config"), difficulty, specials if specials is Dictionary else {})
	var palette_source: Variant = context.get("fruitTypes", content_data.get("fruits", ContentDB.fruit_types()))
	var palette := _sanitize_palette(palette_source)
	var initial_remaining := float(config.challengeSeconds) if mode == "challenge" else 0.0
	state.merge({
		"snapshotVersion": 2,
		"gameId": "fruit_slice",
		"modeId": mode,
		"phase": "ready",
		"score": 0,
		"combo": 0,
		"maxCombo": 0,
		"sliced": 0,
		"missed": 0,
		"bombs": 0,
		"remaining": initial_remaining,
		"elapsed": 0.0,
		"nextSpawn": 0.55,
		"spawned": 0,
		"fruits": [],
		"events": [],
		"spawnQueue": [],
		"config": config,
		"palette": palette,
		"difficulty": difficulty,
		"lastSliceAt": -99.0,
		"comboWindow": float(config.comboWindow),
		"startedOnce": false,
		"reported": false,
		"wave": 1,
		"waveSpawned": 0,
		"winner": -1,
	}, true)
	state.erase("fruitTypes")
	state.erase("fruitData")
	_ensure_spawn_queue(10)
	_sync_rng_state()
	return state


func handle_input(action: Dictionary) -> Dictionary:
	var kind := str(action.get("type", ""))
	if kind == "start" and str(state.get("phase", "")) == "ready":
		state.phase = "playing"
		state.startedOnce = true
		state.score = 0
		state.combo = 0
		state.maxCombo = 0
		state.sliced = 0
		state.missed = 0
		state.bombs = 0
		state.elapsed = 0.0
		state.lastSliceAt = -99.0
		state.nextSpawn = 0.25
		state.fruits = []
		state.wave = 1
		state.waveSpawned = 0
		state.reported = false
		if str(state.modeId) == "challenge":
			state.remaining = float(state.config.challengeSeconds)
		else:
			state.remaining = 0.0
		state.events = []
		_ensure_spawn_queue(10)
		_sync_rng_state()
		return {"ok": true, "started": true, "changed": true}
	if kind == "slice" and str(state.get("phase", "")) == "playing":
		return _slice_segment(action.get("from"), action.get("to"), bool(action.get("tap", false)))
	if kind == "finish":
		return _finish("手动结束")
	return {"ok": false, "changed": false}


func tick(delta: float) -> bool:
	if str(state.get("phase", "")) != "playing":
		return false
	var step := clampf(delta, 0.0, 0.12)
	if step <= 0.0:
		return false
	state.elapsed = float(state.elapsed) + step
	if int(state.get("combo", 0)) > 0:
		var last_slice := float(state.get("lastSliceAt", -99.0))
		if last_slice < 0.0 or float(state.elapsed) - last_slice > float(state.get("comboWindow", 0.46)):
			state.combo = 0
	if str(state.get("modeId", "")) == "challenge":
		state.remaining = maxf(0.0, float(state.get("remaining", 0.0)) - step)
	var changed := false
	var kept: Array = []
	var fruit_values: Variant = state.get("fruits", [])
	var fruit_array: Array = fruit_values if fruit_values is Array else []
	for raw in fruit_array:
		if not raw is Dictionary:
			continue
		var fruit: Dictionary = raw
		var radius := maxf(0.02, float(fruit.get("radius", NORMAL_RADIUS)))
		fruit.y = float(fruit.get("y", 0.0)) + float(fruit.get("vy", 0.0)) * step
		fruit.x = float(fruit.get("x", 0.0)) + float(fruit.get("vx", 0.0)) * step
		fruit.rotation = float(fruit.get("rotation", 0.0)) + float(fruit.get("spin", 0.0)) * step
		fruit.vy = float(fruit.get("vy", 0.0)) + GRAVITY * step
		if float(fruit.y) - radius > 1.15:
			if str(fruit.get("special", "")) != "bomb":
				state.missed = int(state.get("missed", 0)) + 1
				state.combo = 0
				state.lastSliceAt = -99.0
				_add_event({"type":"miss", "x":float(fruit.get("x", 0.5)), "y":minf(1.08, float(fruit.y))})
			changed = true
			continue
		kept.append(fruit)
	state.fruits = kept
	if str(state.get("modeId", "")) == "challenge" and float(state.remaining) <= 0.0:
		_sync_rng_state()
		_finish("挑战时间到")
		return true
	if str(state.get("modeId", "")) == "practice":
		var waves := maxi(1, int(state.config.practiceWaves))
		var total := maxi(1, int(state.config.practiceFruits))
		var per_wave := maxi(1, int(ceil(float(total) / float(waves))))
		if int(state.waveSpawned) >= per_wave and state.fruits.is_empty():
			if int(state.wave) < waves:
				state.wave = int(state.wave) + 1
				state.waveSpawned = 0
				state.nextSpawn = float(state.elapsed) + 0.72
				_add_event({"type":"wave", "wave":int(state.wave)})
				changed = true
			elif int(state.spawned) >= total:
				_sync_rng_state()
				_finish("三波水果练习完成")
				return true
		if (
			int(state.waveSpawned) < per_wave
			and int(state.spawned) < total
			and float(state.elapsed) >= float(state.nextSpawn)
			and int(state.fruits.size()) < int(state.config.maxFruits)
		):
			_spawn_one()
			state.nextSpawn = float(state.elapsed) + float(state.config.spawnDelay)
			changed = true
	else:
		if (
			float(state.elapsed) >= float(state.nextSpawn)
			and int(state.fruits.size()) < int(state.config.maxFruits)
		):
			var count := 2 if random.generator.randf() < 0.35 else 1
			for _index in range(count):
				if int(state.fruits.size()) >= int(state.config.maxFruits):
					break
				_spawn_one()
			state.nextSpawn = float(state.elapsed) + maxf(0.32, float(state.config.spawnDelay))
			changed = true
	_sync_rng_state()
	return changed


func _slice_segment(from_value: Variant, to_value: Variant, tap: bool = false) -> Dictionary:
	if not (from_value is Dictionary and to_value is Dictionary):
		return {"ok": false, "changed": false}
	if not (_finite_number(from_value.get("x")) and _finite_number(from_value.get("y"))):
		return {"ok": false, "changed": false}
	if not (_finite_number(to_value.get("x")) and _finite_number(to_value.get("y"))):
		return {"ok": false, "changed": false}
	var start := Vector2(float(from_value.get("x", 0.0)), float(from_value.get("y", 0.0)))
	var finish := Vector2(float(to_value.get("x", 0.0)), float(to_value.get("y", 0.0)))
	var tap_action := tap or start.distance_squared_to(finish) < 0.000004
	var slice_angle := atan2(finish.y - start.y, finish.x - start.x) if not tap_action else PI * 0.5
	var fruit_values: Variant = state.get("fruits", [])
	var fruit_array: Array = fruit_values if fruit_values is Array else []
	var candidates: Array = []
	for index in fruit_array.size():
		var raw: Variant = fruit_array[index]
		if not raw is Dictionary:
			continue
		var fruit: Dictionary = raw
		if not (_finite_number(fruit.get("x")) and _finite_number(fruit.get("y"))):
			continue
		var center := Vector2(float(fruit.x), float(fruit.y))
		var radius := maxf(0.02, float(fruit.get("radius", NORMAL_RADIUS))) * 1.10
		var distance := _distance_to_segment(center, start, finish)
		if distance <= radius:
			candidates.append({"index":index, "distance":distance})
	if tap_action and candidates.size() > 1:
		candidates.sort_custom(func(a: Dictionary, b: Dictionary): return float(a.distance) < float(b.distance))
		candidates = [candidates[0]]
	var hit_indices := {}
	for candidate in candidates:
		hit_indices[int(candidate.index)] = true
	var events: Array = []
	var kept: Array = []
	var changed := false
	for index in fruit_array.size():
		var raw: Variant = fruit_array[index]
		if not raw is Dictionary:
			continue
		var fruit: Dictionary = raw
		if not hit_indices.has(index):
			kept.append(fruit)
			continue
		changed = true
		var special := str(fruit.get("special", ""))
		if special == "bomb":
			var penalty := maxi(0, int(state.config.bombPenalty))
			var applied := mini(int(state.score), penalty)
			state.bombs = int(state.bombs) + 1
			state.combo = 0
			state.lastSliceAt = -99.0
			state.score = maxi(0, int(state.score) - penalty)
			events.append({
				"type":"bomb",
				"x":float(fruit.get("x", 0.5)),
				"y":float(fruit.get("y", 0.5)),
				"radius":float(fruit.get("radius", BOMB_RADIUS)),
				"delta":-applied,
				"penalty":penalty,
			})
			continue
		var now := float(state.elapsed)
		var last := float(state.get("lastSliceAt", -99.0))
		if last >= 0.0 and now >= last and now - last <= float(state.get("comboWindow", 0.46)):
			state.combo = int(state.combo) + 1
		else:
			state.combo = 1
		state.lastSliceAt = now
		state.maxCombo = maxi(int(state.maxCombo), int(state.combo))
		var points := 10 + maxi(0, int(state.combo) - 1) * 2
		if special == "bonus":
			points += maxi(0, int(state.config.bonusPoints))
		state.score = int(state.score) + points
		state.sliced = int(state.sliced) + 1
		var event_slice_angle := (float(fruit.get("rotation", 0.0)) + PI * 0.5) if tap_action else slice_angle
		events.append({
			"type":"slice",
			"x":float(fruit.get("x", 0.5)),
			"y":float(fruit.get("y", 0.5)),
			"vx":float(fruit.get("vx", 0.0)),
			"vy":float(fruit.get("vy", 0.0)),
			"kind":str(fruit.get("kind", "fruit")),
			"special":special,
			"color":str(fruit.get("color", "#d9534f")),
			"flesh":str(fruit.get("flesh", "#ffe0b8")),
			"leaf":str(fruit.get("leaf", "#4f8248")),
			"shape":str(fruit.get("shape", "apple")),
			"points":points,
			"combo":int(state.combo),
			"radius":float(fruit.get("radius", NORMAL_RADIUS)),
			"sliceAngle":event_slice_angle,
			"rotation":float(fruit.get("rotation", 0.0)),
			"spin":float(fruit.get("spin", 0.0)),
		})
		if int(state.combo) in [3, 5, 8, 12]:
			events.append({
				"type":"combo",
				"combo":int(state.combo),
				"x":float(fruit.get("x", 0.5)),
				"y":float(fruit.get("y", 0.5)),
			})
	state.fruits = kept
	_add_events(events)
	return {
		"ok": true,
		"changed": changed,
		"events": events,
		"finished": str(state.get("phase", "")) == "result",
	}


func drain_events() -> Array:
	var values: Array = state.get("events", []).duplicate(true)
	state.events = []
	return values


func _add_event(event: Dictionary) -> void:
	_add_events([event])


func _add_events(events: Array) -> void:
	if events.is_empty():
		return
	var target: Array = state.get("events", [])
	for event in events:
		if event is Dictionary:
			target.append(event)
	state.events = target.slice(maxi(0, target.size() - 48))


func _spawn_one() -> void:
	var palette: Array = state.get("palette", [])
	if palette.is_empty():
		palette = FALLBACK_FRUITS.duplicate(true)
	_ensure_spawn_queue(10)
	var queue: Array = state.get("spawnQueue", [])
	var kind := str(queue.pop_front()) if not queue.is_empty() else str(palette[0].get("id", "apple"))
	state.spawnQueue = queue
	var fruit := _fruit_for_kind(palette, kind)
	if fruit.is_empty():
		var fallback_fruit: Variant = palette[random.generator.randi_range(0, palette.size() - 1)]
		fruit = fallback_fruit if fallback_fruit is Dictionary else {}
	var special := ""
	var radius := NORMAL_RADIUS
	if str(state.get("modeId", "")) == "challenge":
		var roll := random.generator.randf()
		var bomb_chance := clampf(float(state.config.bombChance), 0.0, 1.0)
		var bonus_chance := clampf(float(state.config.bonusChance), 0.0, 1.0)
		if roll < bomb_chance:
			special = "bomb"
			radius = float(state.config.bombRadius)
		elif roll < bomb_chance + bonus_chance:
			special = "bonus"
			radius = float(state.config.bonusRadius)
	var x := random.generator.randf_range(0.14, 0.86)
	var direction := 1.0 if x < 0.5 else -1.0
	state.fruits.append({
		"id": "fruit-%s-%s" % [str(state.get("spawned", 0)), str(state.get("wave", 1))],
		"kind": str(fruit.get("id", "apple")),
		"name": str(fruit.get("name", "水果")),
		"color": str(fruit.get("color", "#d9534f")),
		"flesh": str(fruit.get("flesh", "#ffe0b8")),
		"leaf": str(fruit.get("leaf", "#4f8248")),
		"shape": str(fruit.get("shape", "apple")),
		"special": special,
		"x": x,
		"y": random.generator.randf_range(1.02, 1.10),
		"vx": direction * random.generator.randf_range(0.02, 0.11),
		"vy": random.generator.randf_range(-1.18, -0.82),
		"radius": radius,
		"rotation": random.generator.randf_range(-0.25, 0.25),
		"spin": random.generator.randf_range(-0.8, 0.8),
	})
	state.spawned = int(state.get("spawned", 0)) + 1
	if str(state.get("modeId", "")) == "practice":
		state.waveSpawned = int(state.get("waveSpawned", 0)) + 1
	_sync_rng_state()


func _ensure_spawn_queue(minimum: int = 10) -> void:
	if state.is_empty():
		return
	var palette: Array = state.get("palette", [])
	if palette.is_empty():
		return
	var queue: Array = state.get("spawnQueue", [])
	var target := clampi(minimum, 1, MAX_SPAWN_QUEUE)
	while queue.size() < target and queue.size() < MAX_SPAWN_QUEUE:
		var entry: Variant = palette[random.generator.randi_range(0, palette.size() - 1)]
		if entry is Dictionary:
			var fruit_id := str(entry.get("id", ""))
			if not fruit_id.is_empty():
				queue.append(fruit_id)
	state.spawnQueue = queue
	_sync_rng_state()


func _fruit_for_kind(palette: Array, kind: String) -> Dictionary:
	for raw in palette:
		if raw is Dictionary and str(raw.get("id", "")) == kind:
			return raw.duplicate(true)
	return {}


func _sanitize_palette(value: Variant) -> Array:
	var result: Array = []
	if value is Array:
		for raw in value:
			if result.size() >= 24:
				break
			if not raw is Dictionary:
				continue
			var fruit_id := str(raw.get("id", "")).strip_edges()
			if fruit_id.is_empty():
				continue
			var duplicate := false
			for existing in result:
				if str(existing.get("id", "")) == fruit_id:
					duplicate = true
					break
			if duplicate:
				continue
			result.append({
				"id":fruit_id,
				"name":str(raw.get("name", "水果")),
				"color":str(raw.get("color", "#d9534f")),
				"flesh":str(raw.get("flesh", "#ffe0b8")),
				"leaf":str(raw.get("leaf", "#4f8248")),
				"shape":str(raw.get("shape", "apple")),
			})
	if result.is_empty():
		result = FALLBACK_FRUITS.duplicate(true)
	return result


func _sanitize_config(value: Variant, difficulty: String, specials: Dictionary = {}) -> Dictionary:
	var source: Dictionary = value if value is Dictionary else {}
	var bomb_special: Variant = specials.get("bomb", {})
	var bonus_special: Variant = specials.get("bonus", {})
	var bomb_data: Dictionary = bomb_special if bomb_special is Dictionary else {}
	var bonus_data: Dictionary = bonus_special if bonus_special is Dictionary else {}
	var bomb_penalty_default := int(bomb_data.get("scorePenalty", DEFAULT_BOMB_PENALTY))
	var bonus_points_default := int(bonus_data.get("points", DEFAULT_BONUS_POINTS))
	var bomb_radius_default := float(bomb_data.get("radius", BOMB_RADIUS))
	var bonus_radius_default := float(bonus_data.get("radius", NORMAL_RADIUS))
	return {
		"practiceWaves": clampi(_int_or(source.get("practiceWaves"), _tuning_int(difficulty, "practiceWaves", 3)), 1, 4),
		"practiceFruits": clampi(_int_or(source.get("practiceFruits"), _tuning_int(difficulty, "practiceFruits", 24)), 1, 60),
		"challengeSeconds": clampf(_float_or(source.get("challengeSeconds"), _tuning_float(difficulty, "challengeSeconds", 60.0)), 0.5, 180.0),
		"spawnDelay": clampf(_float_or(source.get("spawnDelay"), _tuning_float(difficulty, "spawnDelay", 1.15)), 0.05, 3.0),
		"maxFruits": clampi(_int_or(source.get("maxFruits"), _tuning_int(difficulty, "maxFruits", 7)), 1, MAX_ACTIVE),
		"bombChance": clampf(_float_or(source.get("bombChance"), _tuning_float(difficulty, "bombChance", 0.12)), 0.0, 1.0),
		"bonusChance": clampf(_float_or(source.get("bonusChance"), _tuning_float(difficulty, "bonusChance", 0.10)), 0.0, 1.0),
		"comboWindow": clampf(_float_or(source.get("comboWindow"), _tuning_float(difficulty, "comboWindow", 0.46)), 0.05, 2.0),
		"bombPenalty": clampi(_int_or(source.get("bombPenalty"), bomb_penalty_default), 0, 50),
		"bonusPoints": clampi(_int_or(source.get("bonusPoints"), bonus_points_default), 0, 500),
		"bombRadius": clampf(_float_or(source.get("bombRadius"), bomb_radius_default), 0.025, 0.10),
		"bonusRadius": clampf(_float_or(source.get("bonusRadius"), bonus_radius_default), 0.025, 0.10),
	}


func _config_is_valid(value: Dictionary) -> bool:
	var ranges := {
		"practiceWaves":[1.0, 4.0],
		"practiceFruits":[1.0, 60.0],
		"challengeSeconds":[0.5, 180.0],
		"spawnDelay":[0.05, 3.0],
		"maxFruits":[1.0, float(MAX_ACTIVE)],
		"bombChance":[0.0, 1.0],
		"bonusChance":[0.0, 1.0],
		"comboWindow":[0.05, 2.0],
	}
	for key in ranges:
		if not value.has(key) or not _finite_number(value.get(key)):
			return false
		var number := float(value[key])
		var limits: Array = ranges[key]
		if number < float(limits[0]) or number > float(limits[1]):
			return false
	for key in ["bombPenalty", "bonusPoints", "bombRadius", "bonusRadius"]:
		if value.has(key) and not _finite_number(value.get(key)):
			return false
	if value.has("bombPenalty"):
		var penalty := int(value.bombPenalty)
		if penalty < 0 or penalty > 50:
			return false
	if value.has("bonusPoints"):
		var points := int(value.bonusPoints)
		if points < 0 or points > 500:
			return false
	for key in ["practiceWaves", "practiceFruits", "maxFruits", "bombPenalty", "bonusPoints"]:
		if value.has(key) and not _whole_number(value.get(key)):
			return false
	for key in ["bombRadius", "bonusRadius"]:
		if value.has(key) and not (float(value[key]) >= 0.025 and float(value[key]) <= 0.10):
			return false
	return true


func _palette_is_valid(value: Variant) -> bool:
	if not value is Array or value.is_empty() or value.size() > 24:
		return false
	var seen := {}
	for raw in value:
		if not raw is Dictionary:
			return false
		for key in ["id", "name", "color", "flesh", "leaf", "shape"]:
			if not raw.get(key) is String or str(raw.get(key, "")).strip_edges().is_empty():
				return false
		var fruit_id := str(raw.id)
		if seen.has(fruit_id):
			return false
		seen[fruit_id] = true
	return true


func _spawn_queue_is_valid(value: Variant, palette: Array, mode: String) -> bool:
	if not value is Array or value.size() > MAX_SPAWN_QUEUE:
		return false
	if not mode in ["practice", "challenge"]:
		return false
	var ids := {}
	for raw in palette:
		if raw is Dictionary:
			ids[str(raw.get("id", ""))] = true
	for raw in value:
		if not raw is String or str(raw).is_empty() or not ids.has(str(raw)):
			return false
	return true


func _valid_fruits(value: Variant, palette: Array, mode: String, config: Dictionary) -> bool:
	if not value is Array or value.size() > int(config.maxFruits):
		return false
	var palette_ids := {}
	for raw in palette:
		if raw is Dictionary:
			palette_ids[str(raw.get("id", ""))] = true
	var seen_ids := {}
	for raw in value:
		if not raw is Dictionary:
			return false
		var fruit: Dictionary = raw
		for key in ["x", "y", "vx", "vy", "rotation", "spin", "radius"]:
			if not _finite_number(fruit.get(key)):
				return false
		for key in ["id", "kind", "name", "color", "flesh", "leaf", "shape", "special"]:
			if not fruit.get(key) is String:
				return false
		var fruit_id := str(fruit.id)
		if fruit_id.is_empty() or seen_ids.has(fruit_id):
			return false
		seen_ids[fruit_id] = true
		if not palette_ids.has(str(fruit.kind)):
			return false
		var special := str(fruit.special)
		if not special in ["", "bomb", "bonus"]:
			return false
		if mode == "practice" and not special.is_empty():
			return false
		var x := float(fruit.x)
		var y := float(fruit.y)
		var radius := float(fruit.radius)
		if x < -1.0 or x > 2.0 or y < -1.0 or y > 1.5:
			return false
		if absf(float(fruit.vx)) > 5.0 or absf(float(fruit.vy)) > 5.0:
			return false
		if radius < 0.02 or radius > 0.10:
			return false
		if special == "bomb" and radius < 0.025:
			return false
	return true


func _distance_to_segment(point: Vector2, start: Vector2, finish: Vector2) -> float:
	var segment := finish - start
	var length_squared := segment.length_squared()
	if length_squared <= 0.000001:
		return point.distance_to(start)
	var amount := clampf((point - start).dot(segment) / length_squared, 0.0, 1.0)
	return point.distance_to(start + segment * amount)


func _finish(reason: String) -> Dictionary:
	if str(state.get("phase", "")) == "result":
		return {"ok": true, "finished": true, "changed": false}
	state.phase = "result"
	state.winner = -1
	state.reason = reason
	return {"ok": true, "finished": true, "changed": true}


func snapshot() -> Dictionary:
	var value := super.snapshot()
	value.events = []
	value.phase = str(state.get("phase", "ready"))
	value.rngState = str(random.generator.state)
	value.spawnQueue = state.get("spawnQueue", []).duplicate(true)
	return value


func restore(value: Dictionary) -> bool:
	if not value is Dictionary or int(value.get("snapshotVersion", 0)) != 2:
		return false
	if str(value.get("gameId", "")) != "fruit_slice":
		return false
	var players_value: Variant = value.get("players", [])
	if not players_value is Array or players_value.size() != 1:
		return false
	if not value.get("rngState") is String or not str(value.rngState).is_valid_int():
		return false
	if not super.restore(value):
		return false
	var mode := str(state.get("modeId", ""))
	var phase := str(state.get("phase", ""))
	if not mode in ["practice", "challenge"] or not phase in ["ready", "playing", "result"]:
		return _reject_restore()
	if not str(state.get("difficulty", "")) in ["easy", "normal", "challenge"]:
		return _reject_restore()
	if not state.get("reported") is bool or not state.get("startedOnce") is bool:
		return _reject_restore()
	var config_value: Variant = state.get("config", {})
	if not config_value is Dictionary or not _config_is_valid(config_value):
		return _reject_restore()
	var config := _sanitize_config(config_value, str(state.get("difficulty", "normal")), {})
	var palette_value: Variant = state.get("palette", [])
	if not _palette_is_valid(palette_value):
		return _reject_restore()
	var palette: Array = _sanitize_palette(palette_value)
	var numeric_keys := ["score", "sliced", "missed", "bombs", "combo", "maxCombo", "spawned", "wave", "waveSpawned"]
	for key in numeric_keys:
		if not _whole_number(state.get(key)):
			return _reject_restore()
	var float_keys := ["remaining", "elapsed", "nextSpawn"]
	for key in float_keys:
		if not _finite_number(state.get(key)):
			return _reject_restore()
	var last_slice_value: Variant = state.get("lastSliceAt", -99.0)
	if not _finite_number(last_slice_value):
		return _reject_restore()
	if int(state.score) < 0 or int(state.sliced) < 0 or int(state.missed) < 0 or int(state.bombs) < 0:
		return _reject_restore()
	if int(state.combo) < 0 or int(state.maxCombo) < int(state.combo):
		return _reject_restore()
	if int(state.spawned) < 0 or int(state.waveSpawned) < 0:
		return _reject_restore()
	if float(state.elapsed) < 0.0 or float(state.nextSpawn) < 0.0:
		return _reject_restore()
	var last_slice := float(last_slice_value)
	if last_slice >= 0.0 and last_slice > float(state.elapsed) + 0.05:
		return _reject_restore()
	if int(state.combo) > 0 and (
		last_slice < 0.0
		or float(state.elapsed) - last_slice > float(config.comboWindow) + 0.05
	):
		return _reject_restore()
	if mode == "challenge":
		if float(state.remaining) < 0.0 or float(state.remaining) > float(config.challengeSeconds) + 0.05:
			return _reject_restore()
	elif absf(float(state.remaining)) > 0.01:
		return _reject_restore()
	var waves := int(config.practiceWaves)
	var total := int(config.practiceFruits)
	var per_wave := maxi(1, int(ceil(float(total) / float(waves))))
	if int(state.wave) < 1 or int(state.wave) > waves or int(state.waveSpawned) > per_wave:
		return _reject_restore()
	if mode == "practice" and int(state.spawned) > total:
		return _reject_restore()
	var fruits_value: Variant = state.get("fruits", [])
	if not _valid_fruits(fruits_value, palette, mode, config):
		return _reject_restore()
	var queue_value: Variant = state.get("spawnQueue", [])
	if state.has("spawnQueue") and not _spawn_queue_is_valid(queue_value, palette, mode):
		return _reject_restore()
	state.config = config
	state.palette = palette
	state.comboWindow = float(config.comboWindow)
	state.remaining = maxf(0.0, float(state.remaining))
	state.elapsed = maxf(0.0, float(state.elapsed))
	state.nextSpawn = maxf(0.0, float(state.nextSpawn))
	state.lastSliceAt = float(last_slice_value)
	state.score = maxi(0, int(state.score))
	state.sliced = maxi(0, int(state.sliced))
	state.missed = maxi(0, int(state.missed))
	state.bombs = maxi(0, int(state.bombs))
	state.combo = clampi(int(state.combo), 0, int(state.maxCombo))
	state.spawned = maxi(0, int(state.spawned))
	state.wave = clampi(int(state.wave), 1, waves)
	state.waveSpawned = clampi(int(state.waveSpawned), 0, per_wave)
	state.reported = bool(state.get("reported", false))
	state.startedOnce = bool(state.get("startedOnce", false))
	state.events = []
	state.gameId = "fruit_slice"
	var queue_array: Array = queue_value if queue_value is Array else []
	state.spawnQueue = queue_array.duplicate()
	var needs_more := (
		(mode == "practice" and int(state.spawned) < total and str(state.phase) != "result")
		or (mode == "challenge" and float(state.remaining) > 0.0 and str(state.phase) != "result")
	)
	if needs_more and queue_array.is_empty():
		_ensure_spawn_queue(10)
	_sync_rng_state()
	return true


func _reject_restore() -> bool:
	state = {}
	random = SessionRng.new(1)
	return false


func _sync_rng_state() -> void:
	if not state.is_empty():
		state.rngState = str(random.generator.state)


func _tuning_int(difficulty: String, key: String, fallback: int) -> int:
	var value: Variant = GameTuning.value("fruit_slice", difficulty, key, fallback)
	return int(value) if _finite_number(value) else fallback


func _tuning_float(difficulty: String, key: String, fallback: float) -> float:
	var value: Variant = GameTuning.value("fruit_slice", difficulty, key, fallback)
	return float(value) if _finite_number(value) else fallback


func _int_or(value: Variant, fallback: int) -> int:
	return int(value) if _finite_number(value) else fallback


func _float_or(value: Variant, fallback: float) -> float:
	return float(value) if _finite_number(value) else fallback


func _finite_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


func _whole_number(value: Variant) -> bool:
	return _finite_number(value) and is_equal_approx(float(value), roundf(float(value)))
