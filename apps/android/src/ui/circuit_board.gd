class_name CircuitBoard
extends Control

signal part_tapped(index: int)
signal hint_requested

const TAP_SLOP := 14.0
const DOCK_HEIGHT := 62.0
const COPPER := Color("#a55b2a")
const COPPER_DARK := Color("#6d3b20")
const COPPER_LIGHT := Color("#e9c09a")
const LIVE := Color("#e4a72d")
const LIVE_LIGHT := Color("#fff1a8")
const PAPER := Color("#fffaf0")
const PAPER_DEEP := Color("#f3dfc7")
const SAFE_GREEN := Color("#4c956f")

var engine: CircuitRules
var accent := COPPER
var soft := Color("#f6e7d9")
var interactive := true
var selected := -1
var fault_index := -1
var hint_index := -1

var _touch_index := -1
var _press_point := Vector2.ZERO
var _pressing := false
var _last_touch_msec := -1000
var _clock := 0.0
var _style_cache := {}
var _redraw_accumulator := 0.0
var _dock: HBoxContainer
var _dock_label: Label
var _hint_button: Button
var _last_powered_goals := {}
var _goal_celebrate_at := {}


func _ready() -> void:
	custom_minimum_size = Vector2(540, 430)
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	set_process(true)
	resized.connect(_on_resized)
	_build_tool_dock()


func bind(value: CircuitRules) -> void:
	engine = value
	selected = -1
	fault_index = engine.fault_index() if engine != null else -1
	hint_index = engine.hint_index() if engine != null else -1
	_last_powered_goals.clear()
	_goal_celebrate_at.clear()
	if engine != null:
		for index in engine.goal_count():
			_last_powered_goals[index] = engine.goal_is_powered(index)
			if engine.goal_is_powered(index):
				_goal_celebrate_at[index] = _clock - 0.8
	_sync_dock()
	queue_redraw()


func set_interactive(value: bool) -> void:
	interactive = value
	_redraw_accumulator = 0.0
	if is_instance_valid(_hint_button):
		_hint_button.disabled = not value
	queue_redraw()


func set_feedback(value_fault: int, value_hint: int) -> void:
	fault_index = value_fault
	hint_index = value_hint
	queue_redraw()


func cancel_gesture() -> void:
	_touch_index = -1
	_pressing = false


func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_WM_CLOSE_REQUEST]:
		cancel_gesture()


func _on_resized() -> void:
	_style_cache.clear()
	_layout_dock()
	queue_redraw()


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	if not interactive:
		return
	_clock += delta
	if engine != null:
		for index in engine.goal_count():
			var powered := engine.goal_is_powered(index)
			if powered and not bool(_last_powered_goals.get(index, false)):
				_goal_celebrate_at[index] = _clock
			_last_powered_goals[index] = powered
	_redraw_accumulator += delta
	var interval := 1.0 / 60.0 if engine != null and engine.powered_goal_count() > 0 else 1.0 / 30.0
	if _redraw_accumulator >= interval:
		_redraw_accumulator = 0.0
		queue_redraw()


func metrics() -> Dictionary:
	if engine == null or engine.width() <= 0 or engine.height() <= 0:
		return {"cell": 1.0, "gap": 0.0, "origin": Vector2.ZERO, "extent": Vector2.ONE, "board_height": size.y - DOCK_HEIGHT}
	var board_height := maxf(190.0, size.y - DOCK_HEIGHT)
	var horizontal_margin := clampf(size.x * 0.055, 22.0, 46.0)
	var top_margin := 34.0 if board_height >= 330.0 else 24.0
	var bottom_margin := 18.0
	var available := Vector2(
		maxf(40.0, size.x - horizontal_margin * 2.0),
		maxf(40.0, board_height - top_margin - bottom_margin)
	)
	var columns := engine.width()
	var rows := engine.height()
	var rough_cell := minf(available.x / float(columns + 0.25), available.y / float(rows + 0.25))
	var gap := clampf(rough_cell * 0.08, 3.0, 10.0)
	var cell := minf(
		(available.x - gap * float(maxi(0, columns - 1))) / float(columns),
		(available.y - gap * float(maxi(0, rows - 1))) / float(rows)
	)
	var extent := Vector2(
		cell * float(columns) + gap * float(maxi(0, columns - 1)),
		cell * float(rows) + gap * float(maxi(0, rows - 1))
	)
	var origin := Vector2(
		(size.x - extent.x) * 0.5,
		top_margin + maxf(0.0, (available.y - extent.y) * 0.5)
	)
	return {
		"cell": cell,
		"gap": gap,
		"origin": origin,
		"extent": extent,
		"board_height": board_height,
	}


func cell_center(x: int, y: int) -> Vector2:
	var layout := metrics()
	var cell := float(layout.cell)
	var gap := float(layout.gap)
	var origin: Vector2 = layout.origin
	return origin + Vector2(
		float(x) * (cell + gap) + cell * 0.5,
		float(y) * (cell + gap) + cell * 0.5
	)


