class_name TankField
extends Control

signal action_requested(action: Dictionary)

const TAP_SLOP := 16.0
const MAX_PARTICLES := 160
const MAX_BUBBLES := 36
const MAX_POPUPS := 14
const MAX_RIPPLES := 12
const MOVE_REPEAT := 0.115
const FIRE_REPEAT := 0.24
const HOLD_DELAY := 0.32

var engine
var game_screen
var players: Array = []
var accent := Color("#34465a")
var soft := Color("#e3e8ef")
var interactive := true

var _board_rect := Rect2()
var _left_dock_rect := Rect2()
var _right_dock_rect := Rect2()
var _grid_origin := Vector2.ZERO
var _cell_size := 1.0
var _grid_rect := Rect2()
var _button_entries: Array = []
var _pointers: Dictionary = {}
var _last_touch_msec := -1000
var _clock := 0.0
var _notice := ""
var _notice_time := 0.0
var _shake := Vector2.ZERO
var _shake_time := 0.0
var _particles: Array = []
var _particle_cursor := 0
var _active_particles := 0
var _bubbles: Array = []
var _bubble_cursor := 0
var _popups: Array = []
var _ripples: Array = []
var _flash := 0.0
var _flash_color := Color.WHITE
var _flash_position := Vector2.ZERO
var _flash_radius := 20.0
var _style_cache: Dictionary = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	custom_minimum_size = Vector2(760, 520)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	set_process(true)
	resized.connect(_request_layout)
	_ensure_particle_pool()
	_ensure_bubble_pool()


func bind(value, screen, seat_players: Array) -> void:
	engine = value
	game_screen = screen
	players = seat_players.duplicate(true)
	_pointers.clear()
	_notice = ""
	_notice_time = 0.0
	_shake = Vector2.ZERO
	_shake_time = 0.0
	_particles.clear()
	_active_particles = 0
	_particle_cursor = 0
	_ensure_particle_pool()
	_bubbles.clear()
	_bubble_cursor = 0
	_ensure_bubble_pool()
	_popups.clear()
	_ripples.clear()
	_flash = 0.0
	_style_cache.clear()
	_request_layout()
	queue_redraw()


func cancel_inputs() -> void:
	_pointers.clear()
	queue_redraw()


func suspend_effects() -> void:
	cancel_inputs()
	_particles.clear()
	_active_particles = 0
	_particle_cursor = 0
	_ensure_particle_pool()
	_bubbles.clear()
	_bubble_cursor = 0
	_ensure_bubble_pool()
	_popups.clear()
	_ripples.clear()
	_shake = Vector2.ZERO
	_shake_time = 0.0
	_flash = 0.0
	queue_redraw()


func set_interactive(value: bool) -> void:
	interactive = value
	if not value:
		cancel_inputs()
	queue_redraw()


func flash_notice(message: String, seconds: float = 1.9) -> void:
	_notice = message
	_notice_time = seconds
	queue_redraw()


func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_WM_CLOSE_REQUEST]:
		cancel_inputs()


func _blocked() -> bool:
	if engine == null or str(engine.state.get("phase", "")) != "playing":
		return true
	if game_screen != null and game_screen.is_input_blocked():
		return true
	return TabletopLayout.input_blocked(self)


func _request_layout() -> void:
	_layout()
	queue_redraw()


func _process(delta: float) -> void:
	_clock += delta
	_notice_time = maxf(0.0, _notice_time - delta)
	_update_effects(delta)
	_tick_held_buttons()
	if _blocked() and _active_particles == 0 and _popups.is_empty() and _ripples.is_empty() and _bubbles.is_empty():
		return
	queue_redraw()


func _tick_held_buttons() -> void:
	if _blocked() or not interactive:
		return
	for index in _pointers.keys():
		var pointer: Dictionary = _pointers[index]
		if pointer.get("slot", {}).is_empty():
			continue
		if _clock < float(pointer.get("next_repeat", 1e20)):
			continue
		var slot: Dictionary = pointer.slot
		_emit_slot(slot)
		var action := str(slot.get("action", ""))
		pointer.next_repeat = _clock + (FIRE_REPEAT if action == "fire" else MOVE_REPEAT)
		_pointers[index] = pointer


func _gui_input(event: InputEvent) -> void:
	if not interactive or _blocked():
		cancel_inputs()
		return
	if event is InputEventScreenTouch:
		if event.device == InputEvent.DEVICE_ID_EMULATION:
			return
		_last_touch_msec = Time.get_ticks_msec()
		accept_event()
		if event.pressed:
			_pointer_down(event.index, event.position)
		else:
			_pointer_up(event.index)
	elif event is InputEventScreenDrag:
		_last_touch_msec = Time.get_ticks_msec()
		if _pointers.has(event.index):
			var pointer: Dictionary = _pointers[event.index]
			var start: Vector2 = pointer.get("start", event.position)
			if start.distance_to(event.position) > TAP_SLOP:
				pointer.slot = {}
				pointer.next_repeat = 1e20
				_pointers[event.index] = pointer
		accept_event()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if Time.get_ticks_msec() - _last_touch_msec < 500:
			return
		accept_event()
		if event.pressed:
			_pointer_down(-1, event.position)
		else:
			_pointer_up(-1)
	elif event is InputEventMouseMotion and _pointers.has(-1):
		var pointer: Dictionary = _pointers[-1]
		var start: Vector2 = pointer.get("start", event.position)
		if start.distance_to(event.position) > TAP_SLOP:
			pointer.slot = {}
			pointer.next_repeat = 1e20
			_pointers[-1] = pointer
		accept_event()


func _pointer_down(index: int, position: Vector2) -> void:
	var slot := _button_at(position)
	if slot.is_empty():
		return
	_pointers[index] = {
		"slot": slot,
		"start": position,
		"next_repeat": _clock + HOLD_DELAY,
	}
	_emit_slot(slot)
	queue_redraw()


func _pointer_up(index: int) -> void:
	if _pointers.has(index):
		_pointers.erase(index)
		queue_redraw()


func _emit_slot(slot: Dictionary) -> void:
	if slot.is_empty():
		return
	var action := str(slot.get("action", ""))
	var seat := int(slot.get("seat", 0))
	if action == "fire":
		action_requested.emit({"type": "fire", "seat": seat})
	else:
		action_requested.emit({"type": "move", "dir": action, "seat": seat})


func _button_at(point: Vector2) -> Dictionary:
	for entry in _button_entries:
		if entry is Dictionary and (entry.rect as Rect2).has_point(point):
			return {"seat": int(entry.seat), "action": str(entry.action)}
	return {}


