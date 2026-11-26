class_name FruitField
extends Control

signal action_committed
signal game_finished

var engine: FruitRules
var accent := Color("#c25b42")
var game_screen: NativeGameScreen
var high_score := 0
var _pointers: Dictionary = {}
var _trails: Dictionary = {}
var _particles: Array = []
var _particle_cursor := 0
var _active_particles := 0
var _halves: Array = []
var _rings: Array = []
var _popups: Array = []
var _shake := Vector2.ZERO
var _shake_time := 0.0
var _shake_strength := 5.0
var _flash := 0.0
var _flash_color := Color.WHITE
var _flash_position := Vector2(0.5, 0.5)
var _flash_radius := 0.09
var _visual_scale := 1.0
var _focus_time := 0.0
var _clock := 0.0
var _last_touch_msec := -1000
var _completion_sent := false

const MAX_PARTICLES := 160
const MAX_TRAIL_POINTS := 48
const MAX_TRAILS := 4
const MAX_HALVES := 28
const MAX_RINGS := 14
const MAX_POPUPS := 18


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	custom_minimum_size = Vector2(560, 560)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	set_process(true)
	_ensure_particle_pool()
	resized.connect(queue_redraw)


func bind(value: FruitRules, screen: NativeGameScreen) -> void:
	engine = value
	game_screen = screen
	_completion_sent = false
	queue_redraw()


func cancel_inputs() -> void:
	_pointers.clear()
	_trails.clear()
	queue_redraw()


func suspend_effects() -> void:
	cancel_inputs()
	for particle in _particles:
		particle.active = false
	_active_particles = 0
	_halves.clear()
	_rings.clear()
	_popups.clear()
	_shake = Vector2.ZERO
	_shake_time = 0.0
	_flash = 0.0
	_visual_scale = 1.0
	_focus_time = 0.0
	queue_redraw()


func tick(delta: float) -> void:
	if engine == null or _blocked():
		return
	if engine.state.get("phase", "") != "playing":
		return
	if engine.tick(delta):
		_apply_events(engine.drain_events())
		queue_redraw()
	if engine.state.get("phase", "") == "result":
		_emit_finished()


func _process(delta: float) -> void:
	if _blocked():
		return
	_clock += delta
	_focus_time = maxf(0.0, _focus_time - delta)
	_visual_scale = lerpf(_visual_scale, 1.0, clampf(delta * 8.0, 0.0, 1.0))
	_update_effects(delta * _visual_scale)
	_update_trails()
	_shake_time = maxf(0.0, _shake_time - delta)
	if _shake_time > 0.0:
		var quality := clampf(RuntimeQuality.effects_scale, 0.35, 1.0)
		var decay := clampf(_shake_time / 0.42, 0.0, 1.0)
		var strength := _shake_strength * quality * (0.35 + decay * 0.65)
		_shake = Vector2(randf_range(-strength, strength), randf_range(-strength, strength))
	else:
		_shake = Vector2.ZERO
		_shake_strength = 5.0
	_flash = maxf(0.0, _flash - delta * 5.2)
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if engine == null or _blocked():
		return
	var phase := str(engine.state.get("phase", "ready"))
	if phase == "result":
		return
	if event is InputEventScreenTouch:
		if event.device == InputEvent.DEVICE_ID_EMULATION:
			return
		_last_touch_msec = Time.get_ticks_msec()
		accept_event()
		if event.pressed:
			if phase == "ready":
				_start_game()
			else:
				_pointer_down(event.index, event.position)
		else:
			_pointer_up(event.index, event.position)
	elif event is InputEventScreenDrag:
		_last_touch_msec = Time.get_ticks_msec()
		accept_event()
		if phase == "playing":
			_pointer_move(event.index, event.position)
	elif event is InputEventMouse:
		if event.device == InputEvent.DEVICE_ID_EMULATION or Time.get_ticks_msec() - _last_touch_msec < 200:
			return
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			accept_event()
			if event.pressed:
				if phase == "ready":
					_start_game()
				else:
					_pointer_down(0, event.position)
			else:
				_pointer_up(0, event.position)
		elif event is InputEventMouseMotion and _pointers.has(0):
			accept_event()
			if phase == "playing":
				_pointer_move(0, event.position)


func _start_game() -> void:
	if engine == null or str(engine.state.get("phase", "")) != "ready":
		return
	var result := engine.handle_input({"type":"start"})
	if not bool(result.get("ok", false)):
		return
	AudioFX.play("fruit_slice")
	FeedbackKit.haptic(6)
	action_committed.emit()
	queue_redraw()


func _pointer_down(index: int, position: Vector2) -> void:
	if _pointers.size() >= MAX_TRAILS and not _pointers.has(index):
		return
	_pointers[index] = {"last": position, "moved": false, "started": Time.get_ticks_msec()}
	_trails[index] = [{"position": position, "time": Time.get_ticks_msec()}]
	queue_redraw()


