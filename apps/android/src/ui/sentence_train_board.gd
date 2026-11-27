class_name SentenceTrainBoard
extends Control

signal chunk_pressed(chunk_id: String)
signal carriage_pressed(chunk_id: String)

const WOOD_DARK := Color("#70401f")
const WOOD_MID := Color("#9c6135")
const TRACK_INK := Color("#7a6653")
const BRASS := Color("#dbb05a")
const SUCCESS := Color("#557e47")
const RETRY := Color("#a76631")
const CARD_INK := Color("#342419")
const CLOSING_PUNCTUATION := "，。！？；：、）》」』”’…"

var state: Dictionary = {}
var accent := Color("#a35a2d")
var soft := Color("#f4e4d8")
var interactive := true

var _clock := 0.0
var _redraw_accumulator := 0.0
var _last_touch_msec := -1000
var _touch_index := -1
var _pressed_kind := ""
var _pressed_id := ""

var _prompt_rect := Rect2()
var _train_rect := Rect2()
var _tray_rect := Rect2()
var _feedback_rect := Rect2()
var _locomotive_rect := Rect2()
var _slot_rects: Array[Rect2] = []
var _slot_ids: Array[String] = []
var _tray_rects: Array[Rect2] = []
var _tray_ids: Array[String] = []


func _ready() -> void:
	custom_minimum_size = Vector2(760, 560)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	clip_contents = true
	resized.connect(_layout)
	set_process(true)
	_layout()


func configure(value: Dictionary) -> void:
	set_state(value)


func set_state(value: Dictionary) -> void:
	state = value.duplicate(true) if not value.is_empty() else {}
	interactive = str(state.get("phase", "")) == "playing"
	_pressed_kind = ""
	_pressed_id = ""
	_layout()
	queue_redraw()


func stop_interaction() -> void:
	interactive = false
	_pressed_kind = ""
	_pressed_id = ""
	queue_redraw()


func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_CLOSE_REQUEST]:
		_cancel_press()


func _process(delta: float) -> void:
	_clock += delta
	_redraw_accumulator += delta
	if _redraw_accumulator >= 0.08 and str(state.get("phase", "")) == "playing":
		_redraw_accumulator = 0.0
		queue_redraw()


func _layout() -> void:
	_slot_rects.clear()
	_slot_ids.clear()
	_tray_rects.clear()
	_tray_ids.clear()
	var padding := 18.0
	var width := maxf(1.0, size.x - padding * 2.0)
	var available_height := maxf(1.0, size.y - padding * 2.0)
	var prompt_height := clampf(available_height * 0.15, 92.0, 142.0)
	_prompt_rect = Rect2(padding, padding, width, prompt_height)
	var train_top := _prompt_rect.end.y + 12.0
	var feedback_phase := str(state.get("phase", "")) == "feedback"
	var train_height := clampf(available_height * (0.23 if feedback_phase else 0.27), 178.0, 248.0)
	_train_rect = Rect2(padding, train_top, width, train_height)
	var lower_top := _train_rect.end.y + 12.0
	if feedback_phase:
		_tray_rect = Rect2()
		_feedback_rect = Rect2(padding, lower_top, width, maxf(220.0, size.y - padding - lower_top))
	else:
		_feedback_rect = Rect2()
		_tray_rect = Rect2(padding, lower_top, width, maxf(190.0, size.y - padding - lower_top))
	_calculate_train()
	if not feedback_phase:
		_calculate_tray()
	queue_redraw()


func _calculate_train() -> void:
	var placed: Array = state.get("placedIds", [])
	var chunks: Array = state.get("sentence", {}).get("chunks", [])
	var count := maxi(1, chunks.size())
	var left := _train_rect.position.x + 14.0
	var usable := maxf(320.0, _train_rect.size.x - 28.0)
	var gap := clampf(_train_rect.size.x * 0.008, 6.0, 11.0)
	var loco_width := clampf(usable * 0.15, 112.0, 190.0)
	var car_width := (usable - loco_width - gap * float(count)) / float(count)
	car_width = maxf(72.0, car_width)
	var body_top := _train_rect.position.y + 18.0
	var body_height := maxf(102.0, _train_rect.size.y - 56.0)
	_locomotive_rect = Rect2(left, body_top, loco_width, body_height)
	var cursor := _locomotive_rect.end.x + gap
	for index in chunks.size():
		var rect := Rect2(cursor, body_top, car_width, body_height)
		_slot_rects.append(rect)
		_slot_ids.append(str(placed[index]) if index < placed.size() else "")
		cursor += car_width + gap


