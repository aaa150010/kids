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
var face_to_face := false
var _touch_index := -1
var _touch_guard_msec := -1000
var _clock := 0.0

const BOARD_BG := Color("#0d1a13")
const BOARD_SURFACE := Color("#182a20")
const BOARD_CELL := Color("#20362a")
const BOARD_CELL_BORDER := Color(0.55, 0.58, 0.46, 0.32)
const BOARD_BRASS := Color("#c2a767")
const BOARD_BRASS_SOFT := Color(0.76, 0.66, 0.42, 0.42)
const TOKEN_PAPER := Color("#f3ead6")
const TOKEN_INK := Color("#24271f")
const TOKEN_RED := Color("#b43a33")
const TOKEN_BLUE := Color("#326d9d")


func _ready() -> void:
	custom_minimum_size = Vector2(760, 380)
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	resized.connect(queue_redraw)


func update_board(value: MilitaryRules, side: int, selected_position: int, legal: Array, reveal: bool) -> void:
	rules = value
	face_to_face = TabletopLayout.enabled("military", value.state.get("players", []), str(value.state.get("modeId", "classic")))
	current_side = side
	selected = selected_position
	targets = legal.duplicate()
	reveal_all = reveal
	set_process(selected >= 0)
	queue_redraw()


func _process(delta: float) -> void:
	_clock += delta
	queue_redraw()


func _pulse() -> float:
	return 0.5 + 0.5 * sin(_clock * 3.4)


func metrics() -> Dictionary:
	var gap_x := maxf(1.0, (size.x - 24.0) / 13.0)
	var gap_y := maxf(1.0, (size.y - 24.0) / 5.0)
	var extent := Vector2(12.0 * gap_x, 4.0 * gap_y)
	var origin := (size - extent) * 0.5
	return {"gap_x": gap_x, "gap_y": gap_y, "origin": origin}


func audit_bounds() -> Rect2:
	var layout := metrics()
	var gap := Vector2(float(layout.gap_x), float(layout.gap_y))
	return Rect2(Vector2(layout.origin) - gap * 0.44, Vector2(12, 4) * gap + gap * 0.88)


func is_blank_at(point: Vector2) -> bool:
	return cell_at(point) < 0


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
	return index


func _draw() -> void:
	var layout := metrics()
	var gap_x := float(layout.gap_x)
	var gap_y := float(layout.gap_y)
	var unit := minf(gap_x, gap_y)
	if gap_x <= 0 or gap_y <= 0:
		return
	_draw_board_frame()
	_draw_roads(unit)
	for index in MilitaryRules.CELLS:
		if int(index / MilitaryRules.COLS) == MilitaryRules.MIDLINE:
			continue
		var center := position_for(index)
		var cell := Rect2(center - Vector2(gap_x * 0.42, gap_y * 0.42), Vector2(gap_x * 0.84, gap_y * 0.84))
		var background := BOARD_CELL
		var border := BOARD_CELL_BORDER
		if index in MilitaryRules.CAMPS:
			background = Color("#3f4b31")
			border = BOARD_BRASS_SOFT
		if index in MilitaryRules.HEADQUARTERS:
			var hq_side := 0 if int(index / MilitaryRules.COLS) < MilitaryRules.MIDLINE else 1
			var hq_tint := TOKEN_RED if hq_side == 0 else TOKEN_BLUE
			background = PlaygroundUI.mix(BOARD_CELL, hq_tint, 0.22)
			border = Color(hq_tint.r, hq_tint.g, hq_tint.b, 0.50)
		draw_style_box(PlaygroundUI.style(background, 12, border, 1), cell)
		if index in MilitaryRules.CAMPS:
			_draw_place_name("行营", index, center, unit * 0.19, Color("#d5bb7b"))
		if index in MilitaryRules.HEADQUARTERS:
			_draw_place_name("大本营", index, center, unit * 0.17, Color("#e0c48c"))
	if rules != null and not rules.state.get("lastMove", {}).is_empty():
		var last: Dictionary = rules.state.lastMove
		if last.has("from") and last.has("to"):
			draw_line(position_for(int(last.from)), position_for(int(last.to)), Color(0.95, 0.76, 0.35, 0.45), maxf(3.0, unit * 0.055), true)
	var pieces: Array = rules.state.get("pieces", []) if rules != null else []
	for piece in pieces:
		_draw_piece(piece, gap_x, gap_y)
	_draw_move_hints(gap_x, gap_y)
	if rules != null and rules.state.get("phase", "") == "finished":
		var panel := Rect2(size.x * 0.26, size.y * 0.43, size.x * 0.48, size.y * 0.14)
		draw_style_box(PlaygroundUI.style(Color("#f3ead6"), 22, BOARD_BRASS, 2, 6, Color(0, 0, 0, 0.35)), panel)
		_text(str(rules.state.get("reason", "本局结束")), panel.get_center(), unit * 0.22, TOKEN_INK)


