class_name MazeField
extends Control

signal direction_selected(direction: String)

const DIRECTIONS := ["up", "down", "left", "right"]
const DIRECTION_NAMES := {
	"up": "上",
	"down": "下",
	"left": "左",
	"right": "右",
}
const MIN_TOUCH := 48.0

var level: Dictionary = {}
var state: Dictionary = {}
var accent := Color("#5d7436")
var soft := Color("#edf2dd")
var interactive := true

var _map_rect := Rect2()
var _origin := Vector2.ZERO
var _cell_size := 1.0
var _dpad_rects: Dictionary = {}
var _press: Dictionary = {}
var _last_touch_msec := -1000


func _ready() -> void:
	custom_minimum_size = Vector2(760, 500)
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
	_press.clear()
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
		_press.clear()
	queue_redraw()


func cancel_gesture() -> void:
	_press.clear()
	queue_redraw()


func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_CLOSE_REQUEST]:
		_press.clear()


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
	_dpad_rects.clear()
	var margin := 12.0
	var gap := 14.0
	var dpad_width := clampf(size.x * 0.205, 190.0, 272.0)
	_map_rect = Rect2(margin, margin, maxf(320.0, size.x - margin * 2.0 - gap - dpad_width), size.y - margin * 2.0)
	var dpad_room := Rect2(
		Vector2(_map_rect.end.x + gap, margin),
		Vector2(dpad_width, size.y - margin * 2.0)
	)
	var width := maxi(5, int(level.get("width", 8)))
	var height := maxi(5, int(level.get("height", 8)))
	var room := Rect2(_map_rect.position + Vector2(18.0, 18.0), _map_rect.size - Vector2(36.0, 36.0))
	_cell_size = maxf(8.0, minf(room.size.x / float(width), room.size.y / float(height)))
	var extent := Vector2(_cell_size * float(width), _cell_size * float(height))
	_origin = room.position + (room.size - extent) * 0.5
	var button := minf(82.0, maxf(MIN_TOUCH, minf(dpad_room.size.x - 24.0, dpad_room.size.y - 24.0) / 3.2))
	var block := button * 3.0 + 10.0 * 2.0
	var start := dpad_room.position + (dpad_room.size - Vector2(block, block)) * 0.5
	var slots := {
		"up": Vector2(1, 0),
		"left": Vector2(0, 1),
		"right": Vector2(2, 1),
		"down": Vector2(1, 2),
	}
	for direction in DIRECTIONS:
		var slot: Vector2 = slots[direction]
		_dpad_rects[direction] = Rect2(
			start + Vector2(slot.x * (button + 10.0), slot.y * (button + 10.0)),
			Vector2(button, button)
		)


func _draw() -> void:
	if level.is_empty() or state.is_empty():
		return
	draw_style_box(PlaygroundUI.style(PlaygroundUI.mix(soft, Color.WHITE, 0.18), 26, PlaygroundUI.mix(accent, Color.WHITE, 0.50), 2, 9, Color(0, 0, 0, 0.10)), Rect2(Vector2.ZERO, size))
	draw_style_box(PlaygroundUI.style(Color("#fffdf5"), 24, PlaygroundUI.mix(accent, Color.WHITE, 0.38), 3), _map_rect)
	var width := int(level.get("width", 0))
	var height := int(level.get("height", 0))
	for y in height:
		for x in width:
			var cell := Vector2i(x, y)
			var rect := Rect2(_origin + Vector2(float(x), float(y)) * _cell_size, Vector2(_cell_size, _cell_size)).grow(-1.0)
			if _is_wall(cell):
				draw_style_box(PlaygroundUI.style(PlaygroundUI.mix(accent, Color("#644f38"), 0.42), 6, accent.darkened(0.2), 1), rect)
			else:
				var tint := Color("#f3f7e8") if (x + y) % 2 == 0 else Color("#eef4df")
				draw_rect(rect, tint)
				if (x + y) % 5 == 0:
					draw_circle(rect.position + Vector2(rect.size.x * 0.24, rect.size.y * 0.24), maxf(1.5, _cell_size * 0.045), Color(accent, 0.13))
	_draw_patrol_paths()
	_draw_checkpoints()
	_draw_goal()
	_draw_keys()
	_draw_doors()
	_draw_stars()
	_draw_patrols()
	_draw_player()
	_draw_dpad()
	_draw_hint()


