class_name SpotBoard
extends Control

signal point_tapped(position: Vector2, touch_radius: float)

var scene: Dictionary = {}
var found_ids: Array = []
var hint_id := ""
var accent := Color("#526f88")
var interactive := true
var _clock := 0.0
var _wrong_at := Vector2(-1, -1)
var _wrong_remaining := 0.0
var _last_touch_msec := -1000
const MIN_TOUCH_DIAMETER := 44.0


func _ready() -> void:
	custom_minimum_size = Vector2(720, 480)
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	resized.connect(queue_redraw)


func configure(value: Dictionary, tint: Color = Color("#526f88")) -> void:
	scene = value.duplicate(true)
	accent = tint
	found_ids.clear()
	hint_id = ""
	interactive = true
	_wrong_at = Vector2(-1, -1)
	_wrong_remaining = 0.0
	set_process(false)
	queue_redraw()


func update_progress(found: Array, hint: String, wrong_at: Vector2 = Vector2(-1, -1)) -> void:
	found_ids = found.duplicate()
	hint_id = hint
	if wrong_at.x >= 0.0 and wrong_at.y >= 0.0:
		_wrong_at = wrong_at
		_wrong_remaining = 0.65
	else:
		_wrong_at = Vector2(-1, -1)
		_wrong_remaining = 0.0
	set_process(not hint_id.is_empty() or _wrong_remaining > 0.0)
	queue_redraw()


func stop_interaction() -> void:
	interactive = false
	set_process(false)
	queue_redraw()


func _process(delta: float) -> void:
	_clock += delta
	_wrong_remaining = maxf(0.0, _wrong_remaining - delta)
	queue_redraw()
	if hint_id.is_empty() and _wrong_remaining <= 0.0:
		set_process(false)


func panel_rects() -> Array:
	var margin := clampf(size.x * 0.014, 10.0, 20.0)
	var label_height := 34.0
	var gap := 16.0
	var panel_width := (size.x - margin * 2.0 - gap) * 0.5
	var panel_height := size.y - margin * 2.0 - label_height
	return [
		Rect2(Vector2(margin, margin + label_height), Vector2(panel_width, panel_height)),
		Rect2(Vector2(margin + panel_width + gap, margin + label_height), Vector2(panel_width, panel_height)),
	]


func normalized_at(point: Vector2) -> Dictionary:
	var rects := panel_rects()
	for side in rects.size():
		var rect := content_rect(rects[side])
		if rect.has_point(point):
			return {
				"side": side,
				"x": clampf((point.x - rect.position.x) / rect.size.x, 0.0, 1.0),
				"y": clampf((point.y - rect.position.y) / rect.size.y, 0.0, 1.0),
			}
	return {}


func touch_radius_normalized() -> float:
	var rects := panel_rects()
	if rects.is_empty():
		return 0.06
	var rect := content_rect(rects[0])
	var shortest := maxf(1.0, minf(rect.size.x, rect.size.y))
	return clampf((MIN_TOUCH_DIAMETER * 0.5) / shortest, 0.025, 0.2)


func content_rect(panel: Rect2) -> Rect2:
	var inset := clampf(minf(panel.size.x, panel.size.y) * 0.016, 6.0, 12.0)
	return panel.grow(-inset)


func _gui_input(event: InputEvent) -> void:
	if not interactive:
		return
	if event is InputEventScreenTouch:
		if event.device == InputEvent.DEVICE_ID_EMULATION:
			return
		_last_touch_msec = Time.get_ticks_msec()
		if event.pressed:
			_emit_tap(event.position)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if Time.get_ticks_msec() - _last_touch_msec < 500:
			return
		if event.pressed:
			_emit_tap(event.position)


func _emit_tap(point: Vector2) -> void:
	var local := normalized_at(point)
	if local.is_empty():
		return
	point_tapped.emit(Vector2(float(local.x), float(local.y)), touch_radius_normalized())


