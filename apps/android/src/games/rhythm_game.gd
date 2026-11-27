class_name NativeRhythmGame
extends NativeGameScreen

const RULES_SCRIPT := preload("res://src/games/rhythm_rules.gd")
const CONTENT_PATH := "res://content/rhythm.json"
const FALLBACK_TITLE := "节奏拍拍乐"
const FALLBACK_ACCENT := "#a77c16"
const FALLBACK_SOFT := "#f5eccb"
const BAND_LABELS := {"easy": "轻松", "normal": "标准", "challenge": "挑战"}
const BAND_AGES := {"easy": "推荐 4–6 岁", "normal": "推荐 7–9 岁", "challenge": "推荐 10–12 岁"}

var engine = RULES_SCRIPT.new()
var field: RhythmField
var soft_accent := Color(FALLBACK_SOFT)
var view := "map"
var _charts_cache: Array = []
var _catalog_issues: Array[String] = []
var _result_visible := false
var _save_clock := 0.0


func _ready() -> void:
	if game_id.is_empty():
		game_id = "rhythm"
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
	if players.size() <= 1:
		mode_id = "adventure"
	else:
		mode_id = "classic"
	_load_charts()
	SaveStore.set_context(game_id, mode_id, players.map(func(player): return str(player.id)))
	build_shell()
	pause_changed.connect(_on_pause_changed)
	var stored := SaveStore.load_state(game_id, players.map(func(player): return str(player.id)))
	var had_stored := not stored.is_empty()
	if had_stored:
		stored.modeId = mode_id
	if had_stored and engine.restore(stored):
		players = engine.state.players.duplicate(true)
		level_id = int(engine.state.get("levelNumber", engine.state.get("levelId", 1)))
		view = str(engine.state.get("view", "play"))
		_result_visible = false
		if str(engine.state.get("phase", "")) == "finished" and not bool(stored.get("resume", true)):
			_show_map()
			return
		if view == "map":
			_show_map()
			return
		_build_field()
		if str(engine.state.get("phase", "")) == "playing":
			field.start_beat()
		if str(engine.state.get("phase", "")) == "finished":
			call_deferred("_show_result")
		return
	engine.state = {}
	var recovery_level := int(stored.get("levelId", 0)) if had_stored else 0
	if recovery_level >= 1 and recovery_level <= _mode_charts().size():
		if _start_chart(recovery_level, false):
			show_toast("上次的节奏记录不完整，已从这张谱的开头重新准备。", 3.0)
			return
	_show_map()


func _load_charts() -> void:
	_charts_cache.clear()
	_catalog_issues.clear()
	if not FileAccess.file_exists(CONTENT_PATH):
		_catalog_issues.append("找不到 rhythm.json")
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONTENT_PATH))
	if not parsed is Dictionary:
		_catalog_issues.append("rhythm.json 格式不正确")
		return
	var validation: Dictionary = RULES_SCRIPT.validate_catalog(parsed)
	for issue in validation.get("issues", []):
		_catalog_issues.append(str(issue))
	var charts_value: Variant = parsed.get("charts", [])
	if not charts_value is Array:
		return
	for raw in charts_value:
		if not raw is Dictionary:
			continue
		var check: Dictionary = RULES_SCRIPT.validate_chart(raw)
		if bool(check.get("ok", false)):
			_charts_cache.append(raw.duplicate(true))
	for issue in _catalog_issues:
		push_warning("节奏拍拍乐内容：" + issue)


func _mode_charts() -> Array:
	return _charts_cache.filter(func(entry): return entry is Dictionary and str(entry.get("mode", "")) == mode_id)


func _chart_for(number: int) -> Dictionary:
	var charts := _mode_charts()
	if number < 1 or number > charts.size():
		return {}
	var value: Variant = charts[number - 1]
	return value.duplicate(true) if value is Dictionary else {}


func _level_unlocked(number: int) -> bool:
	if mode_id == "classic":
		return true
	if players.is_empty():
		return false
	return SaveStore.level_unlocked(str(players[0].id), game_id, number, mode_id)


func _star_count(number: int) -> int:
	var stars := 0
	for player in players:
		var progress := SaveStore.learning(str(player.id), game_id, mode_id)
		stars = maxi(stars, int(progress.get("stars", {}).get(str(number), 0)))
	return clampi(stars, 0, 3)


func _can_resume_chart(number: int) -> bool:
	return (
		not engine.state.is_empty()
		and str(engine.state.get("phase", "")) == "playing"
		and int(engine.state.get("levelNumber", -1)) == number
		and str(engine.state.get("modeId", "")) == mode_id
		and int(engine.state.get("rhythmVersion", 0)) == RULES_SCRIPT.RHYTHM_VERSION
	)


