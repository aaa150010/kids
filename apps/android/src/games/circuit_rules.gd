class_name CircuitRules
extends GameSession

const VERSION := 1
const SINGLE_LEVEL_COUNT := 24
const COOP_LEVEL_COUNT := 8
const DIRECTION_VECTORS := [
	Vector2i(0, -1),
	Vector2i(1, 0),
	Vector2i(0, 1),
	Vector2i(-1, 0),
]
const OPPOSITE := [2, 3, 0, 1]
const DIRECTION_NAMES := ["上", "右", "下", "左"]
const VALID_TYPES := ["battery", "wire", "switch", "bulb", "fan", "buzzer", "terminal", "resistor"]
const GOAL_TYPES := ["bulb", "fan", "buzzer"]
const TYPE_NAMES := {
	"battery": "低压电池",
	"wire": "导线",
	"switch": "开关",
	"bulb": "小灯泡",
	"fan": "小风扇",
	"buzzer": "蜂鸣器",
	"terminal": "接线端子",
	"resistor": "电阻",
}
const HINTS_BY_BAND := {"easy": 3, "normal": 2, "challenge": 1}

var level_definition: Dictionary = {}
var _flow_cache: Dictionary = {}
var _flow_dirty := true


static func level_count(mode_id: String) -> int:
	return COOP_LEVEL_COUNT if mode_id == "classic" else SINGLE_LEVEL_COUNT


static func validate_catalog(value: Variant) -> Dictionary:
	var issues: Array[String] = []
	if not value is Dictionary:
		return {"ok": false, "issues": ["circuit.json 顶层必须是对象"], "levels": []}
	var catalog: Dictionary = value
	if _integer(catalog.get("version", 0)) != VERSION:
		issues.append("circuit.json 的 version 必须是 %s" % VERSION)
	var levels_value: Variant = catalog.get("levels", null)
	if not levels_value is Array:
		return {"ok": false, "issues": issues + ["circuit.json 缺少 levels 数组"], "levels": []}
	var levels: Array = levels_value
	if levels.size() != SINGLE_LEVEL_COUNT + COOP_LEVEL_COUNT:
		issues.append("电路关卡总数必须是 %s，实际 %s" % [SINGLE_LEVEL_COUNT + COOP_LEVEL_COUNT, levels.size()])
	var ids := {}
	var mode_counts := {"adventure": 0, "classic": 0}
	var band_counts := {
		"adventure": {"easy": 0, "normal": 0, "challenge": 0},
		"classic": {"easy": 0, "normal": 0, "challenge": 0},
	}
	var valid_levels: Array = []
	var players := [
		{"id": "fixture-a", "name": "测试一号", "age": 8, "color": "#a55b2a", "avatar": "🦊"},
		{"id": "fixture-b", "name": "测试二号", "age": 9, "color": "#167d74", "avatar": "🐼"},
	]
	for index in levels.size():
		var raw: Variant = levels[index]
		if not raw is Dictionary:
			issues.append("第 %s 个电路不是对象" % (index + 1))
			continue
		var level: Dictionary = raw
		var expected_mode := "classic" if index >= SINGLE_LEVEL_COUNT else "adventure"
		var declared_mode := str(level.get("mode", expected_mode))
		if declared_mode != expected_mode:
			issues.append("第 %s 个电路的 mode 应为 %s，实际 %s" % [index + 1, expected_mode, declared_mode])
			continue
		var identifier := str(level.get("id", "")).strip_edges()
		if identifier.is_empty() or ids.has(identifier):
			issues.append("第 %s 个电路缺少唯一 id" % (index + 1))
			continue
		ids[identifier] = true
		var player_count := 2 if expected_mode == "classic" else 1
		var level_number := index + 1 if expected_mode == "adventure" else index - SINGLE_LEVEL_COUNT + 1
		var probe = CircuitRules.new()
		probe.create_session({
			"gameId": "circuit",
			"modeId": expected_mode,
			"players": players.slice(0, player_count),
			"levelId": level_number,
			"level": level,
			"seed": 7000 + index,
		})
		if str(probe.state.get("phase", "")) != "playing" or probe.goal_count() <= 0:
			issues.append("%s 的电路无法开始或一开始就亮完了" % identifier)
			continue
		var replay_probe = CircuitRules.new()
		replay_probe.create_session({
			"gameId": "circuit", "modeId": expected_mode,
			"players": players.slice(0, player_count),
			"levelId": level_number, "level": level, "seed": 8000 + index,
		})
		var replay_ok := true
		for step_value in level.get("solution", []):
			if not step_value is Dictionary:
				replay_ok = false
				break
			var step: Dictionary = step_value
			var index_step := int(step.get("index", -1))
			if index_step < 0 or index_step >= replay_probe.piece_count():
				replay_ok = false
				break
			if step.has("rotation"):
				var rotate_guard := 0
				while int(replay_probe.piece_at(index_step).get("rotation", -1)) != int(step.get("rotation", 0)) and rotate_guard < 4:
					replay_probe.rotate_part(index_step)
					rotate_guard += 1
			if step.has("closed") and bool(replay_probe.piece_at(index_step).get("closed", false)) != bool(step.get("closed", false)):
				replay_probe.toggle_switch(index_step)
		if not replay_ok or not replay_probe.goals_completed() or str(replay_probe.state.get("phase", "")) != "finished":
			issues.append("%s 的固定解没有接通全部目标" % identifier)
			continue
		var band := str(level.get("band", ""))
		if not band in ["easy", "normal", "challenge"]:
			issues.append("%s 的难度带不合法" % identifier)
			continue
		mode_counts[expected_mode] = int(mode_counts[expected_mode]) + 1
		band_counts[expected_mode][band] = int(band_counts[expected_mode].get(band, 0)) + 1
		valid_levels.append(level.duplicate(true))
	if int(mode_counts.get("adventure", 0)) != SINGLE_LEVEL_COUNT:
		issues.append("单人电路必须是 %s 关，经过校验的只有 %s 关" % [SINGLE_LEVEL_COUNT, int(mode_counts.get("adventure", 0))])
	if int(mode_counts.get("classic", 0)) != COOP_LEVEL_COUNT:
		issues.append("协作电路必须是 %s 关，经过校验的只有 %s 关" % [COOP_LEVEL_COUNT, int(mode_counts.get("classic", 0))])
	for band in ["easy", "normal", "challenge"]:
		if int(band_counts["adventure"].get(band, 0)) != 8:
			issues.append("单人 %s 电路必须是 8 关" % band)
	if int(band_counts["classic"].get("easy", 0)) != 2 or int(band_counts["classic"].get("normal", 0)) != 4 or int(band_counts["classic"].get("challenge", 0)) != 2:
		issues.append("协作电路难度分布应为轻松 2、标准 4、挑战 2")
	return {"ok": issues.is_empty(), "issues": issues, "levels": valid_levels}


