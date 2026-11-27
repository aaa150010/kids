class_name BoardRules
extends GameSession

const ANIMALS := {"elephant":8,"lion":7,"tiger":6,"leopard":5,"wolf":4,"dog":3,"cat":2,"rat":1}
const NAMES := {"elephant":"大象","lion":"狮子","tiger":"老虎","leopard":"豹子","wolf":"狼","dog":"狗","cat":"猫","rat":"老鼠","commander":"司令","general":"军长","division":"师长","brigade":"旅长","regiment":"团长","battalion":"营长","company":"连长","platoon":"排长","engineer":"工兵","mine":"地雷","bomb":"炸弹","flag":"军旗"}
const ARMY := {"commander":[9,1],"general":[8,1],"division":[7,2],"brigade":[6,2],"regiment":[5,2],"battalion":[4,2],"company":[3,3],"platoon":[2,3],"engineer":[1,3],"mine":[0,3],"bomb":[0,2],"flag":[0,1]}
const WATER := [12,13,14,21,22,23,39,40,41,48,49,50]
const TRAPS := [[18,28,36],[26,34,44]]
const DENS := [27,35]
const CAMPS := [11,13,17,21,23,36,38,42,46,48]
const HEADQUARTERS := [1,3,56,58]

func create_session(context: Dictionary) -> Dictionary:
	super.create_session(context)
	var hints_max := maxi(0, int(context.get("hintsMax", 2)))
	var undos_max := maxi(0, int(context.get("undosMax", 3)))
	state.merge({"turn":0,"pieces":[],"board":[],"selected":"","winner":-1,"reason":"","quietPlies":0,"moveCount":0,"hints":0,"undos":0,"hintsMax":hints_max,"undosMax":undos_max,"autoHintShown":false,"lineIndex":0,"mistakes":0,"winningLine":[],"lastMove":{},"log":[],"puzzleReplyFailed":false,"puzzleReplyError":"","factionSides":[0,1],"factionAssigned":true,"factionLastSides":[-1,-1]},true)
	var puzzle: Dictionary = context.get("puzzle",{})
	if not puzzle.is_empty():
		state.pieces = puzzle.get("pieces",[]).duplicate(true)
		state.board = puzzle.get("board",[]).duplicate()
	elif str(state.gameId) == "gomoku":
		state.board.resize(225)
		state.board.fill(-1)
	elif str(state.gameId) == "jungle":
		var setup := [["lion",0,0],["dog",0,10],["cat",0,46],["tiger",0,54],["rat",0,2],["leopard",0,20],["wolf",0,38],["elephant",0,56],["tiger",1,8],["cat",1,16],["dog",1,52],["lion",1,62],["elephant",1,6],["wolf",1,24],["leopard",1,42],["rat",1,60]]
		for entry in setup:
			state.pieces.append({"id":"%s-%s" % [entry[1],entry[0]],"kind":entry[0],"side":entry[1],"position":entry[2],"revealed":true})
	else:
		var positions: Array = []
		for position in 60:
			if not (position in CAMPS):
				positions.append(position)
		positions = random.shuffled(positions)
		var cursor := 0
		for side in 2:
			for kind in ARMY:
				for copy_index in int(ARMY[kind][1]):
					state.pieces.append({"id":"%s-%s-%s" % [side,kind,copy_index],"kind":kind,"side":side,"position":positions[cursor],"revealed":false})
					cursor += 1
	if str(state.gameId) == "military" and state.players.size() == 2 and state.get("puzzle", {}).is_empty():
		state.factionSides = [-1, -1]
		state.factionAssigned = false
		state.factionLastSides = [-1, -1]
	return state

