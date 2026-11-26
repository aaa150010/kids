class_name MilitaryRules
extends GameSession

const ROWS := 13
const COLS := 5
const CELLS := ROWS * COLS
const MIDLINE := 6
const CAMPS := [11, 13, 17, 21, 23, 41, 43, 47, 51, 53]
const HEADQUARTERS := [1, 3, 61, 63]
const NAMES := {
	"flag": "军旗", "mine": "地雷", "bomb": "炸弹", "engineer": "工兵",
	"platoon": "排长", "company": "连长", "battalion": "营长", "colonel": "团长",
	"brigade": "旅长", "division": "师长", "corps": "军长", "commander": "司令",
}
const RANKS := {
	"flag": 0, "mine": 0, "bomb": 0, "engineer": 1, "platoon": 2, "company": 3,
	"battalion": 4, "colonel": 5, "brigade": 6, "division": 7, "corps": 8,
	"commander": 9,
}

var rails: Dictionary = {}


func _ensure_rails() -> void:
	if not rails.is_empty():
		return
	for row in [1, 5, 7, 11]:
		for col in 4:
			_add_rail(row * COLS + col, row * COLS + col + 1)
	for col in [0, 4]:
		for row in range(1, 11):
			_add_rail(row * COLS + col, (row + 1) * COLS + col)
	for row in [5, 6]:
		_add_rail(row * COLS + 2, (row + 1) * COLS + 2)


func _add_rail(first: int, second: int) -> void:
	if not rails.has(first):
		rails[first] = []
	if not rails.has(second):
		rails[second] = []
	if not (second in rails[first]):
		rails[first].append(second)
	if not (first in rails[second]):
		rails[second].append(first)


func _row(index: int) -> int:
	return int(index / COLS)


func _col(index: int) -> int:
	return index % COLS


func _inside(row: int, col: int) -> bool:
	return row >= 0 and row < ROWS and col >= 0 and col < COLS


func _orthogonal(index: int) -> Array:
	var result: Array = []
	var row := _row(index)
	var col := _col(index)
	for offset in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
		var next_row: int = row + int(offset.x)
		var next_col: int = col + int(offset.y)
		if _inside(next_row, next_col):
			result.append(next_row * COLS + next_col)
	return result


func _reachable_steps(index: int) -> Array:
	_ensure_rails()
	var result: Dictionary = {}
	for target in _orthogonal(index):
		if _row(target) != MIDLINE:
			result[target] = true
	var row := _row(index)
	var col := _col(index)
	if row == 5 and col in [0, 2, 4]:
		result[7 * COLS + col] = true
	elif row == 7 and col in [0, 2, 4]:
		result[5 * COLS + col] = true
	if index in CAMPS:
		for row_offset in [-1, 1]:
			for col_offset in [-1, 1]:
				var next_row: int = row + int(row_offset)
				var next_col: int = col + int(col_offset)
				if _inside(next_row, next_col):
					result[next_row * COLS + next_col] = true
	else:
		for target in _orthogonal(index):
			if target in CAMPS:
				result[target] = true
		for row_offset in [-1, 1]:
			for col_offset in [-1, 1]:
				var next_row: int = row + int(row_offset)
				var next_col: int = col + int(col_offset)
				if _inside(next_row, next_col) and (next_row * COLS + next_col) in CAMPS:
					result[next_row * COLS + next_col] = true
	var clean: Array = []
	for target in result:
		if _row(int(target)) != MIDLINE:
			clean.append(int(target))
	return clean


func _rail_path(start: int, finish: int) -> Array:
	_ensure_rails()
	if start == finish:
		return [start]
	var queue: Array = [start]
	var previous := {start: -1}
	var cursor := 0
	while cursor < queue.size():
		var current: int = queue[cursor]
		cursor += 1
		for next in rails.get(current, []):
			var target := int(next)
			if previous.has(target):
				continue
			previous[target] = current
			if target == finish:
				var path: Array = [finish]
				var walk := target
				while int(previous[walk]) >= 0:
					walk = int(previous[walk])
					path.push_front(walk)
				return path
			var occupied := not piece_at(target).is_empty()
			if not occupied:
				queue.append(target)
	return []


