class_name BubbleRules
extends GameSession

const VERSION := 1
const MODES := ["adventure", "classic"]
const BANDS := ["easy", "normal", "challenge"]
const LOGIC_HZ := ArcadePhysics.STEP_HZ
const LOGIC_STEP := ArcadePhysics.STEP_DELTA
const MAX_FRAME_STEPS := 24
const MAX_ROWS := 12
const MAX_EVENTS := 64
const MAX_AIM_RADIANS := 1.34
const INVALID_INT := -2147483648
const FALLBACK_COLORS := [
	{"id":"coral","name":"珊瑚泡泡","letter":"C","hex":"#e26f62","deep":"#b84c46"},
	{"id":"sun","name":"太阳泡泡","letter":"S","hex":"#e7b73c","deep":"#b48126"},
	{"id":"mint","name":"薄荷泡泡","letter":"M","hex":"#69b987","deep":"#3f8c62"},
	{"id":"sky","name":"天空泡泡","letter":"K","hex":"#5b9bd8","deep":"#376f9f"},
	{"id":"plum","name":"梅子泡泡","letter":"P","hex":"#9871c8","deep":"#6d4b9b"},
]

var _accumulator := 0.0


func create_session(context: Dictionary) -> Dictionary:
	super.create_session(context)
	var mode := str(context.get("modeId", "adventure"))
	if not mode in MODES:
		mode = "adventure"
	var colors := _normalize_palette(context.get("colors", context.get("palette", FALLBACK_COLORS)))
	var level := _normalize_level(context.get("level", {}), colors)
	var level_id := maxi(1, _int_value(context.get("levelId", 1), 1))
	var level_number := _int_value(level.get("levelNumber", level_id), level_id)
	var required_players := 2 if mode == "classic" else 1
	var players_value: Variant = state.get("players", [])
	var player_count: int = players_value.size() if players_value is Array else 0
	if (
		level.is_empty()
		or str(level.get("mode", "")) != mode
		or level_id != level_number
		or player_count != required_players
		or not bool(validate_level(level, colors).get("ok", false))
	):
		state.merge({
			"bubbleVersion": VERSION,
			"gameId": "bubble",
			"modeId": mode,
			"levelId": level_id,
			"levelNumber": level_number,
			"levelKey": "",
			"level": {},
			"colors": colors,
			"view": "map",
			"phase": "empty",
			"reason": "这一张泡泡关还没有准备好",
			"events": [],
			"reported": false,
			"winner": -1,
			"outcome": "",
			"stars": 0,
		}, true)
		_accumulator = 0.0
		return state
	var queue: Array = level.get("queue", []).duplicate()
	var board: Array = level.get("cells", []).duplicate(true)
	state.merge({
		"bubbleVersion": VERSION,
		"gameId": "bubble",
		"modeId": mode,
		"levelId": level_id,
		"levelNumber": level_number,
		"levelKey": str(level.get("id", "")),
		"levelTitle": str(level.get("title", "泡泡星星")),
		"levelBand": str(level.get("band", "easy")),
		"level": level,
		"colors": colors,
		"view": "board",
		"phase": "playing",
		"reason": "",
		"success": false,
		"board": board,
		"queue": queue,
		"queueCursor": 0,
		"currentColor": str(queue[0]) if not queue.is_empty() else "",
		"movesUsed": 0,
		"movesLimit": int(level.get("moves", 1)),
		"score": 0,
		"popped": 0,
		"dropped": 0,
		"starsPopped": 0,
		"colorsPopped": {},
		"hintsUsed": 0,
		"shots": 0,
		"lastShotId": 0,
		"projectile": {},
		"aim": {"x": 0.0, "y": -1.0},
		"turn": 0,
		"turnCount": 0,
		"physicsAccumulator": 0.0,
		"events": [],
		"reported": false,
		"winner": -1,
		"outcome": "",
		"stars": 0,
		"difficulty": str(context.get("difficulty", "normal")),
	}, true)
	_accumulator = 0.0
	return state


func handle_input(action: Dictionary) -> Dictionary:
	match str(action.get("type", "")):
		"aim":
			return set_aim_direction(action.get("aim", action))
		"fire":
			var aim_value: Variant = action.get("aim", null)
			if aim_value is Dictionary:
				set_aim_direction(aim_value)
			return fire()
		"hint":
			return hint()
	return {"ok": false, "changed": false, "message": "这个操作现在不能用"}


func set_aim_direction(value: Variant) -> Dictionary:
	if str(state.get("phase", "")) != "playing":
		return {"ok": false, "changed": false, "message": "这一关已经结束啦"}
	if not value is Dictionary:
		return {"ok": false, "changed": false, "message": "请先瞄准"}
	var x := _finite_float(value.get("x", 0.0))
	var y := _finite_float(value.get("y", -1.0))
	var direction := Vector2(x, y)
	if direction.length_squared() <= 0.000001:
		direction = Vector2.UP
	direction = direction.normalized()
	var angle := atan2(direction.x, -direction.y)
	angle = clampf(angle, -MAX_AIM_RADIANS, MAX_AIM_RADIANS)
	var normalized := Vector2(sin(angle), -cos(angle))
	var aim := {"x": normalized.x, "y": normalized.y}
	var changed := Dictionary(state.get("aim", {})) != aim
	state.aim = aim
	return {"ok": true, "changed": changed, "aim": aim.duplicate()}


func fire() -> Dictionary:
	if str(state.get("phase", "")) != "playing":
		return {"ok": false, "changed": false, "message": "这一关已经结束啦"}
	var projectile_value: Variant = state.get("projectile", {})
	if projectile_value is Dictionary and not projectile_value.is_empty():
		return {"ok": false, "changed": false, "message": "上一颗泡泡还在飞"}
	var queue: Array = state.get("queue", [])
	var cursor := int(state.get("queueCursor", 0))
	if cursor < 0 or cursor >= queue.size():
		return {"ok": false, "changed": false, "message": "颜色队列已经用完啦"}
	var color := str(queue[cursor])
	if color.is_empty():
		return {"ok": false, "changed": false, "message": "下一颗泡泡还没有颜色"}
	var aim_value: Variant = state.get("aim", {"x":0.0,"y":-1.0})
	var aim: Dictionary = aim_value if aim_value is Dictionary else {"x":0.0,"y":-1.0}
	var direction := Vector2(_finite_float(aim.get("x", 0.0)), _finite_float(aim.get("y", -1.0)))
	if direction.length_squared() <= 0.000001:
		direction = Vector2.UP
	var level := _level()
	var speed := maxf(0.15, _finite_float(level.get("shotSpeed", 0.9)))
	var origin := Vector2(0.5, _finite_float(level.get("shooterY", 0.9)))
	var shot_id := int(state.get("lastShotId", 0)) + 1
	state.projectile = {
		"x": origin.x,
		"y": origin.y,
		"dirX": direction.normalized().x,
		"dirY": direction.normalized().y,
		"speed": speed,
		"color": color,
		"shotId": shot_id,
	}
	state.lastShotId = shot_id
	state.queueCursor = cursor + 1
	state.currentColor = str(queue[cursor + 1]) if cursor + 1 < queue.size() else ""
	state.movesUsed = int(state.get("movesUsed", 0)) + 1
	state.shots = int(state.get("shots", 0)) + 1
	_add_event({
		"type": "fire",
		"x": origin.x,
		"y": origin.y,
		"color": _color_hex(color),
		"colorId": color,
		"dirX": direction.normalized().x,
		"dirY": direction.normalized().y,
		"shotId": shot_id,
	})
	return {
		"ok": true,
		"changed": true,
		"color": color,
		"shotId": shot_id,
		"movesUsed": int(state.movesUsed),
	}


