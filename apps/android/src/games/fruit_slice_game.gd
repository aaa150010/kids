class_name NativeFruitSliceGame
extends NativeGameScreen

const LOGIC_STEP := 1.0 / 120.0

var engine := FruitRules.new()
var field: FruitField
var _save_clock := 0.0
var _finished := false
var _tick_accum := 0.0
var _previous_best_score := 0


func _ready() -> void:
	build_shell()
	var stored := SaveStore.load_state(game_id, players.map(func(player): return str(player.id)))
	if not stored.is_empty() and engine.restore(stored):
		players = engine.state.players.duplicate(true)
		difficulty = str(engine.state.get("difficulty", difficulty))
		level_id = 1
	else:
		engine.state = {}
		_new_session()
	_previous_best_score = _best_score_for_primary()
	_build_field()
	if str(engine.state.get("phase", "")) == "result":
		call_deferred("_show_result")
	else:
		_save("水果切切乐准备")
		if str(engine.state.get("phase", "")) == "ready" and not _resume_on_start:
			call_deferred("_announce_ready")
	call_deferred("begin_lesson")


func _new_session() -> void:
	engine.create_session({
		"gameId": game_id,
		"modeId": mode_id,
		"players": players.duplicate(true),
		"difficulty": difficulty,
		"seed": Time.get_ticks_usec(),
		"fruitTypes": ContentDB.fruit_types(),
	})
	session_id = str(engine.state.get("sessionId", ""))
	_finished = false
	_save_clock = 0.0
	_tick_accum = 0.0


func _build_field() -> void:
	field = FruitField.new()
	field.accent = accent
	field.high_score = _previous_best_score
	field.bind(engine, self)
	field.action_committed.connect(_on_field_action)
	field.game_finished.connect(_show_result)
	pause_changed.connect(func(is_paused: bool):
		if is_paused and is_instance_valid(field):
			field.suspend_effects()
			_tick_accum = 0.0
			_save_clock = 0.0
		elif not is_paused and str(engine.state.get("phase", "")) == "ready":
			Speech.speak("轻点开始，用手指划过水果。", "fruit-slice-ready")
	)
	set_content(field)


func _process(delta: float) -> void:
	super._process(delta)
	if paused or not is_instance_valid(field) or _blocked():
		return
	var phase := str(engine.state.get("phase", ""))
	if phase == "playing":
		_tick_accum = minf(_tick_accum + delta, 0.25)
		var steps := 0
		while _tick_accum >= LOGIC_STEP and steps < 12:
			field.tick(LOGIC_STEP)
			_tick_accum -= LOGIC_STEP
			steps += 1
			if str(engine.state.get("phase", "")) == "result":
				break
	else:
		_tick_accum = 0.0
	if str(engine.state.get("phase", "")) in ["ready", "playing"]:
		_save_clock += delta
		if _save_clock >= 2.0:
			_save_clock = 0.0
			_save("水果切切乐自动保存")


func _blocked() -> bool:
	return not _modal_stack.is_empty()


func _on_field_action() -> void:
	Speech.stop_owner("fruit-slice-ready")
	if str(engine.state.get("phase", "")) in ["ready", "playing"]:
		_save("水果切切乐操作保存")
	if str(engine.state.get("phase", "")) == "result":
		_show_result()


func _announce_ready() -> void:
	if not is_inside_tree() or paused or not _modal_stack.is_empty():
		return
	if str(engine.state.get("phase", "")) != "ready":
		return
	Speech.speak("水果切切乐。轻点开始，用手指划过水果。", "fruit-slice-ready")


