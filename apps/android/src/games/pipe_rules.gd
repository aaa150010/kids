class_name PipeRules
extends GameSession

const VERSION := 1
const DIRECTION_VECTORS := [
	Vector2i(0, -1),
	Vector2i(1, 0),
	Vector2i(0, 1),
	Vector2i(-1, 0),
]
const OPPOSITE := [2, 3, 0, 1]
const DIRECTION_NAMES := ["北", "东", "南", "西"]
const VALID_TYPES := ["straight", "elbow", "tee", "cross", "source", "goal"]
const TYPE_NAMES := {
	"straight": "直水管",
	"elbow": "弯水管",
	"tee": "三通管",
	"cross": "十字管",
	"source": "水源",
	"goal": "花圃",
}
const HINTS_BY_BAND := {"easy": 3, "normal": 2, "challenge": 1}

var level_definition: Dictionary = {}
var _flow_cache: Dictionary = {}
var _flow_dirty := true


func create_session(context: Dictionary) -> Dictionary:
	super.create_session(context)
	var requested_level := clampi(_integer(context.get("levelId", 1), 1), 1, 999)
	var normalized := _normalize_level(context.get("level", {}), requested_level)
	level_definition = normalized.duplicate(true)
	if normalized.is_empty():
		state.merge({
			"pipeVersion": VERSION,
			"modeId": str(context.get("modeId", "classic")),
			"view": "map",
			"levelId": requested_level,
			"pieces": [],
			"phase": "empty",
			"loadError": "这一关的内容没有准备好",
			"reported": false,
		}, true)
		_flow_cache = {}
		_flow_dirty = true
		return state
	var pieces: Array = normalized.pieces.duplicate(true)
	var initial_rotations: Array = []
	for piece in pieces:
		initial_rotations.append(int(piece.get("rotation", 0)))
	var band := str(normalized.get("band", "normal"))
	state.merge({
		"pipeVersion": VERSION,
		"levelId": requested_level,
		"level": normalized.duplicate(true),
		"view": "board",
		"pieces": pieces,
		"initialRotations": initial_rotations,
		"parRotations": _par_rotations(pieces, initial_rotations),
		"turns": 0,
		"hints": 0,
		"hintsMax": int(HINTS_BY_BAND.get(band, 2)),
		"retries": maxi(0, _integer(context.get("retries", 0))),
		"hintIndex": -1,
		"hintRotation": -1,
		"turn": 0,
		"phase": "playing",
		"stars": 0,
		"winner": -1,
		"reason": "",
		"reported": false,
	}, true)
	_flow_dirty = true
	_recompute_flow()
	return state


func snapshot() -> Dictionary:
	state.pipeVersion = VERSION
	return super.snapshot()


func restore(value: Dictionary) -> bool:
	if int(value.get("pipeVersion", 0)) != VERSION:
		return false
	if not super.restore(value):
		return false
	if str(state.get("phase", "")) not in ["playing", "finished", "empty"]:
		return false
	var normalized := _normalize_level(state.get("level", {}), _integer(state.get("levelId", 1), 1))
	if normalized.is_empty():
		return false
	level_definition = normalized.duplicate(true)
	if not _restore_pieces(normalized):
		return false
	if not state.get("initialRotations") is Array:
		return false
	var initial_rotations: Array = state.initialRotations
	if initial_rotations.size() != level_definition.pieces.size():
		return false
	for rotation in initial_rotations:
		if not _valid_rotation(rotation):
			return false
	state.initialRotations = initial_rotations.map(func(rotation): return int(rotation))
	state.parRotations = _par_rotations(level_definition.pieces, state.initialRotations)
	state.turns = clampi(_integer(state.get("turns", 0)), 0, 9999)
	state.hints = clampi(_integer(state.get("hints", 0)), 0, 99)
	var band := str(level_definition.get("band", "normal"))
	state.hintsMax = clampi(_integer(state.get("hintsMax", HINTS_BY_BAND.get(band, 2))), 0, 9)
	state.hints = mini(int(state.hints), int(state.hintsMax))
	state.retries = clampi(_integer(state.get("retries", 0)), 0, 999)
	state.turn = 0 if not _is_cooperative() else clampi(_integer(state.get("turn", 0)), 0, 1)
	state.view = str(state.get("view", "board")) if str(state.get("view", "board")) in ["map", "board"] else "board"
	state.reported = bool(state.get("reported", false))
	state.hintIndex = clampi(_integer(state.get("hintIndex", -1)), -1, level_definition.pieces.size() - 1)
	state.hintRotation = clampi(_integer(state.get("hintRotation", -1)), -1, 3)
	_clear_invalid_hint()
	_flow_dirty = true
	_recompute_flow()
	var phase := str(state.get("phase", "playing"))
	if phase == "empty":
		return true
	if goals_completed():
		if phase == "finished":
			state.stars = stars()
			state.reason = "全部花圃通水啦"
			state.winner = 0 if not _is_cooperative() else -1
		elif phase == "playing":
			finish()
	else:
		if phase == "finished":
			return false
		state.phase = "playing"
		state.stars = 0
		state.winner = -1
		state.reason = ""
	state.pipeVersion = VERSION
	return true