func hint() -> Dictionary:
	if str(state.get("phase", "")) != "playing":
		return {"ok": false, "message": "这一关已经结束啦"}
	state.hintsUsed = int(state.get("hintsUsed", 0)) + 1
	var level := _level()
	var result := {
		"ok": true,
		"changed": true,
		"hint": str(level.get("hint", "把同色泡泡连成三个，就能一起消掉。")),
		"hints": int(state.hintsUsed),
	}
	if level.has("hintAngle"):
		result.hintAngle = _finite_float(level.get("hintAngle", 0.0))
	return result


func tick(delta: float) -> bool:
	if str(state.get("phase", "")) != "playing":
		return false
	var frame := ArcadePhysics.consume_fixed_steps(_accumulator, delta, MAX_FRAME_STEPS)
	_accumulator = float(frame.get("accumulator", 0.0))
	var changed := false
	var steps := int(frame.get("steps", 0))
	for _index in steps:
		if str(state.get("phase", "")) != "playing":
			break
		var projectile_value: Variant = state.get("projectile", {})
		if not projectile_value is Dictionary or projectile_value.is_empty():
			continue
		_step(LOGIC_STEP)
		changed = true
	if bool(frame.get("dropped", false)):
		_accumulator = minf(_accumulator, LOGIC_STEP * 0.5)
	return changed


func snapshot() -> Dictionary:
	var value := super.snapshot()
	value.events = []
	value.bubbleVersion = VERSION
	value.physicsAccumulator = clampf(_accumulator, 0.0, LOGIC_STEP)
	value.stars = stars()
	return value


func restore(value: Dictionary) -> bool:
	if _strict_int(value.get("bubbleVersion", null)) != VERSION:
		return false
	if not super.restore(value):
		return false
	var mode := str(state.get("modeId", ""))
	if not mode in MODES:
		return _reject_restore()
	var colors := _normalize_palette(state.get("colors", FALLBACK_COLORS))
	var level := _normalize_level(state.get("level", {}), colors)
	if level.is_empty() or not bool(validate_level(level, colors).get("ok", false)):
		return _reject_restore()
	var level_id := _strict_int(state.get("levelId", null))
	var level_number := _strict_int(state.get("levelNumber", null))
	var normalized_level_number := _strict_int(level.get("levelNumber", null))
	if level_id < 1 or level_number != level_id or normalized_level_number != level_id:
		return _reject_restore()
	if str(level.get("mode", "")) != mode or str(state.get("levelKey", "")) != str(level.get("id", "")):
		return _reject_restore()
	var players_value: Variant = state.get("players", [])
	if not players_value is Array:
		return _reject_restore()
	var expected_players := 2 if mode == "classic" else 1
	if players_value.size() != expected_players:
		return _reject_restore()
	var phase := str(state.get("phase", ""))
	if phase not in ["playing", "finished"]:
		return _reject_restore()
	if phase == "playing" and bool(state.get("reported", false)):
		return _reject_restore()
	var moves_limit := _strict_int(state.get("movesLimit", null))
	var moves_used := _strict_int(state.get("movesUsed", null))
	if moves_limit != int(level.get("moves", -1)) or moves_used < 0 or moves_used > moves_limit:
		return _reject_restore()
	var queue_value: Variant = state.get("queue", null)
	if not queue_value is Array or queue_value.size() < moves_limit + 1:
		return _reject_restore()
	var queue: Array = []
	var color_ids := _color_ids(colors)
	var color_letters := _color_letters(colors)
	for raw in queue_value:
		var identifier := str(raw)
		if color_ids.has(identifier):
			queue.append(identifier)
		elif color_letters.has(identifier):
			queue.append(str(color_letters[identifier]))
		else:
			return _reject_restore()
	var queue_cursor := _strict_int(state.get("queueCursor", null))
	if queue_cursor != moves_used or queue_cursor < 0 or queue_cursor > queue.size():
		return _reject_restore()
	var board_value: Variant = state.get("board", null)
	if not board_value is Array:
		return _reject_restore()
	var board: Array = []
	var occupied := {}
	var board_stars := {}
	var board_colors := {}
	for raw in board_value:
		if not raw is Dictionary:
			return _reject_restore()
		var cell: Dictionary = raw
		var row := _strict_int(cell.get("row", null))
		var column := _strict_int(cell.get("col", null))
		if not _cell_exists(level, row, column):
			return _reject_restore()
		var key := _cell_key(row, column)
		if occupied.has(key):
			return _reject_restore()
		var color := str(cell.get("color", ""))
		if not color_ids.has(color):
			return _reject_restore()
		var is_star := bool(cell.get("star", false))
		var star_keys := _star_keys(level)
		if is_star and not star_keys.has(key):
			return _reject_restore()
		occupied[key] = true
		board_colors[color] = int(board_colors.get(color, 0)) + 1
		if is_star:
			board_stars[key] = true
		board.append({
			"row": row,
			"col": column,
			"color": color,
			"star": is_star,
		})
	if not board.is_empty() and not _board_connected_to_ceiling(board, int(level.get("columns", 0))):
		return _reject_restore()
	var score := _strict_int(state.get("score", null))
	var popped := _strict_int(state.get("popped", null))
	var dropped := _strict_int(state.get("dropped", null))
	var stars_popped := _strict_int(state.get("starsPopped", null))
	if score < 0 or score > 100000 or popped < 0 or popped > 600 or dropped < 0 or dropped > 600:
		return _reject_restore()
	if stars_popped < 0 or stars_popped > (level.get("starCells", []) as Array).size():
		return _reject_restore()
	var colors_popped_value: Variant = state.get("colorsPopped", {})
	var colors_popped: Dictionary = {}
	if colors_popped_value is Dictionary:
		for raw_color in colors_popped_value.keys():
			var identifier := str(raw_color)
			var amount := _strict_int(colors_popped_value[raw_color])
			if not color_ids.has(identifier) or amount < 0 or amount > 600:
				return _reject_restore()
			colors_popped[identifier] = amount
	state.colorsPopped = colors_popped
	var turn := _strict_int(state.get("turn", null))
	if turn < 0 or turn >= expected_players:
		return _reject_restore()
	var turn_count := _strict_int(state.get("turnCount", null))
	if turn_count < 0 or turn_count > 600:
		return _reject_restore()
	var aim_value: Variant = state.get("aim", {"x":0.0,"y":-1.0})
	if not aim_value is Dictionary:
		return _reject_restore()
	var aim_x := _finite_float(aim_value.get("x", 0.0))
	var aim_y := _finite_float(aim_value.get("y", -1.0))
	var aim := Vector2(aim_x, aim_y)
	if aim.length_squared() <= 0.000001 or aim_y > 0.02:
		aim = Vector2.UP
	else:
		aim = aim.normalized()
	state.aim = {"x": aim.x, "y": aim.y}
	var projectile_value: Variant = state.get("projectile", {})
	var projectile: Dictionary = {}
	if projectile_value is Dictionary and not projectile_value.is_empty():
		var shot_id := _strict_int(projectile_value.get("shotId", null))
		var px := _finite_float(projectile_value.get("x", 0.0))
		var py := _finite_float(projectile_value.get("y", 0.0))
		var dir_x := _finite_float(projectile_value.get("dirX", 0.0))
		var dir_y := _finite_float(projectile_value.get("dirY", -1.0))
		var speed := _finite_float(projectile_value.get("speed", 0.0))
		var projectile_color := str(projectile_value.get("color", ""))
		var direction := Vector2(dir_x, dir_y)
		if shot_id <= 0 or shot_id > 10000:
			return _reject_restore()
		if px < -0.1 or px > 1.1 or py < -0.1 or py > 1.1:
			return _reject_restore()
		if direction.length_squared() <= 0.000001 or direction.y > 0.05:
			return _reject_restore()
		if speed < 0.1 or speed > 4.0 or not color_ids.has(projectile_color):
			return _reject_restore()
		projectile = {
			"x": px,
			"y": py,
			"dirX": direction.normalized().x,
			"dirY": direction.normalized().y,
			"speed": speed,
			"color": projectile_color,
			"shotId": shot_id,
		}
	elif projectile_value != null and not projectile_value is Dictionary:
		return _reject_restore()
	if phase == "finished" and not projectile.is_empty():
		return _reject_restore()
	state.projectile = projectile
	state.board = board
	state.queue = queue
	state.queueCursor = queue_cursor
	state.currentColor = str(queue[queue_cursor]) if queue_cursor < queue.size() else ""
	state.turn = turn
	state.turnCount = turn_count
	state.boardColorCounts = board_colors
	state.dropped = dropped
	state.popped = popped
	state.starsPopped = stars_popped
	state.hintsUsed = maxi(0, _strict_int(state.get("hintsUsed", 0)))
	state.lastShotId = maxi(0, _strict_int(state.get("lastShotId", 0)))
	state.score = score
	state.shots = maxi(0, _strict_int(state.get("shots", 0)))
	state.reported = bool(state.get("reported", false))
	state.view = "board"
	state.levelId = level_id
	state.levelNumber = level_id
	state.levelKey = str(level.get("id", ""))
	state.levelTitle = str(level.get("title", "泡泡星星"))
	state.levelBand = str(level.get("band", "easy"))
	state.level = level
	state.events = []
	state.bubbleVersion = VERSION
	state.physicsAccumulator = clampf(_finite_float(state.get("physicsAccumulator", 0.0)), 0.0, LOGIC_STEP)
	_accumulator = float(state.physicsAccumulator)
	var success := bool(state.get("success", false))
	if phase == "finished":
		if success:
			if not goals_complete():
				return _reject_restore()
			state.success = true
			state.outcome = "played" if mode == "classic" else "win"
			state.winner = -1 if mode == "classic" else 0
		else:
			if moves_used < moves_limit and not _danger_reached():
				return _reject_restore()
			state.success = false
			state.outcome = "retry"
			state.winner = -1
		state.stars = stars()
	else:
		if goals_complete():
			return _reject_restore()
		state.success = false
		state.outcome = ""
		state.stars = 0
		state.winner = -1
	return true


