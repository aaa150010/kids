class_name PixelArtBoard
extends Control

signal cell_pressed(index: int)

var level: Dictionary = {}
var state: Dictionary = {}
var accent := Color("#5c4a9a")
var soft := Color("#ebe7f8")
var interactive := true
var tool_mode := "paint"

var _origin := Vector2.ZERO
var _cell_size := 1.0
var _gap := 2.0
var _press_index := -1
var _pressed := false
var _press_point := Vector2.ZERO
var _last_touch_msec := -1000
var _base_size := 600.0
var _zoom := 1.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	clip_contents = true
	resized.connect(_layout)
	_layout()


func configure(value: Dictionary, tint: Color, soft_tint: Color) -> void:
	level = value.duplicate(true)
	accent = tint
	soft = soft_tint
	state = {}
	interactive = true
	tool_mode = "paint"
	_press_index = -1
	_pressed = false
	_update_minimum()
	_layout()
	queue_redraw()


func set_state(value: Dictionary) -> void:
	state = value.duplicate(true)
	if state.get("level") is Dictionary:
		level = state.level.duplicate(true)
	_zoom = clampf(float(state.get("zoom", 1.0)), 0.75, 2.0)
	_update_minimum()
	_layout()
	queue_redraw()


func set_zoom(value: float) -> void:
	_zoom = clampf(value, 0.75, 2.0)
	_update_minimum()
	_layout()
	queue_redraw()


func set_tool_mode(value: String) -> void:
	tool_mode = value
	queue_redraw()


func set_interaction_enabled(value: bool) -> void:
	interactive = value
	if not value:
		_press_index = -1
		_pressed = false
	queue_redraw()


func set_showcase(value: bool) -> void:
	state.showcase = value
	queue_redraw()


func cancel_gesture() -> void:
	_press_index = -1
	_pressed = false
	queue_redraw()


func _update_minimum() -> void:
	var dimension := maxi(8, int(level.get("width", 8)))
	var base := maxf(600.0, float(dimension) * 56.0)
	_base_size = base
	custom_minimum_size = Vector2(base * _zoom, base * _zoom)


func _layout() -> void:
	if size.x < 1.0 or size.y < 1.0 or level.is_empty():
		return
	var width := maxi(8, int(level.get("width", 8)))
	var height := maxi(8, int(level.get("height", 8)))
	var margin := clampf(minf(size.x, size.y) * 0.025, 10.0, 28.0)
	_gap = clampf(minf(size.x, size.y) * 0.003, 1.0, 4.0)
	_cell_size = minf(
		(size.x - margin * 2.0 - _gap * float(width - 1)) / float(width),
		(size.y - margin * 2.0 - _gap * float(height - 1)) / float(height)
	)
	var extent := Vector2(
		_cell_size * float(width) + _gap * float(width - 1),
		_cell_size * float(height) + _gap * float(height - 1)
	)
	_origin = (size - extent) * 0.5


func cell_rect(index: int) -> Rect2:
	var width := maxi(8, int(level.get("width", 8)))
	var column := index % width
	var row := int(index / width)
	return Rect2(
		_origin + Vector2(column * (_cell_size + _gap), row * (_cell_size + _gap)),
		Vector2(_cell_size, _cell_size)
	)


func cell_at(point: Vector2) -> int:
	var width := maxi(8, int(level.get("width", 8)))
	var height := maxi(8, int(level.get("height", 8)))
	var local := point - _origin
	if local.x < 0.0 or local.y < 0.0:
		return -1
	var column := int(floor(local.x / (_cell_size + _gap)))
	var row := int(floor(local.y / (_cell_size + _gap)))
	if column < 0 or row < 0 or column >= width or row >= height:
		return -1
	var index := row * width + column
	if not cell_rect(index).has_point(point):
		return -1
	return index


