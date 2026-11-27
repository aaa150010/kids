class_name TankRules
extends GameSession

const VERSION := 1
const LOGIC_HZ := 120
const LOGIC_STEP := 1.0 / float(LOGIC_HZ)
const BANDS := ["easy", "normal", "challenge"]
const MODES := ["adventure", "classic"]
const DIRECTIONS := ["up", "down", "left", "right"]
const DIRECTION_VECTORS := {
	"up": Vector2i(0, -1),
	"down": Vector2i(0, 1),
	"left": Vector2i(-1, 0),
	"right": Vector2i(1, 0),
}
const MAX_SHIELD := 3
const PLAYER_SHOT_SPEED := 14.0
const EMITTER_SHOT_SPEED := 8.0
const FIRE_COOLDOWN := 0.18
const MAX_BULLETS := 24
const MAX_EVENTS := 64
const MAX_FRAME_STEPS := 32
const SOLUTION_MAX_SECONDS := 120.0

var _accumulator := 0.0


func create_session(context: Dictionary) -> Dictionary:
	super.create_session(context)
	var mode := str(context.get("modeId", "adventure"))
	if not mode in MODES:
		mode = "adventure"
	var level := _normalize_level(context.get("level", {}))
	var level_id := maxi(1, _int_value(context.get("levelId", 1), 1))
	if not level.is_empty() and str(level.get("mode", mode)) != mode:
		level = {}
	if not level.is_empty():
		level.levelNumber = level_id
	if level.is_empty():
		state.merge({
			"tankVersion": VERSION,
			"gameId": "tank",
			"modeId": mode,
			"levelId": level_id,
			"levelNumber": level_id,
			"level": {},
			"view": "map",
			"phase": "empty",
			"reason": "这一张坦克地图还没有准备好",
			"reported": false,
			"stars": 0,
			"winner": -1,
			"events": [],
		}, true)
		_accumulator = 0.0
		return state
	var starts: Array = level.get("starts", [])
	var tanks: Array = []
	for index in starts.size():
		var start: Dictionary = starts[index] if starts[index] is Dictionary else {}
		tanks.append({
			"seat": index,
			"x": _int_value(start.get("x", 0), 0),
			"y": _int_value(start.get("y", 0), 0),
			"dir": _safe_direction(str(start.get("dir", "right"))),
			"shield": MAX_SHIELD,
			"respawnX": _int_value(start.get("x", 0), 0),
			"respawnY": _int_value(start.get("y", 0), 0),
			"respawnCheckpoint": "",
			"fireCooldown": 0.0,
			"invuln": 0.0,
			"hits": 0,
		})
	var goals: Array = level.get("goals", [])
	var goals_lit: Array = []
	for _index in goals.size():
		goals_lit.append(false)
	var emitters: Array = level.get("emitters", [])
	var emitter_timers: Array = []
	for emitter_value in emitters:
		var emitter: Dictionary = emitter_value if emitter_value is Dictionary else {}
		var period := maxf(0.2, _float_value(emitter.get("period", 2.0), 2.0))
		var delay := clampf(_float_value(emitter.get("phase", period * 0.5), period * 0.5), 0.0, period)
		emitter_timers.append(delay)
	state.merge({
		"tankVersion": VERSION,
		"gameId": "tank",
		"modeId": mode,
		"levelId": level_id,
		"levelNumber": level_id,
		"levelKey": str(level.get("id", "")),
		"levelTitle": str(level.get("title", "坦克小卫士")),
		"levelBand": str(level.get("band", "easy")),
		"level": level,
		"view": "board",
		"phase": "playing",
		"reason": "",
		"elapsed": 0.0,
		"tanks": tanks,
		"goalsLit": goals_lit,
		"targetsActive": [],
		"gatesOpen": [],
		"pickupsCollected": [],
		"checkpointsReached": [],
		"bullets": [],
		"nextBulletId": 1,
		"emitterTimers": emitter_timers,
		"shotsFired": 0,
		"shieldBreaks": 0,
		"hintsUsed": 0,
		"stars": 0,
		"winner": -1,
		"outcome": "",
		"reported": false,
		"events": [],
		"difficulty": str(context.get("difficulty", "normal")),
	}, true)
	_accumulator = 0.0
	return state


func handle_input(action: Dictionary) -> Dictionary:
	match str(action.get("type", "")):
		"move":
			return move_tank(_int_value(action.get("seat", 0), 0), str(action.get("dir", "")))
		"face":
			return face_tank(_int_value(action.get("seat", 0), 0), str(action.get("dir", "")))
		"fire":
			return fire(_int_value(action.get("seat", 0), 0))
		"hint":
			return hint()
	return {"ok": false, "changed": false, "message": "这个操作现在不能用"}


func move_tank(seat: int, direction: String) -> Dictionary:
	if str(state.get("phase", "")) != "playing":
		return {"ok": false, "changed": false, "message": "这一张地图已经完成啦"}
	var tank := _tank(seat)
	if tank.is_empty():
		return {"ok": false, "changed": false, "message": "找不到这辆坦克"}
	if not direction in DIRECTIONS:
		return {"ok": false, "changed": false, "message": "请选择一个方向"}
	tank.dir = direction
	var delta: Vector2i = DIRECTION_VECTORS[direction]
	var target := Vector2i(_int_value(tank.x, 0) + delta.x, _int_value(tank.y, 0) + delta.y)
	var blocked := _move_block_reason(seat, target)
	if not blocked.is_empty():
		_set_tank(seat, tank)
		_add_event({"type": "blocked", "seat": seat, "x": target.x, "y": target.y, "reason": blocked})
		return {"ok": true, "changed": false, "moved": false, "message": blocked, "seat": seat}
	tank.x = target.x
	tank.y = target.y
	_set_tank(seat, tank)
	var collected := _collect_at(seat, target)
	_add_event({"type": "move", "seat": seat, "x": target.x, "y": target.y})
	if _all_goals_lit():
		_finish()
	return {
		"ok": true,
		"changed": true,
		"moved": true,
		"seat": seat,
		"x": target.x,
		"y": target.y,
		"collected": collected,
		"finished": str(state.get("phase", "")) == "finished",
	}


func face_tank(seat: int, direction: String) -> Dictionary:
	if str(state.get("phase", "")) != "playing":
		return {"ok": false, "changed": false, "message": "这一张地图已经完成啦"}
	var tank := _tank(seat)
	if tank.is_empty() or not direction in DIRECTIONS:
		return {"ok": false, "changed": false, "message": "这个方向不能转向"}
	if str(tank.get("dir", "")) == direction:
		return {"ok": true, "changed": false, "message": ""}
	tank.dir = direction
	_set_tank(seat, tank)
	return {"ok": true, "changed": true, "message": ""}


func fire(seat: int) -> Dictionary:
	if str(state.get("phase", "")) != "playing":
		return {"ok": false, "changed": false, "message": "这一张地图已经完成啦"}
	var tank := _tank(seat)
	if tank.is_empty():
		return {"ok": false, "changed": false, "message": "找不到这辆坦克"}
	if float(tank.get("fireCooldown", 0.0)) > 0.0:
		return {"ok": false, "changed": false, "message": "炮口还在装泡泡，稍等一下"}
	var direction := _safe_direction(str(tank.get("dir", "right")))
	var delta: Vector2i = DIRECTION_VECTORS[direction]
	var bullets_value: Array = state.get("bullets", [])
	if bullets_value.size() >= MAX_BULLETS:
		return {"ok": false, "changed": false, "message": "泡泡弹太多啦，等它们散开再打"}
	var origin := Vector2(
		float(_int_value(tank.x, 0)) + 0.5 + float(delta.x) * 0.62,
		float(_int_value(tank.y, 0)) + 0.5 + float(delta.y) * 0.62
	)
	var bullet_id := int(state.get("nextBulletId", 1))
	state.nextBulletId = bullet_id + 1
	bullets_value.append({
		"id": bullet_id,
		"x": origin.x,
		"y": origin.y,
		"dir": direction,
		"speed": PLAYER_SHOT_SPEED,
		"kind": "player",
		"owner": seat,
	})
	state.bullets = bullets_value
	state.shotsFired = int(state.get("shotsFired", 0)) + 1
	tank.fireCooldown = FIRE_COOLDOWN
	_set_tank(seat, tank)
	_add_event({
		"type": "fire",
		"seat": seat,
		"x": origin.x - 0.5,
		"y": origin.y - 0.5,
		"dir": direction,
	})
	return {"ok": true, "changed": true, "seat": seat, "shots": int(state.get("shotsFired", 0))}