func result() -> Dictionary:
	if str(state.get("phase", "")) != "finished":
		return {}
	var success := bool(state.get("success", false))
	return {
		"winner": int(state.get("winner", -1)),
		"phase": "finished",
		"success": success,
		"outcome": str(state.get("outcome", "")),
		"reason": str(state.get("reason", "")),
		"stars": stars(),
		"score": int(state.get("score", 0)),
		"popped": int(state.get("popped", 0)),
		"dropped": int(state.get("dropped", 0)),
		"starsPopped": int(state.get("starsPopped", 0)),
		"movesUsed": int(state.get("movesUsed", 0)),
		"movesLimit": int(state.get("movesLimit", 0)),
		"levelId": int(state.get("levelId", 1)),
	}


func stars() -> int:
	if str(state.get("phase", "")) != "finished" or not bool(state.get("success", false)):
		return 0
	var limit := maxi(1, int(state.get("movesLimit", 1)))
	var ratio := float(int(state.get("movesUsed", 0))) / float(limit)
	if ratio <= 0.55:
		return 3
	if ratio <= 0.82:
		return 2
	return 1


func drain_events() -> Array:
	var events_value: Variant = state.get("events", [])
	var events: Array = events_value.duplicate(true) if events_value is Array else []
	state.events = []
	return events


func goal_progress() -> Array:
	var result_rows: Array = []
	var goals_value: Variant = _level().get("goals", [])
	var goals: Array = goals_value if goals_value is Array else []
	for raw in goals:
		if not raw is Dictionary:
			continue
		var goal: Dictionary = raw
		var kind := str(goal.get("type", "clear"))
		var target := maxi(1, _int_value(goal.get("count", 1), 1))
		var current := _goal_current(goal)
		var label := _goal_label(goal, current, target)
		result_rows.append({
			"type": kind,
			"color": str(goal.get("color", "")),
			"current": current,
			"target": target,
			"done": current >= target,
			"label": label,
		})
	return result_rows


func goals_complete() -> bool:
	var goals_value: Variant = _level().get("goals", [])
	var goals: Array = goals_value if goals_value is Array else []
	if goals.is_empty():
		return false
	for raw in goals:
		if not raw is Dictionary:
			return false
		var target := maxi(1, _int_value(raw.get("count", 1), 1))
		if _goal_current(raw) < target:
			return false
	return true


func remaining_moves() -> int:
	return maxi(0, int(state.get("movesLimit", 0)) - int(state.get("movesUsed", 0)))


func current_color() -> String:
	var queue: Array = state.get("queue", [])
	var cursor := int(state.get("queueCursor", 0))
	return str(queue[cursor]) if cursor >= 0 and cursor < queue.size() else ""


func next_colors(count: int = 4) -> Array:
	var colors: Array = []
	var queue: Array = state.get("queue", [])
	var cursor := int(state.get("queueCursor", 0))
	for index in maxi(0, count):
		var queue_index := cursor + index
		if queue_index < queue.size():
			colors.append({
				"id": str(queue[queue_index]),
				"hex": _color_hex(str(queue[queue_index])),
			})
	return colors


func current_player_index() -> int:
	return clampi(int(state.get("turn", 0)), 0, 1)


func is_cooperative() -> bool:
	return str(state.get("modeId", "adventure")) == "classic"


func level_title() -> String:
	return str(state.get("levelTitle", _level().get("title", "泡泡星星")))


func level_band() -> String:
	return str(state.get("levelBand", _level().get("band", "easy")))


func color_definition(identifier: String) -> Dictionary:
	for color in state.get("colors", FALLBACK_COLORS):
		if color is Dictionary and str(color.get("id", "")) == identifier:
			return color.duplicate(true)
	return {}


func palette() -> Array:
	var values: Variant = state.get("colors", FALLBACK_COLORS)
	return values.duplicate(true) if values is Array else FALLBACK_COLORS.duplicate(true)


func cell_center(row: int, column: int) -> Vector2:
	return _cell_center(_level(), row, column)


func board_cells() -> Array:
	var value: Variant = state.get("board", [])
	return value.duplicate(true) if value is Array else []


func projectile_snapshot() -> Dictionary:
	var value: Variant = state.get("projectile", {})
	return value.duplicate(true) if value is Dictionary else {}


func cell_center_for_cell(cell: Dictionary) -> Vector2:
	return cell_center(int(cell.get("row", 0)), int(cell.get("col", 0)))


func color_hex(identifier: String) -> String:
	return _color_hex(identifier)


func aim_preview(max_bounces: int = 2) -> Array:
	var points: Array = []
	if str(state.get("phase", "")) != "playing":
		return points
	var level := _level()
	var radius := _finite_float(level.get("radius", 0.043))
	var aim_value: Variant = state.get("aim", {"x":0.0,"y":-1.0})
	var aim: Dictionary = aim_value if aim_value is Dictionary else {"x":0.0,"y":-1.0}
	var direction := Vector2(_finite_float(aim.get("x", 0.0)), _finite_float(aim.get("y", -1.0))).normalized()
	var speed := maxf(0.15, _finite_float(level.get("shotSpeed", 0.9)))
	var velocity := direction * speed
	var center := Vector2(0.5, _finite_float(level.get("shooterY", 0.9)))
	points.append(center)
	var remaining := 4.0
	var bounces := 0
	for _step_index in 420:
		if remaining <= 0.0001:
			break
		var hit := _projectile_hit(center, velocity, radius, level, remaining)
		if not bool(hit.get("hit", false)):
			points.append(center + velocity * remaining)
			break
		var travel_time := clampf(_finite_float(hit.get("t", 0.0)), 0.0, remaining)
		center += velocity * travel_time
		points.append(center)
		var kind := str(hit.get("kind", ""))
		if kind in ["ceiling", "bubble"]:
			var snap := _choose_snap_cell(center, hit, kind == "ceiling", level)
			if snap.is_empty():
				points.append(center)
			else:
				points.append(_cell_center(level, int(snap.row), int(snap.col)))
			break
		var normal: Vector2 = hit.get("normal", Vector2.ZERO)
		velocity = ArcadePhysics.reflect_velocity(velocity, normal, 1.0, 0.0)
		center += normal.normalized() * 0.0005
		remaining -= travel_time
		bounces += 1
		if bounces > max_bounces:
			break
	return points


