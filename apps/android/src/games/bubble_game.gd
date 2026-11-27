class_name NativeBubbleGame
extends NativeGameScreen

const RULES = preload("res://src/games/bubble_rules.gd")
const FIELD = preload("res://src/ui/bubble_field.gd")
const CONTENT_PATH := "res://content/bubble.json"
const FALLBACK_TITLE := "泡泡星星"
const FALLBACK_ACCENT := "#2f7e91"
const FALLBACK_SOFT := "#e2f0f2"
const BUBBLE_VERSION := 1
const BAND_LABELS := {"easy":"轻松", "normal":"标准", "challenge":"挑战"}
const BAND_AGES := {"easy":"推荐 4–6 岁", "normal":"推荐 7–9 岁", "challenge":"推荐 10–12 岁"}
const FALLBACK_MODES := {
	"adventure":{"id":"adventure","name":"泡泡闯关","player_range":[1,1],"description":"18 个固定泡泡关，颜色队列和步数目标"},
	"classic":{"id":"classic","name":"双人连泡","player_range":[2,2],"description":"两人轮流发射，共享棋盘与分数"},
}

var engine = RULES.new()
var field: BubbleField
var soft_accent := Color(FALLBACK_SOFT)
var view := "map"
var _levels_cache: Array = []
var _palette_cache: Array = []
var _catalog_issues: Array[String] = []
var _result_visible := false
var _save_clock := 0.0


func _ready() -> void:
	if game_id.is_empty():
		game_id = "bubble"
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
			show_toast("上次的泡泡存档不完整，已从第 %s 关开头重新准备。" % recovery_level, 3.0)
			return
	_show_map()


func preview_ready() -> void:
	if field != null and is_instance_valid(field):
		field.queue_redraw()


func _load_levels() -> void:
	_levels_cache.clear()
	_palette_cache.clear()
	_catalog_issues.clear()
	var parsed: Variant = null
	if ContentDB.has_method("bubble_data"):
		parsed = ContentDB.call("bubble_data")
	elif ContentDB.get("bubble_data") is Dictionary:
		parsed = ContentDB.get("bubble_data")
	if not parsed is Dictionary and FileAccess.file_exists(CONTENT_PATH):
		parsed = JSON.parse_string(FileAccess.get_file_as_string(CONTENT_PATH))
	if not parsed is Dictionary:
		_catalog_issues.append("找不到 bubble.json")
		return
	var validation: Dictionary = RULES.validate_catalog(parsed)
	if not bool(validation.get("ok", false)):
		for issue in validation.get("issues", []):
			_catalog_issues.append(str(issue))
		for issue in _catalog_issues:
			push_warning("泡泡星星内容：" + issue)
		return
	var valid_levels: Variant = validation.get("validLevels", [])
	if valid_levels is Array:
		for raw in valid_levels:
			if raw is Dictionary:
				_levels_cache.append(raw.duplicate(true))
	var colors: Variant = validation.get("colors", [])
	if colors is Array:
		_palette_cache = colors.duplicate(true)


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
		and int(engine.state.get("bubbleVersion", 0)) == BUBBLE_VERSION
	)