func _pointer_move(index: int, position: Vector2) -> void:
	if not _pointers.has(index):
		return
	var pointer: Dictionary = _pointers[index]
	var previous: Vector2 = pointer.last
	pointer.last = position
	pointer.moved = true
	_pointers[index] = pointer
	_add_trail(index, position)
	_slice(previous, position)
	queue_redraw()


func _pointer_up(index: int, position: Vector2) -> void:
	if not _pointers.has(index):
		return
	var pointer: Dictionary = _pointers[index]
	_pointers.erase(index)
	if engine != null and str(engine.state.get("phase", "")) == "playing":
		if bool(pointer.get("moved", false)):
			_add_trail(index, position)
			var previous: Vector2 = pointer.get("last", position)
			if previous.distance_squared_to(position) > 1.0:
				_slice(previous, position)
		else:
			_slice(position, position, true)
	queue_redraw()


func _slice(from: Vector2, to: Vector2, tap: bool = false) -> void:
	if engine == null or size.x <= 0.0 or size.y <= 0.0:
		return
	var result := engine.handle_input({
		"type": "slice",
		"tap": tap,
		"from": {"x": clampf(from.x / size.x, 0.0, 1.0), "y": clampf(from.y / size.y, 0.0, 1.0)},
		"to": {"x": clampf(to.x / size.x, 0.0, 1.0), "y": clampf(to.y / size.y, 0.0, 1.0)},
	})
	if not bool(result.get("ok", false)):
		return
	var changed := bool(result.get("changed", false))
	var events := engine.drain_events()
	if not events.is_empty():
		_apply_events(events)
	if changed and not events.is_empty():
		AudioFX.play("fruit_slice")
	if changed:
		action_committed.emit()
	if str(engine.state.get("phase", "")) == "result":
		_emit_finished()
	queue_redraw()


func _emit_finished() -> void:
	if _completion_sent or engine == null or str(engine.state.get("phase", "")) != "result":
		return
	_completion_sent = true
	game_finished.emit()


func _apply_events(events: Array) -> void:
	for event in events:
		if not event is Dictionary:
			continue
		match str(event.get("type", "")):
			"slice":
				_on_slice_event(event)
			"bomb":
				_on_bomb_event(event)
			"combo":
				_on_combo_event(event)
			"miss":
				_burst(float(event.get("x", 0.5)), float(event.get("y", 0.92)), Color("#d9c9ac"), 8, false)
				AudioFX.play("fruit_miss")
			"wave":
				_add_ring(0.5, 0.36, 0.04, 0.65, Color("#fff0a0"))
				_text_popup("第 %s 波" % int(event.get("wave", 2)), 0.5, 0.36, Color("#fff6bd"), 30)
				AudioFX.play("turn")


func _on_slice_event(event: Dictionary) -> void:
	var x := float(event.get("x", 0.5))
	var y := float(event.get("y", 0.5))
	var color := _safe_color(str(event.get("color", "#d9534f")))
	var flesh := _safe_color(str(event.get("flesh", "#ffe0b8")))
	var angle := float(event.get("rotation", 0.0))
	var slice_angle := float(event.get("sliceAngle", angle + PI * 0.5))
	var special := str(event.get("special", ""))
	var combo := int(event.get("combo", 1))
	_spawn_halves(
		x, y, color, flesh, str(event.get("shape", "apple")),
		slice_angle, special, float(event.get("radius", 0.055))
	)
	_burst(x, y, flesh, 24 if special != "bonus" else 42, true)
	_popup(int(event.get("points", 10)), x, y, Color("#fff8e8"))
	_flash = minf(0.20, 0.09 + float(combo) * 0.006)
	_flash_color = Color("#fff3cb") if special == "bonus" else color
	_flash_position = Vector2(x, y)
	_flash_radius = 0.11 if special == "bonus" else 0.09
	AudioFX.play("fruit_splat")
	FeedbackKit.haptic(5)
	if special == "bonus":
		_burst(x, y, Color("#f4cb58"), 34, true)
		_flash = 0.22
		_flash_color = Color("#f4cb58")
		_flash_radius = 0.15
		_add_ring(x, y, 0.06, 0.62, Color("#ffe48a"))
		AudioFX.play("fruit_bonus")
		FeedbackKit.haptic(10)
	if combo >= 3:
		_trigger_combo_focus(combo)


func _on_bomb_event(event: Dictionary) -> void:
	var x := float(event.get("x", 0.5))
	var y := float(event.get("y", 0.5))
	var quality := clampf(RuntimeQuality.effects_scale, 0.35, 1.0)
	_burst(x, y, Color("#665b52"), 34, false, 1.25)
	_burst(x, y, Color("#a08f80"), 18, false, 0.65)
	_burst(x, y, Color("#f4cb58"), 20, true)
	_add_ring(x, y, 0.06, 0.62, Color("#f2a24a"))
	_add_ring(x, y, 0.025, 0.42, Color("#ffe39a"))
	var applied_penalty := int(event.get("delta", -5))
	var penalty_text := ("-%s" % (-applied_penalty)) if applied_penalty < 0 else "躲开它"
	_text_popup(penalty_text, x, y, Color("#ffe1b0"), 28)
	_flash = 0.24 * quality
	_flash_color = Color("#f2a24a")
	_flash_position = Vector2(x, y)
	_flash_radius = 0.18
	_shake_time = 0.42
	_shake_strength = 7.5
	AudioFX.play("fruit_bomb")
	FeedbackKit.haptic(18)


