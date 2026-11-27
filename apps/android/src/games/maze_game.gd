class_name NativeMazeGame
extends NativeGameScreen

const RULES = preload("res://src/games/maze_rules.gd")
const FIELD = preload("res://src/ui/maze_field.gd")
const CONTENT_PATH := "res://content/maze.json"
const FALLBACK_TITLE := "迷宫小探险"
const FALLBACK_ACCENT := "#5d7436"
const FALLBACK_SOFT := "#edf2dd"
const BAND_LABELS := {
	"easy": "轻轻探路",
	"normal": "绕路探险",
	"challenge": "勇敢寻宝",
}
const BAND_AGES := {
	"easy": "推荐 4–6 岁",
	"normal": "推荐 7–9 岁",
	"challenge": "推荐 10–12 岁",
}

var engine = RULES.new()
var field = null
var game_header: Control
var status: Label
var game_tools: Control
var view := "map"
var soft_accent := Color(FALLBACK_SOFT)
var _levels_cache: Array = []
var _catalog_issues: Array[String] = []
var _result_visible := false
var _save_clock := 0.0
var _last_patrol_resets := 0


func _ready() -> void:
	if game_id.is_empty():
		game_id = "maze"
	if str(game_meta.get("title", "")).strip_edges().is_empty():
		game_meta.title = FALLBACK_TITLE
	if str(game_meta.get("accent", "")).strip_edges().is_empty():
		game_meta.accent = FALLBACK_ACCENT
	if str(game_meta.get("soft", "")).strip_edges().is_empty():
		game_meta.soft = FALLBACK_SOFT
	accent = PlaygroundUI.color(str(game_meta.get("accent", FALLBACK_ACCENT)))
	soft_accent = PlaygroundUI.color(str(game_meta.get("soft", FALLBACK_SOFT)))
	if mode_id not in ["adventure", "classic"]:
		mode_id = "adventure" if players.size() <= 1 else "classic"
	_load_catalog()
	SaveStore.set_context(game_id, mode_id, players.map(func(player): return str(player.id)))
	build_shell()
	pause_changed.connect(_on_pause_changed)
	set_process(true)
	var stored := SaveStore.load_state(game_id, players.map(func(player): return str(player.id)))
	var had_stored := not stored.is_empty()
	if had_stored:
		stored.modeId = mode_id
		if engine.restore(stored):
			players = engine.state.players.duplicate(true)
			level_id = int(engine.state.get("levelId", 1))
			view = str(engine.state.get("view", "board"))
			_last_patrol_resets = int(engine.state.get("patrolResets", 0))
			if str(engine.state.get("phase", "")) == "finished" and not bool(stored.get("resume", true)):
				_show_map()
				return
			if view == "map":
				_show_map()
				return
			_build_board()
			_refresh()
			if str(engine.state.get("phase", "")) == "finished":
				_show_result()
			return
	engine.state = {}
	var recovery_level := int(stored.get("levelId", 0)) if had_stored else 0
	if recovery_level >= 1 and not _find_level(recovery_level).is_empty():
		if _start_level(recovery_level, false):
			show_toast("上次的迷宫记录不完整，已从第 %s 关开头重新摆放。" % recovery_level, 3.2)
			return
	_show_map()


func _process(delta: float) -> void:
	if paused or engine.state.is_empty() or str(engine.state.get("phase", "")) != "playing":
		return
	var before_resets := int(engine.state.get("patrolResets", 0))
	var changed: bool = engine.tick(delta)
	if changed:
		var after_resets := int(engine.state.get("patrolResets", 0))
		if after_resets > before_resets:
			_last_patrol_resets = after_resets
			SfxMap.play(&"error")
			FeedbackKit.haptic(9)
			var message := str(engine.state.get("reason", "巡逻小灯发现了你，回到最近的检查点。"))
			show_toast(message, 2.6)
			Speech.speak(message, "maze-feedback")
			_save("巡逻小灯送回检查点")
		_refresh()
	_save_clock += maxf(0.0, delta)
	if _save_clock >= 2.0:
		_save_clock = 0.0
		_save("巡逻继续，保存当前位置", true)