func _mode_definition(identifier: String = "") -> Dictionary:
	var selected := identifier if not identifier.is_empty() else mode_id
	if ContentDB.has_method("mode"):
		var value: Variant = ContentDB.call("mode", game_id, selected)
		if value is Dictionary and not value.is_empty():
			return value
	return FALLBACK_MODES.get(selected, FALLBACK_MODES["adventure"]).duplicate(true)


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
	copy.add_child(PlaygroundUI.label("泡泡星图", 30, accent, 700, true))
	var subtitle := "拖动瞄准，把同一颜色连成三个以上，完成步数和星星目标。"
	if mode_id == "classic":
		subtitle = "两位小朋友轮流发射，共享棋盘、分数和颜色队列，不比较输赢。"
	copy.add_child(PlaygroundUI.label(subtitle, 18, PlaygroundUI.INK_SOFT, 500, true))
	heading.add_child(copy)
	heading.add_child(PlaygroundUI.chip("18 张星图" if mode_id == "adventure" else "6 张合作星图", accent))
	heading.add_child(PlaygroundUI.semantic_icon_button("rules", "怎么玩", accent, show_help, "soft"))
	content_root.add_child(heading)
	if not _catalog_issues.is_empty():
		var warning := PlaygroundUI.panel(PlaygroundUI.mix(soft_accent, Color.WHITE, 0.28), 16, PlaygroundUI.mix(accent, Color.WHITE, 0.45), 1)
		warning.add_child(PlaygroundUI.label("泡泡星图有 %s 处需要检查，暂时只显示可玩的关卡。" % _catalog_issues.size(), 16, PlaygroundUI.INK_SOFT, 600, true))
		content_root.add_child(warning)
	var levels := _mode_levels()
	if levels.is_empty():
		var empty := PlaygroundUI.panel(PlaygroundUI.mix(soft_accent, Color.WHITE, 0.28), 22, PlaygroundUI.TOOL_LINE, 2)
		empty.add_child(PlaygroundUI.label("泡泡星图还没有准备好，请稍后再来看看。", 20, PlaygroundUI.INK_SOFT, 600, true))
		content_root.add_child(empty)
		if not engine.state.is_empty():
			engine.state.view = view
			_save("正在选择泡泡关卡")
		return
	var entries: Array = []
	for index in levels.size():
		var entry: Dictionary = levels[index]
		var number := index + 1
		entries.append({
			"id": number,
			"title": str(entry.get("title", "泡泡星图")),
			"subtitle": "%s · %s" % [str(BAND_LABELS.get(str(entry.get("band", "")), "轻松")), str(BAND_AGES.get(str(entry.get("band", "")), ""))],
			"locked": not _level_unlocked(number),
			"stars": _star_count(number),
			"in_progress": _can_resume_level(number),
		})
	var browser := GameBrowser.new()
	browser.configure(entries, {
		"accent": accent,
		"title":"选择一张泡泡星图",
		"subtitle":"每关的颜色顺序固定，先看目标，再安排每一步。",
	})
	browser.entry_selected.connect(func(number: Variant): _choose_level(int(number)))
	content_root.add_child(browser)
	if not engine.state.is_empty():
		engine.state.view = view
		_save("正在选择泡泡关卡")


func _choose_level(number: int) -> void:
	if not _level_unlocked(number):
		SfxMap.play(&"error")
		show_toast("先完成前一关，再来挑战这张星图。")
		return
	SfxMap.play(&"tap")
	if _can_resume_level(number):
		level_id = number
		view = "board"
		_build_board()
		_refresh()
		_save("继续上一张泡泡星图")
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
	_save("继续上一张泡泡星图")


func _start_level(number: int, announce: bool = true) -> bool:
	if players.is_empty():
		show_toast("先选择小朋友，再来玩泡泡星星。")
		return false
	var entry := _level_for(number)
	if entry.is_empty():
		show_toast("这张泡泡星图还没有准备好。")
		return false
	level_id = number
	_result_visible = false
	engine.create_session({
		"gameId":game_id,
		"modeId":mode_id,
		"players":players.duplicate(true),
		"levelId":number,
		"level":entry,
		"colors":_palette_cache,
		"difficulty":difficulty,
		"seed":Time.get_ticks_usec(),
	})
	if str(engine.state.get("phase", "")) != "playing":
		var reason := str(engine.state.get("reason", "这张泡泡星图不完整。"))
		engine.state = {}
		show_toast(reason)
		_show_map()
		return false
	session_id = str(engine.state.get("sessionId", ""))
	view = "board"
	_build_board()
	_refresh()
	_save("开始泡泡星图")
	if announce:
		Speech.stop()
		Speech.speak(
			"第 %s 关，%s。先看颜色队列，拖动瞄准，松手发射。" % [number, str(entry.get("title", "泡泡星图"))],
			"bubble-start"
		)
	return true


func _build_board() -> void:
	view = "board"
	PlaygroundUI.clear(content_root)
	field = FIELD.new()
	field.accent = accent
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
				_save("泡泡星星自动保存")
		if str(engine.state.get("phase", "")) == "finished":
			_save("泡泡星星本局完成", false)
			_show_result()
	else:
		_save_clock = 0.0


func _on_field_action(action: Dictionary) -> void:
	if _blocked() or _result_visible or view != "board":
		return
	Speech.stop_owner("bubble-feedback")
	var result := engine.handle_input(action)
	if not bool(result.get("ok", false)):
		field.flash_notice(str(result.get("message", "这个操作现在不能用")))
		SfxMap.play(&"error")
		return
	field.consume_events(engine.drain_events())
	_save("泡泡星星操作保存")
	_refresh()
	if str(engine.state.get("phase", "")) == "finished":
		_save("泡泡星星本局完成", false)
		_show_result()


