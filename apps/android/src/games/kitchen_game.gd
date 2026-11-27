class_name NativeKitchenGame
extends NativeGameScreen

const RULES_SCRIPT := preload("res://src/games/kitchen_rules.gd")
const CONTENT_PATH := "res://content/kitchen.json"
const FALLBACK_TITLE := "小小厨房"
const FALLBACK_ACCENT := "#9b653d"
const FALLBACK_SOFT := "#f4e7da"
const BAND_LABELS := {"easy": "轻松", "normal": "标准", "challenge": "挑战"}
const BAND_AGES := {"easy": "推荐 4–6 岁", "normal": "推荐 7–9 岁", "challenge": "推荐 10–12 岁"}

var engine = RULES_SCRIPT.new()
var field: KitchenField
var feedback_panel: PanelContainer
var feedback_title: Label
var feedback_text: Label
var next_button: Button
var cooking_actions: HBoxContainer
var soft_accent := Color(FALLBACK_SOFT)
var view := "map"
var _levels_cache: Array = []
var _ingredients_by_id: Dictionary = {}
var _tools_cache: Array = []
var _templates: Dictionary = {}
var _catalog_issues: Array[String] = []
var _result_visible := false


func _ready() -> void:
	if game_id.is_empty():
		game_id = "kitchen"
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
		view = str(engine.state.get("view", "kitchen"))
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
			show_toast("上次的厨房记录不完整，已从这张订单开头重新准备。", 3.0)
			return
	_show_map()


func _load_data() -> void:
	_levels_cache.clear()
	_ingredients_by_id.clear()
	_tools_cache.clear()
	_templates.clear()
	_catalog_issues.clear()
	if not FileAccess.file_exists(CONTENT_PATH):
		_catalog_issues.append("找不到 kitchen.json")
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONTENT_PATH))
	if not parsed is Dictionary:
		_catalog_issues.append("kitchen.json 格式不正确")
		return
	var validation: Dictionary = RULES_SCRIPT.validate_catalog(parsed)
	for issue in validation.get("issues", []):
		_catalog_issues.append(str(issue))
	var ingredients_value: Variant = parsed.get("ingredients", [])
	if ingredients_value is Array:
		for ingredient in ingredients_value:
			if ingredient is Dictionary and not str(ingredient.get("id", "")).is_empty():
				_ingredients_by_id[str(ingredient.id)] = ingredient.duplicate(true)
	var tools_value: Variant = parsed.get("tools", [])
	if tools_value is Array:
		for tool in tools_value:
			if tool is Dictionary:
				_tools_cache.append(tool.duplicate(true))
	var templates_value: Variant = parsed.get("templates", {})
	if templates_value is Dictionary:
		_templates = templates_value.duplicate(true)
	var levels_value: Variant = parsed.get("levels", [])
	if levels_value is Array:
		for level in levels_value:
			if not level is Dictionary:
				continue
			var used_catalog := _ingredient_catalog_for_level(level)
			var check := RULES_SCRIPT.validate_level(level, used_catalog, _tools_cache, _templates)
			if bool(check.get("ok", false)):
				_levels_cache.append(level.duplicate(true))
	for issue in _catalog_issues:
		push_warning("小小厨房内容：" + issue)


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
		and int(engine.state.get("kitchenVersion", 0)) == RULES_SCRIPT.KITCHEN_VERSION
		and str(engine.state.get("phase", "")) in ["cooking", "feedback"]
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
	copy.add_child(PlaygroundUI.label("今天做哪一张小订单？", 30, accent, 700, true))
	var subtitle := "一个人按菜谱拿食材、加工、装盘，每一步都留下解释。"
	if mode_id == "classic":
		subtitle = "两位小厨师轮流完成一步，共享订单和分数；没有输赢。"
	copy.add_child(PlaygroundUI.label(subtitle, 18, PlaygroundUI.INK_SOFT, 500, true))
	heading.add_child(copy)
	heading.add_child(PlaygroundUI.chip("18 张单人订单" if mode_id == "adventure" else "6 张合作订单", accent))
	heading.add_child(PlaygroundUI.semantic_icon_button("rules", "怎么玩", accent, show_help, "soft"))
	content_root.add_child(heading)
	if not _catalog_issues.is_empty():
		var warning := PlaygroundUI.panel(PlaygroundUI.mix(soft_accent, Color.WHITE, 0.26), 16, PlaygroundUI.mix(accent, Color.WHITE, 0.45), 1)
		warning.add_child(PlaygroundUI.label("厨房菜谱有 %s 处需要检查，暂时只显示可玩的订单。" % _catalog_issues.size(), 16, PlaygroundUI.INK_SOFT, 600, true))
		content_root.add_child(warning)
	var levels := _mode_levels()
	if levels.is_empty():
		var empty := PlaygroundUI.panel(PlaygroundUI.mix(soft_accent, Color.WHITE, 0.26), 22, PlaygroundUI.TOOL_LINE, 2)
		empty.add_child(PlaygroundUI.label("厨房菜谱还没有准备好，请稍后再来看看。", 20, PlaygroundUI.INK_SOFT, 600, true))
		content_root.add_child(empty)
	else:
		var entries: Array = []
		for index in levels.size():
			var level: Dictionary = levels[index]
			var number := index + 1
			entries.append({
				"id": number,
				"title": str(level.get("dish", "今日小菜")),
				"subtitle": "%s · %s · %s 步" % [str(BAND_LABELS.get(str(level.get("band", "")), "练习")), str(BAND_AGES.get(str(level.get("band", "")), "")), level.get("steps", []).size()],
				"locked": not _level_unlocked(number),
				"stars": _stars_for(number),
				"in_progress": _can_resume_level(number),
			})
		var browser := GameBrowser.new()
		browser.configure(entries, {
			"accent": accent,
			"title": "选择一张厨房订单",
			"subtitle": "先看菜谱的下一步，再点食材、加工动作或小盘子。",
		})
		browser.entry_selected.connect(func(number: Variant): _choose_level(int(number)))
		content_root.add_child(browser)
	if not engine.state.is_empty():
		engine.state.view = view
		_save("正在选择厨房订单")


