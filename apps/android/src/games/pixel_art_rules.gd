class_name PixelArtRules
extends GameSession

const VERSION := 1
const MODES := ["adventure", "classic"]
const BANDS := ["easy", "normal", "challenge"]
const ZOOM_LEVELS := [0.75, 1.0, 1.5, 2.0]
const MAX_HISTORY := 240
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
		return _empty_state(requested_level, mode, str(validation.get("message", "这张像素画还没有准备好")))
	if str(level.get("mode", "")) != mode:
		return _empty_state(requested_level, mode, "这张像素画的模式和当前游戏不一致")
	var players_value: Variant = context.get("players", [])
	var player_count: int = players_value.size() if players_value is Array else 0
	if mode == "adventure" and player_count != 1:
		return _empty_state(requested_level, mode, "单人画册需要一位小朋友")
	if mode == "classic" and player_count != 2:
		return _empty_state(requested_level, mode, "双人共画需要两位小朋友")
	level_definition = level
	var count := int(level.get("width", 0)) * int(level.get("height", 0))
	var painted: Array = []
	for _index in count:
		painted.append(0)
	state.merge({
		"pixelVersion": VERSION,
		"gameId": "pixel_art",
		"modeId": mode,
		"levelId": requested_level,
		"levelNumber": requested_level,
		"levelKey": str(level.get("id", "")),
		"levelTitle": str(level.get("title", "像素小画家")),
		"levelBand": str(level.get("band", "easy")),
		"level": level,
		"target": level.get("target", []).duplicate(),
		"painted": painted,
		"selectedColor": 1,
		"zoom": 1.0,
		"turn": 0,
		"moves": 0,
		"errors": 0,
		"hints": 0,
		"undos": 0,
		"restarts": 0,
		"history": [],
		"hintCells": [],
		"showcase": false,
		"phase": "playing",
		"winner": -1,
		"reason": "",
		"stars": 0,
		"reported": false,
	}, true)
	return state


func _empty_state(level_id: int, mode: String, message: String) -> Dictionary:
	state = {
		"pixelVersion": VERSION,
		"gameId": "pixel_art",
		"modeId": mode,
		"levelId": level_id,
		"levelNumber": level_id,
		"level": {},
		"target": [],
		"painted": [],
		"selectedColor": 1,
		"zoom": 1.0,
		"history": [],
		"hintCells": [],
		"phase": "empty",
		"loadError": message,
		"reason": message,
		"stars": 0,
		"reported": false,
	}
	return state


func handle_input(action: Dictionary) -> Dictionary:
	match str(action.get("type", "")):
		"paint":
			return paint(_int_value(action.get("index", -1), -1))
		"erase":
			return erase(_int_value(action.get("index", -1), -1))
		"select_color":
			return select_color(_int_value(action.get("color", -1), -1))
		"hint":
			return hint()
		"zoom":
			return set_zoom(float(action.get("zoom", state.get("zoom", 1.0))))
		"undo":
			return undo()
		"restart":
			return restart()
		"showcase":
			return set_showcase(bool(action.get("showcase", true)))
	return {"ok": false, "message": "这个操作现在不能用"}


func select_color(color_index: int) -> Dictionary:
	if str(state.get("phase", "")) == "empty":
		return {"ok": false, "message": str(state.get("loadError", "这张像素画还没有准备好"))}
	var colors: Array = level_definition.get("palette", [])
	if color_index < 1 or color_index > colors.size():
		return {"ok": false, "message": "这个颜色不在本张画稿的色板里"}
	state.selectedColor = color_index
	return {
		"ok": true,
		"event": "color",
		"color": color_index,
		"name": str(_color_name(color_index)),
	}