func verify_solution(solution_value: Variant) -> Dictionary:
	if not solution_value is Array or (solution_value as Array).is_empty():
		return {"ok": false, "message": "解法为空"}
	var level := _level()
	var colors: Array = palette()
	var probe = BubbleRules.new()
	var players := [
		{"id":"bubble-probe-a","name":"甲","age":8,"color":"#d56c29"},
		{"id":"bubble-probe-b","name":"乙","age":8,"color":"#2878c8"},
	]
	var mode := str(level.get("mode", "adventure"))
	var probe_state := probe.create_session({
		"gameId":"bubble",
		"modeId":mode,
		"players":players.slice(0, 2 if mode == "classic" else 1),
		"levelId":int(level.get("levelNumber", 1)),
		"level":level,
		"colors":colors,
		"seed":17,
	})
	if str(probe_state.get("phase", "")) != "playing":
		return {"ok": false, "message": str(probe_state.get("reason", "无法开始"))}
	for angle_value in solution_value:
		var angle := deg_to_rad(_finite_float(angle_value))
		probe.set_aim_direction({"x":sin(angle),"y":-cos(angle)})
		var fired := probe.fire()
		if not bool(fired.get("ok", false)):
			return {"ok": false, "message": str(fired.get("message", "发射失败"))}
		var guard := 0
		while not probe.projectile_snapshot().is_empty() and guard < 1200:
			probe.tick(LOGIC_STEP)
			guard += 1
		if str(probe.state.get("phase", "")) == "finished":
			break
	return {
		"ok": str(probe.state.get("phase", "")) == "finished" and bool(probe.state.get("success", false)),
		"state": probe.snapshot(),
		"message": str(probe.state.get("reason", "目标还没有完成")),
	}


func _step(delta: float) -> void:
	var projectile_value: Variant = state.get("projectile", {})
	if not projectile_value is Dictionary or projectile_value.is_empty():
		return
	var projectile: Dictionary = projectile_value
	var level := _level()
	var radius := _finite_float(level.get("radius", 0.043))
	var speed := maxf(0.15, _finite_float(projectile.get("speed", 0.9)))
	var direction := Vector2(_finite_float(projectile.get("dirX", 0.0)), _finite_float(projectile.get("dirY", -1.0))).normalized()
	var velocity := direction * speed
	var center := Vector2(_finite_float(projectile.get("x", 0.5)), _finite_float(projectile.get("y", 0.9)))
	var remaining := delta
	for _collision_index in 6:
		if remaining <= 0.000001:
			break
		var hit := _projectile_hit(center, velocity, radius, level, remaining)
		if not bool(hit.get("hit", false)):
			center += velocity * remaining
			remaining = 0.0
			break
		var travel_time := clampf(_finite_float(hit.get("t", 0.0)), 0.0, remaining)
		center += velocity * travel_time
		remaining -= travel_time
		var kind := str(hit.get("kind", ""))
		if kind == "ceiling":
			_attach_and_finish_shot(center, {}, true)
			return
		if kind == "bubble":
			_attach_and_finish_shot(center, hit, false)
			return
		var normal: Vector2 = hit.get("normal", Vector2.ZERO)
		velocity = ArcadePhysics.reflect_velocity(velocity, normal, 1.0, 0.0)
		center += normal.normalized() * 0.0005
		_add_event({
			"type":"bounce",
			"x":center.x,
			"y":center.y,
			"color":_color_hex(str(projectile.get("color", ""))),
			"colorId":str(projectile.get("color", "")),
			"normalX":normal.x,
			"normalY":normal.y,
		})
		if travel_time <= 0.000001:
			break
	projectile.x = center.x
	projectile.y = center.y
	projectile.dirX = velocity.normalized().x
	projectile.dirY = velocity.normalized().y
	state.projectile = projectile


func _projectile_hit(center: Vector2, velocity: Vector2, radius: float, level: Dictionary, max_time: float) -> Dictionary:
	var hits: Array = []
	var columns := int(level.get("columns", 0))
	var bubble_radius := _finite_float(level.get("radius", radius))
	var left := 0.5 - float(columns) * bubble_radius
	var right := 0.5 + float(columns) * bubble_radius
	var ceiling := _finite_float(level.get("ceiling", 0.035))
	var shooter_y := _finite_float(level.get("shooterY", 0.9))
	var ceiling_hit := ArcadePhysics.sweep_circle_segment(
		center, velocity, radius,
		Vector2(left, ceiling), Vector2(right, ceiling),
		0.0, max_time
	)
	if bool(ceiling_hit.get("hit", false)):
		ceiling_hit.kind = "ceiling"
		ceiling_hit.order = 2
		hits.append(ceiling_hit)
	var left_hit := ArcadePhysics.sweep_circle_segment(
		center, velocity, radius,
		Vector2(left, ceiling), Vector2(left, shooter_y + 0.15),
		0.0, max_time
	)
	if bool(left_hit.get("hit", false)):
		left_hit.kind = "wall_left"
		left_hit.order = 0
		hits.append(left_hit)
	var right_hit := ArcadePhysics.sweep_circle_segment(
		center, velocity, radius,
		Vector2(right, ceiling), Vector2(right, shooter_y + 0.15),
		0.0, max_time
	)
	if bool(right_hit.get("hit", false)):
		right_hit.kind = "wall_right"
		right_hit.order = 1
		hits.append(right_hit)
	var board_value: Variant = state.get("board", [])
	var board: Array = board_value if board_value is Array else []
	for raw in board:
		if not raw is Dictionary:
			continue
		var cell: Dictionary = raw
		var row := int(cell.get("row", 0))
		var column := int(cell.get("col", 0))
		var bubble_center := _cell_center(level, row, column)
		var bubble_hit := ArcadePhysics.sweep_circle_circle(
			center, velocity, radius,
			bubble_center, Vector2.ZERO, bubble_radius,
			max_time
		)
		if bool(bubble_hit.get("hit", false)):
			bubble_hit.kind = "bubble"
			bubble_hit.order = 100
			bubble_hit.id = _cell_key(row, column)
			bubble_hit.row = row
			bubble_hit.col = column
			bubble_hit.color = str(cell.get("color", ""))
			hits.append(bubble_hit)
	return ArcadePhysics.earliest_hit(hits)


func _attach_and_finish_shot(point: Vector2, anchor_hit: Dictionary, ceiling: bool) -> void:
	var level := _level()
	var snap := _choose_snap_cell(point, anchor_hit, ceiling, level)
	var projectile_value: Variant = state.get("projectile", {})
	var projectile: Dictionary = projectile_value if projectile_value is Dictionary else {}
	if snap.is_empty():
		_add_event({"type":"miss", "x":point.x, "y":point.y})
	else:
		var board: Array = state.get("board", [])
		board.append({
			"row": int(snap.row),
			"col": int(snap.col),
			"color": str(projectile.get("color", "")),
			"star": false,
		})
		state.board = board
		var center := _cell_center(level, int(snap.row), int(snap.col))
		_add_event({
			"type":"attach",
			"row":int(snap.row),
			"col":int(snap.col),
			"x":center.x,
			"y":center.y,
			"color":_color_hex(str(projectile.get("color", ""))),
			"colorId":str(projectile.get("color", "")),
		})
		_resolve_matches(int(snap.row), int(snap.col))
	state.projectile = {}
	state.physicsAccumulator = 0.0
	_finish_shot()


