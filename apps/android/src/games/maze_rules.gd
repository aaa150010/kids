class_name MazeRules
extends GameSession

const VERSION := 1
const MODES := ["adventure", "classic"]
const BANDS := ["easy", "normal", "challenge"]
const DIRECTIONS := ["up", "down", "left", "right"]
const DIRECTION_NAMES := {
	"up": "上",
	"down": "下",
	"left": "左",
	"right": "右",
}
const DIRECTION_VECTORS := {
	"up": Vector2i(0, -1),
	"down": Vector2i(0, 1),
	"left": Vector2i(-1, 0),
	"right": Vector2i(1, 0),
}
const SOLUTION_LETTERS := {"u": "up", "d": "down", "l": "left", "r": "right"}
const MAX_PATROL_STEPS := 24
const INVALID_INT := -2147483648

var level_definition: Dictionary = {}


func create_session(context: Dictionary) -> Dictionary:
	super.create_session(context)
	var requested_level := maxi(1, _int_value(context.get("levelId", 1), 1))
	var raw_value: Variant = context.get("level", {})
	var raw_level: Dictionary = raw_value.duplicate(true) if raw_value is Dictionary else {}
	raw_level.levelNumber = requested_level if raw_value is Dictionary else 0
	var level := _normalize_level(raw_level)
	var mode := str(context.get("modeId", "adventure"))
	if not mode in MODES:
		mode = "adventure"
	var validation := validate_level(level)
	if not bool(validation.get("ok", false)):
		return _empty_state(requested_level, mode, str(validation.get("message", "这一张迷宫还没有准备好")))
	if str(level.get("mode", "")) != mode:
		return _empty_state(requested_level, mode, "这一张迷宫的模式和当前游戏不一致")
	var players_value: Variant = context.get("players", [])
	var player_count: int = players_value.size() if players_value is Array else 0
	if mode == "adventure" and player_count != 1:
		return _empty_state(requested_level, mode, "单人探险需要一位小朋友")
	if mode == "classic" and player_count != 2:
		return _empty_state(requested_level, mode, "双人探路需要两位小朋友")
	level_definition = level
	var start := _cell(level.get("start", {}))
	var patrols: Array = []
	for raw in level.get("patrols", []):
		var patrol: Dictionary = raw
		var period := maxf(0.6, float(patrol.get("period", 1.6)))
		patrols.append({
			"id": str(patrol.get("id", "")),
			"index": 0,
			"timer": clampf(float(patrol.get("phase", 0.0)), 0.0, period),
			"period": period,
		})
	state.merge({
		"mazeVersion": VERSION,
		"gameId": "maze",
		"modeId": mode,
		"levelId": requested_level,
		"levelNumber": requested_level,
		"levelKey": str(level.get("id", "")),
		"levelTitle": str(level.get("title", "迷宫小探险")),
		"levelBand": str(level.get("band", "easy")),
		"level": level,
		"player": _cell_dictionary(start),
		"initialPlayer": _cell_dictionary(start),
		"checkpoint": _cell_dictionary(start),
		"checkpointId": "",
		"keysCollected": [],
		"starsCollected": [],
		"doorsOpen": [],
		"patrols": patrols,
		"moves": 0,
		"hints": 0,
		"patrolResets": 0,
		"turn": 0,
		"lastMove": "",
		"hintDirection": "",
		"hintText": "",
		"lastEvent": "start",
		"phase": "playing",
		"winner": -1,
		"reason": "",
		"stars": 0,
		"reported": false,
	}, true)
	return state


func _empty_state(level_id: int, mode: String, message: String) -> Dictionary:
	state = {
		"mazeVersion": VERSION,
		"gameId": "maze",
		"modeId": mode,
		"levelId": level_id,
		"levelNumber": level_id,
		"level": {},
		"player": {},
		"checkpoint": {},
		"keysCollected": [],
		"starsCollected": [],
		"doorsOpen": [],
		"patrols": [],
		"moves": 0,
		"hints": 0,
		"patrolResets": 0,
		"turn": 0,
		"phase": "empty",
		"loadError": message,
		"reason": message,
		"stars": 0,
		"reported": false,
	}
	return state


func handle_input(action: Dictionary) -> Dictionary:
	match str(action.get("type", "")):
		"move":
			return move(str(action.get("direction", "")))
		"hint":
			return hint()
		"restart":
			return restart()
	return {"ok": false, "message": "这个操作现在不能用"}


