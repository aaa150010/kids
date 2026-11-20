class_name StoryText
extends Control

const CLOSING_PUNCTUATION := "，。！？；：、）》】」』”’…"
const OPENING_PUNCTUATION := "（《【「『“‘"

var text := ""
var ruby: Array = []
var show_pinyin := false
var text_size := 28
var highlight_tint := Color("#e8f1ea")
var _height := 70.0
var _cells: Array = []
var _last_width := -1.0

var _article_mode := false
var _article_paragraphs: Array = []
var _article_illustrations: Array = []
var _article_cells: Array = []
var _article_images: Array = []
var _article_image_bounds: Array = []
var _placeholder_bounds: Array = []
var _paragraph_ranges: Dictionary = {}
var _paragraph_tops: Dictionary = {}
var _paragraph_bottoms: Dictionary = {}
var _highlight_paragraph_id := ""
var _line_height := 54.0
var _layout_generation := 0
var _texture_cache: Dictionary = {}
var _missing_illustrations := 0
var _missing_anchor_ids: Array[String] = []


func configure(value: Dictionary, pinyin_enabled: bool, font_size: int) -> void:
	_article_mode = false
	text = str(value.get("text", ""))
	ruby = value.get("pinyin", []) if value.get("pinyin") is Array else []
	show_pinyin = pinyin_enabled
	text_size = font_size
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	call_deferred("_layout_text")


func configure_article(
	paragraphs: Array,
	illustrations: Array,
	pinyin_enabled: bool,
	font_size: int
) -> void:
	_article_mode = true
	_article_paragraphs = paragraphs.duplicate(true)
	_article_illustrations = illustrations.duplicate(true)
	_missing_illustrations = 0
	_missing_anchor_ids.clear()
	_placeholder_bounds.clear()
	show_pinyin = pinyin_enabled
	text_size = font_size
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_last_width = -1.0
	_layout_generation += 1
	call_deferred("_layout_text")


func set_highlighted_paragraph(paragraph_id: String) -> void:
	if _highlight_paragraph_id == paragraph_id:
		return
	_highlight_paragraph_id = paragraph_id
	queue_redraw()


func anchor_at_local_y(local_y: float) -> Dictionary:
	if not _article_mode or _article_cells.is_empty():
		return {"paragraphId": "", "characterIndex": 0, "lineOffset": 0.0}
	if local_y < 4.0:
		return {"paragraphId": "", "characterIndex": 0, "lineOffset": 0.0}
	for cell in _article_cells:
		if float(cell.y) + _line_height >= local_y:
			return {
				"paragraphId": str(cell.paragraphId),
				"characterIndex": int(cell.characterIndex),
				"lineOffset": clampf((local_y - float(cell.y)) / maxf(1.0, _line_height), 0.0, 1.0),
			}
	var last: Dictionary = _article_cells.back()
	return {
		"paragraphId": str(last.paragraphId),
		"characterIndex": int(last.characterIndex),
		"lineOffset": 0.0,
	}


func scroll_y_for_anchor(anchor: Dictionary) -> float:
	var paragraph_id := str(anchor.get("paragraphId", ""))
	if paragraph_id.is_empty():
		return 0.0
	var wanted_index := maxi(0, int(anchor.get("characterIndex", 0)))
	for cell in _article_cells:
		if str(cell.paragraphId) == paragraph_id and int(cell.characterIndex) >= wanted_index:
			return float(cell.y) + clampf(float(anchor.get("lineOffset", 0.0)), 0.0, 1.0) * _line_height
	return scroll_y_for_paragraph(paragraph_id)


func scroll_y_for_paragraph(paragraph_id: String) -> float:
	return float(_paragraph_tops.get(paragraph_id, 0.0))


func is_paragraph_visible(paragraph_id: String, visible_top: float, visible_bottom: float) -> bool:
	if not _paragraph_tops.has(paragraph_id):
		return true
	var top := float(_paragraph_tops[paragraph_id])
	var bottom := float(_paragraph_bottoms.get(paragraph_id, top + _line_height))
	return bottom >= visible_top and top <= visible_bottom


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and not is_equal_approx(_last_width, size.x):
		call_deferred("_layout_text")


func _get_minimum_size() -> Vector2:
	return Vector2(0, _height)


func _layout_text() -> void:
	if not is_inside_tree() or size.x < 1.0:
		return
	if _article_mode:
		_layout_article()
	else:
		_layout_simple()


