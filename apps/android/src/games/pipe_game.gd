class_name NativePipeGame
extends NativeGameScreen

const CONTENT_PATH := "res://content/pipes.json"
const FALLBACK_TITLE := "水管工坊"
const FALLBACK_ACCENT := "#2b7d76"
const FALLBACK_SOFT := "#dcefec"
const BAND_LABELS := {"easy": "轻松花圃", "normal": "标准花园", "challenge": "挑战庭院"}
const BAND_AGES := {"easy": "推荐 4–6 岁", "normal": "推荐 7–9 岁", "challenge": "推荐 10–12 岁"}

var engine := PipeRules.new()
var board: PipeBoard
var game_header: Control
var game_tools: Control
var status: Label
var view := "map"
var soft_accent := Color(FALLBACK_SOFT)
var _levels_cache: Array = []
var _result_visible := false


func _ready() -> void:
	if game_id.is_empty():
		game_id = "pipes"
	if str(game_meta.get("title", "")).strip_edges().is_empty():
		game_meta.title = FALLBACK_TITLE
	if str(game_meta.get("accent", "")).strip_edges().is_empty():
		game_meta.accent = FALLBACK_ACCENT
		accent = PlaygroundUI.color(FALLBACK_ACCENT)
	if str(game_meta.get("soft", "")).strip_edges().is_empty():
		game_meta.soft = FALLBACK_SOFT
	soft_accent = PlaygroundUI.color(str(game_meta.get("soft", FALLBACK_SOFT)))
	if mode_id not in ["adventure", "classic"]:
		mode_id = "adventure" if players.size() <= 1 else "classic"
	levels_loaded()
	SaveStore.set_context(game_id, mode_id, players.map(func(player): return str(player.id)))
	build_shell()
	var stored := SaveStore.load_state(game_id, players.map(func(player): return str(player.id)))
	var had_stored := not stored.is_empty()
	stored.modeId = mode_id
	if stored.get("players") is Array and engine.restore(stored):
		players = engine.state.players.duplicate(true)
		level_id = int(engine.state.get("levelId", 1))
		view = str(engine.state.get("view", "board"))
		if engine.state.phase == "finished" and not bool(stored.get("resume", true)):
			_show_map()
		elif view == "map":
			_show_map()
		else:
			_build_board()
			_refresh()
			call_deferred("begin_lesson")
	else:
		engine.state = {}
		var recovery_level := int(stored.get("levelId", 0)) if had_stored else 0
		if recovery_level >= 1 and recovery_level <= levels_loaded().size():
			if _start_level(recovery_level, int(stored.get("retries", 0))):
				show_toast("上次的水管存档不完整，已从第 %s 关开头重新开始。" % recovery_level, 3.0)
		else:
			_show_map()


func preview_ready() -> void:
	_refresh()


func levels_loaded() -> Array:
	if not _levels_cache.is_empty():
		return _levels_cache
	if not FileAccess.file_exists(CONTENT_PATH):
		return []
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONTENT_PATH))
	if not parsed is Dictionary or int(parsed.get("version", 0)) < 1 or not parsed.get("levels") is Array:
		return []
	_levels_cache = parsed.levels.filter(func(entry): return entry is Dictionary)
	return _levels_cache


func _level_for(number: int) -> Dictionary:
	var levels := levels_loaded()
	if number <= 0 or number > levels.size():
		return {}
	return levels[number - 1]


