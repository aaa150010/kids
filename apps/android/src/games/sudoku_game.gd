class_name NativeSudokuGame
extends NativeGameScreen

var engine := SudokuRules.new()
var board: SudokuBoard
var number_buttons: Array[Button] = []
var status: Label
var detail: Label
var active_grid: Control
var game_tools: Control
var _puzzle_index := 0


func _ready() -> void:
	build_shell()
	var stored := SaveStore.load_state(game_id, players.map(func(player): return str(player.id)))
	stored.modeId = mode_id
	if stored.get("players") is Array and engine.restore(stored):
		players = engine.state.players.duplicate(true)
		level_id = int(engine.state.get("levelId", 1))
		_puzzle_index = maxi(0, level_id - 1)
		if engine.state.phase == "finished" and not bool(stored.get("resume", true)):
			engine.state = {}
			_create()
	elif mode_id == "adventure":
		_show_map()
		return
	else:
		_create()
	_build_session()
	_refresh()
	call_deferred("begin_lesson")


func _puzzles() -> Array:
	return ContentDB.sudoku_puzzles()


func _create(index: int = -1) -> void:
	var puzzles := _puzzles()
	_puzzle_index = clampi(index if index >= 0 else _puzzle_index, 0, maxi(0, puzzles.size() - 1))
	level_id = _puzzle_index + 1
	var definition: Dictionary = puzzles[_puzzle_index] if not puzzles.is_empty() else {}
	engine.create_session({
		"gameId": game_id, "modeId": mode_id, "players": players.duplicate(true),
		"levelId": level_id, "seed": Time.get_ticks_usec(), "puzzle": definition,
		"difficulty": str(definition.get("difficulty", "normal")),
	})
	session_id = str(engine.state.sessionId)
	_save("开始数独")


func preview_ready() -> void:
	_refresh()


func _show_map() -> void:
	PlaygroundUI.clear(content_root)
	content_root.add_child(PlaygroundUI.label("今天挑战哪一格？", 30, accent, 700, true))
	content_root.add_child(level_map(_choose_level))
	_save("正在选择数独关卡")


func _choose_level(number: int) -> void:
	if not SaveStore.level_unlocked(str(players[0].id), game_id, number, mode_id):
		return
	_create(number - 1)
	_build_session()
	_refresh()
	begin_lesson()


func _build_session() -> void:
	PlaygroundUI.clear(content_root)
	number_buttons.clear()
	var tools := HFlowContainer.new()
	tools.alignment = FlowContainer.ALIGNMENT_CENTER
	tools.add_theme_constant_override("h_separation", 10)
	if mode_id == "adventure":
		tools.add_child(PlaygroundUI.button("关卡地图", accent, _show_map, "soft"))
	tools.add_child(PlaygroundUI.button("重新开始", accent, _restart, "ghost"))
	game_tools = tools
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 10)
	title_row.add_child(PlaygroundUI.chip(engine.puzzle().get("title", "数独"), accent))
	title_row.add_child(PlaygroundUI.chip("已填 %s 格" % _filled_count(), accent))
	content_root.add_child(title_row)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	board = SudokuBoard.new()
	board.accent = accent
	board.cell_pressed.connect(_cell)
	center.add_child(board)
	content_root.add_child(center)
	active_grid = center
	var control_row := HBoxContainer.new()
	control_row.add_theme_constant_override("separation", 12)
	var actions := VBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	actions.add_child(PlaygroundUI.button("提示一格", accent, _hint, "soft"))
	actions.add_child(PlaygroundUI.button("擦掉", accent, _clear_cell, "soft"))
	actions.add_child(PlaygroundUI.button("换一题", accent, func(): _create((_puzzle_index + 1) % maxi(1, _puzzles().size())); _build_session(); _refresh(), "soft"))
	for child in actions.get_children():
		if child is Button:
			(child as Button).custom_minimum_size = Vector2(108, 56)
	control_row.add_child(actions)
	var numbers := GridContainer.new()
	numbers.columns = 3 if engine.size() == 9 else 2
	numbers.add_theme_constant_override("h_separation", 8)
	numbers.add_theme_constant_override("v_separation", 8)
	var dimension: int = engine.size()
	for digit in range(1, dimension + 1):
		var button := PlaygroundUI.button(str(digit), accent, func(): _input_digit(digit), "primary")
		button.custom_minimum_size = Vector2(66, 60)
		button.add_theme_font_size_override("font_size", 26)
		numbers.add_child(button)
		number_buttons.append(button)
	control_row.add_child(numbers)
	content_root.add_child(control_row)
	status = PlaygroundUI.label("", 21, accent, 700, true)
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content_root.add_child(status)
	detail = PlaygroundUI.label("", 16, PlaygroundUI.INK_SOFT, 500, true)
	detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content_root.add_child(detail)
	_on_immersive_changed(immersive)


