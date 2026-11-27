class_name AirHockeyField
extends Control

signal action_requested(action: Dictionary)

const NOTICE_SECONDS := 2.0
const TRAIL_STEPS := 4

var engine: AirHockeyRules
var game_screen: NativeGameScreen
var players: Array = []
var accent := Color("#3f628f")
var soft := Color("#e4ecf5")
var interactive := true

var fx: ArcadeFxLayer
var _hud_rect := Rect2()
var _board_area := Rect2()
var _rink_rect := Rect2()
var _clock := 0.0
var _notice := ""
var _notice_time := 0.0
var _pointers: Dictionary = {}
var _last_touch_msec := -1000
var _style_cache: Dictionary = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_DRAG
	focus_mode = Control.FOCUS_ALL
	fx = ArcadeFxLayer.new()
	fx.set_palette(accent, soft)
	fx.gravity = 24.0
	add_child(fx)
	resized.connect(_layout)
	_layout()
	queue_redraw()


func bind(value: AirHockeyRules, screen: NativeGameScreen, seat_players: Array) -> void:
	engine = value
	game_screen = screen
	players = seat_players.duplicate(true)
	if engine != null and engine.state.has("level"):
		accent = _safe_color(str(engine.state.level.get("accent", "#3f628f")), accent)
	soft = PlaygroundUI.mix(accent, Color.WHITE, 0.84)
	if is_instance_valid(fx):
		fx.set_palette(accent, soft)
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
	elif what in [NOTIFICATION_FOCUS_EXIT, NOTIFICATION_APPLICATION_FOCUS_OUT]:
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
	var hud_height := clampf(size.y * 0.082, 62.0, 88.0)
	_hud_rect = Rect2(margin, margin, maxf(1.0, size.x - margin * 2.0), hud_height)
	_board_area = Rect2(
		margin,
		margin + hud_height + 10.0,
		maxf(1.0, size.x - margin * 2.0),
		maxf(1.0, size.y - hud_height - margin * 3.0 - 10.0)
	)
	var preferred_aspect := AirHockeyRules.PLAY_ASPECT
	var board_width := minf(_board_area.size.x, _board_area.size.y * preferred_aspect)
	var board_height := board_width / preferred_aspect
	if board_height > _board_area.size.y:
		board_height = _board_area.size.y
		board_width = board_height * preferred_aspect
	board_width = maxf(320.0, board_width)
	board_height = maxf(200.0, board_height)
	_rink_rect = Rect2(
		_board_area.position + (_board_area.size - Vector2(board_width, board_height)) * 0.5,
		Vector2(board_width, board_height)
	)


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
			_begin_pointer(event.index, event.position)
		else:
			_finish_pointer(event.index)
	elif event is InputEventScreenDrag:
		_last_touch_msec = Time.get_ticks_msec()
		_update_pointer(event.index, event.position)
		accept_event()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if Time.get_ticks_msec() - _last_touch_msec < 500:
			return
		accept_event()
		if event.pressed:
			_begin_pointer(-1, event.position)
		else:
			_finish_pointer(-1)
	elif event is InputEventMouseMotion and _pointers.has(-1):
		if Time.get_ticks_msec() - _last_touch_msec >= 500:
			_update_pointer(-1, event.position)
			accept_event()


func _begin_pointer(identifier: int, position: Vector2) -> void:
	if not _rink_rect.grow(18.0).has_point(position):
		return
	var world := _pixel_to_world(position)
	var seat := 0
	if str(engine.state.get("modeId", "")) == "classic" and world.x >= 0.5:
		seat = 1
	if _find_paddle(seat).is_empty():
		return
	_pointers[identifier] = {"seat": seat, "last": world}
	_emit_drag(seat, world)
	if is_instance_valid(fx):
		fx.ring(_world_to_pixel(world), Color(_seat_color(seat), 0.62), 16.0, 0.28, 2.0)
	AudioFX.play("select")


func _update_pointer(identifier: int, position: Vector2) -> void:
	if not _pointers.has(identifier):
		return
	var world := _pixel_to_world(position)
	var pointer: Dictionary = _pointers[identifier]
	var last: Vector2 = pointer.get("last", world)
	if last.distance_to(world) < 0.002:
		return
	pointer.last = world
	_pointers[identifier] = pointer
	_emit_drag(int(pointer.get("seat", 0)), world)