func _show_map() -> void:
	view = "map"
	_result_visible = false
	Speech.stop()
	PlaygroundUI.clear(content_root)
	var levels := levels_loaded()
	if levels.is_empty():
		var empty := PlaygroundUI.panel(PlaygroundUI.mix(accent, Color.WHITE, 0.91), 24, PlaygroundUI.TOOL_LINE, 2)
		var empty_box := VBoxContainer.new()
		empty_box.add_theme_constant_override("separation", 10)
		empty_box.add_child(PlaygroundUI.label("花园地图还在准备中", 24, accent, 700, true))
		empty_box.add_child(PlaygroundUI.label("水管内容还没有装进这台平板，请稍后再来看看。", 18, PlaygroundUI.INK_SOFT, 500, true))
		empty.add_child(empty_box)
		content_root.add_child(empty)
		return
	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation", 12)
	var title := PlaygroundUI.label("今天去哪个花园？", 30, accent, 700, true)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(title)
	heading.add_child(PlaygroundUI.chip("36 座小花园", accent))
	heading.add_child(PlaygroundUI.semantic_icon_button("rules", "怎么玩", accent, show_help, "soft"))
	content_root.add_child(heading)
	var mode_copy := "一个人顺着水流，把每座花圃都浇开花。" if mode_id == "adventure" else "两个人轮流转动同一套水管，一起把花园浇开花，不比较输赢。"
	if players.size() == 2:
		mode_copy = "%s 和 %s 一起合作。每次转动后换另一位小伙伴。" % [
			str(players[0].get("name", "小朋友")),
			str(players[1].get("name", "小伙伴")),
		]
	content_root.add_child(PlaygroundUI.label(mode_copy, 18, PlaygroundUI.INK_SOFT, 500, true))
	var scroll := SmoothScrollContainer.create()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	var groups := VBoxContainer.new()
	groups.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	groups.add_theme_constant_override("separation", 18)
	for band in ["easy", "normal", "challenge"]:
		groups.add_child(_map_group(band, levels))
	scroll.add_child(groups)
	content_root.add_child(scroll)
	if not engine.state.is_empty():
		engine.state.view = "map"
		_save("正在选择花园")


func _map_group(band: String, levels: Array) -> Control:
	var section := VBoxContainer.new()
	section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	section.add_theme_constant_override("separation", 10)
	var label_row := HBoxContainer.new()
	label_row.add_theme_constant_override("separation", 10)
	var dot := ColorRect.new()
	dot.color = PlaygroundUI.mix(accent, Color.WHITE, 0.28 if band == "challenge" else 0.48)
	dot.custom_minimum_size = Vector2(12, 12)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	label_row.add_child(dot)
	label_row.add_child(PlaygroundUI.label(str(BAND_LABELS.get(band, band)), 21, accent, 700))
	label_row.add_child(PlaygroundUI.label(str(BAND_AGES.get(band, "")), 15, PlaygroundUI.INK_SOFT, 500))
	section.add_child(label_row)
	var grid := GridContainer.new()
	var viewport_width := get_viewport_rect().size.x
	grid.columns = 3 if viewport_width <= 1180.0 else 4 if viewport_width < 1500.0 else 6
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	for index in levels.size():
		var level: Dictionary = levels[index]
		if str(level.get("band", "")) != band:
			continue
		var number := index + 1
		var unlocked := _level_unlocked(number)
		var stars := _level_stars(number)
		var resumable := _can_resume_level(number)
		var state_text := "先完成前一关" if not unlocked else "可以开始"
		if unlocked and resumable:
			state_text = "继续这一关"
		elif unlocked and stars > 0:
			state_text = "已获 %s / 3 星" % stars
		var button := PlaygroundUI.semantic_icon_button(
			"play" if unlocked else "lock",
			"第 %s 关\n%s\n%s" % [number, str(level.get("title", "花园")), state_text],
			accent,
			_choose_level.bind(number),
			"soft" if unlocked else "ghost",
			17
		)
		button.custom_minimum_size = Vector2(0, 112)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.disabled = not unlocked
		grid.add_child(button)
	section.add_child(grid)
	return section


func _level_unlocked(number: int) -> bool:
	if mode_id == "classic":
		return true
	if players.is_empty():
		return false
	return SaveStore.level_unlocked(str(players[0].id), game_id, number, mode_id)


func _level_stars(number: int) -> int:
	var stars := 0
	for player in players:
		stars = maxi(stars, int(SaveStore.learning(str(player.id), game_id, mode_id).stars.get(str(number), 0)))
	return clampi(stars, 0, 3)