func handle_input(action: Dictionary) -> Dictionary:
	match str(action.get("type", "")):
		"rotate":
			return rotate_piece(_integer(action.get("index", -1), -1))
		"hint":
			return hint()
	return {"ok": false, "message": "这个操作现在不能用"}


func rotate_piece(index: int) -> Dictionary:
	if str(state.get("phase", "")) != "playing":
		return {"ok": false, "message": "这一局已经完成啦"}
	if index < 0 or index >= level_definition.get("pieces", []).size():
		return {"ok": false, "message": "点一截可以转动的水管"}
	var piece: Dictionary = state.pieces[index]
	if str(piece.get("type", "")) not in VALID_TYPES:
		return {"ok": false, "message": "这截水管找不到啦"}
	if bool(piece.get("locked", false)):
		return {"ok": false, "message": "这截水管是固定的，换一截试试"}
	if str(piece.get("type", "")) == "cross":
		return {"ok": false, "message": "十字管四向都通，不需要转动"}
	var actor := current_player_index()
	piece.rotation = (int(piece.get("rotation", 0)) + 1) % 4
	state.turns = int(state.get("turns", 0)) + 1
	if int(state.get("hintIndex", -1)) == index:
		_clear_hint()
	if _is_cooperative():
		state.turn = 1 - int(state.get("turn", 0))
	_flow_dirty = true
	_recompute_flow()
	var completed := goals_completed()
	if completed:
		finish()
	return {
		"ok": true,
		"completed": completed,
		"actor": actor,
		"turn": int(state.get("turn", 0)),
		"wetGoals": wet_goal_count(),
		"goalCount": goal_count(),
		"leaks": leak_count(),
	}


func hint() -> Dictionary:
	if str(state.get("phase", "")) != "playing":
		return {"ok": false, "message": "这一局已经完成啦"}
	var hints_value := int(state.get("hints", 0))
	var hints_max := int(state.get("hintsMax", 2))
	if hints_value >= hints_max:
		return {"ok": false, "message": "这一档的提示已经用完啦"}
	var source := source_position()
	var best_index := -1
	var best_distance := 100000
	for index in state.pieces.size():
		var piece: Dictionary = state.pieces[index]
		if bool(piece.get("locked", false)) or str(piece.get("type", "")) == "cross":
			continue
		if connectors(index) == solution_connectors(index):
			continue
		var distance := absi(int(piece.x) - source.x) + absi(int(piece.y) - source.y)
		if distance < best_distance:
			best_distance = distance
			best_index = index
	if best_index < 0:
		if goals_completed():
			return {"ok": false, "message": "所有花圃都已经喝到水啦"}
		return {"ok": false, "message": "先转动一下水管，再看看提示"}
	state.hints = hints_value + 1
	state.hintIndex = best_index
	state.hintRotation = int(state.pieces[best_index].get("solutionRotation", 0))
	var piece: Dictionary = state.pieces[best_index]
	return {
		"ok": true,
		"index": best_index,
		"rotation": int(state.hintRotation),
		"message": "看，亮起的水管在左边第 %s 列、上边第 %s 行。把它转到发光的出水口方向。" % [
			int(piece.x) + 1,
			int(piece.y) + 1,
		],
	}


