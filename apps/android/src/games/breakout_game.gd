class_name NativeBreakoutGame
extends NativeGameScreen

const RULES = preload("res://src/games/breakout_rules.gd")
const FIELD = preload("res://src/ui/breakout_field.gd")
const CONTENT_PATH := "res://content/breakout.json"
const FALLBACK_TITLE := "砖块小城堡"
const FALLBACK_ACCENT := "#b35f36"
const FALLBACK_SOFT := "#f7e7dc"
const BREAKOUT_VERSION := 1
const BAND_LABELS := {"easy": "轻松", "normal": "标准", "challenge": "挑战"}
const BAND_AGES := {"easy": "推荐 4–6 岁", "normal": "推荐 7–9 岁", "challenge": "推荐 10–12 岁"}
const FALLBACK_MODES := {
	"adventure": {"id": "adventure", "name": "砖堡闯关", "player_range": [1, 1], "description": "18 座固定砖堡，挡板接球、砖块和道具"},
	"classic": {"id": "classic", "name": "双人守护", "player_range": [2, 2], "description": "两块挡板一起守护小球，共享爱心与进度"},
}

var engine = RULES.new()
var field: BreakoutField
var soft_accent := Color(FALLBACK_SOFT)
var view := "map"
var _levels_cache: Array = []
var _catalog_issues: Array[String] = []
var _result_visible := false
var _save_clock := 0.0


func _ready() -> void:
	if game_id.is_empty():
		game_id = "breakout"
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
			show_toast("上次的城堡存档不完整，已从第 %s 关开头重新准备。" % recovery_level, 3.0)
			return
	_show_map()


func preview_ready() -> void:
	if field != null and is_instance_valid(field):
		field.queue_redraw()


func _load_levels() -> void:
	_levels_cache.clear()
	_catalog_issues.clear()
	var parsed: Variant = null
	if ContentDB.has_method("breakout_levels"):
		var values: Variant = ContentDB.call("breakout_levels")
		if values is Array and not values.is_empty():
			parsed = {"schemaVersion": 1, "id": "breakout", "levels": values}
	if not parsed is Dictionary and ContentDB.get("breakout_data") is Dictionary:
		parsed = ContentDB.get("breakout_data")
	if not parsed is Dictionary and FileAccess.file_exists(CONTENT_PATH):
		parsed = JSON.parse_string(FileAccess.get_file_as_string(CONTENT_PATH))
	if not parsed is Dictionary:
		_catalog_issues.append("找不到 breakout.json")
		return
	var validation: Dictionary = RULES.validate_catalog(parsed)
	if not bool(validation.get("ok", false)):
		for issue in validation.get("issues", []):
			_catalog_issues.append(str(issue))
		for issue in _catalog_issues:
			push_warning("砖块小城堡内容：" + issue)
		return
	var values: Variant = validation.get("validLevels", [])
	if values is Array:
		for raw in values:
			if raw is Dictionary:
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
		and int(engine.state.get("levelNumber", -1)) == number
		and str(engine.state.get("modeId", "")) == mode_id
		and str(engine.state.get("phase", "")) == "playing"
		and int(engine.state.get("breakoutVersion", 0)) == BREAKOUT_VERSION
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
	copy.add_child(PlaygroundUI.label("砖块城堡大门", 30, accent, 700, true))
	var subtitle := "拖动挡板接住小球，敲下彩色砖块，守住每一颗爱心。"
	if mode_id == "classic":
		subtitle = "两位小朋友各守一块挡板，共享砖块、分数和爱心，不比较输赢。"
	copy.add_child(PlaygroundUI.label(subtitle, 18, PlaygroundUI.INK_SOFT, 500, true))
	heading.add_child(copy)
	heading.add_child(PlaygroundUI.chip("18 座砖堡" if mode_id == "adventure" else "6 座双人砖堡", accent))
	heading.add_child(PlaygroundUI.semantic_icon_button("rules", "怎么玩", accent, show_help, "soft"))
	content_root.add_child(heading)
	if not _catalog_issues.is_empty():
		var warning := PlaygroundUI.panel(PlaygroundUI.mix(soft_accent, Color.WHITE, 0.28), 16, PlaygroundUI.mix(accent, Color.WHITE, 0.45), 1)
		warning.add_child(PlaygroundUI.label("砖堡图纸有 %s 处需要检查，暂时只显示可玩的城堡。" % _catalog_issues.size(), 16, PlaygroundUI.INK_SOFT, 600, true))
		content_root.add_child(warning)
	var levels := _mode_levels()
	if levels.is_empty():
		var empty := PlaygroundUI.panel(PlaygroundUI.mix(soft_accent, Color.WHITE, 0.28), 22, PlaygroundUI.TOOL_LINE, 2)
		empty.add_child(PlaygroundUI.label("砖块城堡还没有准备好，请稍后再来看看。", 20, PlaygroundUI.INK_SOFT, 600, true))
		content_root.add_child(empty)
		if not engine.state.is_empty():
			engine.state.view = view
			_save("正在选择砖块城堡")
		return
	var entries: Array = []
	for index in levels.size():
		var entry: Dictionary = levels[index]
		var number := index + 1
		entries.append({
			"id": number,
			"title": str(entry.get("title", "砖块城堡")),
			"subtitle": "%s · %s" % [
				str(BAND_LABELS.get(str(entry.get("band", "")), "轻松")),
				str(BAND_AGES.get(str(entry.get("band", "")), "")),
			],
			"locked": not _level_unlocked(number),
			"stars": _star_count(number),
			"in_progress": _can_resume_level(number),
		})
	var browser := GameBrowser.new()
	browser.configure(entries, {
		"accent": accent,
		"title": "选择一座砖块城堡",
		"subtitle": "每座城堡的砖墙都固定，接住小球再找下一处缺口。",
	})
	browser.entry_selected.connect(func(number: Variant): _choose_level(int(number)))
	content_root.add_child(browser)
	if not engine.state.is_empty():
		engine.state.view = view
		_save("正在选择砖块城堡")