func _on_combo_event(event: Dictionary) -> void:
	var combo := int(event.get("combo", 0))
	var x := float(event.get("x", 0.5))
	var y := float(event.get("y", 0.45))
	_add_ring(x, y, 0.035, 0.52, Color("#f4cb58"))
	_add_ring(x, y, 0.015, 0.44, Color("#fff0a8"))
	_text_popup("连击 x%s" % combo, x, y - 0.045, Color("#ffe98d"), 26)
	AudioFX.play("fruit_combo")
	FeedbackKit.haptic(8)


func _trigger_combo_focus(combo: int) -> void:
	_focus_time = 0.34
	_visual_scale = clampf(1.0 - minf(0.34, 0.16 + float(maxi(0, combo - 3)) * 0.015), 0.62, 1.0)
	_rings.append({
		"x":0.5, "y":0.48, "radius":0.10, "life":0.36, "age":0.0,
		"color":Color("#f4cb58"), "focus":true,
	})
	_trim_effects()


func _spawn_halves(
	x: float,
	y: float,
	color: Color,
	flesh: Color,
	shape: String,
	angle: float,
	special: String = "",
	radius: float = 0.055
) -> void:
	var scale_factor := clampf(RuntimeQuality.effects_scale, 0.35, 1.0)
	var normal := Vector2(cos(angle + PI * 0.5), sin(angle + PI * 0.5))
	for side in 2:
		var direction := 1.0 if side == 0 else -1.0
		var speed := randf_range(0.04, 0.11) * scale_factor
		_halves.append({
			"x": x, "y": y,
			"vx": normal.x * direction * speed,
			"vy": normal.y * direction * speed + randf_range(-0.08, -0.025),
			"angle": angle + randf_range(-0.12, 0.12),
			"spin": direction * randf_range(1.5, 3.2),
			"life": 0.88, "age": 0.0,
			"color": color, "flesh": flesh, "shape": shape, "side": side,
			"gold": special == "bonus", "radius": radius,
		})
	while _halves.size() > MAX_HALVES:
		_halves.pop_front()


func _burst(x: float, y: float, color: Color, count: int, stars: bool, speed_scale: float = 1.0) -> void:
	var limit := int(float(count) * clampf(RuntimeQuality.effects_scale, 0.35, 1.0))
	_ensure_particle_pool()
	for index in range(limit):
		var particle := _acquire_particle()
		if particle.is_empty():
			break
		var angle := randf_range(0.0, TAU)
		var speed := randf_range(0.04, 0.18) * speed_scale
		particle.x = x
		particle.y = y
		particle.vx = cos(angle) * speed
		particle.vy = sin(angle) * speed - 0.02
		particle.life = randf_range(0.32, 0.72)
		particle.age = 0.0
		particle.size = randf_range(3.0, 9.0) * (1.15 if speed_scale > 1.0 else 1.0)
		particle.angle = randf_range(0.0, TAU)
		particle.spin = randf_range(-7.0, 7.0)
		particle.color = color
		particle.star = stars and index % 3 == 0


func _popup(points: int, x: float, y: float, color: Color) -> void:
	_text_popup("+%s" % str(points), x, y, color, 26)


func _text_popup(text: String, x: float, y: float, color: Color, font_size: int = 24) -> void:
	_popups.append({
		"text":text, "x":x, "y":y, "life":0.72, "age":0.0,
		"color":color, "fontSize":font_size,
	})
	while _popups.size() > MAX_POPUPS:
		_popups.pop_front()


func _add_ring(x: float, y: float, radius: float, life: float, color: Color, focus: bool = false) -> void:
	_rings.append({
		"x":x, "y":y, "radius":radius, "life":life, "age":0.0,
		"color":color, "focus":focus,
	})
	while _rings.size() > MAX_RINGS:
		_rings.pop_front()


func _trim_effects() -> void:
	while _halves.size() > MAX_HALVES:
		_halves.pop_front()
	while _rings.size() > MAX_RINGS:
		_rings.pop_front()
	while _popups.size() > MAX_POPUPS:
		_popups.pop_front()


func _ensure_particle_pool() -> void:
	while _particles.size() < MAX_PARTICLES:
		_particles.append({
			"active":false, "x":0.0, "y":0.0, "vx":0.0, "vy":0.0,
			"life":1.0, "age":0.0, "size":6.0, "angle":0.0, "spin":0.0,
			"color":Color.WHITE, "star":false,
		})


func _acquire_particle() -> Dictionary:
	_ensure_particle_pool()
	var quality := clampf(RuntimeQuality.effects_scale, 0.35, 1.0)
	var active_cap := maxi(36, int(float(MAX_PARTICLES) * quality))
	if _active_particles >= active_cap:
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


