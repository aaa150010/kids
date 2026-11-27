class_name RobotRules
extends GameSession

const VERSION := 1
const BANDS := ["easy", "normal", "challenge"]
const COMMANDS := ["up", "down", "left", "right"]
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


func create_session(context: Dictionary) -> Dictionary:
	super.create_session(context)
	var level: Dictionary = context.get("level", {}).duplicate(true) if context.get("level", {}) is Dictionary else {}
	var validation := validate_level(level)
	var level_id := maxi(1, int(context.get("levelId", 1)))
	var start_cell := _cell(level.get("start", {}))
	state.merge({
		"robotVersion": VERSION,
		"levelId": level_id,
		"level": level,
		"levelTitle": str(level.get("title", "路线小机器人")),
		"levelBand": str(level.get("band", "easy")),
		"levelKey": str(level.get("id", "")),
		"difficulty": str(context.get("difficulty", "normal")),
		"program": [],
		"cursor": 0,
		"robot": _cell_dictionary(start_cell),
		"collectedStars": [],
		"phase": "program" if bool(validation.get("ok", false)) else "empty",
		"reason": "" if bool(validation.get("ok", false)) else str(validation.get("message", "路线内容不完整")),
		"lastMove": "",
		"blockedCell": {},
		"hintText": "",
		"hints": 0,
		"retries": 0,
		"steps": 0,
		"stars": 0,
		"completed": false,
		"outcome": "",
		"winner": -1,
		"turn": 0,
		"reported": false,
	}, true)
	return state


func handle_input(action: Dictionary) -> Dictionary:
	match str(action.get("type", "")):
		"add_command":
			return add_command(str(action.get("command", "")))
		"remove_command":
			return remove_command(int(action.get("index", -1)))
		"clear_program":
			return clear_program()
		"step":
			return step()
		"hint":
			return hint()
		"reset_run":
			return reset_run()
	return {"ok": false}


func add_command(command: String) -> Dictionary:
	if str(state.get("phase", "")) == "empty":
		return {"ok": false, "message": "这一关的路线还没有准备好"}
	if str(state.get("phase", "")) == "result":
		return {"ok": false, "message": "这条路线已经完成啦"}
	if not (command in COMMANDS):
		return {"ok": false, "message": "请选择一个方向指令"}
	var allowed: Array = _level().get("allowedCommands", [])
	if not (command in allowed):
		return {"ok": false, "message": "这一关没有“%s”指令" % str(DIRECTION_NAMES.get(command, command))}
	var program: Array = state.get("program", [])
	var slot_limit := int(_level().get("slotLimit", program.size()))
	if program.size() >= slot_limit:
		return {"ok": false, "message": "程序条已经排满了，先点一条指令删掉"}
	var reset := str(state.get("phase", "")) != "program" or int(state.get("cursor", 0)) > 0
	program.append(command)
	state.program = program
	_reset_run(false)
	if _is_coop():
		var players_value: Variant = state.get("players", [])
		var player_count := maxi(1, players_value.size() if players_value is Array else 1)
		state.turn = (int(state.get("turn", 0)) + 1) % player_count
	return {
		"ok": true,
		"event": "added",
		"command": command,
		"count": program.size(),
		"turn": int(state.get("turn", 0)),
		"reset": reset,
	}


func remove_command(index: int) -> Dictionary:
	if str(state.get("phase", "")) == "result":
		return {"ok": false, "message": "这条路线已经完成啦"}
	var program: Array = state.get("program", [])
	if index < 0 or index >= program.size():
		return {"ok": false, "message": "这条指令已经不在程序里了"}
	var removed := str(program[index])
	program.remove_at(index)
	state.program = program
	_reset_run(false)
	return {
		"ok": true,
		"event": "removed",
		"command": removed,
		"index": index,
		"count": program.size(),
	}


func clear_program() -> Dictionary:
	if str(state.get("phase", "")) == "result":
		return {"ok": false, "message": "这条路线已经完成啦"}
	state.program = []
	_reset_run(false)
	return {"ok": true, "event": "cleared", "count": 0}


