class_name StoryText
extends Control

var text := ""
var ruby: Array = []
var show_pinyin := false
var text_size := 28
var _height := 70.0
var _cells: Array = []
var _last_width := -1.0


func configure(value: Dictionary, pinyin_enabled: bool, font_size: int) -> void:
	text = str(value.get("text", ""))
	ruby = value.get("pinyin", []) if value.get("pinyin") is Array else []
	show_pinyin = pinyin_enabled
	text_size = font_size
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	call_deferred("_layout_text")


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and not is_equal_approx(_last_width, size.x):
		call_deferred("_layout_text")


func _get_minimum_size() -> Vector2:
	return Vector2(0, _height)


func _layout_text() -> void:
	if not is_inside_tree() or size.x < 1.0:
		return
	_last_width = size.x
	_cells.clear()
	var font := PlaygroundUI.font()
	var pinyin_size := maxi(14, int(text_size * 0.48))
	var ruby_height := float(pinyin_size + 7) if show_pinyin else 0.0
	var line_height := float(text_size + 18) + ruby_height
	var x := 0.0
	var y := 4.0
	for index in text.length():
		var character := text.substr(index, 1)
		if character == "\n":
			x = 0.0
			y += line_height
			continue
		var annotation := str(ruby[index]) if show_pinyin and index < ruby.size() else ""
		var width := font.get_string_size(character, HORIZONTAL_ALIGNMENT_LEFT, -1, text_size).x + 3.0
		if not annotation.is_empty():
			width = maxf(width, font.get_string_size(annotation, HORIZONTAL_ALIGNMENT_LEFT, -1, pinyin_size).x + 5.0)
		width = minf(width, size.x)
		if x > 0.0 and x + width > size.x:
			x = 0.0
			y += line_height
		_cells.append({"text": character, "ruby": annotation, "x": x, "y": y, "width": width})
		x += width
	_height = y + line_height
	update_minimum_size()
	queue_redraw()


func _draw() -> void:
	var font := PlaygroundUI.font()
	var pinyin_size := maxi(14, int(text_size * 0.48))
	var ruby_height := float(pinyin_size + 7) if show_pinyin else 0.0
	for cell in _cells:
		var character_width := font.get_string_size(str(cell.text), HORIZONTAL_ALIGNMENT_LEFT, -1, text_size).x
		var origin := Vector2(float(cell.x), float(cell.y))
		if show_pinyin and not str(cell.ruby).is_empty():
			var ruby_width := font.get_string_size(str(cell.ruby), HORIZONTAL_ALIGNMENT_LEFT, -1, pinyin_size).x
			draw_string(font, origin + Vector2((float(cell.width) - ruby_width) * 0.5, font.get_ascent(pinyin_size)), str(cell.ruby), HORIZONTAL_ALIGNMENT_LEFT, -1, pinyin_size, PlaygroundUI.INK_SOFT)
		draw_string(font, origin + Vector2((float(cell.width) - character_width) * 0.5, ruby_height + font.get_ascent(text_size)), str(cell.text), HORIZONTAL_ALIGNMENT_LEFT, -1, text_size, PlaygroundUI.INK)
