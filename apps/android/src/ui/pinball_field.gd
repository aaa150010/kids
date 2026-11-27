class_name PinballField
extends Control

signal action_requested(action: Dictionary)

const TAP_SLOP := 14.0
const NOTICE_SECONDS := 2.1
const BOARD_ASPECT := 0.605

var engine: PinballRules
var game_screen: NativeGameScreen
var players: Array = []
var accent := Color("#6f4b98")
var soft := Color("#ede5f6")
var interactive := true

var fx: ArcadeFxLayer
var _board_card := Rect2()
var _world_rect := Rect2()
var _left_hud := Rect2()
var _right_hud := Rect2()
var _wide_layout := true
var _launch_rect := Rect2()
var _left_zone := Rect2()
var _right_zone := Rect2()
var _touch_sides: Dictionary = {}
var _last_touch_msec := -1000
var _clock := 0.0
var _notice := ""
var _notice_time := 0.0
var _style_cache: Dictionary = {}
var _trail_active := false
var _trail_tick := 0.0
var _celebrate := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	clip_contents = true
	custom_minimum_size = Vector2(760, 520)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	fx = ArcadeFxLayer.new()
	fx.set_palette(accent, soft)
	fx.gravity = 65.0
	add_child(fx)
	resized.connect(_layout_and_redraw)
	_layout()
	queue_redraw()


func bind(value: PinballRules, screen: NativeGameScreen, seat_players: Array) -> void:
	engine = value
	game_screen = screen
	players = seat_players.duplicate(true)
	_touch_sides.clear()
	_notice = ""
	_notice_time = 0.0
	_celebrate = false
	_trail_active = false
	_trail_tick = 0.0
	if is_instance_valid(fx):
		fx.clear_effects()
	_layout()
	queue_redraw()


func set_interactive(value: bool) -> void:
	interactive = value
	if not value:
		cancel_inputs()
	queue_redraw()


func cancel_inputs() -> void:
	_touch_sides.clear()
	queue_redraw()


func suspend_effects() -> void:
	cancel_inputs()
	_trail_active = false
	_celebrate = false
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
	_update_ball_trail(frame)
	queue_redraw()


func _update_ball_trail(delta: float) -> void:
	if engine == null or not is_instance_valid(fx):
		return
	var ball := engine.ball_snapshot()
	if str(ball.get("status", "")) == "live":
		var point := _world_to_pixel(Vector2(float(ball.get("x", 0.5)), float(ball.get("y", 0.5))))
		if not _trail_active:
			fx.begin_trail("pinball", point, Color("#ffd66f"), 12.0)
			_trail_active = true
			_trail_tick = 0.0
		_trail_tick += delta
		fx.add_trail_point("pinball", point, 3.0)
		if _trail_tick >= 0.065:
			_trail_tick = 0.0
			fx.emit_burst(point, Color("#ffe89a"), 2, {
				"speed": 20.0,
				"life": 0.34,
				"size": 2.2,
				"kind": "star",
			})
	elif _trail_active:
		_trail_active = false
		fx.end_trail("pinball")


func _layout() -> void:
	if size.x < 2.0 or size.y < 2.0:
		return
	var margin := clampf(minf(size.x, size.y) * 0.014, 10.0, 18.0)
	var gap := 14.0
	var body := Rect2(margin, margin, size.x - margin * 2.0, size.y - margin * 2.0)
	_wide_layout = body.size.x >= 900.0
	var hud_width := clampf(body.size.x * 0.19, 210.0, 310.0) if _wide_layout else 0.0
	var available_width := (body.size.x - hud_width * 2.0 - gap * 2.0) if _wide_layout else (body.size.x * 0.78)
	var board_height := body.size.y
	var board_width := minf(board_height * BOARD_ASPECT, available_width)
	if not _wide_layout:
		board_width = minf(body.size.x * 0.74, body.size.y * BOARD_ASPECT)
		board_height = board_width / BOARD_ASPECT
	var board_size := Vector2(board_width, board_height)
	var board_position := Vector2(
		body.position.x + (body.size.x - board_width) * 0.5,
		body.position.y + (body.size.y - board_height) * 0.5
	)
	_board_card = Rect2(board_position, board_size)
	_world_rect = _board_card.grow(-clampf(board_width * 0.025, 10.0, 18.0))
	_left_hud = Rect2(body.position, Vector2(hud_width, body.size.y)) if _wide_layout else Rect2()
	_right_hud = Rect2(body.end.x - hud_width, body.position.y, hud_width, body.size.y) if _wide_layout else Rect2()
	if _wide_layout:
		_launch_rect = Rect2(
			Vector2(_right_hud.position.x + 18.0, _right_hud.position.y + _right_hud.size.y * 0.64),
			Vector2(maxf(140.0, _right_hud.size.x - 36.0), 70.0)
		)
	else:
		_launch_rect = Rect2(
			Vector2(_board_card.end.x - 146.0, _board_card.position.y + 22.0),
			Vector2(124.0, 56.0)
		)
	var zone_top := _world_to_pixel(Vector2(0.0, 0.68)).y
	var world_center := _world_to_pixel(Vector2(0.5, 0.5)).x
	_left_zone = Rect2(
		Vector2(_world_rect.position.x, zone_top),
		Vector2(world_center - _world_rect.position.x, _world_rect.end.y - zone_top)
	)
	_right_zone = Rect2(
		Vector2(world_center, zone_top),
		Vector2(_world_rect.end.x - world_center, _world_rect.end.y - zone_top)
	)