func _load_catalog() -> void:
	_catalog_issues.clear()
	_levels_cache.clear()
	var parsed: Variant = null
	if FileAccess.file_exists(CONTENT_PATH):
		parsed = JSON.parse_string(FileAccess.get_file_as_string(CONTENT_PATH))
	if not parsed is Dictionary:
		_catalog_issues.append("找不到 maze.json 或内容格式不正确")
		return
	var validation: Dictionary = RULES.validate_catalog(parsed)
	for issue in validation.get("issues", []):
		_catalog_issues.append(str(issue))
	if not bool(validation.get("ok", false)):
		for issue in _catalog_issues:
			push_warning("迷宫小探险内容：" + issue)
		return
	_levels_cache = validation.get("validLevels", []).duplicate(true)
	for issue in _catalog_issues:
		push_warning("迷宫小探险内容：" + issue)


func _mode_levels() -> Array:
	var result: Array = []
	for raw in _levels_cache:
		if raw is Dictionary and str(raw.get("mode", "")) == mode_id:
			result.append(raw)
	result.sort_custom(func(first: Dictionary, second: Dictionary):
		return int(first.get("levelNumber", 0)) < int(second.get("levelNumber", 0))
	)
	return result


func _find_level(number: int) -> Dictionary:
	for raw in _levels_cache:
		if raw is Dictionary and str(raw.get("mode", "")) == mode_id and int(raw.get("levelNumber", 0)) == number:
			return raw.duplicate(true)
	return {}


func _unlocked(number: int) -> bool:
	if mode_id == "classic":
		return true
	if players.is_empty():
		return false
	return SaveStore.level_unlocked(str(players[0].id), game_id, number, mode_id)


func _stars_for(number: int) -> int:
	var stars := 0
	for player in players:
		var learning := SaveStore.learning(str(player.id), game_id, mode_id)
		stars = maxi(stars, int(learning.get("stars", {}).get(str(number), 0)))
	return clampi(stars, 0, 3)


func _can_resume_level(number: int) -> bool:
	return (
		not engine.state.is_empty()
		and str(engine.state.get("phase", "")) == "playing"
		and str(engine.state.get("modeId", "")) == mode_id
		and int(engine.state.get("levelId", 0)) == number
	)


func _show_map() -> void:
	Speech.stop()
	_on_pause_changed(false)
	view = "map"
	_result_visible = false
	PlaygroundUI.clear(content_root)
	field = null
	var levels := _mode_levels()
	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation", 12)
	var copy := VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.add_theme_constant_override("separation", 2)
	copy.add_child(PlaygroundUI.label("今天从哪张藏宝图出发？", 30, accent, 700, true))
	copy.add_child(PlaygroundUI.label(_map_subtitle(), 18, PlaygroundUI.INK_SOFT, 500, true))
	heading.add_child(copy)
	heading.add_child(PlaygroundUI.chip("一起探路 · 不计输赢" if mode_id == "classic" else "单人探险", accent))
	heading.add_child(PlaygroundUI.semantic_icon_button("rules", "怎么玩", accent, show_help, "soft"))
	content_root.add_child(heading)
	if not _catalog_issues.is_empty():
		var warning := PlaygroundUI.panel(PlaygroundUI.mix(accent, Color.WHITE, 0.92), 16, PlaygroundUI.mix(accent, Color.WHITE, 0.48), 1)
		warning.add_child(PlaygroundUI.label("迷宫内容有 %s 处需要检查，只显示完整可玩的关卡。" % _catalog_issues.size(), 16, PlaygroundUI.INK_SOFT, 600, true))
		content_root.add_child(warning)
	if levels.is_empty():
		var empty := PlaygroundUI.panel(PlaygroundUI.mix(soft_accent, Color.WHITE, 0.30), 24, PlaygroundUI.TOOL_LINE, 2)
		var empty_box := VBoxContainer.new()
		empty_box.add_theme_constant_override("separation", 10)
		empty_box.add_child(PlaygroundUI.label("藏宝图还在准备中", 24, accent, 700, true))
		empty_box.add_child(PlaygroundUI.label("小钥匙和星徽还没有装进这台平板，请稍后再来看看。", 18, PlaygroundUI.INK_SOFT, 500, true))
		empty.add_child(empty_box)
		content_root.add_child(empty)
		return
	var entries: Array = []
	var active_level := level_id if _can_resume_level(level_id) else -1
	for raw in levels:
		var number := int(raw.get("levelNumber", 0))
		if number <= 0:
			continue
		var patrol_count: Array = raw.get("patrols", [])
		var star_count: Array = raw.get("stars", [])
		entries.append({
			"id": number,
			"title": str(raw.get("title", "迷宫")),
			"subtitle": "%s · %s · 星徽 %s · 巡逻 %s" % [
				str(BAND_LABELS.get(str(raw.get("band", "")), "探险")),
				str(BAND_AGES.get(str(raw.get("band", "")), "")),
				star_count.size(),
				patrol_count.size(),
			],
			"locked": not _unlocked(number),
			"stars": _stars_for(number),
			"in_progress": number == active_level,
		})
	var browser := GameBrowser.new()
	browser.configure(entries, {
		"title": "探险地图册",
		"subtitle": "每条路线都藏着小钥匙、星徽和会按时巡逻的小灯；迷路也不会丢进度。",
		"accent": accent,
	})
	browser.entry_selected.connect(func(number: Variant): _choose_level(int(number)))
	content_root.add_child(browser)
	if not engine.state.is_empty():
		engine.state.view = view
		_save("正在选择迷宫")


