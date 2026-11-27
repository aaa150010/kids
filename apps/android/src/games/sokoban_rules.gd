class_name SokobanRules
extends GameSession

const VERSION := 1
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
const MAX_HISTORY := 160
const INVALID_INT := -2147483648
const DEADLOCK_MESSAGE := "箱子卡住了，先撤回。"

var level_definition: Dictionary = {}


func create_session(context: Dictionary) -> Dictionary:
	super.create_session(context)
	var requested_level := maxi(1, _integer(context.get("levelId", 1)))
	var raw_level: Variant = context.get("level", {})
	var level: Dictionary = raw_level.duplicate(true) if raw_level is Dictionary else {}
	level.levelNumber = requested_level if raw_level is Dictionary else 0
	var validation := validate_level(level)
	var mode_id := str(context.get("modeId", "classic"))
	if mode_id not in ["classic", "adventure"]:
		var mode_players: Variant = context.get("players", [])
		mode_id = "adventure" if mode_players is Array and mode_players.size() <= 1 else "classic"
	if bool(level.get("coop", false)) != (mode_id == "classic"):
		validation = {"ok": false, "message": "这一关的仓库类型和当前游戏模式不一致"}
	var players_value: Variant = context.get("players", [])
	if mode_id == "classic" and (not players_value is Array or players_value.size() < 2):
		validation = {"ok": false, "message": "双人仓库需要两位小朋友"}
	if mode_id == "adventure" and players_value is Array and players_value.size() > 1:
		validation = {"ok": false, "message": "单人仓库只能选择一位小朋友"}
	level_definition = level.duplicate(true)
	if not bool(validation.get("ok", false)):
		state.merge({
			"sokobanVersion": VERSION,
			"modeId": mode_id,
			"levelId": requested_level,
			"level": level,
			"view": "map",
			"player": {},
			"boxes": [],
			"phase": "empty",
			"loadError": str(validation.get("message", "这一关的仓库还没有准备好")),
			"reason": str(validation.get("message", "这一关的仓库还没有准备好")),
			"reported": false,
		}, true)
		return state
	var initial_player := _cell(level.get("player", {}))
	var initial_boxes := _boxes_from(level.get("boxes", []))
	var initial_box_maps := _box_dicts(initial_boxes)
	var is_coop_session: bool = (
		mode_id == "classic"
		and bool(level.get("coop", false))
		and players_value is Array
		and players_value.size() >= 2
	)
	var turn_order: Array = level.get("turnOrder", [0])
	var first_turn := int(turn_order[0]) if is_coop_session and not turn_order.is_empty() else 0
	state.merge({
		"sokobanVersion": VERSION,
		"modeId": mode_id,
		"levelId": requested_level,
		"levelNumber": requested_level,
		"level": level.duplicate(true),
		"levelKey": str(level.get("id", "")),
		"levelTitle": str(level.get("title", "仓库推推乐")),
		"view": "board",
		"player": _cell_dictionary(initial_player),
		"boxes": initial_box_maps,
		"initialPlayer": _cell_dictionary(initial_player),
		"initialBoxes": initial_box_maps.duplicate(true),
		"moves": 0,
		"pushes": 0,
		"undos": 0,
		"hints": 0,
		"restarts": 0,
		"turn": first_turn,
		"history": [],
		"lastMove": "",
		"lastPushed": false,
		"hintDirection": "",
		"hintText": "",
		"deadlockBox": {},
		"deadlockMessage": "",
		"stuckBoxes": [],
		"phase": "playing",
		"winner": -1,
		"reason": "",
		"stars": 0,
		"reported": false,
	}, true)
	return state


func handle_input(action: Dictionary) -> Dictionary:
	match str(action.get("type", "")):
		"move":
			return move(str(action.get("direction", "")))
		"undo":
			return undo()
		"hint":
			return hint()
		"restart":
			return restart()
	return {"ok": false, "message": "这个操作现在不能用"}


