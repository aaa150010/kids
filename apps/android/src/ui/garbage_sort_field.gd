class_name GarbageSortField
extends Control

signal action_requested(action: Dictionary)

var engine: GarbageSortRules
var accent := Color("#3e7d55")
var soft := Color("#e4f1e6")
var paused := false

var _item_rect := Rect2()
var _bin_rects: Array[Rect2] = []
var _drag_pointer := -1
var _drag_position := Vector2.ZERO
var _drag_origin := Vector2.ZERO
var _drag_active := false
var _last_touch_msec := -1000
var _notice := ""
var _notice_until := 0.0
var _clock := 0.0
var _hover_bin := -1


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	custom_minimum_size = Vector2(900, 600)
	set_process(true)


func bind(rules: GarbageSortRules, tint: Color, soft_color: Color) -> void:
	engine = rules
	accent = tint
	soft = soft_color
	_drag_active = false
	_drag_pointer = -1
	_hover_bin = -1
	_notice = ""
	queue_redraw()


func set_paused(value: bool) -> void:
	paused = value
	if paused:
		_drag_active = false
		_drag_pointer = -1


func show_notice(message: String, seconds: float = 1.7) -> void:
	_notice = message
	_notice_until = _clock + seconds
	queue_redraw()


func bin_rect(index: int) -> Rect2:
	return _bin_rects[index] if index >= 0 and index < _bin_rects.size() else Rect2()


func item_rect() -> Rect2:
	return _item_rect


func _process(delta: float) -> void:
	_clock += delta
	if _notice_until > 0.0 and _clock > _notice_until:
		_notice = ""
		_notice_until = 0.0
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if paused or engine == null or str(engine.state.get("phase", "")) != "sorting":
		return
	get_viewport().set_input_as_handled()
	if event is InputEventScreenTouch:
		if event.device == InputEvent.DEVICE_ID_EMULATION:
			return
		_last_touch_msec = Time.get_ticks_msec()
		_handle_pointer(event.index, event.position, event.pressed)
	elif event is InputEventScreenDrag:
		_last_touch_msec = Time.get_ticks_msec()
		_handle_drag(event.index, event.position)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if Time.get_ticks_msec() - _last_touch_msec < 500:
			return
		_handle_pointer(0, event.position, event.pressed)
	elif event is InputEventMouseMotion and _drag_active and _drag_pointer == 0:
		_handle_drag(0, event.position)


func _handle_pointer(pointer: int, position: Vector2, pressed: bool) -> void:
	if pressed:
		if _item_rect.grow(18.0).has_point(position):
			_drag_pointer = pointer
			_drag_origin = position
			_drag_position = position
			_drag_active = false
			_hover_bin = -1
		return
	if _drag_pointer != pointer:
		if pointer == 0 and not pressed:
			var direct_bin := _bin_at(position)
			if direct_bin >= 0:
				action_requested.emit({"type": "sort", "binId": _bin_id(direct_bin)})
		return
	var drop_bin := _bin_at(position)
	var was_dragging := _drag_active
	_drag_pointer = -1
	_drag_active = false
	_hover_bin = -1
	if was_dragging:
		if drop_bin >= 0:
			action_requested.emit({"type": "sort", "binId": _bin_id(drop_bin)})
		else:
			show_notice("把物品拖到四个桶中的一个，或者直接点桶。")
	else:
		var tapped_bin := _bin_at(position)
		if tapped_bin >= 0:
			action_requested.emit({"type": "sort", "binId": _bin_id(tapped_bin)})
	queue_redraw()


func _handle_drag(pointer: int, position: Vector2) -> void:
	if _drag_pointer != pointer:
		return
	_drag_position = position
	if not _drag_active and _drag_origin.distance_to(position) > 12.0:
		_drag_active = true
	_hover_bin = _bin_at(position) if _drag_active else -1
	queue_redraw()


func _bin_at(position: Vector2) -> int:
	for index in _bin_rects.size():
		if _bin_rects[index].grow(10.0).has_point(position):
			return index
	return -1


func _bin_id(index: int) -> String:
	var categories: Array = engine.state.get("categories", [])
	if index < 0 or index >= categories.size() or not categories[index] is Dictionary:
		return ""
	return str(categories[index].get("id", ""))


func _draw() -> void:
	var canvas := Rect2(Vector2.ZERO, size)
	draw_style_box(
		PlaygroundUI.style(PlaygroundUI.mix(accent, Color.WHITE, 0.94), 28, PlaygroundUI.mix(accent, Color.WHITE, 0.48), 2, 8, Color(0, 0, 0, 0.10)),
		canvas
	)
	_layout()
	_draw_header()
	_draw_item_card()
	_draw_bins()
	_draw_drag_ghost()
	_draw_notice()


