class_name SokobanBoard
extends Control

signal direction_selected(direction: String)

const DIRECTIONS := ["up", "left", "right", "down"]
const DIRECTION_LABELS := {
	"up": "向上",
	"down": "向下",
	"left": "向左",
	"right": "向右",
}
const DIRECTION_ARROWS := {
	"up": Vector2(0, -1),
	"down": Vector2(0, 1),
	"left": Vector2(-1, 0),
	"right": Vector2(1, 0),
}
const SWIPE_DISTANCE := 30.0

var level: Dictionary = {}
var state: Dictionary = {}
var accent := Color("#8a5f3d")
var soft := Color("#f2e5d7")
var interactive := true

var _board_rect := Rect2()
var _dock_rect := Rect2()
var _grid_rect := Rect2()
var _grid_size := Vector2.ZERO
var _cell_size := 1.0
var _grid_gap := 2.0
var _grid_origin := Vector2.ZERO
var _side_dock := false
var _dock_buttons: Dictionary = {}
var _undo_preview: Dictionary = {}
var _pressed_direction := ""
var _press_point := Vector2.ZERO
var _press_index := -1
var _swipe_origin := Vector2.ZERO
var _swipe_current := Vector2.ZERO
var _swipe_origin_active := false
var _swipe_consumed := false
var _last_touch_msec := -1000
var _clock := 0.0
var _style_cache: Dictionary = {}
var _hint_direction := ""
var _deadlock_box: Dictionary = {}
var _last_move := ""
var _last_move_at := -100.0


func _ready() -> void:
	custom_minimum_size = Vector2(760, 500)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	clip_contents = true
	resized.connect(_layout)
	_layout()
	set_process(true)


func configure(value: Dictionary, tint: Color, soft_tint: Color) -> void:
	level = value.duplicate(true)
	accent = tint
	soft = soft_tint
	state = {}
	_undo_preview = {}
	_style_cache.clear()
	_layout()
	queue_redraw()


func set_state(value: Dictionary) -> void:
	var old_width := int(level.get("width", 0))
	var old_height := int(level.get("height", 0))
	state = value
	if state.get("level") is Dictionary:
		level = state.get("level")
	_hint_direction = str(state.get("hintDirection", ""))
	var deadlock_value: Variant = state.get("deadlockBox", {})
	_deadlock_box = deadlock_value.duplicate(true) if deadlock_value is Dictionary else {}
	var next_move := str(state.get("lastMove", ""))
	if not next_move.is_empty() and next_move != _last_move:
		_last_move = next_move
		_last_move_at = _clock
	_pressed_direction = ""
	if int(level.get("width", 0)) != old_width or int(level.get("height", 0)) != old_height:
		_layout()
	queue_redraw()


func set_undo_preview(value: Dictionary) -> void:
	_undo_preview = value.duplicate(true) if value is Dictionary else {}
	queue_redraw()


func set_interaction_enabled(value: bool) -> void:
	interactive = value
	if not value:
		_cancel_pointer()
	queue_redraw()


func cancel_gesture() -> void:
	_cancel_pointer()


func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_WM_CLOSE_REQUEST]:
		_cancel_pointer()


func _process(delta: float) -> void:
	_clock += delta
	if not _hint_direction.is_empty() or not _deadlock_box.is_empty() or _clock - _last_move_at < 0.5 or _swipe_origin_active:
		queue_redraw()


func _layout() -> void:
	if size.x < 2.0 or size.y < 2.0:
		return
	var margin := 12.0
	var gap := 12.0
	var side_dock := size.x >= 930.0 and size.x > size.y * 1.08
	_side_dock = side_dock
	if side_dock:
		var dock_width := clampf(size.x * 0.205, 214.0, 294.0)
		_board_rect = Rect2(margin, margin, maxf(280.0, size.x - dock_width - gap - margin * 2.0), maxf(260.0, size.y - margin * 2.0))
		_dock_rect = Rect2(size.x - margin - dock_width, margin, dock_width, _board_rect.size.y)
	else:
		var dock_height := clampf(size.y * 0.32, 188.0, 258.0)
		_board_rect = Rect2(margin, margin, size.x - margin * 2.0, maxf(250.0, size.y - dock_height - gap - margin * 2.0))
		_dock_rect = Rect2(margin, size.y - margin - dock_height, size.x - margin * 2.0, dock_height)
	_layout_grid()
	_layout_dock(side_dock)