func _layout_and_redraw() -> void:
	_layout()
	queue_redraw()


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
			_pointer_up(event.index)
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		_last_touch_msec = Time.get_ticks_msec()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if Time.get_ticks_msec() - _last_touch_msec < 500:
			return
		if event.pressed:
			_pointer_down(-1, event.position)
		else:
			_pointer_up(-1)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _touch_sides.has(-1):
		var side := str(_touch_sides[-1])
		if not _zone_for(side).has_point(event.position):
			_release_side(-1, side)
		get_viewport().set_input_as_handled()


func _pointer_down(pointer_id: int, point: Vector2) -> void:
	if engine == null:
		return
	if engine.ball_ready() and _launch_rect.has_point(point):
		action_requested.emit({"type": "launch", "seat": 0})
		AudioFX.play("select")
		return
	for side in ["left", "right"]:
		if not _zone_for(side).has_point(point):
			continue
		_touch_sides[pointer_id] = side
		action_requested.emit({
			"type": "flipper",
			"side": side,
			"pressed": true,
			"seat": _seat_for_side(side),
		})
		AudioFX.play("tap")
		return


func _pointer_up(pointer_id: int) -> void:
	if not _touch_sides.has(pointer_id):
		return
	var side := str(_touch_sides[pointer_id])
	_release_side(pointer_id, side)


func _release_side(pointer_id: int, side: String) -> void:
	_touch_sides.erase(pointer_id)
	action_requested.emit({
		"type": "flipper",
		"side": side,
		"pressed": false,
		"seat": _seat_for_side(side),
	})


func _seat_for_side(side: String) -> int:
	if engine == null or not engine.is_cooperative():
		return 0
	return 0 if side == "left" else 1


func _zone_for(side: String) -> Rect2:
	return _left_zone if side == "left" else _right_zone


func _blocked() -> bool:
	if engine == null or str(engine.state.get("phase", "")) != "playing":
		return true
	if game_screen != null and game_screen.is_input_blocked():
		return true
	return TabletopLayout.input_blocked(self)


