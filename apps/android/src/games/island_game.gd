class_name NativeIslandGame
extends NativeGameScreen

const START_CASH := 1500
const PASS_START_BONUS := 250
const QUIZ_REWARD := 200
const BONUS_REWARD := 150
const REST_REWARD := 50

var state: Dictionary = {}
var board_3d: IslandBoard3D
var reported := false
var random := SessionRng.new()
var control_panel: Control
var map_visible := false
var _rolling := false
var _turn_banner: Control
var _turn_banner_tween: Tween


func _ready() -> void:
	build_shell()
	var stored := SaveStore.load_state(game_id, players.map(func(player): return player.id))
	if _valid(stored):
		state = stored.duplicate(true)
		_sanitize_loaded_state()
		reported = bool(state.get("reported",false))
		difficulty = str(state.get("difficulty",difficulty))
		random = SessionRng.new(_integer(state.get("seed", 1)), _integer(state.get("rngState", 0)))
		if state.get("phase", "") == "result" and not bool(stored.get("resume", true)):
			_new_game()
	else:
		if mode_id == "adventure":
			_show_chapter_map()
			return
		_new_game()
	level_id = int(state.get("levelId",1))
	players = state.players.duplicate(true)
	random = SessionRng.new(_integer(state.get("seed",1)),_integer(state.get("rngState",0)))
	var properties := {}
	for key in state.get("properties",{}):
		properties[int(key)] = state.properties[key]
	state.properties = properties
	state.merge({"turnsCompleted":0,"challengesCompleted":0,"sessionId":"legacy-island-"+str(state.get("usedQuestions",[]).hash())},false)
	if str(state.get("view","board")) == "map":
		_show_chapter_map()
	else:
		_render()
	if not map_visible:
		_resume_pending_phase()
	call_deferred("begin_lesson")


func _valid(value: Dictionary) -> bool:
	if value.is_empty() or not _numeric(value.get("schemaVersion", 1)) or _integer(value.get("schemaVersion", 1)) != 1:
		return false
	if value.has("modeId") and str(value.get("modeId", "")) != mode_id:
		return false
	if value.has("seed") and not _numeric(value.get("seed")):
		return false
	if value.has("rngState") and not _numeric(value.get("rngState")):
		return false
	if not value.get("players") is Array or value.players.size() != players.size():
		return false
	var expected_ids := {}
	for player in players:
		expected_ids[str(player.id)] = true
	var saved_ids := {}
	for saved_player in value.players:
		if not saved_player is Dictionary:
			return false
		var player_id := str(saved_player.get("id", ""))
		if not expected_ids.has(player_id) or saved_ids.has(player_id):
			return false
		saved_ids[player_id] = true
		if str(saved_player.get("name", "")).strip_edges().is_empty():
			return false
		if not _numeric(saved_player.get("age", 0)) or _integer(saved_player.get("age", 0)) not in range(4, 13):
			return false
		var cash: Variant = saved_player.get("cash", 0)
		if not (cash is int or cash is float) or not is_finite(float(cash)):
			return false
		if not _numeric(saved_player.get("position", -1)) or int(saved_player.get("position", -1)) < 0 or int(saved_player.get("position", -1)) >= 32 or not is_equal_approx(float(saved_player.get("position", -1)), float(int(saved_player.get("position", -1)))):
			return false
		if not (saved_player.get("properties", []) is Array):
			return false
		for tile_id in saved_player.get("properties", []):
			if not _numeric(tile_id) or int(tile_id) < 0 or int(tile_id) >= 32 or not is_equal_approx(float(tile_id), float(int(tile_id))):
				return false
	if saved_ids.size() != expected_ids.size():
		return false
	var phase := str(value.get("phase", ""))
	if not (phase in ["ready", "rolling", "moving", "tile", "quiz", "challenge", "property", "notice", "result"]):
		return false
	if not _numeric(value.get("currentPlayer", -1)) or int(value.get("currentPlayer", -1)) < 0 or int(value.get("currentPlayer", -1)) >= players.size():
		return false
	if not _numeric(value.get("pendingTile", -1)) or int(value.get("pendingTile", -1)) < -1 or int(value.get("pendingTile", -1)) >= 32:
		return false
	if not _numeric(value.get("lastDie", 1)) or int(value.get("lastDie", 1)) not in range(1, 7):
		return false
	if not (value.get("usedQuestions", []) is Array) or not (value.get("log", []) is Array):
		return false
	var saved_properties: Variant = value.get("properties", {})
	if not saved_properties is Dictionary:
		return false
	for key in saved_properties:
		var key_text := str(key)
		if not key_text.is_valid_int() or int(key_text) < 0 or int(key_text) >= 32:
			return false
		if not saved_properties[key] is Dictionary:
			return false
		var property: Dictionary = saved_properties[key]
		if not _numeric(property.get("ownerId", -1)) or int(property.ownerId) < 0 or int(property.ownerId) >= players.size():
			return false
		if not _numeric(property.get("level", 0)) or int(property.level) not in [0,1,2,3]:
			return false
	if phase == "quiz":
		var quiz: Variant = value.get("quiz", {})
		if not quiz is Dictionary or not _valid_question(quiz.get("question", {})):
			return false
		if not _numeric(quiz.get("selected", -1)) or int(quiz.selected) < -1 or int(quiz.selected) > 2:
			return false
		if bool(quiz.get("answered", false)) and int(quiz.selected) not in [0,1,2]:
			return false
	if phase == "challenge":
		var challenge: Variant = value.get("challenge", {})
		if not challenge is Dictionary or not _valid_question(challenge.get("question", {})) or not (challenge.get("answers", {}) is Dictionary):
			return false
		if not _numeric(challenge.get("responder", -1)) or int(challenge.get("responder", -1)) < 0 or int(challenge.get("responder", -1)) > players.size():
			return false
		for responder in challenge.answers:
			if not str(responder).is_valid_int() or int(responder) < 0 or int(responder) >= players.size():
				return false
			if not _numeric(challenge.answers[responder]) or int(challenge.answers[responder]) not in [0,1,2]:
				return false
	if phase == "notice" and value.has("notice") and not value.notice is Dictionary:
		return false
	if phase in ["tile", "property"] and int(value.get("pendingTile", -1)) < 0:
		return false
	return true


