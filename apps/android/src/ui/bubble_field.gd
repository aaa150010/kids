class_name BubbleField
extends Control

signal action_requested(action: Dictionary)

const TAP_SLOP := 14.0
const NOTICE_SECONDS := 2.0

var engine: BubbleRules
var game_screen: NativeGameScreen
var players: Array = []
var accent := Color("#2f7e91")
var soft := Color("#e2f0f2")
var interactive := true

var fx: ArcadeFxLayer
var _board_area := Rect2()
var _board_card := Rect2()
var _hud_rect := Rect2()
var _wide_layout := true
var _world_origin := Vector2.ZERO
var _world_side := 1.0
var _clock := 0.0
var _style_cache: Dictionary = {}
var _notice := ""
var _notice_time := 0.0
var _aiming := false
var _pointer_id := -1
var _last_touch_msec := -1000
var _trail_active := false
var _trail_tick := 0.0
var _pop_ghosts: Array = []
var _fall_ghosts: Array = []
var _completed := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_CROSS
	focus_mode = Control.FOCUS_ALL
	fx = ArcadeFxLayer.new()
	fx.set_palette(accent, soft)
	fx.gravity = 90.0
	add_child(fx)
	_layout()
	queue_redraw()


func bind(value: BubbleRules, screen: NativeGameScreen, seat_players: Array) -> void:
	engine = value
	game_screen = screen
	players = seat_players.duplicate(true)
	if engine != null and engine.state.has("level"):
		accent = _safe_color(str(engine.state.level.get("accent", "#2f7e91")), accent)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_layout()
	queue_redraw()


func set_interactive(value: bool) -> void:
	interactive = value
	if not value:
		cancel_inputs()
	queue_redraw()


func cancel_inputs() -> void:
	_aiming = false
	_pointer_id = -1
	queue_redraw()


func suspend_effects() -> void:
	cancel_inputs()
	_trail_active = false
	_pop_ghosts.clear()
	_fall_ghosts.clear()
	if is_instance_valid(fx):
		fx.suspend_effects()
	queue_redraw()


func preview_ready() -> void:
	queue_redraw()


func flash_notice(message: String, seconds: float = NOTICE_SECONDS) -> void:
	_notice = message
	_notice_time = maxf(0.2, seconds)
	queue_redraw()


func _notification(what: int) -> void:
	if what in [NOTIFICATION_RESIZED, NOTIFICATION_ENTER_TREE]:
		_layout()
		queue_redraw()
	elif what in [NOTIFICATION_FOCUS_EXIT, NOTIFICATION_APPLICATION_FOCUS_OUT]:
		cancel_inputs()


func _process(delta: float) -> void:
	var frame := clampf(delta, 0.0, 0.1)
	_clock += frame
	_notice_time = maxf(0.0, _notice_time - frame)
	if is_instance_valid(fx):
		fx.tick(frame)
	var shake := fx.get_shake_offset() if is_instance_valid(fx) else Vector2.ZERO
	for ghost in _pop_ghosts:
		ghost.age = float(ghost.age) + frame
	for ghost in _fall_ghosts:
		ghost.age = float(ghost.age) + frame
		ghost.position = Vector2(ghost.position) + Vector2(ghost.velocity) * frame
		ghost.velocity = Vector2(ghost.velocity) + Vector2(0.0, 230.0) * frame
		ghost.rotation = float(ghost.rotation) + float(ghost.spin) * frame
	_pop_ghosts = _pop_ghosts.filter(func(ghost): return float(ghost.age) < float(ghost.life))
	_fall_ghosts = _fall_ghosts.filter(func(ghost): return float(ghost.age) < float(ghost.life))
	var projectile := engine.projectile_snapshot() if engine != null else {}
	if not projectile.is_empty():
		var position := _world_to_pixel(Vector2(float(projectile.get("x", 0.5)), float(projectile.get("y", 0.9)))) + shake
		if not _trail_active and is_instance_valid(fx):
			fx.begin_trail("bubble", position, _safe_color(engine.color_hex(str(projectile.get("color", ""))), accent), maxf(3.0, _bubble_radius() * 0.55))
			_trail_active = true
			_trail_tick = 0.0
		_trail_tick += frame
		if _trail_active and is_instance_valid(fx):
			fx.add_trail_point("bubble", position, maxf(2.5, _bubble_radius() * 0.22))
			if _trail_tick >= 0.055:
				_trail_tick = 0.0
				fx.emit_burst(position, _safe_color(engine.color_hex(str(projectile.get("color", ""))), accent), 2, {
					"speed": 18.0,
					"life": 0.34,
					"size": maxf(1.7, _bubble_radius() * 0.08),
					"kind": "star",
				})
	elif _trail_active:
		_trail_active = false
		if is_instance_valid(fx):
			fx.end_trail("bubble")
	queue_redraw()


