class_name PipeBoard
extends Control

signal piece_tapped(index: int)

const TAP_SLOP := 14.0
const FLOWER_COLORS := [
	Color("#e97a68"), Color("#e9a93f"), Color("#d986b1"),
	Color("#a77bc4"), Color("#e4bd46"), Color("#e8895e"),
]

var engine: PipeRules
var accent := Color("#2b7d76")
var soft := Color("#dcefec")
var interactive := true
var selected := -1

var _touch_index := -1
var _press_point := Vector2.ZERO
var _pressing := false
var _last_touch_msec := -1000
var _clock := 0.0
var _last_wet_goals := {}
var _bloom_started := {}
var _style_cache := {}


func _ready() -> void:
	custom_minimum_size = Vector2(520, 430)
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	set_process(true)
	resized.connect(_on_resized)


func _on_resized() -> void:
	_style_cache.clear()
	queue_redraw()


func bind(value: PipeRules) -> void:
	engine = value
	selected = -1
	_last_wet_goals.clear()
	_bloom_started.clear()
	if engine != null:
		for index in engine.goal_count():
			if engine.goal_is_wet(index):
				_last_wet_goals[index] = true
				_bloom_started[index] = _clock - 0.5
	queue_redraw()


func cancel_gesture() -> void:
	_touch_index = -1
	_pressing = false


func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_WM_CLOSE_REQUEST]:
		cancel_gesture()


func _process(delta: float) -> void:
	_clock += delta
	if engine == null or engine.level_title().is_empty():
		return
	for index in engine.goal_count():
		var wet := engine.goal_is_wet(index)
		if wet and not bool(_last_wet_goals.get(index, false)):
			_bloom_started[index] = _clock
		_last_wet_goals[index] = wet
	queue_redraw()


func metrics() -> Dictionary:
	if engine == null or engine.width() <= 0 or engine.height() <= 0:
		return {"cell": 1.0, "gap": 0.0, "origin": Vector2.ZERO, "extent": Vector2.ONE}
	var board_margin := clampf(minf(size.x, size.y) * 0.05, 22.0, 38.0)
	var padded := size - Vector2.ONE * board_margin * 2.0
	var available := Vector2(maxf(40.0, padded.x), maxf(40.0, padded.y))
	var columns := engine.width()
	var rows := engine.height()
	var rough_cell := minf(available.x / float(columns + 1), available.y / float(rows + 1))
	var gap := clampf(rough_cell * 0.09, 3.0, 12.0)
	var cell := minf(
		(available.x - gap * float(maxi(0, columns - 1))) / float(columns),
		(available.y - gap * float(maxi(0, rows - 1))) / float(rows)
	)
	var extent := Vector2(
		cell * float(columns) + gap * float(maxi(0, columns - 1)),
		cell * float(rows) + gap * float(maxi(0, rows - 1))
	)
	var origin := (size - extent) * 0.5
	return {"cell": cell, "gap": gap, "origin": origin, "extent": extent}


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
	var piece_index := engine.piece_index_at(cell.x, cell.y)
	if piece_index < 0:
		return
	selected = piece_index
	queue_redraw()
	piece_tapped.emit(piece_index)


func _blocked() -> bool:
	if engine == null:
		return true
	if str(engine.state.get("phase", "")) != "playing":
		return true
	return TabletopLayout.input_blocked(self)


func _draw() -> void:
	if engine == null or engine.width() <= 0 or engine.height() <= 0:
		return
	var layout := metrics()
	var cell := float(layout.cell)
	var gap := float(layout.gap)
	var origin: Vector2 = layout.origin
	var extent: Vector2 = layout.extent
	draw_style_box(_cached_style(
		"board",
		PlaygroundUI.mix(soft, Color.WHITE, 0.34),
		32,
		PlaygroundUI.mix(accent, Color.WHITE, 0.42),
		2,
		10,
		Color(0.08, 0.16, 0.13, 0.12)
	), Rect2(Vector2.ZERO, size))
	draw_style_box(
		_cached_style("mat", Color("#f6f1df"), 24, PlaygroundUI.mix(accent, Color.WHITE, 0.58), 2),
		Rect2(origin - Vector2.ONE * 14.0, extent + Vector2.ONE * 28.0)
	)
	_draw_garden_tiles(layout)
	_draw_walls(layout)
	_draw_piece_casing(layout)
	_draw_water(layout)
	_draw_piece_faces(layout)
	_draw_hints_and_selection(layout)
	_draw_leaks(layout)
	_draw_garden_details(layout)


