class_name ChessRules
extends GameSession

const COLS := 9
const ROWS := 10
const CELLS := COLS * ROWS
const NAMES := {
	"general": "将", "advisor": "士", "elephant": "象", "horse": "马",
	"chariot": "车", "cannon": "炮", "soldier": "卒",
}
const RED_NAMES := {
	"general": "帅", "advisor": "仕", "elephant": "相", "horse": "马",
	"chariot": "车", "cannon": "炮", "soldier": "兵",
}
var puzzle_definition: Dictionary = {}


func _start_row(row: int) -> Array:
	match row:
		0, 9:
			return ["chariot", "horse", "elephant", "advisor", "general", "advisor", "elephant", "horse", "chariot"]
		2, 7:
			return ["", "cannon", "", "", "", "", "", "cannon", ""]
		3, 6:
			return ["soldier", "", "soldier", "", "soldier", "", "soldier", "", "soldier"]
		_:
			return ["", "", "", "", "", "", "", "", ""]


func _row(index: int) -> int:
	return int(index / COLS)


func _col(index: int) -> int:
	return index % COLS


func _inside(row: int, col: int) -> bool:
	return row >= 0 and row < ROWS and col >= 0 and col < COLS


func _index(row: int, col: int) -> int:
	return row * COLS + col


func piece_at(position: int) -> Dictionary:
	return _piece_at_in(position, state.get("pieces", []))


func _piece_at_in(position: int, board: Array) -> Dictionary:
	if position < 0 or position >= CELLS:
		return {}
	for piece in board:
		if piece is Dictionary and int(piece.get("position", -1)) == position:
			return piece
	return {}


func piece_name(piece: Dictionary) -> String:
	var kind := str(piece.get("kind", ""))
	if int(piece.get("side", 0)) == 0 and RED_NAMES.has(kind):
		return str(RED_NAMES[kind])
	return str(NAMES.get(kind, "棋子"))


func side_name(side: int) -> String:
	return "红方" if side == 0 else "黑方"


func _start_classic() -> void:
	state.pieces.clear()
	for row in ROWS:
		var row_layout: Array = _start_row(row)
		for col in COLS:
			var kind := str(row_layout[col])
			if kind.is_empty():
				continue
			var side := 0 if row >= 6 else 1
			state.pieces.append({
				"id": "%s-%s-%s-%s" % [side, kind, row, col],
				"side": side, "kind": kind, "position": _index(row, col),
			})
	state.phase = "playing"
	state.turn = 0
	state.selected = -1
	state.winner = -1
	state.reason = ""
	state.reported = false
	state.moveCount = 0
	state.lastMove = {}
	state.history = []
	puzzle_definition = {}


func _start_puzzle(puzzle: Dictionary) -> void:
	puzzle_definition = puzzle.duplicate(true)
	state.pieces.clear()
	for entry in puzzle.get("pieces", []):
		if not entry is Dictionary:
			continue
		state.pieces.append({
			"id": str(entry.get("id", "puzzle-%s" % state.pieces.size())),
			"side": int(entry.get("side", 0)),
			"kind": str(entry.get("kind", "chariot")),
			"position": int(entry.get("position", -1)),
		})
	state.phase = "playing"
	state.turn = int(puzzle.get("turn", 0))
	state.selected = -1
	state.winner = -1
	state.reason = ""
	state.reported = false
	state.moveCount = 0
	state.lastMove = {}
	state.history = []


func create_session(context: Dictionary) -> Dictionary:
	super.create_session(context)
	state.merge({
		"chessVersion": 2, "modeId": str(context.get("modeId", "classic")),
		"phase": "playing", "pieces": [], "selected": -1, "turn": 0, "winner": -1,
		"reason": "", "reported": false, "moveCount": 0, "lastMove": {}, "history": [],
		"puzzle": context.get("puzzle", {}).duplicate(true),
	}, true)
	if str(state.modeId) == "puzzle":
		_start_puzzle(state.puzzle)
	else:
		_start_classic()
	return state