func _finish_pointer(identifier: int) -> void:
	if not _pointers.has(identifier):
		return
	var pointer: Dictionary = _pointers[identifier]
	_pointers.erase(identifier)
	action_requested.emit({"type": "drag_end", "seat": int(pointer.get("seat", 0))})


func _emit_drag(seat: int, world: Vector2) -> void:
	action_requested.emit({
		"type": "drag",
		"seat": seat,
		"x": clampf(world.x, 0.0, 1.0),
		"y": clampf(world.y, 0.0, 1.0),
	})


func _blocked() -> bool:
	if engine == null or str(engine.state.get("phase", "")) != "playing":
		return true
	if game_screen != null and game_screen.is_input_blocked():
		return true
	return TabletopLayout.input_blocked(self)


func _find_paddle(seat: int) -> Dictionary:
	var paddles_value: Variant = engine.state.get("paddles", []) if engine != null else []
	if paddles_value is Array:
		for raw in paddles_value:
			if raw is Dictionary and int(raw.get("seat", -1)) == seat:
				return raw
	return {}


func _seat_color(seat: int) -> Color:
	if seat >= 0 and seat < players.size() and players[seat] is Dictionary:
		return _safe_color(str(players[seat].get("color", "#f1c95f")), Color("#f1c95f"))
	return Color("#f1c95f") if seat == 0 else Color("#e78070")


func consume_events(events: Array) -> void:
	if engine == null:
		return
	for raw in events:
		if not raw is Dictionary:
			continue
		var event: Dictionary = raw
		var point := _world_to_pixel(Vector2(float(event.get("x", 0.5)), float(event.get("y", 0.5))))
		match str(event.get("type", "")):
			"serve_ready":
				AudioFX.play("tap")
			"serve":
				AudioFX.play("whoosh")
				if is_instance_valid(fx):
					fx.ring(point, Color(accent, 0.72), 24.0, 0.34, 2.0)
					fx.emit_burst(point, Color("#e9f6fa"), 8, {"speed": 48.0, "life": 0.3, "size": 3.0})
			"wall":
				if is_instance_valid(fx):
					fx.emit_burst(point, Color("#bde5f2"), 5, {"speed": 34.0, "life": 0.2, "size": 2.4})
				AudioFX.play("tap")
			"paddle":
				if is_instance_valid(fx):
					fx.ring(point, Color(_seat_color(int(event.get("seat", 0))), 0.7), 18.0, 0.25, 2.0)
					fx.emit_burst(point, _seat_color(int(event.get("seat", 0))), 7, {"speed": 45.0, "life": 0.24, "size": 3.0})
				AudioFX.play("tap")
			"target":
				AudioFX.play("pair")
				if is_instance_valid(fx):
					fx.ring(point, Color("#f4d36d"), 28.0, 0.45, 3.0)
					fx.emit_burst(point, Color("#f4d36d"), 16, {"speed": 74.0, "life": 0.48, "size": 3.2, "kind": "star"})
					fx.popup("+1 目标", point + Vector2(0.0, -18.0), Color("#9a7424"), 20, 0.7)
					fx.shake(2.2, 0.14)
			"goal":
				AudioFX.play("confirm")
				if is_instance_valid(fx):
					fx.ring(point, Color("#f4d36d"), 34.0, 0.5, 4.0)
					fx.emit_burst(point, Color("#f4d36d"), 20, {"speed": 82.0, "life": 0.52, "size": 3.4, "kind": "star"})
					fx.popup("进球！", point + Vector2(0.0, -22.0), Color("#8b6421"), 22, 0.78)
					fx.shake(4.0, 0.22)
			"escape":
				flash_notice("冰球从边线溜走了，已放回中间。")
				AudioFX.play("wrong")
			"complete":
				if is_instance_valid(fx):
					fx.ring(point, Color("#f4d36d"), 54.0, 0.8, 5.0)
					for index in 6:
						var angle := TAU * float(index) / 6.0
						fx.emit_burst(
							point + Vector2(cos(angle), sin(angle)) * 30.0,
							Color("#f4d36d"),
							10,
							{"speed": 64.0, "life": 0.58, "size": 3.4, "kind": "star"}
						)
					fx.shake(5.0, 0.26)
				AudioFX.play("win" if bool(event.get("success", false)) else "wrong")
	queue_redraw()