func _layout_grid() -> void:
	var width := maxi(1, int(level.get("width", 1)))
	var height := maxi(1, int(level.get("height", 1)))
	var header := 54.0
	var footer := 34.0
	var room := Rect2(
		_board_rect.position + Vector2(18.0, header + 8.0),
		Vector2(_board_rect.size.x - 36.0, maxf(40.0, _board_rect.size.y - header - footer - 16.0))
	)
	var rough_cell := minf(room.size.x / float(width), room.size.y / float(height))
	var gap := clampf(rough_cell * 0.035, 2.0, 5.0)
	var cell := minf(
		(room.size.x - gap * float(maxi(0, width - 1))) / float(width),
		(room.size.y - gap * float(maxi(0, height - 1))) / float(height)
	)
	cell = maxf(22.0, cell)
	var grid_size := Vector2(
		cell * float(width) + gap * float(maxi(0, width - 1)),
		cell * float(height) + gap * float(maxi(0, height - 1))
	)
	_grid_size = grid_size
	_cell_size = cell
	_grid_gap = gap
	_grid_origin = room.position + (room.size - grid_size) * 0.5
	_grid_rect = Rect2(_grid_origin, grid_size)


func _layout_dock(side_dock: bool) -> void:
	_dock_buttons.clear()
	if side_dock:
		var header := 126.0
		var footer := 40.0
		var room := Rect2(
			_dock_rect.position + Vector2(16.0, header),
			Vector2(_dock_rect.size.x - 32.0, maxf(140.0, _dock_rect.size.y - header - footer))
		)
		var gap := 8.0
		var button_width := minf(88.0, (room.size.x - gap * 2.0) / 3.0)
		var button_height := minf(82.0, (room.size.y - gap * 2.0) / 3.0)
		button_width = maxf(52.0, button_width)
		button_height = maxf(52.0, button_height)
		var cross_size := Vector2(button_width * 3.0 + gap * 2.0, button_height * 3.0 + gap * 2.0)
		var origin := room.position + (room.size - cross_size) * 0.5
		var slots := {
			"up": Vector2i(1, 0),
			"left": Vector2i(0, 1),
			"right": Vector2i(2, 1),
			"down": Vector2i(1, 2),
		}
		for direction in DIRECTIONS:
			var slot: Vector2i = slots[direction]
			_dock_buttons[direction] = Rect2(
				origin + Vector2(float(slot.x) * (button_width + gap), float(slot.y) * (button_height + gap)),
				Vector2(button_width, button_height)
			)
	else:
		var header := 82.0
		var room := Rect2(
			_dock_rect.position + Vector2(14.0, header),
			Vector2(_dock_rect.size.x - 28.0, maxf(60.0, _dock_rect.size.y - header - 18.0))
		)
		var gap := 8.0
		var button_width := (room.size.x - gap * 3.0) / 4.0
		var button_height := minf(104.0, room.size.y)
		button_width = maxf(52.0, button_width)
		var origin := room.position + (room.size - Vector2(button_width * 4.0 + gap * 3.0, button_height)) * 0.5
		for index in DIRECTIONS.size():
			_dock_buttons[DIRECTIONS[index]] = Rect2(
				origin + Vector2(float(index) * (button_width + gap), 0.0),
				Vector2(button_width, button_height)
			)


func _cell_rect(x: int, y: int) -> Rect2:
	return Rect2(
		_grid_origin + Vector2(
			float(x) * (_cell_size + _grid_gap),
			float(y) * (_cell_size + _grid_gap)
		),
		Vector2(_cell_size, _cell_size)
	)


func _cell_center(x: int, y: int) -> Vector2:
	return _cell_rect(x, y).get_center()


func _blocked() -> bool:
	var owner := get_parent()
	while owner != null:
		if owner is NativeGameScreen:
			return owner.is_input_blocked()
		owner = owner.get_parent()
	return false


func _gui_input(event: InputEvent) -> void:
	if not interactive or _blocked():
		_cancel_pointer()
		return
	if event is InputEventScreenTouch:
		if event.device == InputEvent.DEVICE_ID_EMULATION:
			return
		_last_touch_msec = Time.get_ticks_msec()
		if event.pressed:
			_begin_pointer(event.position, event.index)
		else:
			_end_pointer(event.position, event.index, event.canceled)
		accept_event()
	elif event is InputEventScreenDrag:
		_last_touch_msec = Time.get_ticks_msec()
		_move_pointer(event.position, event.index)
		accept_event()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if Time.get_ticks_msec() - _last_touch_msec < 500:
			return
		if event.pressed:
			_begin_pointer(event.position, 0)
		else:
			_end_pointer(event.position, 0, false)
		accept_event()
	elif event is InputEventMouseMotion and _press_index == 0:
		_move_pointer(event.position, 0)
		accept_event()