func _update_effects(delta: float) -> void:
	for particle in _particles:
		if not bool(particle.get("active", false)):
			continue
		particle.age = float(particle.age) + delta
		if float(particle.age) >= float(particle.life):
			particle.active = false
			_active_particles = maxi(0, _active_particles - 1)
			continue
		particle.x = float(particle.x) + float(particle.vx) * delta
		particle.y = float(particle.y) + float(particle.vy) * delta
		particle.vy = float(particle.vy) + 0.26 * delta
		particle.angle = float(particle.angle) + float(particle.spin) * delta
	var kept_halves: Array = []
	for half in _halves:
		half.age = float(half.age) + delta
		if float(half.age) >= float(half.life):
			continue
		half.x = float(half.x) + float(half.vx) * delta
		half.y = float(half.y) + float(half.vy) * delta
		half.vy = float(half.vy) + 0.32 * delta
		half.angle = float(half.angle) + float(half.spin) * delta
		kept_halves.append(half)
	_halves = kept_halves
	var kept_rings: Array = []
	for ring in _rings:
		ring.age = float(ring.age) + delta
		if float(ring.age) < float(ring.life):
			kept_rings.append(ring)
	_rings = kept_rings
	var kept_popups: Array = []
	for popup in _popups:
		popup.age = float(popup.age) + delta
		if float(popup.age) < float(popup.life):
			kept_popups.append(popup)
	_popups = kept_popups


func _update_trails() -> void:
	var now := Time.get_ticks_msec()
	for index in _trails.keys():
		var points: Array = _trails[index]
		while not points.is_empty() and now - int(points[0].get("time", 0)) > 190:
			points.pop_front()
		if points.is_empty():
			_trails.erase(index)
		else:
			_trails[index] = points


func _add_trail(index: int, position: Vector2) -> void:
	if not _trails.has(index):
		_trails[index] = []
	var points: Array = _trails[index]
	points.append({"position": position, "time": Time.get_ticks_msec()})
	while points.size() > MAX_TRAIL_POINTS:
		points.pop_front()
	_trails[index] = points


func _draw() -> void:
	_draw_background()
	var shake := _shake
	if engine != null:
		var fruits: Variant = engine.state.get("fruits", [])
		var fruit_array: Array = fruits if fruits is Array else []
		for fruit in fruit_array:
			if not fruit is Dictionary:
				continue
			_draw_fruit(fruit, _to_pixels(float(fruit.x), float(fruit.y)) + shake)
	for half in _halves:
		_draw_half(half, shake)
	for particle in _particles:
		if bool(particle.get("active", false)):
			_draw_particle(particle, shake)
	_draw_local_flash()
	_draw_trails(shake)
	for ring in _rings:
		_draw_ring(ring)
	for popup in _popups:
		_draw_popup(popup)
	if _focus_time > 0.0:
		_draw_combo_focus()
	var phase := str(engine.state.get("phase", "")) if engine != null else ""
	if phase == "playing" or phase == "result":
		_draw_hud()
	if engine != null and str(engine.state.get("phase", "")) == "ready":
		_draw_ready()


func _draw_background() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("#f5ead5"), true)
	draw_rect(Rect2(0, size.y * 0.72, size.x, size.y * 0.28), Color("#dceac8"), true)
	for index in 7:
		var x := size.x * float(index) / 6.0
		var y := size.y * (0.16 + 0.06 * sin(float(index) * 1.7))
		draw_circle(Vector2(x, y), size.x * 0.12, Color(0.62, 0.78, 0.48, 0.16))
	draw_line(Vector2(0, size.y * 0.72), Vector2(size.x, size.y * 0.72), Color(0.32, 0.48, 0.24, 0.28), 3.0, true)
	for index in 9:
		var x := size.x * (0.06 + 0.11 * float(index))
		var y := size.y * (0.18 + 0.035 * float(index % 3))
		draw_circle(Vector2(x, y), 5.0, Color(0.36, 0.58, 0.30, 0.48))


func _to_pixels(x: float, y: float) -> Vector2:
	return Vector2(x * size.x, y * size.y)