func _draw() -> void:
	var shake := fx.get_shake_offset() if is_instance_valid(fx) else Vector2.ZERO
	_draw_backdrop(shake)
	if engine == null or str(engine.state.get("phase", "")) == "empty":
		_draw_empty()
		return
	_draw_table(shake)
	_draw_targets(shake)
	_draw_paddles(shake)
	_draw_puck(shake)
	_draw_hud()
	_draw_notice()


func _draw_backdrop(shake: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("#faf7ee"))
	var wash := Rect2(10.0, 10.0, size.x - 20.0, size.y - 20.0)
	draw_style_box(_style(Color(soft, 0.55), 28, Color(accent, 0.22), 2), wash)
	for index in 18:
		var x := fmod(35.0 + float(index) * 113.0, maxf(1.0, size.x - 40.0))
		var y := 27.0 + fmod(float(index) * 73.0, maxf(1.0, size.y - 60.0))
		draw_circle(Vector2(x, y) + shake * 0.2, 1.8 + float(index % 3), Color(accent, 0.08))


func _draw_empty() -> void:
	var font := PlaygroundUI.font()
	draw_string(font, Vector2(size.x * 0.5 - 150.0, size.y * 0.5), "这一张冰球台还没有准备好", HORIZONTAL_ALIGNMENT_CENTER, 300.0, 24, PlaygroundUI.INK_SOFT)


func _draw_table(shake: Vector2) -> void:
	var card := Rect2(_rink_rect.position - Vector2(10.0, 10.0) + shake, _rink_rect.size + Vector2(20.0, 20.0))
	draw_style_box(_style(Color("#fffaf0"), 30, Color(accent, 0.58), 3, 8, Color(0.05, 0.08, 0.12, 0.13)), card)
	var surface := Rect2(_rink_rect.position + shake, _rink_rect.size)
	draw_style_box(_style(Color("#d9edf7"), 24, Color("#f7ffff"), 4), surface)
	var bands := 16
	for index in bands:
		var amount := float(index) / float(bands - 1)
		var row := Rect2(
			surface.position.x + 4.0,
			surface.position.y + 4.0 + amount * (surface.size.y - 8.0),
			surface.size.x - 8.0,
			maxf(1.0, (surface.size.y - 8.0) / float(bands) + 1.0)
		)
		draw_rect(row, Color("#e7f5fb").lerp(Color("#bfdbe9"), amount * 0.72))
	var center := _world_to_pixel(Vector2(0.5, 0.5)) + shake
	draw_line(_world_to_pixel(Vector2(0.5, 0.11)) + shake, _world_to_pixel(Vector2(0.5, 0.89)) + shake, Color(accent, 0.26), 2.0)
	draw_arc(center, minf(_rink_rect.size.x, _rink_rect.size.y) * 0.105, 0.0, TAU, 56, Color(accent, 0.27), 2.0, true)
	draw_arc(center, minf(_rink_rect.size.x, _rink_rect.size.y) * 0.018, 0.0, TAU, 24, Color(accent, 0.24), 2.0, true)
	_draw_rink_walls(shake)
	_draw_goals(shake)


