class_name PlaygroundUI
extends RefCounted

const DEFAULT_SIZE := 20
const INK := Color("#2e241f")
const INK_DARK := Color("#171b20")
const INK_SOFT := Color("#716052")
const PAPER := Color("#fffdf7")
const CREAM := Color("#fff9eb")
const TOOL_BG := Color("#fff9ed")
const TOOL_HOVER := Color("#fffdf7")
const TOOL_PRESSED := Color("#f1eadb")
const TOOL_LINE := Color("#d9d0be")
const DANGER := Color("#b57926")
const DANGER_INK := Color("#744515")
const LINE := Color("#2e241f20")
const BREAKPOINT_COMPACT := 1180.0
const BREAKPOINT_WIDE := 1550.0
const TOUCH_MIN := 48.0
const TOUCH_PRIMARY := 56.0

static var _font: Font
static var _heavy_font: Font
static var _emoji_font: Font


static func font() -> Font:
	if _font == null:
		if ResourceLoader.exists("res://assets/fonts/NotoSansCJKsc-Content.otf"):
			var content_font: FontFile = load("res://assets/fonts/NotoSansCJKsc-Content.otf")
			content_font.allow_system_fallback = true
			var names := SystemFont.new()
			names.font_names = PackedStringArray(["Noto Sans CJK SC", "Noto Sans SC", "sans-serif"])
			names.allow_system_fallback = true
			content_font.fallbacks = [names]
			_font = content_font
		else:
			_font = ThemeDB.fallback_font
	return _font


static func install_theme(root: Control) -> void:
	var theme := Theme.new()
	theme.default_font = font()
	theme.default_font_size = DEFAULT_SIZE
	theme.set_color("font_color", "Label", INK)
	theme.set_color("font_color", "Button", INK)
	theme.set_color("font_hover_color", "Button", INK)
	theme.set_color("font_pressed_color", "Button", INK_DARK)
	root.theme = theme


static func color(value: String, fallback: Color = INK) -> Color:
	return Color(value) if Color.html_is_valid(value) else fallback


static func mix(base: Color, other: Color, amount: float) -> Color:
	return base.lerp(other, clampf(amount, 0.0, 1.0))


static func on_accent(accent: Color) -> Color:
	var luminance := accent.r * 0.2126 + accent.g * 0.7152 + accent.b * 0.0722
	return INK_DARK if luminance >= 0.24 else Color.WHITE


static func style(
	background: Color,
	radius: int = 20,
	border_color: Color = Color.TRANSPARENT,
	border_width: int = 0,
	shadow_size: int = 0,
	shadow_color: Color = Color.TRANSPARENT
) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = background
	box.corner_radius_top_left = radius
	box.corner_radius_top_right = radius
	box.corner_radius_bottom_left = radius
	box.corner_radius_bottom_right = radius
	box.border_width_left = border_width
	box.border_width_top = border_width
	box.border_width_right = border_width
	box.border_width_bottom = border_width
	box.border_color = border_color
	if shadow_size > 0:
		box.shadow_size = shadow_size
		box.shadow_color = shadow_color
		box.shadow_offset = Vector2(0, maxf(2.0, shadow_size * 0.45))
	box.content_margin_left = 16
	box.content_margin_right = 16
	box.content_margin_top = 12
	box.content_margin_bottom = 12
	return box


static func label(
	text: String,
	size: int = DEFAULT_SIZE,
	tint: Color = INK,
	weight: int = 500,
	wrap: bool = false
) -> Label:
	var node := Label.new()
	node.text = text
	node.add_theme_font_override("font", font())
	node.add_theme_font_size_override("font_size", size)
	node.add_theme_color_override("font_color", tint)
	node.add_theme_constant_override("outline_size", 0)
	if weight >= 700:
		node.add_theme_font_override("font", _bold_font())
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if wrap else TextServer.AUTOWRAP_OFF
	node.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return node


static func _bold_font() -> Font:
	if _heavy_font == null:
		var variation := FontVariation.new()
		variation.base_font = font()
		variation.variation_embolden = 0.5
		variation.fallbacks = [emoji_font()]
		_heavy_font = variation
	return _heavy_font


static func emoji_font() -> Font:
	if _emoji_font == null:
		if OS.get_name() not in ["Android", "macOS", "Windows"]:
			_emoji_font = font()
			return _emoji_font
		var system_font := SystemFont.new()
		system_font.font_names = PackedStringArray([
			"Noto Color Emoji",
			"Apple Color Emoji",
			"Segoe UI Emoji",
			"sans-serif",
		])
		system_font.allow_system_fallback = true
		_emoji_font = system_font
	return _emoji_font