func paint(index: int) -> Dictionary:
	if str(state.get("phase", "")) == "empty":
		return {"ok": false, "message": str(state.get("loadError", "这张像素画还没有准备好"))}
	if str(state.get("phase", "")) == "finished":
		return {"ok": false, "message": "这张画已经完成啦"}
	var count := int(level_definition.get("width", 0)) * int(level_definition.get("height", 0))
	if index < 0 or index >= count:
		return {"ok": false, "message": "请点画布里的一个格子"}
	var selected := clampi(int(state.get("selectedColor", 1)), 1, level_definition.get("palette", []).size())
	var painted: Array = state.get("painted", []).duplicate()
	if painted.size() != count:
		return {"ok": false, "message": "画布记录不完整，请重新开始这张画"}
	if int(painted[index]) == selected:
		return {"ok": false, "message": "这一格已经是这个颜色啦，可以换一格"}
	_push_history()
	painted[index] = selected
	state.painted = painted
	state.moves = int(state.get("moves", 0)) + 1
	state.hintCells = []
	var target: Array = level_definition.get("target", [])
	var correct := index < target.size() and int(target[index]) == selected
	if not correct:
		state.errors = int(state.get("errors", 0)) + 1
	_advance_turn()
	if completed(painted, target):
		_finish()
		return {
			"ok": true,
			"event": "finished",
			"index": index,
			"color": selected,
			"correct": correct,
			"moves": int(state.get("moves", 0)),
			"turn": int(state.get("turn", 0)),
			"stars": int(state.get("stars", stars())),
		}
	return {
		"ok": true,
		"event": "painted" if correct else "wrong_color",
		"index": index,
		"color": selected,
		"correct": correct,
		"targetColor": int(target[index]) if index < target.size() else 0,
		"moves": int(state.get("moves", 0)),
		"turn": int(state.get("turn", 0)),
		"message": "" if correct else "颜色对不上色号，可以换正确颜色重涂，或用橡皮擦掉。",
	}


func erase(index: int) -> Dictionary:
	if str(state.get("phase", "")) == "empty":
		return {"ok": false, "message": str(state.get("loadError", "这张像素画还没有准备好"))}
	if str(state.get("phase", "")) == "finished":
		return {"ok": false, "message": "这张画已经完成啦"}
	var count := int(level_definition.get("width", 0)) * int(level_definition.get("height", 0))
	if index < 0 or index >= count:
		return {"ok": false, "message": "请点画布里的一个格子"}
	var painted: Array = state.get("painted", []).duplicate()
	if int(painted[index]) == 0:
		return {"ok": false, "message": "这一格本来就是空的"}
	_push_history()
	painted[index] = 0
	state.painted = painted
	state.moves = int(state.get("moves", 0)) + 1
	state.hintCells = []
	_advance_turn()
	return {
		"ok": true,
		"event": "erased",
		"index": index,
		"moves": int(state.get("moves", 0)),
		"turn": int(state.get("turn", 0)),
	}


func hint() -> Dictionary:
	if str(state.get("phase", "")) != "playing":
		return {"ok": false, "message": "这幅画已经完成啦，不用提示"}
	state.hints = int(state.get("hints", 0)) + 1
	var target: Array = level_definition.get("target", [])
	var painted: Array = state.get("painted", [])
	var next_index := -1
	for index in target.size():
		if index >= painted.size() or int(painted[index]) != int(target[index]):
			next_index = index
			break
	if next_index < 0:
		return {"ok": true, "event": "hint", "cells": [], "message": "每个格子都对啦，看看是不是已经完成。", "hints": int(state.hints)}
	var width := int(level_definition.get("width", 0))
	var height := int(level_definition.get("height", 0))
	var center_x := next_index % width
	var center_y := int(next_index / width)
	var cells: Array = []
	for y in range(maxi(0, center_y - 1), mini(height, center_y + 2)):
		for x in range(maxi(0, center_x - 1), mini(width, center_x + 2)):
			cells.append(y * width + x)
	state.hintCells = cells
	return {
		"ok": true,
		"event": "hint",
		"cells": cells,
		"color": int(target[next_index]),
		"name": str(_color_name(int(target[next_index]))),
		"message": "亮起的小区域里，第一格要用%s（色号 %s）。" % [
			str(_color_name(int(target[next_index]))),
			int(target[next_index]),
		],
		"hints": int(state.hints),
	}


func set_zoom(value: float) -> Dictionary:
	if str(state.get("phase", "")) == "empty":
		return {"ok": false, "message": "这张像素画还没有准备好"}
	var nearest := float(ZOOM_LEVELS[0])
	var best := INF
	for zoom_value in ZOOM_LEVELS:
		var distance := absf(float(zoom_value) - value)
		if distance < best:
			best = distance
			nearest = float(zoom_value)
	state.zoom = nearest
	return {"ok": true, "event": "zoom", "zoom": nearest}