func _map_subtitle() -> String:
	if mode_id == "classic":
		if players.size() >= 2:
			return "%s 和 %s 轮流走一格，共用钥匙、小门和星徽。" % [
				str(players[0].get("name", "小朋友")),
				str(players[1].get("name", "小伙伴")),
			]
		return "两个人轮流走一格，共用同一张藏宝图。"
	var name := str(players[0].get("name", "小探险家")) if not players.is_empty() else "小探险家"
	return "%s 一个人慢慢找，经过小旗会记住检查点。" % name


func _choose_level(number: int) -> void:
	if not _unlocked(number):
		SfxMap.play(&"error")
		show_toast("先完成前一关，再来走这张藏宝图。")
		return
	SfxMap.play(&"tap")
	if _can_resume_level(number):
		level_id = number
		view = "board"
		engine.state.view = view
		_build_board()
		_refresh()
		_save("继续探险")
		return
	if str(engine.state.get("phase", "")) == "playing":
		guard_level_switch(number, func(): _start_level(number, true))
		return
	_start_level(number, true)


func _start_level(number: int, announce: bool = true) -> bool:
	if players.is_empty():
		show_toast("先选择小朋友，再来探险。")
		return false
	var entry := _find_level(number)
	if entry.is_empty():
		show_toast("第 %s 张藏宝图还没有准备好，编号不会被替换。" % number, 2.8)
		return false
	level_id = number
	_result_visible = false
	_save_clock = 0.0
	engine.create_session({
		"gameId": game_id,
		"modeId": mode_id,
		"players": players.duplicate(true),
		"levelId": number,
		"level": entry,
		"difficulty": difficulty,
		"seed": Time.get_ticks_usec(),
	})
	if str(engine.state.get("phase", "")) != "playing":
		var message := str(engine.state.get("loadError", "这一张迷宫的内容不完整。"))
		engine.state = {}
		show_toast(message + " 请回地图选另一关。", 3.0)
		_show_map()
		return false
	session_id = str(engine.state.get("sessionId", ""))
	_last_patrol_resets = int(engine.state.get("patrolResets", 0))
	view = "board"
	_build_board()
	_refresh()
	_save("开始探险")
	if announce:
		Speech.stop_owner("maze-result")
		Speech.stop_owner("maze-feedback")
		Speech.speak(str(entry.get("narration", "看清钥匙、门和星徽，再一步一步探路。")), "maze-narration")
	return true


