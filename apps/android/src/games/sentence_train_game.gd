class_name NativeSentenceTrainGame
extends NativeGameScreen

const FALLBACK_ID := "sentence_train"
const FALLBACK_TITLE := "句子小火车"
const FALLBACK_ACCENT := "#a35a2d"
const FALLBACK_SOFT := "#f4e4d8"
const BAND_NAMES := {
	"easy": "4–6 岁",
	"normal": "7–9 岁",
	"challenge": "10–12 岁",
}
const SPEECH_CARDS := "sentence-train-cards"
const SPEECH_PROMPT := "sentence-train-prompt"
const SPEECH_FEEDBACK := "sentence-train-feedback"
const SPEECH_RESULT := "sentence-train-result"

var engine := SentenceRules.new()
var board: SentenceTrainBoard
var game_header: Control
var title_label: Label
var progress_label: Label
var score_label: Label
var turn_label: Label
var status_label: Label
var action_bar: HFlowContainer
var speech_cards_button: Button
var prompt_button: Button
var submit_button: Button
var speech_sentence_button: Button
var next_button: Button
var soft_accent := Color("#f4e4d8")
var _view := "map"
var _result_visible := false
var _stations_cache: Array = []
var _data_loaded := false


func _ready() -> void:
	if game_id.is_empty():
		game_id = FALLBACK_ID
	if str(game_meta.get("title", "")).strip_edges().is_empty():
		game_meta.title = FALLBACK_TITLE
	if str(game_meta.get("accent", "")).strip_edges().is_empty():
		game_meta.accent = FALLBACK_ACCENT
		accent = PlaygroundUI.color(FALLBACK_ACCENT)
	if str(game_meta.get("soft", "")).strip_edges().is_empty():
		game_meta.soft = FALLBACK_SOFT
	if mode_id not in ["adventure", "classic"]:
		mode_id = "adventure" if players.size() <= 1 else "classic"
	elif mode_id == "adventure" and players.size() != 1:
		mode_id = "classic"
	elif mode_id == "classic" and players.size() != 2:
		mode_id = "adventure"
	SaveStore.set_context(game_id, mode_id, players.map(func(player): return str(player.id)))
	build_shell()
	soft_accent = PlaygroundUI.color(str(game_meta.get("soft", FALLBACK_SOFT)))
	_load_content()
	var stored := SaveStore.load_state(game_id, players.map(func(player): return str(player.id)))
	var had_stored := not stored.is_empty()
	if had_stored:
		stored.modeId = mode_id
	if engine.restore(stored):
		players = engine.state.players.duplicate(true)
		level_id = int(engine.state.get("levelId", 1))
		_view = str(engine.state.get("view", "play"))
		var saved_station := _station_by_id(str(engine.state.get("stationId", "")))
		if saved_station.is_empty() or _station_number(str(engine.state.get("stationId", ""))) != level_id:
			engine.state = {}
			_recover_after_bad_save(stored)
			return
		if str(engine.state.get("phase", "")) == "station_result":
			if bool(engine.state.get("reported", false)) and not bool(stored.get("resume", true)):
				_show_map()
			else:
				_build_play()
				_refresh()
			return
		if _view == "map":
			_show_map()
			return
		_build_play()
		_refresh()
		return
	_recover_after_bad_save(stored)


func _load_content() -> void:
	if _data_loaded:
		return
	_data_loaded = true
	var data_value: Variant = {}
	if ContentDB.has_method("_json_dictionary"):
		data_value = ContentDB.call("_json_dictionary", "sentence_train.json")
	var data: Dictionary = data_value if data_value is Dictionary else {}
	if data.is_empty():
		var path := "res://content/sentence_train.json"
		if FileAccess.file_exists(path):
			var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
			if parsed is Dictionary:
				data = parsed
	if data.is_empty() or int(data.get("version", 0)) != 1:
		return
	var stations: Variant = data.get("stations", [])
	if not stations is Array:
		return
	for entry in stations:
		if not entry is Dictionary:
			continue
		var station_entry: Dictionary = entry
		if engine.validate_station(station_entry):
			_stations_cache.append(station_entry.duplicate(true))
	if _stations_cache.size() != 24:
		_stations_cache.clear()


