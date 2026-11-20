class_name ChessBoard
extends Control

signal cell_pressed(position: int)

var rules: ChessRules
var current_side := 0
var selected := -1
var targets: Array = []
var interactive := true
var accent := Color("#167d74")
var face_to_face := false
var _touch_index := -1
var _touch_guard_msec := -1000
var _clock := 0.0
var _pressed_cell := -1
var _preview_cell := -1
var _press_seat := 0
var notice: Dictionary = {}


func _ready() -> void:
	custom_minimum_size = Vector2(520, 420)
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	resized.connect(queue_redraw)


func update_board(value: ChessRules, side: int, selected_position: int, legal: Array) -> void:
	rules = value
	face_to_face = TabletopLayout.enabled("chess", value.state.get("players", []), str(value.state.get("modeId", "classic")))
	current_side = side
	selected = selected_position
	targets = legal.duplicate()
	if not interactive:
		_cancel_press()
	notice = value.state.get("interactionNote", {}).duplicate(true) if value.state.get("interactionNote", {}) is Dictionary else {}
	set_process(selected >= 0 or _pressed_cell >= 0)
	queue_redraw()


func _process(delta: float) -> void:
	if not interactive or TabletopLayout.input_blocked(self):
		_cancel_press()
		return
	_clock += delta
	queue_redraw()
	if selected < 0 and _pressed_cell < 0:
		set_process(false)


func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_WM_CLOSE_REQUEST]:
		_cancel_press()


func _pulse() -> float:
	return 0.5 + 0.5 * sin(_clock * 3.4)


func metrics() -> Dictionary:
	var steps := Vector2(9, 8) if face_to_face else Vector2(8, 9)
	var gap_x := maxf(1.0, (size.x - 84.0) / (steps.x + 1.24))
	var gap_y := maxf(1.0, (size.y - 76.0) / (steps.y + 1.24))
	var extent := Vector2(steps.x * gap_x, steps.y * gap_y)
	var origin := (size - extent) * 0.5
	return {"gap": minf(gap_x, gap_y), "gap_x": gap_x, "gap_y": gap_y, "origin": origin}


func position_for(index: int) -> Vector2:
	var layout := metrics()
	var row := int(index / ChessRules.COLS)
	var col := index % ChessRules.COLS
	var gap_x := float(layout.gap_x)
	var gap_y := float(layout.gap_y)
	var x := (9.0 - float(row)) * gap_x if face_to_face else float(col) * gap_x
	var y := float(col) * gap_y if face_to_face else float(row) * gap_y
	return Vector2(layout.origin) + Vector2(x, y)


func cell_at(point: Vector2) -> int:
	var layout := metrics()
	var gap := float(layout.gap)
	if gap <= 0:
		return -1
	var local: Vector2 = point - layout.origin
	var gap_x := float(layout.gap_x)
	var gap_y := float(layout.gap_y)
	var screen_x := roundi(local.x / gap_x)
	var screen_y := roundi(local.y / gap_y)
	var row := 9 - screen_x if face_to_face else screen_y
	var col := screen_y if face_to_face else screen_x
	if row < 0 or row >= ChessRules.ROWS or col < 0 or col >= ChessRules.COLS:
		return -1
	if absf(local.x - float(screen_x) * gap_x) > gap_x * 0.48 or absf(local.y - float(screen_y) * gap_y) > gap_y * 0.48:
		return -1
	if point.distance_to(position_for(row * ChessRules.COLS + col)) > gap * 0.58:
		return -1
	return row * ChessRules.COLS + col


func audit_bounds() -> Rect2:
	var layout := metrics()
	var steps := Vector2(9, 8) if face_to_face else Vector2(8, 9)
	var gap := Vector2(float(layout.gap_x), float(layout.gap_y))
	return Rect2(Vector2(layout.origin) - gap * 0.62, steps * gap + gap * 1.24)


func is_blank_at(point: Vector2) -> bool:
	return cell_at(point) < 0