func _is_wall(cell: Vector2i) -> bool:
	var rows: Array = level.get("layout", [])
	if cell.y < 0 or cell.y >= rows.size():
		return true
	var row := str(rows[cell.y])
	return cell.x < 0 or cell.x >= row.length() or row.substr(cell.x, 1) == "#"


func _cell_rect(cell: Vector2i) -> Rect2:
	return Rect2(_origin + Vector2(float(cell.x), float(cell.y)) * _cell_size, Vector2(_cell_size, _cell_size))


func _draw_patrol_paths() -> void:
	for raw in level.get("patrols", []):
		if not raw is Dictionary:
			continue
		var path: Array = raw.get("path", [])
		for index in range(1, path.size()):
			var first := _cell_rect(_point(path[index - 1])).get_center()
			var second := _cell_rect(_point(path[index])).get_center()
			draw_line(first, second, Color(accent.darkened(0.25), 0.30), maxf(2.0, _cell_size * 0.055), true)
		if path.size() > 1:
			draw_line(_cell_rect(_point(path.back())).get_center(), _cell_rect(_point(path[0])).get_center(), Color(accent.darkened(0.25), 0.18), maxf(1.5, _cell_size * 0.035), true)


func _draw_checkpoints() -> void:
	for raw in level.get("checkpoints", []):
		if not raw is Dictionary:
			continue
		var rect := _cell_rect(_point(raw))
		var active := str(raw.get("id", "")) == str(state.get("checkpointId", ""))
		draw_style_box(PlaygroundUI.style(Color("#fff8cf") if active else Color("#fffdf0"), 10, Color("#d9b84d") if active else PlaygroundUI.mix(accent, Color.WHITE, 0.42), 2), rect.grow(-_cell_size * 0.16))
		var pole := rect.position + Vector2(rect.size.x * 0.34, rect.size.y * 0.25)
		draw_line(pole, pole + Vector2(0, rect.size.y * 0.48), accent.darkened(0.25), maxf(2.0, _cell_size * 0.05), true)
		var flag := PackedVector2Array([
			pole + Vector2(0, 2),
			pole + Vector2(rect.size.x * 0.34, rect.size.y * 0.08),
			pole + Vector2(rect.size.x * 0.34, rect.size.y * 0.25),
			pole + Vector2(0, rect.size.y * 0.20),
		])
		draw_colored_polygon(flag, Color("#efc94c") if not active else Color("#f39a3c"))


func _draw_goal() -> void:
	var rect := _cell_rect(_point(level.get("goal", {})))
	var ready: bool = bool(state.get("_goalReady", false))
	draw_style_box(PlaygroundUI.style(Color("#fff1a9"), 12, Color("#d7ab2f"), 3), rect.grow(-_cell_size * 0.12))
	draw_circle(rect.get_center() + Vector2(0, -rect.size.y * 0.04), rect.size.x * 0.24, Color("#f6d95e"))
	draw_circle(rect.get_center() + Vector2(-rect.size.x * 0.08, -rect.size.y * 0.07), rect.size.x * 0.035, Color("#7a5b22"))
	draw_circle(rect.get_center() + Vector2(rect.size.x * 0.08, -rect.size.y * 0.07), rect.size.x * 0.035, Color("#7a5b22"))
	draw_arc(rect.get_center() + Vector2(0, rect.size.y * 0.03), rect.size.x * 0.11, 0.1, PI - 0.1, 18, Color("#7a5b22"), maxf(1.5, _cell_size * 0.035), true)
	if ready:
		draw_arc(rect.get_center(), rect.size.x * 0.43, 0, TAU, 28, Color("#fff6b0"), maxf(2.0, _cell_size * 0.045), true)


