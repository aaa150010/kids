class_name OriginalGlyph
extends Control

var content_name := ""
var semantic := ""
var kind := "object"
var accent := Color("#d56c29")
var show_label := true
var label_size := 16
const GLYPH_INK := Color("#2e241f")
static var _font_cache: Font


func configure(
	value_name: String,
	value_semantic: String = "",
	value_kind: String = "",
	value_accent: Color = Color("#d56c29"),
	value_show_label: bool = true,
	minimum: Vector2 = Vector2(96, 96)
) -> void:
	content_name = value_name.strip_edges()
	semantic = value_semantic.strip_edges()
	kind = value_kind if not value_kind.is_empty() else "object"
	accent = value_accent
	show_label = value_show_label
	custom_minimum_size = minimum
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	if rect.size.x <= 1.0 or rect.size.y <= 1.0:
		return
	var card := _paper_style(rect)
	draw_style_box(card, rect)
	var label_height := float(label_size + 12) if show_label and not content_name.is_empty() else 0.0
	var art_rect := Rect2(10, 10, maxf(1.0, size.x - 20.0), maxf(1.0, size.y - 20.0 - label_height))
	var center := art_rect.get_center()
	var radius := minf(art_rect.size.x, art_rect.size.y) * 0.31
	match kind:
		"animal":
			_draw_animal(center, radius)
		"fruit":
			_draw_fruit(center, radius)
		"vehicle":
			_draw_vehicle(center, radius)
		"shape":
			_draw_shape(center, radius)
		"cover":
			_draw_cover(center, radius)
		_:
			_draw_object(center, radius)
	if label_height > 0.0:
		var font := _glyph_font()
		var use_size := label_size
		var width := font.get_string_size(content_name, HORIZONTAL_ALIGNMENT_CENTER, -1, use_size).x
		while width > size.x - 16.0 and use_size > 11:
			use_size -= 1
			width = font.get_string_size(content_name, HORIZONTAL_ALIGNMENT_CENTER, -1, use_size).x
		var baseline := size.y - 8.0 - font.get_descent(use_size)
		draw_string(
			font,
			Vector2(8.0, baseline),
			content_name,
			HORIZONTAL_ALIGNMENT_CENTER,
			size.x - 16.0,
			use_size,
			GLYPH_INK
		)


func _draw_animal(center: Vector2, radius: float) -> void:
	var value := _stable_value()
	var body := accent.lightened(0.18 + float(int(value % 4)) * 0.05)
	var dark := accent.darkened(0.3)
	draw_circle(center + Vector2(0, radius * 0.18), radius * 0.76, body)
	var ear_width := radius * (0.34 if value % 3 != 0 else 0.18)
	var ear_height := radius * (0.72 if value % 5 != 0 else 0.34)
	draw_colored_polygon(PackedVector2Array([
		center + Vector2(-radius * 0.48, -radius * 0.35),
		center + Vector2(-radius * 0.48 - ear_width, -radius * 0.35 - ear_height),
		center + Vector2(-radius * 0.15, -radius * 0.64),
	]), body)
	draw_colored_polygon(PackedVector2Array([
		center + Vector2(radius * 0.48, -radius * 0.35),
		center + Vector2(radius * 0.48 + ear_width, -radius * 0.35 - ear_height),
		center + Vector2(radius * 0.15, -radius * 0.64),
	]), body)
	draw_circle(center + Vector2(-radius * 0.28, -radius * 0.06), radius * 0.09, dark)
	draw_circle(center + Vector2(radius * 0.28, -radius * 0.06), radius * 0.09, dark)
	draw_circle(center + Vector2(0, radius * 0.23), radius * 0.15, dark)
	var stripe_count := 2 + int(value % 3)
	for index in stripe_count:
		var x := center.x - radius * 0.45 + float(index) * radius * 0.45
		draw_line(Vector2(x, center.y - radius * 0.55), Vector2(x, center.y - radius * 0.3), dark, 3.0)


