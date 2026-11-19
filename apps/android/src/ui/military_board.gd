class_name MilitaryBoard
extends Control

signal cell_pressed(position: int)

var rules: MilitaryRules
var current_side := 0
var reveal_all := true
var selected := -1
var targets: Array = []
var interactive := true
var accent := Color("#5b63b2")
var _touch_index := -1


func _ready() -> void:
	custom_minimum_size = Vector2(760, 380)
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	resized.connect(queue_redraw)


func update_board(value: MilitaryRules, side: int, selected_position: int, legal: Array, reveal: bool) -> void:
	rules = value
	current_side = side
	selected = selected_position
	targets = legal.duplicate()
	reveal_all = reveal
	queue_redraw()


func metrics() -> Dictionary:
	var side_margin := clampf(size.x * 0.035, 32.0, 64.0)
	var gap_x := maxf(1.0, (size.x - side_margin * 2.0) / 12.0)
	var gap_y := maxf(1.0, minf((size.y - 48.0) / 4.0, gap_x * 1.55))
	var extent := Vector2(12.0 * gap_x, 4.0 * gap_y)
	var origin := (size - extent) * 0.5
	return {"gap_x": gap_x, "gap_y": gap_y, "origin": origin}


func position_for(index: int) -> Vector2:
	var layout := metrics()
	var row := int(index / MilitaryRules.COLS)
	var col := index % MilitaryRules.COLS
	return layout.origin + Vector2(float(row) * float(layout.gap_x), float(col) * float(layout.gap_y))


func cell_at(point: Vector2) -> int:
	var layout := metrics()
	var gap_x := float(layout.gap_x)
	var gap_y := float(layout.gap_y)
	if gap_x <= 0 or gap_y <= 0:
		return -1
	var local: Vector2 = point - layout.origin
	var row := roundi(local.x / gap_x)
	var col := roundi(local.y / gap_y)
	if row < 0 or row >= MilitaryRules.ROWS or col < 0 or col >= MilitaryRules.COLS or row == MilitaryRules.MIDLINE:
		return -1
	var index := row * MilitaryRules.COLS + col
	if absf(local.x - float(row) * gap_x) > gap_x * 0.46 or absf(local.y - float(col) * gap_y) > gap_y * 0.46:
		return -1
	if point.distance_to(position_for(index)) <= minf(gap_x, gap_y) * 0.70:
		return index
	return -1


func _draw() -> void:
	var layout := metrics()
	var gap_x := float(layout.gap_x)
	var gap_y := float(layout.gap_y)
	var unit := minf(gap_x, gap_y)
	if gap_x <= 0 or gap_y <= 0:
		return
	draw_style_box(PlaygroundUI.style(Color("#e9e1cf"), 28, Color("#8d7a62"), 3, 8, Color(0, 0, 0, 0.12)), Rect2(Vector2.ZERO, size))
	_draw_roads(unit)
	for index in MilitaryRules.CELLS:
		if int(index / MilitaryRules.COLS) == MilitaryRules.MIDLINE:
			continue
		var center := position_for(index)
		var cell := Rect2(center - Vector2(gap_x * 0.42, gap_y * 0.42), Vector2(gap_x * 0.84, gap_y * 0.84))
		var background := Color("#f6f0df")
		var border := Color("#b9a98e")
		if index in MilitaryRules.CAMPS:
			background = Color("#fff0b7")
			border = Color("#c8a34a")
		if index in MilitaryRules.HEADQUARTERS:
			background = Color("#f7d6c6")
			border = Color("#b96d55")
		draw_style_box(PlaygroundUI.style(background, 14, border, 1), cell)
		if index in MilitaryRules.CAMPS:
			_text("行营", center + Vector2(0, unit * 0.02), unit * 0.18, Color("#9b7927"))
		if index in MilitaryRules.HEADQUARTERS:
			_text("大本营", center + Vector2(0, unit * 0.02), unit * 0.16, Color("#a04e3d"))
		if index in targets:
			draw_circle(center, unit * 0.24, Color(0.35, 0.68, 0.38, 0.30))
			draw_arc(center, unit * 0.38, 0, TAU, 32, Color(0.25, 0.58, 0.32, 0.82), 4.0, true)
	if rules != null and not rules.state.get("lastMove", {}).is_empty():
		var last: Dictionary = rules.state.lastMove
		if last.has("from") and last.has("to"):
			draw_line(position_for(int(last.from)), position_for(int(last.to)), Color(0.9, 0.65, 0.2, 0.35), maxf(2.0, unit * 0.05), true)
	var pieces: Array = rules.state.get("pieces", []) if rules != null else []
	for piece in pieces:
		_draw_piece(piece, gap_x, gap_y)
	if rules != null and rules.state.get("phase", "") == "finished":
		var panel := Rect2(size.x * 0.26, size.y * 0.43, size.x * 0.48, size.y * 0.14)
		draw_style_box(PlaygroundUI.style(Color("#fff9e9"), 22, accent, 2, 6, Color(0, 0, 0, 0.15)), panel)
		_text(str(rules.state.get("reason", "本局结束")), panel.get_center(), unit * 0.22, PlaygroundUI.INK)


