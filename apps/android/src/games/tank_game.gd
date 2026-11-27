class_name NativeTankGame
extends NativeGameScreen

const CONTENT_PATH := "res://content/tank.json"
const FALLBACK_TITLE := "坦克小卫士"
const FALLBACK_ACCENT := "#34465a"
const FALLBACK_SOFT := "#e3e8ef"
const BAND_LABELS := {"easy": "轻松", "normal": "标准", "challenge": "挑战"}
const BAND_AGES := {"easy": "推荐 4–6 岁", "normal": "推荐 7–9 岁", "challenge": "推荐 10–12 岁"}
const TANK_RULES_SCRIPT := preload("res://src/games/tank_rules.gd")
const TANK_VERSION := 1

var engine = TANK_RULES_SCRIPT.new()
var field
var soft_accent := Color(FALLBACK_SOFT)
var view := "map"
var _levels_cache: Array = []
var _catalog_issues: Array[String] = []
var _result_visible := false
var _save_clock := 0.0


func _ready() -> void:
	if game_id.is_empty():
		game_id = "tank"
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
	elif mode_id == "adventure" and players.size() != 1:
		mode_id = "classic"
	elif mode_id == "classic" and players.size() != 2:
		mode_id = "adventure"
	_load_levels()
	SaveStore.set_context(game_id, mode_id, players.map(func(player): return str(player.id)))
	build_shell()
	pause_changed.connect(_on_pause_changed)
	var stored := SaveStore.load_state(game_id, players.map(func(player): return str(player.id)))
	var had_stored := not stored.is_empty()
	stored.modeId = mode_id
	if had_stored and engine.restore(stored):
		players = engine.state.players.duplicate(true)
		level_id = int(engine.state.get("levelId", 1))
		view = str(engine.state.get("view", "board"))
		if str(engine.state.get("phase", "")) == "finished" and not bool(stored.get("resume", true)):
			_show_map()
			return
		if view == "map":
			_show_map()
			return
		_build_board()
		_refresh()
		if str(engine.state.get("phase", "")) == "finished":
			call_deferred("_show_result")
		return
	engine.state = {}
	var recovery_level := int(stored.get("levelId", 0)) if had_stored else 0
	if recovery_level >= 1 and recovery_level <= _mode_levels().size():
		if _start_level(recovery_level, false):
			show_toast("上次的坦克存档不完整，已从第 %s 关开头重新准备。" % recovery_level, 3.0)
			return
	_show_map()


func preview_ready() -> void:
	if field != null and is_instance_valid(field):
		field.queue_redraw()


func _load_levels() -> void:
	_levels_cache.clear()
	_catalog_issues.clear()
	if not FileAccess.file_exists(CONTENT_PATH):
		_catalog_issues.append("找不到 tank.json")
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONTENT_PATH))
	if not parsed is Dictionary:
		_catalog_issues.append("tank.json 格式不正确")
		return
	var validation: Dictionary = TANK_RULES_SCRIPT.validate_catalog(parsed)
	for issue in validation.get("issues", []):
		_catalog_issues.append(str(issue))
	if not bool(validation.get("ok", false)):
		for issue in _catalog_issues:
			push_warning("坦克小卫士内容：" + issue)
		return
	var levels_value: Variant = parsed.get("levels", [])
	if not levels_value is Array:
		return
	for raw in levels_value:
		if not raw is Dictionary:
			continue
		_levels_cache.append(raw.duplicate(true))


func _mode_levels() -> Array:
	return _levels_cache.filter(func(entry): return entry is Dictionary and str(entry.get("mode", "")) == mode_id)


func _level_for(number: int) -> Dictionary:
	var levels := _mode_levels()
	if number < 1 or number > levels.size():
		return {}
	var value: Variant = levels[number - 1]
	return value.duplicate(true) if value is Dictionary else {}


func _star_count(number: int) -> int:
	var stars := 0
	for player in players:
		var progress := SaveStore.learning(str(player.id), game_id, mode_id)
		stars = maxi(stars, int(progress.get("stars", {}).get(str(number), 0)))
	return clampi(stars, 0, 3)


