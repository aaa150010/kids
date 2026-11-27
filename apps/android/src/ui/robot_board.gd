class_name RobotBoard
extends Control

signal command_selected(command: String)
signal program_item_selected(index: int)

const COMMAND_ORDER := ["up", "left", "right", "down"]
const COMMAND_NAMES := {
	"up": "上",
	"down": "下",
	"left": "左",
	"right": "右",
}
const MIN_TOUCH := 44.0

var level: Dictionary = {}
var state: Dictionary = {}
var accent := Color("#4266a8")
var soft := Color("#e4eaf8")
var auto_running := false
var interactive := true

var _board_rect := Rect2()
var _tray_rect := Rect2()
var _program_rect := Rect2()
var _grid_rect := Rect2()
var _cell_size := 1.0
var _grid_origin := Vector2.ZERO
var _command_rects: Dictionary = {}
var _program_rects: Array[Rect2] = []
var _empty_program_rects: Array[Rect2] = []
var _press: Dictionary = {}
var _last_touch_msec := -1000
var _clock := 0.0


func _ready() -> void:
	custom_minimum_size = Vector2(760, 520)
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	resized.connect(_layout)
	_layout()
	set_process(false)


func configure(value: Dictionary, tint: Color, soft_tint: Color) -> void:
	level = value.duplicate(true)
	accent = tint
	soft = soft_tint
	state = {}
	interactive = true
	auto_running = false
	_press.clear()
	_layout()
	queue_redraw()


func set_state(value: Dictionary) -> void:
	state = value.duplicate(true)
	if state.get("level") is Dictionary:
		level = state.get("level").duplicate(true)
	_press.clear()
	_layout()
	queue_redraw()


func set_auto_running(value: bool) -> void:
	auto_running = value
	set_process(value)
	if not value:
		_clock = 0.0
	queue_redraw()


func set_interaction_enabled(value: bool) -> void:
	interactive = value
	if not value:
		_press.clear()
	queue_redraw()


func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_CLOSE_REQUEST]:
		_press.clear()


func _blocked() -> bool:
	var owner := get_parent()
	while owner != null:
		if owner is NativeGameScreen:
			return owner.is_input_blocked()
		owner = owner.get_parent()
	return false


func _process(delta: float) -> void:
	_clock += delta
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if not interactive or _blocked():
		return
	if event is InputEventScreenTouch:
		if event.device == InputEvent.DEVICE_ID_EMULATION:
			return
		_last_touch_msec = Time.get_ticks_msec()
		if event.pressed:
			_press_at(event.position, event.index)
		else:
			_release(event.position, event.index)
		accept_event()
	elif event is InputEventScreenDrag:
		_last_touch_msec = Time.get_ticks_msec()
		if int(_press.get("screen_index", -1)) == event.index:
			_press.clear()
		accept_event()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if Time.get_ticks_msec() - _last_touch_msec < 500:
			return
		if event.pressed:
			_press_at(event.position, 0)
		else:
			_release(event.position, 0)
		accept_event()
	elif event is InputEventMouseMotion and not _press.is_empty():
		var target := _target_at(event.position, 0)
		if not _same_target(target, _press):
			_press.clear()
			queue_redraw()
		accept_event()


func _press_at(position: Vector2, screen_index: int) -> void:
	_press = _target_at(position, screen_index)
	queue_redraw()


func _release(position: Vector2, screen_index: int) -> void:
	if _press.is_empty():
		return
	if int(_press.get("screen_index", -1)) != screen_index:
		return
	var target := _target_at(position, screen_index)
	var matched := _same_target(target, _press)
	_press.clear()
	queue_redraw()
	if not matched:
		return
	match str(target.get("kind", "")):
		"command":
			command_selected.emit(str(target.get("command", "")))
		"program":
			program_item_selected.emit(int(target.get("index", -1)))


func _same_target(first: Dictionary, second: Dictionary) -> bool:
	return str(first.get("kind", "")) == str(second.get("kind", "")) \
		and str(first.get("command", "")) == str(second.get("command", "")) \
		and int(first.get("index", -1)) == int(second.get("index", -1))