func _begin_pointer(position: Vector2, pointer_index: int) -> void:
	_press_index = pointer_index
	_press_point = position
	_pressed_direction = _dock_direction_at(position)
	_swipe_origin_active = false
	_swipe_consumed = false
	if _pressed_direction.is_empty() and _board_rect.has_point(position):
		_swipe_origin = position
		_swipe_current = position
		_swipe_origin_active = true
	queue_redraw()


func _move_pointer(position: Vector2, pointer_index: int) -> void:
	if pointer_index != _press_index:
		return
	_swipe_current = position
	if _swipe_origin_active and not _swipe_consumed:
		var delta := position - _swipe_origin
		if delta.length() >= SWIPE_DISTANCE:
			var direction := ""
			if absf(delta.x) >= absf(delta.y):
				direction = "right" if delta.x > 0.0 else "left"
			else:
				direction = "down" if delta.y > 0.0 else "up"
			_swipe_consumed = true
			direction_selected.emit(direction)
	queue_redraw()


func _end_pointer(position: Vector2, pointer_index: int, canceled: bool) -> void:
	if pointer_index != _press_index:
		return
	var pressed_direction := _pressed_direction
	var was_swipe := _swipe_origin_active
	var swipe_consumed := _swipe_consumed
	_cancel_pointer()
	if canceled:
		return
	if not pressed_direction.is_empty() and _dock_direction_at(position) == pressed_direction:
		direction_selected.emit(pressed_direction)
	elif was_swipe and not swipe_consumed and _board_rect.has_point(position):
		queue_redraw()


func _cancel_pointer() -> void:
	_press_index = -1
	_pressed_direction = ""
	_swipe_origin_active = false
	_swipe_consumed = false
	queue_redraw()


func _dock_direction_at(point: Vector2) -> String:
	for direction in _dock_buttons:
		var rect: Rect2 = _dock_buttons[direction]
		if rect.has_point(point):
			return str(direction)
	return ""


func _draw() -> void:
	var font := PlaygroundUI.font()
	draw_style_box(
		_cached_style("outer", PlaygroundUI.mix(soft, Color.WHITE, 0.22), 32, PlaygroundUI.mix(accent, Color.WHITE, 0.50), 2, 9, Color(0.10, 0.07, 0.04, 0.13)),
		Rect2(Vector2.ZERO, size)
	)
	_draw_board_card(font)
	_draw_dock(font)


func _draw_board_card(font: Font) -> void:
	draw_style_box(
		_cached_style("board_card", Color("#fffaf0"), 26, PlaygroundUI.mix(accent, Color.WHITE, 0.45), 2, 5, Color(0.10, 0.07, 0.04, 0.10)),
		_board_rect
	)
	var level_number := int(state.get("levelId", 1))
	var title := "第 %s 间 · %s" % [level_number, str(level.get("title", "仓库推推乐"))]
	draw_string(font, _board_rect.position + Vector2(20, 28), title, HORIZONTAL_ALIGNMENT_LEFT, _board_rect.size.x - 300, 21, accent)
	draw_string(
		font,
		_board_rect.position + Vector2(20, 46),
		"箱子只能推，不能拉；把每只木箱送到小圆点",
		HORIZONTAL_ALIGNMENT_LEFT,
		_board_rect.size.x - 300,
		13,
		PlaygroundUI.INK_SOFT
	)
	var moves := int(state.get("moves", 0))
	var par := int(level.get("parMoves", 0))
	var goal_count := _goal_count()
	var boxes_done := _boxes_on_goals()
	var stats := "步数 %s / 标准 %s     归位 %s / %s" % [moves, par, boxes_done, goal_count]
	draw_string(font, _board_rect.position + Vector2(_board_rect.size.x - 268, 30), stats, HORIZONTAL_ALIGNMENT_RIGHT, 244, 14, accent)
	var mode_text := "一起推箱" if _is_coop() else "单人整理"
	draw_string(font, _board_rect.position + Vector2(_board_rect.size.x - 268, 47), mode_text, HORIZONTAL_ALIGNMENT_RIGHT, 244, 12, PlaygroundUI.INK_SOFT)
	draw_style_box(
		_cached_style("grid_back", PlaygroundUI.mix(accent, Color.WHITE, 0.955), 18, PlaygroundUI.mix(accent, Color.WHITE, 0.74), 1),
		Rect2(_grid_origin - Vector2(7, 7), _grid_size + Vector2(14, 14))
	)
	_draw_cells(font)
	_draw_goals()
	_draw_undo_preview()
	_draw_boxes()
	_draw_player()
	_draw_hint_arrow()
	_draw_swipe_trail()
	_draw_board_footer(font)