func _choose_level(number: int) -> void:
	if not _level_unlocked(number):
		SfxMap.play(&"error")
		show_toast("先完成上一张订单，再来挑战这里。")
		return
	SfxMap.play(&"tap")
	if _can_resume_level(number):
		level_id = number
		view = "kitchen"
		_build_game()
		_render(false)
		_save("继续上一张厨房订单")
		return
	if str(engine.state.get("phase", "")) in ["cooking", "feedback"]:
		guard_level_switch(number, func(): _start_level(number, true), func(): _resume_level(number))
		return
	_start_level(number, true)


func _resume_level(number: int) -> void:
	if not _can_resume_level(number):
		return
	level_id = number
	view = "kitchen"
	_build_game()
	_render(false)
	_save("继续上一张厨房订单")


func _start_level(number: int, announce: bool = true) -> bool:
	if players.is_empty():
		show_toast("先选择小朋友，再来做菜。")
		return false
	var level := _level_for(number)
	if level.is_empty():
		show_toast("这张厨房订单还没有准备好。")
		return false
	var ingredient_catalog := _ingredient_catalog_for_level(level)
	level_id = number
	_result_visible = false
	engine.create_session({
		"gameId": game_id,
		"modeId": mode_id,
		"players": players.duplicate(true),
		"levelId": number,
		"levelNumber": number,
		"level": level,
		"ingredientCatalog": ingredient_catalog,
		"toolCatalog": _tools_cache.duplicate(true),
		"templates": _templates,
		"difficulty": difficulty,
		"seed": Time.get_ticks_usec(),
	})
	if str(engine.state.get("phase", "")) != "cooking":
		var reason := str(engine.state.get("reason", "这张菜谱不完整。"))
		engine.state = {}
		show_toast(reason)
		_show_map()
		return false
	session_id = str(engine.state.get("sessionId", ""))
	view = "kitchen"
	_build_game()
	_render(false)
	_save("开始厨房订单")
	if announce:
		Speech.stop()
		Speech.speak("第 %s 张订单，%s。%s" % [number, str(level.get("dish", "今日小菜")), str(level.get("narration", ""))], "kitchen-start")
	return true