func _draw_fruit(center: Vector2, radius: float) -> void:
	var value := _stable_value()
	var fruit_color := accent.lightened(0.08)
	var dark := accent.darkened(0.28)
	if content_name.contains("香蕉"):
		draw_arc(center + Vector2(0, -radius * 0.05), radius * 0.72, -0.15, 2.55, 32, fruit_color, radius * 0.34)
	elif content_name.contains("西瓜"):
		draw_circle(center, radius * 0.78, fruit_color)
		draw_arc(center, radius * 0.78, 0.05, PI - 0.05, 32, Color("#5d9b55"), 7.0)
		for index in 6:
			var angle := 0.45 + float(index) * 0.42
			draw_circle(center + Vector2(cos(angle), sin(angle)) * radius * 0.42, 2.7, dark)
	elif content_name.contains("葡萄") or content_name.contains("桑葚"):
		for row in 3:
			for col in 3 - row:
				draw_circle(center + Vector2((float(col) - float(2 - row) * 0.5) * radius * 0.28, -radius * 0.35 + float(row) * radius * 0.28), radius * 0.16, fruit_color)
	else:
		var width := radius * (1.2 + float(value % 3) * 0.08)
		draw_circle(center + Vector2(0, radius * 0.08), radius * 0.68, fruit_color)
		if content_name.contains("梨") or content_name.contains("柿子"):
			draw_circle(center + Vector2(0, -radius * 0.38), radius * 0.35, fruit_color)
		if content_name.contains("菠萝") or content_name.contains("榴莲") or content_name.contains("杨梅"):
			for index in 10:
				var angle := TAU * float(index) / 10.0
				draw_line(center + Vector2(cos(angle), sin(angle)) * radius * 0.45, center + Vector2(cos(angle), sin(angle)) * radius * 0.78, dark, 3.0)
		draw_line(center + Vector2(0, -radius * 0.58), center + Vector2(radius * 0.08, -radius * 0.98), dark, 5.0)
		draw_colored_polygon(PackedVector2Array([
			center + Vector2(radius * 0.08, -radius * 0.88),
			center + Vector2(radius * 0.65, -radius * 0.92),
			center + Vector2(radius * 0.25, -radius * 0.56),
		]), Color("#62a24a"))
	draw_circle(center + Vector2(-radius * 0.22, radius * 0.02), radius * 0.12, Color(1, 1, 1, 0.36))


func _draw_vehicle(center: Vector2, radius: float) -> void:
	var body := accent.lightened(0.12)
	var dark := accent.darkened(0.35)
	if content_name.contains("船") or content_name.contains("艇") or content_name.contains("舟"):
		draw_colored_polygon(PackedVector2Array([
			center + Vector2(-radius * 0.85, radius * 0.15),
			center + Vector2(radius * 0.85, radius * 0.15),
			center + Vector2(radius * 0.55, radius * 0.62),
			center + Vector2(-radius * 0.55, radius * 0.62),
		]), body)
		draw_line(center + Vector2(0, radius * 0.18), center + Vector2(0, -radius * 0.75), dark, 5.0)
		draw_colored_polygon(PackedVector2Array([
			center + Vector2(radius * 0.06, -radius * 0.72),
			center + Vector2(radius * 0.6, -radius * 0.05),
			center + Vector2(radius * 0.06, -radius * 0.05),
		]), Color("#fff3c7"))
	elif content_name.contains("机") and not content_name.contains("拖拉"):
		draw_colored_polygon(PackedVector2Array([
			center + Vector2(-radius * 0.82, radius * 0.02),
			center + Vector2(radius * 0.75, -radius * 0.15),
			center + Vector2(radius * 0.42, radius * 0.22),
			center + Vector2(-radius * 0.7, radius * 0.28),
		]), body)
		draw_colored_polygon(PackedVector2Array([
			center + Vector2(-radius * 0.1, radius * 0.04),
			center + Vector2(radius * 0.35, -radius * 0.62),
			center + Vector2(radius * 0.62, radius * 0.02),
		]), accent.lightened(0.3))
	else:
		draw_style_box(_box_style(body, int(radius * 0.34), dark, 3), Rect2(center - Vector2(radius * 0.78, radius * 0.38), Vector2(radius * 1.56, radius * 0.72)))
		draw_style_box(_box_style(Color("#d8f0f6"), int(radius * 0.18), dark, 2), Rect2(center - Vector2(radius * 0.38, radius * 0.26), Vector2(radius * 0.76, radius * 0.3)))
		draw_circle(center + Vector2(-radius * 0.45, radius * 0.38), radius * 0.2, dark)
		draw_circle(center + Vector2(radius * 0.45, radius * 0.38), radius * 0.2, dark)
		if content_name.contains("列车") or content_name.contains("火车") or content_name.contains("地铁"):
			draw_line(center + Vector2(-radius * 0.82, radius * 0.72), center + Vector2(radius * 0.82, radius * 0.72), dark, 5.0)