func restore(value: Dictionary) -> bool:
	if not super.restore(value):
		return false
	var had_faction_sides := state.has("factionSides")
	var game := str(state.get("gameId",""))
	if not (game in ["gomoku", "jungle", "military"]):
		return false
	if not (str(state.get("phase", "")) in ["playing", "finished"]):
		return false
	if game == "gomoku":
		if not state.get("board") is Array or state.board.size() != 225:
			return false
		for cell in state.board:
			if not _numeric(cell) or int(cell) not in [-1,0,1] or not is_equal_approx(float(cell), float(int(cell))):
				return false
	else:
		if not state.get("pieces") is Array or state.pieces.size() > (16 if game == "jungle" else 50):
			return false
		if state.pieces.is_empty():
			return false
		var positions := {}
		var identifiers := {}
		for piece in state.pieces:
			if not piece is Dictionary:
				return false
			if not _whole(piece.get("side", -1)):
				return false
			if int(piece.get("side", -1)) not in [0,1]:
				return false
			if piece.has("position") and not _whole(piece.get("position")):
				return false
			if not piece.has("position") and (not _whole(piece.get("y", 0)) or not _whole(piece.get("x", 0))):
				return false
			piece.kind = str(piece.get("kind",piece.get("animal",piece.get("rank",""))))
			piece.position = int(piece.get("position",int(piece.get("y",0))*9+int(piece.get("x",0))))
			piece.revealed = bool(piece.get("revealed",true))
			var position := int(piece.position)
			var identifier := str(piece.get("id", ""))
			if identifier.is_empty() or position < 0 or position >= (63 if game == "jungle" else 60) or positions.has(position) or identifiers.has(identifier):
				return false
			if not (ANIMALS if game == "jungle" else ARMY).has(piece.kind):
				return false
			positions[position] = true
			identifiers[identifier] = true
			if game == "jungle" and position in WATER and piece.kind != "rat":
				return false
	state.merge({"history":[],"log":[],"selected":"","lineIndex":0,"hints":0,"undos":0,"hintsMax":2,"undosMax":3,"autoHintShown":false,"mistakes":0,"winningLine":[],"lastMove":{},"moveCount":0,"quietPlies":0,"puzzleReplyFailed":false,"puzzleReplyError":""},false)
	if game == "military" and state.players.size() == 2 and state.get("puzzle", {}).is_empty():
		var sides_valid: bool = state.get("factionSides") is Array and state.factionSides.size() == 2
		if sides_valid:
			for side in state.factionSides:
				if not _whole(side) or int(side) not in [-1, 0, 1]:
					sides_valid = false
					break
		if not sides_valid:
			if had_faction_sides:
				return false
			state.factionSides = [0, 1]
			state.factionAssigned = true
		state.factionAssigned = bool(state.get("factionAssigned", true))
		if state.factionAssigned and (int(state.factionSides[0]) < 0 or int(state.factionSides[1]) < 0 or int(state.factionSides[0]) == int(state.factionSides[1])):
			return false
		if not state.get("factionLastSides") is Array or state.factionLastSides.size() != 2:
			state.factionLastSides = [-1, -1]
		else:
			for side in state.factionLastSides:
				if not _whole(side) or int(side) not in [-1, 0, 1]:
					state.factionLastSides = [-1, -1]
					break
	else:
		state.factionSides = [0, 1]
		state.factionAssigned = true
		state.factionLastSides = [-1, -1]
	if not state.get("history") is Array:
		state.history = []
	else:
		var clean_history: Array = []
		for entry in state.history:
			if _valid_history_entry(entry, game):
				clean_history.append(entry)
		state.history = clean_history
	if not state.get("log") is Array:
		state.log = []
	else:
		state.log = state.log.filter(func(line): return line is String).slice(0, 40)
	var stored_puzzle: Dictionary = state.get("puzzle", {}) if state.get("puzzle", {}) is Dictionary else {}
	if not stored_puzzle.is_empty() and not stored_puzzle.get("line", []) is Array:
		return false
	var puzzle_line: Array = stored_puzzle.get("line", [])
	if not stored_puzzle.is_empty():
		for step in stored_puzzle.get("line", []):
			if not step is Dictionary or not _whole(step.get("to", -1)) or int(step.get("to", -1)) < 0 or int(step.get("to", -1)) >= (225 if game == "gomoku" else 63 if game == "jungle" else 60):
				return false
			if step.has("from") and (not _whole(step.get("from")) or int(step.from) < 0 or int(step.from) >= (63 if game == "jungle" else 60)):
				return false
		if not _whole(stored_puzzle.get("targetSteps", 1)) or _integer(stored_puzzle.get("targetSteps", 1)) < 1:
			return false
		if str(stored_puzzle.get("hint", "")).is_empty() or str(stored_puzzle.get("title", "")).is_empty():
			return false
		if str(state.get("phase", "")) == "playing" and state.lineIndex >= puzzle_line.size():
			return false
	state.puzzle = stored_puzzle
	state.lineIndex = clampi(_integer(state.get("lineIndex", 0)), 0, puzzle_line.size())
	state.moveCount = maxi(0, _integer(state.get("moveCount", 0)))
	state.quietPlies = maxi(0, _integer(state.get("quietPlies", 0)))
	state.hints = maxi(0, _integer(state.get("hints", 0)))
	state.undos = maxi(0, _integer(state.get("undos", 0)))
	state.hintsMax = maxi(0, _integer(state.get("hintsMax", 2)))
	state.undosMax = maxi(0, _integer(state.get("undosMax", 3)))
	state.mistakes = maxi(0, _integer(state.get("mistakes", 0)))
	state.puzzleReplyFailed = bool(state.get("puzzleReplyFailed", false))
	state.puzzleReplyError = str(state.get("puzzleReplyError", ""))
	state.turn = clampi(_integer(state.get("turn",0)),0,1)
	state.winner = clampi(_integer(state.get("winner", -1)), -1, 1)
	state.reason = str(state.get("reason", ""))
	var board_size := 225 if game == "gomoku" else 63 if game == "jungle" else 60
	var clean_line: Array = []
	if state.get("winningLine") is Array:
		for index in state.winningLine:
			if _whole(index) and int(index) >= 0 and int(index) < board_size:
				clean_line.append(int(index))
	state.winningLine = clean_line
	var saved_last: Variant = state.get("lastMove", {})
	var saved_to: Variant = saved_last.get("to", -1) if saved_last is Dictionary else -1
	var saved_from: Variant = saved_last.get("from", -1) if saved_last is Dictionary else -1
	if not saved_last is Dictionary or not _whole(saved_to) or int(saved_to) < 0 or int(saved_to) >= board_size:
		state.lastMove = {}
	elif saved_last.has("from") and (not _whole(saved_from) or int(saved_from) < 0 or int(saved_from) >= board_size):
		state.lastMove = {}
	else:
		state.lastMove = saved_last
		if not state.lastMove.get("captured", {}) is Dictionary:
			state.lastMove.captured = {}
	if not piece_by_id(str(state.get("selected", ""))).is_empty():
		state.selected = str(state.selected)
	else:
		state.selected = ""
	return str(state.get("phase","")) in ["playing","finished"]