func consume_events(events: Array) -> void:
	for raw in events:
		if not raw is Dictionary:
			continue
		var event: Dictionary = raw
		var point := _event_point(event)
		match str(event.get("type", "")):
			"launch":
				if is_instance_valid(fx):
					fx.emit_burst(point, Color("#ffe58b"), 12, {
						"speed": 68.0,
						"spread": 1.0,
						"direction": Vector2.UP,
						"life": 0.42,
						"size": 3.2,
						"kind": "star",
					})
					fx.ring(point, Color(accent, 0.75), 24.0, 0.35)
				AudioFX.play("whoosh")
			"bumper":
				if is_instance_valid(fx):
					fx.emit_burst(point, Color("#f2ce69"), 10, {"speed": 75.0, "life": 0.45, "size": 3.4, "kind": "star"})
					fx.ring(point, Color("#ffdf84"), 24.0, 0.36, 3.0)
					fx.popup("+%s" % int(event.get("points", 0)), point + Vector2(0, -18), Color("#ffe8a2"), 20, 0.62)
				AudioFX.play("tap")
				FeedbackKit.haptic(4)
			"target":
				if is_instance_valid(fx):
					fx.ring(point, Color("#fff1b2"), 30.0, 0.45, 4.0)
					fx.emit_burst(point, Color("#ffe078"), 14, {"speed": 72.0, "life": 0.56, "size": 3.4, "kind": "star"})
					fx.popup("目标灯 +%s" % int(event.get("points", 0)), point + Vector2(0, -20), Color("#fff4c4"), 19, 0.72)
				AudioFX.play("correct")
				FeedbackKit.haptic(6)
			"all_targets":
				if is_instance_valid(fx):
					fx.ring(_world_to_pixel(Vector2(0.5, 0.35)), Color("#ffe58c"), 64.0, 0.8, 5.0)
					fx.emit_burst(point, Color("#ffe692"), 24, {"speed": 104.0, "spread": TAU, "life": 0.72, "size": 3.8, "kind": "star"})
					fx.popup("全部点亮！", point + Vector2(0, -28), Color("#fff4bd"), 25, 0.9)
				flash_notice("全部目标灯点亮！让弹珠落进中间，就能完成星轨。", 3.0)
				AudioFX.play("win")
			"flipper":
				if bool(event.get("pressed", false)) and is_instance_valid(fx):
					fx.ring(point, Color(accent, 0.35), 12.0, 0.18, 2.0)
			"flipper_hit":
				if is_instance_valid(fx):
					fx.emit_burst(point, Color("#f6dbff"), 4, {"speed": 34.0, "life": 0.24, "size": 2.3})
				AudioFX.play("flip")
			"bounce":
				if is_instance_valid(fx):
					fx.emit_burst(point, Color("#ddc9ff"), 3, {"speed": 30.0, "life": 0.20, "size": 2.0})
				AudioFX.play("tap")
			"drain":
				if is_instance_valid(fx):
					fx.emit_star_trail(point, Color("#c1a9e8"), 6)
					fx.shake(3.5, 0.22)
			"ball_save":
				if is_instance_valid(fx):
					fx.ring(_world_to_pixel(Vector2(0.5, 0.82)), Color("#ffe58f"), 46.0, 0.7, 5.0)
					fx.emit_burst(_world_to_pixel(Vector2(0.5, 0.78)), Color("#ffe897"), 20, {
						"speed": 90.0,
						"spread": TAU,
						"life": 0.65,
						"size": 3.5,
						"kind": "star",
					})
					fx.popup("落球保护", point + Vector2(0, -22), Color("#fff1b9"), 22, 0.8)
				flash_notice("落球保护接住了这一颗！还剩 %s 次。" % int(event.get("remaining", 0)), 2.4)
				AudioFX.play("pair")
			"ball_lost":
				flash_notice("还剩 %s 颗弹珠，准备下一颗。" % int(event.get("ballsLeft", 0)), 2.1)
				AudioFX.play("drop")
			"nudge":
				if is_instance_valid(fx):
					fx.emit_burst(point, Color(accent, 0.9), 6, {"speed": 46.0, "life": 0.3, "size": 2.8})
			"complete":
				_celebrate = true
				_trail_active = false
				if is_instance_valid(fx):
					fx.end_trail("pinball")
					fx.ring(_world_to_pixel(Vector2(0.5, 0.45)), Color("#ffe58a"), 80.0, 1.0, 5.0)
					for index in 8:
						var angle := TAU * float(index) / 8.0
						var target := _world_to_pixel(Vector2(0.5, 0.45)) + Vector2(cos(angle), sin(angle)) * _world_rect.size.x * 0.25
						fx.emit_burst(target, Color("#ffe390"), 10, {"speed": 82.0, "life": 0.7, "size": 3.4, "kind": "star"})
					fx.shake(5.0, 0.3)
				AudioFX.play("win" if bool(event.get("success", false)) else "wrong")
	queue_redraw()


func _draw() -> void:
	var shake := fx.get_shake_offset() if is_instance_valid(fx) else Vector2.ZERO
	_draw_backdrop(shake)
	if engine == null or str(engine.state.get("phase", "")) == "empty":
		_draw_empty()
		return
	_draw_board(shake)
	_draw_launch_guide(shake)
	_draw_walls(shake)
	_draw_bumpers(shake)
	_draw_targets(shake)
	_draw_flippers(shake)
	_draw_ball(shake)
	_draw_touch_zones(shake)
	if _wide_layout:
		_draw_side_hud(_left_hud, true)
		_draw_side_hud(_right_hud, false)
	else:
		_draw_compact_hud()
	_draw_launch_button()
	_draw_notice()
	if _celebrate:
		_draw_celebrate()