func move(direction: String) -> Dictionary:
	if str(state.get("phase", "")) == "empty":
		return {"ok": false, "message": str(state.get("loadError", "这一关的仓库还没有准备好"))}
	if str(state.get("phase", "")) == "finished":
		return {"ok": false, "message": "所有木箱都已经归位啦"}
	if not DIRECTIONS.has(direction):
		return {"ok": false, "message": "请选择一个方向"}
	var player := _cell(state.get("player", {}))
	var boxes: Array = _boxes_from(state.get("boxes", []))
	var vector := _direction(direction)
	var target := player + vector
	if _is_wall(target):
		return {"ok": false, "blocked": true, "message": "前面是仓库墙，换个方向试试"}
	var box_index := _box_index_at(boxes, target)
	var pushed := box_index >= 0
	if pushed:
		var beyond := target + vector
		if _is_wall(beyond) or _box_index_at(boxes, beyond) >= 0:
			return {"ok": false, "blocked": true, "message": "木箱后面没有空位，先换一条路"}
		_push_history()
		boxes[box_index] = beyond
		state.moves = int(state.get("moves", 0)) + 1
		state.pushes = int(state.get("pushes", 0)) + 1
	else:
		_push_history()
		state.moves = int(state.get("moves", 0)) + 1
	state.player = _cell_dictionary(target)
	state.boxes = _box_dicts(boxes)
	state.lastMove = direction
	state.lastPushed = pushed
	state.hintDirection = ""
	state.deadlockMessage = ""
	_advance_turn()
	var stuck := _stuck_cell_keys(boxes)
	var newly_stuck: Array = stuck.filter(func(value): return not (value in state.get("stuckBoxes", [])))
	state.stuckBoxes = stuck
	state.deadlockBox = {}
	if not newly_stuck.is_empty():
		var stuck_cell := _cell_from_key(str(newly_stuck[0]))
		state.deadlockBox = _cell_dictionary(stuck_cell)
		state.deadlockMessage = DEADLOCK_MESSAGE
	if boxes_complete(boxes):
		state.phase = "finished"
		state.winner = -1 if str(state.get("modeId", "classic")) == "classic" else 0
		state.reason = "所有木箱都送到小圆点啦。"
		state.stars = stars()
		state.deadlockBox = {}
		state.deadlockMessage = ""
		return {
			"ok": true,
			"event": "finished",
			"direction": direction,
			"pushed": pushed,
			"player": state.player,
			"boxes": state.boxes,
			"moves": int(state.moves),
			"pushes": int(state.pushes),
			"stars": int(state.stars),
			"turn": int(state.get("turn", 0)),
		}
	var result := {
		"ok": true,
		"event": "pushed" if pushed else "moved",
		"direction": direction,
		"pushed": pushed,
		"player": state.player,
		"boxes": state.boxes,
		"moves": int(state.moves),
		"pushes": int(state.pushes),
		"turn": int(state.get("turn", 0)),
		"deadlocked": not bool(state.deadlockBox.is_empty()),
	}
	if not state.deadlockBox.is_empty():
		result.deadlockBox = state.deadlockBox
		result.deadlockMessage = str(state.deadlockMessage)
	return result


func undo() -> Dictionary:
	if str(state.get("phase", "")) == "finished":
		return {"ok": false, "message": "这一关已经完成啦"}
	if str(state.get("phase", "")) != "playing":
		return {"ok": false, "message": "现在没有可以撤回的一步"}
	var history: Array = state.get("history", [])
	if history.is_empty():
		return {"ok": false, "message": "已经回到仓库开头啦"}
	var previous_value: Variant = history.pop_back()
	if not previous_value is Dictionary:
		return {"ok": false, "message": "这步记录不完整，先重新开始这一关"}
	var previous: Dictionary = previous_value
	state.history = history
	state.player = previous.get("player", {}).duplicate(true)
	state.boxes = previous.get("boxes", []).duplicate(true)
	state.turn = int(previous.get("turn", 0))
	state.moves = int(previous.get("moves", 0))
	state.pushes = int(previous.get("pushes", 0))
	state.undos = int(state.get("undos", 0)) + 1
	state.lastMove = ""
	state.lastPushed = false
	state.hintDirection = ""
	state.hintText = ""
	state.deadlockBox = {}
	state.deadlockMessage = ""
	state.stuckBoxes = _stuck_cell_keys(state.get("boxes", []))
	state.phase = "playing"
	state.reason = ""
	state.winner = -1
	state.stars = 0
	return {
		"ok": true,
		"event": "undone",
		"player": state.player,
		"boxes": state.boxes,
		"moves": int(state.moves),
		"pushes": int(state.pushes),
		"undos": int(state.undos),
		"turn": int(state.turn),
	}


func undo_preview() -> Dictionary:
	var history: Array = state.get("history", [])
	if history.is_empty() or str(state.get("phase", "")) != "playing":
		return {"available": false}
	var previous_value: Variant = history.back()
	if not previous_value is Dictionary:
		return {"available": false}
	var previous: Dictionary = previous_value
	return {
		"available": true,
		"player": previous.get("player", {}).duplicate(true),
		"boxes": previous.get("boxes", []).duplicate(true),
		"turn": int(previous.get("turn", 0)),
	}


func can_undo() -> bool:
	return str(state.get("phase", "")) == "playing" and not (state.get("history", []) as Array).is_empty()


