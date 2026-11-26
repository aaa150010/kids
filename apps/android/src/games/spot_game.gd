class_name NativeSpotGame
extends NativeGameScreen

var engine := SpotRules.new()
var board: SpotBoard
var status: Label
var found_chip: PanelContainer
var hint_chip: PanelContainer
var found_label: Label
var hint_label: Label
var player_row: HBoxContainer
var game_tools: Control
var view := "map"
var _scenes_cache: Array = []
var _result_visible := false


func _ready() -> void:
	build_shell()
	var stored := SaveStore.load_state(game_id, players.map(func(player): return str(player.id)))
	var had_stored := not stored.is_empty()
	stored.modeId = mode_id
	var restored := had_stored and stored.get("players") is Array and engine.restore(stored)
	if restored:
		players = engine.state.players.duplicate(true)
		level_id = int(engine.state.get("levelId", 1))
		view = str(engine.state.get("view", "scene"))
		var scenes := _scenes()
		var content_matches := level_id >= 1 and level_id <= scenes.size() and str(engine.state.get("sceneId", "")) == str(scenes[level_id - 1].get("id", ""))
		if not content_matches:
			engine.state = {}
			if level_id >= 1 and level_id <= scenes.size() and _new_session():
				_build_scene()
				_refresh()
				show_toast("上次的画页不完整，已从第 %s 关开头重新开始。" % level_id, 2.8)
				return
			_show_map()
			return
		if engine.state.phase == "result" and not bool(stored.get("resume", true)):
			engine.state = {}
			_show_map()
			return
	else:
		engine.state = {}
		var recovery_level := int(stored.get("levelId", 0)) if had_stored else 0
		if recovery_level >= 1 and recovery_level <= _scenes().size():
			level_id = recovery_level
			if _new_session():
				_build_scene()
				_refresh()
				show_toast("上次的画页不完整，已从第 %s 关开头重新开始。" % level_id, 2.8)
				return
		_show_map()
		return
	if view == "map":
		_show_map()
	else:
		_build_scene()
		_refresh()
		if engine.state.phase == "result":
			_show_result()


func _scenes() -> Array:
	if not _scenes_cache.is_empty():
		return _scenes_cache
	if ContentDB.has_method("spot_scene_data"):
		_scenes_cache = ContentDB.spot_scene_data().duplicate(true)
	if _scenes_cache.is_empty() and ContentDB.get("spot_scenes") is Array:
		_scenes_cache = ContentDB.get("spot_scenes").duplicate(true)
	if _scenes_cache.is_empty():
		var path := "res://content/spot.json"
		if FileAccess.file_exists(path):
			var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
			if parsed is Array:
				_scenes_cache = parsed.duplicate(true)
			elif parsed is Dictionary and parsed.get("scenes") is Array:
				_scenes_cache = parsed.get("scenes").duplicate(true)
	_scenes_cache = _scenes_cache.filter(func(entry): return entry is Dictionary and not str(entry.get("id", "")).is_empty())
	return _scenes_cache


func _unlocked(number: int) -> bool:
	for player in players:
		if SaveStore.level_unlocked(str(player.id), game_id, number, mode_id):
			return true
	return false


func _stars_for(number: int) -> int:
	var stars := 0
	for player in players:
		stars = maxi(stars, int(SaveStore.learning(str(player.id), game_id, mode_id).stars.get(str(number), 0)))
	return clampi(stars, 0, 3)