func move(direction: String) -> Dictionary:
	if str(state.get("phase", "")) == "empty":
		return {"ok": false, "message": str(state.get("loadError", "这一张迷宫还没有准备好"))}
	if str(state.get("phase", "")) == "finished":
		return {"ok": false, "message": "终点已经到达啦"}
	if not direction in DIRECTIONS:
		return {"ok": false, "message": "请选择一个方向"}
	var player := _cell(state.get("player", {}))
	var target := player + _direction(direction)
	if not _inside(target) or _is_wall(target):
		return {"ok": false, "blocked": "wall", "message": "前面是花园篱笆，换个方向试试"}
	var door := _door_at(target)
	if not door.is_empty() and not str(door.get("id", "")) in state.get("doorsOpen", []):
		var key_id := str(door.get("keyId", ""))
		if not key_id in state.get("keysCollected", []):
			return {"ok": false, "blocked": "door", "message": "这扇小门还锁着，先去找到对应的小钥匙"}
		var opened: Array = state.get("doorsOpen", [])
		opened.append(str(door.get("id", "")))
		state.doorsOpen = opened
	state.player = _cell_dictionary(target)
	state.moves = int(state.get("moves", 0)) + 1
	state.lastMove = direction
	state.hintDirection = ""
	state.lastEvent = "move"
	var collected: Array = []
	var key := _key_at(target)
	if not key.is_empty() and not str(key.get("id", "")) in state.get("keysCollected", []):
		var keys: Array = state.get("keysCollected", [])
		keys.append(str(key.get("id", "")))
		state.keysCollected = keys
		collected.append("key")
	var star := _star_at(target)
	if not star.is_empty() and not str(star.get("id", "")) in state.get("starsCollected", []):
		var stars: Array = state.get("starsCollected", [])
		stars.append(str(star.get("id", "")))
		state.starsCollected = stars
		collected.append("star")
	var checkpoint := _checkpoint_at(target)
	if not checkpoint.is_empty():
		state.checkpoint = _cell_dictionary(target)
		state.checkpointId = str(checkpoint.get("id", ""))
		collected.append("checkpoint")
		state.lastEvent = "checkpoint"
	_advance_turn()
	var caught := _patrol_at(target)
	if caught >= 0:
		_respawn_from_patrol(caught)
		collected.append("patrol")
	var goal := _cell(state.get("level", {}).get("goal", {}))
	if target == goal and caught < 0:
		if _goal_ready():
			_finish()
			return {
				"ok": true,
				"event": "finished",
				"collected": collected,
				"moves": int(state.get("moves", 0)),
				"turn": int(state.get("turn", 0)),
				"stars": int(state.get("stars", stars())),
			}
		state.lastEvent = "goal_locked"
		return {
			"ok": true,
			"event": "goal_locked",
			"collected": collected,
			"message": _goal_locked_message(),
			"turn": int(state.get("turn", 0)),
		}
	if not door.is_empty():
		state.lastEvent = "door"
	if "key" in collected:
		state.lastEvent = "key"
	elif "star" in collected:
		state.lastEvent = "star"
	return {
		"ok": true,
		"event": str(state.get("lastEvent", "move")),
		"collected": collected,
		"caught": caught >= 0,
		"turn": int(state.get("turn", 0)),
		"moves": int(state.get("moves", 0)),
		"keys": state.get("keysCollected", []).size(),
		"stars": state.get("starsCollected", []).size(),
	}


func tick(delta: float) -> bool:
	if str(state.get("phase", "")) != "playing":
		return false
	var changed := false
	var patrols: Array = state.get("patrols", [])
	var level_patrols: Array = level_definition.get("patrols", [])
	for patrol_index in patrols.size():
		if patrol_index >= level_patrols.size():
			break
		var runtime: Dictionary = patrols[patrol_index]
		var period := maxf(0.25, float(runtime.get("period", 1.6)))
		var timer := float(runtime.get("timer", 0.0))
		timer = maxf(0.0, timer + maxf(0.0, delta))
		var path: Array = level_patrols[patrol_index].get("path", [])
		if path.size() < 2:
			runtime.timer = timer
			continue
		var index := int(runtime.get("index", 0))
		var steps := 0
		while timer >= period and steps < MAX_PATROL_STEPS:
			timer -= period
			index = (index + 1) % path.size()
			steps += 1
			changed = true
			var guard := _cell(path[index])
			if guard == _cell(state.get("player", {})):
				runtime.index = index
				runtime.timer = timer
				patrols[patrol_index] = runtime
				state.patrols = patrols
				_respawn_from_patrol(patrol_index)
				return true
		if steps >= MAX_PATROL_STEPS:
			timer = fmod(timer, period)
		runtime.index = index
		runtime.timer = timer
		patrols[patrol_index] = runtime
	state.patrols = patrols
	return changed