func cell_at(point: Vector2) -> Vector2i:
	if engine == null:
		return Vector2i(-1, -1)
	var layout := metrics()
	var cell := float(layout.cell)
	if cell <= 1.0:
		return Vector2i(-1, -1)
	var local := point - Vector2(layout.origin)
	var stride := cell + float(layout.gap)
	var column := int(floor(local.x / stride))
	var row := int(floor(local.y / stride))
	if column < 0 or column >= engine.width() or row < 0 or row >= engine.height():
		return Vector2i(-1, -1)
	var within := Vector2(local.x - float(column) * stride, local.y - float(row) * stride)
	if within.x > cell or within.y > cell:
		return Vector2i(-1, -1)
	return Vector2i(column, row)


func _gui_input(event: InputEvent) -> void:
	if not interactive or _blocked():
		cancel_gesture()
		return
	if event is InputEventScreenTouch:
		if event.device == InputEvent.DEVICE_ID_EMULATION:
			return
		_last_touch_msec = Time.get_ticks_msec()
		if event.index != _touch_index and not event.pressed:
			return
		if event.pressed:
			_touch_index = event.index
			_pressing = true
			_press_point = event.position
		else:
			_finish_tap(_touch_index, event.position, event.canceled)
			_touch_index = -1
		accept_event()
	elif event is InputEventScreenDrag:
		_last_touch_msec = Time.get_ticks_msec()
		if event.index == _touch_index and _press_point.distance_to(event.position) > TAP_SLOP:
			_pressing = false
		accept_event()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if Time.get_ticks_msec() - _last_touch_msec < 500:
			return
		if event.pressed:
			_pressing = true
			_press_point = event.position
		else:
			_finish_tap(0, event.position, false)
		accept_event()
	elif event is InputEventMouseMotion and _pressing:
		if _press_point.distance_to(event.position) > TAP_SLOP:
			_pressing = false
		accept_event()


func _finish_tap(index: int, point: Vector2, canceled: bool) -> void:
	if not _pressing or canceled or index < 0:
		return
	_pressing = false
	if point.distance_to(_press_point) > TAP_SLOP:
		return
	var cell := cell_at(point)
	if cell.x < 0:
		return
	var part_index := engine.piece_index_at(cell.x, cell.y)
	if part_index < 0:
		return
	selected = part_index
	queue_redraw()
	part_tapped.emit(part_index)


func _blocked() -> bool:
	if engine == null:
		return true
	if str(engine.state.get("phase", "")) != "playing":
		return true
	return TabletopLayout.input_blocked(self)


func _draw() -> void:
	var board_height := maxf(120.0, size.y - DOCK_HEIGHT)
	draw_style_box(
		_cached_style(
			"control",
			PlaygroundUI.mix(soft, Color.WHITE, 0.22),
			30,
			PlaygroundUI.mix(accent, Color.WHITE, 0.48),
			2,
			8,
			Color(0.15, 0.09, 0.04, 0.12)
		),
		Rect2(Vector2.ZERO, size)
	)
	draw_style_box(
		_cached_style("paper", PAPER, 24, PlaygroundUI.mix(accent, Color.WHITE, 0.60), 2, 5, Color(0.20, 0.10, 0.04, 0.10)),
		Rect2(Vector2(8, 8), Vector2(maxf(1.0, size.x - 16.0), maxf(1.0, board_height - 12.0)))
	)
	if engine == null or engine.width() <= 0 or engine.height() <= 0:
		return
	var layout := metrics()
	_draw_grid(layout)
	_draw_tiles(layout)
	_draw_connectors(layout)
	_draw_faces(layout)
	_draw_live_sparks(layout)
	_draw_feedback(layout)
	_draw_board_caption(layout)
	_draw_tool_tray(board_height)


func _draw_grid(layout: Dictionary) -> void:
	var cell := float(layout.cell)
	var gap := float(layout.gap)
	var origin: Vector2 = layout.origin
	var stride := cell + gap
	for y in engine.height():
		for x in engine.width():
			var center := origin + Vector2(
				float(x) * stride + cell * 0.5,
				float(y) * stride + cell * 0.5
			)
			var occupied := engine.piece_index_at(x, y) >= 0
			var dot_color := Color(accent, 0.11) if not occupied else Color(accent, 0.18)
			draw_circle(center, maxf(1.5, cell * 0.022), dot_color)
			if (x + y) % 3 == 0:
				draw_circle(center + Vector2(cell * 0.16, -cell * 0.13), maxf(1.0, cell * 0.012), Color(accent, 0.06))