func reset_run() -> Dictionary:
	if str(state.get("phase", "")) == "result":
		return {"ok": false, "message": "这条路线已经完成啦"}
	_reset_run(true)
	return {"ok": true, "event": "reset_run"}


func step() -> Dictionary:
	var phase := str(state.get("phase", ""))
	if phase == "empty":
		return {"ok": false, "message": "这一关的路线还没有准备好"}
	if phase == "result":
		return {"ok": false, "message": "已经到小旗啦"}
	if phase == "retry":
		return {"ok": false, "message": "先改一改程序里的指令，再继续走"}
	var program: Array = state.get("program", [])
	if program.is_empty():
		return {"ok": false, "message": "先在右边选几条方向指令"}
	var cursor := int(state.get("cursor", 0))
	if cursor < 0 or cursor >= program.size():
		return {"ok": false, "message": "程序已经走完，请修改后再试"}
	var command := str(program[cursor])
	var robot := _cell(state.get("robot", {}))
	var target := robot + _direction(command)
	if not _walkable(target):
		state.blockedCell = _cell_dictionary(target)
		state.lastMove = command
		state.phase = "retry"
		state.retries = int(state.get("retries", 0)) + 1
		state.reason = _collision_reason(target)
		return {
			"ok": true,
			"event": "blocked",
			"command": command,
			"reason": str(state.reason),
			"robot": state.robot,
			"blockedCell": state.blockedCell,
			"retries": int(state.retries),
		}
	state.robot = _cell_dictionary(target)
	state.cursor = cursor + 1
	state.steps = int(state.get("steps", 0)) + 1
	state.lastMove = command
	state.blockedCell = {}
	state.reason = ""
	state.phase = "running"
	_collect_star(target)
	if target == _cell(_level().get("goal", {})):
		state.phase = "result"
		state.completed = true
		state.winner = -1
		state.outcome = "played" if str(state.get("modeId", "classic")) == "classic" else "win"
		state.reason = "到达小旗啦！"
		state.stars = stars()
		return {
			"ok": true,
			"event": "finished",
			"command": command,
			"robot": state.robot,
			"stars": int(state.stars),
			"steps": int(state.steps),
			"par": int(_level().get("par", 0)),
		}
	if int(state.cursor) >= program.size():
		state.phase = "retry"
		state.retries = int(state.get("retries", 0)) + 1
		state.reason = "程序走完了，小旗还在前面。补一条方向指令再试。"
		return {
			"ok": true,
			"event": "dead_end",
			"command": command,
			"reason": str(state.reason),
			"robot": state.robot,
			"retries": int(state.retries),
		}
	return {
		"ok": true,
		"event": "stepped",
		"command": command,
		"robot": state.robot,
		"cursor": int(state.cursor),
		"remaining": program.size() - int(state.cursor),
	}


func hint() -> Dictionary:
	if str(state.get("phase", "")) == "empty":
		return {"ok": false, "message": "这一关的路线还没有准备好"}
	if str(state.get("phase", "")) == "result":
		return {"ok": false, "message": "已经完成啦，不用提示"}
	state.hints = int(state.get("hints", 0)) + 1
	state.hintText = str(_level().get("hint", "先看小旗在哪一边，再决定先走哪条边。"))
	return {
		"ok": true,
		"hint": str(state.hintText),
		"hints": int(state.hints),
	}


func stars() -> int:
	if str(state.get("phase", "")) != "result":
		return 0
	var steps := int(state.get("steps", 0))
	var par := int(_level().get("par", steps))
	var hints := int(state.get("hints", 0))
	var retries := int(state.get("retries", 0))
	if steps <= par and hints == 0 and retries == 0:
		return 3
	if steps <= par + 2 and hints <= 1 and retries <= 1:
		return 2
	return 1


