class_name PoemRubyText
extends Control

var line_text := ""
var line_pinyin := ""
var show_pinyin := true
var hide_text := false
var text_size := 32
var _height := 60.0
var _cells: Array = []
var _last_width := -1.0


func configure(value: String, pinyin_value: String, font_size: int, pinyin_enabled: bool, text_hidden: bool) -> void:
	line_text = value
	line_pinyin = pinyin_value
	text_size = font_size
	show_pinyin = pinyin_enabled and not text_hidden
	hide_text = text_hidden
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	call_deferred("_layout_line")


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and not is_equal_approx(_last_width, size.x):
		call_deferred("_layout_line")


func _get_minimum_size() -> Vector2:
	return Vector2(0, _height)


func _pinyin_tokens() -> Array:
	var result: Array = []
	for token in line_pinyin.strip_edges().split(" ", false):
		var syllable := str(token).strip_edges()
		if syllable.is_empty():
			continue
		while syllable.length() > 1 and _is_punctuation(syllable.substr(syllable.length() - 1, 1)):
			syllable = syllable.substr(0, syllable.length() - 1)
		if not syllable.is_empty():
			result.append(syllable)
	return result


func _is_punctuation(character: String) -> bool:
	return character in ["，", "。", "！", "？", "；", "：", "、", ",", ".", "!", "?", ";", ":"]


func _layout_line() -> void:
	if not is_inside_tree() or size.x < 1.0:
		return
	_last_width = size.x
	_cells.clear()
	var font := PlaygroundUI.font()
	var pinyin_size := maxi(13, int(text_size * 0.44))
	var ruby_height := float(pinyin_size + 10) if show_pinyin else 0.0
	var tokens := _pinyin_tokens()
	var token_index := 0
	var widths: Array = []
	var total_width := 0.0
	for index in line_text.length():
		var character := line_text.substr(index, 1)
		var annotation := ""
		if not _is_punctuation(character) and token_index < tokens.size():
			annotation = str(tokens[token_index])
			token_index += 1
		var shown := "•" if hide_text and not _is_punctuation(character) else character
		var character_width := font.get_string_size(shown, HORIZONTAL_ALIGNMENT_LEFT, -1, text_size).x
		var width := character_width + 4.0
		if show_pinyin and not annotation.is_empty():
			width = maxf(width, font.get_string_size(annotation, HORIZONTAL_ALIGNMENT_LEFT, -1, pinyin_size).x + 6.0)
		widths.append(width)
		total_width += width
		_cells.append({"text": shown, "ruby": annotation, "width": width})
	var cursor := maxf(0.0, (size.x - total_width) * 0.5)
	for index in _cells.size():
		_cells[index].x = cursor
		cursor += float(_cells[index].width)
	_height = ruby_height + float(text_size + 16)
	update_minimum_size()
	queue_redraw()


func _draw() -> void:
	var font := PlaygroundUI.font()
	var pinyin_size := maxi(13, int(text_size * 0.44))
	var ruby_height := float(pinyin_size + 10) if show_pinyin else 0.0
	for cell in _cells:
		var origin := Vector2(float(cell.x), 0.0)
		var cell_width := float(cell.width)
		var annotation := str(cell.ruby)
		if show_pinyin and not annotation.is_empty():
			var ruby_width := font.get_string_size(annotation, HORIZONTAL_ALIGNMENT_LEFT, -1, pinyin_size).x
			draw_string(font, origin + Vector2((cell_width - ruby_width) * 0.5, font.get_ascent(pinyin_size)), annotation, HORIZONTAL_ALIGNMENT_LEFT, -1, pinyin_size, PlaygroundUI.INK_SOFT)
		var character_width := font.get_string_size(str(cell.text), HORIZONTAL_ALIGNMENT_LEFT, -1, text_size).x
		draw_string(font, origin + Vector2((cell_width - character_width) * 0.5, ruby_height + font.get_ascent(text_size)), str(cell.text), HORIZONTAL_ALIGNMENT_LEFT, -1, text_size, PlaygroundUI.INK)