func _choose_level(number: int) -> void:
	if not _level_unlocked(number):
		SfxMap.play(&"error")
		show_toast("先完成前一座砖堡，再来挑战这一座。")
		return
	SfxMap.play(&"tap")
	if _can_resume_level(number):
		level_id = number
		view = "board"
		_build_board()
		_refresh()
		_save("继续上一座砖块城堡")
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
	_save("继续上一座砖块城堡")


func _start_level(number: int, announce: bool = true) -> bool:
	if players.is_empty():
		show_toast("先选择小朋友，再来守护砖堡。")
		return false
	var entry := _level_for(number)
	if entry.is_empty():
		show_toast("这座砖块城堡还没有准备好。")
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
		var reason := str(engine.state.get("reason", "这座砖块城堡不完整。"))
		engine.state = {}
		show_toast(reason)
		_show_map()
		return false
	session_id = str(engine.state.get("sessionId", ""))
	view = "board"
	_build_board()
	_refresh()
	_save("开始守卫砖块城堡")
	if announce:
		Speech.stop()
		Speech.speak(
			"第 %s 关，%s。拖动挡板接住小球，敲下彩色砖块。" % [number, str(entry.get("title", "砖块城堡"))],
			"breakout-start"
		)
	return true


func _build_board() -> void:
	view = "board"
	PlaygroundUI.clear(content_root)
	field = FIELD.new()
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
				_save("砖块小城堡自动保存")
		if str(engine.state.get("phase", "")) == "finished":
			_save("砖块小城堡本局完成", false)
			_show_result()
	else:
		_save_clock = 0.0


func _on_field_action(action: Dictionary) -> void:
	if _blocked() or _result_visible or view != "board":
		return
	Speech.stop_owner("breakout-feedback")
	var action_type := str(action.get("type", ""))
	var result := engine.handle_input(action)
	if not bool(result.get("ok", false)):
		field.flash_notice(str(result.get("message", "这个操作现在不能用")))
		SfxMap.play(&"error")
		return
	if action_type == "hint":
		_save("看了砖堡提示")
		field.flash_notice(str(result.get("hint", "接住小球，留意下一块砖。")), 3.0)
		SfxMap.play(&"tap")
		_refresh()
		return
	field.consume_events(engine.drain_events())
	_save("砖块小城堡操作保存")
	_refresh()
	if str(engine.state.get("phase", "")) == "finished":
		_save("砖块小城堡本局完成", false)
		_show_result()