func hint() -> Dictionary:
	if str(state.get("phase", "")) != "playing":
		return {"ok": false, "message": "现在不用提示啦"}
	state.hints = int(state.get("hints", 0)) + 1
	var current := _cell(state.get("player", {}))
	var positions := _solution_positions()
	var found := -1
	for index in positions.size():
		if _cell(positions[index]) == current:
			found = index
			break
	var solution := _solution_directions()
	if found < 0 or found >= solution.size():
		state.hintDirection = ""
		state.hintText = "这一步离开了作者路线。先回到检查点，再沿星徽的方向重新探路。"
		return {
			"ok": true,
			"event": "hint",
			"direction": "",
			"message": str(state.hintText),
			"hints": int(state.hints),
		}
	var direction := str(solution[found])
	state.hintDirection = direction
	state.hintText = "下一格向%s走。%s" % [
		str(DIRECTION_NAMES.get(direction, "")),
		str(level_definition.get("hint", "先看小地图，再找钥匙和星徽。")),
	]
	return {
		"ok": true,
		"event": "hint",
		"direction": direction,
		"directionName": str(DIRECTION_NAMES.get(direction, "")),
		"message": str(state.hintText),
		"hints": int(state.hints),
	}


func restart() -> Dictionary:
	if str(state.get("phase", "")) == "empty":
		return {"ok": false, "message": str(state.get("loadError", "这一张迷宫还没有准备好"))}
	var start := _cell(level_definition.get("start", {}))
	state.player = _cell_dictionary(start)
	state.initialPlayer = _cell_dictionary(start)
	state.checkpoint = _cell_dictionary(start)
	state.checkpointId = ""
	state.keysCollected = []
	state.starsCollected = []
	state.doorsOpen = []
	state.moves = 0
	state.hints = 0
	state.patrolResets = 0
	state.turn = 0
	state.lastMove = ""
	state.hintDirection = ""
	state.hintText = ""
	state.lastEvent = "restart"
	state.phase = "playing"
	state.winner = -1
	state.reason = ""
	state.stars = 0
	state.reported = false
	var patrols: Array = []
	for raw in level_definition.get("patrols", []):
		var period := maxf(0.6, float(raw.get("period", 1.6)))
		patrols.append({
			"id": str(raw.get("id", "")),
			"index": 0,
			"timer": clampf(float(raw.get("phase", 0.0)), 0.0, period),
			"period": period,
		})
	state.patrols = patrols
	return {"ok": true, "event": "restarted"}


func stars() -> int:
	if str(state.get("phase", "")) != "finished":
		return 0
	var par := int(level_definition.get("parMoves", 0))
	var moves := int(state.get("moves", 0))
	var hints := int(state.get("hints", 0))
	var resets := int(state.get("patrolResets", 0))
	if moves <= par and hints == 0 and resets == 0:
		return 3
	if moves <= par + 8 and hints <= 1 and resets <= 1:
		return 2
	return 1


func result() -> Dictionary:
	if str(state.get("phase", "")) != "finished":
		return {}
	return {
		"winner": int(state.get("winner", -1)),
		"reason": str(state.get("reason", "走出迷宫啦")),
		"phase": "finished",
		"outcome": "played" if str(state.get("modeId", "adventure")) == "classic" else "win",
		"stars": int(state.get("stars", stars())),
		"moves": int(state.get("moves", 0)),
		"parMoves": int(level_definition.get("parMoves", 0)),
		"hints": int(state.get("hints", 0)),
		"patrolResets": int(state.get("patrolResets", 0)),
		"keys": state.get("keysCollected", []).size(),
		"starsCollected": state.get("starsCollected", []).size(),
		"levelId": int(state.get("levelId", 1)),
		"levelKey": str(level_definition.get("id", "")),
	}


func snapshot() -> Dictionary:
	state.mazeVersion = VERSION
	if str(state.get("phase", "")) == "finished":
		state.stars = stars()
	return super.snapshot()