func _valid_question(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	if not value.get("options") is Array or value.options.size() != 3:
		return false
	return _numeric(value.get("answer", -1)) and int(value.answer) in [0, 1, 2]


func _sanitize_loaded_state() -> void:
	state.currentPlayer = clampi(_integer(state.get("currentPlayer", 0)), 0, state.players.size() - 1)
	state.pendingTile = clampi(_integer(state.get("pendingTile", -1)), -1, 31)
	state.lastDie = clampi(_integer(state.get("lastDie", 1)), 1, 6)
	state.rollRemaining = clampf(_number(state.get("rollRemaining", 0.725), 0.725), 0.0, 0.725)
	state.moveRemaining = clampf(_number(state.get("moveRemaining", 0.18), 0.18), 0.0, 0.28)
	state.stepsRemaining = clampi(_integer(state.get("stepsRemaining", state.lastDie)), 0, 6)
	state.energy = maxi(0, _integer(state.get("energy", 0)))
	state.energyMax = maxi(1, _integer(state.get("energyMax", 8)))
	state.islandLevel = maxi(0, _integer(state.get("islandLevel", 0)))
	state.levelId = clampi(_integer(state.get("levelId", level_id)), 1, 12)
	state.maxRounds = clampi(_integer(state.get("maxRounds", 8)), 1, 12)
	state.round = clampi(_integer(state.get("round", 1)), 1, state.maxRounds + 1)
	state.energyMax = clampi(_integer(state.get("energyMax", 8)), 1, 8)
	state.energy = clampi(_integer(state.get("energy", 0)), 0, state.energyMax)
	state.turnsCompleted = maxi(0, _integer(state.get("turnsCompleted", 0)))
	state.challengesCompleted = maxi(0, _integer(state.get("challengesCompleted", 0)))
	state.finished = bool(state.get("finished", false))
	state.winnerIndex = clampi(_integer(state.get("winnerIndex", -1)), -1, state.players.size() - 1)
	state.reported = bool(state.get("reported", false))
	state.difficulty = GameTuning.normalize(state.get("difficulty", difficulty))
	state.notice = state.get("notice", {}) if state.get("notice") is Dictionary else {}
	if state.get("quiz") is Dictionary:
		state.quiz.selected = clampi(_integer(state.quiz.get("selected", -1)), -1, 2)
		state.quiz.answered = bool(state.quiz.get("answered", false))
		state.quiz.correct = bool(state.quiz.get("correct", false))
	if state.get("challenge") is Dictionary:
		state.challenge.responder = clampi(_integer(state.challenge.get("responder", 0)), 0, state.players.size())
		var clean_answers := {}
		for responder in state.challenge.get("answers", {}):
			clean_answers[str(responder)] = _integer(state.challenge.answers[responder])
		state.challenge.answers = clean_answers
	var clean_properties := {}
	for key in state.properties:
		var property_id := int(key)
		var property: Dictionary = state.properties[key]
		clean_properties[property_id] = {"ownerId": clampi(_integer(property.get("ownerId", 0)), 0, state.players.size() - 1), "level": clampi(_integer(property.get("level", 0)), 0, 3)}
	state.properties = clean_properties
	var used_questions: Variant = state.get("usedQuestions", [])
	state.usedQuestions = used_questions.filter(func(id): return id is String) if used_questions is Array else []
	var state_log: Variant = state.get("log", [])
	state.log = state_log.filter(func(line): return line is String).slice(0, 40) if state_log is Array else []
	for saved_player in state.players:
		saved_player.name = str(saved_player.get("name", "小朋友"))
		saved_player.age = clampi(_integer(saved_player.get("age", 8)), 4, 12)
		saved_player.avatar = str(saved_player.get("avatar", "🦊"))
		saved_player.color = str(saved_player.get("color", "#d56c29"))
		saved_player.character = saved_player.get("character", {}) if saved_player.get("character") is Dictionary else {}
		saved_player.cash = maxi(0, _integer(saved_player.get("cash", 0)))
		saved_player.position = clampi(_integer(saved_player.get("position", 0)), 0, 31)
		saved_player.correctCount = maxi(0, _integer(saved_player.get("correctCount", 0)))
		saved_player.wrongCount = maxi(0, _integer(saved_player.get("wrongCount", 0)))
		saved_player.wisdomStars = maxi(0, _integer(saved_player.get("wisdomStars", 0)))
		saved_player.eliminated = bool(saved_player.get("eliminated", false))
		var owned: Array = []
		for tile_id in saved_player.get("properties", []):
			var cleaned := _integer(tile_id)
			if cleaned >= 0 and cleaned < 32 and not (cleaned in owned):
				owned.append(cleaned)
		saved_player.properties = owned


func _numeric(value: Variant) -> bool:
	if value is int or value is float:
		return is_finite(float(value))
	if value is String:
		return value.is_valid_float()
	return false


func _integer(value: Variant) -> int:
	if value is int or value is float:
		return int(value)
	if value is String and value.is_valid_float():
		return int(float(value))
	return 0


func _number(value: Variant, fallback: float) -> float:
	if value is int or value is float:
		return float(value) if is_finite(float(value)) else fallback
	if value is String and value.is_valid_float():
		var parsed := float(value)
		return parsed if is_finite(parsed) else fallback
	return fallback


func _new_game() -> void:
	random = SessionRng.new(int(ContentDB.level(game_id,level_id).get("seed",Time.get_ticks_usec())) if mode_id == "adventure" else Time.get_ticks_usec())
	var characters: Array = ContentDB.characters()
	var start_cash := int(GameTuning.value(game_id,difficulty,"startCash",START_CASH))
	var player_state := []
	for index in players.size():
		var character: Dictionary = characters[index % characters.size()] if not characters.is_empty() else {}
		player_state.append({
			"id": str(players[index].id),
			"name": str(players[index].name),
			"age": int(players[index].age),
			"avatar": str(players[index].avatar),
			"color": str(players[index].color),
			"character": character,
			"cash": start_cash,
			"position": 0,
			"properties": [],
			"correctCount": 0,
			"wrongCount": 0,
			"wisdomStars": 0,
			"eliminated": false,
		})
	state = {
		"schemaVersion": 1,
		"players": player_state,
		"properties": {},
		"currentPlayer": 0,
		"round": 1,
		"maxRounds": 12 if players.size() == 2 else 8 if players.size() == 3 else 6,
		"phase": "ready",
		"lastDie": 1,
		"pendingTile": -1,
		"quiz": {},
		"challenge": {},
		"usedQuestions": [],
		"energy": 0,
		"energyMax": 8,
		"difficulty":difficulty,
		"startCash":start_cash,
		"passBonus":int(GameTuning.value(game_id,difficulty,"passBonus",PASS_START_BONUS)),
		"islandLevel": 0,
		"finished": false,
		"winnerIndex": -1,
		"log": [],
		"reported": false,
		"snapshotVersion":2,
		"modeId":mode_id,
		"levelId":level_id,
		"seed":random.generator.seed,
		"sessionId":"island-%s-%s" % [Time.get_unix_time_from_system(),random.generator.seed],
		"turnsCompleted":0,
		"challengesCompleted":0,
	}
	reported = false
	map_visible = false
	_rolling = false
	if is_instance_valid(board_3d):
		board_3d.reset_presentation()
	if _turn_banner_tween != null and _turn_banner_tween.is_valid():
		_turn_banner_tween.kill()
	if _turn_banner != null and is_instance_valid(_turn_banner):
		_turn_banner.queue_free()
	if mode_id == "adventure":
		state.maxRounds = 3
		var goal := str(ContentDB.level(game_id,level_id).get("goal","turns"))
		for index in state.players.size():
			state.players[index].position = 11 if goal in ["correct","challenges","islandLevel"] else index*5
		if goal in ["challenges","islandLevel"]:
			state.energy = 2
			state.energyMax = int(GameTuning.value(game_id,difficulty,"energyTarget",3))
		if goal == "upgrades":
			var categories := ["math","chinese","science","logic"]
			for index in state.players.size():
				var ids: Array = ContentDB.island.groups.get(categories[index],[])
				state.players[index].properties = ids.duplicate()
				if not ids.is_empty():
					state.players[index].position = (int(ids[0])+31)%32
				for id in ids:
					state.properties[int(id)] = {"ownerId":index,"level":0}
	_save("智慧岛出发")


func _render() -> void:
	var row: Node
	if not is_instance_valid(board_3d) or not board_3d.is_inside_tree():
		PlaygroundUI.clear(content_root)
		row = HBoxContainer.new()
		row.name = "IslandLayout"
		row.size_flags_vertical = Control.SIZE_EXPAND_FILL
		row.add_theme_constant_override("separation",16)
		board_3d = IslandBoard3D.new()
		board_3d.custom_minimum_size = Vector2(540,430)
		board_3d.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		board_3d.size_flags_vertical = Control.SIZE_EXPAND_FILL
		row.add_child(board_3d)
		content_root.add_child(row)
		control_panel = _control_panel()
		row.add_child(control_panel)
		await get_tree().process_frame
		if not is_instance_valid(board_3d):
			return
		board_3d.set_tiles(ContentDB.board_tiles())
	else:
		row = board_3d.get_parent()
		row.remove_child(control_panel)
		control_panel.queue_free()
		control_panel = _control_panel()
		row.add_child(control_panel)
	var visual_players: Array = state.players.duplicate(true)
	for index: int in visual_players.size():
		visual_players[index].accentColor = visual_players[index].get("color","#e4572e")
		visual_players[index].avatar = str(visual_players[index].get("avatar","🦊"))
	board_3d.set_players(visual_players)
	board_3d.set_owners(state.properties,state.players.map(func(player): return str(player.color)))


func _control_panel() -> Control:
	var panel := PlaygroundUI.panel(Color(1, 1, 1, 0.78), 26, PlaygroundUI.mix(accent, Color.WHITE, 0.52), 1)
	panel.custom_minimum_size.x = 350
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	panel.add_child(column)
	column.add_child(PlaygroundUI.label("第 %s / %s 回合" % [int(state.round), int(state.maxRounds)], 14, accent, 700))
	var current: Dictionary = state.players[int(state.currentPlayer)]
	column.add_child(PlaygroundUI.label("轮到 %s" % current.name, 28, PlaygroundUI.INK, 700))
	column.add_child(PlaygroundUI.label("总资产 %s 金币 · ⭐ %s" % [_total_assets(int(state.currentPlayer)), int(current.wisdomStars)], 14, PlaygroundUI.INK_SOFT, 500))
	var start_button_text := "🎲 骰子滚动中…" if _rolling else "🎲 掷骰子" if state.phase == "ready" else "正在处理这一格…"
	var roll := PlaygroundUI.button(start_button_text, accent, roll_dice)
	roll.custom_minimum_size.y = 64
	roll.disabled = _rolling or state.phase != "ready" or bool(state.finished)
	column.add_child(roll)
	var energy_card := PlaygroundUI.panel(PlaygroundUI.mix(accent, Color.WHITE, 0.9), 18, PlaygroundUI.mix(accent, Color.WHITE, 0.55), 1)
	var energy_copy := VBoxContainer.new()
	energy_copy.add_child(PlaygroundUI.label("💫 岛心能量 %s / %s" % [int(state.energy), int(state.energyMax)], 16, accent, 700))
	energy_copy.add_child(PlaygroundUI.label("答对题会增加能量，集满后大家轮流挑战岛心题。", 12, PlaygroundUI.INK_SOFT, 500, true))
	energy_card.add_child(energy_copy)
	column.add_child(energy_card)
	column.add_child(PlaygroundUI.separator())
	for index in state.players.size():
		var player: Dictionary = state.players[index]
		var tint := PlaygroundUI.color(str(player.get("color", "#d56c29")))
		var card := PlaygroundUI.panel(
			PlaygroundUI.mix(tint, Color.WHITE, 0.88),
			17,
			tint if index == int(state.currentPlayer) else PlaygroundUI.mix(tint, Color.WHITE, 0.55),
			3 if index == int(state.currentPlayer) else 1
		)
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 8)
		line.add_child(PlaygroundUI.label(str(player.get("character", {}).get("previewEmoji", "🦊")), 27, tint, 700))
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_child(PlaygroundUI.label(str(player.name), 17, PlaygroundUI.INK, 700))
		info.add_child(PlaygroundUI.label("🪙 %s  🏠 %s  ⭐ %s" % [int(player.cash), player.properties.size(), int(player.wisdomStars)], 12, PlaygroundUI.INK_SOFT))
		line.add_child(info)
		card.add_child(line)
		column.add_child(card)
	return panel


