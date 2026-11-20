class_name SudokuBoard
extends Control

signal cell_pressed(position: int)

var rules: SudokuRules
var interactive := true
var accent := Color("#276f9e")
var _touch_index := -1


func _ready() -> void:
	custom_minimum_size = Vector2(520, 520)
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
	draw_style_box(PlaygroundUI.style(Color("#f7fbff"), 28, Color("#6ba9d0"), 3, 8, Color(0, 0, 0, 0.12)), Rect2(Vector2.ZERO, size))
	var origin: Vector2 = layout.origin
	draw_style_box(PlaygroundUI.style(Color("#fffef8"), 12, Color("#276f9e"), 3), Rect2(origin, Vector2(extent, extent)))
	for index in dimension * dimension:
		var rect := Rect2(position_for(index), Vector2(cell, cell))
		var given := rules.is_given(index)
		if index == int(rules.state.get("selected", -1)):
			draw_rect(rect, Color(1.0, 0.84, 0.38, 0.48))
		elif index == int(rules.state.get("hintCell", -1)):
			draw_rect(rect, Color(0.45, 0.80, 0.55, 0.30))
		elif given:
			draw_rect(rect, Color(0.86, 0.92, 0.97, 0.55))
		var digit := int(str(rules.state.get("values", ""))[index])
		if digit > 0:
			var tint := Color("#276f9e") if given else Color("#e08a2e") if rules.conflicts(index, digit) else accent
			_text(str(digit), rect.get_center(), cell * 0.54, tint, given)
	var box_rows := rules.box_rows()
	var box_cols := rules.box_cols()
	for row in dimension + 1:
		var weight := 4.0 if row % box_rows == 0 else 1.4
		draw_line(origin + Vector2(0, cell * float(row)), origin + Vector2(extent, cell * float(row)), Color("#4a86b1"), weight, true)
	for col in dimension + 1:
		var weight := 4.0 if col % box_cols == 0 else 1.4
		draw_line(origin + Vector2(cell * float(col), 0), origin + Vector2(cell * float(col), extent), Color("#4a86b1"), weight, true)
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
	if not interactive:
		return
	var point := Vector2.ZERO
	var pressed := false
	if event is InputEventScreenTouch:
		if event.index != _touch_index and not event.pressed:
			return
		_touch_index = event.index if event.pressed else -1
		point = event.position
		pressed = event.pressed
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		point = event.position
		pressed = event.pressed
	else:
		return
	if not pressed:
		return
	var index := cell_at(point)
	if index >= 0:
		cell_pressed.emit(index)
		accept_event()
