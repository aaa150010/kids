class_name BreakoutField
extends Control

signal action_requested(action: Dictionary)

const NOTICE_SECONDS := 2.0
const TAP_SLOP := 14.0

var engine: BreakoutRules
var game_screen: NativeGameScreen
var players: Array = []
var accent := Color("#b35f36")
var soft := Color("#f7e7dc")
var interactive := true

var fx: ArcadeFxLayer
var _board_area := Rect2()
var _board_card := Rect2()
var _world_rect := Rect2()
var _hud_rect := Rect2()
var _wide_layout := true
var _clock := 0.0
var _style_cache: Dictionary = {}
var _notice := ""
var _notice_time := 0.0
var _pointers: Dictionary = {}
var _last_touch_msec := -1000


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	fx = ArcadeFxLayer.new()
	fx.set_palette(accent, soft)
	fx.gravity = 90.0
	add_child(fx)
	resized.connect(_layout)
	_layout()
	queue_redraw()


func bind(value: BreakoutRules, screen: NativeGameScreen, seat_players: Array) -> void:
	engine = value
	game_screen = screen
	players = seat_players.duplicate(true)
	_pointers.clear()
	_notice = ""
	_notice_time = 0.0
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
	_pointers.clear()
	queue_redraw()


func suspend_effects() -> void:
	cancel_inputs()
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
	elif what in [NOTIFICATION_FOCUS_EXIT, NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED]:
		cancel_inputs()


func _process(delta: float) -> void:
	var frame := clampf(delta, 0.0, 0.1)
	_clock += frame
	_notice_time = maxf(0.0, _notice_time - frame)
	if is_instance_valid(fx):
		fx.tick(frame)
	queue_redraw()


func _layout() -> void:
	if size.x < 2.0 or size.y < 2.0:
		return
	var margin := 14.0
	var header := 54.0
	var body := Rect2(
		margin,
		header,
		maxf(1.0, size.x - margin * 2.0),
		maxf(1.0, size.y - header - margin)
	)
	_wide_layout = body.size.x >= 960.0
	if _wide_layout:
		var hud_width := clampf(body.size.x * 0.24, 286.0, 360.0)
		_board_area = Rect2(body.position, Vector2(body.size.x - hud_width - 16.0, body.size.y))
		_hud_rect = Rect2(body.position.x + body.size.x - hud_width, body.position.y, hud_width, body.size.y)
	else:
		var hud_height := clampf(body.size.y * 0.22, 126.0, 168.0)
		_board_area = Rect2(body.position, Vector2(body.size.x, body.size.y - hud_height - 10.0))
		_hud_rect = Rect2(body.position.x, body.position.y + body.size.y - hud_height, body.size.x, hud_height)
	var aspect := 0.98
	var board_size := Vector2(_board_area.size.y * aspect, _board_area.size.y)
	if board_size.x > _board_area.size.x:
		board_size = Vector2(_board_area.size.x, _board_area.size.x / aspect)
	var origin := _board_area.position + (_board_area.size - board_size) * 0.5
	_world_rect = Rect2(origin, board_size)
	_board_card = _world_rect.grow(15.0)


func _gui_input(event: InputEvent) -> void:
	if not interactive or _blocked():
		cancel_inputs()
		return
	if event is InputEventScreenTouch:
		if event.device == InputEvent.DEVICE_ID_EMULATION:
			return
		_last_touch_msec = Time.get_ticks_msec()
		if event.pressed:
			_pointer_down(event.index, event.position)
		else:
			_pointers.erase(event.index)
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		_last_touch_msec = Time.get_ticks_msec()
		if _pointers.has(event.index):
			_pointer_move(event.index, event.position)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if Time.get_ticks_msec() - _last_touch_msec < 500:
			return
		if event.pressed:
			_pointer_down(-1, event.position)
		else:
			_pointers.erase(-1)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _pointers.has(-1):
		if Time.get_ticks_msec() - _last_touch_msec >= 500:
			_pointer_move(-1, event.position)
		get_viewport().set_input_as_handled()


