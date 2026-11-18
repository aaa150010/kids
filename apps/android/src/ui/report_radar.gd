class_name ReportRadar
extends Control

const AXES := [
	{"key": "math", "name": "数算"},
	{"key": "language", "name": "语言"},
	{"key": "science", "name": "科学"},
	{"key": "logic", "name": "逻辑"},
	{"key": "memory", "name": "记忆"},
	{"key": "strategy", "name": "策略"},
]
var values: Array = [0.15, 0.15, 0.15, 0.15, 0.15, 0.15]
var accent := Color("#167d74")


func configure(skills: Dictionary, tint: Color) -> void:
	accent = tint
	values.clear()
	for axis in AXES:
		var entry: Dictionary = skills.get(axis.key, {})
		var answered := maxf(1.0, float(entry.get("answered", 0)))
		var score := float(entry.get("correct", 0)) / answered if int(entry.get("answered", 0)) > 0 else 0.15
		values.append(clampf(score, 0.12, 1.0))
	queue_redraw()


func _ready() -> void:
	custom_minimum_size = Vector2(360, 310)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func _draw() -> void:
	var center := size * 0.5
	var radius := minf(size.x, size.y) * 0.36
	for ring in [0.25, 0.5, 0.75, 1.0]:
		var points := PackedVector2Array()
		for index in AXES.size():
			var angle := -PI / 2.0 + float(index) / AXES.size() * TAU
			points.append(center + Vector2(cos(angle), sin(angle)) * radius * ring)
		points.append(points[0])
		draw_polyline(points, Color(accent, 0.18), 1.3, true)
	draw_polyline(PackedVector2Array([center + Vector2(0, -radius), center + Vector2(radius * 0.86, -radius * 0.5)]), Color(accent, 0.12), 1.0)
	for index in AXES.size():
		var angle := -PI / 2.0 + float(index) / AXES.size() * TAU
		draw_line(center, center + Vector2(cos(angle), sin(angle)) * radius, Color(accent, 0.2), 1.0)
	var polygon := PackedVector2Array()
	for index in AXES.size():
		var angle := -PI / 2.0 + float(index) / AXES.size() * TAU
		polygon.append(center + Vector2(cos(angle), sin(angle)) * radius * values[index])
	if polygon.size() >= 3:
		draw_colored_polygon(polygon, Color(accent, 0.3))
		var outline := polygon.duplicate()
		outline.append(polygon[0])
		draw_polyline(outline, accent, 3.0, true)
	var font := PlaygroundUI.font()
	for index in AXES.size():
		var angle := -PI / 2.0 + float(index) / AXES.size() * TAU
		var point: Vector2 = center + Vector2(cos(angle), sin(angle)) * radius * (float(values[index]) + 0.03)
		draw_circle(point, 5.0, accent)
		var label_pos: Vector2 = center + Vector2(cos(angle), sin(angle)) * (radius + 31.0)
		var text := str(AXES[index].name)
		var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14)
		draw_string(font, label_pos - Vector2(text_size.x * 0.5, -5), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, PlaygroundUI.INK_SOFT)
