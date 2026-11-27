class_name SlidePuzzleBoard
extends Control

signal tile_pressed(index: int)

var level: Dictionary = {}
var state: Dictionary = {}
var accent := Color("#4f6078")
var soft := Color("#e8edf3")
var interactive := true

var _board_rect := Rect2()
var _origin := Vector2.ZERO
var _cell_size := 1.0
var _gap := 6.0
var _press_index := -1
var _pressed := false
var _last_touch_msec := -1000


func _ready() -> void:
	custom_minimum_size = Vector2(440, 440)
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	resized.connect(_layout)
	_layout()


func configure(value: Dictionary, tint: Color, soft_tint: Color) -> void:
	level = value.duplicate(true)
	accent = tint
	soft = soft_tint
	state = {}
	interactive = true
	_press_index = -1
	_layout()
	queue_redraw()


func set_state(value: Dictionary) -> void:
	state = value.duplicate(true)
	if state.get("level") is Dictionary:
		level = state.level.duplicate(true)
	_layout()
	queue_redraw()


func set_interaction_enabled(value: bool) -> void:
	interactive = value
	if not value:
		_press_index = -1
		_pressed = false
	queue_redraw()


func cancel_gesture() -> void:
	_press_index = -1
	_pressed = false
	queue_redraw()


func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_CLOSE_REQUEST]:
		cancel_gesture()


func _blocked() -> bool:
	var owner := get_parent()
	while owner != null:
		if owner is NativeGameScreen:
			return owner.is_input_blocked()
		owner = owner.get_parent()
	return false


func _layout() -> void:
	if size.x < 1.0 or size.y < 1.0:
		return
	var margin := clampf(minf(size.x, size.y) * 0.035, 12.0, 30.0)
	var usable := Vector2(size.x - margin * 2.0, size.y - margin * 2.0)
	var extent := minf(usable.x, usable.y)
	_board_rect = Rect2((size - Vector2(extent, extent)) * 0.5, Vector2(extent, extent))
	var dimension := maxi(3, int(level.get("size", 3)))
	_gap = clampf(extent * 0.016, 5.0, 12.0)
	_cell_size = (extent - margin * 2.0 - _gap * float(dimension - 1)) / float(dimension)
	_origin = _board_rect.position + Vector2(margin, margin)


func cell_rect(index: int) -> Rect2:
	var dimension := maxi(3, int(level.get("size", 3)))
	var column := index % dimension
	var row := int(index / dimension)
	return Rect2(
		_origin + Vector2(column * (_cell_size + _gap), row * (_cell_size + _gap)),
		Vector2(_cell_size, _cell_size)
	)


func index_at(point: Vector2) -> int:
	var dimension := maxi(3, int(level.get("size", 3)))
	for index in dimension * dimension:
		if cell_rect(index).has_point(point):
			return index
	return -1


func _draw() -> void:
	if level.is_empty() or state.is_empty():
		return
	draw_style_box(PlaygroundUI.style(PlaygroundUI.mix(soft, Color.WHITE, 0.25), 28, PlaygroundUI.mix(accent, Color.WHITE, 0.48), 2, 8, Color(0, 0, 0, 0.12)), Rect2(Vector2.ZERO, size))
	var margin := clampf(minf(size.x, size.y) * 0.035, 12.0, 30.0)
	draw_style_box(PlaygroundUI.style(PlaygroundUI.mix(accent, Color("#25364b"), 0.42), 24, accent.darkened(0.24), 4, 5), _board_rect)
	var dimension := maxi(3, int(level.get("size", 3)))
	var tiles: Array = state.get("tiles", [])
	var hint_index := int(state.get("hintTile", -1))
	for index in dimension * dimension:
		var rect := cell_rect(index)
		if index >= tiles.size():
			continue
		var value := int(tiles[index])
		if value == 0:
			_draw_blank(rect)
			continue
		_draw_tile(rect, value, index == hint_index, index == _press_index and _pressed)
	if str(state.get("phase", "")) == "finished":
		var banner := Rect2(size.x * 0.16, size.y - margin - 74.0, size.x * 0.68, 64.0)
		draw_style_box(PlaygroundUI.style(Color("#fff9ed"), 22, accent, 3, 8, Color(0, 0, 0, 0.16)), banner)
		_text("拼好啦！", banner.get_center(), 26, accent, true)


func _draw_blank(rect: Rect2) -> void:
	draw_style_box(PlaygroundUI.style(Color("#c7d3df"), 18, Color("#71849a"), 3), rect.grow(-2.0))
	var inner := rect.grow(-rect.size.x * 0.10)
	draw_style_box(PlaygroundUI.style(PlaygroundUI.mix(accent, Color.BLACK, 0.20), 13, Color("#d9e2ea"), 2), inner)
	var center := rect.get_center()
	for index in 4:
		var angle := PI * 0.25 + PI * 0.5 * index
		var start := center + Vector2(cos(angle), sin(angle)) * rect.size.x * 0.21
		var finish := center + Vector2(cos(angle), sin(angle)) * rect.size.x * 0.31
		draw_line(start, finish, Color(1, 1, 1, 0.42), maxf(2.0, rect.size.x * 0.025), true)