func _pointer_down(identifier: int, position: Vector2) -> void:
	if not _board_card.has_point(position):
		return
	var point := _pixel_to_world(position)
	var seat := _seat_for_world_x(point.x)
	_pointers[identifier] = {"seat": seat, "start": position}
	_move_seat(seat, point.x)
	if _waiting_for_serve():
		action_requested.emit({"type": "serve"})
	if is_instance_valid(fx):
		fx.emit_burst(position, accent, 3, {"speed": 30.0, "life": 0.22, "size": 2.8})


func _pointer_move(identifier: int, position: Vector2) -> void:
	if not _pointers.has(identifier):
		return
	var pointer: Dictionary = _pointers[identifier]
	var start: Vector2 = pointer.get("start", position)
	if start.distance_to(position) < TAP_SLOP and not _board_card.has_point(position):
		return
	var point := _pixel_to_world(position)
	var seat := int(pointer.get("seat", 0))
	_move_seat(seat, point.x)


func _move_seat(seat: int, world_x: float) -> void:
	action_requested.emit({
		"type": "move",
		"seat": seat,
		"x": clampf(world_x, 0.035, 0.965),
	})


func _seat_for_world_x(world_x: float) -> int:
	if engine != null and str(engine.state.get("modeId", "")) == "classic" and world_x >= 0.5:
		return 1
	return 0


func _waiting_for_serve() -> bool:
	if engine == null:
		return false
	var balls_value: Variant = engine.state.get("balls", [])
	return balls_value is Array and balls_value.is_empty() and str(engine.state.get("phase", "")) == "playing"


func _blocked() -> bool:
	if engine == null or str(engine.state.get("phase", "")) != "playing":
		return true
	if game_screen != null and game_screen.is_input_blocked():
		return true
	return TabletopLayout.input_blocked(self)


func _pixel_to_world(point: Vector2) -> Vector2:
	if _world_rect.size.x <= 0.0 or _world_rect.size.y <= 0.0:
		return Vector2(0.5, 0.5)
	return Vector2(
		(point.x - _world_rect.position.x) / _world_rect.size.x,
		(point.y - _world_rect.position.y) / _world_rect.size.y
	)


func _world_to_pixel(point: Vector2) -> Vector2:
	return _world_rect.position + Vector2(point.x * _world_rect.size.x, point.y * _world_rect.size.y)


func _world_scale() -> float:
	return maxf(0.001, minf(_world_rect.size.x, _world_rect.size.y))


func consume_events(events: Array) -> void:
	for raw in events:
		if not raw is Dictionary:
			continue
		var event: Dictionary = raw
		var kind := str(event.get("type", ""))
		var point := _world_to_pixel(Vector2(_number(event.get("x", 0.5)), _number(event.get("y", 0.5))))
		var color := _event_color(event)
		match kind:
			"serve_ready":
				if is_instance_valid(fx):
					fx.ring(point, Color(accent, 0.74), 24.0, 0.46, 3.0)
				AudioFX.play("select")
			"serve", "launch":
				if is_instance_valid(fx):
					fx.emit_burst(point, color, 8, {"speed": 46.0, "life": 0.32, "size": 3.2})
				AudioFX.play("whoosh")
			"bounce":
				if is_instance_valid(fx):
					fx.emit_burst(point, color, 4, {"speed": 40.0, "life": 0.22, "size": 2.2})
				AudioFX.play("tap")
			"paddle":
				if is_instance_valid(fx):
					fx.ring(point, Color("#fff2b5"), 17.0, 0.25, 3.0)
					fx.emit_burst(point, color, 7, {"speed": 46.0, "life": 0.25, "size": 2.4})
					fx.shake(2.2, 0.11)
				AudioFX.play("tap")
			"brick_hit":
				if is_instance_valid(fx):
					fx.emit_burst(point, color, 7, {"speed": 58.0, "life": 0.28, "size": 2.6})
					fx.shake(1.6, 0.09)
				AudioFX.play("drop")
			"brick":
				if is_instance_valid(fx):
					fx.emit_burst(point, color, 14, {"speed": 78.0, "life": 0.48, "size": 3.1, "kind": "star"})
					fx.ring(point, Color(color, 0.68), 23.0, 0.34)
					fx.popup("+%s" % (80 + int(event.get("combo", 0)) * 5), point + Vector2(0, -16), color, 19, 0.58)
					fx.shake(2.8, 0.13)
				AudioFX.play("drop")
			"powerup_drop":
				if is_instance_valid(fx):
					fx.emit_star_trail(point, Color("#f4cf69"), 5)
			"powerup_collect":
				if is_instance_valid(fx):
					fx.ring(point, Color("#fff0ab"), 31.0, 0.44, 4.0)
					fx.emit_burst(point, Color("#f4cf69"), 14, {"speed": 70.0, "life": 0.48, "kind": "star"})
					fx.popup(_powerup_name(str(event.get("kind", ""))), point + Vector2(0, -22), Color("#9a6521"), 20, 0.7)
				AudioFX.play("collect")
			"heart_lost":
				if is_instance_valid(fx):
					fx.emit_burst(point, Color("#e26f62"), 16, {"speed": 78.0, "life": 0.52, "kind": "heart"})
					fx.shake(4.5, 0.24)
				flash_notice("爱心少了一颗，接住下一球。")
				AudioFX.play("wrong")
			"heart_bonus":
				if is_instance_valid(fx):
					fx.emit_burst(point, Color("#e26f62"), 12, {"speed": 62.0, "life": 0.42, "kind": "heart"})
					fx.popup("爱心 +1", point + Vector2(0, -18), Color("#b84c46"), 20, 0.66)
				AudioFX.play("collect")
			"complete":
				if is_instance_valid(fx):
					fx.ring(point, Color("#ffe08a"), 88.0, 0.8, 5.0)
					fx.shake(5.0, 0.32)
					for index in 6:
						var angle := TAU * float(index) / 6.0
						fx.emit_burst(point + Vector2(cos(angle), sin(angle)) * 58.0, Color("#f3d476"), 10, {"speed": 72.0, "life": 0.62, "kind": "star"})
				AudioFX.play("win" if bool(event.get("success", false)) else "wrong")
	queue_redraw()


