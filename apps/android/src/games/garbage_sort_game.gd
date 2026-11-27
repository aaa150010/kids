class_name NativeGarbageSortGame
extends NativeGameScreen

const RULES_SCRIPT := preload("res://src/games/garbage_sort_rules.gd")
const CONTENT_PATH := "res://content/garbage_sort.json"
const FALLBACK_TITLE := "垃圾分类站"
const FALLBACK_ACCENT := "#3e7d55"
const FALLBACK_SOFT := "#e4f1e6"
const BAND_LABELS := {"easy": "轻松", "normal": "标准", "challenge": "挑战"}
const BAND_AGES := {"easy": "推荐 4–6 岁", "normal": "推荐 7–9 岁", "challenge": "推荐 10–12 岁"}

var engine = RULES_SCRIPT.new()
var field: GarbageSortField
var feedback_panel: PanelContainer
var feedback_title: Label
var feedback_text: Label
var next_button: Button
var listen_button: Button
var sorting_actions: HBoxContainer
var hint_button: Button
var soft_accent := Color(FALLBACK_SOFT)
var view := "map"
var _levels_cache: Array = []
var _categories: Array = []
var _items_by_id: Dictionary = {}
var _catalog_issues: Array[String] = []
var _result_visible := false


func _ready() -> void:
	if game_id.is_empty():
		game_id = "garbage_sort"
	if str(game_meta.get("title", "")).strip_edges().is_empty():
		game_meta.title = FALLBACK_TITLE
	if str(game_meta.get("accent", "")).strip_edges().is_empty():
		game_meta.accent = FALLBACK_ACCENT
		accent = PlaygroundUI.color(FALLBACK_ACCENT)
	if str(game_meta.get("soft", "")).strip_edges().is_empty():
		game_meta.soft = FALLBACK_SOFT
	soft_accent = PlaygroundUI.color(str(game_meta.get("soft", FALLBACK_SOFT)))
	if players.size() > 2:
		players = players.slice(0, 2)
	mode_id = "adventure" if players.size() <= 1 else "classic"
	_load_data()
	SaveStore.set_context(game_id, mode_id, players.map(func(player): return str(player.id)))
	build_shell()
	pause_changed.connect(_on_pause_changed)
	var stored := SaveStore.load_state(game_id, players.map(func(player): return str(player.id)))
	var had_stored := not stored.is_empty()
	stored.modeId = mode_id
	if had_stored and engine.restore(stored):
		players = engine.state.players.duplicate(true)
		level_id = int(engine.state.get("levelNumber", engine.state.get("levelId", 1)))
		view = str(engine.state.get("view", "sort"))
		_result_visible = false
		if str(engine.state.get("phase", "")) == "finished" and not bool(stored.get("resume", true)):
			_show_map()
			return
		if view == "map":
			_show_map()
			return
		_build_game()
		_render(false)
		if str(engine.state.get("phase", "")) == "finished":
			call_deferred("_show_result")
		return
	engine.state = {}
	var recovery_level := int(stored.get("levelId", 0)) if had_stored else 0
	if recovery_level >= 1 and recovery_level <= _mode_levels().size():
		if _start_level(recovery_level, false):
			show_toast("上次的分类记录不完整，已从这一关开头重新准备。", 3.0)
			return
	_show_map()


func _load_data() -> void:
	_levels_cache.clear()
	_categories.clear()
	_items_by_id.clear()
	_catalog_issues.clear()
	if not FileAccess.file_exists(CONTENT_PATH):
		_catalog_issues.append("找不到 garbage_sort.json")
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONTENT_PATH))
	if not parsed is Dictionary:
		_catalog_issues.append("garbage_sort.json 格式不正确")
		return
	var validation: Dictionary = RULES_SCRIPT.validate_catalog(parsed)
	for issue in validation.get("issues", []):
		_catalog_issues.append(str(issue))
	var categories_value: Variant = parsed.get("categories", [])
	if categories_value is Array:
		for category in categories_value:
			if category is Dictionary:
				_categories.append(category.duplicate(true))
	var items_value: Variant = parsed.get("items", [])
	if items_value is Array:
		for item in items_value:
			if item is Dictionary and not str(item.get("id", "")).is_empty():
				_items_by_id[str(item.id)] = item.duplicate(true)
	var levels_value: Variant = parsed.get("levels", [])
	if levels_value is Array:
		for level in levels_value:
			if not level is Dictionary:
				continue
			var check := RULES_SCRIPT.validate_level(level, _categories, _items_by_id)
			if bool(check.get("ok", false)):
				_levels_cache.append(level.duplicate(true))
	for issue in _catalog_issues:
		push_warning("垃圾分类站内容：" + issue)