func hint() -> Dictionary:
	if str(state.get("phase", "")) == "finished":
		return {"ok": false, "message": "所有木箱都归位啦，不用提示"}
	if str(state.get("phase", "")) != "playing":
		return {"ok": false, "message": "这一关还没有准备好"}
	state.hints = int(state.get("hints", 0)) + 1
	var next_direction := _next_solution_direction()
	var level_hint := str(level_definition.get("hint", "先走到箱子背后，再看箱子前面有没有空位。"))
	var message := ""
	if next_direction.is_empty():
		state.hintDirection = ""
		state.hintText = level_hint
		message = "这一步离开了作者路线。先点撤销回到上一格，再照着提示试；箱子卡住时也一样。"
	else:
		state.hintDirection = next_direction
		state.hintText = "下一格向%s走。%s" % [str(DIRECTION_NAMES.get(next_direction, "")), level_hint]
		message = str(state.hintText)
	return {
		"ok": true,
		"event": "hint",
		"direction": str(state.hintDirection),
		"directionName": str(DIRECTION_NAMES.get(str(state.hintDirection), "")),
		"message": message,
		"levelHint": level_hint,
		"hints": int(state.hints),
	}


func restart() -> Dictionary:
	if str(state.get("phase", "")) == "empty":
		return {"ok": false, "message": "这一关还没有准备好"}
	var restarts := int(state.get("restarts", 0)) + 1
	state.player = state.get("initialPlayer", {}).duplicate(true)
	state.boxes = state.get("initialBoxes", []).duplicate(true)
	state.moves = 0
	state.pushes = 0
	state.undos = 0
	state.hints = 0
	state.restarts = restarts
	state.turn = int(_turn_order()[0]) if is_cooperative() else 0
	state.history = []
	state.lastMove = ""
	state.lastPushed = false
	state.hintDirection = ""
	state.hintText = ""
	state.deadlockBox = {}
	state.deadlockMessage = ""
	state.stuckBoxes = _stuck_cell_keys(state.get("boxes", []))
	state.phase = "playing"
	state.winner = -1
	state.reason = ""
	state.stars = 0
	state.reported = false
	return {"ok": true, "event": "restarted", "moves": 0, "restarts": restarts}


func stars() -> int:
	if str(state.get("phase", "")) != "finished":
		return 0
	var moves := int(state.get("moves", 0))
	var par := int(level_definition.get("parMoves", moves))
	var hints := int(state.get("hints", 0))
	var undos := int(state.get("undos", 0))
	if moves <= par and hints == 0 and undos == 0:
		return 3
	if moves <= par + 4 and hints <= 1 and undos <= 3:
		return 2
	return 1


func result() -> Dictionary:
	if str(state.get("phase", "")) != "finished":
		return {}
	return {
		"winner": int(state.get("winner", -1)),
		"reason": str(state.get("reason", "所有木箱都归位啦")),
		"phase": "finished",
		"outcome": "played" if str(state.get("modeId", "classic")) == "classic" else "win",
		"stars": int(state.get("stars", stars())),
		"moves": int(state.get("moves", 0)),
		"parMoves": int(level_definition.get("parMoves", 0)),
		"pushes": int(state.get("pushes", 0)),
		"hints": int(state.get("hints", 0)),
		"undos": int(state.get("undos", 0)),
		"goals": goal_count(),
		"boxes": boxes_on_goals(),
		"levelId": int(state.get("levelId", 1)),
		"levelKey": str(level_definition.get("id", "")),
	}


func tick(_delta: float) -> bool:
	return false


func snapshot() -> Dictionary:
	state.sokobanVersion = VERSION
	if str(state.get("phase", "")) == "finished":
		state.stars = stars()
	return super.snapshot()