func _draw_cells(font: Font) -> void:
	var width := maxi(1, int(level.get("width", 1)))
	var height := maxi(1, int(level.get("height", 1)))
	var wall_keys := _wall_keys()
	for y in height:
		for x in width:
			var rect := _cell_rect(x, y)
			var cell := rect.grow(-_grid_gap * 0.45)
			var wall := wall_keys.has("%s:%s" % [x, y])
			if wall:
				_draw_wall(cell, x, y)
				continue
			var tone := 0.965 if (x + y) % 2 == 0 else 0.985
			draw_style_box(
				_cached_style("floor_%s" % tone, PlaygroundUI.mix(accent, Color.WHITE, tone), 8, Color(accent, 0.08), 1),
				cell
			)
			var line_y := cell.position.y + cell.size.y * 0.70
			draw_line(
				Vector2(cell.position.x + cell.size.x * 0.20, line_y),
				Vector2(cell.position.x + cell.size.x * 0.80, line_y),
				Color(accent, 0.08),
				maxf(1.0, _cell_size * 0.018)
			)


func _draw_wall(rect: Rect2, x: int, y: int) -> void:
	var shadow := _cached_style("wall_shadow", Color(0.22, 0.13, 0.08, 0.18), 8, Color.TRANSPARENT, 0)
	draw_style_box(shadow, Rect2(rect.position + Vector2(0, 3), rect.size))
	draw_style_box(
		_cached_style("wall_%s" % ((x + y) % 2), PlaygroundUI.mix(accent.darkened(0.10), Color.WHITE, 0.18 if (x + y) % 2 == 0 else 0.26), 8, Color("#60442d"), 2),
		rect
	)
	var inset := rect.grow(-_cell_size * 0.18)
	draw_line(inset.position + Vector2(0, inset.size.y * 0.5), inset.position + Vector2(inset.size.x, inset.size.y * 0.5), Color(1, 1, 1, 0.18), maxf(1.0, _cell_size * 0.035))
	draw_circle(inset.position + Vector2(5, 5), maxf(1.6, _cell_size * 0.028), Color(0.25, 0.15, 0.09, 0.34))
	draw_circle(inset.position + Vector2(inset.size.x - 5, 5), maxf(1.6, _cell_size * 0.028), Color(0.25, 0.15, 0.09, 0.34))


func _draw_goals() -> void:
	var font := PlaygroundUI.font()
	var goals_value: Variant = level.get("goals", [])
	if not goals_value is Array:
		return
	for raw in goals_value:
		if not raw is Dictionary:
			continue
		var x := int(raw.get("x", -1))
		var y := int(raw.get("y", -1))
		if x < 0 or y < 0:
			continue
		var center := _cell_center(x, y)
		var radius := _cell_size * 0.24
		draw_circle(center, radius + 4.0, Color(accent, 0.08))
		_draw_dashed_circle(center, radius, Color(accent, 0.62), maxf(1.6, _cell_size * 0.035))
		draw_circle(center, radius * 0.44, PlaygroundUI.mix(accent, Color.WHITE, 0.22))
		draw_circle(center + Vector2(-radius * 0.14, -radius * 0.14), radius * 0.15, Color(1, 1, 1, 0.60))
		if int(level.get("goals", []).size()) == 1:
			draw_string(font, center + Vector2(-radius * 2.0, radius * 0.72), "收货口", HORIZONTAL_ALIGNMENT_CENTER, radius * 4.0, 11, Color(accent, 0.70))


