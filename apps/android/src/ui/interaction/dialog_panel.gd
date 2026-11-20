class_name DialogPanel
extends RefCounted


static func build(
	opts: Dictionary,
	viewport_size: Vector2,
	card_width: float,
	on_close: Callable
) -> Dictionary:
	var accent: Color = opts.get("accent", Color("#167d74"))
	var card := PanelContainer.new()
	var panel_style := PlaygroundUI.style(
		PlaygroundUI.PAPER,
		28,
		PlaygroundUI.mix(accent, PlaygroundUI.TOOL_LINE, 0.35),
		2,
		12,
		Color(0, 0, 0, 0.22)
	)
	panel_style.content_margin_left = 26
	panel_style.content_margin_right = 26
	panel_style.content_margin_top = 22
	panel_style.content_margin_bottom = 22
	card.add_theme_stylebox_override("panel", panel_style)
	card.custom_minimum_size = Vector2(card_width, 0)

	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", int(opts.get("separation", 16)))
	card.add_child(column)

	var eyebrow := str(opts.get("eyebrow", ""))
	var title := str(opts.get("title", ""))
	var dismissible := bool(opts.get("dismissible", true))
	if dismissible or not eyebrow.is_empty() or not title.is_empty():
		var header := HBoxContainer.new()
		header.add_theme_constant_override("separation", 16)
		var heading := VBoxContainer.new()
		heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		heading.add_theme_constant_override("separation", 3)
		if not eyebrow.is_empty():
			heading.add_child(PlaygroundUI.label(eyebrow, 15, accent, 700))
		if not title.is_empty():
			heading.add_child(PlaygroundUI.label(title, 30, PlaygroundUI.INK_DARK, 700, true))
		header.add_child(heading)
		if dismissible:
			var close := PlaygroundUI.semantic_icon_button("close", "", accent, on_close, "soft", 18)
			close.focus_mode = Control.FOCUS_NONE
			close.custom_minimum_size = Vector2(54, 54)
			close.tooltip_text = "关闭"
			header.add_child(close)
		column.add_child(header)
		column.add_child(PlaygroundUI.separator(PlaygroundUI.TOOL_LINE))

	var body_value: Variant = opts.get("body")
	var body: Control
	if body_value is Control:
		body = body_value
	else:
		body = PlaygroundUI.label("" if body_value == null else str(body_value), 17, PlaygroundUI.INK_SOFT, 500, true)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var body_scroll: ScrollContainer
	var fit_content := bool(opts.get("fit_content", false))
	if fit_content or not bool(opts.get("scroll", true)):
		column.add_child(body)
	else:
		body_scroll = ScrollContainer.new()
		body_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		body_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
		body_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		body_scroll.add_child(body)
		body_scroll.custom_minimum_size.y = minf(
			maxf(52.0, body.get_combined_minimum_size().y),
			body_limit(viewport_size, opts)
		)
		column.add_child(body_scroll)

	var layout := str(opts.get("layout", "standard"))
	var primary_action: Dictionary = opts.get("primary_action", {})
	var tool_actions: Array = opts.get("tool_actions", [])
	var extra_actions: Array = opts.get("extra_actions", [])
	var buttons: Array = opts.get("buttons", [])
	if layout == "pause":
		if not extra_actions.is_empty():
			column.add_child(PlaygroundUI.separator(PlaygroundUI.TOOL_LINE))
			column.add_child(PlaygroundUI.label("本局工具", 16, PlaygroundUI.INK_SOFT, 700))
			column.add_child(_grouped_actions(extra_actions, accent, 84, 19))
		if not tool_actions.is_empty():
			column.add_child(PlaygroundUI.separator(PlaygroundUI.TOOL_LINE))
			column.add_child(_pause_tools(tool_actions, accent))
		if not primary_action.is_empty():
			column.add_child(_full_action(primary_action, accent, 68, 22))
	elif not buttons.is_empty():
		column.add_child(PlaygroundUI.separator(PlaygroundUI.TOOL_LINE))
		column.add_child(_standard_actions(buttons, accent))

	return {
		"card": card,
		"column": column,
		"body": body,
		"body_scroll": body_scroll,
	}


static func body_limit(viewport_size: Vector2, opts: Dictionary = {}) -> float:
	var max_card_height := minf(maxf(320.0, viewport_size.y - 48.0), 900.0)
	var limit := maxf(180.0, max_card_height - 250.0)
	if opts.has("max_content_height"):
		limit = minf(limit, maxf(120.0, float(opts["max_content_height"])))
	return limit


static func update_body_limit(
	body_scroll: ScrollContainer,
	body: Control,
	viewport_size: Vector2,
	opts: Dictionary
) -> void:
	body_scroll.custom_minimum_size.y = minf(
		maxf(52.0, body.get_combined_minimum_size().y),
		body_limit(viewport_size, opts)
	)


static func _pause_tools(actions: Array, accent: Color) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	var index := 0
	while index < actions.size():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		for offset in 2:
			var action_index := index + offset
			if action_index >= actions.size():
				break
			row.add_child(_action_button(actions[action_index], accent, 90, 20, true))
		box.add_child(row)
		index += 2
	return box


static func _standard_actions(actions: Array, accent: Color) -> Control:
	if actions.size() == 1:
		return _full_action(actions[0], accent, 64, 22)
	if actions.size() == 2:
		return _equal_row(actions, accent, 64, 22)
	if actions.size() == 3:
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 12)
		box.add_child(_equal_row([actions[0], actions[1]], accent, 60, 21))
		box.add_child(_full_action(actions[2], accent, 68, 22))
		return box
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	for action in actions:
		grid.add_child(_action_button(action, accent, 60, 20, true))
	return grid


static func _grouped_actions(actions: Array, accent: Color, height: int, font_size: int) -> Control:
	if actions.size() == 1:
		return _full_action(actions[0], accent, height, font_size)
	if actions.size() == 2:
		return _equal_row(actions, accent, height, font_size)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	if actions.size() >= 2:
		box.add_child(_equal_row([actions[0], actions[1]], accent, height, font_size))
	if actions.size() >= 3:
		box.add_child(_full_action(actions[2], accent, height, font_size))
	return box


static func _equal_row(actions: Array, accent: Color, height: int, font_size: int) -> Control:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 12)
	for action in actions:
		row.add_child(_action_button(action, accent, height, font_size, true))
	return row


static func _full_action(action: Dictionary, accent: Color, height: int, font_size: int) -> Button:
	return _action_button(action, accent, height, font_size, true)


static func _action_button(
	action: Dictionary,
	accent: Color,
	height: int,
	font_size: int,
	expand: bool = false
) -> Button:
	var kind := str(action.get("kind", "primary"))
	var button: Button
	if action.has("icon"):
		button = PlaygroundUI.semantic_icon_button(
			str(action["icon"]),
			str(action.get("text", "好")),
			accent,
			action.get("callback", Callable()),
			kind,
			font_size
		)
	else:
		button = PlaygroundUI.button(
			str(action.get("text", "好")),
			accent,
			action.get("callback", Callable()),
			kind
		)
	button.custom_minimum_size = Vector2(0, height)
	button.add_theme_font_size_override("font_size", font_size)
	if expand:
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return button