func _draw_garden_tiles(layout: Dictionary) -> void:
	var cell := float(layout.cell)
	var gap := float(layout.gap)
	var origin: Vector2 = layout.origin
	var stride := cell + gap
	for y in engine.height():
		for x in engine.width():
			var rect := Rect2(origin + Vector2(float(x) * stride, float(y) * stride), Vector2.ONE * cell)
			var hash_value := (x * 37 + y * 71 + engine.width() * 11) % 7
			var ground := PlaygroundUI.mix(Color("#dfeacb"), Color("#f7f0d9"), 0.35 + float(hash_value) * 0.055)
			draw_style_box(
				_cached_style(
					"tile_%s" % hash_value,
					ground,
					int(maxf(8.0, cell * 0.13)),
					PlaygroundUI.mix(accent, Color.WHITE, 0.78),
					1
				),
				rect
			)
			if hash_value in [1, 5]:
				_draw_grass_tuft(rect.position + Vector2(cell * (0.18 + 0.09 * float(hash_value)), cell * 0.82), cell * 0.11)


func _draw_walls(layout: Dictionary) -> void:
	var walls: Variant = engine.level_definition.get("walls", [])
	if not walls is Array:
		return
	for wall in walls:
		if not wall is Dictionary:
			continue
		var center := cell_center(int(wall.get("x", 0)), int(wall.get("y", 0)))
		var cell := float(layout.cell)
		var stone := Rect2(center - Vector2.ONE * cell * 0.36, Vector2.ONE * cell * 0.72)
		draw_style_box(
			_cached_style("stone_shadow", Color(0.25, 0.29, 0.23, 0.14), int(cell * 0.18)),
			Rect2(stone.position + Vector2(0, cell * 0.055), stone.size)
		)
		draw_style_box(
			_cached_style("stone", Color("#b9ad91"), int(cell * 0.18), Color("#938870"), maxi(1, int(cell * 0.025))),
			stone
		)
		draw_style_box(
			_cached_style("stone_face", Color("#d5c9ac"), int(cell * 0.14)),
			Rect2(stone.position + Vector2.ONE * cell * 0.11, stone.size - Vector2.ONE * cell * 0.18)
		)
		draw_circle(stone.position + Vector2(cell * 0.23, cell * 0.20), cell * 0.075, Color("#91a66f"))
		draw_circle(stone.position + Vector2(cell * 0.47, cell * 0.24), cell * 0.045, Color("#81a065"))


func _draw_piece_casing(layout: Dictionary) -> void:
	var cell := float(layout.cell)
	for index in engine.piece_count():
		var piece := engine.piece_at(index)
		var center := cell_center(int(piece.get("x", 0)), int(piece.get("y", 0)))
		var mask := engine.connectors(index)
		var fixed := engine.is_fixed(index)
		for direction in 4:
			if (mask & (1 << direction)) == 0:
				continue
			var endpoint := center + _direction_vector(direction) * cell * 0.50
			draw_line(center + Vector2(0, cell * 0.04), endpoint + Vector2(0, cell * 0.04), Color(0.14, 0.20, 0.17, 0.18), maxf(5.0, cell * 0.24), true)
			draw_line(center, endpoint, Color("#696958"), maxf(4.0, cell * 0.21), true)
			draw_line(center, endpoint, Color("#e2d3b3") if not fixed else Color("#c8b999"), maxf(3.0, cell * 0.145), true)
			draw_circle(endpoint, cell * 0.072, Color("#696958"))
			draw_circle(endpoint, cell * 0.049, Color("#e2d3b3") if not fixed else Color("#c8b999"))
		draw_circle(center, cell * 0.115, Color("#696958"))
		draw_circle(center, cell * 0.082, Color("#e8d9b8"))
		if fixed:
			draw_arc(center, cell * 0.095, -0.65, 0.65, 20, Color("#a67a42"), maxf(2.0, cell * 0.022), true)
			draw_arc(center, cell * 0.095, PI - 0.65, PI + 0.65, 20, Color("#a67a42"), maxf(2.0, cell * 0.022), true)