func _target_at(point: Vector2, screen_index: int) -> Dictionary:
	for command in _command_rects:
		var command_rect: Rect2 = _command_rects[command]
		if command_rect.has_point(point):
			return {"kind": "command", "command": str(command), "index": -1, "screen_index": screen_index}
	for index in _program_rects.size():
		if _program_rects[index].has_point(point):
			return {"kind": "program", "command": "", "index": index, "screen_index": screen_index}
	return {}


func _layout() -> void:
	if size.x < 1.0 or size.y < 1.0:
		return
	var margin := 12.0
	var gap := 12.0
	var program_height := clampf(size.y * 0.24, 142.0, 208.0)
	var main_height := maxf(210.0, size.y - margin * 2.0 - gap - program_height)
	var tray_width := clampf(size.x * 0.245, 220.0, 340.0)
	var board_width := maxf(300.0, size.x - margin * 2.0 - gap - tray_width)
	_board_rect = Rect2(margin, margin, board_width, main_height)
	_tray_rect = Rect2(margin + board_width + gap, margin, tray_width, main_height)
	_program_rect = Rect2(margin, margin + main_height + gap, size.x - margin * 2.0, program_height)
	_layout_grid()
	_layout_commands()
	_layout_program()


func _layout_grid() -> void:
	if not state.get("level") is Dictionary:
		return
	var width := maxi(3, int(level.get("width", 5)))
	var height := maxi(3, int(level.get("height", 5)))
	var grid_room := Rect2(
		_board_rect.position + Vector2(16.0, 48.0),
		Vector2(_board_rect.size.x - 32.0, _board_rect.size.y - 64.0)
	)
	grid_room.size.x = maxf(1.0, grid_room.size.x)
	grid_room.size.y = maxf(1.0, grid_room.size.y)
	var cell := minf(grid_room.size.x / float(width), grid_room.size.y / float(height))
	cell = maxf(20.0, cell)
	_cell_size = cell
	var grid_size := Vector2(cell * float(width), cell * float(height))
	_grid_origin = grid_room.position + (grid_room.size - grid_size) * 0.5
	_grid_rect = Rect2(_grid_origin, grid_size)


func _layout_commands() -> void:
	_command_rects.clear()
	var allowed: Array = level.get("allowedCommands", [])
	var room := Rect2(
		_tray_rect.position + Vector2(14.0, 44.0),
		Vector2(_tray_rect.size.x - 28.0, _tray_rect.size.y - 88.0)
	)
	var gap := 8.0
	var button_width := minf(92.0, maxf(MIN_TOUCH, (room.size.x - gap * 2.0) / 3.0))
	var button_height := minf(78.0, maxf(MIN_TOUCH, (room.size.y - gap * 2.0) / 3.0))
	var block := Vector2(button_width * 3.0 + gap * 2.0, button_height * 3.0 + gap * 2.0)
	var origin := room.position + (room.size - block) * 0.5
	var slots := {
		"up": Vector2(1, 0),
		"left": Vector2(0, 1),
		"right": Vector2(2, 1),
		"down": Vector2(1, 2),
	}
	for command in COMMAND_ORDER:
		if not str(command) in allowed:
			continue
		var slot: Vector2 = slots[command]
		_command_rects[command] = Rect2(
			origin + Vector2(slot.x * (button_width + gap), slot.y * (button_height + gap)),
			Vector2(button_width, button_height)
		)