func roll_dice() -> void:
	if paused or state.phase != "ready" or _rolling:
		return
	lesson_action("roll")
	var die := random.next_int(1,6)
	if mode_id == "adventure":
		var goal := str(ContentDB.level(game_id,level_id).get("goal","turns"))
		var player: Dictionary = state.players[int(state.currentPlayer)]
		for step in range(1,7):
			var tile: Dictionary = ContentDB.board_tiles()[(int(player.position)+step)%32]
			if (goal in ["correct","challenges","islandLevel"] and str(tile.type) == "quiz") or (goal == "houses" and str(tile.type) == "property" and not state.properties.has(int(tile.id))) or (goal == "upgrades" and int(state.properties.get(int(tile.id),{}).get("ownerId",-1)) == int(state.currentPlayer)):
				die = step
				break
			die = 6
	# 点数与随机数游标先落盘；动画只负责表现，不提交规则结果。
	_rolling = true
	state.lastDie = die
	state.phase = "rolling"
	state.rollRemaining = 0.725
	_save("骰子结果已保存")
	FeedbackKit.haptic(12)
	_render()
	AudioFX.play("whoosh")
	if is_instance_valid(board_3d) and not map_visible:
		board_3d.play_dice_roll(die)


func _begin_move(die: int) -> void:
	if paused or map_visible or state.get("phase", "") != "rolling":
		return
	_rolling = false
	state.lastDie = die
	state.phase = "moving"
	state.stepsRemaining = die
	state.moveRemaining = 0.28
	AudioFX.play("select")
	_save("掷骰子")
	var from_position := int(state.players[int(state.currentPlayer)].position)
	_render()
	if is_instance_valid(board_3d) and not map_visible:
		# 从当前格开始逐格点亮路径，与棋子跳跃同步
		board_3d.show_path(from_position, die)