func _draw() -> void:
	draw_style_box(PlaygroundUI.style(PlaygroundUI.mix(accent, Color.WHITE, 0.9), 26, PlaygroundUI.mix(accent, Color.WHITE, 0.55), 2, 7, Color(0, 0, 0, 0.1)), Rect2(Vector2.ZERO, size))
	var font := PlaygroundUI.font()
	for side in 2:
		var rect: Rect2 = panel_rects()[side]
		var label := "左图" if side == 0 else "右图"
		draw_string(font, Vector2(rect.position.x + 6.0, rect.position.y - 11.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, PlaygroundUI.INK_SOFT)
		_draw_panel(rect, side)
	var divider: float = panel_rects()[0].end.x + 8.0
	draw_line(Vector2(divider, panel_rects()[0].position.y), Vector2(divider, panel_rects()[0].end.y), PlaygroundUI.mix(accent, Color.WHITE, 0.55), 2.0, true)


func _draw_panel(rect: Rect2, side: int) -> void:
	var theme_name := str(scene.get("theme", "forest"))
	var sky := Color("#dff3e3")
	var ground := Color("#b8d99a")
	match theme_name:
		"beach":
			sky = Color("#d9f3ff")
			ground = Color("#99d8ef")
		"space":
			sky = Color("#141d44")
			ground = Color("#232b59")
		"kitchen":
			sky = Color("#ffe8ce")
			ground = Color("#e9cda9")
		"garden":
			sky = Color("#e7f6dc")
			ground = Color("#b9db8d")
		"classroom":
			sky = Color("#edf2fb")
			ground = Color("#cbd9ea")
		"farm":
			sky = Color("#eaf6d1")
			ground = Color("#c3da8b")
		"castle":
			sky = Color("#e9ddf5")
			ground = Color("#cbb8de")
	draw_style_box(PlaygroundUI.style(PlaygroundUI.mix(accent, Color.WHITE, 0.94), 22, PlaygroundUI.mix(accent, Color.WHITE, 0.52), 2), rect)
	var picture := content_rect(rect)
	draw_rect(picture, sky)
	var ground_rect := Rect2(picture.position + Vector2(0, picture.size.y * 0.7), Vector2(picture.size.x, picture.size.y * 0.3))
	draw_rect(ground_rect, ground)
	_draw_backdrop(theme_name, picture, side)
	var objects: Variant = scene.get("objects", [])
	if objects is Array:
		for object in objects:
			if not object is Dictionary:
				continue
			_draw_scene_object(picture, object, side)
	var differences: Variant = scene.get("differences", [])
	if differences is Array:
		for difference in differences:
			if not difference is Dictionary:
				continue
			var identifier := str(difference.get("id", ""))
			var center := _point_in_panel(picture, difference)
			var radius := maxf(24.0, float(difference.get("radius", 0.07)) * minf(picture.size.x, picture.size.y))
			if identifier in found_ids:
				draw_arc(center, radius, 0.0, TAU, 40, accent, 4.0, true)
				draw_circle(center, 6.0, accent)
			elif identifier == hint_id:
				draw_arc(center, radius + 4.0 + sin(_clock * 7.0) * 4.0, 0.0, TAU, 40, Color("#e7b04b"), 4.0, true)
	if _wrong_remaining > 0.0:
		var wrong_center := _point_in_panel(picture, {"x": _wrong_at.x, "y": _wrong_at.y})
		draw_arc(wrong_center, 21.0, 0.0, TAU, 24, Color("#d66b52"), 3.0, true)
	draw_rect(picture, PlaygroundUI.mix(accent, Color.WHITE, 0.35), false, 1.0)


func _draw_backdrop(theme_name: String, rect: Rect2, side: int) -> void:
	match theme_name:
		"forest", "garden", "farm":
			draw_circle(rect.position + Vector2(rect.size.x * 0.82, rect.size.y * 0.18), minf(rect.size.x, rect.size.y) * 0.075, Color("#f2ce5d"))
			draw_circle(rect.position + Vector2(rect.size.x * 0.72, rect.size.y * 0.2), minf(rect.size.x, rect.size.y) * 0.045, Color("#fff4ba"))
		"beach":
			draw_circle(rect.position + Vector2(rect.size.x * 0.82, rect.size.y * 0.18), minf(rect.size.x, rect.size.y) * 0.07, Color("#f1c84e"))
			draw_rect(Rect2(rect.position + Vector2(0, rect.size.y * 0.62), Vector2(rect.size.x, rect.size.y * 0.08)), Color("#84cce4"))
		"space":
			for index in 12:
				var px := rect.position.x + fmod(float(index * 73 + side * 19), rect.size.x)
				var py := rect.position.y + fmod(float(index * 41 + 17), rect.size.y * 0.6)
				draw_circle(Vector2(px, py), 1.5 + float(index % 3), Color("#f6df8b"))
		"kitchen":
			draw_rect(Rect2(rect.position + Vector2(0, rect.size.y * 0.7), Vector2(rect.size.x, rect.size.y * 0.3)), Color("#e5c59b"))
			for index in 4:
				draw_line(rect.position + Vector2(0, rect.size.y * (0.72 + index * 0.06)), rect.position + Vector2(rect.size.x, rect.size.y * (0.72 + index * 0.06)), Color("#c89e6b"), 1.0, true)
		"classroom":
			draw_rect(Rect2(rect.position + Vector2(0, rect.size.y * 0.69), Vector2(rect.size.x, rect.size.y * 0.31)), Color("#c3d2e4"))
			for index in 5:
				draw_line(rect.position + Vector2(0, rect.size.y * (0.75 + index * 0.045)), rect.position + Vector2(rect.size.x, rect.size.y * (0.75 + index * 0.045)), Color("#aebfd3"), 1.0, true)
		"castle":
			draw_rect(Rect2(rect.position + Vector2(0, rect.size.y * 0.66), Vector2(rect.size.x, rect.size.y * 0.34)), Color("#c7b3da"))
			for index in 3:
				draw_rect(Rect2(rect.position + Vector2(rect.size.x * (0.1 + index * 0.3), rect.size.y * 0.08), Vector2(rect.size.x * 0.16, rect.size.y * 0.24)), Color("#d5c1e6"))


func _draw_scene_object(rect: Rect2, object: Dictionary, side: int) -> void:
	var visible_value: Variant = _property(object, side, "visible", true)
	if visible_value is bool and not visible_value:
		return
	var center := _point_in_panel(rect, object)
	var u := maxf(18.0, float(_property(object, side, "size", 0.12)) * minf(rect.size.x, rect.size.y))
	var color := PlaygroundUI.color(str(_property(object, side, "color", "#ffffff")))
	var angle := deg_to_rad(float(_property(object, side, "angle", 0.0)))
	var flip_value: Variant = _property(object, side, "flip", false)
	var sx := -1.0 if bool(flip_value) else 1.0
	draw_set_transform(center, angle, Vector2(sx, 1.0))
	_draw_object_shape(str(_property(object, side, "kind", "circle")), u, color)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_object_shape(kind: String, u: float, color: Color) -> void:
	var ink := PlaygroundUI.mix(color, Color.BLACK, 0.38)
	match kind:
		"tree":
			draw_rect(Rect2(Vector2(-u * 0.1, 0.0), Vector2(u * 0.2, u * 0.48)), Color("#9b6b3f"))
			draw_circle(Vector2(0, -u * 0.25), u * 0.34, color)
			draw_circle(Vector2(-u * 0.24, -u * 0.1), u * 0.24, color)
			draw_circle(Vector2(u * 0.24, -u * 0.1), u * 0.24, color)
		"bush":
			draw_circle(Vector2(-u * 0.22, 0), u * 0.26, color)
			draw_circle(Vector2(0, -u * 0.1), u * 0.32, color)
			draw_circle(Vector2(u * 0.24, 0), u * 0.25, color)
		"flower":
			draw_line(Vector2(0, u * 0.42), Vector2(0, 0), Color("#4f8b4a"), 3.0, true)
			for index in 5:
				draw_circle(Vector2(cos(TAU * index / 5.0), sin(TAU * index / 5.0)) * u * 0.2, u * 0.13, color)
			draw_circle(Vector2.ZERO, u * 0.1, Color("#f2c84d"))
		"cloud":
			draw_circle(Vector2(-u * 0.23, u * 0.02), u * 0.2, color)
			draw_circle(Vector2(0, -u * 0.08), u * 0.28, color)
			draw_circle(Vector2(u * 0.24, u * 0.02), u * 0.2, color)
		"rain":
			for index in 5:
				var drop_x := -u * 0.36 + float(index) * u * 0.18
				draw_line(Vector2(drop_x, -u * 0.1), Vector2(drop_x - u * 0.08, u * 0.4), color, maxf(2.0, u * 0.04), true)
		"sun":
			draw_circle(Vector2.ZERO, u * 0.3, color)
			for index in 8:
				var direction := Vector2.RIGHT.rotated(TAU * index / 8.0)
				draw_line(direction * u * 0.38, direction * u * 0.5, color, 3.0, true)
		"moon":
			draw_circle(Vector2.ZERO, u * 0.34, color)
			draw_circle(Vector2(u * 0.13, -u * 0.05), u * 0.28, Color("#141d44"))
		"star":
			var points := PackedVector2Array()
			for index in 10:
				var radius := u * 0.44 if index % 2 == 0 else u * 0.2
				var angle := -PI * 0.5 + index * PI / 5.0
				points.append(Vector2(cos(angle), sin(angle)) * radius)
			draw_colored_polygon(points, color)
		"bird":
			draw_circle(Vector2.ZERO, u * 0.18, color)
			draw_line(Vector2(-u * 0.1, 0), Vector2(-u * 0.4, -u * 0.1), color, 4.0, true)
			draw_line(Vector2(u * 0.1, 0), Vector2(u * 0.4, -u * 0.1), color, 4.0, true)
			draw_circle(Vector2(u * 0.12, -u * 0.07), 2.5, ink)
		"kite":
			draw_colored_polygon(PackedVector2Array([Vector2(0, -u * 0.45), Vector2(u * 0.35, 0), Vector2(0, u * 0.42), Vector2(-u * 0.35, 0)]), color)
			draw_line(Vector2(0, u * 0.42), Vector2(u * 0.12, u * 0.7), ink, 2.0, true)
			draw_line(Vector2(u * 0.12, u * 0.7), Vector2(-u * 0.05, u * 0.88), ink, 2.0, true)
		"fish":
			draw_circle(Vector2.ZERO, u * 0.3, color)
			draw_colored_polygon(PackedVector2Array([Vector2(u * 0.25, 0), Vector2(u * 0.48, -u * 0.2), Vector2(u * 0.48, u * 0.2)]), color)
			draw_circle(Vector2(-u * 0.1, -u * 0.06), 2.0, ink)
		"shell":
			draw_arc(Vector2.ZERO, u * 0.34, PI, TAU, 24, color, 8.0, true)
			for index in 4:
				draw_line(Vector2(0, u * 0.28), Vector2(cos(PI + index * PI / 4.0), sin(PI + index * PI / 4.0)) * u * 0.3, color, 2.0, true)
		"boat":
			draw_colored_polygon(PackedVector2Array([Vector2(-u * 0.42, 0), Vector2(u * 0.42, 0), Vector2(u * 0.28, u * 0.22), Vector2(-u * 0.28, u * 0.22)]), color)
			draw_line(Vector2(0, -u * 0.5), Vector2(0, 0), ink, 2.0, true)
			draw_colored_polygon(PackedVector2Array([Vector2(0, -u * 0.45), Vector2(u * 0.3, 0), Vector2(0, 0)]), Color("#fffaf0"))
		"rocket":
			draw_colored_polygon(PackedVector2Array([Vector2(0, -u * 0.5), Vector2(u * 0.22, u * 0.18), Vector2(0, u * 0.34), Vector2(-u * 0.22, u * 0.18)]), color)
			draw_colored_polygon(PackedVector2Array([Vector2(-u * 0.2, u * 0.08), Vector2(-u * 0.42, u * 0.28), Vector2(-u * 0.18, u * 0.28)]), Color("#e58a3f"))
			draw_circle(Vector2(0, -u * 0.12), u * 0.08, Color("#b9e7f3"))
		"tractor":
			draw_rect(Rect2(Vector2(-u * 0.32, -u * 0.24), Vector2(u * 0.52, u * 0.34)), color)
			draw_rect(Rect2(Vector2(-u * 0.12, -u * 0.4), Vector2(u * 0.25, u * 0.22)), PlaygroundUI.mix(color, Color.WHITE, 0.24))
			draw_circle(Vector2(-u * 0.26, u * 0.24), u * 0.18, ink)
			draw_circle(Vector2(u * 0.3, u * 0.24), u * 0.14, ink)
			draw_circle(Vector2(-u * 0.26, u * 0.24), u * 0.08, Color("#f1d17c"))
			draw_circle(Vector2(u * 0.3, u * 0.24), u * 0.06, Color("#f1d17c"))
		"planet":
			draw_circle(Vector2.ZERO, u * 0.34, color)
			draw_arc(Vector2.ZERO, u * 0.44, -PI * 0.16, PI * 1.16, 28, Color("#f0d58a"), 3.0, true)
		"book":
			draw_rect(Rect2(Vector2(-u * 0.42, -u * 0.3), Vector2(u * 0.42, u * 0.6)), color)
			draw_rect(Rect2(Vector2(0, -u * 0.3), Vector2(u * 0.42, u * 0.6)), PlaygroundUI.mix(color, Color.WHITE, 0.18))
			draw_line(Vector2(0, -u * 0.3), Vector2(0, u * 0.3), ink, 2.0, true)
		"cup":
			draw_rect(Rect2(Vector2(-u * 0.25, -u * 0.22), Vector2(u * 0.5, u * 0.44)), color)
			draw_arc(Vector2(u * 0.28, 0), u * 0.18, -PI * 0.5, PI * 0.5, 16, ink, 3.0, true)
		"lamp":
			draw_colored_polygon(PackedVector2Array([Vector2(-u * 0.3, -u * 0.25), Vector2(u * 0.3, -u * 0.25), Vector2(u * 0.18, 0), Vector2(-u * 0.18, 0)]), color)
			draw_line(Vector2(0, 0), Vector2(0, u * 0.28), ink, 3.0, true)
			draw_line(Vector2(-u * 0.22, u * 0.28), Vector2(u * 0.22, u * 0.28), ink, 3.0, true)
		"cat":
			draw_circle(Vector2.ZERO, u * 0.3, color)
			draw_colored_polygon(PackedVector2Array([Vector2(-u * 0.24, -u * 0.18), Vector2(-u * 0.12, -u * 0.48), Vector2(0, -u * 0.2)]), color)
			draw_colored_polygon(PackedVector2Array([Vector2(u * 0.24, -u * 0.18), Vector2(u * 0.12, -u * 0.48), Vector2(0, -u * 0.2)]), color)
			draw_circle(Vector2(-u * 0.1, -u * 0.03), 2.5, ink)
			draw_circle(Vector2(u * 0.1, -u * 0.03), 2.5, ink)
		"apple":
			draw_circle(Vector2.ZERO, u * 0.34, color)
			draw_line(Vector2(0, -u * 0.25), Vector2(u * 0.06, -u * 0.45), ink, 3.0, true)
			draw_circle(Vector2(u * 0.12, -u * 0.38), u * 0.1, Color("#70a94e"))
		"mushroom":
			draw_rect(Rect2(Vector2(-u * 0.12, 0), Vector2(u * 0.24, u * 0.35)), Color("#f1dfc0"))
			draw_arc(Vector2(0, 0), u * 0.34, PI, TAU, 20, color, u * 0.3, true)
			draw_circle(Vector2(-u * 0.12, -u * 0.12), u * 0.06, Color("#fff4dc"))
		"house":
			draw_rect(Rect2(Vector2(-u * 0.36, -u * 0.05), Vector2(u * 0.72, u * 0.45)), color)
			draw_colored_polygon(PackedVector2Array([Vector2(-u * 0.48, -u * 0.05), Vector2(0, -u * 0.48), Vector2(u * 0.48, -u * 0.05)]), PlaygroundUI.mix(color, Color.BLACK, 0.18))
			draw_rect(Rect2(Vector2(-u * 0.08, u * 0.16), Vector2(u * 0.16, u * 0.24)), Color("#8b5c3d"))
		"butterfly":
			draw_circle(Vector2(-u * 0.2, 0), u * 0.2, color)
			draw_circle(Vector2(u * 0.2, 0), u * 0.2, PlaygroundUI.mix(color, Color.WHITE, 0.18))
			draw_line(Vector2(0, -u * 0.2), Vector2(0, u * 0.28), ink, 2.0, true)
		"ball":
			draw_circle(Vector2.ZERO, u * 0.32, color)
			draw_arc(Vector2.ZERO, u * 0.32, -0.8, 0.8, 12, Color("#fffaf0"), 2.0, true)
			draw_arc(Vector2.ZERO, u * 0.32, PI - 0.8, PI + 0.8, 12, Color("#fffaf0"), 2.0, true)
		"robot":
			draw_rect(Rect2(Vector2(-u * 0.26, -u * 0.3), Vector2(u * 0.52, u * 0.5)), color)
			draw_rect(Rect2(Vector2(-u * 0.14, -u * 0.44), Vector2(u * 0.28, u * 0.14)), PlaygroundUI.mix(color, Color.WHITE, 0.25))
			draw_circle(Vector2(-u * 0.1, -u * 0.1), 3.0, ink)
			draw_circle(Vector2(u * 0.1, -u * 0.1), 3.0, ink)
		"bucket":
			draw_colored_polygon(PackedVector2Array([Vector2(-u * 0.3, -u * 0.2), Vector2(u * 0.3, -u * 0.2), Vector2(u * 0.2, u * 0.3), Vector2(-u * 0.2, u * 0.3)]), color)
			draw_line(Vector2(-u * 0.16, -u * 0.2), Vector2(0, -u * 0.45), ink, 2.0, true)
		"crab":
			draw_circle(Vector2.ZERO, u * 0.27, color)
			for side in [-1.0, 1.0]:
				draw_line(Vector2(side * u * 0.2, u * 0.1), Vector2(side * u * 0.42, u * 0.28), color, 2.0, true)
				draw_circle(Vector2(side * u * 0.28, -u * 0.12), u * 0.08, color)
			draw_circle(Vector2(-u * 0.1, -u * 0.08), 2.0, ink)
			draw_circle(Vector2(u * 0.1, -u * 0.08), 2.0, ink)
		"flag":
			draw_line(Vector2(-u * 0.22, -u * 0.42), Vector2(-u * 0.22, u * 0.4), ink, 2.0, true)
			draw_colored_polygon(PackedVector2Array([Vector2(-u * 0.2, -u * 0.38), Vector2(u * 0.34, -u * 0.22), Vector2(-u * 0.2, -u * 0.04)]), color)
		"rock":
			draw_colored_polygon(PackedVector2Array([Vector2(-u * 0.35, u * 0.28), Vector2(-u * 0.18, -u * 0.18), Vector2(u * 0.14, -u * 0.3), Vector2(u * 0.38, u * 0.24)]), color)
		_:
			draw_circle(Vector2.ZERO, u * 0.3, color)


func _property(object: Dictionary, side: int, key: String, fallback: Variant) -> Variant:
	var override_value: Variant = object.get("right" if side == 1 else "left", {})
	if override_value is Dictionary and override_value.has(key):
		return override_value[key]
	return object.get(key, fallback)


func _point_in_panel(rect: Rect2, value: Dictionary) -> Vector2:
	return rect.position + Vector2(float(value.get("x", 0.0)), float(value.get("y", 0.0))) * rect.size