func finish() -> void:
	if str(state.get("phase", "")) != "playing":
		return
	state.phase = "finished"
	state.stars = stars()
	state.winner = 0 if not _is_cooperative() else -1
	state.reason = "全部花圃通水啦"
	state.hintIndex = -1
	state.hintRotation = -1


func result() -> Dictionary:
	if str(state.get("phase", "")) != "finished":
		return {}
	return {
		"winner": int(state.get("winner", -1)),
		"reason": str(state.get("reason", "")),
		"phase": "finished",
		"stars": int(state.get("stars", stars())),
		"turns": int(state.get("turns", 0)),
		"parRotations": int(state.get("parRotations", 0)),
		"hints": int(state.get("hints", 0)),
		"retries": int(state.get("retries", 0)),
		"wetGoals": wet_goal_count(),
		"goalCount": goal_count(),
	}


func stars() -> int:
	if str(state.get("phase", "")) != "finished":
		return 0
	var hints := int(state.get("hints", 0))
	var retries := int(state.get("retries", 0))
	var turns := int(state.get("turns", 0))
	var par := int(state.get("parRotations", 0))
	var extra := maxi(0, turns - par)
	var band := str(level_definition.get("band", "normal"))
	var three_extra := 4 if band == "easy" else 2 if band == "normal" else 0
	var two_extra := 12 if band == "easy" else 8 if band == "normal" else 4
	if hints == 0 and retries == 0 and extra <= three_extra:
		return 3
	if hints <= 1 and retries <= 1 and extra <= two_extra:
		return 2
	return 1


func width() -> int:
	return int(level_definition.get("width", 0))


func height() -> int:
	return int(level_definition.get("height", 0))


func level_title() -> String:
	return str(level_definition.get("title", "水管工坊"))


func level_band() -> String:
	return str(level_definition.get("band", "normal"))


func source_position() -> Vector2i:
	var source: Dictionary = level_definition.get("source", {})
	return Vector2i(_integer(source.get("x", 0)), _integer(source.get("y", 0)))


func goal_count() -> int:
	var goals: Variant = level_definition.get("goals", [])
	return goals.size() if goals is Array else 0


func wet_goal_count() -> int:
	return int(flow().get("wetGoalCount", 0))


func goals_completed() -> bool:
	return goal_count() > 0 and wet_goal_count() >= goal_count()


func leak_count() -> int:
	return int(flow().get("leaks", {}).size())


func flow() -> Dictionary:
	if _flow_dirty:
		_recompute_flow()
	return _flow_cache


func is_wet(x: int, y: int) -> bool:
	return bool(flow().get("wet", {}).has(_cell_key(x, y)))


func is_link(x: int, y: int, direction: int) -> bool:
	return bool(flow().get("links", {}).has("%s|%s" % [_cell_key(x, y), direction]))


func is_leak(x: int, y: int, direction: int) -> bool:
	return bool(flow().get("leaks", {}).has("%s|%s" % [_cell_key(x, y), direction]))


func goal_is_wet(goal_index: int) -> bool:
	var goals: Variant = level_definition.get("goals", [])
	if not goals is Array or goal_index < 0 or goal_index >= goals.size():
		return false
	var goal: Dictionary = goals[goal_index]
	return is_wet(_integer(goal.get("x", -1)), _integer(goal.get("y", -1)))


func piece_count() -> int:
	var pieces_value: Variant = state.get("pieces", [])
	return pieces_value.size() if pieces_value is Array else 0


func piece_at(index: int) -> Dictionary:
	if index < 0 or index >= piece_count():
		return {}
	return state.pieces[index]