func _calculate_tray() -> void:
	var ids: Array = state.get("trayIds", [])
	if ids.is_empty():
		return
	var inner := Rect2(
		_tray_rect.position + Vector2(16.0, 48.0),
		_tray_rect.size - Vector2(32.0, 62.0)
	)
	var columns := 5 if inner.size.x >= 1150.0 else 4 if inner.size.x >= 820.0 else 3
	columns = mini(columns, maxi(1, ids.size()))
	var rows := ceili(float(ids.size()) / float(columns))
	var gap := 12.0
	var card_width := (inner.size.x - gap * float(columns - 1)) / float(columns)
	var card_height := minf(142.0, (inner.size.y - gap * float(rows - 1)) / float(rows))
	card_height = maxf(70.0, card_height)
	var top := inner.position.y + maxf(0.0, (inner.size.y - (card_height * rows + gap * (rows - 1))) * 0.5)
	for index in ids.size():
		var column := index % columns
		var row := int(index / columns)
		_tray_rects.append(Rect2(
			Vector2(inner.position.x + float(column) * (card_width + gap), top + float(row) * (card_height + gap)),
			Vector2(card_width, card_height)
		))
		_tray_ids.append(str(ids[index]))


func _gui_input(event: InputEvent) -> void:
	if not interactive or _blocked():
		return
	if event is InputEventScreenTouch:
		if event.device == InputEvent.DEVICE_ID_EMULATION:
			return
		_last_touch_msec = Time.get_ticks_msec()
		if event.pressed:
			if _touch_index < 0:
				_touch_index = event.index
				_press(event.position)
		elif event.index == _touch_index:
			_release(event.position)
		accept_event()
	elif event is InputEventScreenDrag:
		_last_touch_msec = Time.get_ticks_msec()
		if event.index == _touch_index:
			_cancel_press()
		accept_event()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if Time.get_ticks_msec() - _last_touch_msec < 500:
			return
		if event.pressed:
			_press(event.position)
		else:
			_release(event.position)
		accept_event()
	elif event is InputEventMouseMotion and not _pressed_id.is_empty():
		var target := _hit_target(event.position)
		if str(target.get("kind", "")) != _pressed_kind or str(target.get("id", "")) != _pressed_id:
			_cancel_press()


func _press(position: Vector2) -> void:
	var target := _hit_target(position)
	_pressed_kind = str(target.get("kind", ""))
	_pressed_id = str(target.get("id", ""))
	queue_redraw()


func _release(position: Vector2) -> void:
	var target := _hit_target(position)
	var kind := _pressed_kind
	var chunk_id := _pressed_id
	_cancel_press()
	if kind.is_empty() or chunk_id.is_empty():
		return
	if str(target.get("kind", "")) != kind or str(target.get("id", "")) != chunk_id:
		return
	if kind == "tray":
		chunk_pressed.emit(chunk_id)
	elif kind == "car":
		carriage_pressed.emit(chunk_id)


func _cancel_press() -> void:
	_touch_index = -1
	_pressed_kind = ""
	_pressed_id = ""
	queue_redraw()


func _hit_target(position: Vector2) -> Dictionary:
	for index in _slot_rects.size():
		if _slot_rects[index].has_point(position) and index < _slot_ids.size() and not _slot_ids[index].is_empty():
			return {"kind": "car", "id": _slot_ids[index]}
	for index in _tray_rects.size():
		if _tray_rects[index].has_point(position) and index < _tray_ids.size():
			return {"kind": "tray", "id": _tray_ids[index]}
	return {}


func _blocked() -> bool:
	var owner := get_parent()
	while owner != null:
		if owner is NativeGameScreen:
			return owner.is_input_blocked()
		owner = owner.get_parent()
	return false


func _draw() -> void:
	var outer := Rect2(Vector2.ZERO, size)
	draw_style_box(PlaygroundUI.style(
		PlaygroundUI.mix(soft, Color.WHITE, 0.34),
		28,
		PlaygroundUI.mix(accent, Color.WHITE, 0.48),
		2,
		8,
		Color(0.21, 0.12, 0.04, 0.12)
	), outer)
	_draw_paper_speckles(outer)
	_draw_prompt()
	_draw_train()
	if str(state.get("phase", "")) == "feedback":
		_draw_feedback()
	else:
		_draw_tray()