func _layout() -> void:
	if engine == null:
		return
	var margin := 16.0
	var header_h := 58.0
	var body := Rect2(margin, header_h, maxf(1.0, size.x - margin * 2.0), maxf(1.0, size.y - header_h - margin))
	_wide_layout = body.size.x >= 960.0
	if _wide_layout:
		var hud_width := clampf(body.size.x * 0.26, 320.0, 410.0)
		_board_area = Rect2(body.position, Vector2(body.size.x - hud_width - 18.0, body.size.y))
		_hud_rect = Rect2(body.position.x + body.size.x - hud_width, body.position.y, hud_width, body.size.y)
	else:
		var hud_height := clampf(body.size.y * 0.20, 128.0, 176.0)
		_board_area = Rect2(body.position, Vector2(body.size.x, body.size.y - hud_height - 12.0))
		_hud_rect = Rect2(body.position.x, body.position.y + body.size.y - hud_height, body.size.x, hud_height)
	var side := maxf(120.0, minf(_board_area.size.x - 26.0, _board_area.size.y - 26.0))
	_world_side = side
	_world_origin = _board_area.position + (_board_area.size - Vector2(side, side)) * 0.5
	_board_card = Rect2(_world_origin - Vector2(18.0, 18.0), Vector2(side + 36.0, side + 36.0))
	_board_card.position.y = maxf(_board_area.position.y, _board_card.position.y)


func _gui_input(event: InputEvent) -> void:
	if _blocked():
		return
	if event is InputEventScreenTouch:
		if event.device == InputEvent.DEVICE_ID_EMULATION:
			return
		_last_touch_msec = Time.get_ticks_msec()
		if event.pressed:
			_begin_pointer(event.index, event.position)
		elif _pointer_id == event.index:
			_finish_pointer(event.position)
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		_last_touch_msec = Time.get_ticks_msec()
		if _pointer_id == event.index:
			_update_pointer(event.position)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if Time.get_ticks_msec() - _last_touch_msec < 500:
			return
		if event.pressed:
			_begin_pointer(0, event.position)
		elif _pointer_id == 0:
			_finish_pointer(event.position)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _pointer_id == 0 and _aiming:
		if Time.get_ticks_msec() - _last_touch_msec >= 500:
			_update_pointer(event.position)


func _begin_pointer(identifier: int, position: Vector2) -> void:
	if not _board_card.has_point(position):
		return
	if not engine.projectile_snapshot().is_empty():
		return
	_aiming = true
	_pointer_id = identifier
	_update_pointer(position)
	if is_instance_valid(fx):
		fx.emit_burst(position, accent, 4, {"speed": 34.0, "life": 0.24, "size": 3.0})
	AudioFX.play("select")


func _update_pointer(position: Vector2) -> void:
	if not _aiming or engine == null:
		return
	var world_point := (position - _world_origin) / maxf(1.0, _world_side)
	var shooter := Vector2(0.5, float(engine.state.level.get("shooterY", 0.9)))
	var direction := world_point - shooter
	if direction.length_squared() <= 0.000001:
		direction = Vector2.UP
	engine.set_aim_direction({"x": direction.x, "y": direction.y})
	queue_redraw()


func _finish_pointer(position: Vector2) -> void:
	if not _aiming:
		_pointer_id = -1
		return
	_update_pointer(position)
	var fired := _aiming
	_aiming = false
	_pointer_id = -1
	if not fired or _blocked() or not engine.projectile_snapshot().is_empty():
		return
	var aim_value: Variant = engine.state.get("aim", {"x":0.0,"y":-1.0})
	var aim: Dictionary = aim_value if aim_value is Dictionary else {"x":0.0,"y":-1.0}
	action_requested.emit({"type":"fire","aim":aim.duplicate()})


