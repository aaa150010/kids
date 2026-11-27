class_name NativeAirHockeyGame
extends NativeGameScreen

const RULES = preload("res://src/games/air_hockey_rules.gd")
const FIELD = preload("res://src/ui/air_hockey_field.gd")
const CONTENT_PATH := "res://content/air_hockey.json"
const FALLBACK_TITLE := "冰球碰碰台"
const FALLBACK_ACCENT := "#3f628f"
const FALLBACK_SOFT := "#e4ecf5"
const AIR_HOCKEY_VERSION := 1
const BAND_LABELS := {"easy":"轻松", "normal":"标准", "challenge":"挑战"}
const BAND_AGES := {"easy":"推荐 4–6 岁", "normal":"推荐 7–9 岁", "challenge":"推荐 10–12 岁"}
const FALLBACK_MODES := {
	"practice":{"id":"practice","name":"目标练习","player_range":[1,1],"description":"12 张固定目标场，拖动球拍，把冰球送进星门"},
	"classic":{"id":"classic","name":"双人对抗","player_range":[2,2],"description":"左右同屏轻竞技，记录双方得分与胜平负"},
}

var engine = RULES.new()
var field: AirHockeyField
var soft_accent := Color(FALLBACK_SOFT)
var view := "map"
var _arenas_cache: Array = []
var _catalog_issues: Array[String] = []
var _result_visible := false
var _save_clock := 0.0
var _last_drag_save_msec := 0


func _ready() -> void:
	if game_id.is_empty():
		game_id = "air_hockey"
	if str(game_meta.get("title", "")).strip_edges().is_empty():
		game_meta.title = FALLBACK_TITLE
	if str(game_meta.get("accent", "")).strip_edges().is_empty():
		game_meta.accent = FALLBACK_ACCENT
		accent = PlaygroundUI.color(FALLBACK_ACCENT)
	if str(game_meta.get("soft", "")).strip_edges().is_empty():
		game_meta.soft = FALLBACK_SOFT
	soft_accent = PlaygroundUI.color(str(game_meta.get("soft", FALLBACK_SOFT)))
	if mode_id not in ["practice", "classic"]:
		mode_id = "practice" if players.size() <= 1 else "classic"
	elif mode_id == "practice" and players.size() != 1:
		mode_id = "classic"
	elif mode_id == "classic" and players.size() != 2:
		mode_id = "practice"
	_load_arenas()
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
	if recovery_level >= 1 and recovery_level <= _mode_arenas().size():
		if _start_level(recovery_level, false):
			show_toast("上次的冰球存档不完整，已从第 %s 张场地开头重新准备。" % recovery_level, 3.0)
			return
	_show_map()


func preview_ready() -> void:
	if field != null and is_instance_valid(field):
		field.queue_redraw()


func _load_arenas() -> void:
	_arenas_cache.clear()
	_catalog_issues.clear()
	var parsed: Variant = null
	var content_value: Variant = ContentDB.get("air_hockey_data")
	if content_value is Dictionary and not content_value.is_empty():
		parsed = content_value
	elif FileAccess.file_exists(CONTENT_PATH):
		parsed = JSON.parse_string(FileAccess.get_file_as_string(CONTENT_PATH))
	if not parsed is Dictionary:
		_catalog_issues.append("找不到 air_hockey.json")
		return
	var validation: Dictionary = RULES.validate_catalog(parsed)
	if not bool(validation.get("ok", false)):
		for issue in validation.get("issues", []):
			_catalog_issues.append(str(issue))
		for issue in _catalog_issues:
			push_warning("冰球碰碰台内容：" + issue)
		return
	var arenas_value: Variant = validation.get("validArenas", [])
	if arenas_value is Array:
		for raw in arenas_value:
			if raw is Dictionary:
				_arenas_cache.append(raw.duplicate(true))


func _mode_arenas() -> Array:
	return _arenas_cache.filter(func(entry): return entry is Dictionary and str(entry.get("mode", "")) == mode_id)


func _arena_for(number: int) -> Dictionary:
	var arenas := _mode_arenas()
	if number < 1 or number > arenas.size():
		return {}
	var value: Variant = arenas[number - 1]
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
		and int(engine.state.get("airHockeyVersion", 0)) == AIR_HOCKEY_VERSION
	)