func hint() -> Dictionary:
	if str(state.get("phase", "")) != "playing":
		return {"ok": false, "message": "这一张地图已经完成啦"}
	state.hintsUsed = int(state.get("hintsUsed", 0)) + 1
	return {
		"ok": true,
		"hint": str(_level().get("hint", "先看清靶子和门，再安排坦克的路线。")),
		"hints": int(state.get("hintsUsed", 0)),
	}


func tick(delta: float) -> bool:
	if str(state.get("phase", "")) != "playing":
		return false
	var frame := clampf(delta, 0.0, 0.25)
	if frame <= 0.0:
		return false
	_accumulator += frame
	var changed := false
	var steps := 0
	while _accumulator >= LOGIC_STEP and steps < MAX_FRAME_STEPS:
		if str(state.get("phase", "")) != "playing":
			_accumulator = 0.0
			break
		_step(LOGIC_STEP)
		_accumulator -= LOGIC_STEP
		steps += 1
		changed = true
	if steps >= MAX_FRAME_STEPS:
		_accumulator = minf(_accumulator, LOGIC_STEP)
	return changed


func snapshot() -> Dictionary:
	var value := super.snapshot()
	value.events = []
	value.tankVersion = VERSION
	if str(state.get("phase", "")) == "finished":
		state.stars = stars()
		value.stars = int(state.stars)
	return value


func restore(value: Dictionary) -> bool:
	if _strict_int(value.get("tankVersion", null)) != VERSION:
		return false
	if not super.restore(value):
		return false
	var level := _normalize_level(state.get("level", {}))
	if level.is_empty():
		return _reject_restore()
	var level_validation := validate_level(level)
	if not bool(level_validation.get("ok", false)):
		return _reject_restore()
	var level_id := _strict_int(state.get("levelId", null))
	var level_number := _strict_int(state.get("levelNumber", null))
	var normalized_level_number := _strict_int(level.get("levelNumber", null))
	if level_id < 1 or level_number != level_id or normalized_level_number != level_id:
		return _reject_restore()
	if str(state.get("levelKey", "")) != str(level.get("id", "")):
		return _reject_restore()
	state.level = level
	var mode := str(state.get("modeId", "adventure"))
	if not mode in MODES:
		return _reject_restore()
	if str(level.get("mode", "adventure")) != mode:
		return _reject_restore()
	var phase := str(state.get("phase", ""))
	if phase not in ["playing", "finished"]:
		return _reject_restore()
	var starts: Array = level.get("starts", [])
	var tanks_value: Variant = state.get("tanks", null)
	if not tanks_value is Array or tanks_value.size() != starts.size():
		return _reject_restore()
	if (mode == "adventure" and tanks_value.size() != 1) or (mode == "classic" and tanks_value.size() != 2):
		return _reject_restore()
	var occupied := {}
	var normalized_tanks: Array = []
	for index in tanks_value.size():
		var raw: Variant = tanks_value[index]
		if not raw is Dictionary:
			return _reject_restore()
		var tank: Dictionary = raw
		var x := _strict_int(tank.get("x", null))
		var y := _strict_int(tank.get("y", null))
		var respawn_x := _strict_int(tank.get("respawnX", null))
		var respawn_y := _strict_int(tank.get("respawnY", null))
		if not _inside(Vector2i(x, y), int(level.width), int(level.height)):
			return _reject_restore()
		if not _inside(Vector2i(respawn_x, respawn_y), int(level.width), int(level.height)):
			return _reject_restore()
		if _is_wall(Vector2i(x, y)) or _is_wall(Vector2i(respawn_x, respawn_y)):
			return _reject_restore()
		if _target_at(Vector2i(x, y)) >= 0 or _target_at(Vector2i(respawn_x, respawn_y)) >= 0:
			return _reject_restore()
		var key := "%s:%s" % [x, y]
		if occupied.has(key):
			return _reject_restore()
		occupied[key] = true
		var direction := str(tank.get("dir", "right"))
		if not direction in DIRECTIONS:
			return _reject_restore()
		var shield := _strict_int(tank.get("shield", null))
		if shield < 1 or shield > MAX_SHIELD:
			return _reject_restore()
		var fire_cooldown := _finite_float(tank.get("fireCooldown", 0.0))
		var invuln := _finite_float(tank.get("invuln", 0.0))
		if fire_cooldown < 0.0 or fire_cooldown > 1.0 or invuln < 0.0 or invuln > 2.0:
			return _reject_restore()
		normalized_tanks.append({
			"seat": index,
			"x": x,
			"y": y,
			"dir": direction,
			"shield": shield,
			"respawnX": respawn_x,
			"respawnY": respawn_y,
			"respawnCheckpoint": str(tank.get("respawnCheckpoint", "")),
			"fireCooldown": fire_cooldown,
			"invuln": invuln,
			"hits": maxi(0, _strict_int(tank.get("hits", 0))),
		})
	state.tanks = normalized_tanks
	var goal_count := (level.get("goals", []) as Array).size()
	var goals_value: Variant = state.get("goalsLit", null)
	if not goals_value is Array or goals_value.size() != goal_count:
		return _reject_restore()
	var goals_lit: Array = []
	for raw in goals_value:
		if not raw is bool:
			return _reject_restore()
		goals_lit.append(raw)
	state.goalsLit = goals_lit
	var target_ids := {}
	for target in level.get("targets", []):
		if target is Dictionary:
			target_ids[str(target.get("id", ""))] = true
	var active_value: Variant = state.get("targetsActive", null)
	if not active_value is Array:
		return _reject_restore()
	var active: Array = []
	for raw in active_value:
		var identifier := str(raw)
		if not target_ids.has(identifier) or identifier in active:
			return _reject_restore()
		active.append(identifier)
	state.targetsActive = active
	state.gatesOpen = []
	state.events = []
	_recalculate_gates()
	var pickup_ids := {}
	for pickup in level.get("pickups", []):
		if pickup is Dictionary:
			pickup_ids[str(pickup.get("id", ""))] = true
	var pickups_value: Variant = state.get("pickupsCollected", null)
	if not pickups_value is Array:
		return _reject_restore()
	var pickups: Array = []
	for raw in pickups_value:
		var identifier := str(raw)
		if not pickup_ids.has(identifier) or identifier in pickups:
			return _reject_restore()
		pickups.append(identifier)
	state.pickupsCollected = pickups
	var checkpoint_ids := {}
	for checkpoint in level.get("checkpoints", []):
		if checkpoint is Dictionary:
			checkpoint_ids[str(checkpoint.get("id", ""))] = true
	var reached_value: Variant = state.get("checkpointsReached", [])
	if not reached_value is Array:
		return _reject_restore()
	var reached: Array = []
	for raw in reached_value:
		var identifier := str(raw)
		if not checkpoint_ids.has(identifier) or identifier in reached:
			return _reject_restore()
		reached.append(identifier)
	state.checkpointsReached = reached
	var emitters: Array = level.get("emitters", [])
	var timers_value: Variant = state.get("emitterTimers", null)
	if not timers_value is Array or timers_value.size() != emitters.size():
		return _reject_restore()
	var timers: Array = []
	for index in timers_value.size():
		var timer := _finite_float(timers_value[index])
		var emitter: Dictionary = emitters[index] if index < emitters.size() and emitters[index] is Dictionary else {}
		var period := maxf(0.2, _float_value(emitter.get("period", 2.0), 2.0))
		if timer < 0.0 or timer > period + LOGIC_STEP:
			return _reject_restore()
		timers.append(timer)
	state.emitterTimers = timers
	var bullets_value: Variant = state.get("bullets", null)
	if not bullets_value is Array or bullets_value.size() > MAX_BULLETS:
		return _reject_restore()
	var bullets: Array = []
	var bullet_ids := {}
	for raw in bullets_value:
		if not raw is Dictionary:
			return _reject_restore()
		var bullet: Dictionary = raw
		var bullet_id := _strict_int(bullet.get("id", null))
		var bx := _finite_float(bullet.get("x", null))
		var by := _finite_float(bullet.get("y", null))
		var direction := str(bullet.get("dir", ""))
		var kind := str(bullet.get("kind", ""))
		var speed := _finite_float(bullet.get("speed", 0.0))
		var owner := _strict_int(bullet.get("owner", -1))
		if bullet_id <= 0 or bullet_ids.has(bullet_id):
			return _reject_restore()
		if not direction in DIRECTIONS or not kind in ["player", "emitter"]:
			return _reject_restore()
		if speed <= 0.0 or speed > 40.0:
			return _reject_restore()
		if bx < -1.0 or by < -1.0 or bx > float(level.width) + 1.0 or by > float(level.height) + 1.0:
			return _reject_restore()
		if kind == "player" and (owner < 0 or owner >= normalized_tanks.size()):
			return _reject_restore()
		bullet_ids[bullet_id] = true
		bullets.append({
			"id": bullet_id,
			"x": bx,
			"y": by,
			"dir": direction,
			"speed": speed,
			"kind": kind,
			"owner": owner,
		})
	state.bullets = bullets
	state.nextBulletId = maxi(int(state.get("nextBulletId", 1)), int(bullet_ids.size()) + 1)
	state.elapsed = maxf(0.0, _finite_float(state.get("elapsed", 0.0)))
	state.shotsFired = maxi(0, _strict_int(state.get("shotsFired", 0)))
	state.shieldBreaks = maxi(0, _strict_int(state.get("shieldBreaks", 0)))
	state.hintsUsed = maxi(0, _strict_int(state.get("hintsUsed", 0)))
	state.view = str(state.get("view", "board")) if str(state.get("view", "board")) in ["map", "board"] else "board"
	state.reported = bool(state.get("reported", false))
	state.levelId = maxi(1, _strict_int(state.get("levelId", 1)))
	state.levelKey = str(level.get("id", ""))
	state.levelTitle = str(level.get("title", "坦克小卫士"))
	state.levelBand = str(level.get("band", "easy"))
	state.winner = -1
	if phase == "finished":
		if not _all_goals_lit():
			return _reject_restore()
		state.phase = "finished"
		state.reason = str(state.get("reason", "所有终点都亮啦"))
		state.outcome = "played" if mode == "classic" else "win"
		state.stars = stars()
	elif _all_goals_lit():
		_finish()
	else:
		state.phase = "playing"
		state.reason = ""
		state.outcome = ""
		state.stars = 0
	if _tank_overlaps_mover():
		return _reject_restore()
	state.events = []
	state.tankVersion = VERSION
	_accumulator = 0.0
	return true