func _numeric(value: Variant) -> bool:
	if value is int or value is float:
		return is_finite(float(value))
	if value is String:
		return value.is_valid_float()
	return false


func _whole(value: Variant) -> bool:
	return _numeric(value) and is_equal_approx(float(value), float(int(value)))


func _valid_history_entry(entry: Variant, game: String) -> bool:
	if not entry is Dictionary or not (str(entry.get("type", "")) in ["place", "move", "flip"]):
		return false
	var before: Variant = entry.get("before", {})
	if not before is Dictionary or str(before.get("gameId", "")) != game or not _whole(before.get("turn", -1)):
		return false
	if int(before.turn) not in [0,1] or not (str(before.get("phase", "")) in ["playing", "finished"]):
		return false
	if game == "gomoku":
		return before.get("board") is Array and before.board.size() == 225
	return before.get("pieces") is Array


func _integer(value: Variant) -> int:
	if value is int:
		return int(value)
	if value is float and is_finite(value):
		return int(value)
	if value is String and value.is_valid_float():
		return int(float(value))
	return 0

func piece_at(position: int) -> Dictionary:
	for piece in state.get("pieces",[]):
		if int(piece.position) == position:
			return piece
	return {}

func piece_by_id(identifier: String) -> Dictionary:
	for piece in state.get("pieces",[]):
		if str(piece.id) == identifier:
			return piece
	return {}


func player_side(player_index: int = -1) -> int:
	var index := int(state.turn) if player_index < 0 else player_index
	if str(state.get("gameId", "")) != "military" or bool(state.get("factionAssigned", true)):
		var sides: Array = state.get("factionSides", [0, 1])
		return int(sides[index]) if index >= 0 and index < sides.size() else index
	return -1


func player_for_side(side: int) -> int:
	if str(state.get("gameId", "")) == "military" and bool(state.get("factionAssigned", false)):
		var sides: Array = state.get("factionSides", [0, 1])
		for index in mini(sides.size(), state.players.size()):
			if int(sides[index]) == side:
				return index
		return -1
	return side


func can_select(piece: Dictionary) -> bool:
	if piece.is_empty() or not bool(piece.get("revealed", true)):
		return false
	if str(state.get("gameId", "")) == "military" and not bool(state.get("factionAssigned", true)):
		return false
	return int(piece.side) == player_side()

