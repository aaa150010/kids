class_name NativeMilitaryGame
extends NativeGameScreen

var engine := MilitaryRules.new()
var board: MilitaryBoard
var status: Label
var detail: Label
var player_labels: Array[Label] = []
var player_panels: Array[PanelContainer] = []
var game_header: Control
var game_tools: Control
var view := "board"
var _puzzle_picker: Control
var _last_immersive_turn := -1


func _ready() -> void:
	build_shell()
	var stored := SaveStore.load_state(game_id, players.map(func(player): return str(player.id)))
	stored.modeId = mode_id
	if stored.get("players") is Array and engine.restore(stored):
		players = engine.state.players.duplicate(true)
		level_id = int(engine.state.get("levelId", 1))
		view = str(engine.state.get("view", "board"))
		if engine.state.phase == "finished" and not bool(stored.get("resume", true)):
			engine.state = {}
			_create()
	elif mode_id == "puzzle":
		_create()
	else:
		_create()
	_build_board()
	_refresh()
	call_deferred("begin_lesson")


func _create(number: int = 1) -> void:
	level_id = maxi(1, number)
	if mode_id == "puzzle":
		var puzzles := ContentDB.military_puzzles()
		if puzzles.is_empty():
			engine.create_session({"gameId": game_id, "modeId": "puzzle", "players": players, "puzzle": {}})
		else:
			level_id = clampi(level_id, 1, puzzles.size())
			engine.create_session({
				"gameId": game_id, "modeId": "puzzle", "players": players,
				"levelId": level_id, "puzzle": puzzles[level_id - 1], "seed": Time.get_ticks_usec(),
			})
	else:
		engine.create_session({"gameId": game_id, "modeId": "classic", "players": players, "seed": Time.get_ticks_usec()})
	session_id = str(engine.state.sessionId)
	view = "board"
	_save("开始军棋" if mode_id == "classic" else "开始军棋残局")


func preview_ready() -> void:
	_refresh()


func _build_board() -> void:
	PlaygroundUI.clear(content_root)
	content_root.rotation = 0.0
	player_labels.clear()
	player_panels.clear()
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	header.add_child(_player_chip(0))
	var middle := CenterContainer.new()
	middle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	middle.add_child(PlaygroundUI.chip("明棋 · 双方棋子可见", accent))
	header.add_child(middle)
	header.add_child(_player_chip(1))
	content_root.add_child(header)
	game_header = header
	board = MilitaryBoard.new()
	board.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	board.size_flags_vertical = Control.SIZE_EXPAND_FILL
	board.cell_pressed.connect(_cell)
	content_root.add_child(board)
	status = PlaygroundUI.label("", 22, accent, 700, true)
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content_root.add_child(status)
	detail = PlaygroundUI.label("", 16, PlaygroundUI.INK_SOFT, 500, true)
	detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content_root.add_child(detail)
	var tools := HFlowContainer.new()
	tools.alignment = FlowContainer.ALIGNMENT_CENTER
	tools.add_theme_constant_override("h_separation", 12)
	if mode_id == "puzzle":
		tools.add_child(PlaygroundUI.button("残局列表", accent, _show_puzzle_map, "soft"))
	tools.add_child(PlaygroundUI.button("悔棋", accent, _undo, "soft"))
	tools.add_child(PlaygroundUI.button("重新开始", accent, _confirm_restart, "ghost"))
	content_root.add_child(tools)
	game_tools = tools
	_on_immersive_changed(immersive)


func _player_chip(side: int) -> Control:
	var panel := PlaygroundUI.panel(PlaygroundUI.mix(accent, Color.WHITE, 0.90), 18, PlaygroundUI.mix(accent, Color.WHITE, 0.45), 2)
	panel.custom_minimum_size = Vector2(230, 60)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	panel.add_child(row)
	var player: Dictionary = players[side] if side < players.size() else {}
	row.add_child(ArtLibrary.picture(str(player.get("avatar", "🎖️")), Vector2(46, 48)))
	var copy := VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.add_theme_constant_override("separation", 1)
	copy.add_child(PlaygroundUI.label(str(player.get("name", "本关目标")), 18, PlaygroundUI.INK, 700, true))
	var label := PlaygroundUI.label("", 14, PlaygroundUI.INK_SOFT, 500, true)
	copy.add_child(label)
	row.add_child(copy)
	player_labels.append(label)
	player_panels.append(panel)
	return panel


func _extra_topbar_actions(row: HBoxContainer) -> void:
	var rules := PlaygroundUI.button("规则", accent, show_game_rules, "soft")
	rules.custom_minimum_size = Vector2(70, 48)
	rules.add_theme_font_size_override("font_size", 17)
	row.add_child(rules)


func show_game_rules() -> void:
	_show_rules()