func _draw_boxes() -> void:
	var boxes_value: Variant = state.get("boxes", [])
	if not boxes_value is Array:
		return
	var goals := _goal_keys()
	for index in boxes_value.size():
		var raw: Variant = boxes_value[index]
		if not raw is Dictionary:
			continue
		var x := int(raw.get("x", -1))
		var y := int(raw.get("y", -1))
		if x < 0 or y < 0:
			continue
		var rect := _cell_rect(x, y).grow(-_cell_size * 0.14)
		var on_goal := goals.has("%s:%s" % [x, y])
		var deadlocked := int(_deadlock_box.get("x", -1)) == x and int(_deadlock_box.get("y", -1)) == y
		if on_goal:
			var pulse := 0.5 + 0.5 * sin(_clock * 3.6 + float(index))
			draw_circle(rect.get_center(), _cell_size * (0.42 + pulse * 0.025), Color("#7ca561", 0.13 + pulse * 0.05))
		var bounce := -2.0 if on_goal else 0.0
		rect.position.y += bounce
		var shadow_rect := Rect2(rect.position + Vector2(0, 4), rect.size)
		draw_style_box(_cached_style("crate_shadow", Color(0.22, 0.13, 0.07, 0.20), 11, Color.TRANSPARENT, 0), shadow_rect)
		var base := PlaygroundUI.mix(Color("#d8a56b"), Color.WHITE, 0.18 if on_goal else 0.05)
		if deadlocked:
			base = PlaygroundUI.mix(Color("#c97858"), Color.WHITE, 0.12)
		draw_style_box(
			_cached_style("crate_%s_%s" % [on_goal, deadlocked], base, 11, base.darkened(0.32), 2),
			rect
		)
		var inset := rect.grow(-rect.size.x * 0.16)
		draw_line(inset.position, inset.position + inset.size, Color(0.36, 0.20, 0.10, 0.42), maxf(2.0, _cell_size * 0.045))
		draw_line(Vector2(inset.position.x + inset.size.x, inset.position.y), Vector2(inset.position.x, inset.position.y + inset.size.y), Color(0.36, 0.20, 0.10, 0.34), maxf(1.5, _cell_size * 0.033))
		var nail := maxf(2.0, _cell_size * 0.035)
		for corner in [inset.position, Vector2(inset.position.x + inset.size.x, inset.position.y), inset.position + inset.size, Vector2(inset.position.x, inset.position.y + inset.size.y)]:
			draw_circle(corner, nail, Color("#6b492e"))
		if on_goal:
			var badge := rect.position + Vector2(rect.size.x - 10, 10)
			draw_circle(badge, _cell_size * 0.12, Color("#7ca561"))
			draw_polyline(
				PackedVector2Array([
					badge + Vector2(-_cell_size * 0.06, 0),
					badge + Vector2(-_cell_size * 0.015, _cell_size * 0.055),
					badge + Vector2(_cell_size * 0.065, -_cell_size * 0.05),
				]),
				Color.WHITE,
				maxf(2.0, _cell_size * 0.035),
				true
			)
		if deadlocked:
			var warn := rect.position + Vector2(10, 10)
			draw_circle(warn, _cell_size * 0.12, Color("#fff1dc"))
			var warn_size := maxi(12, int(_cell_size * 0.22))
			draw_string(PlaygroundUI.font(), warn + Vector2(-_cell_size * 0.12, _cell_size * 0.09), "!", HORIZONTAL_ALIGNMENT_CENTER, _cell_size * 0.24, warn_size, Color("#a44f39"))


func _draw_player() -> void:
	var player_value: Variant = state.get("player", {})
	if not player_value is Dictionary:
		return
	var x := int(player_value.get("x", -1))
	var y := int(player_value.get("y", -1))
	if x < 0 or y < 0:
		return
	var center := _cell_center(x, y)
	var tint := accent
	var players_value: Variant = state.get("players", [])
	if _is_coop() and players_value is Array and not players_value.is_empty():
		var index := clampi(int(state.get("turn", 0)), 0, players_value.size() - 1)
		if players_value[index] is Dictionary:
			tint = PlaygroundUI.color(str(players_value[index].get("color", accent.to_html(false))))
	var bob := sin(_clock * 5.0) * _cell_size * 0.014
	center.y += bob
	draw_circle(center + Vector2(0, _cell_size * 0.27), _cell_size * 0.28, Color(0.18, 0.11, 0.06, 0.16))
	var body_size := Vector2(_cell_size * 0.52, _cell_size * 0.44)
	var body := Rect2(center - body_size * 0.5 + Vector2(0, _cell_size * 0.03), body_size)
	draw_style_box(
		_cached_style("player_body_" + tint.to_html(false), PlaygroundUI.mix(tint, Color.WHITE, 0.14), 12, tint.darkened(0.34), 2),
		body
	)
	var face_center := center + Vector2(0, -_cell_size * 0.16)
	draw_circle(face_center, _cell_size * 0.22, PlaygroundUI.mix(soft, Color.WHITE, 0.42))
	draw_circle(face_center, _cell_size * 0.22, tint.darkened(0.12), false, maxf(2.0, _cell_size * 0.035))
	draw_circle(face_center + Vector2(-_cell_size * 0.075, -_cell_size * 0.02), _cell_size * 0.025, PlaygroundUI.INK)
	draw_circle(face_center + Vector2(_cell_size * 0.075, -_cell_size * 0.02), _cell_size * 0.025, PlaygroundUI.INK)
	draw_arc(face_center + Vector2(0, _cell_size * 0.015), _cell_size * 0.065, 0.18, PI - 0.18, 18, PlaygroundUI.INK, maxf(1.5, _cell_size * 0.025), true)
	var left_wheel := center + Vector2(-_cell_size * 0.19, _cell_size * 0.32)
	var right_wheel := center + Vector2(_cell_size * 0.19, _cell_size * 0.32)
	draw_circle(left_wheel, _cell_size * 0.075, Color("#5a3c27"))
	draw_circle(right_wheel, _cell_size * 0.075, Color("#5a3c27"))
	draw_circle(left_wheel, _cell_size * 0.028, Color("#f6ead9"))
	draw_circle(right_wheel, _cell_size * 0.028, Color("#f6ead9"))
	var direction := str(state.get("lastMove", ""))
	if not direction.is_empty() and _clock - _last_move_at < 0.34:
		var arrow_dir: Vector2 = DIRECTION_ARROWS.get(direction, Vector2.ZERO)
		var start := center + arrow_dir * _cell_size * 0.35
		var end := center + arrow_dir * _cell_size * 0.54
		draw_line(start, end, Color(tint, 0.74), maxf(2.0, _cell_size * 0.05), true)
		_draw_arrow_head(end, arrow_dir, maxf(5.0, _cell_size * 0.09), Color(tint, 0.74))