func undo() -> Dictionary:
	if str(state.get("phase", "")) == "finished":
		return {"ok": false, "message": "这张画已经完成啦"}
	if str(state.get("phase", "")) != "playing":
		return {"ok": false, "message": "现在没有可以撤销的一下"}
	var history: Array = state.get("history", [])
	if history.is_empty():
		return {"ok": false, "message": "已经回到这张画的开头啦"}
	var previous_value: Variant = history.pop_back()
	if not previous_value is Dictionary:
		return {"ok": false, "message": "这一下记录不完整，先重新开始"}
	var previous: Dictionary = previous_value
	state.history = history
	state.painted = previous.get("painted", []).duplicate()
	state.selectedColor = int(previous.get("selectedColor", 1))
	state.turn = int(previous.get("turn", 0))
	state.moves = int(previous.get("moves", 0))
	state.errors = int(previous.get("errors", 0))
	state.undos = int(state.get("undos", 0)) + 1
	state.hintCells = []
	state.phase = "playing"
	state.reason = ""
	state.winner = -1
	state.stars = 0
	state.showcase = false
	return {
		"ok": true,
		"event": "undone",
		"moves": int(state.moves),
		"undos": int(state.undos),
		"turn": int(state.turn),
	}


func restart() -> Dictionary:
	if str(state.get("phase", "")) == "empty":
		return {"ok": false, "message": str(state.get("loadError", "这张画还没有准备好"))}
	var count := int(level_definition.get("width", 0)) * int(level_definition.get("height", 0))
	var painted: Array = []
	for _index in count:
		painted.append(0)
	state.painted = painted
	state.selectedColor = 1
	state.zoom = clampf(float(state.get("zoom", 1.0)), 0.75, 2.0)
	state.turn = 0
	state.moves = 0
	state.errors = 0
	state.hints = 0
	state.undos = 0
	state.restarts = int(state.get("restarts", 0)) + 1
	state.history = []
	state.hintCells = []
	state.showcase = false
	state.phase = "playing"
	state.reason = ""
	state.winner = -1
	state.stars = 0
	state.reported = false
	return {"ok": true, "event": "restarted"}


func set_showcase(value: bool) -> Dictionary:
	if str(state.get("phase", "")) not in ["playing", "finished"]:
		return {"ok": false, "message": "这张画还没有准备好"}
	state.showcase = value and str(state.get("phase", "")) == "finished"
	return {"ok": true, "event": "showcase", "showcase": bool(state.showcase)}


func stars() -> int:
	if str(state.get("phase", "")) != "finished":
		return 0
	var par := int(level_definition.get("parCells", 0))
	var moves := int(state.get("moves", 0))
	var hints := int(state.get("hints", 0))
	var errors := int(state.get("errors", 0))
	var undos := int(state.get("undos", 0))
	if moves <= par and hints == 0 and errors == 0 and undos == 0:
		return 3
	if moves <= par + 8 and hints <= 1 and errors <= 4 and undos <= 6:
		return 2
	return 1


func result() -> Dictionary:
	if str(state.get("phase", "")) != "finished":
		return {}
	return {
		"winner": int(state.get("winner", -1)),
		"reason": str(state.get("reason", "像素画画好啦")),
		"phase": "finished",
		"outcome": "played" if is_cooperative() else "win",
		"stars": int(state.get("stars", stars())),
		"moves": int(state.get("moves", 0)),
		"parCells": int(level_definition.get("parCells", 0)),
		"errors": int(state.get("errors", 0)),
		"hints": int(state.get("hints", 0)),
		"undos": int(state.get("undos", 0)),
		"width": int(level_definition.get("width", 0)),
		"height": int(level_definition.get("height", 0)),
		"levelId": int(state.get("levelId", 1)),
		"levelKey": str(level_definition.get("id", "")),
	}


func completed(painted: Array, target: Array) -> bool:
	if painted.size() != target.size() or painted.is_empty():
		return false
	for index in target.size():
		if int(painted[index]) != int(target[index]):
			return false
	return true


func snapshot() -> Dictionary:
	state.pixelVersion = VERSION
	if str(state.get("phase", "")) == "finished":
		state.stars = stars()
	return super.snapshot()


