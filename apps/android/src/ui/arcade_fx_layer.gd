class_name ArcadeFxLayer
extends Control

const MAX_PARTICLES := 160
const MAX_POPUPS := 18
const MAX_RINGS := 14
const MAX_TRAILS := 6
const MAX_TRAIL_POINTS := 56

var accent := Color("#2f7e91")
var soft := Color("#e2f0f2")
var intensity := 1.0
var gravity := 38.0

var _clock := 0.0
var _particles: Array = []
var _particle_cursor := 0
var _active_particles := 0
var _popups: Array = []
var _popup_cursor := 0
var _rings: Array = []
var _ring_cursor := 0
var _trails: Dictionary = {}
var _trail_order: Array[String] = []
var _shake_time := 0.0
var _shake_duration := 0.0
var _shake_strength := 0.0
var _shake_offset := Vector2.ZERO
var _needs_redraw := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ensure_particle_pool()
	_ensure_popup_pool()
	_ensure_ring_pool()


func set_palette(main: Color, secondary: Color) -> void:
	accent = main
	soft = secondary
	queue_redraw()


func emit_burst(position: Vector2, color: Color, count: int = 12, options: Dictionary = {}) -> void:
	var scale := effects_scale()
	var requested := mini(maxi(0, count), maxi(0, int(round(float(count) * scale))))
	var speed := float(options.get("speed", 78.0)) * intensity
	var spread := float(options.get("spread", TAU))
	var direction: Vector2 = options.get("direction", Vector2.ZERO)
	var kind := str(options.get("kind", "spark"))
	var life := float(options.get("life", 0.48))
	var size := float(options.get("size", 4.2))
	var base_angle := direction.angle() if direction.length_squared() > 0.000001 else 0.0
	for index in requested:
		var particle := _acquire_particle()
		if particle.is_empty():
			break
		var angle := base_angle + (float(index) / maxf(1.0, float(requested)) - 0.5) * spread
		angle += randf_range(-0.08, 0.08)
		var velocity := Vector2(cos(angle), sin(angle)) * randf_range(speed * 0.42, speed)
		particle.active = true
		particle.position = position
		particle.velocity = velocity
		particle.life = maxf(0.08, life * randf_range(0.72, 1.18))
		particle.age = 0.0
		particle.size = maxf(1.0, size * randf_range(0.72, 1.35))
		particle.color = color
		particle.kind = kind
		particle.rotation = randf_range(0.0, TAU)
		particle.spin = randf_range(-7.0, 7.0)
	_needs_redraw = true


func emit_star_trail(position: Vector2, color: Color, count: int = 5) -> void:
	emit_burst(position, color, count, {
		"speed": 28.0,
		"spread": TAU,
		"life": 0.7,
		"size": 3.0,
		"kind": "star",
	})


func begin_trail(trail_id: String, position: Vector2, color: Color, width: float = 10.0) -> void:
	if trail_id.is_empty():
		return
	_trails[trail_id] = {
		"color": color,
		"width": maxf(1.0, width),
		"points": [{"position": position, "age": 0.0}],
	}
	if not trail_id in _trail_order:
		_trail_order.append(trail_id)
	while _trail_order.size() > _trail_capacity():
		var oldest: String = _trail_order.pop_front()
		if oldest != trail_id:
			_trails.erase(oldest)
	_needs_redraw = true


func add_trail_point(trail_id: String, position: Vector2, spacing: float = 4.0) -> void:
	if not _trails.has(trail_id):
		return
	var trail: Dictionary = _trails[trail_id]
	var points: Array = trail.get("points", [])
	if not points.is_empty():
		var last: Dictionary = points.back()
		if Vector2(last.get("position", Vector2.ZERO)).distance_to(position) < spacing:
			return
	points.append({"position": position, "age": 0.0})
	while points.size() > MAX_TRAIL_POINTS:
		points.pop_front()
	trail.points = points
	_trails[trail_id] = trail
	_needs_redraw = true


func end_trail(trail_id: String) -> void:
	if _trails.has(trail_id):
		var trail: Dictionary = _trails[trail_id]
		trail.ending = true
		_trails[trail_id] = trail