func piece_index_at(x: int, y: int) -> int:
	for index in piece_count():
		var piece: Dictionary = state.pieces[index]
		if _integer(piece.get("x", -1)) == x and _integer(piece.get("y", -1)) == y:
			return index
	return -1


func connectors(index: int) -> int:
	var piece := piece_at(index)
	if piece.is_empty():
		return 0
	return connector_mask(str(piece.get("type", "")), _integer(piece.get("rotation", 0)))


func solution_connectors(index: int) -> int:
	var piece := piece_at(index)
	if piece.is_empty():
		return 0
	return connector_mask(str(piece.get("type", "")), _integer(piece.get("solutionRotation", 0)))


func is_fixed(index: int) -> bool:
	return bool(piece_at(index).get("locked", false))


func is_hint_piece(index: int) -> bool:
	return index >= 0 and index == int(state.get("hintIndex", -1))


func hint_rotation() -> int:
	return int(state.get("hintRotation", -1))


func current_player_index() -> int:
	if not _is_cooperative():
		return 0
	return clampi(int(state.get("turn", 0)), 0, 1)


func is_cooperative() -> bool:
	return _is_cooperative()


func type_name(index: int) -> String:
	return str(TYPE_NAMES.get(str(piece_at(index).get("type", "")), "水管"))


static func connector_mask(kind: String, rotation: int) -> int:
	var turn := posmod(rotation, 4)
	match kind:
		"straight":
			return ((1 << 0) | (1 << 2)) if turn in [0, 2] else ((1 << 1) | (1 << 3))
		"elbow":
			var elbow_base := (1 << 0) | (1 << 1)
			return ((elbow_base << turn) | (elbow_base >> (4 - turn))) & 0xF
		"tee":
			var tee_base := (1 << 0) | (1 << 1) | (1 << 2)
			return ((tee_base << turn) | (tee_base >> (4 - turn))) & 0xF
		"cross":
			return 0xF
		"source":
			return 1 << ((1 + turn) % 4)
		"goal":
			return 1 << ((3 + turn) % 4)
	return 0


static func direction_name(direction: int) -> String:
	return str(DIRECTION_NAMES[posmod(direction, 4)])


func _recompute_flow() -> void:
	_flow_dirty = false
	_flow_cache = {
		"wet": {},
		"links": {},
		"leaks": {},
		"wetGoalCount": 0,
		"goalCount": goal_count(),
	}
	if level_definition.is_empty() or piece_count() == 0:
		return
	var pieces_by_key := {}
	for index in piece_count():
		var piece: Dictionary = state.pieces[index]
		pieces_by_key[_cell_key(_integer(piece.get("x", -1)), _integer(piece.get("y", -1)))] = piece
	var wall_keys := {}
	var walls: Variant = level_definition.get("walls", [])
	if walls is Array:
		for wall in walls:
			if wall is Dictionary:
				wall_keys[_cell_key(_integer(wall.get("x", -1)), _integer(wall.get("y", -1)))] = true
	var source := source_position()
	var source_key := _cell_key(source.x, source.y)
	if not pieces_by_key.has(source_key) or wall_keys.has(source_key):
		return
	var wet := {source_key: true}
	var queue: Array[String] = [source_key]
	var cursor := 0
	var links := {}
	var leaks := {}
	while cursor < queue.size():
		var current_key := queue[cursor]
		cursor += 1
		var piece: Dictionary = pieces_by_key.get(current_key, {})
		if piece.is_empty():
			continue
		var mask := connector_mask(str(piece.get("type", "")), _integer(piece.get("rotation", 0)))
		for direction in 4:
			if (mask & (1 << direction)) == 0:
				continue
			var delta: Vector2i = DIRECTION_VECTORS[direction]
			var next_x := _integer(piece.get("x", -1)) + delta.x
			var next_y := _integer(piece.get("y", -1)) + delta.y
			var edge_key := "%s|%s" % [current_key, direction]
			if next_x < 0 or next_x >= width() or next_y < 0 or next_y >= height():
				leaks[edge_key] = true
				continue
			var next_key := _cell_key(next_x, next_y)
			if wall_keys.has(next_key) or not pieces_by_key.has(next_key):
				leaks[edge_key] = true
				continue
			var neighbor: Dictionary = pieces_by_key[next_key]
			var neighbor_mask := connector_mask(str(neighbor.get("type", "")), _integer(neighbor.get("rotation", 0)))
			if (neighbor_mask & (1 << OPPOSITE[direction])) == 0:
				leaks[edge_key] = true
				continue
			links[edge_key] = true
			links["%s|%s" % [next_key, OPPOSITE[direction]]] = true
			if not wet.has(next_key):
				wet[next_key] = true
				queue.append(next_key)
	var wet_goals := 0
	var goals: Variant = level_definition.get("goals", [])
	if goals is Array:
		for goal in goals:
			if goal is Dictionary and wet.has(_cell_key(_integer(goal.get("x", -1)), _integer(goal.get("y", -1)))):
				wet_goals += 1
	_flow_cache = {
		"wet": wet,
		"links": links,
		"leaks": leaks,
		"wetGoalCount": wet_goals,
		"goalCount": goal_count(),
	}