func _layout_program() -> void:
	_program_rects.clear()
	_empty_program_rects.clear()
	var slot_limit := maxi(1, int(level.get("slotLimit", 8)))
	var columns := mini(slot_limit, 12)
	var rows := maxi(1, ceili(float(slot_limit) / float(columns)))
	var gap := 8.0
	var room := Rect2(
		_program_rect.position + Vector2(16.0, 42.0),
		Vector2(_program_rect.size.x - 32.0, _program_rect.size.y - 58.0)
	)
	var cell_width := (room.size.x - gap * float(columns - 1)) / float(columns)
	var cell_height := (room.size.y - gap * float(rows - 1)) / float(rows)
	cell_width = minf(104.0, maxf(MIN_TOUCH, cell_width))
	cell_height = minf(70.0, maxf(MIN_TOUCH, cell_height))
	var grid_size := Vector2(
		cell_width * float(columns) + gap * float(columns - 1),
		cell_height * float(rows) + gap * float(rows - 1)
	)
	var origin := room.position + (room.size - grid_size) * 0.5
	var program: Array = state.get("program", [])
	for index in slot_limit:
		var column := index % columns
		var row := int(index / columns)
		var rect := Rect2(
			origin + Vector2(float(column) * (cell_width + gap), float(row) * (cell_height + gap)),
			Vector2(cell_width, cell_height)
		)
		if index < program.size():
			_program_rects.append(rect)
		else:
			_empty_program_rects.append(rect)


func _draw() -> void:
	_layout()
	var font := PlaygroundUI.font()
	draw_style_box(
		PlaygroundUI.style(PlaygroundUI.mix(accent, Color.WHITE, 0.88), 30, PlaygroundUI.mix(accent, Color.WHITE, 0.42), 2, 8, Color(0.08, 0.10, 0.14, 0.12)),
		Rect2(Vector2.ZERO, size)
	)
	_draw_board_card(font)
	_draw_tray_card(font)
	_draw_program_card(font)


func _draw_board_card(font: Font) -> void:
	draw_style_box(
		PlaygroundUI.style(Color("#fffaf0"), 24, PlaygroundUI.mix(accent, Color.WHITE, 0.48), 2),
		_board_rect
	)
	var level_title := "第 %s 关 · %s" % [int(state.get("levelId", 1)), str(level.get("title", "路线小机器人"))]
	draw_string(font, _board_rect.position + Vector2(18, 29), level_title, HORIZONTAL_ALIGNMENT_LEFT, _board_rect.size.x - 36, 20, accent)
	draw_string(
		font,
		_board_rect.position + Vector2(18, 42),
		"看小旗，排好方向，再让机器人出发",
		HORIZONTAL_ALIGNMENT_LEFT,
		_board_rect.size.x - 36,
		13,
		PlaygroundUI.INK_SOFT
	)
	draw_style_box(
		PlaygroundUI.style(PlaygroundUI.mix(accent, Color.WHITE, 0.97), 18, PlaygroundUI.mix(accent, Color.WHITE, 0.68), 1),
		Rect2(_grid_rect.position - Vector2(8, 8), _grid_rect.size + Vector2(16, 16))
	)
	var width := maxi(1, int(level.get("width", 1)))
	var height := maxi(1, int(level.get("height", 1)))
	for y in height:
		for x in width:
			var rect := _cell_rect(Vector2i(x, y)).grow(-2.0)
			var shade := 0.955 if (x + y) % 2 == 0 else 0.975
			draw_rect(rect, PlaygroundUI.mix(accent, Color.WHITE, shade))
			draw_rect(rect, Color(accent, 0.08), false, 1.0)
	_draw_start(Vector2i(int(level.get("start", {}).get("x", 0)), int(level.get("start", {}).get("y", 0))))
	for wall in level.get("walls", []):
		if wall is Dictionary:
			_draw_wall(_cell(Vector2i(int(wall.get("x", 0)), int(wall.get("y", 0)))))
	_draw_stars()
	_draw_goal(_cell(Vector2i(int(level.get("goal", {}).get("x", 0)), int(level.get("goal", {}).get("y", 0)))))
	_draw_failure_mark()
	_draw_robot(_cell(Vector2i(int(state.get("robot", {}).get("x", 0)), int(state.get("robot", {}).get("y", 0)))))
	if auto_running:
		var pulse := 0.5 + 0.5 * sin(_clock * 8.0)
		draw_arc(_grid_rect.get_center(), minf(_grid_rect.size.x, _grid_rect.size.y) * 0.5 + 4.0, 0, TAU, 60, Color(accent, 0.12 + pulse * 0.10), 2.0, true)