func _draw_backdrop(shake: Vector2) -> void:
	var full := Rect2(Vector2.ZERO, size)
	draw_style_box(_style(Color("#f8f1e5"), 28, Color(accent, 0.22), 2), full.grow(-2.0))
	var wash := Rect2(8.0, 8.0, size.x - 16.0, size.y - 16.0)
	draw_style_box(_style(Color(soft, 0.55), 23, Color.TRANSPARENT, 0), wash)
	for index in 18:
		var x := 34.0 + fmod(float(index) * 97.0, maxf(1.0, size.x - 68.0))
		var y := 22.0 + fmod(float(index) * 67.0, maxf(1.0, size.y - 44.0))
		var radius := 1.5 + float(index % 3) * 0.7
		draw_circle(Vector2(x, y) + shake * 0.18, radius, Color(accent, 0.10))


func _draw_board(shake: Vector2) -> void:
	var card := Rect2(_board_card.position + shake, _board_card.size)
	draw_style_box(_style(Color("#fff8e8"), 30, Color(accent, 0.52), 3), card)
	var inner := _world_rect.grow(1.0)
	inner.position += shake
	draw_style_box(_style(Color("#20162f"), 25, Color("#c7b6e4"), 2), inner)
	var bands := 20
	for index in bands:
		var amount := float(index) / float(bands - 1)
		var row := Rect2(
			inner.position.x + 3.0,
			inner.position.y + 3.0 + (inner.size.y - 6.0) * amount,
			inner.size.x - 6.0,
			(inner.size.y - 6.0) / float(bands) + 1.0
		)
		draw_rect(row, Color("#271b3c").lerp(Color("#392450"), amount), true)
	for index in 15:
		var point := _world_to_pixel(Vector2(
			0.06 + fmod(float(index) * 0.173, 0.86),
			0.05 + fmod(float(index) * 0.119, 0.72)
		)) + shake * 0.5
		_draw_star(point, 2.0 + float(index % 3), Color(0.96, 0.87, 0.57, 0.32), float(index) * 0.31)
	var rail_left := _world_to_pixel(Vector2(0.018, 0.06)) + shake
	var rail_right := _world_to_pixel(Vector2(0.982, 0.06)) + shake
	draw_line(rail_left, rail_left + Vector2(0, _world_rect.size.y * 0.88), Color("#e8d8a7"), 2.0, true)
	draw_line(rail_right, rail_right + Vector2(0, _world_rect.size.y * 0.88), Color("#e8d8a7"), 2.0, true)
	var lane_glow := _world_to_pixel(Vector2(0.90, 0.56)) + shake
	draw_circle(lane_glow, _world_rect.size.x * 0.055, Color(accent, 0.10))


func _draw_launch_guide(shake: Vector2) -> void:
	var lane_start := _world_to_pixel(Vector2(0.895, 0.84)) + shake
	var lane_finish := _world_to_pixel(Vector2(0.895, 0.18)) + shake
	var pulse := (0.35 + sin(_clock * 2.4) * 0.12) if engine.ball_ready() else 0.12
	draw_dashed_line(lane_start, lane_finish, Color("#f6dc81", pulse), 2.0, 8.0, true)
	if engine.ball_ready():
		var arrow := _world_to_pixel(Vector2(0.895, 0.24)) + shake
		_draw_arrow(arrow, Vector2.UP, Color("#ffe790"))


func _draw_walls(shake: Vector2) -> void:
	var table: Dictionary = engine.state.get("level", {})
	var wall_width := clampf(_world_rect.size.x * 0.012, 2.0, 7.0)
	for raw in table.get("walls", []):
		if not raw is Dictionary:
			continue
		var wall: Dictionary = raw
		var start := _world_to_pixel(Vector2(float(wall.get("x1", 0.0)), float(wall.get("y1", 0.0)))) + shake
		var finish := _world_to_pixel(Vector2(float(wall.get("x2", 0.0)), float(wall.get("y2", 0.0)))) + shake
		var radius := maxf(2.0, float(wall.get("radius", 0.006)) * _world_rect.size.x)
		draw_line(start + Vector2(0, 2), finish + Vector2(0, 2), Color(0.04, 0.02, 0.08, 0.4), wall_width + radius * 1.6, true)
		draw_line(start, finish, Color("#d8c6f0"), wall_width + radius, true)
		draw_line(start, finish, Color("#f6edff"), maxf(1.0, wall_width * 0.30), true)
		draw_circle(start, radius, Color("#eadcf8"))
		draw_circle(finish, radius, Color("#eadcf8"))