func _draw() -> void:
	var layout := metrics()
	var gap := float(layout.gap)
	var origin: Vector2 = layout.origin
	if gap <= 0:
		return
	draw_style_box(PlaygroundUI.style(PlaygroundUI.mix(accent, Color.WHITE, 0.92), 30, PlaygroundUI.mix(accent, Color.WHITE, 0.55), 2), Rect2(Vector2.ZERO, size))
	var board_rect := audit_bounds()
	draw_style_box(PlaygroundUI.style(Color("#fff0cf"), 24, Color("#bc8458"), 3, 6, Color(0, 0, 0, 0.10)), board_rect)
	_draw_grid(origin, gap)
	_draw_palaces(origin, gap)
	_draw_river(origin, float(layout.gap_x), gap)
	if rules != null and not rules.state.get("lastMove", {}).is_empty():
		var last: Dictionary = rules.state.lastMove
		if last.has("from") and last.has("to"):
			draw_line(position_for(int(last.from)), position_for(int(last.to)), Color(0.95, 0.66, 0.18, 0.45), maxf(3.0, gap * 0.045), true)
	var pieces: Array = rules.state.get("pieces", []) if rules != null else []
	for piece in pieces:
		if piece is Dictionary and int(piece.get("position", -1)) >= 0:
			_draw_piece(piece, gap)
	_draw_move_hints(gap)
	_draw_board_feedback(gap)
	if rules != null:
		TabletopLayout.draw_turn_marks(self, rules.state.get("players", []), current_side, face_to_face, [Color("#b23b32"), Color("#29313a")], str(rules.state.get("phase", "")) == "finished")
	if rules != null and rules.state.get("phase", "") == "finished":
		var panel := Rect2(size.x * 0.20, size.y * 0.44, size.x * 0.60, size.y * 0.12)
		draw_style_box(PlaygroundUI.style(Color("#fff9e9"), 24, accent, 3, 8, Color(0, 0, 0, 0.18)), panel)
		_text(str(rules.state.get("reason", "本局结束")), panel.get_center(), maxf(20.0, gap * 0.33), accent)


func _draw_grid(_origin: Vector2, gap: float) -> void:
	var line_color := Color("#8e5737")
	var width := maxf(1.5, gap * 0.022)
	for row in ChessRules.ROWS:
		draw_line(position_for(row * ChessRules.COLS), position_for(row * ChessRules.COLS + 8), line_color, width, true)
	for col in ChessRules.COLS:
		if col == 0 or col == ChessRules.COLS - 1:
			draw_line(position_for(col), position_for(81 + col), line_color, width, true)
		else:
			draw_line(position_for(col), position_for(36 + col), line_color, width, true)
			draw_line(position_for(45 + col), position_for(81 + col), line_color, width, true)


func _draw_palaces(_origin: Vector2, gap: float) -> void:
	var line_color := Color("#8e5737")
	var width := maxf(1.5, gap * 0.022)
	for row in [0, 7]:
		draw_line(position_for(int(row) * 9 + 3), position_for((int(row) + 2) * 9 + 5), line_color, width, true)
		draw_line(position_for(int(row) * 9 + 5), position_for((int(row) + 2) * 9 + 3), line_color, width, true)


func _draw_river(origin: Vector2, gap_x: float, gap: float) -> void:
	var center := (position_for(4 * ChessRules.COLS + 4) + position_for(5 * ChessRules.COLS + 4)) * 0.5
	if face_to_face:
		for side in 2:
			var label_center := center + Vector2(0, gap * (-2.15 if side == 0 else 2.15))
			draw_set_transform(label_center, TabletopLayout.facing_angle(side), Vector2.ONE)
			_text("楚 河" if side == 0 else "汉 界", Vector2.ZERO, gap * 0.26, Color("#9a5b3b"))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		center = (position_for(4 * ChessRules.COLS + 4) + position_for(5 * ChessRules.COLS + 4)) * 0.5
		_text("楚 河", center + Vector2(-gap_x * 2.0, 0), gap * 0.28, Color("#9a5b3b"))
		_text("汉 界", center + Vector2(gap_x * 2.0, 0), gap * 0.28, Color("#9a5b3b"))