func _event_color(event: Dictionary) -> Color:
	var value := str(event.get("color", ""))
	return Color(value) if Color.html_is_valid(value) else accent


func _powerup_name(kind: String) -> String:
	match kind:
		"wide":
			return "宽挡板"
		"slow":
			return "慢球"
		"heart":
			return "爱心 +1"
	return "小道具"


func _draw() -> void:
	var shake := fx.get_shake_offset() if is_instance_valid(fx) else Vector2.ZERO
	_draw_backdrop(shake)
	if engine == null or str(engine.state.get("phase", "")) == "empty":
		_draw_empty()
		return
	_draw_board(shake)
	_draw_bricks(shake)
	_draw_powerups(shake)
	_draw_paddles(shake)
	_draw_balls(shake)
	_draw_header()
	_draw_hud()
	_draw_notice()


func _draw_backdrop(shake: Vector2) -> void:
	var full := Rect2(Vector2.ZERO, size)
	draw_style_box(_style(Color("#f9f2e6"), 30, Color(accent, 0.18), 2), full.grow(-2.0))
	var wash := Rect2(12.0, 12.0, size.x - 24.0, size.y - 24.0)
	draw_style_box(_style(Color(soft, 0.58), 24, Color.TRANSPARENT, 0), wash)
	for index in 15:
		var x := fmod(51.0 + float(index) * 131.0, maxf(1.0, size.x))
		var y := 32.0 + fmod(float(index) * 73.0, maxf(1.0, size.y * 0.75))
		draw_circle(Vector2(x, y) + shake * 0.2, 2.0 + float(index % 3), Color(accent, 0.08))


func _draw_empty() -> void:
	var center := size * 0.5
	draw_string(PlaygroundUI.font(), center - Vector2(180, 0), "这一座砖块城堡还没有准备好", HORIZONTAL_ALIGNMENT_CENTER, 360, 24, PlaygroundUI.INK_SOFT)