func _choose_snap_cell(point: Vector2, anchor_hit: Dictionary, ceiling: bool, level: Dictionary) -> Dictionary:
	var board_value: Variant = state.get("board", [])
	var board: Array = board_value if board_value is Array else []
	var occupied := _board_key_set(board)
	var candidates: Array = []
	if ceiling:
		var columns := int(level.get("columns", 0))
		for column in columns:
			if not occupied.has(_cell_key(0, column)):
				candidates.append({"row":0,"col":column})
	elif not anchor_hit.is_empty():
		var anchor_row := int(anchor_hit.get("row", -1))
		var anchor_col := int(anchor_hit.get("col", -1))
		for neighbor in _neighbors(anchor_row, anchor_col):
			if not occupied.has(_cell_key(int(neighbor.y), int(neighbor.x))):
				candidates.append({"row":int(neighbor.y),"col":int(neighbor.x)})
	if candidates.is_empty():
		candidates = _frontier_empty_cells(board, level)
	var best := {}
	var best_distance := INF
	for raw in candidates:
		var candidate: Dictionary = raw
		var row := int(candidate.get("row", -1))
		var column := int(candidate.get("col", -1))
		if not _cell_exists(level, row, column):
			continue
		if occupied.has(_cell_key(row, column)):
			continue
		var center := _cell_center(level, row, column)
		var distance := center.distance_squared_to(point)
		if distance < best_distance - 0.0000001:
			best_distance = distance
			best = {"row":row, "col":column}
		elif is_equal_approx(distance, best_distance):
			var current_row := int(best.get("row", 9999))
			var current_col := int(best.get("col", 9999))
			if row < current_row or (row == current_row and column < current_col):
				best = {"row":row, "col":column}
	return best


func _resolve_matches(row: int, column: int) -> void:
	var level := _level()
	var board: Array = state.get("board", [])
	var by_key := _board_lookup(board)
	var start_key := _cell_key(row, column)
	if not by_key.has(start_key):
		return
	var color := str(by_key[start_key].get("color", ""))
	var group := _connected_same_color(start_key, color, by_key)
	if group.size() >= 3:
		var popped_cells: Array = []
		var kept: Array = []
		for raw in board:
			var cell: Dictionary = raw
			var key := _cell_key(int(cell.get("row", 0)), int(cell.get("col", 0)))
			if group.has(key):
				var center := _cell_center(level, int(cell.row), int(cell.col))
				popped_cells.append({
					"row":int(cell.row),
					"col":int(cell.col),
					"color":str(cell.get("color", "")),
					"hex":_color_hex(str(cell.get("color", ""))),
					"star":bool(cell.get("star", false)),
					"x":center.x,
					"y":center.y,
				})
			else:
				kept.append(cell)
		state.board = kept
		var current_color := str(state.get("currentColor", ""))
		var colors_popped: Dictionary = state.get("colorsPopped", {})
		colors_popped[color] = int(colors_popped.get(color, 0)) + popped_cells.size()
		state.colorsPopped = colors_popped
		state.popped = int(state.get("popped", 0)) + popped_cells.size()
		state.score = int(state.get("score", 0)) + popped_cells.size() * 10 + maxi(0, popped_cells.size() - 3) * 5
		var newly_stars := 0
		for cell in popped_cells:
			if bool(cell.get("star", false)):
				newly_stars += 1
		state.starsPopped = int(state.get("starsPopped", 0)) + newly_stars
		_add_event({
			"type":"pop",
			"cells":popped_cells,
			"count":popped_cells.size(),
			"color":_color_hex(color),
			"colorId":color,
			"x":_cell_center(level, row, column).x,
			"y":_cell_center(level, row, column).y,
			"newStars":newly_stars,
			"nextColor":current_color,
		})
		var remaining_board: Array = state.get("board", [])
		var connected := _connected_from_ceiling(remaining_board, int(level.get("columns", 0)))
		var dropped_cells: Array = []
		var stable: Array = []
		for raw in remaining_board:
			var cell: Dictionary = raw
			var key := _cell_key(int(cell.get("row", 0)), int(cell.get("col", 0)))
			if connected.has(key):
				stable.append(cell)
			else:
				var center := _cell_center(level, int(cell.row), int(cell.col))
				dropped_cells.append({
					"row":int(cell.row),
					"col":int(cell.col),
					"color":str(cell.get("color", "")),
					"hex":_color_hex(str(cell.get("color", ""))),
					"star":bool(cell.get("star", false)),
					"x":center.x,
					"y":center.y,
				})
		state.board = stable
		if not dropped_cells.is_empty():
			state.dropped = int(state.get("dropped", 0)) + dropped_cells.size()
			state.score = int(state.get("score", 0)) + dropped_cells.size() * 15
			_add_event({
				"type":"drop",
				"cells":dropped_cells,
				"count":dropped_cells.size(),
				"color":_color_hex(color),
				"x":dropped_cells[0].x,
				"y":dropped_cells[0].y,
			})
		if state.has("boardColorCounts"):
			state.boardColorCounts = _board_color_counts(state.get("board", []))


func _finish_shot() -> void:
	var mode := str(state.get("modeId", "adventure"))
	state.turnCount = int(state.get("turnCount", 0)) + 1
	if goals_complete():
		_finish(true, "目标完成啦")
		return
	if int(state.get("movesUsed", 0)) >= int(state.get("movesLimit", 1)):
		_finish(false, "步数用完了，再试一次")
		return
	if _danger_reached():
		_finish(false, "泡泡落得太低了，再试一次")
		return
	state.turn = (int(state.get("turn", 0)) + 1) % (2 if mode == "classic" else 1)
	_add_event({
		"type":"turn",
		"seat":int(state.turn),
		"x":0.5,
		"y":0.5,
		"movesLeft":remaining_moves(),
	})


func _finish(success: bool, reason: String) -> void:
	state.phase = "finished"
	state.success = success
	state.reason = reason
	state.outcome = ("played" if str(state.get("modeId", "")) == "classic" else "win") if success else "retry"
	state.winner = -1 if not success or str(state.get("modeId", "")) == "classic" else 0
	state.projectile = {}
	state.stars = stars()
	_add_event({
		"type":"complete",
		"success":success,
		"x":0.5,
		"y":0.5,
		"reason":reason,
	})


func _goal_current(goal: Dictionary) -> int:
	match str(goal.get("type", "clear")):
		"clear":
			return int(state.get("popped", 0))
		"color":
			return int(state.get("colorsPopped", {}).get(str(goal.get("color", "")), 0))
		"stars":
			return int(state.get("starsPopped", 0))
		"clearAll":
			return 1 if (state.get("board", []) as Array).is_empty() else 0
	return 0


func _goal_label(goal: Dictionary, current: int, target: int) -> String:
	match str(goal.get("type", "clear")):
		"color":
			var definition := color_definition(str(goal.get("color", "")))
			return "%s泡泡 %s/%s" % [str(definition.get("name", "同色")).replace("泡泡", ""), current, target]
		"stars":
			return "亮星 %s/%s" % [current, target]
		"clearAll":
			return "清空泡泡" if current >= target else "清空全部泡泡"
	return "连消 %s/%s" % [current, target]


func _danger_reached() -> bool:
	var level := _level()
	var danger_y := _finite_float(level.get("dangerY", 0.69))
	var radius := _finite_float(level.get("radius", 0.043))
	var board_value: Variant = state.get("board", [])
	for raw in board_value if board_value is Array else []:
		if raw is Dictionary:
			var center := _cell_center(level, int(raw.get("row", 0)), int(raw.get("col", 0)))
			if center.y + radius >= danger_y:
				return true
	return false