func _draw_board_frame() -> void:
	draw_style_box(PlaygroundUI.style(BOARD_BG, 30, Color("#314536"), 2, 8, Color(0, 0, 0, 0.24)), Rect2(Vector2.ZERO, size))
	var inner := Rect2(Vector2(8, 8), size - Vector2(16, 16))
	draw_style_box(PlaygroundUI.style(BOARD_SURFACE, 24, BOARD_BRASS_SOFT, 1), inner)
	var field := Rect2(Vector2(14, 14), size - Vector2(28, 28))
	draw_style_box(PlaygroundUI.style(Color("#15261d"), 20, Color(0.72, 0.61, 0.37, 0.22), 1), field)
	var center := size * 0.5
	for index in 3:
		draw_arc(center, float(index + 1) * minf(size.x, size.y) * 0.115, 0, TAU, 80, Color(0.75, 0.64, 0.40, 0.055), 1.0, true)
	var midline_x := position_for(MilitaryRules.MIDLINE * MilitaryRules.COLS).x
	draw_rect(Rect2(midline_x - 3.0, 16.0, 6.0, size.y - 32.0), Color(0.08, 0.15, 0.11, 0.38))
	draw_line(Vector2(midline_x, 18.0), Vector2(midline_x, size.y - 18.0), Color(0.76, 0.66, 0.42, 0.16), 1.0)


func _draw_place_name(value: String, index: int, center: Vector2, font_size: float, tint: Color) -> void:
	var side := 0 if int(index / MilitaryRules.COLS) < MilitaryRules.MIDLINE else 1
	draw_set_transform(center, TabletopLayout.facing_angle(side, face_to_face), Vector2.ONE)
	_text(value, Vector2.ZERO, font_size, tint)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


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
				draw_line(position_for(first), position_for(second), Color("#0b1510"), maxf(5.0, gap * 0.080), true)
				draw_line(position_for(first), position_for(second), Color("#b49a5b"), maxf(2.0, gap * 0.030), true)
				draw_line(position_for(first), position_for(second), Color(1, 0.95, 0.77, 0.30), maxf(0.8, gap * 0.011), true)
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
				draw_line(position_for(index), position_for(target), Color(0.58, 0.58, 0.45, 0.44), maxf(1.2, gap * 0.020), true)