func restore(value: Dictionary) -> bool:
	if not _strict_int_is(value.get("sokobanVersion", null), VERSION):
		return false
	if not super.restore(value):
		return false
	var raw_level: Variant = state.get("level", {})
	if not raw_level is Dictionary:
		return false
	var level_id_value := _strict_int(state.get("levelId", null))
	if level_id_value < 1:
		return false
	var level_number_value := _strict_int(raw_level.get("levelNumber", null))
	if level_number_value != level_id_value:
		return false
	if str(raw_level.get("id", "")) != str(state.get("levelKey", "")):
		return false
	var validation := validate_level(raw_level)
	if not bool(validation.get("ok", false)):
		return false
	level_definition = raw_level.duplicate(true)
	var mode_id := str(state.get("modeId", "classic"))
	if mode_id not in ["classic", "adventure"]:
		return false
	if bool(raw_level.get("coop", false)) != (mode_id == "classic"):
		return false
	var players_value: Variant = state.get("players", [])
	if mode_id == "classic" and (not players_value is Array or players_value.size() < 2):
		return false
	var phase := str(state.get("phase", ""))
	if phase not in ["playing", "finished", "empty"]:
		return false
	if phase == "empty":
		return true
	var player_value: Variant = state.get("player", {})
	var boxes_value: Variant = state.get("boxes", [])
	var initial_player_value: Variant = state.get("initialPlayer", {})
	var initial_boxes_value: Variant = state.get("initialBoxes", [])
	if not player_value is Dictionary or not boxes_value is Array:
		return false
	if not initial_player_value is Dictionary or not initial_boxes_value is Array:
		return false
	if boxes_value.size() != goal_count() or initial_boxes_value.size() != goal_count():
		return false
	var player := _cell(player_value)
	var initial_player := _cell(initial_player_value)
	var initial_boxes := _boxes_from(initial_boxes_value)
	if not _valid_state_geometry(initial_player, initial_boxes):
		return false
	if initial_boxes != _normalized_boxes(initial_boxes_value):
		return false
	var boxes := _boxes_from(boxes_value)
	if not _valid_state_geometry(player, boxes):
		return false
	if boxes.size() != initial_boxes.size():
		return false
	for key in ["moves", "pushes", "undos", "hints", "restarts"]:
		var value_int := _strict_int(state.get(key, null))
		if value_int < 0:
			return false
		state[key] = value_int
	if int(state.pushes) > int(state.moves):
		return false
	var turn := _strict_int(state.get("turn", null))
	var expected_turn_max := 1 if is_cooperative() else 0
	if turn < 0 or turn > expected_turn_max:
		return false
	if is_cooperative() and not (turn in _turn_order()):
		return false
	state.turn = turn
	var history_value: Variant = state.get("history", [])
	if not history_value is Array:
		return false
	var history: Array = history_value
	if history.size() > MAX_HISTORY or history.size() > int(state.moves):
		return false
	for raw_entry in history:
		if not raw_entry is Dictionary:
			return false
		var entry: Dictionary = raw_entry
		var entry_boxes_value: Variant = entry.get("boxes", [])
		var entry_player_value: Variant = entry.get("player", {})
		if not entry_boxes_value is Array or not entry_player_value is Dictionary:
			return false
		if entry_boxes_value.size() != goal_count():
			return false
		var entry_boxes := _boxes_from(entry_boxes_value)
		var entry_player := _cell(entry_player_value)
		if not _valid_state_geometry(entry_player, entry_boxes):
			return false
		if entry_boxes.size() != boxes.size():
			return false
		var entry_turn := _strict_int(entry.get("turn", null))
		var entry_moves := _strict_int(entry.get("moves", null))
		var entry_pushes := _strict_int(entry.get("pushes", null))
		if entry_turn < 0 or entry_turn > expected_turn_max:
			return false
		if entry_moves < 0 or entry_moves > int(state.moves):
			return false
		if entry_pushes < 0 or entry_pushes > entry_moves:
			return false
		entry.turn = entry_turn
		entry.moves = entry_moves
		entry.pushes = entry_pushes
		entry.player = _cell_dictionary(entry_player)
		entry.boxes = _box_dicts(entry_boxes)
		if not entry.get("lastMove", "") is String:
			return false
	state.history = history
	state.boxes = _box_dicts(boxes)
	state.player = _cell_dictionary(player)
	state.initialPlayer = _cell_dictionary(initial_player)
	state.initialBoxes = _box_dicts(initial_boxes)
	var last_move := str(state.get("lastMove", ""))
	if not last_move.is_empty() and not DIRECTIONS.has(last_move):
		return false
	var hint_direction := str(state.get("hintDirection", ""))
	if not hint_direction.is_empty() and not DIRECTIONS.has(hint_direction):
		return false
	if not state.get("hintText", "") is String:
		return false
	if not state.get("lastPushed", false) is bool:
		return false
	var deadlock_value: Variant = state.get("deadlockBox", {})
	if not deadlock_value is Dictionary:
		return false
	if not deadlock_value.is_empty() and not _inside(_cell(deadlock_value), width(), height()):
		return false
	state.deadlockBox = _cell_dictionary(_cell(deadlock_value)) if not deadlock_value.is_empty() else {}
	state.deadlockMessage = DEADLOCK_MESSAGE if not deadlock_value.is_empty() else ""
	var stuck_value: Variant = state.get("stuckBoxes", [])
	if not stuck_value is Array:
		return false
	for stuck_key in stuck_value:
		if not stuck_key is String:
			return false
		var stuck_cell := _cell_from_key(str(stuck_key))
		if not _inside(stuck_cell, width(), height()):
			return false
	state.stuckBoxes = stuck_value.duplicate()
	var complete := boxes_complete(boxes)
	if phase == "finished":
		if not complete:
			return false
		state.stars = stars()
		state.winner = -1 if str(state.get("modeId", "classic")) == "classic" else 0
		state.reason = "所有木箱都送到小圆点啦。"
	else:
		if complete:
			return false
		state.stars = 0
		state.winner = -1
		state.reason = ""
	if not state.get("reported", false) is bool:
		return false
	return true