func _rail_straight(start: int, finish: int) -> bool:
	_ensure_rails()
	var start_row := _row(start)
	var start_col := _col(start)
	var finish_row := _row(finish)
	var finish_col := _col(finish)
	if start_row != finish_row and start_col != finish_col:
		return false
	if start_row == finish_row:
		var step := 1 if finish_col > start_col else -1
		var current := start_col
		while current != finish_col:
			var next_col := current + step
			var first := start_row * COLS + current
			var second := start_row * COLS + next_col
			if not (second in rails.get(first, [])):
				return false
			if second != finish and not piece_at(second).is_empty():
				return false
			current = next_col
		return true
	var row_step := 1 if finish_row > start_row else -1
	var row_cursor := start_row
	while row_cursor != finish_row:
		var next_row := row_cursor + row_step
		var first := row_cursor * COLS + start_col
		var second := next_row * COLS + start_col
		if not (second in rails.get(first, [])):
			return false
		if second != finish and not piece_at(second).is_empty():
			return false
		row_cursor = next_row
	return true


func _movement_targets(index: int) -> Array:
	var piece := piece_at(index)
	if piece.is_empty() or str(piece.kind) in ["flag", "mine"]:
		return []
	var result: Array = []
	var seen: Dictionary = {}
	var add := func(target: int) -> void:
		if target == index or _row(target) == MIDLINE or seen.has(target):
			return
		var occupant := piece_at(target)
		if not occupant.is_empty():
			if int(occupant.side) == int(piece.side) or target in CAMPS:
				return
		seen[target] = true
		result.append(target)
	if index in HEADQUARTERS:
		for target in _orthogonal(index):
			add.call(target)
		return result
	if str(piece.kind) == "engineer":
		for target in CELLS:
			if _row(target) == MIDLINE:
				continue
			var path := _rail_path(index, target)
			if path.size() < 2:
				continue
			var blocked := false
			for step in path.slice(1, path.size() - 1):
				if not piece_at(int(step)).is_empty():
					blocked = true
					break
			if not blocked:
				add.call(target)
	else:
		for target in CELLS:
			if _row(target) == MIDLINE or target == index:
				continue
			if _rail_straight(index, target):
				add.call(target)
	for target in _reachable_steps(index):
		add.call(int(target))
	return result


func _make_piece(side: int, kind: String, position: int, suffix: String) -> Dictionary:
	return {"id": "%s-%s-%s" % [side, kind, suffix], "side": side, "kind": kind, "position": position}


func _formation_pieces(side: int, formation: Dictionary) -> Array:
	var result: Array = []
	var cells: Array = formation.get("cells", [])
	for entry in cells:
		if not entry is Array or entry.size() != 2:
			continue
		var logical_index := int(entry[0])
		var row := _row(logical_index)
		var col := _col(logical_index)
		var target_row := row if side == 0 else 12 - row
		var target := target_row * COLS + col
		result.append(_make_piece(side, str(entry[1]), target, str(logical_index)))
	return result


func _start_classic() -> void:
	var formations := ContentDB.military_formations()
	if formations.size() < 3:
		state.phase = "finished"
		state.reason = "军棋阵法数据缺失"
		return
	state.pieces.clear()
	for side in 2:
		var formation: Dictionary = formations[int(state.formations[side]) % formations.size()]
		state.pieces.append_array(_formation_pieces(side, formation))
	state.phase = "playing"
	state.turn = 0
	state.selected = -1
	state.needsHandoff = false
	state.handoffPlayer = 0
	state.setupDone = [true, true]
	state.revealAll = true
	state.lastMove = {}
	state.lastBattle = {}
	state.history = []
	state.moveCount = 0
	state.noCapturePlies = 0
	state.winner = -1
	state.reason = ""
	state.reported = false