func _layout() -> void:
	var width := maxf(900.0, size.x)
	var height := maxf(560.0, size.y)
	_item_rect = Rect2(Vector2(width * 0.5 - 128.0, 118.0), Vector2(256.0, 250.0))
	var bin_gap := 14.0
	var bin_width := minf(268.0, (width - 92.0 - bin_gap * 3.0) / 4.0)
	var total_width := bin_width * 4.0 + bin_gap * 3.0
	var start_x := (width - total_width) * 0.5
	var bin_y := maxf(_item_rect.end.y + 38.0, height - 218.0)
	_bin_rects.clear()
	for index in 4:
		_bin_rects.append(Rect2(Vector2(start_x + (bin_width + bin_gap) * float(index), bin_y), Vector2(bin_width, 158.0)))


func _draw_header() -> void:
	if engine == null:
		return
	var level: Dictionary = engine.state.get("levelData", {})
	var font := PlaygroundUI.font()
	draw_string(font, Vector2(26, 40), str(level.get("title", "垃圾分类站")), HORIZONTAL_ALIGNMENT_LEFT, size.x - 500.0, 25, PlaygroundUI.INK)
	draw_string(font, Vector2(26, 65), "%s · 第 %s 关 · %s" % [engine.progress_text(), int(level.get("levelNumber", 1)), _band_name(str(level.get("band", "")))], HORIZONTAL_ALIGNMENT_LEFT, size.x - 520.0, 15, PlaygroundUI.INK_SOFT)
	var player_name := "一起分类" if engine.state.players.size() > 1 else "分类小助手"
	if engine.state.players.size() == 1:
		player_name = str(engine.state.players[0].get("name", player_name))
	elif engine.state.players.size() > 1:
		var current := clampi(int(engine.state.get("currentPlayer", 0)), 0, engine.state.players.size() - 1)
		player_name = "%s · 轮到你" % str(engine.state.players[current].get("name", "小助手"))
	draw_string(font, Vector2(size.x - 360, 41), player_name, HORIZONTAL_ALIGNMENT_LEFT, 220.0, 17, accent)
	var score_text := "得分 %s · 连对 %s · 纠正 %s" % [
		int(engine.state.get("score", 0)),
		int(engine.state.get("combo", 0)),
		int(engine.state.get("mistakes", 0)),
	]
	draw_string(font, Vector2(size.x - 360, 65), score_text, HORIZONTAL_ALIGNMENT_LEFT, 320.0, 14, PlaygroundUI.INK_SOFT)


func _draw_item_card() -> void:
	if engine == null:
		return
	var item := engine.current_item()
	if item.is_empty():
		return
	draw_style_box(
		PlaygroundUI.style(PlaygroundUI.mix(soft, Color.WHITE, 0.18), 26, PlaygroundUI.mix(accent, Color.WHITE, 0.35), 2, 6, Color(0, 0, 0, 0.12)),
		_item_rect
	)
	var art_rect := Rect2(_item_rect.position + Vector2(55, 26), Vector2(146, 142))
	_draw_item_art(item, art_rect.get_center(), 66.0)
	var font := PlaygroundUI.font()
	draw_string(font, Vector2(_item_rect.position.x + 20.0, _item_rect.position.y + 192.0), str(item.get("name", "生活物品")), HORIZONTAL_ALIGNMENT_CENTER, _item_rect.size.x - 40.0, 24, PlaygroundUI.INK)
	draw_string(font, Vector2(_item_rect.position.x + 24.0, _item_rect.position.y + 220.0), "拖到桶里，或点下面的桶", HORIZONTAL_ALIGNMENT_CENTER, _item_rect.size.x - 48.0, 15, PlaygroundUI.INK_SOFT)