func popup(text: String, position: Vector2, color: Color, font_size: int = 22, life: float = 0.72) -> void:
	if text.strip_edges().is_empty():
		return
	var entry := _acquire_popup()
	entry.active = true
	entry.text = text
	entry.position = position
	entry.color = color
	entry.font_size = maxi(11, font_size)
	entry.life = maxf(0.12, life)
	entry.age = 0.0
	entry.drift = Vector2(randf_range(-5.0, 5.0), -24.0)
	_needs_redraw = true


func ring(position: Vector2, color: Color, radius: float = 20.0, life: float = 0.42, width: float = 2.4) -> void:
	var entry := _acquire_ring()
	entry.active = true
	entry.position = position
	entry.color = color
	entry.radius = maxf(1.0, radius)
	entry.life = maxf(0.1, life)
	entry.age = 0.0
	entry.width = maxf(1.0, width)
	_needs_redraw = true


func shake(amount: float = 5.0, duration: float = 0.24) -> void:
	var scaled := amount * intensity * effects_scale()
	if scaled <= 0.0:
		return
	_shake_strength = maxf(_shake_strength, scaled)
	_shake_duration = maxf(_shake_duration, duration)
	_shake_time = maxf(_shake_time, duration)
	_needs_redraw = true


func get_shake_offset() -> Vector2:
	return _shake_offset


func clear_effects() -> void:
	for particle in _particles:
		particle.active = false
	for popup_entry in _popups:
		popup_entry.active = false
	for ring_entry in _rings:
		ring_entry.active = false
	_trails.clear()
	_trail_order.clear()
	_active_particles = 0
	_particle_cursor = 0
	_shake_time = 0.0
	_shake_strength = 0.0
	_shake_offset = Vector2.ZERO
	queue_redraw()


func suspend_effects() -> void:
	clear_effects()


func tick(delta: float) -> void:
	var frame := clampf(delta, 0.0, 0.1)
	if frame <= 0.0 and not _needs_redraw:
		return
	_clock += frame
	var active := false
	for particle in _particles:
		if not bool(particle.get("active", false)):
			continue
		particle.age = float(particle.age) + frame
		if float(particle.age) >= float(particle.life):
			particle.active = false
			_active_particles = maxi(0, _active_particles - 1)
			continue
		active = true
		particle.position = Vector2(particle.position) + Vector2(particle.velocity) * frame
		particle.velocity = Vector2(particle.velocity) * (1.0 - minf(0.95, frame * 2.2)) + Vector2(0.0, gravity) * frame
		particle.rotation = float(particle.rotation) + float(particle.spin) * frame
	for popup_entry in _popups:
		if not bool(popup_entry.get("active", false)):
			continue
		popup_entry.age = float(popup_entry.age) + frame
		if float(popup_entry.age) >= float(popup_entry.life):
			popup_entry.active = false
			continue
		active = true
		popup_entry.position = Vector2(popup_entry.position) + Vector2(popup_entry.drift) * frame
	for ring_entry in _rings:
		if not bool(ring_entry.get("active", false)):
			continue
		ring_entry.age = float(ring_entry.age) + frame
		if float(ring_entry.age) >= float(ring_entry.life):
			ring_entry.active = false
			continue
		active = true
	var expired_trails: Array[String] = []
	for trail_id in _trails.keys():
		var trail: Dictionary = _trails[trail_id]
		var points: Array = trail.get("points", [])
		for point in points:
			point.age = float(point.get("age", 0.0)) + frame
		while not points.is_empty() and (float(points[0].get("age", 0.0)) > 0.52 or points.size() > MAX_TRAIL_POINTS):
			points.pop_front()
		if points.is_empty() and bool(trail.get("ending", false)):
			expired_trails.append(str(trail_id))
			continue
		if not points.is_empty():
			active = true
		trail.points = points
		_trails[trail_id] = trail
	for trail_id in expired_trails:
		_trails.erase(trail_id)
		_trail_order.erase(trail_id)
	if _shake_time > 0.0:
		_shake_time = maxf(0.0, _shake_time - frame)
		var ratio := clampf(_shake_time / maxf(0.001, _shake_duration), 0.0, 1.0)
		var magnitude := _shake_strength * ratio
		_shake_offset = Vector2(randf_range(-magnitude, magnitude), randf_range(-magnitude, magnitude))
		active = true
	else:
		_shake_offset = Vector2.ZERO
		_shake_strength = 0.0
	if active or _needs_redraw:
		queue_redraw()
	_needs_redraw = false