func _draw_board(shake: Vector2) -> void:
	draw_style_box(_style(Color("#fff9ed"), 32, Color(accent, 0.45), 3), _board_card)
	var inner := _board_card.grow(-9.0)
	draw_style_box(_style(Color("#7c3f20"), 25, Color("#f0cf9f"), 3), inner)
	var field := Rect2(_world_rect.position + shake, _world_rect.size)
	draw_rect(field, Color("#9a512b"))
	var brick_top := _world_to_pixel(Vector2(0.035, 0.055))
	var brick_bottom := _world_to_pixel(Vector2(0.965, 0.965))
	var field_rect := Rect2(brick_top, brick_bottom - brick_top)
	draw_rect(field_rect, Color("#f6e1c5"))
	for index in 22:
		var x := field_rect.position.x + fmod(float(index) * 49.0, maxf(1.0, field_rect.size.x))
		var y := field_rect.position.y + fmod(float(index) * 31.0, maxf(1.0, field_rect.size.y))
		draw_circle(Vector2(x, y), 1.7, Color(accent, 0.13))
	var sky := Rect2(field_rect.position, Vector2(field_rect.size.x, field_rect.size.y * 0.27))
	draw_rect(sky, Color("#f1c99d"))
	for index in 6:
		var notch_x := sky.position.x + float(index) * sky.size.x / 6.0
		draw_rect(Rect2(notch_x + 5.0, sky.position.y + sky.size.y - 13.0, 22.0, 13.0), Color("#8d4826"))
	draw_line(
		_world_to_pixel(Vector2(0.035, 0.965)) + shake,
		_world_to_pixel(Vector2(0.965, 0.965)) + shake,
		Color("#8d4826"),
		maxf(3.0, _world_scale() * 0.008),
		true
	)
	var center := _world_to_pixel(Vector2(0.5, 0.64))
	draw_arc(center, _world_scale() * 0.11, -PI * 0.85, PI * 0.15, 42, Color(accent, 0.10), maxf(2.0, _world_scale() * 0.004), true)


func _draw_bricks(shake: Vector2) -> void:
	var bricks_value: Variant = engine.state.get("bricks", [])
	if not bricks_value is Array:
		return
	for raw in bricks_value:
		if not raw is Dictionary:
			continue
		var brick: Dictionary = raw
		var rect := Rect2(
			_world_to_pixel(Vector2(_number(brick.get("x", 0.0)), _number(brick.get("y", 0.0)))) + shake,
			Vector2(_number(brick.get("w", 0.0)) * _world_rect.size.x, _number(brick.get("h", 0.0)) * _world_rect.size.y)
		)
		var color := _safe_color(str(brick.get("color", "#e7b73c")), accent)
		var radius := clampf(rect.size.y * 0.28, 3.0, 10.0)
		draw_style_box(_style(color.darkened(0.24), radius, Color("#fff0d2"), maxf(1.0, rect.size.y * 0.09)), rect)
		var shine := Rect2(rect.position + Vector2(3.0, 3.0), Vector2(rect.size.x - 6.0, maxf(2.0, rect.size.y * 0.24)))
		draw_rect(shine, Color(1, 1, 1, 0.19))
		var mortar_y := rect.position.y + rect.size.y * 0.5
		draw_line(Vector2(rect.position.x + 4.0, mortar_y), Vector2(rect.end.x - 4.0, mortar_y), Color(0.35, 0.20, 0.12, 0.14), maxf(1.0, rect.size.y * 0.05), true)
		if int(brick.get("hp", 1)) > 1:
			var crack := PackedVector2Array([
				rect.position + Vector2(rect.size.x * 0.38, rect.size.y * 0.14),
				rect.position + Vector2(rect.size.x * 0.47, rect.size.y * 0.43),
				rect.position + Vector2(rect.size.x * 0.35, rect.size.y * 0.58),
				rect.position + Vector2(rect.size.x * 0.50, rect.size.y * 0.82),
			])
			draw_polyline(crack, Color(0.38, 0.19, 0.10, 0.48), maxf(1.0, rect.size.y * 0.07), true)


func _draw_powerups(shake: Vector2) -> void:
	var powerups_value: Variant = engine.state.get("powerups", [])
	if not powerups_value is Array:
		return
	for raw in powerups_value:
		if not raw is Dictionary:
			continue
		var powerup: Dictionary = raw
		var center := _world_to_pixel(Vector2(_number(powerup.get("x", 0.5)), _number(powerup.get("y", 0.5)))) + shake
		var radius := clampf(_world_scale() * 0.019, 10.0, 22.0)
		var color := _powerup_color(str(powerup.get("kind", "")))
		draw_circle(center + Vector2(0, 3.0), radius + 2.0, Color(0.20, 0.15, 0.10, 0.16))
		draw_circle(center, radius, color)
		draw_circle(center + Vector2(-radius * 0.28, -radius * 0.35), radius * 0.33, Color(1, 1, 1, 0.30))
		_draw_powerup_symbol(center, radius, str(powerup.get("kind", "")), Color("#fff8df"))