func _stations() -> Array:
	return _stations_cache


func _station(number: int) -> Dictionary:
	var stations := _stations()
	if number < 1 or number > stations.size():
		return {}
	return stations[number - 1]


func _station_by_id(station_id: String) -> Dictionary:
	for entry in _stations():
		if entry is Dictionary and str(entry.get("id", "")) == station_id:
			return entry
	return {}


func _station_number(station_id: String) -> int:
	var stations := _stations()
	for index in stations.size():
		if str(stations[index].get("id", "")) == station_id:
			return index + 1
	return 0


func _recover_after_bad_save(stored: Dictionary) -> void:
	engine.state = {}
	var recovery_level := int(stored.get("levelId", 0)) if not stored.is_empty() else 0
	if recovery_level >= 1 and recovery_level <= _stations().size():
		level_id = recovery_level
		if _start_station(recovery_level):
			if not stored.is_empty():
				show_toast("上次的句子存档不完整，已从第 %s 站开头重新开始。" % recovery_level, 3.2)
			return
	var message := ""
	if not stored.is_empty():
		message = "上次的句子存档不完整，回到车站地图重新选择吧。"
	_show_map()
	if not message.is_empty():
		show_toast(message, 3.2)


func _show_map() -> void:
	Speech.stop_owner(SPEECH_CARDS)
	Speech.stop_owner(SPEECH_PROMPT)
	Speech.stop_owner(SPEECH_FEEDBACK)
	Speech.stop_owner(SPEECH_RESULT)
	_view = "map"
	_result_visible = false
	PlaygroundUI.clear(content_root)
	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation", 12)
	var title_box := VBoxContainer.new()
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_box.add_theme_constant_override("separation", 2)
	title_box.add_child(PlaygroundUI.label("今天坐火车去哪里？", 30, accent, 700, true))
	var copy := "每一站有五句话。点词卡接车厢，把句子排通顺。"
	if mode_id == "classic":
		copy = "两位小朋友轮流接车厢，一起把每一句话排通顺，不分输赢。"
		if players.size() == 2:
			copy = "%s 和 %s 轮流接车厢，一起把每一句话排通顺，不分输赢。" % [
				str(players[0].get("name", "小朋友")),
				str(players[1].get("name", "小伙伴")),
			]
	title_box.add_child(PlaygroundUI.label(copy, 18, PlaygroundUI.INK_SOFT, 500, true))
	heading.add_child(title_box)
	heading.add_child(PlaygroundUI.semantic_icon_button("rules", "怎么玩", accent, show_help, "soft"))
	content_root.add_child(heading)
	if _stations().is_empty():
		var empty := PlaygroundUI.panel(PlaygroundUI.mix(soft_accent, Color.WHITE, 0.35), 22, PlaygroundUI.TOOL_LINE, 2)
		empty.add_child(PlaygroundUI.label("句子小火车的车站还没有准备好，请稍后再来看看。", 20, PlaygroundUI.INK_SOFT, 600, true))
		content_root.add_child(empty)
		if not engine.state.is_empty():
			_save("正在选择句子车站")
		return
	var scroll := SmoothScrollContainer.create()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	var grid := GridContainer.new()
	var viewport_width := get_viewport_rect().size.x
	grid.columns = 3 if viewport_width <= 1180.0 else 4 if viewport_width < 1500.0 else 6
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	for index in _stations().size():
		var number := index + 1
		var station: Dictionary = _stations()[index]
		var unlocked := _unlocked(number)
		var active := _can_resume_station(number)
		var stars := _stars_for(number)
		var state_text := "先完成上一站"
		if active:
			state_text = "继续 · 第 %s / 5 句" % (int(engine.state.get("sentenceIndex", 0)) + 1)
		elif unlocked and stars > 0:
			state_text = "已获 %s / 3 星" % stars
		elif unlocked:
			state_text = "双人协作" if mode_id == "classic" else "可以出发"
		var button := PlaygroundUI.semantic_icon_button(
			"play" if unlocked or active else "lock",
			"第 %s 站\n%s\n%s · %s" % [
				number,
				str(station.get("title", "句子车站")),
				_band_age_text(str(station.get("band", ""))),
				state_text,
			],
			accent,
			_choose_station.bind(number),
			"soft",
			17
		)
		button.custom_minimum_size = Vector2(0, 138)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.disabled = not unlocked and not active
		grid.add_child(button)
	scroll.add_child(grid)
	content_root.add_child(scroll)
	if not engine.state.is_empty():
		_save("正在选择句子车站")


