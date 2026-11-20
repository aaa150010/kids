class_name SudokuBoard
extends Control

signal cell_pressed(position: int)

var rules: SudokuRules
var interactive := true
var accent := Color("#51418f")
var _touch_index := -1
var _touch_guard_msec := -1000
var _press_point := Vector2.ZERO
var _pressing := false


func _ready() -> void:
	custom_minimum_size = Vector2(440, 440)
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	resized.connect(queue_redraw)


func update_board(value: SudokuRules) -> void:
	rules = value
	queue_redraw()


func metrics() -> Dictionary:
	if rules == null:
		return {"cell": 48.0, "origin": Vector2.ZERO}
	var dimension := rules.size()
	var margin := clampf(minf(size.x, size.y) * 0.045, 18.0, 46.0)
	var cell := minf((size.x - margin * 2.0) / float(dimension), (size.y - margin * 2.0) / float(dimension))
	var extent := Vector2(cell * float(dimension), cell * float(dimension))
	return {"cell": cell, "origin": (size - extent) * 0.5}


func position_for(index: int) -> Vector2:
	var layout := metrics()
	var dimension := rules.size()
	return layout.origin + Vector2(float(index % dimension), float(int(index / dimension))) * float(layout.cell)


func cell_at(point: Vector2) -> int:
	if rules == null:
		return -1
	var layout := metrics()
	var cell := float(layout.cell)
	if cell <= 0:
		return -1
	var local: Vector2 = point - layout.origin
	var col := int(floor(local.x / cell))
	var row := int(floor(local.y / cell))
	var dimension := rules.size()
	if row < 0 or row >= dimension or col < 0 or col >= dimension:
		return -1
	return row * dimension + col


func _draw() -> void:
	if rules == null:
		return
	var layout := metrics()
	var cell := float(layout.cell)
	if cell <= 0:
		return
	var dimension := rules.size()
	var extent := cell * float(dimension)
	draw_style_box(PlaygroundUI.style(PlaygroundUI.mix(accent, Color.WHITE, 0.92), 28, PlaygroundUI.mix(accent, Color.WHITE, 0.55), 3, 8, Color(0, 0, 0, 0.12)), Rect2(Vector2.ZERO, size))
	var origin: Vector2 = layout.origin
	draw_style_box(PlaygroundUI.style(Color("#fffef8"), 12, accent, 3), Rect2(origin, Vector2(extent, extent)))
	var selected_index := int(rules.state.get("selected", -1))
	var same_digit := int(str(rules.state.get("values", ""))[selected_index]) if selected_index >= 0 and selected_index < str(rules.state.get("values", "")).length() else 0
	var conflict_cells: Array = []
	if selected_index >= 0 and same_digit > 0:
		conflict_cells = rules.conflict_cells(selected_index, same_digit)
	for index in dimension * dimension:
		var rect := Rect2(position_for(index), Vector2(cell, cell))
		var given := rules.is_given(index)
		var selected_row := int(selected_index / dimension) if selected_index >= 0 else -1
		var selected_col := selected_index % dimension if selected_index >= 0 else -1
		if selected_index >= 0 and (int(index / dimension) == selected_row or index % dimension == selected_col):
			draw_rect(rect, Color(accent.r, accent.g, accent.b, 0.08))
		if selected_index >= 0 and int(int(index / dimension) / rules.box_rows()) == int(selected_row / rules.box_rows()) and int((index % dimension) / rules.box_cols()) == int(selected_col / rules.box_cols()):
			draw_rect(rect, Color(accent.r, accent.g, accent.b, 0.09))
		if index == selected_index:
			draw_rect(rect, Color(1.0, 0.84, 0.38, 0.48))
		elif index == int(rules.state.get("hintCell", -1)):
			draw_rect(rect, Color(0.45, 0.80, 0.55, 0.30))
		elif given:
			draw_rect(rect, Color(accent.r, accent.g, accent.b, 0.10))
		var digit := int(str(rules.state.get("values", ""))[index])
		if digit > 0:
			var bad := rules.conflicts(index, digit)
			var tint := accent if given else Color("#e08a2e") if bad else PlaygroundUI.INK
			_text(str(digit), rect.get_center(), cell * 0.54, tint, given)
			if digit == same_digit and index != selected_index:
				draw_arc(rect.get_center(), cell * 0.36, 0, TAU, 28, Color(1.0, 0.80, 0.28, 0.8), 2.0, true)
		if index in conflict_cells and int(str(rules.state.get("values", ""))[index]) == same_digit:
			draw_rect(rect.grow(-2.0), Color("#d75c45"), false, maxf(2.0, cell * 0.045), true)
	var box_rows := rules.box_rows()
	var box_cols := rules.box_cols()
	for row in dimension + 1:
		var weight := 4.0 if row % box_rows == 0 else 1.4
		draw_line(origin + Vector2(0, cell * float(row)), origin + Vector2(extent, cell * float(row)), accent, weight, true)
	for col in dimension + 1:
		var weight := 4.0 if col % box_cols == 0 else 1.4
		draw_line(origin + Vector2(cell * float(col), 0), origin + Vector2(cell * float(col), extent), accent, weight, true)
	if str(rules.state.get("phase", "")) == "finished":
		var banner := Rect2(size.x * 0.18, size.y * 0.44, size.x * 0.64, size.y * 0.12)
		draw_style_box(PlaygroundUI.style(Color("#fff9e9"), 22, accent, 3, 8, Color(0, 0, 0, 0.16)), banner)
		_text("完成啦！", banner.get_center(), maxf(22.0, cell * 0.48), accent)


func _text(value: String, center: Vector2, font_size: float, tint: Color, bold: bool = false) -> void:
	var pixels := maxi(14, int(font_size))
	var font := PlaygroundUI.font()
	var width := font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, pixels).x
	draw_string(font, center + Vector2(-width * 0.5, pixels * 0.35), value, HORIZONTAL_ALIGNMENT_LEFT, -1, pixels, tint)
	if bold:
		draw_string(font, center + Vector2(-width * 0.5 + 1.0, pixels * 0.35), value, HORIZONTAL_ALIGNMENT_LEFT, -1, pixels, Color(tint.r, tint.g, tint.b, 0.25))


func _gui_input(event: InputEvent) -> void:
	if not interactive or TabletopLayout.input_blocked(self):
		_pressing = false
		return
	if event is InputEventScreenTouch:
		_touch_guard_msec = Time.get_ticks_msec()
		if event.index != _touch_index and not event.pressed:
			return
		if event.pressed:
			_touch_index = event.index
			_pressing = true
			_press_point = event.position
		else:
			_touch_index = -1
			_finish_press(event.position, event.canceled)
	elif event is InputEventScreenDrag:
		_touch_guard_msec = Time.get_ticks_msec()
		if event.index == _touch_index and _press_point.distance_to(event.position) > 16.0:
			_pressing = false
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if Time.get_ticks_msec() - _touch_guard_msec < 500:
			return
		if event.pressed:
			_pressing = true
			_press_point = event.position
		else:
			_finish_press(event.position, false)
	elif event is InputEventMouseMotion and _pressing:
		if _press_point.distance_to(event.position) > 16.0:
			_pressing = false
	else:
		return
	accept_event()


func _finish_press(point: Vector2, cancelled: bool) -> void:
	if not _pressing:
		return
	_pressing = false
	if cancelled or _press_point.distance_to(point) > 16.0:
		return
	var index := cell_at(point)
	if index >= 0:
		cell_pressed.emit(index)