func consume_events(events: Array) -> void:
	if engine == null:
		return
	for raw in events:
		if not raw is Dictionary:
			continue
		var event: Dictionary = raw
		var point := _event_point(event)
		match str(event.get("type", "")):
			"fire":
				_trail_active = false
				if is_instance_valid(fx):
					fx.emit_burst(point, _event_color(event), 10, {
						"speed": 56.0,
						"spread": 1.1,
						"direction": Vector2.UP,
						"life": 0.34,
						"size": 4.0,
					})
					fx.ring(point, Color(_event_color(event), 0.72), maxf(12.0, _bubble_radius() * 0.34), 0.3)
				AudioFX.play("whoosh")
			"bounce":
				if is_instance_valid(fx):
					fx.emit_burst(point, _event_color(event), 5, {"speed": 42.0, "life": 0.24, "size": 2.8})
					fx.shake(2.0, 0.12)
				AudioFX.play("tap")
			"attach":
				if is_instance_valid(fx):
					fx.ring(point, _event_color(event), maxf(10.0, _bubble_radius() * 0.32), 0.34)
					fx.emit_burst(point, _event_color(event), 5, {"speed": 26.0, "life": 0.28, "size": 2.6, "kind":"bubble"})
				AudioFX.play("drop")
			"pop":
				_consume_pop(event)
			"drop":
				_consume_drop(event)
			"miss":
				flash_notice("泡泡从边上溜走了，再瞄一次。")
				AudioFX.play("wrong")
			"turn":
				if str(engine.state.get("modeId", "")) == "classic":
					var seat := clampi(int(event.get("seat", 0)), 0, maxi(0, players.size() - 1))
					var player_name := str(players[seat].get("name", "下一位")) if seat < players.size() else "下一位"
					flash_notice("轮到 %s 发射" % player_name, 1.35)
			"complete":
				_completed = true
				_trail_active = false
				if is_instance_valid(fx):
					fx.ring(point, Color("#efc755"), maxf(50.0, _world_side * 0.12), 0.8, 4.0)
					for burst_index in 6:
						var angle := TAU * float(burst_index) / 6.0
						var target := point + Vector2(cos(angle), sin(angle)) * _world_side * 0.13
						fx.emit_burst(target, Color("#f2d36b"), 10, {"speed": 72.0, "life": 0.65, "size": 4.0, "kind":"star"})
					fx.shake(5.0, 0.3)
				AudioFX.play("win" if bool(event.get("success", false)) else "wrong")
	queue_redraw()


func _consume_pop(event: Dictionary) -> void:
	var cells_value: Variant = event.get("cells", [])
	var cells: Array = cells_value if cells_value is Array else []
	var count := cells.size()
	for raw in cells:
		if not raw is Dictionary:
			continue
		var cell: Dictionary = raw
		var center := _world_to_pixel(Vector2(float(cell.get("x", 0.5)), float(cell.get("y", 0.5))))
		var color := _safe_color(str(cell.get("hex", "#2f7e91")), _event_color(event))
		_pop_ghosts.append({
			"position":center,
			"color":color,
			"star":bool(cell.get("star", false)),
			"age":0.0,
			"life":0.28,
		})
		if is_instance_valid(fx):
			fx.emit_burst(center, color, 8, {"speed": 82.0, "life": 0.48, "size": maxf(2.5, _bubble_radius()*0.12), "kind":"bubble"})
			fx.emit_burst(center, Color("#fff2b5"), 4, {"speed": 55.0, "life": 0.52, "size": maxf(2.2, _bubble_radius()*0.10), "kind":"star"})
			fx.ring(center, Color(color, 0.68), maxf(12.0, _bubble_radius()*0.45), 0.38)
	if count > 0:
		var midpoint := _event_point(event)
		if is_instance_valid(fx):
			var bonus := maxi(0, count - 3) * 15 + int(event.get("newStars", 0)) * 20
			var popup_text := "连消 +%s" % (count * 10 + bonus)
			fx.popup(popup_text, midpoint + Vector2(0, -_bubble_radius() * 0.8), accent, 22, 0.75)
			fx.shake(3.5 if count < 5 else 5.2, 0.2)
		AudioFX.play("pair")
	elif is_instance_valid(fx):
		fx.emit_burst(_event_point(event), _event_color(event), 8, {"speed": 60.0, "life": 0.4})


func _consume_drop(event: Dictionary) -> void:
	var cells_value: Variant = event.get("cells", [])
	var cells: Array = cells_value if cells_value is Array else []
	for raw in cells:
		if not raw is Dictionary:
			continue
		var cell: Dictionary = raw
		var center := _world_to_pixel(Vector2(float(cell.get("x", 0.5)), float(cell.get("y", 0.5))))
		_fall_ghosts.append({
			"position":center,
			"velocity":Vector2(randf_range(-38.0, 38.0), randf_range(-15.0, 10.0)),
			"color":_safe_color(str(cell.get("hex", "#2f7e91")), _event_color(event)),
			"star":bool(cell.get("star", false)),
			"angle":0.0,
			"rotation":randf_range(0.0, TAU),
			"spin":randf_range(-3.0, 3.0),
			"age":0.0,
			"life":randf_range(0.62, 0.9),
		})
	if not _fall_ghosts.is_empty() and is_instance_valid(fx):
		fx.popup("掉落 +%s" % (cells.size() * 15), _event_point(event), Color("#9a7424"), 19, 0.65)
	AudioFX.play("drop")


