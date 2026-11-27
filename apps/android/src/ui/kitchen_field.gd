class_name KitchenField
extends Control

signal action_requested(action: Dictionary)

var engine: KitchenRules
var accent := Color("#9b653d")
var soft := Color("#f4e7da")
var paused := false

var _ingredient_rects: Array[Rect2] = []
var _ingredient_ids: Array[String] = []
var _tool_rects: Array[Rect2] = []
var _tool_ids: Array[String] = []
var _plate_rect := Rect2()
var _recipe_rect := Rect2()
var _last_touch_msec := -1000
var _notice := ""
var _notice_until := 0.0
var _clock := 0.0
var _hover_rect := Rect2()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	custom_minimum_size = Vector2(900, 600)
	set_process(true)


func bind(rules: KitchenRules, tint: Color, soft_color: Color) -> void:
	engine = rules
	accent = tint
	soft = soft_color
	_notice = ""
	_hover_rect = Rect2()
	queue_redraw()


func set_paused(value: bool) -> void:
	paused = value


func show_notice(message: String, seconds: float = 1.8) -> void:
	_notice = message
	_notice_until = _clock + seconds
	queue_redraw()


func ingredient_rects() -> Array[Rect2]:
	return _ingredient_rects.duplicate()


func tool_rects() -> Array[Rect2]:
	return _tool_rects.duplicate()


func plate_rect() -> Rect2:
	return _plate_rect


func _process(delta: float) -> void:
	_clock += delta
	if _notice_until > 0.0 and _clock > _notice_until:
		_notice = ""
		_notice_until = 0.0
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if paused or engine == null or str(engine.state.get("phase", "")) != "cooking":
		return
	get_viewport().set_input_as_handled()
	var pointer := Vector2(-1, -1)
	var pressed := false
	var pointer_id := 0
	var is_touch := false
	if event is InputEventScreenTouch:
		if event.device == InputEvent.DEVICE_ID_EMULATION:
			return
		_last_touch_msec = Time.get_ticks_msec()
		pointer = event.position
		pressed = event.pressed
		pointer_id = event.index
		is_touch = true
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if Time.get_ticks_msec() - _last_touch_msec < 500:
			return
		pointer = event.position
		pressed = event.pressed
	elif event is InputEventMouseMotion:
		_hover_rect = _action_rect_at(event.position)
		queue_redraw()
		return
	else:
		return
	if pressed:
		return
	_activate_at(pointer, pointer_id, is_touch)


func _activate_at(position: Vector2, _pointer_id: int, _is_touch: bool) -> void:
	for index in _ingredient_rects.size():
		if _ingredient_rects[index].grow(6.0).has_point(position):
			action_requested.emit({"type": "grab", "ingredientId": _ingredient_ids[index]})
			return
	for index in _tool_rects.size():
		if _tool_rects[index].grow(6.0).has_point(position):
			action_requested.emit({"type": "process", "toolId": _tool_ids[index]})
			return
	if _plate_rect.grow(6.0).has_point(position):
		action_requested.emit({"type": "plate"})


func _action_rect_at(position: Vector2) -> Rect2:
	for rect in _ingredient_rects:
		if rect.has_point(position):
			return rect
	for rect in _tool_rects:
		if rect.has_point(position):
			return rect
	if _plate_rect.has_point(position):
		return _plate_rect
	return Rect2()


func _draw() -> void:
	draw_style_box(
		PlaygroundUI.style(PlaygroundUI.mix(accent, Color.WHITE, 0.94), 28, PlaygroundUI.mix(accent, Color.WHITE, 0.48), 2, 8, Color(0, 0, 0, 0.10)),
		Rect2(Vector2.ZERO, size)
	)
	_layout()
	_draw_header()
	_draw_recipe()
	_draw_stations()
	_draw_notice()