func _show_result() -> void:
	if _finished or str(engine.state.get("phase", "")) != "result":
		return
	_finished = true
	var primary: Dictionary = players[0] if not players.is_empty() else {}
	var primary_id := str(primary.get("id", ""))
	var score := int(engine.state.get("score", 0))
	var previous_best := _best_score_for(primary_id)
	if not primary.is_empty() and not bool(engine.state.get("reported", false)):
		engine.state.reported = true
		SaveStore.record_outcome(
			primary_id,
			game_id,
			"played",
			score,
			int(engine.state.sliced),
			int(engine.state.spawned),
			{},
			str(engine.state.get("sessionId", "fruit-slice"))
		)
		_save("水果切切乐本局完成", false)
	var best := maxi(previous_best, score)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	content.add_child(PlaygroundUI.label("得分 %s" % score, 42, accent, 700))
	content.add_child(PlaygroundUI.label(
		"切开 %s 个水果 · 最高连击 x%s" % [int(engine.state.sliced), int(engine.state.maxCombo)],
		22,
		PlaygroundUI.INK,
		600,
		true
	))
	if str(engine.state.get("modeId", "")) == "challenge":
		var record_text := ("新纪录！最高纪录 %s 分" % best) if score > previous_best else ("最高纪录 %s 分" % best)
		content.add_child(PlaygroundUI.label(record_text, 19, accent, 700, true))
	if int(engine.state.get("bombs", 0)) > 0:
		content.add_child(PlaygroundUI.label(
			"遇到 %s 颗炸弹，切到只扣 5 分，不会马上结束，下次躲开它。" % int(engine.state.bombs),
			17,
			PlaygroundUI.INK_SOFT,
			500,
			true
		))
	var title := "挑战时间到" if str(engine.state.get("modeId", "")) == "challenge" else "果园练习完成"
	open_modal(title, content, [
		{"text": "再切一局", "icon": "restart", "kind": "soft", "callback": func(): Speech.stop_owner("fruit-slice-result"); _close_top_modal(); restart_requested.emit()},
		{"text": "回游戏大厅", "icon": "home", "kind": "primary", "callback": func(): Speech.stop_owner("fruit-slice-result"); _close_top_modal(); back_requested.emit()},
	], "本局已自动保存", false)
	var spoken := "本局得分 %s。切开 %s 个水果，最高连击 %s。" % [
		score, int(engine.state.sliced), int(engine.state.maxCombo)
	]
	Speech.speak(spoken, "fruit-slice-result")
	AudioFX.play("win")
	FeedbackKit.haptic(14)


func begin_lesson(force: bool = false) -> void:
	if players.is_empty() or not force:
		return
	if not paused:
		_open_pause_tools()
	lesson_actions = ["slice", "star", "pause"]
	lesson_texts = [
		"水果飞起来时，用手指快速划过它。轻轻点一下，也能切到最近的一颗水果。",
		"连续切中水果会亮起连击环。金色水果会拖出金色光轨，分数更多。",
		"挑战里遇到炸弹要绕开。切到炸弹只扣 5 分并打断连击，不会马上结束。",
	]
	_lesson_icons = ["play", "star", "pause"]
	_show_lesson_page(0)


func _save(note: String, resume: bool = true) -> void:
	if engine.state.is_empty():
		return
	var primary: Dictionary = players[0] if not players.is_empty() else {}
	var primary_id := str(primary.get("id", ""))
	if primary_id.is_empty():
		primary_id = SaveStore.primary_id(game_id)
	if primary_id.is_empty():
		return
	SaveStore.save_state(
		game_id,
		primary_id,
		engine.snapshot(),
		note,
		resume and str(engine.state.get("phase", "")) in ["ready", "playing"]
	)


func _best_score_for_primary() -> int:
	var primary: Dictionary = players[0] if not players.is_empty() else {}
	return _best_score_for(str(primary.get("id", "")))


func _best_score_for(profile_id: String) -> int:
	if profile_id.is_empty():
		return 0
	var record: Dictionary = SaveStore.records_for(profile_id)
	var games_value: Variant = record.get("games", {})
	var game_value: Variant = games_value.get(game_id, {}) if games_value is Dictionary else {}
	return maxi(0, int(game_value.get("bestScore", 0))) if game_value is Dictionary else 0
