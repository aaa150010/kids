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
		"lastNumber": 0, "hintCell": -1,
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
	for index in values.length():
		var digit := int(values[index])
		if digit < 0 or digit > dimension:
			return false
	state.selected = clampi(int(state.get("selected", -1)), -1, dimension * dimension - 1)
	state.mistakes = maxi(0, int(state.get("mistakes", 0)))
	state.hints = maxi(0, int(state.get("hints", 0)))
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
	if digit > 0:
		characters[position] = str(digit)
	else:
		characters[position] = "0"
	state.values = "".join(characters)
	state.lastNumber = digit
	state.hintCell = -1
	if digit > 0 and conflicts(position, digit):
		state.mistakes = int(state.mistakes) + 1
		return {"ok": true, "invalid": true}
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
	if str(state.get("phase", "")) != "playing":
		return {"ok": false, "message": "这一局已经完成啦"}
	var values := str(state.get("values", ""))
	var solution := str(state.get("solution", ""))
	var candidates: Array = []
	for index in values.length():
		if values[index] == "0":
			candidates.append(index)
	if candidates.is_empty():
		return {"ok": false, "message": "没有需要填的格子"}
	var position := int(candidates[randi() % candidates.size()])
	var characters := values.split("")
	characters[position] = solution[position]
	state.values = "".join(characters)
	state.selected = position
	state.hintCell = position
	state.hints = int(state.hints) + 1
	state.lastNumber = int(str(solution[position]))
	return {"ok": true, "position": position, "digit": state.lastNumber, "complete": is_complete()}


func clear_cell() -> Dictionary:
	if str(state.get("phase", "")) != "playing":
		return {"ok": false, "message": "这一局已经完成啦"}
	var position := int(state.get("selected", -1))
	if position < 0 or is_given(position):
		return {"ok": false, "message": "先选一个自己填的格子"}
	return set_number(0)


