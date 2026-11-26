class_name TangramRules
extends GameSession

const PIECES := [
	"large_triangle", "large_triangle", "medium_triangle",
	"small_triangle", "small_triangle", "square", "parallelogram",
]
const PIECE_NAMES := {
	"large_triangle": "大三角",
	"medium_triangle": "中三角",
	"small_triangle": "小三角",
	"square": "正方形",
	"parallelogram": "平行四边形",
}
const SNAP_DISTANCE := 0.16
const VALID_ROTATIONS := [0, 1, 2, 3]

var target_pieces: Array = []
var piece_states: Array = []


func create_session(context: Dictionary) -> Dictionary:
	super.create_session(context)
	var level: Dictionary = context.get("level", {}) if context.get("level", {}) is Dictionary else {}
	target_pieces = level.get("targetPieces", []).duplicate(true) if level.get("targetPieces", []) is Array else []
	piece_states = []
	for index in PIECES.size():
		piece_states.append({
			"index": index,
			"kind": PIECES[index],
			"x": -1.0,
			"y": -1.0,
			"rotation": 0,
			"mirror": false,
			"placed": false,
			"slot": -1,
		})
	var hints_max := int(context.get("hintsMax", _tuning_int("hints", 3)))
	state.merge({
		"levelId": int(context.get("levelId", 1)),
		"levelTitle": str(level.get("title", "七巧板")),
		"levelBand": str(level.get("band", "easy")),
		"targetPieces": target_pieces,
		"pieces": piece_states,
		"selected": -1,
		"hints": 0,
		"hintsMax": hints_max,
		"mistakes": 0,
		"hintSlot": -1,
		"stars": 0,
		"winner": 0,
		"reason": "",
		"phase": "playing" if target_pieces.size() == PIECES.size() else "empty",
		"reported": false,
	}, true)
	return state


func restore(value: Dictionary) -> bool:
	if not super.restore(value):
		return false
	if not (str(state.get("phase", "")) in ["playing", "finished", "empty"]):
		return false
	if not state.get("targetPieces") is Array or not state.get("pieces") is Array:
		return false
	var targets: Array = state.targetPieces
	var pieces: Array = state.pieces
	if targets.size() != PIECES.size() or pieces.size() != PIECES.size():
		return false
	for target in targets:
		if not target is Dictionary or not str(target.get("kind", "")) in PIECES:
			return false
		if not _valid_position(target.get("x", -1.0), target.get("y", -1.0)):
			return false
		if not _valid_rotation(target.get("rotation", -1)):
			return false
		if not target.get("mirror", false) is bool:
			return false
	for piece in pieces:
		if not piece is Dictionary or not str(piece.get("kind", "")) in PIECES:
			return false
		if not _valid_position(piece.get("x", -1.0), piece.get("y", -1.0)):
			return false
		if not _valid_rotation(piece.get("rotation", -1)):
			return false
		if not piece.get("mirror", false) is bool:
			return false
		if not _valid_slot(piece.get("slot", -1)):
			return false
		if not piece.get("placed", false) is bool:
			return false
	state.selected = clampi(_integer(state.get("selected", -1)), -1, pieces.size() - 1)
	state.hints = maxi(0, _integer(state.get("hints", 0)))
	state.hintsMax = maxi(0, _integer(state.get("hintsMax", _tuning_int("hints", 3))))
	state.mistakes = maxi(0, _integer(state.get("mistakes", 0)))
	state.hintSlot = clampi(_integer(state.get("hintSlot", -1)), -1, targets.size() - 1)
	state.stars = clampi(_integer(state.get("stars", 0)), 0, 3)
	target_pieces = targets.duplicate(true)
	piece_states = pieces.duplicate(true)
	return true


func _tuning_int(key: String, fallback: int) -> int:
	var level := "normal"
	if not state.is_empty():
		level = str(state.get("difficulty", level))
	return int(GameTuning.value("tangram", level, key, fallback))


func _is_coop() -> bool:
	var players_value: Variant = state.get("players", [])
	return str(state.get("modeId", "classic")) == "classic" and players_value is Array and players_value.size() == 2


func _valid_position(x_value: Variant, y_value: Variant) -> bool:
	return _numeric(x_value) and _numeric(y_value) and float(x_value) >= -0.2 and float(x_value) <= 1.2 and float(y_value) >= -0.2 and float(y_value) <= 1.2


func _valid_rotation(value: Variant) -> bool:
	return _numeric(value) and int(value) in VALID_ROTATIONS and is_equal_approx(float(value), float(int(value)))


func _valid_slot(value: Variant) -> bool:
	return _numeric(value) and int(value) >= -1 and int(value) < PIECES.size() and is_equal_approx(float(value), float(int(value)))