func _finish_roll() -> void:
	if state.phase != "moving":
		return
	var current_index := int(state.currentPlayer)
	var player: Dictionary = state.players[current_index]
	var next_position := (int(player.position) + 1) % 32
	if next_position == 0:
		player.cash = int(player.cash) + int(state.get("passBonus",PASS_START_BONUS))
	player.position = next_position
	state.stepsRemaining = maxi(0,int(state.get("stepsRemaining",state.lastDie))-1)
	state.moveRemaining = 0.18
	AudioFX.play("tap") # 每跳一格轻轻一声
	if int(state.stepsRemaining) > 0:
		_save("逐格前进")
		_render()
		return
	state.pendingTile = next_position
	state.phase = "tile"
	state.moveRemaining = 0.24
	_save("骰子前进")
	_render()


func _resolve_tile() -> void:
	var tile = ContentDB.board_tiles()[int(state.pendingTile)]
	var tile_type := str(tile.get("type", "rest"))
	if tile_type == "property":
		_resolve_property(tile)
	elif tile_type == "quiz":
		_open_quiz(tile)
	elif tile_type == "bonus":
		_gain_cash(BONUS_REWARD)
		_celebrate_tile("coin", 9)
		_notice("🌈 获得宝箱", "打开宝箱，获得 %s 金币。" % BONUS_REWARD, true)
	elif tile_type == "penalty":
		_gain_cash(-int(tile.get("penaltyAmount", 80)))
		_bounce_tile("🌧️")
		_notice("🌧️ 淘气云朵", "支付 %s 金币，下次一定会遇到好事。" % int(tile.get("penaltyAmount", 80)), false)
	elif tile_type == "move":
		var steps := int(tile.get("moveSteps", 2))
		var player: Dictionary = state.players[int(state.currentPlayer)]
		player.position = (int(player.position) + steps) % 32
		state.pendingTile = int(player.position)
		state.phase = "tile"
		state.moveRemaining = 0.3
		_save("额外前进")
		_render()
	else:
		_gain_cash(REST_REWARD)
		_bounce_tile("🌿")
		_notice("🌿 休息一下", "在智慧岛边休息，获得 %s 金币。" % REST_REWARD, true)