func result() -> Dictionary:
	if str(state.get("phase", "")) != "finished":
		return {}
	return {
		"winner": -1,
		"phase": "finished",
		"reason": str(state.get("reason", "所有终点都亮啦")),
		"outcome": "played" if str(state.get("modeId", "adventure")) == "classic" else "win",
		"stars": int(state.get("stars", stars())),
		"shots": int(state.get("shotsFired", 0)),
		"parShots": int(_level().get("parShots", 0)),
		"starsCollected": (state.get("pickupsCollected", []) as Array).size(),
		"starTotal": (_level().get("pickups", []) as Array).size(),
		"shieldBreaks": int(state.get("shieldBreaks", 0)),
		"elapsed": float(state.get("elapsed", 0.0)),
		"levelId": int(state.get("levelId", 1)),
	}


func stars() -> int:
	if str(state.get("phase", "")) != "finished":
		return 0
	var level := _level()
	var pickups: Array = level.get("pickups", [])
	var collected := (state.get("pickupsCollected", []) as Array).size()
	var par := maxi(0, int(level.get("parShots", 0)))
	var shots := int(state.get("shotsFired", 0))
	var clean := int(state.get("shieldBreaks", 0)) == 0
	if shots <= par and collected == pickups.size() and clean:
		return 3
	var enough_stars := pickups.is_empty() or collected >= ceili(float(pickups.size()) * 0.5)
	if shots <= par + 3 and enough_stars:
		return 2
	return 1


func drain_events() -> Array:
	var events: Array = state.get("events", []).duplicate(true)
	state.events = []
	return events


func level_title() -> String:
	return str(state.get("levelTitle", _level().get("title", "坦克小卫士")))


func width() -> int:
	return int(_level().get("width", 0))


func height() -> int:
	return int(_level().get("height", 0))


func tank_at(seat: int) -> Dictionary:
	return _tank(seat).duplicate(true)


func tank_count() -> int:
	return (state.get("tanks", []) as Array).size()


func mover_cell(mover: Dictionary) -> Vector2i:
	var path_value: Variant = mover.get("path", [])
	if not path_value is Array or (path_value as Array).is_empty():
		return Vector2i(-1, -1)
	var path: Array = path_value
	var step_seconds := maxf(0.1, _float_value(mover.get("stepSeconds", 1.0), 1.0))
	var phase := maxf(0.0, _float_value(mover.get("phase", 0.0), 0.0))
	var index := int(floor((float(state.get("elapsed", 0.0)) + phase) / step_seconds)) % path.size()
	return _cell(path[index])


func gate_cell_open(x: int, y: int) -> bool:
	var gate := _gate_at(Vector2i(x, y))
	return gate.is_empty() or str(gate.get("id", "")) in (state.get("gatesOpen", []) as Array)


func target_active(identifier: String) -> bool:
	return identifier in (state.get("targetsActive", []) as Array)


func pickup_collected(identifier: String) -> bool:
	return identifier in (state.get("pickupsCollected", []) as Array)


func checkpoint_reached(identifier: String) -> bool:
	return identifier in (state.get("checkpointsReached", []) as Array)


func goal_lit(index: int) -> bool:
	var goals: Array = state.get("goalsLit", [])
	return index >= 0 and index < goals.size() and bool(goals[index])


func emitter_next_ratio(emitter: Dictionary, index: int) -> float:
	var timers: Array = state.get("emitterTimers", [])
	if index < 0 or index >= timers.size():
		return 1.0
	var period := maxf(0.2, _float_value(emitter.get("period", 2.0), 2.0))
	return clampf(float(timers[index]) / period, 0.0, 1.0)


func _step(delta: float) -> void:
	state.elapsed = float(state.get("elapsed", 0.0)) + delta
	var tanks_value: Array = state.get("tanks", [])
	for index in tanks_value.size():
		var tank: Dictionary = tanks_value[index]
		tank.fireCooldown = maxf(0.0, float(tank.get("fireCooldown", 0.0)) - delta)
		tank.invuln = maxf(0.0, float(tank.get("invuln", 0.0)) - delta)
		tanks_value[index] = tank
	state.tanks = tanks_value
	_tick_emitters(delta)
	_tick_bullets(delta)
	_check_mover_contacts()
	if str(state.get("phase", "")) == "playing" and _all_goals_lit():
		_finish()