func _normalize_level(raw_value: Variant, requested_level: int) -> Dictionary:
	if not raw_value is Dictionary:
		return {}
	var raw: Dictionary = raw_value
	var level_width := _integer(raw.get("width", 0))
	var level_height := _integer(raw.get("height", 0))
	if level_width < 3 or level_width > 12 or level_height < 3 or level_height > 10:
		return {}
	var source_value := _normalize_point(raw.get("source"), level_width, level_height)
	if source_value.is_empty():
		return {}
	var raw_goals: Variant = raw.get("goals", [])
	if not raw_goals is Array or raw_goals.is_empty():
		return {}
	var goals: Array = []
	var goal_keys := {}
	for goal_value in raw_goals:
		var goal := _normalize_point(goal_value, level_width, level_height)
		if goal.is_empty():
			return {}
		var goal_key := _cell_key(goal.x, goal.y)
		if goal_keys.has(goal_key):
			return {}
		goal_keys[goal_key] = true
		goals.append(goal)
	var pieces: Array = []
	var piece_keys := {}
	var raw_pieces: Variant = raw.get("pieces", [])
	if not raw_pieces is Array or raw_pieces.is_empty():
		return {}
	for raw_piece in raw_pieces:
		if not raw_piece is Dictionary:
			return {}
		var piece_type := str(raw_piece.get("type", ""))
		if piece_type not in VALID_TYPES:
			return {}
		var x := _integer(raw_piece.get("x", -1))
		var y := _integer(raw_piece.get("y", -1))
		if x < 0 or x >= level_width or y < 0 or y >= level_height:
			return {}
		var piece_key := _cell_key(x, y)
		if piece_keys.has(piece_key):
			return {}
		var rotation := _integer(raw_piece.get("rotation", -1))
		var solution_rotation := _integer(raw_piece.get("solutionRotation", -1))
		if not _valid_rotation(rotation) or not _valid_rotation(solution_rotation):
			return {}
		if not raw_piece.get("locked", null) is bool:
			return {}
		if bool(raw_piece.locked) and connector_mask(piece_type, rotation) != connector_mask(piece_type, solution_rotation):
			return {}
		piece_keys[piece_key] = true
		pieces.append({
			"x": x,
			"y": y,
			"type": piece_type,
			"rotation": rotation,
			"solutionRotation": solution_rotation,
			"locked": bool(raw_piece.locked),
		})
	var source_key := _cell_key(source_value.x, source_value.y)
	var source_piece := _piece_definition_at(pieces, source_key)
	if source_piece.is_empty() or str(source_piece.get("type", "")) != "source":
		return {}
	for goal in goals:
		var goal_piece := _piece_definition_at(pieces, _cell_key(goal.x, goal.y))
		if goal_piece.is_empty() or str(goal_piece.get("type", "")) != "goal":
			return {}
	var walls := _normalize_points(raw.get("walls", []), level_width, level_height)
	if not raw.get("walls", []) is Array:
		return {}
	for wall in walls:
		if piece_keys.has(_cell_key(wall.x, wall.y)):
			return {}
	var fixed := _normalize_points(raw.get("fixed", []), level_width, level_height)
	if not raw.get("fixed", []) is Array:
		return {}
	for fixed_point in fixed:
		var fixed_piece := _piece_definition_at(pieces, _cell_key(fixed_point.x, fixed_point.y))
		if fixed_piece.is_empty() or not bool(fixed_piece.get("locked", false)):
			return {}
	if fixed.is_empty() and walls.is_empty():
		return {}
	var title := str(raw.get("title", "")).strip_edges()
	var identifier := str(raw.get("id", "")).strip_edges()
	var band := str(raw.get("band", "normal"))
	if title.is_empty() or identifier.is_empty() or band not in ["easy", "normal", "challenge"]:
		return {}
	var min_age := _integer(raw.get("minAge", 0))
	if min_age < 4 or min_age > 12:
		return {}
	var normalized := {
		"id": identifier,
		"band": band,
		"minAge": min_age,
		"title": title,
		"width": level_width,
		"height": level_height,
		"source": source_value,
		"goals": goals,
		"fixed": fixed,
		"walls": walls,
		"pieces": pieces,
		"levelNumber": requested_level,
	}
	if not _solution_reaches_all_goals(normalized):
		return {}
	return normalized