func create_session(context: Dictionary) -> Dictionary:
	super.create_session(context)
	var requested_mode := "classic" if str(context.get("modeId", "adventure")) == "classic" else "adventure"
	var requested_level := clampi(_integer(context.get("levelId", 1), 1), 1, level_count(requested_mode))
	var normalized := _normalize_level(context.get("level", {}), requested_level)
	var players_value: Variant = context.get("players", [])
	if not normalized.is_empty() and str(normalized.get("mode", requested_mode)) != requested_mode:
		normalized = {}
	if requested_mode == "classic" and (not players_value is Array or players_value.size() < 2):
		normalized = {}
	if requested_mode == "adventure" and players_value is Array and players_value.size() > 1:
		normalized = {}
	level_definition = normalized.duplicate(true)
	var band := str(normalized.get("band", "normal"))
	if normalized.is_empty():
		state.merge({
			"circuitVersion": VERSION,
			"modeId": requested_mode,
			"levelId": requested_level,
			"view": "map",
			"parts": [],
			"phase": "empty",
			"loadError": "这一关的安全电路还没有准备好。",
			"reported": false,
			"faultIndex": -1,
			"lastFault": "这一关的内容不完整，请先回到地图。",
		}, true)
		_flow_cache = {}
		_flow_dirty = true
		return state
	var parts: Array = normalized.parts.duplicate(true)
	var initial_rotations: Array = []
	var initial_closed: Array = []
	for piece in parts:
		initial_rotations.append(int(piece.rotation))
		initial_closed.append(bool(piece.closed))
	state.merge({
		"circuitVersion": VERSION,
		"modeId": requested_mode,
		"levelId": requested_level,
		"level": normalized,
		"view": "board",
		"parts": parts,
		"initialRotations": initial_rotations,
		"initialClosed": initial_closed,
		"parActions": _par_actions(parts, initial_rotations, initial_closed),
		"actions": 0,
		"hints": 0,
		"hintsMax": int(HINTS_BY_BAND.get(band, 2)),
		"retries": maxi(0, _integer(context.get("retries", 0))),
		"hintIndex": -1,
		"hintMessage": "",
		"faultIndex": -1,
		"lastFault": "",
		"turn": 0,
		"phase": "playing",
		"stars": 0,
		"winner": -1,
		"reason": "",
		"reported": false,
	}, true)
	_flow_dirty = true
	_recompute_flow()
	if goals_completed():
		finish()
	else:
		_analyse_fault()
	return state


func snapshot() -> Dictionary:
	state.circuitVersion = VERSION
	return super.snapshot()


func restore(value: Dictionary) -> bool:
	if int(value.get("circuitVersion", 0)) != VERSION:
		return false
	if not super.restore(value):
		return false
	if str(state.get("phase", "")) not in ["playing", "finished", "empty"]:
		return false
	if str(state.get("modeId", "")) not in ["adventure", "classic"]:
		return false
	var stored_level_id := _integer(state.get("levelId", 0), 0)
	var max_level := level_count(str(state.get("modeId", "adventure")))
	if stored_level_id < 1 or stored_level_id > max_level:
		return false
	var requested_level := stored_level_id
	var raw_level_value: Variant = state.get("level", {})
	if not raw_level_value is Dictionary:
		return false
	if _integer(raw_level_value.get("levelNumber", -1), -1) != requested_level:
		return false
	var normalized := _normalize_level(raw_level_value, requested_level)
	if normalized.is_empty():
		return false
	if str(normalized.get("mode", "adventure")) != str(state.get("modeId", "adventure")):
		return false
	if int(normalized.get("levelNumber", -1)) != requested_level:
		return false
	var stored_level: Variant = state.get("level", {})
	if not stored_level is Dictionary or str(stored_level.get("id", "")) != str(normalized.get("id", "")):
		return false
	level_definition = normalized.duplicate(true)
	state.levelId = requested_level
	if not _restore_parts(normalized):
		return false
	var expected_parts: Array = normalized.parts
	if not state.get("initialRotations") is Array or not state.get("initialClosed") is Array:
		return false
	var initial_rotations: Array = state.initialRotations
	var initial_closed: Array = state.initialClosed
	if initial_rotations.size() != expected_parts.size() or initial_closed.size() != expected_parts.size():
		return false
	for index in expected_parts.size():
		if _integer(initial_rotations[index], -1) != int(expected_parts[index].rotation):
			return false
		if typeof(initial_closed[index]) != TYPE_BOOL or bool(initial_closed[index]) != bool(expected_parts[index].closed):
			return false
	state.initialRotations = initial_rotations.map(func(value): return _integer(value, 0))
	state.initialClosed = initial_closed.map(func(value): return bool(value))
	state.parActions = _par_actions(level_definition.parts, state.initialRotations, state.initialClosed)
	state.actions = clampi(_integer(state.get("actions", 0)), 0, 9999)
	state.hints = clampi(_integer(state.get("hints", 0)), 0, 99)
	var band := str(level_definition.get("band", "normal"))
	state.hintsMax = clampi(_integer(state.get("hintsMax", HINTS_BY_BAND.get(band, 2))), 0, 9)
	state.hints = mini(int(state.hints), int(state.hintsMax))
	state.retries = clampi(_integer(state.get("retries", 0)), 0, 999)
	state.turn = 0 if not _is_cooperative() else clampi(_integer(state.get("turn", 0)), 0, 1)
	state.view = str(state.get("view", "board")) if str(state.get("view", "board")) in ["map", "board"] else "board"
	state.reported = bool(state.get("reported", false))
	state.hintIndex = clampi(_integer(state.get("hintIndex", -1)), -1, state.parts.size() - 1)
	state.hintMessage = str(state.get("hintMessage", ""))
	state.faultIndex = -1
	state.lastFault = ""
	_clear_invalid_hint()
	_flow_dirty = true
	_recompute_flow()
	var phase := str(state.get("phase", "playing"))
	if phase == "empty":
		return true
	if goals_completed():
		if phase == "finished":
			state.stars = stars()
			state.reason = "全部小电器都通电啦"
			state.winner = 0 if not _is_cooperative() else -1
		else:
			finish()
	else:
		if phase == "finished":
			return false
		state.phase = "playing"
		state.stars = 0
		state.winner = -1
		state.reason = ""
		_analyse_fault()
	state.circuitVersion = VERSION
	return true


