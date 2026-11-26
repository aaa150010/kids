class_name ShopCounter
extends Control

signal item_pressed(item_id: String)

var items: Array = []
var basket: Dictionary = {}
var accent := Color("#7c7a2d")
var enabled := true
var _pressed_index := -1
var _last_touch_msec := -1000


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(540, 440)
	resized.connect(queue_redraw)


func configure(values: Array, tint: Color) -> void:
	items = values.duplicate(true)
	accent = tint
	queue_redraw()


func set_basket(value: Dictionary) -> void:
	basket = value.duplicate(true)
	queue_redraw()


func set_enabled(value: bool) -> void:
	enabled = value
	if not enabled:
		_pressed_index = -1
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if not enabled:
		return
	if event is InputEventScreenTouch:
		if event.device == InputEvent.DEVICE_ID_EMULATION:
			return
		_last_touch_msec = Time.get_ticks_msec()
		if event.pressed:
			_pressed_index = _hit_index(event.position)
			accept_event()
		else:
			var released_index := _hit_index(event.position)
			if _pressed_index >= 0 and released_index == _pressed_index:
				_emit_item(_pressed_index)
			_pressed_index = -1
			accept_event()
	elif event is InputEventScreenDrag:
		_last_touch_msec = Time.get_ticks_msec()
		_pressed_index = -1
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if Time.get_ticks_msec() - _last_touch_msec < 500:
			return
		if event.pressed:
			_pressed_index = _hit_index(event.position)
			accept_event()
		else:
			var released_index := _hit_index(event.position)
			if _pressed_index >= 0 and released_index == _pressed_index:
				_emit_item(_pressed_index)
			_pressed_index = -1
			accept_event()


func _emit_item(index: int) -> void:
	if index < 0 or index >= items.size():
		return
	var item: Dictionary = items[index]
	item_pressed.emit(str(item.get("id", "")))


func _hit_index(point: Vector2) -> int:
	if items.is_empty():
		return -1
	var layout := _layout()
	var columns := int(layout.columns)
	var cell: Vector2 = layout.cell
	var gap := float(layout.gap)
	var origin: Vector2 = layout.origin
	for index in items.size():
		var column := index % columns
		var row := int(index / columns)
		var rect := Rect2(origin + Vector2(column * (cell.x + gap), row * (cell.y + gap)), cell)
		if rect.has_point(point):
			return index
	return -1


func _layout() -> Dictionary:
	var columns := 4 if size.x >= 620.0 else 3
	var gap := 12.0
	var margin := 14.0
	var row_count := ceili(float(items.size()) / float(maxi(1, columns)))
	var available := Vector2(maxf(1.0, size.x - margin * 2.0), maxf(1.0, size.y - 52.0 - margin))
	var cell := Vector2(
		maxf(1.0, (available.x - gap * float(columns - 1)) / float(columns)),
		maxf(1.0, (available.y - gap * float(maxi(0, row_count - 1))) / float(maxi(1, row_count)))
	)
	return {"columns": columns, "gap": gap, "cell": cell, "origin": Vector2(margin, 46.0)}