func _band_age_text(band: String) -> String:
	return str(BAND_NAMES.get(band, "适龄"))


func _unlocked(number: int) -> bool:
	if mode_id == "classic":
		return true
	var primary := SaveStore.primary_id(game_id)
	return not primary.is_empty() and SaveStore.level_unlocked(primary, game_id, number, mode_id)


func _stars_for(number: int) -> int:
	var stars := 0
	for player in players:
		stars = maxi(stars, int(SaveStore.learning(str(player.id), game_id, mode_id).stars.get(str(number), 0)))
	return clampi(stars, 0, 3)


func _can_resume_station(number: int) -> bool:
	if engine.state.is_empty() or _stations().is_empty():
		return false
	if str(engine.state.get("phase", "")) not in ["playing", "feedback"]:
		return false
	if int(engine.state.get("levelId", 0)) != number:
		return false
	var station := _station(number)
	return not station.is_empty() and str(engine.state.get("stationId", "")) == str(station.get("id", ""))


func _choose_station(number: int) -> void:
	if not _unlocked(number) and not _can_resume_station(number):
		show_toast("先完成上一站，再来挑战这一站。")
		return
	Speech.stop_owner(SPEECH_CARDS)
	Speech.stop_owner(SPEECH_PROMPT)
	Speech.stop_owner(SPEECH_FEEDBACK)
	if _can_resume_station(number):
		level_id = number
		_view = "play"
		_result_visible = false
		_build_play()
		_refresh()
		_save("继续句子小火车")
		return
	if str(engine.state.get("phase", "")) in ["playing", "feedback"]:
		guard_level_switch(number, func(): _start_station(number))
		return
	_start_station(number)


func _start_station(number: int, note: String = "") -> bool:
	Speech.stop_owner(SPEECH_CARDS)
	Speech.stop_owner(SPEECH_PROMPT)
	Speech.stop_owner(SPEECH_FEEDBACK)
	Speech.stop_owner(SPEECH_RESULT)
	var station := _station(number)
	if station.is_empty():
		show_toast("这一站还没有准备好。")
		return false
	level_id = number
	_view = "play"
	_result_visible = false
	engine.create_session({
		"gameId": game_id,
		"modeId": mode_id,
		"players": players.duplicate(true),
		"levelId": number,
		"station": station,
		"seed": Time.get_ticks_usec(),
	})
	if str(engine.state.get("phase", "")) != "playing":
		engine.state = {}
		show_toast("这一站的句子还不完整，请换一站再来。")
		return false
	_build_play()
	_refresh()
	_save(note if not note.is_empty() else "第 %s 站出发" % number)
	return true


