class_name TangramBoard
extends Control

signal piece_selected(index: int)
signal piece_placed(index: int, position: Vector2)

const PIECE_NAMES := {
	"large_triangle": "大三角",
	"medium_triangle": "中三角",
	"small_triangle": "小三角",
	"square": "正方形",
	"parallelogram": "平行四边形",
}
const PIECE_COLORS := [
	Color("#c86549"), Color("#d98462"), Color("#e0ad63"),
	Color("#83a56a"), Color("#6f9eab"), Color("#8f7fb4"), Color("#c47b8d"),
]
const TAP_SLOP := 12.0

var level: Dictionary = {}
var state: Dictionary = {}
var accent := Color("#b85c38")
var interactive := true
var selected := -1
var hint_slot := -1

var _board_rect := Rect2()
var _tray_rect := Rect2()
var _tray_rects: Array = []
var _tray_indices: Array = []
var _drag_index := -1
var _drag_pos := Vector2.ZERO
var _drag_start := Vector2.ZERO
var _pending_place := -1
var _pending_pos := Vector2.ZERO
var _touch_index := -1
var _last_touch_msec := -1000
var _clock := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	resized.connect(_layout)
	_layout()
	set_process(true)


func set_level(value: Dictionary) -> void:
	level = value.duplicate(true)
	queue_redraw()


func set_state(value: Dictionary) -> void:
	state = value.duplicate(true)
	selected = int(state.get("selected", -1))
	hint_slot = int(state.get("hintSlot", -1))
	_layout()
	queue_redraw()


func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_CLOSE_REQUEST]:
		_cancel_gesture()


func _layout() -> void:
	var tray_width := clampf(size.x * 0.27, 210.0, 330.0)
	var gap := 12.0
	var margin := 12.0
	_board_rect = Rect2(margin, margin, maxf(1.0, size.x - tray_width - gap - margin * 2.0), maxf(1.0, size.y - margin * 2.0))
	_tray_rect = Rect2(size.x - tray_width - margin, margin, tray_width, maxf(1.0, size.y - margin * 2.0))
	_tray_rects.clear()
	_tray_indices.clear()
	var unplaced: Array = []
	for entry in state.get("pieces", []):
		if entry is Dictionary and not bool(entry.get("placed", false)):
			unplaced.append(int(entry.get("index", -1)))
	var columns := 2
	var rows := maxi(1, ceili(float(unplaced.size()) / float(columns)))
	var cell_gap := 8.0
	var cell_width := (_tray_rect.size.x - 20.0 - cell_gap) / 2.0
	var cell_height := minf(112.0, (_tray_rect.size.y - 20.0 - cell_gap * float(rows - 1)) / float(rows))
	for index in unplaced.size():
		var column := index % columns
		var row := int(index / columns)
		_tray_rects.append(Rect2(
			_tray_rect.position + Vector2(10.0 + column * (cell_width + cell_gap), 10.0 + row * (cell_height + cell_gap)),
			Vector2(cell_width, cell_height)
		))
		_tray_indices.append(int(unplaced[index]))
	queue_redraw()


func _process(delta: float) -> void:
	_clock += delta
	if hint_slot >= 0 and not _blocked():
		queue_redraw()


func _blocked() -> bool:
	var owner := get_parent()
	while owner != null:
		if owner is NativeGameScreen:
			return owner.is_input_blocked()
		owner = owner.get_parent()
	return false


func _gui_input(event: InputEvent) -> void:
	if not interactive or _blocked():
		return
	if event is InputEventScreenTouch:
		if event.device == InputEvent.DEVICE_ID_EMULATION:
			return
		_last_touch_msec = Time.get_ticks_msec()
		if event.pressed:
			_press(event.position, event.index)
		else:
			_release(event.position)
		accept_event()
	elif event is InputEventScreenDrag:
		_last_touch_msec = Time.get_ticks_msec()
		if event.index == _touch_index:
			_drag(event.position)
		accept_event()
	elif event is InputEventMouse:
		if event.device == InputEvent.DEVICE_ID_EMULATION or Time.get_ticks_msec() - _last_touch_msec < 200:
			return
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_press(event.position, 0)
			else:
				_release(event.position)
			accept_event()
		elif event is InputEventMouseMotion and _touch_index == 0:
			_drag(event.position)
			accept_event()


func _press(position: Vector2, touch_index: int) -> void:
	_touch_index = touch_index
	_drag_start = position
	_pending_place = -1
	var tray_index := _tray_hit(position)
	if tray_index >= 0:
		_drag_index = tray_index
		_drag_pos = position
		selected = tray_index
		piece_selected.emit(tray_index)
		queue_redraw()
		return
	var placed_index := _placed_hit(position)
	if placed_index >= 0:
		_drag_index = placed_index
		_drag_pos = position
		selected = placed_index
		piece_selected.emit(placed_index)
		queue_redraw()
		return
	if _board_rect.has_point(position) and selected >= 0:
		_pending_place = selected
		_pending_pos = position