func _numeric(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


func _integer(value: Variant) -> int:
	return int(value) if _numeric(value) else 0


func _piece(index: int) -> Dictionary:
	if index < 0 or index >= piece_states.size() or not piece_states[index] is Dictionary:
		return {}
	return piece_states[index]


func _target(index: int) -> Dictionary:
	if index < 0 or index >= target_pieces.size() or not target_pieces[index] is Dictionary:
		return {}
	return target_pieces[index]


func select_piece(index: int) -> Dictionary:
	if _piece(index).is_empty():
		return {"ok": false, "message": "先点一块七巧板"}
	state.selected = index
	state.hintSlot = -1
	return {"ok": true, "selected": index}


func place_piece(index: int, x: float, y: float) -> Dictionary:
	var piece := _piece(index)
	if piece.is_empty():
		return {"ok": false, "message": "这块七巧板找不到啦"}
	if not _valid_position(x, y):
		return {"ok": false, "message": "放到轮廓里面试试"}
	var old_slot := int(piece.get("slot", -1))
	if old_slot >= 0:
		piece.slot = -1
	var slot := _nearest_slot(str(piece.kind), x, y)
	piece.placed = true
	if slot >= 0:
		var target := _target(slot)
		piece.slot = slot
		piece.x = float(target.get("x", x))
		piece.y = float(target.get("y", y))
	else:
		piece.slot = -1
		piece.x = x
		piece.y = y
		state.mistakes = int(state.get("mistakes", 0)) + 1
	state.selected = -1
	state.hintSlot = -1
	_check_complete()
	return {
		"ok": true,
		"snapped": slot >= 0,
		"slot": slot,
		"message": "放好啦" if slot >= 0 else "再靠近轮廓一点点",
	}


func rotate_piece(index: int = -1) -> Dictionary:
	var target_index := index if index >= 0 else int(state.get("selected", -1))
	var piece := _piece(target_index)
	if piece.is_empty():
		return {"ok": false, "message": "先选一块七巧板"}
	piece.rotation = (int(piece.get("rotation", 0)) + 1) % 4
	state.selected = target_index
	state.hintSlot = -1
	_check_complete()
	return {"ok": true, "rotation": int(piece.rotation)}


func mirror_piece(index: int = -1) -> Dictionary:
	var target_index := index if index >= 0 else int(state.get("selected", -1))
	var piece := _piece(target_index)
	if piece.is_empty():
		return {"ok": false, "message": "先选平行四边形"}
	if str(piece.kind) != "parallelogram":
		return {"ok": false, "message": "只有平行四边形可以翻转"}
	piece.mirror = not bool(piece.get("mirror", false))
	state.selected = target_index
	state.hintSlot = -1
	_check_complete()
	return {"ok": true, "mirror": bool(piece.mirror)}


func hint() -> Dictionary:
	if int(state.get("hints", 0)) >= int(state.get("hintsMax", 3)):
		return {"ok": false, "message": "这一档难度的提示次数已经用完"}
	var slot := _first_unfilled_slot()
	if slot < 0:
		return {"ok": false, "message": "已经拼好了，不用提示啦"}
	state.hints = int(state.get("hints", 0)) + 1
	state.hintSlot = slot
	var target := _target(slot)
	return {
		"ok": true,
		"slot": slot,
		"x": float(target.get("x", 0.5)),
		"y": float(target.get("y", 0.5)),
		"message": "看，有一块正好放在这里",
	}


func reset_pieces() -> Dictionary:
	for index in piece_states.size():
		var piece: Dictionary = piece_states[index]
		piece.x = -1.0
		piece.y = -1.0
		piece.rotation = 0
		piece.mirror = false
		piece.placed = false
		piece.slot = -1
	state.selected = -1
	state.hintSlot = -1
	state.hints = 0
	state.mistakes = 0
	state.phase = "playing"
	return {"ok": true}


func stars() -> int:
	var hints := int(state.get("hints", 0))
	var mistakes := int(state.get("mistakes", 0))
	var three_mistakes := _tuning_int("threeStarMistakes", 0)
	var two_mistakes := _tuning_int("twoStarMistakes", 3)
	if hints == 0 and mistakes <= three_mistakes:
		return 3
	if hints <= 1 and mistakes <= two_mistakes:
		return 2
	return 1


func _nearest_slot(kind: String, x: float, y: float) -> int:
	var used := {}
	for piece in piece_states:
		var slot := int(piece.get("slot", -1))
		if slot >= 0:
			used[slot] = true
	var best := -1
	var best_distance := SNAP_DISTANCE
	for index in target_pieces.size():
		if used.has(index):
			continue
		var target: Dictionary = target_pieces[index]
		if str(target.get("kind", "")) != kind:
			continue
		var distance := Vector2(x - float(target.get("x", 0.0)), y - float(target.get("y", 0.0))).length()
		if distance <= best_distance:
			best = index
			best_distance = distance
	return best


func _first_unfilled_slot() -> int:
	for index in target_pieces.size():
		var target: Dictionary = target_pieces[index]
		var piece := _piece_for_slot(index)
		if piece.is_empty():
			return index
		if int(piece.get("rotation", 0)) != int(target.get("rotation", 0)) or bool(piece.get("mirror", false)) != bool(target.get("mirror", false)):
			return index
	return -1


func _piece_for_slot(slot: int) -> Dictionary:
	for piece in piece_states:
		if int(piece.get("slot", -1)) == slot:
			return piece
	return {}


func _check_complete() -> void:
	if str(state.get("phase", "")) != "playing":
		return
	for index in target_pieces.size():
		var target: Dictionary = target_pieces[index]
		var piece := _piece_for_slot(index)
		if piece.is_empty():
			return
		if str(piece.get("kind", "")) != str(target.get("kind", "")):
			return
		if int(piece.get("rotation", 0)) != int(target.get("rotation", 0)):
			return
		if bool(piece.get("mirror", false)) != bool(target.get("mirror", false)):
			return
	state.phase = "finished"
	state.winner = 0
	state.reason = "七块拼好啦！"
	state.stars = stars()
	state.hintSlot = -1


func handle_input(action: Dictionary) -> Dictionary:
	var kind := str(action.get("type", ""))
	if kind == "select":
		return select_piece(int(action.get("index", -1)))
	if kind == "place":
		return place_piece(int(action.get("index", -1)), float(action.get("x", -1.0)), float(action.get("y", -1.0)))
	if kind == "rotate":
		return rotate_piece(int(action.get("index", -1)))
	if kind == "mirror":
		return mirror_piece(int(action.get("index", -1)))
	if kind == "hint":
		return hint()
	if kind == "reset":
		return reset_pieces()
	return {"ok": false}