func _resolve_property(tile: Dictionary) -> void:
	var tile_id := int(tile.id)
	var property: Dictionary = state.properties.get(tile_id, {})
	var current_index := int(state.currentPlayer)
	if property.is_empty():
		if int(state.players[current_index].cash) < int(tile.get("price", 0)):
			_notice("🏠 金币不够", "可以先存一些金币，下次再买下 %s。" % tile.name, false)
			return
		state.phase = "property"
		_save("选择是否买房")
		_show_property_modal(tile)
		return
	var owner_index := int(property.ownerId)
	if owner_index == current_index:
		var category := str(tile.get("category", ""))
		var group_ids: Array = ContentDB.island.get("groups", {}).get(category, [])
		var own_count := group_ids.filter(func(id):
			return state.properties.get(int(id), {}).get("ownerId", -1) == current_index
		).size()
		var level := int(property.get("level", 0))
		if group_ids.size() > 0 and own_count == group_ids.size() and level < 3 and int(state.players[current_index].cash) >= int(tile.get("upgradeCost", 0)):
			state.phase = "property"
			_save("选择是否升级")
			_show_upgrade_modal(tile, property, level)
			return
		_notice("🏠 回到自己的房子", "%s 正在欢迎你。集齐同区域四套房子后可以升级。" % tile.name, true)
		return
	var rent := mini(int(tile.get("baseRent", 0)) * (1 + int(property.get("level", 0))), int(state.players[current_index].cash))
	_gain_cash(-rent)
	state.players[owner_index].cash = int(state.players[owner_index].cash) + rent
	_notice("🏠 自动收租", "%s 是房东，你支付了 %s 金币租金。" % [state.players[owner_index].name, rent], false)


func _show_property_modal(tile: Dictionary) -> void:
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	content.add_child(PlaygroundUI.label("🏠 %s" % tile.name, 28, PlaygroundUI.INK, 700))
	content.add_child(PlaygroundUI.label("售价 %s 金币 · 基础租金 %s 金币" % [tile.get("price", 0), tile.get("baseRent", 0)], 17, PlaygroundUI.INK_SOFT, 700))
	content.add_child(PlaygroundUI.label(str(tile.get("description", "")), 16, PlaygroundUI.INK_SOFT, 500, true))
	open_modal("买下这套房子？", content, [
		{"text": "先不买", "kind": "soft", "callback": func(): _close_top_modal(); _end_turn("路过房子")},
		{"text": "买下 %s" % tile.get("price", 0), "kind": "primary", "callback": func(): _buy_property(tile)},
	], "可以慢慢决定")


func _buy_property(tile: Dictionary) -> void:
	_close_top_modal()
	var current_index := int(state.currentPlayer)
	var player: Dictionary = state.players[current_index]
	player.cash = int(player.cash) - int(tile.get("price", 0))
	player.properties.append(int(tile.id))
	state.properties[int(tile.id)] = {"ownerId": current_index, "level": 0}
	AudioFX.play("coin")
	FeedbackKit.haptic(10)
	_render()
	_celebrate_tile("coin", 10)
	_notice("🏠 买房子成功", "%s 买下了 %s，其他小朋友来到这里会自动付租金。" % [player.name, tile.name], true)


func _show_upgrade_modal(tile: Dictionary, property: Dictionary, level: int) -> void:
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	content.add_child(PlaygroundUI.label("🏯 %s 正在升级" % tile.name, 26, PlaygroundUI.INK, 700))
	content.add_child(PlaygroundUI.label("已经集齐同区域四套房子。升级后租金会提高。", 16, PlaygroundUI.INK_SOFT, 500, true))
	var upgrade := func():
		_close_top_modal()
		var player: Dictionary = state.players[int(state.currentPlayer)]
		player.cash = int(player.cash) - int(tile.get("upgradeCost", 0))
		property.level = level + 1
		state.properties[int(tile.id)] = property
		AudioFX.play("coin")
		_render()
		_celebrate_tile("star", 10)
		_notice("🏯 升级成功", "%s 升级到 %s 级，下一次收租更多。" % [tile.name, level + 1], true)
	open_modal("升级为 %s 级建筑？" % (level + 1), content, [
		{"text": "先不升级", "kind": "soft", "callback": func(): _close_top_modal(); _end_turn("回到自己的房子")},
		{"text": "花 %s 升级" % tile.get("upgradeCost", 0), "kind": "primary", "callback": upgrade},
	], "房子升级")


func _open_quiz(tile: Dictionary) -> void:
	var category := str(tile.get("category", ""))
	if bool(tile.get("randomCategory", false)):
		category = ["math", "chinese", "science", "logic"][random.next_int(0,3)]
	var age := int(state.players[int(state.currentPlayer)].age)
	var used: Array = state.usedQuestions
	var candidates := ContentDB.island_questions().filter(func(question):
		return (
			int(question.age) == age
			and str(question.category) == category
			and not (str(question.id) in used)
		)
	)
	if candidates.is_empty():
		candidates = ContentDB.island_questions().filter(func(question):
			return int(question.age) == age and str(question.category) == category
		)
	if candidates.is_empty():
		_notice("📚 今天没有新题", "这一格先送你一份小金币，换一题继续。", true)
		return
	var question: Dictionary = candidates[random.next_int(0,candidates.size()-1)]
	used.append(str(question.id))
	state.phase = "quiz"
	state.quiz = {"question": question, "selected": -1, "answered": false, "correct": false}
	SfxMap.play(&"dialog_open")
	_save("开始答题")
	_show_quiz_modal(question)