func _mode_definition(identifier: String = "") -> Dictionary:
	var selected := identifier if not identifier.is_empty() else mode_id
	if ContentDB.has_method("mode"):
		var value: Variant = ContentDB.call("mode", game_id, selected)
		if value is Dictionary and not value.is_empty():
			return value
	return FALLBACK_MODES.get(selected, FALLBACK_MODES["practice"]).duplicate(true)


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
	var title_text := "冰球目标练习场" if mode_id == "practice" else "冬日双人冰球场"
	copy.add_child(PlaygroundUI.label(title_text, 30, accent, 700, true))
	var subtitle := "拖动球拍，把冰球送进固定的星门；没有电脑对手，只和自己比稳。"
	if mode_id == "classic":
		subtitle = "两位小朋友各守一边，拖动自己的球拍，把冰球推进对面球门。"
	copy.add_child(PlaygroundUI.label(subtitle, 18, PlaygroundUI.INK_SOFT, 500, true))
	heading.add_child(copy)
	heading.add_child(PlaygroundUI.chip("12 张练习台" if mode_id == "practice" else "6 张对抗台", accent))
	heading.add_child(PlaygroundUI.semantic_icon_button("rules", "怎么玩", accent, show_help, "soft"))
	content_root.add_child(heading)
	if not _catalog_issues.is_empty():
		var warning := PlaygroundUI.panel(PlaygroundUI.mix(soft_accent, Color.WHITE, 0.28), 16, PlaygroundUI.mix(accent, Color.WHITE, 0.45), 1)
		warning.add_child(PlaygroundUI.label("冰球台有 %s 处需要检查，暂时只显示可玩的场地。" % _catalog_issues.size(), 16, PlaygroundUI.INK_SOFT, 600, true))
		content_root.add_child(warning)
	var arenas := _mode_arenas()
	if arenas.is_empty():
		var empty := PlaygroundUI.panel(PlaygroundUI.mix(soft_accent, Color.WHITE, 0.28), 22, PlaygroundUI.TOOL_LINE, 2)
		empty.add_child(PlaygroundUI.label("冰球台还没有准备好，请稍后再来看看。", 20, PlaygroundUI.INK_SOFT, 600, true))
		content_root.add_child(empty)
		if not engine.state.is_empty():
			engine.state.view = view
			_save("正在选择冰球台")
		return
	var entries: Array = []
	for index in arenas.size():
		var entry: Dictionary = arenas[index]
		var number := index + 1
		entries.append({
			"id": number,
			"title": str(entry.get("title", "冰球台")),
			"subtitle": "%s · %s" % [str(BAND_LABELS.get(str(entry.get("band", "")), "轻松")), str(BAND_AGES.get(str(entry.get("band", "")), ""))],
			"locked": not _level_unlocked(number),
			"stars": _star_count(number),
			"in_progress": _can_resume_level(number),
		})
	var browser := GameBrowser.new()
	browser.configure(entries, {
		"accent": accent,
		"title": "选择一张冰球台",
		"subtitle": "练习台按顺序解锁；双人对抗台可以自由选择。",
	})
	browser.entry_selected.connect(func(number: Variant): _choose_level(int(number)))
	content_root.add_child(browser)
	if not engine.state.is_empty():
		engine.state.view = view
		_save("正在选择冰球台")


func _choose_level(number: int) -> void:
	if not _level_unlocked(number):
		SfxMap.play(&"error")
		show_toast("先完成前一张练习台，再来挑战这一张。")
		return
	SfxMap.play(&"tap")
	if _can_resume_level(number):
		level_id = number
		view = "board"
		_build_board()
		_refresh()
		_save("继续上一张冰球台")
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
	_save("继续上一张冰球台")