func _draw() -> void:
	var shake := fx.get_shake_offset() if is_instance_valid(fx) else Vector2.ZERO
	_draw_backdrop(shake)
	if engine == null or str(engine.state.get("phase", "")) == "empty":
		_draw_empty()
		return
	_draw_board(shake)
	_draw_aim(shake)
	_draw_launcher(shake)
	_draw_header()
	_draw_hud()
	_draw_notice()
	if _completed:
		_draw_complete_glow()


func _draw_backdrop(shake: Vector2) -> void:
	var full := Rect2(Vector2.ZERO, size)
	draw_style_box(_style(Color("#f9f4e8"), 30, Color(accent, 0.20), 2), full.grow(-2.0))
	var wash := Rect2(12.0, 12.0, size.x - 24.0, size.y - 24.0)
	draw_style_box(_style(Color(soft, 0.58), 24, Color.TRANSPARENT, 0), wash)
	for index in 13:
		var x := fmod(57.0 + float(index) * 137.0, maxf(1.0, size.x))
		var y := 34.0 + fmod(float(index) * 89.0, maxf(1.0, size.y * 0.58))
		var radius := 2.0 + float(index % 3)
		draw_circle(Vector2(x, y) + shake * 0.24, radius, Color(accent, 0.12 + float(index % 2) * 0.06))
	var big_ring := _world_to_pixel(Vector2(0.5, 0.84)) + shake
	draw_arc(big_ring, _world_side * 0.33, PI * 0.1, PI * 0.9, 64, Color(accent, 0.08), maxf(12.0, _world_side * 0.025), true)


func _draw_empty() -> void:
	var font := PlaygroundUI.font()
	var center := size * 0.5
	draw_string(font, center - Vector2(170, 0), "这一张泡泡关还没有准备好", HORIZONTAL_ALIGNMENT_CENTER, 340, 24, PlaygroundUI.INK_SOFT)


func _draw_board(shake: Vector2) -> void:
	draw_style_box(_style(Color("#fff9ed"), 34, Color(accent, 0.46), 3), _board_card)
	var inner := _board_card.grow(-9.0)
	draw_style_box(_style(Color("#183e50"), 28, Color("#d5ecee"), 2), inner)
	var sky_top := Color("#1a4459")
	var sky_bottom := Color("#245f70")
	var bands := 18
	for index in bands:
		var amount := float(index) / float(bands - 1)
		var row_rect := Rect2(
			inner.position.x,
			inner.position.y + inner.size.y * amount,
			inner.size.x,
			inner.size.y / float(bands) + 1.0
		)
		draw_rect(row_rect, sky_top.lerp(sky_bottom, amount))
	for index in 10:
		var star_x := inner.position.x + 20.0 + fmod(float(index) * 83.0, maxf(20.0, inner.size.x - 40.0))
		var star_y := inner.position.y + 20.0 + fmod(float(index) * 61.0, maxf(20.0, inner.size.y * 0.62))
		_draw_star(Vector2(star_x, star_y) + shake * 0.5, 2.0 + float(index % 2), Color(0.96, 0.88, 0.62, 0.38), 0.0)
	var ceiling := _world_to_pixel(Vector2(0.0, float(engine.state.level.get("ceiling", 0.035)))) + shake
	draw_line(ceiling, ceiling + Vector2(inner.size.x, 0.0), Color("#d8eef0"), 4.0)
	var danger_y := float(engine.state.level.get("dangerY", 0.69))
	var danger_start := _world_to_pixel(Vector2(0.04, danger_y)) + shake
	var danger_finish := _world_to_pixel(Vector2(0.96, danger_y)) + shake
	_draw_dashed_line(danger_start, danger_finish, Color("#efb4a7"), 2.0, 8.0, 7.0)
	draw_string(
		PlaygroundUI.font(),
		danger_start + Vector2(8.0, -7.0),
		"泡泡警戒线",
		HORIZONTAL_ALIGNMENT_LEFT,
		160.0,
		13,
		Color("#f1c9bd")
	)
	var board_value: Variant = engine.state.get("board", [])
	for raw in board_value if board_value is Array else []:
		if raw is Dictionary:
			_draw_cell(raw, shake)
	for ghost in _pop_ghosts:
		var ratio := clampf(float(ghost.age) / maxf(0.001, float(ghost.life)), 0.0, 1.0)
		var radius := _bubble_radius() * (1.0 - ratio * 0.7)
		var color: Color = ghost.color
		color.a *= 1.0 - ratio
		draw_circle(Vector2(ghost.position) + shake, radius, color)
		draw_arc(Vector2(ghost.position) + shake, radius, 0.0, TAU, 28, Color(1,1,1,1.0-ratio), 2.5, true)
	for ghost in _fall_ghosts:
		var ratio := clampf(float(ghost.age) / maxf(0.001, float(ghost.life)), 0.0, 1.0)
		var color: Color = ghost.color
		color.a *= 1.0 - ratio
		var position := Vector2(ghost.position) + Vector2(0.0, sin(float(ghost.rotation)) * _bubble_radius() * 0.12)
		draw_circle(position, _bubble_radius() * (1.0 - ratio * 0.35), color)
		if bool(ghost.get("star", false)):
			_draw_star(position, _bubble_radius() * 0.32, Color(1,1,1,1.0-ratio), float(ghost.get("rotation", 0.0)))