func _start_puzzle(puzzle: Dictionary) -> void:
	state.pieces.clear()
	state.puzzleTargetSide = 1
	state.targetSteps = maxi(1, int(puzzle.get("targetSteps", 1)))
	for enemy in puzzle.get("pieces", []):
		if not enemy is Dictionary:
			continue
		var side := int(enemy.get("side", 1))
		var kind := str(enemy.get("kind", "flag"))
		if kind == "flag" and side != 0:
			state.puzzleTargetSide = side
		state.pieces.append({
			"id": str(enemy.get("id", "puzzle-%s" % state.pieces.size())),
			"side": side,
			"kind": kind,
			"position": int(enemy.get("position", 0)),
		})
	state.phase = "playing"
	state.turn = 0
	state.selected = -1
	state.needsHandoff = false
	state.handoffPlayer = 0
	state.setupDone = [true, true]
	state.revealAll = true
	state.lastMove = {}
	state.lastBattle = {}
	state.history = []
	state.moveCount = 0
	state.noCapturePlies = 0
	state.winner = -1
	state.reason = ""
	state.reported = false
	state.puzzleBlocked = false
	state.puzzleMiss = false
	state.lastPuzzleReply = ""


func create_session(context: Dictionary) -> Dictionary:
	super.create_session(context)
	var hints_max := maxi(0, int(context.get("hintsMax", 2)))
	var undos_max := maxi(0, int(context.get("undosMax", 3)))
	var formations := ContentDB.military_formations()
	var formation_count := maxi(1, formations.size())
	var seed_value := int(state.get("seed", 0))
	var first_formation := ((seed_value % formation_count) + formation_count) % formation_count
	var second_formation := first_formation
	if formation_count > 1:
		var quotient := int(floor(float(seed_value) / 7.0))
		var offset := 1 + ((quotient % (formation_count - 1)) + (formation_count - 1)) % (formation_count - 1)
		second_formation = (first_formation + offset) % formation_count
	state.merge({
		"militaryVersion": 3, "modeId": str(context.get("modeId", "classic")),
		"phase": "playing", "pieces": [], "selected": -1, "turn": 0, "winner": -1,
		"reason": "", "needsHandoff": false, "handoffPlayer": 0,
		"setupDone": [true, true], "formations": [first_formation, second_formation], "revealAll": true,
		"lastMove": {}, "lastBattle": {}, "moveCount": 0, "noCapturePlies": 0,
		"history": [], "reported": false, "puzzle": context.get("puzzle", {}).duplicate(true),
		"hints": 0, "undos": 0, "hintsMax": hints_max, "undosMax": undos_max,
		"mistakes": 0, "puzzleBlocked": false, "puzzleMiss": false,
		"puzzleTargetSide": 1, "targetSteps": 1, "lastPuzzleReply": "",
	}, true)
	if str(state.modeId) == "puzzle":
		_start_puzzle(state.puzzle)
	else:
		_start_classic()
	return state