func _show_quiz_modal(question: Dictionary) -> void:
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	var visual := PlaygroundUI.label(str(question.get("visual", "💡")), 56, accent, 700)
	visual.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(visual)
	var prompt := PlaygroundUI.label(str(question.prompt), 26, PlaygroundUI.INK, 700, true)
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(prompt)
	Speech.speak(str(question.get("narration", question.prompt)))
	var options: Array = question.options
	var selected := int(state.quiz.get("selected", -1))
	var answered := bool(state.quiz.get("answered", false))
	for index in options.size():
		var text := str(options[index])
		if answered and index == int(question.answer):
			text = "✓ " + text
		elif answered and index == selected:
			text = "× " + text
		var button := PlaygroundUI.button(
			text,
			Color("#4e9b6b") if answered and index == int(question.answer) else accent,
			_answer_island_quiz.bind(index),
			"soft" if not answered or index != int(question.answer) else "primary"
		)
		button.disabled = answered
		content.add_child(button)
	if answered:
		content.add_child(PlaygroundUI.label("正确答案：%s" % question.options[int(question.answer)], 19, PlaygroundUI.INK, 700, true))
		content.add_child(PlaygroundUI.label(str(question.explanation), 17, PlaygroundUI.INK_SOFT, 500, true))
		content.add_child(PlaygroundUI.label("📚 知识卡：%s" % str(question.knowledge), 15, PlaygroundUI.INK_SOFT, 500, true))
	var actions := []
	if answered:
		actions.append({"text": "我明白了，继续 →", "kind": "primary", "callback": func(): _close_top_modal(); _after_quiz()})
	open_modal("智慧岛答题", content, actions, "答对赚金币，岛心能量 +1", false)


func _answer_island_quiz(index: int) -> void:
	if paused or bool(state.quiz.get("answered", false)):
		return
	lesson_action("answer")
	var question: Dictionary = state.quiz.question
	var correct := index == int(question.answer)
	state.quiz.selected = index
	state.quiz.answered = true
	state.quiz.correct = correct
	var player: Dictionary = state.players[int(state.currentPlayer)]
	if correct:
		player.cash = int(player.cash) + QUIZ_REWARD
		player.correctCount += 1
		state.energy = mini(int(state.energy) + 1, int(state.energyMax))
	else:
		player.wrongCount += 1
	AudioFX.play("correct" if correct else "wrong")
	_save("岛心答题")
	_close_top_modal()
	_show_quiz_modal(question)


func _after_quiz() -> void:
	state.quiz = {}
	if int(state.energy) >= int(state.energyMax):
		_start_challenge()
	else:
		_end_turn("答题结束")


func _start_challenge() -> void:
	var age := int(state.players[int(state.currentPlayer)].age)
	var candidates := ContentDB.island_challenges().filter(func(question): return int(question.age) == age)
	if not candidates.is_empty():
		var question: Dictionary = candidates[random.next_int(0,candidates.size()-1)]
		state.challenge = {
			"question": question,
			"responder": 0,
			"answers": {},
		}
		state.phase = "challenge"
		_save("岛心挑战")
		_show_challenge_modal()
	else:
		state.energy = 0
		_end_turn("能量满了")


func _show_challenge_modal() -> void:
	var challenge: Dictionary = state.challenge
	if challenge.is_empty():
		_end_turn("岛心挑战结束")
		return
	var question: Dictionary = challenge.question
	var responder := int(challenge.responder)
	if responder >= state.players.size():
		_show_challenge_result()
		return
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	content.add_child(PlaygroundUI.label("🏝️ 岛心共答 · %s / %s" % [responder + 1, state.players.size()], 14, accent, 700))
	content.add_child(PlaygroundUI.label("现在轮到 %s" % state.players[responder].name, 24, PlaygroundUI.INK, 700))
	var visual := PlaygroundUI.label(str(question.get("prompt", "")), 23, PlaygroundUI.INK, 700, true)
	visual.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(visual)
	Speech.speak(str(question.get("narration", question.prompt)))
	var options: Array = question.options
	for index in options.size():
		content.add_child(PlaygroundUI.button("%s %s" % [question.get("optionEmojis", ["", "", ""])[index], options[index]], accent, _answer_challenge.bind(index), "soft"))
	open_modal("大家都来点亮岛心", content, [], "答完会一起揭晓")


func _answer_challenge(index: int) -> void:
	if paused:
		return
	var challenge: Dictionary = state.challenge
	var responder := int(challenge.responder)
	challenge.answers[str(responder)] = index
	challenge.responder = responder + 1
	state.challenge = challenge
	AudioFX.play("select")
	_save("岛心作答")
	_close_top_modal()
	_show_challenge_modal()


func _show_challenge_result() -> void:
	var question: Dictionary = state.challenge.question
	var correct_count := 0
	for responder in state.players.size():
		if int(state.challenge.answers.get(str(responder), -1)) == int(question.answer):
			correct_count += 1
			if not bool(state.challenge.get("resolved",false)):
				state.players[responder].wisdomStars += 1
	var success := correct_count >= ceili(state.players.size() / 2.0)
	if success and not bool(state.challenge.get("resolved",false)):
		state.islandLevel = int(state.islandLevel) + 1
	if not bool(state.challenge.get("resolved",false)):
		state.challengesCompleted = int(state.get("challengesCompleted",0))+1
	state.challenge.resolved = true
	state.energy = 0
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 9)
	content.add_child(PlaygroundUI.label("🏝️ 正确答案：%s" % question.options[int(question.answer)], 22, accent, 700))
	content.add_child(PlaygroundUI.label(str(question.explanation), 17, PlaygroundUI.INK_SOFT, 500, true))
	content.add_child(PlaygroundUI.label("答对 %s / %s 人%s" % [correct_count, state.players.size(), "，中央小岛亮起来了！" if success else "，下一次再一起努力。"], 18, PlaygroundUI.INK, 700, true))
	var close_challenge := func():
		_close_top_modal()
		state.challenge = {}
		_end_turn("岛心挑战结束")
	open_modal("岛心挑战结束", content, [
		{"text": "回岛继续 →", "kind": "primary", "callback": close_challenge},
	], "每个答案都算数")
	if success:
		FeedbackKit.success()
	else:
		AudioFX.play("turn")
		FeedbackKit.haptic(8)
	_save("岛心揭晓")