static func layout_metrics(viewport_size: Vector2) -> Dictionary:
	var width := maxf(1.0, viewport_size.x)
	var mode := "compact" if width < BREAKPOINT_COMPACT else "wide" if width >= BREAKPOINT_WIDE else "standard"
	return {
		"mode": mode,
		"columns": 2 if mode == "compact" else 3 if mode == "standard" else 4,
		"margin": 16.0 if mode == "compact" else 20.0 if mode == "standard" else 24.0,
		"gap": 18.0 if mode == "compact" else 24.0,
		"topbar": 60.0 if mode == "compact" else 64.0,
		"card_min_width": 300.0,
		"compact_cards": mode == "compact",
	}


static func fit_text(size: int, compact: bool, minimum: int = 12) -> int:
	return maxi(minimum, size - (2 if compact else 0))


static func safe_insets(viewport_size: Vector2) -> Dictionary:
	var empty := {"left":0.0,"top":0.0,"right":0.0,"bottom":0.0}
	if not DisplayServer.has_method("get_display_safe_area"):
		return empty
	var screen := DisplayServer.screen_get_size(DisplayServer.window_get_current_screen())
	var safe: Rect2i = DisplayServer.get_display_safe_area()
	if screen.x <= 0 or screen.y <= 0 or safe.size.x <= 0 or safe.size.y <= 0:
		return empty
	var scale := Vector2(viewport_size.x/float(screen.x),viewport_size.y/float(screen.y))
	return {
		"left": maxf(0.0,float(safe.position.x)*scale.x),
		"top": maxf(0.0,float(safe.position.y)*scale.y),
		"right": maxf(0.0,float(screen.x-(safe.position.x+safe.size.x))*scale.x),
		"bottom": maxf(0.0,float(screen.y-(safe.position.y+safe.size.y))*scale.y),
	}


static func icon(text: String, size: int = 28) -> Label:
	var node := label(text, size, INK, 700)
	node.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return node


static func panel(
	background: Color = PAPER,
	radius: int = 24,
	border_color: Color = LINE,
	border_width: int = 1
) -> PanelContainer:
	var node := PanelContainer.new()
	node.add_theme_stylebox_override("panel", style(background, radius, border_color, border_width))
	return node


static func margin(child: Control, values: int = 18) -> MarginContainer:
	var node := MarginContainer.new()
	node.add_theme_constant_override("margin_left", values)
	node.add_theme_constant_override("margin_right", values)
	node.add_theme_constant_override("margin_top", values)
	node.add_theme_constant_override("margin_bottom", values)
	node.add_child(child)
	return node


static func button(
	text: String,
	accent: Color,
	on_pressed: Callable,
	kind: String = "primary"
) -> Button:
	var node := Button.new()
	node.text = text
	node.custom_minimum_size = Vector2(0, TOUCH_PRIMARY)
	node.focus_mode = Control.FOCUS_ALL
	node.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	node.add_theme_font_override("font", _bold_font())
	node.add_theme_font_size_override("font_size", 20)
	var foreground := on_accent(accent)
	var normal := style(
		accent,
		18,
		mix(accent, Color.BLACK, 0.18),
		2,
		5,
		Color(0, 0, 0, 0.18)
	)
	normal.content_margin_left = 22
	normal.content_margin_right = 22
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = mix(accent, Color.WHITE, 0.12)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = mix(accent, Color.BLACK, 0.12)
	pressed.shadow_size = 1
	pressed.shadow_offset = Vector2.ZERO
	var focus := normal.duplicate() as StyleBoxFlat
	focus.bg_color = accent
	focus.border_color = foreground
	focus.border_width_left = 4
	focus.border_width_top = 4
	focus.border_width_right = 4
	focus.border_width_bottom = 4
	node.add_theme_color_override("font_color", foreground)
	node.add_theme_color_override("font_hover_color", foreground)
	node.add_theme_color_override("font_pressed_color", foreground)
	if kind == "soft":
		normal = style(TOOL_BG, 18, TOOL_LINE, 2, 3, Color(0, 0, 0, 0.10))
		hover = normal.duplicate() as StyleBoxFlat
		hover.bg_color = TOOL_HOVER
		pressed = normal.duplicate() as StyleBoxFlat
		pressed.bg_color = TOOL_PRESSED
		pressed.shadow_size = 1
		focus = normal.duplicate() as StyleBoxFlat
		focus.border_color = accent
		focus.border_width_left = 4
		focus.border_width_top = 4
		focus.border_width_right = 4
		focus.border_width_bottom = 4
		node.add_theme_color_override("font_color", INK_DARK)
		node.add_theme_color_override("font_hover_color", INK_DARK)
		node.add_theme_color_override("font_pressed_color", INK)
	elif kind == "ghost":
		normal = style(Color(1, 1, 1, 0.56), 18, TOOL_LINE, 1)
		hover = normal.duplicate() as StyleBoxFlat
		hover.bg_color = TOOL_HOVER
		pressed = normal.duplicate() as StyleBoxFlat
		pressed.bg_color = TOOL_PRESSED
		focus = normal.duplicate() as StyleBoxFlat
		focus.border_color = accent
		focus.border_width_left = 4
		focus.border_width_top = 4
		focus.border_width_right = 4
		focus.border_width_bottom = 4
		node.add_theme_color_override("font_color", INK)
		node.add_theme_color_override("font_hover_color", INK)
		node.add_theme_color_override("font_pressed_color", INK_SOFT)
	elif kind == "danger":
		normal = style(TOOL_BG, 18, DANGER, 2, 2, Color(0, 0, 0, 0.08))
		hover = normal.duplicate() as StyleBoxFlat
		hover.bg_color = TOOL_HOVER
		pressed = normal.duplicate() as StyleBoxFlat
		pressed.bg_color = Color("#f5ead8")
		focus = normal.duplicate() as StyleBoxFlat
		focus.border_color = DANGER
		focus.border_width_left = 4
		focus.border_width_top = 4
		focus.border_width_right = 4
		focus.border_width_bottom = 4
		node.add_theme_color_override("font_color", DANGER_INK)
		node.add_theme_color_override("font_hover_color", DANGER_INK)
		node.add_theme_color_override("font_pressed_color", DANGER_INK)
	node.add_theme_color_override("font_focus_color", node.get_theme_color("font_color") if node.has_theme_color_override("font_color") else foreground)
	node.add_theme_color_override("icon_focus_color", node.get_theme_color("font_color") if node.has_theme_color_override("font_color") else foreground)
	node.add_theme_stylebox_override("normal", normal)
	node.add_theme_stylebox_override("hover", hover)
	node.add_theme_stylebox_override("pressed", pressed)
	node.add_theme_stylebox_override("focus", focus)
	node.add_theme_stylebox_override("disabled", style(Color("#eee9de"), 18, TOOL_LINE, 1))
	node.add_theme_color_override("font_disabled_color", Color(0.55, 0.5, 0.45, 0.75))
	if on_pressed.is_valid():
		node.pressed.connect(on_pressed)
	# 统一按压反馈：按下缩放 + 短音效，释放回弹（W1 PressFeedback）
	PressFeedback.attach(node, &"tap")
	node.resized.connect(func(): node.pivot_offset = node.size * 0.5)
	return node