func _preview_snap_center(point: Vector2, hit: Dictionary, level: Dictionary, ceiling: bool) -> Vector2:
	var board_value: Variant = state.get("board", [])
	var board: Array = board_value if board_value is Array else []
	var occupied := _board_key_set(board)
	var best := Vector2.ZERO
	var best_distance := INF
	if ceiling:
		for column in int(level.get("columns", 0)):
			if occupied.has(_cell_key(0, column)):
				continue
			var center := _cell_center(level, 0, column)
			var distance := center.distance_squared_to(point)
			if distance < best_distance:
				best_distance = distance
				best = center
	elif not hit.is_empty():
		for neighbor in _neighbors(int(hit.get("row", -1)), int(hit.get("col", -1))):
			var row := int(neighbor.y)
			var column := int(neighbor.x)
			if not _cell_exists(level, row, column) or occupied.has(_cell_key(row, column)):
				continue
			var center := _cell_center(level, row, column)
			var distance := center.distance_squared_to(point)
			if distance < best_distance:
				best_distance = distance
				best = center
	return best


func _add_event(event: Dictionary) -> void:
	var events_value: Variant = state.get("events", [])
	var events: Array = events_value if events_value is Array else []
	events.append(event.duplicate(true))
	if events.size() > MAX_EVENTS:
		events = events.slice(events.size() - MAX_EVENTS)
	state.events = events


func _color_hex(identifier: String) -> String:
	var definition := color_definition(identifier)
	return str(definition.get("hex", "#2f7e91"))


func _level() -> Dictionary:
	var value: Variant = state.get("level", {})
	return value if value is Dictionary else {}


func _reject_restore() -> bool:
	state = {}
	_accumulator = 0.0
	return false


static func validate_catalog(value: Variant) -> Dictionary:
	var issues: Array[String] = []
	if not value is Dictionary:
		return {"ok": false, "issues": ["bubble.json 顶层必须是对象"], "validLevels": []}
	var data: Dictionary = value
	if _strict_int(data.get("schemaVersion", data.get("version", null))) != VERSION:
		issues.append("bubble.json 的 schemaVersion 必须是 %s" % VERSION)
	var colors := _normalize_palette(data.get("colors", []))
	var palette_validation := _validate_palette(data.get("colors", []))
	for issue in palette_validation.get("issues", []):
		issues.append(str(issue))
	var levels_value: Variant = data.get("levels", null)
	if not levels_value is Array:
		issues.append("bubble.json 缺少 levels 数组")
		return {"ok": false, "issues": issues, "validLevels": []}
	var levels: Array = levels_value
	var mode_counts := {"adventure": 0, "classic": 0}
	var band_counts := {
		"adventure": {"easy":0,"normal":0,"challenge":0},
		"classic": {"easy":0,"normal":0,"challenge":0},
	}
	var next_number := {"adventure":1, "classic":1}
	var seen_ids := {}
	var valid_levels: Array = []
	for index in levels.size():
		if not levels[index] is Dictionary:
			issues.append("第 %s 关不是对象" % (index + 1))
			continue
		var entry: Dictionary = levels[index]
		var validation := validate_level(entry, colors)
		if not bool(validation.get("ok", false)):
			issues.append("%s：%s" % [str(entry.get("id", "第 %s 关" % (index + 1))), str(validation.get("message", "配置异常"))])
			continue
		var normalized: Dictionary = validation.get("level", {})
		var identifier := str(normalized.get("id", ""))
		if seen_ids.has(identifier):
			issues.append("关卡 id 重复：%s" % identifier)
		seen_ids[identifier] = true
		var mode := str(normalized.get("mode", ""))
		var number := int(normalized.get("levelNumber", 0))
		if number != int(next_number.get(mode, 0)):
			issues.append("%s 的 levelNumber 应稳定为 %s" % [identifier, int(next_number.get(mode, 0))])
		next_number[mode] = maxi(int(next_number.get(mode, 1)), number + 1)
		mode_counts[mode] = int(mode_counts.get(mode, 0)) + 1
		var band := str(normalized.get("band", ""))
		band_counts[mode][band] = int(band_counts[mode].get(band, 0)) + 1
		valid_levels.append(normalized)
	if palette_validation.get("ok", false):
		if int(mode_counts.get("adventure", 0)) != 18:
			issues.append("单人闯关必须是 18 关，实际 %s 关" % int(mode_counts.get("adventure", 0)))
		if int(mode_counts.get("classic", 0)) != 6:
			issues.append("双人合作必须是 6 关，实际 %s 关" % int(mode_counts.get("classic", 0)))
		for band in BANDS:
			if int(band_counts["adventure"].get(band, 0)) != 6:
				issues.append("单人 %s 难度必须有 6 关，实际 %s 关" % [band, int(band_counts["adventure"].get(band, 0))])
			if int(band_counts["classic"].get(band, 0)) != 2:
				issues.append("双人 %s 难度必须有 2 关，实际 %s 关" % [band, int(band_counts["classic"].get(band, 0))])
	return {
		"ok": issues.is_empty(),
		"issues": issues,
		"validLevels": valid_levels,
		"modeCounts": mode_counts,
		"bandCounts": band_counts,
		"colors": colors,
	}