func consume_events(events: Array, origin_for: Callable = Callable()) -> void:
	for raw in events:
		if not raw is Dictionary:
			continue
		var event: Dictionary = raw
		var point: Vector2 = origin_for.call(event) if origin_for.is_valid() else Vector2(event.get("x", 0.0), event.get("y", 0.0))
		var color := _event_color(event)
		var kind := str(event.get("type", ""))
		if kind in ["pop", "match", "burst", "star", "collect", "goal"]:
			emit_burst(point, color, 18 if kind == "goal" else 10, {"speed": 72.0, "life": 0.52, "kind": "star" if kind in ["star", "goal"] else "spark"})
			ring(point, Color(color, 0.72), 22.0, 0.36)
		elif kind in ["bounce", "hit"]:
			emit_burst(point, color, 7, {"speed": 58.0, "life": 0.28})
		elif kind in ["drop", "fall"]:
			emit_star_trail(point, color, 4)
		elif kind == "fire":
			emit_burst(point, color, 8, {"speed": 54.0, "spread": 1.1, "direction": Vector2.UP, "life": 0.34})
		if event.has("text"):
			popup(str(event.text), point, color, int(event.get("fontSize", 22)))


func _draw() -> void:
	for trail_id in _trail_order:
		if not _trails.has(trail_id):
			continue
		var trail: Dictionary = _trails[trail_id]
		var points: Array = trail.get("points", [])
		if points.size() < 2:
			continue
		var trail_color: Color = trail.get("color", accent)
		var width := float(trail.get("width", 8.0))
		for index in range(1, points.size()):
			var previous: Dictionary = points[index - 1]
			var current: Dictionary = points[index]
			var fade := 1.0 - clampf(float(current.get("age", 0.0)) / 0.52, 0.0, 1.0)
			var segment_width := width * (0.35 + fade * 0.65)
			draw_line(
				Vector2(previous.position),
				Vector2(current.position),
				Color(trail_color, fade * 0.58),
				segment_width,
				true
			)
	for particle in _particles:
		if bool(particle.get("active", false)):
			_draw_particle(particle)
	for ring_entry in _rings:
		if bool(ring_entry.get("active", false)):
			_draw_ring(ring_entry)
	for popup_entry in _popups:
		if bool(popup_entry.get("active", false)):
			_draw_popup(popup_entry)


func _draw_particle(particle: Dictionary) -> void:
	var life_ratio := 1.0 - clampf(float(particle.age) / maxf(0.001, float(particle.life)), 0.0, 1.0)
	var color: Color = particle.color
	color.a *= life_ratio
	var size := float(particle.size) * (0.45 + life_ratio * 0.55)
	var position := Vector2(particle.position)
	match str(particle.get("kind", "spark")):
		"star":
			_draw_star(position, size * 1.6, color, float(particle.rotation))
		"bubble":
			draw_circle(position, size, Color(color, color.a * 0.28))
			draw_arc(position, size, 0.0, TAU, 18, Color(1, 1, 1, color.a * 0.72), maxf(1.0, size * 0.22), true)
		_:
			draw_circle(position, size, color)
			draw_circle(position + Vector2(-size * 0.26, -size * 0.3), size * 0.3, Color(1, 1, 1, color.a * 0.6))


func _draw_ring(ring_entry: Dictionary) -> void:
	var ratio := clampf(float(ring_entry.age) / maxf(0.001, float(ring_entry.life)), 0.0, 1.0)
	var color: Color = ring_entry.color
	color.a *= 1.0 - ratio
	draw_arc(Vector2(ring_entry.position), float(ring_entry.radius) * (0.35 + ratio * 0.9), 0.0, TAU, 32, color, float(ring_entry.get("width", 2.0)), true)