func _draw_bumpers(shake: Vector2) -> void:
	var table: Dictionary = engine.state.get("level", {})
	var bumpers: Array = table.get("bumpers", [])
	for index in bumpers.size():
		var raw: Variant = bumpers[index]
		if not raw is Dictionary:
			continue
		var bumper: Dictionary = raw
		var center := _world_to_pixel(Vector2(float(bumper.get("x", 0.5)), float(bumper.get("y", 0.4)))) + shake
		var radius := maxf(10.0, float(bumper.get("radius", 0.04)) * _world_rect.size.x)
		var glow := 0.10 + sin(_clock * 3.0 + float(index)) * 0.035
		draw_circle(center, radius * 1.42, Color(accent, glow))
		draw_circle(center, radius, Color("#6d4a8d"))
		draw_circle(center, radius * 0.82, Color("#a889c2"))
		draw_circle(center - Vector2(radius * 0.22, radius * 0.25), radius * 0.35, Color("#f8eeff"))
		_draw_star(center, radius * 0.45, Color("#ffe49a"), _clock * 0.35 + float(index))
		draw_arc(center, radius, 0.0, TAU, 28, Color("#f1ddff"), 2.0, true)


func _draw_targets(shake: Vector2) -> void:
	var progress := engine.target_progress()
	var font := PlaygroundUI.font()
	var table: Dictionary = engine.state.get("level", {})
	var target_defs_value: Variant = table.get("targets", [])
	var target_defs: Array = target_defs_value if target_defs_value is Array else []
	for raw in progress:
		if not raw is Dictionary:
			continue
		var target: Dictionary = raw
		var center := _world_to_pixel(Vector2(float(target.get("x", 0.5)), float(target.get("y", 0.2)))) + shake
		var lit := bool(target.get("lit", false))
		var target_radius := 0.018
		var target_index := int(target.get("index", -1))
		if target_index >= 0 and target_index < target_defs.size() and target_defs[target_index] is Dictionary:
			target_radius = float((target_defs[target_index] as Dictionary).get("radius", 0.018))
		var radius := maxf(7.0, target_radius * _world_rect.size.x)
		var color := Color("#ffe17a") if lit else Color(accent, 0.76)
		if lit:
			draw_circle(center, radius * 1.75, Color(1.0, 0.84, 0.38, 0.14 + sin(_clock * 3.0) * 0.03))
			draw_circle(center, radius * 1.28, Color("#ffd96c"))
			_draw_star(center, radius * 0.82, Color("#fff8d0"), _clock * 0.18)
		else:
			draw_circle(center, radius * 1.18, Color("#3b2853"))
			draw_circle(center, radius, color)
			draw_circle(center, radius * 0.46, Color("#f2e6ff"))
			draw_arc(center, radius * 1.32, 0.0, TAU, 22, Color(accent, 0.4), 1.5, true)
		var label := str(target.get("label", "目标灯"))
		var label_size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12)
		draw_string(
			font,
			center - Vector2(label_size.x * 0.5, -radius - 5.0),
			label,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			12,
			Color("#fff1c6") if lit else Color("#d9c7ef")
		)