func result() -> Dictionary:
	if str(state.get("phase", "")) != "result":
		return {}
	return {
		"winner": -1,
		"phase": "result",
		"outcome": "played" if str(state.get("modeId", "classic")) == "classic" else "win",
		"reason": str(state.get("reason", "到达小旗")),
		"stars": int(state.get("stars", stars())),
		"steps": int(state.get("steps", 0)),
		"par": int(_level().get("par", 0)),
		"hints": int(state.get("hints", 0)),
		"retries": int(state.get("retries", 0)),
		"levelId": int(state.get("levelId", 1)),
		"levelIdText": str(_level().get("id", "")),
	}


func tick(_delta: float) -> bool:
	return false


func snapshot() -> Dictionary:
	state.robotVersion = VERSION
	if str(state.get("phase", "")) == "result":
		state.stars = stars()
	return super.snapshot()


func restore(value: Dictionary) -> bool:
	if _strict_int(value.get("robotVersion", null)) != VERSION:
		return false
	if not super.restore(value):
		return false
	var level: Variant = state.get("level", {})
	if not level is Dictionary:
		return false
	var validation := validate_level(level)
	if not bool(validation.get("ok", false)):
		return false
	var phase := str(state.get("phase", ""))
	if phase not in ["program", "running", "retry", "result"]:
		return false
	var mode := str(state.get("modeId", "classic"))
	if mode not in ["classic", "adventure"]:
		return false
	var program: Variant = state.get("program", null)
	if not program is Array:
		return false
	var allowed: Array = level.get("allowedCommands", [])
	var slot_limit := int(level.get("slotLimit", 0))
	if program.size() > slot_limit:
		return false
	for command in program:
		if not command is String or not (str(command) in allowed):
			return false
	var cursor_value := _strict_int(state.get("cursor", null))
	if cursor_value < 0 or cursor_value > program.size():
		return false
	var robot_value: Variant = state.get("robot", {})
	if not robot_value is Dictionary:
		return false
	var robot := _cell(robot_value)
	if not _position_valid(robot):
		return false
	var prefix := _replay_prefix(level, program, cursor_value)
	if not bool(prefix.get("ok", false)):
		return false
	if prefix.get("robot", Vector2i(-1, -1)) != robot:
		return false
	var prefix_stars: Array = prefix.get("stars", [])
	var collected: Variant = state.get("collectedStars", [])
	if not collected is Array:
		return false
	var collected_sorted: Array = collected.duplicate()
	collected_sorted.sort()
	var prefix_sorted: Array = prefix_stars.duplicate()
	prefix_sorted.sort()
	if collected_sorted != prefix_sorted:
		return false
	var goal := _cell(level.get("goal", {}))
	if phase == "result":
		if robot != goal:
			return false
	elif robot == goal:
		return false
	if phase == "program":
		if cursor_value != 0 or robot != _cell(level.get("start", {})):
			return false
	elif phase in ["running", "retry"]:
		if cursor_value >= program.size() and phase != "retry":
			return false
		if cursor_value >= program.size() and robot == goal:
			return false
	state.steps = cursor_value
	if phase == "retry":
		if cursor_value < program.size():
			var blocked_command := str(program[cursor_value])
			var blocked_target := robot + _direction(blocked_command)
			if _walkable(blocked_target):
				return false
			var blocked_value: Variant = state.get("blockedCell", {})
			if not blocked_value is Dictionary:
				return false
			if _cell(blocked_value) != blocked_target:
				return false
		else:
			var blocked_value: Variant = state.get("blockedCell", {})
			if blocked_value is Dictionary and not blocked_value.is_empty():
				return false
	for key in ["hints", "retries"]:
		var number := _strict_int(state.get(key, null))
		if number < 0:
			return false
		state[key] = number
	var turn_value := _strict_int(state.get("turn", 0))
	if turn_value < 0 or turn_value >= maxi(1, state.players.size()):
		return false
	state.turn = turn_value
	if not state.get("reported", null) is bool:
		return false
	if not state.get("completed", null) is bool:
		return false
	state.completed = phase == "result"
	state.reason = str(state.get("reason", ""))
	state.hintText = str(state.get("hintText", ""))
	state.lastMove = str(state.get("lastMove", ""))
	if not str(state.lastMove).is_empty() and not (str(state.lastMove) in COMMANDS):
		return false
	state.level = level.duplicate(true)
	state.levelId = maxi(1, _strict_int(state.get("levelId", 1)))
	state.levelKey = str(level.get("id", ""))
	state.levelTitle = str(level.get("title", "路线小机器人"))
	state.levelBand = str(level.get("band", "easy"))
	state.winner = -1
	if phase == "result":
		state.outcome = "played" if mode == "classic" else "win"
	else:
		state.outcome = ""
	state.stars = stars() if phase == "result" else 0
	state.robotVersion = VERSION
	return true