func _on_immersive_changed(value: bool) -> void:
	if game_header != null and is_instance_valid(game_header):
		game_header.visible = not value
	if status != null and is_instance_valid(status):
		status.visible = not value
	if detail != null and is_instance_valid(detail):
		detail.visible = not value
	if game_tools != null and is_instance_valid(game_tools):
		game_tools.visible = not value
	if value:
		_last_immersive_turn = int(engine.state.get("turn", 0)) if not engine.state.is_empty() else -1


func _refresh() -> void:
	if board == null or not is_instance_valid(board) or engine.state.is_empty():
		return
	if engine.state.phase == "finished" and not bool(engine.state.get("reported", false)):
		_show_result()
	content_root.rotation = 0.0
	board.visible = true
	board.interactive = not paused and engine.state.phase == "playing"
	var selected := int(engine.state.get("selected", -1))
	var targets := engine.legal_targets(selected) if selected >= 0 else []
	board.update_board(engine, int(engine.state.get("turn", 0)), selected, targets, bool(engine.state.get("revealAll", true)))
	var turn := int(engine.state.get("turn", 0))
	if immersive and engine.state.phase == "playing" and turn != _last_immersive_turn:
		_last_immersive_turn = turn
		var who := str(players[turn].get("name", "")) if turn < players.size() else ""
		var hint := "%s走棋" % engine.side_name(turn)
		if not who.is_empty():
			hint = "%s · %s" % [who, hint]
		show_toast(hint, 1.2)
	for side in 2:
		var current: bool = side == turn and str(engine.state.phase) == "playing"
		player_panels[side].add_theme_stylebox_override("panel", PlaygroundUI.style(
			PlaygroundUI.mix(accent, Color.WHITE, 0.84 if current else 0.94), 22,
			accent if current else PlaygroundUI.LINE, 3 if current else 1
		))
		var formation_name := ""
		if side < engine.state.formations.size():
			var formations := ContentDB.military_formations()
			var index := int(engine.state.formations[side])
			if index >= 0 and index < formations.size():
				formation_name = str(formations[index].get("name", ""))
		if mode_id == "puzzle":
			if side == 0:
				player_labels[side].text = "现在轮到你\n红方 · 残局" if current else "红方 · 残局"
			else:
				player_labels[side].text = "目标\n夺取红色军旗"
		else:
			var prefix := "现在轮到你" if current else "等一等"
			if engine.state.phase == "finished":
				prefix = "本局结束"
			var formation_text := formation_name if not formation_name.is_empty() else "预置阵"
			player_labels[side].text = "%s\n%s方 · %s" % [prefix, engine.side_name(side), formation_text]
	if engine.state.phase == "finished":
		status.text = str(engine.state.get("reason", "本局结束"))
		detail.text = "本局共走 %s 手，进度已经自动保存。" % int(engine.state.get("moveCount", 0))
	else:
		status.text = "残局练习：点自己的棋子，再点亮起的位置" if mode_id == "puzzle" else "%s走棋：点自己的棋子，再点亮起的位置" % engine.side_name(turn)
		detail.text = "所有棋子都亮着；工兵可排雷，炸弹同归于尽，夺取军旗获胜。"
		var battle: Dictionary = engine.state.get("lastBattle", {})
		if not battle.is_empty():
			detail.text = _battle_text(battle)


func _cell(position: int) -> void:
	if paused or engine.state.phase != "playing":
		return
	var selected := int(engine.state.get("selected", -1))
	var piece := engine.piece_at(position)
	var action: Dictionary
	if selected >= 0 and position in engine.legal_targets(selected):
		action = {"type": "move", "to": position}
	elif not piece.is_empty() and engine.can_select(piece):
		action = {"type": "select", "position": position}
	else:
		action = {"type": "deselect"}
	var result := engine.handle_input(action)
	if not bool(result.get("ok", false)):
		SfxMap.play(&"error")
		show_toast(str(result.get("message", "试试亮起的位置")))
		return
	if action.type == "select":
		SfxMap.play(&"select")
	else:
		SfxMap.play(&"move")
	_save("军棋进行中")
	_refresh()
	if engine.state.phase == "finished":
		_show_result()


func _battle_text(battle: Dictionary) -> String:
	var attacker := str(MilitaryRules.NAMES.get(str(battle.get("attacker", "")), "棋子"))
	var defender := str(MilitaryRules.NAMES.get(str(battle.get("defender", "")), "棋子"))
	match str(battle.get("result", "")):
		"capture":
			return "%s夺下了%s！" % [attacker, defender]
		"attacker":
			return "%s吃掉了%s。" % [attacker, defender]
		"defender":
			return "%s挡住了%s。" % [defender, attacker]
		_:
			return "%s和%s同归于尽。" % [attacker, defender]


