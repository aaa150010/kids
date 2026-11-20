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
var _result_visible := false


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
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 10)
	title_row.add_child(PlaygroundUI.chip(engine.puzzle().get("title", "数独"), accent))
	title_row.add_child(PlaygroundUI.chip("已填 %s 格" % _filled_count(), accent))
	content_root.add_child(title_row)
	var main := HBoxContainer.new()
	main.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.add_theme_constant_override("separation", 18)
	content_root.add_child(main)
	var board_wrap := Control.new()
	board_wrap.custom_minimum_size = Vector2(520, 520)
	board_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	board_wrap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	board_wrap.size_flags_stretch_ratio = 1.8
	main.add_child(board_wrap)
	board = SudokuBoard.new()
	board.accent = accent
	board.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	board.size_flags_vertical = Control.SIZE_EXPAND_FILL
	board.cell_pressed.connect(_cell)
	board_wrap.add_child(board)
	board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	active_grid = board_wrap
	var side_panel := PlaygroundUI.panel(PlaygroundUI.mix(accent, Color.WHITE, 0.91), 24, PlaygroundUI.mix(accent, Color.WHITE, 0.52), 2)
	side_panel.custom_minimum_size.x = 310
	side_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.add_child(side_panel)
	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 12)
	side_panel.add_child(side)
	side.add_child(PlaygroundUI.label("选数字填进空格", 24, accent, 700))
	var numbers := GridContainer.new()
	numbers.columns = 3 if engine.size() == 9 else 2
	numbers.add_theme_constant_override("h_separation", 8)
	numbers.add_theme_constant_override("v_separation", 8)
	numbers.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var dimension: int = engine.size()
	for digit in range(1, dimension + 1):
		var button := PlaygroundUI.button(str(digit), accent, func(): _input_digit(digit), "primary")
		button.custom_minimum_size = Vector2(72, 64)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", 28)
		numbers.add_child(button)
		number_buttons.append(button)
	side.add_child(numbers)
	side.add_child(PlaygroundUI.semantic_icon_button("hint", "看提示", accent, _explain_hint, "soft"))
	side.add_child(PlaygroundUI.semantic_icon_button("undo", "撤回", accent, _undo, "soft"))
	side.add_child(PlaygroundUI.semantic_icon_button("erase", "擦掉", accent, _clear_cell, "soft"))
	status = PlaygroundUI.label("先点一个空格，再点数字。", 19, PlaygroundUI.INK_SOFT, 600, true)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	side.add_child(status)
	var filler := Control.new()
	filler.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(filler)
	var nav := HFlowContainer.new()
	nav.add_theme_constant_override("h_separation", 8)
	nav.add_theme_constant_override("v_separation", 8)
	if mode_id == "adventure":
		nav.add_child(PlaygroundUI.semantic_icon_button("back", "关卡", accent, _show_map, "ghost"))
	else:
		nav.add_child(PlaygroundUI.semantic_icon_button("shuffle", "换一题", accent, _confirm_next_puzzle, "ghost"))
	nav.add_child(PlaygroundUI.semantic_icon_button("restart", "重玩", accent, _confirm_restart, "ghost"))
	side.add_child(nav)
	game_tools = side
	_on_immersive_changed(immersive)


func _extra_topbar_actions(row: HBoxContainer) -> void:
	var rules := PlaygroundUI.button("规则", accent, show_game_rules, "soft")
	rules.custom_minimum_size = Vector2(70, 48)
	row.add_child(rules)


func show_game_rules() -> void:
	_show_rules()


func _on_immersive_changed(_value: bool) -> void:
	if game_tools != null and is_instance_valid(game_tools):
		game_tools.show()
	if status != null and is_instance_valid(status):
		status.show()
	if detail != null and is_instance_valid(detail):
		detail.show()


func _filled_count() -> int:
	var count := 0
	for character in str(engine.state.get("values", "")):
		if character != "0":
			count += 1
	return count


func _refresh() -> void:
	if board == null or not is_instance_valid(board) or engine.state.is_empty():
		return
	if engine.state.phase == "finished" and not _result_visible:
		_show_result()
	board.interactive = not paused and str(engine.state.phase) == "playing"
	board.update_board(engine)
	var selected := int(engine.state.get("selected", -1))
	if selected < 0:
		status.text = "先点一个空格。同行、同列和同宫会一起亮起。"
	else:
		var digit := int(str(engine.state.get("values", ""))[selected])
		if digit <= 0:
			status.text = "空格已选好，点右边数字填入。"
		elif engine.conflicts(selected, digit):
			status.text = "这个 %s 和圈出的格子重复，可以撤回或擦掉。" % digit
		else:
			status.text = "这一格现在填的是 %s。" % digit
	if int(engine.state.get("mistakes", 0)) > 0:
		status.text += "\n本局已发现 %s 次重复。" % int(engine.state.mistakes)


func _cell(position: int) -> void:
	if paused or str(engine.state.phase) != "playing":
		return
	if engine.is_given(position):
		engine.state.selected = position
		_save("查看数独题目数字")
		_refresh()
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
	_explain_hint()