func _level() -> Dictionary:
	var value: Variant = state.get("level", {})
	return value if value is Dictionary else {}


func _is_coop() -> bool:
	var players_value: Variant = state.get("players", [])
	return str(state.get("modeId", "classic")) == "classic" and players_value is Array and players_value.size() == 2


func _reset_run(clear_failure: bool) -> void:
	state.cursor = 0
	state.steps = 0
	state.robot = _cell_dictionary(_cell(_level().get("start", {})))
	state.collectedStars = []
	state.blockedCell = {}
	state.lastMove = ""
	state.completed = false
	state.stars = 0
	state.outcome = ""
	if clear_failure:
		state.reason = ""
	else:
		state.reason = ""
	state.phase = "program" if str(state.get("phase", "program")) != "empty" else "empty"


func _collect_star(cell: Vector2i) -> void:
	for entry in _level().get("stars", []):
		if entry is Dictionary and _cell(entry) == cell:
			var key := _cell_key(cell)
			var collected: Array = state.get("collectedStars", [])
			if not (key in collected):
				collected.append(key)
				state.collectedStars = collected
			return


func _walkable(cell: Vector2i) -> bool:
	var level := _level()
	var width := int(level.get("width", 0))
	var height := int(level.get("height", 0))
	if cell.x < 0 or cell.y < 0 or cell.x >= width or cell.y >= height:
		return false
	for wall in level.get("walls", []):
		if wall is Dictionary and _cell(wall) == cell:
			return false
	return true


func _collision_reason(cell: Vector2i) -> String:
	var level := _level()
	if cell.x < 0 or cell.y < 0 or cell.x >= int(level.get("width", 0)) or cell.y >= int(level.get("height", 0)):
		return "前面是地图边界，机器人停在最后安全格。删掉这条指令再试试。"
	return "前面有一堵纸墙，机器人停在最后安全格。删掉这条指令再试试。"


static func _cell(value: Variant) -> Vector2i:
	if not value is Dictionary:
		return Vector2i(-1, -1)
	var x := _strict_int(value.get("x", null))
	var y := _strict_int(value.get("y", null))
	return Vector2i(x, y)


func _cell_dictionary(cell: Vector2i) -> Dictionary:
	return {"x": cell.x, "y": cell.y}


func _cell_key(cell: Vector2i) -> String:
	return "%s:%s" % [cell.x, cell.y]


func _position_valid(cell: Vector2i) -> bool:
	var level := _level()
	return cell.x >= 0 and cell.y >= 0 and cell.x < int(level.get("width", 0)) and cell.y < int(level.get("height", 0))