func _draw_tray_card(font: Font) -> void:
	draw_style_box(
		PlaygroundUI.style(PlaygroundUI.mix(soft, Color.WHITE, 0.40), 24, PlaygroundUI.mix(accent, Color.WHITE, 0.52), 2),
		_tray_rect
	)
	draw_string(font, _tray_rect.position + Vector2(16, 28), "方向指令", HORIZONTAL_ALIGNMENT_LEFT, _tray_rect.size.x - 32, 19, accent)
	draw_string(font, _tray_rect.position + Vector2(16, 45), "点一下接到程序尾巴", HORIZONTAL_ALIGNMENT_LEFT, _tray_rect.size.x - 32, 13, PlaygroundUI.INK_SOFT)
	var allowed: Array = level.get("allowedCommands", [])
	for command in COMMAND_ORDER:
		if not _command_rects.has(command):
			continue
		var rect: Rect2 = _command_rects[command]
		var is_pressed := str(_press.get("kind", "")) == "command" and str(_press.get("command", "")) == str(command)
		var fill := PlaygroundUI.mix(soft, Color.WHITE, 0.18 if is_pressed else 0.62)
		draw_style_box(PlaygroundUI.style(fill, 17, accent, 2 if is_pressed else 1, 3, Color(0.08, 0.10, 0.14, 0.10)), rect)
		var arrow_center := rect.position + Vector2(rect.size.x * 0.5, rect.size.y * 0.36)
		_draw_arrow(str(command), arrow_center, minf(rect.size.x, rect.size.y) * 0.27, accent)
		draw_string(
			font,
			rect.position + Vector2(6, rect.size.y - 10),
			str(COMMAND_NAMES.get(str(command), "")),
			HORIZONTAL_ALIGNMENT_CENTER,
			rect.size.x - 12,
			18,
			PlaygroundUI.INK
		)
	if allowed.size() < COMMAND_ORDER.size():
		draw_string(
			font,
			_tray_rect.position + Vector2(14, _tray_rect.size.y - 14),
			"这一关只开放亮着的方向",
			HORIZONTAL_ALIGNMENT_LEFT,
			_tray_rect.size.x - 28,
			12,
			PlaygroundUI.INK_SOFT
		)