func _draw_paper_speckles(rect: Rect2) -> void:
	for index in 18:
		var x := rect.position.x + 20.0 + fmod(float(index * 137 + 53), maxf(1.0, rect.size.x - 40.0))
		var y := rect.position.y + 18.0 + fmod(float(index * 83 + 41), maxf(1.0, rect.size.y - 36.0))
		draw_circle(Vector2(x, y), 1.2 + float(index % 2), Color(accent, 0.055))


func _draw_prompt() -> void:
	draw_style_box(PlaygroundUI.style(
		Color("#fff9ee"),
		24,
		PlaygroundUI.mix(accent, Color.WHITE, 0.34),
		2,
		5,
		Color(0.24, 0.14, 0.06, 0.09)
	), _prompt_rect)
	var ticket_color := PlaygroundUI.mix(accent, Color.WHITE, 0.7)
	draw_style_box(PlaygroundUI.style(ticket_color, 13), Rect2(
		_prompt_rect.position + Vector2(16, 18),
		Vector2(104, 32)
	))
	var font := PlaygroundUI.font()
	draw_string(font, _prompt_rect.position + Vector2(29, 41), "情境小票", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, WOOD_DARK)
	var station_title := str(state.get("stationTitle", "句子小火车"))
	draw_string(
		font,
		_prompt_rect.position + Vector2(136, 41),
		station_title,
		HORIZONTAL_ALIGNMENT_LEFT,
		_prompt_rect.size.x - 168.0,
		17,
		PlaygroundUI.INK_SOFT
	)
	draw_circle(_prompt_rect.end - Vector2(29, 28), 7.0, Color(soft, 0.9))
	draw_circle(_prompt_rect.end - Vector2(29, 28), 3.0, Color(WOOD_DARK, 0.7))
	var prompt := "把词卡接成一句通顺的话。"
	if not state.is_empty():
		prompt = str(state.get("sentence", {}).get("prompt", prompt))
	var copy_size := 23 if _prompt_rect.size.x > 880.0 else 20
	var lines := _wrap_text(prompt, _prompt_rect.size.x - 66.0, copy_size)
	var line_height := font.get_height(copy_size) + 4.0
	var top := _prompt_rect.position.y + 53.0
	if lines.size() <= 2:
		top += 3.0
	_draw_lines(lines, Vector2(_prompt_rect.position.x + 25.0, top), _prompt_rect.size.x - 50.0, copy_size, CARD_INK, HORIZONTAL_ALIGNMENT_LEFT, 4.0)
	if float(lines.size()) * line_height > _prompt_rect.size.y - 58.0:
		draw_line(
			Vector2(_prompt_rect.position.x + 22.0, _prompt_rect.end.y - 15.0),
			Vector2(_prompt_rect.end.x - 22.0, _prompt_rect.end.y - 15.0),
			Color(accent, 0.18),
			1.0,
			true
		)


func _draw_train() -> void:
	var track_y := _train_rect.end.y - 13.0
	draw_line(
		Vector2(_train_rect.position.x + 10.0, track_y),
		Vector2(_train_rect.end.x - 10.0, track_y),
		TRACK_INK,
		5.0,
		true
	)
	var sleeper_x := _train_rect.position.x + 24.0
	while sleeper_x < _train_rect.end.x - 18.0:
		draw_line(Vector2(sleeper_x, track_y - 5.0), Vector2(sleeper_x, track_y + 7.0), Color(TRACK_INK, 0.52), 3.0, true)
		sleeper_x += 24.0
	for index in _slot_rects.size():
		var rect := _slot_rects[index]
		draw_line(Vector2(rect.position.x - 8.0, rect.position.y + rect.size.y * 0.5), Vector2(rect.position.x, rect.position.y + rect.size.y * 0.5), WOOD_DARK, 5.0, true)
		_draw_carriage(rect, index)
	_draw_locomotive()