func _ingredient_catalog_for_level(level: Dictionary) -> Array:
	var result: Array = []
	for ingredient_id in level.get("ingredients", []) if level.get("ingredients") is Array else []:
		var value: Variant = _ingredients_by_id.get(str(ingredient_id))
		if value is Dictionary:
			result.append(value.duplicate(true))
	return result


func _build_game() -> void:
	view = "kitchen"
	PlaygroundUI.clear(content_root)
	field = KitchenField.new()
	field.bind(engine, accent, soft_accent)
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	field.size_flags_vertical = Control.SIZE_EXPAND_FILL
	field.action_requested.connect(_on_field_action)
	field.set_paused(paused)
	content_root.add_child(field)
	cooking_actions = HBoxContainer.new()
	cooking_actions.alignment = BoxContainer.ALIGNMENT_CENTER
	cooking_actions.add_theme_constant_override("separation", 10)
	cooking_actions.add_child(PlaygroundUI.semantic_icon_button("listen", "听这一步", accent, _listen_current_step, "soft"))
	cooking_actions.add_child(PlaygroundUI.semantic_icon_button("hint", "看提示", accent, _show_hint, "soft"))
	content_root.add_child(cooking_actions)
	feedback_panel = PlaygroundUI.panel(PlaygroundUI.mix(soft_accent, Color.WHITE, 0.20), 22, PlaygroundUI.mix(accent, Color.WHITE, 0.36), 2)
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
	actions.add_child(PlaygroundUI.semantic_icon_button("speech", "听解释", accent, _listen_feedback, "soft"))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(spacer)
	next_button = PlaygroundUI.semantic_icon_button("next", "下一步", accent, _next_step, "primary")
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
	cooking_actions.visible = not feedback
	var feedback_data: Dictionary = engine.state.get("feedback", {})
	if feedback and not feedback_data.is_empty():
		feedback_title.text = "这一小步做好了"
		feedback_text.text = "%s\n%s" % [
			str(feedback_data.get("title", "按菜谱完成一步")),
			str(feedback_data.get("explanation", "")),
		]
		var steps_size := int(engine.state.get("stepsData", []).size())
		next_button.text = "查看成品" if int(engine.state.get("currentStepIndex", 0)) + 1 >= steps_size else "下一步"
	else:
		var step := engine.current_step()
		if not step.is_empty():
			field.show_notice("下一步：%s" % str(step.get("label", "看菜谱")), 2.0)
	field.queue_redraw()


func _on_pause_changed(value: bool) -> void:
	if field != null and is_instance_valid(field):
		field.set_paused(value)


func _on_field_action(action: Dictionary) -> void:
	if is_input_blocked() or _result_visible or view != "kitchen":
		return
	var result := engine.handle_input(action)
	if not bool(result.get("ok", false)):
		SfxMap.play(&"error")
		field.show_notice(str(result.get("message", "这一步先听一听菜谱。")), 1.8)
		return
	if bool(result.get("correct", false)):
		SfxMap.play(&"success")
		FeedbackKit.haptic(9)
		_save("厨房步骤与解释已保存")
		_render(false)
		_speak_feedback()
	else:
		SfxMap.play(&"error")
		FeedbackKit.haptic(15)
		_save("厨房错误提示已保存")
		_render(false)
		var message := "%s。再看一遍发亮的那一步。" % str(result.get("message", "这一步和菜谱不一样。"))
		field.show_notice(message, 2.4)
		Speech.speak(message, "kitchen-feedback")