func _build_board() -> void:
	view = "board"
	PlaygroundUI.clear(content_root)
	game_header = HBoxContainer.new()
	game_header.add_theme_constant_override("separation", 10)
	var title_box: VBoxContainer
	if mode_id == "classic" and players.size() >= 2:
		game_header.add_child(_player_badge(0))
		var middle := CenterContainer.new()
		middle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title_box = VBoxContainer.new()
		title_box.add_theme_constant_override("separation", 1)
		title_box.add_child(PlaygroundUI.label("第 %s 张 · %s" % [level_id, engine.state.get("levelTitle", "迷宫")], 20, accent, 700, true))
		title_box.add_child(PlaygroundUI.label("轮流走一格，共用藏宝进度，不比较输赢", 13, PlaygroundUI.INK_SOFT, 500, true))
		middle.add_child(title_box)
		game_header.add_child(middle)
		game_header.add_child(_player_badge(1))
	else:
		title_box = VBoxContainer.new()
		title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title_box.add_theme_constant_override("separation", 1)
		title_box.add_child(PlaygroundUI.label("第 %s 张 · %s" % [level_id, engine.state.get("levelTitle", "迷宫")], 25, accent, 700, true))
		title_box.add_child(PlaygroundUI.label("点方向键、点相邻格或滑动，小探险家走一格。", 16, PlaygroundUI.INK_SOFT, 500, true))
		game_header.add_child(title_box)
		game_header.add_child(PlaygroundUI.chip(str(BAND_LABELS.get(engine.state.get("levelBand", "easy"), "探险")), accent))
	game_header.add_child(PlaygroundUI.semantic_icon_button("rules", "怎么玩", accent, show_help, "soft", 17))
	content_root.add_child(game_header)

	field = FIELD.new()
	field.configure(engine.level_definition, accent, soft_accent)
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	field.size_flags_vertical = Control.SIZE_EXPAND_FILL
	field.direction_selected.connect(_move)
	content_root.add_child(field)

	status = PlaygroundUI.label("", 18, accent, 600, true)
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.custom_minimum_size = Vector2(0, 38)
	content_root.add_child(status)

	game_tools = HFlowContainer.new()
	game_tools.alignment = FlowContainer.ALIGNMENT_CENTER
	game_tools.add_theme_constant_override("h_separation", 10)
	game_tools.add_theme_constant_override("v_separation", 6)
	var hint_button := PlaygroundUI.semantic_icon_button("hint", "路牌提示", accent, _hint, "soft", 18)
	hint_button.custom_minimum_size = Vector2(154, 48)
	game_tools.add_child(hint_button)
	var restart_button := PlaygroundUI.semantic_icon_button("restart", "重走这关", accent, _confirm_restart, "ghost", 18)
	restart_button.custom_minimum_size = Vector2(150, 48)
	game_tools.add_child(restart_button)
	var map_button := PlaygroundUI.semantic_icon_button("game", "探险地图", accent, _show_map, "ghost", 18)
	map_button.custom_minimum_size = Vector2(150, 48)
	game_tools.add_child(map_button)
	content_root.add_child(game_tools)
	field.set_state(engine.state)
	field.set_interaction_enabled(str(engine.state.get("phase", "")) == "playing")
	_on_immersive_changed(immersive)


func _player_badge(index: int) -> Control:
	var player: Dictionary = players[index] if index < players.size() else {}
	var tint := PlaygroundUI.color(str(player.get("color", accent.to_html(false))))
	var panel := PlaygroundUI.panel(PlaygroundUI.mix(tint, Color.WHITE, 0.88), 16, PlaygroundUI.mix(tint, Color.WHITE, 0.44), 1)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 7)
	row.add_child(ArtLibrary.profile_picture(player, Vector2(32, 34)))
	var copy := VBoxContainer.new()
	copy.add_theme_constant_override("separation", 0)
	copy.add_child(PlaygroundUI.label(str(player.get("name", "小朋友")), 15, PlaygroundUI.INK, 700, true))
	var current := engine.current_player_index() == index if engine.is_cooperative() else false
	copy.add_child(PlaygroundUI.label("轮到这一位" if current else "一起探路", 11, PlaygroundUI.INK_SOFT, 500))
	row.add_child(copy)
	panel.add_child(row)
	return panel


func _on_immersive_changed(value: bool) -> void:
	if game_header != null and is_instance_valid(game_header):
		game_header.visible = not value
	if status != null and is_instance_valid(status):
		status.show()
	if game_tools != null and is_instance_valid(game_tools):
		game_tools.show()