func _draw_undo_preview() -> void:
	if not bool(_undo_preview.get("available", false)):
		return
	var current_boxes := _box_keys_from(state.get("boxes", []))
	var previous_boxes_value: Variant = _undo_preview.get("boxes", [])
	if previous_boxes_value is Array:
		var previous_boxes := _box_keys_from(previous_boxes_value)
		for key in previous_boxes:
			if current_boxes.has(key):
				continue
			var pieces := str(key).split(":")
			if pieces.size() != 2:
				continue
			var rect := _cell_rect(int(pieces[0]), int(pieces[1])).grow(-_cell_size * 0.16)
			_draw_dashed_rect(rect, Color(accent, 0.52), maxf(1.5, _cell_size * 0.028))
	var previous_player_value: Variant = _undo_preview.get("player", {})
	if previous_player_value is Dictionary:
		var cells := Vector2i(int(previous_player_value.get("x", -1)), int(previous_player_value.get("y", -1)))
		var current := Vector2i(int(state.get("player", {}).get("x", -1)), int(state.get("player", {}).get("y", -1)))
		if cells.x >= 0 and cells.y >= 0 and cells != current:
			var center := _cell_center(cells.x, cells.y)
			_draw_dashed_circle(center, _cell_size * 0.27, Color(accent, 0.52), maxf(1.5, _cell_size * 0.028))


func _draw_hint_arrow() -> void:
	if _hint_direction.is_empty():
		return
	var player_value: Variant = state.get("player", {})
	if not player_value is Dictionary:
		return
	var center := _cell_center(int(player_value.get("x", 0)), int(player_value.get("y", 0)))
	var direction: Vector2 = DIRECTION_ARROWS.get(_hint_direction, Vector2.ZERO)
	var pulse := 0.5 + 0.5 * sin(_clock * 6.0)
	var start := center + direction * _cell_size * 0.62
	var end := center + direction * _cell_size * (0.88 + pulse * 0.06)
	draw_line(start, end, Color(accent, 0.48 + pulse * 0.28), maxf(3.0, _cell_size * 0.07), true)
	_draw_arrow_head(end, direction, maxf(7.0, _cell_size * 0.12), Color(accent, 0.58 + pulse * 0.28))


func _draw_swipe_trail() -> void:
	if not _swipe_origin_active or _swipe_current.distance_to(_swipe_origin) < 4.0:
		return
	var delta := _swipe_current - _swipe_origin
	var end := _swipe_origin + delta.limit_length(130.0)
	draw_line(_swipe_origin, end, Color(accent, 0.30), 3.0, true)
	if end.distance_to(_swipe_origin) > 22.0:
		_draw_arrow_head(end, delta.normalized(), 9.0, Color(accent, 0.42))


func _draw_board_footer(font: Font) -> void:
	var footer_y := _board_rect.position.y + _board_rect.size.y - 22.0
	var message := "左右滑动棋盘也能选方向"
	if not _deadlock_box.is_empty():
		message = "箱子卡住了，先撤回一步"
	elif bool(_undo_preview.get("available", false)):
		message = "虚线是撤销后的位置"
	draw_string(
		font,
		Vector2(_board_rect.position.x + 20.0, footer_y),
		message,
		HORIZONTAL_ALIGNMENT_LEFT,
		_board_rect.size.x - 40.0,
		13,
		Color("#ad503d") if not _deadlock_box.is_empty() else PlaygroundUI.INK_SOFT
	)


