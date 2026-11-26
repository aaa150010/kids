class_name SudokuRules
extends GameSession

var puzzle_definition: Dictionary = {}


func puzzle() -> Dictionary:
	return puzzle_definition


func size() -> int:
	return clampi(int(puzzle_definition.get("size", 9)), 4, 9)


func box_rows() -> int:
	return maxi(1, int(puzzle_definition.get("boxRows", 3)))


func box_cols() -> int:
	return maxi(1, int(puzzle_definition.get("boxCols", 3)))


func create_session(context: Dictionary) -> Dictionary:
	super.create_session(context)
	var definition: Dictionary = context.get("puzzle", {})
	if definition.is_empty():
		definition = {
			"id": "mini-01", "title": "四宫格入门 1", "size": 4, "boxRows": 2, "boxCols": 2,
			"givens": "4130324100131000", "solution": "4132324124131324", "difficulty": "easy",
		}
	puzzle_definition = definition.duplicate(true)
	var dimension := size()
	state.merge({
		"sudokuVersion": 1, "modeId": str(context.get("modeId", "classic")),
		"phase": "playing", "puzzleId": str(definition.get("id", "")),
		"title": str(definition.get("title", "数独")),
		"values": str(definition.get("givens", "")).substr(0, dimension * dimension).lpad(dimension * dimension, "0"),
		"givens": str(definition.get("givens", "")),
		"solution": str(definition.get("solution", "")),
		"selected": -1, "mistakes": 0, "hints": 0, "reported": false,
		"undos": 0, "hintsMax": maxi(0, int(context.get("hintsMax", 3))),
		"undosMax": maxi(0, int(context.get("undosMax", 3))),
		"lastNumber": 0, "hintCell": -1, "hintPreview": {}, "undo": [],
	}, true)
	return state


func restore(value: Dictionary) -> bool:
	if int(value.get("sudokuVersion", 0)) != 1:
		return false
	if not super.restore(value):
		return false
	if not str(state.get("phase", "")) in ["playing", "finished"]:
		return false
	var definition: Dictionary = state.get("puzzle", {})
	if definition.is_empty():
		var given_length := str(state.get("givens", "")).length()
		var restored_size := 4 if given_length == 16 else 9
		var restored_box := 2 if given_length == 16 else 3
		definition = {
			"id": str(state.get("puzzleId", "")), "title": str(state.get("title", "数独")),
			"size": restored_size,
			"boxRows": restored_box,
			"boxCols": restored_box,
			"givens": str(state.get("givens", "")), "solution": str(state.get("solution", "")),
		}
	puzzle_definition = definition.duplicate(true)
	var dimension := size()
	var values := str(state.get("values", ""))
	if values.length() != dimension * dimension:
		return false
	var givens := str(state.get("givens", ""))
	var solution := str(state.get("solution", ""))
	if givens.length() != dimension * dimension or solution.length() != dimension * dimension:
		return false
	for index in values.length():
		var digit := int(values[index])
		if digit < 0 or digit > dimension:
			return false
		var given_digit := int(givens[index])
		if given_digit < 0 or given_digit > dimension:
			return false
		if given_digit > 0 and digit != given_digit:
			return false
		var solution_digit := int(solution[index])
		if solution_digit < 1 or solution_digit > dimension:
			return false
	state.selected = clampi(int(state.get("selected", -1)), -1, dimension * dimension - 1)
	state.mistakes = maxi(0, int(state.get("mistakes", 0)))
	state.hints = maxi(0, int(state.get("hints", 0)))
	state.undos = maxi(0, int(state.get("undos", 0)))
	state.hintsMax = maxi(0, int(state.get("hintsMax", 3)))
	state.undosMax = maxi(0, int(state.get("undosMax", 3)))
	if not state.get("undo") is Array:
		state.undo = []
	if not state.get("hintPreview") is Dictionary:
		state.hintPreview = {}
	return true


func is_given(position: int) -> bool:
	var givens := str(state.get("givens", ""))
	return position >= 0 and position < givens.length() and int(givens[position]) != 0