func _extra_topbar_actions(row: HBoxContainer) -> void:
	var rules := PlaygroundUI.button("规则", accent, show_game_rules, "soft")
	rules.custom_minimum_size = Vector2(70, 48)
	row.add_child(rules)


func show_game_rules() -> void:
	_show_rules()


func _on_immersive_changed(value: bool) -> void:
	if game_tools != null and is_instance_valid(game_tools):
		game_tools.visible = not value
	if status != null and is_instance_valid(status):
		status.visible = not value
	if detail != null and is_instance_valid(detail):
		detail.visible = not value


func _filled_count() -> int:
	var count := 0
	for character in str(engine.state.get("values", "")):
		if character != "0":
			count += 1
	return count


func _refresh() -> void:
	if board == null or not is_instance_valid(board) or engine.state.is_empty():
		return
	if engine.state.phase == "finished" and not bool(engine.state.get("reported", false)):
		_show_result()
	board.interactive = not paused and str(engine.state.phase) == "playing"
	board.update_board(engine)
	status.text = "点一格，再点数字" if int(engine.state.get("selected", -1)) < 0 else "选好数字了，填进去吧"
	detail.text = "每行、每列、每个小宫的数字都不能重复。"
	if int(engine.state.get("mistakes", 0)) > 0:
		detail.text += "  重复 %s 次" % int(engine.state.mistakes)


func _cell(position: int) -> void:
	if paused or str(engine.state.phase) != "playing":
		return
	if engine.is_given(position):
		show_toast("这是题目给出的数字")
		return
	engine.state.selected = position
	SfxMap.play(&"select")
	_save("选择数独格子")
	_refresh()


func _input_digit(digit: int) -> void:
	if paused or str(engine.state.phase) != "playing":
		return
	var result: Dictionary = engine.set_number(digit)
	if not bool(result.ok):
		show_toast(str(result.message))
		return
	if bool(result.get("invalid", false)):
		SfxMap.play(&"error")
		show_toast("这里有重复数字")
	else:
		SfxMap.play(&"tap")
	if bool(result.get("complete", false)):
		engine.finish()
	_save("填写数独")
	_refresh()
	if engine.state.phase == "finished":
		_show_result()


func _clear_cell() -> void:
	if paused:
		return
	var result: Dictionary = engine.clear_cell()
	if bool(result.ok):
		_save("擦掉一个数字")
		_refresh()


func _hint() -> void:
	if paused:
		return
	var result: Dictionary = engine.hint()
	if not bool(result.ok):
		show_toast(str(result.message))
		return
	SfxMap.play(&"select")
	show_toast("已经帮你填好一格", 1.6)
	if bool(result.get("complete", false)):
		engine.finish()
	_save("使用数独提示")
	_refresh()
	if engine.state.phase == "finished":
		_show_result()


func _restart() -> void:
	_create(_puzzle_index)
	_build_session()
	_refresh()


func _show_rules() -> void:
	var lines := [
		"先点一个空格，再点下面的数字。",
		"每一行、每一列、每个粗线小宫里，数字都不能重复。",
		"四宫格用 1 到 4，九宫格用 1 到 9；蓝色数字是题目给出的。",
		"填错了会变成橙色，可以用“擦掉”重新填。",
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
	open_modal("数独规则", body, [
		{"text": "读给我听", "kind": "soft", "callback": func(): Speech.speak(" ".join(PackedStringArray(lines)))},
		{"text": "知道了", "kind": "primary", "callback": func(): _close_top_modal()},
	], "一格一格慢慢填")


func _show_result() -> void:
	var state: Dictionary = engine.state
	if bool(state.get("reported", false)):
		return
	state.reported = true
	var stars := 3 if int(state.hints) == 0 else 2 if int(state.hints) <= 1 else 1
	SaveStore.complete_level(str(players[0].id), game_id, level_id, stars, mode_id)
	SaveStore.record_outcome(str(players[0].id), game_id, "win", stars, 1, 1, {"logic":{"correct":1,"answered":1}}, str(state.get("sessionId", "sudoku")))
	_save("数独完成", false)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	body.add_child(ArtLibrary.picture("🏆", Vector2(88, 88)))
	body.add_child(PlaygroundUI.label("数字都排好啦！", 24, accent, 700, true))
	open_modal("数独完成", body, [{"text": "再来一题", "kind": "primary", "callback": func(): _restart()}], "本局已自动保存")


func _save(note: String, resume: bool = true) -> void:
	if engine.state.is_empty():
		return
	SaveStore.save_state(game_id, str(players[0].id), engine.snapshot(), note, resume and str(engine.state.get("phase", "")) == "playing")