func _mode_levels() -> Array:
	return _levels_cache.filter(func(entry): return entry is Dictionary and str(entry.get("mode", "")) == mode_id)


func _level_for(number: int) -> Dictionary:
	var levels := _mode_levels()
	if number < 1 or number > levels.size():
		return {}
	var value: Variant = levels[number - 1]
	return value.duplicate(true) if value is Dictionary else {}


func _level_unlocked(number: int) -> bool:
	if mode_id == "classic":
		return true
	if players.is_empty():
		return false
	return SaveStore.level_unlocked(str(players[0].id), game_id, number, mode_id)


func _stars_for(number: int) -> int:
	var stars := 0
	for player in players:
		var lesson := SaveStore.learning(str(player.id), game_id, mode_id)
		stars = maxi(stars, int(lesson.get("stars", {}).get(str(number), 0)))
	return clampi(stars, 0, 3)


func _can_resume_level(number: int) -> bool:
	return (
		not engine.state.is_empty()
		and int(engine.state.get("levelNumber", -1)) == number
		and str(engine.state.get("modeId", "")) == mode_id
		and int(engine.state.get("garbageVersion", 0)) == RULES_SCRIPT.GARBAGE_VERSION
		and str(engine.state.get("phase", "")) in ["sorting", "feedback"]
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
	copy.add_child(PlaygroundUI.label("今天去哪一间分类站？", 30, accent, 700, true))
	var subtitle := "一个人把生活物品送回四个桶，每次都会告诉你为什么。"
	if mode_id == "classic":
		subtitle = "两位小朋友轮流分类，共用一条环保成绩；没有输赢。"
	copy.add_child(PlaygroundUI.label(subtitle, 18, PlaygroundUI.INK_SOFT, 500, true))
	heading.add_child(copy)
	heading.add_child(PlaygroundUI.chip("24 间分类站" if mode_id == "adventure" else "6 间合作站", accent))
	heading.add_child(PlaygroundUI.semantic_icon_button("rules", "怎么玩", accent, show_help, "soft"))
	content_root.add_child(heading)
	if not _catalog_issues.is_empty():
		var warning := PlaygroundUI.panel(PlaygroundUI.mix(soft_accent, Color.WHITE, 0.25), 16, PlaygroundUI.mix(accent, Color.WHITE, 0.45), 1)
		warning.add_child(PlaygroundUI.label("分类内容有 %s 处需要检查，暂时只显示可玩的关卡。" % _catalog_issues.size(), 16, PlaygroundUI.INK_SOFT, 600, true))
		content_root.add_child(warning)
	var levels := _mode_levels()
	if levels.is_empty():
		var empty := PlaygroundUI.panel(PlaygroundUI.mix(soft_accent, Color.WHITE, 0.25), 22, PlaygroundUI.TOOL_LINE, 2)
		empty.add_child(PlaygroundUI.label("分类站还没有准备好，请稍后再来看看。", 20, PlaygroundUI.INK_SOFT, 600, true))
		content_root.add_child(empty)
	else:
		var entries: Array = []
		for index in levels.size():
			var level: Dictionary = levels[index]
			var number := index + 1
			entries.append({
				"id": number,
				"title": str(level.get("title", "垃圾分类站")),
				"subtitle": "%s · %s · %s 件物品" % [str(BAND_LABELS.get(str(level.get("band", "")), "练习")), str(BAND_AGES.get(str(level.get("band", "")), "")), level.get("items", []).size()],
				"locked": not _level_unlocked(number),
				"stars": _stars_for(number),
				"in_progress": _can_resume_level(number),
			})
		var browser := GameBrowser.new()
		browser.configure(entries, {
			"accent": accent,
			"title": "选择一间分类站",
			"subtitle": "点桶或把物品拖进桶里；答完会留下物品去向的讲解。",
		})
		browser.entry_selected.connect(func(number: Variant): _choose_level(int(number)))
		content_root.add_child(browser)
	if not engine.state.is_empty():
		engine.state.view = view
		_save("正在选择垃圾分类站")


func _choose_level(number: int) -> void:
	if not _level_unlocked(number):
		SfxMap.play(&"error")
		show_toast("先完成上一间分类站，再来挑战这里。")
		return
	SfxMap.play(&"tap")
	if _can_resume_level(number):
		level_id = number
		view = "sort"
		_build_game()
		_render(false)
		_save("继续上一间分类站")
		return
	if str(engine.state.get("phase", "")) in ["sorting", "feedback"]:
		guard_level_switch(number, func(): _start_level(number, true), func(): _resume_level(number))
		return
	_start_level(number, true)


func _resume_level(number: int) -> void:
	if not _can_resume_level(number):
		return
	level_id = number
	view = "sort"
	_build_game()
	_render(false)
	_save("继续上一间分类站")


func _start_level(number: int, announce: bool = true) -> bool:
	if players.is_empty():
		show_toast("先选择小朋友，再来分垃圾。")
		return false
	var level := _level_for(number)
	if level.is_empty():
		show_toast("这一间分类站还没有准备好。")
		return false
	var item_catalog := _catalog_for_level(level)
	level_id = number
	_result_visible = false
	engine.create_session({
		"gameId": game_id,
		"modeId": mode_id,
		"players": players.duplicate(true),
		"levelId": number,
		"levelNumber": number,
		"level": level,
		"categories": _categories.duplicate(true),
		"itemCatalog": item_catalog,
		"difficulty": difficulty,
		"seed": Time.get_ticks_usec(),
	})
	if str(engine.state.get("phase", "")) != "sorting":
		var reason := str(engine.state.get("reason", "这一关的分类内容不完整。"))
		engine.state = {}
		show_toast(reason)
		_show_map()
		return false
	session_id = str(engine.state.get("sessionId", ""))
	view = "sort"
	_build_game()
	_render(false)
	_save("开始垃圾分类站")
	if announce:
		Speech.stop()
		Speech.speak("第 %s 关，%s。%s" % [number, str(level.get("title", "垃圾分类站")), str(level.get("narration", ""))], "garbage-start")
	return true


func _catalog_for_level(level: Dictionary) -> Dictionary:
	var result := {}
	for item_id in level.get("items", []) if level.get("items") is Array else []:
		var key := str(item_id)
		if _items_by_id.get(key) is Dictionary:
			result[key] = _items_by_id[key].duplicate(true)
	return result


func _build_game() -> void:
	view = "sort"
	PlaygroundUI.clear(content_root)
	field = GarbageSortField.new()
	field.bind(engine, accent, soft_accent)
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	field.size_flags_vertical = Control.SIZE_EXPAND_FILL
	field.action_requested.connect(_on_field_action)
	field.set_paused(paused)
	content_root.add_child(field)
	sorting_actions = HBoxContainer.new()
	sorting_actions.alignment = BoxContainer.ALIGNMENT_CENTER
	sorting_actions.add_theme_constant_override("separation", 10)
	hint_button = PlaygroundUI.semantic_icon_button("hint", "提示", accent, _show_hint, "soft")
	listen_button = PlaygroundUI.semantic_icon_button("listen", "听物品", accent, _listen_current, "soft")
	sorting_actions.add_child(listen_button)
	sorting_actions.add_child(hint_button)
	content_root.add_child(sorting_actions)
	feedback_panel = PlaygroundUI.panel(PlaygroundUI.mix(soft_accent, Color.WHITE, 0.18), 22, PlaygroundUI.mix(accent, Color.WHITE, 0.36), 2)
	feedback_panel.custom_minimum_size.y = 156
	var feedback_column := VBoxContainer.new()
	feedback_column.add_theme_constant_override("separation", 7)
	feedback_panel.add_child(feedback_column)
	feedback_title = PlaygroundUI.label("", 22, accent, 700, true)
	feedback_column.add_child(feedback_title)
	feedback_text = PlaygroundUI.label("", 19, PlaygroundUI.INK, 500, true)
	feedback_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	feedback_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	feedback_column.add_child(feedback_text)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	var speak_button := PlaygroundUI.semantic_icon_button("speech", "听解释", accent, _listen_feedback, "soft")
	actions.add_child(speak_button)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(spacer)
	next_button = PlaygroundUI.semantic_icon_button("next", "下一件", accent, _next_item, "primary")
	next_button.custom_minimum_size.x = 190
	actions.add_child(next_button)
	feedback_column.add_child(actions)
	content_root.add_child(feedback_panel)


func _render(_animated: bool = true) -> void:
	if engine.state.is_empty() or not is_instance_valid(field):
		return
	if str(engine.state.get("phase", "")) == "finished":
		_show_result()
		return
	var feedback := str(engine.state.get("phase", "")) == "feedback"
	feedback_panel.visible = feedback
	sorting_actions.visible = not feedback
	hint_button.disabled = feedback
	var feedback_data: Dictionary = engine.state.get("feedback", {})
	if feedback and not feedback_data.is_empty():
		var correct := bool(feedback_data.get("correct", false))
		feedback_title.text = "分对啦，看看它为什么在这里" if correct else "一起看清它应该去哪一桶"
		feedback_text.text = "%s · 正确桶：%s\n%s" % [
			str(feedback_data.get("itemName", "生活物品")),
			str(feedback_data.get("categoryName", "正确垃圾桶")),
			str(feedback_data.get("explanation", "")),
		]
		next_button.text = "查看成绩" if int(engine.state.get("currentIndex", 0)) + 1 >= int(engine.state.get("queue", []).size()) else "下一件"
	elif str(engine.state.get("phase", "")) == "sorting":
		feedback_text.text = ""
		field.show_notice("接着分第 %s 件" % (int(engine.state.get("currentIndex", 0)) + 1), 1.0)
	field.queue_redraw()


func _on_pause_changed(value: bool) -> void:
	if field != null and is_instance_valid(field):
		field.set_paused(value)


func _on_field_action(action: Dictionary) -> void:
	if is_input_blocked() or _result_visible or view != "sort":
		return
	var result := engine.handle_input(action)
	if not bool(result.get("ok", false)):
		SfxMap.play(&"error")
		field.show_notice(str(result.get("message", "先看清楚再分。")), 1.8)
		return
	if str(result.get("event", "")) == "correct":
		SfxMap.play(&"success")
		FeedbackKit.haptic(9)
	elif str(result.get("event", "")) == "mistake":
		SfxMap.play(&"error")
		FeedbackKit.haptic(15)
	else:
		SfxMap.play(&"drop")
	_save("分类操作与解释已保存")
	_render(false)
	_speak_feedback()


func _next_item() -> void:
	if is_input_blocked():
		return
	var result := engine.handle_input({"type": "next"})
	if not bool(result.get("ok", false)):
		return
	SfxMap.play(&"turn" if engine.state.players.size() > 1 else &"next")
	_save("分类进度已保存")
	_render(false)
	if str(engine.state.get("phase", "")) == "finished":
		_save("分类站完成", false)
		_show_result()
	elif engine.state.players.size() > 1:
		var index := int(engine.state.get("currentPlayer", 0))
		show_toast("%s 接着来分类" % str(engine.state.players[index].get("name", "小伙伴")), 1.2)


func _show_hint() -> void:
	if is_input_blocked():
		return
	var result := engine.handle_input({"type": "hint"})
	if not bool(result.get("ok", false)):
		return
	SfxMap.play(&"tap")
	_save("查看分类提示")
	field.show_notice(str(result.get("hint", "先想想它还能再利用吗。")), 2.4)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	body.add_child(ArtLibrary.semantic_picture("hint", "ui", Vector2(58, 58)))
	body.add_child(PlaygroundUI.label(str(result.get("hint", "先想想它还能再利用吗。")), 20, PlaygroundUI.INK, 600, true))
	var spoken := str(result.get("hint", ""))
	if not spoken.is_empty():
		Speech.speak(spoken, "garbage-hint")
	open_modal("分类小提示", body, [
		{"text": "再读一遍", "icon": "repeat", "kind": "soft", "callback": func(): Speech.speak(spoken, "garbage-hint")},
		{"text": "继续分类", "icon": "check", "kind": "primary", "callback": func(): _close_top_modal()},
	], "提示不会直接替你选桶")


func _listen_current() -> void:
	if is_input_blocked():
		return
	var item := engine.current_item()
	if item.is_empty():
		return
	Speech.speak("%s。它应该去哪个桶呢？" % str(item.get("name", "生活物品")), "garbage-item")


func _listen_feedback() -> void:
	if is_input_blocked():
		return
	_speak_feedback()


func _speak_feedback() -> void:
	var feedback: Dictionary = engine.state.get("feedback", {})
	if feedback.is_empty():
		return
	var copy := "%s。正确桶是%s。%s" % [
		str(feedback.get("itemName", "生活物品")),
		str(feedback.get("categoryName", "正确垃圾桶")),
		str(feedback.get("explanation", "")),
	]
	Speech.speak(copy, "garbage-feedback")


func _save(note: String = "实时自动保存分类进度", resume: bool = true) -> void:
	if engine.state.is_empty() or players.is_empty():
		return
	_record_completion_if_needed()
	engine.state.view = view
	SaveStore.save_state(
		game_id,
		str(players[0].id),
		engine.snapshot(),
		note,
		resume and (view == "map" or str(engine.state.get("phase", "")) in ["sorting", "feedback"])
	)


func _record_completion_if_needed() -> bool:
	if engine.state.is_empty() or str(engine.state.get("phase", "")) != "finished":
		return false
	if bool(engine.state.get("reported", false)):
		return false
	var summary := engine.result()
	var stars := int(summary.get("stars", 0))
	var outcome := "win" if mode_id == "adventure" and stars > 0 else "played"
	var all_recorded := true
	for player in players:
		var player_id := str(player.get("id", ""))
		if player_id.is_empty():
			continue
		if mode_id == "adventure":
			SaveStore.complete_level(player_id, game_id, level_id, stars, mode_id)
		var recorded := SaveStore.record_outcome(
			player_id,
			game_id,
			outcome,
			int(summary.get("score", 0)),
			int(summary.get("correct", 0)),
			int(summary.get("answered", 0)),
			{"science": {"correct": int(summary.get("correct", 0)), "answered": int(summary.get("answered", 0))}},
			str(engine.state.get("sessionId", "garbage"))
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
		_save("分类成绩已保存", false)
	if _result_visible:
		return
	_result_visible = true
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	var trophy := ArtLibrary.semantic_picture("trophy", "ui", Vector2(84, 84))
	trophy.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	body.add_child(trophy)
	var title_text := "两位小助手一起分完啦！" if mode_id == "classic" else "这一间分类站完成啦！"
	var title := PlaygroundUI.label(title_text, 26, accent, 700, true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(title)
	var stats := "分对 %s / %s 件 · 需要再看 %s 次 · 提示 %s 次" % [
		int(summary.get("correct", 0)),
		int(summary.get("answered", 0)),
		int(summary.get("mistakes", 0)),
		int(summary.get("hints", 0)),
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
	var level: Dictionary = engine.state.get("levelData", {})
	var explanation := PlaygroundUI.label(str(level.get("explanation", "先认物品，再想它能不能回收，分类会越来越快。")), 18, PlaygroundUI.INK, 500, true)
	explanation.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(explanation)
	var actions: Array = [
		{"text": "分类地图", "icon": "game", "kind": "soft", "callback": func(): Speech.stop_owner("garbage-result"); _close_top_modal(); _show_map()},
		{"text": "再分一次", "icon": "repeat", "kind": "soft", "callback": func(): Speech.stop_owner("garbage-result"); _close_top_modal(); _start_level(level_id, true)},
	]
	if level_id < _mode_levels().size() and _level_unlocked(level_id + 1):
		actions.append({"text": "下一间", "icon": "next", "kind": "primary", "callback": _go_next_level})
	else:
		actions.append({"text": "回游戏大厅", "icon": "home", "kind": "primary", "callback": func(): Speech.stop_owner("garbage-result"); _close_all_game_dialogs(); back_requested.emit()})
	open_modal("垃圾分类站", body, actions, "四个桶，各有各的去处", false)
	SfxMap.play(&"win")
	FeedbackKit.haptic(14)
	var spoken := "垃圾分类站完成啦，分对 %s 件，得到 %s 颗星。" % [int(summary.get("correct", 0)), int(summary.get("stars", 0))]
	if mode_id == "classic" and players.size() >= 2:
		spoken = "%s和%s一起完成了分类站，环保分共享。" % [
			str(players[0].get("name", "小朋友")),
			str(players[1].get("name", "小伙伴")),
		]
	Speech.speak(spoken, "garbage-result")


func _go_next_level() -> void:
	Speech.stop_owner("garbage-result")
	_close_top_modal()
	var next_number := level_id + 1
	if next_number > _mode_levels().size() or not _level_unlocked(next_number):
		_show_map()
		return
	_start_level(next_number, true)


func _extra_pause_actions() -> Array:
	if view != "sort":
		return []
	return [{
		"text": "分类地图",
		"icon": "game",
		"kind": "soft",
		"callback": func(): _close_pause_tools(); _show_map(),
	}]


func show_help() -> void:
	if not paused and view == "sort":
		_open_pause_tools()
	Speech.stop()
	var lines := [
		"看中间的物品，先想一想它还能回收、会伤害环境，还是来自厨房。",
		"把物品拖进任意一个桶，或者直接点桶；分错也没关系，会留下正确去向和原因。",
		"两位小朋友合作时轮流操作，分类分和成绩共享，不比较输赢。",
	]
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	for index in lines.size():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var icon_name: String = ["game", "next", "check"][index]
		row.add_child(ArtLibrary.semantic_picture(icon_name, "ui", Vector2(42, 42)))
		var copy := PlaygroundUI.label(str(lines[index]), 19, PlaygroundUI.INK, 600, true)
		copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(copy)
		body.add_child(row)
	var spoken := "垃圾分类站玩法。" + " ".join(PackedStringArray(lines))
	Speech.speak(spoken, "game-help")
	open_modal("怎么玩", body, [
		{"text": "三步小课堂", "icon": "play", "kind": "soft", "callback": func(): _close_top_modal(); call_deferred("begin_lesson", true)},
		{"text": "再读一遍", "icon": "repeat", "kind": "soft", "callback": func(): Speech.speak(spoken, "game-help")},
		{"text": "知道了", "icon": "check", "kind": "primary", "callback": func(): _close_top_modal()},
	], "拖放或点击都能分类")


func begin_lesson(force: bool = false) -> void:
	if not force:
		return
	if not paused:
		_open_pause_tools()
	lesson_texts = [
		"看中间的大物品卡，听一听它的名字。",
		"把它拖到有正确标志的桶里；也可以直接点一个桶。",
		"读一读为什么放在这里，再点下一件；两位小朋友轮流来。",
	]
	_lesson_icons = ["game", "next", "check"]
	call("_show_lesson_page", 0)