func _draw_roads(gap: float) -> void:
	var drawn := {}
	if rules != null:
		rules._ensure_rails()
		for source in rules.rails:
			for target in rules.rails[source]:
				var first := mini(int(source), int(target))
				var second := maxi(int(source), int(target))
				var key := "%s:%s" % [first, second]
				if drawn.has(key):
					continue
				drawn[key] = true
				draw_line(position_for(first), position_for(second), Color("#596b9b"), maxf(4.0, gap * 0.075), true)
				draw_line(position_for(first), position_for(second), Color(1, 1, 1, 0.38), maxf(1.0, gap * 0.018), true)
	for row in MilitaryRules.ROWS:
		for col in MilitaryRules.COLS:
			if row == MilitaryRules.MIDLINE:
				continue
			var index := row * MilitaryRules.COLS + col
			for offset in [Vector2i(0, 1), Vector2i(1, 0)]:
				var next_row: int = row + int(offset.x)
				var next_col: int = col + int(offset.y)
				if next_row < 0 or next_row >= MilitaryRules.ROWS or next_col < 0 or next_col >= MilitaryRules.COLS or next_row == MilitaryRules.MIDLINE:
					continue
				var target: int = next_row * MilitaryRules.COLS + next_col
				var key := "%s:%s" % [mini(index, target), maxi(index, target)]
				if drawn.has(key):
					continue
				drawn[key] = true
				draw_line(position_for(index), position_for(target), Color("#bfae91"), maxf(1.5, gap * 0.025), true)


func _draw_piece(piece: Dictionary, gap_x: float, gap_y: float) -> void:
	var index := int(piece.get("position", -1))
	var center := position_for(index)
	var grid_top := position_for(0).y - gap_y * 0.5
	var grid_bottom := position_for(4).y + gap_y * 0.5
	if center.y < grid_top or center.y > grid_bottom:
		return
	var side := int(piece.get("side", 0))
	var own := side == current_side
	var face_up := reveal_all or own
	var selected_piece := index == selected
	var unit := minf(gap_x, gap_y)
	var box_w := gap_x * 0.78
	var box_h := minf(gap_y * 0.84, gap_x * 1.20)
	if selected_piece:
		draw_circle(center + Vector2(0, box_h * 0.06), unit * 0.41, Color(0, 0, 0, 0.15))
		draw_circle(center, unit * 0.47, Color(0.95, 0.75, 0.25, 0.20))
		draw_arc(center, unit * 0.45, 0, TAU, 40, Color("#e4ac28"), 4.0, true)
	var tint := Color("#c95248") if side == 0 else Color("#3f72b8")
	var rect := Rect2(center - Vector2(box_w * 0.5, box_h * 0.5), Vector2(box_w, box_h))
	if not face_up:
		draw_style_box(PlaygroundUI.style(Color("#515b91"), 16, Color("#303966"), 3, 4, Color(0, 0, 0, 0.15)), rect)
		_text("?", center, unit * 0.36, Color("#fff5d4"))
		return
	draw_style_box(PlaygroundUI.style(Color("#fffdf6"), 15, tint, 3, 4, Color(0, 0, 0, 0.14)), rect)
	var band := Rect2(rect.position + Vector2(unit * 0.05, unit * 0.04), Vector2(rect.size.x - unit * 0.10, unit * 0.06))
	draw_style_box(PlaygroundUI.style(tint, 6, tint, 0), band)
	_draw_side_badge(rect, side, unit, tint)
	var kind := str(piece.get("kind", ""))
	_draw_kind_icon(kind, center + Vector2(0, -box_h * 0.09), unit * 0.42, tint)
	_text(str(MilitaryRules.NAMES.get(kind, "棋子")), center + Vector2(0, box_h * 0.34), unit * 0.18, tint)


func _draw_side_badge(rect: Rect2, side: int, gap: float, tint: Color) -> void:
	var center := Vector2(rect.end.x - gap * 0.12, rect.position.y + gap * 0.12)
	draw_circle(center, gap * 0.10, tint)
	if side == 0:
		draw_circle(center, gap * 0.055, Color.WHITE)
	else:
		_draw_diamond(center, gap * 0.06, Color.WHITE)