func _draw() -> void:
	var font := PlaygroundUI.font()
	draw_style_box(PlaygroundUI.style(PlaygroundUI.mix(accent, Color.WHITE, 0.92), 24, PlaygroundUI.mix(accent, Color.WHITE, 0.48), 2, 5, Color(0, 0, 0, 0.10)), Rect2(Vector2.ZERO, size))
	draw_string(font, Vector2(18, 29), "小商店货架", HORIZONTAL_ALIGNMENT_LEFT, -1, 19, accent)
	draw_string(font, Vector2(size.x - 190, 29), "点商品放进购物篮", HORIZONTAL_ALIGNMENT_LEFT, 170, 14, PlaygroundUI.INK_SOFT)
	if items.is_empty():
		return
	var layout := _layout()
	var columns := int(layout.columns)
	var cell: Vector2 = layout.cell
	var gap := float(layout.gap)
	var origin: Vector2 = layout.origin
	for index in items.size():
		var item: Dictionary = items[index]
		var column := index % columns
		var row := int(index / columns)
		var rect := Rect2(origin + Vector2(column * (cell.x + gap), row * (cell.y + gap)), cell)
		var is_pressed := index == _pressed_index and enabled
		var card_color := PlaygroundUI.mix(accent, Color.WHITE, 0.86 if not is_pressed else 0.72)
		draw_style_box(PlaygroundUI.style(card_color, 16, accent if is_pressed else PlaygroundUI.mix(accent, Color.WHITE, 0.5), 2 if is_pressed else 1), rect)
		var art_size := minf(cell.x * 0.35, cell.y * 0.5)
		_draw_item_icon(
			str(item.get("id", "")),
			rect.position + Vector2(12.0 + art_size * 0.5, 10.0 + art_size * 0.5),
			art_size
		)
		var name := str(item.get("name", "商品"))
		var price := "%s 元" % int(item.get("price", 0))
		var text_x := rect.position.x + 16.0 + art_size + 8.0
		draw_string(font, Vector2(text_x, rect.position.y + 32), name, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - (text_x - rect.position.x) - 10.0, 19, PlaygroundUI.INK)
		draw_string(font, Vector2(text_x, rect.position.y + 57), price, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - (text_x - rect.position.x) - 10.0, 16, accent)
		var count := int(basket.get(str(item.get("id", "")), 0))
		if count > 0:
			draw_circle(rect.position + Vector2(rect.size.x - 18, 17), 15, accent)
			draw_string(font, rect.position + Vector2(rect.size.x - 25, 23), str(count), HORIZONTAL_ALIGNMENT_LEFT, 20, 15, Color.WHITE)
	if not enabled:
		draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.18))