func _can_resume_level(number: int) -> bool:
	return (
		not engine.state.is_empty()
		and int(engine.state.get("levelId", -1)) == number
		and str(engine.state.get("phase", "")) == "playing"
		and int(engine.state.get("pipeVersion", 0)) == PipeRules.VERSION
	)


func _choose_level(number: int) -> void:
	if not _level_unlocked(number):
		SfxMap.play(&"error")
		show_toast("先完成这个花圃里的前一关，再来挑战。")
		return
	SfxMap.play(&"tap")
	if _can_resume_level(number):
		level_id = number
		engine.state.view = "board"
		view = "board"
		_build_board()
		_refresh()
		_save("继续浇灌花园")
		return
	if str(engine.state.get("phase", "")) == "playing":
		guard_level_switch(number, func(): _start_level(number, 0))
		return
	_start_level(number, 0)


func _start_level(number: int, retries: int = 0) -> bool:
	var entry := _level_for(number)
	if entry.is_empty():
		show_toast("这一关的内容还没有准备好。")
		return false
	level_id = number
	_result_visible = false
	engine.create_session({
		"gameId": game_id,
		"modeId": mode_id,
		"players": players.duplicate(true),
		"levelId": number,
		"level": entry,
		"retries": maxi(0, retries),
		"seed": Time.get_ticks_usec(),
	})
	if str(engine.state.get("phase", "")) != "playing":
		engine.state = {}
		show_toast("这一关的水管内容不完整，先回到地图选一关。")
		_show_map()
		return false
	session_id = str(engine.state.sessionId)
	view = "board"
	_build_board()
	_refresh()
	_save("开始浇灌花园")
	begin_lesson()
	return true


func _build_board() -> void:
	view = "board"
	PlaygroundUI.clear(content_root)
	game_header = HBoxContainer.new()
	game_header.add_theme_constant_override("separation", 10)
	if players.size() >= 2:
		game_header.add_child(_player_pill(players[0], true))
		var middle := CenterContainer.new()
		middle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		middle.add_child(PlaygroundUI.chip("第 %s 关 · %s" % [level_id, engine.level_title()], accent))
		game_header.add_child(middle)
		game_header.add_child(_player_pill(players[1], false))
	else:
		game_header.add_child(PlaygroundUI.chip("第 %s 关 · %s" % [level_id, engine.level_title()], accent))
		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		game_header.add_child(spacer)
		game_header.add_child(PlaygroundUI.chip("单人引水", accent))
	content_root.add_child(game_header)
	board = PipeBoard.new()
	board.accent = accent
	board.soft = soft_accent
	board.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	board.size_flags_vertical = Control.SIZE_EXPAND_FILL
	board.piece_tapped.connect(_rotate_pipe)
	content_root.add_child(board)
	status = PlaygroundUI.label("", 19, PlaygroundUI.INK, 600, true)
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.custom_minimum_size.y = 44
	content_root.add_child(status)
	game_tools = HFlowContainer.new()
	game_tools.alignment = FlowContainer.ALIGNMENT_CENTER
	game_tools.add_theme_constant_override("h_separation", 10)
	game_tools.add_theme_constant_override("v_separation", 6)
	var hint_button := PlaygroundUI.semantic_icon_button("hint", "看提示", accent, _hint, "soft", 17)
	hint_button.custom_minimum_size = Vector2(142, 48)
	game_tools.add_child(hint_button)
	var restart_button := PlaygroundUI.semantic_icon_button("restart", "重开这一关", accent, _confirm_restart, "soft", 17)
	restart_button.custom_minimum_size = Vector2(170, 48)
	game_tools.add_child(restart_button)
	var map_button := PlaygroundUI.semantic_icon_button("game", "关卡地图", accent, _show_map, "ghost", 17)
	map_button.custom_minimum_size = Vector2(142, 48)
	game_tools.add_child(map_button)
	content_root.add_child(game_tools)
	board.bind(engine)
	_on_immersive_changed(immersive)