func _draw_piece(piece: Dictionary, gap: float) -> void:
	var center := position_for(int(piece.position))
	var side := int(piece.get("side", 0))
	var tint := Color("#b23b32") if side == 0 else Color("#29313a")
	var radius := gap * 0.44
	var text_angle := TabletopLayout.facing_angle(side, face_to_face)
	if str(piece.kind) == "general" and rules.in_check(side) and str(rules.state.get("phase", "")) == "playing":
		draw_circle(center, radius * 1.25, Color(0.88, 0.22, 0.18, 0.15))
		draw_arc(center, radius * 1.25, 0.0, TAU, 44, Color("#c83c32"), 4.0, true)
	if int(piece.position) == selected:
		draw_circle(center, radius * 1.20, Color(0.95, 0.74, 0.25, 0.30))
		draw_arc(center, radius * 1.18, 0, TAU, 40, Color("#e4ac28"), maxf(3.0, gap * 0.04), true)
	draw_circle(center + Vector2(0, gap * 0.045), radius, Color(0, 0, 0, 0.16))
	draw_circle(center, radius, Color("#fffaf0"))
	draw_arc(center, radius, 0, TAU, 48, tint, maxf(2.5, gap * 0.035), true)
	draw_arc(center, radius * 0.86, 0, TAU, 48, tint, maxf(1.0, gap * 0.012), true)
	draw_set_transform(center, text_angle, Vector2.ONE)
	_text(engine_name(piece), Vector2.ZERO, maxf(18.0, gap * 0.48), tint)
	if str(piece.kind) == "general" and rules.in_check(side) and str(rules.state.get("phase", "")) == "playing":
		_text("将军", Vector2(0.0, -radius * 1.42), maxf(14.0, gap * 0.19), Color("#b23b32"))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_board_feedback(gap: float) -> void:
	if rules == null:
		return
	for value in notice.get("cells", []):
		var index := int(value)
		if index >= 0 and index < ChessRules.CELLS:
			draw_arc(position_for(index), gap * 0.52, 0, TAU, 40, Color("#c67c20"), 3.0, true)
	var last: Dictionary = rules.state.get("lastMove", {})
	if last.has("to"):
		draw_arc(position_for(int(last.to)), gap * 0.29, 0, TAU, 32, Color("#d5a02e"), 3.0, true)
	if _preview_cell >= 0:
		var center := position_for(_preview_cell)
		draw_arc(center, gap * 0.57, 0, TAU, 40, accent, 4.0, true)
		var piece := rules.piece_at(_preview_cell)
		var message := rules.piece_hint(piece) if not piece.is_empty() and int(piece.side) == current_side else str(rules.explain_move(selected, _preview_cell).message)
		TabletopLayout.draw_note(self, center, message, TabletopLayout.facing_angle(_press_seat, face_to_face), accent)
	elif not str(notice.get("message", "")).is_empty():
		var cells: Array = notice.get("cells", [])
		var anchor := position_for(int(cells[0])) if not cells.is_empty() and int(cells[0]) in range(ChessRules.CELLS) else size * 0.5
		TabletopLayout.draw_note(self, anchor, str(notice.message), TabletopLayout.facing_angle(int(notice.get("side", current_side)), face_to_face), accent)


func engine_name(piece: Dictionary) -> String:
	if rules == null:
		return ""
	return rules.piece_name(piece)


func _draw_move_hints(gap: float) -> void:
	if rules == null or selected < 0 or targets.is_empty():
		return
	var piece := rules.piece_at(selected)
	if piece.is_empty():
		return
	var start := position_for(selected)
	var kind := str(piece.get("kind", ""))
	var route_color := accent
	route_color.a = 0.30
	var pulse := _pulse()
	draw_arc(start, gap * (0.53 + 0.03 * pulse), 0, TAU, 44, Color("#e4ac28"), 4.0, true)
	for value in targets:
		var target := int(value)
		var finish := position_for(target)
		match kind:
			"horse":
				_draw_horse_route(start, finish, gap, route_color)
			"elephant":
				_draw_elephant_route(start, finish, gap, route_color)
			"chariot", "cannon":
				draw_line(start, finish, route_color, maxf(2.0, gap * 0.045), true)
			"advisor", "general":
				draw_line(start, finish, route_color, maxf(2.0, gap * 0.05), true)
			"soldier":
				_draw_arrow(start, finish, route_color, maxf(2.5, gap * 0.055), gap * 0.13)
			_:
				draw_line(start, finish, route_color, maxf(2.0, gap * 0.045), true)
		_draw_target_marker(finish, not rules.piece_at(target).is_empty(), gap, pulse)


func _draw_horse_route(start: Vector2, finish: Vector2, gap: float, tint: Color) -> void:
	var rect := Rect2(Vector2(minf(start.x, finish.x), minf(start.y, finish.y)), (finish - start).abs())
	var strong := Color(tint.r, tint.g, tint.b, minf(1.0, tint.a + 0.34))
	draw_rect(rect, strong, false, maxf(2.5, gap * 0.042))
	var middle := rect.get_center()
	if absf(finish.x - start.x) >= absf(finish.y - start.y):
		draw_line(Vector2(middle.x, rect.position.y), Vector2(middle.x, rect.end.y), strong, maxf(2.2, gap * 0.036), true)
	else:
		draw_line(Vector2(rect.position.x, middle.y), Vector2(rect.end.x, middle.y), strong, maxf(2.2, gap * 0.036), true)
	var glyph := Color(tint.r, tint.g, tint.b, 0.92)
	_text("日", middle, gap * 0.36, glyph)