func _show_map() -> void:
	Speech.stop_owner("spot-hint")
	Speech.stop_owner("spot-result")
	view = "map"
	_result_visible = false
	PlaygroundUI.clear(content_root)
	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation", 12)
	var title := PlaygroundUI.label("今天找哪一页？", 30, accent, 700, true)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(title)
	heading.add_child(PlaygroundUI.chip("双人一起找" if mode_id == "classic" else "单人侦探", accent))
	content_root.add_child(heading)
	var second_name := "小伙伴"
	if players.size() > 1:
		second_name = str(players[1].get("name", "小伙伴"))
	var copy := "左右两张图几乎一样，找出 5 处不同。找到后两张图会一起圈出来。" if mode_id == "adventure" else "%s 和 %s 一起找，找到的不同会同时记在两张图上。" % [players[0].get("name", "小朋友"), second_name]
	content_root.add_child(PlaygroundUI.label(copy, 18, PlaygroundUI.INK_SOFT, 500, true))
	var scenes := _scenes()
	if scenes.is_empty():
		var empty := PlaygroundUI.panel(PlaygroundUI.mix(accent, Color.WHITE, 0.9), 22, PlaygroundUI.TOOL_LINE, 2)
		empty.add_child(PlaygroundUI.label("找不同的画页还没有准备好，请稍后再来看看。", 20, PlaygroundUI.INK_SOFT, 600, true))
		content_root.add_child(empty)
		return
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	var grid := GridContainer.new()
	var viewport_width := get_viewport_rect().size.x
	grid.columns = 3 if viewport_width <= 1180.0 else 4 if viewport_width < 1500.0 else 6
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	for index in scenes.size():
		var scene: Dictionary = scenes[index]
		var number := index + 1
		var unlocked := _unlocked(number)
		var stars := _stars_for(number)
		var resume_here := _can_resume_level(number)
		var state_text := "尚未解锁"
		if unlocked and resume_here:
			state_text = "继续这一页 · 已找到 %s / %s" % [engine.found_count(), engine.total()]
		elif unlocked:
			state_text = "已获 %s / 3 星" % stars if stars > 0 else "可以开始寻找"
		var button := PlaygroundUI.semantic_icon_button(
			"play" if unlocked else "lock",
			"第 %s 关\n%s\n%s" % [number, str(scene.get("title", "找不同")), state_text],
			accent,
			_choose_level.bind(number),
			"soft",
			18
		)
		button.custom_minimum_size = Vector2(0, 124)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.disabled = not unlocked
		grid.add_child(button)
	scroll.add_child(grid)
	content_root.add_child(scroll)
	if not engine.state.is_empty():
		engine.state.view = view
		_save("正在选择找不同关卡", false)


func _choose_level(number: int) -> void:
	if not _unlocked(number):
		show_toast("先完成前一关，再来挑战这一关。")
		return
	level_id = number
	var resuming := _can_resume_level(number)
	if not resuming and not _new_session():
		return
	view = "scene"
	_result_visible = false
	if resuming:
		_save("继续找不同")
	_build_scene()
	_refresh()
	begin_lesson()


func _can_resume_level(number: int) -> bool:
	if engine.state.is_empty() or str(engine.state.get("phase", "")) != "playing":
		return false
	if int(engine.state.get("levelId", 0)) != number:
		return false
	var scenes := _scenes()
	if number < 1 or number > scenes.size():
		return false
	return str(engine.state.get("sceneId", "")) == str(scenes[number - 1].get("id", ""))


func _new_session() -> bool:
	Speech.stop_owner("spot-hint")
	Speech.stop_owner("spot-result")
	var scenes := _scenes()
	if scenes.is_empty() or level_id < 1 or level_id > scenes.size():
		show_toast("找不同内容还没有准备好。")
		return false
	var scene: Dictionary = scenes[level_id - 1]
	engine.create_session({
		"gameId": game_id,
		"modeId": mode_id,
		"players": players.duplicate(true),
		"levelId": level_id,
		"difficulty": difficulty,
		"scene": scene,
		"hintsMax": int(GameTuning.value(game_id, difficulty, "hints", 3)),
		"view": "scene",
	})
	if str(engine.state.get("phase", "")) != "playing":
		engine.state = {}
		show_toast("这一页的画页还不完整，请换一页再来。")
		return false
	view = "scene"
	_result_visible = false
	_save("开始找不同")
	return true


func _player_chip(player: Dictionary) -> Control:
	var panel := PlaygroundUI.panel(PlaygroundUI.mix(accent, Color.WHITE, 0.9), 18, PlaygroundUI.LINE)
	panel.custom_minimum_size = Vector2(0, 58)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 9)
	panel.add_child(row)
	row.add_child(ArtLibrary.profile_picture(player, Vector2(44, 44)))
	var copy := VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.add_child(PlaygroundUI.label(str(player.get("name", "小朋友")), 17, PlaygroundUI.INK, 700, true))
	copy.add_child(PlaygroundUI.label("一起找不同" if players.size() > 1 else "仔细看一看", 13, PlaygroundUI.INK_SOFT, 500, true))
	row.add_child(copy)
	return panel