func _on_immersive_changed(_value: bool) -> void:
	if game_header != null and is_instance_valid(game_header):
		game_header.hide()
	if game_tools != null and is_instance_valid(game_tools):
		game_tools.show()
	if status != null and is_instance_valid(status):
		status.show()


func _rotate_pipe(index: int) -> void:
	if paused or _result_visible:
		return
	var result := engine.handle_input({"type": "rotate", "index": index})
	if not bool(result.get("ok", false)):
		SfxMap.play(&"error")
		show_toast(str(result.get("message", "这截水管转不动")))
		if board != null and is_instance_valid(board):
			board.queue_redraw()
		return
	SfxMap.play(&"move")
	FeedbackKit.haptic(6)
	_save("转动水管")
	_refresh()
	if bool(result.get("completed", false)):
		call_deferred("_show_result")
	elif engine.is_cooperative():
		AudioFX.play("turn")
		show_toast("轮到 %s 转水管" % _player_name(engine.current_player_index()))


func _hint() -> void:
	if paused or _result_visible:
		return
	var result := engine.handle_input({"type": "hint"})
	if not bool(result.get("ok", false)):
		SfxMap.play(&"error")
		show_toast(str(result.get("message", "先找一截方向不对的水管")))
		return
	SfxMap.play(&"select")
	_save("查看水管提示")
	_refresh()
	var message := str(result.get("message", "看看发光的水管。"))
	show_toast(message, 3.2)
	Speech.speak(message, "pipes-hint")


func _refresh() -> void:
	if board == null or not is_instance_valid(board) or engine.state.is_empty():
		return
	board.interactive = not paused and str(engine.state.get("phase", "")) == "playing"
	board.queue_redraw()
	var water_line := "已浇水 %s / %s 朵花圃 · 漏水 %s 处 · 转动 %s 次" % [
		engine.wet_goal_count(),
		engine.goal_count(),
		engine.leak_count(),
		int(engine.state.get("turns", 0)),
	]
	if engine.is_hint_piece(int(engine.state.get("hintIndex", -1))):
		var piece := engine.piece_at(int(engine.state.hintIndex))
		water_line = "提示：左边第 %s 列、上边第 %s 行的水管在发光。" % [int(piece.x) + 1, int(piece.y) + 1]
	elif engine.leak_count() > 0:
		water_line = "已浇水 %s / %s 朵 · 还有 %s 处接口在漏水。" % [
			engine.wet_goal_count(),
			engine.goal_count(),
			engine.leak_count(),
		]
	if engine.is_cooperative():
		water_line = "轮到 %s · %s" % [_player_name(engine.current_player_index()), water_line]
	status.text = water_line
	if str(engine.state.get("phase", "")) == "finished" and not _result_visible:
		call_deferred("_show_result")


func _player_name(index: int) -> String:
	if index >= 0 and index < players.size():
		return str(players[index].get("name", "小朋友"))
	return "小朋友"


func _extra_topbar_actions(row: HBoxContainer) -> void:
	var rules := PlaygroundUI.button("规则", accent, show_game_rules, "soft")
	rules.custom_minimum_size = Vector2(72, 48)
	row.add_child(rules)


func show_game_rules() -> void:
	_show_rules()


func _extra_pause_actions() -> Array:
	if view != "board":
		return []
	return [{
		"text": "关卡地图",
		"icon": "game",
		"kind": "soft",
		"callback": func(): _close_pause_tools(); _show_map(),
	}]