func _next_step() -> void:
	if is_input_blocked():
		return
	var result := engine.handle_input({"type": "next"})
	if not bool(result.get("ok", false)):
		return
	SfxMap.play(&"turn" if engine.state.players.size() > 1 else &"next")
	_save("厨房进度已保存")
	_render(false)
	if str(engine.state.get("phase", "")) == "finished":
		_save("厨房订单完成", false)
		_show_result()
	elif engine.state.players.size() > 1:
		var current := int(engine.state.get("currentPlayer", 0))
		show_toast("%s 接着做下一步" % str(engine.state.players[current].get("name", "小伙伴")), 1.2)


func _show_hint() -> void:
	if is_input_blocked():
		return
	var hint := engine.hint_for_current()
	if not bool(hint.get("ok", false)):
		return
	SfxMap.play(&"tap")
	_save("查看厨房提示")
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	body.add_child(ArtLibrary.semantic_picture("hint", "ui", Vector2(58, 58)))
	body.add_child(PlaygroundUI.label(str(hint.get("hint", "看菜谱发亮的那一步。")), 20, PlaygroundUI.INK, 600, true))
	Speech.speak("%s。%s" % [str(hint.get("stepLabel", "下一步")), str(hint.get("hint", ""))], "kitchen-hint")
	open_modal("厨房小提示", body, [
		{"text": "再读一遍", "icon": "repeat", "kind": "soft", "callback": func(): Speech.speak("%s。%s" % [str(hint.get("stepLabel", "下一步")), str(hint.get("hint", ""))], "kitchen-hint")},
		{"text": "继续做菜", "icon": "check", "kind": "primary", "callback": func(): _close_top_modal()},
	], "只提示动作，不替你做")


func _listen_current_step() -> void:
	if is_input_blocked():
		return
	var step := engine.current_step()
	if step.is_empty():
		return
	Speech.speak("%s。%s" % [str(step.get("label", "看菜谱下一步")), str(step.get("hint", ""))], "kitchen-step")


func _listen_feedback() -> void:
	if is_input_blocked():
		return
	_speak_feedback()


func _speak_feedback() -> void:
	var feedback: Dictionary = engine.state.get("feedback", {})
	if feedback.is_empty():
		return
	Speech.speak("%s。%s" % [str(feedback.get("title", "做好一步")), str(feedback.get("explanation", ""))], "kitchen-feedback")