func _draw_water(layout: Dictionary) -> void:
	var cell := float(layout.cell)
	for index in engine.piece_count():
		var piece := engine.piece_at(index)
		var center := cell_center(int(piece.get("x", 0)), int(piece.get("y", 0)))
		var mask := engine.connectors(index)
		for direction in 4:
			if (mask & (1 << direction)) == 0:
				continue
			if not engine.is_link(int(piece.x), int(piece.y), direction):
				continue
			var endpoint := center + _direction_vector(direction) * cell * 0.50
			draw_line(center, endpoint, Color("#80d4d2"), maxf(2.0, cell * 0.070), true)
			draw_line(center, endpoint, Color("#e3ffff"), maxf(1.0, cell * 0.018), true)
			for bubble_index in 2:
				var progress := fmod(_clock * (0.42 + 0.08 * float(bubble_index)) + float(index + direction) * 0.19, 1.0)
				var bubble := center.lerp(endpoint, progress)
				draw_circle(bubble, maxf(1.5, cell * 0.018), Color(1, 1, 1, 0.72))
		if engine.is_wet(int(piece.x), int(piece.y)):
			draw_circle(center, cell * 0.060, Color("#57aaa9"))
			draw_circle(center, cell * 0.035, Color("#dcffff"))


func _draw_piece_faces(layout: Dictionary) -> void:
	var cell := float(layout.cell)
	for goal_index in engine.goal_count():
		var goals: Array = engine.level_definition.get("goals", [])
		var goal: Dictionary = goals[goal_index]
		_draw_goal(
			cell_center(int(goal.get("x", 0)), int(goal.get("y", 0))),
			cell,
			goal_index,
			engine.goal_is_wet(goal_index)
		)
	var source := engine.source_position()
	_draw_source(cell_center(source.x, source.y), cell, engine.is_wet(source.x, source.y))


func _draw_source(center: Vector2, cell: float, wet: bool) -> void:
	draw_circle(center + Vector2(0, cell * 0.045), cell * 0.195, Color(0.10, 0.18, 0.17, 0.18))
	draw_circle(center, cell * 0.190, Color("#397f7c"))
	draw_circle(center, cell * 0.145, Color("#77c6c2"))
	draw_circle(center + Vector2(0, cell * 0.014), cell * 0.100, Color("#2d7e9a"))
	if wet:
		for ripple in 2:
			var pulse := fmod(_clock * 0.65 + float(ripple) * 0.5, 1.0)
			draw_arc(center, cell * (0.10 + 0.17 * pulse), 0.2, PI - 0.2, 22, Color(1, 1, 1, 0.48 * (1.0 - pulse)), maxf(1.5, cell * 0.014), true)
	draw_circle(center + Vector2(-cell * 0.055, -cell * 0.055), cell * 0.030, Color(1, 1, 1, 0.65))
	var label_y := center.y + cell * 0.305
	_draw_centered_text("水源", Vector2(center.x, label_y), maxi(11, int(cell * 0.105)), PlaygroundUI.mix(accent, PlaygroundUI.INK, 0.25))