func _confirm_restart() -> void:
	if view != "board":
		_close_pause_tools()
		show_toast("先选一座花园，再开始转动水管。")
		return
	var retries := int(engine.state.get("retries", 0)) + 1
	var text := PlaygroundUI.label(
		"这一关的水管会回到起点，重试次数会加一。已经得到的花园星星和其他游戏会保留。",
		19,
		PlaygroundUI.INK_SOFT,
		500,
		true
	)
	open_modal("重开这一关？", text, [
		{"text": "继续引水", "icon": "back", "kind": "soft", "callback": func(): _close_top_modal()},
		{"text": "重新开始", "icon": "restart", "kind": "primary", "callback": _restart_from_confirm.bind(retries)},
	], "水管工坊")


func _restart_from_confirm(retries: int) -> void:
	var was_paused := paused
	_suppress_resume_on_close = was_paused
	_close_all_game_dialogs()
	if was_paused:
		paused = false
		_pause_root_layer = null
		MotionKit.set_paused_tree(self, false)
		pause_changed.emit(false)
	_suppress_resume_on_close = false
	SfxMap.play(&"drop")
	_start_level(level_id, retries)


func show_help() -> void:
	if not paused and view == "board":
		_open_pause_tools()
	Speech.stop()
	var lines := [
		"点一下水管，它会顺时针转九十度。",
		"让水源和下一截水管的接口相合，水流会一路亮起来。",
		"接口没对齐会漏水；把所有花圃都浇开花就完成。",
		"铜色卡扣表示固定水管，不能转动。提示会点亮一截需要调整的水管。",
	]
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	for index in lines.size():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		row.add_child(ArtLibrary.semantic_picture(["next", "hint", "star", "lock"][index], "ui", Vector2(42, 42)))
		var copy := PlaygroundUI.label(lines[index], 19, PlaygroundUI.INK, 600, true)
		copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(copy)
		body.add_child(row)
	var spoken := "水管工坊玩法。" + " ".join(PackedStringArray(lines))
	Speech.speak(spoken, "game-help")
	open_modal("怎么玩", body, [
		{"text": "三步小课堂", "icon": "play", "kind": "soft", "callback": func(): _close_top_modal(); call_deferred("begin_lesson", true)},
		{"text": "再读一遍", "icon": "repeat", "kind": "soft", "callback": func(): Speech.repeat()},
		{"text": "知道了", "icon": "check", "kind": "primary", "callback": func(): Speech.stop_owner("game-help"); _close_top_modal()},
	], "接对接口，小花就会开")


func _show_rules() -> void:
	var lines := [
		"点一截可以转的水管，它每次顺时针转九十度。",
		"水源旁边亮起的水，会顺着接口相合的水管往前走。",
		"接口没对齐就会漏水；把整条水路接顺，花圃就会开花。",
		"所有花圃都喝到水就完成。固定水管带铜色卡扣，不能转动。",
		"提示会点亮一截方向不对的水管；重开这一关会把重试次数加一。",
	]
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	for index in lines.size():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		row.add_child(PlaygroundUI.chip(str(index + 1), accent))
		var copy := PlaygroundUI.label(lines[index], 18, PlaygroundUI.INK_SOFT, 500, true)
		copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(copy)
		body.add_child(row)
	Speech.speak(" ".join(PackedStringArray(lines)), "pipes-help")
	open_modal("水管工坊规则", body, [
		{"text": "读给我听", "icon": "speech", "kind": "soft", "callback": func(): Speech.repeat()},
		{"text": "知道了", "icon": "check", "kind": "primary", "callback": func(): _close_top_modal()},
	], "接对接口，小花就会开")


func begin_lesson(force: bool = false) -> void:
	if not force:
		return
	if not paused and view == "board":
		_open_pause_tools()
	lesson_texts = [
		"点一下水管，它会顺时针转九十度。",
		"让水源和下一截水管的接口对齐，水就会亮起来。",
		"所有花圃都开花就完成。看到漏水，再慢慢调整。",
	]
	_lesson_icons = ["next", "hint", "star"]
	call("_show_lesson_page", 0)