func _draw_bins() -> void:
	if engine == null:
		return
	var categories: Array = engine.state.get("categories", [])
	for index in mini(4, categories.size()):
		var category: Dictionary = categories[index]
		var rect := _bin_rects[index]
		var tint := PlaygroundUI.color(str(category.get("color", "#7b8a72")), accent)
		var hover := _hover_bin == index or (_drag_active and _bin_at(_drag_position) == index)
		draw_style_box(
			PlaygroundUI.style(PlaygroundUI.mix(tint, Color.WHITE, 0.80 if not hover else 0.58), 22, tint if hover else PlaygroundUI.mix(tint, Color.WHITE, 0.36), 3 if hover else 2, 5, Color(0, 0, 0, 0.10)),
			rect
		)
		draw_style_box(
			PlaygroundUI.style(Color(tint, 0.16), 16, Color(tint, 0.26), 1),
			Rect2(Vector2(rect.position.x + 15.0, rect.position.y + 13.0), Vector2(rect.size.x - 30.0, 44.0))
		)
		_draw_category_glyph(str(category.get("id", "")), Vector2(rect.position.x + 48.0, rect.position.y + 35.0), 24.0, tint)
		draw_string(PlaygroundUI.font(), Vector2(rect.position.x + 76.0, rect.position.y + 43.0), str(category.get("name", "垃圾桶")), HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 90.0, 19, PlaygroundUI.INK)
		var short_text := str(category.get("short", ""))
		draw_multiline_string(PlaygroundUI.font(), Vector2(rect.position.x + 18.0, rect.position.y + 91.0), short_text, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 36.0, 14, 3, PlaygroundUI.INK_SOFT)


func _draw_drag_ghost() -> void:
	if not _drag_active or engine == null:
		return
	var item := engine.current_item()
	if item.is_empty():
		return
	var center := _drag_position + Vector2(0, -20)
	draw_circle(center + Vector2(0, 8), 58.0, Color(0, 0, 0, 0.16))
	_draw_item_art(item, center, 52.0)