func _draw_tiles(layout: Dictionary) -> void:
	var cell := float(layout.cell)
	var gap := float(layout.gap)
	var origin: Vector2 = layout.origin
	var stride := cell + gap
	for index in engine.piece_count():
		var piece := engine.piece_at(index)
		var center := origin + Vector2(
			float(int(piece.x)) * stride + cell * 0.5,
			float(int(piece.y)) * stride + cell * 0.5
		)
		var rect := Rect2(center - Vector2.ONE * cell * 0.47, Vector2.ONE * cell * 0.94)
		var tile_color := _piece_tile_color(piece, index)
		draw_style_box(
			_cached_style(
				"tile_shadow",
				Color(0.30, 0.15, 0.06, 0.10),
				int(cell * 0.17),
				Color.TRANSPARENT,
				0,
				0
			),
			Rect2(rect.position + Vector2(0, cell * 0.045), rect.size)
		)
		draw_style_box(
			_cached_style(
				"tile_%s" % tile_color.to_html(false),
				tile_color,
				int(cell * 0.17),
				PlaygroundUI.mix(accent, Color.WHITE, 0.70),
				maxi(1, int(cell * 0.018))
			),
			rect
		)
		if bool(piece.get("locked", false)):
			var lock_dot := center + Vector2(cell * 0.31, -cell * 0.30)
			draw_circle(lock_dot, cell * 0.035, Color(accent, 0.40))
			draw_arc(lock_dot, cell * 0.060, PI * 0.08, PI * 0.92, 12, Color(accent, 0.28), maxf(1.0, cell * 0.018), true)


func _piece_tile_color(piece: Dictionary, index: int) -> Color:
	var tint := accent
	var piece_type := str(piece.get("type", ""))
	if piece_type == "battery":
		tint = Color("#e1ad4c")
	elif piece_type == "bulb":
		tint = Color("#d49a2c")
	elif piece_type == "fan":
		tint = Color("#4a8e86")
	elif piece_type == "buzzer":
		tint = Color("#b77b3d")
	elif piece_type == "switch":
		tint = SAFE_GREEN
	elif piece_type == "terminal":
		tint = Color("#6f8e87")
	elif piece_type == "resistor":
		tint = Color("#9b805f")
	elif piece_type == "wire":
		tint = COPPER
	var jitter := float((index * 17) % 5) * 0.015
	return PlaygroundUI.mix(soft, Color.WHITE, 0.60 + jitter).lerp(PlaygroundUI.mix(tint, Color.WHITE, 0.86), 0.22)


func _draw_connectors(layout: Dictionary) -> void:
	var cell := float(layout.cell)
	var gap := float(layout.gap)
	for index in engine.piece_count():
		var piece := engine.piece_at(index)
		var center := cell_center(int(piece.x), int(piece.y))
		var mask := engine.connectors(index)
		var powered := engine.is_powered(index)
		for direction in 4:
			if (mask & (1 << direction)) == 0:
				continue
			var delta: Vector2i = CircuitRules.DIRECTION_VECTORS[direction]
			var endpoint := center + Vector2(delta) * (cell * 0.5 + gap * 0.5)
			var linked := engine.is_link(int(piece.x), int(piece.y), direction)
			var cable := COPPER_DARK
			var core := LIVE if linked and powered else COPPER
			draw_line(center, endpoint, Color(0.22, 0.10, 0.04, 0.18), maxf(4.0, cell * 0.23), true)
			draw_line(center, endpoint, cable, maxf(3.0, cell * 0.17), true)
			draw_line(center, endpoint, core, maxf(2.0, cell * 0.10), true)
			draw_circle(endpoint, maxf(2.0, cell * 0.052), cable)
			draw_circle(endpoint, maxf(1.2, cell * 0.032), _soft_metal(index))
			if linked and powered:
				draw_line(
					center.lerp(endpoint, 0.18),
					center.lerp(endpoint, 0.76),
					Color(1.0, 0.93, 0.55, 0.65),
					maxf(1.0, cell * 0.028),
					true
				)


func _draw_faces(layout: Dictionary) -> void:
	var cell := float(layout.cell)
	for index in engine.piece_count():
		var piece := engine.piece_at(index)
		var center := cell_center(int(piece.x), int(piece.y))
		var powered := engine.is_powered(index)
		match str(piece.get("type", "")):
			"battery":
				_draw_battery(index, piece, center, cell)
			"wire":
				_draw_wire_face(index, center, cell)
			"switch":
				_draw_switch(index, piece, center, cell)
			"bulb":
				_draw_bulb(index, center, cell, powered)
			"fan":
				_draw_fan(index, center, cell, powered)
			"buzzer":
				_draw_buzzer(index, center, cell, powered)
			"terminal":
				_draw_terminal(index, center, cell, powered)
			"resistor":
				_draw_resistor(index, piece, center, cell, powered)