func _notice(title: String, detail: String, good: bool) -> void:
	state.phase = "notice"
	state.notice = {"title":title,"detail":detail,"good":good}
	_save(title)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	content.add_child(PlaygroundUI.label(("🌟" if good else "📖"), 54, accent, 700))
	content.add_child(PlaygroundUI.label(detail, 18, PlaygroundUI.INK_SOFT, 500, true))
	var continue_adventure := func():
		_close_top_modal()
		_end_turn("事件结束")
	open_modal(title, content, [
		{"text": "继续冒险 →", "kind": "primary", "callback": continue_adventure},
	], "智慧岛播报")
	AudioFX.play("coin" if good else "turn")


func _gain_cash(amount: int) -> void:
	var player: Dictionary = state.players[int(state.currentPlayer)]
	player.cash = maxi(0, int(player.cash) + amount)


func _end_turn(reason: String) -> void:
	if bool(state.finished):
		return
	state.log.push_front("%s：%s" % [state.players[int(state.currentPlayer)].name, reason])
	state.log = state.log.slice(0, 40)
	state.turnsCompleted = int(state.get("turnsCompleted",0))+1
	var current := int(state.currentPlayer)
	if current + 1 >= state.players.size():
		state.round = int(state.round) + 1
	if int(state.round) > int(state.maxRounds):
		_finish_game()
		return
	state.currentPlayer = (current + 1) % state.players.size()
	state.phase = "ready"
	state.pendingTile = -1
	state.quiz = {}
	_save("轮到下一位")
	_render()
	_show_turn_banner()