func _build_play() -> void:
	_view = "play"
	PlaygroundUI.clear(content_root)
	game_header = HBoxContainer.new()
	game_header.add_theme_constant_override("separation", 10)
	game_header.add_child(PlaygroundUI.semantic_icon_button("back", "车站", accent, _show_map, "soft"))
	var heading := VBoxContainer.new()
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_theme_constant_override("separation", 0)
	title_label = PlaygroundUI.label(str(engine.state.get("stationTitle", "句子小火车")), 23, accent, 700, true)
	heading.add_child(title_label)
	var station := _station(level_id)
	heading.add_child(PlaygroundUI.label("第 %s 站 · %s" % [level_id, _band_age_text(str(station.get("band", "")))], 15, PlaygroundUI.INK_SOFT, 500))
	game_header.add_child(heading)
	progress_label = PlaygroundUI.label("", 16, accent, 700)
	var progress_panel := PlaygroundUI.panel(PlaygroundUI.mix(soft_accent, Color.WHITE, 0.25), 999, PlaygroundUI.mix(accent, Color.WHITE, 0.5), 1)
	progress_panel.custom_minimum_size = Vector2(128, 42)
	progress_panel.add_child(progress_label)
	progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	game_header.add_child(progress_panel)
	score_label = PlaygroundUI.label("", 16, accent, 700)
	var score_panel := PlaygroundUI.panel(PlaygroundUI.mix(accent, Color.WHITE, 0.84), 999, PlaygroundUI.mix(accent, Color.WHITE, 0.42), 1)
	score_panel.custom_minimum_size = Vector2(128, 42)
	score_panel.add_child(score_label)
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	game_header.add_child(score_panel)
	turn_label = PlaygroundUI.label("", 15, PlaygroundUI.INK_SOFT, 600, true)
	turn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	turn_label.custom_minimum_size.x = 190
	game_header.add_child(turn_label)
	content_root.add_child(game_header)
	board = SentenceTrainBoard.new()
	board.accent = accent
	board.soft = soft_accent
	board.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	board.size_flags_vertical = Control.SIZE_EXPAND_FILL
	board.chunk_pressed.connect(_on_chunk_pressed)
	board.carriage_pressed.connect(_on_carriage_pressed)
	content_root.add_child(board)
	status_label = PlaygroundUI.label("", 17, PlaygroundUI.INK_SOFT, 600, true)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content_root.add_child(status_label)
	action_bar = HFlowContainer.new()
	action_bar.alignment = FlowContainer.ALIGNMENT_CENTER
	action_bar.add_theme_constant_override("h_separation", 10)
	action_bar.add_theme_constant_override("v_separation", 8)
	speech_cards_button = PlaygroundUI.semantic_icon_button("listen", "听词卡", accent, _read_cards, "soft", 18)
	prompt_button = PlaygroundUI.semantic_icon_button("speech", "听提示", accent, _read_prompt, "ghost", 18)
	submit_button = PlaygroundUI.semantic_icon_button("check", "完成句子", accent, _submit_sentence, "primary", 20)
	speech_sentence_button = PlaygroundUI.semantic_icon_button("speech", "朗读完整句", accent, _read_feedback, "soft", 18)
	next_button = PlaygroundUI.semantic_icon_button("next", "下一句", accent, _advance_sentence, "primary", 20)
	action_bar.add_child(speech_cards_button)
	action_bar.add_child(prompt_button)
	action_bar.add_child(submit_button)
	action_bar.add_child(speech_sentence_button)
	action_bar.add_child(next_button)
	content_root.add_child(action_bar)
	board.set_state(engine.state)
	_on_immersive_changed(immersive)


func _on_immersive_changed(_value: bool) -> void:
	if game_header != null and is_instance_valid(game_header):
		game_header.show()
	if status_label != null and is_instance_valid(status_label):
		status_label.show()
	if action_bar != null and is_instance_valid(action_bar):
		action_bar.show()