func _layout() -> void:
	var width := maxf(900.0, size.x)
	var height := maxf(560.0, size.y)
	_recipe_rect = Rect2(Vector2(26.0, 82.0), Vector2(width - 52.0, 94.0))
	var main_top := _recipe_rect.end.y + 16.0
	var main_height := maxf(280.0, height - main_top - 26.0)
	_plate_rect = Rect2(Vector2(width - 328.0, main_top), Vector2(302.0, 104.0))
	var ingredient_panel_height := maxf(166.0, main_height - _plate_rect.size.y - 16.0)
	var tool_panel_rect := Rect2(Vector2(width - 328.0, main_top + 120.0), Vector2(302.0, ingredient_panel_height))
	var ingredient_panel_rect := Rect2(Vector2(26.0, main_top), Vector2(width - 378.0, ingredient_panel_height))
	_ingredient_rects.clear()
	_ingredient_ids.clear()
	var ingredients: Array = engine.state.get("ingredientCatalog", []) if engine != null else []
	var columns := maxi(4, int(floor((ingredient_panel_rect.size.x - 24.0) / 142.0)))
	var rows := maxi(1, int(ceil(float(ingredients.size()) / float(columns))))
	var card_gap := 10.0
	var card_width := (ingredient_panel_rect.size.x - 28.0 - card_gap * float(columns - 1)) / float(columns)
	var card_height := clampf((ingredient_panel_rect.size.y - 58.0 - card_gap * float(rows - 1)) / float(maxi(1, rows)), 88.0, 126.0)
	for index in ingredients.size():
		if not ingredients[index] is Dictionary:
			continue
		var column := index % columns
		var row := int(floor(float(index) / float(columns)))
		var rect := Rect2(
			Vector2(
				ingredient_panel_rect.position.x + 14.0 + float(column) * (card_width + card_gap),
				ingredient_panel_rect.position.y + 48.0 + float(row) * (card_height + card_gap)
			),
			Vector2(card_width, card_height)
		)
		_ingredient_rects.append(rect)
		_ingredient_ids.append(str(ingredients[index].get("id", "")))
	_tool_rects.clear()
	_tool_ids.clear()
	var tools: Array = engine.state.get("toolCatalog", []) if engine != null else []
	var tool_columns := 2
	var tool_card_width := (tool_panel_rect.size.x - 28.0 - 10.0) / 2.0
	var tool_rows := maxi(1, int(ceil(float(tools.size()) / 2.0)))
	var tool_card_height := clampf((tool_panel_rect.size.y - 48.0 - 10.0 * float(tool_rows - 1)) / float(tool_rows), 72.0, 108.0)
	for index in tools.size():
		if not tools[index] is Dictionary:
			continue
		var column := index % tool_columns
		var row := int(floor(float(index) / float(tool_columns)))
		_tool_rects.append(Rect2(
			Vector2(
				tool_panel_rect.position.x + 14.0 + float(column) * (tool_card_width + 10.0),
				tool_panel_rect.position.y + 44.0 + float(row) * (tool_card_height + 10.0)
			),
			Vector2(tool_card_width, tool_card_height)
		))
		_tool_ids.append(str(tools[index].get("id", "")))


func _draw_header() -> void:
	if engine == null:
		return
	var level: Dictionary = engine.state.get("levelData", {})
	var font := PlaygroundUI.font()
	draw_string(font, Vector2(26, 42), str(level.get("title", "小小厨房")), HORIZONTAL_ALIGNMENT_LEFT, size.x - 560.0, 25, PlaygroundUI.INK)
	draw_string(font, Vector2(26, 66), "%s · %s · 第 %s 张订单" % [str(level.get("dish", "今日小菜")), engine.progress_text(), int(level.get("levelNumber", 1))], HORIZONTAL_ALIGNMENT_LEFT, size.x - 560.0, 15, PlaygroundUI.INK_SOFT)
	var player_text := "小厨师"
	if engine.state.players.size() == 1:
		player_text = str(engine.state.players[0].get("name", player_text))
	elif engine.state.players.size() > 1:
		var current := clampi(int(engine.state.get("currentPlayer", 0)), 0, engine.state.players.size() - 1)
		player_text = "%s · 轮到你" % str(engine.state.players[current].get("name", "小厨师"))
	draw_string(font, Vector2(size.x - 392.0, 42), player_text, HORIZONTAL_ALIGNMENT_LEFT, 330.0, 17, accent)
	draw_string(font, Vector2(size.x - 392.0, 66), "得分 %s · 连做 %s · 纠正 %s" % [int(engine.state.get("score", 0)), int(engine.state.get("combo", 0)), int(engine.state.get("mistakes", 0))], HORIZONTAL_ALIGNMENT_LEFT, 330.0, 14, PlaygroundUI.INK_SOFT)