func handle_input(action: Dictionary) -> Dictionary:
	match str(action.get("type", "")):
		"tap":
			return _interact_with_part(_integer(action.get("index", -1), -1))
		"rotate":
			return rotate_part(_integer(action.get("index", -1), -1))
		"toggle":
			return toggle_switch(_integer(action.get("index", -1), -1))
		"hint":
			return hint()
	return {"ok": false, "message": "这个操作现在不能用。"}


func _interact_with_part(index: int) -> Dictionary:
	if index < 0 or index >= piece_count():
		return {"ok": false, "message": "点一下发光纸板上的导线或开关。"}
	var piece := piece_at(index)
	if str(piece.get("type", "")) == "wire":
		return rotate_part(index)
	if str(piece.get("type", "")) == "switch":
		return toggle_switch(index)
	return {
		"ok": false,
		"message": "这块%s是固定的，点导线或开关来改变线路。" % str(TYPE_NAMES.get(str(piece.get("type", "")), "元件")),
		"faultIndex": index,
	}


func rotate_part(index: int) -> Dictionary:
	if str(state.get("phase", "")) != "playing":
		return {"ok": false, "message": "这一局已经完成啦。"}
	if index < 0 or index >= piece_count():
		return {"ok": false, "message": "点一截可以转动的导线。"}
	var piece: Dictionary = state.parts[index]
	if str(piece.get("type", "")) != "wire":
		return {"ok": false, "message": "这个元件不用转动。"}
	if bool(piece.get("locked", false)):
		return {"ok": false, "message": "这段导线是固定的，换一段试试。"}
	var actor := current_player_index()
	piece.rotation = (int(piece.get("rotation", 0)) + 1) % 4
	state.actions = int(state.get("actions", 0)) + 1
	if int(state.get("hintIndex", -1)) == index:
		_clear_hint()
	if _is_cooperative():
		state.turn = 1 - int(state.get("turn", 0))
	_flow_dirty = true
	_recompute_flow()
	var completed := goals_completed()
	if completed:
		finish()
	else:
		_analyse_fault()
	return {
		"ok": true,
		"action": "rotate",
		"completed": completed,
		"actor": actor,
		"turn": int(state.get("turn", 0)),
		"poweredGoals": powered_goal_count(),
		"goalCount": goal_count(),
		"message": str(state.get("lastFault", "")),
		"faultIndex": int(state.get("faultIndex", -1)),
	}


func toggle_switch(index: int) -> Dictionary:
	if str(state.get("phase", "")) != "playing":
		return {"ok": false, "message": "这一局已经完成啦。"}
	if index < 0 or index >= piece_count():
		return {"ok": false, "message": "点一下纸板上的小开关。"}
	var piece: Dictionary = state.parts[index]
	if str(piece.get("type", "")) != "switch":
		return {"ok": false, "message": "这个元件不用开关。"}
	if bool(piece.get("locked", false)):
		return {"ok": false, "message": "这个开关被固定住了。"}
	var actor := current_player_index()
	piece.closed = not bool(piece.get("closed", false))
	state.actions = int(state.get("actions", 0)) + 1
	if int(state.get("hintIndex", -1)) == index:
		_clear_hint()
	if _is_cooperative():
		state.turn = 1 - int(state.get("turn", 0))
	_flow_dirty = true
	_recompute_flow()
	var completed := goals_completed()
	if completed:
		finish()
	else:
		_analyse_fault()
	return {
		"ok": true,
		"action": "toggle",
		"closed": bool(piece.closed),
		"completed": completed,
		"actor": actor,
		"turn": int(state.get("turn", 0)),
		"poweredGoals": powered_goal_count(),
		"goalCount": goal_count(),
		"message": str(state.get("lastFault", "")),
		"faultIndex": int(state.get("faultIndex", -1)),
	}


func hint() -> Dictionary:
	if str(state.get("phase", "")) != "playing":
		return {"ok": false, "message": "这一局已经完成啦。"}
	var hints_value := int(state.get("hints", 0))
	var hints_max := int(state.get("hintsMax", 2))
	if hints_value >= hints_max:
		return {"ok": false, "message": "这一档的提示已经用完啦。"}
	var source := source_position()
	var best_index := -1
	var best_distance := 100000
	for index in piece_count():
		var piece := piece_at(index)
		if bool(piece.get("locked", false)):
			continue
		var wrong := false
		if str(piece.get("type", "")) == "wire" and int(piece.get("rotation", 0)) != int(piece.get("solutionRotation", 0)):
			wrong = true
		elif str(piece.get("type", "")) == "switch" and bool(piece.get("closed", false)) != bool(piece.get("solutionClosed", false)):
			wrong = true
		if not wrong:
			continue
		var distance := absi(int(piece.x) - source.x) + absi(int(piece.y) - source.y)
		if distance < best_distance:
			best_distance = distance
			best_index = index
	if best_index < 0:
		return {
			"ok": false,
			"message": "可转的导线和开关都已经对好啦，看看哪一个目标还没有通电。",
		}
	state.hints = hints_value + 1
	state.hintIndex = best_index
	state.hintMessage = level_hint()
	var piece := piece_at(best_index)
	return {
		"ok": true,
		"index": best_index,
		"message": "%s 接着看闪光的第 %s 行第 %s 列。" % [
			level_hint(),
			int(piece.y) + 1,
			int(piece.x) + 1,
		],
	}