func _build_scene() -> void:
	PlaygroundUI.clear(content_root)
	var tools := HBoxContainer.new()
	tools.add_theme_constant_override("separation", 10)
	tools.add_child(PlaygroundUI.semantic_icon_button("back", "关卡", accent, _show_map, "soft"))
	found_chip = PlaygroundUI.chip("找到 0 / 5", accent)
	tools.add_child(found_chip)
	hint_chip = PlaygroundUI.chip("提示 0 / 3", accent)
	tools.add_child(hint_chip)
	found_label = found_chip.get_child(0).get_child(0) as Label
	hint_label = hint_chip.get_child(0).get_child(0) as Label
	var scene_title := str(engine.state.get("scene", {}).get("title", "找不同"))
	tools.add_child(PlaygroundUI.chip("第 %s 关 · %s" % [level_id, scene_title], accent))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tools.add_child(spacer)
	tools.add_child(PlaygroundUI.button("看提示", accent, _hint, "soft"))
	tools.add_child(PlaygroundUI.button("重新开始", accent, _confirm_restart, "ghost"))
	content_root.add_child(tools)
	game_tools = tools
	player_row = HBoxContainer.new()
	player_row.add_theme_constant_override("separation", 10)
	for player in players:
		player_row.add_child(_player_chip(player))
	content_root.add_child(player_row)
	board = SpotBoard.new()
	board.accent = accent
	board.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	board.size_flags_vertical = Control.SIZE_EXPAND_FILL
	board.point_tapped.connect(_tap)
	content_root.add_child(board)
	status = PlaygroundUI.label("左右两张图几乎一样，点出不一样的地方。", 18, PlaygroundUI.INK_SOFT, 600, true)
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content_root.add_child(status)
	board.configure(engine.state.scene, accent)
	_on_immersive_changed(immersive)


func _on_immersive_changed(value: bool) -> void:
	if player_row != null and is_instance_valid(player_row):
		player_row.visible = not value and mode_id == "classic"
	if game_tools != null and is_instance_valid(game_tools):
		game_tools.visible = true
	if status != null and is_instance_valid(status):
		status.show()


func _refresh(wrong_at: Vector2 = Vector2(-1, -1)) -> void:
	if board == null or not is_instance_valid(board) or engine.state.is_empty():
		return
	board.update_progress(engine.state.foundIds, engine.state.hintId, wrong_at)
	if found_label != null:
		found_label.text = "找到 %s / %s" % [engine.found_count(), engine.total()]
	if hint_label != null:
		hint_label.text = "提示 %s / %s" % [int(engine.state.get("hints", 0)), int(engine.state.get("hintsMax", 3))]
	var remaining := engine.total() - engine.found_count()
	var prefix := "%s一起找 · " % _player_names() if mode_id == "classic" else ""
	status.text = "%s还剩 %s 处不同。" % [prefix, remaining] if remaining > 0 else "%s全部找到啦！" % prefix
	if engine.state.phase == "result":
		board.stop_interaction()


func _player_names() -> String:
	var names := PackedStringArray()
	for player in players:
		names.append(str(player.get("name", "小朋友")))
	return " 和 ".join(names)


func _tap(position: Vector2, touch_radius: float) -> void:
	if is_input_blocked() or engine.state.phase != "playing":
		return
	var result := engine.handle_input({"type": "tap", "x": position.x, "y": position.y, "touchRadius": touch_radius})
	if not bool(result.get("ok", false)):
		return
	if bool(result.get("already", false)):
		SfxMap.play(&"tap")
		FeedbackKit.haptic(4)
		show_toast("这一处已经圈出来了，再看看别处。", 1.6)
		return
	if bool(result.get("wrong", false)):
		SfxMap.play(&"error")
		FeedbackKit.haptic(12)
		_save("找不同点时看错了")
		_refresh(position)
		show_toast("这里没有不同，再看看别处。", 1.8)
		return
	AudioFX.play("select")
	Speech.stop_owner("spot-hint")
	FeedbackKit.haptic(7)
	_save("找到一处不同")
	_refresh()
	if bool(result.get("completed", false)):
		_show_result()


func _hint() -> void:
	if is_input_blocked() or engine.state.phase != "playing":
		return
	var result := engine.handle_input({"type": "hint"})
	if not bool(result.get("ok", false)):
		show_toast(str(result.get("message", "现在没有可用的提示。")))
		return
	AudioFX.play("whoosh")
	_save("看了一处提示")
	_refresh()
	show_toast("发光的圆圈里有一处不同。", 2.2)
	Speech.speak("发光的圆圈里有一处不同。", "spot-hint")