static func validate_catalog(value: Variant) -> Dictionary:
	var issues: Array[String] = []
	if not value is Dictionary:
		return {"ok": false, "issues": ["robot.json 顶层必须是对象"], "validLevels": []}
	var data: Dictionary = value
	if _strict_int(data.get("version", null)) != VERSION:
		issues.append("robot.json 的 version 必须是 %s" % VERSION)
	var levels_value: Variant = data.get("levels", null)
	if not levels_value is Array:
		issues.append("robot.json 缺少 levels 数组")
		return {"ok": false, "issues": issues, "validLevels": []}
	var levels: Array = levels_value
	if levels.size() != 24:
		issues.append("路线关卡必须是 24 关，实际 %s 关" % levels.size())
	var band_counts := {"easy": 0, "normal": 0, "challenge": 0}
	var seen_ids := {}
	var valid_levels: Array = []
	for index in levels.size():
		var raw: Variant = levels[index]
		if not raw is Dictionary:
			issues.append("第 %s 关不是对象" % (index + 1))
			continue
		var entry: Dictionary = raw
		var identifier := str(entry.get("id", ""))
		if identifier.is_empty():
			issues.append("第 %s 关缺少 id" % (index + 1))
		elif seen_ids.has(identifier):
			issues.append("关卡 id 重复：%s" % identifier)
		else:
			seen_ids[identifier] = true
		var validation := validate_level(entry)
		if not bool(validation.get("ok", false)):
			issues.append("第 %s 关：%s" % [index + 1, str(validation.get("message", "配置异常"))])
			continue
		var band := str(entry.get("band", ""))
		band_counts[band] = int(band_counts.get(band, 0)) + 1
		valid_levels.append(entry)
	for band in BANDS:
		if int(band_counts.get(band, 0)) != 8:
			issues.append("%s 难度应有 8 关，实际 %s 关" % [band, int(band_counts.get(band, 0))])
	return {
		"ok": issues.is_empty(),
		"issues": issues,
		"validLevels": valid_levels,
		"bandCounts": band_counts,
	}