func _level_unlocked(number: int) -> bool:
	if mode_id == "classic":
		return true
	if players.is_empty():
		return false
	return SaveStore.level_unlocked(str(players[0].id), game_id, number, mode_id)


func _can_resume_level(number: int) -> bool:
	return (
		not engine.state.is_empty()
		and int(engine.state.get("levelId", -1)) == number
		and str(engine.state.get("phase", "")) == "playing"
		and int(engine.state.get("tankVersion", 0)) == TANK_VERSION
	)


func _show_map() -> void:
	Speech.stop()
	view = "map"
	_result_visible = false
	PlaygroundUI.clear(content_root)
	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation", 12)
	var copy := VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.add_theme_constant_override("separation", 2)
	copy.add_child(PlaygroundUI.label("坦克小卫士训练场", 30, accent, 700, true))
	var subtitle := "一个人开着泡泡坦克，穿过固定迷宫，点亮全部终点。"
	if mode_id == "classic":
		subtitle = "两位小朋友各守一座操作坞，一起打开信号门、收集星徽，不分输赢。"
		copy.add_child(PlaygroundUI.label(subtitle, 18, PlaygroundUI.INK_SOFT, 500, true))
	heading.add_child(copy)
	heading.add_child(PlaygroundUI.chip("24 个迷宫" if mode_id == "adventure" else "6 张合作图", accent))
	heading.add_child(PlaygroundUI.semantic_icon_button("rules", "怎么玩", accent, show_help, "soft"))
	content_root.add_child(heading)
	if not _catalog_issues.is_empty():
		var warning := PlaygroundUI.panel(PlaygroundUI.mix(soft_accent, Color.WHITE, 0.28), 16, PlaygroundUI.mix(accent, Color.WHITE, 0.45), 1)
		warning.add_child(PlaygroundUI.label("坦克地图有 %s 处需要检查，暂时只显示可玩的关卡。" % _catalog_issues.size(), 16, PlaygroundUI.INK_SOFT, 600, true))
		content_root.add_child(warning)
	var levels := _mode_levels()
	if levels.is_empty():
		var empty := PlaygroundUI.panel(PlaygroundUI.mix(soft_accent, Color.WHITE, 0.28), 22, PlaygroundUI.TOOL_LINE, 2)
		empty.add_child(PlaygroundUI.label("坦克迷宫还没有准备好，请稍后再来看看。", 20, PlaygroundUI.INK_SOFT, 600, true))
		content_root.add_child(empty)
		if not engine.state.is_empty():
			engine.state.view = view
			_save("正在选择坦克地图")
		return
	var entries: Array = []
	for index in levels.size():
		var entry: Dictionary = levels[index]
		var number := index + 1
		entries.append({
			"id": number,
			"title": str(entry.get("title", "坦克迷宫")),
			"subtitle": "%s · %s" % [str(BAND_LABELS.get(str(entry.get("band", "")), "轻松")), str(BAND_AGES.get(str(entry.get("band", "")), ""))],
			"locked": not _level_unlocked(number),
			"stars": _star_count(number),
			"in_progress": _can_resume_level(number),
		})
	var browser := GameBrowser.new()
	browser.configure(entries, {
		"accent": accent,
		"title": "选择一张坦克地图",
		"subtitle": "每张地图都有固定解法，信号靶和星徽会保留到本局结束。",
	})
	browser.entry_selected.connect(func(number: Variant): _choose_level(int(number)))
	content_root.add_child(browser)
	if not engine.state.is_empty():
		engine.state.view = view
		_save("正在选择坦克地图")


func _choose_level(number: int) -> void:
	if not _level_unlocked(number):
		SfxMap.play(&"error")
		show_toast("先完成前一关，再来挑战这张迷宫。")
		return
	SfxMap.play(&"tap")
	if _can_resume_level(number):
		level_id = number
		view = "board"
		_build_board()
		_refresh()
		_save("继续上一张坦克地图")
		return
	if str(engine.state.get("phase", "")) == "playing":
		guard_level_switch(number, func(): _start_level(number, true), func(): _resume_level(number))
		return
	_start_level(number, true)


func _resume_level(number: int) -> void:
	if not _can_resume_level(number):
		return
	level_id = number
	view = "board"
	_build_board()
	_refresh()
	_save("继续上一张坦克地图")