func _save(note: String = "实时自动保存砖堡进度", resume: bool = true) -> void:
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
	var success := bool(summary.get("success", false))
	if not success:
		engine.state.reported = true
		return true
	var stars := int(summary.get("stars", engine.stars()))
	var session := str(engine.state.get("sessionId", "breakout"))
	var score := int(summary.get("score", 0))
	var broken := int(summary.get("bricksBroken", 0))
	var total := maxi(1, int(summary.get("bricksTotal", 1)))
	var outcome := "played" if mode_id == "classic" else "win"
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
			score,
			broken,
			total,
			{"logic": {"correct": broken, "answered": total}},
			session
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
		_save("砖块小城堡结算保存", false)
	if _result_visible:
		return
	_result_visible = true
	var success := bool(summary.get("success", false))
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	var trophy := ArtLibrary.semantic_picture("trophy" if success else "hint", "ui", Vector2(80, 80))
	trophy.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	body.add_child(trophy)
	var title_text := "砖块城堡完成啦！"
	if not success:
		title_text = "爱心用完啦，再看看落点"
	elif mode_id == "classic" and players.size() >= 2:
		title_text = "两位小朋友一起守住了砖堡！"
	var title := PlaygroundUI.label(title_text, 27, accent, 700, true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(title)
	var stats := "敲下 %s/%s 块砖 · 得分 %s · 剩余爱心 %s · 最高连击 %s" % [
		int(summary.get("bricksBroken", 0)),
		int(summary.get("bricksTotal", 0)),
		int(summary.get("score", 0)),
		int(summary.get("lives", 0)),
		int(summary.get("bestCombo", 0)),
	]
	var stats_label := PlaygroundUI.label(stats, 18, PlaygroundUI.INK_SOFT, 500, true)
	stats_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(stats_label)
	if success:
		var stars_row := HBoxContainer.new()
		stars_row.alignment = BoxContainer.ALIGNMENT_CENTER
		stars_row.add_theme_constant_override("separation", 8)
		for index in 3:
			var star := ArtLibrary.semantic_picture("star", "ui", Vector2(38, 38))
			star.modulate = Color.WHITE if index < int(summary.get("stars", 0)) else Color(1, 1, 1, 0.24)
			stars_row.add_child(star)
		body.add_child(stars_row)
	var explanation_text := str(engine.state.get("level", {}).get("explanation", ""))
	if not success:
		explanation_text = str(summary.get("reason", "先观察小球落点，再移动挡板。")) + "\n" + explanation_text
	if not explanation_text.is_empty():
		var explanation := PlaygroundUI.label(explanation_text, 18, PlaygroundUI.INK, 500, true)
		explanation.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		body.add_child(explanation)
	var actions: Array = [
		{"text": "回看砖堡", "icon": "back", "kind": "soft", "callback": func(): _result_visible = false; Speech.stop_owner("breakout-result"); _close_top_modal()},
		{"text": "砖堡地图", "icon": "game", "kind": "soft", "callback": func(): Speech.stop_owner("breakout-result"); _close_top_modal(); _show_map()},
	]
	if not success:
		actions = [
			{"text": "砖堡地图", "icon": "game", "kind": "soft", "callback": func(): Speech.stop_owner("breakout-result"); _close_top_modal(); _show_map()},
			{"text": "再来一次", "icon": "restart", "kind": "primary", "callback": func(): Speech.stop_owner("breakout-result"); _close_top_modal(); _start_level(level_id, false)},
		]
	elif level_id < _mode_levels().size() and _level_unlocked(level_id + 1):
		actions.append({"text": "下一座砖堡", "icon": "next", "kind": "primary", "callback": _go_next_level})
	else:
		actions.append({"text": "回游戏大厅", "icon": "home", "kind": "primary", "callback": func(): Speech.stop_owner("breakout-result"); _close_all_game_dialogs(); back_requested.emit()})
	open_modal("砖块小城堡", body, actions, SaveStore.save_status_text(), false)
	SfxMap.play(&"win" if success else &"error")
	FeedbackKit.haptic(14 if success else 7)
	var spoken := "砖块城堡完成，获得 %s 颗评价星。" % int(summary.get("stars", 0)) if success else "这一座砖堡还没有完成，再试一次就会更熟练。"
	if success and mode_id == "classic" and players.size() >= 2:
		spoken = "%s和%s一起守住了砖块城堡。" % [
			str(players[0].get("name", "小朋友")),
			str(players[1].get("name", "小伙伴")),
		]
	Speech.speak(spoken, "breakout-result")


func _go_next_level() -> void:
	Speech.stop_owner("breakout-result")
	_close_top_modal()
	var next_number := level_id + 1
	if next_number > _mode_levels().size() or not _level_unlocked(next_number):
		_show_map()
		return
	_start_level(next_number, true)


func _extra_pause_actions() -> Array:
	if view != "board" or str(engine.state.get("phase", "")) != "playing":
		return []
	return [
		{"text": "砖堡地图", "icon": "game", "kind": "soft", "callback": func(): _close_pause_tools(); _show_map()},
		{"text": "看看提示", "icon": "hint", "kind": "soft", "callback": _show_hint},
	]


func _show_hint() -> void:
	var result := engine.hint()
	if not bool(result.get("ok", false)):
		field.flash_notice(str(result.get("message", "暂时没有提示")))
		return
	_save("看了砖堡提示")
	field.flash_notice(str(result.get("hint", "接住小球，留意下一块砖。")), 3.0)
	SfxMap.play(&"tap")
	_refresh()


func _confirm_restart() -> void:
	if view != "board" or engine.state.is_empty():
		_close_pause_tools()
		show_toast("先选一座砖块城堡，再重新开始。")
		return
	var text := PlaygroundUI.label("本关会回到最初的砖墙；其他城堡、已获得星星和儿童档案不会受影响。", 19, PlaygroundUI.INK_SOFT, 500, true)
	open_modal("重开这一关？", text, [
		{"text": "继续这局", "icon": "back", "kind": "soft", "callback": func(): _close_top_modal()},
		{"text": "重新开始", "icon": "restart", "kind": "primary", "callback": _restart_from_confirm},
	], "砖块小城堡")


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
		"按住并左右拖动挡板，让小球落在挡板中央。",
		"小球碰到砖块会反弹；把全部砖块敲下来，就完成这一座城堡。",
		"接住道具会有宽挡板、慢球或额外爱心，失效前尽快用上。",
		"双人守护时，左边小朋友管左半场，右边小朋友管右半场，共享爱心和进度。",
	]
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	var icons := ["play", "game", "star", "hint"]
	for index in lines.size():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		row.add_child(ArtLibrary.semantic_picture(str(icons[index]), "ui", Vector2(42, 42)))
		var copy := PlaygroundUI.label(str(lines[index]), 19, PlaygroundUI.INK, 600, true)
		copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(copy)
		body.add_child(row)
	var spoken := "砖块小城堡玩法。" + " ".join(PackedStringArray(lines))
	Speech.speak(spoken, "game-help")
	open_modal("怎么玩", body, [
		{"text": "三步小课堂", "icon": "play", "kind": "soft", "callback": func(): _close_top_modal(); call_deferred("begin_lesson", true)},
		{"text": "再读一遍", "icon": "repeat", "kind": "soft", "callback": func(): Speech.speak(spoken, "game-help")},
		{"text": "知道了", "icon": "check", "kind": "primary", "callback": func(): _close_top_modal()},
	], "拖动挡板，接住小球")