func _draw_recipe() -> void:
	if engine == null:
		return
	draw_style_box(
		PlaygroundUI.style(PlaygroundUI.mix(soft, Color.WHITE, 0.20), 20, PlaygroundUI.mix(accent, Color.WHITE, 0.46), 2),
		_recipe_rect
	)
	var lines := engine.recipe_lines()
	var current := int(engine.state.get("currentStepIndex", 0))
	var count := maxi(1, lines.size())
	var width := (_recipe_rect.size.x - 28.0) / float(count)
	var font := PlaygroundUI.font()
	for index in lines.size():
		var entry: Dictionary = lines[index]
		var rect := Rect2(
			Vector2(_recipe_rect.position.x + 14.0 + width * float(index), _recipe_rect.position.y + 12.0),
			Vector2(width - 6.0, _recipe_rect.size.y - 24.0)
		)
		var done := index < int(engine.state.get("doneSteps", []).size())
		var active := index == current and str(engine.state.get("phase", "")) == "cooking"
		var fill := Color(1, 1, 1, 0.48)
		if done:
			fill = PlaygroundUI.mix(accent, Color.WHITE, 0.72)
		if active:
			fill = PlaygroundUI.mix(soft, accent, 0.18)
		draw_style_box(
			PlaygroundUI.style(fill, 13, accent if active else PlaygroundUI.mix(accent, Color.WHITE, 0.45), 2 if active else 1),
			rect
		)
		if done:
			_draw_check(rect.position + Vector2(rect.size.x - 19.0, 19.0), 8.0, accent)
		draw_multiline_string(font, rect.position + Vector2(9.0, 26.0), "%s. %s" % [index + 1, str(entry.get("label", "做一步"))], HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 18.0, 14, 3, PlaygroundUI.INK if active or done else PlaygroundUI.INK_SOFT)