func _tick_emitters(delta: float) -> void:
	var emitters: Array = _level().get("emitters", [])
	var timers: Array = state.get("emitterTimers", [])
	for index in emitters.size():
		var emitter: Dictionary = emitters[index] if emitters[index] is Dictionary else {}
		var disabled_by := str(emitter.get("disableByTarget", ""))
		if not disabled_by.is_empty() and target_active(disabled_by):
			continue
		if index >= timers.size():
			continue
		var timer := float(timers[index]) - delta
		var period := maxf(0.2, _float_value(emitter.get("period", 2.0), 2.0))
		if timer <= 0.0:
			timer += period
			_spawn_emitter_bullet(emitter)
		timers[index] = timer
	state.emitterTimers = timers


func _spawn_emitter_bullet(emitter: Dictionary) -> void:
	var cell := _cell(emitter)
	var direction := _safe_direction(str(emitter.get("dir", "down")))
	var delta: Vector2i = DIRECTION_VECTORS[direction]
	var bullets: Array = state.get("bullets", [])
	if bullets.size() >= MAX_BULLETS:
		return
	var bullet_id := int(state.get("nextBulletId", 1))
	state.nextBulletId = bullet_id + 1
	var origin := Vector2(
		float(cell.x) + 0.5 + float(delta.x) * 0.62,
		float(cell.y) + 0.5 + float(delta.y) * 0.62
	)
	bullets.append({
		"id": bullet_id,
		"x": origin.x,
		"y": origin.y,
		"dir": direction,
		"speed": maxf(2.0, _float_value(emitter.get("speed", EMITTER_SHOT_SPEED), EMITTER_SHOT_SPEED)),
		"kind": "emitter",
		"owner": -1,
	})
	state.bullets = bullets
	_add_event({
		"type": "emitter_fire",
		"x": float(cell.x),
		"y": float(cell.y),
		"dir": direction,
	})


func _tick_bullets(delta: float) -> void:
	var bullets: Array = state.get("bullets", [])
	var kept: Array = []
	for raw in bullets:
		if not raw is Dictionary:
			continue
		var bullet: Dictionary = raw
		if _advance_bullet(bullet, delta):
			kept.append(bullet)
	state.bullets = kept


func _advance_bullet(bullet: Dictionary, delta: float) -> bool:
	var direction := str(bullet.get("dir", ""))
	if not direction in DIRECTIONS:
		return false
	var delta_cell: Vector2i = DIRECTION_VECTORS[direction]
	var old := Vector2(_finite_float(bullet.get("x", 0.0)), _finite_float(bullet.get("y", 0.0)))
	var speed := _finite_float(bullet.get("speed", 0.0))
	var target_position := old + Vector2(delta_cell) * speed * delta
	var start_cell := Vector2i(int(floor(old.x)), int(floor(old.y)))
	var end_cell := Vector2i(int(floor(target_position.x)), int(floor(target_position.y)))
	var cells: Array = []
	if delta_cell.x > 0:
		for x in range(start_cell.x, end_cell.x + 1):
			cells.append(Vector2i(x, start_cell.y))
	elif delta_cell.x < 0:
		for x in range(start_cell.x, end_cell.x - 1, -1):
			cells.append(Vector2i(x, start_cell.y))
	elif delta_cell.y > 0:
		for y in range(start_cell.y, end_cell.y + 1):
			cells.append(Vector2i(start_cell.x, y))
	elif delta_cell.y < 0:
		for y in range(start_cell.y, end_cell.y - 1, -1):
			cells.append(Vector2i(start_cell.x, y))
	for cell in cells:
		if _bullet_hit(cell, bullet):
			return false
	bullet.x = target_position.x
	bullet.y = target_position.y
	return true


func _bullet_hit(cell: Vector2i, bullet: Dictionary) -> bool:
	if not _inside(cell, width(), height()):
		_add_event({"type": "foam", "x": float(cell.x), "y": float(cell.y), "cause": "edge"})
		return true
	if _is_wall(cell):
		_add_event({"type": "foam", "x": float(cell.x), "y": float(cell.y), "cause": "wall"})
		return true
	var gate := _gate_at(cell)
	if not gate.is_empty() and not (str(gate.get("id", "")) in (state.get("gatesOpen", []) as Array)):
		_add_event({"type": "foam", "x": float(cell.x), "y": float(cell.y), "cause": "gate"})
		return true
	if _mover_at(cell) >= 0:
		_add_event({"type": "foam", "x": float(cell.x), "y": float(cell.y), "cause": "mover"})
		return true
	var target_index := _target_at(cell)
	if target_index >= 0:
		if str(bullet.get("kind", "")) == "player":
			var targets: Array = _level().get("targets", [])
			var target: Dictionary = targets[target_index] if targets[target_index] is Dictionary else {}
			_activate_target(str(target.get("id", "")), target)
		else:
			_add_event({"type": "foam", "x": float(cell.x), "y": float(cell.y), "cause": "target"})
		return true
	if str(bullet.get("kind", "")) == "emitter":
		for index in tank_count():
			var tank := _tank(index)
			if _int_value(tank.get("x", -1), -1) == cell.x and _int_value(tank.get("y", -1), -1) == cell.y:
				_damage_tank(index, "emitter")
				_add_event({"type": "foam", "x": float(cell.x), "y": float(cell.y), "cause": "tank"})
				return true
	return false


func _activate_target(identifier: String, target: Dictionary) -> void:
	if identifier.is_empty():
		return
	var active: Array = state.get("targetsActive", [])
	if identifier in active:
		return
	active.append(identifier)
	state.targetsActive = active
	_recalculate_gates()
	_add_event({
		"type": "target",
		"id": identifier,
		"x": _int_value(target.get("x", 0), 0),
		"y": _int_value(target.get("y", 0), 0),
	})


func _recalculate_gates() -> void:
	var active_value: Variant = state.get("targetsActive", [])
	var active: Array = active_value if active_value is Array else []
	var opened: Array = []
	for gate_value in _level().get("gates", []):
		if not gate_value is Dictionary:
			continue
		var gate: Dictionary = gate_value
		var required_value: Variant = gate.get("targets", [])
		if not required_value is Array:
			continue
		var required: Array = required_value
		var ready := not required.is_empty()
		for target_id in required:
			if not str(target_id) in active:
				ready = false
				break
		if ready:
			opened.append(str(gate.get("id", "")))
	var previous_value: Variant = state.get("gatesOpen", [])
	var previous: Array = previous_value if previous_value is Array else []
	state.gatesOpen = opened
	for gate_id in opened:
		if not gate_id in previous:
			var gate := _gate_by_id(gate_id)
			var cells: Array = gate.get("cells", [])
			var first: Dictionary = cells[0] if not cells.is_empty() and cells[0] is Dictionary else {}
			_add_event({
				"type": "gate",
				"id": gate_id,
				"x": _int_value(first.get("x", 0), 0),
				"y": _int_value(first.get("y", 0), 0),
			})


func _collect_at(seat: int, cell: Vector2i) -> Dictionary:
	var result := {"star": false, "checkpoint": false, "goal": false}
	var pickups: Array = _level().get("pickups", [])
	for pickup_value in pickups:
		if not pickup_value is Dictionary:
			continue
		var pickup: Dictionary = pickup_value
		if _cell(pickup) != cell:
			continue
		var identifier := str(pickup.get("id", ""))
		var collected: Array = state.get("pickupsCollected", [])
		if identifier.is_empty() or identifier in collected:
			continue
		collected.append(identifier)
		state.pickupsCollected = collected
		result.star = true
		_add_event({"type": "star", "id": identifier, "x": cell.x, "y": cell.y})
	var checkpoints: Array = _level().get("checkpoints", [])
	for checkpoint_value in checkpoints:
		if not checkpoint_value is Dictionary:
			continue
		var checkpoint: Dictionary = checkpoint_value
		if _cell(checkpoint) != cell:
			continue
		var identifier := str(checkpoint.get("id", ""))
		var reached: Array = state.get("checkpointsReached", [])
		if not identifier.is_empty() and not identifier in reached:
			reached.append(identifier)
			state.checkpointsReached = reached
			_add_event({"type": "checkpoint", "id": identifier, "x": cell.x, "y": cell.y})
		var tank := _tank(seat)
		if not tank.is_empty():
			tank.respawnX = cell.x
			tank.respawnY = cell.y
			tank.respawnCheckpoint = identifier
			_set_tank(seat, tank)
		result.checkpoint = true
	var goals: Array = _level().get("goals", [])
	var goals_lit: Array = state.get("goalsLit", [])
	for index in goals.size():
		var goal: Dictionary = goals[index] if goals[index] is Dictionary else {}
		if _cell(goal) != cell:
			continue
		if index < goals_lit.size() and not bool(goals_lit[index]):
			goals_lit[index] = true
			state.goalsLit = goals_lit
			_add_event({"type": "goal", "index": index, "x": cell.x, "y": cell.y})
		result.goal = true
	return result