func handle_input(action: Dictionary) -> Dictionary:
	if state.phase != "playing":
		return {"ok":false,"message":"这一局已经结束。"}
	var destination := int(action.get("to",-1))
	if str(action.get("type","")) == "select":
		var selected := piece_at(destination)
		if str(state.gameId) == "military" and not bool(state.get("factionAssigned", true)):
			return {"ok":false,"message":"先翻两次同色棋子，确定自己的阵营。"}
		if not can_select(selected):
			return {"ok":false,"message":"选一枚自己的亮棋吧。"}
		state.selected = str(selected.id)
		return {"ok":true,"event":"select"}
	if str(state.gameId) == "gomoku":
		if destination < 0 or destination >= 225 or int(state.board[destination]) >= 0:
			return {"ok":false,"message":"请点空的交叉点。"}
		if not _puzzle_accepts(-1,destination):
			return {"ok":false,"message":"再观察一下目标，试试另一处。"}
		_push_history("place")
		state.board[destination] = int(state.turn)
		state.lastMove = {"to":destination,"side":state.turn,"kind":"stone"}
		state.winningLine = winning_line(destination)
		if state.winningLine.size() >= 5:
			_finish(int(state.turn),"连成五颗啦！")
		elif not state.board.has(-1):
			_finish(-1,"棋盘放满，这一局和棋。")
		_complete_action("落下一颗棋子")
		return {"ok":true,"event":"move"}
	var target := piece_at(destination)
	if str(state.gameId) == "military" and not target.is_empty() and not bool(target.revealed):
		if not state.get("puzzle",{}).is_empty():
			return {"ok":false,"message":"这一关练习移动亮棋。"}
		_push_history("flip")
		target.revealed = true
		state.selected = ""
		state.lastMove = {"to":destination,"kind":target.kind,"side":target.side,"flip":true}
		var faction_now := false
		if state.players.size() == 2 and not bool(state.get("factionAssigned", true)):
			var player := int(state.turn)
			var last_sides: Array = state.get("factionLastSides", [-1, -1])
			if int(last_sides[player]) == int(target.side):
				state.factionSides[player] = int(target.side)
				state.factionSides[1-player] = 1-int(target.side)
				state.factionAssigned = true
				state.factionLastSides = [-1, -1]
				faction_now = true
			else:
				last_sides[player] = int(target.side)
				state.factionLastSides = last_sides
		_complete_action("翻开了%s" % NAMES[target.kind])
		return {"ok":true,"event":"flip","factionAssigned":faction_now,"factionSide":int(target.side) if faction_now else -1}
	var moving := piece_by_id(str(state.get("selected","")))
	if moving.is_empty() or not (destination in legal_moves(moving)):
		return {"ok":false,"message":"点亮起的位置移动。"}
	var origin := int(moving.position)
	if not _puzzle_accepts(origin,destination):
		return {"ok":false,"message":"先看看本关目标，换一步试试。"}
	_push_history("move")
	var side := int(moving.side)
	state.lastMove = {"from":origin,"to":destination,"kind":moving.kind,"side":side,"captured":target.duplicate(true)}
	if not target.is_empty():
		if str(state.gameId) == "military":
			var result := resolve_battle(str(moving.kind),str(target.kind))
			if not bool(result.defenderSurvives):
				state.pieces.erase(target)
			if not bool(result.attackerSurvives):
				state.pieces.erase(moving)
			if bool(result.flagCaptured):
				_finish(side,"夺取了对方的军旗！")
		else:
			state.pieces.erase(target)
		state.quietPlies = 0
	else:
		state.quietPlies = int(state.quietPlies)+1
	moving.position = destination
	state.selected = ""
	if str(state.gameId) == "jungle" and destination == DENS[1-side]:
		_finish(side,"走进了对方的兽穴！")
	if state.phase == "playing" and not _has_actions(1-int(state.turn)):
		_finish(side,"对方没有可进行的动作了。")
	if int(state.quietPlies) >= 100 and str(state.gameId) == "jungle":
		_finish(-1,"连续五十回合没有吃子，这一局和棋。")
	_complete_action("%s%s" % [NAMES[moving.kind],"完成了移动" if target.is_empty() else "与" + str(NAMES[target.kind]) + "相遇"])
	return {"ok":true,"event":"move","lastMove":state.lastMove}