func _layout_simple() -> void:
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
		var width := _unit_width(font, character, annotation, pinyin_size)
		if x > 0.0 and x + width > size.x:
			x = 0.0
			y += line_height
		_cells.append({"text": character, "ruby": annotation, "x": x, "y": y, "width": width})
		x += width
	_height = y + line_height
	update_minimum_size()
	queue_redraw()


func _layout_article() -> void:
	if is_equal_approx(_last_width, size.x) and not _article_cells.is_empty():
		return
	_last_width = size.x
	var generation := _layout_generation
	_article_cells.clear()
	_article_images.clear()
	_article_image_bounds.clear()
	_placeholder_bounds.clear()
	_paragraph_ranges.clear()
	_paragraph_tops.clear()
	_paragraph_bottoms.clear()
	var font := PlaygroundUI.font()
	var pinyin_size := maxi(14, int(text_size * 0.48))
	var ruby_height := float(pinyin_size + 7) if show_pinyin else 0.0
	_line_height = float(text_size + 18) + ruby_height
	var images_by_anchor := _prepare_illustrations()
	var y := 4.0
	var right_side := true
	for paragraph_index in _article_paragraphs.size():
		var paragraph: Variant = _article_paragraphs[paragraph_index]
		if not paragraph is Dictionary:
			continue
		var paragraph_id := str(paragraph.get("id", "p%d" % paragraph_index))
		if y > 4.0:
			y += _line_height * 0.42
		_paragraph_tops[paragraph_id] = y
		var anchored_images: Array = images_by_anchor.get(paragraph_id, [])
		var placeholders: Array = []
		if anchored_images.is_empty() and paragraph_id in _missing_anchor_ids:
			placeholders = _placeholder_images(paragraph_id)
		for placeholder in placeholders:
			var sample_unit := _unit_width(font, "汉", "hàn", pinyin_size)
			var reading_reserve := sample_unit * 8.0 + 24.0
			var max_width := clampf(size.x - reading_reserve, 160.0, size.x * 0.38)
			var placeholder_height := _line_height * 4.5
			var placeholder_width := clampf(placeholder_height * 4.0 / 3.0, minf(220.0, max_width), max_width)
			var placeholder_side := str(placeholder.get("side", "right"))
			if placeholder_side not in ["left", "right"]:
				placeholder_side = "right" if right_side else "left"
			right_side = placeholder_side == "left"
			var placeholder_rect := Rect2(
				Vector2(size.x - placeholder_width if placeholder_side == "right" else 0.0, y + 4.0),
				Vector2(placeholder_width, placeholder_height)
			)
			for existing in _article_image_bounds:
				var existing_rect: Rect2 = existing.rect
				if placeholder_rect.intersects(existing_rect):
					placeholder_rect.position.y = existing_rect.end.y + 14.0
			_article_image_bounds.append({"rect": placeholder_rect, "side": placeholder_side})
			_placeholder_bounds.append({"rect": placeholder_rect, "side": placeholder_side})
		for image in anchored_images:
			var item: Dictionary = image.duplicate(true)
			var texture: Texture2D = item.texture
			var texture_size := texture.get_size() if texture != null else Vector2(768, 576)
			if texture_size.x <= 0.0 or texture_size.y <= 0.0:
				texture_size = Vector2(768, 576)
			var target_height := _line_height * 4.5
			var target_width := target_height * texture_size.x / texture_size.y
			var sample_unit := _unit_width(font, "汉", "hàn", pinyin_size)
			var reading_reserve := sample_unit * 8.0 + 24.0
			var max_width := clampf(size.x - reading_reserve, 160.0, size.x * 0.38)
			target_width = clampf(target_width, minf(220.0, max_width), max_width)
			target_height = target_width * texture_size.y / texture_size.x
			var side := str(item.get("side", "right"))
			if side not in ["left", "right"]:
				side = "right" if right_side else "left"
			right_side = side == "left"
			var image_rect := Rect2(
				Vector2(size.x - target_width if side == "right" else 0.0, y + 4.0),
				Vector2(target_width, target_height)
			)
			for existing in _article_image_bounds:
				var existing_rect: Rect2 = existing.rect
				if image_rect.intersects(existing_rect):
					image_rect.position.y = existing_rect.end.y + 14.0
			var image_entry := {
				"texture": texture,
				"rect": image_rect,
				"side": side,
				"alt": str(item.get("alt", "")),
			}
			_article_images.append(image_entry)
			_article_image_bounds.append(image_entry)
		var start_cell := _article_cells.size()
		var paragraph_text := str(paragraph.get("text", ""))
		var paragraph_pinyin: Array = paragraph.get("pinyin", []) if paragraph.get("pinyin") is Array else []
		var line_y := y
		var bounds := _line_bounds(line_y)
		var x := float(bounds.left)
		for character_index in paragraph_text.length():
			var character := paragraph_text.substr(character_index, 1)
			if character == "\n":
				line_y += _line_height
				bounds = _line_bounds(line_y)
				x = float(bounds.left)
				continue
			var annotation := str(paragraph_pinyin[character_index]) if show_pinyin and character_index < paragraph_pinyin.size() else ""
			var unit_width := _unit_width(font, character, annotation, pinyin_size)
			if character in OPENING_PUNCTUATION:
				var next_width := 0.0
				if character_index + 1 < paragraph_text.length():
					next_width = _unit_width(font, paragraph_text.substr(character_index + 1, 1), "", pinyin_size)
				if x > float(bounds.left) and x + unit_width + next_width > float(bounds.right):
					line_y += _line_height
					bounds = _line_bounds(line_y)
					x = float(bounds.left)
			if x + unit_width > float(bounds.right):
				if character in CLOSING_PUNCTUATION and _article_cells.size() > start_cell and x > float(bounds.left):
					var moved: Dictionary = _article_cells.pop_back()
					x = maxf(float(bounds.left), x - float(moved.width))
					line_y += _line_height
					bounds = _line_bounds(line_y)
					x = float(bounds.left)
					moved.x = x
					moved.y = line_y
					_article_cells.append(moved)
					x += float(moved.width)
				else:
					line_y += _line_height
					bounds = _line_bounds(line_y)
					x = float(bounds.left)
			_article_cells.append({
				"paragraphId": paragraph_id,
				"characterIndex": character_index,
				"character": character,
				"ruby": annotation,
				"role": str(paragraph.get("role", "story")),
				"x": x,
				"y": line_y,
				"width": unit_width,
			})
			x += unit_width
		_paragraph_ranges[paragraph_id] = [start_cell, _article_cells.size()]
		_paragraph_bottoms[paragraph_id] = line_y + _line_height
		y = line_y + _line_height
	if generation != _layout_generation:
		return
	var image_bottom := 0.0
	for image in _article_images:
		var rect: Rect2 = image.rect
		image_bottom = maxf(image_bottom, rect.end.y)
	_height = maxf(y + 16.0, image_bottom + 20.0)
	update_minimum_size()
	queue_redraw()