func restore(value: Dictionary) -> bool:
	if _strict_int(value.get("pixelVersion", null)) != VERSION:
		return false
	if not super.restore(value):
		return false
	if str(state.get("gameId", "")) != "pixel_art":
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
	var target_value: Variant = state.get("target", null)
	var painted_value: Variant = state.get("painted", null)
	var expected_target: Array = level.get("target", [])
	if not target_value is Array or target_value != expected_target:
		return _reject_restore()
	if not painted_value is Array or painted_value.size() != expected_target.size():
		return _reject_restore()
	var palette_size := (level.get("palette", []) as Array).size()
	for raw in painted_value:
		var color_index := _strict_int(raw)
		if color_index < 0 or color_index > palette_size:
			return _reject_restore()
	var selected := _strict_int(state.get("selectedColor", null))
	if selected < 1 or selected > palette_size:
		return _reject_restore()
	var zoom := -1.0
	if state.get("zoom") is int or state.get("zoom") is float:
		zoom = float(state.get("zoom"))
	var zoom_valid := false
	for allowed in ZOOM_LEVELS:
		if is_equal_approx(zoom, float(allowed)):
			zoom_valid = true
	if not zoom_valid:
		return _reject_restore()
	for field in ["turn", "moves", "errors", "hints", "undos", "restarts"]:
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
		var entry_painted: Variant = entry.get("painted", null)
		if not entry_painted is Array or entry_painted.size() != expected_target.size():
			return _reject_restore()
		for raw_color in entry_painted:
			var color_index := _strict_int(raw_color)
			if color_index < 0 or color_index > palette_size:
				return _reject_restore()
		var entry_selected := _strict_int(entry.get("selectedColor", null))
		if entry_selected < 1 or entry_selected > palette_size:
			return _reject_restore()
		var entry_turn := _strict_int(entry.get("turn", null))
		var entry_moves := _strict_int(entry.get("moves", null))
		var entry_errors := _strict_int(entry.get("errors", null))
		if entry_turn < 0 or entry_turn > (1 if mode == "classic" else 0) or entry_moves < 0 or entry_errors < 0:
			return _reject_restore()
		entry.painted = entry_painted.duplicate()
		entry.selectedColor = entry_selected
		entry.turn = entry_turn
		entry.moves = entry_moves
		entry.errors = entry_errors
	state.history = history
	var hint_value: Variant = state.get("hintCells", null)
	if not hint_value is Array:
		return _reject_restore()
	var seen_hint := {}
	for raw_index in hint_value:
		var hint_index := _strict_int(raw_index)
		if hint_index < 0 or hint_index >= expected_target.size() or seen_hint.has(hint_index):
			return _reject_restore()
		seen_hint[hint_index] = true
	if not state.get("showcase", false) is bool:
		return _reject_restore()
	var phase := str(state.get("phase", ""))
	if phase not in ["playing", "finished"]:
		return _reject_restore()
	if phase == "playing" and bool(state.get("reported", false)):
		return _reject_restore()
	var complete := completed(painted_value, expected_target)
	if phase == "finished":
		if not complete:
			return _reject_restore()
		state.stars = stars()
		state.winner = -1 if mode == "classic" else 0
		state.reason = "整张像素画都涂对啦。"
	else:
		if complete:
			return _reject_restore()
		state.stars = 0
		state.winner = -1
		state.reason = ""
		state.showcase = false
	if not state.get("reported", false) is bool:
		return _reject_restore()
	state.level = level
	state.selectedColor = selected
	state.zoom = zoom
	state.painted = painted_value.duplicate()
	state.target = expected_target.duplicate()
	return true


func current_player_index() -> int:
	return clampi(int(state.get("turn", 0)), 0, 1)


func is_cooperative() -> bool:
	return str(state.get("modeId", "adventure")) == "classic"


func palette() -> Array:
	return level_definition.get("palette", []).duplicate()


func color_name(index: int) -> String:
	return _color_name(index)


func _color_name(index: int) -> String:
	var names: Array = level_definition.get("colorNames", [])
	if index > 0 and index <= names.size():
		return str(names[index - 1])
	return "色号 %s" % index


func _advance_turn() -> void:
	if is_cooperative():
		state.turn = 1 - clampi(int(state.get("turn", 0)), 0, 1)
	else:
		state.turn = 0


func _finish() -> void:
	state.phase = "finished"
	state.winner = -1 if is_cooperative() else 0
	state.reason = "整张像素画都涂对啦。"
	state.stars = stars()
	state.hintCells = []