func _layout() -> void:
	if size.x < 2.0 or size.y < 2.0:
		return
	_button_entries.clear()
	var margin := clampf(minf(size.x, size.y) * 0.012, 8.0, 16.0)
	var gap := 14.0
	var tall := size.y - margin * 2.0
	var classic: bool = engine != null and int(engine.tank_count()) == 2
	var dock_width := clampf(size.x * 0.22, 250.0, 350.0)
	if not classic:
		dock_width = clampf(size.x * 0.26, 280.0, 380.0)
	if classic:
		_left_dock_rect = Rect2(margin, margin, dock_width, tall)
		_board_rect = Rect2(margin + dock_width + gap, margin, size.x - margin * 2.0 - dock_width * 2.0 - gap * 2.0, tall)
		_right_dock_rect = Rect2(size.x - margin - dock_width, margin, dock_width, tall)
	else:
		_left_dock_rect = Rect2()
		_board_rect = Rect2(margin, margin, size.x - margin * 2.0 - dock_width - gap, tall)
		_right_dock_rect = Rect2(size.x - margin - dock_width, margin, dock_width, tall)
	_layout_grid()
	if classic:
		_layout_dock(0, _left_dock_rect)
		_layout_dock(1, _right_dock_rect)
	else:
		_layout_dock(0, _right_dock_rect)


func _layout_grid() -> void:
	if engine == null:
		_grid_rect = Rect2()
		return
	var width: int = maxi(1, int(engine.width()))
	var height: int = maxi(1, int(engine.height()))
	var header := clampf(_board_rect.size.y * 0.07, 54.0, 76.0)
	var room := Rect2(
		_board_rect.position + Vector2(20.0, header + 12.0),
		Vector2(_board_rect.size.x - 40.0, _board_rect.size.y - header - 28.0)
	)
	room.size.x = maxf(10.0, room.size.x)
	room.size.y = maxf(10.0, room.size.y)
	var cell := minf(room.size.x / float(width), room.size.y / float(height))
	cell = maxf(16.0, cell)
	_cell_size = cell
	var grid_size := Vector2(cell * float(width), cell * float(height))
	_grid_origin = room.position + (room.size - grid_size) * 0.5
	_grid_rect = Rect2(_grid_origin, grid_size)


func _layout_dock(seat: int, rect: Rect2) -> void:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	var inner := clampf(rect.size.x * 0.07, 14.0, 24.0)
	var gap := 8.0
	var key := minf((rect.size.x - inner * 2.0 - gap * 2.0) / 3.0, rect.size.y * 0.105)
	key = maxf(48.0, key)
	var block := Vector2(key * 3.0 + gap * 2.0, key * 3.0 + gap * 2.0)
	var start_y := rect.position.y + maxf(118.0, rect.size.y * 0.24)
	var origin := Vector2(rect.position.x + (rect.size.x - block.x) * 0.5, start_y)
	var slots := {
		"up": Vector2(1, 0),
		"left": Vector2(0, 1),
		"right": Vector2(2, 1),
		"down": Vector2(1, 2),
	}
	for action in slots:
		var slot: Vector2 = slots[action]
		_button_entries.append({
			"seat": seat,
			"action": action,
			"rect": Rect2(origin + Vector2(slot.x * (key + gap), slot.y * (key + gap)), Vector2(key, key)),
		})
	var fire_radius := clampf(key * 0.72, 38.0, 62.0)
	var fire_center := Vector2(origin.x + block.x * 0.5, origin.y + block.y + 22.0 + fire_radius)
	_button_entries.append({
		"seat": seat,
		"action": "fire",
		"rect": Rect2(fire_center - Vector2(fire_radius, fire_radius), Vector2(fire_radius * 2.0, fire_radius * 2.0)),
		"circle": true,
		"center": fire_center,
		"radius": fire_radius,
	})


func _cell_center(cell: Vector2i) -> Vector2:
	return _grid_origin + (Vector2(cell) + Vector2(0.5, 0.5)) * _cell_size


func _float_point(x: float, y: float) -> Vector2:
	return _grid_origin + Vector2(x, y) * _cell_size


func _draw() -> void:
	if engine == null or _board_rect.size.x <= 1.0:
		return
	var shake := _shake
	_draw_board_card(shake)
	_draw_grid(shake)
	_draw_movers(shake)
	_draw_targets(shake)
	_draw_pickups(shake)
	_draw_goals(shake)
	_draw_checkpoints(shake)
	_draw_emitters(shake)
	_draw_gates(shake)
	_draw_tanks(shake)
	_draw_bullets(shake)
	_draw_effects(shake)
	_draw_dock(0, _left_dock_rect if engine.tank_count() == 2 else _right_dock_rect)
	if engine.tank_count() == 2:
		_draw_dock(1, _right_dock_rect)
	_draw_header()
	_draw_notice()


func _draw_board_card(shake: Vector2) -> void:
	var rect := Rect2(_board_rect.position + shake, _board_rect.size)
	draw_style_box(
		_cached_style("board_card", PlaygroundUI.mix(soft, Color.WHITE, 0.16), 30, PlaygroundUI.mix(accent, Color.WHITE, 0.48), 2, 10, Color(0.06, 0.09, 0.14, 0.14)),
		rect
	)
	draw_style_box(
		_cached_style("grid_paper", Color("#fbfaf4"), 24, PlaygroundUI.mix(accent, Color.WHITE, 0.64), 1),
		Rect2(_grid_rect.position - Vector2(12, 12) + shake, _grid_rect.size + Vector2(24, 24))
	)


func _draw_grid(shake: Vector2) -> void:
	var width: int = int(engine.width())
	var height: int = int(engine.height())
	var level: Dictionary = engine.state.get("level", {})
	var layout: Array = level.get("layout", [])
	for y in height:
		var row := str(layout[y]) if y < layout.size() else ""
		for x in width:
			var cell := Vector2i(x, y)
			var rect := Rect2(_grid_origin + Vector2(cell) * _cell_size + shake, Vector2(_cell_size, _cell_size)).grow(-1.5)
			var tile := row.substr(x, 1) if x < row.length() else "#"
			if tile == "#":
				_draw_wall_tile(rect)
			else:
				var shade := 0.965 if (x + y) % 2 == 0 else 0.985
				draw_style_box(
					_cached_style("grid_%s_%d" % [shade, int(_cell_size)], PlaygroundUI.mix(soft, Color.WHITE, shade), maxi(4, int(_cell_size * 0.10)), Color(accent, 0.045), 1),
					rect
				)
				if (x + y) % 3 == 0:
					draw_circle(rect.position + Vector2(_cell_size * 0.12, _cell_size * 0.12), maxf(1.0, _cell_size * 0.018), Color(accent, 0.08))