func _draw_rink_walls(shake: Vector2) -> void:
	var wall_color := Color("#466377")
	var width := maxf(5.0, _rink_rect.size.y * 0.014)
	var top_left := _world_to_pixel(Vector2(AirHockeyRules.LEFT, AirHockeyRules.TOP)) + shake
	var top_right := _world_to_pixel(Vector2(AirHockeyRules.RIGHT, AirHockeyRules.TOP)) + shake
	var bottom_left := _world_to_pixel(Vector2(AirHockeyRules.LEFT, AirHockeyRules.BOTTOM)) + shake
	var bottom_right := _world_to_pixel(Vector2(AirHockeyRules.RIGHT, AirHockeyRules.BOTTOM)) + shake
	draw_line(top_left, top_right, wall_color, width, true)
	draw_line(bottom_left, bottom_right, wall_color, width, true)
	if str(engine.state.get("modeId", "")) == "classic":
		var goal_height := float(engine.state.level.get("goalHeight", 0.24))
		var goal_top := 0.5 - goal_height * 0.5
		var goal_bottom := 0.5 + goal_height * 0.5
		draw_line(
			_world_to_pixel(Vector2(AirHockeyRules.LEFT, AirHockeyRules.TOP)) + shake,
			_world_to_pixel(Vector2(AirHockeyRules.LEFT, goal_top)) + shake,
			wall_color, width, true
		)
		draw_line(
			_world_to_pixel(Vector2(AirHockeyRules.LEFT, goal_bottom)) + shake,
			_world_to_pixel(Vector2(AirHockeyRules.LEFT, AirHockeyRules.BOTTOM)) + shake,
			wall_color, width, true
		)
		draw_line(
			_world_to_pixel(Vector2(AirHockeyRules.RIGHT, AirHockeyRules.TOP)) + shake,
			_world_to_pixel(Vector2(AirHockeyRules.RIGHT, goal_top)) + shake,
			wall_color, width, true
		)
		draw_line(
			_world_to_pixel(Vector2(AirHockeyRules.RIGHT, goal_bottom)) + shake,
			_world_to_pixel(Vector2(AirHockeyRules.RIGHT, AirHockeyRules.BOTTOM)) + shake,
			wall_color, width, true
		)
	else:
		draw_line(top_left, bottom_left, wall_color, width, true)
		draw_line(top_right, bottom_right, wall_color, width, true)


func _draw_goals(shake: Vector2) -> void:
	if str(engine.state.get("modeId", "")) != "classic":
		return
	var goal_height := float(engine.state.level.get("goalHeight", 0.24))
	var half := goal_height * 0.5
	for side in 2:
		var x := AirHockeyRules.LEFT if side == 0 else AirHockeyRules.RIGHT
		var outer_x := x - 0.045 if side == 0 else x + 0.045
		var top := _world_to_pixel(Vector2(outer_x, 0.5 - half)) + shake
		var bottom := _world_to_pixel(Vector2(outer_x, 0.5 + half)) + shake
		var mouth_top := _world_to_pixel(Vector2(x, 0.5 - half)) + shake
		var mouth_bottom := _world_to_pixel(Vector2(x, 0.5 + half)) + shake
		var color := _seat_color(side)
		var rect_pos := Vector2(minf(outer_x, x), 0.5 - half)
		var px_rect := Rect2(_world_to_pixel(rect_pos) + shake, Vector2(absf(x - outer_x), goal_height) * _rink_rect.size)
		draw_rect(px_rect, Color(color, 0.28))
		var post_radius := maxf(5.0, _rink_rect.size.y * 0.012)
		draw_circle(mouth_top, post_radius, color)
		draw_circle(mouth_bottom, post_radius, color)
		draw_string(
			PlaygroundUI.font(),
			Vector2((top.x + bottom.x) * 0.5 - 36.0, (top.y + bottom.y) * 0.5 + 5.0),
			"球门",
			HORIZONTAL_ALIGNMENT_CENTER,
			72.0,
			14,
			Color("#38505e")
		)


func _draw_targets(shake: Vector2) -> void:
	if str(engine.state.get("modeId", "")) != "practice":
		return
	var targets_value: Variant = engine.state.get("targets", [])
	if not targets_value is Array:
		return
	for index in targets_value.size():
		if not targets_value[index] is Dictionary:
			continue
		var target: Dictionary = targets_value[index]
		var center := _world_to_pixel(Vector2(float(target.get("x", 0.5)), float(target.get("y", 0.5)))) + shake
		var radius := float(target.get("radius", 0.06)) * _rink_rect.size.y
		var lit := bool(target.get("lit", false))
		var pulse := 0.5 + 0.5 * sin(_clock * 3.2 + float(index) * 0.9)
		var ring_color := Color("#f0cf68") if lit else Color(accent, 0.42 + pulse * 0.18)
		draw_circle(center, radius + 8.0, Color(ring_color, 0.12 if lit else 0.07))
		draw_arc(center, radius, 0.0, TAU, 44, ring_color, maxf(3.0, radius * 0.12), true)
		draw_arc(center, radius * 0.66, 0.0, TAU, 32, Color(ring_color, 0.52), maxf(1.5, radius * 0.05), true)
		_draw_star(center, radius * 0.35, Color("#f5d979") if lit else Color(accent, 0.74), _clock * 0.25 + float(index))
		if not lit:
			draw_string(
				PlaygroundUI.font(),
				center + Vector2(-30.0, radius + 23.0),
				str(target.get("label", "星门")),
				HORIZONTAL_ALIGNMENT_CENTER,
				60.0,
				12,
				Color("#4b6876")
			)