func _draw_piece(piece: Dictionary, gap_x: float, gap_y: float) -> void:
	var index := int(piece.get("position", -1))
	if index < 0 or index >= MilitaryRules.CELLS:
		return
	var center := position_for(index)
	var side := int(piece.get("side", 0))
	var card_size := Vector2.ZERO
	if face_to_face:
		card_size.x = minf(gap_y * 0.82, gap_x * 1.30)
		card_size.y = card_size.x / 1.48
	else:
		card_size.x = minf(gap_x * 0.80, gap_y * 0.62)
		card_size.y = minf(gap_y * 0.82, card_size.x * 1.52)
	var tint := TOKEN_RED if side == 0 else TOKEN_BLUE
	draw_set_transform(center, TabletopLayout.facing_angle(side, face_to_face), Vector2.ONE)
	var rect := Rect2(-card_size * 0.5, card_size)
	_draw_token(piece, rect, side, tint)
	if index == selected:
		draw_style_box(PlaygroundUI.style(Color(0, 0, 0, 0.0), 15, Color("#e5bf5c"), 4, 3, Color(0, 0, 0, 0.24)), rect.grow(5.0))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_token(piece: Dictionary, rect: Rect2, side: int, tint: Color) -> void:
	var kind := str(piece.get("kind", ""))
	var special := kind in ["flag", "mine", "bomb"]
	var band_h := clampf(minf(rect.size.x, rect.size.y) * 0.22, 12.0, 30.0)
	draw_style_box(PlaygroundUI.style(Color(0, 0, 0, 0.34), 13, Color.TRANSPARENT, 0, 5, Color(0, 0, 0, 0.20)), Rect2(rect.position + Vector2(2.0, 5.0), rect.size))
	draw_style_box(PlaygroundUI.style(TOKEN_PAPER, 13, tint, 3), rect)
	var band_rect := Rect2(rect.position, Vector2(rect.size.x, band_h + 8.0))
	draw_style_box(PlaygroundUI.style(tint, 11, tint, 0), band_rect)
	_draw_band_pattern(rect, band_h, tint)
	var paper_rect := Rect2(rect.position + Vector2(3.0, band_h), Vector2(rect.size.x - 6.0, rect.size.y - band_h - 3.0))
	draw_style_box(PlaygroundUI.style(TOKEN_PAPER, 8, Color(0.70, 0.61, 0.43, 0.58), 1), paper_rect)
	draw_line(
		Vector2(rect.position.x + 4.0, paper_rect.position.y),
		Vector2(rect.end.x - 4.0, paper_rect.position.y),
		Color(0.78, 0.65, 0.37, 0.75),
		maxf(1.0, band_h * 0.06),
		true
	)
	var rank := int(MilitaryRules.RANKS.get(kind, 0))
	var force_code := "R" if side == 0 else "B"
	var rank_code := "特" if special else "%02d" % rank
	var serial := force_code + " · " + rank_code
	_text_left(serial, Vector2(rect.position.x + band_h * 0.48, rect.position.y + band_h * 0.52), minf(band_h * 0.52, rect.size.x * 0.13), Color("#fff5e1"))
	_draw_team_mark(Vector2(rect.end.x - band_h * 0.54, rect.position.y + band_h * 0.52), band_h * 0.28, side)
	var main_top := paper_rect.position.y + 2.0
	var main_h := paper_rect.size.y - 4.0
	var landscape := rect.size.x > rect.size.y * 1.16
	if special:
		_draw_special_token(kind, rect, main_top, main_h, landscape, tint)
	else:
		_draw_rank_token(kind, rank, rect, main_top, main_h, landscape, tint)
	draw_style_box(PlaygroundUI.style(Color(0, 0, 0, 0.0), 13, Color(tint.r, tint.g, tint.b, 0.78), 2), rect)
	draw_style_box(PlaygroundUI.style(Color(0, 0, 0, 0.0), 9, Color(0.80, 0.72, 0.55, 0.50), 1), paper_rect)


func _draw_rank_token(kind: String, rank: int, rect: Rect2, main_top: float, main_h: float, landscape: bool, tint: Color) -> void:
	var name := str(MilitaryRules.NAMES.get(kind, "棋子"))
	var number_text := "%02d" % rank
	if landscape:
		var number_size := clampf(main_h * 0.54, 18.0, 52.0)
		var name_size := clampf(main_h * 0.40, 15.0, 38.0)
		_text(number_text, Vector2(rect.position.x + rect.size.x * 0.13, main_top + main_h * 0.40), number_size, tint)
		_text(name, Vector2(rect.position.x + rect.size.x * 0.49, main_top + main_h * 0.42), name_size, TOKEN_INK)
		_draw_emblem(kind, Vector2(rect.position.x + rect.size.x * 0.84, main_top + main_h * 0.66), main_h * 0.22, tint)
	else:
		var number_size := clampf(main_h * 0.32, 18.0, 44.0)
		var name_size := clampf(main_h * 0.20, 15.0, 32.0)
		_text(number_text, Vector2(rect.position.x + rect.size.x * 0.27, main_top + main_h * 0.18), number_size, tint)
		_text(name, Vector2(rect.get_center().x, main_top + main_h * 0.51), name_size, TOKEN_INK)
		_draw_emblem(kind, Vector2(rect.get_center().x, main_top + main_h * 0.80), main_h * 0.14, tint)
	_draw_rank_ticks(rect, main_top, main_h, rank, tint)