func _undo() -> void:
	if paused or not engine.undo_last_move():
		show_toast("现在没有可以撤回的走法")
		return
	_save("撤回了一步")
	_refresh()


func _confirm_restart() -> void:
	open_modal("重新开始？", PlaygroundUI.label("当前局面会保存为上一局，确认后重新开局。", 19, PlaygroundUI.INK, 500, true), [
		{"text": "继续下棋", "kind": "soft", "callback": func(): _close_top_modal()},
		{"text": "重新开始", "kind": "primary", "callback": func(): _restart_game()},
	], "军棋")


func _restart_game() -> void:
	_close_top_modal()
	_create(level_id)
	_build_board()
	_refresh()


func _show_puzzle_map() -> void:
	if mode_id != "puzzle":
		return
	var puzzles := ContentDB.military_puzzles()
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	for index in puzzles.size():
		var puzzle: Dictionary = puzzles[index]
		var button := PlaygroundUI.button(
			"%s\n一步夺旗" % str(puzzle.get("title", "残局")),
			accent,
			func(): _open_puzzle(index),
			"primary" if index + 1 == level_id else "soft"
		)
		button.custom_minimum_size = Vector2(0, 88)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(button)
	body.add_child(grid)
	open_modal("军棋残局", body, [{"text": "关闭", "kind": "soft", "callback": func(): _close_top_modal()}], "24 个固定练习")


func _open_puzzle(index: int) -> void:
	_close_top_modal()
	_create(index + 1)
	_build_board()
	_refresh()


func _show_rules() -> void:
	var lines := [
		"棋盘横向摆放，双方各 25 枚棋子；军旗放在大本营，地雷放在后方。",
		"棋子用数字和条纹数表示军衔：数字越大、条纹越多，军衔越高；炸弹、地雷、军旗和工兵用专属图形。",
		"右上角白圆点代表红方，白菱形代表蓝方。",
		"这是明棋对弈：双方棋子全部亮着，红方先走，轮流走棋。",
		"司令 > 军长 > 师长 > 旅长 > 团长 > 营长 > 连长 > 排长 > 工兵，大吃小，同级同归于尽。",
		"点自己的棋子，再点亮起的位置移动；行营里的棋子不能被攻击。",
		"炸弹与任何棋子同归于尽；只有工兵可以排雷，其他棋子碰雷会失败。",
		"铁路可以让棋子沿直线快速移动，工兵可以沿铁路转弯；夺取军旗获胜。",
	]
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	for index in lines.size():
		var row := HBoxContainer.new()
		row.add_child(PlaygroundUI.chip(str(index + 1), accent))
		var label := PlaygroundUI.label(lines[index], 18, PlaygroundUI.INK_SOFT, 500, true)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		body.add_child(row)
	open_modal("军棋规则", body, [
		{"text": "读给我听", "kind": "soft", "callback": func(): Speech.speak(" ".join(PackedStringArray(lines)))},
		{"text": "知道了", "kind": "primary", "callback": func(): _close_top_modal()},
	], "明棋规则")


func _show_result() -> void:
	var state := engine.state
	if bool(state.get("reported", false)):
		return
	state.reported = true
	if mode_id == "puzzle" and int(state.winner) == 0:
		SaveStore.complete_level(str(players[0].id), game_id, level_id, 1, mode_id)
		SaveStore.record_outcome(str(players[0].id), game_id, "win", 1, 0, 0, {"strategy": {"correct": 1, "answered": 1}}, str(state.get("sessionId", "military")))
	elif mode_id == "classic":
		var winner := int(state.winner)
		for side in players.size():
			var outcome := "draw" if winner < 0 else "win" if side == winner else "loss"
			SaveStore.record_outcome(str(players[side].id), game_id, outcome, 1 if outcome == "win" else 0, 0, 0, {"strategy": {"correct": 1 if outcome == "win" else 0, "answered": 1}}, str(state.get("sessionId", "military")))
	_save("军棋完成", false)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	body.add_child(ArtLibrary.picture("🏆" if int(state.winner) == 0 else "🎖️", Vector2(88, 88)))
	body.add_child(PlaygroundUI.label(str(state.get("reason", "本局结束")), 24, accent, 700, true))
	var actions := [{"text": "再来一局", "kind": "primary", "callback": func(): _restart_game()}]
	if mode_id == "puzzle":
		actions.insert(0, {"text": "选择残局", "kind": "soft", "callback": func(): _close_top_modal(); _show_puzzle_map()})
	open_modal("军棋结束", body, actions, "本局已自动保存")


func _save(note: String, resume: bool = true) -> void:
	if engine.state.is_empty():
		return
	SaveStore.save_state(game_id, str(players[0].id), engine.snapshot(), note, resume and str(engine.state.get("phase", "")) == "playing")