func _draw_paddles(shake: Vector2) -> void:
	var paddles_value: Variant = engine.state.get("paddles", [])
	if not paddles_value is Array:
		return
	for raw in paddles_value:
		if not raw is Dictionary:
			continue
		var paddle: Dictionary = raw
		var center := _world_to_pixel(Vector2(float(paddle.get("x", 0.5)), float(paddle.get("y", 0.5)))) + shake
		var radius := float(paddle.get("radius", 0.055)) * _rink_rect.size.y
		var seat := int(paddle.get("seat", 0))
		var color := _seat_color(seat)
		draw_circle(center + Vector2(0.0, 5.0), radius * 1.08, Color(0.05, 0.09, 0.13, 0.14))
		draw_circle(center, radius, color)
		draw_arc(center, radius, 0.0, TAU, 42, Color("#fff9e7"), maxf(3.0, radius * 0.13), true)
		draw_circle(center, radius * 0.52, PlaygroundUI.mix(color, Color.WHITE, 0.2))
		draw_circle(center, radius * 0.22, Color("#fff9e7"))
		draw_circle(center - Vector2(radius * 0.26, radius * 0.3), radius * 0.11, Color(1, 1, 1, 0.48))


func _draw_puck(shake: Vector2) -> void:
	var puck_value: Variant = engine.state.get("puck", {})
	if not puck_value is Dictionary or puck_value.is_empty():
		var ready := _world_to_pixel(Vector2(0.5, 0.5)) + shake
		var ready_radius := puck_radius_pixels()
		draw_circle(ready, ready_radius, Color(0.13, 0.20, 0.26, 0.28))
		draw_arc(ready, ready_radius + 5.0, 0.0, TAU, 26, Color(accent, 0.34), 2.0, true)
		draw_string(
			PlaygroundUI.font(),
			ready + Vector2(-54.0, ready_radius + 27.0),
			"发球准备",
			HORIZONTAL_ALIGNMENT_CENTER,
			108.0,
			14,
			Color("#486470")
		)
		return
	var puck: Dictionary = puck_value
	var center := _world_to_pixel(Vector2(float(puck.get("x", 0.5)), float(puck.get("y", 0.5)))) + shake
	var velocity := Vector2(
		float(puck.get("vx", 0.0)) * AirHockeyRules.PLAY_ASPECT,
		float(puck.get("vy", 0.0))
	)
	var direction := velocity.normalized() if velocity.length_squared() > 0.000001 else Vector2.LEFT
	for index in range(TRAIL_STEPS, 0, -1):
		var ghost := center - direction * float(index) * 9.0
		draw_circle(ghost, puck_radius_pixels() * 0.54, Color(0.10, 0.18, 0.22, 0.05))
	var radius := puck_radius_pixels()
	draw_circle(center + Vector2(0.0, 4.0), radius * 1.08, Color(0.03, 0.06, 0.08, 0.2))
	draw_circle(center, radius, Color("#27343b"))
	draw_arc(center, radius, 0.0, TAU, 34, Color("#9ebec9"), maxf(2.0, radius * 0.16), true)
	draw_circle(center - Vector2(radius * 0.25, radius * 0.28), radius * 0.18, Color(1, 1, 1, 0.34))


func puck_radius_pixels() -> float:
	return maxf(8.0, AirHockeyRules.PUCK_RADIUS * _rink_rect.size.y)