func _draw_stations() -> void:
	if engine == null:
		return
	var ingredients: Array = engine.state.get("ingredientCatalog", [])
	if not _ingredient_rects.is_empty():
		var first := _ingredient_rects[0]
		var last := _ingredient_rects[-1]
		var panel := Rect2(Vector2(first.position.x - 14.0, first.position.y - 48.0), Vector2(size.x - 378.0, last.end.y - first.position.y + 62.0))
		draw_style_box(
			PlaygroundUI.style(PlaygroundUI.mix(soft, Color.WHITE, 0.40), 20, PlaygroundUI.mix(accent, Color.WHITE, 0.52), 1),
			panel
		)
		var font := PlaygroundUI.font()
		draw_string(font, Vector2(panel.position.x + 15.0, panel.position.y + 30.0), "食材架 · 点一种食材拿下来", HORIZONTAL_ALIGNMENT_LEFT, panel.size.x - 30.0, 17, accent)
		for index in _ingredient_rects.size():
			var rect := _ingredient_rects[index]
			var ingredient: Dictionary = ingredients[index] if index < ingredients.size() else {}
			var hover := rect == _hover_rect
			draw_style_box(
				PlaygroundUI.style(PlaygroundUI.mix(PlaygroundUI.color(str(ingredient.get("color", "#d5965f"))), Color.WHITE, 0.80 if not hover else 0.68), 16, PlaygroundUI.color(str(ingredient.get("color", "#d5965f"))), 2, 4 if hover else 2, Color(0, 0, 0, 0.08)),
				rect
			)
			_draw_ingredient_art(ingredient, rect.position + Vector2(rect.size.x * 0.5, rect.size.y * 0.42), minf(32.0, rect.size.y * 0.28))
			draw_string(font, rect.position + Vector2(7.0, rect.size.y - 11.0), str(ingredient.get("name", "食材")), HORIZONTAL_ALIGNMENT_CENTER, rect.size.x - 14.0, 15, PlaygroundUI.INK)
	var tools: Array = engine.state.get("toolCatalog", [])
	if not _tool_rects.is_empty():
		var tool_first := _tool_rects[0]
		var tool_last := _tool_rects[-1]
		var panel_tools := Rect2(Vector2(tool_first.position.x - 14.0, tool_first.position.y - 44.0), Vector2(302.0, tool_last.end.y - tool_first.position.y + 58.0))
		draw_style_box(
			PlaygroundUI.style(PlaygroundUI.mix(soft, Color.WHITE, 0.40), 20, PlaygroundUI.mix(accent, Color.WHITE, 0.52), 1),
			panel_tools
		)
		var font_tools := PlaygroundUI.font()
		draw_string(font_tools, Vector2(panel_tools.position.x + 15.0, panel_tools.position.y + 28.0), "加工台 · 选一个动作", HORIZONTAL_ALIGNMENT_LEFT, 270.0, 17, accent)
		for index in _tool_rects.size():
			var rect := _tool_rects[index]
			var tool: Dictionary = tools[index] if index < tools.size() else {}
			var hover := rect == _hover_rect
			var tint := PlaygroundUI.color(str(tool.get("color", "#c08a50")))
			draw_style_box(
				PlaygroundUI.style(PlaygroundUI.mix(tint, Color.WHITE, 0.76 if not hover else 0.62), 15, tint, 2, 4 if hover else 2, Color(0, 0, 0, 0.08)),
				rect
			)
			_draw_tool_art(str(tool.get("id", "")), rect.position + Vector2(28.0, rect.size.y * 0.48), minf(22.0, rect.size.y * 0.28), tint)
			draw_string(font_tools, rect.position + Vector2(48.0, rect.size.y * 0.52), str(tool.get("verb", tool.get("name", "加工"))), HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 56.0, 17, PlaygroundUI.INK)
	draw_style_box(
		PlaygroundUI.style(PlaygroundUI.mix(Color("#f0d9bd"), Color.WHITE, 0.18), 20, Color(accent, 0.38), 2, 4, Color(0, 0, 0, 0.08)),
		_plate_rect
	)
	draw_circle(_plate_rect.position + Vector2(54.0, 62.0), 34.0, Color.WHITE)
	draw_arc(_plate_rect.position + Vector2(54.0, 62.0), 32.0, 0, TAU, 32, Color(accent, 0.45), 3.0, true)
	draw_circle(_plate_rect.position + Vector2(54.0, 62.0), 23.0, Color(accent, 0.12))
	draw_string(PlaygroundUI.font(), _plate_rect.position + Vector2(104.0, 45.0), "装盘", HORIZONTAL_ALIGNMENT_LEFT, 180.0, 23, PlaygroundUI.INK)
	draw_string(PlaygroundUI.font(), _plate_rect.position + Vector2(104.0, 74.0), "做好最后一步再点", HORIZONTAL_ALIGNMENT_LEFT, 188.0, 14, PlaygroundUI.INK_SOFT)