func _draw_flippers(shake: Vector2) -> void:
	var table: Dictionary = engine.state.get("level", {})
	var flippers_value: Variant = table.get("flippers", {})
	var flippers: Dictionary = flippers_value if flippers_value is Dictionary else {}
	for side in ["left", "right"]:
		var definition: Dictionary = flippers.get(side, {})
		var default_pivot := [0.30, 0.80] if side == "left" else [0.70, 0.80]
		var pivot_value: Variant = definition.get("pivot", default_pivot)
		var pivot := Vector2(0.30, 0.80) if side == "left" else Vector2(0.70, 0.80)
		if pivot_value is Array and pivot_value.size() >= 2:
			pivot = Vector2(float(pivot_value[0]), float(pivot_value[1]))
		var length := float(definition.get("length", 0.17))
		var angle := engine.flipper_angle(side)
		var start := _world_to_pixel(pivot) + shake
		var finish := _world_to_pixel(pivot + Vector2(cos(angle), sin(angle)) * length) + shake
		var thickness := clampf(_world_rect.size.x * 0.040, 12.0, 25.0)
		draw_line(start + Vector2(0, 3), finish + Vector2(0, 3), Color(0.04, 0.02, 0.08, 0.5), thickness + 8.0, true)
		draw_line(start, finish, Color("#d99055"), thickness + 5.0, true)
		draw_line(start, finish, Color("#ffcf8c"), thickness, true)
		draw_line(start + (finish - start) * 0.18, finish, Color("#fff0c0"), maxf(2.0, thickness * 0.22), true)
		draw_circle(start, thickness * 0.62, Color("#704a8b"))
		draw_circle(start, thickness * 0.43, Color("#ffe6a4"))
		var pressed := engine.flipper_pressed(side)
		if pressed:
			draw_circle(finish, thickness * 0.42, Color("#fff3b2"))


func _draw_ball(shake: Vector2) -> void:
	var ball := engine.ball_snapshot()
	var status := str(ball.get("status", ""))
	if status == "settled":
		return
	var center := _world_to_pixel(Vector2(float(ball.get("x", 0.5)), float(ball.get("y", 0.88)))) + shake
	var table: Dictionary = engine.state.get("level", {})
	var radius := maxf(5.0, float(table.get("ballRadius", 0.021)) * _world_rect.size.x)
	var pulse := (1.0 + sin(_clock * 4.0) * 0.05) if status == "ready" else 1.0
	draw_circle(center, radius * 2.2 * pulse, Color(1.0, 0.88, 0.45, 0.10))
	draw_circle(center, radius * 1.35 * pulse, Color("#fff2b5"))
	draw_circle(center, radius * pulse, Color("#fff9ee"))
	draw_circle(center - Vector2(radius * 0.28, radius * 0.30), radius * 0.34, Color.WHITE)
	draw_arc(center, radius * pulse, 0.0, TAU, 20, Color("#e6b84f"), 1.5, true)
	if status == "ready":
		var ring_radius := radius * (2.1 + sin(_clock * 3.2) * 0.18)
		draw_arc(center, ring_radius, 0.0, TAU, 28, Color("#ffe58e", 0.72), 2.0, true)


func _draw_touch_zones(shake: Vector2) -> void:
	var left_color := Color(accent, 0.10)
	var right_color := Color("#d99055", 0.12)
	var left_rect := Rect2(_left_zone.position + shake, _left_zone.size)
	var right_rect := Rect2(_right_zone.position + shake, _right_zone.size)
	draw_style_box(_style(left_color, 14, Color(accent, 0.18), 1), left_rect.grow(-4.0))
	draw_style_box(_style(right_color, 14, Color("#d99055", 0.24), 1), right_rect.grow(-4.0))
	_draw_zone_label(left_rect, "左弹板", "left")
	_draw_zone_label(right_rect, "右弹板", "right")


func _draw_zone_label(rect: Rect2, text: String, side: String) -> void:
	var font := PlaygroundUI.font()
	var label_rect := Rect2(rect.position + Vector2(12.0, rect.size.y - 42.0), Vector2(rect.size.x - 24.0, 32.0))
	var tint := Color(accent, 0.32) if side == "left" else Color("#b35f36", 0.34)
	draw_style_box(_style(Color(0.05, 0.03, 0.10, 0.58), 13, tint, 1), label_rect)
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15)
	draw_string(
		font,
		Vector2(label_rect.position.x + (label_rect.size.x - text_size.x) * 0.5, label_rect.position.y + 22.0),
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		15,
		Color("#fff2c8")
	)