func restore(value: Dictionary) -> bool:
	if _strict_int(value.get("mazeVersion", null)) != VERSION:
		return false
	if not super.restore(value):
		return false
	if str(state.get("gameId", "")) != "maze":
		return _reject_restore()
	var raw_level: Variant = state.get("level", {})
	if not raw_level is Dictionary:
		return false
	var level := _normalize_level(raw_level)
	var validation := validate_level(level)
	if not bool(validation.get("ok", false)):
		return _reject_restore()
	level_definition = level
	var level_id := _strict_int(state.get("levelId", null))
	var level_number := _strict_int(state.get("levelNumber", null))
	if level_id < 1 or level_number != level_id or int(level.get("levelNumber", -1)) != level_id:
		return _reject_restore()
	if str(state.get("levelKey", "")) != str(level.get("id", "")):
		return _reject_restore()
	var mode := str(state.get("modeId", ""))
	if not mode in MODES or str(level.get("mode", "")) != mode:
		return _reject_restore()
	var players_value: Variant = state.get("players", [])
	var player_count: int = players_value.size() if players_value is Array else 0
	if (mode == "adventure" and player_count != 1) or (mode == "classic" and player_count != 2):
		return _reject_restore()
	var phase := str(state.get("phase", ""))
	if phase not in ["playing", "finished"]:
		return _reject_restore()
	if phase == "playing" and bool(state.get("reported", false)):
		return _reject_restore()
	var player_value: Variant = state.get("player", null)
	var checkpoint_value: Variant = state.get("checkpoint", null)
	if not player_value is Dictionary or not checkpoint_value is Dictionary:
		return _reject_restore()
	var player := _cell(player_value)
	var checkpoint := _cell(checkpoint_value)
	if not _inside(player) or not _inside(checkpoint) or _is_wall(player) or _is_wall(checkpoint):
		return _reject_restore()
	for raw in [state.get("keysCollected", null), state.get("starsCollected", null), state.get("doorsOpen", null)]:
		if not raw is Array:
			return _reject_restore()
	var collected_keys := {}
	for key_id in state.get("keysCollected", []):
		if not key_id is String or not _has_object("keys", str(key_id)):
			return _reject_restore()
		if collected_keys.has(str(key_id)):
			return _reject_restore()
		collected_keys[str(key_id)] = true
	var collected_stars := {}
	for star_id in state.get("starsCollected", []):
		if not star_id is String or not _has_object("stars", str(star_id)):
			return _reject_restore()
		if collected_stars.has(str(star_id)):
			return _reject_restore()
		collected_stars[str(star_id)] = true
	var opened_doors := {}
	for door_id in state.get("doorsOpen", []):
		if not door_id is String or not _has_object("doors", str(door_id)):
			return _reject_restore()
		if opened_doors.has(str(door_id)):
			return _reject_restore()
		opened_doors[str(door_id)] = true
	var patrol_runtime: Variant = state.get("patrols", null)
	var level_patrols: Array = level.get("patrols", [])
	if not patrol_runtime is Array or patrol_runtime.size() != level_patrols.size():
		return _reject_restore()
	for index in patrol_runtime.size():
		var runtime: Variant = patrol_runtime[index]
		var source: Dictionary = level_patrols[index]
		if not runtime is Dictionary:
			return _reject_restore()
		var runtime_index := _strict_int(runtime.get("index", null))
		var timer_value: Variant = runtime.get("timer", null)
		var period_value: Variant = runtime.get("period", null)
		if runtime_index < 0 or runtime_index >= source.get("path", []).size():
			return _reject_restore()
		if not (timer_value is int or timer_value is float) or not (period_value is int or period_value is float):
			return _reject_restore()
		var period := float(period_value)
		var timer := float(timer_value)
		if period <= 0.0 or timer < 0.0 or timer > period + 0.001:
			return _reject_restore()
		runtime.index = runtime_index
		runtime.period = period
		runtime.timer = timer
	for field in ["moves", "hints", "patrolResets", "turn"]:
		var field_value := _strict_int(state.get(field, null))
		if field_value < 0:
			return _reject_restore()
		state[field] = field_value
	if int(state.turn) > (1 if mode == "classic" else 0):
		return _reject_restore()
	var last_move := str(state.get("lastMove", ""))
	if not last_move.is_empty() and not last_move in DIRECTIONS:
		return _reject_restore()
	var hint_direction := str(state.get("hintDirection", ""))
	if not hint_direction.is_empty() and not hint_direction in DIRECTIONS:
		return _reject_restore()
	state.level = level
	state.player = _cell_dictionary(player)
	state.checkpoint = _cell_dictionary(checkpoint)
	state.checkpointId = _checkpoint_at(checkpoint).get("id", "")
	state.patrols = patrol_runtime
	var goal := _cell(level.get("goal", {}))
	var complete := player == goal and _goal_ready()
	if phase == "finished":
		if not complete:
			return _reject_restore()
		state.stars = stars()
		state.winner = -1 if mode == "classic" else 0
		state.reason = "收齐星徽，走出迷宫啦。"
	else:
		state.stars = 0
		state.winner = -1
		state.reason = ""
	if not state.get("reported", false) is bool:
		return _reject_restore()
	return true


func width() -> int:
	return int(level_definition.get("width", 0))


func height() -> int:
	return int(level_definition.get("height", 0))


func current_player_index() -> int:
	return clampi(int(state.get("turn", 0)), 0, 1)


func is_cooperative() -> bool:
	return str(state.get("modeId", "adventure")) == "classic"