func _push_history() -> void:
	var history: Array = state.get("history", [])
	history.append({
		"painted": state.get("painted", []).duplicate(),
		"selectedColor": int(state.get("selectedColor", 1)),
		"turn": int(state.get("turn", 0)),
		"moves": int(state.get("moves", 0)),
		"errors": int(state.get("errors", 0)),
	})
	if history.size() > MAX_HISTORY:
		history = history.slice(history.size() - MAX_HISTORY)
	state.history = history


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
	var rows: Array = []
	var raw_rows: Variant = level.get("rows", [])
	if raw_rows is Array:
		for row_value in raw_rows:
			rows.append(str(row_value))
	level.rows = rows
	level.width = _int_value(level.get("width", rows[0].length() if not rows.is_empty() else 0), 0)
	level.height = _int_value(level.get("height", rows.size()), rows.size())
	var palette: Array = []
	var raw_palette: Variant = level.get("palette", [])
	if raw_palette is Array:
		for color in raw_palette:
			palette.append(str(color))
	level.palette = palette
	var names: Array = []
	var raw_names: Variant = level.get("colorNames", [])
	if raw_names is Array:
		for color_name_value in raw_names:
			names.append(str(color_name_value))
	while names.size() < palette.size():
		names.append("色号 %s" % (names.size() + 1))
	level.colorNames = names.slice(0, palette.size())
	var target: Array = []
	for row in rows:
		for index in str(row).length():
			var token := str(row).substr(index, 1)
			var code := token.unicode_at(0) - 48
			target.append(code if code >= 1 and code <= 9 else 0)
	level.target = target
	level.parCells = _int_value(level.get("parCells", target.size()), target.size())
	level.hint = str(level.get("hint", ""))
	level.narration = str(level.get("narration", ""))
	level.explanation = str(level.get("explanation", ""))
	return level


static func validate_catalog(value: Variant) -> Dictionary:
	var issues: Array[String] = []
	if not value is Dictionary:
		return {"ok": false, "issues": ["pixel_art.json 顶层必须是对象"], "validLevels": []}
	var data: Dictionary = value
	if _strict_int(data.get("schemaVersion", data.get("version", null))) != VERSION:
		issues.append("pixel_art.json 的 schemaVersion 必须是 %s" % VERSION)
	var levels_value: Variant = data.get("levels", null)
	if not levels_value is Array:
		return {"ok": false, "issues": ["pixel_art.json 缺少 levels 数组"], "validLevels": []}
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
			issues.append("第 %s 张画：%s" % [index + 1, str(validation.get("message", "格式不正确"))])
			continue
		var id := str(normalized.id)
		if ids.has(id):
			issues.append("像素画 id 重复：%s" % id)
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
	if levels_value.size() != 30:
		issues.append("像素画册应为 30 张，实际 %s 张" % levels_value.size())
	for band in BANDS:
		if int(counts["adventure"][band]) != 8:
			issues.append("adventure %s 应为 8 张，实际 %s 张" % [band, counts["adventure"][band]])
		if int(counts["classic"][band]) != 2:
			issues.append("classic %s 应为 2 张，实际 %s 张" % [band, counts["classic"][band]])
	return {"ok": issues.is_empty(), "issues": issues, "validLevels": valid_levels, "counts": counts}


static func validate_level(raw: Variant) -> Dictionary:
	if not raw is Dictionary:
		return {"ok": false, "message": "像素画关卡必须是对象"}
	var level := _normalize_level(raw)
	var identifier := str(level.get("id", "未命名像素画"))
	if identifier.strip_edges().is_empty():
		return {"ok": false, "message": "像素画关卡缺少 id"}
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
	if width < 8 or height < 8 or width > 16 or height > 16:
		return {"ok": false, "message": "%s 的画布尺寸不合适" % identifier}
	var rows: Array = level.get("rows", [])
	if rows.size() != height:
		return {"ok": false, "message": "%s 的 rows 行数应为 %s" % [identifier, height]}
	var palette: Array = level.get("palette", [])
	if palette.size() < 2 or palette.size() > 9:
		return {"ok": false, "message": "%s 的色板应有 2–9 种颜色" % identifier}
	for tint in palette:
		if not Color.html_is_valid(str(tint)):
			return {"ok": false, "message": "%s 的色板颜色不合法" % identifier}
	var target: Array = level.get("target", [])
	if target.size() != width * height:
		return {"ok": false, "message": "%s 的格子数量不对" % identifier}
	var used := {}
	for row in rows:
		if str(row).length() != width:
			return {"ok": false, "message": "%s 的 rows 每行宽度应为 %s" % [identifier, width]}
		for index in str(row).length():
			var code := str(row).substr(index, 1).unicode_at(0) - 48
			if code < 1 or code > palette.size():
				return {"ok": false, "message": "%s 的色号超出色板" % identifier}
			used[code] = true
	for index in palette.size():
		if not used.has(index + 1):
			return {"ok": false, "message": "%s 的色板有未使用的颜色" % identifier}
	if int(level.get("parCells", 0)) != target.size():
		return {"ok": false, "message": "%s 的 parCells 应等于格子总数" % identifier}
	return {"ok": true, "message": "", "level": level}


func _reject_restore() -> bool:
	state = {}
	level_definition = {}
	return false