static func icon_button(symbol: String, tint: Color, on_pressed: Callable, tooltip: String = "") -> Button:
	var node := button(symbol, tint, on_pressed, "soft")
	node.custom_minimum_size = Vector2(52, 52)
	node.tooltip_text = tooltip
	node.add_theme_font_size_override("font_size", 26)
	return node


static func icon_asset_button(icon_token: String, tint: Color, on_pressed: Callable, tooltip: String = "") -> Button:
	var node := button("", tint, on_pressed, "soft")
	node.custom_minimum_size = Vector2(52, 52)
	node.tooltip_text = tooltip
	var icon := ArtLibrary.semantic_picture(icon_token, "ui", Vector2(28, 28))
	icon.name = "ButtonIcon"
	icon.size = Vector2(28, 28)
	icon.position = Vector2(12, 12)
	node.add_child(icon)
	node.resized.connect(func():
		if is_instance_valid(icon):
			icon.position = (node.size - Vector2(28, 28)) * 0.5
	)
	return node


static func icon_text_button(icon_token: String, text: String, tint: Color, on_pressed: Callable, kind: String = "soft", font_size: int = 19) -> Button:
	var node := button(text, tint, on_pressed, kind)
	node.add_theme_font_size_override("font_size", font_size)
	node.alignment = HORIZONTAL_ALIGNMENT_LEFT
	var icon := ArtLibrary.semantic_picture(icon_token, "ui", Vector2(28, 28))
	icon.name = "ButtonIcon"
	icon.size = Vector2(28, 28)
	icon.position = Vector2(18, 14)
	node.add_child(icon)
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var box := node.get_theme_stylebox(state)
		if box is StyleBoxFlat:
			var copy := box.duplicate() as StyleBoxFlat
			copy.content_margin_left += 42
			copy.content_margin_right = maxf(12.0, copy.content_margin_right - 8.0)
			node.add_theme_stylebox_override(state, copy)
	node.resized.connect(func():
		if is_instance_valid(icon):
			icon.position = Vector2(18, (node.size.y - 28) * 0.5)
	)
	return node