func _draw_goal(center: Vector2, cell: float, goal_index: int, wet: bool) -> void:
	var bed := Rect2(center - Vector2.ONE * cell * 0.245, Vector2.ONE * cell * 0.49)
	draw_style_box(
		_cached_style("bed_shadow", Color(0.14, 0.19, 0.12, 0.14), int(cell * 0.15)),
		Rect2(bed.position + Vector2(0, cell * 0.045), bed.size)
	)
	draw_style_box(_cached_style("bed", Color("#9c6f4b"), int(cell * 0.15), Color("#745337"), maxi(1, int(cell * 0.020))), bed)
	draw_style_box(_cached_style("soil", Color("#5e4838")), Rect2(bed.position + Vector2(cell * 0.055, cell * 0.22), Vector2(cell * 0.39, cell * 0.15)))
	draw_style_box(_cached_style("soil_light", Color("#725439"), int(cell * 0.07)), Rect2(bed.position + Vector2(cell * 0.13, cell * 0.265), Vector2(cell * 0.24, cell * 0.075)))
	var flower_tint: Color = FLOWER_COLORS[goal_index % FLOWER_COLORS.size()]
	var stem_top := center + Vector2(0, -cell * 0.12)
	draw_line(center + Vector2(0, cell * 0.06), stem_top, Color("#4f8a55"), maxf(1.5, cell * 0.020), true)
	draw_circle(center + Vector2(-cell * 0.035, cell * 0.035), cell * 0.035, Color("#649d5c"))
	draw_circle(center + Vector2(cell * 0.040, cell * 0.055), cell * 0.028, Color("#78ad67"))
	var bloom := 0.25 if not wet else clampf((_clock - float(_bloom_started.get(goal_index, _clock - 1.0))) / 0.45, 0.0, 1.0)
	var petals := 6
	for petal in petals:
		var angle := TAU * float(petal) / float(petals)
		var distance := cell * (0.025 + 0.050 * bloom)
		draw_circle(stem_top + Vector2(cos(angle), sin(angle)) * distance, cell * (0.028 + 0.016 * bloom), flower_tint)
	draw_circle(stem_top, cell * (0.024 + 0.014 * bloom), Color("#f7d56d"))
	if wet and bloom >= 0.98:
		for sparkle in 3:
			var angle := _clock * 1.2 + float(sparkle) * TAU / 3.0
			var point := stem_top + Vector2(cos(angle), sin(angle)) * cell * 0.19
			draw_circle(point, maxf(1.0, cell * 0.010), Color(1, 1, 0.82, 0.72))
	else:
		_draw_droplet(stem_top + Vector2(cell * 0.12, -cell * 0.15), cell * 0.035, Color("#6eb9b6"))


func _draw_hints_and_selection(layout: Dictionary) -> void:
	var cell := float(layout.cell)
	for index in engine.piece_count():
		var piece := engine.piece_at(index)
		var center := cell_center(int(piece.get("x", 0)), int(piece.get("y", 0)))
		if index == selected:
			draw_arc(center, cell * 0.375, 0, TAU, 48, Color(accent, 0.48), maxf(2.0, cell * 0.025), true)
		if not engine.is_hint_piece(index):
			continue
		var pulse := 0.5 + 0.5 * sin(_clock * 5.2)
		draw_arc(center, cell * (0.36 + pulse * 0.045), 0, TAU, 52, Color(1.0, 0.77, 0.24, 0.72), maxf(2.0, cell * 0.028), true)
		var hinted_mask := PipeRules.connector_mask(str(piece.get("type", "")), engine.hint_rotation())
		for direction in 4:
			if (hinted_mask & (1 << direction)) == 0:
				continue
			var vector := _direction_vector(direction)
			var endpoint := center + vector * cell * 0.43
			draw_line(center, endpoint, Color(1.0, 0.79, 0.26, 0.48 + pulse * 0.28), maxf(2.0, cell * 0.040), true)
			var perpendicular := Vector2(-vector.y, vector.x)
			var base := endpoint - vector * cell * 0.055
			draw_colored_polygon(PackedVector2Array([
				endpoint + vector * cell * 0.025,
				base + perpendicular * cell * 0.035,
				base - perpendicular * cell * 0.035,
			]), Color(1.0, 0.72, 0.18, 0.86))