func _on_pause_changed(paused_value: bool) -> void:
	if paused_value and field != null and is_instance_valid(field):
		field.cancel_gesture()


func _status_text() -> String:
	if engine.state.is_empty():
		return "先选一张藏宝图。"
	if str(engine.state.get("phase", "")) == "finished":
		return "收齐星徽，已经走到终点啦。"
	var prefix := ""
	if engine.is_cooperative():
		var index := engine.current_player_index()
		var name := str(players[index].get("name", "小朋友")) if index < players.size() else "小朋友"
		prefix = "轮到 %s · " % name
	var text := "%s钥匙 %s / %s · 星徽 %s / %s · 步数 %s · 检查点 %s" % [
		prefix,
		engine.state.get("keysCollected", []).size(),
		engine.key_total(),
		engine.state.get("starsCollected", []).size(),
		engine.star_total(),
		int(engine.state.get("moves", 0)),
		1 if not str(engine.state.get("checkpointId", "")).is_empty() else 0,
	]
	if int(engine.state.get("patrolResets", 0)) > 0:
		text += " · 被巡逻发现 %s 次" % int(engine.state.get("patrolResets", 0))
	return text


func _refresh() -> void:
	if field == null or not is_instance_valid(field) or engine.state.is_empty():
		return
	engine.state._goalReady = engine.goal_ready()
	field.set_state(engine.state)
	field.set_interaction_enabled(str(engine.state.get("phase", "")) == "playing")
	if status != null and is_instance_valid(status):
		status.text = _status_text()
		status.add_theme_color_override("font_color", Color("#b65a43") if int(engine.state.get("patrolResets", 0)) > _last_patrol_resets else accent)
	if str(engine.state.get("phase", "")) == "finished" and not _result_visible:
		call_deferred("_show_result")


func _move(direction: String) -> void:
	if is_input_blocked() or _result_visible or engine.state.is_empty():
		return
	var result: Dictionary = engine.handle_input({"type": "move", "direction": direction})
	if not bool(result.get("ok", false)):
		SfxMap.play(&"error")
		FeedbackKit.haptic(7)
		show_toast(str(result.get("message", "这个方向走不过去")))
		return
	var event := str(result.get("event", "move"))
	if event == "finished":
		SfxMap.play(&"success")
		FeedbackKit.haptic(14)
		_save("收齐星徽，走出迷宫", false)
	elif event == "goal_locked":
		SfxMap.play(&"error")
		FeedbackKit.haptic(7)
		var message := str(result.get("message", "终点还差几件宝物。"))
		show_toast(message, 3.0)
		Speech.speak(message, "maze-feedback")
		_save("到达终点，还差宝物")
	elif event == "patrol":
		SfxMap.play(&"error")
		FeedbackKit.haptic(9)
		var message := str(engine.state.get("reason", "巡逻小灯发现了你，回到最近的检查点。"))
		show_toast(message, 2.8)
		Speech.speak(message, "maze-feedback")
		_save("被巡逻送回检查点")
	elif event == "checkpoint":
		SfxMap.play(&"save")
		FeedbackKit.haptic(8)
		Speech.speak("检查点记住了，下次从这里继续。", "maze-feedback")
		_save("经过检查点")
	elif event == "door":
		SfxMap.play(&"unlock")
		FeedbackKit.haptic(6)
		_save("用小钥匙打开小门")
	elif event == "key":
		SfxMap.play(&"success")
		FeedbackKit.haptic(5)
		_save("找到一把小钥匙")
	elif event == "star":
		SfxMap.play(&"star")
		FeedbackKit.haptic(5)
		_save("收集一颗星徽")
	else:
		SfxMap.play(&"move")
		FeedbackKit.haptic(3)
		_save("探险家向前走一格")
	_last_patrol_resets = int(engine.state.get("patrolResets", 0))
	_refresh()
	if not event in ["finished", "patrol", "goal_locked"] and immersive and engine.is_cooperative() and players.size() >= 2:
		var next_index := engine.current_player_index()
		var next_name := str(players[next_index].get("name", "小朋友"))
		show_toast("轮到 %s 探路。" % next_name, 1.1)
	if event == "finished":
		_show_result()