func _refresh() -> void:
	if engine.state.is_empty():
		return
	var phase := str(engine.state.get("phase", ""))
	if phase == "station_result":
		_finish_station()
		return
	board.set_state(engine.state)
	progress_label.text = "第 %s / 5 句" % (int(engine.state.get("sentenceIndex", 0)) + 1)
	var correct := int(engine.state.get("correctCount", 0))
	score_label.text = "排对 %s 句" % correct
	turn_label.text = _turn_copy()
	if mode_id == "classic" and players.size() == 2:
		var turn_index := clampi(int(engine.state.get("turn", 0)), 0, 1)
		turn_label.add_theme_color_override("font_color", PlaygroundUI.color(str(players[turn_index].get("color", "#a35a2d")), accent))
	else:
		turn_label.add_theme_color_override("font_color", PlaygroundUI.INK_SOFT)
	_update_actions(phase)
	if phase == "playing":
		if mode_id == "classic" and _current_player_name() != "":
			status_label.text = "轮到 %s 选一张词卡，接到下一节车厢。" % _current_player_name()
		else:
			status_label.text = "点词卡接到下一节车厢；点已放车厢可以取回。"
	else:
		status_label.text = "完整句子和解释会留在这里，点“%s”才继续。" % ("查看成绩" if _is_last_sentence() else "下一句")


func _current_player_name() -> String:
	if mode_id != "classic" or players.size() != 2:
		return ""
	var index := clampi(int(engine.state.get("turn", 0)), 0, players.size() - 1)
	return str(players[index].get("name", "小朋友"))


func _turn_copy() -> String:
	if mode_id != "classic":
		return "单人闯关"
	if str(engine.state.get("phase", "")) == "feedback":
		return "两个人一起看讲解"
	return "轮到 %s 接车厢" % _current_player_name()


func _update_actions(phase: String) -> void:
	var playing := phase == "playing"
	var feedback := phase == "feedback"
	speech_cards_button.visible = playing
	prompt_button.visible = playing
	submit_button.visible = playing
	speech_sentence_button.visible = feedback
	next_button.visible = feedback
	if playing:
		var chunks: Array = engine.state.get("sentence", {}).get("chunks", [])
		var placed: Array = engine.state.get("placedIds", [])
		var tray: Array = engine.state.get("trayIds", [])
		submit_button.disabled = placed.size() != chunks.size()
		speech_cards_button.disabled = tray.is_empty()
	elif feedback and mode_id == "classic":
		turn_label.add_theme_color_override("font_color", accent)
	if feedback:
		next_button.text = "查看成绩" if _is_last_sentence() else "下一句"


func _is_last_sentence() -> bool:
	return int(engine.state.get("sentenceIndex", 0)) >= int(engine.state.get("sentenceCount", 5)) - 1


func _on_chunk_pressed(chunk_id: String) -> void:
	if is_input_blocked() or str(engine.state.get("phase", "")) != "playing":
		return
	var result := engine.handle_input({"type": "place_chunk", "chunkId": chunk_id})
	if not bool(result.get("ok", false)):
		show_toast(str(result.get("message", "这张词卡现在放不上去。")))
		return
	Speech.stop_owner(SPEECH_CARDS)
	Speech.stop_owner(SPEECH_PROMPT)
	SfxMap.play(&"drop")
	FeedbackKit.haptic(7)
	_save("接上一节词卡车厢")
	_refresh()
	if bool(result.get("complete", false)):
		AudioFX.play("confirm")
		show_toast("词卡都接上车啦，检查顺序后点“完成句子”。", 2.4)


func _on_carriage_pressed(chunk_id: String) -> void:
	if is_input_blocked() or str(engine.state.get("phase", "")) != "playing":
		return
	var result := engine.handle_input({"type": "remove_chunk", "chunkId": chunk_id})
	if not bool(result.get("ok", false)):
		show_toast(str(result.get("message", "这节车厢现在取不下来。")))
		return
	SfxMap.play(&"back")
	FeedbackKit.haptic(5)
	_save("取回一张词卡")
	_refresh()