func _save(note: String = "实时自动保存厨房进度", resume: bool = true) -> void:
	if engine.state.is_empty() or players.is_empty():
		return
	_record_completion_if_needed()
	engine.state.view = view
	SaveStore.save_state(
		game_id,
		str(players[0].id),
		engine.snapshot(),
		note,
		resume and (view == "map" or str(engine.state.get("phase", "")) in ["cooking", "feedback"])
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
			{"logic": {"correct": int(summary.get("correct", 0)), "answered": int(summary.get("answered", 0))}},
			str(engine.state.get("sessionId", "kitchen"))
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
		_save("厨房成绩已保存", false)
	if _result_visible:
		return
	_result_visible = true
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	var trophy := ArtLibrary.semantic_picture("trophy", "ui", Vector2(84, 84))
	trophy.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	body.add_child(trophy)
	var title_text := "两位小厨师一起端出成品！" if mode_id == "classic" else "小小厨房出餐啦！"
	var title := PlaygroundUI.label(title_text, 26, accent, 700, true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(title)
	var stats := "完成 %s 步 · 得分 %s · 最高连做 %s · 纠正 %s 次" % [
		int(summary.get("answered", 0)),
		int(summary.get("score", 0)),
		int(summary.get("maxCombo", 0)),
		int(summary.get("mistakes", 0)),
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
	var explanation := PlaygroundUI.label(str(level.get("explanation", "按顺序拿食材、加工、装盘，一步一步就能做好。")), 18, PlaygroundUI.INK, 500, true)
	explanation.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(explanation)
	var actions: Array = [
		{"text": "订单地图", "icon": "game", "kind": "soft", "callback": func(): Speech.stop_owner("kitchen-result"); _close_top_modal(); _show_map()},
		{"text": "再做一次", "icon": "repeat", "kind": "soft", "callback": func(): Speech.stop_owner("kitchen-result"); _close_top_modal(); _start_level(level_id, true)},
	]
	if level_id < _mode_levels().size() and _level_unlocked(level_id + 1):
		actions.append({"text": "下一张", "icon": "next", "kind": "primary", "callback": _go_next_level})
	else:
		actions.append({"text": "回游戏大厅", "icon": "home", "kind": "primary", "callback": func(): Speech.stop_owner("kitchen-result"); _close_all_game_dialogs(); back_requested.emit()})
	open_modal("小小厨房", body, actions, "把菜谱一步一步做出来", false)
	SfxMap.play(&"win")
	FeedbackKit.haptic(14)
	var spoken := "小小厨房出餐啦，完成 %s 步，得到 %s 颗星。" % [int(summary.get("answered", 0)), int(summary.get("stars", 0))]
	if mode_id == "classic" and players.size() >= 2:
		spoken = "%s和%s一起完成了这张厨房订单，成品共享。" % [
			str(players[0].get("name", "小朋友")),
			str(players[1].get("name", "小伙伴")),
		]
	Speech.speak(spoken, "kitchen-result")


func _go_next_level() -> void:
	Speech.stop_owner("kitchen-result")
	_close_top_modal()
	var next_number := level_id + 1
	if next_number > _mode_levels().size() or not _level_unlocked(next_number):
		_show_map()
		return
	_start_level(next_number, true)


func _extra_pause_actions() -> Array:
	if view != "kitchen":
		return []
	return [{
		"text": "订单地图",
		"icon": "game",
		"kind": "soft",
		"callback": func(): _close_pause_tools(); _show_map(),
	}]


func show_help() -> void:
	if not paused and view == "kitchen":
		_open_pause_tools()
	Speech.stop()
	var lines := [
		"上方菜谱会亮出下一步；先看它需要哪种食材、加工动作还是装盘。",
		"从食材架点正确食材，到加工台点正确动作，做好后点小盘子装盘。",
		"每一步完成后会留下解释；两位小朋友合作时，每完成一步就换人。",
	]
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	var icon_names := ["game", "next", "check"]
	for index in lines.size():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		row.add_child(ArtLibrary.semantic_picture(str(icon_names[index]), "ui", Vector2(42, 42)))
		var copy := PlaygroundUI.label(str(lines[index]), 19, PlaygroundUI.INK, 600, true)
		copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(copy)
		body.add_child(row)
	var spoken := "小小厨房玩法。" + " ".join(PackedStringArray(lines))
	Speech.speak(spoken, "game-help")
	open_modal("怎么玩", body, [
		{"text": "三步小课堂", "icon": "play", "kind": "soft", "callback": func(): _close_top_modal(); call_deferred("begin_lesson", true)},
		{"text": "再读一遍", "icon": "repeat", "kind": "soft", "callback": func(): Speech.speak(spoken, "game-help")},
		{"text": "知道了", "icon": "check", "kind": "primary", "callback": func(): _close_top_modal()},
	], "按菜谱顺序做菜")


func begin_lesson(force: bool = false) -> void:
	if not force:
		return
	if not paused:
		_open_pause_tools()
	lesson_texts = [
		"先看上方菜谱，发亮的一格就是现在要做的事。",
		"食材架拿正确食材，加工台选正确动作；错选会留下一句提示。",
		"每完成一步看解释，再点下一步；双人合作时轮流操作，共享成品。",
	]
	_lesson_icons = ["game", "next", "check"]
	call("_show_lesson_page", 0)