func _draw_side_hud(rect: Rect2, left: bool) -> void:
	if rect.size.x <= 1.0:
		return
	var font := PlaygroundUI.font()
	var ink := PlaygroundUI.INK
	var muted := PlaygroundUI.INK_SOFT
	var panel := Rect2(rect.position, rect.size)
	draw_style_box(_style(Color(1, 1, 1, 0.46), 24, Color(accent, 0.16), 1), panel)
	var x := rect.position.x + 18.0
	var width := rect.size.x - 36.0
	var y := rect.position.y + 20.0
	if left:
		_draw_text("弹珠星轨", Vector2(x, y + 14.0), 18, Color(accent, 0.88))
		_draw_text(str(engine.state.get("levelTitle", "星轨弹珠")), Vector2(x, y + 46.0), 23, ink)
		_draw_text("分数", Vector2(x, y + 88.0), 14, muted)
		_draw_text(str(int(engine.state.get("score", 0))), Vector2(x, y + 127.0), 34, ink)
		var balls_left := int(engine.state.get("ballsLeft", 0))
		var saves_left := int(engine.state.get("savesRemaining", 0))
		_draw_text("剩余弹珠  %s" % balls_left, Vector2(x, y + 166.0), 17, ink)
		_draw_text("落球保护  %s" % saves_left, Vector2(x, y + 193.0), 17, Color("#8a6324"))
		var line_y := y + 231.0
		if engine.is_cooperative():
			for index in mini(players.size(), 2):
				var player: Dictionary = players[index]
				var side := "左弹板" if index == 0 else "右弹板"
				_draw_text("%s 守%s" % [str(player.get("name", "小朋友")), side], Vector2(x, line_y), 16, ink)
				line_y += 27.0
		elif not players.is_empty():
			_draw_text("%s 控制两块弹板" % str(players[0].get("name", "小朋友")), Vector2(x, line_y), 16, ink)
		_draw_text("按住下方弹板区域", Vector2(x, rect.end.y - 70.0), 14, muted)
		_draw_text("松开后弹板回位", Vector2(x, rect.end.y - 45.0), 14, muted)
	else:
		_draw_text("目标灯", Vector2(x, y + 14.0), 18, Color(accent, 0.88))
		var progress := engine.target_progress()
		var row_y := y + 52.0
		for index in progress.size():
			var target: Dictionary = progress[index]
			var dot_center := Vector2(x + 13.0, row_y - 4.0)
			if bool(target.get("lit", false)):
				draw_circle(dot_center, 9.0, Color("#ffd96c"))
				_draw_star(dot_center, 5.0, Color("#fff8d5"), 0.0)
			else:
				draw_circle(dot_center, 9.0, Color(accent, 0.26))
				draw_arc(dot_center, 9.0, 0.0, TAU, 18, Color(accent, 0.55), 1.5, true)
			_draw_text(str(target.get("label", "目标灯")), Vector2(x + 30.0, row_y), 17, ink if bool(target.get("lit", false)) else muted)
			row_y += 31.0
		var done := 0
		for target in progress:
			if bool(target.get("lit", false)):
				done += 1
		_draw_text("已点亮 %s / %s" % [done, progress.size()], Vector2(x, rect.end.y - 105.0), 17, ink)
		if int(engine.state.get("hintsUsed", 0)) > 0:
			_draw_text("提示 %s 次" % int(engine.state.get("hintsUsed", 0)), Vector2(x, rect.end.y - 76.0), 14, muted)
		var coop := engine.is_cooperative()
		_draw_text("共享分数与球权" if coop else "单人星轨挑战", Vector2(x, rect.end.y - 47.0), 14, muted)


func _draw_compact_hud() -> void:
	var font := PlaygroundUI.font()
	var box := Rect2(_board_card.position + Vector2(10.0, 8.0), Vector2(_board_card.size.x - 150.0, 52.0))
	draw_style_box(_style(Color(0.08, 0.04, 0.13, 0.76), 16, Color(accent, 0.35), 1), box)
	var done := 0
	var progress := engine.target_progress()
	for target in progress:
		if bool(target.get("lit", false)):
			done += 1
	var copy := "分数 %s   目标 %s/%s   球 %s   保护 %s" % [
		int(engine.state.get("score", 0)),
		done,
		progress.size(),
		int(engine.state.get("ballsLeft", 0)),
		int(engine.state.get("savesRemaining", 0)),
	]
	draw_string(font, box.position + Vector2(14.0, 33.0), copy, HORIZONTAL_ALIGNMENT_LEFT, box.size.x - 24.0, 16, Color("#fff4cf"))