func conflicts(position: int, digit: int) -> bool:
	if digit <= 0:
		return false
	var dimension := size()
	var row := int(position / dimension)
	var col := position % dimension
	var values := str(state.get("values", ""))
	for index in dimension * dimension:
		if index == position or int(values[index]) != digit:
			continue
		var other_row := int(index / dimension)
		var other_col := index % dimension
		if other_row == row or other_col == col:
			return true
		if int(other_row / box_rows()) == int(row / box_rows()) and int(other_col / box_cols()) == int(col / box_cols()):
			return true
	return false


func set_number(digit: int) -> Dictionary:
	if str(state.get("phase", "")) != "playing":
		return {"ok": false, "message": "这一局已经完成啦"}
	var position := int(state.get("selected", -1))
	if position < 0 or is_given(position):
		return {"ok": false, "message": "先选一个空格"}
	var values := str(state.get("values", ""))
	var characters := values.split("")
	var before := _cell_snapshot()
	if digit > 0:
		characters[position] = str(digit)
	else:
		characters[position] = "0"
	if "".join(characters) == values:
		return {"ok": true, "invalid": false, "complete": is_complete()}
	state.values = "".join(characters)
	state.lastNumber = digit
	state.hintCell = -1
	state.hintPreview = {}
	if digit > 0 and conflicts(position, digit):
		state.mistakes = int(state.mistakes) + 1
		_push_undo(before)
		return {"ok": true, "invalid": true}
	_push_undo(before)
	return {"ok": true, "invalid": false, "complete": is_complete()}


func is_complete() -> bool:
	var values := str(state.get("values", ""))
	var solution := str(state.get("solution", ""))
	if values.length() != solution.length():
		return false
	for index in values.length():
		if int(values[index]) == 0 or values[index] != solution[index]:
			return false
	return true


func finish() -> void:
	if str(state.get("phase", "")) == "finished":
		return
	state.phase = "finished"
	state.winner = 0
	state.reason = "数独完成！"


func hint() -> Dictionary:
	var analysis := hint_analysis()
	if not bool(analysis.get("ok", false)):
		return analysis
	return fill_hint(int(analysis.position), int(analysis.digit))


func hint_analysis() -> Dictionary:
	if str(state.get("phase", "")) != "playing":
		return {"ok": false, "message": "这一局已经完成啦"}
	if int(state.get("hints", 0)) >= int(state.get("hintsMax", 3)):
		return {"ok": false, "message": "这一档难度的提示次数已经用完。"}
	var values := str(state.get("values", ""))
	var solution := str(state.get("solution", ""))
	for index in values.length():
		var digit := int(values[index])
		if digit > 0 and not is_given(index) and conflicts(index, digit):
			state.selected = index
			state.hintCell = index
			var related := conflict_cells(index, digit)
			state.hintPreview = {"position": index, "digit": digit, "candidates": [], "related": related}
			state.hints = int(state.get("hints", 0)) + 1
			return {
				"ok": true, "position": index, "digit": digit, "candidates": [],
				"related": related, "reason": "这一格和关联格出现了相同的 %s，请先检查画圈的位置。" % digit,
			}
	var best_position := -1
	var best_candidates: Array = []
	for index in values.length():
		if values[index] != "0":
			continue
		var candidates := _candidates(index)
		if best_position < 0 or candidates.size() < best_candidates.size():
			best_position = index
			best_candidates = candidates
		if candidates.size() == 1:
			break
	if best_position < 0:
		return {"ok": false, "message": "没有空格需要提示"}
	var digit := int(str(solution[best_position])) if best_position < solution.length() else -1
	state.selected = best_position
	state.hintCell = best_position
	state.hintPreview = {"position": best_position, "digit": digit, "candidates": best_candidates, "related": []}
	state.hints = int(state.get("hints", 0)) + 1
	var reason := ""
	if best_candidates.size() == 1:
		reason = "这一格所在的行、列和小宫已经排除了其他数字，只剩 %s。" % digit
	elif best_candidates.is_empty():
		reason = "这一格目前的候选需要重新检查。可以点“帮我填一格”，再观察关联位置。"
	else:
		var candidate_texts: PackedStringArray = PackedStringArray()
		for candidate in best_candidates:
			candidate_texts.append(str(candidate))
		reason = "从候选最少的这一格开始：目前可能是 %s。找到了吗？可以点“帮我填一格”核对。" % "、".join(candidate_texts)
	return {
		"ok": true, "position": best_position, "digit": digit,
		"candidates": best_candidates, "related": [], "reason": reason,
	}