func _draw_locomotive() -> void:
	var rect := _locomotive_rect
	var body_y := rect.position.y + 24.0
	var body_h := rect.size.y - 38.0
	var cab_width := rect.size.x * 0.37
	var boiler := Rect2(
		Vector2(rect.position.x + cab_width * 0.72, body_y + 14.0),
		Vector2(rect.size.x - cab_width * 0.72 - 18.0, body_h - 22.0)
	)
	draw_style_box(PlaygroundUI.style(WOOD_MID, 18, WOOD_DARK, 3, 5, Color(0.25, 0.13, 0.05, 0.18)), boiler)
	draw_style_box(PlaygroundUI.style(PlaygroundUI.mix(accent, Color.WHITE, 0.22), 18, WOOD_DARK, 3, 5, Color(0.25, 0.13, 0.05, 0.18)), Rect2(
		Vector2(rect.position.x + cab_width * 0.42, rect.position.y + 3.0),
		Vector2(cab_width, body_h + 20.0)
	))
	draw_rect(Rect2(
		Vector2(rect.position.x + cab_width * 0.62, rect.position.y + 20.0),
		Vector2(cab_width * 0.55, cab_width * 0.46)
	), Color("#e9f1e2"), true)
	draw_rect(Rect2(
		Vector2(rect.position.x + cab_width * 0.62, rect.position.y + 20.0),
		Vector2(cab_width * 0.55, cab_width * 0.46)
	), WOOD_DARK, false, 2.0)
	draw_rect(Rect2(
		Vector2(rect.position.x + cab_width * 0.66, rect.position.y + 24.0),
		Vector2(cab_width * 0.18, cab_width * 0.35)
	), Color("#c7dcc6"), true)
	var chimney := Rect2(
		Vector2(boiler.position.x + boiler.size.x * 0.64, rect.position.y - 3.0),
		Vector2(26.0, 24.0)
	)
	draw_style_box(PlaygroundUI.style(WOOD_DARK, 7), chimney)
	draw_style_box(PlaygroundUI.style(WOOD_DARK, 8), Rect2(chimney.position + Vector2(-5, -2), Vector2(36, 9)))
	for index in 3:
		var drift := sin(_clock * 1.35 + float(index) * 1.3) * 6.0
		var radius := 8.0 + float(index) * 3.5
		draw_circle(
			Vector2(chimney.position.x + 13.0 + drift + float(index) * 7.0, chimney.position.y - 12.0 - float(index) * 17.0),
			radius,
			Color(1, 1, 1, 0.42 - float(index) * 0.08)
		)
	draw_circle(boiler.position + Vector2(boiler.size.x - 20.0, boiler.size.y * 0.46), 10.0, BRASS)
	draw_circle(boiler.position + Vector2(boiler.size.x - 20.0, boiler.size.y * 0.46), 4.0, WOOD_DARK)
	draw_colored_polygon(PackedVector2Array([
		Vector2(boiler.end.x - 4.0, boiler.position.y + boiler.size.y * 0.35),
		Vector2(boiler.end.x + 15.0, boiler.position.y + boiler.size.y * 0.48),
		Vector2(boiler.end.x - 4.0, boiler.position.y + boiler.size.y * 0.67),
	]), PlaygroundUI.mix(accent, Color.WHITE, 0.36))
	for wheel_index in 3:
		var wheel_center := Vector2(rect.position.x + cab_width * 0.36 + float(wheel_index) * rect.size.x * 0.28, rect.end.y - 7.0)
		draw_circle(wheel_center, 17.0, WOOD_DARK)
		draw_circle(wheel_center, 9.0, BRASS)
		draw_circle(wheel_center, 3.0, WOOD_DARK)
	var font := PlaygroundUI.font()
	draw_string(
		font,
		Vector2(boiler.position.x + 9.0, boiler.position.y + boiler.size.y * 0.59),
		"句",
		HORIZONTAL_ALIGNMENT_CENTER,
		boiler.size.x - 18.0,
		28,
		Color.WHITE
	)
	draw_string(
		font,
		Vector2(rect.position.x + 7.0, rect.end.y - 28.0),
		"小火车",
		HORIZONTAL_ALIGNMENT_CENTER,
		cab_width,
		14,
		Color(WOOD_DARK, 0.86)
	)