func _show_rules() -> void:
	var lines := [
		"挡板只在小球下方左右移动，小球碰到左右墙、顶部和砖块都会反弹。",
		"普通砖块敲一下就会碎；带裂纹的厚砖要敲两下，每次碰撞都会留下反馈。",
		"爱心是小球掉出底边的保护次数；双人模式共享爱心，不单独比较输赢。",
		"宽挡板会加长挡板，慢球会让冰球短暂减速，额外爱心会补回一颗爱心。",
		"全部砖块敲下就过关；爱心用完则本关结束，可以重新开始。",
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
	Speech.speak(" ".join(PackedStringArray(lines)), "breakout-help")
	open_modal("砖块城堡规则", body, [
		{"text": "读给我听", "icon": "speech", "kind": "soft", "callback": func(): Speech.repeat()},
		{"text": "知道了", "icon": "check", "kind": "primary", "callback": func(): _close_top_modal()},
	], "接球、反弹、敲砖")


func begin_lesson(force: bool = false) -> void:
	if not force:
		return
	if not paused and view == "board":
		_open_pause_tools()
	lesson_texts = [
		"先把手指放到小球会落下的那一边，拖动挡板跟上小球。",
		"挡板中央接球最稳；接到道具后，宽挡板和慢球会帮你更容易接住。",
		"敲下全部砖块就完成城堡；双人时两个人一起守住同一排爱心。",
	]
	_lesson_icons = ["play", "hint", "star"]
	call("_show_lesson_page", 0)