func _draw_cell(cell: Dictionary, shake: Vector2) -> void:
	var row := int(cell.get("row", 0))
	var column := int(cell.get("col", 0))
	var center := _world_to_pixel(engine.cell_center(row, column)) + shake
	var radius := _bubble_radius()
	var definition := engine.color_definition(str(cell.get("color", "")))
	var color := _safe_color(str(definition.get("hex", "#2f7e91")), accent)
	var deep := _safe_color(str(definition.get("deep", "#1b5664")), color.darkened(0.3))
	draw_circle(center + Vector2(0.0, radius * 0.16), radius * 1.02, Color(0.02, 0.12, 0.13, 0.26))
	draw_circle(center, radius, deep)
	draw_circle(center - Vector2(0.0, radius * 0.07), radius * 0.91, color)
	draw_circle(center - Vector2(radius * 0.26, radius * 0.29), radius * 0.25, Color(1, 1, 1, 0.34))
	draw_arc(center, radius * 0.91, PI * 0.08, PI * 0.92, 24, Color(1, 1, 1, 0.20), maxf(1.5, radius * 0.06), true)
	draw_arc(center, radius * 0.98, 0.0, TAU, 30, Color(deep, 0.52), maxf(1.0, radius * 0.035), true)
	if bool(cell.get("star", false)):
		_draw_star(center + Vector2(radius * 0.08, 0.0), radius * 0.32, Color("#fff3b3"), _clock * 0.35)
		draw_arc(center, radius * 0.55, -PI * 0.74, -PI * 0.25, 16, Color(1, 1, 1, 0.54), maxf(1.2, radius * 0.04), true)


func _draw_aim(shake: Vector2) -> void:
	var points_value: Array = engine.aim_preview(8)
	if points_value.size() < 2:
		return
	var pixel_points: Array[Vector2] = []
	for point in points_value:
		if point is Vector2:
			pixel_points.append(_world_to_pixel(point) + shake)
	if pixel_points.size() < 2:
		return
	var current_hex := engine.color_hex(engine.current_color())
	var current_color := _safe_color(current_hex, accent)
	for index in range(1, pixel_points.size()):
		var start := pixel_points[index - 1]
		var finish := pixel_points[index]
		_draw_dashed_line(start, finish, Color(current_color, 0.34 + float(index) * 0.03), maxf(2.0, _bubble_radius() * 0.07), 9.0, 7.0)
	var landing: Vector2 = pixel_points.back()
	var pulse := 0.75 + sin(_clock * 4.0) * 0.12
	draw_circle(landing, _bubble_radius() * (0.82 + sin(_clock * 3.2) * 0.04), Color(current_color, 0.12))
	draw_arc(landing, _bubble_radius() * 0.86, 0.0, TAU, 32, Color(current_color, 0.54), 2.5, true)
	draw_arc(landing, _bubble_radius() * pulse, 0.0, TAU, 32, Color(1,1,1,0.30), 1.5, true)
	if _aiming:
		var direction := (pixel_points[1] - pixel_points[0]).normalized()
		if direction.length_squared() > 0.1:
			_draw_arrow(pixel_points[0] + direction * _bubble_radius() * 0.75, direction, current_color)


func _draw_launcher(shake: Vector2) -> void:
	var shooter_norm := Vector2(0.5, float(engine.state.level.get("shooterY", 0.9)))
	var center := _world_to_pixel(shooter_norm) + shake
	var radius := _bubble_radius()
	var current_id := engine.current_color()
	var current_color := _safe_color(engine.color_hex(current_id), accent)
	var aim_value: Variant = engine.state.get("aim", {"x":0.0,"y":-1.0})
	var aim: Dictionary = aim_value if aim_value is Dictionary else {"x":0.0,"y":-1.0}
	var direction := Vector2(float(aim.get("x", 0.0)), float(aim.get("y", -1.0))).normalized()
	var base_rect := Rect2(center - Vector2(radius * 1.6, radius * 0.72), Vector2(radius * 3.2, radius * 1.18))
	draw_style_box(_style(Color("#fdf4dd"), int(radius * 0.48), Color(accent, 0.72), 3), base_rect)
	draw_circle(center + Vector2(0.0, radius * 0.22), radius * 1.16, Color(access_color_dark(), 0.42))
	draw_arc(center + Vector2(0.0, radius * 0.23), radius * 1.05, PI * 0.08, PI * 0.92, 30, Color(accent, 0.72), maxf(2.0, radius * 0.08), true)
	var bubble_center := center - Vector2(0.0, radius * 0.65)
	_draw_launcher_bubble(bubble_center, radius * 0.82, current_color, direction)
	var barrel_start := bubble_center + direction * radius * 0.76
	var barrel_finish := bubble_center + direction * radius * 1.65
	draw_line(barrel_start, barrel_finish, Color("#f8e6b4"), maxf(4.0, radius * 0.16), true)
	draw_circle(barrel_finish, maxf(3.2, radius * 0.10), current_color)
	draw_string(
		PlaygroundUI.font(),
		center + Vector2(-radius * 1.7, radius * 1.75),
		"按住瞄准 · 松手发射",
		HORIZONTAL_ALIGNMENT_CENTER,
		radius * 3.4,
		14,
		Color("#e6f7f6")
	)