func _draw_battery(index: int, piece: Dictionary, center: Vector2, cell: float) -> void:
	var port := _mask_angle(engine.connectors(index))
	var body := Rect2(center - Vector2(cell * 0.34, cell * 0.28), Vector2(cell * 0.68, cell * 0.56))
	draw_style_box(
		_cached_style("battery_shadow", Color(0.31, 0.17, 0.05, 0.17), int(cell * 0.15)),
		Rect2(body.position + Vector2(0, cell * 0.05), body.size)
	)
	draw_style_box(
		_cached_style("battery_body", Color("#f6ca62"), int(cell * 0.15), Color("#9f6627"), maxf(1.0, cell * 0.030)),
		body
	)
	draw_style_box(
		_cached_style("battery_label", Color("#fff5cf"), int(cell * 0.09)),
		Rect2(body.position + Vector2(cell * 0.08, cell * 0.09), Vector2(cell * 0.25, cell * 0.35))
	)
	draw_line(center + Vector2(-cell * 0.25, 0), center + Vector2(-cell * 0.12, 0), Color("#684626"), maxf(1.0, cell * 0.035), true)
	draw_line(center + Vector2(-cell * 0.185, -cell * 0.065), center + Vector2(-cell * 0.185, cell * 0.065), Color("#684626"), maxf(1.0, cell * 0.035), true)
	draw_line(center + Vector2(cell * 0.07, cell * 0.12), center + Vector2(cell * 0.20, cell * 0.12), Color("#684626"), maxf(1.0, cell * 0.035), true)
	draw_string(PlaygroundUI.font(), center + Vector2(-cell * 0.01, cell * 0.20), "3V", HORIZONTAL_ALIGNMENT_LEFT, cell * 0.30, maxi(11, int(cell * 0.12)), Color("#654322"))
	draw_arc(center + Vector2(0, -cell * 0.27), cell * 0.045, 0, TAU, 12, Color(accent, 0.18), 1.0, true)
	draw_circle(center + Vector2(cos(port), sin(port)) * cell * 0.42, cell * 0.060, Color("#8d5728"))
	draw_circle(center + Vector2(cos(port), sin(port)) * cell * 0.42, cell * 0.033, Color(LIVE_LIGHT, 0.85))


func _draw_wire_face(index: int, center: Vector2, cell: float) -> void:
	draw_circle(center, cell * 0.13, Color(COPPER_DARK, 0.35))
	draw_circle(center, cell * 0.095, _soft_metal(index))
	draw_circle(center - Vector2(cell * 0.020, cell * 0.023), cell * 0.035, Color(1, 1, 1, 0.72))