func width() -> int:
	return int(level_definition.get("width", 0))


func height() -> int:
	return int(level_definition.get("height", 0))


func level_title() -> String:
	return str(level_definition.get("title", "仓库推推乐"))


func level_band() -> String:
	return str(level_definition.get("band", "easy"))


func goal_count() -> int:
	var goals_value: Variant = level_definition.get("goals", [])
	return goals_value.size() if goals_value is Array else 0


func boxes_on_goals() -> int:
	var goals := _goals_set(level_definition.get("goals", []))
	var count := 0
	for box in _boxes_from(state.get("boxes", [])):
		if goals.has(_cell_key(box)):
			count += 1
	return count


func current_player_index() -> int:
	var players_value: Variant = state.get("players", [])
	var player_count: int = players_value.size() if players_value is Array else 1
	if not is_cooperative() or player_count <= 0:
		return 0
	return clampi(int(state.get("turn", 0)), 0, player_count - 1)


func is_cooperative() -> bool:
	var players_value: Variant = state.get("players", [])
	return (
		str(state.get("modeId", "classic")) == "classic"
		and bool(level_definition.get("coop", false))
		and players_value is Array
		and players_value.size() >= 2
	)


static func validate_catalog(content: Variant) -> Dictionary:
	var issues: Array[String] = []
	var valid_levels: Array = []
	if not content is Dictionary:
		return {"ok": false, "issues": ["sokoban.json 顶层必须是对象"], "levels": []}
	var data: Dictionary = content
	if _strict_int(data.get("version", null)) != VERSION:
		issues.append("sokoban.json 的 version 必须是 %s" % VERSION)
	var levels_value: Variant = data.get("levels", null)
	if not levels_value is Array:
		return {"ok": false, "issues": issues + ["sokoban.json 缺少 levels 数组"], "levels": []}
	var solo_count := 0
	var coop_count := 0
	var band_solo := {"easy": 0, "normal": 0, "challenge": 0}
	var ids := {}
	for raw in levels_value:
		var validation := validate_level(raw)
		if not bool(validation.get("ok", false)):
			issues.append(str(validation.get("message", "有一关内容不完整")))
			continue
		var level: Dictionary = raw
		var level_id := str(level.get("id", ""))
		if ids.has(level_id):
			issues.append("关卡 ID 重复：%s" % level_id)
			continue
		ids[level_id] = true
		valid_levels.append(level.duplicate(true))
		var band := str(level.get("band", ""))
		if bool(level.get("coop", false)):
			coop_count += 1
		else:
			solo_count += 1
			if band_solo.has(band):
				band_solo[band] = int(band_solo[band]) + 1
	if int(levels_value.size()) != 48:
		issues.append("关卡总数应为 48，现在是 %s" % int(levels_value.size()))
	if solo_count != 36:
		issues.append("单人关卡应为 36，经过校验的是 %s" % solo_count)
	if coop_count != 12:
		issues.append("协作关卡应为 12，经过校验的是 %s" % coop_count)
	for band in BANDS:
		if int(band_solo.get(band, 0)) != 12:
			issues.append("%s 单人关卡应为 12，经过校验的是 %s" % [band, int(band_solo.get(band, 0))])
	return {"ok": issues.is_empty(), "issues": issues, "levels": valid_levels}