func _draw_powerup_symbol(center: Vector2, radius: float, kind: String, color: Color) -> void:
	match kind:
		"wide":
			draw_line(center - Vector2(radius * 0.52, 0), center + Vector2(radius * 0.52, 0), color, maxf(3.0, radius * 0.16), true)
			draw_circle(center - Vector2(radius * 0.55, 0), radius * 0.12, color)
			draw_circle(center + Vector2(radius * 0.55, 0), radius * 0.12, color)
		"slow":
			for index in 3:
				var angle := PI * float(index) / 3.0
				var arm := Vector2(cos(angle), sin(angle)) * radius * 0.55
				draw_line(center - arm, center + arm, color, maxf(2.0, radius * 0.10), true)
			draw_circle(center, radius * 0.12, color)
		"heart":
			_draw_heart(center, radius * 0.50, color)
		_:
			draw_circle(center, radius * 0.20, color)


func _draw_paddles(shake: Vector2) -> void:
	var paddles_value: Variant = engine.state.get("paddles", [])
	if not paddles_value is Array:
		return
	for raw in paddles_value:
		if not raw is Dictionary:
			continue
		var paddle: Dictionary = raw
		var width := _number(paddle.get("width", 0.15))
		var x := _number(paddle.get("x", 0.5))
		var rect := Rect2(
			_world_to_pixel(Vector2(x - width * 0.5, 0.905 - 0.013)) + shake,
			Vector2(width * _world_rect.size.x, 0.026 * _world_rect.size.y)
		)
		var seat := int(paddle.get("seat", 0))
		var tint := _seat_color(seat)
		draw_style_box(_style(tint.darkened(0.28), rect.size.y * 0.48, Color("#fff2cc"), maxf(2.0, rect.size.y * 0.10)), Rect2(rect.position + Vector2(0, 4.0), rect.size))
		draw_style_box(_style(tint, rect.size.y * 0.48, Color("#fff7e5"), maxf(1.5, rect.size.y * 0.08)), rect)
		var shine := Rect2(rect.position + Vector2(6.0, 3.0), Vector2(maxf(4.0, rect.size.x - 12.0), maxf(2.0, rect.size.y * 0.20)))
		draw_rect(shine, Color(1, 1, 1, 0.26))
		var center_x := rect.position.x + rect.size.x * 0.5
		draw_circle(Vector2(center_x, rect.position.y + rect.size.y * 0.5), maxf(2.0, rect.size.y * 0.17), Color("#fff8e7"))
		draw_circle(Vector2(center_x, rect.position.y + rect.size.y * 0.5), maxf(1.0, rect.size.y * 0.08), tint.darkened(0.25))


func _draw_balls(shake: Vector2) -> void:
	var balls_value: Variant = engine.state.get("balls", [])
	if not balls_value is Array:
		return
	for raw in balls_value:
		if not raw is Dictionary:
			continue
		var ball: Dictionary = raw
		var center := _world_to_pixel(Vector2(_number(ball.get("x", 0.5)), _number(ball.get("y", 0.9)))) + shake
		var radius := maxf(5.0, _number(ball.get("radius", 0.017)) * _world_scale())
		draw_circle(center + Vector2(0, radius * 0.55), radius * 0.95, Color(0.24, 0.13, 0.08, 0.18))
		draw_circle(center, radius, Color("#fff5cd"))
		draw_circle(center, radius * 0.78, Color("#efbd54"))
		draw_circle(center + Vector2(-radius * 0.28, -radius * 0.32), radius * 0.28, Color(1, 1, 1, 0.65))
		if engine != null and float(engine.state.get("slowTimer", 0.0)) > 0.0:
			draw_arc(center, radius + 4.0, 0.0, TAU, 24, Color("#72a8d3"), 1.6, true)