func _submit_sentence() -> void:
	if is_input_blocked() or str(engine.state.get("phase", "")) != "playing":
		return
	var result := engine.handle_input({"type": "submit"})
	if not bool(result.get("ok", false)):
		show_toast(str(result.get("message", "先把词卡都接好。")))
		return
	Speech.stop_owner(SPEECH_CARDS)
	Speech.stop_owner(SPEECH_PROMPT)
	if bool(result.get("correct", false)):
		SfxMap.play(&"success")
		FeedbackKit.haptic(12)
	else:
		SfxMap.play(&"error")
		FeedbackKit.haptic(14)
	_save("完成句子判定")
	_refresh()


func _advance_sentence() -> void:
	if is_input_blocked() or str(engine.state.get("phase", "")) != "feedback":
		return
	var result := engine.handle_input({"type": "next"})
	if not bool(result.get("ok", false)):
		show_toast(str(result.get("message", "先看完这一句。")))
		return
	Speech.stop_owner(SPEECH_FEEDBACK)
	if bool(result.get("finished", false)):
		_finish_station()
		return
	SfxMap.play(&"confirm")
	_save("准备下一句")
	_refresh()


func _read_cards() -> void:
	if engine.state.is_empty() or is_input_blocked():
		return
	var tray: Array = engine.state.get("trayIds", [])
	if tray.is_empty():
		show_toast("词卡都接上车了，检查顺序后点“完成句子”。")
		return
	var lookup := _chunk_lookup()
	var texts := PackedStringArray()
	for chunk_id in tray:
		var text := str(lookup.get(str(chunk_id), "")).strip_edges()
		if not text.is_empty():
			texts.append(text)
	if texts.is_empty():
		return
	SfxMap.play(&"select")
	Speech.speak("词卡有：%s。请挑一张接到下一节车厢。" % "；".join(texts), SPEECH_CARDS)


func _read_prompt() -> void:
	if engine.state.is_empty() or is_input_blocked():
		return
	var text := str(engine.state.get("sentence", {}).get("narration", ""))
	if text.is_empty():
		text = str(engine.state.get("sentence", {}).get("prompt", ""))
	SfxMap.play(&"select")
	Speech.speak(text, SPEECH_PROMPT)


func _read_feedback() -> void:
	if engine.state.is_empty() or is_input_blocked():
		return
	var judgement_value: Variant = engine.state.get("judgement", {})
	var judgement: Dictionary = judgement_value if judgement_value is Dictionary else {}
	var sentence := str(judgement.get("fullSentence", engine.full_sentence()))
	var explanation := str(judgement.get("explanation", engine.explanation()))
	SfxMap.play(&"select")
	Speech.speak("%s。解释：%s" % [sentence, explanation], SPEECH_FEEDBACK)


func _chunk_lookup() -> Dictionary:
	var result := {}
	for chunk in engine.current_chunks():
		if chunk is Dictionary:
			result[str(chunk.get("id", ""))] = str(chunk.get("text", ""))
	return result


func _finish_station() -> void:
	if engine.state.is_empty():
		return
	if not bool(engine.state.get("reported", false)):
		engine.state.reported = true
		var stars := engine.stars()
		engine.state.stars = stars
		var correct := int(engine.state.get("correctCount", 0))
		var answered := int(engine.state.get("sentenceCount", 5))
		var skills := {"language": {"correct": correct, "answered": answered}}
		var recipients: Array = players if mode_id == "classic" else [players[0]]
		for player in recipients:
			var player_id := str(player.get("id", ""))
			if player_id.is_empty():
				continue
			var outcome := "played"
			if mode_id == "adventure" and stars > 0:
				outcome = "win"
			SaveStore.complete_level(player_id, game_id, level_id, stars, mode_id)
			SaveStore.record_outcome(
				player_id,
				game_id,
				outcome,
				correct,
				correct,
				answered,
				skills,
				str(engine.state.get("sessionId", "sentence-train"))
			)
		_save("第 %s 站完成" % level_id, false)
	_show_result()