func _draw_wall_tile(rect: Rect2) -> void:
	var wall := PlaygroundUI.mix(accent, Color("#6e7782"), 0.38)
	draw_style_box(
		_cached_style("wall_%d" % int(_cell_size), wall, maxi(4, int(_cell_size * 0.12)), PlaygroundUI.mix(wall, Color.BLACK, 0.25), 2, 3, Color(0.04, 0.06, 0.09, 0.18)),
		rect.grow(-2.0)
	)
	draw_line(
		rect.position + Vector2(_cell_size * 0.18, _cell_size * 0.30),
		rect.position + Vector2(_cell_size * 0.82, _cell_size * 0.30),
		Color(1, 1, 1, 0.18),
		maxf(1.0, _cell_size * 0.025),
		true
	)
	draw_line(
		rect.position + Vector2(_cell_size * 0.30, _cell_size * 0.54),
		rect.position + Vector2(_cell_size * 0.70, _cell_size * 0.54),
		Color(0, 0, 0, 0.12),
		maxf(1.0, _cell_size * 0.018),
		true
	)


func _draw_movers(shake: Vector2) -> void:
	var movers: Array = engine.state.get("level", {}).get("movers", [])
	for mover_value in movers:
		if not mover_value is Dictionary:
			continue
		var mover: Dictionary = mover_value
		var path: Array = mover.get("path", [])
		for index in maxi(0, path.size() - 1):
			var first := _cell_center(Vector2i(int(path[index].x), int(path[index].y))) + shake
			var second := _cell_center(Vector2i(int(path[index + 1].x), int(path[index + 1].y))) + shake
			draw_dashed_line(first, second, Color(accent, 0.22), maxf(1.5, _cell_size * 0.026), 5.0, true)
		for point in path:
			draw_circle(_cell_center(Vector2i(int(point.x), int(point.y))) + shake, maxf(2.0, _cell_size * 0.035), Color(accent, 0.30))
		var cell: Vector2i = engine.mover_cell(mover)
		if cell.x < 0:
			continue
		var rect := Rect2(_grid_origin + Vector2(cell) * _cell_size + shake, Vector2(_cell_size, _cell_size)).grow(-_cell_size * 0.10)
		var fill := PlaygroundUI.mix(accent, Color("#c9b06b"), 0.34)
		draw_style_box(
			_cached_style("mover_%d" % int(_cell_size), fill, maxi(6, int(_cell_size * 0.16)), PlaygroundUI.mix(fill, Color.BLACK, 0.28), 2, 4, Color(0, 0, 0, 0.18)),
			rect
		)
		var stripe := PlaygroundUI.mix(fill, Color.WHITE, 0.36)
		for offset in [-0.22, 0.0, 0.22]:
			draw_line(
				rect.position + Vector2(rect.size.x * (0.20 + offset), rect.size.y * 0.78),
				rect.position + Vector2(rect.size.x * (0.58 + offset), rect.size.y * 0.22),
				Color(stripe, 0.74),
				maxf(1.5, _cell_size * 0.035),
				true
			)


func _draw_targets(shake: Vector2) -> void:
	var targets: Array = engine.state.get("level", {}).get("targets", [])
	for target_value in targets:
		if not target_value is Dictionary:
			continue
		var target: Dictionary = target_value
		var center := _cell_center(Vector2i(int(target.x), int(target.y))) + shake
		var active: bool = bool(engine.target_active(str(target.get("id", ""))))
		var radius := _cell_size * 0.34
		draw_circle(center + Vector2(0, _cell_size * 0.28), radius * 0.92, Color(0.04, 0.06, 0.09, 0.12))
		draw_circle(center, radius, PlaygroundUI.mix(accent, Color.WHITE, 0.88 if not active else 0.68))
		draw_arc(center, radius, 0, TAU, 36, Color(accent, 0.55 if not active else 0.25), maxf(1.5, _cell_size * 0.03), true)
		draw_arc(center, radius * 0.68, 0, TAU, 30, Color(accent, 0.50 if not active else 0.22), maxf(1.0, _cell_size * 0.022), true)
		draw_circle(center, radius * 0.24, Color(accent, 0.66 if not active else 0.30))
		if active:
			var glow := 0.5 + 0.5 * sin(_clock * 5.0)
			draw_arc(center, radius * 1.15, 0, TAU, 36, Color("#7fb58a", 0.25 + glow * 0.20), maxf(2.0, _cell_size * 0.04), true)
			_draw_check(center, _cell_size * 0.16, Color("#4d8f66"))
		else:
			draw_line(center + Vector2(-radius * 0.72, 0), center + Vector2(radius * 0.72, 0), Color(accent, 0.42), maxf(1.0, _cell_size * 0.018), true)
			draw_line(center + Vector2(0, -radius * 0.72), center + Vector2(0, radius * 0.72), Color(accent, 0.42), maxf(1.0, _cell_size * 0.018), true)


func _draw_pickups(shake: Vector2) -> void:
	var pickups: Array = engine.state.get("level", {}).get("pickups", [])
	for pickup_value in pickups:
		if not pickup_value is Dictionary:
			continue
		var pickup: Dictionary = pickup_value
		if engine.pickup_collected(str(pickup.get("id", ""))):
			continue
		var cell := Vector2i(int(pickup.x), int(pickup.y))
		var bob := sin(_clock * 3.2 + float(cell.x) * 0.7 + float(cell.y)) * _cell_size * 0.035
		var center := _cell_center(cell) + Vector2(0, bob) + shake
		var radius := _cell_size * 0.18
		draw_circle(center + Vector2(0, _cell_size * 0.26), radius * 1.15, Color(0.04, 0.06, 0.09, 0.10))
		draw_circle(center, radius * 1.75, Color("#f6dc8c", 0.20))
		_draw_star_shape(center, radius, Color("#d7a833"), Color("#fff7ce"))


func _draw_goals(shake: Vector2) -> void:
	var goals: Array = engine.state.get("level", {}).get("goals", [])
	for index in goals.size():
		if not goals[index] is Dictionary:
			continue
		var goal: Dictionary = goals[index]
		var center := _cell_center(Vector2i(int(goal.x), int(goal.y))) + shake
		var lit: bool = bool(engine.goal_lit(index))
		draw_circle(center + Vector2(0, _cell_size * 0.25), _cell_size * 0.32, Color(0.04, 0.06, 0.09, 0.12))
		draw_circle(center, _cell_size * 0.33, Color("#f8f2dc") if not lit else Color("#f9e7a7"))
		draw_arc(center, _cell_size * 0.35, 0, TAU, 32, Color("#bfa15c" if not lit else "#c28e20"), maxf(1.5, _cell_size * 0.035), true)
		if lit:
			var glow := 0.5 + 0.5 * sin(_clock * 4.4 + index)
			draw_arc(center, _cell_size * 0.48, 0, TAU, 32, Color("#f0c34d", 0.24 + glow * 0.18), maxf(2.0, _cell_size * 0.04), true)
		var pole_top := center + Vector2(-_cell_size * 0.13, -_cell_size * 0.40)
		draw_line(pole_top, center + Vector2(-_cell_size * 0.13, _cell_size * 0.24), Color("#7a6a58"), maxf(1.8, _cell_size * 0.032), true)
		var flag := PackedVector2Array([
			pole_top,
			pole_top + Vector2(_cell_size * 0.34, _cell_size * 0.11),
			pole_top + Vector2(0, _cell_size * 0.24),
		])
		draw_colored_polygon(flag, Color("#d3a438") if not lit else Color("#e8b849"))
		draw_circle(center + Vector2(_cell_size * 0.06, _cell_size * 0.17), maxf(1.5, _cell_size * 0.035), Color("#fff8dd"))