func restore(value: Dictionary) -> bool:
	if int(value.get("militaryVersion", 0)) not in [2, 3]:
		return false
	if not super.restore(value):
		return false
	if not (str(state.get("phase", "")) in ["setup", "playing", "finished"]):
		return false
	if not (str(state.get("modeId", "")) in ["classic", "puzzle"]):
		return false
	if not state.get("pieces") is Array or not state.get("history") is Array:
		return false
	if not _valid_piece_snapshot(state.pieces) or state.pieces.size() > 50:
		return false
	for entry in state.history:
		if not entry is Dictionary or not entry.get("pieces") is Array or not _valid_piece_snapshot(entry.pieces):
			return false
		if not (str(entry.get("phase", "")) in ["playing", "finished"]):
			return false
	if not state.get("formations") is Array or state.formations.size() != 2:
		state.formations = [0, 0]
	else:
		var formation_total := ContentDB.military_formations().size()
		for formation in state.formations:
			if not _whole_number(formation) or int(formation) < 0:
				return false
			if formation_total > 0 and int(formation) >= formation_total:
				return false
	if not state.get("setupDone") is Array or state.setupDone.size() != 2:
		state.setupDone = [true, true]
	state.turn = clampi(int(state.get("turn", 0)), 0, 1)
	state.selected = int(state.get("selected", -1))
	state.phase = str(state.get("phase", "playing"))
	state.needsHandoff = false
	state.handoffPlayer = clampi(int(state.get("handoffPlayer", state.turn)), 0, 1)
	state.moveCount = maxi(0, int(state.get("moveCount", 0)))
	state.noCapturePlies = maxi(0, int(state.get("noCapturePlies", 0)))
	state.hints = maxi(0, int(state.get("hints", 0)))
	state.undos = maxi(0, int(state.get("undos", 0)))
	state.hintsMax = maxi(0, int(state.get("hintsMax", 2)))
	state.undosMax = maxi(0, int(state.get("undosMax", 3)))
	state.mistakes = maxi(0, int(state.get("mistakes", 0)))
	state.puzzleBlocked = bool(state.get("puzzleBlocked", false))
	state.puzzleMiss = bool(state.get("puzzleMiss", false))
	state.lastPuzzleReply = str(state.get("lastPuzzleReply", ""))
	if not state.get("lastBattle") is Dictionary:
		state.lastBattle = {}
	if not state.get("lastMove") is Dictionary:
		state.lastMove = {}
	state.militaryVersion = 3
	if str(state.modeId) == "classic" and str(state.phase) == "setup":
		_start_classic()
	else:
		state.revealAll = true
	if str(state.modeId) == "puzzle":
		state.turn = 0
		var puzzle: Dictionary = state.get("puzzle", {}) if state.get("puzzle", {}) is Dictionary else {}
		state.targetSteps = maxi(1, int(puzzle.get("targetSteps", state.get("targetSteps", 1))))
		state.puzzleTargetSide = int(state.get("puzzleTargetSide", 1))
		if state.puzzleTargetSide not in [0, 1] or state.puzzleTargetSide == 0:
			state.puzzleTargetSide = 1
	var selected_position := int(state.get("selected", -1))
	var selected_piece := piece_at(selected_position)
	if not selected_piece.is_empty() and int(selected_piece.get("side", -1)) == int(state.turn):
		state.selected = selected_position
	else:
		state.selected = -1
	return true


func _whole_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and is_equal_approx(float(value), float(int(value)))


func _valid_piece_snapshot(pieces: Array) -> bool:
	var seen_positions := {}
	var seen_ids := {}
	for piece in pieces:
		if not piece is Dictionary:
			return false
		var kind := str(piece.get("kind", ""))
		var position := int(piece.get("position", -1))
		var identifier := str(piece.get("id", ""))
		if not RANKS.has(kind) or position < 0 or position >= CELLS or _row(position) == MIDLINE:
			return false
		if int(piece.get("side", -1)) not in [0, 1] or seen_positions.has(position) or identifier.is_empty() or seen_ids.has(identifier):
			return false
		seen_positions[position] = true
		seen_ids[identifier] = true
	return true


func piece_at(position: int) -> Dictionary:
	for piece in state.get("pieces", []):
		if int(piece.get("position", -1)) == position:
			return piece
	return {}


func piece_by_id(identifier: String) -> Dictionary:
	for piece in state.get("pieces", []):
		if str(piece.get("id", "")) == identifier:
			return piece
	return {}


func can_select(piece: Dictionary) -> bool:
	return not piece.is_empty() and int(piece.get("side", -1)) == int(state.get("turn", 0)) and str(state.get("phase", "")) == "playing"


func legal_targets(position: int) -> Array:
	if not can_select(piece_at(position)):
		return []
	return _movement_targets(position)