func _show_result() -> void:
	if _result_visible:
		return
	_result_visible = true
	board.stop_interaction()
	action_bar.hide()
	var stars := int(engine.state.get("stars", engine.stars()))
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	var trophy := ArtLibrary.semantic_picture("trophy", "ui", Vector2(84, 84))
	trophy.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	body.add_child(trophy)
	body.add_child(PlaygroundUI.label("第 %s 站到站啦！" % level_id, 26, accent, 700, true))
	var summary := "五句都看完了 · 排对 %s 句" % int(engine.state.get("correctCount", 0))
	if mode_id == "classic":
		summary = "两个人一起完成五句 · 排对 %s 句" % int(engine.state.get("correctCount", 0))
	body.add_child(PlaygroundUI.label(summary, 19, PlaygroundUI.INK_SOFT, 500, true))
	var stars_row := HBoxContainer.new()
	stars_row.alignment = BoxContainer.ALIGNMENT_CENTER
	stars_row.add_theme_constant_override("separation", 8)
	for index in 3:
		var star := ArtLibrary.semantic_picture("star", "ui", Vector2(38, 38))
		star.modulate = Color.WHITE if index < stars else Color(1, 1, 1, 0.24)
		stars_row.add_child(star)
	body.add_child(stars_row)
	var actions: Array = [
		{"text": "车站地图", "icon": "back", "kind": "soft", "callback": func(): _close_top_modal(); _result_visible = false; _show_map()},
	]
	var next_unlocked := level_id < _stations().size() and (mode_id == "classic" or _unlocked(level_id + 1))
	if next_unlocked:
		actions.append({"text": "再坐一次", "icon": "repeat", "kind": "soft", "callback": func(): _close_top_modal(); _result_visible = false; _start_station(level_id)})
		actions.append({"text": "下一站", "icon": "next", "kind": "primary", "callback": _next_station})
	elif level_id >= _stations().size():
		actions.append({"text": "再坐一次", "icon": "repeat", "kind": "soft", "callback": func(): _close_top_modal(); _result_visible = false; _start_station(level_id)})
		actions.append({"text": "回游戏大厅", "icon": "home", "kind": "primary", "callback": func(): _close_top_modal(); back_requested.emit()})
	else:
		actions.append({"text": "再坐一次", "icon": "repeat", "kind": "primary", "callback": func(): _close_top_modal(); _result_visible = false; _start_station(level_id)})
	var save_note := "本局已自动保存" if SaveStore.last_save_ok else "存档暂时没写完，继续操作时会自动重试"
	open_modal("句子火车到站", body, actions, save_note, false)
	if stars > 0:
		SfxMap.play(&"win")
		FeedbackKit.haptic(14)
	else:
		SfxMap.play(&"confirm")
	Speech.speak("第 %s 站到站啦。排对了 %s 句。" % [level_id, int(engine.state.get("correctCount", 0))], SPEECH_RESULT)


func _next_station() -> void:
	_close_top_modal()
	_result_visible = false
	var next := level_id + 1
	if next <= _stations().size() and (mode_id == "classic" or _unlocked(next)):
		_start_station(next)
	else:
		_show_map()


func _confirm_restart() -> void:
	if _view == "map":
		_close_pause_tools()
		show_toast("先选一个车站，再开始这一局。")
		return
	var text := PlaygroundUI.label("第 %s 站的五句会从第一句重新开始，已获得的星星和其他车站会保留。" % level_id, 19, PlaygroundUI.INK_SOFT, 500, true)
	open_modal("重坐这一站？", text, [
		{"text": "继续这一站", "icon": "back", "kind": "soft", "callback": func(): _close_top_modal()},
		{"text": "重新开始", "icon": "restart", "kind": "primary", "callback": _restart_station},
	], "句子小火车")


func _restart_station() -> void:
	_close_top_modal()
	_result_visible = false
	if _start_station(level_id):
		show_toast("第 %s 站重新出发。" % level_id, 1.8)


func _extra_pause_actions() -> Array:
	if _view == "map":
		return []
	return [{"text": "车站地图", "icon": "back", "kind": "soft", "callback": func(): _close_pause_tools(); _show_map()}]