func _draw_fruit(fruit: Dictionary, center: Vector2) -> void:
	var radius := minf(size.x, size.y) * float(fruit.get("radius", 0.055))
	var rotation := float(fruit.get("rotation", 0.0))
	var shape := str(fruit.get("shape", "apple"))
	var color := _safe_color(str(fruit.get("color", "#d9534f")))
	var flesh := _safe_color(str(fruit.get("flesh", "#ffe0b8")))
	var leaf := _safe_color(str(fruit.get("leaf", "#4f8248")))
	var special := str(fruit.get("special", ""))
	var quality := clampf(RuntimeQuality.effects_scale, 0.35, 1.0)
	var pulse := 0.5 + 0.5 * sin(_clock * 5.2 + rotation * 2.0)
	if special == "bonus":
		var velocity := Vector2(float(fruit.get("vx", 0.0)), float(fruit.get("vy", 0.0)))
		var trail_direction := -velocity.normalized() if velocity.length_squared() > 0.0001 else Vector2.DOWN
		for index in range(4):
			var trail_alpha := (0.18 - float(index) * 0.032) * quality
			draw_circle(
				center + trail_direction * radius * (0.65 + float(index) * 0.48),
				radius * (0.58 - float(index) * 0.08),
				Color(1.0, 0.79, 0.22, trail_alpha)
			)
		draw_circle(center, radius * (1.42 + pulse * 0.12), Color(1.0, 0.82, 0.24, 0.10 * quality))
		draw_arc(center, radius * (1.34 + pulse * 0.10), 0, TAU, 40, Color(1.0, 0.88, 0.38, 0.78), 3.5, true)
		for sparkle_index in range(4):
			var sparkle_angle := _clock * 1.8 + float(sparkle_index) * TAU * 0.25
			var sparkle_center := center + Vector2(cos(sparkle_angle), sin(sparkle_angle)) * radius * (1.48 + pulse * 0.12)
			_draw_star(sparkle_center, radius * 0.14, Color(1.0, 0.92, 0.54, 0.80 * quality), sparkle_angle)
	elif special == "bomb":
		draw_circle(center, radius * (1.28 + pulse * 0.08), Color(0.98, 0.44, 0.18, 0.08 * quality))
	draw_set_transform(center + Vector2(0, radius * 0.8), 0.0, Vector2(1.0, 0.28))
	draw_circle(Vector2.ZERO, radius * 0.9, Color(0.18, 0.14, 0.11, 0.14))
	var fruit_scale: Vector2 = (Vector2.ONE * (1.0 + pulse * 0.035)) if special == "bonus" else Vector2.ONE
	draw_set_transform(center, rotation, fruit_scale)
	if special == "bomb":
		_draw_bomb(radius)
	else:
		_draw_fruit_shape(shape, radius, color, flesh, leaf)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_fruit_shape(shape: String, radius: float, color: Color, flesh: Color, leaf: Color) -> void:
	match shape:
		"watermelon":
			draw_circle(Vector2.ZERO, radius, color)
			draw_circle(Vector2.ZERO, radius * 0.76, flesh)
			for seed_index in 6:
				var seed_angle := float(seed_index) * TAU / 6.0
				draw_circle(Vector2(cos(seed_angle), sin(seed_angle)) * radius * 0.45, radius * 0.06, Color(0.17, 0.20, 0.12))
			draw_line(Vector2(-radius * 0.6, -radius * 0.72), Vector2(radius * 0.58, -radius * 0.72), leaf, radius * 0.10, true)
		"orange":
			draw_circle(Vector2.ZERO, radius, color)
			for stripe in 5:
				var angle := float(stripe) * TAU / 5.0
				draw_line(Vector2.ZERO, Vector2(cos(angle), sin(angle)) * radius * 0.8, Color(0.28, 0.19, 0.08, 0.20), 2.0, true)
			_draw_leaf(radius, leaf)
		"strawberry":
			draw_colored_polygon(PackedVector2Array([
				Vector2(0, -radius * 0.82), Vector2(radius * 0.72, -radius * 0.42),
				Vector2(radius * 0.58, radius * 0.54), Vector2(0, radius * 0.84),
				Vector2(-radius * 0.58, radius * 0.54), Vector2(-radius * 0.72, -radius * 0.42),
			]), color)
			draw_colored_polygon(PackedVector2Array([
				Vector2(-radius * 0.55, -radius * 0.48), Vector2(radius * 0.55, -radius * 0.48),
				Vector2(radius * 0.35, -radius * 0.12), Vector2(-radius * 0.35, -radius * 0.12),
			]), leaf)
			for seed_index in 5:
				draw_circle(Vector2(-radius * 0.35 + seed_index * radius * 0.17, radius * 0.08 + (seed_index % 2) * radius * 0.18), radius * 0.045, Color(0.98, 0.89, 0.60))
		"banana":
			draw_colored_polygon(PackedVector2Array([
				Vector2(-radius * 0.8, radius * 0.25), Vector2(-radius * 0.55, -radius * 0.32),
				Vector2(radius * 0.48, -radius * 0.55), Vector2(radius * 0.86, -radius * 0.18),
				Vector2(radius * 0.52, radius * 0.02), Vector2(-radius * 0.32, radius * 0.18),
			]), color)
			draw_line(Vector2(-radius * 0.55, radius * 0.20), Vector2(radius * 0.55, -radius * 0.28), Color(0.48, 0.37, 0.11), 2.0, true)
		"grape":
			for row in 3:
				for column in (row + 2):
					var offset := Vector2((float(column) - float(row + 1) * 0.5) * radius * 0.34, -radius * 0.45 + row * radius * 0.34)
					draw_circle(offset, radius * 0.22, color)
			_draw_leaf(radius, leaf)
		"pear":
			draw_circle(Vector2(0, radius * 0.16), radius * 0.70, color)
			draw_circle(Vector2(0, -radius * 0.40), radius * 0.46, color)
			draw_circle(Vector2(-radius * 0.18, -radius * 0.02), radius * 0.18, Color(1, 1, 1, 0.16))
			_draw_leaf(radius, leaf)
		"peach":
			draw_circle(Vector2(0, radius * 0.02), radius * 0.76, color)
			draw_line(Vector2(0, -radius * 0.55), Vector2(0, radius * 0.64), Color(0.76, 0.36, 0.28, 0.36), 2.0, true)
			_draw_leaf(radius, leaf)
		"pineapple":
			draw_circle(Vector2(0, radius * 0.08), radius * 0.66, color)
			for row in 4:
				for column in 4:
					var point := Vector2((float(column) - 1.5) * radius * 0.26, (float(row) - 1.5) * radius * 0.25)
					draw_line(point + Vector2(-6, -7), point + Vector2(6, 7), Color(0.58, 0.37, 0.09, 0.44), 2.0)
			for leaf_index in 4:
				draw_colored_polygon(PackedVector2Array([
					Vector2(0, -radius * 0.40), Vector2((float(leaf_index) - 1.5) * radius * 0.28, -radius * 0.94),
					Vector2((float(leaf_index) - 1.1) * radius * 0.20, -radius * 0.40),
				]), leaf)
		"mango":
			draw_circle(Vector2(0, 0), radius * 0.76, color)
			draw_circle(Vector2(radius * 0.18, -radius * 0.12), radius * 0.35, Color(0.92, 0.43, 0.20, 0.34))
			draw_circle(Vector2(-radius * 0.22, -radius * 0.16), radius * 0.14, Color(1, 1, 1, 0.16))
			_draw_leaf(radius, leaf)
		"kiwi":
			draw_circle(Vector2.ZERO, radius * 0.78, color)
			draw_circle(Vector2.ZERO, radius * 0.64, flesh)
			for seed_index in 8:
				var angle := float(seed_index) * TAU / 8.0
				draw_circle(Vector2(cos(angle), sin(angle)) * radius * 0.36, radius * 0.045, Color(0.25, 0.22, 0.12))
		"lemon":
			draw_circle(Vector2.ZERO, radius * 0.72, color)
			draw_colored_polygon(PackedVector2Array([Vector2(-radius * 0.82, 0), Vector2(-radius * 0.58, -radius * 0.23), Vector2(-radius * 0.58, radius * 0.23)]), color)
			draw_colored_polygon(PackedVector2Array([Vector2(radius * 0.82, 0), Vector2(radius * 0.58, -radius * 0.23), Vector2(radius * 0.58, radius * 0.23)]), color)
			_draw_leaf(radius, leaf)
		_:
			draw_circle(Vector2.ZERO, radius * 0.78, color)
			draw_circle(Vector2(-radius * 0.20, -radius * 0.24), radius * 0.16, Color(1, 1, 1, 0.18))
			_draw_leaf(radius, leaf)