func _draw_elephant_route(start: Vector2, finish: Vector2, gap: float, tint: Color) -> void:
	var rect := Rect2(Vector2(minf(start.x, finish.x), minf(start.y, finish.y)), (finish - start).abs())
	var strong := Color(tint.r, tint.g, tint.b, minf(1.0, tint.a + 0.34))
	draw_rect(rect, strong, false, maxf(2.5, gap * 0.042))
	var middle := rect.get_center()
	draw_line(Vector2(middle.x, rect.position.y), Vector2(middle.x, rect.end.y), strong, maxf(2.2, gap * 0.034), true)
	draw_line(Vector2(rect.position.x, middle.y), Vector2(rect.end.x, middle.y), strong, maxf(2.2, gap * 0.034), true)
	_text("田", middle, gap * 0.36, Color(tint.r, tint.g, tint.b, 0.92))


func _draw_arrow(start: Vector2, finish: Vector2, tint: Color, width: float, head: float) -> void:
	draw_line(start, finish, tint, width, true)
	var direction := (finish - start).normalized()
	if direction.is_zero_approx():
		return
	var side := Vector2(-direction.y, direction.x)
	draw_colored_polygon(PackedVector2Array([
		finish,
		finish - direction * head + side * head * 0.55,
		finish - direction * head - side * head * 0.55,
	]), tint)


func _draw_target_marker(center: Vector2, captured: bool, gap: float, pulse: float) -> void:
	var red := Color("#e04b3f")
	if captured:
		draw_circle(center, gap * (0.55 + 0.025 * pulse), Color(red, 0.10))
		draw_arc(center, gap * (0.53 + 0.025 * pulse), 0, TAU, 40, red, maxf(3.0, gap * 0.05), true)
		draw_circle(center + Vector2(0, -gap * 0.52), gap * 0.075, red)
	else:
		draw_circle(center, gap * (0.25 + 0.025 * pulse), Color(red, 0.16))
		draw_circle(center, gap * (0.13 + 0.012 * pulse), red)
		draw_circle(center, gap * 0.045, Color("#fff7df"))


func _text(value: String, center: Vector2, font_size: float, tint: Color) -> void:
	var pixels := maxi(12, int(font_size))
	var font := PlaygroundUI.font()
	var width := font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, pixels).x
	draw_string(font, center + Vector2(-width * 0.5, pixels * 0.35), value, HORIZONTAL_ALIGNMENT_LEFT, -1, pixels, tint)


func _gui_input(event: InputEvent) -> void:
	if not interactive or TabletopLayout.input_blocked(self):
		_cancel_press()
		return
	if event is InputEventScreenTouch:
		_touch_guard_msec = Time.get_ticks_msec()
		if event.pressed and _touch_index >= 0 and event.index != _touch_index:
			return
		if not event.pressed and event.index != _touch_index:
			return
		if event.pressed:
			_touch_index = event.index
			_begin_press(event.position)
		else:
			_touch_index = -1
			if event.canceled:
				_cancel_press()
			else:
				_finish_press(event.position)
	elif event is InputEventScreenDrag:
		_touch_guard_msec = Time.get_ticks_msec()
		if event.index == _touch_index:
			_move_press(event.position)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if Time.get_ticks_msec() - _touch_guard_msec < 500:
			return
		if event.pressed:
			_begin_press(event.position)
		else:
			_finish_press(event.position)
	elif event is InputEventMouseMotion and _pressed_cell >= 0:
		_move_press(event.position)
	else:
		return
	accept_event()


func _begin_press(point: Vector2) -> void:
	_pressed_cell = cell_at(point)
	_preview_cell = _pressed_cell
	_press_seat = current_side
	TabletopLayout.remember_seat(self, _press_seat)
	set_process(true)
	queue_redraw()


func _move_press(point: Vector2) -> void:
	_preview_cell = _pressed_cell if cell_at(point) == _pressed_cell else -1
	queue_redraw()


func _finish_press(point: Vector2) -> void:
	var target := cell_at(point)
	var commit := _pressed_cell >= 0 and target == _pressed_cell and not TabletopLayout.input_blocked(self)
	_cancel_press()
	if commit:
		cell_pressed.emit(target)


func _cancel_press() -> void:
	_touch_index = -1
	_pressed_cell = -1
	_preview_cell = -1
	queue_redraw()