func piece_hint(piece: Dictionary) -> String:
	match str(piece.get("kind", "")):
		"flag": return "军旗守在这里，不能移动；保护好它"
		"mine": return "地雷不能移动，只有工兵能排雷"
		"engineer": return "工兵可以排雷，还能沿铁路转弯"
		"bomb": return "炸弹和碰到的对方棋子会一起退场"
	return "公路走一格，铁路可直走；行营里的棋子不能被攻击"


func explain_move(origin: int, destination: int) -> Dictionary:
	var piece := piece_at(origin)
	if piece.is_empty():
		return {"message": "先点自己的棋子，再点红点或红圈", "cells": []}
	if str(piece.kind) in ["flag", "mine"]:
		return {"message": piece_hint(piece), "cells": [origin]}
	if destination < 0 or destination >= CELLS:
		return {"message": piece_hint(piece), "cells": [origin]}
	var target := piece_at(destination)
	if not target.is_empty() and int(target.side) == int(piece.side):
		return {"message": "这里是自己的棋子，可以改选它", "cells": [destination]}
	if not target.is_empty() and destination in CAMPS:
		return {"message": "行营像保护伞，里面的棋子不能被攻击", "cells": [destination]}
	if destination in _movement_targets(origin):
		return engagement_preview(origin, destination)
	return {"message": "沿连着的公路走一格，或沿没有棋子阻挡的铁路走", "cells": [destination]}


func engagement_preview(origin: int, destination: int) -> Dictionary:
	var attacker := piece_at(origin)
	var defender := piece_at(destination)
	if attacker.is_empty() or destination not in _movement_targets(origin):
		return {"result": "blocked", "message": "这里暂时走不到", "cells": [destination], "icon": "hint"}
	if defender.is_empty():
		return {"result": "move", "message": "松手后走到这里", "cells": [destination], "icon": "next"}
	var result := _resolve_combat(attacker, defender)
	var message := ""
	match result:
		"capture": message = "可以夺取对方军旗"
		"attacker": message = "%s可以吃掉%s" % [str(NAMES[attacker.kind]), str(NAMES[defender.kind])]
		"defender": message = "%s会被%s挡住，自己的棋子会退场" % [str(NAMES[attacker.kind]), str(NAMES[defender.kind])]
		_: message = "%s和%s会一起退场" % [str(NAMES[attacker.kind]), str(NAMES[defender.kind])]
	return {"result": result, "message": message, "cells": [destination], "icon": "hint" if result in ["defender", "both"] else "check"}


func _snapshot_before() -> Dictionary:
	return {
		"pieces": state.pieces.duplicate(true),
		"turn": state.turn,
		"noCapturePlies": state.noCapturePlies,
		"winner": state.winner,
		"phase": state.phase,
		"reason": state.reason,
		"lastMove": state.lastMove.duplicate(true),
		"lastBattle": state.lastBattle.duplicate(true),
		"puzzleBlocked": bool(state.get("puzzleBlocked", false)),
		"puzzleMiss": bool(state.get("puzzleMiss", false)),
		"lastPuzzleReply": str(state.get("lastPuzzleReply", "")),
	}