func _draw_leaf(radius: float, leaf: Color) -> void:
	draw_colored_polygon(PackedVector2Array([
		Vector2(radius * 0.10, -radius * 0.70),
		Vector2(radius * 0.48, -radius * 0.98),
		Vector2(radius * 0.28, -radius * 0.55),
	]), leaf)
	draw_line(Vector2(0, -radius * 0.60), Vector2(radius * 0.14, -radius * 0.92), Color(0.38, 0.27, 0.13), 2.0, true)


func _draw_bomb(radius: float) -> void:
	draw_circle(Vector2.ZERO, radius, Color("#32343c"))
	draw_circle(Vector2(-radius * 0.22, -radius * 0.24), radius * 0.26, Color(0.92, 0.90, 0.80, 0.16))
	draw_arc(Vector2.ZERO, radius * 0.72, 0, TAU, 30, Color("#f2a24a"), 3.0, true)
	draw_line(Vector2(radius * 0.34, -radius * 0.64), Vector2(radius * 0.62, -radius * 1.08), Color("#e1b45a"), 3.0, true)
	draw_circle(Vector2(radius * 0.64, -radius * 1.10), radius * 0.10, Color("#f4cb58"))
	_draw_star(Vector2.ZERO, radius * 0.36, Color("#f2a24a"), 0.0)