func _draw_carriage(rect: Rect2, index: int) -> void:
	var chunk_id := _slot_ids[index] if index < _slot_ids.size() else ""
	var filled := not chunk_id.is_empty()
	var is_next := not filled and index == int(state.get("placedIds", []).size())
	var is_pressed := _pressed_kind == "car" and _pressed_id == chunk_id
	var body := rect
	if is_pressed:
		body.position.y += 3.0
	var fill := PlaygroundUI.mix(soft, Color.WHITE, 0.46 if filled else 0.72)
	if filled:
		fill = PlaygroundUI.mix(accent, Color.WHITE, 0.83)
	elif is_next:
		fill = PlaygroundUI.mix(accent, Color.WHITE, 0.88)
	var border_color := PlaygroundUI.mix(WOOD_MID, Color.WHITE, 0.4)
	if filled:
		border_color = WOOD_DARK
	elif is_next:
		border_color = accent
	var border_width := 3 if filled or is_next else 2
	draw_style_box(PlaygroundUI.style(
		fill,
		19,
		border_color,
		border_width,
		5,
		Color(0.22, 0.12, 0.05, 0.14)
	), body)
	for wheel_index in 2:
		var wheel_x := body.position.x + body.size.x * (0.3 + float(wheel_index) * 0.4)
		var wheel_center := Vector2(wheel_x, body.end.y - 2.0)
		draw_circle(wheel_center, 14.0, WOOD_DARK)
		draw_circle(wheel_center, 6.0, PlaygroundUI.mix(BRASS, Color.WHITE, 0.15))
	draw_circle(body.position + Vector2(18.0, 16.0), 10.0, Color(WOOD_DARK, 0.82))
	var font := PlaygroundUI.font()
	draw_string(font, body.position + Vector2(14.0, 21.0), str(index + 1), HORIZONTAL_ALIGNMENT_CENTER, 8.0, 12, Color.WHITE)
	if filled:
		var text := str(erasing_chunk_text(chunk_id))
		var text_width := body.size.x - 24.0
		var font_size := 20 if text.length() <= 8 else 17 if text.length() <= 14 else 15
		var lines := _wrap_text(text, text_width, font_size, 3)
		var total_height := float(lines.size()) * (font.get_height(font_size) + 2.0)
		var top := body.position.y + maxf(26.0, (body.size.y - total_height) * 0.5 + 4.0)
		_draw_lines(lines, Vector2(body.position.x + 12.0, top), text_width, font_size, CARD_INK, HORIZONTAL_ALIGNMENT_CENTER, 2.0)
	else:
		draw_string(
			font,
			Vector2(body.position.x + 12.0, body.position.y + body.size.y * 0.56),
			"下一节" if is_next else "空车厢",
			HORIZONTAL_ALIGNMENT_CENTER,
			body.size.x - 24.0,
			16,
			Color(accent, 0.78) if is_next else Color(WOOD_DARK, 0.45)
		)


func erasing_chunk_text(chunk_id: String) -> String:
	var lookup := _chunk_lookup()
	return str(lookup.get(chunk_id, ""))


func _draw_tray() -> void:
	draw_style_box(PlaygroundUI.style(
		Color("#fff8eb"),
		24,
		PlaygroundUI.mix(accent, Color.WHITE, 0.42),
		2,
		4,
		Color(0.22, 0.12, 0.05, 0.08)
	), _tray_rect)
	var font := PlaygroundUI.font()
	draw_string(font, _tray_rect.position + Vector2(20, 31), "词卡托盘", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, WOOD_DARK)
	var tray_ids: Array = state.get("trayIds", [])
	var hint := "还剩 %s 张" % tray_ids.size() if not tray_ids.is_empty() else "词卡都接好啦，点“完成句子”"
	draw_string(font, _tray_rect.position + Vector2(_tray_rect.size.x - 252.0, 31), hint, HORIZONTAL_ALIGNMENT_LEFT, 232.0, 15, PlaygroundUI.INK_SOFT)
	if tray_ids.is_empty():
		draw_circle(_tray_rect.get_center(), 24.0, Color(accent, 0.11))
		draw_circle(_tray_rect.get_center(), 11.0, Color(accent, 0.22))
		draw_string(
			font,
			Vector2(_tray_rect.position.x + 20.0, _tray_rect.position.y + _tray_rect.size.y * 0.6),
			"车厢里已经有全部词卡，检查顺序后让火车出发。",
			HORIZONTAL_ALIGNMENT_CENTER,
			_tray_rect.size.x - 40.0,
			20,
			PlaygroundUI.INK_SOFT
		)
		return
	var lookup := _chunk_lookup()
	for index in _tray_rects.size():
		if index >= _tray_ids.size():
			continue
		var chunk_id := _tray_ids[index]
		var rect := _tray_rects[index]
		var pressed := _pressed_kind == "tray" and _pressed_id == chunk_id
		if pressed:
			rect.position.y += 3.0
		draw_style_box(PlaygroundUI.style(
			PlaygroundUI.mix(soft, Color.WHITE, 0.28 if pressed else 0.18),
			17,
			accent if pressed else PlaygroundUI.mix(accent, Color.WHITE, 0.4),
			3 if pressed else 2,
			5,
			Color(0.26, 0.14, 0.05, 0.12)
		), rect)
		draw_circle(rect.position + Vector2(15.0, 15.0), 5.0, Color(accent, 0.34))
		var text := str(lookup.get(chunk_id, ""))
		var text_width := rect.size.x - 24.0
		var font_size := 21 if text.length() <= 8 else 18 if text.length() <= 14 else 16
		var lines := _wrap_text(text, text_width, font_size, 3)
		var total_height := float(lines.size()) * (font.get_height(font_size) + 2.0)
		var top := rect.position.y + maxf(14.0, (rect.size.y - total_height) * 0.5 - 2.0)
		_draw_lines(lines, Vector2(rect.position.x + 12.0, top), text_width, font_size, CARD_INK, HORIZONTAL_ALIGNMENT_CENTER, 2.0)