func _draw_program_card(font: Font) -> void:
	draw_style_box(
		PlaygroundUI.style(PlaygroundUI.mix(accent, Color.WHITE, 0.92), 24, PlaygroundUI.mix(accent, Color.WHITE, 0.50), 2),
		_program_rect
	)
	var program: Array = state.get("program", [])
	var slot_limit := int(level.get("slotLimit", program.size()))
	var collected := 0
	var stars_value: Variant = state.get("collectedStars", [])
	if stars_value is Array:
		collected = stars_value.size()
	var star_total: Variant = level.get("stars", [])
	var star_count := 0
	if star_total is Array:
		star_count = star_total.size()
	var title := "程序小火车  %s / %s" % [program.size(), slot_limit]
	if star_count > 0:
		title += "   ·   星星 %s / %s" % [collected, star_count]
	draw_string(font, _program_rect.position + Vector2(18, 26), title, HORIZONTAL_ALIGNMENT_LEFT, _program_rect.size.x - 36, 18, accent)
	draw_string(
		font,
		_program_rect.position + Vector2(18, _program_rect.size.y - 12),
		"点已经排好的指令可以删除" if not program.is_empty() else "程序还空着，先从右边选方向",
		HORIZONTAL_ALIGNMENT_LEFT,
		_program_rect.size.x - 36,
		12,
		PlaygroundUI.INK_SOFT
	)
	for index in _empty_program_rects.size():
		var rect: Rect2 = _empty_program_rects[index]
		_draw_dashed_rect(rect, Color(accent, 0.26), 1.0)
		var empty_index := program.size() + index + 1
		draw_string(
			font,
			rect.position + Vector2(5, rect.size.y * 0.5 + 6),
			str(empty_index),
			HORIZONTAL_ALIGNMENT_CENTER,
			rect.size.x - 10,
			13,
			Color(PlaygroundUI.INK_SOFT, 0.55)
		)
	var cursor := int(state.get("cursor", 0))
	for index in program.size():
		if index >= _program_rects.size():
			break
		var rect: Rect2 = _program_rects[index]
		var command := str(program[index])
		var is_next := index == cursor and str(state.get("phase", "")) != "result"
		var executed := index < cursor
		var fill := PlaygroundUI.mix(accent, Color.WHITE, 0.82)
		if executed:
			fill = PlaygroundUI.mix(accent, Color.WHITE, 0.92)
		if _is_pressed_program(index):
			fill = PlaygroundUI.mix(accent, Color.WHITE, 0.65)
		var border := accent if is_next or _is_pressed_program(index) else PlaygroundUI.mix(accent, Color.WHITE, 0.45)
		draw_style_box(PlaygroundUI.style(fill, 13, border, 2 if is_next or _is_pressed_program(index) else 1, 2, Color(0.08, 0.10, 0.14, 0.08)), rect)
		var number_center := rect.position + Vector2(14, 13)
		draw_circle(number_center, 9, accent if not executed else Color(accent, 0.55))
		draw_string(font, number_center + Vector2(-9, 5), str(index + 1), HORIZONTAL_ALIGNMENT_CENTER, 18, 11, Color.WHITE)
		var arrow_center := rect.position + Vector2(rect.size.x * 0.5, rect.size.y * 0.44)
		_draw_arrow(command, arrow_center, minf(rect.size.x, rect.size.y) * 0.22, accent if not executed else Color(accent, 0.55))
		draw_string(
			font,
			rect.position + Vector2(5, rect.size.y - 7),
			str(COMMAND_NAMES.get(command, "")),
			HORIZONTAL_ALIGNMENT_CENTER,
			rect.size.x - 10,
			14,
			PlaygroundUI.INK if not executed else PlaygroundUI.INK_SOFT
		)
		if is_next:
			draw_circle(rect.position + Vector2(rect.size.x - 11, 11), 4.0, accent)


func _is_pressed_program(index: int) -> bool:
	return str(_press.get("kind", "")) == "program" and int(_press.get("index", -1)) == index


func _cell_rect(cell: Vector2i) -> Rect2:
	return Rect2(_grid_origin + Vector2(float(cell.x), float(cell.y)) * _cell_size, Vector2(_cell_size, _cell_size))


func _cell(value: Vector2i) -> Vector2i:
	return value


func _cell_center(cell: Vector2i) -> Vector2:
	return _grid_origin + (Vector2(cell) + Vector2(0.5, 0.5)) * _cell_size


func _draw_start(cell: Vector2i) -> void:
	var center := _cell_center(cell)
	draw_circle(center, _cell_size * 0.20, Color(accent, 0.10))
	draw_arc(center, _cell_size * 0.20, 0, TAU, 28, Color(accent, 0.36), 2.0, true)
	draw_line(center + Vector2(-_cell_size * 0.10, 0), center + Vector2(_cell_size * 0.10, 0), Color(accent, 0.38), 2.0, true)
	draw_line(center + Vector2(0, -_cell_size * 0.10), center + Vector2(0, _cell_size * 0.10), Color(accent, 0.38), 2.0, true)