func _draw_object(center: Vector2, radius: float) -> void:
	var body := accent.lightened(0.1)
	var dark := accent.darkened(0.32)
	var value := _stable_value()
	draw_style_box(
		_box_style(body, int(radius * 0.35), dark, 3),
		Rect2(center - Vector2(radius * 0.66, radius * 0.62), Vector2(radius * 1.32, radius * 1.24))
	)
	draw_arc(center, radius * 0.33, -PI * 0.82, PI * 0.82, 24, Color(1, 1, 1, 0.72), 5.0)
	var mark := radius * 0.18
	if value % 3 == 0:
		draw_line(center + Vector2(-mark, 0), center + Vector2(mark, 0), dark, 5.0)
		draw_line(center + Vector2(0, -mark), center + Vector2(0, mark), dark, 5.0)
	elif value % 3 == 1:
		draw_circle(center, mark, Color(1, 1, 1, 0.72))
	else:
		draw_colored_polygon(PackedVector2Array([
			center + Vector2(0, -mark * 1.4),
			center + Vector2(mark * 1.2, mark),
			center + Vector2(-mark * 1.2, mark),
		]), Color(1, 1, 1, 0.72))


func _draw_shape(center: Vector2, radius: float) -> void:
	var points: PackedVector2Array
	match _stable_value() % 3:
		0:
			draw_circle(center, radius * 0.76, accent)
		1:
			points = PackedVector2Array([
				center + Vector2(0, -radius * 0.8),
				center + Vector2(radius * 0.78, radius * 0.52),
				center + Vector2(-radius * 0.78, radius * 0.52),
			])
			draw_colored_polygon(points, accent)
		_:
			draw_style_box(_box_style(accent, int(radius * 0.18), accent.darkened(0.2), 2), Rect2(center - Vector2(radius * 0.7, radius * 0.7), Vector2(radius * 1.4, radius * 1.4)))


func _draw_cover(center: Vector2, radius: float) -> void:
	draw_circle(center + Vector2(-radius * 0.85, -radius * 0.65), radius * 0.55, accent.lerp(Color.WHITE, 0.55))
	draw_style_box(
		_box_style(accent.lightened(0.08), int(radius * 0.24), accent.darkened(0.22), 3),
		Rect2(center - Vector2(radius * 0.9, radius * 0.35), Vector2(radius * 1.8, radius * 1.0))
	)
	for index in 3:
		draw_circle(center + Vector2((float(index) - 1.0) * radius * 0.5, radius * 0.2), radius * 0.14, Color(1, 1, 1, 0.84))


func _stable_value() -> int:
	var source := content_name if not content_name.is_empty() else semantic
	var result := 17
	for index in source.length():
		result = (result * 31 + source.unicode_at(index)) % 1000003
	return result


func _paper_style(rect: Rect2) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = accent.lerp(Color.WHITE, 0.78)
	var radius := int(minf(28.0, rect.size.x * 0.16))
	box.corner_radius_top_left = radius
	box.corner_radius_top_right = radius
	box.corner_radius_bottom_left = radius
	box.corner_radius_bottom_right = radius
	box.border_color = accent.lerp(Color.WHITE, 0.35)
	box.border_width_left = 2
	box.border_width_top = 2
	box.border_width_right = 2
	box.border_width_bottom = 2
	box.shadow_size = 2
	box.shadow_color = Color(0, 0, 0, 0.08)
	return box


func _box_style(background: Color, radius: int, border: Color, border_width: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = background
	box.corner_radius_top_left = radius
	box.corner_radius_top_right = radius
	box.corner_radius_bottom_left = radius
	box.corner_radius_bottom_right = radius
	box.border_color = border
	box.border_width_left = border_width
	box.border_width_top = border_width
	box.border_width_right = border_width
	box.border_width_bottom = border_width
	return box


static func _glyph_font() -> Font:
	if _font_cache != null:
		return _font_cache
	if ResourceLoader.exists("res://assets/fonts/NotoSansCJKsc-Content.otf"):
		var content_font: FontFile = load("res://assets/fonts/NotoSansCJKsc-Content.otf")
		content_font.allow_system_fallback = true
		_font_cache = content_font
	else:
		_font_cache = ThemeDB.fallback_font
	return _font_cache