func _check_mover_contacts() -> void:
	for index in tank_count():
		var tank := _tank(index)
		var cell := Vector2i(_int_value(tank.get("x", -1), -1), _int_value(tank.get("y", -1), -1))
		if _mover_at(cell) >= 0:
			_damage_tank(index, "mover")


func _damage_tank(seat: int, cause: String) -> void:
	if str(state.get("phase", "")) != "playing":
		return
	var tank := _tank(seat)
	if tank.is_empty() or float(tank.get("invuln", 0.0)) > 0.0:
		return
	tank.hits = int(tank.get("hits", 0)) + 1
	tank.shield = maxi(0, int(tank.get("shield", MAX_SHIELD)) - 1)
	if int(tank.shield) > 0:
		tank.invuln = 0.7
		_set_tank(seat, tank)
		_add_event({
			"type": "shield_hit",
			"seat": seat,
			"x": _int_value(tank.get("x", 0), 0),
			"y": _int_value(tank.get("y", 0), 0),
			"shield": int(tank.shield),
			"cause": cause,
		})
		return
	var previous := Vector2i(_int_value(tank.get("x", 0), 0), _int_value(tank.get("y", 0), 0))
	var respawn := _safe_respawn_cell(seat, Vector2i(_int_value(tank.get("respawnX", 0), 0), _int_value(tank.get("respawnY", 0), 0)))
	tank.x = respawn.x
	tank.y = respawn.y
	tank.shield = MAX_SHIELD
	tank.invuln = 1.2
	_set_tank(seat, tank)
	state.shieldBreaks = int(state.get("shieldBreaks", 0)) + 1
	_add_event({
		"type": "shield_break",
		"seat": seat,
		"fromX": previous.x,
		"fromY": previous.y,
		"x": respawn.x,
		"y": respawn.y,
		"cause": cause,
	})


func _safe_respawn_cell(seat: int, preferred: Vector2i) -> Vector2i:
	var other := Vector2i(-1, -1)
	for index in tank_count():
		if index == seat:
			continue
		var tank := _tank(index)
		other = Vector2i(_int_value(tank.get("x", -1), -1), _int_value(tank.get("y", -1), -1))
	if preferred != other and _walkable_respawn(preferred):
		return preferred
	for direction in DIRECTIONS:
		var delta: Vector2i = DIRECTION_VECTORS[direction]
		var candidate := preferred + delta
		if candidate != other and _walkable_respawn(candidate):
			return candidate
	return preferred


func _walkable_respawn(cell: Vector2i) -> bool:
	if not _inside(cell, width(), height()) or _is_wall(cell):
		return false
	if not _gate_at(cell).is_empty() or _target_at(cell) >= 0 or _mover_at(cell) >= 0:
		return false
	return true


func _finish() -> void:
	if str(state.get("phase", "")) != "playing":
		return
	state.phase = "finished"
	state.reason = "所有终点都亮啦"
	state.outcome = "played" if str(state.get("modeId", "adventure")) == "classic" else "win"
	state.stars = stars()
	state.winner = -1
	_add_event({"type": "complete"})


func _all_goals_lit() -> bool:
	var goals: Array = state.get("goalsLit", [])
	if goals.is_empty():
		return false
	for value in goals:
		if not bool(value):
			return false
	return true


func _move_block_reason(seat: int, cell: Vector2i) -> String:
	if not _inside(cell, width(), height()):
		return "前面是地图边界，换个方向试试"
	if _is_wall(cell):
		return "前面是纸箱墙，换个方向试试"
	var gate := _gate_at(cell)
	if not gate.is_empty() and not (str(gate.get("id", "")) in (state.get("gatesOpen", []) as Array)):
		return "信号门还关着，先打亮对应的信号靶"
	if _mover_at(cell) >= 0:
		return "移动纸门正挡在这里，等它挪开"
	if _target_at(cell) >= 0:
		return "前面是信号靶座，绕到旁边再瞄准"
	for index in tank_count():
		if index == seat:
			continue
		var tank := _tank(index)
		if _int_value(tank.get("x", -1), -1) == cell.x and _int_value(tank.get("y", -1), -1) == cell.y:
			return "小伙伴正站在这里，换一边走"
	return ""


func _tank(index: int) -> Dictionary:
	var tanks: Array = state.get("tanks", [])
	if index < 0 or index >= tanks.size() or not tanks[index] is Dictionary:
		return {}
	return tanks[index]


func _set_tank(index: int, tank: Dictionary) -> void:
	var tanks: Array = state.get("tanks", [])
	if index < 0 or index >= tanks.size():
		return
	tanks[index] = tank
	state.tanks = tanks


func _level() -> Dictionary:
	var value: Variant = state.get("level", {})
	return value if value is Dictionary else {}


func _target_at(cell: Vector2i) -> int:
	var targets: Array = _level().get("targets", [])
	for index in targets.size():
		if targets[index] is Dictionary and _cell(targets[index]) == cell:
			return index
	return -1


func _gate_at(cell: Vector2i) -> Dictionary:
	for gate_value in _level().get("gates", []):
		if not gate_value is Dictionary:
			continue
		var gate: Dictionary = gate_value
		var cells_value: Variant = gate.get("cells", [])
		if not cells_value is Array:
			continue
		for raw_cell in cells_value:
			if raw_cell is Dictionary and _cell(raw_cell) == cell:
				return gate
	return {}


func _gate_by_id(identifier: String) -> Dictionary:
	for gate_value in _level().get("gates", []):
		if gate_value is Dictionary and str(gate_value.get("id", "")) == identifier:
			return gate_value
	return {}


func _mover_at(cell: Vector2i) -> int:
	var movers: Array = _level().get("movers", [])
	for index in movers.size():
		if movers[index] is Dictionary and mover_cell(movers[index]) == cell:
			return index
	return -1


func _tank_overlaps_mover() -> bool:
	for index in tank_count():
		var tank := _tank(index)
		var cell := Vector2i(_int_value(tank.get("x", -1), -1), _int_value(tank.get("y", -1), -1))
		if _mover_at(cell) >= 0:
			return true
	return false


func _is_wall(cell: Vector2i) -> bool:
	if not _inside(cell, width(), height()):
		return true
	var layout: Array = _level().get("layout", [])
	if cell.y < 0 or cell.y >= layout.size():
		return true
	var row := str(layout[cell.y])
	if cell.x < 0 or cell.x >= row.length():
		return true
	return row.substr(cell.x, 1) == "#"


func _add_event(event: Dictionary) -> void:
	var events_value: Variant = state.get("events", [])
	var events: Array = events_value if events_value is Array else []
	events.append(event)
	if events.size() > MAX_EVENTS:
		events = events.slice(events.size() - MAX_EVENTS)
	state.events = events


func _reject_restore() -> bool:
	state = {}
	_accumulator = 0.0
	return false