func _drag(position: Vector2) -> void:
	_drag_pos = position
	if _pending_place >= 0 and position.distance_to(_drag_start) > TAP_SLOP:
		_pending_place = -1
	queue_redraw()


func _release(position: Vector2) -> void:
	if _drag_index >= 0 and _board_rect.has_point(position):
		if position.distance_to(_drag_start) > TAP_SLOP:
			piece_placed.emit(_drag_index, _normalized(position))
	elif _pending_place >= 0 and _board_rect.has_point(position):
		piece_placed.emit(_pending_place, _normalized(position))
	_pending_place = -1
	_drag_index = -1
	_touch_index = -1
	queue_redraw()


func cancel_gesture() -> void:
	_cancel_gesture()


func _cancel_gesture() -> void:
	_drag_index = -1
	_pending_place = -1
	_touch_index = -1
	queue_redraw()


func _tray_hit(position: Vector2) -> int:
	for index in _tray_rects.size():
		if _tray_rects[index].has_point(position):
			return int(_tray_indices[index])
	return -1


func _placed_hit(position: Vector2) -> int:
	for entry in state.get("pieces", []):
		if not entry is Dictionary or not bool(entry.get("placed", false)):
			continue
		var center := _board_point(float(entry.get("x", 0.0)), float(entry.get("y", 0.0)))
		if center.distance_to(position) <= 86.0:
			return int(entry.get("index", -1))
	return -1


func _normalized(position: Vector2) -> Vector2:
	return Vector2(
		clampf((position.x - _board_rect.position.x) / maxf(1.0, _board_rect.size.x), 0.0, 1.0),
		clampf((position.y - _board_rect.position.y) / maxf(1.0, _board_rect.size.y), 0.0, 1.0)
	)


func _board_point(x_value: float, y_value: float) -> Vector2:
	return _board_rect.position + Vector2(x_value, y_value) * _board_rect.size


func _draw() -> void:
	draw_style_box(PlaygroundUI.style(PlaygroundUI.mix(accent, Color.WHITE, 0.90), 26, PlaygroundUI.mix(accent, Color.WHITE, 0.45), 2, 6, Color(0, 0, 0, 0.10)), Rect2(Vector2.ZERO, size))
	draw_style_box(PlaygroundUI.style(Color("#fffaf0"), 22, PlaygroundUI.mix(accent, Color.WHITE, 0.50), 2), _board_rect)
	_draw_target()
	_draw_placed()
	_draw_tray()
	_draw_ghost()
	_draw_text_hints()


func _draw_target() -> void:
	var targets: Array = level.get("targetPieces", [])
	var unit := minf(_board_rect.size.x, _board_rect.size.y)
	for index in targets.size():
		var target: Dictionary = targets[index]
		var center := _board_point(float(target.get("x", 0.5)), float(target.get("y", 0.5)))
		var color := PlaygroundUI.mix(accent, Color.WHITE, 0.74)
		if index == hint_slot:
			var pulse := 1.0 + sin(_clock * 5.0) * 0.08
			draw_circle(center, unit * 0.19 * pulse, Color(accent, 0.18))
			draw_arc(center, unit * 0.19 * pulse, 0, TAU, 40, Color(accent, 0.72), 4.0, true)
		var target_points := _piece_polygon(str(target.get("kind", "square")), center, unit, int(target.get("rotation", 0)), bool(target.get("mirror", false)))
		draw_colored_polygon(target_points, color)
		var target_outline := target_points.duplicate()
		target_outline.append(target_points[0])
		draw_polyline(target_outline, Color(accent, 0.22), 1.5, true)
	var title := str(level.get("title", "七巧板"))
	var font := PlaygroundUI.font()
	draw_string(font, _board_rect.position + Vector2(18, 27), "轮廓：" + title, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, PlaygroundUI.mix(accent, PlaygroundUI.INK_SOFT, 0.25))
	if targets.is_empty():
		draw_string(font, _board_rect.position + Vector2(18, 62), "这一关还没有内容", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, PlaygroundUI.INK_SOFT)


func _draw_placed() -> void:
	var unit := minf(_board_rect.size.x, _board_rect.size.y)
	for entry in state.get("pieces", []):
		if not entry is Dictionary or not bool(entry.get("placed", false)):
			continue
		var index := int(entry.get("index", -1))
		var center := _board_point(float(entry.get("x", 0.5)), float(entry.get("y", 0.5)))
		var color: Color = PIECE_COLORS[index % PIECE_COLORS.size()]
		var points := _piece_polygon(str(entry.get("kind", "square")), center, unit, int(entry.get("rotation", 0)), bool(entry.get("mirror", false)))
		draw_colored_polygon(points, color)
		var outline := points.duplicate()
		outline.append(points[0])
		draw_polyline(outline, Color(1, 1, 1, 0.72), 2.0, true)
		if index == selected:
			draw_polyline(outline, Color("#fff1a8"), 5.0, true)