func _restore_pieces(normalized: Dictionary) -> bool:
	var saved_value: Variant = state.get("pieces", null)
	if not saved_value is Array or saved_value.is_empty():
		return false
	var saved: Array = saved_value
	var expected: Array = normalized.pieces
	if saved.size() != expected.size():
		return false
	var expected_by_key := {}
	for entry in expected:
		expected_by_key[_cell_key(int(entry.x), int(entry.y))] = entry
	var restored: Array = []
	var seen := {}
	for entry in saved:
		if not entry is Dictionary:
			return false
		var x := _integer(entry.get("x", -1))
		var y := _integer(entry.get("y", -1))
		var cell_key := _cell_key(x, y)
		if seen.has(cell_key) or not expected_by_key.has(cell_key):
			return false
		var expected_piece: Dictionary = expected_by_key[cell_key]
		var piece_type := str(entry.get("type", ""))
		if piece_type != str(expected_piece.get("type", "")):
			return false
		if int(entry.get("solutionRotation", -1)) != int(expected_piece.get("solutionRotation", -2)):
			return false
		if bool(entry.get("locked", false)) != bool(expected_piece.get("locked", false)):
			return false
		var rotation := _integer(entry.get("rotation", -1))
		if not _valid_rotation(rotation):
			return false
		if bool(entry.get("locked", false)) and connector_mask(piece_type, rotation) != connector_mask(piece_type, int(entry.get("solutionRotation", 0))):
			return false
		seen[cell_key] = true
		restored.append({
			"x": x,
			"y": y,
			"type": piece_type,
			"rotation": rotation,
			"solutionRotation": int(entry.get("solutionRotation", 0)),
			"locked": bool(entry.get("locked", false)),
		})
	state.pieces = restored
	return seen.size() == expected.size()


func _par_rotations(pieces: Array, initial_rotations: Array) -> int:
	var result := 0
	for index in pieces.size():
		if index >= initial_rotations.size():
			continue
		var piece: Dictionary = pieces[index]
		var piece_type := str(piece.get("type", ""))
		var from_rotation := int(initial_rotations[index])
		var target_mask := connector_mask(piece_type, int(piece.get("solutionRotation", 0)))
		var shortest := 4
		for turns in 4:
			if connector_mask(piece_type, (from_rotation + turns) % 4) == target_mask:
				shortest = turns
				break
		result += shortest
	return result


