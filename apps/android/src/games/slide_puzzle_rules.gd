class_name SlidePuzzleRules
extends GameSession

const VERSION := 1
const MODES := ["adventure", "classic"]
const BANDS := ["easy", "normal", "challenge"]
const KINDS := ["number", "pattern"]
const BLANK_DIRECTIONS := {
	"u": "up",
	"d": "down",
	"l": "left",
	"r": "right",
}
const DIRECTION_NAMES := {
	"up": "上",
	"down": "下",
	"left": "左",
	"right": "右",
}
const VECTORS := {
	"up": Vector2i(0, -1),
	"down": Vector2i(0, 1),
	"left": Vector2i(-1, 0),
	"right": Vector2i(1, 0),
}
const MAX_HISTORY := 300
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
		return _empty_state(requested_level, mode, str(validation.get("message", "这一盘华容道还没有准备好")))
	if str(level.get("mode", "")) != mode:
		return _empty_state(requested_level, mode, "这一盘棋盘的模式和当前游戏不一致")
	var players_value: Variant = context.get("players", [])
	var player_count: int = players_value.size() if players_value is Array else 0
	if mode == "adventure" and player_count != 1:
		return _empty_state(requested_level, mode, "单人闯关需要一位小朋友")
	if mode == "classic" and player_count != 2:
		return _empty_state(requested_level, mode, "双人推格需要两位小朋友")
	level_definition = level
	var initial: Array = level.get("startTiles", []).duplicate()
	state.merge({
		"slideVersion": VERSION,
		"gameId": "slide_puzzle",
		"modeId": mode,
		"levelId": requested_level,
		"levelNumber": requested_level,
		"levelKey": str(level.get("id", "")),
		"levelTitle": str(level.get("title", "数字华容道")),
		"levelBand": str(level.get("band", "easy")),
		"level": level,
		"initialTiles": initial.duplicate(),
		"tiles": initial.duplicate(),
		"blank": initial.find(0),
		"turn": 0,
		"moves": 0,
		"undos": 0,
		"hints": 0,
		"restarts": 0,
		"history": [],
		"hintTile": -1,
		"lastDirection": "",
		"phase": "playing",
		"winner": -1,
		"reason": "",
		"stars": 0,
		"reported": false,
	}, true)
	return state


