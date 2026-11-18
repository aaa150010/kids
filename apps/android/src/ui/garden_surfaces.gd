class_name GardenSurfaces
extends RefCounted


static func surface(path: String, margin_size: float, padding: float) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = load("res://assets/garden/runtime/" + path)
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		style.set_texture_margin(side, margin_size)
		style.set_content_margin(side, padding)
	return style


static func panel(_background: Color = PlaygroundUI.PAPER, _radius: int = 20, _border: Color = Color.TRANSPARENT, _border_width: int = 1) -> PanelContainer:
	var result := PanelContainer.new()
	result.add_theme_stylebox_override("panel", surface("ui/parchment-button.webp", 6, 18))
	return result


static func skin_button(node: Button) -> void:
	var normal := surface("ui/parchment-button.webp", 6, 12)
	node.add_theme_stylebox_override("normal", normal)
	node.add_theme_stylebox_override("hover", normal)
	node.add_theme_stylebox_override("pressed", normal)
	var focus := PlaygroundUI.style(Color.TRANSPARENT, 7, Color("#715027"), 2)
	node.add_theme_stylebox_override("focus", focus)
	for name in ["font_color", "font_hover_color", "font_pressed_color"]:
		node.add_theme_color_override(name, Color("#3c2b1a"))


static func button(text: String, accent: Color, callback: Callable, kind: String = "primary") -> Button:
	var node := PlaygroundUI.button(text, accent, callback, kind)
	skin_button(node)
	return node