func _draw_half(half: Dictionary, shake: Vector2) -> void:
	var center := _to_pixels(float(half.x), float(half.y)) + shake
	var radius := minf(size.x, size.y) * float(half.get("radius", 0.055))
	var alpha := clampf(1.0 - float(half.age) / float(half.life), 0.0, 1.0)
	var color := _safe_color(str(half.color))
	var flesh := _safe_color(str(half.flesh))
	draw_set_transform(center, float(half.angle), Vector2.ONE)
	var start_angle := 0.0 if int(half.get("side", 0)) == 0 else PI
	var outer := PackedVector2Array()
	for index in range(18):
		var angle := start_angle + float(index) * PI / 17.0
		outer.append(Vector2(cos(angle), sin(angle)) * radius)
	outer.append(Vector2.ZERO)
	draw_colored_polygon(outer, Color(color, alpha))
	var inner := PackedVector2Array()
	for index in range(18):
		var angle := start_angle + float(index) * PI / 17.0
		inner.append(Vector2(cos(angle), sin(angle)) * radius * 0.82)
	inner.append(Vector2.ZERO)
	draw_colored_polygon(inner, Color(flesh, alpha * 0.94))
	draw_arc(Vector2.ZERO, radius, start_angle, start_angle + PI, 24, Color(color.darkened(0.16), alpha), 2.2, true)
	var cut := Vector2(cos(start_angle), sin(start_angle)) * radius
	draw_line(-cut, cut, Color(1.0, 0.97, 0.86, alpha * 0.92), 2.8, true)
	if bool(half.get("gold", false)):
		draw_arc(Vector2.ZERO, radius * 1.18, start_angle, start_angle + PI, 24, Color(1.0, 0.82, 0.26, alpha * 0.90), 3.0, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_particle(particle: Dictionary, shake: Vector2) -> void:
	var life := maxf(0.01, float(particle.life))
	var alpha := clampf(1.0 - float(particle.age) / life, 0.0, 1.0)
	var color := _safe_color(str(particle.color))
	color.a *= alpha
	var center := _to_pixels(float(particle.x), float(particle.y)) + shake
	if bool(particle.get("star", false)):
		draw_set_transform(center, float(particle.angle), Vector2.ONE)
		draw_colored_polygon(_star_points(float(particle.size)), color)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		draw_circle(center, float(particle.size) * (0.5 + alpha * 0.5), color)


func _draw_trails(shake: Vector2) -> void:
	var now := Time.get_ticks_msec()
	var quality := clampf(RuntimeQuality.effects_scale, 0.35, 1.0)
	for index in _trails.keys():
		var entries: Array = _trails[index]
		if entries.size() < 2:
			continue
		var points := PackedVector2Array()
		for entry in entries:
			var point: Vector2 = entry.position
			points.append(point + shake)
		draw_polyline(points, Color(accent, 0.20 * quality), 17.0, true)
		draw_polyline(points, Color(1.0, 0.97, 0.78, 0.28 * quality), 9.0, true)
		draw_polyline(points, Color(1.0, 0.99, 0.91, 0.94), 3.8, true)
		if _focus_time > 0.0:
			draw_polyline(points, Color(1.0, 0.80, 0.28, 0.34), 6.0, true)
		for point_index in range(0, entries.size(), 5):
			var entry: Dictionary = entries[point_index]
			var age := clampf(float(now - int(entry.get("time", 0))) / 190.0, 0.0, 1.0)
			draw_circle(entry.position + shake, 2.3 * (1.0 - age * 0.55), Color(1.0, 0.93, 0.64, (1.0 - age) * 0.82))


func _draw_ring(ring: Dictionary) -> void:
	var progress := clampf(float(ring.age) / float(ring.life), 0.0, 1.0)
	var center := _to_pixels(float(ring.x), float(ring.y))
	var radius := minf(size.x, size.y) * (float(ring.radius) + progress * 0.18)
	var color := _safe_color(str(ring.color))
	color.a = 1.0 - progress
	var quality := clampf(RuntimeQuality.effects_scale, 0.35, 1.0)
	color.a *= quality
	draw_arc(center, radius, 0, TAU, 48, color, 4.0 * (1.0 - progress * 0.5), true)
	color.a *= 0.48
	draw_arc(center, radius * 0.82, 0, TAU, 42, color, 2.0, true)


func _draw_popup(popup: Dictionary) -> void:
	var progress := clampf(float(popup.age) / float(popup.life), 0.0, 1.0)
	var center := _to_pixels(float(popup.x), float(popup.y)) + Vector2(0, -progress * 48.0)
	var color := _safe_color(str(popup.color))
	color.a = 1.0 - progress
	var font_size := int(popup.get("fontSize", 26))
	var text := str(popup.text)
	var font := PlaygroundUI.font()
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	draw_string(font, center - Vector2(text_size.x * 0.5, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


func _draw_hud() -> void:
	if engine == null:
		return
	var score := int(engine.state.get("score", 0))
	var mode := str(engine.state.get("modeId", "practice"))
	var left_text := "得分 %s" % score
	var right_text := ""
	if mode == "challenge":
		right_text = "%02d 秒" % ceili(float(engine.state.get("remaining", 0.0)))
	else:
		right_text = "第 %s / %s 波" % [int(engine.state.get("wave", 1)), int(engine.state.config.get("practiceWaves", 3))]
	_draw_hud_pill(Rect2(24, 22, 190, 52), left_text, Color("#fff9ec"))
	_draw_hud_pill(Rect2(size.x - 214, 22, 190, 52), right_text, Color("#fff9ec"))
	if int(engine.state.get("combo", 0)) >= 2:
		var combo := int(engine.state.combo)
		var combo_text := "连击 x%s" % combo
		var font := PlaygroundUI.font()
		var text_size := font.get_string_size(combo_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 28)
		draw_string(font, Vector2((size.x - text_size.x) * 0.5, 88), combo_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color("#fff4b5"))


func _draw_hud_pill(rect: Rect2, text: String, paper: Color) -> void:
	draw_style_box(PlaygroundUI.style(Color(0.12, 0.14, 0.12, 0.72), 18, Color(1, 1, 1, 0.18), 1), rect)
	draw_string(PlaygroundUI.font(), rect.position + Vector2(18, rect.size.y * 0.66), text, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 34, 23, paper)


func _draw_ready() -> void:
	var panel_size := Vector2(clampf(size.x * 0.48, 320.0, 520.0), clampf(size.y * 0.34, 226.0, 292.0))
	var panel := Rect2((size - panel_size) * 0.5, panel_size)
	draw_style_box(PlaygroundUI.style(Color(1, 1, 1, 0.91), 30, Color(accent, 0.65), 3, 10, Color(0, 0, 0, 0.16)), panel)
	var title := "水果切切乐"
	var challenge := str(engine.state.get("modeId", "practice")) == "challenge"
	var subtitle := "60 秒挑战" if challenge else "果园练习 · 三波慢速水果"
	_draw_centered_text(title, panel.position.y + 66, panel.size.x, accent, 34)
	_draw_centered_text(subtitle, panel.position.y + 108, panel.size.x, PlaygroundUI.INK_SOFT, 20)
	if challenge:
		var record_text := ("最高纪录 %s 分" % high_score) if high_score > 0 else "第一次挑战，先试试连击吧"
		_draw_centered_text(record_text, panel.position.y + 146, panel.size.x, PlaygroundUI.INK_SOFT, 17)
	else:
		_draw_centered_text("没有炸弹，慢慢熟悉刀光", panel.position.y + 146, panel.size.x, PlaygroundUI.INK_SOFT, 17)
	var prompt := "轻点开始 · 用手指划过水果"
	var prompt_y := panel.position.y + panel.size.y - 42
	_draw_centered_text(prompt, prompt_y, panel.size.x, accent, 18)
	var prompt_width := PlaygroundUI.font().get_string_size(prompt, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
	var badge_center := Vector2(size.x * 0.5 - prompt_width * 0.5 - 20.0, prompt_y - 8.0)
	draw_circle(badge_center, 11.0, accent)
	draw_colored_polygon(PackedVector2Array([
		badge_center + Vector2(-3.5, -6.0),
		badge_center + Vector2(7.0, 0.0),
		badge_center + Vector2(-3.5, 6.0),
	]), Color("#fff8e9"))


func _draw_centered_text(text: String, baseline_y: float, width: float, color: Color, font_size: int) -> void:
	var font := PlaygroundUI.font()
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var panel_left := (size.x - width) * 0.5
	var x := panel_left + maxf(14.0, (width - text_size.x) * 0.5)
	draw_string(font, Vector2(x, baseline_y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


func _draw_local_flash() -> void:
	if _flash <= 0.0:
		return
	var quality := clampf(RuntimeQuality.effects_scale, 0.35, 1.0)
	var center := _to_pixels(_flash_position.x, _flash_position.y) + _shake
	var radius := minf(size.x, size.y) * _flash_radius
	var strength := _flash * quality
	for index in range(3):
		var alpha := strength * (0.075 / float(index + 1))
		draw_circle(center, radius * (1.0 + float(index) * 0.34), Color(_flash_color, alpha))
	var ring_color := Color(_flash_color, strength * 0.70)
	draw_arc(center, radius * 0.88, 0, TAU, 36, ring_color, 3.0, true)


func _draw_combo_focus() -> void:
	var quality := clampf(RuntimeQuality.effects_scale, 0.35, 1.0)
	var strength := clampf(_focus_time / 0.34, 0.0, 1.0) * quality
	var center := size * 0.5
	var radius := minf(size.x, size.y)
	for index in range(12):
		var angle := float(index) * TAU / 12.0
		var direction := Vector2(cos(angle), sin(angle))
		var start := center + direction * radius * 0.27
		var finish := center + direction * radius * (0.40 + 0.04 * sin(_clock * 9.0 + float(index)))
		draw_line(start, finish, Color(1.0, 0.82, 0.30, 0.20 * strength), 2.4, true)


func _star_points(radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for index in 10:
		var r := radius if index % 2 == 0 else radius * 0.44
		var angle := -PI * 0.5 + float(index) * PI / 5.0
		points.append(Vector2(cos(angle), sin(angle)) * r)
	return points


func _draw_star(center: Vector2, radius: float, color: Color, angle: float) -> void:
	var points := PackedVector2Array()
	for index in 10:
		var r := radius if index % 2 == 0 else radius * 0.44
		var theta := angle - PI * 0.5 + float(index) * PI / 5.0
		points.append(center + Vector2(cos(theta), sin(theta)) * r)
	draw_colored_polygon(points, color)


func _safe_color(value: String) -> Color:
	return Color(value) if Color.html_is_valid(value) else accent


func _blocked() -> bool:
	if game_screen == null or not is_instance_valid(game_screen):
		return false
	return game_screen.paused or not game_screen._modal_stack.is_empty()