func _draw_item_icon(item_id: String, center: Vector2, icon_size: float) -> void:
	var radius := icon_size * 0.38
	draw_circle(center, icon_size * 0.5, PlaygroundUI.mix(accent, Color.WHITE, 0.82))
	match item_id:
		"apple":
			draw_circle(center + Vector2(-radius * 0.10, radius * 0.06), radius, Color("#df5d50"))
			draw_circle(center + Vector2(-radius * 0.30, -radius * 0.20), radius * 0.22, Color(1, 1, 1, 0.24))
			_draw_small_leaf(center, radius, Color("#4f8d4b"))
		"banana":
			draw_colored_polygon(PackedVector2Array([
				center + Vector2(-radius, radius * 0.30), center + Vector2(-radius * 0.62, -radius * 0.58),
				center + Vector2(radius * 0.70, -radius * 0.56), center + Vector2(radius, -radius * 0.08),
				center + Vector2(radius * 0.4, radius * 0.06), center + Vector2(-radius * 0.38, radius * 0.58),
			]), Color("#edc342"))
			draw_line(center + Vector2(-radius * 0.55, radius * 0.16), center + Vector2(radius * 0.56, -radius * 0.25), Color("#9b7a27"), 2.0, true)
		"orange":
			draw_circle(center, radius, Color("#eb9634"))
			for stripe in 5:
				var angle := TAU * float(stripe) / 5.0
				draw_line(center, center + Vector2(cos(angle), sin(angle)) * radius * 0.82, Color(0.36, 0.22, 0.06, 0.24), 1.5, true)
			_draw_small_leaf(center, radius, Color("#4f8d4b"))
		"strawberry":
			draw_colored_polygon(PackedVector2Array([
				center + Vector2(0, -radius * 0.9), center + Vector2(radius * 0.78, -radius * 0.35),
				center + Vector2(radius * 0.55, radius * 0.55), center + Vector2(0, radius),
				center + Vector2(-radius * 0.55, radius * 0.55), center + Vector2(-radius * 0.78, -radius * 0.35),
			]), Color("#dd5366"))
			draw_circle(center + Vector2(0, -radius * 0.56), radius * 0.16, Color("#5aa04b"))
			for leaf in 5:
				var leaf_angle := -PI * 0.5 + TAU * float(leaf) / 5.0
				draw_line(center + Vector2(0, -radius * 0.56), center + Vector2(cos(leaf_angle), sin(leaf_angle)) * radius * 0.48 + Vector2(0, -radius * 0.42), Color("#5aa04b"), 3.0, true)
			for seed in 5:
				draw_circle(center + Vector2(-radius * 0.35 + float(seed) * radius * 0.17, radius * 0.06 + float(seed % 2) * radius * 0.22), 2.0, Color("#ffe6a3"))
		"watermelon":
			draw_circle(center, radius, Color("#65ae59"))
			draw_circle(center, radius * 0.78, Color("#ef7269"))
			for seed in 6:
				var angle := TAU * float(seed) / 6.0
				draw_circle(center + Vector2(cos(angle), sin(angle)) * radius * 0.44, 2.0, Color("#413b2a"))
		"pear":
			draw_circle(center + Vector2(0, radius * 0.18), radius * 0.70, Color("#a8c554"))
			draw_circle(center + Vector2(0, -radius * 0.40), radius * 0.46, Color("#a8c554"))
			draw_circle(center + Vector2(-radius * 0.18, -radius * 0.02), radius * 0.18, Color(1, 1, 1, 0.18))
			_draw_small_leaf(center, radius, Color("#4f8d4b"))
		"peach":
			draw_circle(center, radius * 0.82, Color("#eea07f"))
			draw_line(center + Vector2(0, -radius * 0.62), center + Vector2(0, radius * 0.78), Color(0.72, 0.32, 0.24, 0.36), 1.6, true)
			_draw_small_leaf(center, radius, Color("#4f8d4b"))
		"pineapple":
			draw_circle(center + Vector2(0, radius * 0.12), radius * 0.68, Color("#cf9a38"))
			for row in 3:
				for column in 3:
					var point := center + Vector2((float(column) - 1.0) * radius * 0.30, (float(row) - 1.0) * radius * 0.28)
					draw_line(point + Vector2(-4, -5), point + Vector2(4, 5), Color(0.58, 0.37, 0.09, 0.46), 1.5)
			for leaf_index in 4:
				draw_colored_polygon(PackedVector2Array([
					center + Vector2(0, -radius * 0.42),
					center + Vector2((float(leaf_index) - 1.5) * radius * 0.28, -radius),
					center + Vector2((float(leaf_index) - 1.1) * radius * 0.18, -radius * 0.40),
				]), Color("#458b4b"))
		"milk":
			var milk_rect := Rect2(center + Vector2(-radius * 0.62, -radius * 0.82), Vector2(radius * 1.24, radius * 1.70))
			draw_style_box(PlaygroundUI.style(Color("#f8f4e8"), 8, Color("#cdbfa3"), 2), milk_rect)
			draw_colored_polygon(PackedVector2Array([
				milk_rect.position, milk_rect.position + Vector2(milk_rect.size.x, 0),
				milk_rect.position + Vector2(milk_rect.size.x * 0.72, milk_rect.size.y * 0.30),
				milk_rect.position + Vector2(milk_rect.size.x * 0.28, milk_rect.size.y * 0.30),
			]), Color("#dceef7"))
			draw_rect(Rect2(center + Vector2(-radius * 0.52, radius * 0.10), Vector2(radius * 1.04, radius * 0.22)), Color("#5a9bc5"))
		"bread":
			draw_style_box(PlaygroundUI.style(Color("#d9a35b"), 18, Color("#9a6838"), 2), Rect2(center + Vector2(-radius * 0.92, -radius * 0.58), Vector2(radius * 1.84, radius * 1.20)))
			for cut in 3:
				draw_line(center + Vector2(-radius * 0.52 + float(cut) * radius * 0.48, -radius * 0.34), center + Vector2(-radius * 0.30 + float(cut) * radius * 0.48, radius * 0.18), Color("#fff0ca"), 2.0, true)
		"egg":
			draw_colored_polygon(PackedVector2Array([
				center + Vector2(0, -radius), center + Vector2(radius * 0.62, -radius * 0.25),
				center + Vector2(radius * 0.48, radius * 0.70), center + Vector2(0, radius),
				center + Vector2(-radius * 0.48, radius * 0.70), center + Vector2(-radius * 0.62, -radius * 0.25),
			]), Color("#fffdf4"))
			draw_circle(center + Vector2(0, radius * 0.05), radius * 0.42, Color("#f3c244"))
			draw_circle(center + Vector2(-radius * 0.12, -radius * 0.08), radius * 0.12, Color(1, 1, 1, 0.35))
		"rice":
			draw_colored_polygon(PackedVector2Array([
				center + Vector2(-radius, radius * 0.18), center + Vector2(radius, radius * 0.18),
				center + Vector2(radius * 0.68, radius), center + Vector2(-radius * 0.68, radius),
			]), Color("#e9ece8"))
			draw_arc(center + Vector2(0, radius * 0.15), radius, 0, PI, 18, Color("#6e8b96"), radius * 0.28, true)
			for grain in 7:
				var grain_angle := TAU * float(grain) / 7.0
				draw_circle(center + Vector2(cos(grain_angle), sin(grain_angle)) * radius * 0.58 + Vector2(0, -radius * 0.12), 2.2, Color("#fffef9"))
			draw_line(center + Vector2(radius * 0.38, -radius * 0.82), center + Vector2(radius * 0.70, radius * 0.02), Color("#9c6f38"), 2.5, true)
			draw_line(center + Vector2(radius * 0.58, -radius * 0.76), center + Vector2(radius * 0.86, radius * 0.06), Color("#9c6f38"), 2.5, true)
		"carrot":
			draw_colored_polygon(PackedVector2Array([
				center + Vector2(-radius * 0.44, -radius * 0.42), center + Vector2(radius * 0.30, -radius * 0.20),
				center + Vector2(0, radius), center + Vector2(-radius * 0.30, radius * 0.28),
			]), Color("#e88835"))
			for leaf in 3:
				draw_line(center + Vector2(-radius * 0.22, -radius * 0.46), center + Vector2((float(leaf) - 1.0) * radius * 0.35, -radius), Color("#4e9149"), 3.0, true)
		"tomato":
			draw_circle(center, radius * 0.82, Color("#e35e4f"))
			for leaf in 5:
				var angle := -PI * 0.5 + TAU * float(leaf) / 5.0
				draw_line(center + Vector2(0, -radius * 0.75), center + Vector2(cos(angle), sin(angle)) * radius * 0.38 + Vector2(0, -radius * 0.6), Color("#4e9149"), 3.0, true)
		"cookie":
			draw_circle(center, radius * 0.84, Color("#d9aa69"))
			for chip in 5:
				var angle := TAU * float(chip) / 5.0 + 0.3
				draw_circle(center + Vector2(cos(angle), sin(angle)) * radius * 0.46, radius * 0.10, Color("#765035"))
		"juice":
			draw_colored_polygon(PackedVector2Array([
				center + Vector2(-radius * 0.56, -radius * 0.56), center + Vector2(radius * 0.56, -radius * 0.56),
				center + Vector2(radius * 0.40, radius), center + Vector2(-radius * 0.40, radius),
			]), Color("#f7dfae"))
			draw_colored_polygon(PackedVector2Array([
				center + Vector2(-radius * 0.50, -radius * 0.18), center + Vector2(radius * 0.50, -radius * 0.18),
				center + Vector2(radius * 0.40, radius * 0.92), center + Vector2(-radius * 0.40, radius * 0.92),
			]), Color("#f1a52f"))
			draw_line(center + Vector2(radius * 0.18, -radius), center + Vector2(radius * 0.06, -radius * 0.54), Color("#e46b55"), 4.0, true)
		_:
			draw_circle(center, radius, PlaygroundUI.mix(accent, Color.WHITE, 0.45))
			draw_circle(center, radius * 0.30, Color.WHITE)


func _draw_small_leaf(center: Vector2, radius: float, color: Color) -> void:
	draw_colored_polygon(PackedVector2Array([
		center + Vector2(radius * 0.06, -radius * 0.82),
		center + Vector2(radius * 0.62, -radius * 0.98),
		center + Vector2(radius * 0.30, -radius * 0.58),
	]), color)
	draw_line(center + Vector2(0, -radius * 0.62), center + Vector2(radius * 0.10, -radius * 0.92), Color("#7a5a2f"), 2.0, true)