func finish() -> void:
	if str(state.get("phase", "")) != "playing":
		return
	state.phase = "finished"
	state.stars = stars()
	state.winner = 0 if not _is_cooperative() else -1
	state.reason = "全部小电器都通电啦"
	state.hintIndex = -1
	state.hintMessage = ""
	state.faultIndex = -1
	state.lastFault = ""


func result() -> Dictionary:
	if str(state.get("phase", "")) != "finished":
		return {}
	return {
		"winner": int(state.get("winner", -1)),
		"reason": str(state.get("reason", "")),
		"phase": "finished",
		"stars": int(state.get("stars", stars())),
		"actions": int(state.get("actions", 0)),
		"parActions": int(state.get("parActions", 0)),
		"hints": int(state.get("hints", 0)),
		"retries": int(state.get("retries", 0)),
		"poweredGoals": powered_goal_count(),
		"goalCount": goal_count(),
	}


func stars() -> int:
	if str(state.get("phase", "")) != "finished":
		return 0
	var hints := int(state.get("hints", 0))
	var retries := int(state.get("retries", 0))
	var actions := int(state.get("actions", 0))
	var par := int(state.get("parActions", 0))
	var extra := maxi(0, actions - par)
	var band := str(level_definition.get("band", "normal"))
	var three_extra := 3 if band == "easy" else 2 if band == "normal" else 1
	var two_extra := 8 if band == "easy" else 5 if band == "normal" else 3
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
	return str(level_definition.get("title", "电路小工坊"))


func level_band() -> String:
	return str(level_definition.get("band", "normal"))


func level_narration() -> String:
	return str(level_definition.get("narration", ""))


func level_explanation() -> String:
	return str(level_definition.get("explanation", ""))


func level_hint() -> String:
	return str(level_definition.get("hint", ""))


func source_position() -> Vector2i:
	var source: Dictionary = level_definition.get("source", {})
	return Vector2i(_integer(source.get("x", 0)), _integer(source.get("y", 0)))


func goal_count() -> int:
	var goals: Variant = level_definition.get("goals", [])
	return goals.size() if goals is Array else 0


func powered_goal_count() -> int:
	return int(flow().get("poweredGoalCount", 0))


func goals_completed() -> bool:
	return goal_count() > 0 and powered_goal_count() >= goal_count()


func flow() -> Dictionary:
	if _flow_dirty:
		_recompute_flow()
	return _flow_cache


func piece_count() -> int:
	var pieces_value: Variant = state.get("parts", [])
	return pieces_value.size() if pieces_value is Array else 0


func piece_at(index: int) -> Dictionary:
	if index < 0 or index >= piece_count():
		return {}
	return state.parts[index]


func piece_index_at(x: int, y: int) -> int:
	for index in piece_count():
		var piece: Dictionary = state.parts[index]
		if _integer(piece.get("x", -1)) == x and _integer(piece.get("y", -1)) == y:
			return index
	return -1


func piece_shape(index: int) -> String:
	return piece_shape_for(piece_at(index))


static func piece_shape_for(piece: Dictionary) -> String:
	if str(piece.get("type", "")) != "wire":
		return "straight"
	var shape := str(piece.get("shape", "straight"))
	return shape if shape in ["straight", "elbow"] else "straight"


func connectors(index: int) -> int:
	var piece := piece_at(index)
	if piece.is_empty():
		return 0
	return connector_mask(str(piece.get("type", "")), _integer(piece.get("rotation", 0)), piece_shape(index))


func solution_connectors(index: int) -> int:
	var piece := piece_at(index)
	if piece.is_empty():
		return 0
	return connector_mask(
		str(piece.get("type", "")),
		_integer(piece.get("solutionRotation", 0)),
		piece_shape(index)
	)


static func connector_mask(kind: String, rotation: int, shape: String = "straight") -> int:
	var turn := posmod(rotation, 4)
	if kind in ["battery", "bulb", "fan", "buzzer"]:
		return 1 << ((1 + turn) % 4)
	if kind == "terminal":
		return 0xF
	var base := (1 << 1) | (1 << 3)
	if kind == "wire" and shape == "elbow":
		base = (1 << 0) | (1 << 1)
	elif kind not in ["wire", "switch", "resistor"]:
		return 0
	return ((base << turn) | (base >> (4 - turn))) & 0xF


static func direction_name(direction: int) -> String:
	return str(DIRECTION_NAMES[posmod(direction, 4)])


func is_powered(index: int) -> bool:
	var piece := piece_at(index)
	return not piece.is_empty() and bool(flow().get("powered", {}).has(_cell_key(int(piece.x), int(piece.y))))


func is_link(x: int, y: int, direction: int) -> bool:
	var edge_key := "%s|%s" % [_cell_key(x, y), direction]
	return bool(flow().get("links", {}).has(edge_key))


func is_flow_link(x: int, y: int, direction: int) -> bool:
	var edge_key := "%s|%s" % [_cell_key(x, y), direction]
	return bool(flow().get("flowLinks", {}).has(edge_key))


func is_switch(index: int) -> bool:
	return str(piece_at(index).get("type", "")) == "switch"


func is_open_switch(index: int) -> bool:
	var piece := piece_at(index)
	return str(piece.get("type", "")) == "switch" and not bool(piece.get("closed", false))


func is_goal_piece(index: int) -> bool:
	return str(piece_at(index).get("type", "")) in GOAL_TYPES


func goal_position(goal_index: int) -> Vector2i:
	var goals: Variant = level_definition.get("goals", [])
	if not goals is Array or goal_index < 0 or goal_index >= goals.size():
		return Vector2i(-1, -1)
	var goal: Dictionary = goals[goal_index]
	return Vector2i(_integer(goal.get("x", -1)), _integer(goal.get("y", -1)))