func _draw_keys() -> void:
	var collected: Array = state.get("keysCollected", [])
	for raw in level.get("keys", []):
		if not raw is Dictionary or str(raw.get("id", "")) in collected:
			continue
		var rect := _cell_rect(_point(raw))
		var center := rect.get_center()
		var ring := rect.size.x * 0.16
		draw_arc(center + Vector2(-rect.size.x * 0.10, -rect.size.y * 0.06), ring, 0, TAU, 20, Color("#8c6724"), maxf(2.0, _cell_size * 0.055), true)
		draw_line(center + Vector2(-rect.size.x * 0.01, -rect.size.y * 0.01), center + Vector2(rect.size.x * 0.22, rect.size.y * 0.17), Color("#8c6724"), maxf(2.0, _cell_size * 0.055), true)
		draw_line(center + Vector2(rect.size.x * 0.12, rect.size.y * 0.09), center + Vector2(rect.size.x * 0.18, rect.size.y * 0.03), Color("#8c6724"), maxf(1.5, _cell_size * 0.045), true)
		draw_line(center + Vector2(rect.size.x * 0.18, rect.size.y * 0.15), center + Vector2(rect.size.x * 0.24, rect.size.y * 0.09), Color("#8c6724"), maxf(1.5, _cell_size * 0.045), true)


func _draw_doors() -> void:
	var opened: Array = state.get("doorsOpen", [])
	for raw in level.get("doors", []):
		if not raw is Dictionary:
			continue
		var rect := _cell_rect(_point(raw))
		var is_open := str(raw.get("id", "")) in opened
		var arch := Rect2(rect.position + rect.size * Vector2(0.18, 0.12), rect.size * Vector2(0.64, 0.76))
		if is_open:
			draw_style_box(PlaygroundUI.style(Color("#f7e7bf"), 8, Color("#96713b"), 2), arch)
			draw_rect(Rect2(arch.position + arch.size * Vector2(0.12, 0.16), arch.size * Vector2(0.76, 0.78)), Color("#fffaf0"))
			draw_arc(arch.get_center(), arch.size.x * 0.42, PI, TAU, 18, Color("#96713b"), maxf(2.0, _cell_size * 0.045), true)
		else:
			draw_style_box(PlaygroundUI.style(Color("#e5bf76"), 8, Color("#76542a"), 2), arch)
			draw_circle(arch.get_center() + Vector2(0, -arch.size.y * 0.08), arch.size.x * 0.18, Color("#fff4d2"))
			draw_line(arch.get_center() + Vector2(0, arch.size.y * 0.00), arch.get_center() + Vector2(0, arch.size.y * 0.18), Color("#76542a"), maxf(2.0, _cell_size * 0.05), true)


func _draw_stars() -> void:
	var collected: Array = state.get("starsCollected", [])
	for raw in level.get("stars", []):
		if not raw is Dictionary or str(raw.get("id", "")) in collected:
			continue
		_star(_cell_rect(_point(raw)).get_center(), _cell_size * 0.22, Color("#f2bd32"), Color("#96711c"))


func _draw_patrols() -> void:
	var runtime: Array = state.get("patrols", [])
	var sources: Array = level.get("patrols", [])
	for index in runtime.size():
		if index >= sources.size():
			break
		var path: Array = sources[index].get("path", [])
		var path_index := int(runtime[index].get("index", 0))
		if path_index < 0 or path_index >= path.size():
			continue
		var rect := _cell_rect(_point(path[path_index]))
		var center := rect.get_center()
		draw_circle(center, rect.size.x * 0.33, Color("#f4c95d"))
		draw_circle(center, rect.size.x * 0.25, Color("#e58e43"))
		draw_circle(center + Vector2(-rect.size.x * 0.07, -rect.size.y * 0.04), maxf(1.5, rect.size.x * 0.035), Color("#5f3f25"))
		draw_circle(center + Vector2(rect.size.x * 0.07, -rect.size.y * 0.04), maxf(1.5, rect.size.x * 0.035), Color("#5f3f25"))
		draw_line(center + Vector2(-rect.size.x * 0.08, rect.size.y * 0.08), center + Vector2(rect.size.x * 0.08, rect.size.y * 0.08), Color("#7c4e28"), maxf(1.5, rect.size.x * 0.035), true)