func _show_turn_banner() -> void:
	# 屏幕顶部滑入“轮到 XX”横幅，1 秒左右自动收走
	if state.players.is_empty() or overlay_root == null:
		return
	if _turn_banner_tween != null and _turn_banner_tween.is_valid():
		_turn_banner_tween.kill()
	if _turn_banner != null and is_instance_valid(_turn_banner):
		_turn_banner.queue_free()
	var player: Dictionary = state.players[int(state.currentPlayer)]
	var tint := PlaygroundUI.color(str(player.get("color", "#d56c29")))
	var banner := PlaygroundUI.panel(PlaygroundUI.mix(tint, Color.WHITE, 0.84), 999, tint, 2)
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.z_index = 70
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 10)
	row.add_child(PlaygroundUI.label(str(player.get("avatar", "🦊")), 30, tint, 700))
	var text := VBoxContainer.new()
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.add_theme_constant_override("separation", 0)
	text.add_child(PlaygroundUI.label("轮到 %s" % str(player.name), 24, PlaygroundUI.INK, 700))
	text.add_child(PlaygroundUI.label("第 %s / %s 回合" % [int(state.round), int(state.maxRounds)], 12, PlaygroundUI.INK_SOFT, 500))
	row.add_child(text)
	banner.add_child(row)
	for node in banner.find_children("*", "Control", true, false):
		(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay_root.add_child(banner)
	banner.reset_size()
	var width := overlay_root.size.x if overlay_root.size.x > 10.0 else size.x
	var target := Vector2((width - banner.size.x) * 0.5, 86.0)
	banner.position = Vector2(target.x, -banner.size.y - 10.0)
	banner.modulate.a = 0.0
	_turn_banner = banner
	var tween := MotionKit.tween(self)
	_turn_banner_tween = tween
	tween.set_parallel(true)
	tween.tween_property(banner, "modulate:a", 1.0, 0.2)
	tween.tween_property(banner, "position:y", target.y, 0.26).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.chain().tween_interval(0.85)
	tween.chain().tween_property(banner, "modulate:a", 0.0, 0.22)
	tween.parallel().tween_property(banner, "position:y", target.y - 12.0, 0.22)
	tween.chain().tween_callback(banner.queue_free)
	AudioFX.play("turn")
	FeedbackKit.haptic(8)


func _celebrate_tile(kind: String, count: int = 10) -> void:
	if is_instance_valid(board_3d) and not map_visible and int(state.get("pendingTile", -1)) >= 0:
		board_3d.celebrate(int(state.pendingTile), kind, count)


func _bounce_tile(symbol: String) -> void:
	if is_instance_valid(board_3d) and not map_visible and int(state.get("pendingTile", -1)) >= 0:
		board_3d.bounce_icon(int(state.pendingTile), symbol)


func _finish_game() -> void:
	state.finished = true
	state.phase = "result"
	var winner := 0
	for index in state.players.size():
		if _total_assets(index) > _total_assets(winner):
			winner = index
	state.winnerIndex = winner
	if mode_id == "adventure":
		var completed := _chapter_goal_met()
		for player in state.players:
			if completed:
				SaveStore.complete_level(str(player.id),game_id,level_id,3,mode_id)
	if not reported:
		reported = true
		state.reported = true
		var leaders := 0
		for index in state.players.size():
			if _total_assets(index) == _total_assets(winner):
				leaders += 1
		for index in state.players.size():
			var tied := leaders > 1
			var outcome := "draw" if tied and _total_assets(index) == _total_assets(winner) else "win" if index == winner else "loss"
			SaveStore.record_outcome(
				str(state.players[index].id),
				game_id,
				outcome,
				_total_assets(index),
				int(state.players[index].correctCount),
				int(state.players[index].correctCount) + int(state.players[index].wrongCount),
				{"strategy": {"correct": int(state.players[index].correctCount), "answered": int(state.players[index].correctCount) + int(state.players[index].wrongCount)}},
				str(state.get("sessionId","legacy-island-"+str(state.usedQuestions.hash())))
			)
	_save("智慧岛探险完成", false)
	_render()
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	for index in state.players.size():
		content.add_child(PlaygroundUI.chip("%s  ·  %s 金币  ·  ⭐ %s" % [state.players[index].name, _total_assets(index), int(state.players[index].wisdomStars)], accent))
	if mode_id == "adventure":
		content.add_child(PlaygroundUI.label("章节目标完成啦！" if _chapter_goal_met() else "这次差一点，再试试这个目标。",23,accent,700,true))
	var play_again := func():
		_close_top_modal()
		_new_game()
		_render()
	open_modal("%s 的智慧岛探险完成！" % state.players[winner].name, content, [
		{"text": "事件回顾", "kind": "soft", "callback": func(): _show_event_review()},
		{"text": "章节地图", "kind": "soft", "callback": func(): _close_top_modal(); _show_chapter_map()},
		{"text": "回游戏大厅", "kind": "soft", "callback": func(): back_requested.emit()},
		{"text": "重新出发", "kind": "primary", "callback": play_again},
	], "最后一回合结束")
	AudioFX.play("win")


func _resume_pending_phase() -> void:
	if state.phase == "rolling":
		_rolling = true
		state.rollRemaining = clampf(float(state.get("rollRemaining",0.0)),0.0,0.725)
	elif state.phase == "moving":
		state.stepsRemaining = int(state.get("stepsRemaining",state.lastDie))
		state.moveRemaining = float(state.get("moveRemaining",0.18))
	elif state.phase == "tile":
		state.moveRemaining = float(state.get("moveRemaining",0.24))
	elif state.phase == "quiz" and not state.quiz.is_empty():
		_show_quiz_modal(state.quiz.question)
	elif state.phase == "challenge" and not state.challenge.is_empty():
		_show_challenge_modal()
	elif state.phase == "property" and int(state.pendingTile) >= 0:
		_resolve_property(ContentDB.board_tiles()[int(state.pendingTile)])
	elif state.phase == "notice":
		var notice: Dictionary = state.get("notice",{"title":"继续冒险","detail":"上次的事件已经处理，确认后继续。","good":true})
		_notice(str(notice.title),str(notice.detail),bool(notice.good))
	elif state.phase == "result":
		_finish_game()


func _total_assets(index: int) -> int:
	var player: Dictionary = state.players[index]
	var total := int(player.cash)
	for tile_id in player.properties:
		var tile = ContentDB.board_tiles()[int(tile_id)]
		var level := int(state.properties.get(int(tile_id), {}).get("level", 0))
		total += int(tile.get("price", 0)) + level * int(tile.get("upgradeCost", 0))
	return total


func _save(note: String, resume: bool = true) -> void:
	if state.is_empty():
		return
	state.rngState = str(random.generator.state)
	state.view = "map" if map_visible else "board"
	var primary := str(state.get("players", [{}])[0].get("id", players[0].id))
	SaveStore.save_state(game_id, primary, state, note, resume and (not bool(state.get("finished",false)) or map_visible))


func _process(delta: float) -> void:
	super._process(delta)
	if paused or map_visible or state.is_empty():
		return
	if state.phase == "rolling":
		state.rollRemaining = maxf(0.0,float(state.get("rollRemaining",0.0))-delta)
		if float(state.rollRemaining) <= 0.0:
			_begin_move(int(state.lastDie))
	elif state.phase in ["moving","tile"]:
		state.moveRemaining = float(state.get("moveRemaining",0.0))-delta
		if float(state.moveRemaining) <= 0:
			if state.phase == "moving":
				_finish_roll()
			else:
				_resolve_tile()


func _show_chapter_map() -> void:
	map_visible = true
	PlaygroundUI.clear(content_root)
	board_3d = null
	content_root.add_child(PlaygroundUI.label("一起探索智慧岛",32,accent,700))
	content_root.add_child(PlaygroundUI.label("每章三轮，大家一起完成一个小目标。",19,PlaygroundUI.INK_SOFT,500,true))
	content_root.add_child(level_map(_choose_chapter))
	_save("正在看章节地图")


func _choose_chapter(number: int) -> void:
	if not SaveStore.level_unlocked(str(players[0].id),game_id,number,mode_id):
		return
	level_id = number
	_new_game()
	_render()
	begin_lesson()
	var chapter := ContentDB.level(game_id,number)
	show_toast("本章目标："+str(chapter.get("title","")),5)
	Speech.speak("本章目标，"+str(chapter.get("title","")))


func _chapter_goal_met() -> bool:
	var chapter := ContentDB.level(game_id,level_id)
	var goal := str(chapter.get("goal","turns"))
	var value := 0
	match goal:
		"turns": value = int(state.get("turnsCompleted",0))
		"correct":
			for player in state.players:
				value += int(player.correctCount)
		"houses": value = state.properties.size()
		"upgrades":
			for property in state.properties.values():
				value += int(property.get("level",0))
		"challenges": value = int(state.get("challengesCompleted",0))
		"islandLevel": value = int(state.islandLevel)
	return value >= int(chapter.get("target",1))


func _show_event_review() -> void:
	var list := VBoxContainer.new()
	for entry in state.log:
		list.add_child(PlaygroundUI.label(str(entry),20,PlaygroundUI.INK_SOFT,500,true))
	open_modal("刚才的冒险",list,[{"text":"看完啦","kind":"primary","callback":func(): _close_top_modal()}])