func _draw_feedback() -> void:
	var judgement_value: Variant = state.get("judgement", {})
	var judgement: Dictionary = judgement_value if judgement_value is Dictionary else {}
	var correct := bool(judgement.get("correct", false))
	var verdict_color := SUCCESS if correct else RETRY
	draw_style_box(PlaygroundUI.style(
		Color("#fff9ed"),
		26,
		PlaygroundUI.mix(verdict_color, Color.WHITE, 0.52),
		3,
		6,
		Color(0.22, 0.12, 0.05, 0.10)
	), _feedback_rect)
	draw_style_box(PlaygroundUI.style(
		PlaygroundUI.mix(verdict_color, Color.WHITE, 0.84),
		16
	), Rect2(_feedback_rect.position + Vector2(14, 14), Vector2(_feedback_rect.size.x - 28.0, 48.0)))
	_draw_verdict_icon(Vector2(_feedback_rect.position.x + 40.0, _feedback_rect.position.y + 38.0), verdict_color, correct)
	var font := PlaygroundUI.font()
	var verdict := "排对啦！整句话已经连成一条线。" if correct else "顺序还差一点，看看正确句子。"
	draw_string(
		font,
		Vector2(_feedback_rect.position.x + 62.0, _feedback_rect.position.y + 45.0),
		verdict,
		HORIZONTAL_ALIGNMENT_LEFT,
		_feedback_rect.size.x - 100.0,
		20,
		verdict_color
	)
	var y := _feedback_rect.position.y + 78.0
	draw_string(font, Vector2(_feedback_rect.position.x + 22.0, y), "完整句子", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, PlaygroundUI.INK_SOFT)
	y += 8.0
	var sentence_font := 28 if _feedback_rect.size.x >= 940.0 else 24
	var sentence_lines := _wrap_text(str(judgement.get("fullSentence", "")), _feedback_rect.size.x - 48.0, sentence_font)
	y = _draw_lines(
		sentence_lines,
		Vector2(_feedback_rect.position.x + 24.0, y),
		_feedback_rect.size.x - 48.0,
		sentence_font,
		WOOD_DARK,
		HORIZONTAL_ALIGNMENT_LEFT,
		5.0
	)
	y += 5.0
	if not correct:
		var attempt := str(judgement.get("attemptText", ""))
		if not attempt.is_empty():
			var attempt_lines := _wrap_text("你排成的是：%s" % attempt, _feedback_rect.size.x - 48.0, 17)
			y = _draw_lines(
				attempt_lines,
				Vector2(_feedback_rect.position.x + 24.0, y),
				_feedback_rect.size.x - 48.0,
				17,
				PlaygroundUI.INK_SOFT,
				HORIZONTAL_ALIGNMENT_LEFT,
				3.0
			)
			y += 5.0
	draw_line(
		Vector2(_feedback_rect.position.x + 24.0, y + 2.0),
		Vector2(_feedback_rect.end.x - 24.0, y + 2.0),
		PlaygroundUI.mix(verdict_color, Color.WHITE, 0.66),
		2.0,
		true
	)
	y += 16.0
	draw_string(font, Vector2(_feedback_rect.position.x + 24.0, y), "为什么这样说", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, verdict_color)
	y += 8.0
	var explanation_size := 20 if _feedback_rect.size.x >= 940.0 else 18
	var explanation_lines := _wrap_text(str(judgement.get("explanation", "")), _feedback_rect.size.x - 48.0, explanation_size)
	var bottom_limit := _feedback_rect.end.y - 40.0
	while explanation_size > 14:
		var line_height := font.get_height(explanation_size) + 4.0
		if y + float(explanation_lines.size()) * line_height <= bottom_limit:
			break
		explanation_size -= 1
		explanation_lines = _wrap_text(str(judgement.get("explanation", "")), _feedback_rect.size.x - 48.0, explanation_size)
	_draw_lines(
		explanation_lines,
		Vector2(_feedback_rect.position.x + 24.0, y),
		_feedback_rect.size.x - 48.0,
		explanation_size,
		PlaygroundUI.INK,
		HORIZONTAL_ALIGNMENT_LEFT,
		4.0
	)
	draw_string(
		font,
		Vector2(_feedback_rect.position.x + 24.0, _feedback_rect.end.y - 16.0),
		"看清标点，再点下面的“%s”。" % ("查看成绩" if is_last_sentence() else "下一句"),
		HORIZONTAL_ALIGNMENT_LEFT,
		_feedback_rect.size.x - 48.0,
		15,
		Color(PlaygroundUI.INK_SOFT, 0.78)
	)