func _draw_special_token(kind: String, rect: Rect2, main_top: float, main_h: float, landscape: bool, tint: Color) -> void:
	var name := str(MilitaryRules.NAMES.get(kind, "棋子"))
	var stamp_size := clampf(minf(rect.size.x * 0.24, main_h * 0.42), 16.0, 34.0)
	var stamp_center: Vector2 = Vector2(rect.position.x + rect.size.x * 0.17, main_top + main_h * 0.48) if landscape else Vector2(rect.position.x + rect.size.x * 0.26, main_top + main_h * 0.22)
	var stamp_rect := Rect2(stamp_center - Vector2.ONE * stamp_size * 0.5, Vector2.ONE * stamp_size)
	draw_style_box(PlaygroundUI.style(Color(0, 0, 0, 0.0), 3, tint, 2), stamp_rect)
	_text("特", stamp_center, stamp_size * 0.72, tint)
	if landscape:
		_text(name, Vector2(rect.position.x + rect.size.x * 0.51, main_top + main_h * 0.42), clampf(main_h * 0.38, 15.0, 38.0), TOKEN_INK)
		_draw_emblem(kind, Vector2(rect.position.x + rect.size.x * 0.84, main_top + main_h * 0.68), main_h * 0.20, tint)
	else:
		_text(name, Vector2(rect.get_center().x, main_top + main_h * 0.49), clampf(main_h * 0.20, 15.0, 32.0), TOKEN_INK)
		_draw_emblem(kind, Vector2(rect.get_center().x, main_top + main_h * 0.78), main_h * 0.13, tint)
	_draw_special_marks(rect, main_top, main_h)


func _draw_band_pattern(rect: Rect2, band_h: float, tint: Color) -> void:
	draw_rect(
		Rect2(
			rect.position.x + band_h * 0.36,
			rect.position.y + band_h * 0.20,
			rect.size.x - band_h * 0.72,
			maxf(1.0, band_h * 0.035)
		),
		Color(1, 1, 1, 0.12)
	)
	draw_line(rect.position + Vector2(0, band_h + 2.0), Vector2(rect.end.x, rect.position.y + band_h + 2.0), Color(tint.r * 0.62, tint.g * 0.62, tint.b * 0.62, 0.55), 1.0)


func _draw_team_mark(center: Vector2, radius: float, side: int) -> void:
	draw_circle(center, radius, Color("#f7f0df"))
	if side == 0:
		draw_circle(center, radius * 0.53, TOKEN_RED)
	else:
		_draw_diamond(center, radius * 0.64, TOKEN_BLUE)


func _draw_rank_ticks(rect: Rect2, main_top: float, main_h: float, rank: int, tint: Color) -> void:
	var tick_h := maxf(1.4, main_h * 0.033)
	var tick_gap := maxf(0.9, main_h * 0.017)
	var total := tick_h * 9.0 + tick_gap * 8.0
	var start_y := main_top + (main_h - total) * 0.5
	var tick_x := rect.end.x - maxf(3.0, rect.size.x * 0.036)
	for index in 9:
		var y := start_y + float(index) * (tick_h + tick_gap)
		var color: Color = tint if index < rank else Color(0.48, 0.43, 0.32, 0.30)
		draw_rect(Rect2(tick_x, y, maxf(1.4, rect.size.x * 0.018), tick_h), color)


func _draw_special_marks(rect: Rect2, main_top: float, main_h: float) -> void:
	for index in 3:
		var center := Vector2(rect.end.x - maxf(4.0, rect.size.x * 0.045), main_top + main_h * (0.30 + float(index) * 0.20))
		_draw_diamond(center, maxf(2.0, main_h * 0.035), BOARD_BRASS)