func _draw_wall(cell: Vector2i) -> void:
	var rect := _cell_rect(cell).grow(-_cell_size * 0.10)
	var wall_color := PlaygroundUI.mix(accent, Color("#625a54"), 0.58)
	draw_style_box(PlaygroundUI.style(wall_color, 10, PlaygroundUI.mix(wall_color, Color.BLACK, 0.28), 2, 2, Color(0.06, 0.08, 0.12, 0.14)), rect)
	var line_color := PlaygroundUI.mix(wall_color, Color.WHITE, 0.28)
	draw_line(rect.position + Vector2(6, rect.size.y * 0.5), rect.end - Vector2(6, rect.size.y * 0.5), line_color, 2.0, true)
	var offset := rect.size.x * 0.5
	draw_line(rect.position + Vector2(offset, 6), rect.position + Vector2(offset, rect.size.y * 0.5 - 3), line_color, 1.5, true)
	draw_line(rect.position + Vector2(rect.size.x * 0.3, rect.size.y * 0.5 + 3), rect.position + Vector2(rect.size.x * 0.3, rect.size.y - 6), line_color, 1.5, true)
	draw_line(rect.position + Vector2(rect.size.x * 0.7, rect.size.y * 0.5 + 3), rect.position + Vector2(rect.size.x * 0.7, rect.size.y - 6), line_color, 1.5, true)


func _draw_goal(cell: Vector2i) -> void:
	var center := _cell_center(cell)
	draw_circle(center, _cell_size * 0.37, PlaygroundUI.mix(accent, Color.WHITE, 0.82))
	draw_arc(center, _cell_size * 0.37, 0, TAU, 32, Color(accent, 0.40), 2.0, true)
	var pole_top := center + Vector2(-_cell_size * 0.15, -_cell_size * 0.34)
	var pole_bottom := center + Vector2(-_cell_size * 0.15, _cell_size * 0.24)
	draw_line(pole_bottom, pole_top, Color("#6f6257"), maxf(2.0, _cell_size * 0.035), true)
	draw_colored_polygon(
		PackedVector2Array([
			pole_top,
			pole_top + Vector2(_cell_size * 0.34, _cell_size * 0.10),
			pole_top + Vector2(0, _cell_size * 0.22),
		]),
		Color("#e0ad4d")
	)
	draw_circle(center + Vector2(_cell_size * 0.08, _cell_size * 0.20), _cell_size * 0.055, Color("#fff9df"))


func _draw_stars() -> void:
	var collected: Array = state.get("collectedStars", [])
	for entry in level.get("stars", []):
		if not entry is Dictionary:
			continue
		var cell := Vector2i(int(entry.get("x", 0)), int(entry.get("y", 0)))
		var key := "%s:%s" % [cell.x, cell.y]
		if key in collected:
			continue
		var center := _cell_center(cell)
		var radius := _cell_size * 0.17
		draw_circle(center, radius * 1.55, Color("#f6d98533"))
		_draw_star(center, radius, Color("#d7a833"))


func _draw_star(center: Vector2, radius: float, color: Color) -> void:
	var points := PackedVector2Array()
	for index in 10:
		var ring := radius if index % 2 == 0 else radius * 0.44
		var angle := -PI * 0.5 + float(index) * PI / 5.0
		points.append(center + Vector2(cos(angle), sin(angle)) * ring)
	draw_colored_polygon(points, color)
	var outline := points.duplicate()
	outline.append(points[0])
	draw_polyline(outline, Color(1, 1, 1, 0.56), 1.3, true)


func _draw_failure_mark() -> void:
	if str(state.get("phase", "")) != "retry":
		return
	var blocked_value: Variant = state.get("blockedCell", {})
	if not blocked_value is Dictionary or blocked_value.is_empty():
		return
	var cell := Vector2i(int(blocked_value.get("x", 0)), int(blocked_value.get("y", 0)))
	var width := int(level.get("width", 0))
	var height := int(level.get("height", 0))
	if cell.x < 0 or cell.y < 0 or cell.x >= width or cell.y >= height:
		return
	var rect := _cell_rect(cell).grow(-_cell_size * 0.12)
	_draw_dashed_rect(rect, Color("#b65a43"), 2.5)
	var inset := _cell_size * 0.28
	draw_line(rect.position + Vector2(inset, inset), rect.end - Vector2(inset, inset), Color("#b65a43"), 3.0, true)
	draw_line(rect.position + Vector2(rect.size.x - inset, inset), rect.position + Vector2(inset, rect.size.y - inset), Color("#b65a43"), 3.0, true)