func _draw_hud() -> void:
	var card := _hud_rect
	draw_style_box(_style(Color("#fffdf7"), 22, Color(accent, 0.34), 2, 5, Color(0.08, 0.1, 0.12, 0.1)), card)
	var padding := 18.0
	var title := str(engine.state.get("levelTitle", "冰球碰碰台"))
	draw_string(
		PlaygroundUI.font(),
		Vector2(card.position.x + padding, card.position.y + card.size.y * 0.62),
		title,
		HORIZONTAL_ALIGNMENT_LEFT,
		maxf(160.0, card.size.x * 0.30),
		22,
		PlaygroundUI.INK
	)
	var score := "0 : 0"
	var mode := str(engine.state.get("modeId", "practice"))
	if mode == "classic":
		var scores: Array = engine.state.get("scores", [0, 0])
		var left_name := _player_name(0, "左边")
		var right_name := _player_name(1, "右边")
		score = "%s  %s : %s  %s" % [left_name, int(scores[0]), int(scores[1]), right_name]
	else:
		score = "目标  %s / %s" % [int(engine.state.get("targetsHit", 0)), int(engine.state.get("targetTotal", 0))]
	draw_string(
		PlaygroundUI.font(),
		Vector2(card.position.x + card.size.x * 0.33, card.position.y + card.size.y * 0.62),
		score,
		HORIZONTAL_ALIGNMENT_CENTER,
		card.size.x * 0.43,
		23,
		accent
	)
	var seconds := int(ceil(float(engine.state.get("timeLeft", 0.0))))
	var timer_color := Color("#a84f39") if seconds <= 10 else PlaygroundUI.INK_SOFT
	draw_string(
		PlaygroundUI.font(),
		Vector2(card.position.x + card.size.x - 150.0, card.position.y + card.size.y * 0.62),
		"%s 秒" % maxi(0, seconds),
		HORIZONTAL_ALIGNMENT_RIGHT,
		132.0,
		24,
		timer_color
	)


func _draw_notice() -> void:
	if _notice_time <= 0.0 or _notice.is_empty():
		return
	var font := PlaygroundUI.font()
	var text_size := font.get_string_size(_notice, HORIZONTAL_ALIGNMENT_LEFT, -1, 18)
	var rect := Rect2(
		Vector2((size.x - text_size.x) * 0.5 - 18.0, _hud_rect.position.y + _hud_rect.size.y + 5.0),
		Vector2(text_size.x + 36.0, 34.0)
	)
	draw_style_box(_style(Color(accent, 0.92), 14, Color(accent, 0.4), 1, 3, Color(0, 0, 0, 0.1)), rect)
	draw_string(font, rect.position + Vector2(18.0, 23.0), _notice, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 36.0, 18, Color.WHITE)


func _draw_star(center: Vector2, radius: float, color: Color, rotation: float) -> void:
	var points := PackedVector2Array()
	for index in 10:
		var angle := -PI * 0.5 + rotation + float(index) * PI / 5.0
		var length := radius if index % 2 == 0 else radius * 0.46
		points.append(center + Vector2(cos(angle), sin(angle)) * length)
	draw_colored_polygon(points, color)


func _world_to_pixel(world: Vector2) -> Vector2:
	return _rink_rect.position + Vector2(
		clampf(world.x, 0.0, 1.0) * _rink_rect.size.x,
		clampf(world.y, 0.0, 1.0) * _rink_rect.size.y
	)


func _pixel_to_world(point: Vector2) -> Vector2:
	return Vector2(
		clampf((point.x - _rink_rect.position.x) / maxf(1.0, _rink_rect.size.x), 0.0, 1.0),
		clampf((point.y - _rink_rect.position.y) / maxf(1.0, _rink_rect.size.y), 0.0, 1.0)
	)


func _player_name(seat: int, fallback: String) -> String:
	if seat < players.size() and players[seat] is Dictionary:
		return str(players[seat].get("name", fallback))
	return fallback


func _style(
	background: Color,
	radius: int,
	border_color: Color = Color.TRANSPARENT,
	border_width: int = 0,
	shadow_size: int = 0,
	shadow_color: Color = Color.TRANSPARENT
) -> StyleBoxFlat:
	var key := "%s:%s:%s:%s:%s:%s" % [background.to_html(), radius, border_color.to_html(), border_width, shadow_size, shadow_color.to_html()]
	if not _style_cache.has(key):
		_style_cache[key] = PlaygroundUI.style(background, radius, border_color, border_width, shadow_size, shadow_color)
	return _style_cache[key]


func _safe_color(value: String, fallback: Color) -> Color:
	return Color(value) if Color.html_is_valid(value) else fallback