func _show_map() -> void:
	Speech.stop()
	if field != null and is_instance_valid(field):
		field.stop_beat()
	view = "map"
	_result_visible = false
	PlaygroundUI.clear(content_root)
	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation", 12)
	var copy := VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.add_theme_constant_override("separation", 2)
	copy.add_child(PlaygroundUI.label("今天拍哪一张谱？", 30, accent, 700, true))
	var subtitle := "一个人跟着四轨节拍轻轻点，长按的纸条要按完整。"
	if mode_id == "classic":
		subtitle = "两位小乐手一起合拍，分数共享，不分输赢。"
	copy.add_child(PlaygroundUI.label(subtitle, 18, PlaygroundUI.INK_SOFT, 500, true))
	heading.add_child(copy)
	heading.add_child(PlaygroundUI.chip("18 张单人谱" if mode_id == "adventure" else "6 张合拍谱", accent))
	heading.add_child(PlaygroundUI.semantic_icon_button("rules", "怎么玩", accent, show_help, "soft"))
	content_root.add_child(heading)
	if not _catalog_issues.is_empty():
		var warning := PlaygroundUI.panel(PlaygroundUI.mix(soft_accent, Color.WHITE, 0.24), 16, PlaygroundUI.mix(accent, Color.WHITE, 0.45), 1)
		warning.add_child(PlaygroundUI.label("节奏内容有 %s 处需要检查，暂时只显示可玩的谱面。" % _catalog_issues.size(), 16, PlaygroundUI.INK_SOFT, 600, true))
		content_root.add_child(warning)
	var charts := _mode_charts()
	if charts.is_empty():
		var empty := PlaygroundUI.panel(PlaygroundUI.mix(soft_accent, Color.WHITE, 0.24), 22, PlaygroundUI.TOOL_LINE, 2)
		empty.add_child(PlaygroundUI.label("节奏谱还没有准备好，请稍后再来看看。", 20, PlaygroundUI.INK_SOFT, 600, true))
		content_root.add_child(empty)
	else:
		var entries: Array = []
		for index in charts.size():
			var chart: Dictionary = charts[index]
			var number := index + 1
			entries.append({
				"id": number,
				"title": str(chart.get("title", "节奏谱")),
				"subtitle": "%s · %s · %s BPM" % [str(BAND_LABELS.get(str(chart.get("band", "")), "轻松")), str(BAND_AGES.get(str(chart.get("band", "")), "")), int(chart.get("bpm", 90))],
				"locked": not _level_unlocked(number),
				"stars": _star_count(number),
				"in_progress": _can_resume_chart(number),
			})
		var browser := GameBrowser.new()
		browser.configure(entries, {
			"accent": accent,
			"title": "选择一张节奏谱",
			"subtitle": "每张谱都有固定拍点和完美解，先听节拍再开始。",
		})
		browser.entry_selected.connect(func(number: Variant): _choose_chart(int(number)))
		content_root.add_child(browser)
	if not engine.state.is_empty():
		engine.state.view = view
		_save("正在选择节奏谱")


func _choose_chart(number: int) -> void:
	if not _level_unlocked(number):
		SfxMap.play(&"error")
		show_toast("先完成前一张谱，再来拍这一张。")
		return
	SfxMap.play(&"tap")
	if _can_resume_chart(number):
		level_id = number
		view = "play"
		_build_field()
		field.start_beat()
		_save("继续上一张节奏谱")
		return
	if str(engine.state.get("phase", "")) == "playing":
		guard_level_switch(number, func(): _start_chart(number, true), func(): _resume_chart(number))
		return
	_start_chart(number, true)


func _resume_chart(number: int) -> void:
	if not _can_resume_chart(number):
		return
	level_id = number
	view = "play"
	_build_field()
	field.start_beat()
	_save("继续上一张节奏谱")


func _start_chart(number: int, announce: bool = true) -> bool:
	if players.is_empty():
		show_toast("先选择小朋友，再来拍节奏。")
		return false
	var chart := _chart_for(number)
	if chart.is_empty():
		show_toast("这张节奏谱还没有准备好。")
		return false
	level_id = number
	_result_visible = false
	engine.create_session({
		"gameId": game_id,
		"modeId": mode_id,
		"players": players.duplicate(true),
		"levelId": number,
		"levelNumber": number,
		"chart": chart,
		"difficulty": difficulty,
		"seed": Time.get_ticks_usec(),
	})
	if str(engine.state.get("phase", "")) != "playing":
		var reason := str(engine.state.get("reason", "这张节奏谱不完整。"))
		engine.state = {}
		show_toast(reason)
		_show_map()
		return false
	session_id = str(engine.state.get("sessionId", ""))
	view = "play"
	_build_field()
	_save("开始节奏谱")
	if announce:
		Speech.stop()
		Speech.speak(
			"第 %s 张谱，%s。%s 先听两拍，再跟着发光的纸条点。" % [
				number,
				str(chart.get("title", "节奏谱")),
				str(chart.get("narration", "")),
			],
			"rhythm-start"
		)
	return true