func goal_is_powered(goal_index: int) -> bool:
	var position := goal_position(goal_index)
	if position.x < 0:
		return false
	return bool(flow().get("powered", {}).has(_cell_key(position.x, position.y)))


func goal_type(goal_index: int) -> String:
	var position := goal_position(goal_index)
	var index := piece_index_at(position.x, position.y)
	return str(piece_at(index).get("type", ""))


func hint_index() -> int:
	return int(state.get("hintIndex", -1))


func fault_index() -> int:
	return int(state.get("faultIndex", -1))


func last_fault() -> String:
	return str(state.get("lastFault", ""))


func current_player_index() -> int:
	if not _is_cooperative():
		return 0
	return clampi(int(state.get("turn", 0)), 0, 1)


func is_cooperative() -> bool:
	return _is_cooperative()


func type_name(index: int) -> String:
	return str(TYPE_NAMES.get(str(piece_at(index).get("type", "")), "元件"))


func _recompute_flow() -> void:
	_flow_dirty = false
	_flow_cache = _build_flow(level_definition, state.get("parts", []))


func _build_flow(level: Dictionary, pieces: Array, include_parents: bool = false) -> Dictionary:
	var result := {
		"powered": {},
		"links": {},
		"flowLinks": {},
		"parents": {},
		"poweredGoalCount": 0,
		"goalCount": 0,
	}
	var goals: Variant = level.get("goals", [])
	if goals is Array:
		result.goalCount = goals.size()
	var level_width := _integer(level.get("width", 0))
	var level_height := _integer(level.get("height", 0))
	if level_width <= 0 or level_height <= 0 or pieces.is_empty():
		return result
	var pieces_by_key := {}
	for piece_value in pieces:
		if not piece_value is Dictionary:
			continue
		var piece: Dictionary = piece_value
		var piece_key := _cell_key(_integer(piece.get("x", -1)), _integer(piece.get("y", -1)))
		pieces_by_key[piece_key] = piece
	var source: Dictionary = level.get("source", {})
	var source_key := _cell_key(_integer(source.get("x", -1)), _integer(source.get("y", -1)))
	var source_piece: Dictionary = pieces_by_key.get(source_key, {})
	if source_piece.is_empty() or str(source_piece.get("type", "")) != "battery":
		return result
	var powered := {source_key: true}
	var queue: Array[String] = [source_key]
	var cursor := 0
	var links := {}
	var flow_links := {}
	var parents := {}
	while cursor < queue.size():
		var current_key := queue[cursor]
		cursor += 1
		var piece: Dictionary = pieces_by_key.get(current_key, {})
		if piece.is_empty():
			continue
		if str(piece.get("type", "")) == "switch" and not bool(piece.get("closed", false)):
			continue
		var mask := connector_mask(
			str(piece.get("type", "")),
			_integer(piece.get("rotation", 0)),
			piece_shape_for(piece)
		)
		for direction in 4:
			if (mask & (1 << direction)) == 0:
				continue
			var delta: Vector2i = DIRECTION_VECTORS[direction]
			var next_x := _integer(piece.get("x", -1)) + delta.x
			var next_y := _integer(piece.get("y", -1)) + delta.y
			if next_x < 0 or next_x >= level_width or next_y < 0 or next_y >= level_height:
				continue
			var next_key := _cell_key(next_x, next_y)
			var neighbor: Dictionary = pieces_by_key.get(next_key, {})
			if neighbor.is_empty():
				continue
			var neighbor_mask := connector_mask(
				str(neighbor.get("type", "")),
				_integer(neighbor.get("rotation", 0)),
				piece_shape_for(neighbor)
			)
			if (neighbor_mask & (1 << OPPOSITE[direction])) == 0:
				continue
			links["%s|%s" % [current_key, direction]] = true
			links["%s|%s" % [next_key, OPPOSITE[direction]]] = true
			if not powered.has(next_key):
				powered[next_key] = true
				queue.append(next_key)
				flow_links["%s|%s" % [current_key, direction]] = true
				if include_parents:
					parents[next_key] = current_key
	var powered_goals := 0
	if goals is Array:
		for goal_value in goals:
			if goal_value is Dictionary and powered.has(_cell_key(_integer(goal_value.get("x", -1)), _integer(goal_value.get("y", -1)))):
				powered_goals += 1
	result.powered = powered
	result.links = links
	result.flowLinks = flow_links
	result.parents = parents
	result.poweredGoalCount = powered_goals
	return result


func _solution_parts() -> Array:
	var result: Array = []
	for piece_value in level_definition.get("parts", []):
		if not piece_value is Dictionary:
			continue
		var piece: Dictionary = piece_value.duplicate(true)
		piece.rotation = int(piece.get("solutionRotation", 0))
		piece.closed = bool(piece.get("solutionClosed", false))
		result.append(piece)
	return result