func _draw_launcher_bubble(center: Vector2, radius: float, color: Color, direction: Vector2) -> void:
	draw_circle(center + Vector2(0, 3), radius * 1.03, Color(0.02, 0.1, 0.12, 0.3))
	draw_circle(center, radius, color.darkened(0.2))
	draw_circle(center - Vector2(0, radius * 0.06), radius * 0.9, color)
	draw_circle(center - Vector2(radius * 0.27, radius * 0.3), radius * 0.23, Color(1,1,1,0.52))
	draw_arc(center, radius * 0.92, 0.0, TAU, 30, Color(1,1,1,0.25), 2.0, true)
	var notch := center + direction * radius * 0.48
	draw_circle(notch, maxf(2.0, radius * 0.10), Color("#fff8de"))


func _draw_header() -> void:
	var font := PlaygroundUI.font()
	var title := engine.level_title()
	draw_string(font, Vector2(28, 37), "泡泡星星", HORIZONTAL_ALIGNMENT_LEFT, -1, 27, accent)
	draw_string(font, Vector2(162, 35), "第 %s 关 · %s" % [int(engine.state.get("levelNumber", 1)), title], HORIZONTAL_ALIGNMENT_LEFT, maxf(100.0, size.x - 500.0), 17, PlaygroundUI.INK)
	var band_label: String = str({"easy":"轻松", "normal":"标准", "challenge":"挑战"}.get(engine.level_band(), "轻松"))
	var score_text := "得分 %s" % int(engine.state.get("score", 0))
	var moves_text := "余 %s 步" % engine.remaining_moves()
	var right := size.x - 28.0
	draw_string(font, Vector2(right - 240, 25), band_label, HORIZONTAL_ALIGNMENT_RIGHT, 240, 14, Color(accent, 0.82))
	draw_string(font, Vector2(right - 330, 47), score_text, HORIZONTAL_ALIGNMENT_RIGHT, 180, 17, PlaygroundUI.INK_SOFT)
	draw_string(font, Vector2(right - 144, 47), moves_text, HORIZONTAL_ALIGNMENT_RIGHT, 144, 18, accent)


func _draw_hud() -> void:
	if _wide_layout:
		_draw_side_hud()
	else:
		_draw_compact_hud()


func _draw_side_hud() -> void:
	var gap := 10.0
	var card_h := 126.0
	var top := _hud_rect.position
	_draw_hud_card(Rect2(top, Vector2(_hud_rect.size.x, card_h)), "本局目标")
	var goals := engine.goal_progress()
	var y := top.y + 40.0
	for goal in goals:
		_draw_goal_row(Vector2(top.x + 20.0, y), _hud_rect.size.x - 40.0, goal)
		y += 38.0
	_draw_hud_card(Rect2(top.x, top.y + card_h + gap, _hud_rect.size.x, 190.0), "颜色队列")
	_draw_queue_block(Vector2(top.x + 20.0, top.y + card_h + gap + 42.0), _hud_rect.size.x - 40.0)
	var stats_y := top.y + card_h + gap + 190.0 + gap
	_draw_hud_card(Rect2(top.x, stats_y, _hud_rect.size.x, maxf(120.0, _hud_rect.end.y - stats_y)), "本局小成绩")
	_draw_stats_block(Vector2(top.x + 20.0, stats_y + 44.0), _hud_rect.size.x - 40.0)