func _explain_hint() -> void:
	if paused:
		return
	var result: Dictionary = engine.hint_analysis()
	if not bool(result.ok):
		show_toast(str(result.message))
		return
	SfxMap.play(&"select")
	_save("正在查看数独提示")
	_refresh()
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	var hint_icon := ArtLibrary.semantic_picture("hint", "ui", Vector2(56, 56))
	hint_icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	body.add_child(hint_icon)
	body.add_child(PlaygroundUI.label(str(result.get("reason", "从候选最少的格子开始观察。")), 20, PlaygroundUI.INK, 600, true))
	if int(result.get("digit", -1)) > 0:
		body.add_child(PlaygroundUI.label("提示数字：%s" % int(result.digit), 24, accent, 700))
	var hint_position := int(result.get("position", -1))
	var cell_empty := hint_position >= 0 and str(engine.state.get("values", ""))[hint_position] == "0"
	var actions := [{"text":"自己再想想", "icon":"back", "kind":"soft", "callback":func(): _close_top_modal()}]
	if cell_empty:
		actions.append({"text":"帮我填一格", "icon":"check", "kind":"primary", "callback":_fill_hint})
	else:
		actions.append({"text":"知道了", "icon":"check", "kind":"primary", "callback":func(): _close_top_modal()})
	open_modal("先看线索，再决定", body, actions, "提示会留下圈线")


func _fill_hint() -> void:
	_close_top_modal()
	var result := engine.fill_hint()
	if not bool(result.ok):
		show_toast(str(result.get("message", "先看一次提示")))
		return
	SfxMap.play(&"select")
	if bool(result.get("complete", false)):
		engine.finish()
	_save("使用数独提示")
	_refresh()
	if engine.state.phase == "finished":
		_show_result()


func _undo() -> void:
	if paused or not engine.undo_last():
		show_toast("现在没有可以撤回的填写")
		return
	_save("撤回了一个数字")
	_refresh()


func _confirm_next_puzzle() -> void:
	if _puzzles().is_empty():
		return
	open_modal("换一道新题？", PlaygroundUI.label("当前这道题的填写会被替换。已经完成的关卡和其他游戏会保留。", 20, PlaygroundUI.INK_SOFT, 500, true), [
		{"text":"继续这题", "kind":"soft", "callback":func(): _close_top_modal()},
		{"text":"换一题", "kind":"primary", "callback":_change_puzzle},
	], "当前这题会被替换")


func _change_puzzle() -> void:
	_close_top_modal()
	_create((_puzzle_index + 1) % maxi(1, _puzzles().size()))
	_build_session()
	_refresh()


func _restart() -> void:
	_result_visible = false
	_create(_puzzle_index)
	_build_session()
	_refresh()


func _confirm_restart() -> void:
	open_modal("重玩这题？", PlaygroundUI.label("当前填写会被清空，重玩同一道题；已完成关卡和其他游戏会保留。", 20, PlaygroundUI.INK_SOFT, 500, true), [
		{"text":"继续这题", "kind":"soft", "callback":func(): _close_top_modal()},
		{"text":"清空重玩", "kind":"primary", "callback":_restart_from_confirm},
	], "数独")


func _show_rules() -> void:
	var lines := [
		"先点一个空格，再点右边的数字。",
		"每一行、每一列、每个粗线小宫里，数字都不能重复。",
		"四宫格用 1 到 4，九宫格用 1 到 9；题目给出的数字会用主题色保持醒目。",
		"填错了会用橙色圈出关联格，可以“撤回”或“擦掉”。",
		"看提示会先说明线索；需要时再点“帮我填一格”。",
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
	if not bool(state.get("reported", false)):
		state.reported = true
		var stars := 3 if int(state.hints) == 0 else 2 if int(state.hints) <= 1 else 1
		SaveStore.complete_level(str(players[0].id), game_id, level_id, stars, mode_id)
		SaveStore.record_outcome(str(players[0].id), game_id, "win", stars, 1, 1, {"logic":{"correct":1,"answered":1}}, str(state.get("sessionId", "sudoku")))
		_save("数独完成", false)
	if _result_visible:
		return
	_result_visible = true
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	var trophy := ArtLibrary.semantic_picture("trophy", "ui", Vector2(88, 88))
	trophy.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	body.add_child(trophy)
	body.add_child(PlaygroundUI.label("数字都排好啦！", 24, accent, 700, true))
	var actions := [
		{"text":"回看棋盘", "kind":"soft", "callback":func(): _result_visible = false; _close_top_modal()},
		{"text":"再来一题", "icon":"next", "kind":"primary", "callback":_show_next_puzzle},
	]
	if mode_id == "adventure":
		actions.insert(1, {"text":"关卡地图", "icon":"back", "kind":"soft", "callback":func(): _result_visible = false; _close_top_modal(); _show_map()})
	open_modal("数独完成", body, actions, "本局已自动保存")


func _show_next_puzzle() -> void:
	_result_visible = false
	_close_top_modal()
	_create((_puzzle_index + 1) % maxi(1, _puzzles().size()))
	_build_session()
	_refresh()


func _restart_from_confirm() -> void:
	_close_top_modal()
	if paused:
		toggle_pause(false)
	_restart()


func _save(note: String, resume: bool = true) -> void:
	if engine.state.is_empty():
		return
	SaveStore.save_state(game_id, str(players[0].id), engine.snapshot(), note, resume and str(engine.state.get("phase", "")) == "playing")