func _build_field() -> void:
	view = "play"
	PlaygroundUI.clear(content_root)
	field = RhythmField.new()
	field.bind(engine, accent, soft_accent)
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	field.size_flags_vertical = Control.SIZE_EXPAND_FILL
	field.action_requested.connect(_on_field_action)
	content_root.add_child(field)
	if paused and is_instance_valid(field):
		field.set_paused(true)


func _process(delta: float) -> void:
	super._process(delta)
	if paused or view != "play" or engine.state.is_empty() or _result_visible:
		return
	if str(engine.state.get("phase", "")) != "playing":
		_save_clock = 0.0
		return
	var changed: bool = engine.tick(delta)
	if changed:
		var timed_feedback: Dictionary = engine.state.get("feedback", {}) if engine.state.get("feedback") is Dictionary else {}
		if str(timed_feedback.get("judgement", "")) == "miss":
			var lane := int(timed_feedback.get("lane", 0))
			field.show_judgement(lane, "miss", "这一拍漏掉了，继续跟住下一拍。")
			SfxMap.play(&"error")
			FeedbackKit.haptic(14)
			engine.state.feedback = {}
		_save_clock += delta
		if _save_clock >= 2.0 or str(engine.state.get("phase", "")) == "finished":
			_save_clock = 0.0
			var finished := str(engine.state.get("phase", "")) == "finished"
			_save("节奏自然漏拍保存" if not finished else "节奏谱完成", not finished)
	if str(engine.state.get("phase", "")) == "finished":
		call_deferred("_show_result")
	if field != null and is_instance_valid(field):
		field.queue_redraw()


func _on_field_action(action: Dictionary) -> void:
	if is_input_blocked() or _result_visible or view != "play":
		return
	var lane := int(action.get("lane", -1))
	if bool(action.get("cancelled", false)):
		var release_result := engine.handle_input({"type": "release", "lane": lane})
		if bool(release_result.get("ok", false)):
			_save("节奏长按取消")
		return
	var result := engine.handle_input(action)
	var judgement := str(result.get("judgement", ""))
	if not bool(result.get("ok", false)):
		field.show_judgement(lane, "stray", str(result.get("message", "这一拍先听一听")))
		if str(action.get("type", "")) == "press":
			SfxMap.play(&"error")
		return
	if judgement == "perfect":
		SfxMap.play(&"success")
		FeedbackKit.haptic(8)
	elif judgement == "good":
		SfxMap.play(&"select")
		FeedbackKit.haptic(6)
	elif judgement == "miss":
		SfxMap.play(&"error")
		FeedbackKit.haptic(14)
	elif str(result.get("event", "")) == "hold_start":
		SfxMap.play(&"tap")
		FeedbackKit.haptic(5)
	else:
		SfxMap.play(&"tap")
	field.show_judgement(lane, judgement, str(result.get("message", "")))
	engine.state.feedback = {}
	_save("节奏操作已保存")
	if str(engine.state.get("phase", "")) == "finished":
		_save("节奏谱完成", false)
		call_deferred("_show_result")


func _on_pause_changed(value: bool) -> void:
	if field == null or not is_instance_valid(field):
		return
	if value and not engine.state.is_empty():
		engine.release_all_holds()
		_save("暂停取消节奏长按")
	field.set_paused(value)
	if not value and str(engine.state.get("phase", "")) == "playing":
		AudioFX.stop_music()
		field.start_beat()