func _draw_compact_hud() -> void:
	_draw_hud_card(_hud_rect, "目标与颜色")
	var goal_x := _hud_rect.position.x + 20.0
	var goal_y := _hud_rect.position.y + 38.0
	var goals := engine.goal_progress()
	var goal_index := 0
	for goal in goals:
		_draw_goal_row(Vector2(goal_x + float(goal_index) * ((_hud_rect.size.x - 40.0) * 0.5), goal_y), (_hud_rect.size.x - 40.0) * 0.5 - 12.0, goal)
		goal_index += 1
	_draw_queue_block(Vector2(_hud_rect.position.x + 20.0, goal_y + 48.0), _hud_rect.size.x - 40.0, true)


func _draw_hud_card(rect: Rect2, label: String) -> void:
	draw_style_box(_style(Color("#fffaf0"), 22, Color(accent, 0.24), 2), rect)
	draw_style_box(_style(Color(soft, 0.70), 15, Color.TRANSPARENT, 0), Rect2(rect.position + Vector2(12, 11), Vector2(minf(rect.size.x - 24.0, 116.0), 24.0)))
	draw_string(PlaygroundUI.font(), rect.position + Vector2(22, 28), label, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 44.0, 15, accent)


func _draw_goal_row(position: Vector2, width: float, goal: Dictionary) -> void:
	var done := bool(goal.get("done", false))
	var color := accent if not done else Color("#5b9a66")
	_draw_star(position + Vector2(7, 8), 6.0, color, 0.0)
	draw_string(PlaygroundUI.font(), position + Vector2(20, 15), str(goal.get("label", "完成目标")), HORIZONTAL_ALIGNMENT_LEFT, width - 24.0, 16, PlaygroundUI.INK if done else PlaygroundUI.INK_SOFT)
	var bar := Rect2(position + Vector2(20, 22), Vector2(maxf(30.0, width - 26.0), 5.0))
	draw_style_box(_style(Color(accent, 0.12), 4, Color.TRANSPARENT, 0), bar)
	var ratio := clampf(float(goal.get("current", 0)) / maxf(1.0, float(goal.get("target", 1))), 0.0, 1.0)
	draw_style_box(_style(Color(color, 0.80), 4, Color.TRANSPARENT, 0), Rect2(bar.position, Vector2(bar.size.x * ratio, bar.size.y)))


func _draw_queue_block(position: Vector2, width: float, compact: bool = false) -> void:
	var queue: Array = engine.next_colors(4)
	var current_id := engine.current_color()
	var current_color := _safe_color(engine.color_hex(current_id), accent)
	var radius := 20.0 if compact else 27.0
	draw_string(PlaygroundUI.font(), position + Vector2(0, 15), "现在", HORIZONTAL_ALIGNMENT_LEFT, 64, 14, PlaygroundUI.INK_SOFT)
	draw_circle(position + Vector2(radius + 58.0, -1.0), radius, current_color)
	draw_circle(position + Vector2(radius + 49.0, -8.0), radius * 0.25, Color(1,1,1,0.44))
	draw_arc(position + Vector2(radius + 58.0, -1.0), radius, 0.0, TAU, 26, Color(accent,0.58), 2.0, true)
	var start_x := 130.0
	for index in queue.size():
		if index == 0:
			continue
		var color := _safe_color(str(queue[index].get("hex", "#2f7e91")), accent)
		var center := position + Vector2(start_x + float(index - 1) * (radius * 2.0 + 12.0), -1.0)
		draw_circle(center, radius * 0.74, color)
		draw_circle(center + Vector2(-radius*0.17, -radius*0.2), radius*0.17, Color(1,1,1,0.4))
	draw_string(PlaygroundUI.font(), position + Vector2(start_x, -radius - 8.0), "接下来", HORIZONTAL_ALIGNMENT_LEFT, width - start_x, 13, PlaygroundUI.INK_SOFT)
	draw_string(PlaygroundUI.font(), position + Vector2(0, radius + 30.0), "颜色顺序固定，每个小朋友都看得见。", HORIZONTAL_ALIGNMENT_LEFT, width, 13, PlaygroundUI.INK_SOFT)
	var player_text := "单人闯关"
	if str(engine.state.get("modeId", "")) == "classic" and players.size() >= 2:
		var seat := engine.current_player_index()
		player_text = "轮到 %s" % str(players[seat].get("name", "下一位"))
	draw_string(PlaygroundUI.font(), position + Vector2(0, radius + 53.0), player_text, HORIZONTAL_ALIGNMENT_LEFT, width, 16, accent)