func _empty_state(level_id: int, mode: String, message: String) -> Dictionary:
	state = {
		"slideVersion": VERSION,
		"gameId": "slide_puzzle",
		"modeId": mode,
		"levelId": level_id,
		"levelNumber": level_id,
		"level": {},
		"tiles": [],
		"initialTiles": [],
		"blank": -1,
		"history": [],
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
			return move_tile(_int_value(action.get("index", -1), -1))
		"undo":
			return undo()
		"hint":
			return hint()
		"restart":
			return restart()
	return {"ok": false, "message": "这个操作现在不能用"}


func move_tile(index: int) -> Dictionary:
	if str(state.get("phase", "")) == "empty":
		return {"ok": false, "message": str(state.get("loadError", "这一盘华容道还没有准备好"))}
	if str(state.get("phase", "")) == "finished":
		return {"ok": false, "message": "数字已经排好啦"}
	var size_value := int(level_definition.get("size", 0))
	if index < 0 or index >= size_value * size_value:
		return {"ok": false, "message": "请点空格旁边的一格"}
	var blank := int(state.get("blank", -1))
	if not _adjacent(index, blank, size_value):
		return {"ok": false, "message": "只有空格上下左右相邻的数字可以滑进去"}
	var tiles: Array = state.get("tiles", []).duplicate()
	if tiles.is_empty():
		return {"ok": false, "message": "棋盘记录不完整，请重新开始这一关"}
	var value := int(tiles[index])
	var direction := _direction_between(blank, index, size_value)
	_push_history()
	tiles[blank] = value
	tiles[index] = 0
	state.tiles = tiles
	state.blank = index
	state.moves = int(state.get("moves", 0)) + 1
	state.lastDirection = direction
	state.hintTile = -1
	_advance_turn()
	if solved(tiles):
		state.phase = "finished"
		state.winner = -1 if is_cooperative() else 0
		state.reason = "每一格都会到自己的位置啦。"
		state.stars = stars()
		return {
			"ok": true,
			"event": "finished",
			"tile": value,
			"index": index,
			"direction": direction,
			"moves": int(state.get("moves", 0)),
			"turn": int(state.get("turn", 0)),
			"stars": int(state.get("stars", stars())),
		}
	return {
		"ok": true,
		"event": "moved",
		"tile": value,
		"index": index,
		"direction": direction,
		"moves": int(state.get("moves", 0)),
		"turn": int(state.get("turn", 0)),
	}


func undo() -> Dictionary:
	if str(state.get("phase", "")) == "finished":
		return {"ok": false, "message": "这一盘已经完成啦"}
	if str(state.get("phase", "")) != "playing":
		return {"ok": false, "message": "现在没有可以撤回的一步"}
	var history: Array = state.get("history", [])
	if history.is_empty():
		return {"ok": false, "message": "已经回到这一盘开头啦"}
	var previous_value: Variant = history.pop_back()
	if not previous_value is Dictionary:
		return {"ok": false, "message": "这一步记录不完整，先重新开始"}
	var previous: Dictionary = previous_value
	state.history = history
	state.tiles = previous.get("tiles", []).duplicate()
	state.blank = int(previous.get("blank", -1))
	state.turn = int(previous.get("turn", 0))
	state.moves = int(previous.get("moves", 0))
	state.undos = int(state.get("undos", 0)) + 1
	state.hintTile = -1
	state.lastDirection = ""
	state.phase = "playing"
	state.reason = ""
	state.winner = -1
	state.stars = 0
	return {
		"ok": true,
		"event": "undone",
		"moves": int(state.moves),
		"undos": int(state.undos),
		"turn": int(state.turn),
	}


func hint() -> Dictionary:
	if str(state.get("phase", "")) != "playing":
		return {"ok": false, "message": "现在不用提示啦"}
	state.hints = int(state.get("hints", 0)) + 1
	var path := _solution_path()
	var current_tiles: Array = state.get("tiles", [])
	var found := -1
	for index in path.size():
		if path[index].get("tiles", []) == current_tiles:
			found = index
			break
	if found < 0 or found >= path.size() - 1:
		state.hintTile = -1
		return {
			"ok": true,
			"event": "hint",
			"direction": "",
			"tile": -1,
			"message": "这一步离开了作者路线。先撤销几步，回到亮起的棋盘位置再看提示。",
			"hints": int(state.hints),
		}
	var next_state: Dictionary = path[found + 1]
	var blank := int(state.get("blank", -1))
	var next_index := int(next_state.get("blank", -1))
	var direction := _direction_between(blank, next_index, int(level_definition.get("size", 0)))
	var tile := int((state.get("tiles", []) as Array)[next_index])
	state.hintTile = next_index
	return {
		"ok": true,
		"event": "hint",
		"direction": direction,
		"directionName": str(DIRECTION_NAMES.get(direction, "")),
		"tile": tile,
		"index": next_index,
		"message": "空格向%s移动：把 %s 滑进空格。" % [
			str(DIRECTION_NAMES.get(direction, "")),
			_tile_name(tile),
		],
		"hints": int(state.hints),
	}


func restart() -> Dictionary:
	if str(state.get("phase", "")) == "empty":
		return {"ok": false, "message": str(state.get("loadError", "这一盘还没有准备好"))}
	state.tiles = state.get("initialTiles", []).duplicate()
	state.blank = (state.get("initialTiles", []) as Array).find(0)
	state.turn = 0
	state.moves = 0
	state.undos = 0
	state.hints = 0
	state.restarts = int(state.get("restarts", 0)) + 1
	state.history = []
	state.hintTile = -1
	state.lastDirection = ""
	state.phase = "playing"
	state.reason = ""
	state.winner = -1
	state.stars = 0
	state.reported = false
	return {"ok": true, "event": "restarted"}


func stars() -> int:
	if str(state.get("phase", "")) != "finished":
		return 0
	var par := int(level_definition.get("parMoves", 0))
	var moves := int(state.get("moves", 0))
	var hints := int(state.get("hints", 0))
	var undos := int(state.get("undos", 0))
	if moves <= par and hints == 0 and undos == 0:
		return 3
	if moves <= par + 8 and hints <= 1 and undos <= 4:
		return 2
	return 1


func result() -> Dictionary:
	if str(state.get("phase", "")) != "finished":
		return {}
	return {
		"winner": int(state.get("winner", -1)),
		"reason": str(state.get("reason", "数字排好啦")),
		"phase": "finished",
		"outcome": "played" if is_cooperative() else "win",
		"stars": int(state.get("stars", stars())),
		"moves": int(state.get("moves", 0)),
		"parMoves": int(level_definition.get("parMoves", 0)),
		"undos": int(state.get("undos", 0)),
		"hints": int(state.get("hints", 0)),
		"size": int(level_definition.get("size", 3)),
		"levelId": int(state.get("levelId", 1)),
		"levelKey": str(level_definition.get("id", "")),
	}


func solved(tiles: Array) -> bool:
	var size_value := int(level_definition.get("size", 0))
	if tiles.size() != size_value * size_value:
		return false
	var count := size_value * size_value
	for index in count - 1:
		if int(tiles[index]) != index + 1:
			return false
	return int(tiles[count - 1]) == 0


func snapshot() -> Dictionary:
	state.slideVersion = VERSION
	if str(state.get("phase", "")) == "finished":
		state.stars = stars()
	return super.snapshot()


func restore(value: Dictionary) -> bool:
	if _strict_int(value.get("slideVersion", null)) != VERSION:
		return false
	if not super.restore(value):
		return false
	if str(state.get("gameId", "")) != "slide_puzzle":
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
	var tiles_value: Variant = state.get("tiles", null)
	var initial_value: Variant = state.get("initialTiles", null)
	if not tiles_value is Array or not initial_value is Array:
		return _reject_restore()
	var expected: Array = level.get("startTiles", [])
	if initial_value != expected:
		return _reject_restore()
	var tiles: Array = tiles_value.duplicate()
	if not _valid_permutation(tiles, int(level.get("size", 3))):
		return _reject_restore()
	var blank := _strict_int(state.get("blank", null))
	if blank != tiles.find(0):
		return _reject_restore()
	var phase := str(state.get("phase", ""))
	if phase not in ["playing", "finished"]:
		return _reject_restore()
	if phase == "playing" and bool(state.get("reported", false)):
		return _reject_restore()
	for field in ["moves", "undos", "hints", "restarts", "turn"]:
		var field_value := _strict_int(state.get(field, null))
		if field_value < 0:
			return _reject_restore()
		state[field] = field_value
	if int(state.turn) > (1 if mode == "classic" else 0):
		return _reject_restore()
	var history_value: Variant = state.get("history", null)
	if not history_value is Array or history_value.size() > MAX_HISTORY:
		return _reject_restore()
	var history: Array = history_value
	for raw in history:
		if not raw is Dictionary:
			return _reject_restore()
		var entry: Dictionary = raw
		var entry_tiles_value: Variant = entry.get("tiles", null)
		if not entry_tiles_value is Array or not _valid_permutation(entry_tiles_value, int(level.get("size", 3))):
			return _reject_restore()
		var entry_blank := _strict_int(entry.get("blank", null))
		if entry_blank != entry_tiles_value.find(0):
			return _reject_restore()
		var entry_turn := _strict_int(entry.get("turn", null))
		var entry_moves := _strict_int(entry.get("moves", null))
		if entry_turn < 0 or entry_turn > (1 if mode == "classic" else 0) or entry_moves < 0:
			return _reject_restore()
		entry.tiles = entry_tiles_value.duplicate()
		entry.blank = entry_blank
		entry.turn = entry_turn
		entry.moves = entry_moves
	state.history = history
	state.tiles = tiles
	state.blank = blank
	state.level = level
	var hint_tile := _strict_int(state.get("hintTile", null))
	if hint_tile < -1 or hint_tile >= int(level.get("size", 3)) * int(level.get("size", 3)):
		return _reject_restore()
	state.hintTile = hint_tile
	var direction := str(state.get("lastDirection", ""))
	if not direction.is_empty() and not direction in VECTORS:
		return _reject_restore()
	var complete := solved(tiles)
	if phase == "finished":
		if not complete:
			return _reject_restore()
		state.stars = stars()
		state.winner = -1 if mode == "classic" else 0
		state.reason = "每一格都会到自己的位置啦。"
	else:
		if complete:
			return _reject_restore()
		state.stars = 0
		state.winner = -1
		state.reason = ""
	if not state.get("reported", false) is bool:
		return _reject_restore()
	return true


func current_player_index() -> int:
	return clampi(int(state.get("turn", 0)), 0, 1)


func is_cooperative() -> bool:
	return str(state.get("modeId", "adventure")) == "classic"


func size() -> int:
	return int(level_definition.get("size", 3))


func tile_name(value: int) -> String:
	return _tile_name(value)


func _tile_name(value: int) -> String:
	if value <= 0:
		return "空格"
	if str(level_definition.get("kind", "number")) == "pattern":
		return "图案 %s" % value
	return "数字 %s" % value


func _advance_turn() -> void:
	if is_cooperative():
		state.turn = 1 - clampi(int(state.get("turn", 0)), 0, 1)
	else:
		state.turn = 0


func _push_history() -> void:
	var history: Array = state.get("history", [])
	history.append({
		"tiles": state.get("tiles", []).duplicate(),
		"blank": int(state.get("blank", -1)),
		"turn": int(state.get("turn", 0)),
		"moves": int(state.get("moves", 0)),
	})
	if history.size() > MAX_HISTORY:
		history = history.slice(history.size() - MAX_HISTORY)
	state.history = history


func _solution_path() -> Array:
	var tiles: Array = level_definition.get("startTiles", []).duplicate()
	var blank := tiles.find(0)
	var path: Array = [{"tiles": tiles.duplicate(), "blank": blank}]
	for direction in _solution_directions():
		var next_blank: int = blank + _index_delta(_direction(direction), int(level_definition.get("size", 3)))
		if next_blank < 0 or next_blank >= tiles.size():
			return path
		var value := int(tiles[next_blank])
		tiles[blank] = value
		tiles[next_blank] = 0
		blank = next_blank
		path.append({"tiles": tiles.duplicate(), "blank": blank})
	return path


func _solution_directions() -> Array:
	var result: Array = []
	var raw := str(level_definition.get("solution", "")).to_lower()
	for index in raw.length():
		var letter := raw.substr(index, 1)
		if BLANK_DIRECTIONS.has(letter):
			result.append(str(BLANK_DIRECTIONS[letter]))
	return result


static func _direction(value: String) -> Vector2i:
	return VECTORS.get(value, Vector2i.ZERO)


static func _index_delta(vector: Vector2i, size_value: int) -> int:
	return vector.y * size_value + vector.x


static func _adjacent(first: int, second: int, size_value: int) -> bool:
	if first < 0 or second < 0:
		return false
	var first_x := first % size_value
	var first_y := int(first / size_value)
	var second_x := second % size_value
	var second_y := int(second / size_value)
	return absi(first_x - second_x) + absi(first_y - second_y) == 1


static func _direction_between(blank: int, tile_index: int, size_value: int) -> String:
	var delta := Vector2i(
		(tile_index % size_value) - (blank % size_value),
		int(tile_index / size_value) - int(blank / size_value)
	)
	if delta == Vector2i(0, -1):
		return "up"
	if delta == Vector2i(0, 1):
		return "down"
	if delta == Vector2i(-1, 0):
		return "left"
	if delta == Vector2i(1, 0):
		return "right"
	return ""


static func _valid_permutation(tiles: Variant, size_value: int) -> bool:
	if not tiles is Array or size_value not in [3, 4] or tiles.size() != size_value * size_value:
		return false
	var seen := {}
	for raw in tiles:
		var value := _strict_int(raw)
		if value < 0 or value >= size_value * size_value or seen.has(value):
			return false
		seen[value] = true
	return seen.size() == size_value * size_value


static func solvable_permutation(tiles: Array, size_value: int) -> bool:
	if not _valid_permutation(tiles, size_value):
		return false
	var values: Array = []
	var blank_index := -1
	for index in tiles.size():
		var value := int(tiles[index])
		if value == 0:
			blank_index = index
		else:
			values.append(value)
	var inversions := 0
	for first in values.size():
		for second in range(first + 1, values.size()):
			if int(values[first]) > int(values[second]):
				inversions += 1
	if size_value % 2 == 1:
		return inversions % 2 == 0
	var blank_row_from_bottom := size_value - int(blank_index / size_value)
	return (inversions + blank_row_from_bottom) % 2 == 1


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
	level.size = _int_value(level.get("size", 0), 0)
	level.kind = str(level.get("kind", "number"))
	level.startTiles = _parse_tiles(level.get("start", ""))
	level.solution = str(level.get("solution", ""))
	level.parMoves = _int_value(level.get("parMoves", 0), 0)
	level.motif = _normalize_motif(level.get("motif", []), level.size)
	level.hint = str(level.get("hint", ""))
	level.narration = str(level.get("narration", ""))
	level.explanation = str(level.get("explanation", ""))
	return level


static func _parse_tiles(value: Variant) -> Array:
	var result: Array = []
	if value is Array:
		for raw in value:
			result.append(_int_value(raw, 0))
	elif value is String:
		for token in str(value).split(",", false):
			var cleaned := token.strip_edges()
			result.append(int(cleaned) if cleaned.is_valid_int() else 0)
	return result


static func _normalize_motif(value: Variant, size_value: int) -> Array:
	var result: Array = []
	var count := size_value * size_value
	if value is Array:
		for raw in value:
			result.append(str(raw))
	while result.size() < count:
		result.append("")
	return result.slice(0, count)


static func validate_catalog(value: Variant) -> Dictionary:
	var issues: Array[String] = []
	if not value is Dictionary:
		return {"ok": false, "issues": ["slide_puzzle.json 顶层必须是对象"], "validLevels": []}
	var data: Dictionary = value
	if _strict_int(data.get("schemaVersion", data.get("version", null))) != VERSION:
		issues.append("slide_puzzle.json 的 schemaVersion 必须是 %s" % VERSION)
	var levels_value: Variant = data.get("levels", null)
	if not levels_value is Array:
		return {"ok": false, "issues": ["slide_puzzle.json 缺少 levels 数组"], "validLevels": []}
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
			issues.append("第 %s 盘：%s" % [index + 1, str(validation.get("message", "格式不正确"))])
			continue
		var id := str(normalized.id)
		if ids.has(id):
			issues.append("华容道 id 重复：%s" % id)
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
	if levels_value.size() != 32:
		issues.append("华容道应为 32 盘，实际 %s 盘" % levels_value.size())
	for band in BANDS:
		if int(counts["adventure"][band]) != 8:
			issues.append("adventure %s 应为 8 盘，实际 %s 盘" % [band, counts["adventure"][band]])
	var classic_expected := {"easy": 2, "normal": 3, "challenge": 3}
	for band in BANDS:
		if int(counts["classic"][band]) != int(classic_expected[band]):
			issues.append("classic %s 应为 %s 盘，实际 %s 盘" % [band, classic_expected[band], counts["classic"][band]])
	return {"ok": issues.is_empty(), "issues": issues, "validLevels": valid_levels, "counts": counts}


static func validate_level(raw: Variant) -> Dictionary:
	if not raw is Dictionary:
		return {"ok": false, "message": "华容道关卡必须是对象"}
	var level := _normalize_level(raw)
	var identifier := str(level.get("id", "未命名华容道"))
	if identifier.strip_edges().is_empty():
		return {"ok": false, "message": "华容道关卡缺少 id"}
	if not str(level.get("mode", "")) in MODES:
		return {"ok": false, "message": "%s 的 mode 不合法" % identifier}
	if not str(level.get("band", "")) in BANDS:
		return {"ok": false, "message": "%s 的 band 不合法" % identifier}
	if int(level.get("minAge", 0)) < 4 or int(level.get("minAge", 0)) > 12:
		return {"ok": false, "message": "%s 的 minAge 必须在 4–12" % identifier}
	if int(level.get("levelNumber", 0)) < 1:
		return {"ok": false, "message": "%s 的 levelNumber 无效" % identifier}
	var size_value := int(level.get("size", 0))
	if not size_value in [3, 4]:
		return {"ok": false, "message": "%s 的 size 必须是 3 或 4" % identifier}
	if not str(level.get("kind", "")) in KINDS:
		return {"ok": false, "message": "%s 的 kind 不合法" % identifier}
	var tiles: Array = level.get("startTiles", [])
	if not _valid_permutation(tiles, size_value):
		return {"ok": false, "message": "%s 的 start 不是唯一数字排列" % identifier}
	if not solvable_permutation(tiles, size_value):
		return {"ok": false, "message": "%s 的 start 无解" % identifier}
	if str(level.get("kind", "")) == "pattern":
		var motif: Array = level.get("motif", [])
		if motif.size() != size_value * size_value:
			return {"ok": false, "message": "%s 的图案颜色数量不对" % identifier}
		for tint in motif:
			if not Color.html_is_valid(str(tint)):
				return {"ok": false, "message": "%s 的图案颜色不合法" % identifier}
	var solution := str(level.get("solution", "")).to_lower()
	if solution.is_empty():
		return {"ok": false, "message": "%s 缺少作者解" % identifier}
	var check := _apply_solution(tiles, solution, size_value)
	if not bool(check.get("ok", false)):
		return {"ok": false, "message": "%s 的作者解不成立：%s" % [identifier, str(check.get("message", ""))]}
	var par := int(level.get("parMoves", 0))
	if par < solution.length() or par > solution.length() + 2:
		return {"ok": false, "message": "%s 的 parMoves 应接近作者解步数" % identifier}
	return {"ok": true, "message": "", "level": level}


static func _apply_solution(initial: Array, solution: String, size_value: int) -> Dictionary:
	var tiles := initial.duplicate()
	var blank := tiles.find(0)
	for index in solution.length():
		var letter := solution.substr(index, 1)
		if not BLANK_DIRECTIONS.has(letter):
			return {"ok": false, "message": "解里有无法识别的方向 %s" % letter}
		var direction := str(BLANK_DIRECTIONS[letter])
		var next_blank := blank + _index_delta(_direction(direction), size_value)
		if next_blank < 0 or next_blank >= tiles.size() or not _adjacent(blank, next_blank, size_value):
			return {"ok": false, "message": "第 %s 步空格越界" % (index + 1)}
		var value := int(tiles[next_blank])
		tiles[blank] = value
		tiles[next_blank] = 0
		blank = next_blank
	for index in tiles.size() - 1:
		if int(tiles[index]) != index + 1:
			return {"ok": false, "message": "最后没有回到数字顺序"}
	if int(tiles.back()) != 0:
		return {"ok": false, "message": "最后空格不在右下角"}
	return {"ok": true, "message": ""}


func _reject_restore() -> bool:
	state = {}
	level_definition = {}
	return false