func _show_result() -> void:
	if engine.state.is_empty() or str(engine.state.get("phase", "")) != "finished":
		return
	if _record_completion_if_needed():
		_save("花园浇灌完成", false)
	if _result_visible:
		return
	_result_visible = true
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	var trophy := ArtLibrary.semantic_picture("trophy", "ui", Vector2(88, 88))
	trophy.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	body.add_child(trophy)
	var result_title := "合作引水成功！" if mode_id == "classic" else "全部花圃都开花啦！"
	var title := PlaygroundUI.label(result_title, 24, accent, 700, true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(title)
	var result_copy := PlaygroundUI.label(
		"转动 %s 次 · 提示 %s 次 · 重开 %s 次" % [
			int(engine.state.get("turns", 0)),
			int(engine.state.get("hints", 0)),
			int(engine.state.get("retries", 0)),
		],
		18,
		PlaygroundUI.INK_SOFT,
		500,
		true
	)
	result_copy.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(result_copy)
	var stars_row := HBoxContainer.new()
	stars_row.alignment = BoxContainer.ALIGNMENT_CENTER
	for index in 3:
		var star := ArtLibrary.semantic_picture("star", "ui", Vector2(38, 38))
		star.modulate = Color.WHITE if index < int(engine.state.get("stars", 0)) else Color(1, 1, 1, 0.24)
		stars_row.add_child(star)
	body.add_child(stars_row)
	var can_next := level_id < levels_loaded().size() and _level_unlocked(level_id + 1)
	var actions := [
		{
			"text": "回看花园",
			"icon": "back",
			"kind": "soft",
			"callback": func(): _result_visible = false; Speech.stop_owner("pipes-result"); _close_top_modal(),
		},
	]
	if can_next:
		actions.append({
			"text": "关卡地图",
			"icon": "game",
			"kind": "soft",
			"callback": func(): Speech.stop_owner("pipes-result"); _close_top_modal(); _show_map(),
		})
		actions.append({
			"text": "下一关",
			"icon": "next",
			"kind": "primary",
			"callback": func(): Speech.stop_owner("pipes-result"); _close_top_modal(); _choose_level(level_id + 1),
		})
	else:
		actions.append({
			"text": "回游戏大厅",
			"icon": "home",
			"kind": "primary",
			"callback": func(): Speech.stop_owner("pipes-result"); _close_all_game_dialogs(); back_requested.emit(),
		})
	open_modal("水管工坊完成", body, actions, "本局已自动保存")
	SfxMap.play(&"win")
	FeedbackKit.haptic(14)
	var spoken := "全部花圃都喝到水了。"
	if mode_id == "classic" and players.size() >= 2:
		spoken = "%s和%s一起把全部花圃都浇开花啦。" % [
			str(players[0].get("name", "小朋友")),
			str(players[1].get("name", "小伙伴")),
		]
	Speech.speak(spoken, "pipes-result")


func _record_completion_if_needed() -> bool:
	if engine.state.is_empty() or str(engine.state.get("phase", "")) != "finished":
		return false
	if bool(engine.state.get("reported", false)):
		return false
	engine.state.reported = true
	var stars := int(engine.state.get("stars", engine.stars()))
	for index in players.size():
		var player_id := str(players[index].id)
		SaveStore.complete_level(player_id, game_id, level_id, stars, mode_id)
		SaveStore.record_outcome(
			player_id,
			game_id,
			"win" if mode_id == "adventure" else "played",
			stars,
			engine.goal_count(),
			engine.goal_count(),
			{"logic": {"correct": engine.goal_count(), "answered": engine.goal_count()}},
			str(engine.state.get("sessionId", "pipes"))
		)
	return true


func _save(note: String = "实时自动保存水管进度", resume: bool = true) -> void:
	if engine.state.is_empty() or players.is_empty():
		return
	_record_completion_if_needed()
	engine.state.view = view
	SaveStore.save_state(
		game_id,
		str(players[0].id),
		engine.snapshot(),
		note,
		resume and str(engine.state.get("phase", "")) == "playing" and view in ["board", "map"]
	)