func _hint() -> void:
	if is_input_blocked() or _result_visible or engine.state.is_empty():
		return
	var result: Dictionary = engine.handle_input({"type": "hint"})
	if not bool(result.get("ok", false)):
		SfxMap.play(&"error")
		show_toast(str(result.get("message", "现在没有提示")))
		return
	AudioFX.play("whoosh")
	_save("查看路牌提示")
	_refresh()
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	var icon := ArtLibrary.semantic_picture("hint", "ui", Vector2(58, 58))
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	body.add_child(icon)
	var message := str(result.get("message", "先看看钥匙和门的颜色。"))
	var message_label := PlaygroundUI.label(message, 21, PlaygroundUI.INK, 600, true)
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(message_label)
	body.add_child(PlaygroundUI.label("路牌会指出作者路线；多看一眼不扣完成，但会少一颗星。", 15, PlaygroundUI.INK_SOFT, 500, true))
	Speech.speak(message, "maze-hint")
	open_modal("路牌提示", body, [
		{"text": "再读一遍", "icon": "repeat", "kind": "soft", "callback": func(): Speech.speak(message, "maze-hint")},
		{"text": "继续探险", "icon": "check", "kind": "primary", "callback": func(): Speech.stop_owner("maze-hint"); _close_top_modal()},
	], "第 %s 次看路牌" % int(result.get("hints", 0)))


func _confirm_restart() -> void:
	if view != "board" or engine.state.is_empty():
		_close_pause_tools()
		show_toast("先选一张藏宝图，再重新开始。")
		return
	var copy := PlaygroundUI.label(
		"这张藏宝图会回到起点，钥匙、星徽、检查点和步数都会重新摆放。其他关卡和其他进度会保留。",
		19,
		PlaygroundUI.INK_SOFT,
		500,
		true
	)
	open_modal("重走这一关？", copy, [
		{"text": "继续探险", "icon": "back", "kind": "soft", "callback": func(): _close_top_modal()},
		{"text": "重新出发", "icon": "restart", "kind": "primary", "callback": _restart_level},
	], "迷宫小探险")


func _restart_level() -> void:
	var was_paused := paused
	_suppress_resume_on_close = was_paused
	_close_all_game_dialogs()
	if was_paused:
		paused = false
		_pause_root_layer = null
		MotionKit.set_paused_tree(self, false)
		pause_changed.emit(false)
	_suppress_resume_on_close = false
	var result: Dictionary = engine.handle_input({"type": "restart"})
	if not bool(result.get("ok", false)):
		show_toast(str(result.get("message", "这一关暂时不能重新开始")))
		return
	_result_visible = false
	view = "board"
	_last_patrol_resets = 0
	SfxMap.play(&"drop")
	FeedbackKit.haptic(8)
	_refresh()
	_save("重新开始这一关")
	Speech.speak("藏宝图回到起点，再慢慢找钥匙和星徽。", "maze-feedback")


func _extra_pause_actions() -> Array:
	if view != "board":
		return []
	return [{
		"text": "探险地图",
		"icon": "game",
		"kind": "soft",
		"callback": func(): _close_pause_tools(); _show_map(),
	}]


func show_help() -> void:
	if not paused:
		_open_pause_tools()
	Speech.stop()
	var lines := [
		"点右侧方向键、点小探险家旁边的格子，或在地图上滑动，每次走一格。",
		"先找小钥匙，再走到同色小门；门打开后会一直保持打开。",
		"经过小旗会记住检查点。巡逻小灯按固定路线走，被它碰到就回到检查点，钥匙和星徽不会丢。",
		"收齐钥匙和要求的星徽，再走到终点。自动保存会留住当前位置和巡逻位置。",
	]
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	for index in lines.size():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		row.add_child(ArtLibrary.semantic_picture(["next", "lock", "save", "star"][index], "ui", Vector2(42, 42)))
		var copy_label := PlaygroundUI.label(str(lines[index]), 19, PlaygroundUI.INK, 600, true)
		copy_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(copy_label)
		body.add_child(row)
	var spoken := "迷宫小探险玩法。" + " ".join(PackedStringArray(lines))
	Speech.speak(spoken, "game-help")
	open_modal("怎么玩", body, [
		{"text": "三步小课堂", "icon": "play", "kind": "soft", "callback": func(): _close_top_modal(); call_deferred("begin_lesson", true)},
		{"text": "再读一遍", "icon": "repeat", "kind": "soft", "callback": func(): Speech.speak(spoken, "game-help")},
		{"text": "知道了", "icon": "check", "kind": "primary", "callback": func(): Speech.stop_owner("game-help"); _close_top_modal()},
	], "先看钥匙，再找门")