func _save(note: String = "实时自动保存泡泡进度", resume: bool = true) -> void:
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
	if summary.is_empty() or not bool(summary.get("success", false)):
		engine.state.reported = true
		return true
	var stars := int(summary.get("stars", engine.stars()))
	var outcome := str(summary.get("outcome", "played"))
	var session := str(engine.state.get("sessionId", "bubble"))
	var score := int(summary.get("score", 0))
	var goals_completed := engine.goal_progress().filter(func(goal): return bool(goal.get("done", false))).size()
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
			goals_completed,
			engine.goal_progress().size(),
			{"logic": {"correct": goals_completed, "answered": engine.goal_progress().size()}},
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
		_save("泡泡星星结算保存", false)
	if _result_visible:
		return
	_result_visible = true
	var success := bool(summary.get("success", false))
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	var trophy := ArtLibrary.semantic_picture("trophy" if success else "hint", "ui", Vector2(78, 78))
	trophy.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	body.add_child(trophy)
	var title_text := "泡泡星星亮起来啦！"
	if not success:
		title_text = "再瞄一次就会啦"
	elif str(engine.state.get("modeId", "")) == "classic" and players.size() >= 2:
		title_text = "两位小朋友一起点亮星图！"
	var title := PlaygroundUI.label(title_text, 27, accent, 700, true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(title)
	var stats := "连消 %s 个 · 掉落 %s 个 · 亮星 %s 颗 · 得分 %s · 用了 %s/%s 步" % [
		int(summary.get("popped", 0)),
		int(summary.get("dropped", 0)),
		int(summary.get("starsPopped", 0)),
		int(summary.get("score", 0)),
		int(summary.get("movesUsed", 0)),
		int(summary.get("movesLimit", 0)),
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
		explanation_text = str(summary.get("reason", "先看目标，再瞄准同色泡泡。")) + "\n" + explanation_text
	if not explanation_text.is_empty():
		var explanation := PlaygroundUI.label(explanation_text, 18, PlaygroundUI.INK, 500, true)
		explanation.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		body.add_child(explanation)
	var actions: Array = [
		{"text":"回看星盘", "icon":"back", "kind":"soft", "callback":func(): _result_visible = false; Speech.stop_owner("bubble-result"); _close_top_modal()},
		{"text":"关卡星图", "icon":"game", "kind":"soft", "callback":func(): Speech.stop_owner("bubble-result"); _close_top_modal(); _show_map()},
	]
	if not success:
		actions = [
			{"text":"关卡星图", "icon":"game", "kind":"soft", "callback":func(): Speech.stop_owner("bubble-result"); _close_top_modal(); _show_map()},
			{"text":"重新瞄准", "icon":"restart", "kind":"primary", "callback":func(): Speech.stop_owner("bubble-result"); _close_top_modal(); _start_level(level_id, false)},
		]
	elif level_id < _mode_levels().size() and _level_unlocked(level_id + 1):
		actions.append({"text":"下一张星图", "icon":"next", "kind":"primary", "callback":_go_next_level})
	else:
		actions.append({"text":"回游戏大厅", "icon":"home", "kind":"primary", "callback":func(): Speech.stop_owner("bubble-result"); _close_all_game_dialogs(); back_requested.emit()})
	open_modal("泡泡星星", body, actions, SaveStore.save_status_text(), false)
	SfxMap.play(&"win" if success else &"error")
	FeedbackKit.haptic(14 if success else 7)
	var spoken := "泡泡星图完成，获得 %s 颗评价星。" % int(summary.get("stars", 0)) if success else "这一张星图还没有完成，再试一次就会更熟练。"
	if success and str(engine.state.get("modeId", "")) == "classic" and players.size() >= 2:
		spoken = "%s和%s一起完成了泡泡星图。" % [str(players[0].get("name", "小朋友")), str(players[1].get("name", "小伙伴"))]
	Speech.speak(spoken, "bubble-result")


func _go_next_level() -> void:
	Speech.stop_owner("bubble-result")
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
		{"text":"关卡星图", "icon":"game", "kind":"soft", "callback":func(): _close_pause_tools(); _show_map()},
		{"text":"看看提示", "icon":"hint", "kind":"soft", "callback":_show_hint},
	]


func _show_hint() -> void:
	var result := engine.hint()
	if not bool(result.get("ok", false)):
		field.flash_notice(str(result.get("message", "暂时没有提示")))
		return
	if result.has("hintAngle"):
		var angle := deg_to_rad(float(result.hintAngle))
		engine.set_aim_direction({"x":sin(angle),"y":-cos(angle)})
	_save("看了泡泡提示")
	field.flash_notice(str(result.get("hint", "先找两颗同色泡泡，再打第三颗。")), 3.0)
	SfxMap.play(&"tap")
	_refresh()


func _confirm_restart() -> void:
	if view != "board" or engine.state.is_empty():
		_close_pause_tools()
		show_toast("先选一张泡泡星图，再重新开始。")
		return
	var text := PlaygroundUI.label("本关会回到最初的泡泡星图；其他关卡、已获得星星和儿童档案不会受影响。", 19, PlaygroundUI.INK_SOFT, 500, true)
	open_modal("重开这一关？", text, [
		{"text":"继续这局", "icon":"back", "kind":"soft", "callback":func(): _close_top_modal()},
		{"text":"重新开始", "icon":"restart", "kind":"primary", "callback":_restart_from_confirm},
	], "泡泡星星")


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
		"按住泡泡星盘拖动，瞄准线会告诉你泡泡会飞到哪里；松手就发射。",
		"三个同色泡泡连在一起会一起消失；挂在外面的泡泡也会跟着掉落。",
		"看准右侧目标和剩余步数，亮星泡泡消掉后会给额外星星。",
		"双人合作时两个人轮流发射，共用一张星盘和一份成绩。",
	]
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	var icons := ["play", "next", "star", "game"]
	for index in lines.size():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		row.add_child(ArtLibrary.semantic_picture(str(icons[index]), "ui", Vector2(42, 42)))
		var copy := PlaygroundUI.label(str(lines[index]), 19, PlaygroundUI.INK, 600, true)
		copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(copy)
		body.add_child(row)
	var spoken := "泡泡星星玩法。" + " ".join(PackedStringArray(lines))
	Speech.speak(spoken, "game-help")
	open_modal("怎么玩", body, [
		{"text":"三步小课堂", "icon":"play", "kind":"soft", "callback":func(): _close_top_modal(); call_deferred("begin_lesson", true)},
		{"text":"再读一遍", "icon":"repeat", "kind":"soft", "callback":func(): Speech.speak(spoken, "game-help")},
		{"text":"知道了", "icon":"check", "kind":"primary", "callback":func(): _close_top_modal()},
	], "拖动瞄准，松手发射")