func show_help() -> void:
	if not paused:
		_open_pause_tools()
	var lines := [
		"先看情境小票，再从词卡托盘挑一张词卡。",
		"词卡会接到下一节车厢；点已经放好的车厢，就能把词卡取回来。",
		"全部接好后点“完成句子”，只判定一次。",
		"完整句子、标点和解释会留在这里，读完再点“下一句”或“查看成绩”。",
		"双人协作时两位小朋友轮流接车厢，一起完成，不分输赢。",
	]
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	var icons := ["play", "next", "check", "listen", "repeat"]
	for index in lines.size():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		row.add_child(ArtLibrary.semantic_picture(str(icons[mini(index, icons.size() - 1)]), "ui", Vector2(38, 38)))
		var text := PlaygroundUI.label(str(lines[index]), 19, PlaygroundUI.INK, 600, true)
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(text)
		content.add_child(row)
	Speech.speak("%s玩法。%s" % [str(game_meta.get("title", "句子小火车")), " ".join(PackedStringArray(lines))], "game-help")
	var extra := HBoxContainer.new()
	extra.add_theme_constant_override("separation", 10)
	extra.add_child(PlaygroundUI.semantic_icon_button("play", "三步小课堂", accent, func(): _close_top_modal(); begin_lesson(true), "soft"))
	extra.add_child(PlaygroundUI.semantic_icon_button("rules", "更多规则", accent, func(): _close_top_modal(); _show_rules(), "soft"))
	content.add_child(PlaygroundUI.separator(PlaygroundUI.TOOL_LINE))
	content.add_child(extra)
	open_modal("怎么玩", content, [
		{"text": "再读一遍", "icon": "repeat", "kind": "soft", "callback": func(): Speech.repeat()},
		{"text": "知道了", "icon": "check", "kind": "primary", "callback": func(): _close_top_modal()},
	], "句子小火车指南")


func _show_rules() -> void:
	var lines := [
		"词卡必须一张一张接到紧挨着的下一节车厢。",
		"点已经放好的词卡车厢可以取回词卡，再重新选择位置。",
		"只有全部词卡都上车后，才能点“完成句子”。",
		"判定后会保留正确句子、标点和解释，不会自动换句。",
		"同一句话若有多种通顺顺序，内容里会明确保存为可接受答案。",
	]
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	for index in lines.size():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.add_child(PlaygroundUI.chip(str(index + 1), accent))
		var text := PlaygroundUI.label(str(lines[index]), 19, PlaygroundUI.INK_SOFT, 500, true)
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(text)
		body.add_child(row)
	open_modal("句子火车小规则", body, [
		{"text": "读给我听", "icon": "speech", "kind": "soft", "callback": func(): Speech.speak(" ".join(PackedStringArray(lines)), "game-help")},
		{"text": "知道了", "icon": "check", "kind": "primary", "callback": func(): _close_top_modal()},
	], "排一句，开一程")


func begin_lesson(force: bool = false) -> void:
	if not force:
		return
	if not paused:
		_open_pause_tools()
	lesson_texts = [
		"先听情境或自己读小票，再从词卡托盘挑一张词卡。",
		"词卡接到下一节车厢；点已放车厢可以取回，双人协作会轮流放。",
		"全部接好后点“完成句子”。读完留下的讲解，再点“下一句”或“查看成绩”。",
	]
	_lesson_icons = ["listen", "next", "check"]
	_show_lesson_page(0)


func _save(note: String, resume: bool = true) -> void:
	if engine.state.is_empty() or players.is_empty():
		return
	engine.state.view = _view
	var phase := str(engine.state.get("phase", ""))
	var can_resume := resume and (_view in ["map", "play"]) and (phase in ["playing", "feedback"])
	SaveStore.save_state(game_id, str(players[0].id), engine.snapshot(), note, can_resume)
	if not SaveStore.last_save_ok:
		show_toast("刚才没记住，我再试一次。", 2.8)