func _clear_invalid_hint() -> void:
	var index := int(state.get("hintIndex", -1))
	if index < 0 or index >= piece_count():
		_clear_hint()
		return
	var piece: Dictionary = state.pieces[index]
	if bool(piece.get("locked", false)) or connectors(index) == solution_connectors(index):
		_clear_hint()
		return
	if not _valid_rotation(state.get("hintRotation", -1)):
		_clear_hint()


func _clear_hint() -> void:
	state.hintIndex = -1
	state.hintRotation = -1


func _is_cooperative() -> bool:
	var players_value: Variant = state.get("players", [])
	return str(state.get("modeId", "classic")) == "classic" and players_value is Array and players_value.size() >= 2


func _normalize_point(value: Variant, level_width: int, level_height: int) -> Dictionary:
	if not value is Dictionary:
		return {}
	var x := _integer(value.get("x", -1))
	var y := _integer(value.get("y", -1))
	if x < 0 or x >= level_width or y < 0 or y >= level_height:
		return {}
	return {"x": x, "y": y}


func _normalize_points(values: Variant, level_width: int, level_height: int) -> Array:
	var result: Array = []
	if not values is Array:
		return result
	var seen := {}
	for value in values:
		var point := _normalize_point(value, level_width, level_height)
		if point.is_empty():
			continue
		var point_key := _cell_key(point.x, point.y)
		if seen.has(point_key):
			continue
		seen[point_key] = true
		result.append(point)
	return result


func _piece_definition_at(pieces: Array, cell_key: String) -> Dictionary:
	for piece in pieces:
		if _cell_key(int(piece.get("x", -1)), int(piece.get("y", -1))) == cell_key:
			return piece
	return {}


func _solution_reaches_all_goals(level: Dictionary) -> bool:
	var pieces: Array = level.get("pieces", [])
	var pieces_by_key := {}
	for piece in pieces:
		pieces_by_key[_cell_key(int(piece.get("x", -1)), int(piece.get("y", -1)))] = piece
	var wall_keys := {}
	for wall in level.get("walls", []):
		wall_keys[_cell_key(int(wall.get("x", -1)), int(wall.get("y", -1)))] = true
	var source: Dictionary = level.get("source", {})
	var source_key := _cell_key(int(source.get("x", -1)), int(source.get("y", -1)))
	if not pieces_by_key.has(source_key):
		return false
	var reached := {source_key: true}
	var queue: Array[String] = [source_key]
	var cursor := 0
	while cursor < queue.size():
		var current_key := queue[cursor]
		cursor += 1
		var piece: Dictionary = pieces_by_key.get(current_key, {})
		if piece.is_empty():
			continue
		var mask := connector_mask(str(piece.get("type", "")), int(piece.get("solutionRotation", 0)))
		for direction in 4:
			if (mask & (1 << direction)) == 0:
				continue
			var delta: Vector2i = DIRECTION_VECTORS[direction]
			var next_x := int(piece.get("x", -1)) + delta.x
			var next_y := int(piece.get("y", -1)) + delta.y
			var next_key := _cell_key(next_x, next_y)
			if wall_keys.has(next_key) or not pieces_by_key.has(next_key):
				continue
			var neighbor: Dictionary = pieces_by_key[next_key]
			var neighbor_mask := connector_mask(str(neighbor.get("type", "")), int(neighbor.get("solutionRotation", 0)))
			if (neighbor_mask & (1 << OPPOSITE[direction])) == 0:
				continue
			if not reached.has(next_key):
				reached[next_key] = true
				queue.append(next_key)
	for goal in level.get("goals", []):
		if not reached.has(_cell_key(int(goal.get("x", -1)), int(goal.get("y", -1)))):
			return false
	return true


func _valid_rotation(value: Variant) -> bool:
	if not (value is int or value is float):
		return false
	var number := int(value)
	return number >= 0 and number <= 3 and is_equal_approx(float(value), float(number))


func _integer(value: Variant, fallback: int = 0) -> int:
	if value is int:
		return value
	if value is float and is_finite(value):
		return int(value)
	return fallback


func _cell_key(x: int, y: int) -> String:
	return "%s,%s" % [x, y]