func _solution_paths() -> Dictionary:
	var parts := _solution_parts()
	var level_width := width()
	var level_height := height()
	var pieces_by_key := {}
	var index_by_key := {}
	for index in parts.size():
		var piece: Dictionary = parts[index]
		var piece_key := _cell_key(int(piece.x), int(piece.y))
		pieces_by_key[piece_key] = piece
		index_by_key[piece_key] = index
	var source := source_position()
	var source_key := _cell_key(source.x, source.y)
	if not pieces_by_key.has(source_key):
		return {}
	var reached := {source_key: true}
	var parents := {}
	var queue: Array[String] = [source_key]
	var cursor := 0
	while cursor < queue.size():
		var current_key := queue[cursor]
		cursor += 1
		var piece: Dictionary = pieces_by_key.get(current_key, {})
		if piece.is_empty():
			continue
		if str(piece.get("type", "")) == "switch" and not bool(piece.get("closed", false)):
			continue
		var mask := connector_mask(
			str(piece.get("type", "")),
			_integer(piece.get("rotation", 0)),
			piece_shape_for(piece)
		)
		for direction in 4:
			if (mask & (1 << direction)) == 0:
				continue
			var delta: Vector2i = DIRECTION_VECTORS[direction]
			var next_x := _integer(piece.get("x", -1)) + delta.x
			var next_y := _integer(piece.get("y", -1)) + delta.y
			if next_x < 0 or next_x >= level_width or next_y < 0 or next_y >= level_height:
				continue
			var next_key := _cell_key(next_x, next_y)
			var neighbor: Dictionary = pieces_by_key.get(next_key, {})
			if neighbor.is_empty():
				continue
			var neighbor_mask := connector_mask(
				str(neighbor.get("type", "")),
				_integer(neighbor.get("rotation", 0)),
				piece_shape_for(neighbor)
			)
			if (neighbor_mask & (1 << OPPOSITE[direction])) == 0:
				continue
			if not reached.has(next_key):
				reached[next_key] = true
				parents[next_key] = current_key
				queue.append(next_key)
	var paths := {}
	for goal_index in goal_count():
		var goal := goal_position(goal_index)
		var goal_key := _cell_key(goal.x, goal.y)
		if not reached.has(goal_key):
			continue
		var chain: Array[String] = []
		var current := goal_key
		var guard := 0
		while current != source_key and parents.has(current) and guard < 128:
			chain.push_front(current)
			current = str(parents[current])
			guard += 1
		if current != source_key:
			continue
		chain.push_front(source_key)
		var indices: Array = []
		for piece_key in chain:
			if index_by_key.has(piece_key):
				indices.append(int(index_by_key[piece_key]))
		paths[goal_index] = indices
	return paths


func _analyse_fault() -> void:
	state.faultIndex = -1
	state.lastFault = ""
	if goals_completed():
		return
	var paths := _solution_paths()
	var current_flow := flow()
	var powered: Dictionary = current_flow.get("powered", {})
	for goal_index in goal_count():
		if goal_is_powered(goal_index):
			continue
		var path: Array = paths.get(goal_index, [])
		if path.is_empty():
			_fallback_fault(goal_index)
			return
		var first_unpowered_position := -1
		var first_unpowered_index := -1
		for path_position in path.size():
			var piece_index := int(path[path_position])
			var piece := piece_at(piece_index)
			if not piece.is_empty() and bool(powered.has(_cell_key(int(piece.x), int(piece.y)))):
				if str(piece.get("type", "")) == "switch" and not bool(piece.get("closed", false)):
					_report_fault(piece_index, goal_index)
					return
				continue
			first_unpowered_position = path_position
			first_unpowered_index = piece_index
			break
		if first_unpowered_index < 0:
			_fallback_fault(goal_index)
			return
		if first_unpowered_position > 0:
			var previous_index := int(path[first_unpowered_position - 1])
			var previous := piece_at(previous_index)
			if str(previous.get("type", "")) == "switch" and not bool(previous.get("closed", false)):
				_report_fault(previous_index, goal_index)
				return
			if str(previous.get("type", "")) == "wire" and not bool(previous.get("locked", false)) and int(previous.get("rotation", 0)) != int(previous.get("solutionRotation", 0)):
				_report_fault(previous_index, goal_index)
				return
		_report_fault(first_unpowered_index, goal_index)
		return


func _report_fault(index: int, goal_index: int) -> void:
	var piece := piece_at(index)
	if piece.is_empty():
		_fallback_fault(goal_index)
		return
	state.faultIndex = index
	var target_name := str(TYPE_NAMES.get(goal_type(goal_index), "小电器"))
	var piece_type := str(piece.get("type", ""))
	var location := "第 %s 行第 %s 列" % [int(piece.get("y", 0)) + 1, int(piece.get("x", 0)) + 1]
	if piece_type == "switch":
		if not bool(piece.get("closed", false)):
			state.lastFault = "%s还没工作：%s的开关还开着，点一下合上它。" % [target_name, location]
		else:
			state.lastFault = "%s还没工作：%s的开关附近还有一段没接通。" % [target_name, location]
	elif piece_type == "wire":
		state.lastFault = "%s还没工作：%s的导线方向没对上，点一下转动它。" % [target_name, location]
	elif piece_type in GOAL_TYPES:
		state.lastFault = "%s还没工作：%s的接头没有和发光导线对齐。" % [target_name, location]
	elif piece_type == "terminal":
		state.lastFault = "%s还没工作：%s的接线端子前面有一段断开。" % [target_name, location]
	elif piece_type == "resistor":
		state.lastFault = "%s还没工作：%s的电阻接头前面有一段断开。" % [target_name, location]
	else:
		state.lastFault = "%s还没工作：从%s往目标的一段线路断开了。" % [target_name, location]


func _fallback_fault(goal_index: int) -> void:
	var goal := goal_position(goal_index)
	var best_index := -1
	var best_distance := 100000
	for index in piece_count():
		var piece := piece_at(index)
		if bool(piece.get("locked", false)):
			continue
		if str(piece.get("type", "")) not in ["wire", "switch"]:
			continue
		if is_powered(index):
			continue
		var distance := absi(int(piece.x) - goal.x) + absi(int(piece.y) - goal.y)
		if distance < best_distance:
			best_distance = distance
			best_index = index
	if best_index >= 0:
		_report_fault(best_index, goal_index)
		return
	state.faultIndex = -1
	state.lastFault = "%s还没亮：先检查从电池出来的第一段导线和开关。" % str(TYPE_NAMES.get(goal_type(goal_index), "小电器"))


func _par_actions(pieces: Array, initial_rotations: Array, initial_closed: Array) -> int:
	var result := 0
	for index in pieces.size():
		var piece: Dictionary = pieces[index]
		if bool(piece.get("locked", false)) or index >= initial_rotations.size() or index >= initial_closed.size():
			continue
		if str(piece.get("type", "")) == "wire":
			var from_rotation := int(initial_rotations[index])
			var to_rotation := int(piece.get("solutionRotation", from_rotation))
			result += posmod(to_rotation - from_rotation, 4)
		elif str(piece.get("type", "")) == "switch" and bool(initial_closed[index]) != bool(piece.get("solutionClosed", false)):
			result += 1
	return result