func _draw_emblem(kind: String, center: Vector2, radius: float, tint: Color) -> void:
	draw_arc(center, radius, 0, TAU, 32, Color(tint.r, tint.g, tint.b, 0.55), maxf(1.0, radius * 0.055), true)
	draw_arc(center, radius * 0.72, 0, TAU, 32, Color(tint.r, tint.g, tint.b, 0.24), 1.0, true)
	for index in 8:
		var angle := float(index) * TAU / 8.0
		var direction := Vector2(cos(angle), sin(angle))
		var length := 0.92 if index % 2 == 0 else 0.64
		draw_line(center + direction * radius * 0.22, center + direction * radius * length, Color(tint.r, tint.g, tint.b, 0.40), maxf(0.9, radius * 0.040), true)
	draw_circle(center, maxf(1.2, radius * 0.07), tint)
	match kind:
		"flag":
			_draw_flag_icon(center, radius * 0.74, tint)
		"mine":
			_draw_mine_icon(center, radius * 0.56, tint)
		"bomb":
			_draw_bomb_icon(center, radius * 0.52, tint)
		"engineer":
			_draw_engineer_icon(center, radius * 0.64, tint)
		_:
			draw_star(center, maxf(1.8, radius * 0.17), tint)


func _draw_move_hints(gap_x: float, gap_y: float) -> void:
	if rules == null or selected < 0 or targets.is_empty():
		return
	var piece := rules.piece_at(selected)
	if piece.is_empty():
		return
	var unit := minf(gap_x, gap_y)
	var pulse := _pulse()
	var start := position_for(selected)
	var route := Color(0.82, 0.69, 0.38, 0.42)
	var selected_radius := maxf(unit * 0.52, gap_y * 0.42)
	draw_arc(start, selected_radius + unit * 0.035 * pulse, 0, TAU, 44, Color("#e5c268"), 4.0, true)
	var kind := str(piece.get("kind", ""))
	for value in targets:
		var target := int(value)
		var finish := position_for(target)
		if kind == "engineer":
			var path: Array = rules._rail_path(selected, target)
			if path.size() < 2:
				draw_line(start, finish, route, maxf(2.0, unit * 0.035), true)
			else:
				for index in path.size() - 1:
					draw_line(position_for(int(path[index])), position_for(int(path[index + 1])), route, maxf(2.0, unit * 0.035), true)
		else:
			draw_line(start, finish, route, maxf(2.0, unit * 0.035), true)
		var captured := not rules.piece_at(target).is_empty()
		if captured:
			var radius := maxf(unit * 0.46, gap_y * 0.38) + unit * 0.025 * pulse
			draw_circle(finish, radius, Color(0.88, 0.28, 0.22, 0.10))
			draw_arc(finish, radius, 0, TAU, 36, Color("#e04b3f"), maxf(3.0, unit * 0.045), true)
			draw_circle(finish + Vector2(0, -radius), unit * 0.07, Color("#e04b3f"))
		else:
			draw_circle(finish, unit * (0.24 + 0.025 * pulse), Color(0.88, 0.28, 0.22, 0.16))
			draw_circle(finish, unit * (0.115 + 0.01 * pulse), Color("#e04b3f"))
			draw_circle(finish, unit * 0.04, Color("#fff7df"))


func _draw_diamond(center: Vector2, radius: float, color: Color) -> void:
	draw_colored_polygon(PackedVector2Array([
		center + Vector2(0, -radius),
		center + Vector2(radius, 0),
		center + Vector2(0, radius),
		center + Vector2(-radius, 0),
	]), color)


func draw_star(center: Vector2, radius: float, color: Color) -> void:
	var points := PackedVector2Array()
	for index in 10:
		var angle := -PI * 0.5 + float(index) * PI / 5.0
		var distance := radius if index % 2 == 0 else radius * 0.46
		points.append(center + Vector2(cos(angle), sin(angle)) * distance)
	draw_colored_polygon(points, color)


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


func _text_left(value: String, anchor: Vector2, font_size: float, tint: Color) -> void:
	var pixels := maxi(10, int(font_size))
	var font := PlaygroundUI.font()
	draw_string(font, anchor + Vector2(0, pixels * 0.35), value, HORIZONTAL_ALIGNMENT_LEFT, -1, pixels, tint)


func _gui_input(event: InputEvent) -> void:
	if not interactive:
		return
	var position := Vector2.ZERO
	var pressed := false
	if event is InputEventScreenTouch:
		_touch_guard_msec = Time.get_ticks_msec()
		if event.pressed and _touch_index >= 0 and event.index != _touch_index:
			return
		if event.index != _touch_index and not event.pressed:
			return
		if event.pressed:
			_touch_index = event.index
		else:
			_touch_index = -1
		position = event.position
		pressed = event.pressed
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if Time.get_ticks_msec() - _touch_guard_msec < 500:
			return
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