func _draw_tile(rect: Rect2, value: int, hinted: bool, pressed: bool) -> void:
	var shown := rect.grow(-1.0) if not pressed else rect.grow(-5.0)
	var tint := _tile_tint(value)
	var border := accent.darkened(0.32)
	draw_style_box(PlaygroundUI.style(Color(0, 0, 0, 0.20), 18, Color.TRANSPARENT, 0), Rect2(shown.position + Vector2(0, 5), shown.size).grow(-1.0))
	draw_style_box(PlaygroundUI.style(tint, 18, border, 3, 4), shown)
	if hinted:
		draw_style_box(PlaygroundUI.style(Color(1, 0.93, 0.50, 0.30), 18, Color("#f6cf49"), 5), shown.grow(3.0))
	var inner := shown.grow(-shown.size.x * 0.12)
	draw_style_box(PlaygroundUI.style(PlaygroundUI.mix(tint, Color.WHITE, 0.28), 13), inner)
	if str(level.get("kind", "number")) == "pattern":
		_draw_pattern(inner, value)
		_text(str(value), shown.position + Vector2(shown.size.x * 0.17, shown.size.y * 0.18), maxf(14.0, shown.size.x * 0.17), Color("#fffaf0"), true)
	else:
		_text(str(value), shown.get_center(), maxf(24.0, shown.size.x * 0.45), Color("#fffaf0"), true)
	draw_line(shown.position + Vector2(shown.size.x * 0.16, shown.size.y * 0.13), shown.position + Vector2(shown.size.x * 0.34, shown.size.y * 0.13), Color(1, 1, 1, 0.32), maxf(2.0, shown.size.x * 0.022), true)


func _tile_tint(value: int) -> Color:
	var motif: Array = level.get("motif", [])
	if value > 0 and value <= motif.size() and Color.html_is_valid(str(motif[value - 1])):
		return Color(str(motif[value - 1]))
	var colors := [
		Color("#5c7894"), Color("#6d8ca7"), Color("#7a9bb4"),
		Color("#647d98"), Color("#58768e"), Color("#7391aa"),
		Color("#5e829a"), Color("#7c94ac"), Color("#68869f"),
		Color("#7896a8"), Color("#5d7890"), Color("#7290a8"),
		Color("#637e97"), Color("#7997ad"), Color("#688aa3"), Color("#5f819b"),
	]
	return colors[(value - 1) % colors.size()]


func _draw_pattern(rect: Rect2, value: int) -> void:
	var center := rect.get_center()
	var radius := rect.size.x * 0.28
	var ink := Color(1, 1, 1, 0.38)
	var dark := Color("#2e4053")
	match value % 6:
		0:
			draw_circle(center, radius, ink)
			draw_circle(center + Vector2(rect.size.x * 0.08, rect.size.y * 0.08), radius * 0.62, Color(tint_dark(level, value), 0.55))
		1:
			draw_line(center - Vector2(radius, radius), center + Vector2(radius, radius), ink, maxf(3.0, rect.size.x * 0.055), true)
			draw_line(center - Vector2(radius, -radius), center + Vector2(radius, -radius), dark, maxf(2.0, rect.size.x * 0.035), true)
		2:
			draw_rect(Rect2(center - Vector2(radius, radius), Vector2(radius * 2.0, radius * 2.0)), ink, false, maxf(3.0, rect.size.x * 0.045), true)
		3:
			draw_colored_polygon(PackedVector2Array([
				center + Vector2(0, -radius),
				center + Vector2(radius, radius * 0.75),
				center + Vector2(-radius, radius * 0.75),
			]), ink)
		4:
			for step in 3:
				draw_arc(center, radius * (0.38 + 0.21 * step), 0.25, TAU - 0.4, 18, ink, maxf(2.0, rect.size.x * 0.035), true)
		5:
			draw_arc(center, radius, 0, TAU, 28, ink, maxf(3.0, rect.size.x * 0.05), true)
			draw_circle(center, radius * 0.30, dark)


func tint_dark(_source: Dictionary, _value: int) -> Color:
	return accent.darkened(0.12)


func _gui_input(event: InputEvent) -> void:
	if not interactive or _blocked():
		cancel_gesture()
		return
	if event is InputEventScreenTouch:
		if event.device == InputEvent.DEVICE_ID_EMULATION:
			return
		_last_touch_msec = Time.get_ticks_msec()
		if event.pressed:
			_press_index = index_at(event.position)
			_pressed = _press_index >= 0
		else:
			_release(event.position, event.index)
		accept_event()
	elif event is InputEventScreenDrag:
		_last_touch_msec = Time.get_ticks_msec()
		if _press_index >= 0 and not cell_rect(_press_index).grow(12.0).has_point(event.position):
			_press_index = -1
			_pressed = false
		accept_event()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if Time.get_ticks_msec() - _last_touch_msec < 500:
			return
		if event.pressed:
			_press_index = index_at(event.position)
			_pressed = _press_index >= 0
		else:
			_release(event.position, 0)
		accept_event()
	elif event is InputEventMouseMotion and _pressed:
		if _press_index < 0 or not cell_rect(_press_index).grow(12.0).has_point(event.position):
			_press_index = -1
			_pressed = false
		accept_event()


func _release(point: Vector2, screen_index: int) -> void:
	if not _pressed:
		return
	var released_index := index_at(point)
	var pressed_index := _press_index
	_pressed = false
	_press_index = -1
	queue_redraw()
	if screen_index >= 0 and released_index >= 0 and released_index == pressed_index:
		tile_pressed.emit(released_index)


func _text(value: String, center: Vector2, font_size: float, tint: Color, bold: bool = false) -> void:
	var pixels := maxi(12, int(font_size))
	var font := PlaygroundUI.font()
	var width := font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, pixels).x
	draw_string(font, center + Vector2(-width * 0.5, pixels * 0.35), value, HORIZONTAL_ALIGNMENT_LEFT, -1, pixels, tint)
	if bold:
		draw_string(font, center + Vector2(-width * 0.5 + 1.0, pixels * 0.35 + 1.0), value, HORIZONTAL_ALIGNMENT_LEFT, -1, pixels, Color(0, 0, 0, 0.20))