static func semantic_icon_button(
	semantic: String,
	label: String,
	tint: Color,
	on_pressed: Callable,
	kind: String = "soft",
	font_size: int = 20
) -> Button:
	var node := button(label, tint, on_pressed, kind)
	node.add_theme_font_size_override("font_size", font_size)
	node.alignment = HORIZONTAL_ALIGNMENT_LEFT
	var image := ArtLibrary.semantic_picture(semantic, "ui", Vector2(28, 28))
	image.name = "SemanticIcon"
	image.size = Vector2(28, 28)
	image.position = Vector2(16, 14)
	node.add_child(image)
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var box := node.get_theme_stylebox(state)
		if box is StyleBoxFlat:
			var copy := box.duplicate() as StyleBoxFlat
			copy.content_margin_left += 42
			copy.content_margin_right = maxf(12.0, copy.content_margin_right - 8.0)
			node.add_theme_stylebox_override(state, copy)
	node.resized.connect(func():
		if is_instance_valid(image):
			image.position = Vector2(16, (node.size.y - 28) * 0.5)
	)
	return node


static func choice_button(
	text: String,
	accent: Color,
	group: ButtonGroup,
	value: Variant,
	selected: bool,
	minimum_size: Vector2 = Vector2(0, 50),
	font_size: int = 18
) -> Button:
	var node := button(text, accent, func(): pass, "soft")
	node.toggle_mode = true
	node.button_group = group
	node.button_pressed = selected
	node.custom_minimum_size = minimum_size
	node.add_theme_font_size_override("font_size", font_size)
	node.set_meta("choice_value", value)
	var active := style(accent, 16, mix(accent, Color.BLACK, 0.2), 2, 4, Color(0, 0, 0, 0.16))
	active.content_margin_left = 14
	active.content_margin_right = 14
	var active_hover := active.duplicate() as StyleBoxFlat
	active_hover.bg_color = mix(accent, Color.WHITE, 0.1)
	node.add_theme_stylebox_override("pressed", active)
	node.add_theme_stylebox_override("hover_pressed", active_hover)
	var active_foreground := on_accent(accent)
	node.add_theme_color_override("font_pressed_color", active_foreground)
	node.add_theme_color_override("font_hover_pressed_color", active_foreground)
	return node


static func text_field(placeholder: String, value: String, accent: Color) -> LineEdit:
	var node := LineEdit.new()
	node.text = value
	node.placeholder_text = placeholder
	node.custom_minimum_size.y = 58
	node.add_theme_font_override("font", font())
	node.add_theme_font_size_override("font_size", 21)
	node.add_theme_color_override("font_color", INK)
	node.add_theme_color_override("font_placeholder_color", mix(INK_SOFT, Color.WHITE, 0.48))
	node.add_theme_color_override("caret_color", accent)
	node.add_theme_color_override("selection_color", Color(accent, 0.22))
	var normal := style(Color("#fffdf8"), 17, mix(accent, Color.WHITE, 0.55), 2)
	normal.content_margin_left = 18
	normal.content_margin_right = 18
	normal.content_margin_top = 14
	normal.content_margin_bottom = 14
	var focus := normal.duplicate() as StyleBoxFlat
	focus.bg_color = Color.WHITE
	focus.border_color = accent
	focus.border_width_left = 3
	focus.border_width_top = 3
	focus.border_width_right = 3
	focus.border_width_bottom = 3
	node.add_theme_stylebox_override("normal", normal)
	node.add_theme_stylebox_override("focus", focus)
	node.add_theme_stylebox_override("read_only", normal)
	return node


static func chip(text: String, accent: Color) -> PanelContainer:
	var node := panel(mix(accent, Color.WHITE, 0.82), 999, mix(accent, Color.WHITE, 0.3), 1)
	node.custom_minimum_size = Vector2(0, 34)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var label_text := text
	var icon_token := ""
	for symbol in ArtLibrary.symbols(text):
		if text.begins_with(str(symbol)):
			icon_token = str(symbol)
			label_text = text.substr(icon_token.length()).strip_edges()
			break
	var content := label(label_text, 14, mix(accent, Color.BLACK, 0.25), 700)
	content.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_theme_constant_override("outline_size", 0)
	row.add_child(content)
	node.add_child(row)
	return node


static func separator(tint: Color = LINE) -> HSeparator:
	var node := HSeparator.new()
	var line := StyleBoxLine.new()
	line.color = tint
	line.thickness = 1
	node.add_theme_stylebox_override("separator", line)
	return node


static func clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()


static func fade_in(node: CanvasItem, duration: float = 0.22, from_y: float = 12.0) -> void:
	MotionKit.fade_in(node, null, duration, from_y)


static func press_pop(node: Control) -> void:
	if node.has_meta("press_feedback"):
		return
	MotionKit.press_pop(node)


static func background(accent: Color) -> Control:
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([
		mix(Color("#f4f9e9"), accent, 0.06),
		Color("#fff9eb"),
		mix(Color("#e5f3ee"), accent, 0.08),
	])
	gradient.offsets = PackedFloat32Array([0.0, 0.58, 1.0])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_from = Vector2(0, 0)
	texture.fill_to = Vector2(1, 1)
	var rect := TextureRect.new()
	rect.texture = texture
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(rect)
	return root