func _finish_if_needed() -> void:
	if str(state.get("modeId", "")) == "puzzle":
		var target_side := int(state.get("puzzleTargetSide", 1))
		var target_flag := false
		for piece in state.pieces:
			if str(piece.get("kind", "")) == "flag" and int(piece.get("side", -1)) == target_side:
				target_flag = true
				break
		if not target_flag:
			state.phase = "finished"
			state.winner = 0
			state.reason = "夺取军旗，获得胜利"
			state.needsHandoff = false
			return
		var target_steps := maxi(1, int(state.get("targetSteps", 1)))
		if int(state.moveCount) >= target_steps:
			state.puzzleBlocked = true
			state.puzzleMiss = true
			state.reason = "还没夺旗，撤回再试一次"
		return
	var flags := {0: false, 1: false}
	for piece in state.pieces:
		if str(piece.kind) == "flag":
			flags[int(piece.side)] = true
	if not flags[0] or not flags[1]:
		state.phase = "finished"
		state.winner = 0 if not flags[1] else 1
		state.reason = "夺取军旗，获得胜利"
		state.needsHandoff = false
		return
	if str(state.modeId) == "classic":
		var possible := false
		for piece in state.pieces:
			if int(piece.side) == int(state.turn) and not _movement_targets(int(piece.position)).is_empty():
				possible = true
				break
		if not possible:
			state.phase = "finished"
			state.winner = 1 - int(state.turn)
			state.reason = "对方没有合法走法，获得胜利"
			state.needsHandoff = false
			return
	if int(state.noCapturePlies) >= 70:
		state.phase = "finished"
		state.winner = -1
		state.reason = "连续 70 手没有吃子，判和"
		state.needsHandoff = false


func _resolve_combat(attacker: Dictionary, defender: Dictionary) -> String:
	var attacker_kind := str(attacker.kind)
	var defender_kind := str(defender.kind)
	if defender_kind == "flag":
		return "capture"
	if attacker_kind == "bomb" or defender_kind == "bomb":
		return "both"
	if defender_kind == "mine":
		return "attacker" if attacker_kind == "engineer" else "defender"
	var attacker_rank := int(RANKS.get(attacker_kind, 0))
	var defender_rank := int(RANKS.get(defender_kind, 0))
	if attacker_rank > defender_rank:
		return "attacker"
	if attacker_rank < defender_rank:
		return "defender"
	return "both"


func _remove_piece(identifier: String) -> void:
	for index in state.pieces.size():
		if str(state.pieces[index].get("id", "")) == identifier:
			state.pieces.remove_at(index)
			return


func _move_piece(piece: Dictionary, target: int) -> void:
	piece.position = target


func _execute_move(target: int) -> Dictionary:
	var position := int(state.selected)
	var piece := piece_at(position)
	if piece.is_empty() or not (target in _movement_targets(position)):
		var explanation := explain_move(position, target)
		return {"ok": false, "message": explanation.message, "cells": explanation.cells}
	var before := _snapshot_before()
	var defender := piece_at(target)
	state.selected = -1
	state.lastBattle = {}
	var captured := false
	if defender.is_empty():
		_move_piece(piece, target)
		state.lastMove = {"from": position, "to": target}
	else:
		var result := _resolve_combat(piece, defender)
		state.lastBattle = {
			"from": position, "to": target,
			"attacker": str(piece.kind), "defender": str(defender.kind),
			"result": result, "side": int(piece.side),
		}
		captured = true
		match result:
			"capture":
				_remove_piece(str(defender.id))
				_move_piece(piece, target)
				state.lastMove = {"from": position, "to": target, "captured": defender.duplicate(true)}
			"attacker":
				_remove_piece(str(defender.id))
				_move_piece(piece, target)
				state.lastMove = {"from": position, "to": target, "captured": defender.duplicate(true)}
			"defender":
				_remove_piece(str(piece.id))
				state.lastMove = {"from": position, "to": target, "captured": piece.duplicate(true)}
			_:
				_remove_piece(str(piece.id))
				_remove_piece(str(defender.id))
				state.lastMove = {"from": position, "to": target, "captured": defender.duplicate(true)}
	state.history.append(before)
	state.lastMove.side = int(piece.side)
	state.history = state.history.slice(maxi(0, state.history.size() - 30))
	state.moveCount = int(state.moveCount) + 1
	state.noCapturePlies = 0 if captured else int(state.noCapturePlies) + 1
	if str(state.modeId) == "classic":
		state.turn = 1 - int(state.turn)
		state.handoffPlayer = int(state.turn)
	_finish_if_needed()
	if str(state.modeId) == "puzzle" and str(state.phase) == "playing":
		state.puzzleMiss = true
		state.lastPuzzleReply = "还没夺旗，撤回再试一次。"
		if int(state.moveCount) >= int(state.get("targetSteps", 1)):
			state.puzzleBlocked = true
	return {
		"ok": true,
		"battle": state.lastBattle.duplicate(true),
		"winner": int(state.winner),
		"finished": str(state.phase) == "finished",
		"puzzleMiss": bool(state.get("puzzleMiss", false)),
		"puzzleBlocked": bool(state.get("puzzleBlocked", false)),
	}