func _draw_switch(index: int, piece: Dictionary, center: Vector2, cell: float) -> void:
	var closed := bool(piece.get("closed", false))
	var powered := engine.is_powered(index)
	var angle := _straight_angle(engine.connectors(index))
	draw_set_transform(center, angle, Vector2.ONE)
	var base := Rect2(Vector2(-cell * 0.32, -cell * 0.25), Vector2(cell * 0.64, cell * 0.50))
	draw_style_box(
		_cached_style("switch_base", Color("#fff1d0"), int(cell * 0.14), Color("#8b5b2a"), maxf(1.0, cell * 0.030)),
		base
	)
	draw_line(Vector2(-cell * 0.33, 0), Vector2(-cell * 0.15, 0), Color("#87552a"), maxf(2.0, cell * 0.09), true)
	draw_line(Vector2(cell * 0.15, 0), Vector2(cell * 0.33, 0), Color("#87552a"), maxf(2.0, cell * 0.09), true)
	draw_circle(Vector2(-cell * 0.15, 0), cell * 0.065, Color("#fff0b3"))
	draw_circle(Vector2(cell * 0.15, 0), cell * 0.065, Color("#fff0b3"))
	if closed:
		draw_line(
			Vector2(-cell * 0.15, 0),
			Vector2(cell * 0.15, 0),
			Color(SAFE_GREEN, 0.92),
			maxf(2.0, cell * 0.085),
			true
		)
		draw_line(
			Vector2(-cell * 0.12, -cell * 0.018),
			Vector2(cell * 0.11, -cell * 0.018),
			Color(0.93, 1.0, 0.78, 0.65),
			maxf(1.0, cell * 0.025),
			true
		)
	else:
		draw_line(
			Vector2(-cell * 0.13, 0),
			Vector2(cell * 0.12, -cell * 0.21),
			Color("#9a6740"),
			maxf(2.0, cell * 0.075),
			true
		)
		draw_line(
			Vector2(-cell * 0.14, 0),
			Vector2(cell * 0.12, -cell * 0.21),
			Color("#f5d87b"),
			maxf(1.0, cell * 0.032),
			true
		)
		draw_arc(
			Vector2(cell * 0.15, 0),
			cell * 0.17,
			-PI * 0.5,
			PI * 0.3,
			10,
			Color("#d18b2d", 0.72),
			maxf(1.0, cell * 0.035),
			true
		)
	draw_circle(Vector2(cell * 0.02, -cell * 0.17), cell * 0.038, Color(1, 0.91, 0.45, 0.55 if not powered else 0.86))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_bulb(index: int, center: Vector2, cell: float, powered: bool) -> void:
	var port := _mask_angle(engine.connectors(index))
	var socket := Rect2(center - Vector2(cell * 0.16, cell * 0.30), Vector2(cell * 0.32, cell * 0.20))
	draw_style_box(
		_cached_style("socket", Color("#b37943"), int(cell * 0.08), Color("#745036"), maxf(1.0, cell * 0.028)),
		socket
	)
	draw_line(center + Vector2(-cell * 0.09, cell * 0.10), center + Vector2(-cell * 0.09, cell * 0.23), Color("#745036"), maxf(1.0, cell * 0.028), true)
	draw_line(center + Vector2(cell * 0.09, cell * 0.10), center + Vector2(cell * 0.09, cell * 0.23), Color("#745036"), maxf(1.0, cell * 0.028), true)
	var glass_center := center + Vector2(0, -cell * 0.06)
	var glass_color := Color("#fff2ad") if powered else Color("#fffdf0")
	if powered:
		draw_circle(glass_center, cell * 0.31, Color(1.0, 0.82, 0.22, 0.16))
		draw_circle(glass_center, cell * 0.24, Color(1.0, 0.88, 0.35, 0.20))
		draw_arc(glass_center, cell * 0.33, 0, TAU, 32, Color(1, 0.86, 0.26, 0.58), maxf(1.0, cell * 0.030), true)
	draw_circle(glass_center, cell * 0.245, glass_color)
	draw_arc(glass_center, cell * 0.245, 0, TAU, 28, Color("#8d733e"), maxf(1.0, cell * 0.024), true)
	var filament := PackedVector2Array([
		glass_center + Vector2(-cell * 0.09, cell * 0.05),
		glass_center + Vector2(-cell * 0.04, -cell * 0.05),
		glass_center + Vector2(0, cell * 0.04),
		glass_center + Vector2(cell * 0.04, -cell * 0.05),
		glass_center + Vector2(cell * 0.09, cell * 0.05),
	])
	draw_polyline(filament, Color("#c28532"), maxf(1.0, cell * 0.024), true)
	draw_circle(glass_center + Vector2(-cell * 0.08, cell * 0.06), cell * 0.063, Color("#f6df88"))
	draw_circle(glass_center + Vector2(cell * 0.08, cell * 0.06), cell * 0.063, Color("#f6df88"))
	if powered:
		for ray in 6:
			var direction := Vector2(cos(float(ray) * TAU / 6.0), sin(float(ray) * TAU / 6.0))
			draw_line(
				glass_center + direction * cell * 0.33,
				glass_center + direction * (cell * 0.41 + sin(_clock * 4.0 + float(ray)) * cell * 0.018),
				Color(1.0, 0.82, 0.32, 0.60),
				maxf(1.0, cell * 0.024),
				true
			)
	draw_circle(center + Vector2(cos(port), sin(port)) * cell * 0.42, cell * 0.055, Color("#866136"))


func _draw_fan(index: int, center: Vector2, cell: float, powered: bool) -> void:
	var port := _mask_angle(engine.connectors(index))
	draw_style_box(
		_cached_style("fan_stem", Color("#c6aa86"), int(cell * 0.08), Color("#75573d"), maxf(1.0, cell * 0.025)),
		Rect2(center + Vector2(-cell * 0.05, cell * 0.17), Vector2(cell * 0.10, cell * 0.18))
	)
	draw_style_box(
		_cached_style("fan_feet", Color("#8d6e50"), int(cell * 0.06), Color("#5d4632"), maxf(1.0, cell * 0.02)),
		Rect2(center + Vector2(-cell * 0.22, cell * 0.31), Vector2(cell * 0.44, cell * 0.08))
	)
	var hub := center + Vector2(0, -cell * 0.05)
	var spin := _clock * 2.4 if powered else 0.15
	for blade in 3:
		var angle := spin + float(blade) * TAU / 3.0
		var blade_direction := Vector2(cos(angle), sin(angle))
		var tangent := Vector2(-sin(angle), cos(angle))
		draw_colored_polygon(PackedVector2Array([
			hub + blade_direction * cell * 0.08,
			hub + blade_direction * cell * 0.22 + tangent * cell * 0.13,
			hub + blade_direction * cell * 0.32 + tangent * cell * 0.075,
			hub + blade_direction * cell * 0.20 - tangent * cell * 0.015,
		]), PlaygroundUI.mix(accent, Color.WHITE, 0.55))
		draw_polyline(PackedVector2Array([
			hub + blade_direction * cell * 0.08,
			hub + blade_direction * cell * 0.22 + tangent * cell * 0.13,
			hub + blade_direction * cell * 0.32 + tangent * cell * 0.075,
		]), PlaygroundUI.mix(accent, Color.BLACK, 0.22), maxf(1.0, cell * 0.022), true)
	draw_circle(hub, cell * 0.11, PlaygroundUI.mix(accent, Color.WHITE, 0.42))
	draw_circle(hub, cell * 0.075, Color("#8b653d"))
	draw_arc(hub, cell * 0.39, 0, TAU, 32, Color("#7f6548", 0.42), maxf(1.0, cell * 0.022), true)
	draw_arc(hub, cell * 0.32, -0.4, 2.4, 22, Color("#fff6d6", 0.55), maxf(1.0, cell * 0.018), true)
	if powered:
		draw_circle(hub, cell * 0.05, Color(1.0, 0.94, 0.62, 0.88))
		for arc_index in 2:
			draw_arc(
				hub,
				cell * (0.47 + float(arc_index) * 0.07),
				-0.9 + float(arc_index) * 0.35,
				0.4 + float(arc_index) * 0.35,
				20,
				Color(SAFE_GREEN, 0.32),
				maxf(1.0, cell * 0.018),
				true
			)
	draw_circle(center + Vector2(cos(port), sin(port)) * cell * 0.42, cell * 0.055, Color("#866136"))