static func validate_level(raw: Variant) -> Dictionary:
	if not raw is Dictionary:
		return _invalid("关卡必须是对象")
	var level: Dictionary = raw
	var level_id := str(level.get("id", "")).strip_edges()
	if level_id.is_empty():
		return _invalid("关卡缺少 id")
	if not str(level.get("band", "")) in BANDS:
		return _invalid("%s 的 band 不正确" % level_id)
	var min_age := _strict_int(level.get("minAge", null))
	if min_age < 4 or min_age > 12:
		return _invalid("%s 的 minAge 应为 4–12" % level_id)
	var width_value := _strict_int(level.get("width", null))
	var height_value := _strict_int(level.get("height", null))
	if width_value < 4 or width_value > 14 or height_value < 4 or height_value > 12:
		return _invalid("%s 的棋盘尺寸不正确" % level_id)
	if not level.get("coop", null) is bool:
		return _invalid("%s 的 coop 必须是布尔值" % level_id)
	var walls_value: Variant = level.get("walls", null)
	var goals_value: Variant = level.get("goals", null)
	var boxes_value: Variant = level.get("boxes", null)
	var player_value: Variant = level.get("player", null)
	if not walls_value is Array or not goals_value is Array or not boxes_value is Array or not player_value is Dictionary:
		return _invalid("%s 缺少墙、目标、木箱或玩家位置" % level_id)
	var walls_seen := {}
	for raw_wall in walls_value:
		if not raw_wall is Dictionary:
			return _invalid("%s 的墙坐标格式不正确" % level_id)
		var wall := _cell(raw_wall)
		if not _inside(wall, width_value, height_value):
			return _invalid("%s 的墙坐标超出棋盘" % level_id)
		var wall_key := _cell_key(wall)
		if walls_seen.has(wall_key):
			return _invalid("%s 有重复的墙" % level_id)
		walls_seen[wall_key] = true
	var goals_seen := {}
	for raw_goal in goals_value:
		if not raw_goal is Dictionary:
			return _invalid("%s 的目标坐标格式不正确" % level_id)
		var goal := _cell(raw_goal)
		if not _inside(goal, width_value, height_value):
			return _invalid("%s 的目标超出棋盘" % level_id)
		var goal_key := _cell_key(goal)
		if walls_seen.has(goal_key):
			return _invalid("%s 的目标压住了墙" % level_id)
		if goals_seen.has(goal_key):
			return _invalid("%s 有重复的目标" % level_id)
		goals_seen[goal_key] = true
	if goals_seen.is_empty():
		return _invalid("%s 至少需要一个目标" % level_id)
	if goals_seen.size() != boxes_value.size():
		return _invalid("%s 的木箱数量必须和目标数量相同" % level_id)
	var boxes_seen := {}
	for raw_box in boxes_value:
		if not raw_box is Dictionary:
			return _invalid("%s 的木箱坐标格式不正确" % level_id)
		var box := _cell(raw_box)
		if not _inside(box, width_value, height_value) or walls_seen.has(_cell_key(box)):
			return _invalid("%s 的木箱位置不合法" % level_id)
		var box_key := _cell_key(box)
		if boxes_seen.has(box_key):
			return _invalid("%s 有重叠的木箱" % level_id)
		boxes_seen[box_key] = true
	var player := _cell(player_value)
	if not _inside(player, width_value, height_value) or walls_seen.has(_cell_key(player)) or boxes_seen.has(_cell_key(player)):
		return _invalid("%s 的玩家位置不合法" % level_id)
	var solution_value: Variant = level.get("solution", null)
	if not solution_value is Array or solution_value.is_empty():
		return _invalid("%s 缺少作者解法" % level_id)
	for direction in solution_value:
		if not direction is String or not DIRECTIONS.has(str(direction)):
			return _invalid("%s 的作者解法含有未知方向" % level_id)
	var par_moves := _strict_int(level.get("parMoves", null))
	if par_moves != solution_value.size():
		return _invalid("%s 的 parMoves 必须等于作者解法步数" % level_id)
	var turn_order_value: Variant = level.get("turnOrder", null)
	if not turn_order_value is Array or turn_order_value.is_empty():
		return _invalid("%s 缺少 turnOrder" % level_id)
	var turn_seen := {}
	for turn_value in turn_order_value:
		var turn := _strict_int(turn_value)
		if turn < 0 or turn > 1 or turn_seen.has(turn):
			return _invalid("%s 的 turnOrder 不合法" % level_id)
		turn_seen[turn] = true
	if not turn_seen.has(0):
		return _invalid("%s 的 turnOrder 必须从玩家 0 开始" % level_id)
	if bool(level.get("coop", false)) and turn_seen.size() != 2:
		return _invalid("%s 的协作关卡需要两位玩家轮流" % level_id)
	if not bool(level.get("coop", false)) and turn_seen.size() != 1:
		return _invalid("%s 的单人关卡只需要一位玩家" % level_id)
	for key in ["title", "hint", "narration", "explanation"]:
		if str(level.get(key, "")).strip_edges().is_empty():
			return _invalid("%s 缺少 %s" % [level_id, key])
	var simulation := simulate_solution(level)
	if not bool(simulation.get("ok", false)):
		return _invalid("%s 的作者解法无法完成：%s" % [level_id, str(simulation.get("message", "校验失败"))])
	var completed_at_start := true
	for box in boxes_seen:
		if not goals_seen.has(box):
			completed_at_start = false
			break
	if completed_at_start:
		return _invalid("%s 一开始就已经完成，没有可玩的步骤" % level_id)
	return {"ok": true, "message": "", "simulation": simulation}