func _draw_leaks(layout: Dictionary) -> void:
	var cell := float(layout.cell)
	var drop_limit := 32
	var drawn := 0
	for index in engine.piece_count():
		var piece := engine.piece_at(index)
		var mask := engine.connectors(index)
		var center := cell_center(int(piece.get("x", 0)), int(piece.get("y", 0)))
		for direction in 4:
			if drawn >= drop_limit or (mask & (1 << direction)) == 0:
				continue
			if not engine.is_leak(int(piece.x), int(piece.y), direction):
				continue
			var vector := _direction_vector(direction)
			var point := center + vector * cell * 0.46
			draw_circle(point, maxf(2.0, cell * 0.033), Color("#d56a4c"))
			draw_circle(point + vector * cell * 0.035, maxf(1.0, cell * 0.013), Color("#ecad5d"))
			drawn += 1


func _draw_garden_details(layout: Dictionary) -> void:
	var cell := float(layout.cell)
	if str(engine.state.get("phase", "")) == "finished":
		for index in 7:
			var angle := _clock * 0.32 + float(index) * TAU / 7.0
			var radius := minf(size.x, size.y) * (0.36 + 0.035 * float(index % 3))
			var point := size * 0.5 + Vector2(cos(angle), sin(angle)) * radius
			_draw_small_petal(point, cell * 0.040, Color(1.0, 0.82, 0.36, 0.54))
	var title_tint := PlaygroundUI.mix(accent, PlaygroundUI.INK_SOFT, 0.25)
	_draw_centered_text(
		"%s · %s" % [engine.level_title(), {"easy":"轻松", "normal":"标准", "challenge":"挑战"}.get(engine.level_band(), "标准")],
		Vector2(size.x * 0.5, size.y - 15.0),
		maxi(12, int(cell * 0.11)),
		title_tint
	)


func _draw_grass_tuft(origin: Vector2, scale: float) -> void:
	draw_line(origin, origin + Vector2(-scale, -scale * 1.45), Color("#82a867"), maxf(1.0, scale * 0.16), true)
	draw_line(origin, origin + Vector2(scale * 0.18, -scale * 1.8), Color("#789f60"), maxf(1.0, scale * 0.16), true)
	draw_line(origin, origin + Vector2(scale, -scale * 1.25), Color("#8eb373"), maxf(1.0, scale * 0.16), true)


func _draw_droplet(center: Vector2, radius: float, tint: Color) -> void:
	draw_circle(center + Vector2(0, radius * 0.25), radius, tint)
	draw_colored_polygon(PackedVector2Array([
		center + Vector2(0, -radius * 1.45),
		center + Vector2(-radius * 0.78, radius * 0.10),
		center + Vector2(radius * 0.78, radius * 0.10),
	]), tint)
	draw_circle(center + Vector2(-radius * 0.20, radius * 0.20), radius * 0.22, Color(1, 1, 1, 0.45))


func _draw_small_petal(center: Vector2, radius: float, tint: Color) -> void:
	draw_set_transform(center, _clock * 0.35, Vector2.ONE)
	for petal in 4:
		var angle := TAU * float(petal) / 4.0
		draw_circle(Vector2(cos(angle), sin(angle)) * radius, radius * 0.62, tint)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_centered_text(text: String, center: Vector2, font_size: int, tint: Color) -> void:
	var font := PlaygroundUI.font()
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string(
		font,
		center + Vector2(-width * 0.5, float(font_size) * 0.35),
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		font_size,
		tint
	)


func _direction_vector(direction: int) -> Vector2:
	return Vector2(PipeRules.DIRECTION_VECTORS[posmod(direction, 4)])


func _cached_style(
	cache_key: String,
	background: Color,
	radius: int = 20,
	border: Color = Color.TRANSPARENT,
	border_width: int = 0,
	shadow_size: int = 0,
	shadow_color: Color = Color.TRANSPARENT
) -> StyleBoxFlat:
	if _style_cache.has(cache_key):
		return _style_cache[cache_key]
	var style := PlaygroundUI.style(background, radius, border, border_width, shadow_size, shadow_color)
	_style_cache[cache_key] = style
	return style