func _start_level(number: int, announce: bool = true) -> bool:
	if players.is_empty():
		show_toast("先选择小朋友，再来开坦克。")
		return false
	var entry := _level_for(number)
	if entry.is_empty():
		show_toast("这张坦克地图还没有准备好。")
		return false
	level_id = number
	_result_visible = false
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
		var reason := str(engine.state.get("reason", "这张坦克地图不完整。"))
		engine.state = {}
		show_toast(reason)
		_show_map()
		return false
	session_id = str(engine.state.get("sessionId", ""))
	view = "board"
	_build_board()
	_refresh()
	_save("开始坦克地图")
	if announce:
		Speech.stop()
		Speech.speak("第 %s 关，%s。用方向键移动坦克，开火键打出泡泡弹。" % [number, str(entry.get("title", "坦克迷宫"))], "tank-start")
	return true


func _build_board() -> void:
	view = "board"
	PlaygroundUI.clear(content_root)
	var field_script: GDScript = load("res://src/ui/tank_field.gd")
	field = field_script.new()
	field.accent = accent
	field.soft = soft_accent
	field.bind(engine, self, players)
	field.action_requested.connect(_on_field_action)
	content_root.add_child(field)


func _refresh() -> void:
	if field != null and is_instance_valid(field):
		field.queue_redraw()


func _blocked() -> bool:
	return is_input_blocked()


func _on_pause_changed(paused_value: bool) -> void:
	if not is_instance_valid(field):
		return
	if paused_value:
		field.suspend_effects()
		_save_clock = 0.0
	else:
		field.queue_redraw()


func _process(delta: float) -> void:
	super._process(delta)
	if paused or view != "board" or not is_instance_valid(field) or _blocked():
		return
	var phase := str(engine.state.get("phase", ""))
	if phase == "playing":
		var changed := engine.tick(delta)
		var events := engine.drain_events()
		if not events.is_empty():
			field.consume_events(events)
		if changed:
			_save_clock += delta
			if _save_clock >= 2.0:
				_save_clock = 0.0
				_save("坦克小卫士自动保存")
		if str(engine.state.get("phase", "")) == "finished":
			_save("坦克任务完成", false)
			_show_result()
	else:
		_save_clock = 0.0


func _on_field_action(action: Dictionary) -> void:
	if _blocked() or _result_visible or view != "board":
		return
	Speech.stop_owner("tank-feedback")
	var result := engine.handle_input(action)
	if not bool(result.get("ok", false)):
		field.flash_notice(str(result.get("message", "这个操作现在不能用")))
		SfxMap.play(&"error")
		return
	if str(action.get("type", "")) == "move" and not bool(result.get("moved", true)):
		field.flash_notice(str(result.get("message", "前面过不去")))
		SfxMap.play(&"error")
		field.consume_events(engine.drain_events())
		_save("坦克改变朝向")
		_refresh()
		return
	if str(action.get("type", "")) == "fire":
		SfxMap.play(&"tap")
	else:
		SfxMap.play(&"move")
	field.consume_events(engine.drain_events())
	_save("坦克小卫士操作保存")
	_refresh()
	if str(engine.state.get("phase", "")) == "finished":
		_save("坦克任务完成", false)
		_show_result()


func _save(note: String = "实时自动保存坦克进度", resume: bool = true) -> void:
	if engine.state.is_empty() or players.is_empty():
		return
	_record_completion_if_needed()
	engine.state.view = view
	var primary_id := str(players[0].id)
	SaveStore.save_state(
		game_id,
		primary_id,
		engine.snapshot(),
		note,
		resume and str(engine.state.get("phase", "")) == "playing"
	)


func _record_completion_if_needed() -> bool:
	if engine.state.is_empty() or str(engine.state.get("phase", "")) != "finished":
		return false
	if bool(engine.state.get("reported", false)):
		return false
	var summary: Dictionary = engine.result()
	var stars := int(summary.get("stars", engine.stars()))
	var outcome := "win" if mode_id == "adventure" else "played"
	var all_recorded := true
	for player in players:
		var player_id := str(player.get("id", ""))
		if player_id.is_empty():
			continue
		SaveStore.complete_level(player_id, game_id, level_id, stars, mode_id)
		var recorded := SaveStore.record_outcome(
			player_id,
			game_id,
			outcome,
			stars,
			stars,
			3,
			{"strategy": {"correct": stars, "answered": 3}},
			str(engine.state.get("sessionId", "tank"))
		)
		if not recorded:
			all_recorded = false
	if all_recorded:
		engine.state.reported = true
	return all_recorded