static func validate_level(value: Variant, colors: Variant = FALLBACK_COLORS) -> Dictionary:
	if not value is Dictionary:
		return {"ok": false, "message": "关卡必须是对象"}
	var palette := _normalize_palette(colors)
	var level := _normalize_level(value, palette)
	if level.is_empty():
		return {"ok": false, "message": "关卡缺少稳定编号、尺寸或泡泡网格"}
	var identifier := str(level.get("id", ""))
	if not str(level.get("mode", "")) in MODES:
		return {"ok": false, "message": "%s 的 mode 不合法" % identifier}
	if not str(level.get("band", "")) in BANDS:
		return {"ok": false, "message": "%s 的 band 不合法" % identifier}
	var level_number := _strict_int(level.get("levelNumber", null))
	if level_number < 1 or level_number > 99:
		return {"ok": false, "message": "%s 的 levelNumber 不合法" % identifier}
	var min_age := _strict_int(level.get("minAge", null))
	if min_age < 4 or min_age > 12:
		return {"ok": false, "message": "%s 的 minAge 必须在 4–12" % identifier}
	if str(level.get("title", "")).strip_edges().is_empty():
		return {"ok": false, "message": "%s 缺少标题" % identifier}
	var columns := int(level.get("columns", 0))
	if columns < 5 or columns > 11:
		return {"ok": false, "message": "%s 的 columns 必须在 5–11" % identifier}
	var radius := _finite_float(level.get("radius", 0.0))
	if radius < 0.025 or radius > 0.055:
		return {"ok": false, "message": "%s 的 radius 必须在 0.025–0.055" % identifier}
	var rows_value: Variant = level.get("rows", [])
	if not rows_value is Array or rows_value.is_empty() or rows_value.size() > 8:
		return {"ok": false, "message": "%s 的 rows 必须为 1–8 行" % identifier}
	var cells: Array = level.get("cells", [])
	if cells.is_empty():
		return {"ok": false, "message": "%s 没有初始泡泡" % identifier}
	if not _board_connected_to_ceiling(cells, columns):
		return {"ok": false, "message": "%s 的初始泡泡必须连在顶部" % identifier}
	var largest := _largest_color_group(cells)
	if largest >= 3:
		return {"ok": false, "message": "%s 开局已有三连，应先错开颜色" % identifier}
	var star_cells_value: Variant = level.get("starCells", [])
	if not star_cells_value is Array:
		return {"ok": false, "message": "%s 的 starCells 必须是数组" % identifier}
	var star_keys := _star_keys(level)
	for key in star_keys.keys():
		if not _board_key_set(cells).has(key):
			return {"ok": false, "message": "%s 的亮星位置没有泡泡" % identifier}
	var moves := _strict_int(level.get("moves", null))
	if moves < 3 or moves > 30:
		return {"ok": false, "message": "%s 的 moves 必须在 3–30" % identifier}
	var queue_value: Variant = level.get("queue", [])
	if not queue_value is Array or queue_value.size() < moves + 1:
		return {"ok": false, "message": "%s 的颜色队列必须覆盖全部步数" % identifier}
	var color_ids := _color_ids(palette)
	for color in queue_value:
		if not color_ids.has(str(color)):
			return {"ok": false, "message": "%s 的颜色队列含有未知颜色" % identifier}
	var goals_value: Variant = level.get("goals", [])
	if not goals_value is Array or goals_value.is_empty() or goals_value.size() > 2:
		return {"ok": false, "message": "%s 必须有 1 或 2 个目标" % identifier}
	var initial_color_counts := _board_color_counts(cells)
	for raw_goal in goals_value:
		if not raw_goal is Dictionary:
			return {"ok": false, "message": "%s 的目标不是对象" % identifier}
		var goal: Dictionary = raw_goal
		var kind := str(goal.get("type", ""))
		var count := _strict_int(goal.get("count", null))
		if kind not in ["clear", "color", "stars", "clearAll"]:
			return {"ok": false, "message": "%s 的目标类型不合法" % identifier}
		if kind == "clearAll":
			continue
		if count < 1 or count > 60:
			return {"ok": false, "message": "%s 的目标数量不合法" % identifier}
		if kind == "clear" and count > cells.size() + moves:
			return {"ok": false, "message": "%s 的连消目标超过可达泡泡数" % identifier}
		if kind == "color":
			var goal_color := str(goal.get("color", ""))
			if not color_ids.has(goal_color) or int(initial_color_counts.get(goal_color, 0)) + moves < count:
				return {"ok": false, "message": "%s 的消灭同色目标不可达" % identifier}
		if kind == "stars" and count > star_keys.size():
			return {"ok": false, "message": "%s 的亮星目标超过星星数量" % identifier}
	if bool(level.get("coop", false)) != (str(level.get("mode", "")) == "classic"):
		return {"ok": false, "message": "%s 的 coop 必须与模式一致" % identifier}
	if level.has("hintAngle"):
		var hint_angle := _finite_float(level.get("hintAngle", 0.0))
		if absf(hint_angle) > 80.0:
			return {"ok": false, "message": "%s 的 hintAngle 超出瞄准范围" % identifier}
	if level.has("solution"):
		var solution_value: Variant = level.get("solution", [])
		if not solution_value is Array or solution_value.is_empty() or solution_value.size() > moves:
			return {"ok": false, "message": "%s 的 solution 必须覆盖在步数以内" % identifier}
		for angle in solution_value:
			if not (angle is int or angle is float) or absf(float(angle)) > 80.0:
				return {"ok": false, "message": "%s 的 solution 含非法角度" % identifier}
	return {"ok": true, "message": "", "level": level}


static func cell_center_for_level(level: Dictionary, row: int, column: int) -> Vector2:
	return _cell_center(level, row, column)


static func cell_exists(level: Dictionary, row: int, column: int) -> bool:
	return _cell_exists(level, row, column)


static func _normalize_level(value: Variant, colors: Array) -> Dictionary:
	if not value is Dictionary:
		return {}
	var raw: Dictionary = value
	var identifier := str(raw.get("id", "")).strip_edges()
	var mode := str(raw.get("mode", ""))
	var band := str(raw.get("band", ""))
	var level_number := _strict_int(raw.get("levelNumber", raw.get("number", null)))
	var columns := _strict_int(raw.get("columns", null))
	var radius := _finite_float(raw.get("radius", 0.043))
	var rows_value: Variant = raw.get("rows", [])
	if identifier.is_empty() or not rows_value is Array or columns < 5 or columns > 11:
		return {}
	var rows: Array = []
	for raw_row in rows_value:
		rows.append(str(raw_row))
	var color_ids := _color_ids(colors)
	var color_letters := _color_letters(colors)
	var cells: Array = []
	for row_index in rows.size():
		var row_text := str(rows[row_index])
		var expected := columns if row_index % 2 == 0 else columns - 1
		if row_text.length() != expected:
			return {}
		for column_index in expected:
			var letter := row_text.substr(column_index, 1)
			if letter == ".":
				continue
			if not color_letters.has(letter):
				return {}
			cells.append({
				"row": row_index,
				"col": column_index,
				"color": str(color_letters[letter]),
				"star": false,
			})
	var star_cells_value: Variant = raw.get("starCells", [])
	if not star_cells_value is Array:
		return {}
	var star_keys := {}
	for star_value in star_cells_value:
		if not star_value is Dictionary:
			return {}
		var row := _strict_int(star_value.get("row", null))
		var column := _strict_int(star_value.get("col", null))
		if row < 0 or column < 0:
			return {}
		star_keys[_cell_key(row, column)] = true
	for cell in cells:
		if star_keys.has(_cell_key(int(cell.row), int(cell.col))):
			cell.star = true
	var queue_value: Variant = raw.get("queue", [])
	if not queue_value is Array:
		return {}
	var queue: Array = []
	for raw_color in queue_value:
		var identifier_value := str(raw_color)
		if color_ids.has(identifier_value):
			queue.append(identifier_value)
		elif color_letters.has(identifier_value):
			queue.append(str(color_letters[identifier_value]))
		else:
			return {}
	var goals_value: Variant = raw.get("goals", [])
	if not goals_value is Array:
		return {}
	var goals: Array = []
	for goal_value in goals_value:
		if not goal_value is Dictionary:
			return {}
		var goal: Dictionary = goal_value.duplicate(true)
		if goal.has("color"):
			var goal_color := str(goal.get("color", ""))
			if color_letters.has(goal_color):
				goal.color = str(color_letters[goal_color])
			elif not color_ids.has(goal_color):
				return {}
		goals.append(goal)
	var normalized := {
		"id":identifier,
		"levelNumber":level_number,
		"mode":mode,
		"band":band,
		"minAge":maxi(0, _int_value(raw.get("minAge", 0), 0)),
		"title":str(raw.get("title", "")).strip_edges(),
		"columns":columns,
		"radius":radius,
		"ceiling":clampf(_finite_float(raw.get("ceiling", 0.035)), 0.0, 0.12),
		"shooterY":clampf(_finite_float(raw.get("shooterY", 0.9)), 0.78, 0.96),
		"dangerY":clampf(_finite_float(raw.get("dangerY", 0.69)), 0.55, 0.82),
		"shotSpeed":clampf(_finite_float(raw.get("shotSpeed", 0.9)), 0.4, 2.2),
		"maxRows":clampi(_int_value(raw.get("maxRows", maxi(rows.size() + 3, 10)), 10), 6, MAX_ROWS),
		"rows":rows,
		"cells":cells,
		"starCells":star_cells_value.duplicate(true),
		"queue":queue,
		"moves":_int_value(raw.get("moves", 0), 0),
		"goals":goals,
		"coop":bool(raw.get("coop", false)),
		"hint":str(raw.get("hint", "把同色泡泡连成三个，就能一起消掉。")),
		"explanation":str(raw.get("explanation", "")),
	}
	if raw.has("hintAngle"):
		normalized.hintAngle = _finite_float(raw.get("hintAngle", 0.0))
	if raw.get("solution") is Array:
		normalized.solution = raw.get("solution").duplicate()
	return normalized