func begin_lesson(force: bool = false) -> void:
	if not force:
		return
	if not paused:
		_open_pause_tools()
	lesson_texts = [
		"先看整张迷宫，找到小钥匙、对应的小门和沿路星徽。",
		"每次走一格；经过小旗会记住检查点，巡逻小灯只按固定路线来回走。",
		"收齐钥匙和星徽再到终点；每一步、每次巡逻和检查点都会自动保存。",
	]
	_lesson_icons = ["game", "save", "star"]
	_show_lesson_page(0)


func _show_rules() -> void:
	var lines := [
		"迷宫是固定网格，没有倒计时，也没有会自己找路的角色。",
		"小钥匙按 keyId 打开对应小门；门开后保持打开，钥匙也留在背包。",
		"巡逻小灯只沿作者写好的路线按周期移动，不追逐、不寻路。被碰到会回到最近检查点，不会丢钥匙或星徽。",
		"单人过关至少一星记赢；双人轮流走一格，只记一起玩过，不比较输赢。",
		"三星：不看提示、没被巡逻送回，并在标准步数内完成。",
	]
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	for index in lines.size():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		row.add_child(PlaygroundUI.chip(str(index + 1), accent))
		var copy_label := PlaygroundUI.label(str(lines[index]), 18, PlaygroundUI.INK_SOFT, 500, true)
		copy_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(copy_label)
		body.add_child(row)
	var spoken := "迷宫小探险规则。" + " ".join(PackedStringArray(lines))
	Speech.speak(spoken, "maze-rules")
	open_modal("迷宫小探险规则", body, [
		{"text": "读给我听", "icon": "speech", "kind": "soft", "callback": func(): Speech.speak(spoken, "maze-rules")},
		{"text": "知道了", "icon": "check", "kind": "primary", "callback": func(): _close_top_modal()},
	], "固定巡逻，不追人")


func show_game_rules() -> void:
	_show_rules()


func _record_completion_if_needed() -> bool:
	if engine.state.is_empty() or str(engine.state.get("phase", "")) != "finished":
		return false
	if bool(engine.state.get("reported", false)):
		return false
	var summary: Dictionary = engine.result()
	var stars := int(summary.get("stars", engine.stars()))
	var total := engine.star_total()
	var session_key := str(engine.state.get("sessionId", "maze"))
	var all_recorded := true
	if mode_id == "adventure":
		if players.is_empty():
			return false
		var player_id := str(players[0].id)
		SaveStore.complete_level(player_id, game_id, level_id, stars, mode_id)
		if not SaveStore.record_outcome(
			player_id,
			game_id,
			"win",
			stars,
			total,
			total,
			{"logic": {"correct": total, "answered": total}},
			session_key
		):
			all_recorded = false
	else:
		for player in players:
			var player_id := str(player.id)
			SaveStore.complete_level(player_id, game_id, level_id, stars, mode_id)
			if not SaveStore.record_outcome(
				player_id,
				game_id,
				"played",
				stars,
				total,
				total,
				{"logic": {"correct": total, "answered": total}},
				session_key
			):
				all_recorded = false
	if all_recorded:
		engine.state.reported = true
	return all_recorded