func restore(value: Dictionary) -> bool:
	var version := int(value.get("chessVersion", 0))
	if version not in [1, 2]:
		return false
	if not super.restore(value):
		return false
	if not str(state.get("modeId", "")) in ["classic", "puzzle"]:
		return false
	if not str(state.get("phase", "")) in ["playing", "finished"]:
		return false
	if not state.get("pieces") is Array or not state.get("history") is Array:
		return false
	if version == 1:
		return _restore_legacy(value)
	if not _valid_pieces(state.pieces, str(state.modeId) == "classic"):
		return false
	if not _whole(state.get("turn", -1)) or int(state.turn) not in [0, 1]:
		return false
	if not _whole(state.get("moveCount", -1)) or int(state.moveCount) < 0:
		return false
	if not state.get("puzzle", {}) is Dictionary:
		return false
	if state.pieces.size() > 32:
		return false
	if str(state.phase) == "playing" and (_find_general_in(0, state.pieces).is_empty() or _find_general_in(1, state.pieces).is_empty()):
		return false
	for step in state.history:
		if not step is Dictionary or not step.get("before") is Dictionary:
			return false
		var before: Dictionary = step.before
		if not before.get("pieces") is Array or not _valid_pieces(before.pieces, str(state.modeId) == "classic"):
			return false
		if not _whole(before.get("turn", -1)) or int(before.turn) not in [0, 1]:
			return false
		if not _whole(step.get("from", -1)) or not _whole(step.get("to", -1)):
			return false
		if int(step.from) not in range(CELLS) or int(step.to) not in range(CELLS):
			return false
	state.turn = int(state.turn)
	var selected_piece := piece_at(int(state.get("selected", -1)))
	if selected_piece.is_empty() or int(selected_piece.get("side", -1)) != state.turn:
		state.selected = -1
	if not state.get("lastMove") is Dictionary:
		state.lastMove = {}
	state.moveCount = int(state.moveCount)
	puzzle_definition = state.get("puzzle", {})
	return true


func _whole(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value))


func _valid_pieces(pieces: Array, classic: bool = false) -> bool:
	var seen_positions := {}
	var seen_ids := {}
	for piece in pieces:
		if not piece is Dictionary:
			return false
		var kind := str(piece.get("kind", ""))
		if not _whole(piece.get("position", -1)) or not _whole(piece.get("side", -1)):
			return false
		var position := int(piece.get("position", -1))
		var identifier := str(piece.get("id", ""))
		if not NAMES.has(kind) or position < 0 or position >= CELLS:
			return false
		if int(piece.get("side", -1)) not in [0, 1] or seen_positions.has(position) or identifier.is_empty() or seen_ids.has(identifier):
			return false
		if classic and not _valid_classic_identity(piece):
			return false
		seen_positions[position] = true
		seen_ids[identifier] = true
	return pieces.size() <= 32


func _valid_classic_identity(piece: Dictionary) -> bool:
	var parts := str(piece.get("id", "")).split("-")
	if parts.size() != 4 or str(parts[0]) not in ["0", "1"]:
		return false
	if not str(parts[2]).is_valid_int() or not str(parts[3]).is_valid_int():
		return false
	var origin_row := int(parts[2])
	var origin_col := int(parts[3])
	if not _inside(origin_row, origin_col):
		return false
	var side := 0 if origin_row >= 6 else 1
	var kind := str(piece.get("kind", ""))
	if int(parts[0]) != side or int(piece.get("side", -1)) != side or str(parts[1]) != kind:
		return false
	var expected := str(_start_row(origin_row)[origin_col])
	return expected == kind or (kind == "cannon" and origin_row in [2, 7] and origin_col in [0, 8])