func _draw_launch_button() -> void:
	if not engine.ball_ready():
		return
	var hover := 1.0 + sin(_clock * 4.0) * 0.015
	var rect := Rect2(
		_launch_rect.position + _launch_rect.size * (1.0 - hover) * 0.5,
		_launch_rect.size * hover
	)
	var base := Color("#ffe08a")
	draw_style_box(_style(Color(0.05, 0.02, 0.08, 0.36), 20, Color.TRANSPARENT, 0), Rect2(rect.position + Vector2(0, 4), rect.size))
	draw_style_box(_style(base, 20, Color("#9a6b27"), 2), rect)
	var font := PlaygroundUI.font()
	var text := "发射弹珠"
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 19)
	draw_string(
		font,
		rect.position + Vector2((rect.size.x - text_size.x) * 0.5, rect.size.y * 0.5 + 7.0),
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		19,
		Color("#422b13")
	)
	_draw_arrow(Vector2(rect.position.x + 22.0, rect.position.y + rect.size.y * 0.5), Vector2.UP, Color("#6f4b2a"))


func _draw_notice() -> void:
	if _notice_time <= 0.0 or _notice.is_empty():
		return
	var alpha := clampf(_notice_time / 0.7, 0.0, 1.0)
	var width := minf(size.x - 100.0, 620.0)
	var font := PlaygroundUI.font()
	var text_size := font.get_string_size(_notice, HORIZONTAL_ALIGNMENT_LEFT, -1, 17)
	var box := Rect2(Vector2((size.x - width) * 0.5, 24.0), Vector2(width, 42.0))
	draw_style_box(_style(Color(0.10, 0.05, 0.16, 0.88 * alpha), 16, Color(accent, 0.36 * alpha), 1), box)
	draw_string(font, Vector2((size.x - text_size.x) * 0.5, 50.0), _notice, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color(1, 1, 1, alpha))


func _draw_celebrate() -> void:
	var center := _world_to_pixel(Vector2(0.5, 0.42))
	var radius := _world_rect.size.x * (0.33 + sin(_clock * 2.0) * 0.018)
	draw_circle(center, radius, Color(1.0, 0.84, 0.39, 0.07))
	draw_arc(center, radius, 0.0, TAU, 64, Color(1.0, 0.88, 0.54, 0.32), 4.0, true)
	for index in 9:
		var angle := TAU * float(index) / 9.0 + _clock * 0.15
		var point := center + Vector2(cos(angle), sin(angle)) * radius * 0.76
		_draw_star(point, 6.0, Color("#ffe393"), angle)


func _draw_empty() -> void:
	var font := PlaygroundUI.font()
	draw_string(
		font,
		Vector2(size.x * 0.5 - 230.0, size.y * 0.5),
		"这张弹珠台还没有准备好",
		HORIZONTAL_ALIGNMENT_CENTER,
		460.0,
		24,
		PlaygroundUI.INK_SOFT
	)


func _draw_text(text: String, position: Vector2, font_size: int, color: Color) -> void:
	draw_string(PlaygroundUI.font(), position, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


func _draw_arrow(center: Vector2, direction: Vector2, color: Color) -> void:
	var side := Vector2(-direction.y, direction.x)
	var size_value := 7.0
	draw_colored_polygon(PackedVector2Array([
		center + direction * size_value,
		center - direction * size_value * 0.5 + side * size_value * 0.62,
		center - direction * size_value * 0.5 - side * size_value * 0.62,
	]), color)


func _draw_star(center: Vector2, radius: float, color: Color, rotation: float) -> void:
	var points := PackedVector2Array()
	for index in 10:
		var angle := rotation - PI * 0.5 + float(index) * PI / 5.0
		var length := radius if index % 2 == 0 else radius * 0.44
		points.append(center + Vector2(cos(angle), sin(angle)) * length)
	draw_colored_polygon(points, color)


func _world_to_pixel(point: Vector2) -> Vector2:
	return _world_rect.position + Vector2(point.x * _world_rect.size.x, point.y * _world_rect.size.y)


func _event_point(event: Dictionary) -> Vector2:
	return _world_to_pixel(Vector2(float(event.get("x", 0.5)), float(event.get("y", 0.5))))


func _style(fill: Color, radius: int, border: Color, border_width: int) -> StyleBoxFlat:
	var key := "%s|%s|%s|%s" % [fill.to_html(), radius, border.to_html(), border_width]
	if _style_cache.has(key):
		return _style_cache[key]
	var style := PlaygroundUI.style(fill, radius, border, border_width)
	_style_cache[key] = style
	return style