func _draw_kind_icon(kind: String, center: Vector2, size: float, tint: Color) -> void:
	match kind:
		"flag":
			_draw_flag_icon(center, size * 0.80, tint)
		"mine":
			_draw_mine_icon(center, size * 0.80, tint)
		"bomb":
			_draw_bomb_icon(center, size * 0.80, tint)
		"engineer":
			_draw_engineer_icon(center, size * 0.80, tint)
		_:
			_draw_rank_insignia(kind, center, size, tint)


func _draw_rank_insignia(kind: String, center: Vector2, size: float, tint: Color) -> void:
	var rank := int(MilitaryRules.RANKS.get(kind, 0))
	if rank <= 0:
		return
	var stripe_count := int(ceil(float(rank) / 3.0))
	_text(str(rank), center + Vector2(0, -size * 0.12), size * 0.52, tint)
	var bar_width := size * 1.15
	var bar_height := maxf(2.0, size * 0.11)
	for row in stripe_count:
		var y := center.y + size * 0.02 + float(row) * size * 0.23
		draw_rect(Rect2(center.x - bar_width * 0.5, y - bar_height * 0.5, bar_width, bar_height), tint)


func _draw_diamond(center: Vector2, radius: float, color: Color) -> void:
	draw_colored_polygon(PackedVector2Array([
		center + Vector2(0, -radius),
		center + Vector2(radius, 0),
		center + Vector2(0, radius),
		center + Vector2(-radius, 0),
	]), color)


func _draw_flag_icon(center: Vector2, size: float, tint: Color) -> void:
	draw_line(center + Vector2(-size * 0.42, size * 0.62), center + Vector2(-size * 0.42, -size * 0.62), tint, maxf(2.0, size * 0.14), true)
	var flag := PackedVector2Array([
		center + Vector2(-size * 0.42, -size * 0.56),
		center + Vector2(size * 0.56, -size * 0.34),
		center + Vector2(-size * 0.42, -size * 0.02),
	])
	draw_colored_polygon(flag, tint)


func _draw_bomb_icon(center: Vector2, size: float, tint: Color) -> void:
	draw_circle(center + Vector2(0, size * 0.12), size * 0.52, tint)
	draw_line(center + Vector2(size * 0.20, -size * 0.40), center + Vector2(size * 0.50, -size * 0.70), tint, maxf(2.0, size * 0.12), true)
	draw_circle(center + Vector2(size * 0.54, -size * 0.74), size * 0.12, Color("#e4ac28"))


func _draw_mine_icon(center: Vector2, size: float, tint: Color) -> void:
	draw_circle(center, size * 0.38, tint)
	for index in 8:
		var angle := float(index) * TAU / 8.0
		var direction := Vector2(cos(angle), sin(angle))
		draw_line(center + direction * size * 0.40, center + direction * size * 0.70, tint, maxf(2.0, size * 0.10), true)
	draw_circle(center, size * 0.15, Color("#fffdf6"))


func _draw_engineer_icon(center: Vector2, size: float, tint: Color) -> void:
	var width := maxf(3.0, size * 0.17)
	var start := center + Vector2(-size * 0.56, size * 0.56)
	var end := center + Vector2(size * 0.38, -size * 0.38)
	draw_line(start, end, tint, width, true)
	draw_circle(start, size * 0.18, tint)
	draw_line(end + Vector2(-size * 0.18, size * 0.02), end + Vector2(size * 0.12, -size * 0.18), tint, width, true)
	draw_line(end + Vector2(size * 0.02, size * 0.18), end + Vector2(size * 0.12, -size * 0.18), tint, width, true)


func _text(value: String, center: Vector2, font_size: float, tint: Color) -> void:
	var pixels := maxi(12, int(font_size))
	var font := PlaygroundUI.font()
	var width := font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, pixels).x
	draw_string(font, center + Vector2(-width * 0.5, pixels * 0.35), value, HORIZONTAL_ALIGNMENT_LEFT, -1, pixels, tint)


func _gui_input(event: InputEvent) -> void:
	if not interactive:
		return
	var position := Vector2.ZERO
	var pressed := false
	if event is InputEventScreenTouch:
		if event.index != _touch_index and not event.pressed:
			return
		if event.pressed:
			_touch_index = event.index
		else:
			_touch_index = -1
		position = event.position
		pressed = event.pressed
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		position = event.position
		pressed = event.pressed
	else:
		return
	if not pressed:
		return
	var index := cell_at(position)
	if index >= 0:
		cell_pressed.emit(index)
		accept_event()