func _legacy_classic_start(saved: Array) -> Array:
	if saved.size() != 32:
		return []
	var initial: Array = []
	var counts := [0, 0]
	for entry in saved:
		if not entry is Dictionary:
			return []
		var parts := str(entry.get("id", "")).split("-")
		if parts.size() != 4 or not str(parts[2]).is_valid_int() or not str(parts[3]).is_valid_int():
			return []
		var row := int(parts[2])
		var col := int(parts[3])
		var kind := str(entry.get("kind", ""))
		if not _inside(row, col) or kind != str(parts[1]):
			return []
		var side := 0 if row >= 6 else 1
		if str(parts[0]) not in ["0", "1"]:
			return []
		if int(parts[0]) != side and not (kind == "soldier" and row == 6):
			return []
		var expected := str(_start_row(row)[col])
		if expected != kind and not (kind == "cannon" and row in [2, 7] and col in [0, 8]):
			return []
		counts[side] += 1
		initial.append({"id": "%s-%s-%s-%s" % [side, kind, row, col], "side": side, "kind": kind, "position": _index(row, col)})
	if counts != [16, 16] or not _valid_pieces(initial, true):
		return []
	return initial


func _normalized_legacy_pieces(saved: Array, classic: bool) -> Array:
	var normalized: Array = []
	for entry in saved:
		if not entry is Dictionary or not _whole(entry.get("position", -1)):
			return []
		var piece: Dictionary = entry.duplicate(true)
		if int(piece.position) == -999:
			continue
		if classic:
			var parts := str(piece.get("id", "")).split("-")
			if parts.size() != 4:
				return []
			var side := 0 if int(parts[2]) >= 6 else 1
			piece.id = "%s-%s-%s-%s" % [side, parts[1], parts[2], parts[3]]
			piece.side = side
		normalized.append(piece)
	return normalized


func _same_position(first: Array, second: Array) -> bool:
	if first.size() != second.size():
		return false
	for piece in first:
		var match_piece := _piece_at_in(int(piece.position), second)
		if match_piece.is_empty() or str(match_piece.id) != str(piece.id) or int(match_piece.side) != int(piece.side) or str(match_piece.kind) != str(piece.kind):
			return false
	return true


func _restore_legacy(value: Dictionary) -> bool:
	var classic := str(value.modeId) == "classic"
	var initial: Array = _legacy_classic_start(value.pieces) if classic else []
	if classic and initial.is_empty():
		return false
	var replay: ChessRules = get_script().new()
	replay.create_session(value)
	if classic:
		replay.state.pieces = initial
	for step in value.history:
		if not step is Dictionary or not _whole(step.get("from", -1)) or not _whole(step.get("to", -1)):
			return false
		if not bool(replay.handle_input({"type": "select", "position": int(step.from)}).get("ok", false)):
			return false
		if not bool(replay.handle_input({"type": "move", "to": int(step.to)}).get("ok", false)):
			return false
	var normalized := _normalized_legacy_pieces(value.pieces, classic)
	if not _valid_pieces(normalized, classic) or not _same_position(normalized, replay.state.pieces):
		return false
	if int(value.get("moveCount", -1)) != value.history.size():
		return false
	if int(value.get("turn", -1)) != int(replay.state.turn):
		return false
	if str(value.phase) != str(replay.state.phase):
		return false
	state = value.duplicate(true)
	state.merge(replay.state, true)
	state.sessionId = str(value.get("sessionId", replay.state.sessionId))
	state.reported = bool(value.get("reported", false))
	if value.get("recoverySnapshot") is Dictionary:
		state.recoverySnapshot = value.recoverySnapshot.duplicate(true)
	var selected := int(value.get("selected", -1))
	var selected_piece := piece_at(selected)
	state.selected = selected if not selected_piece.is_empty() and int(selected_piece.side) == int(state.turn) else -1
	if classic and value.history.is_empty():
		_start_classic()
	puzzle_definition = state.get("puzzle", {})
	return true


func _palace(side: int, row: int, col: int) -> bool:
	return col >= 3 and col <= 5 and (row >= 0 and row <= 2 if side == 1 else row >= 7 and row <= 9)


func _own_side(piece: Dictionary, side: int) -> bool:
	return not piece.is_empty() and int(piece.get("side", -1)) == side