static func _normalize_palette(value: Variant) -> Array:
	var source: Array = value if value is Array else FALLBACK_COLORS
	var colors: Array = []
	for raw in source:
		if not raw is Dictionary:
			continue
		var color: Dictionary = raw
		var identifier := str(color.get("id", "")).strip_edges()
		var letter := str(color.get("letter", "")).strip_edges()
		if identifier.is_empty() or letter.length() != 1:
			continue
		colors.append({
			"id":identifier,
			"name":str(color.get("name", identifier)),
			"letter":letter,
			"hex":str(color.get("hex", "#2f7e91")),
			"deep":str(color.get("deep", "#1f5361")),
		})
	return colors if not colors.is_empty() else FALLBACK_COLORS.duplicate(true)


static func _validate_palette(value: Variant) -> Dictionary:
	var issues: Array[String] = []
	if not value is Array or (value as Array).size() < 3 or (value as Array).size() > 6:
		return {"ok": false, "issues": ["colors 必须是 3–6 种颜色"]}
	var ids := {}
	var letters := {}
	for raw in value:
		if not raw is Dictionary:
			issues.append("颜色定义不是对象")
			continue
		var identifier := str(raw.get("id", "")).strip_edges()
		var letter := str(raw.get("letter", "")).strip_edges()
		var hex := str(raw.get("hex", ""))
		if identifier.is_empty() or ids.has(identifier):
			issues.append("颜色 id 缺失或重复")
		if letter.length() != 1 or letters.has(letter):
			issues.append("颜色 letter 必须是唯一单字母")
		if not hex.is_valid_html_color():
			issues.append("%s 的颜色值不合法" % identifier)
		ids[identifier] = true
		letters[letter] = true
	return {"ok": issues.is_empty(), "issues": issues}


static func _color_ids(colors: Array) -> Dictionary:
	var result := {}
	for color in colors:
		if color is Dictionary:
			result[str(color.get("id", ""))] = true
	return result


static func _color_letters(colors: Array) -> Dictionary:
	var result := {}
	for color in colors:
		if color is Dictionary:
			result[str(color.get("letter", ""))] = str(color.get("id", ""))
	return result


static func _cell_exists(level: Dictionary, row: int, column: int) -> bool:
	var columns := int(level.get("columns", 0))
	var max_rows := int(level.get("maxRows", MAX_ROWS))
	if row < 0 or row >= max_rows or columns < 1:
		return false
	var row_columns := columns if row % 2 == 0 else columns - 1
	return column >= 0 and column < row_columns


static func _cell_center(level: Dictionary, row: int, column: int) -> Vector2:
	var columns := int(level.get("columns", 0))
	var radius := _finite_float(level.get("radius", 0.043))
	var ceiling := _finite_float(level.get("ceiling", 0.035))
	var left := 0.5 - float(columns) * radius
	return Vector2(
		left + radius + float(column) * radius * 2.0 + float(row % 2) * radius,
		ceiling + radius + float(row) * sqrt(3.0) * radius
	)


static func _neighbors(row: int, column: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = [
		Vector2i(column - 1, row),
		Vector2i(column + 1, row),
	]
	if row % 2 == 0:
		result.append(Vector2i(column - 1, row - 1))
		result.append(Vector2i(column, row - 1))
		result.append(Vector2i(column - 1, row + 1))
		result.append(Vector2i(column, row + 1))
	else:
		result.append(Vector2i(column, row - 1))
		result.append(Vector2i(column + 1, row - 1))
		result.append(Vector2i(column, row + 1))
		result.append(Vector2i(column + 1, row + 1))
	return result


static func _cell_key(row: int, column: int) -> String:
	return "%s:%s" % [row, column]


static func _board_key_set(cells: Array) -> Dictionary:
	var result := {}
	for raw in cells:
		if raw is Dictionary:
			result[_cell_key(int(raw.get("row", -1)), int(raw.get("col", -1)))] = true
	return result


static func _board_lookup(cells: Array) -> Dictionary:
	var result := {}
	for raw in cells:
		if raw is Dictionary:
			result[_cell_key(int(raw.get("row", -1)), int(raw.get("col", -1)))] = raw
	return result


static func _board_color_counts(cells: Array) -> Dictionary:
	var counts := {}
	for raw in cells:
		if not raw is Dictionary:
			continue
		var color := str(raw.get("color", ""))
		counts[color] = int(counts.get(color, 0)) + 1
	return counts


static func _connected_same_color(start_key: String, color: String, lookup: Dictionary) -> Dictionary:
	var visited := {}
	var queue: Array[String] = [start_key]
	while not queue.is_empty():
		var key: String = queue.pop_front()
		if visited.has(key) or not lookup.has(key):
			continue
		var cell: Dictionary = lookup[key]
		if str(cell.get("color", "")) != color:
			continue
		visited[key] = true
		var row := int(cell.get("row", 0))
		var column := int(cell.get("col", 0))
		for neighbor in _neighbors(row, column):
			var next_key := _cell_key(neighbor.y, neighbor.x)
			if lookup.has(next_key) and not visited.has(next_key):
				queue.append(next_key)
	return visited


static func _connected_from_ceiling(cells: Array, columns: int) -> Dictionary:
	var lookup := _board_lookup(cells)
	var connected := {}
	var queue: Array[String] = []
	for column in columns:
		var key := _cell_key(0, column)
		if lookup.has(key):
			queue.append(key)
	while not queue.is_empty():
		var key: String = queue.pop_front()
		if connected.has(key) or not lookup.has(key):
			continue
		connected[key] = true
		var cell: Dictionary = lookup[key]
		for neighbor in _neighbors(int(cell.get("row", 0)), int(cell.get("col", 0))):
			var next_key := _cell_key(neighbor.y, neighbor.x)
			if lookup.has(next_key) and not connected.has(next_key):
				queue.append(next_key)
	return connected


static func _board_connected_to_ceiling(cells: Array, columns: int) -> bool:
	var connected := _connected_from_ceiling(cells, columns)
	return connected.size() == _board_lookup(cells).size()


static func _largest_color_group(cells: Array) -> int:
	var lookup := _board_lookup(cells)
	var visited := {}
	var largest := 0
	for key in lookup.keys():
		if visited.has(key):
			continue
		var cell: Dictionary = lookup[key]
		var group := _connected_same_color(str(key), str(cell.get("color", "")), lookup)
		for grouped_key in group.keys():
			visited[grouped_key] = true
		largest = maxi(largest, group.size())
	return largest


static func _frontier_empty_cells(cells: Array, level: Dictionary) -> Array:
	var occupied := _board_key_set(cells)
	var result: Array = []
	var seen := {}
	for raw in cells:
		if not raw is Dictionary:
			continue
		for neighbor in _neighbors(int(raw.get("row", 0)), int(raw.get("col", 0))):
			var row := int(neighbor.y)
			var column := int(neighbor.x)
			var key := _cell_key(row, column)
			if seen.has(key) or occupied.has(key) or not _cell_exists(level, row, column):
				continue
			seen[key] = true
			result.append({"row":row,"col":column})
	return result


static func _star_keys(level: Dictionary) -> Dictionary:
	var result := {}
	var star_value: Variant = level.get("starCells", [])
	for raw in star_value if star_value is Array else []:
		if raw is Dictionary:
			result[_cell_key(_int_value(raw.get("row", -1), -1), _int_value(raw.get("col", -1), -1))] = true
	return result


static func _strict_int(value: Variant) -> int:
	if value is int:
		return int(value)
	if value is float and is_finite(float(value)) and is_equal_approx(float(value), float(int(value))):
		return int(value)
	return INVALID_INT


static func _int_value(value: Variant, fallback: int) -> int:
	var parsed := _strict_int(value)
	return fallback if parsed == INVALID_INT else parsed


static func _finite_float(value: Variant) -> float:
	if (value is int or value is float) and is_finite(float(value)):
		return float(value)
	return 0.0