static func simulate_solution(level: Dictionary) -> Dictionary:
	var width_value := _strict_int(level.get("width", null))
	var height_value := _strict_int(level.get("height", null))
	var walls := _walls_set(level.get("walls", []))
	var goals := _goals_set(level.get("goals", []))
	var boxes: Array = _boxes_from(level.get("boxes", []))
	var player_value: Variant = level.get("player", {})
	if not player_value is Dictionary:
		return {"ok": false, "message": "玩家位置不正确"}
	var player := _cell(player_value)
	var solution_value: Variant = level.get("solution", [])
	if not solution_value is Array:
		return {"ok": false, "message": "作者解法不是数组"}
	for index in solution_value.size():
		var direction := str(solution_value[index])
		if not DIRECTIONS.has(direction):
			return {"ok": false, "message": "第 %s 步方向不正确" % (index + 1)}
		var target := player + _direction(direction)
		if not _inside(target, width_value, height_value) or walls.has(_cell_key(target)):
			return {"ok": false, "message": "第 %s 步撞墙" % (index + 1)}
		var box_index := _box_index_at(boxes, target)
		if box_index >= 0:
			var beyond := target + _direction(direction)
			if not _inside(beyond, width_value, height_value) or walls.has(_cell_key(beyond)) or _box_index_at(boxes, beyond) >= 0:
				return {"ok": false, "message": "第 %s 步木箱无法推动" % (index + 1)}
			boxes[box_index] = beyond
		player = target
	if boxes.size() != goals.size():
		return {"ok": false, "message": "木箱与目标数量不一致"}
	for box in boxes:
		if not goals.has(_cell_key(box)):
			return {"ok": false, "message": "作者解法结束后仍有木箱没有归位"}
	return {"ok": true, "moves": solution_value.size(), "player": _cell_dictionary(player), "boxes": boxes}


static func _invalid(message: String) -> Dictionary:
	return {"ok": false, "message": message}


static func _strict_int(value: Variant) -> int:
	if not (value is int or value is float):
		return INVALID_INT
	if not is_finite(float(value)) or not is_equal_approx(float(value), float(int(value))):
		return INVALID_INT
	return int(value)


static func _strict_int_is(value: Variant, expected: int) -> bool:
	var parsed := _strict_int(value)
	return parsed != INVALID_INT and parsed == expected


static func _integer(value: Variant) -> int:
	if value is int:
		return int(value)
	if value is float and is_finite(float(value)):
		return int(value)
	return 0


static func _cell(value: Variant) -> Vector2i:
	if not value is Dictionary:
		return Vector2i(-9999, -9999)
	return Vector2i(_integer(value.get("x", -9999)), _integer(value.get("y", -9999)))


static func _cell_dictionary(cell: Vector2i) -> Dictionary:
	return {"x": cell.x, "y": cell.y}


static func _cell_key(cell: Vector2i) -> String:
	return "%s:%s" % [cell.x, cell.y]


static func _cell_from_key(value: String) -> Vector2i:
	var pieces := value.split(":")
	if pieces.size() != 2:
		return Vector2i(-9999, -9999)
	return Vector2i(int(pieces[0]), int(pieces[1]))


static func _inside(cell: Vector2i, width_value: int, height_value: int) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < width_value and cell.y < height_value


static func _direction(direction: String) -> Vector2i:
	return DIRECTION_VECTORS.get(direction, Vector2i.ZERO)


static func _walls_set(value: Variant) -> Dictionary:
	var walls := {}
	if not value is Array:
		return walls
	for raw in value:
		if raw is Dictionary:
			walls[_cell_key(_cell(raw))] = true
	return walls


static func _goals_set(value: Variant) -> Dictionary:
	var goals := {}
	if not value is Array:
		return goals
	for raw in value:
		if raw is Dictionary:
			goals[_cell_key(_cell(raw))] = true
	return goals


static func _boxes_from(value: Variant) -> Array:
	if not value is Array:
		return []
	var boxes: Array = value
	return _normalized_boxes(boxes)


static func _box_dicts(boxes: Array) -> Array:
	var result: Array = []
	for box in _normalized_boxes(boxes):
		result.append(_cell_dictionary(Vector2i(box)))
	return result


static func _normalized_boxes(value: Array) -> Array:
	var boxes: Array = []
	for raw in value:
		if raw is Vector2i:
			boxes.append(raw)
		elif raw is Dictionary:
			boxes.append(_cell(raw))
	boxes.sort_custom(func(first: Vector2i, second: Vector2i):
		return first.y < second.y or (first.y == second.y and first.x < second.x)
	)
	return boxes


static func _box_index_at(boxes: Array, cell: Vector2i) -> int:
	for index in boxes.size():
		if Vector2i(boxes[index]) == cell:
			return index
	return -1