func undo_last_move() -> bool:
	if state.history.is_empty() or str(state.phase) == "finished":
		return false
	if int(state.get("undos", 0)) >= int(state.get("undosMax", 3)):
		return false
	var before: Dictionary = state.history.pop_back()
	state.pieces = before.pieces.duplicate(true)
	state.turn = int(before.turn)
	state.noCapturePlies = int(before.noCapturePlies)
	state.winner = int(before.winner)
	state.phase = str(before.phase)
	state.reason = str(before.reason)
	state.lastMove = before.lastMove.duplicate(true)
	state.lastBattle = before.lastBattle.duplicate(true)
	state.puzzleBlocked = bool(before.get("puzzleBlocked", false))
	state.puzzleMiss = bool(before.get("puzzleMiss", false))
	state.lastPuzzleReply = str(before.get("lastPuzzleReply", ""))
	state.selected = -1
	state.needsHandoff = false
	state.handoffPlayer = int(state.turn)
	state.moveCount = maxi(0, int(state.moveCount) - 1)
	state.undos = int(state.get("undos", 0)) + 1
	return true


func handle_input(action: Dictionary) -> Dictionary:
	var kind := str(action.get("type", ""))
	if str(state.phase) == "finished":
		return {"ok": false, "message": "这一局已经结束。"}
	if str(state.phase) != "playing":
		return {"ok": false}
	if kind == "select":
		var position := int(action.get("position", -1))
		var piece := piece_at(position)
		if not can_select(piece):
			return {"ok": false, "message": "先点自己的棋子。"}
		state.selected = position
		return {"ok": true, "select": position, "targets": _movement_targets(position)}
	if kind == "deselect":
		state.selected = -1
		return {"ok": true}
	if kind == "move":
		if str(state.get("modeId", "")) == "puzzle" and bool(state.get("puzzleBlocked", false)):
			return {"ok": false, "message": "这一步还没夺旗，先撤回再试。"}
		return _execute_move(int(action.get("to", -1)))
	if kind == "hint":
		var puzzle_value: Variant = state.get("puzzle", {})
		if not puzzle_value is Dictionary or puzzle_value.is_empty() or str(state.get("modeId", "")) != "puzzle":
			return {"ok": false, "message": "提示只在残局练习里使用。"}
		if int(state.get("hints", 0)) >= int(state.get("hintsMax", 2)):
			return {"ok": false, "message": "这一档难度的提示次数已经用完。"}
		state.hints = int(state.get("hints", 0)) + 1
		var text := str(state.get("puzzle", {}).get("hint", "先找一条能直达军旗的路线。"))
		state.lastPuzzleReply = text
		return {"ok": true, "message": text, "hint": text}
	if kind == "undo":
		return {"ok": undo_last_move()}
	return {"ok": false}


func current_player() -> int:
	return int(state.get("turn", 0))


func side_name(side: int) -> String:
	return "红方" if side == 0 else "蓝方"


func puzzle_target_side() -> int:
	return int(state.get("puzzleTargetSide", 1))


func puzzle_target_position() -> int:
	var target_side := puzzle_target_side()
	for piece in state.get("pieces", []):
		if str(piece.get("kind", "")) == "flag" and int(piece.get("side", -1)) == target_side:
			return int(piece.get("position", -1))
	return -1


func puzzle_is_blocked() -> bool:
	return str(state.get("modeId", "")) == "puzzle" and bool(state.get("puzzleBlocked", false))