func _draw_popup(entry: Dictionary) -> void:
	var ratio := clampf(float(entry.age) / maxf(0.001, float(entry.life)), 0.0, 1.0)
	var color: Color = entry.color
	color.a *= 1.0 - pow(ratio, 2.0)
	var font := PlaygroundUI.font()
	var font_size := int(entry.font_size)
	var text := str(entry.text)
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var position := Vector2(entry.position) - Vector2(text_size.x * 0.5, 0.0)
	draw_string(font, position, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


func _draw_star(center: Vector2, radius: float, color: Color, rotation: float) -> void:
	var points := PackedVector2Array()
	for index in 10:
		var angle := rotation - PI * 0.5 + float(index) * PI / 5.0
		var length := radius if index % 2 == 0 else radius * 0.45
		points.append(center + Vector2(cos(angle), sin(angle)) * length)
	draw_colored_polygon(points, color)


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
			"kind": "spark",
			"rotation": 0.0,
			"spin": 0.0,
		})


func _ensure_popup_pool() -> void:
	while _popups.size() < MAX_POPUPS:
		_popups.append({
			"active": false,
			"text": "",
			"position": Vector2.ZERO,
			"drift": Vector2.ZERO,
			"color": Color.WHITE,
			"font_size": 22,
			"life": 0.7,
			"age": 0.0,
		})


func _ensure_ring_pool() -> void:
	while _rings.size() < MAX_RINGS:
		_rings.append({
			"active": false,
			"position": Vector2.ZERO,
			"color": Color.WHITE,
			"radius": 20.0,
			"width": 2.0,
			"life": 0.4,
			"age": 0.0,
		})


func _acquire_particle() -> Dictionary:
	_ensure_particle_pool()
	var capacity := maxi(24, int(round(float(MAX_PARTICLES) * effects_scale())))
	if _active_particles >= capacity:
		var recycled: Dictionary = _particles[_particle_cursor]
		_particle_cursor = (_particle_cursor + 1) % MAX_PARTICLES
		return recycled
	for offset in MAX_PARTICLES:
		var index := (_particle_cursor + offset) % MAX_PARTICLES
		var particle: Dictionary = _particles[index]
		if bool(particle.get("active", false)):
			continue
		_active_particles = mini(MAX_PARTICLES, _active_particles + 1)
		_particle_cursor = (index + 1) % MAX_PARTICLES
		return particle
	return {}


func _acquire_popup() -> Dictionary:
	_ensure_popup_pool()
	var capacity := maxi(5, int(round(float(MAX_POPUPS) * effects_scale())))
	var active := _popups.filter(func(entry): return bool(entry.get("active", false))).size()
	if active >= capacity:
		var recycled: Dictionary = _popups[_popup_cursor]
		_popup_cursor = (_popup_cursor + 1) % MAX_POPUPS
		return recycled
	for offset in MAX_POPUPS:
		var index := (_popup_cursor + offset) % MAX_POPUPS
		var entry: Dictionary = _popups[index]
		if not bool(entry.get("active", false)):
			_popup_cursor = (index + 1) % MAX_POPUPS
			return entry
	return _popups[0]


func _acquire_ring() -> Dictionary:
	_ensure_ring_pool()
	var capacity := maxi(4, int(round(float(MAX_RINGS) * effects_scale())))
	var active := _rings.filter(func(entry): return bool(entry.get("active", false))).size()
	if active >= capacity:
		var recycled: Dictionary = _rings[_ring_cursor]
		_ring_cursor = (_ring_cursor + 1) % MAX_RINGS
		return recycled
	for offset in MAX_RINGS:
		var index := (_ring_cursor + offset) % MAX_RINGS
		var entry: Dictionary = _rings[index]
		if not bool(entry.get("active", false)):
			_ring_cursor = (index + 1) % MAX_RINGS
			return entry
	return _rings[0]


func _trail_capacity() -> int:
	return maxi(1, int(round(float(MAX_TRAILS) * effects_scale())))


func effects_scale() -> float:
	var tree := get_tree()
	if tree == null:
		return 1.0
	var quality := tree.root.get_node_or_null("RuntimeQuality")
	if quality == null:
		return 1.0
	return clampf(float(quality.get("effects_scale")), 0.35, 1.0)


func _event_color(event: Dictionary) -> Color:
	var value := str(event.get("color", ""))
	if value.is_valid_html_color():
		return Color(value)
	if str(event.get("type", "")) in ["goal", "star"]:
		return Color("#efc755")
	return accent