func _draw_checkpoints(shake: Vector2) -> void:
	var checkpoints: Array = engine.state.get("level", {}).get("checkpoints", [])
	for checkpoint_value in checkpoints:
		if not checkpoint_value is Dictionary:
			continue
		var checkpoint: Dictionary = checkpoint_value
		var center := _cell_center(Vector2i(int(checkpoint.x), int(checkpoint.y))) + shake
		var reached: bool = bool(engine.checkpoint_reached(str(checkpoint.get("id", ""))))
		draw_arc(center, _cell_size * 0.27, 0, TAU, 28, Color("#7f9a86" if reached else "#9aa6b2", 0.60), maxf(1.2, _cell_size * 0.024), true)
		draw_circle(center, _cell_size * 0.08, Color("#7f9a86" if reached else "#b2bdc8", 0.55))
		draw_line(center + Vector2(-_cell_size * 0.20, _cell_size * 0.10), center + Vector2(-_cell_size * 0.20, -_cell_size * 0.24), Color("#7f6c59"), maxf(1.2, _cell_size * 0.02), true)
		draw_colored_polygon(PackedVector2Array([
			center + Vector2(-_cell_size * 0.20, -_cell_size * 0.24),
			center + Vector2(_cell_size * 0.06, -_cell_size * 0.16),
			center + Vector2(-_cell_size * 0.20, -_cell_size * 0.05),
		]), Color("#86a98d") if reached else Color("#b7c5c0"))


func _draw_emitters(shake: Vector2) -> void:
	var emitters: Array = engine.state.get("level", {}).get("emitters", [])
	for index in emitters.size():
		if not emitters[index] is Dictionary:
			continue
		var emitter: Dictionary = emitters[index]
		var cell := Vector2i(int(emitter.x), int(emitter.y))
		var center := _cell_center(cell) + shake
		var direction := str(emitter.get("dir", "down"))
		var angle := _direction_angle(direction)
		var disabled: bool = not str(emitter.get("disableByTarget", "")).is_empty() and bool(engine.target_active(str(emitter.get("disableByTarget", ""))))
		draw_set_transform(center, angle, Vector2.ONE)
		draw_style_box(
			PlaygroundUI.style(PlaygroundUI.mix(accent, Color("#b9c2cb"), 0.36), maxi(4, int(_cell_size * 0.12)), PlaygroundUI.mix(accent, Color.BLACK, 0.22), 2),
			Rect2(-Vector2(_cell_size * 0.20, _cell_size * 0.24), Vector2(_cell_size * 0.40, _cell_size * 0.42))
		)
		draw_style_box(
			PlaygroundUI.style(Color("#e9eef2") if disabled else Color("#f6fbfd"), maxi(4, int(_cell_size * 0.09)), PlaygroundUI.mix(accent, Color.WHITE, 0.35), 1),
			Rect2(-Vector2(_cell_size * 0.14, -_cell_size * 0.55), Vector2(_cell_size * 0.28, _cell_size * 0.38))
		)
		draw_circle(Vector2(0, -_cell_size * 0.58), _cell_size * 0.085, Color("#9fc6d4") if not disabled else Color("#b8c4c8"))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		if not disabled:
			var pulse: float = 1.0 - float(engine.emitter_next_ratio(emitter, index))
			draw_arc(center, _cell_size * 0.55, 0, TAU, 28, Color("#8cc7da", 0.10 + pulse * 0.16), maxf(1.5, _cell_size * 0.035), true)


func _draw_gates(shake: Vector2) -> void:
	var gates: Array = engine.state.get("level", {}).get("gates", [])
	for gate_value in gates:
		if not gate_value is Dictionary:
			continue
		var gate: Dictionary = gate_value
		var opened := str(gate.get("id", "")) in (engine.state.get("gatesOpen", []) as Array)
		for cell_value in gate.get("cells", []):
			if not cell_value is Dictionary:
				continue
			var cell := Vector2i(int(cell_value.x), int(cell_value.y))
			var rect := Rect2(_grid_origin + Vector2(cell) * _cell_size + shake, Vector2(_cell_size, _cell_size)).grow(-_cell_size * 0.08)
			if opened:
				_draw_dashed_rect(rect, Color(accent, 0.20), maxf(1.0, _cell_size * 0.022))
				continue
			var fill := PlaygroundUI.mix(accent, Color("#e6d6a9"), 0.28)
			draw_style_box(
				PlaygroundUI.style(fill, maxi(4, int(_cell_size * 0.13)), PlaygroundUI.mix(fill, Color.BLACK, 0.24), 2, 3, Color(0.04, 0.06, 0.09, 0.15)),
				rect
			)
			for stripe in 3:
				var y := rect.position.y + rect.size.y * (0.22 + float(stripe) * 0.23)
				draw_line(
					Vector2(rect.position.x + rect.size.x * 0.16, y),
					Vector2(rect.end.x - rect.size.x * 0.16, y),
					Color(1, 1, 1, 0.30),
					maxf(1.5, _cell_size * 0.030),
					true
				)
			draw_circle(rect.get_center(), _cell_size * 0.052, Color("#b68b36"))