func _show_result() -> void:
	if engine.state.is_empty() or str(engine.state.get("phase", "")) != "finished":
		return
	var summary := engine.result()
	if summary.is_empty():
		return
	if _record_completion_if_needed():
		_save("坦克任务完成", false)
	if _result_visible:
		return
	_result_visible = true
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	var trophy := ArtLibrary.semantic_picture("trophy", "ui", Vector2(84, 84))
	trophy.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	body.add_child(trophy)
	var title_text := "两位小卫士一起完成任务！" if mode_id == "classic" else "坦克任务完成！"
	var title := PlaygroundUI.label(title_text, 26, accent, 700, true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(title)
	var stats := "泡泡弹 %s / %s · 星徽 %s / %s · 泡泡盾破 %s 次 · 用时 %s 秒" % [
		int(summary.get("shots", 0)),
		int(summary.get("parShots", 0)),
		int(summary.get("starsCollected", 0)),
		int(summary.get("starTotal", 0)),
		int(summary.get("shieldBreaks", 0)),
		int(round(float(summary.get("elapsed", 0.0)))),
	]
	var stats_label := PlaygroundUI.label(stats, 18, PlaygroundUI.INK_SOFT, 500, true)
	stats_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(stats_label)
	var stars_row := HBoxContainer.new()
	stars_row.alignment = BoxContainer.ALIGNMENT_CENTER
	stars_row.add_theme_constant_override("separation", 8)
	for index in 3:
		var star := ArtLibrary.semantic_picture("star", "ui", Vector2(38, 38))
		star.modulate = Color.WHITE if index < int(summary.get("stars", 0)) else Color(1, 1, 1, 0.24)
		stars_row.add_child(star)
	body.add_child(stars_row)
	var level_title := str(engine.state.get("levelTitle", "坦克迷宫"))
	var explanation := PlaygroundUI.label("%s\n%s" % [str(engine.state.get("level", {}).get("explanation", "")), level_title], 18, PlaygroundUI.INK, 500, true)
	explanation.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(explanation)
	var actions: Array = [
		{"text": "回看场地", "icon": "back", "kind": "soft", "callback": func(): _result_visible = false; Speech.stop_owner("tank-result"); _close_top_modal()},
		{"text": "关卡地图", "icon": "game", "kind": "soft", "callback": func(): Speech.stop_owner("tank-result"); _close_top_modal(); _show_map()},
	]
	var levels := _mode_levels()
	if level_id < levels.size() and _level_unlocked(level_id + 1):
		actions.append({"text": "下一关", "icon": "next", "kind": "primary", "callback": _go_next_level})
	else:
		actions.append({"text": "回游戏大厅", "icon": "home", "kind": "primary", "callback": func(): Speech.stop_owner("tank-result"); _close_all_game_dialogs(); back_requested.emit()})
	open_modal("坦克小卫士", body, actions, SaveStore.save_status_text(), false)
	SfxMap.play(&"win")
	FeedbackKit.haptic(14)
	var spoken := "坦克任务完成，获得 %s 颗评价星。" % int(summary.get("stars", 0))
	if mode_id == "classic" and players.size() >= 2:
		spoken = "%s和%s一起完成了坦克合作图。" % [
			str(players[0].get("name", "小朋友")),
			str(players[1].get("name", "小伙伴")),
		]
	Speech.speak(spoken, "tank-result")


func _go_next_level() -> void:
	Speech.stop_owner("tank-result")
	_close_top_modal()
	var next_number := level_id + 1
	if next_number > _mode_levels().size() or not _level_unlocked(next_number):
		_show_map()
		return
	_start_level(next_number, true)


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
	if view != "board" or engine.state.is_empty():
		_close_pause_tools()
		show_toast("先选一张坦克地图，再重新开始。")
		return
	var text := PlaygroundUI.label("本关会回到起点重新准备，泡泡盾恢复三格；其他关卡和儿童档案不会受影响。", 19, PlaygroundUI.INK_SOFT, 500, true)
	open_modal("重开这一关？", text, [
		{"text": "继续这局", "icon": "back", "kind": "soft", "callback": func(): _close_top_modal()},
		{"text": "重新开始", "icon": "restart", "kind": "primary", "callback": _restart_from_confirm},
	], "坦克小卫士")


func _restart_from_confirm() -> void:
	var was_paused := paused
	_suppress_resume_on_close = was_paused
	_close_all_game_dialogs()
	if was_paused:
		paused = false
		_pause_root_layer = null
		MotionKit.set_paused_tree(self, false)
		pause_changed.emit(false)
	_suppress_resume_on_close = false
	_start_level(level_id, false)


func show_help() -> void:
	if not paused and view == "board":
		_open_pause_tools()
	Speech.stop()
	var lines := [
		"点方向键，让坦克一格一格移动；长按可以连续前进。",
		"点开火键打出泡泡弹。泡泡弹会扫过整条通道，打亮信号靶就会打开信号门。",
		"移动纸门会沿固定轨道移动，泡泡发射器按固定节拍工作，它们都不会追着你跑。",
		"每辆坦克有三格泡泡盾。盾破后回到最近检查点，已经点亮的靶和星徽不会丢。",
	]
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	var icons := ["play", "next", "hint", "star"]
	for index in lines.size():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		row.add_child(ArtLibrary.semantic_picture(str(icons[index]), "ui", Vector2(42, 42)))
		var copy := PlaygroundUI.label(str(lines[index]), 19, PlaygroundUI.INK, 600, true)
		copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(copy)
		body.add_child(row)
	var spoken := "坦克小卫士玩法。" + " ".join(PackedStringArray(lines))
	Speech.speak(spoken, "game-help")
	open_modal("怎么玩", body, [
		{"text": "三步小课堂", "icon": "play", "kind": "soft", "callback": func(): _close_top_modal(); call_deferred("begin_lesson", true)},
		{"text": "再读一遍", "icon": "repeat", "kind": "soft", "callback": func(): Speech.speak(spoken, "game-help")},
		{"text": "知道了", "icon": "check", "kind": "primary", "callback": func(): _close_top_modal()},
	], "方向键移动，开火键打靶")


func _show_rules() -> void:
	var lines := [
		"坦克每次沿上下左右移动一格，不能穿过纸箱墙和关着的信号门。",
		"泡泡弹沿炮口方向飞行，打亮信号靶后，对应的信号门会永久打开。",
		"移动纸门只沿关卡里的固定轨道循环；泡泡发射器只按固定周期发射，不会瞄准谁。",
		"三格泡泡盾被泡泡弹打光后，坦克回到最近检查点，信号靶、星徽和终点进度都会保留。",
		"双人合作时，两位小朋友各用左右操作坞，可以同时移动和开火，共享同一份进度。",
	]
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	for index in lines.size():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		row.add_child(PlaygroundUI.chip(str(index + 1), accent))
		var copy := PlaygroundUI.label(str(lines[index]), 18, PlaygroundUI.INK_SOFT, 500, true)
		copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(copy)
		body.add_child(row)
	Speech.speak(" ".join(PackedStringArray(lines)), "tank-help")
	open_modal("坦克小卫士规则", body, [
		{"text": "读给我听", "icon": "speech", "kind": "soft", "callback": func(): Speech.repeat()},
		{"text": "知道了", "icon": "check", "kind": "primary", "callback": func(): _close_top_modal()},
	], "泡泡坦克的固定迷宫")


func begin_lesson(force: bool = false) -> void:
	if not force:
		return
	if not paused and view == "board":
		_open_pause_tools()
	lesson_texts = [
		"先用大方向键把坦克开到合适的位置，炮口会朝向最后按下的方向。",
		"按开火键打出一串泡泡弹。打亮信号靶，对应的信号门就会收起。",
		"留意移动纸门和固定节拍的泡泡发射器，泡泡盾破了会回到最近检查点。",
	]
	_lesson_icons = ["play", "next", "hint"]
	call("_show_lesson_page", 0)