func _prepare_illustrations() -> Dictionary:
	var result: Dictionary = {}
	var fallback_side := "right"
	for value in _article_illustrations:
		if not value is Dictionary:
			continue
		var paragraph_id := str(value.get("paragraphId", value.get("paragraph_id", "")))
		var asset := str(value.get("asset", value.get("path", value.get("assetPath", ""))))
		if paragraph_id.is_empty():
			continue
		if asset.is_empty():
			_missing_illustrations += 1
			if not (paragraph_id in _missing_anchor_ids):
				_missing_anchor_ids.append(paragraph_id)
			continue
		var texture: Texture2D = _texture_cache.get(asset, null)
		if texture == null and ResourceLoader.exists(asset):
			texture = load(asset) as Texture2D
			_texture_cache[asset] = texture
		if texture == null and FileAccess.file_exists(asset):
			var bytes := FileAccess.get_file_as_bytes(asset)
			if not bytes.is_empty():
				var image := Image.new()
				if image.load_webp_from_buffer(bytes) == OK:
					texture = ImageTexture.create_from_image(image)
					_texture_cache[asset] = texture
		if texture == null:
			continue
		var item: Dictionary = value.duplicate(true)
		item.texture = texture
		var side := str(item.get("side", fallback_side))
		if side not in ["left", "right"]:
			side = fallback_side
		item.side = side
		fallback_side = "left" if side == "right" else "right"
		if not result.has(paragraph_id):
			result[paragraph_id] = []
		result[paragraph_id].append(item)
	return result


func _placeholder_images(paragraph_id: String) -> Array:
	var result: Array = []
	for value in _article_illustrations:
		if not value is Dictionary:
			continue
		if str(value.get("paragraphId", "")) != paragraph_id:
			continue
		result.append({
			"side": str(value.get("side", "right")),
			"alt": str(value.get("alt", "")),
		})
	return result