func _puzzle_accepts(origin: int, destination: int) -> bool:
	var puzzle: Dictionary = state.get("puzzle",{})
	if puzzle.is_empty():
		return true
	var line: Array = puzzle.get("line",[])
	var cursor := int(state.lineIndex)
	if cursor >= line.size():
		return false
	var expected: Dictionary = line[cursor]
	if destination != int(expected.to) or (expected.has("from") and origin != int(expected.from)):
		state.mistakes = int(state.mistakes)+1
		return false
	return true

func _push_history(action_type: String) -> void:
	var before := state.duplicate(true)
	before.erase("history")
	state.history.append({"before":before,"type":action_type})
	if state.history.size() > 24:
		state.history = state.history.slice(state.history.size() - 24)

func _complete_action(message: String) -> void:
	state.moveCount = int(state.moveCount)+1
	state.log.push_front(message)
	state.log = state.log.slice(0,40)
	var puzzle: Dictionary = state.get("puzzle",{})
	if not puzzle.is_empty():
		state.lineIndex = int(state.lineIndex)+1
	if not puzzle.is_empty() and int(state.lineIndex) >= puzzle.get("line",[]).size():
		_finish(0,"本关目标达成！")
	if state.phase == "playing":
		state.turn = 1-int(state.turn)

func _finish(side: int, reason: String) -> void:
	state.phase = "finished"
	state.winner = side
	state.reason = reason

func undo() -> bool:
	if state.phase != "playing" or state.history.is_empty() or str(state.history.back().type) == "flip":
		return false
	if int(state.undos) >= int(state.get("undosMax",3)):
		return false
	var history: Array = state.history.duplicate(true)
	var entry: Dictionary = history.pop_back()
	var count := int(state.undos)+1
	state = entry.before.duplicate(true)
	state.history = history
	state.undos = count
	return true


func undo_player_turn() -> bool:
	if state.phase != "playing" or state.history.is_empty() or str(state.history.back().type) == "flip":
		return false
	if int(state.undos) >= int(state.get("undosMax", 3)):
		return false
	var history: Array = state.history.duplicate(true)
	var steps := 1
	if not state.get("puzzle", {}).is_empty() and history.size() >= 2:
		var before_last: Dictionary = history.back().get("before", {})
		if int(before_last.get("turn", -1)) == 1:
			steps = 2
	var entry: Dictionary = history[history.size() - steps]
	var count := int(state.undos) + 1
	state = entry.before.duplicate(true)
	state.history = history.slice(0, history.size() - steps)
	state.undos = count
	return true

func winning_line(position: int) -> Array:
	var result: Array = []
	var row: int = int(position / 15)
	var col: int = position % 15
	var side := int(state.board[position])
	for direction: Vector2i in [Vector2i(1,0),Vector2i(0,1),Vector2i(1,1),Vector2i(1,-1)]:
		var line: Array = [position]
		for sign_value: int in [-1,1]:
			var next_row := int(row)+direction.y*sign_value
			var next_col := col+direction.x*sign_value
			while next_row >= 0 and next_row < 15 and next_col >= 0 and next_col < 15 and int(state.board[next_row*15+next_col]) == side:
				line.append(next_row*15+next_col)
				next_row += direction.y*sign_value
				next_col += direction.x*sign_value
		if line.size() >= 5:
			result = line
			break
	return result

func legal_moves(piece: Dictionary) -> Array:
	if not bool(piece.get("revealed",true)):
		return []
	return _jungle_moves(piece) if str(state.gameId) == "jungle" else _army_moves(piece)

func _jungle_moves(piece: Dictionary) -> Array:
	var result: Array = []
	var origin := int(piece.position)
	for direction: Vector2i in [Vector2i(1,0),Vector2i(-1,0),Vector2i(0,1),Vector2i(0,-1)]:
		var col := origin%9+direction.x
		var row := int(origin/9)+direction.y
		if piece.kind in ["lion","tiger"]:
			while col >= 0 and col < 9 and row >= 0 and row < 7 and row*9+col in WATER:
				if not piece_at(row*9+col).is_empty():
					col = -1
					break
				col += direction.x
				row += direction.y
		if col < 0 or col >= 9 or row < 0 or row >= 7:
			continue
		var destination := row*9+col
		if destination == DENS[int(piece.side)] or (destination in WATER and piece.kind != "rat"):
			continue
		var defender := piece_at(destination)
		if defender.is_empty() or (int(defender.side) != int(piece.side) and _animal_capture(piece,defender)):
			result.append(destination)
	return result