func _is_wall(cell: Vector2i) -> bool:
	if not _inside(cell, width(), height()):
		return true
	return _walls_set(level_definition.get("walls", [])).has(_cell_key(cell))


func _valid_state_geometry(player: Vector2i, boxes: Array) -> bool:
	if not _inside(player, width(), height()):
		return false
	if boxes.size() != goal_count():
		return false
	var walls := _walls_set(level_definition.get("walls", []))
	if walls.has(_cell_key(player)):
		return false
	var seen := {}
	for box in boxes:
		if not box is Vector2i or not _inside(box, width(), height()):
			return false
		var key := _cell_key(box)
		if walls.has(key) or seen.has(key) or box == player:
			return false
		seen[key] = true
	if seen.size() != goal_count():
		return false
	return true


func _push_history() -> void:
	var history: Array = state.get("history", [])
	history.append({
		"player": state.get("player", {}).duplicate(true),
		"boxes": state.get("boxes", []).duplicate(true),
		"turn": int(state.get("turn", 0)),
		"moves": int(state.get("moves", 0)),
		"pushes": int(state.get("pushes", 0)),
		"lastMove": str(state.get("lastMove", "")),
	})
	while history.size() > MAX_HISTORY:
		history.pop_front()
	state.history = history


func _advance_turn() -> void:
	var players_value: Variant = state.get("players", [])
	var player_count: int = players_value.size() if players_value is Array else 1
	if is_cooperative() and player_count >= 2:
		var order := _turn_order()
		var current_index := order.find(int(state.get("turn", 0)))
		if current_index < 0:
			current_index = -1
		state.turn = int(order[(current_index + 1) % order.size()])
	else:
		state.turn = 0


func _turn_order() -> Array:
	var value: Variant = level_definition.get("turnOrder", [0])
	var result: Array = []
	if value is Array:
		for raw in value:
			var turn := _strict_int(raw)
			if turn in [0, 1] and not (turn in result):
				result.append(turn)
	if result.is_empty():
		result.append(0)
	return result


func _stuck_cell_keys(boxes: Array) -> Array:
	var goals := _goals_set(level_definition.get("goals", []))
	var walls := _walls_set(level_definition.get("walls", []))
	var result: Array = []
	for box in _boxes_from(boxes):
		var cell := Vector2i(box)
		if goals.has(_cell_key(cell)):
			continue
		var up := not _inside(cell + Vector2i(0, -1), width(), height()) or walls.has(_cell_key(cell + Vector2i(0, -1)))
		var down := not _inside(cell + Vector2i(0, 1), width(), height()) or walls.has(_cell_key(cell + Vector2i(0, 1)))
		var left := not _inside(cell + Vector2i(-1, 0), width(), height()) or walls.has(_cell_key(cell + Vector2i(-1, 0)))
		var right := not _inside(cell + Vector2i(1, 0), width(), height()) or walls.has(_cell_key(cell + Vector2i(1, 0)))
		if (up and left) or (up and right) or (down and left) or (down and right):
			result.append(_cell_key(cell))
	result.sort()
	return result


func boxes_complete(boxes: Array) -> bool:
	var goals := _goals_set(level_definition.get("goals", []))
	if boxes.size() != goals.size() or boxes.is_empty():
		return false
	for box in boxes:
		if not goals.has(_cell_key(Vector2i(box))):
			return false
	return true


func _next_solution_direction() -> String:
	var solution_value: Variant = level_definition.get("solution", [])
	if not solution_value is Array:
		return ""
	var player := _cell(level_definition.get("player", {}))
	var boxes: Array = _boxes_from(level_definition.get("boxes", []))
	var current_boxes: Array = _boxes_from(state.get("boxes", []))
	var current_player := _cell(state.get("player", {}))
	var current_key := _state_key(current_player, current_boxes)
	for index in solution_value.size():
		if _state_key(player, boxes) == current_key:
			return str(solution_value[index])
		var direction := str(solution_value[index])
		var target := player + _direction(direction)
		if not _inside(target, width(), height()) or _is_wall(target):
			return ""
		var box_index := _box_index_at(boxes, target)
		if box_index >= 0:
			var beyond := target + _direction(direction)
			if not _inside(beyond, width(), height()) or _is_wall(beyond) or _box_index_at(boxes, beyond) >= 0:
				return ""
			boxes[box_index] = beyond
		player = target
	return ""


static func _state_key(player: Vector2i, boxes: Array) -> String:
	var keys: Array = []
	for box in boxes:
		keys.append(_cell_key(Vector2i(box)))
	keys.sort()
	return "%s|%s" % [_cell_key(player), "|".join(PackedStringArray(keys))]