static func validate_catalog(value: Variant) -> Dictionary:
	var issues: Array[String] = []
	if not value is Dictionary:
		return {"ok": false, "issues": ["tank.json 顶层必须是对象"], "validLevels": []}
	var data: Dictionary = value
	if _strict_int(data.get("schemaVersion", data.get("version", null))) != VERSION:
		issues.append("tank.json 的 schemaVersion 必须是 %s" % VERSION)
	var levels_value: Variant = data.get("levels", null)
	if not levels_value is Array:
		issues.append("tank.json 缺少 levels 数组")
		return {"ok": false, "issues": issues, "validLevels": []}
	var levels: Array = levels_value
	var mode_counts := {"adventure": 0, "classic": 0}
	var band_counts := {"adventure": {"easy": 0, "normal": 0, "challenge": 0}, "classic": {"easy": 0, "normal": 0, "challenge": 0}}
	var seen_ids := {}
	var valid_levels: Array = []
	for index in levels.size():
		var raw: Variant = levels[index]
		if not raw is Dictionary:
			issues.append("第 %s 关不是对象" % (index + 1))
			continue
		var entry: Dictionary = raw
		var identifier := str(entry.get("id", "")).strip_edges()
		if identifier.is_empty():
			issues.append("第 %s 关缺少 id" % (index + 1))
		elif seen_ids.has(identifier):
			issues.append("关卡 id 重复：%s" % identifier)
		else:
			seen_ids[identifier] = true
		var mode := str(entry.get("mode", ""))
		if not mode in MODES:
			issues.append("%s 的 mode 不合法" % identifier)
			continue
		var validation := validate_level(entry)
		if not bool(validation.get("ok", false)):
			issues.append("%s：%s" % [identifier if not identifier.is_empty() else ("第 %s 关" % (index + 1)), str(validation.get("message", "配置异常"))])
			continue
		mode_counts[mode] = int(mode_counts.get(mode, 0)) + 1
		var band := str(entry.get("band", ""))
		band_counts[mode][band] = int(band_counts[mode].get(band, 0)) + 1
		valid_levels.append(entry)
	if int(mode_counts.get("adventure", 0)) != 24:
		issues.append("单人闯关必须是 24 关，实际 %s 关" % int(mode_counts.get("adventure", 0)))
	if int(mode_counts.get("classic", 0)) != 6:
		issues.append("双人协作必须是 6 张地图，实际 %s 张" % int(mode_counts.get("classic", 0)))
	for band in BANDS:
		if int(band_counts["adventure"].get(band, 0)) != 8:
			issues.append("单人 %s 难度必须有 8 关，实际 %s 关" % [band, int(band_counts["adventure"].get(band, 0))])
		if int(band_counts["classic"].get(band, 0)) != 2:
			issues.append("双人 %s 难度必须有 2 张，实际 %s 张" % [band, int(band_counts["classic"].get(band, 0))])
	return {
		"ok": issues.is_empty(),
		"issues": issues,
		"validLevels": valid_levels,
		"modeCounts": mode_counts,
		"bandCounts": band_counts,
	}


