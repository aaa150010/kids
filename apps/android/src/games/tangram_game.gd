class_name NativeTangramGame
extends NativeGameScreen

var engine := TangramRules.new()
var board: TangramBoard
var game_header: Control
var status: Label
var game_tools: Control
var view := "map"
var _levels_cache: Array = []
var _result_visible := false


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
			_show_map()
			return
		if view == "map":
			_show_map()
			return
	else:
		_show_map()
		return
	_build_board()
	_refresh()
	call_deferred("begin_lesson")


func _content_data() -> Dictionary:
	var content: Variant = ContentDB.get("tangram_data")
	if content is Dictionary:
		return content
	var path := "res://content/tangram.json"
	if FileAccess.file_exists(path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary:
			return parsed
	return {}


func _levels() -> Array:
	if not _levels_cache.is_empty():
		return _levels_cache
	var direct: Variant = ContentDB.get("tangram_levels")
	if direct is Array and not direct.is_empty() and direct[0] is Dictionary and direct[0].get("targetPieces") is Array:
		_levels_cache = direct.duplicate(true)
		return _levels_cache
	var data := _content_data()
	var templates: Dictionary = data.get("templates", {}) if data.get("templates") is Dictionary else {}
	for raw in data.get("levels", []):
		if not raw is Dictionary:
			continue
		var entry: Dictionary = raw.duplicate(true)
		var template_name := str(entry.get("template", ""))
		var template: Array = templates.get(template_name, []) if templates.get(template_name) is Array else []
		var turn := int(entry.get("turn", 0))
		var target: Array = []
		for piece in template:
			if not piece is Dictionary:
				continue
			var source := Vector2(float(piece.get("x", 0.5)), float(piece.get("y", 0.5))) - Vector2(0.5, 0.5)
			source = source.rotated(float(turn) * PI * 0.5) + Vector2(0.5, 0.5)
			target.append({
				"kind": str(piece.get("kind", "square")),
				"x": source.x,
				"y": source.y,
				"rotation": (int(piece.get("rotation", 0)) + turn) % 4,
				"mirror": bool(piece.get("mirror", false)),
			})
		entry.targetPieces = target
		_levels_cache.append(entry)
	return _levels_cache


func _level(number: int = -1) -> Dictionary:
	var levels := _levels()
	if levels.is_empty():
		return {}
	var index := clampi((number if number > 0 else level_id) - 1, 0, levels.size() - 1)
	return levels[index].duplicate(true)


func _show_map() -> void:
	view = "map"
	_result_visible = false
	PlaygroundUI.clear(content_root)
	var entries: Array = []
	var levels := _levels()
	var active_level := level_id if str(engine.state.get("phase", "")) == "playing" else -1
	for index in levels.size():
		var number := index + 1
		var entry: Dictionary = levels[index]
		var unlocked := SaveStore.level_unlocked(str(players[0].id), game_id, number, mode_id)
		var stars := clampi(int(SaveStore.learning(str(players[0].id), game_id, mode_id).stars.get(str(number), 0)), 0, 3)
		entries.append({
			"id": number,
			"title": str(entry.get("title", "七巧板")),
			"subtitle": str(entry.get("band", "")),
			"locked": not unlocked,
			"stars": stars,
			"in_progress": number == active_level,
		})
	var browser := GameBrowser.new()
	browser.configure(entries, {
		"title": "七块积木，拼出想象",
		"subtitle": "拖动积木到轮廓上，旋转和翻转方向。拼好后会亮起来。",
		"accent": accent,
	})
	browser.entry_selected.connect(func(number: Variant): _choose_level(int(number)))
	content_root.add_child(browser)
	if not engine.state.is_empty():
		_save("正在选择拼图关卡")


func _choose_level(number: int) -> void:
	if not SaveStore.level_unlocked(str(players[0].id), game_id, number, mode_id):
		show_toast("先完成前一关，再来挑战这一关。")
		return
	guard_level_switch(number, func(): _start_level(number), func():
		view = "board"
		_build_board()
		_refresh()
	)


func _start_level(number: int) -> void:
	level_id = number
	_new_session()
	_build_board()
	_refresh()
	begin_lesson()


func _new_session() -> void:
	var entry := _level(level_id)
	if entry.is_empty():
		show_toast("这一关还没有准备好。")
		return
	engine.create_session({
		"gameId": game_id,
		"modeId": mode_id,
		"players": players.duplicate(true),
		"levelId": level_id,
		"level": entry,
		"difficulty": difficulty,
		"hintsMax": int(GameTuning.value(game_id, difficulty, "hints", 3)),
		"seed": Time.get_ticks_usec(),
	})
	view = "board"
	_result_visible = false
	_save("开始拼图")


func _build_board() -> void:
	view = "board"
	PlaygroundUI.clear(content_root)
	game_header = HBoxContainer.new()
	game_header.add_theme_constant_override("separation", 10)
	if players.size() >= 2:
		game_header.add_child(_player_chip(0))
		var middle := CenterContainer.new()
		middle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		middle.add_child(PlaygroundUI.chip("一起拼同一幅", accent))
		game_header.add_child(middle)
		game_header.add_child(_player_chip(1))
	else:
		game_header.add_child(PlaygroundUI.chip("第 %s 关 · %s" % [level_id, str(_level(level_id).get("title", "七巧板"))], accent))
		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		game_header.add_child(spacer)
		game_header.add_child(PlaygroundUI.chip("单人拼图", accent))
	content_root.add_child(game_header)
	board = TangramBoard.new()
	board.accent = accent
	board.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	board.size_flags_vertical = Control.SIZE_EXPAND_FILL
	board.set_level(_level(level_id))
	board.piece_selected.connect(_select)
	board.piece_placed.connect(_place)
	content_root.add_child(board)
	var tools := HFlowContainer.new()
	tools.alignment = FlowContainer.ALIGNMENT_CENTER
	tools.add_theme_constant_override("h_separation", 10)
	tools.add_theme_constant_override("v_separation", 8)
	tools.add_child(PlaygroundUI.semantic_icon_button("hint", "看提示", accent, _hint, "soft", 18))
	tools.add_child(PlaygroundUI.semantic_icon_button("rotate", "旋转", accent, _rotate, "soft", 18))
	tools.add_child(PlaygroundUI.semantic_icon_button("game", "翻转", accent, _mirror, "soft", 18))
	tools.add_child(PlaygroundUI.semantic_icon_button("undo", "重摆", accent, _confirm_reset, "ghost", 18))
	if mode_id in ["adventure", "classic"]:
		tools.add_child(PlaygroundUI.semantic_icon_button("back", "关卡地图", accent, _show_map, "ghost", 18))
	content_root.add_child(tools)
	game_tools = tools
	status = PlaygroundUI.label("先选一块积木，再放到轮廓上。", 19, accent, 700, true)
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content_root.add_child(status)
	board.set_state(engine.state)
	_on_immersive_changed(immersive)


func _on_immersive_changed(value: bool) -> void:
	if game_header != null and is_instance_valid(game_header):
		game_header.visible = not value
	if status != null and is_instance_valid(status):
		status.visible = not value
	if game_tools != null and is_instance_valid(game_tools):
		# 提示、旋转、翻转和重摆是本游戏的必要操作，固定在棋盘下方保留。
		game_tools.show()


func _player_chip(index: int) -> Control:
	var panel := PlaygroundUI.panel(PlaygroundUI.mix(accent, Color.WHITE, 0.90), 18, PlaygroundUI.mix(accent, Color.WHITE, 0.45), 2)
	panel.custom_minimum_size = Vector2(230, 62)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	panel.add_child(row)
	if index < players.size():
		row.add_child(ArtLibrary.profile_picture(players[index], Vector2(46, 48)))
		var copy := VBoxContainer.new()
		copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		copy.add_child(PlaygroundUI.label(str(players[index].get("name", "小朋友")), 18, PlaygroundUI.INK, 700, true))
		copy.add_child(PlaygroundUI.label("一起拼图" if players.size() > 1 else "单人拼图", 14, PlaygroundUI.INK_SOFT, 500))
		row.add_child(copy)
	return panel


func _select(index: int) -> void:
	if paused or _result_visible:
		return
	var result := engine.select_piece(index)
	if bool(result.get("ok", false)):
		_refresh()


func _place(index: int, position: Vector2) -> void:
	if paused or _result_visible:
		return
	var result := engine.place_piece(index, position.x, position.y)
	if not bool(result.get("ok", false)):
		show_toast(str(result.get("message", "试试轮廓上的位置")))
		return
	SfxMap.play(&"drop")
	FeedbackKit.haptic(7)
	_save("拼上一块积木")
	_refresh()
	if engine.state.phase == "finished":
		_show_result()


func _rotate() -> void:
	if paused or _result_visible:
		return
	var result := engine.rotate_piece()
	if not bool(result.get("ok", false)):
		show_toast(str(result.get("message", "先选一块积木")))
		return
	SfxMap.play(&"select")
	_save("旋转积木")
	_refresh()


func _mirror() -> void:
	if paused or _result_visible:
		return
	var result := engine.mirror_piece()
	if not bool(result.get("ok", false)):
		show_toast(str(result.get("message", "先选平行四边形")))
		return
	SfxMap.play(&"select")
	_save("翻转积木")
	_refresh()


func _hint() -> void:
	if paused or _result_visible:
		return
	var result := engine.handle_input({"type": "hint"})
	if not bool(result.get("ok", false)):
		show_toast(str(result.get("message", "现在没有提示了")))
		return
	SfxMap.play(&"select")
	_save("查看拼图提示")
	_refresh()
	Speech.speak(str(result.get("message", "看看发光的位置。")))


func _confirm_reset() -> void:
	open_modal("重新摆这七块？", PlaygroundUI.label("当前摆放会回到起点，不会影响关卡进度。", 20, PlaygroundUI.INK_SOFT, 500, true), [
		{"text": "继续拼", "kind": "soft", "callback": func(): _close_top_modal()},
		{"text": "重新摆", "kind": "primary", "callback": _reset_pieces},
	], "七巧板")


func _reset_pieces() -> void:
	_close_top_modal()
	engine.handle_input({"type": "reset"})
	_save("重新摆放积木")
	_refresh()


func _refresh() -> void:
	if board == null or not is_instance_valid(board) or engine.state.is_empty():
		return
	board.set_state(engine.state)
	var selected := int(engine.state.get("selected", -1))
	if selected >= 0:
		var piece: Dictionary = engine.state.pieces[selected]
		status.text = "选中：%s · 旋转或翻转，再放到轮廓上。" % str(TangramRules.PIECE_NAMES.get(str(piece.get("kind", "")), "积木"))
	else:
		status.text = "先选一块积木，再放到轮廓上。提示 %s / %s" % [int(engine.state.get("hints", 0)), int(engine.state.get("hintsMax", 3))]
	if str(engine.state.get("phase", "")) == "finished" and not _result_visible:
		_show_result()


func _show_result() -> void:
	if _result_visible:
		return
	var state := engine.state
	if not bool(state.get("reported", false)):
		state.reported = true
		var star_count := engine.stars()
		state.stars = star_count
		if mode_id == "adventure":
			SaveStore.complete_level(str(players[0].id), game_id, level_id, star_count, mode_id)
			SaveStore.record_outcome(str(players[0].id), game_id, "win", star_count, 1, 1, {"logic": {"correct": 1, "answered": 1}}, str(state.get("sessionId", "tangram")))
		else:
			for player in players:
				SaveStore.complete_level(str(player.id), game_id, level_id, star_count, mode_id)
				SaveStore.record_outcome(str(player.id), game_id, "played", star_count, 1, 1, {"logic": {"correct": 1, "answered": 1}}, str(state.get("sessionId", "tangram")))
		_save("拼图完成", false)
	_result_visible = true
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	var trophy := ArtLibrary.semantic_picture("trophy", "ui", Vector2(84, 84))
	trophy.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	body.add_child(trophy)
	body.add_child(PlaygroundUI.label("七块拼好啦！", 26, accent, 700, true))
	var stars := HBoxContainer.new()
	stars.alignment = BoxContainer.ALIGNMENT_CENTER
	stars.add_theme_constant_override("separation", 8)
	for index in 3:
		var star := ArtLibrary.semantic_picture("star", "ui", Vector2(38, 38))
		star.modulate = Color.WHITE if index < int(engine.stars()) else Color(1, 1, 1, 0.25)
		stars.add_child(star)
	body.add_child(stars)
	var actions := [
		{"text": "关卡地图", "icon": "back", "kind": "soft", "callback": func(): _close_top_modal(); _show_map()},
		{"text": "再拼一次", "icon": "restart", "kind": "soft", "callback": func(): _close_top_modal(); _new_session(); _build_board(); _refresh()},
	]
	if level_id < _levels().size():
		actions.append({"text": "下一关", "icon": "next", "kind": "primary", "callback": _next_level})
	else:
		actions.append({"text": "回大厅", "icon": "home", "kind": "primary", "callback": func(): _close_top_modal(); back_requested.emit()})
	open_modal("拼图完成", body, actions, "每一块都放对了")
	SfxMap.play(&"win")
	FeedbackKit.haptic(14)


func _next_level() -> void:
	_close_top_modal()
	if mode_id == "adventure" and not SaveStore.level_unlocked(str(players[0].id), game_id, level_id + 1, mode_id):
		_show_map()
		return
	level_id += 1
	_new_session()
	_build_board()
	_refresh()


func _extra_pause_actions() -> Array:
	return [{"text": "关卡地图", "icon": "back", "kind": "soft", "callback": func(): _close_pause_tools(); _show_map()}]


func _show_rules() -> void:
	var lines := [
		"七块积木是两片大三角、一片中三角、两片小三角、一块正方形和一块平行四边形。",
		"拖动积木到轮廓上，松手会自动靠近合适的位置。",
		"选中积木后可以旋转；平行四边形还能翻转。",
		"看提示会点亮一块还没放好的位置。",
	]
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	for index in lines.size():
		var row := HBoxContainer.new()
		row.add_child(PlaygroundUI.chip(str(index + 1), accent))
		var label := PlaygroundUI.label(str(lines[index]), 19, PlaygroundUI.INK_SOFT, 500, true)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		body.add_child(row)
	open_modal("七巧板规则", body, [
		{"text": "读给我听", "icon": "speech", "kind": "soft", "callback": func(): Speech.speak(" ".join(PackedStringArray(lines)))},
		{"text": "知道了", "icon": "check", "kind": "primary", "callback": func(): _close_top_modal()},
	], "七块积木的玩法")


func begin_lesson(force: bool = false) -> void:
	if not force:
		return
	if not paused:
		_open_pause_tools()
	lesson_texts = [
		"从右边选一块积木，拖到左边的轮廓上。",
		"点旋转，平行四边形还可以翻转。",
		"放对会自动保存，拼好七块就完成啦。",
	]
	_lesson_icons = ["game", "next", "check"]
	_show_lesson_page(0)


func _save(note: String, resume: bool = true) -> void:
	if engine.state.is_empty():
		return
	engine.state.view = view
	SaveStore.save_state(game_id, str(players[0].id), engine.snapshot(), note, resume and engine.state.phase == "playing" and view == "board")