func _draw_dock(font: Font) -> void:
	draw_style_box(
		_cached_style("dock_card", PlaygroundUI.mix(soft, Color.WHITE, 0.18), 26, PlaygroundUI.mix(accent, Color.WHITE, 0.46), 2, 6, Color(0.10, 0.07, 0.04, 0.11)),
		_dock_rect
	)
	var side := _side_dock
	draw_string(font, _dock_rect.position + Vector2(18, 31), "推一推", HORIZONTAL_ALIGNMENT_LEFT, _dock_rect.size.x - 36, 23, accent)
	draw_string(font, _dock_rect.position + Vector2(18, 51), "点方向，或滑动棋盘", HORIZONTAL_ALIGNMENT_LEFT, _dock_rect.size.x - 36, 13, PlaygroundUI.INK_SOFT)
	if side:
		_draw_turn_badge(font, Rect2(_dock_rect.position + Vector2(16, 65), Vector2(_dock_rect.size.x - 32, 50)))
	else:
		_draw_turn_badge(font, Rect2(_dock_rect.position + Vector2(16, 56), Vector2(_dock_rect.size.x - 32, 30)))
	for direction in DIRECTIONS:
		if not _dock_buttons.has(direction):
			continue
		var rect: Rect2 = _dock_buttons[direction]
		var pressed: bool = direction == _pressed_direction
		var hinted: bool = direction == _hint_direction
		var enabled := interactive and str(state.get("phase", "")) == "playing"
		var fill := PlaygroundUI.mix(accent, Color.WHITE, 0.78)
		var foreground := accent
		if pressed:
			fill = PlaygroundUI.mix(accent, Color.WHITE, 0.56)
			foreground = Color.WHITE
		if hinted:
			var pulse := 0.5 + 0.5 * sin(_clock * 6.0)
			draw_style_box(
				_cached_style("hint_glow", Color(accent, 0.06 + pulse * 0.08), 20, Color(accent, 0.18 + pulse * 0.20), 2),
				rect.grow(4.0)
			)
		if not enabled:
			fill = PlaygroundUI.mix(soft, Color.WHITE, 0.52)
			foreground = Color(accent, 0.42)
		draw_style_box(
			_cached_style("dir_%s_%s_%s" % [direction, pressed, enabled], fill, 17, foreground, 2, 2, Color(0.08, 0.05, 0.03, 0.10)),
			rect
		)
		var arrow := Vector2(DIRECTION_ARROWS[direction])
		var center := rect.get_center() + Vector2(0, -3)
		var shaft_start := center - arrow * rect.size.y * 0.17
		var shaft_end := center + arrow * rect.size.y * 0.12
		draw_line(shaft_start, shaft_end, foreground, maxf(3.0, rect.size.y * 0.055), true)
		_draw_arrow_head(shaft_end, arrow, maxf(8.0, rect.size.y * 0.13), foreground)
		draw_string(
			font,
			rect.position + Vector2(4, rect.size.y - 8),
			str(DIRECTION_LABELS[direction]),
			HORIZONTAL_ALIGNMENT_CENTER,
			rect.size.x - 8,
			maxi(12, int(minf(17.0, rect.size.y * 0.23))),
			foreground
		)
	if side:
		var footer_y := _dock_rect.position.y + _dock_rect.size.y - 22.0
		var footer := "已可撤回" if bool(_undo_preview.get("available", false)) else "走错也不怕，可随时撤回"
		draw_string(font, Vector2(_dock_rect.position.x + 16, footer_y), footer, HORIZONTAL_ALIGNMENT_CENTER, _dock_rect.size.x - 32, 12, PlaygroundUI.INK_SOFT)