func _draw_notice() -> void:
	if _notice.is_empty():
		return
	var font := PlaygroundUI.font()
	var width := minf(size.x - 120.0, font.get_string_size(_notice, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x + 36.0)
	var rect := Rect2(Vector2((size.x - width) * 0.5, size.y - 58.0), Vector2(width, 36.0))
	draw_style_box(PlaygroundUI.style(PlaygroundUI.mix(accent, Color.WHITE, 0.82), 18, Color(accent, 0.32), 1), rect)
	draw_string(font, rect.position + Vector2(18.0, 24.0), _notice, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 36.0, 17, accent)


func _draw_check(center: Vector2, radius: float, tint: Color) -> void:
	draw_circle(center, radius + 4.0, Color(tint, 0.16))
	draw_arc(center, radius + 4.0, 0, TAU, 24, tint, 2.0, true)
	draw_line(center + Vector2(-radius * 0.48, 0.0), center + Vector2(-radius * 0.08, radius * 0.40), tint, 3.0, true)
	draw_line(center + Vector2(-radius * 0.08, radius * 0.40), center + Vector2(radius * 0.52, -radius * 0.38), tint, 3.0, true)


func _draw_tool_art(tool_id: String, center: Vector2, radius: float, tint: Color) -> void:
	match tool_id:
		"wash":
			draw_arc(center + Vector2(0, 5), radius * 0.65, PI, TAU, 22, tint, radius * 0.24, true)
			for index in 3:
				draw_line(center + Vector2(-radius * 0.35 + index * radius * 0.35, -radius * 0.8), center + Vector2(-radius * 0.28 + index * radius * 0.35, -radius * 0.42), Color("#6aa9b5"), 3.0, true)
		"cut":
			draw_line(center + Vector2(-radius * 0.65, radius * 0.60), center + Vector2(radius * 0.45, -radius * 0.55), Color("#8d9aa4"), 5.0, true)
			draw_colored_polygon(PackedVector2Array([
				center + Vector2(-radius * 0.65, radius * 0.60),
				center + Vector2(-radius * 0.10, radius * 0.40),
				center + Vector2(-radius * 0.42, radius * 0.80),
			]), tint)
		"mix":
			draw_arc(center + Vector2(0, 2), radius * 0.64, PI, TAU, 22, tint, radius * 0.20, true)
			draw_line(center + Vector2(0, 2), center + Vector2(0, -radius * 0.82), tint, 5.0, true)
			draw_line(center + Vector2(0, -radius * 0.82), center + Vector2(radius * 0.36, -radius * 1.02), tint, 4.0, true)
		"cook":
			draw_style_box(PlaygroundUI.style(Color(tint, 0.24), 8, tint, 3), Rect2(center + Vector2(-radius * 0.66, -radius * 0.34), Vector2(radius * 1.32, radius * 0.82)))
			draw_line(center + Vector2(-radius * 0.84, -radius * 0.32), center + Vector2(radius * 0.84, -radius * 0.32), tint, 4.0, true)
			draw_line(center + Vector2(0, -radius * 0.84), center + Vector2(0, -radius * 0.48), tint, 3.0, true)
		"steam":
			draw_style_box(PlaygroundUI.style(Color(tint, 0.24), 8, tint, 3), Rect2(center + Vector2(-radius * 0.62, -radius * 0.10), Vector2(radius * 1.24, radius * 0.62)))
			for index in 2:
				draw_arc(center + Vector2(-radius * 0.22 + index * radius * 0.44, -radius * 0.48), radius * 0.22, -PI * 0.6, PI * 0.6, 12, Color("#9db6b6"), 3.0, true)
		"bake":
			draw_style_box(PlaygroundUI.style(Color(tint, 0.18), 8, tint, 3), Rect2(center + Vector2(-radius * 0.70, -radius * 0.58), Vector2(radius * 1.40, radius * 1.16)))
			draw_rect(Rect2(center + Vector2(-radius * 0.50, -radius * 0.30), Vector2(radius * 1.0, radius * 0.52)), Color(1, 1, 1, 0.42))
			draw_line(center + Vector2(-radius * 0.60, -radius * 0.56), center + Vector2(radius * 0.60, -radius * 0.56), tint, 2.0, true)
		_:
			draw_circle(center, radius * 0.58, Color(tint, 0.25))
			draw_arc(center, radius * 0.58, 0, TAU, 24, tint, 3.0, true)


func _draw_ingredient_art(ingredient: Dictionary, center: Vector2, radius: float) -> void:
	var art := str(ingredient.get("art", "round"))
	var tint := PlaygroundUI.color(str(ingredient.get("color", "#d5965f")))
	var ink := tint.darkened(0.26)
	match art:
		"round":
			draw_circle(center, radius * 0.72, tint)
			draw_circle(center + Vector2(-radius * 0.18, -radius * 0.20), radius * 0.22, Color(1, 1, 1, 0.28))
			draw_line(center + Vector2(0, -radius * 0.68), center + Vector2(radius * 0.25, -radius * 0.92), Color("#5c8a4a"), 2.0, true)
			draw_colored_polygon(PackedVector2Array([
				center + Vector2(radius * 0.16, -radius * 0.82),
				center + Vector2(radius * 0.58, -radius * 0.98),
				center + Vector2(radius * 0.42, -radius * 0.62),
			]), Color("#6b9a53"))
		"long":
			draw_set_transform(center, -0.48, Vector2.ONE)
			draw_style_box(PlaygroundUI.style(tint, int(radius * 0.28), ink, 2), Rect2(Vector2(-radius * 0.70, -radius * 0.22), Vector2(radius * 1.40, radius * 0.44)))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			draw_line(center + Vector2(-radius * 0.28, -radius * 0.08), center + Vector2(radius * 0.30, radius * 0.08), Color(1, 1, 1, 0.38), 2.0, true)
		"grain":
			draw_colored_polygon(PackedVector2Array([
				center + Vector2(-radius * 0.60, radius * 0.38),
				center + Vector2(radius * 0.54, radius * 0.38),
				center + Vector2(radius * 0.36, -radius * 0.22),
				center + Vector2(-radius * 0.36, -radius * 0.22),
			]), tint)
			draw_arc(center + Vector2(0, -radius * 0.22), radius * 0.36, PI, TAU, 18, Color(1, 1, 1, 0.42), 2.0, true)
			for index in 4:
				draw_circle(center + Vector2(-radius * 0.26 + index * radius * 0.18, 0), radius * 0.06, Color(1, 1, 1, 0.56))
		"leafy":
			for index in 5:
				var angle := TAU * float(index) / 5.0 - 0.5
				draw_set_transform(center, angle, Vector2.ONE)
				draw_circle(Vector2(radius * 0.30, 0), radius * 0.35, PlaygroundUI.mix(tint, Color.WHITE, 0.08))
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			draw_circle(center, radius * 0.24, ink)
		"liquid":
			draw_style_box(PlaygroundUI.style(Color(1, 1, 1, 0.54), 6, tint, 2), Rect2(center + Vector2(-radius * 0.34, -radius * 0.56), Vector2(radius * 0.68, radius * 1.12)))
			draw_rect(Rect2(center + Vector2(-radius * 0.26, radius * 0.02), Vector2(radius * 0.52, radius * 0.43)), Color(tint, 0.52))
			draw_rect(Rect2(center + Vector2(-radius * 0.18, -radius * 0.72), Vector2(radius * 0.36, radius * 0.18)), tint)
		"powder":
			draw_style_box(PlaygroundUI.style(Color("#f8f1dd"), 6, tint, 2), Rect2(center + Vector2(-radius * 0.44, -radius * 0.36), Vector2(radius * 0.88, radius * 0.82)))
			for index in 5:
				draw_circle(center + Vector2(-radius * 0.22 + float(index) * radius * 0.11, radius * 0.02 + float(index % 2) * radius * 0.12), radius * 0.035, tint)
		"block":
			draw_style_box(PlaygroundUI.style(tint, 8, ink, 2), Rect2(center + Vector2(-radius * 0.56, -radius * 0.42), Vector2(radius * 1.12, radius * 0.84)))
			draw_line(center + Vector2(-radius * 0.42, -radius * 0.20), center + Vector2(radius * 0.38, -radius * 0.20), Color(1, 1, 1, 0.38), 2.0, true)
		"flake":
			draw_circle(center, radius * 0.70, PlaygroundUI.mix(tint, Color.WHITE, 0.08))
			for index in 4:
				draw_circle(center + Vector2(-radius * 0.24 + index * radius * 0.16, -radius * 0.04), radius * 0.10, Color(1, 1, 1, 0.38))
		"berry":
			for index in 4:
				var angle := TAU * float(index) / 4.0
				draw_circle(center + Vector2(cos(angle), sin(angle)) * radius * 0.24, radius * 0.33, tint)
			draw_circle(center, radius * 0.22, Color(1, 1, 1, 0.25))
		_:
			draw_style_box(PlaygroundUI.style(PlaygroundUI.mix(tint, Color.WHITE, 0.22), 10, ink, 2), Rect2(center + Vector2(-radius * 0.55, -radius * 0.42), Vector2(radius * 1.10, radius * 0.84)))