func _draw_stats_block(position: Vector2, width: float) -> void:
	var font := PlaygroundUI.font()
	var stats := [
		["连消泡泡", str(int(engine.state.get("popped", 0)))],
		["掉落泡泡", str(int(engine.state.get("dropped", 0)))],
		["亮起星星", str(int(engine.state.get("starsPopped", 0)))],
		["剩余步数", str(engine.remaining_moves())],
	]
	for index in stats.size():
		var column := index % 2
		var row := index / 2
		var x := position.x + float(column) * width * 0.52
		var y := position.y + float(row) * 48.0
		draw_string(font, Vector2(x, y), str(stats[index][0]), HORIZONTAL_ALIGNMENT_LEFT, width * 0.45, 13, PlaygroundUI.INK_SOFT)
		draw_string(font, Vector2(x, y + 20), str(stats[index][1]), HORIZONTAL_ALIGNMENT_LEFT, width * 0.45, 23, accent)
	var hint := str(engine.state.get("level", {}).get("hint", ""))
	if not hint.is_empty() and position.y + 102.0 < _hud_rect.end.y - 8.0:
		draw_multiline_string(font, Vector2(position.x, position.y + 105.0), hint, HORIZONTAL_ALIGNMENT_LEFT, width, 13, 2, Color(PlaygroundUI.INK_SOFT, 0.84))


func _draw_notice() -> void:
	if _notice_time <= 0.0 or _notice.is_empty():
		return
	var alpha := clampf(_notice_time / 0.7, 0.0, 1.0)
	var width := minf(size.x - 160.0, 520.0)
	var font := PlaygroundUI.font()
	var text_size := font.get_string_size(_notice, HORIZONTAL_ALIGNMENT_LEFT, -1, 18)
	var box := Rect2(Vector2((size.x - width) * 0.5, 23.0), Vector2(width, 40.0))
	draw_style_box(_style(Color(0.10, 0.20, 0.22, 0.88 * alpha), 16, Color(accent, 0.35 * alpha), 1), box)
	draw_string(font, Vector2((size.x - text_size.x) * 0.5, 49.0), _notice, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1,1,1,alpha))


func _draw_complete_glow() -> void:
	var center := _world_to_pixel(Vector2(0.5, 0.44))
	var radius := _world_side * (0.26 + sin(_clock * 2.1) * 0.015)
	draw_circle(center, radius, Color(0.98, 0.83, 0.38, 0.06))
	draw_arc(center, radius, 0.0, TAU, 64, Color(0.98, 0.83, 0.38, 0.22), 3.0, true)


func _event_point(event: Dictionary) -> Vector2:
	return _world_to_pixel(Vector2(float(event.get("x", 0.5)), float(event.get("y", 0.5))))


func _event_color(event: Dictionary) -> Color:
	var value := str(event.get("color", ""))
	if value.is_valid_html_color():
		return Color(value)
	return accent


func _world_to_pixel(point: Vector2) -> Vector2:
	return _world_origin + point * _world_side


func _bubble_radius() -> float:
	if engine == null:
		return 24.0
	return float(engine.state.get("level", {}).get("radius", 0.043)) * _world_side


func _blocked() -> bool:
	if not interactive or engine == null or str(engine.state.get("phase", "")) != "playing":
		return true
	if game_screen != null and game_screen.is_input_blocked():
		return true
	return false


func _safe_color(value: String, fallback: Color) -> Color:
	return Color(value) if value.is_valid_html_color() else fallback


func access_color_dark() -> Color:
	return accent.darkened(0.55)


func _style(fill: Color, radius: int, border: Color, border_width: int) -> StyleBoxFlat:
	var key := "%s|%s|%s|%s" % [fill.to_html(), radius, border.to_html(), border_width]
	if _style_cache.has(key):
		return _style_cache[key]
	var style := PlaygroundUI.style(fill, radius, border, border_width)
	_style_cache[key] = style
	return style


func _draw_dashed_line(
	start: Vector2,
	finish: Vector2,
	color: Color,
	width: float,
	dash: float,
	gap: float
) -> void:
	var delta := finish - start
	var length := delta.length()
	if length <= 0.001:
		return
	var direction := delta / length
	var cursor := 0.0
	while cursor < length:
		var segment_end := minf(length, cursor + dash)
		draw_line(start + direction * cursor, start + direction * segment_end, color, width, true)
		cursor += dash + gap


func _draw_arrow(center: Vector2, direction: Vector2, color: Color) -> void:
	var side := Vector2(-direction.y, direction.x)
	var size_value := maxf(6.0, _bubble_radius() * 0.18)
	draw_colored_polygon(PackedVector2Array([
		center + direction * size_value * 1.4,
		center - direction * size_value * 0.6 + side * size_value * 0.7,
		center - direction * size_value * 0.6 - side * size_value * 0.7,
	]), color)


func _draw_star(center: Vector2, radius: float, color: Color, rotation: float) -> void:
	var points := PackedVector2Array()
	for index in 10:
		var angle := rotation - PI * 0.5 + float(index) * PI / 5.0
		var length := radius if index % 2 == 0 else radius * 0.44
		points.append(center + Vector2(cos(angle), sin(angle)) * length)
	draw_colored_polygon(points, color)