func _animal_capture(attacker: Dictionary, defender: Dictionary) -> bool:
	if (int(attacker.position) in WATER) != (int(defender.position) in WATER):
		return false
	if int(attacker.position) in WATER:
		return attacker.kind == "rat" and defender.kind == "rat"
	if int(defender.position) in TRAPS[int(attacker.side)]:
		return true
	if attacker.kind == "rat" and defender.kind == "elephant":
		return true
	if attacker.kind == "elephant" and defender.kind == "rat":
		return false
	return int(ANIMALS[attacker.kind]) >= int(ANIMALS[defender.kind])

func resolve_battle(attacker: String, defender: String) -> Dictionary:
	if defender == "flag":
		return {"attackerSurvives":attacker != "bomb","defenderSurvives":false,"flagCaptured":true}
	if attacker == "bomb" or defender == "bomb":
		return {"attackerSurvives":false,"defenderSurvives":false,"flagCaptured":false}
	if defender == "mine":
		return {"attackerSurvives":attacker == "engineer","defenderSurvives":attacker != "engineer","flagCaptured":false}
	var difference := int(ARMY[attacker][0])-int(ARMY[defender][0])
	return {"attackerSurvives":difference > 0,"defenderSurvives":difference < 0,"flagCaptured":false}

func road_neighbours(position: int) -> Array:
	var row := int(position/5)
	var col := position%5
	var result: Array = []
	for row_step: int in [-1,0,1]:
		for col_step: int in [-1,0,1]:
			var target_row := row+row_step
			var target_col := col+col_step
			if (row_step == 0 and col_step == 0) or target_row < 0 or target_row >= 12 or target_col < 0 or target_col >= 5:
				continue
			var target := target_row*5+target_col
			var diagonal := row_step != 0 and col_step != 0
			if (row == 5 and target_row == 6) or (row == 6 and target_row == 5):
				if diagonal or not (col in [0,2,4]):
					continue
			if diagonal and not (position in CAMPS) and not (target in CAMPS):
				continue
			result.append(target)
	return result

func rail_link(origin: int, destination: int) -> bool:
	var row := int(origin/5)
	var col := origin%5
	var target_row := int(destination/5)
	var target_col := destination%5
	if absi(row-target_row)+absi(col-target_col) != 1:
		return false
	if row == target_row:
		return row in [1,5,6,10]
	return (col == target_col and col in [0,4] and mini(row,target_row) >= 1 and maxi(row,target_row) <= 10) or (col == 2 and target_col == 2 and mini(row,target_row) == 5 and maxi(row,target_row) == 6)

func _can_land(piece: Dictionary, destination: int) -> bool:
	var defender := piece_at(destination)
	if defender.is_empty():
		return true
	return bool(defender.revealed) and int(defender.side) != int(piece.side) and not (destination in CAMPS)

func _army_moves(piece: Dictionary) -> Array:
	if piece.kind in ["mine","flag"] or int(piece.position) in HEADQUARTERS:
		return []
	var result: Array = []
	var origin := int(piece.position)
	for destination in road_neighbours(origin):
		if _can_land(piece,int(destination)):
			result.append(destination)
	if piece.kind == "engineer":
		var visited := {origin:true}
		var queue: Array = [origin]
		while not queue.is_empty():
			var current := int(queue.pop_front())
			for destination in road_neighbours(current):
				if visited.has(destination) or not rail_link(current,int(destination)):
					continue
				visited[destination] = true
				if _can_land(piece,int(destination)) and not (destination in result):
					result.append(destination)
				if piece_at(int(destination)).is_empty():
					queue.append(destination)
	else:
		for direction in [-5,5,-1,1]:
			var current := origin
			while current+direction >= 0 and current+direction < 60 and rail_link(current,current+direction):
				current += direction
				if _can_land(piece,current) and not (current in result):
					result.append(current)
				if not piece_at(current).is_empty():
					break
	return result

func _has_actions(player_index: int) -> bool:
	var faction_side := player_side(player_index)
	for piece in state.pieces:
		if not bool(piece.revealed) and str(state.gameId) == "military":
			return true
		if int(piece.side) == faction_side and not legal_moves(piece).is_empty():
			return true
	return false