static func validate_level(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return {"ok": false, "message": "关卡必须是对象"}
	var level: Dictionary = value
	var identifier := str(level.get("id", "")).strip_edges()
	if identifier.is_empty():
		return {"ok": false, "message": "缺少关卡 id"}
	if str(level.get("band", "")) not in BANDS:
		return {"ok": false, "message": "%s 的 band 不合法" % identifier}
	var min_age := _strict_int(level.get("minAge", null))
	if min_age < 4 or min_age > 12:
		return {"ok": false, "message": "%s 的 minAge 必须在 4–12" % identifier}
	if str(level.get("title", "")).strip_edges().is_empty():
		return {"ok": false, "message": "%s 缺少标题" % identifier}
	var width := _strict_int(level.get("width", null))
	var height := _strict_int(level.get("height", null))
	if width < 3 or height < 3 or width > 16 or height > 16:
		return {"ok": false, "message": "%s 的宽高必须在 3–16" % identifier}
	var start := _cell(level.get("start", {}))
	var goal := _cell(level.get("goal", {}))
	if not _inside(start, width, height) or not _inside(goal, width, height):
		return {"ok": false, "message": "%s 的起点或旗子越界" % identifier}
	if start == goal:
		return {"ok": false, "message": "%s 的起点和旗子不能相同" % identifier}
	var walls_value: Variant = level.get("walls", null)
	var stars_value: Variant = level.get("stars", null)
	if not walls_value is Array or not stars_value is Array:
		return {"ok": false, "message": "%s 的 walls 或 stars 不是数组" % identifier}
	var walls := {}
	for wall in walls_value:
		var cell := _cell(wall)
		if not _inside(cell, width, height):
			return {"ok": false, "message": "%s 的墙越界" % identifier}
		if cell == start or cell == goal:
			return {"ok": false, "message": "%s 的墙不能盖住起点或旗子" % identifier}
		var key := "%s:%s" % [cell.x, cell.y]
		if walls.has(key):
			return {"ok": false, "message": "%s 有重复的墙" % identifier}
		walls[key] = true
	var star_cells := {}
	for star in stars_value:
		var cell := _cell(star)
		if not _inside(cell, width, height):
			return {"ok": false, "message": "%s 的星星越界" % identifier}
		if cell == start or cell == goal or walls.has("%s:%s" % [cell.x, cell.y]):
			return {"ok": false, "message": "%s 的星星不能放在起点、旗子或墙上" % identifier}
		var key := "%s:%s" % [cell.x, cell.y]
		if star_cells.has(key):
			return {"ok": false, "message": "%s 有重复的星星" % identifier}
		star_cells[key] = true
	var commands_value: Variant = level.get("allowedCommands", null)
	if not commands_value is Array or commands_value.is_empty():
		return {"ok": false, "message": "%s 缺少可用方向指令" % identifier}
	var allowed := {}
	for command in commands_value:
		if not command is String or not (str(command) in COMMANDS):
			return {"ok": false, "message": "%s 含未知方向指令" % identifier}
		if allowed.has(str(command)):
			return {"ok": false, "message": "%s 的方向指令重复" % identifier}
		allowed[str(command)] = true
	var slot_limit := _strict_int(level.get("slotLimit", null))
	var par := _strict_int(level.get("par", null))
	var solution_value: Variant = level.get("solution", null)
	if not solution_value is Array or solution_value.is_empty():
		return {"ok": false, "message": "%s 缺少标准解" % identifier}
	var solution: Array = solution_value
	if par != solution.size():
		return {"ok": false, "message": "%s 的 par 必须等于标准解步数" % identifier}
	if slot_limit < solution.size():
		return {"ok": false, "message": "%s 的程序容量放不下标准解" % identifier}
	var robot := start
	var seen_goal := false
	for command_index in solution.size():
		var command: Variant = solution[command_index]
		if not command is String or not (str(command) in allowed):
			return {"ok": false, "message": "%s 的标准解用了不可用指令" % identifier}
		robot += _direction(str(command))
		if not _inside(robot, width, height):
			return {"ok": false, "message": "%s 的标准解越界" % identifier}
		if walls.has("%s:%s" % [robot.x, robot.y]):
			return {"ok": false, "message": "%s 的标准解撞墙" % identifier}
		if robot == goal:
			if command_index < solution.size() - 1:
				return {"ok": false, "message": "%s 的标准解提前到达旗子" % identifier}
			seen_goal = true
	if robot != goal:
		return {"ok": false, "message": "%s 的标准解没有到达旗子" % identifier}
	if not seen_goal:
		return {"ok": false, "message": "%s 的标准解无法验证" % identifier}
	for key in ["hint", "narration", "explanation"]:
		if str(level.get(key, "")).strip_edges().is_empty():
			return {"ok": false, "message": "%s 缺少 %s 文案" % [identifier, key]}
	return {
		"ok": true,
		"message": identifier,
		"solutionLength": solution.size(),
		"par": par,
	}


static func _replay_prefix(level: Dictionary, program: Array, count: int) -> Dictionary:
	var width := int(level.get("width", 0))
	var height := int(level.get("height", 0))
	var robot := _cell(level.get("start", {}))
	var goal := _cell(level.get("goal", {}))
	var walls := {}
	for wall in level.get("walls", []):
		if wall is Dictionary:
			var cell := _cell(wall)
			walls["%s:%s" % [cell.x, cell.y]] = true
	var star_cells := {}
	for star in level.get("stars", []):
		if star is Dictionary:
			var cell := _cell(star)
			star_cells["%s:%s" % [cell.x, cell.y]] = true
	var collected: Array = []
	for index in count:
		var command := str(program[index])
		var target := robot + _direction(command)
		if not _inside(target, width, height) or walls.has("%s:%s" % [target.x, target.y]):
			return {"ok": false, "message": "执行记录撞墙或越界"}
		robot = target
		var key := "%s:%s" % [robot.x, robot.y]
		if star_cells.has(key) and not (key in collected):
			collected.append(key)
		if robot == goal and index < count - 1:
			return {"ok": false, "message": "到达旗子后还有执行记录"}
	return {"ok": true, "robot": robot, "stars": collected}


static func _inside(cell: Vector2i, width: int, height: int) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < width and cell.y < height


static func _direction(command: String) -> Vector2i:
	var value: Variant = DIRECTION_VECTORS.get(command, Vector2i.ZERO)
	return value if value is Vector2i else Vector2i.ZERO


static func _strict_int(value: Variant) -> int:
	if value is int:
		return int(value)
	if value is float and is_finite(float(value)) and is_equal_approx(float(value), float(int(value))):
		return int(value)
	return -2147483648