func _draw_player() -> void:
	var cell := _point(state.get("player", {}))
	var rect := _cell_rect(cell)
	var center := rect.get_center()
	_draw_soft_ellipse(center + Vector2(0, rect.size.y * 0.28), Vector2(rect.size.x * 0.27, rect.size.y * 0.10), Color(0.2, 0.18, 0.12, 0.20))
	draw_circle(center + Vector2(0, rect.size.y * 0.10), rect.size.x * 0.22, Color("#79a6c7"))
	draw_circle(center + Vector2(0, -rect.size.y * 0.08), rect.size.x * 0.21, Color("#f0c89e"))
	draw_arc(center + Vector2(0, -rect.size.y * 0.09), rect.size.x * 0.18, PI, TAU, 18, accent.darkened(0.2), maxf(2.0, rect.size.x * 0.045), true)
	draw_circle(center + Vector2(-rect.size.x * 0.07, -rect.size.y * 0.08), maxf(1.4, rect.size.x * 0.026), Color("#503c2d"))
	draw_circle(center + Vector2(rect.size.x * 0.07, -rect.size.y * 0.08), maxf(1.4, rect.size.x * 0.026), Color("#503c2d"))
	draw_line(center + Vector2(-rect.size.x * 0.05, rect.size.y * 0.02), center + Vector2(rect.size.x * 0.05, rect.size.y * 0.02), Color("#7b4f3a"), maxf(1.2, rect.size.x * 0.022), true)


func _draw_dpad() -> void:
	var labels := {"up": "上", "down": "下", "left": "左", "right": "右"}
	for direction in _dpad_rects:
		var rect: Rect2 = _dpad_rects[direction]
		var pressed: bool = str(_press.get("dpad", "")) == direction
		var bg := accent.darkened(0.10) if pressed else accent
		draw_style_box(PlaygroundUI.style(bg, 20, Color.WHITE, 2, 5, Color(0, 0, 0, 0.15)), rect)
		var center := rect.get_center()
		var size := minf(rect.size.x, rect.size.y) * 0.22
		var points := PackedVector2Array()
		match direction:
			"up":
				points = PackedVector2Array([center + Vector2(0, -size), center + Vector2(-size, size * 0.55), center + Vector2(size, size * 0.55)])
			"down":
				points = PackedVector2Array([center + Vector2(0, size), center + Vector2(-size, -size * 0.55), center + Vector2(size, -size * 0.55)])
			"left":
				points = PackedVector2Array([center + Vector2(-size, 0), center + Vector2(size * 0.55, -size), center + Vector2(size * 0.55, size)])
			"right":
				points = PackedVector2Array([center + Vector2(size, 0), center + Vector2(-size * 0.55, -size), center + Vector2(-size * 0.55, size)])
		draw_colored_polygon(points, Color("#fff9e9"))
		_text(str(labels.get(direction, "")), center + Vector2(0, rect.size.y * 0.29), rect.size.y * 0.14, Color("#fff9e9"))


func _draw_hint() -> void:
	var direction := str(state.get("hintDirection", ""))
	if direction.is_empty():
		return
	var cell := _point(state.get("player", {}))
	var center := _cell_rect(cell).get_center()
	var vector: Vector2 = {"up": Vector2(0, -1), "down": Vector2(0, 1), "left": Vector2(-1, 0), "right": Vector2(1, 0)}.get(direction, Vector2.ZERO)
	var tip: Vector2 = center + vector * _cell_size * 0.42
	var side := Vector2(-vector.y, vector.x) * _cell_size * 0.13
	draw_line(center + vector * _cell_size * 0.16, tip, Color("#fff6c9"), maxf(3.0, _cell_size * 0.07), true)
	draw_colored_polygon(PackedVector2Array([tip, tip - vector * _cell_size * 0.18 + side, tip - vector * _cell_size * 0.18 - side]), Color("#fff6c9"))