func _show_rules() -> void:
	var lines := [
		"泡泡只能从星盘下方发射，碰顶或碰到泡泡后会停在最近的空位。",
		"同色泡泡上下左右斜着相邻都算连在一起，三颗以上就会一起消除。",
		"消除后没有连到顶部的泡泡会掉落；颜色队列每发射一次前进一格。",
		"在限定步数内完成全部目标才算过关；步数用完或泡泡碰到警戒线就要重试。",
		"合作模式固定两人轮流，每人发射一次，共享棋盘、目标和分数，不比较输赢。",
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
	Speech.speak(" ".join(PackedStringArray(lines)), "bubble-help")
	open_modal("泡泡星星规则", body, [
		{"text":"读给我听", "icon":"speech", "kind":"soft", "callback":func(): Speech.repeat()},
		{"text":"知道了", "icon":"check", "kind":"primary", "callback":func(): _close_top_modal()},
	], "六角泡泡和固定颜色队列")


func begin_lesson(force: bool = false) -> void:
	if not force:
		return
	if not paused and view == "board":
		_open_pause_tools()
	var scope := 3 if str(engine.state.get("modeId", "")) == "classic" else 3
	var copy := [
		"先看右侧目标，再看发射台前面的颜色队列。",
		"按住星盘拖动，让虚线落到同色泡泡旁边，松手发射第三颗。",
		"三颗同色泡泡连起来就会消除，掉落和亮星都会变成分数。",
	]
	if scope == 3:
		lesson_texts = copy
	_lesson_icons = ["hint", "play", "star"]
	call("_show_lesson_page", 0)