func _draw_header() -> void:
	var font := PlaygroundUI.font()
	var title := str(engine.state.get("levelTitle", "砖块小城堡"))
	var band := _band_label(str(engine.state.get("levelBand", "easy")))
	draw_string(font, Vector2(18.0, 37.0), title, HORIZONTAL_ALIGNMENT_LEFT, size.x - 300.0, 25, PlaygroundUI.INK)
	var label_width := font.get_string_size(band, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
	var band_rect := Rect2(size.x - label_width - 28.0, 15.0, label_width + 16.0, 28.0)
	draw_style_box(_style(Color(accent, 0.12), 14, Color(accent, 0.22), 1), band_rect)
	draw_string(font, Vector2(band_rect.position.x + 8.0, 34.0), band, HORIZONTAL_ALIGNMENT_LEFT, band_rect.size.x - 16.0, 15, accent)


func _draw_hud() -> void:
	if _hud_rect.size.x < 20.0 or _hud_rect.size.y < 20.0:
		return
	draw_style_box(_style(Color("#fff8e9"), 24, Color(accent, 0.26), 2, 7, Color(0.16, 0.08, 0.03, 0.12)), _hud_rect)
	var inner := _hud_rect.grow(-16.0)
	var font := PlaygroundUI.font()
	var title_size := 19
	draw_string(font, inner.position + Vector2(0, 24), "城堡进度", HORIZONTAL_ALIGNMENT_LEFT, inner.size.x, title_size, PlaygroundUI.INK)
	var broken := int(engine.state.get("bricksBroken", 0))
	var total := maxi(1, int(engine.state.get("bricksTotal", 0)))
	var ratio := clampf(float(broken) / float(total), 0.0, 1.0)
	var bar := Rect2(inner.position + Vector2(0, 38), Vector2(inner.size.x, 16))
	draw_style_box(_style(Color("#ecd6bf"), 8, Color.TRANSPARENT, 0), bar)
	draw_style_box(_style(accent, 8, Color.TRANSPARENT, 0), Rect2(bar.position, Vector2(bar.size.x * ratio, bar.size.y)))
	draw_string(font, bar.position + Vector2(0, 33), "%s / %s 块" % [broken, total], HORIZONTAL_ALIGNMENT_LEFT, inner.size.x, 15, PlaygroundUI.INK_SOFT)
	var score_y := bar.position.y + 56.0
	draw_string(font, Vector2(inner.position.x, score_y), "分数", HORIZONTAL_ALIGNMENT_LEFT, inner.size.x, 15, PlaygroundUI.INK_SOFT)
	draw_string(font, Vector2(inner.position.x, score_y + 30.0), str(int(engine.state.get("score", 0))), HORIZONTAL_ALIGNMENT_LEFT, inner.size.x, 29, accent)
	var lives := int(engine.state.get("lives", 0))
	var heart_y := score_y + 58.0
	draw_string(font, Vector2(inner.position.x, heart_y), "爱心", HORIZONTAL_ALIGNMENT_LEFT, inner.size.x, 15, PlaygroundUI.INK_SOFT)
	var heart_size := minf(24.0, inner.size.x / 7.0)
	for index in lives:
		var center := Vector2(inner.position.x + 12.0 + float(index) * (heart_size + 5.0), heart_y + 30.0)
		if center.x + heart_size > inner.end.x:
			break
		_draw_heart(center, heart_size, Color("#e26f62"))
	if str(engine.state.get("modeId", "")) == "classic":
		var seat_y := heart_y + 69.0
		draw_string(font, Vector2(inner.position.x, seat_y), "双人守台", HORIZONTAL_ALIGNMENT_LEFT, inner.size.x, 15, PlaygroundUI.INK_SOFT)
		for seat in 2:
			var row_y := seat_y + 28.0 + float(seat) * 34.0
			draw_circle(Vector2(inner.position.x + 10.0, row_y - 5.0), 7.0, _seat_color(seat))
			var player_name := "左边小朋友" if seat == 0 else "右边小朋友"
			if seat < players.size():
				player_name = str(players[seat].get("name", player_name))
			draw_string(font, Vector2(inner.position.x + 24.0, row_y), player_name, HORIZONTAL_ALIGNMENT_LEFT, inner.size.x - 24.0, 15, PlaygroundUI.INK)
	var serve_timer := float(engine.state.get("serveTimer", 0.0))
	var message := "拖动挡板接球"
	if _waiting_for_serve():
		message = "轻点发球" if serve_timer <= 0.01 else "准备发球 %.1f" % serve_timer
	var hint_rect := Rect2(inner.position.x, inner.end.y - 42.0, inner.size.x, 32.0)
	draw_style_box(_style(Color(soft, 0.72), 13, Color(accent, 0.20), 1), hint_rect)
	draw_string(font, hint_rect.position + Vector2(8.0, 21.0), message, HORIZONTAL_ALIGNMENT_CENTER, hint_rect.size.x - 16.0, 15, accent)


func _draw_notice() -> void:
	if _notice_time <= 0.0 or _notice.is_empty():
		return
	var font := PlaygroundUI.font()
	var width := clampf(font.get_string_size(_notice, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x + 38.0, 190.0, size.x - 60.0)
	var rect := Rect2((size.x - width) * 0.5, size.y - 72.0, width, 42.0)
	draw_style_box(_style(Color(0.20, 0.12, 0.08, 0.92), 18, Color(1, 1, 1, 0.18), 1), rect)
	draw_string(font, rect.position + Vector2(0, 28.0), _notice, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 17, Color("#fff1cf"))


func _draw_heart(center: Vector2, size_value: float, color: Color) -> void:
	var radius := size_value * 0.28
	var points := PackedVector2Array([
		center + Vector2(0, size_value * 0.42),
		center + Vector2(-size_value * 0.50, -size_value * 0.05),
		center + Vector2(-size_value * 0.37, -size_value * 0.34),
		center + Vector2(-size_value * 0.12, -size_value * 0.33),
		center + Vector2(0, -size_value * 0.13),
		center + Vector2(size_value * 0.12, -size_value * 0.33),
		center + Vector2(size_value * 0.37, -size_value * 0.34),
		center + Vector2(size_value * 0.50, -size_value * 0.05),
	])
	draw_colored_polygon(points, color)
	draw_circle(center + Vector2(-size_value * 0.18, -size_value * 0.19), radius, color)
	draw_circle(center + Vector2(size_value * 0.18, -size_value * 0.19), radius, color)
	draw_circle(center + Vector2(-size_value * 0.16, -size_value * 0.24), radius * 0.35, Color(1, 1, 1, 0.35))


func _band_label(band: String) -> String:
	match band:
		"easy":
			return "轻松砖堡"
		"normal":
			return "标准砖堡"
		"challenge":
			return "挑战砖堡"
	return "砖块城堡"


func _seat_color(seat: int) -> Color:
	var tint := Color("#d56c29") if seat == 0 else Color("#2878c8")
	if seat < players.size():
		var profile_color := str(players[seat].get("color", ""))
		if Color.html_is_valid(profile_color):
			tint = Color(profile_color)
	return tint


func _powerup_color(kind: String) -> Color:
	match kind:
		"heart":
			return Color("#e26f62")
		"slow":
			return Color("#5b9bd8")
		"wide":
			return Color("#e7b73c")
	return accent


func _style(color: Color, radius: int, border: Color, border_width: int, shadow: int = 0, shadow_color: Color = Color.TRANSPARENT) -> StyleBoxFlat:
	var key := "%s|%s|%s|%s|%s|%s" % [color.to_html(), radius, border.to_html(), border_width, shadow, shadow_color.to_html()]
	if _style_cache.has(key):
		return _style_cache[key]
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.corner_radius_top_left = radius
	box.corner_radius_top_right = radius
	box.corner_radius_bottom_left = radius
	box.corner_radius_bottom_right = radius
	box.border_color = border
	box.border_width_left = border_width
	box.border_width_top = border_width
	box.border_width_right = border_width
	box.border_width_bottom = border_width
	if shadow > 0:
		box.shadow_size = shadow
		box.shadow_color = shadow_color
		box.shadow_offset = Vector2(0, 4)
	_style_cache[key] = box
	return box


func _safe_color(value: String, fallback: Color) -> Color:
	return Color(value) if Color.html_is_valid(value) else fallback


func _number(value: Variant) -> float:
	return float(value) if value is int or value is float else 0.0