func _gui_input(event: InputEvent) -> void:
	if not interactive or _blocked():
		_press.clear()
		return
	if event is InputEventScreenTouch:
		if event.device == InputEvent.DEVICE_ID_EMULATION:
			return
		_last_touch_msec = Time.get_ticks_msec()
		if event.pressed:
			_press = _target_at(event.position)
			_press["screenIndex"] = event.index
			_press["start"] = event.position
		else:
			_release(event.position, event.index)
		accept_event()
	elif event is InputEventScreenDrag:
		_last_touch_msec = Time.get_ticks_msec()
		if int(_press.get("screenIndex", -1)) == event.index:
			var start: Vector2 = _press.get("start", event.position)
			if start.distance_to(event.position) > 26.0:
				_press = {"kind": "swipe", "screenIndex": event.index, "start": start}
		accept_event()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if Time.get_ticks_msec() - _last_touch_msec < 500:
			return
		if event.pressed:
			_press = _target_at(event.position)
			_press["screenIndex"] = 0
			_press["start"] = event.position
		else:
			_release(event.position, 0)
		accept_event()
	elif event is InputEventMouseMotion and int(_press.get("screenIndex", -1)) == 0:
		var start: Vector2 = _press.get("start", event.position)
		if start.distance_to(event.position) > 26.0:
			_press = {"kind": "swipe", "screenIndex": 0, "start": start}
		accept_event()


func _target_at(point: Vector2) -> Dictionary:
	for direction in _dpad_rects:
		if _dpad_rects[direction].has_point(point):
			return {"kind": "dpad", "dpad": str(direction)}
	var local := point - _origin
	if local.x < 0.0 or local.y < 0.0:
		return {}
	var width := int(level.get("width", 0))
	var height := int(level.get("height", 0))
	var x := int(floor(local.x / _cell_size))
	var y := int(floor(local.y / _cell_size))
	if x < 0 or y < 0 or x >= width or y >= height:
		return {}
	return {"kind": "cell", "cell": Vector2i(x, y)}


func _release(point: Vector2, screen_index: int) -> void:
	if int(_press.get("screenIndex", -1)) != screen_index:
		return
	var press := _press
	_press.clear()
	if str(press.get("kind", "")) == "swipe":
		var start: Vector2 = press.get("start", point)
		var delta := point - start
		if delta.length() >= 26.0:
			var direction := "right" if delta.x >= 0.0 else "left"
			if absf(delta.y) > absf(delta.x):
				direction = "down" if delta.y >= 0.0 else "up"
			direction_selected.emit(direction)
			queue_redraw()
		return
	var target := _target_at(point)
	if str(target.get("kind", "")) != str(press.get("kind", "")):
		queue_redraw()
		return
	if str(target.get("kind", "")) == "dpad" and str(target.get("dpad", "")) == str(press.get("dpad", "")):
		direction_selected.emit(str(target.get("dpad", "")))
	elif str(target.get("kind", "")) == "cell":
		var player := _point(state.get("player", {}))
		var cell: Vector2i = target.get("cell", player)
		var delta := cell - player
		if absi(delta.x) + absi(delta.y) == 1:
			var direction := ""
			if delta.x < 0:
				direction = "left"
			elif delta.x > 0:
				direction = "right"
			elif delta.y < 0:
				direction = "up"
			else:
				direction = "down"
			direction_selected.emit(direction)
	queue_redraw()


func _star(center: Vector2, radius: float, fill: Color, outline: Color) -> void:
	var points := PackedVector2Array()
	for index in 10:
		var angle := -PI * 0.5 + TAU * float(index) / 10.0
		var length := radius if index % 2 == 0 else radius * 0.44
		points.append(center + Vector2(cos(angle), sin(angle)) * length)
	draw_colored_polygon(points, fill)
	points.append(points[0])
	draw_polyline(points, outline, maxf(1.0, radius * 0.12), true)


func _draw_soft_ellipse(center: Vector2, radii: Vector2, color: Color) -> void:
	var points := PackedVector2Array()
	for index in 28:
		var angle := TAU * float(index) / 28.0
		points.append(center + Vector2(cos(angle) * radii.x, sin(angle) * radii.y))
	draw_colored_polygon(points, color)


func _text(value: String, center: Vector2, font_size: float, tint: Color) -> void:
	var pixels := maxi(11, int(font_size))
	var font := PlaygroundUI.font()
	var width := font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, pixels).x
	draw_string(font, center + Vector2(-width * 0.5, pixels * 0.34), value, HORIZONTAL_ALIGNMENT_LEFT, -1, pixels, tint)


static func _point(value: Variant) -> Vector2i:
	if not value is Dictionary:
		return Vector2i.ZERO
	return Vector2i(int(value.get("x", 0)), int(value.get("y", 0)))