func _draw_tray() -> void:
	draw_style_box(PlaygroundUI.style(PlaygroundUI.mix(accent, Color.WHITE, 0.94), 20, PlaygroundUI.mix(accent, Color.WHITE, 0.55), 1), _tray_rect)
	draw_string(PlaygroundUI.font(), _tray_rect.position + Vector2(12, 27), "七块小积木", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, PlaygroundUI.mix(accent, PlaygroundUI.INK_SOFT, 0.2))
	_tray_rects.clear()
	_tray_indices.clear()
	var unplaced: Array = []
	for entry in state.get("pieces", []):
		if entry is Dictionary and not bool(entry.get("placed", false)):
			unplaced.append(int(entry.get("index", -1)))
	var columns := 2
	var rows := maxi(1, ceili(float(unplaced.size()) / float(columns)))
	var gap := 8.0
	var cell_width := (_tray_rect.size.x - 20.0 - gap) / 2.0
	var cell_height := minf(112.0, (_tray_rect.size.y - 20.0 - gap * float(rows - 1)) / float(rows))
	for index in unplaced.size():
		var column := index % columns
		var row := int(index / columns)
		var rect := Rect2(_tray_rect.position + Vector2(10.0 + column * (cell_width + gap), 10.0 + row * (cell_height + gap)), Vector2(cell_width, cell_height))
		_tray_rects.append(rect)
		_tray_indices.append(int(unplaced[index]))
		var piece_index := int(unplaced[index])
		var piece: Dictionary = _piece(piece_index)
		var selected_now := piece_index == selected
		draw_style_box(PlaygroundUI.style(PlaygroundUI.mix(accent, Color.WHITE, 0.82 if selected_now else 0.94), 14, accent if selected_now else PlaygroundUI.TOOL_LINE, 2 if selected_now else 1), rect)
		var unit := minf(rect.size.x, rect.size.y) * 0.95
		var center := rect.position + Vector2(rect.size.x * 0.5, rect.size.y * 0.43)
		draw_colored_polygon(_piece_polygon(str(piece.get("kind", "square")), center, unit, int(piece.get("rotation", 0)), bool(piece.get("mirror", false))), PIECE_COLORS[piece_index % PIECE_COLORS.size()])
		draw_string(PlaygroundUI.font(), rect.position + Vector2(8, rect.size.y - 8), str(PIECE_NAMES.get(str(piece.get("kind", "")), "积木")), HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 16, 13, PlaygroundUI.INK_SOFT)


func _draw_ghost() -> void:
	if _drag_index < 0:
		return
	var piece: Dictionary = _piece(_drag_index)
	if piece.is_empty():
		return
	var unit := minf(_board_rect.size.x, _board_rect.size.y) * 0.72
	var points := _piece_polygon(str(piece.get("kind", "square")), _drag_pos, unit, int(piece.get("rotation", 0)), bool(piece.get("mirror", false)))
	var color: Color = PIECE_COLORS[_drag_index % PIECE_COLORS.size()]
	color.a = 0.62
	draw_colored_polygon(points, color)
	var outline := points.duplicate()
	outline.append(points[0])
	draw_polyline(outline, Color(accent, 0.65), 2.0, true)


func _draw_text_hints() -> void:
	if _pending_place >= 0:
		draw_string(PlaygroundUI.font(), _board_rect.position + Vector2(18, _board_rect.size.y - 18), "松手放到轮廓上", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, accent)


func _piece(index: int) -> Dictionary:
	var values: Array = state.get("pieces", [])
	if index < 0 or index >= values.size() or not values[index] is Dictionary:
		return {}
	return values[index]


func _piece_polygon(kind: String, center: Vector2, scale: float, rotation: int, mirror: bool) -> PackedVector2Array:
	var points := PackedVector2Array()
	for point in _shape(kind):
		var transformed := point * scale
		if mirror:
			transformed.x = -transformed.x
		transformed = transformed.rotated(float(rotation) * PI * 0.5)
		points.append(center + transformed)
	return points


func _shape(kind: String) -> PackedVector2Array:
	match kind:
		"large_triangle":
			return PackedVector2Array([Vector2(-0.20, 0.12), Vector2(0.20, 0.12), Vector2(0.0, -0.30)])
		"medium_triangle":
			return PackedVector2Array([Vector2(-0.15, 0.09), Vector2(0.15, 0.09), Vector2(0.0, -0.22)])
		"small_triangle":
			return PackedVector2Array([Vector2(-0.11, 0.07), Vector2(0.11, 0.07), Vector2(0.0, -0.16)])
		"square":
			return PackedVector2Array([Vector2(-0.12, -0.12), Vector2(0.12, -0.12), Vector2(0.12, 0.12), Vector2(-0.12, 0.12)])
		"parallelogram":
			return PackedVector2Array([Vector2(-0.17, 0.08), Vector2(0.03, 0.08), Vector2(0.17, -0.08), Vector2(-0.03, -0.08)])
	return PackedVector2Array([Vector2(-0.12, -0.12), Vector2(0.12, -0.12), Vector2(0.12, 0.12), Vector2(-0.12, 0.12)])