func _draw_buzzer(index: int, center: Vector2, cell: float, powered: bool) -> void:
	var port := _mask_angle(engine.connectors(index))
	draw_style_box(
		_cached_style("buzzer_base", Color("#806b54"), int(cell * 0.14), Color("#564633"), maxf(1.0, cell * 0.03)),
		Rect2(center - Vector2(cell * 0.27, cell * 0.30), Vector2(cell * 0.54, cell * 0.34))
	)
	var dome := center + Vector2(0, -cell * 0.10)
	draw_circle(dome, cell * 0.245, Color("#e5c58f") if not powered else Color("#f5d37d"))
	draw_arc(dome, cell * 0.245, 0, TAU, 30, Color("#725435"), maxf(1.0, cell * 0.028), true)
	draw_circle(dome, cell * 0.09, Color("#5f4b37"))
	draw_circle(dome - Vector2(cell * 0.035, cell * 0.035), cell * 0.04, Color(1, 1, 1, 0.65))
	if powered:
		for ring in 2:
			var radius := cell * (0.34 + float(ring) * 0.10)
			draw_arc(
				dome,
				radius,
				-0.65,
				0.65,
				18,
				Color(SAFE_GREEN, 0.62 - float(ring) * 0.18),
				maxf(1.0, cell * 0.025),
				true
			)
			draw_arc(
				dome,
				radius,
				PI - 0.65,
				PI + 0.65,
				18,
				Color(SAFE_GREEN, 0.62 - float(ring) * 0.18),
				maxf(1.0, cell * 0.025),
				true
			)
	draw_circle(center + Vector2(cos(port), sin(port)) * cell * 0.42, cell * 0.055, Color("#866136"))


func _draw_terminal(index: int, center: Vector2, cell: float, powered: bool) -> void:
	draw_style_box(
		_cached_style("terminal_plate", Color("#647c75"), int(cell * 0.14), Color("#40534f"), maxf(1.0, cell * 0.03)),
		Rect2(center - Vector2.ONE * cell * 0.25, Vector2.ONE * cell * 0.50)
	)
	draw_circle(center, cell * 0.115, Color("#c7a261") if not powered else Color(LIVE_LIGHT))
	draw_circle(center, cell * 0.070, Color("#5f4932"))
	for direction in 4:
		var delta: Vector2i = CircuitRules.DIRECTION_VECTORS[direction]
		var post_center := center + Vector2(delta) * cell * 0.28
		draw_circle(post_center, cell * 0.070, Color("#80512d"))
		draw_circle(post_center, cell * 0.036, Color("#fff0bb") if powered else Color("#b48755"))
	draw_arc(center, cell * 0.37, 0, TAU, 24, Color(SAFE_GREEN, 0.28 if not powered else 0.58), maxf(1.0, cell * 0.018), true)