func _pseudo_targets(position: int, board: Array) -> Array:
	var piece := _piece_at_in(position, board)
	if piece.is_empty():
		return []
	var side := int(piece.side)
	var kind := str(piece.kind)
	var row := _row(position)
	var col := _col(position)
	var result: Array = []
	var add := func(target_row: int, target_col: int) -> void:
		if not _inside(target_row, target_col):
			return
		var target := _index(target_row, target_col)
		var occupant := _piece_at_in(target, board)
		if occupant.is_empty() or int(occupant.side) != side:
			result.append(target)
	match kind:
		"chariot", "cannon":
			for direction in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
				var step := 1
				var screen := 0
				var direction_x := int(direction.x)
				var direction_y := int(direction.y)
				while true:
					var target_row: int = row + direction_x * step
					var target_col: int = col + direction_y * step
					if not _inside(target_row, target_col):
						break
					var target := _index(target_row, target_col)
					var occupant := _piece_at_in(target, board)
					if kind == "chariot":
						if occupant.is_empty():
							result.append(target)
						else:
							if int(occupant.side) != side:
								result.append(target)
							break
					elif screen == 0:
						if occupant.is_empty():
							result.append(target)
						else:
							screen = 1
					else:
						if not occupant.is_empty():
							if int(occupant.side) != side:
								result.append(target)
							break
					step += 1
		"horse":
			for move in [Vector2i(-2, -1), Vector2i(-2, 1), Vector2i(2, -1), Vector2i(2, 1), Vector2i(-1, -2), Vector2i(1, -2), Vector2i(-1, 2), Vector2i(1, 2)]:
				var move_x := int(move.x)
				var move_y := int(move.y)
				var leg_row := row
				var leg_col := col
				if absi(move_x) == 2:
					leg_row += 1 if move_x > 0 else -1
				else:
					leg_col += 1 if move_y > 0 else -1
				if not _piece_at_in(_index(leg_row, leg_col), board).is_empty():
					continue
				add.call(row + move_x, col + move_y)
		"elephant":
			for move in [Vector2i(-2, -2), Vector2i(-2, 2), Vector2i(2, -2), Vector2i(2, 2)]:
				var move_x := int(move.x)
				var move_y := int(move.y)
				var eye_row := row + int(move_x / 2)
				var eye_col := col + int(move_y / 2)
				if not _piece_at_in(_index(eye_row, eye_col), board).is_empty():
					continue
				var target_row: int = row + move_x
				var target_col: int = col + move_y
				var crossed := target_row <= 4 if side == 0 else target_row >= 5
				if _inside(target_row, target_col) and not crossed:
					add.call(target_row, target_col)
		"advisor":
			for move in [Vector2i(-1, -1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(1, 1)]:
				var target_row: int = row + int(move.x)
				var target_col: int = col + int(move.y)
				if _palace(side, target_row, target_col):
					add.call(target_row, target_col)
		"general":
			for move in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
				var target_row: int = row + int(move.x)
				var target_col: int = col + int(move.y)
				if _palace(side, target_row, target_col):
					add.call(target_row, target_col)
			var enemy_general := _find_general_in(1 - side, board)
			if not enemy_general.is_empty() and col == _col(int(enemy_general.position)):
				var target_row := _row(int(enemy_general.position))
				var between := 0
				var start := mini(row, target_row) + 1
				var finish := maxi(row, target_row)
				for check_row in range(start, finish):
					if not _piece_at_in(_index(check_row, col), board).is_empty():
						between += 1
				if between == 0:
					result.append(int(enemy_general.position))
		"soldier":
			var forward := -1 if side == 0 else 1
			add.call(row + forward, col)
			var crossed := row <= 4 if side == 0 else row >= 5
			if crossed:
				add.call(row, col - 1)
				add.call(row, col + 1)
	return result


func _find_general_in(side: int, board: Array) -> Dictionary:
	for piece in board:
		if piece is Dictionary and int(piece.side) == side and str(piece.kind) == "general":
			return piece
	return {}


func _moved_board(position: int, target: int, board: Array) -> Array:
	var result: Array = []
	for piece in board:
		var current_position := int(piece.position)
		if current_position == target:
			continue
		var copy: Dictionary = piece.duplicate(true)
		if current_position == position:
			copy.position = target
		result.append(copy)
	return result


func _in_check(side: int, board: Array) -> bool:
	var general := _find_general_in(side, board)
	if general.is_empty():
		return true
	var general_position := int(general.position)
	for piece in board:
		if piece is Dictionary and int(piece.side) != side and int(piece.position) >= 0:
			if general_position in _pseudo_targets(int(piece.position), board):
				return true
	return false


func legal_targets(position: int) -> Array:
	var piece := piece_at(position)
	if str(state.get("phase", "")) != "playing" or piece.is_empty() or int(piece.side) != int(state.turn):
		return []
	return _legal_targets_in(position, state.pieces)


func _legal_targets_in(position: int, board: Array) -> Array:
	var piece := _piece_at_in(position, board)
	if piece.is_empty():
		return []
	var side := int(piece.side)
	var result: Array = []
	for target in _pseudo_targets(position, board):
		var moved := _moved_board(position, int(target), board)
		if not _in_check(side, moved):
			result.append(target)
	return result


func _has_legal_move(side: int) -> bool:
	for piece in state.pieces:
		if int(piece.side) == side and not _legal_targets_in(int(piece.position), state.pieces).is_empty():
			return true
	return false


func _position_snapshot() -> Dictionary:
	var result := {}
	for key in ["pieces", "turn", "selected", "winner", "phase", "reason", "moveCount", "lastMove", "reported"]:
		var value: Variant = state.get(key)
		result[key] = value.duplicate(true) if value is Array or value is Dictionary else value
	return result


func can_select(piece: Dictionary) -> bool:
	return _own_side(piece, int(state.turn))


func piece_hint(piece: Dictionary) -> String:
	match str(piece.get("kind", "")):
		"chariot": return "车走直线，不能越过棋子"
		"horse": return "马走日字，先看看马腿有没有被挡住"
		"cannon": return "炮走直线，吃子时中间恰好隔一枚棋子"
		"elephant": return "象走田字，不能过河，也不能塞象眼"
		"advisor": return "士在九宫里斜走一格"
		"general": return "将帅在九宫里直走一格，不能被将军"
		"soldier": return "兵卒向前走一格，过河以后也能横着走"
	return "先点自己的棋子，再点红点或红圈"


func in_check(side: int) -> bool:
	return _in_check(side, state.get("pieces", []))


# Explanations reuse the real move generators. They never make a move legal.
func explain_move(origin: int, destination: int) -> Dictionary:
	var piece := piece_at(origin)
	if piece.is_empty():
		return {"message": "先点自己的棋子，再点亮起的位置", "cells": []}
	if destination < 0 or destination >= CELLS:
		return {"message": piece_hint(piece), "cells": [origin]}
	if destination in legal_targets(origin):
		return {"message": "松手后走到这里", "cells": [destination]}
	var occupant := piece_at(destination)
	if not occupant.is_empty() and int(occupant.side) == int(piece.side):
		return {"message": "这里是自己的棋子，可以改选它", "cells": [destination]}
	if destination in _pseudo_targets(origin, state.pieces):
		return {"message": "这样会让自己的将帅被将军，先保护将帅", "cells": [int(_find_general_in(int(piece.side), state.pieces).get("position", origin))]}
	var row_delta := _row(destination) - _row(origin)
	var col_delta := _col(destination) - _col(origin)
	var kind := str(piece.kind)
	if kind == "horse" and ((absi(row_delta) == 2 and absi(col_delta) == 1) or (absi(row_delta) == 1 and absi(col_delta) == 2)):
		var leg := _index(_row(origin) + (signi(row_delta) if absi(row_delta) == 2 else 0), _col(origin) + (signi(col_delta) if absi(col_delta) == 2 else 0))
		return {"message": "马腿被这枚棋子挡住了", "cells": [leg]}
	if kind == "elephant" and absi(row_delta) == 2 and absi(col_delta) == 2:
		var crossed := _row(destination) <= 4 if int(piece.side) == 0 else _row(destination) >= 5
		if crossed:
			return {"message": "象不能过河，试试自己这一边", "cells": [destination]}
		var eye := _index(_row(origin) + int(row_delta / 2), _col(origin) + int(col_delta / 2))
		return {"message": "象眼被这枚棋子挡住了", "cells": [eye]}
	if kind in ["chariot", "cannon"] and (row_delta == 0 or col_delta == 0):
		var between: Array = []
		var step_row := signi(row_delta)
		var step_col := signi(col_delta)
		var row := _row(origin) + step_row
		var col := _col(origin) + step_col
		while row != _row(destination) or col != _col(destination):
			var position := _index(row, col)
			if not piece_at(position).is_empty():
				between.append(position)
			row += step_row
			col += step_col
		if kind == "chariot":
			return {"message": "车的直路被挡住了，不能越过棋子", "cells": between}
		return {"message": "炮吃子时中间要恰好隔一枚棋子" if not occupant.is_empty() else "炮移动到空位时不能越过棋子", "cells": between if not between.is_empty() else [destination]}
	if kind in ["advisor", "general"] and not _palace(int(piece.side), _row(destination), _col(destination)):
		return {"message": "这枚棋子只能在九宫里走", "cells": [destination]}
	return {"message": piece_hint(piece), "cells": [destination]}


func handle_input(action: Dictionary) -> Dictionary:
	if state.phase != "playing":
		return {"ok": false, "message": "本局已经结束"}
	if str(action.get("type", "")) == "select":
		var piece := piece_at(int(action.get("position", -1)))
		if not _own_side(piece, int(state.turn)):
			return {"ok": false, "message": "请先选自己的棋子"}
		state.selected = int(piece.position)
		return {"ok": true, "message": piece_hint(piece)}
	if str(action.get("type", "")) == "deselect":
		state.selected = -1
		return {"ok": true}
	if str(action.get("type", "")) != "move":
		return {"ok": false, "message": "请点棋子或亮起的位置"}
	var from := int(state.get("selected", -1))
	var to := int(action.get("to", -1))
	if from < 0 or not (to in legal_targets(from)):
		var explanation := explain_move(from, to)
		return {"ok": false, "message": explanation.message, "cells": explanation.cells}
	var moving := piece_at(from)
	var captured := piece_at(to)
	var captured_kind := str(captured.get("kind", "")) if not captured.is_empty() else ""
	state.history.append({
		"from": from, "to": to, "side": state.turn, "piece": str(moving.kind),
		"movingId": str(moving.id), "captured": captured.duplicate(true), "before": _position_snapshot(),
	})
	state.pieces = _moved_board(from, to, state.pieces)
	state.lastMove = {"from": from, "to": to, "side": int(state.turn), "kind": str(moving.kind), "captured": captured_kind}
	state.selected = -1
	state.moveCount = int(state.moveCount) + 1
	if captured_kind == "general":
		state.phase = "finished"
		state.winner = int(state.turn)
		state.reason = "%s吃掉了对方将帅，获胜！" % side_name(int(state.turn))
	else:
		state.turn = 1 - int(state.turn)
		if not _has_legal_move(int(state.turn)):
			state.phase = "finished"
			state.winner = 1 - int(state.turn)
			state.reason = "%s将死，获胜！" % side_name(int(state.winner)) if _in_check(int(state.turn), state.pieces) else "%s无棋可走，%s获胜！" % [side_name(int(state.turn)), side_name(int(state.winner))]
	return {"ok": true, "captured": captured_kind, "check": str(state.phase) == "playing" and _in_check(int(state.turn), state.pieces)}


func undo_last_move() -> bool:
	if state.history.is_empty():
		return false
	var last: Dictionary = state.history.back()
	if not last.get("before") is Dictionary:
		return false
	var before: Dictionary = last.before
	if not before.get("pieces") is Array or not _valid_pieces(before.pieces, str(state.get("modeId", "")) == "classic"):
		return false
	state.history.pop_back()
	state.merge(before.duplicate(true), true)
	state.selected = -1
	state.reported = false
	return true