func _draw_verdict_icon(center: Vector2, tint: Color, correct: bool) -> void:
	draw_circle(center, 15.0, PlaygroundUI.mix(tint, Color.WHITE, 0.8))
	draw_arc(center, 15.0, 0.0, TAU, 30, tint, 2.0, true)
	if correct:
		draw_line(center + Vector2(-7, 0), center + Vector2(-2, 6), tint, 3.0, true)
		draw_line(center + Vector2(-2, 6), center + Vector2(8, -7), tint, 3.0, true)
	else:
		draw_line(center + Vector2(0, -7), center + Vector2(0, 3), tint, 3.0, true)
		draw_circle(center + Vector2(0, 8), 2.2, tint)


func is_last_sentence() -> bool:
	return int(state.get("sentenceIndex", 0)) >= int(state.get("sentenceCount", 5)) - 1


func _chunk_lookup() -> Dictionary:
	var lookup := {}
	var chunks: Array = state.get("sentence", {}).get("chunks", [])
	for chunk in chunks:
		if chunk is Dictionary:
			lookup[str(chunk.get("id", ""))] = str(chunk.get("text", ""))
	return lookup


func _wrap_text(text: String, width: float, font_size: int, max_lines: int = -1) -> PackedStringArray:
	var result := PackedStringArray()
	if text.is_empty() or width <= 1.0:
		return result
	var font := PlaygroundUI.font()
	var current := ""
	for index in text.length():
		var character := text.substr(index, 1)
		if character == "\n":
			result.append(current)
			current = ""
			if max_lines > 0 and result.size() >= max_lines:
				break
			continue
		var trial := current + character
		var overflows := font.get_string_size(trial, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > width
		var punctuation_break := (character in CLOSING_PUNCTUATION) and not current.is_empty()
		if overflows and not punctuation_break and not current.is_empty():
			result.append(current)
			if max_lines > 0 and result.size() >= max_lines:
				current = ""
				break
			current = character
		else:
			current = trial
	if not current.is_empty() and (max_lines <= 0 or result.size() < max_lines):
		result.append(current)
	if max_lines > 0 and result.size() > max_lines:
		result.resize(max_lines)
		result[max_lines - 1] = result[max_lines - 1] + "…"
	return result


func _draw_lines(
	lines: PackedStringArray,
	origin: Vector2,
	width: float,
	font_size: int,
	color: Color,
	alignment: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT,
	gap: float = 2.0
) -> float:
	var font := PlaygroundUI.font()
	var line_height := font.get_height(font_size) + gap
	var baseline := origin.y + font.get_ascent(font_size)
	for line in lines:
		draw_string(font, Vector2(origin.x, baseline), line, alignment, width, font_size, color)
		baseline += line_height
	return origin.y + float(lines.size()) * line_height