func _draw_robot(cell: Vector2i) -> void:
	if cell.x < 0 or cell.y < 0 or cell.x >= int(level.get("width", 0)) or cell.y >= int(level.get("height", 0)):
		return
	var center := _cell_center(cell)
	var s := _cell_size
	var failed := str(state.get("phase", "")) == "retry"
	draw_circle(center + Vector2(0, s * 0.31), s * 0.28, Color(0.08, 0.10, 0.14, 0.10))
	if failed:
		draw_circle(center, s * 0.40, Color("#b65a4322"))
	var body := Rect2(center + Vector2(-s * 0.23, -s * 0.08), Vector2(s * 0.46, s * 0.34))
	draw_style_box(PlaygroundUI.style(PlaygroundUI.mix(accent, Color.WHITE, 0.18), int(maxf(5, s * 0.10)), PlaygroundUI.mix(accent, Color.BLACK, 0.20), int(maxf(1.0, s * 0.018))), body)
	var head := Rect2(center + Vector2(-s * 0.18, -s * 0.31), Vector2(s * 0.36, s * 0.25))
	draw_style_box(PlaygroundUI.style(soft, int(maxf(5, s * 0.09)), PlaygroundUI.mix(accent, Color.BLACK, 0.20), int(maxf(1.0, s * 0.018))), head)
	draw_circle(center + Vector2(-s * 0.075, -s * 0.19), maxf(1.8, s * 0.026), accent)
	draw_circle(center + Vector2(s * 0.075, -s * 0.19), maxf(1.8, s * 0.026), accent)
	draw_line(center + Vector2(-s * 0.06, -s * 0.02), center + Vector2(s * 0.06, -s * 0.02), Color(accent, 0.65), maxf(1.2, s * 0.020), true)
	draw_line(center + Vector2(0, -s * 0.31), center + Vector2(0, -s * 0.42), accent, maxf(1.5, s * 0.024), true)
	draw_circle(center + Vector2(0, -s * 0.44), maxf(2.0, s * 0.038), Color("#d7a833"))
	draw_circle(center + Vector2(-s * 0.15, s * 0.29), maxf(2.0, s * 0.052), accent)
	draw_circle(center + Vector2(s * 0.15, s * 0.29), maxf(2.0, s * 0.052), accent)
	draw_line(center + Vector2(-s * 0.23, s * 0.08), center + Vector2(-s * 0.32, s * 0.18), accent, maxf(1.5, s * 0.025), true)
	draw_line(center + Vector2(s * 0.23, s * 0.08), center + Vector2(s * 0.32, s * 0.18), accent, maxf(1.5, s * 0.025), true)


func _draw_arrow(command: String, center: Vector2, radius: float, color: Color) -> void:
	var direction := Vector2.ZERO
	match command:
		"up":
			direction = Vector2.UP
		"down":
			direction = Vector2.DOWN
		"left":
			direction = Vector2.LEFT
		"right":
			direction = Vector2.RIGHT
		_:
			return
	var tip := center + direction * radius
	var tail := center - direction * radius * 0.72
	draw_line(tail, center + direction * radius * 0.18, color, maxf(2.0, radius * 0.22), true)
	var side := direction.orthogonal() * radius * 0.54
	draw_colored_polygon(PackedVector2Array([
		tip,
		center + direction * radius * 0.12 + side,
		center + direction * radius * 0.12 - side,
	]), color)


func _draw_dashed_rect(rect: Rect2, color: Color, width: float) -> void:
	draw_dashed_line(rect.position, Vector2(rect.end.x, rect.position.y), color, width, 5.0, true)
	draw_dashed_line(Vector2(rect.end.x, rect.position.y), rect.end, color, width, 5.0, true)
	draw_dashed_line(rect.end, Vector2(rect.position.x, rect.end.y), color, width, 5.0, true)
	draw_dashed_line(Vector2(rect.position.x, rect.end.y), rect.position, color, width, 5.0, true)