func _restore_parts(expected: Dictionary) -> bool:
	var saved_value: Variant = state.get("parts", null)
	if not saved_value is Array or saved_value.is_empty():
		return false
	var saved: Array = saved_value
	var expected_parts: Array = expected.get("parts", [])
	if saved.size() != expected_parts.size():
		return false
	var saved_by_key := {}
	for entry in saved:
		if not entry is Dictionary:
			return false
		var entry_x := _integer(entry.get("x", -1))
		var entry_y := _integer(entry.get("y", -1))
		var entry_key := _cell_key(entry_x, entry_y)
		if saved_by_key.has(entry_key):
			return false
		saved_by_key[entry_key] = entry
	var restored: Array = []
	for expected_value in expected_parts:
		var expected_piece: Dictionary = expected_value
		var expected_key := _cell_key(_integer(expected_piece.get("x", -1)), _integer(expected_piece.get("y", -1)))
		if not saved_by_key.has(expected_key):
			return false
		var entry: Dictionary = saved_by_key[expected_key]
		var piece_type := str(entry.get("type", ""))
		if piece_type != str(expected_piece.get("type", "")):
			return false
		if piece_shape_for(entry) != piece_shape_for(expected_piece):
			return false
		if int(entry.get("solutionRotation", -1)) != int(expected_piece.get("solutionRotation", -2)):
			return false
		if typeof(entry.get("closed", null)) != TYPE_BOOL or typeof(entry.get("solutionClosed", null)) != TYPE_BOOL:
			return false
		if bool(entry.get("solutionClosed", false)) != bool(expected_piece.get("solutionClosed", false)):
			return false
		if typeof(entry.get("locked", null)) != TYPE_BOOL:
			return false
		if bool(entry.get("locked", false)) != bool(expected_piece.get("locked", false)):
			return false
		var rotation := _integer(entry.get("rotation", -1))
		if rotation < 0 or rotation > 3:
			return false
		if bool(entry.get("locked", false)):
			if rotation != int(entry.get("solutionRotation", 0)):
				return false
			if bool(entry.get("closed", false)) != bool(entry.get("solutionClosed", false)):
				return false
		var clean := {
			"x": _integer(expected_piece.get("x", 0)),
			"y": _integer(expected_piece.get("y", 0)),
			"type": piece_type,
			"rotation": rotation,
			"closed": bool(entry.get("closed", false)),
			"locked": bool(entry.get("locked", false)),
			"solutionRotation": int(entry.get("solutionRotation", 0)),
			"solutionClosed": bool(entry.get("solutionClosed", false)),
		}
		if piece_type == "wire":
			clean.shape = piece_shape_for(entry)
		restored.append(clean)
	state.parts = restored
	return restored.size() == expected_parts.size()