func star_total() -> int:
	return (level_definition.get("stars", []) as Array).size()


func key_total() -> int:
	return (level_definition.get("keys", []) as Array).size()


func required_stars() -> int:
	return clampi(int(level_definition.get("requiredStars", star_total())), 0, star_total())


func goal_ready() -> bool:
	return _goal_ready()


func _goal_ready() -> bool:
	if state.get("keysCollected", []).size() < key_total():
		return false
	return state.get("starsCollected", []).size() >= required_stars()


func _goal_locked_message() -> String:
	var missing_keys: int = key_total() - state.get("keysCollected", []).size()
	var missing_stars := maxi(0, required_stars() - state.get("starsCollected", []).size())
	var parts := PackedStringArray()
	if missing_keys > 0:
		parts.append("还差 %s 把钥匙" % missing_keys)
	if missing_stars > 0:
		parts.append("还差 %s 颗星徽" % missing_stars)
	return "终点小门还没亮：%s。" % "、".join(parts)


func _finish() -> void:
	state.phase = "finished"
	state.winner = -1 if is_cooperative() else 0
	state.reason = "收齐星徽，走出迷宫啦。"
	state.stars = stars()
	state.lastEvent = "finished"


func _respawn_from_patrol(patrol_index: int) -> void:
	var checkpoint := _cell(state.get("checkpoint", level_definition.get("start", {})))
	state.player = _cell_dictionary(checkpoint)
	state.patrolResets = int(state.get("patrolResets", 0)) + 1
	state.lastEvent = "patrol"
	state.hintDirection = ""
	var patrols: Array = level_definition.get("patrols", [])
	var patrol_name := "巡逻小灯"
	if patrol_index >= 0 and patrol_index < patrols.size():
		patrol_name = str(patrols[patrol_index].get("name", patrol_name))
	state.reason = "%s发现了你，回到最近的检查点。" % patrol_name


func _advance_turn() -> void:
	if is_cooperative():
		state.turn = 1 - clampi(int(state.get("turn", 0)), 0, 1)
	else:
		state.turn = 0


func _solution_directions() -> Array:
	var result: Array = []
	var raw := str(level_definition.get("solution", "")).to_lower()
	for index in raw.length():
		var letter := raw.substr(index, 1)
		if SOLUTION_LETTERS.has(letter):
			result.append(str(SOLUTION_LETTERS[letter]))
	return result


func _solution_positions() -> Array:
	var positions: Array = [_cell(level_definition.get("start", {}))]
	var position := _cell(level_definition.get("start", {}))
	for direction in _solution_directions():
		position += _direction(direction)
		positions.append(position)
	return positions


func _is_wall(cell: Vector2i) -> bool:
	if not _inside(cell):
		return true
	var rows: Array = level_definition.get("layout", [])
	if cell.y < 0 or cell.y >= rows.size():
		return true
	var row := str(rows[cell.y])
	return cell.x < 0 or cell.x >= row.length() or row.substr(cell.x, 1) == "#"