func _draw() -> void:
	if level.is_empty() or state.is_empty():
		return
	var showcase := bool(state.get("showcase", false)) or str(state.get("phase", "")) == "finished"
	draw_style_box(PlaygroundUI.style(PlaygroundUI.mix(soft, Color.WHITE, 0.30), 26, PlaygroundUI.mix(accent, Color.WHITE, 0.48), 2, 8, Color(0, 0, 0, 0.12)), Rect2(Vector2.ZERO, size))
	var width := int(level.get("width", 0))
	var height := int(level.get("height", 0))
	var target: Array = level.get("target", [])
	var painted: Array = state.get("painted", [])
	var palette: Array = level.get("palette", [])
	var hint_cells: Array = state.get("hintCells", [])
	var showcase_pad := maxf(6.0, _cell_size * 0.12) if showcase else 0.0
	if showcase:
		var art_rect := Rect2(
			_origin - Vector2(showcase_pad, showcase_pad),
			Vector2(
				_cell_size * float(width) + _gap * float(width - 1) + showcase_pad * 2.0,
				_cell_size * float(height) + _gap * float(height - 1) + showcase_pad * 2.0
			)
		)
		draw_style_box(PlaygroundUI.style(Color("#fffdf7"), 16, accent, 3, 5, Color(0, 0, 0, 0.15)), art_rect)
	for index in width * height:
		var rect := cell_rect(index)
		var target_color := int(target[index]) if index < target.size() else 0
		var paint_color := int(painted[index]) if index < painted.size() else 0
		if showcase:
			draw_rect(rect.grow(_gap * 0.5), _palette_color(palette, paint_color if paint_color > 0 else target_color))
			continue
		draw_style_box(
			PlaygroundUI.style(Color("#fffef9"), maxi(2, int(_cell_size * 0.12)), Color("#ddd6eb"), 1),
			rect.grow(-_gap * 0.5)
		)
		if paint_color > 0:
			var color := _palette_color(palette, paint_color)
			draw_style_box(PlaygroundUI.style(color, maxi(2, int(_cell_size * 0.12)), color.darkened(0.18), 1), rect.grow(-_gap))
			_draw_paint_texture(rect, paint_color)
			if paint_color != target_color:
				_draw_wrong(rect)
				_text(str(target_color), rect.position + Vector2(rect.size.x * 0.18, rect.size.y * 0.18), maxf(10.0, rect.size.x * 0.21), Color("#fff9ed"))
		else:
			var number_tint := _palette_color(palette, target_color).darkened(0.25)
			draw_circle(rect.get_center(), rect.size.x * 0.34, _palette_color(palette, target_color).lightened(0.72))
			_text(str(target_color), rect.get_center(), maxf(12.0, rect.size.x * 0.39), number_tint, true)
		if index in hint_cells:
			draw_style_box(PlaygroundUI.style(Color(1, 0.91, 0.39, 0.18), maxi(2, int(rect.size.x * 0.13)), Color("#f2c52d"), maxf(2.0, rect.size.x * 0.055)), rect.grow(-_gap))
			if paint_color == 0:
				_text(str(target_color), rect.get_center(), maxf(12.0, rect.size.x * 0.39), Color("#74520d"), true)
		if index == _press_index and _pressed:
			draw_rect(rect.grow(-_gap * 2.0), Color(1, 1, 1, 0.30))
	if not showcase:
		_draw_tool_corner()


func _draw_paint_texture(rect: Rect2, color_index: int) -> void:
	if color_index % 3 == 0:
		draw_circle(rect.get_center(), rect.size.x * 0.20, Color(1, 1, 1, 0.14))
	elif color_index % 3 == 1:
		draw_line(
			rect.position + Vector2(rect.size.x * 0.24, rect.size.y * 0.25),
			rect.position + Vector2(rect.size.x * 0.75, rect.size.y * 0.72),
			Color(1, 1, 1, 0.16),
			maxf(1.5, rect.size.x * 0.05),
			true
		)
	else:
		draw_arc(rect.get_center(), rect.size.x * 0.24, 0.2, PI - 0.2, 16, Color(1, 1, 1, 0.18), maxf(1.5, rect.size.x * 0.04), true)