func _show_result() -> void:
	if engine.state.is_empty() or str(engine.state.get("phase", "")) != "finished":
		return
	var summary: Dictionary = engine.result()
	if summary.is_empty():
		return
	if _record_completion_if_needed():
		_save("收齐星徽，走出迷宫", false)
	if _result_visible:
		return
	_result_visible = true
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 9)
	var trophy := ArtLibrary.semantic_picture("trophy", "ui", Vector2(84, 84))
	trophy.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	body.add_child(trophy)
	var title_text := "一起走出迷宫啦！" if mode_id == "classic" else "藏宝图探完啦！"
	var title := PlaygroundUI.label(title_text, 26, accent, 700, true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(title)
	var stats := "步数 %s · 标准 %s · 星徽 %s / %s · 路牌提示 %s · 巡逻送回 %s" % [
		int(summary.get("moves", 0)),
		int(summary.get("parMoves", 0)),
		int(summary.get("starsCollected", 0)),
		engine.star_total(),
		int(summary.get("hints", 0)),
		int(summary.get("patrolResets", 0)),
	]
	var stats_label := PlaygroundUI.label(stats, 17, PlaygroundUI.INK_SOFT, 500, true)
	stats_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(stats_label)
	var stars_row := HBoxContainer.new()
	stars_row.alignment = BoxContainer.ALIGNMENT_CENTER
	stars_row.add_theme_constant_override("separation", 8)
	var stars := int(summary.get("stars", 0))
	for index in 3:
		var star := ArtLibrary.semantic_picture("star", "ui", Vector2(38, 38))
		star.modulate = Color.WHITE if index < stars else Color(1, 1, 1, 0.24)
		stars_row.add_child(star)
	body.add_child(stars_row)
	var rating := "路线又稳又准，钥匙和星徽一颗都没漏！" if stars == 3 else "已经走到终点啦，下次可以少看一次路牌。" if stars == 2 else "收齐宝物真不容易，回头再试会更熟悉路线。"
	var rating_label := PlaygroundUI.label(rating, 18, PlaygroundUI.INK, 600, true)
	rating_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(rating_label)
	var explanation := PlaygroundUI.label(str(engine.level_definition.get("explanation", "先找钥匙，再用星徽照亮终点。")), 16, PlaygroundUI.INK_SOFT, 500, true)
	explanation.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(explanation)
	var actions := [
		{"text": "探险地图", "icon": "game", "kind": "soft", "callback": func(): Speech.stop_owner("maze-result"); _close_top_modal(); _show_map()},
		{"text": "再探一次", "icon": "restart", "kind": "soft", "callback": func(): Speech.stop_owner("maze-result"); _close_top_modal(); _start_level(level_id, false)},
	]
	var next_number := level_id + 1
	if not _find_level(next_number).is_empty() and (mode_id == "classic" or _unlocked(next_number)):
		actions.append({"text": "下一张", "icon": "next", "kind": "primary", "callback": _go_next_level})
	else:
		actions.append({
			"text": "回游戏大厅",
			"icon": "home",
			"kind": "primary",
			"callback": func():
				Speech.stop_owner("maze-result")
				_close_all_game_dialogs()
				SaveStore.flush()
				back_requested.emit(),
		})
	open_modal("走出迷宫", body, actions, SaveStore.save_status_text(), false)
	SfxMap.play(&"win")
	FeedbackKit.haptic(14)
	var spoken := str(engine.level_definition.get("explanation", "收齐星徽，走到终点，迷宫就探完啦。"))
	if mode_id == "classic" and players.size() >= 2:
		spoken = "%s和%s轮流探路，一起收齐了星徽，走出了迷宫。" % [
			str(players[0].get("name", "小朋友")),
			str(players[1].get("name", "小伙伴")),
		]
	Speech.speak(spoken, "maze-result")


func _go_next_level() -> void:
	Speech.stop_owner("maze-result")
	_close_top_modal()
	var next_number := level_id + 1
	if _find_level(next_number).is_empty():
		_show_map()
		return
	if mode_id == "adventure" and not _unlocked(next_number):
		_show_map()
		return
	_start_level(next_number, true)


func _save(note: String = "实时自动保存迷宫进度", resume: bool = true) -> void:
	if engine.state.is_empty() or players.is_empty():
		return
	_record_completion_if_needed()
	engine.state.view = view
	engine.state._goalReady = engine.goal_ready()
	var phase := str(engine.state.get("phase", ""))
	SaveStore.save_state(
		game_id,
		str(players[0].id),
		engine.snapshot(),
		note,
		resume and phase == "playing" and view in ["board", "map"]
	)