static func validate_level(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return {"ok": false, "message": "关卡必须是对象"}
	var level: Dictionary = _normalize_level(value)
	if level.is_empty():
		return {"ok": false, "message": "关卡缺少完整的宽高与 layout"}
	var identifier := str(level.get("id", "")).strip_edges()
	if identifier.is_empty():
		return {"ok": false, "message": "缺少关卡 id"}
	var mode := str(level.get("mode", ""))
	if not mode in MODES:
		return {"ok": false, "message": "%s 的 mode 不合法" % identifier}
	var band := str(level.get("band", ""))
	if not band in BANDS:
		return {"ok": false, "message": "%s 的 band 不合法" % identifier}
	var min_age := _strict_int(level.get("minAge", null))
	if min_age < 4 or min_age > 12:
		return {"ok": false, "message": "%s 的 minAge 必须在 4–12" % identifier}
	if str(level.get("title", "")).strip_edges().is_empty():
		return {"ok": false, "message": "%s 缺少标题" % identifier}
	var width := int(level.width)
	var height := int(level.height)
	if width < 5 or height < 4 or width > 14 or height > 10:
		return {"ok": false, "message": "%s 的宽高必须在 5–14 × 4–10" % identifier}
	var layout: Array = level.get("layout", [])
	if layout.size() != height:
		return {"ok": false, "message": "%s 的 layout 行数不对" % identifier}
	for row_value in layout:
		var row := str(row_value)
		if row.length() != width:
			return {"ok": false, "message": "%s 的 layout 行宽不对" % identifier}
		for column in width:
			var tile := row.substr(column, 1)
			if not tile in ["#", "."]:
				return {"ok": false, "message": "%s 的 layout 只能包含 # 和 ." % identifier}
	var starts: Array = level.get("starts", [])
	var expected_starts := 1 if mode == "adventure" else 2
	if starts.size() != expected_starts:
		return {"ok": false, "message": "%s 需要 %s 个起点" % [identifier, expected_starts]}
	var occupied := {}
	for index in starts.size():
		if not starts[index] is Dictionary:
			return {"ok": false, "message": "%s 的 start 不是对象" % identifier}
		var start: Dictionary = starts[index]
		var cell := _cell(start)
		if not _inside(cell, width, height) or _layout_wall(layout, cell, width):
			return {"ok": false, "message": "%s 的起点越界或落在墙上" % identifier}
		var key := _cell_key(cell)
		if occupied.has(key):
			return {"ok": false, "message": "%s 的起点重复" % identifier}
		occupied[key] = true
		if not str(start.get("dir", "right")) in DIRECTIONS:
			return {"ok": false, "message": "%s 的起点方向不合法" % identifier}
	var goals: Array = level.get("goals", [])
	if goals.size() < 1 or goals.size() > 2:
		return {"ok": false, "message": "%s 必须有 1 或 2 个终点" % identifier}
	var goal_cells := {}
	for goal_value in goals:
		if not goal_value is Dictionary:
			return {"ok": false, "message": "%s 的终点不是对象" % identifier}
		var cell := _cell(goal_value)
		if not _inside(cell, width, height) or _layout_wall(layout, cell, width):
			return {"ok": false, "message": "%s 的终点越界或落在墙上" % identifier}
		if occupied.has(_cell_key(cell)):
			return {"ok": false, "message": "%s 的终点不能和起点重合" % identifier}
		if goal_cells.has(_cell_key(cell)):
			return {"ok": false, "message": "%s 的终点重复" % identifier}
		goal_cells[_cell_key(cell)] = true
	var target_ids := {}
	var target_cells := {}
	for target_value in level.get("targets", []):
		if not target_value is Dictionary:
			return {"ok": false, "message": "%s 的信号靶不是对象" % identifier}
		var target: Dictionary = target_value
		var target_id := str(target.get("id", "")).strip_edges()
		var cell := _cell(target)
		if target_id.is_empty() or target_ids.has(target_id):
			return {"ok": false, "message": "%s 的信号靶 id 缺失或重复" % identifier}
		if not _inside(cell, width, height) or _layout_wall(layout, cell, width):
			return {"ok": false, "message": "%s 的信号靶越界或落在墙上" % identifier}
		if occupied.has(_cell_key(cell)) or goal_cells.has(_cell_key(cell)) or target_cells.has(_cell_key(cell)):
			return {"ok": false, "message": "%s 的信号靶位置冲突" % identifier}
		target_ids[target_id] = true
		target_cells[_cell_key(cell)] = target_id
	var gate_cells := {}
	var gate_ids := {}
	for gate_value in level.get("gates", []):
		if not gate_value is Dictionary:
			return {"ok": false, "message": "%s 的信号门不是对象" % identifier}
		var gate: Dictionary = gate_value
		var gate_id := str(gate.get("id", "")).strip_edges()
		if gate_id.is_empty() or gate_ids.has(gate_id):
			return {"ok": false, "message": "%s 的信号门 id 缺失或重复" % identifier}
		var cells_value: Variant = gate.get("cells", null)
		if not cells_value is Array or (cells_value as Array).is_empty():
			return {"ok": false, "message": "%s 的信号门 %s 没有格子" % [identifier, gate_id]}
		var required: Variant = gate.get("targets", null)
		if not required is Array or (required as Array).is_empty():
			return {"ok": false, "message": "%s 的信号门 %s 没有关联靶" % [identifier, gate_id]}
		for target_id in required:
			if not target_ids.has(str(target_id)):
				return {"ok": false, "message": "%s 的信号门 %s 关联了不存在的靶" % [identifier, gate_id]}
		for cell_value in cells_value:
			if not cell_value is Dictionary:
				return {"ok": false, "message": "%s 的信号门格子不是对象" % identifier}
			var cell := _cell(cell_value)
			if not _inside(cell, width, height) or _layout_wall(layout, cell, width):
				return {"ok": false, "message": "%s 的信号门越界或落在墙上" % identifier}
			var key := _cell_key(cell)
			if occupied.has(key) or goal_cells.has(key) or target_cells.has(key) or gate_cells.has(key):
				return {"ok": false, "message": "%s 的信号门位置冲突" % identifier}
			gate_cells[key] = gate_id
		gate_ids[gate_id] = true
	var mover_paths := {}
	var mover_ids := {}
	for mover_value in level.get("movers", []):
		if not mover_value is Dictionary:
			return {"ok": false, "message": "%s 的移动机关不是对象" % identifier}
		var mover: Dictionary = mover_value
		var mover_id := str(mover.get("id", "")).strip_edges()
		if mover_id.is_empty() or mover_ids.has(mover_id):
			return {"ok": false, "message": "%s 的移动机关 id 缺失或重复" % identifier}
		var path_value: Variant = mover.get("path", null)
		if not path_value is Array or (path_value as Array).size() < 2:
			return {"ok": false, "message": "%s 的移动机关 %s 路径太短" % [identifier, mover_id]}
		var path: Array = path_value
		var seen_path := {}
		for cell_value in path:
			if not cell_value is Dictionary:
				return {"ok": false, "message": "%s 的移动机关路径不是对象" % identifier}
			var cell := _cell(cell_value)
			if not _inside(cell, width, height) or _layout_wall(layout, cell, width):
				return {"ok": false, "message": "%s 的移动机关越界或落在墙上" % identifier}
			var key := _cell_key(cell)
			if occupied.has(key) or goal_cells.has(key) or target_cells.has(key) or gate_cells.has(key):
				return {"ok": false, "message": "%s 的移动机关压住重要格子" % identifier}
			if seen_path.has(key):
				return {"ok": false, "message": "%s 的移动机关路径有重复格" % identifier}
			seen_path[key] = true
			mover_paths[key] = mover_id
		var step_seconds := _float_value(mover.get("stepSeconds", -1.0), -1.0)
		if step_seconds < 0.2 or step_seconds > 6.0:
			return {"ok": false, "message": "%s 的移动机关步进时间不合法" % identifier}
		if _float_value(mover.get("phase", 0.0), 0.0) < 0.0:
			return {"ok": false, "message": "%s 的移动机关相位不合法" % identifier}
		mover_ids[mover_id] = true
	var emitter_ids := {}
	for emitter_value in level.get("emitters", []):
		if not emitter_value is Dictionary:
			return {"ok": false, "message": "%s 的泡泡发射器不是对象" % identifier}
		var emitter: Dictionary = emitter_value
		var emitter_id := str(emitter.get("id", "")).strip_edges()
		if emitter_id.is_empty() or emitter_ids.has(emitter_id):
			return {"ok": false, "message": "%s 的泡泡发射器 id 缺失或重复" % identifier}
		var cell := _cell(emitter)
		if not _inside(cell, width, height) or not _layout_wall(layout, cell, width):
			return {"ok": false, "message": "%s 的泡泡发射器必须装在墙上" % identifier}
		var direction := str(emitter.get("dir", ""))
		if not direction in DIRECTIONS:
			return {"ok": false, "message": "%s 的泡泡发射器方向不合法" % identifier}
		var delta: Vector2i = DIRECTION_VECTORS[direction]
		var front := cell + delta
		if not _inside(front, width, height) or _layout_wall(layout, front, width):
			return {"ok": false, "message": "%s 的泡泡发射器前方没有通道" % identifier}
		var period := _float_value(emitter.get("period", -1.0), -1.0)
		if period < 0.5 or period > 12.0:
			return {"ok": false, "message": "%s 的泡泡发射器周期不合法" % identifier}
		var phase := _float_value(emitter.get("phase", 0.0), 0.0)
		if phase < 0.0 or phase > period:
			return {"ok": false, "message": "%s 的泡泡发射器相位不合法" % identifier}
		var disabled_by := str(emitter.get("disableByTarget", ""))
		if not disabled_by.is_empty() and not target_ids.has(disabled_by):
			return {"ok": false, "message": "%s 的泡泡发射器关联了不存在的靶" % identifier}
		emitter_ids[emitter_id] = true
	var pickup_ids := {}
	for pickup_value in level.get("pickups", []):
		if not pickup_value is Dictionary:
			return {"ok": false, "message": "%s 的星徽不是对象" % identifier}
		var pickup: Dictionary = pickup_value
		var pickup_id := str(pickup.get("id", "")).strip_edges()
		var cell := _cell(pickup)
		if pickup_id.is_empty() or pickup_ids.has(pickup_id):
			return {"ok": false, "message": "%s 的星徽 id 缺失或重复" % identifier}
		if str(pickup.get("kind", "star")) != "star":
			return {"ok": false, "message": "%s 的星徽 kind 必须是 star" % identifier}
		if not _inside(cell, width, height) or _layout_wall(layout, cell, width):
			return {"ok": false, "message": "%s 的星徽越界或落在墙上" % identifier}
		var key := _cell_key(cell)
		if occupied.has(key) or goal_cells.has(key) or target_cells.has(key) or gate_cells.has(key) or mover_paths.has(key):
			return {"ok": false, "message": "%s 的星徽位置冲突" % identifier}
		pickup_ids[pickup_id] = true
	var checkpoint_ids := {}
	for checkpoint_value in level.get("checkpoints", []):
		if not checkpoint_value is Dictionary:
			return {"ok": false, "message": "%s 的检查点不是对象" % identifier}
		var checkpoint: Dictionary = checkpoint_value
		var checkpoint_id := str(checkpoint.get("id", "")).strip_edges()
		var cell := _cell(checkpoint)
		if checkpoint_id.is_empty() or checkpoint_ids.has(checkpoint_id):
			return {"ok": false, "message": "%s 的检查点 id 缺失或重复" % identifier}
		if not _inside(cell, width, height) or _layout_wall(layout, cell, width):
			return {"ok": false, "message": "%s 的检查点越界或落在墙上" % identifier}
		var key := _cell_key(cell)
		if occupied.has(key) or goal_cells.has(key) or target_cells.has(key) or gate_cells.has(key) or mover_paths.has(key) or pickup_ids.has("cell:" + key):
			return {"ok": false, "message": "%s 的检查点位置冲突" % identifier}
		for pickup_value in level.get("pickups", []):
			if pickup_value is Dictionary and _cell(pickup_value) == cell:
				return {"ok": false, "message": "%s 的检查点和星徽重合" % identifier}
		checkpoint_ids[checkpoint_id] = true
	var par_shots := _strict_int(level.get("parShots", null))
	if par_shots < 0:
		return {"ok": false, "message": "%s 的 parShots 不合法" % identifier}
	for key in ["hint", "explanation"]:
		if str(level.get(key, "")).strip_edges().is_empty():
			return {"ok": false, "message": "%s 缺少 %s 文案" % [identifier, key]}
	var solution_value: Variant = level.get("solution", null)
	if not solution_value is Array or (solution_value as Array).is_empty():
		return {"ok": false, "message": "%s 缺少固定解" % identifier}
	var replay := _replay_solution(level)
	if not bool(replay.get("ok", false)):
		return {"ok": false, "message": "%s 的固定解验证失败：%s" % [identifier, str(replay.get("message", "未知原因"))]}
	var stats: Dictionary = replay.get("stats", {})
	if int(stats.get("shots", -1)) != par_shots:
		return {"ok": false, "message": "%s 的 parShots 应等于固定解射击数 %s" % [identifier, int(stats.get("shots", 0))]}
	if int(stats.get("stars", 0)) != 3:
		return {"ok": false, "message": "%s 的固定解必须拿到三颗评价星" % identifier}
	return {
		"ok": true,
		"message": identifier,
		"solutionLength": (solution_value as Array).size(),
		"parShots": par_shots,
		"stats": stats,
	}


static func _replay_solution(level: Dictionary) -> Dictionary:
	var rules_script: GDScript = load("res://src/games/tank_rules.gd")
	if rules_script == null:
		return {"ok": false, "message": "规则脚本没有加载成功"}
	var sim = rules_script.new()
	var mode := str(level.get("mode", "adventure"))
	var players: Array = [{"id": "p1", "name": "测试一号", "age": 8, "color": "#4e7fa8", "avatar": "🦊"}]
	if mode == "classic":
		players.append({"id": "p2", "name": "测试二号", "age": 8, "color": "#b9793f", "avatar": "🐼"})
	sim.create_session({
		"gameId": "tank",
		"modeId": mode,
		"players": players,
		"levelId": 1,
		"level": level,
		"seed": 1,
	})
	if str(sim.state.get("phase", "")) != "playing":
		return {"ok": false, "message": "会话没有进入可玩状态"}
	var solution: Array = level.get("solution", [])
	var total_wait := 0.0
	for index in solution.size():
		var token := str(solution[index]).strip_edges()
		if token.begins_with("wait:"):
			var seconds_text := token.substr(5)
			if not seconds_text.is_valid_float():
				return {"ok": false, "message": "第 %s 步等待时长不合法" % (index + 1)}
			var seconds := float(seconds_text)
			if seconds < 0.0 or seconds > 20.0:
				return {"ok": false, "message": "第 %s 步等待时长超出范围" % (index + 1)}
			total_wait += seconds
			if total_wait > SOLUTION_MAX_SECONDS:
				return {"ok": false, "message": "固定解等待时间过长"}
			_simulate_seconds(sim, seconds)
			continue
		var parts := token.split(":")
		if parts.size() < 2:
			return {"ok": false, "message": "第 %s 步指令格式不对" % (index + 1)}
		var seat := int(parts[0]) if str(parts[0]).is_valid_int() else -1
		if seat < 0 or seat >= players.size():
			return {"ok": false, "message": "第 %s 步座位号不合法" % (index + 1)}
		var action := str(parts[1])
		var payload := ""
		if parts.size() >= 3:
			payload = str(parts[2])
		var result := {}
		if action == "move":
			result = sim.handle_input({"type": "move", "seat": seat, "dir": payload})
		elif action == "face":
			result = sim.handle_input({"type": "face", "seat": seat, "dir": payload})
		elif action == "fire":
			result = sim.handle_input({"type": "fire", "seat": seat})
		else:
			return {"ok": false, "message": "第 %s 步未知动作 %s" % [index + 1, action]}
		if not bool(result.get("ok", false)):
			return {"ok": false, "message": "第 %s 步被拒绝：%s" % [index + 1, str(result.get("message", "无法执行"))]}
		if str(sim.state.get("phase", "")) == "finished" and index < solution.size() - 1:
			return {"ok": false, "message": "固定解提前完成，后面还有多余步骤"}
	if str(sim.state.get("phase", "")) != "finished":
		return {"ok": false, "message": "固定解没有点亮全部终点"}
	var targets: Array = level.get("targets", [])
	for target_value in targets:
		if not target_value is Dictionary:
			continue
		var target_id := str(target_value.get("id", ""))
		if not target_id in (sim.state.get("targetsActive", []) as Array):
			return {"ok": false, "message": "固定解漏掉了信号靶 %s" % target_id}
	var pickups: Array = level.get("pickups", [])
	for pickup_value in pickups:
		if not pickup_value is Dictionary:
			continue
		var pickup_id := str(pickup_value.get("id", ""))
		if not pickup_id in (sim.state.get("pickupsCollected", []) as Array):
			return {"ok": false, "message": "固定解漏掉了星徽 %s" % pickup_id}
	return {
		"ok": true,
		"message": "固定解到达全部终点",
		"stats": {
			"shots": int(sim.state.get("shotsFired", 0)),
			"stars": sim.stars(),
			"shieldBreaks": int(sim.state.get("shieldBreaks", 0)),
			"elapsed": float(sim.state.get("elapsed", 0.0)),
			"tanks": sim.tank_count(),
		},
	}


static func _simulate_seconds(sim: Variant, seconds: float) -> void:
	var remaining := maxf(0.0, seconds)
	var guard := 0
	while remaining > 0.000001 and guard < 30000:
		var step := minf(LOGIC_STEP, remaining)
		sim._step(step)
		remaining -= step
		guard += 1


static func _normalize_level(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return {}
	var raw: Dictionary = value
	var width := _strict_int(raw.get("width", null))
	var height := _strict_int(raw.get("height", null))
	if width <= 0 or height <= 0:
		return {}
	var layout_value: Variant = raw.get("layout", null)
	if not layout_value is Array or (layout_value as Array).size() != height:
		return {}
	var layout: Array = []
	for raw_row in layout_value:
		if not raw_row is String:
			return {}
		var row := str(raw_row)
		if row.length() != width:
			return {}
		for column in width:
			if not row.substr(column, 1) in ["#", "."]:
				return {}
		layout.append(row)
	var level := raw.duplicate(true)
	level["id"] = str(raw.get("id", ""))
	level["mode"] = str(raw.get("mode", "adventure"))
	level["band"] = str(raw.get("band", "easy"))
	level["title"] = str(raw.get("title", ""))
	level["levelNumber"] = _int_value(raw.get("levelNumber", -1), -1)
	level["width"] = width
	level["height"] = height
	level["layout"] = layout
	for key in ["starts", "goals", "targets", "gates", "movers", "emitters", "pickups", "checkpoints"]:
		var array_value: Variant = raw.get(key, [])
		level[key] = array_value.duplicate(true) if array_value is Array else []
	level["parShots"] = _strict_int(raw.get("parShots", 0))
	level["hint"] = str(raw.get("hint", ""))
	level["explanation"] = str(raw.get("explanation", ""))
	var solution_value: Variant = raw.get("solution", [])
	level["solution"] = solution_value.duplicate(true) if solution_value is Array else []
	return level


static func _layout_wall(layout: Array, cell: Vector2i, width: int) -> bool:
	if cell.y < 0 or cell.y >= layout.size() or cell.x < 0 or cell.x >= width:
		return true
	return str(layout[cell.y]).substr(cell.x, 1) == "#"


static func _cell(value: Variant) -> Vector2i:
	if not value is Dictionary:
		return Vector2i(-1, -1)
	return Vector2i(_strict_int(value.get("x", null)), _strict_int(value.get("y", null)))


static func _cell_key(cell: Vector2i) -> String:
	return "%s:%s" % [cell.x, cell.y]


static func _inside(cell: Vector2i, width: int, height: int) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < width and cell.y < height


static func _safe_direction(value: String) -> String:
	return value if value in DIRECTIONS else "right"


static func _strict_int(value: Variant) -> int:
	if value is int:
		return int(value)
	if value is float and is_finite(float(value)) and is_equal_approx(float(value), float(int(value))):
		return int(value)
	return -2147483648


static func _int_value(value: Variant, fallback: int) -> int:
	var parsed := _strict_int(value)
	return fallback if parsed == -2147483648 else parsed


static func _finite_float(value: Variant) -> float:
	if (value is int or value is float) and is_finite(float(value)):
		return float(value)
	return 0.0


static func _float_value(value: Variant, fallback: float) -> float:
	if (value is int or value is float) and is_finite(float(value)):
		return float(value)
	return fallback