func fill_hint(position: int = -1, digit: int = -1) -> Dictionary:
	var preview: Dictionary = state.get("hintPreview", {})
	if preview.is_empty():
		return {"ok": false, "message": "先看一次提示，再填写"}
	if position < 0:
		position = int(preview.get("position", -1))
	if digit < 0:
		digit = int(preview.get("digit", -1))
	if position < 0 or position >= size() * size() or digit < 1 or digit > size():
		return {"ok": false, "message": "先看一次提示，再填写"}
	if str(state.get("values", ""))[position] != "0":
		return {"ok": false, "message": "这一格已经有数字了"}
	var before := _cell_snapshot()
	var characters := str(state.get("values", "")).split("")
	characters[position] = str(digit)
	state.values = "".join(characters)
	state.selected = position
	state.hintCell = position
	state.lastNumber = digit
	state.hintPreview = {}
	_push_undo(before)
	return {"ok": true, "position": position, "digit": digit, "complete": is_complete()}


func conflict_cells(position: int, digit: int) -> Array:
	var related: Array = [position] if position >= 0 else []
	if digit <= 0:
		return related
	var dimension := size()
	var row := int(position / dimension)
	var col := position % dimension
	var values := str(state.get("values", ""))
	for index in dimension * dimension:
		if index == position or int(values[index]) != digit:
			continue
		var other_row := int(index / dimension)
		var other_col := index % dimension
		if other_row == row or other_col == col:
			related.append(index)
		elif int(other_row / box_rows()) == int(row / box_rows()) and int(other_col / box_cols()) == int(col / box_cols()):
			related.append(index)
	return related


func undo_last() -> bool:
	if not state.get("undo") is Array or state.undo.is_empty():
		return false
	if int(state.get("undos", 0)) >= int(state.get("undosMax", 3)):
		return false
	var value: Variant = state.undo.pop_back()
	if not value is Dictionary or str(value.get("values", "")).length() != size() * size():
		return false
	_restore_cell_snapshot(value)
	state.undos = int(state.get("undos", 0)) + 1
	return true


func _candidates(position: int) -> Array:
	var result: Array = []
	for digit in range(1, size() + 1):
		if not conflicts(position, digit):
			result.append(digit)
	return result


func _cell_snapshot() -> Dictionary:
	return {
		"values": str(state.get("values", "")),
		"selected": int(state.get("selected", -1)),
		"mistakes": int(state.get("mistakes", 0)),
		"hints": int(state.get("hints", 0)),
		"lastNumber": int(state.get("lastNumber", 0)),
		"hintCell": int(state.get("hintCell", -1)),
	}


func _restore_cell_snapshot(value: Dictionary) -> void:
	state.values = str(value.get("values", state.get("values", "")))
	state.selected = int(value.get("selected", -1))
	state.mistakes = int(value.get("mistakes", 0))
	state.hints = int(value.get("hints", 0))
	state.lastNumber = int(value.get("lastNumber", 0))
	state.hintCell = int(value.get("hintCell", -1))
	state.hintPreview = {}


func _push_undo(value: Dictionary) -> void:
	state.undo.append(value)
	state.undo = state.undo.slice(maxi(0, state.undo.size() - 40))


func clear_cell() -> Dictionary:
	if str(state.get("phase", "")) != "playing":
		return {"ok": false, "message": "这一局已经完成啦"}
	var position := int(state.get("selected", -1))
	if position < 0 or is_given(position):
		return {"ok": false, "message": "先选一个自己填的格子"}
	return set_number(0)