func _start_level(number: int, announce: bool = true) -> bool:
	if players.is_empty():
		show_toast("先选择小朋友，再来玩冰球。")
		return false
	var entry := _arena_for(number)
	if entry.is_empty():
		show_toast("这张冰球台还没有准备好。")
		return false
	level_id = number
	_result_visible = false
	engine.create_session({
		"gameId": game_id,
		"modeId": mode_id,
		"players": players.duplicate(true),
		"levelId": number,
		"arena": entry,
		"difficulty": difficulty,
		"seed": Time.get_ticks_usec(),
	})
	if str(engine.state.get("phase", "")) != "playing":
		var reason := str(engine.state.get("reason", "这张冰球台不完整。"))
		engine.state = {}
		show_toast(reason)
		_show_map()
		return false
	session_id = str(engine.state.get("sessionId", ""))
	view = "board"
	_build_board()
	_refresh()
	_save("开始冰球台")
	if announce:
		Speech.stop()
		if mode_id == "classic" and players.size() >= 2:
			Speech.speak(
				"%s守左边，%s守右边。拖动自己的球拍，把冰球推进对面球门。" % [
					str(players[0].get("name", "小朋友")),
					str(players[1].get("name", "小伙伴")),
				],
				"air-hockey-start"
			)
		else:
			Speech.speak(
				"第 %s 张练习台，%s。拖动球拍，把冰球送进发光星门。" % [number, str(entry.get("title", "冰球台"))],
				"air-hockey-start"
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
			for raw in events:
				if raw is Dictionary and str(raw.get("type", "")) in ["target", "goal"]:
					_save("冰球得分保存")
					break
		if changed:
			_save_clock += delta
			if _save_clock >= 2.0:
				_save_clock = 0.0
				_save("冰球碰碰台自动保存")
		if str(engine.state.get("phase", "")) == "finished":
			_save("冰球比赛结束", false)
			_show_result()
	else:
		_save_clock = 0.0


func _on_field_action(action: Dictionary) -> void:
	if _blocked() or _result_visible or view != "board":
		return
	var kind := str(action.get("type", ""))
	if kind == "drag_end":
		_save("球拍停稳")
		return
	Speech.stop_owner("air-hockey-feedback")
	var result := engine.handle_input(action)
	if not bool(result.get("ok", false)):
		field.flash_notice(str(result.get("message", "这个操作现在不能用")))
		SfxMap.play(&"error")
		return
	var changed := bool(result.get("changed", false))
	if kind in ["drag", "move"]:
		if changed:
			var now := Time.get_ticks_msec()
			if now - _last_drag_save_msec >= 450:
				_last_drag_save_msec = now
				_save("球拍移动")
		_refresh()
		return
	field.consume_events(engine.drain_events())
	_save("冰球操作保存")
	_refresh()
	if str(engine.state.get("phase", "")) == "finished":
		_save("冰球比赛结束", false)
		_show_result()


func _save(note: String = "实时自动保存冰球进度", resume: bool = true) -> void:
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
	if summary.is_empty():
		return false
	var session := str(engine.state.get("sessionId", "air-hockey"))
	var all_recorded := true
	if mode_id == "practice":
		var player_id := str(players[0].get("id", "")) if not players.is_empty() else ""
		if player_id.is_empty():
			return false
		var success := bool(summary.get("success", false))
		var stars := int(summary.get("stars", engine.stars()))
		var hits := int(summary.get("targetsHit", 0))
		var total := maxi(1, int(summary.get("targetTotal", 1)))
		if success:
			SaveStore.complete_level(player_id, game_id, level_id, stars, mode_id)
		var recorded := SaveStore.record_outcome(
			player_id,
			game_id,
			"win" if success else "played",
			hits,
			hits,
			total,
			{"strategy": {"correct": hits, "answered": total}},
			session
		)
		if not recorded:
			all_recorded = false
	else:
		var scores: Array = summary.get("scores", [0, 0]) if summary.get("scores") is Array else [0, 0]
		var total_goals := maxi(1, int(scores[0]) + int(scores[1]))
		var stars_by_seat: Array = summary.get("starsBySeat", [1, 1]) if summary.get("starsBySeat") is Array else [1, 1]
		for seat in players.size():
			var player_id := str(players[seat].get("id", ""))
			if player_id.is_empty():
				continue
			var own_score := int(scores[seat]) if seat < scores.size() else 0
			var seat_stars := int(stars_by_seat[seat]) if seat < stars_by_seat.size() else 1
			var outcome := engine.outcome_for_seat(seat)
			SaveStore.complete_level(player_id, game_id, level_id, seat_stars, mode_id)
			var recorded := SaveStore.record_outcome(
				player_id,
				game_id,
				outcome,
				own_score,
				own_score,
				total_goals,
				{"strategy": {"correct": own_score, "answered": total_goals}},
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
	var summary: Dictionary = engine.result()
	if summary.is_empty():
		return
	if _record_completion_if_needed():
		_save("冰球结算保存", false)
	if _result_visible:
		return
	_result_visible = true
	var success := bool(summary.get("success", false))
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	var trophy := ArtLibrary.semantic_picture("trophy" if success else "hint", "ui", Vector2(78, 78))
	trophy.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	body.add_child(trophy)
	var title_text := "目标全部点亮！"
	if mode_id == "classic":
		var winner := int(summary.get("winner", -1))
		title_text = "势均力敌的平局！" if winner < 0 else "%s先到目标分！" % str(players[winner].get("name", "小朋友"))
	elif not success:
		title_text = "再练一次会更稳"
	var title := PlaygroundUI.label(title_text, 27, accent, 700, true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(title)
	var scores: Array = summary.get("scores", [0, 0]) if summary.get("scores") is Array else [0, 0]
	var stats := ""
	if mode_id == "classic":
		var left_name := str(players[0].get("name", "左边")) if players.size() > 0 else "左边"
		var right_name := str(players[1].get("name", "右边")) if players.size() > 1 else "右边"
		stats = "%s  %s : %s  %s · 剩余 %s 秒" % [
			left_name,
			int(scores[0]),
			int(scores[1]),
			right_name,
			int(ceil(float(summary.get("timeLeft", 0.0)))),
		]
	else:
		stats = "点亮星门 %s / %s · 还剩 %s 秒" % [
			int(summary.get("targetsHit", 0)),
			int(summary.get("targetTotal", 0)),
			int(ceil(float(summary.get("timeLeft", 0.0)))),
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
	var explanation_text := str(engine.state.get("level", {}).get("explanation", ""))
	if not explanation_text.is_empty():
		var explanation := PlaygroundUI.label(explanation_text, 18, PlaygroundUI.INK, 500, true)
		explanation.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		body.add_child(explanation)
	var actions: Array = []
	if mode_id == "practice" and not success:
		actions = [
			{"text":"练习台列表", "icon":"game", "kind":"soft", "callback":func(): Speech.stop_owner("air-hockey-result"); _close_top_modal(); _show_map()},
			{"text":"重新练习", "icon":"restart", "kind":"primary", "callback":func(): Speech.stop_owner("air-hockey-result"); _close_top_modal(); _start_level(level_id, false)},
		]
	else:
		actions = [
			{"text":"回看冰面", "icon":"back", "kind":"soft", "callback":func(): _result_visible = false; Speech.stop_owner("air-hockey-result"); _close_top_modal()},
			{"text":"场地列表", "icon":"game", "kind":"soft", "callback":func(): Speech.stop_owner("air-hockey-result"); _close_top_modal(); _show_map()},
		]
		if level_id < _mode_arenas().size() and _level_unlocked(level_id + 1):
			actions.append({"text":"下一张场地", "icon":"next", "kind":"primary", "callback":_go_next_level})
		elif mode_id == "classic":
			actions.append({"text":"再来一局", "icon":"restart", "kind":"primary", "callback":func(): Speech.stop_owner("air-hockey-result"); _close_top_modal(); _start_level(level_id, false)})
		else:
			actions.append({"text":"回游戏大厅", "icon":"home", "kind":"primary", "callback":func(): Speech.stop_owner("air-hockey-result"); _close_all_game_dialogs(); back_requested.emit()})
	open_modal("冰球碰碰台", body, actions, SaveStore.save_status_text(), false)
	SfxMap.play(&"win" if success else &"error")
	FeedbackKit.haptic(14 if success else 7)
	var spoken := "所有目标都点亮了，获得 %s 颗评价星。" % int(summary.get("stars", 0)) if success else "这次还差一点，再试一次会更熟练。"
	if mode_id == "classic":
		var winner := int(summary.get("winner", -1))
		if winner < 0:
			spoken = "比赛结束，两边得分一样，是平局。"
		else:
			spoken = "%s赢下了这场冰球比赛。" % str(players[winner].get("name", "小朋友"))
	Speech.speak(spoken, "air-hockey-result")


func _go_next_level() -> void:
	Speech.stop_owner("air-hockey-result")
	_close_top_modal()
	var next_number := level_id + 1
	if next_number > _mode_arenas().size() or not _level_unlocked(next_number):
		_show_map()
		return
	_start_level(next_number, true)


func _extra_pause_actions() -> Array:
	if view != "board" or str(engine.state.get("phase", "")) != "playing":
		return []
	return [
		{"text":"场地列表", "icon":"game", "kind":"soft", "callback":func(): _close_pause_tools(); _show_map()},
		{"text":"看看提示", "icon":"hint", "kind":"soft", "callback":_show_hint},
	]


func _show_hint() -> void:
	var result := engine.hint()
	if not bool(result.get("ok", false)):
		field.flash_notice(str(result.get("message", "暂时没有提示")))
		return
	_save("看了冰球提示")
	field.flash_notice(str(result.get("hint", "先把球拍放在冰球后方，再向球门滑过去。")), 3.2)
	SfxMap.play(&"tap")
	_refresh()


func _confirm_restart() -> void:
	if view != "board" or engine.state.is_empty():
		_close_pause_tools()
		show_toast("先选一张冰球台，再重新开始。")
		return
	var text := PlaygroundUI.label("本场会回到最初的发球位置；其他练习台、已获得成绩和儿童档案不会受影响。", 19, PlaygroundUI.INK_SOFT, 500, true)
	open_modal("重开这一场？", text, [
		{"text":"继续这局", "icon":"back", "kind":"soft", "callback":func(): _close_top_modal()},
		{"text":"重新开始", "icon":"restart", "kind":"primary", "callback":_restart_from_confirm},
	], "冰球碰碰台")


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
		"按住自己的球拍拖动；松手后球拍会停在最后的位置。",
		"球拍碰到冰球时，冰球会顺着球拍滑动的方向前进。",
		"练习台要依次点亮全部星门；星门没有电脑对手会移动。",
		"双人对抗时左边守左门、右边守右门，目标分或时间到就结算。",
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
	var spoken := "冰球碰碰台玩法。" + " ".join(PackedStringArray(lines))
	Speech.speak(spoken, "game-help")
	open_modal("怎么玩", body, [
		{"text":"三步小课堂", "icon":"play", "kind":"soft", "callback":func(): _close_top_modal(); call_deferred("begin_lesson", true)},
		{"text":"再读一遍", "icon":"repeat", "kind":"soft", "callback":func(): Speech.speak(spoken, "game-help")},
		{"text":"知道了", "icon":"check", "kind":"primary", "callback":func(): _close_top_modal()},
	], "拖动球拍，碰碰冰球")


func _show_rules() -> void:
	var lines := [
		"冰球碰到围栏会反弹；球拍、冰球和围栏的碰撞都由固定 120Hz 规则计算。",
		"练习模式只有一位小朋友，没有电脑对手；每碰亮一个星门就得到一分。",
		"星门全部点亮就过关；时间结束前没点完可以重新练习。",
		"双人模式左边和右边各一只球拍、一座球门，两位小朋友同时拖动。",
		"先到目标分或时间结束时得分更多的人获胜；同分就是平局，会分别记录两边成绩。",
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
	Speech.speak(" ".join(PackedStringArray(lines)), "air-hockey-help")
	open_modal("冰球碰碰台规则", body, [
		{"text":"读给我听", "icon":"speech", "kind":"soft", "callback":func(): Speech.repeat()},
		{"text":"知道了", "icon":"check", "kind":"primary", "callback":func(): _close_top_modal()},
	], "固定冰面与无 AI 对手")


func begin_lesson(force: bool = false) -> void:
	if not force:
		return
	if not paused and view == "board":
		_open_pause_tools()
	lesson_texts = [
		"先按住自己的球拍，慢慢往冰球旁边拖。",
		"球拍碰到冰球时，继续向目标方向滑，冰球就会飞出去。",
		"练习台点亮全部星门就过关；双人台守住自己的球门并进攻对面。",
	]
	_lesson_icons = ["play", "next", "star"]
	call("_show_lesson_page", 0)