func _save(note: String = "实时自动保存节奏进度", resume: bool = true) -> void:
	if engine.state.is_empty() or players.is_empty():
		return
	_record_completion_if_needed()
	engine.state.view = view
	SaveStore.save_state(
		game_id,
		str(players[0].id),
		engine.snapshot(),
		note,
		resume and (view == "map" or str(engine.state.get("phase", "")) == "playing")
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
			int(summary.get("perfect", 0)) + int(summary.get("good", 0)),
			int(summary.get("totalNotes", 0)),
			{"memory": {"correct": int(summary.get("perfect", 0)) + int(summary.get("good", 0)), "answered": int(summary.get("totalNotes", 0))}},
			str(engine.state.get("sessionId", "rhythm"))
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
		_save("节奏成绩已保存", false)
	if _result_visible:
		return
	_result_visible = true
	if field != null and is_instance_valid(field):
		field.stop_beat()
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	var trophy := ArtLibrary.semantic_picture("trophy", "ui", Vector2(84, 84))
	trophy.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	body.add_child(trophy)
	var title_text := "两位小乐手一起拍完啦！" if mode_id == "classic" else "这一张谱拍完啦！"
	var title := PlaygroundUI.label(title_text, 26, accent, 700, true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(title)
	var stats := "得分 %s · 准确度 %s%% · 最高连击 %s\n刚刚好 %s · 跟上 %s · 漏拍 %s" % [
		int(summary.get("score", 0)),
		int(round(float(summary.get("accuracy", 0.0)) * 100.0)),
		int(summary.get("maxCombo", 0)),
		int(summary.get("perfect", 0)),
		int(summary.get("good", 0)),
		int(summary.get("miss", 0)),
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
	var chart: Dictionary = engine.state.get("chart", {})
	var explanation := PlaygroundUI.label(
		"%s\n四轨节拍靠的是先听、再对准；长按纸条要按到尾巴。" % str(chart.get("explanation", "")),
		18,
		PlaygroundUI.INK,
		500,
		true
	)
	explanation.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(explanation)
	var actions: Array = [
		{"text": "节奏地图", "icon": "game", "kind": "soft", "callback": func(): Speech.stop_owner("rhythm-result"); _close_top_modal(); _show_map()},
		{"text": "再拍一次", "icon": "repeat", "kind": "soft", "callback": func(): Speech.stop_owner("rhythm-result"); _close_top_modal(); _start_chart(level_id, true)},
	]
	if level_id < _mode_charts().size() and _level_unlocked(level_id + 1):
		actions.append({"text": "下一张谱", "icon": "next", "kind": "primary", "callback": _go_next_chart})
	else:
		actions.append({"text": "回游戏大厅", "icon": "home", "kind": "primary", "callback": func(): Speech.stop_owner("rhythm-result"); _close_all_game_dialogs(); back_requested.emit()})
	open_modal("节奏拍拍乐", body, actions, "四轨合拍，共享掌声", false)
	SfxMap.play(&"win")
	FeedbackKit.haptic(14)
	var spoken := "这一张谱拍完啦，准确度 %s%%，最高连击 %s。" % [int(round(float(summary.get("accuracy", 0.0)) * 100.0)), int(summary.get("maxCombo", 0))]
	if mode_id == "classic" and players.size() >= 2:
		spoken = "%s和%s一起拍完了这张谱，得分共享。" % [
			str(players[0].get("name", "小朋友")),
			str(players[1].get("name", "小伙伴")),
		]
	Speech.speak(spoken, "rhythm-result")


func _go_next_chart() -> void:
	Speech.stop_owner("rhythm-result")
	_close_top_modal()
	var next_number := level_id + 1
	if next_number > _mode_charts().size() or not _level_unlocked(next_number):
		_show_map()
		return
	_start_chart(next_number, true)


func _extra_pause_actions() -> Array:
	if view != "play":
		return []
	return [{
		"text": "节奏地图",
		"icon": "game",
		"kind": "soft",
		"callback": func(): _close_pause_tools(); _show_map(),
	}]


func show_help() -> void:
	if not paused and view == "play":
		_open_pause_tools()
	Speech.stop()
	var lines := [
		"先听两拍预备，纸条会从上面落下，到发光横线时点一下自己的轨道。",
		"彩色长纸条要按住，等到尾巴越过分界线再松手；提早松手会断连击。",
		"刚刚好落在线上的得分最高；稍微偏一点也能跟上，漏拍不会扣掉已经得到的掌声。",
	]
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	var icons := ["listen", "repeat", "star"]
	for index in lines.size():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		row.add_child(ArtLibrary.semantic_picture(str(icons[index]), "ui", Vector2(42, 42)))
		var copy := PlaygroundUI.label(str(lines[index]), 19, PlaygroundUI.INK, 600, true)
		copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(copy)
		body.add_child(row)
	var spoken := "节奏拍拍乐玩法。" + " ".join(PackedStringArray(lines))
	Speech.speak(spoken, "game-help")
	open_modal("怎么玩", body, [
		{"text": "三步小课堂", "icon": "play", "kind": "soft", "callback": func(): _close_top_modal(); call_deferred("begin_lesson", true)},
		{"text": "再读一遍", "icon": "repeat", "kind": "soft", "callback": func(): Speech.speak(spoken, "game-help")},
		{"text": "知道了", "icon": "check", "kind": "primary", "callback": func(): _close_top_modal()},
	], "四轨点击与长按")


func begin_lesson(force: bool = false) -> void:
	if not force:
		return
	if not paused:
		_open_pause_tools()
	lesson_texts = [
		"先听两拍，眼睛看着纸条从上方靠近发光横线。",
		"纸条碰到横线时，点它所在的那一轨；短纸条点一下，长纸条要按住。",
		"松手后继续听下一拍，四轨节拍共享一份分数。",
	]
	_lesson_icons = ["listen", "next", "star"]
	call("_show_lesson_page", 0)