func _draw_tanks(shake: Vector2) -> void:
	var tanks: Array = engine.state.get("tanks", [])
	for index in tanks.size():
		var tank: Dictionary = tanks[index]
		var center := _cell_center(Vector2i(int(tank.x), int(tank.y))) + shake
		var angle := _direction_angle(str(tank.get("dir", "right")))
		var tint := _seat_color(index)
		var alpha := 1.0
		if float(tank.get("invuln", 0.0)) > 0.0:
			alpha = 0.62 + 0.38 * absf(sin(_clock * 13.0))
		draw_set_transform(center + Vector2(0, _cell_size * 0.27), 0.0, Vector2(1.0, 0.36))
		draw_circle(Vector2.ZERO, _cell_size * 0.36, Color(0.04, 0.06, 0.09, 0.20 * alpha))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		draw_set_transform(center, angle, Vector2.ONE)
		var s := _cell_size
		draw_style_box(
			PlaygroundUI.style(Color(tint.darkened(0.26), alpha), maxi(4, int(s * 0.075)), Color(tint.darkened(0.45), alpha), 1),
			Rect2(-Vector2(s * 0.31, s * 0.28), Vector2(s * 0.20, s * 0.56))
		)
		draw_style_box(
			PlaygroundUI.style(Color(tint.darkened(0.26), alpha), maxi(4, int(s * 0.075)), Color(tint.darkened(0.45), alpha), 1),
			Rect2(Vector2(s * 0.11, -s * 0.28), Vector2(s * 0.20, s * 0.56))
		)
		draw_style_box(
			PlaygroundUI.style(Color(tint, alpha), maxi(5, int(s * 0.13)), Color(tint.darkened(0.35), alpha), maxf(1.0, s * 0.028), 3, Color(0, 0, 0, 0.16)),
			Rect2(-Vector2(s * 0.26, -s * 0.20), Vector2(s * 0.52, s * 0.42))
		)
		draw_circle(Vector2(0, s * 0.00), s * 0.17, Color(tint.lightened(0.16), alpha))
		draw_arc(Vector2(0, s * 0.00), s * 0.17, 0, TAU, 28, Color(tint.darkened(0.28), alpha), maxf(1.0, s * 0.024), true)
		draw_style_box(
			PlaygroundUI.style(Color(tint.darkened(0.18), alpha), maxi(3, int(s * 0.07)), Color(tint.darkened(0.42), alpha), 1),
			Rect2(-Vector2(s * 0.055, -s * 0.46), Vector2(s * 0.11, s * 0.34))
		)
		draw_circle(Vector2(0, -s * 0.48), s * 0.065, Color(tint.lightened(0.26), alpha))
		draw_circle(Vector2(-s * 0.13, s * 0.24), s * 0.045, Color(tint.darkened(0.16), alpha))
		draw_circle(Vector2(s * 0.13, s * 0.24), s * 0.045, Color(tint.darkened(0.16), alpha))
		if engine.tank_count() > 1:
			draw_circle(Vector2(s * 0.18, -s * 0.18), s * 0.085, Color("#fdf8e7"))
			draw_string(PlaygroundUI.font(), Vector2(s * 0.18 - s * 0.05, -s * 0.18 + s * 0.052), str(index + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, maxi(10, int(s * 0.11)), tint.darkened(0.30))
		var shield := clampi(int(tank.get("shield", 0)), 0, 3)
		for bubble_index in 3:
			var bubble_angle := -PI * 0.5 + float(bubble_index) * TAU / 3.0 + _clock * 0.25
			var bubble_center := Vector2(cos(bubble_angle), sin(bubble_angle)) * s * 0.31
			var filled := bubble_index < shield
			draw_circle(bubble_center, s * 0.075, Color(0.78, 0.91, 0.98, 0.42 if filled else 0.10))
			draw_arc(bubble_center, s * 0.075, 0, TAU, 18, Color(1, 1, 1, 0.68 if filled else 0.18), maxf(1.0, s * 0.016), true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_bullets(shake: Vector2) -> void:
	var bullets: Array = engine.state.get("bullets", [])
	for bullet_value in bullets:
		if not bullet_value is Dictionary:
			continue
		var bullet: Dictionary = bullet_value
		var point := _float_point(float(bullet.x), float(bullet.y)) + shake
		var direction := _direction_vector(str(bullet.get("dir", "")))
		var radius := maxf(4.0, _cell_size * 0.15)
		var tint := Color("#d9f3fb") if str(bullet.get("kind", "")) == "player" else Color("#f6dfb2")
		for trail_index in 2:
			var trail := point - direction * _cell_size * (0.18 + float(trail_index) * 0.14)
			draw_circle(trail, radius * (0.55 - float(trail_index) * 0.12), Color(tint, 0.22 - float(trail_index) * 0.06))
		draw_circle(point, radius, Color(tint, 0.88))
		draw_circle(point, radius * 0.62, Color(1, 1, 1, 0.82))
		draw_circle(point - Vector2(radius * 0.28, radius * 0.28), radius * 0.22, Color(1, 1, 1, 0.95))


func _draw_effects(shake: Vector2) -> void:
	for bubble in _bubbles:
		if not bool(bubble.get("active", false)):
			continue
		var bubble_life := 1.0 - float(bubble.age) / maxf(0.001, float(bubble.life))
		var bubble_color: Color = bubble.color
		bubble_color.a *= clampf(bubble_life, 0.0, 1.0)
		draw_circle(Vector2(bubble.position) + shake, float(bubble.size) * (0.6 + bubble_life * 0.4), bubble_color)
	for particle in _particles:
		if not bool(particle.get("active", false)):
			continue
		var position: Vector2 = particle.position + shake
		var life_ratio := 1.0 - float(particle.age) / maxf(0.001, float(particle.life))
		var color: Color = particle.color
		color.a *= clampf(life_ratio, 0.0, 1.0)
		if str(particle.kind) == "star":
			_draw_star_shape(position, float(particle.size) * (0.5 + life_ratio * 0.5), color, Color(1, 1, 1, 0.45))
		else:
			draw_circle(position, float(particle.size) * (0.5 + life_ratio * 0.5), color)
			if str(particle.kind) == "bubble":
				draw_circle(position - Vector2(particle.size * 0.24, particle.size * 0.24), maxf(1.0, particle.size * 0.22), Color(1, 1, 1, 0.55 * life_ratio))
	for ripple in _ripples:
		var ratio := float(ripple.age) / maxf(0.001, float(ripple.life))
		var color: Color = ripple.color
		color.a *= clampf(1.0 - ratio, 0.0, 1.0)
		draw_arc(ripple.position + shake, float(ripple.radius) * (0.4 + ratio * 1.6), 0, TAU, 32, color, maxf(1.5, _cell_size * 0.035), true)
	if _flash > 0.0:
		draw_circle(_flash_position + shake, _flash_radius * (0.65 + _flash * 0.6), Color(_flash_color, _flash * 0.34))
	var font := PlaygroundUI.font()
	for popup in _popups:
		var ratio := 1.0 - float(popup.age) / maxf(0.001, float(popup.life))
		var color: Color = popup.color
		color.a *= clampf(ratio, 0.0, 1.0)
		var pos: Vector2 = popup.position + shake + Vector2(0, -26.0 * (1.0 - ratio))
		draw_string(font, pos, str(popup.text), HORIZONTAL_ALIGNMENT_CENTER, 180.0, int(popup.font_size), color)


func _draw_dock(seat: int, rect: Rect2) -> void:
	if rect.size.x <= 0.0:
		return
	var tint := _seat_color(seat)
	draw_style_box(
		_cached_style("dock_%s" % seat, PlaygroundUI.mix(tint, Color.WHITE, 0.86), 26, PlaygroundUI.mix(tint, Color.WHITE, 0.45), 2, 6, Color(0.05, 0.07, 0.10, 0.12)),
		rect
	)
	var inner := clampf(rect.size.x * 0.07, 14.0, 24.0)
	var tag: String = "左操作区" if seat == 0 and int(engine.tank_count()) == 2 else "右操作区" if seat == 1 else "单人操作区"
	draw_string(PlaygroundUI.font(), rect.position + Vector2(inner, 30), tag, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - inner * 2.0, 14, Color(tint.darkened(0.18), 0.72))
	var player_name := "小卫士"
	if seat < players.size():
		player_name = str(players[seat].get("name", "小卫士"))
	draw_string(PlaygroundUI.font(), rect.position + Vector2(inner, 60), player_name, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - inner * 2.0, 24, PlaygroundUI.INK)
	var tank: Dictionary = engine.state.get("tanks", [])[seat] if seat < (engine.state.get("tanks", []) as Array).size() else {}
	var shield := clampi(int(tank.get("shield", 0)), 0, 3)
	for index in 3:
		var centre := rect.position + Vector2(inner + 12.0 + float(index) * 31.0, 94.0)
		draw_circle(centre, 10.0, Color(0.78, 0.91, 0.98, 0.55 if index < shield else 0.14))
		draw_arc(centre, 10.0, 0, TAU, 20, Color(1, 1, 1, 0.70 if index < shield else 0.24), 1.5, true)
	for entry in _button_entries:
		if int(entry.get("seat", -1)) != seat:
			continue
		if bool(entry.get("circle", false)):
			_draw_fire_button(entry, tint)
		else:
			_draw_direction_button(entry, tint)
	var foot := rect.position + Vector2(inner, rect.size.y - 22.0)
	draw_string(PlaygroundUI.font(), foot, "同时按方向键和开火键也行", HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - inner * 2.0, 13, Color(PlaygroundUI.INK_SOFT, 0.72))


func _draw_direction_button(entry: Dictionary, tint: Color) -> void:
	var rect: Rect2 = entry.rect
	var action := str(entry.action)
	var pressed := _slot_pressed(int(entry.seat), action)
	var fill := PlaygroundUI.mix(tint, Color.WHITE, 0.18 if pressed else 0.68)
	draw_style_box(
		PlaygroundUI.style(fill, maxi(8, int(_cell_size * 0.17)), tint.darkened(0.16), 2 if pressed else 1, 4 if pressed else 2, Color(0.04, 0.06, 0.09, 0.14)),
		rect
	)
	_draw_direction_arrow(rect.get_center(), minf(rect.size.x, rect.size.y) * 0.24, action, tint.darkened(0.35))
	draw_string(
		PlaygroundUI.font(),
		rect.position + Vector2(4, rect.size.y - 8),
		{"up":"上","down":"下","left":"左","right":"右"}.get(action, ""),
		HORIZONTAL_ALIGNMENT_CENTER,
		rect.size.x - 8.0,
		maxi(12, int(rect.size.y * 0.15)),
		PlaygroundUI.INK
	)


func _draw_fire_button(entry: Dictionary, tint: Color) -> void:
	var center: Vector2 = entry.center
	var radius := float(entry.radius)
	var pressed := _slot_pressed(int(entry.seat), "fire")
	draw_circle(center + Vector2(0, 4), radius, Color(0.04, 0.06, 0.09, 0.16))
	draw_circle(center, radius, PlaygroundUI.mix(tint, Color.WHITE, 0.10 if pressed else 0.30))
	draw_arc(center, radius, 0, TAU, 44, Color(tint.darkened(0.22), 0.80), 2.0, true)
	for index in 3:
		var angle := -PI * 0.75 + float(index) * 0.45
		var point := center + Vector2(cos(angle), sin(angle)) * radius * 0.40
		draw_circle(point, radius * 0.14, Color(0.86, 0.95, 0.99, 0.82))
		draw_circle(point - Vector2(radius * 0.03, radius * 0.03), radius * 0.045, Color(1, 1, 1, 0.92))
	draw_string(PlaygroundUI.font(), center + Vector2(-radius, radius * 0.30), "开火", HORIZONTAL_ALIGNMENT_CENTER, radius * 2.0, maxi(16, int(radius * 0.28)), Color.WHITE)


func _slot_pressed(seat: int, action: String) -> bool:
	for pointer in _pointers.values():
		var slot: Dictionary = pointer.get("slot", {})
		if int(slot.get("seat", -1)) == seat and str(slot.get("action", "")) == action:
			return true
	return false


func _draw_header() -> void:
	var level: Dictionary = engine.state.get("level", {})
	var level_id := int(engine.state.get("levelId", 1))
	var title := "第 %s 关 · %s" % [level_id, str(level.get("title", "坦克小卫士"))]
	if str(engine.state.get("modeId", "")) == "classic":
		title = "合作图 %s · %s" % [level_id, str(level.get("title", "坦克小卫士"))]
	var font := PlaygroundUI.font()
	draw_string(font, _board_rect.position + Vector2(26, 35), title, HORIZONTAL_ALIGNMENT_LEFT, _board_rect.size.x - 380.0, 22, accent)
	var targets: Array = level.get("targets", [])
	var active_targets := 0
	for target in targets:
		if target is Dictionary and engine.target_active(str(target.get("id", ""))):
			active_targets += 1
	var pickups: Array = level.get("pickups", [])
	var stats_parts: Array[String] = []
	if not targets.is_empty():
		stats_parts.append("信号靶 %s/%s" % [active_targets, targets.size()])
	if not pickups.is_empty():
		stats_parts.append("星徽 %s/%s" % [(engine.state.get("pickupsCollected", []) as Array).size(), pickups.size()])
	stats_parts.append("泡泡弹 %s/%s" % [int(engine.state.get("shotsFired", 0)), int(level.get("parShots", 0))])
	draw_string(font, _board_rect.position + Vector2(26, 58), " · ".join(PackedStringArray(stats_parts)), HORIZONTAL_ALIGNMENT_LEFT, _board_rect.size.x - 52.0, 14, PlaygroundUI.INK_SOFT)
	var goals: Array = level.get("goals", [])
	if goals.size() > 1:
		var lit := 0
		for index in goals.size():
			if engine.goal_lit(index):
				lit += 1
		draw_string(font, _board_rect.position + Vector2(_board_rect.size.x - 160.0, 35), "终点 %s/%s" % [lit, goals.size()], HORIZONTAL_ALIGNMENT_RIGHT, 132.0, 15, accent)


func _draw_notice() -> void:
	if _notice_time <= 0.0 or _notice.is_empty():
		return
	var alpha := clampf(_notice_time / 0.35, 0.0, 1.0)
	var font := PlaygroundUI.font()
	var width := minf(_board_rect.size.x - 80.0, font.get_string_size(_notice, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x + 42.0)
	var height := 38.0
	var center := Vector2(_board_rect.get_center().x, _board_rect.position.y + _board_rect.size.y - 34.0)
	draw_style_box(
		PlaygroundUI.style(Color(0.15, 0.18, 0.22, 0.90 * alpha), 14, Color(1, 1, 1, 0.10 * alpha), 1),
		Rect2(center - Vector2(width * 0.5, height * 0.5), Vector2(width, height))
	)
	draw_string(font, center + Vector2(-width * 0.5 + 21.0, 6.0), _notice, HORIZONTAL_ALIGNMENT_LEFT, width - 32.0, 17, Color(1, 1, 1, alpha))


func _draw_direction_arrow(center: Vector2, radius: float, action: String, color: Color) -> void:
	var direction := _direction_vector({"up":"up","down":"down","left":"left","right":"right"}.get(action, "up"))
	var tip := center + direction * radius
	var tail := center - direction * radius * 0.72
	draw_line(tail, center + direction * radius * 0.18, color, maxf(2.0, radius * 0.22), true)
	var side := direction.orthogonal() * radius * 0.54
	draw_colored_polygon(PackedVector2Array([
		tip,
		center + direction * radius * 0.12 + side,
		center + direction * radius * 0.12 - side,
	]), color)


func _draw_star_shape(center: Vector2, radius: float, color: Color, highlight: Color = Color.TRANSPARENT) -> void:
	var points := PackedVector2Array()
	for index in 10:
		var ring := radius if index % 2 == 0 else radius * 0.44
		var angle := -PI * 0.5 + float(index) * PI / 5.0
		points.append(center + Vector2(cos(angle), sin(angle)) * ring)
	draw_colored_polygon(points, color)
	var outline := points.duplicate()
	outline.append(points[0])
	draw_polyline(outline, highlight if highlight.a > 0.0 else Color(1, 1, 1, 0.50), 1.3, true)
	if highlight.a > 0.0:
		draw_circle(center - Vector2(radius * 0.18, radius * 0.18), radius * 0.14, Color(1, 1, 1, 0.65))


func _draw_check(center: Vector2, radius: float, color: Color) -> void:
	draw_line(center + Vector2(-radius, 0), center + Vector2(-radius * 0.28, radius * 0.72), color, maxf(2.0, radius * 0.34), true)
	draw_line(center + Vector2(-radius * 0.28, radius * 0.72), center + Vector2(radius, -radius * 0.70), color, maxf(2.0, radius * 0.34), true)


func _draw_dashed_rect(rect: Rect2, color: Color, width: float) -> void:
	draw_dashed_line(rect.position, Vector2(rect.end.x, rect.position.y), color, width, 5.0, true)
	draw_dashed_line(Vector2(rect.end.x, rect.position.y), rect.end, color, width, 5.0, true)
	draw_dashed_line(rect.end, Vector2(rect.position.x, rect.end.y), color, width, 5.0, true)
	draw_dashed_line(Vector2(rect.position.x, rect.end.y), rect.position, color, width, 5.0, true)


func _seat_color(seat: int) -> Color:
	return Color("#4e7fa8") if seat == 0 else Color("#b9793f")


func _effects_scale() -> float:
	var tree := get_tree()
	if tree == null:
		return 1.0
	var quality := tree.root.get_node_or_null("RuntimeQuality")
	if quality == null:
		return 1.0
	return clampf(float(quality.get("effects_scale")), 0.35, 1.0)


func _direction_vector(direction: String) -> Vector2:
	match direction:
		"up":
			return Vector2.UP
		"down":
			return Vector2.DOWN
		"left":
			return Vector2.LEFT
		"right":
			return Vector2.RIGHT
	return Vector2.UP


func _direction_angle(direction: String) -> float:
	match direction:
		"right":
			return PI * 0.5
		"down":
			return PI
		"left":
			return -PI * 0.5
	return 0.0


func _ensure_particle_pool() -> void:
	while _particles.size() < MAX_PARTICLES:
		_particles.append({
			"active": false,
			"position": Vector2.ZERO,
			"velocity": Vector2.ZERO,
			"life": 1.0,
			"age": 0.0,
			"size": 4.0,
			"color": Color.WHITE,
			"kind": "bubble",
		})


func _ensure_bubble_pool() -> void:
	while _bubbles.size() < MAX_BUBBLES:
		_bubbles.append({
			"active": false,
			"position": Vector2.ZERO,
			"velocity": Vector2.ZERO,
			"life": 0.4,
			"age": 0.0,
			"size": 4.0,
			"color": Color(0.82, 0.94, 0.98, 0.7),
		})


func _acquire_particle() -> Dictionary:
	_ensure_particle_pool()
	var quality := _effects_scale()
	var cap := maxi(36, int(float(MAX_PARTICLES) * quality))
	if _active_particles >= cap:
		return {}
	for offset in range(MAX_PARTICLES):
		var index := (_particle_cursor + offset) % MAX_PARTICLES
		var particle: Dictionary = _particles[index]
		if bool(particle.get("active", false)):
			continue
		particle.active = true
		_active_particles += 1
		_particle_cursor = (index + 1) % MAX_PARTICLES
		return particle
	return {}


func _acquire_bubble() -> Dictionary:
	_ensure_bubble_pool()
	for offset in range(MAX_BUBBLES):
		var index := (_bubble_cursor + offset) % MAX_BUBBLES
		var bubble: Dictionary = _bubbles[index]
		if bool(bubble.get("active", false)):
			continue
		bubble.active = true
		_bubble_cursor = (index + 1) % MAX_BUBBLES
		return bubble
	return {}


func _emit_trail_bubbles(position: Vector2, direction: Vector2, color: Color, count: int) -> void:
	var quality := _effects_scale()
	var limit := maxi(1, int(float(count) * quality))
	for index in limit:
		var bubble := _acquire_bubble()
		if bubble.is_empty():
			break
		bubble.position = position - direction * randf_range(0.0, 16.0) + Vector2(randf_range(-5, 5), randf_range(-5, 5))
		bubble.velocity = -direction * randf_range(18.0, 46.0) + Vector2(randf_range(-16, 16), randf_range(-16, 16))
		bubble.life = randf_range(0.22, 0.46)
		bubble.age = 0.0
		bubble.size = randf_range(2.0, 5.0)
		bubble.color = Color(color, 0.62)


func _emit_bubbles(position: Vector2, color: Color, count: int, speed_scale: float = 1.0, kind: String = "bubble") -> void:
	var quality := _effects_scale()
	var limit := maxi(2, int(float(count) * quality))
	for index in limit:
		var particle := _acquire_particle()
		if particle.is_empty():
			break
		var angle := randf_range(0.0, TAU)
		var speed := randf_range(24.0, 92.0) * speed_scale
		particle.position = position + Vector2(randf_range(-4, 4), randf_range(-4, 4))
		particle.velocity = Vector2(cos(angle), sin(angle)) * speed - Vector2(0, 22.0)
		particle.life = randf_range(0.34, 0.72)
		particle.age = 0.0
		particle.size = randf_range(2.0, 6.0) * (1.2 if kind == "star" else 1.0)
		particle.color = color
		particle.kind = kind


func _add_ripple(position: Vector2, color: Color, radius: float = 18.0, life: float = 0.45) -> void:
	_ripples.append({"position": position, "color": color, "radius": radius, "life": life, "age": 0.0})
	while _ripples.size() > MAX_RIPPLES:
		_ripples.pop_front()


func _add_popup(text: String, position: Vector2, color: Color, font_size: int = 22) -> void:
	_popups.append({"text": text, "position": position, "color": color, "life": 0.80, "age": 0.0, "font_size": font_size})
	while _popups.size() > MAX_POPUPS:
		_popups.pop_front()


func _cached_style(
	key: String,
	background: Color,
	radius: int,
	border_color: Color = Color.TRANSPARENT,
	border_width: int = 0,
	shadow_size: int = 0,
	shadow_color: Color = Color.TRANSPARENT
) -> StyleBoxFlat:
	if _style_cache.has(key):
		return _style_cache[key]
	var value := PlaygroundUI.style(background, radius, border_color, border_width, shadow_size, shadow_color)
	_style_cache[key] = value
	return value


func _update_effects(delta: float) -> void:
	for bubble in _bubbles:
		if not bool(bubble.get("active", false)):
			continue
		bubble.age = float(bubble.age) + delta
		if float(bubble.age) >= float(bubble.life):
			bubble.active = false
			continue
		bubble.position = Vector2(bubble.position) + Vector2(bubble.velocity) * delta
		bubble.velocity = Vector2(bubble.velocity) * (1.0 - minf(0.9, delta * 2.0))
	for particle in _particles:
		if not bool(particle.get("active", false)):
			continue
		particle.age = float(particle.age) + delta
		if float(particle.age) >= float(particle.life):
			particle.active = false
			_active_particles = maxi(0, _active_particles - 1)
			continue
		particle.position = Vector2(particle.position) + Vector2(particle.velocity) * delta
		particle.velocity = Vector2(particle.velocity) * (1.0 - minf(0.92, delta * 1.5)) + Vector2(0, 32.0 * delta)
	var kept_ripples: Array = []
	for ripple in _ripples:
		ripple.age = float(ripple.age) + delta
		if float(ripple.age) < float(ripple.life):
			kept_ripples.append(ripple)
	_ripples = kept_ripples
	var kept_popups: Array = []
	for popup in _popups:
		popup.age = float(popup.age) + delta
		if float(popup.age) < float(popup.life):
			kept_popups.append(popup)
	_popups = kept_popups
	_shake_time = maxf(0.0, _shake_time - delta)
	if _shake_time > 0.0:
		var strength := 4.0 * clampf(_shake_time / 0.28, 0.0, 1.0)
		_shake = Vector2(randf_range(-strength, strength), randf_range(-strength, strength))
	else:
		_shake = Vector2.ZERO
	_flash = maxf(0.0, _flash - delta * 5.2)


func consume_events(events: Array) -> void:
	for event_value in events:
		if not event_value is Dictionary:
			continue
		var event: Dictionary = event_value
		var event_type := str(event.get("type", ""))
		var point := _float_point(float(event.get("x", 0.0)) + 0.5, float(event.get("y", 0.0)) + 0.5)
		match event_type:
			"blocked":
				flash_notice(str(event.get("reason", "这里过不去")), 1.8)
				_emit_bubbles(point, Color("#c6d2dd"), 6, 0.55)
			"fire":
				_emit_bubbles(point, Color("#d7f2fb"), 10, 0.70)
				_emit_trail_bubbles(point, _direction_vector(str(event.get("dir", "right"))), Color("#d7f2fb"), 9)
				_add_ripple(point, Color("#bfe7f3"), _cell_size * 0.20, 0.30)
			"foam":
				_emit_bubbles(point, Color("#dbeaf2"), 8, 0.54)
				_emit_trail_bubbles(point, Vector2.UP, Color("#dbeaf2"), 5)
			"target":
				_add_ripple(point, Color("#7fb58a"), _cell_size * 0.35, 0.48)
				_emit_bubbles(point, Color("#8fc7a0"), 22, 0.72)
				_add_popup("信号靶亮了", point + Vector2(-70, -6), Color("#4d8f66"), 19)
			"gate":
				_add_ripple(point, Color("#d7b25c"), _cell_size * 0.42, 0.55)
				_add_popup("信号门打开", point + Vector2(-66, -6), Color("#9b7927"), 19)
			"star":
				_emit_bubbles(point, Color("#e8c44c"), 18, 0.64, "star")
				_add_ripple(point, Color("#f2d77b"), _cell_size * 0.26, 0.42)
				_add_popup("星徽 +1", point + Vector2(-54, -6), Color("#a37a1d"), 19)
			"checkpoint":
				_add_ripple(point, Color("#86a98d"), _cell_size * 0.30, 0.42)
				_add_popup("检查点", point + Vector2(-42, -6), Color("#5c7e64"), 18)
			"goal":
				_add_ripple(point, Color("#e7bd55"), _cell_size * 0.40, 0.55)
				_emit_bubbles(point, Color("#f1d47d"), 18, 0.62, "star")
			"shield_hit":
				_emit_bubbles(point, Color("#c6e7f2"), 20, 0.85)
				_add_ripple(point, Color("#a8d7e6"), _cell_size * 0.34, 0.42)
				_shake_time = 0.20
			"shield_break":
				var from_point := _float_point(float(event.get("fromX", 0)) + 0.5, float(event.get("fromY", 0)) + 0.5)
				_emit_bubbles(from_point, Color("#d4eef7"), 42, 1.15)
				_add_ripple(from_point, Color("#9bcfdf"), _cell_size * 0.55, 0.65)
				_add_popup("泡泡盾破了，回到检查点", from_point + Vector2(-130, -12), Color("#4e7b93"), 19)
				_flash = 0.22
				_flash_color = Color("#bde4f0")
				_flash_position = from_point
				_flash_radius = _cell_size * 0.65
				_shake_time = 0.32
			"emitter_fire":
				_emit_bubbles(point, Color("#f5dfb0"), 8, 0.55)
				_emit_trail_bubbles(point, _direction_vector(str(event.get("dir", "down"))), Color("#f5dfb0"), 6)
			"complete":
				_add_ripple(_grid_rect.get_center(), Color("#e7c258"), _cell_size * 0.8, 0.9)
				for index in 5:
					_emit_bubbles(_grid_rect.get_center() + Vector2(randf_range(-160, 160), randf_range(-90, 90)), Color("#f2d77b"), 8, 0.55, "star")