func _show_result() -> void:
	if engine.state.is_empty():
		return
	if not bool(engine.state.get("reported", false)):
		engine.state.reported = true
		var stars := int(engine.state.get("stars", engine.stars()))
		for player in players:
			SaveStore.complete_level(str(player.id), game_id, level_id, stars, mode_id)
			var outcome := "win" if mode_id == "adventure" else "played"
			SaveStore.record_outcome(
				str(player.id),
				game_id,
				outcome,
				stars,
				engine.found_count(),
				engine.total(),
				{},
				str(engine.state.get("sessionId", "spot"))
			)
		_save("找不同完成", false)
	if _result_visible:
		return
	_result_visible = true
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	var trophy := ArtLibrary.semantic_picture("trophy", "ui", Vector2(90, 90))
	trophy.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	body.add_child(trophy)
	var result_title := "%s一起找到全部不同啦！" % _player_names() if mode_id == "classic" else "全部不同都找到啦！"
	body.add_child(PlaygroundUI.label(result_title, 24, accent, 700, true))
	body.add_child(PlaygroundUI.label("找到 %s / %s 处 · 看提示 %s 次 · 看错 %s 次" % [engine.found_count(), engine.total(), int(engine.state.get("hints", 0)), int(engine.state.get("wrongTaps", 0))], 19, PlaygroundUI.INK_SOFT, 500, true))
	var stars_row := HBoxContainer.new()
	stars_row.alignment = BoxContainer.ALIGNMENT_CENTER
	for index in 3:
		var star := ArtLibrary.semantic_picture("star", "ui", Vector2(38, 38))
		star.modulate = Color.WHITE if index < int(engine.state.get("stars", 0)) else Color(1, 1, 1, 0.24)
		stars_row.add_child(star)
	body.add_child(stars_row)
	var actions: Array = []
	actions.append({"text": "关卡地图", "icon": "back", "kind": "soft", "callback": func(): _close_top_modal(); _show_map()})
	if level_id < _scenes().size():
		actions.append({"text": "回大厅", "icon": "home", "kind": "soft", "callback": func(): _close_top_modal(); back_requested.emit()})
		actions.append({"text": "下一关", "icon": "next", "kind": "primary", "callback": func(): _close_top_modal(); _choose_level(level_id + 1)})
	else:
		actions.append({"text": "回大厅", "icon": "home", "kind": "primary", "callback": func(): _close_top_modal(); back_requested.emit()})
	open_modal("找不同完成", body, actions, "本页已自动保存")
	SfxMap.play(&"win")
	FeedbackKit.haptic(14)
	var spoken_result := "%s一起找到全部不同。" % _player_names() if mode_id == "classic" else "全部不同都找到了。"
	Speech.speak(spoken_result, "spot-result")


func _confirm_restart() -> void:
	if view == "map":
		_close_pause_tools()
		show_toast("先选一页，再开始寻找。")
		return
	open_modal("重新找这一页？", PlaygroundUI.label("这一页找到的不同会重新开始，其他关卡和其他游戏会保留。", 19, PlaygroundUI.INK_SOFT, 500, true), [
		{"text": "继续这一页", "icon": "back", "kind": "soft", "callback": func(): _close_top_modal()},
		{"text": "重新开始", "icon": "restart", "kind": "primary", "callback": _restart_level},
	], "找不同侦探")


func _restart_level() -> void:
	_close_top_modal()
	if _new_session():
		_build_scene()
		_refresh()


func _extra_pause_actions() -> Array:
	if view == "map":
		return []
	return [{"text": "关卡地图", "icon": "back", "kind": "soft", "callback": func(): _close_pause_tools(); _show_map()}]


func begin_lesson(force: bool = false) -> void:
	if not force:
		return
	if not paused:
		_open_pause_tools()
	lesson_texts = ["左右两张图几乎一样。", "点出不一样的地方，两张图会一起圈出来。", "找不到时看提示，全部找到后点下一关。"]
	_lesson_icons = ["search", "check", "next"]
	call("_show_lesson_page", 0)


func _save(note: String = "自动保存找不同进度", resume: bool = true) -> void:
	if engine.state.is_empty():
		return
	engine.state.view = view
	SaveStore.save_state(
		game_id,
		str(players[0].id),
		engine.snapshot(),
		note,
		resume and engine.state.phase == "playing" and view == "scene"
	)