func _draw_wrong(rect: Rect2) -> void:
	var inset := rect.grow(-rect.size.x * 0.09)
	var tint := Color("#d65f4d")
	draw_line(inset.position, inset.end, tint, maxf(2.0, rect.size.x * 0.065), true)
	draw_line(inset.position + Vector2(inset.size.x, 0), inset.position + Vector2(0, inset.size.y), tint, maxf(2.0, rect.size.x * 0.065), true)


func _draw_tool_corner() -> void:
	var dimension_text := "%s×%s" % [int(level.get("width", 0)), int(level.get("height", 0))]
	var rect := Rect2(size.x - 104.0, 10.0, 92.0, 30.0)
	draw_style_box(PlaygroundUI.style(PlaygroundUI.mix(accent, Color.WHITE, 0.86), 12, accent, 1), rect)
	_text(dimension_text, rect.get_center(), 14, accent, true)
	if tool_mode == "erase":
		var eraser := Rect2(rect.position - Vector2(0, 38), rect.size)
		draw_style_box(PlaygroundUI.style(Color("#fff3d7"), 12, Color("#dfaa44"), 2), eraser)
		_text("橡皮擦", eraser.get_center(), 14, Color("#7d5b21"), true)


func _palette_color(palette: Array, index: int) -> Color:
	if index > 0 and index <= palette.size():
		return Color(str(palette[index - 1]))
	return Color("#d7d0df")


func _gui_input(event: InputEvent) -> void:
	if not interactive or _blocked():
		cancel_gesture()
		return
	if event is InputEventScreenTouch:
		if event.device == InputEvent.DEVICE_ID_EMULATION:
			return
		_last_touch_msec = Time.get_ticks_msec()
		if event.pressed:
			_press_index = cell_at(event.position)
			_pressed = _press_index >= 0
			_press_point = event.position
		else:
			_release(event.position)
	elif event is InputEventScreenDrag:
		_last_touch_msec = Time.get_ticks_msec()
		if _press_point.distance_to(event.position) > 12.0:
			_press_index = -1
			_pressed = false
		# 拖动交给外层 ScrollContainer，放大后仍可用一指平移。
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if Time.get_ticks_msec() - _last_touch_msec < 500:
			return
		if event.pressed:
			_press_index = cell_at(event.position)
			_pressed = _press_index >= 0
			_press_point = event.position
			accept_event()
		else:
			_release(event.position)
			accept_event()
	elif event is InputEventMouseMotion and _pressed:
		if _press_point.distance_to(event.position) > 12.0:
			_press_index = -1
			_pressed = false
		accept_event()


func _release(point: Vector2) -> void:
	if not _pressed:
		return
	var pressed_index := _press_index
	_pressed = false
	_press_index = -1
	queue_redraw()
	var released_index := cell_at(point)
	if released_index >= 0 and released_index == pressed_index:
		cell_pressed.emit(released_index)


func _blocked() -> bool:
	var owner := get_parent()
	while owner != null:
		if owner is NativeGameScreen:
			return owner.is_input_blocked()
		owner = owner.get_parent()
	return false


func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_CLOSE_REQUEST]:
		cancel_gesture()


func _text(value: String, center: Vector2, font_size: float, tint: Color, bold: bool = false) -> void:
	var pixels := maxi(10, int(font_size))
	var font := PlaygroundUI.font()
	var width := font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, pixels).x
	draw_string(font, center + Vector2(-width * 0.5, pixels * 0.35), value, HORIZONTAL_ALIGNMENT_LEFT, -1, pixels, tint)
	if bold:
		draw_string(font, center + Vector2(-width * 0.5 + 1.0, pixels * 0.35 + 1.0), value, HORIZONTAL_ALIGNMENT_LEFT, -1, pixels, Color(0, 0, 0, 0.16))