func _draw_resistor(index: int, piece: Dictionary, center: Vector2, cell: float, powered: bool) -> void:
	var angle := _straight_angle(engine.connectors(index))
	draw_set_transform(center, angle, Vector2.ONE)
	draw_style_box(
		_cached_style("resistor_body", Color("#e6d2a9"), int(cell * 0.20), Color("#725439"), maxf(1.0, cell * 0.030)),
		Rect2(Vector2(-cell * 0.30, -cell * 0.18), Vector2(cell * 0.60, cell * 0.36))
	)
	var stripe_colors := [Color("#a45632"), Color("#4c8c73"), Color("#d2a33c")]
	for stripe in 3:
		draw_rect(
			Rect2(Vector2(-cell * 0.19 + float(stripe) * cell * 0.13, -cell * 0.15), Vector2(cell * 0.055, cell * 0.30)),
			stripe_colors[stripe]
		)
	draw_line(Vector2(-cell * 0.32, 0), Vector2(-cell * 0.23, 0), Color("#795a3c"), maxf(1.0, cell * 0.045), true)
	draw_line(Vector2(cell * 0.23, 0), Vector2(cell * 0.32, 0), Color("#795a3c"), maxf(1.0, cell * 0.045), true)
	if powered:
		draw_arc(Vector2.ZERO, cell * 0.38, 0, TAU, 24, Color(LIVE, 0.20), maxf(1.0, cell * 0.025), true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_live_sparks(layout: Dictionary) -> void:
	var cell := float(layout.cell)
	for index in engine.piece_count():
		var piece := engine.piece_at(index)
		if not engine.is_powered(index):
			continue
		var center := cell_center(int(piece.x), int(piece.y))
		var mask := engine.connectors(index)
		for direction in 4:
			if (mask & (1 << direction)) == 0:
				continue
			if not engine.is_flow_link(int(piece.x), int(piece.y), direction):
				continue
			var delta: Vector2i = CircuitRules.DIRECTION_VECTORS[direction]
			var endpoint := center + Vector2(delta) * cell * 0.46
			var progress := fmod(_clock * 0.72 + float(index * 3 + direction) * 0.17, 1.0)
			var spark := center.lerp(endpoint, 0.16 + progress * 0.70)
			draw_circle(spark, maxf(1.3, cell * 0.022), Color(1.0, 0.95, 0.60, 0.76))
			var arrow_point := center.lerp(endpoint, 0.62)
			var arrow_size := maxf(3.0, cell * 0.055)
			var direction_vector := Vector2(delta.x, delta.y)
			var tangent := Vector2(-direction_vector.y, direction_vector.x)
			draw_colored_polygon(PackedVector2Array([
				arrow_point + direction_vector * arrow_size,
				arrow_point - direction_vector * arrow_size * 0.65 + tangent * arrow_size * 0.78,
				arrow_point - direction_vector * arrow_size * 0.65 - tangent * arrow_size * 0.78,
			]), Color(0.96, 0.73, 0.18, 0.68))
		for goal_index in engine.goal_count():
			if engine.goal_position(goal_index) != Vector2i(int(piece.x), int(piece.y)):
				continue
			var started := float(_goal_celebrate_at.get(goal_index, _clock - 1.0))
			var elapsed := _clock - started
			if elapsed >= 0.0 and elapsed < 0.9:
				var ring_radius := cell * (0.34 + elapsed * 0.36)
				draw_arc(center, ring_radius, 0, TAU, 28, Color(1.0, 0.86, 0.27, 0.58 * (1.0 - elapsed / 0.9)), maxf(1.0, cell * 0.028), true)


func _draw_feedback(layout: Dictionary) -> void:
	var cell := float(layout.cell)
	if fault_index >= 0 and fault_index < engine.piece_count():
		var piece := engine.piece_at(fault_index)
		var center := cell_center(int(piece.x), int(piece.y))
		var pulse := 0.5 + 0.5 * sin(_clock * 4.0)
		draw_arc(center, cell * (0.45 + pulse * 0.035), 0, TAU, 30, Color("#d08a24", 0.82), maxf(2.0, cell * 0.035), true)
		var marker := center + Vector2(cell * 0.32, -cell * 0.32)
		draw_circle(marker, cell * 0.11, Color("#d08a24"))
		draw_line(marker + Vector2(0, -cell * 0.045), marker + Vector2(0, cell * 0.015), Color.WHITE, maxf(2.0, cell * 0.022), true)
		draw_circle(marker + Vector2(0, cell * 0.050), maxf(1.2, cell * 0.014), Color.WHITE)
	if hint_index >= 0 and hint_index < engine.piece_count():
		var hint_piece := engine.piece_at(hint_index)
		var hint_center := cell_center(int(hint_piece.x), int(hint_piece.y))
		var glow := 0.38 + 0.22 * sin(_clock * 3.2)
		draw_arc(hint_center, cell * 0.50, 0, TAU, 32, Color(accent, glow), maxf(2.0, cell * 0.028), true)
		draw_arc(hint_center, cell * (0.56 + sin(_clock * 2.0) * 0.018), 0, TAU, 32, Color(accent, 0.20), maxf(1.0, cell * 0.018), true)
	if selected >= 0 and selected < engine.piece_count():
		var selected_piece := engine.piece_at(selected)
		var selected_center := cell_center(int(selected_piece.x), int(selected_piece.y))
		draw_arc(selected_center, cell * 0.44, -0.75, 0.75, 18, Color(accent, 0.55), maxf(1.0, cell * 0.028), true)
		draw_arc(selected_center, cell * 0.44, PI - 0.75, PI + 0.75, 18, Color(accent, 0.55), maxf(1.0, cell * 0.028), true)


func _draw_board_caption(layout: Dictionary) -> void:
	var font := PlaygroundUI.font()
	var caption := "低压 3V 玩具电路 · 不碰家里的插座"
	var font_size := maxi(12, int(clampf(size.x * 0.012, 12.0, 16.0)))
	var width := font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + 26.0
	var rect := Rect2(Vector2(16, 15), Vector2(width, 24))
	draw_style_box(
		_cached_style("safety_caption", Color(SAFE_GREEN, 0.12), 12, Color(SAFE_GREEN, 0.28), 1),
		rect
	)
	draw_circle(rect.position + Vector2(12, 12), 4.0, Color(SAFE_GREEN, 0.82))
	draw_string(
		font,
		rect.position + Vector2(22, 17),
		caption,
		HORIZONTAL_ALIGNMENT_LEFT,
		width - 28.0,
		font_size,
		Color(SAFE_GREEN.darkened(0.28), 0.94)
	)
func _draw_tool_tray(board_height: float) -> void:
	var rect := Rect2(Vector2(10, board_height + 5), Vector2(maxf(1.0, size.x - 20), DOCK_HEIGHT - 10))
	draw_style_box(
		_cached_style("tray", PlaygroundUI.mix(accent, Color.WHITE, 0.86), 20, PlaygroundUI.mix(accent, Color.WHITE, 0.46), 1, 3, Color(0.25, 0.12, 0.04, 0.08)),
		rect
	)
	draw_circle(rect.position + Vector2(24, rect.size.y * 0.5), 9.0, Color(SAFE_GREEN, 0.18))
	draw_line(rect.position + Vector2(18, rect.size.y * 0.5), rect.position + Vector2(30, rect.size.y * 0.5), Color(SAFE_GREEN, 0.84), 3.0, true)
	draw_colored_polygon(PackedVector2Array([
		rect.position + Vector2(30, rect.size.y * 0.5),
		rect.position + Vector2(24, rect.size.y * 0.5 - 5),
		rect.position + Vector2(24, rect.size.y * 0.5 + 5),
	]), Color(SAFE_GREEN, 0.84))


func _build_tool_dock() -> void:
	_dock = HBoxContainer.new()
	_dock.name = "CircuitToolDock"
	_dock.add_theme_constant_override("separation", 12)
	_dock.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(_dock)
	_dock_label = PlaygroundUI.label("从电池出发  ·  合上每一段安全电路", 17, PlaygroundUI.INK_SOFT, 600, true)
	_dock_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_dock_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dock.add_child(_dock_label)
	_hint_button = PlaygroundUI.semantic_icon_button("hint", "看提示", accent, func(): hint_requested.emit(), "soft", 17)
	_hint_button.custom_minimum_size = Vector2(142, 48)
	_dock.add_child(_hint_button)
	_layout_dock()


func _layout_dock() -> void:
	if not is_instance_valid(_dock):
		return
	_dock.anchor_left = 0.0
	_dock.anchor_right = 1.0
	_dock.anchor_top = 1.0
	_dock.anchor_bottom = 1.0
	_dock.offset_left = 50.0
	_dock.offset_right = -22.0
	_dock.offset_top = -56.0
	_dock.offset_bottom = -8.0


func _sync_dock() -> void:
	if not is_instance_valid(_dock_label):
		return
	if engine == null:
		_dock_label.text = "选一关安全电路，从低压电池出发"
		return
	if str(engine.state.get("phase", "")) == "finished":
		_dock_label.text = "全部小电器都亮啦  ·  本局已自动保存"
	elif engine.is_cooperative():
		_dock_label.text = "两个人轮流操作  ·  点导线转，点开关合"
	else:
		_dock_label.text = "从电池出发  ·  点导线转，点开关合"


func _mask_angle(mask: int) -> float:
	if mask & (1 << 1):
		return 0.0
	if mask & (1 << 2):
		return PI * 0.5
	if mask & (1 << 3):
		return PI
	return -PI * 0.5


func _straight_angle(mask: int) -> float:
	return 0.0 if (mask & (1 << 1)) != 0 or (mask & (1 << 3)) != 0 else PI * 0.5


func _soft_metal(seed_value: int) -> Color:
	var palette := [Color("#efe0c5"), Color("#dfc7a0"), Color("#f8ecd6")]
	return palette[seed_value % palette.size()]


func _cached_style(
	cache_key: String,
	background: Color,
	radius: int,
	border_color: Color = Color.TRANSPARENT,
	border_width: int = 0,
	shadow_size: int = 0,
	shadow_color: Color = Color.TRANSPARENT
) -> StyleBoxFlat:
	if _style_cache.has(cache_key):
		return _style_cache[cache_key]
	var color_key := "%s:%s" % [cache_key, background.to_html()]
	if _style_cache.has(color_key):
		return _style_cache[color_key]
	var style_box := PlaygroundUI.style(background, radius, border_color, border_width, shadow_size, shadow_color)
	_style_cache[color_key] = style_box
	return style_box