func _draw_turn_badge(font: Font, rect: Rect2) -> void:
	var tint := accent
	var name := "小整理员"
	var players_value: Variant = state.get("players", [])
	if _is_coop() and players_value is Array and not players_value.is_empty():
		var index := clampi(int(state.get("turn", 0)), 0, players_value.size() - 1)
		if players_value[index] is Dictionary:
			var player: Dictionary = players_value[index]
			name = str(player.get("name", "小朋友"))
			tint = PlaygroundUI.color(str(player.get("color", accent.to_html(false))))
	draw_style_box(
		_cached_style("turn_" + tint.to_html(false), PlaygroundUI.mix(tint, Color.WHITE, 0.87), 14, PlaygroundUI.mix(tint, Color.WHITE, 0.48), 1),
		rect
	)
	draw_circle(rect.position + Vector2(23, rect.size.y * 0.5), 10.0, PlaygroundUI.mix(tint, Color.WHITE, 0.2))
	draw_circle(rect.position + Vector2(20, rect.size.y * 0.5 - 3), 1.8, Color.WHITE)
	draw_circle(rect.position + Vector2(26, rect.size.y * 0.5 - 3), 1.8, Color.WHITE)
	var text := "单人推箱" if not _is_coop() else "轮到 %s" % name
	var font_size := maxi(13, int(minf(17.0, rect.size.y * 0.40)))
	draw_string(
		font,
		rect.position + Vector2(42, rect.size.y * 0.5 + font_size * 0.34),
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		rect.size.x - 50,
		font_size,
		PlaygroundUI.mix(tint, PlaygroundUI.INK, 0.22)
	)


func _draw_arrow_head(tip: Vector2, direction: Vector2, head_size: float, color: Color) -> void:
	var normal := Vector2(-direction.y, direction.x)
	var base := tip - direction * head_size
	draw_colored_polygon(
		PackedVector2Array([tip, base + normal * head_size * 0.52, base - normal * head_size * 0.52]),
		color
	)


func _draw_dashed_circle(center: Vector2, radius: float, color: Color, width: float) -> void:
	var segments := 14
	var gap_ratio := 0.42
	for index in segments:
		var start := TAU * float(index) / float(segments)
		var end := start + TAU / float(segments) * (1.0 - gap_ratio)
		draw_arc(center, radius, start, end, 5, color, width, true)


func _draw_dashed_rect(rect: Rect2, color: Color, width: float) -> void:
	var length := 10.0
	var gap := 7.0
	var sides := [
		[rect.position, rect.position + Vector2(rect.size.x, 0)],
		[rect.position + Vector2(rect.size.x, 0), rect.position + rect.size],
		[rect.position + Vector2(0, rect.size.y), rect.position + rect.size],
		[rect.position, rect.position + Vector2(0, rect.size.y)],
	]
	for side in sides:
		var start: Vector2 = side[0]
		var end: Vector2 = side[1]
		var distance := start.distance_to(end)
		if distance <= 0.01:
			continue
		var direction := (end - start).normalized()
		var cursor := 0.0
		while cursor < distance:
			var segment_end := minf(cursor + length, distance)
			draw_line(start + direction * cursor, start + direction * segment_end, color, width, true)
			cursor += length + gap


func _goal_count() -> int:
	var value: Variant = level.get("goals", [])
	return value.size() if value is Array else 0


func _boxes_on_goals() -> int:
	var goals := _goal_keys()
	var boxes_value: Variant = state.get("boxes", [])
	var count := 0
	if boxes_value is Array:
		for raw in boxes_value:
			if raw is Dictionary and goals.has("%s:%s" % [int(raw.get("x", -1)), int(raw.get("y", -1))]):
				count += 1
	return count


func _is_coop() -> bool:
	var players_value: Variant = state.get("players", [])
	return (
		str(state.get("modeId", "classic")) == "classic"
		and bool(level.get("coop", false))
		and players_value is Array
		and players_value.size() >= 2
	)


func _wall_keys() -> Dictionary:
	var result := {}
	var walls_value: Variant = level.get("walls", [])
	if walls_value is Array:
		for raw in walls_value:
			if raw is Dictionary:
				result["%s:%s" % [int(raw.get("x", -1)), int(raw.get("y", -1))]] = true
	return result


func _goal_keys() -> Dictionary:
	var result := {}
	var goals_value: Variant = level.get("goals", [])
	if goals_value is Array:
		for raw in goals_value:
			if raw is Dictionary:
				result["%s:%s" % [int(raw.get("x", -1)), int(raw.get("y", -1))]] = true
	return result


func _box_keys_from(value: Variant) -> Dictionary:
	var result := {}
	if value is Array:
		for raw in value:
			if raw is Dictionary:
				result["%s:%s" % [int(raw.get("x", -1)), int(raw.get("y", -1))]] = true
	return result


func _cached_style(
	key: String,
	fill: Color,
	radius: int,
	border: Color,
	border_width: int,
	shadow_size: int = 0,
	shadow_color: Color = Color.TRANSPARENT
) -> StyleBoxFlat:
	if _style_cache.has(key):
		return _style_cache[key]
	var style := PlaygroundUI.style(fill, radius, border, border_width, shadow_size, shadow_color)
	_style_cache[key] = style
	return style