func _inside(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < width() and cell.y < height()


func _key_at(cell: Vector2i) -> Dictionary:
	return _object_at("keys", cell)


func _door_at(cell: Vector2i) -> Dictionary:
	return _object_at("doors", cell)


func _star_at(cell: Vector2i) -> Dictionary:
	return _object_at("stars", cell)


func _checkpoint_at(cell: Vector2i) -> Dictionary:
	return _object_at("checkpoints", cell)


func _object_at(group: String, cell: Vector2i) -> Dictionary:
	for raw in level_definition.get(group, []):
		if raw is Dictionary and _cell(raw) == cell:
			return raw
	return {}


func _patrol_at(cell: Vector2i) -> int:
	var patrols: Array = state.get("patrols", [])
	var level_patrols: Array = level_definition.get("patrols", [])
	for index in patrols.size():
		if index >= level_patrols.size():
			break
		var path: Array = level_patrols[index].get("path", [])
		var path_index := int(patrols[index].get("index", 0))
		if path_index >= 0 and path_index < path.size() and _cell(path[path_index]) == cell:
			return index
	return -1


func _has_object(group: String, id: String) -> bool:
	for raw in level_definition.get(group, []):
		if raw is Dictionary and str(raw.get("id", "")) == id:
			return true
	return false


static func _direction(value: String) -> Vector2i:
	return DIRECTION_VECTORS.get(value, Vector2i.ZERO)


static func _cell(value: Variant) -> Vector2i:
	if not value is Dictionary:
		return Vector2i.ZERO
	return Vector2i(_strict_int(value.get("x", 0)), _strict_int(value.get("y", 0)))


static func _cell_dictionary(cell: Vector2i) -> Dictionary:
	return {"x": cell.x, "y": cell.y}


static func _strict_int(value: Variant) -> int:
	if value is int:
		return int(value)
	if value is float and is_finite(float(value)) and is_equal_approx(float(value), float(int(value))):
		return int(value)
	return INVALID_INT


static func _int_value(value: Variant, fallback: int) -> int:
	var parsed := _strict_int(value)
	return fallback if parsed == INVALID_INT else parsed


static func _normalize_level(raw: Dictionary) -> Dictionary:
	var level := raw.duplicate(true)
	level.id = str(level.get("id", ""))
	level.mode = str(level.get("mode", ""))
	level.band = str(level.get("band", ""))
	level.minAge = _int_value(level.get("minAge", 0), 0)
	level.levelNumber = _int_value(level.get("levelNumber", 0), 0)
	level.title = str(level.get("title", ""))
	level.width = _int_value(level.get("width", 0), 0)
	level.height = _int_value(level.get("height", 0), 0)
	var layout: Array = []
	var raw_layout: Variant = level.get("layout", [])
	if raw_layout is Array:
		for row in raw_layout:
			layout.append(str(row))
	level.layout = layout
	level.start = _cell_dictionary(_cell(level.get("start", {})))
	level.goal = _cell_dictionary(_cell(level.get("goal", {})))
	for group in ["keys", "doors", "stars", "checkpoints"]:
		var normalized: Array = []
		var source: Variant = level.get(group, [])
		if source is Array:
			for item in source:
				if not item is Dictionary:
					continue
				var entry: Dictionary = item.duplicate(true)
				entry.id = str(entry.get("id", ""))
				entry.x = _int_value(entry.get("x", 0), 0)
				entry.y = _int_value(entry.get("y", 0), 0)
				if group == "doors":
					entry.keyId = str(entry.get("keyId", ""))
				normalized.append(entry)
		level[group] = normalized
	var patrols: Array = []
	var raw_patrols: Variant = level.get("patrols", [])
	if raw_patrols is Array:
		for item in raw_patrols:
			if not item is Dictionary:
				continue
			var patrol: Dictionary = item.duplicate(true)
			patrol.id = str(patrol.get("id", ""))
			patrol.name = str(patrol.get("name", "巡逻小灯"))
			patrol.period = float(patrol.get("period", 1.6))
			patrol.phase = float(patrol.get("phase", 0.0))
			var path: Array = []
			var raw_path: Variant = patrol.get("path", [])
			if raw_path is String:
				for token in str(raw_path).split(";", false):
					var bits := token.split(",", false)
					if bits.size() == 2:
						var px_text := str(bits[0]).strip_edges()
						var py_text := str(bits[1]).strip_edges()
						path.append({
							"x": int(px_text) if px_text.is_valid_int() else -1,
							"y": int(py_text) if py_text.is_valid_int() else -1,
						})
			elif raw_path is Array:
				for point in raw_path:
					path.append(_cell_dictionary(_cell(point)))
			patrol.path = path
			patrols.append(patrol)
	level.patrols = patrols
	level.requiredStars = _int_value(level.get("requiredStars", 0), 0)
	level.parMoves = _int_value(level.get("parMoves", 0), 0)
	level.solution = str(level.get("solution", ""))
	level.hint = str(level.get("hint", ""))
	level.narration = str(level.get("narration", ""))
	level.explanation = str(level.get("explanation", ""))
	return level


static func validate_catalog(value: Variant) -> Dictionary:
	var issues: Array[String] = []
	if not value is Dictionary:
		return {"ok": false, "issues": ["maze.json 顶层必须是对象"], "validLevels": []}
	var data: Dictionary = value
	if _strict_int(data.get("schemaVersion", data.get("version", null))) != VERSION:
		issues.append("maze.json 的 schemaVersion 必须是 %s" % VERSION)
	var levels_value: Variant = data.get("levels", null)
	if not levels_value is Array:
		return {"ok": false, "issues": ["maze.json 缺少 levels 数组"], "validLevels": []}
	var valid_levels: Array = []
	var ids := {}
	var numbers := {"adventure": {}, "classic": {}}
	var counts := {
		"adventure": {"easy": 0, "normal": 0, "challenge": 0},
		"classic": {"easy": 0, "normal": 0, "challenge": 0},
	}
	for index in levels_value.size():
		var normalized := _normalize_level(levels_value[index] if levels_value[index] is Dictionary else {})
		var validation := validate_level(normalized)
		if not bool(validation.get("ok", false)):
			issues.append("第 %s 个迷宫：%s" % [index + 1, str(validation.get("message", "格式不正确"))])
			continue
		var id := str(normalized.id)
		if ids.has(id):
			issues.append("迷宫 id 重复：%s" % id)
			continue
		ids[id] = true
		var mode := str(normalized.mode)
		var number := int(normalized.levelNumber)
		if numbers[mode].has(number):
			issues.append("%s 的关卡编号 %s 重复" % [mode, number])
			continue
		numbers[mode][number] = true
		counts[mode][str(normalized.band)] += 1
		valid_levels.append(normalized)
	if int(levels_value.size()) != 32:
		issues.append("迷宫应为 32 关，实际 %s 关" % levels_value.size())
	for band in BANDS:
		if int(counts["adventure"][band]) != 8:
			issues.append("adventure %s 应为 8 关，实际 %s 关" % [band, counts["adventure"][band]])
	var classic_expected := {"easy": 2, "normal": 3, "challenge": 3}
	for band in BANDS:
		if int(counts["classic"][band]) != int(classic_expected[band]):
			issues.append("classic %s 应为 %s 关，实际 %s 关" % [band, classic_expected[band], counts["classic"][band]])
	for mode in MODES:
		var expected_total := 24 if mode == "adventure" else 8
		var actual := 0
		for band in BANDS:
			actual += int(counts[mode][band])
		if actual != expected_total:
			issues.append("%s 应为 %s 关，实际 %s 关" % [mode, expected_total, actual])
	return {"ok": issues.is_empty(), "issues": issues, "validLevels": valid_levels, "counts": counts}


static func validate_level(raw: Variant) -> Dictionary:
	if not raw is Dictionary:
		return {"ok": false, "message": "迷宫关卡必须是对象"}
	var level := _normalize_level(raw)
	var identifier := str(level.get("id", "未命名迷宫"))
	if identifier.strip_edges().is_empty():
		return {"ok": false, "message": "迷宫关卡缺少 id"}
	if not str(level.get("mode", "")) in MODES:
		return {"ok": false, "message": "%s 的 mode 不合法" % identifier}
	if not str(level.get("band", "")) in BANDS:
		return {"ok": false, "message": "%s 的 band 不合法" % identifier}
	if int(level.get("minAge", 0)) < 4 or int(level.get("minAge", 0)) > 12:
		return {"ok": false, "message": "%s 的 minAge 必须在 4–12" % identifier}
	if int(level.get("levelNumber", 0)) < 1:
		return {"ok": false, "message": "%s 的 levelNumber 无效" % identifier}
	var width := int(level.get("width", 0))
	var height := int(level.get("height", 0))
	if width < 5 or height < 5 or width > 20 or height > 16:
		return {"ok": false, "message": "%s 的迷宫尺寸不合适" % identifier}
	var rows: Array = level.get("layout", [])
	if rows.size() != height:
		return {"ok": false, "message": "%s 的 layout 行数应为 %s" % [identifier, height]}
	for row in rows:
		if str(row).length() != width:
			return {"ok": false, "message": "%s 的 layout 每行宽度应为 %s" % [identifier, width]}
		for index in str(row).length():
			if not str(row).substr(index, 1) in ["#", "."]:
				return {"ok": false, "message": "%s 的 layout 只能使用 # 和 ." % identifier}
	var start := _cell(level.get("start", {}))
	var goal := _cell(level.get("goal", {}))
	if not _level_inside(start, width, height) or _level_wall(rows, start):
		return {"ok": false, "message": "%s 的起点不可走" % identifier}
	if not _level_inside(goal, width, height) or _level_wall(rows, goal):
		return {"ok": false, "message": "%s 的终点不可走" % identifier}
	var occupied := {_cell_key(start): true}
	var keys: Array = level.get("keys", [])
	var doors: Array = level.get("doors", [])
	var stars: Array = level.get("stars", [])
	var checkpoints: Array = level.get("checkpoints", [])
	var ids := {}
	for pair in [["keys", keys], ["doors", doors], ["stars", stars], ["checkpoints", checkpoints]]:
		for item in pair[1]:
			var entry: Dictionary = item
			var id := str(entry.get("id", ""))
			var cell := _cell(entry)
			if id.is_empty() or ids.has(id):
				return {"ok": false, "message": "%s 的物件 id 为空或重复" % identifier}
			ids[id] = true
			if not _level_inside(cell, width, height) or _level_wall(rows, cell):
				return {"ok": false, "message": "%s 的物件 %s 位于墙内" % [identifier, id]}
			if cell == goal:
				return {"ok": false, "message": "%s 的物件 %s 和终点重叠" % [identifier, id]}
			var key := _cell_key(cell)
			if occupied.has(key):
				return {"ok": false, "message": "%s 的物件 %s 和其他物件重叠" % [identifier, id]}
			occupied[key] = true
	var key_ids := {}
	for item in keys:
		key_ids[str(item.get("id", ""))] = true
	for item in doors:
		if not str(item.get("keyId", "")) in key_ids:
			return {"ok": false, "message": "%s 的门 %s 没有对应钥匙" % [identifier, item.get("id", "")]}
	var required_stars := clampi(int(level.get("requiredStars", 0)), 0, stars.size())
	if required_stars < 1 and not stars.is_empty():
		return {"ok": false, "message": "%s 必须要求至少一颗星徽" % identifier}
	level.requiredStars = required_stars
	var patrols: Array = level.get("patrols", [])
	for item in patrols:
		var path: Array = item.get("path", [])
		if path.size() < 2:
			return {"ok": false, "message": "%s 的巡逻路线至少要有两个点" % identifier}
		for path_index in path.size():
			var cell := _cell(path[path_index])
			if not _level_inside(cell, width, height) or _level_wall(rows, cell):
				return {"ok": false, "message": "%s 的巡逻点不可走" % identifier}
			if path_index > 0:
				var prior := _cell(path[path_index - 1])
				if absi(cell.x - prior.x) + absi(cell.y - prior.y) != 1:
					return {"ok": false, "message": "%s 的巡逻路线必须逐格相邻" % identifier}
		if float(item.get("period", 0.0)) < 0.4 or float(item.get("period", 0.0)) > 8.0:
			return {"ok": false, "message": "%s 的巡逻周期不合适" % identifier}
		var phase := float(item.get("phase", 0.0))
		if phase < 0.0 or phase > float(item.get("period", 0.0)) + 0.001:
			return {"ok": false, "message": "%s 的巡逻初始延迟不合适" % identifier}
	var solution := str(level.get("solution", "")).to_lower()
	if solution.is_empty():
		return {"ok": false, "message": "%s 缺少作者解" % identifier}
	var solution_check := _check_solution(level, solution)
	if not bool(solution_check.get("ok", false)):
		return {"ok": false, "message": "%s 的作者解不成立：%s" % [identifier, str(solution_check.get("message", ""))]}
	if int(level.get("parMoves", 0)) < solution.length():
		return {"ok": false, "message": "%s 的 parMoves 小于作者解" % identifier}
	return {"ok": true, "message": "", "level": level}


static func _check_solution(level: Dictionary, solution: String) -> Dictionary:
	var width := int(level.get("width", 0))
	var height := int(level.get("height", 0))
	var rows: Array = level.get("layout", [])
	var position := _cell(level.get("start", {}))
	var collected_keys := {}
	var open_doors := {}
	var collected_stars := {}
	var doors: Array = level.get("doors", [])
	var keys: Array = level.get("keys", [])
	var stars: Array = level.get("stars", [])
	for index in solution.length():
		var letter := solution.substr(index, 1)
		if not SOLUTION_LETTERS.has(letter):
			return {"ok": false, "message": "解里有无法识别的方向 %s" % letter}
		var direction := str(SOLUTION_LETTERS[letter])
		var target := position + _direction(direction)
		if not _level_inside(target, width, height) or _level_wall(rows, target):
			return {"ok": false, "message": "第 %s 步走进墙里" % (index + 1)}
		for door in doors:
			if _cell(door) == target and not str(door.get("id", "")) in open_doors:
				if not str(door.get("keyId", "")) in collected_keys:
					return {"ok": false, "message": "第 %s 步开门前没有钥匙" % (index + 1)}
				open_doors[str(door.get("id", ""))] = true
		position = target
		for key in keys:
			if _cell(key) == target:
				collected_keys[str(key.get("id", ""))] = true
		for star in stars:
			if _cell(star) == target:
				collected_stars[str(star.get("id", ""))] = true
	if position != _cell(level.get("goal", {})):
		return {"ok": false, "message": "最后没有到达终点"}
	if collected_keys.size() != keys.size():
		return {"ok": false, "message": "没有收齐全部钥匙"}
	if collected_stars.size() < int(level.get("requiredStars", 0)):
		return {"ok": false, "message": "没有收齐要求的星徽"}
	return {"ok": true, "message": ""}


static func _level_inside(cell: Vector2i, width: int, height: int) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < width and cell.y < height


static func _level_wall(rows: Array, cell: Vector2i) -> bool:
	if cell.y < 0 or cell.y >= rows.size():
		return true
	var row := str(rows[cell.y])
	return cell.x < 0 or cell.x >= row.length() or row.substr(cell.x, 1) == "#"


static func _cell_key(cell: Vector2i) -> String:
	return "%s:%s" % [cell.x, cell.y]


func _reject_restore() -> bool:
	state = {}
	return false