func _normalize_level(raw_value: Variant, requested_level: int) -> Dictionary:
	if not raw_value is Dictionary:
		return {}
	var raw: Dictionary = raw_value
	var expected_mode := str(raw.get("mode", "classic" if requested_level > SINGLE_LEVEL_COUNT else "adventure"))
	if not expected_mode in ["adventure", "classic"]:
		return {}
	var level_width := _integer(raw.get("width", 0))
	var level_height := _integer(raw.get("height", 0))
	if level_width < 4 or level_width > 9 or level_height < 3 or level_height > 7:
		return {}
	var source_value := _normalize_point(raw.get("source"), level_width, level_height)
	if source_value.is_empty():
		return {}
	var goal_values: Variant = raw.get("goals", [])
	if not goal_values is Array or goal_values.is_empty():
		return {}
	var goals: Array = []
	var goal_keys := {}
	for goal_value in goal_values:
		var goal := _normalize_point(goal_value, level_width, level_height)
		if goal.is_empty():
			return {}
		var goal_key := _cell_key(goal.x, goal.y)
		if goal_keys.has(goal_key):
			return {}
		goal_keys[goal_key] = true
		goals.append(goal)
	var raw_parts: Variant = raw.get("parts", [])
	if not raw_parts is Array or raw_parts.size() < 3:
		return {}
	var parts: Array = []
	var piece_keys := {}
	for raw_part in raw_parts:
		if not raw_part is Dictionary:
			return {}
		var part: Dictionary = raw_part
		var piece_type := str(part.get("type", ""))
		if piece_type not in VALID_TYPES:
			return {}
		var x := _integer(part.get("x", -1))
		var y := _integer(part.get("y", -1))
		if x < 0 or x >= level_width or y < 0 or y >= level_height:
			return {}
		var piece_key := _cell_key(x, y)
		if piece_keys.has(piece_key):
			return {}
		var rotation := _integer(part.get("rotation", -1))
		var solution_rotation := _integer(part.get("solutionRotation", -1))
		if rotation < 0 or rotation > 3 or solution_rotation < 0 or solution_rotation > 3:
			return {}
		if typeof(part.get("closed", null)) != TYPE_BOOL or typeof(part.get("solutionClosed", null)) != TYPE_BOOL:
			return {}
		if typeof(part.get("locked", null)) != TYPE_BOOL:
			return {}
		var shape := "straight"
		if piece_type == "wire":
			shape = str(part.get("shape", "straight"))
			if shape not in ["straight", "elbow"]:
				return {}
		var locked := bool(part.locked)
		if piece_type == "switch" and locked:
			return {}
		if locked:
			if connector_mask(piece_type, rotation, shape) != connector_mask(piece_type, solution_rotation, shape):
				return {}
			if bool(part.closed) != bool(part.solutionClosed):
				return {}
		var normalized_piece := {
			"x": x,
			"y": y,
			"type": piece_type,
			"rotation": rotation,
			"closed": bool(part.closed),
			"locked": locked,
			"solutionRotation": solution_rotation,
			"solutionClosed": bool(part.solutionClosed),
		}
		if piece_type == "wire":
			normalized_piece.shape = shape
		piece_keys[piece_key] = true
		parts.append(normalized_piece)
	var source_piece_index := _piece_index_at(parts, _cell_key(source_value.x, source_value.y))
	if source_piece_index < 0 or str(parts[source_piece_index].get("type", "")) != "battery":
		return {}
	var battery_count := 0
	for part in parts:
		if str(part.get("type", "")) == "battery":
			battery_count += 1
	if battery_count != 1:
		return {}
	for goal in goals:
		var goal_piece_index := _piece_index_at(parts, _cell_key(goal.x, goal.y))
		if goal_piece_index < 0 or str(parts[goal_piece_index].get("type", "")) not in GOAL_TYPES:
			return {}
	var raw_fixed: Variant = raw.get("fixed", [])
	if not raw_fixed is Array:
		return {}
	var fixed: Array = []
	var fixed_keys := {}
	for fixed_value in raw_fixed:
		var fixed_point := _normalize_point(fixed_value, level_width, level_height)
		if fixed_point.is_empty():
			return {}
		var fixed_key := _cell_key(fixed_point.x, fixed_point.y)
		if fixed_keys.has(fixed_key):
			return {}
		fixed_keys[fixed_key] = true
		fixed.append(fixed_point)
	for piece in parts:
		var is_fixed := fixed_keys.has(_cell_key(int(piece.x), int(piece.y)))
		if bool(piece.get("locked", false)) != is_fixed:
			return {}
	var raw_solution: Variant = raw.get("solution", [])
	if not raw_solution is Array or raw_solution.is_empty():
		return {}
	var solved_rotations: Array = []
	var solved_closed: Array = []
	for piece in parts:
		solved_rotations.append(int(piece.rotation))
		solved_closed.append(bool(piece.closed))
	for step_value in raw_solution:
		if not step_value is Dictionary:
			return {}
		var step: Dictionary = step_value
		var index := _integer(step.get("index", -1))
		if index < 0 or index >= parts.size():
			return {}
		if bool(parts[index].get("locked", false)):
			return {}
		var has_rotation := step.has("rotation")
		var has_closed := step.has("closed")
		if not has_rotation and not has_closed:
			return {}
		if has_rotation:
			var target_rotation := _integer(step.get("rotation", -1))
			if target_rotation < 0 or target_rotation > 3 or str(parts[index].get("type", "")) != "wire":
				return {}
			solved_rotations[index] = target_rotation
		if has_closed:
			if typeof(step.get("closed", null)) != TYPE_BOOL or str(parts[index].get("type", "")) != "switch":
				return {}
			solved_closed[index] = bool(step.closed)
	var solution_parts: Array = []
	for index in parts.size():
		var piece: Dictionary = parts[index].duplicate(true)
		if int(solved_rotations[index]) != int(piece.get("solutionRotation", 0)):
			return {}
		if bool(solved_closed[index]) != bool(piece.get("solutionClosed", false)):
			return {}
		piece.rotation = int(solved_rotations[index])
		piece.closed = bool(solved_closed[index])
		solution_parts.append(piece)
	var title := str(raw.get("title", "")).strip_edges()
	var identifier := str(raw.get("id", "")).strip_edges()
	var band := str(raw.get("band", "normal"))
	var min_age := _integer(raw.get("minAge", 0))
	if title.is_empty() or identifier.is_empty() or band not in ["easy", "normal", "challenge"]:
		return {}
	if min_age < 4 or min_age > 12:
		return {}
	for field in ["hint", "narration", "explanation"]:
		if str(raw.get(field, "")).strip_edges().is_empty():
			return {}
	var normalized := {
		"id": identifier,
		"mode": expected_mode,
		"band": band,
		"minAge": min_age,
		"title": title,
		"width": level_width,
		"height": level_height,
		"source": source_value,
		"fixed": fixed,
		"parts": parts,
		"goals": goals,
		"hint": str(raw.get("hint", "")),
		"solution": raw_solution.duplicate(true),
		"narration": str(raw.get("narration", "")),
		"explanation": str(raw.get("explanation", "")),
		"levelNumber": requested_level,
	}
	var initial_flow := _build_flow(normalized, parts)
	if int(initial_flow.get("poweredGoalCount", 0)) >= goals.size():
		return {}
	var solved_flow := _build_flow(normalized, solution_parts)
	if int(solved_flow.get("poweredGoalCount", 0)) < goals.size():
		return {}
	return normalized


func _clear_invalid_hint() -> void:
	var index := int(state.get("hintIndex", -1))
	if index < 0 or index >= piece_count():
		_clear_hint()
		return
	var piece := piece_at(index)
	var wrong := false
	if str(piece.get("type", "")) == "wire" and int(piece.get("rotation", 0)) != int(piece.get("solutionRotation", 0)):
		wrong = true
	elif str(piece.get("type", "")) == "switch" and bool(piece.get("closed", false)) != bool(piece.get("solutionClosed", false)):
		wrong = true
	if not wrong:
		_clear_hint()


func _clear_hint() -> void:
	state.hintIndex = -1
	state.hintMessage = ""


func _is_cooperative() -> bool:
	var players_value: Variant = state.get("players", [])
	return str(state.get("modeId", "adventure")) == "classic" and players_value is Array and players_value.size() >= 2


func _piece_index_at(parts: Array, cell_key: String) -> int:
	for index in parts.size():
		var piece: Dictionary = parts[index]
		if _cell_key(_integer(piece.get("x", -1)), _integer(piece.get("y", -1))) == cell_key:
			return index
	return -1


func _normalize_point(value: Variant, level_width: int, level_height: int) -> Dictionary:
	if not value is Dictionary:
		return {}
	var x := _integer(value.get("x", -1))
	var y := _integer(value.get("y", -1))
	if x < 0 or x >= level_width or y < 0 or y >= level_height:
		return {}
	return {"x": x, "y": y}


func _cell_key(x: int, y: int) -> String:
	return "%s,%s" % [x, y]


static func _integer(value: Variant, fallback: int = 0) -> int:
	if value is int:
		return int(value)
	if value is float and is_finite(float(value)) and is_equal_approx(float(value), roundf(float(value))):
		return int(value)
	return fallback