func _line_bounds(line_y: float) -> Dictionary:
	var left := 0.0
	var right := size.x
	for image in _article_image_bounds:
		var rect: Rect2 = image.rect
		if line_y + _line_height <= rect.position.y or line_y >= rect.end.y:
			continue
		if str(image.side) == "right":
			right = minf(right, rect.position.x - 24.0)
		else:
			left = maxf(left, rect.end.x + 24.0)
	return {"left": left, "right": right}


func _unit_width(font: Font, character: String, annotation: String, pinyin_size: int) -> float:
	var width := font.get_string_size(character, HORIZONTAL_ALIGNMENT_LEFT, -1, text_size).x + 3.0
	if not annotation.is_empty():
		width = maxf(width, font.get_string_size(annotation, HORIZONTAL_ALIGNMENT_LEFT, -1, pinyin_size).x + 5.0)
	return minf(width, size.x)


func _draw() -> void:
	if _article_mode:
		_draw_article()
	else:
		_draw_simple()


func _draw_simple() -> void:
	var font := PlaygroundUI.font()
	var pinyin_size := maxi(14, int(text_size * 0.48))
	var ruby_height := float(pinyin_size + 7) if show_pinyin else 0.0
	for cell in _cells:
		_draw_cell(font, cell, pinyin_size, ruby_height, PlaygroundUI.INK)


func _draw_article() -> void:
	var font := PlaygroundUI.font()
	var pinyin_size := maxi(14, int(text_size * 0.48))
	var ruby_height := float(pinyin_size + 7) if show_pinyin else 0.0
	for image in _article_images:
		var rect: Rect2 = image.rect
		draw_style_box(
			PlaygroundUI.style(Color("#f8f0df"), 20, Color("#d8cdb9"), 2, 5, Color(0, 0, 0, 0.12)),
			rect.grow(5.0)
		)
		if image.texture != null:
			draw_texture_rect(image.texture, rect, false)
	for placeholder in _placeholder_bounds:
		var rect: Rect2 = placeholder.rect
		draw_style_box(
			PlaygroundUI.style(Color("#f8f0df"), 20, Color("#d8cdb9"), 2, 5, Color(0, 0, 0, 0.12)),
			rect
		)
		draw_string(
			font,
			Vector2(rect.position.x + 18.0, rect.position.y + rect.size.y * 0.5),
			"插画加载中",
			HORIZONTAL_ALIGNMENT_CENTER,
			rect.size.x - 36.0,
			18,
			PlaygroundUI.INK_SOFT
		)
	for cell in _article_cells:
		if str(cell.paragraphId) == _highlight_paragraph_id:
			draw_rect(
				Rect2(float(cell.x) - 1.0, float(cell.y) + 2.0, float(cell.width) + 2.0, _line_height - 4.0),
				Color(highlight_tint, 0.72)
			)
	for cell in _article_cells:
		var tint := PlaygroundUI.INK_SOFT if str(cell.role) in ["meaning", "example"] else PlaygroundUI.INK
		_draw_cell(font, cell, pinyin_size, ruby_height, tint)
	if _missing_illustrations > 0:
		draw_string(
			font,
			Vector2(16, size.y - 20),
			"插画正在加载 · 可先继续阅读",
			HORIZONTAL_ALIGNMENT_LEFT,
			size.x - 32,
			15,
			PlaygroundUI.INK_SOFT
		)


func _draw_cell(font: Font, cell: Dictionary, pinyin_size: int, ruby_height: float, tint: Color) -> void:
	var character := str(cell.get("text", cell.get("character", "")))
	var annotation := str(cell.get("ruby", ""))
	var character_width := font.get_string_size(character, HORIZONTAL_ALIGNMENT_LEFT, -1, text_size).x
	var origin := Vector2(float(cell.x), float(cell.y))
	if show_pinyin and not annotation.is_empty():
		var ruby_width := font.get_string_size(annotation, HORIZONTAL_ALIGNMENT_LEFT, -1, pinyin_size).x
		draw_string(
			font,
			origin + Vector2((float(cell.width) - ruby_width) * 0.5, font.get_ascent(pinyin_size)),
			annotation,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			pinyin_size,
			PlaygroundUI.INK_SOFT
		)
	draw_string(
		font,
		origin + Vector2((float(cell.width) - character_width) * 0.5, ruby_height + font.get_ascent(text_size)),
		character,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		text_size,
		tint
	)