func _draw_notice() -> void:
	if _notice.is_empty():
		return
	var font := PlaygroundUI.font()
	var width := minf(size.x - 120.0, font.get_string_size(_notice, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x + 36.0)
	var rect := Rect2(Vector2((size.x - width) * 0.5, size.y - 58.0), Vector2(width, 36.0))
	draw_style_box(PlaygroundUI.style(PlaygroundUI.mix(accent, Color.WHITE, 0.82), 18, Color(accent, 0.32), 1), rect)
	draw_string(font, rect.position + Vector2(18.0, 24.0), _notice, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 36.0, 17, accent)


func _draw_category_glyph(category_id: String, center: Vector2, radius: float, tint: Color) -> void:
	match category_id:
		"recyclable":
			for index in 3:
				var start := -PI * 0.5 + TAU * float(index) / 3.0
				draw_arc(center, radius * 0.72, start + 0.22, start + PI * 0.62, 12, tint, 3.0, true)
				var tip := center + Vector2(cos(start + PI * 0.62), sin(start + PI * 0.62)) * radius * 0.72
				draw_colored_polygon(PackedVector2Array([tip, tip + Vector2(-4, 9), tip + Vector2(8, 7)]), tint)
		"hazardous":
			draw_colored_polygon(PackedVector2Array([
				center + Vector2(0, -radius * 0.92),
				center + Vector2(radius * 0.86, radius * 0.70),
				center + Vector2(-radius * 0.86, radius * 0.70),
			]), tint)
			draw_line(center + Vector2(0, -radius * 0.35), center + Vector2(0, radius * 0.18), Color.WHITE, 3.0, true)
			draw_circle(center + Vector2(0, radius * 0.45), 2.2, Color.WHITE)
		"kitchen":
			draw_colored_polygon(PackedVector2Array([
				center + Vector2(0, radius * 0.72),
				center + Vector2(-radius * 0.68, -radius * 0.10),
				center + Vector2(0, -radius * 0.62),
				center + Vector2(radius * 0.68, -radius * 0.10),
			]), tint)
			draw_line(center + Vector2(0, radius * 0.45), center + Vector2(0, radius * 0.88), Color(tint, 0.75), 2.0, true)
		_:
			draw_style_box(
				PlaygroundUI.style(Color(tint, 0.18), 6, tint, 2),
				Rect2(center + Vector2(-radius * 0.62, -radius * 0.36), Vector2(radius * 1.24, radius * 1.15))
			)
			draw_line(center + Vector2(-radius * 0.82, -radius * 0.48), center + Vector2(radius * 0.82, -radius * 0.48), tint, 3.0, true)
			for offset in [-0.30, 0.0, 0.30]:
				draw_line(center + Vector2(radius * offset, -radius * 0.12), center + Vector2(radius * offset, radius * 0.46), Color(tint, 0.58), 1.5, true)


func _draw_item_art(item: Dictionary, center: Vector2, radius: float) -> void:
	var art := str(item.get("art", "object"))
	var category_engine := engine.category_for_item(str(item.get("id", ""))) if engine != null else {}
	var tint := PlaygroundUI.color(str(category_engine.get("color", "#7b8a72")), accent)
	draw_circle(center, radius * 1.05, PlaygroundUI.mix(tint, Color.WHITE, 0.82))
	draw_circle(center + Vector2(-radius * 0.28, -radius * 0.25), radius * 0.23, Color(1, 1, 1, 0.32))
	var ink := tint.darkened(0.30)
	match art:
		"bottle":
			draw_style_box(PlaygroundUI.style(Color(tint, 0.28), int(radius * 0.22), tint, 3), Rect2(center + Vector2(-radius * 0.25, -radius * 0.22), Vector2(radius * 0.50, radius * 0.80)))
			draw_rect(Rect2(center + Vector2(-radius * 0.13, -radius * 0.55), Vector2(radius * 0.26, radius * 0.30)), tint)
			draw_rect(Rect2(center + Vector2(-radius * 0.17, -radius * 0.62), Vector2(radius * 0.34, radius * 0.10)), ink)
		"paper":
			draw_set_transform(center, -0.14, Vector2.ONE)
			draw_style_box(PlaygroundUI.style(Color.WHITE, 4, Color(tint, 0.55), 2), Rect2(Vector2(-radius * 0.50, -radius * 0.55), Vector2(radius, radius * 1.10)))
			for row in 4:
				draw_line(Vector2(-radius * 0.34, -radius * 0.33 + row * radius * 0.18), Vector2(radius * 0.35, -radius * 0.33 + row * radius * 0.18), Color(tint, 0.38), 2.0, true)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		"can":
			draw_style_box(PlaygroundUI.style(tint, 8, ink, 2), Rect2(center + Vector2(-radius * 0.32, -radius * 0.52), Vector2(radius * 0.64, radius * 1.08)))
			_draw_oval(center + Vector2(0, -radius * 0.50), Vector2(radius * 0.32, radius * 0.10), Color.WHITE)
			draw_line(center + Vector2(-radius * 0.18, -radius * 0.15), center + Vector2(radius * 0.20, radius * 0.35), Color(1, 1, 1, 0.48), 4.0, true)
		"battery":
			draw_style_box(PlaygroundUI.style(Color(tint, 0.30), 8, tint, 3), Rect2(center + Vector2(-radius * 0.26, -radius * 0.48), Vector2(radius * 0.52, radius * 0.96)))
			draw_rect(Rect2(center + Vector2(-radius * 0.11, -radius * 0.61), Vector2(radius * 0.22, radius * 0.13)), ink)
			draw_line(center + Vector2(4, -radius * 0.30), center + Vector2(-5, 0), tint, 4.0, true)
			draw_line(center + Vector2(-5, 0), center + Vector2(4, 0), tint, 4.0, true)
			draw_line(center + Vector2(4, 0), center + Vector2(-4, radius * 0.30), tint, 4.0, true)
		"bulb", "tube":
			draw_arc(center + Vector2(0, -radius * 0.08), radius * 0.42, 0, TAU, 28, tint, radius * 0.18, true)
			draw_rect(Rect2(center + Vector2(-radius * 0.16, radius * 0.28), Vector2(radius * 0.32, radius * 0.36)), Color(tint, 0.28))
			for row in 3:
				draw_line(center + Vector2(-radius * 0.16, radius * 0.36 + row * radius * 0.09), center + Vector2(radius * 0.16, radius * 0.36 + row * radius * 0.09), ink, 2.0, true)
		"medicine":
			draw_style_box(PlaygroundUI.style(Color.WHITE, 8, tint, 2), Rect2(center + Vector2(-radius * 0.45, -radius * 0.32), Vector2(radius * 0.90, radius * 0.64)))
			draw_line(center + Vector2(0, -radius * 0.28), center + Vector2(0, radius * 0.28), Color(tint, 0.40), 2.0, true)
			draw_circle(center + Vector2(-radius * 0.20, 0), radius * 0.12, tint)
			draw_circle(center + Vector2(radius * 0.20, 0), radius * 0.12, tint)
		"food":
			draw_colored_polygon(PackedVector2Array([
				center + Vector2(-radius * 0.58, -radius * 0.05),
				center + Vector2(radius * 0.58, -radius * 0.05),
				center + Vector2(radius * 0.42, radius * 0.48),
				center + Vector2(-radius * 0.42, radius * 0.48),
			]), PlaygroundUI.mix(tint, Color.WHITE, 0.12))
			draw_arc(center + Vector2(0, -radius * 0.05), radius * 0.58, PI, TAU, 24, ink, 3.0, true)
			draw_circle(center + Vector2(-radius * 0.18, radius * 0.16), radius * 0.12, Color("#6d9a52"))
			draw_circle(center + Vector2(radius * 0.20, radius * 0.10), radius * 0.10, Color("#d9aa4c"))
		"peel":
			draw_arc(center + Vector2(0, radius * 0.18), radius * 0.48, PI * 1.08, PI * 1.92, 18, tint, radius * 0.16, true)
			draw_line(center + Vector2(0, -radius * 0.30), center + Vector2(radius * 0.08, -radius * 0.58), ink, 3.0, true)
			draw_colored_polygon(PackedVector2Array([
				center + Vector2(radius * 0.08, -radius * 0.50),
				center + Vector2(radius * 0.45, -radius * 0.67),
				center + Vector2(radius * 0.32, -radius * 0.28),
			]), Color("#6d9a52"))
		"tissue", "mask":
			draw_style_box(PlaygroundUI.style(Color.WHITE, 8, Color(tint, 0.42), 2), Rect2(center + Vector2(-radius * 0.44, -radius * 0.32), Vector2(radius * 0.88, radius * 0.64)))
			if art == "mask":
				draw_arc(center + Vector2(0, 0), radius * 0.66, PI * 0.15, PI * 0.85, 18, Color(tint, 0.52), 2.0, true)
			draw_line(center + Vector2(-radius * 0.30, 0), center + Vector2(radius * 0.30, 0), Color(tint, 0.30), 2.0, true)
		"ceramic", "glass":
			draw_arc(center + Vector2(0, radius * 0.05), radius * 0.52, 0, TAU, 30, tint, radius * 0.18, true)
			draw_colored_polygon(PackedVector2Array([
				center + Vector2(-radius * 0.12, -radius * 0.50),
				center + Vector2(radius * 0.06, radius * 0.10),
				center + Vector2(-radius * 0.38, -radius * 0.42),
			]), Color(tint, 0.40))
		"toothbrush":
			draw_line(center + Vector2(-radius * 0.45, radius * 0.55), center + Vector2(radius * 0.30, -radius * 0.40), tint, 7.0, true)
			for row in 4:
				draw_line(center + Vector2(radius * 0.24 + row * radius * 0.08, -radius * 0.44), center + Vector2(radius * 0.31 + row * radius * 0.08, -radius * 0.62), Color.WHITE, 3.0, true)
		"mirror":
			draw_arc(center, radius * 0.52, 0, TAU, 32, ink, 4.0, true)
			draw_circle(center, radius * 0.45, Color("#b7d4d9"))
			draw_line(center + Vector2(-radius * 0.52, -radius * 0.10), center + Vector2(radius * 0.16, -radius * 0.54), Color.WHITE, 3.0, true)
		"pen":
			draw_line(center + Vector2(-radius * 0.50, radius * 0.45), center + Vector2(radius * 0.40, -radius * 0.48), tint, 8.0, true)
			draw_line(center + Vector2(-radius * 0.50, radius * 0.45), center + Vector2(-radius * 0.62, radius * 0.58), ink, 5.0, true)
		"wrapper", "foam":
			draw_colored_polygon(PackedVector2Array([
				center + Vector2(-radius * 0.46, -radius * 0.40),
				center + Vector2(radius * 0.25, -radius * 0.54),
				center + Vector2(radius * 0.48, radius * 0.12),
				center + Vector2(-radius * 0.10, radius * 0.45),
				center + Vector2(-radius * 0.52, radius * 0.12),
			]), PlaygroundUI.mix(tint, Color.WHITE, 0.20))
			draw_line(center + Vector2(-radius * 0.18, -radius * 0.26), center + Vector2(radius * 0.18, -radius * 0.10), Color.WHITE, 2.0, true)
		_:
			draw_style_box(PlaygroundUI.style(PlaygroundUI.mix(tint, Color.WHITE, 0.40), 14, tint, 3), Rect2(center + Vector2(-radius * 0.48, -radius * 0.38), Vector2(radius * 0.96, radius * 0.76)))
			draw_line(center + Vector2(-radius * 0.26, 0), center + Vector2(radius * 0.26, 0), Color(1, 1, 1, 0.52), 4.0, true)


func _draw_oval(center: Vector2, radii: Vector2, tint: Color) -> void:
	var points := PackedVector2Array()
	for index in 24:
		var angle := TAU * float(index) / 24.0
		points.append(center + Vector2(cos(angle) * radii.x, sin(angle) * radii.y))
	draw_colored_polygon(points, tint)


func _band_name(band: String) -> String:
	return {"easy": "轻松", "normal": "标准", "challenge": "挑战"}.get(band, "练习")
