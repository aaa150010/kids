class_name GameBrowser
extends VBoxContainer

signal entry_selected(entry_id: Variant)

var accent := Color("#99644f")
var _entries: Array = []
var _cards: Array[Button] = []
var _grid: GridContainer
var _scroll: ScrollContainer
var _empty: Control
var _empty_label: Label
var _search: LineEdit
var _query := ""
var _options: Dictionary = {}


func configure(entries: Array, options: Dictionary = {}) -> void:
	_entries = entries.duplicate(true)
	_options = options.duplicate(true)
	accent = options.get("accent", accent)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 10)
	_build()


func _build() -> void:
	PlaygroundUI.clear(self)
	_cards.clear()
	var title := str(_options.get("title", "")).strip_edges()
	var subtitle := str(_options.get("subtitle", "")).strip_edges()
	if not title.is_empty() or not subtitle.is_empty():
		var heading := VBoxContainer.new()
		heading.add_theme_constant_override("separation", 2)
		if not title.is_empty():
			heading.add_child(PlaygroundUI.label(title, 27, accent, 700, true))
		if not subtitle.is_empty():
			heading.add_child(PlaygroundUI.label(subtitle, 16, PlaygroundUI.INK_SOFT, 500, true))
		add_child(heading)
	if _entries.size() > 8:
		var search_row := HBoxContainer.new()
		search_row.add_theme_constant_override("separation", 8)
		_search = PlaygroundUI.text_field("搜索关卡或标题", _query, accent)
		_search.custom_minimum_size.y = 52
		_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_search.clear_button_enabled = true
		_search.text_changed.connect(func(value: String):
			_query = value
			_apply_filter()
		)
		search_row.add_child(_search)
		add_child(search_row)
	_scroll = SmoothScrollContainer.create() as ScrollContainer
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_grid = GridContainer.new()
	_grid.columns = 4
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 14)
	_grid.add_theme_constant_override("v_separation", 14)
	_scroll.add_child(_grid)
	add_child(_scroll)
	_empty = VBoxContainer.new()
	_empty.alignment = BoxContainer.ALIGNMENT_CENTER
	_empty.visible = false
	_empty_label = PlaygroundUI.label("没有找到这一页", 21, PlaygroundUI.INK_SOFT, 600, true)
	_empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty.add_child(_empty_label)
	add_child(_empty)
	if not resized.is_connected(_apply_columns):
		resized.connect(_apply_columns)
	if not tree_entered.is_connected(_apply_columns):
		tree_entered.connect(_apply_columns)
	if is_inside_tree():
		_apply_columns()
	for entry in _entries:
		_add_entry(entry)
	_apply_filter()


func _apply_columns() -> void:
	if not is_inside_tree() or not is_instance_valid(_grid):
		return
	var width := get_viewport_rect().size.x
	_grid.columns = 2 if width < 1000.0 else 3 if width < 1280.0 else 4 if width < 1540.0 else 5


func _add_entry(entry: Dictionary) -> void:
	var number := int(entry.get("id", _cards.size() + 1))
	var locked := bool(entry.get("locked", false))
	var in_progress := bool(entry.get("in_progress", false))
	var stars := clampi(int(entry.get("stars", 0)), 0, 3)
	var title := str(entry.get("title", "第 %s 关" % number))
	var band := str(entry.get("subtitle", "")).strip_edges()
	var status := "进行中" if in_progress else ("继续完成前一关" if locked else ("已获 %s / 3 星" % stars if stars > 0 else "可以挑战"))
	var card_text := "第 %s 关\n%s\n%s" % [number, title, status]
	if not band.is_empty() and not locked:
		card_text += "\n%s" % band
	var icon := "continue" if in_progress else ("lock" if locked else "play")
	var button := PlaygroundUI.semantic_icon_button(
		icon,
		card_text,
		accent,
		func(): entry_selected.emit(number),
		"primary" if in_progress else "soft",
		18
	)
	button.custom_minimum_size = Vector2(0, 146)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.disabled = locked
	button.set_meta("entry", entry)
	button.set_meta("search_text", "%s %s %s %s" % [number, title, band, status])
	if in_progress:
		var progress := PlaygroundUI.chip("进行中", accent)
		progress.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		progress.position = Vector2(-106, 10)
		button.add_child(progress)
	_grid.add_child(button)
	_cards.append(button)


func _apply_filter() -> void:
	if not is_instance_valid(_grid):
		return
	var needle := _query.strip_edges().to_lower()
	var visible := 0
	for card in _cards:
		if not is_instance_valid(card):
			continue
		var entry: Dictionary = card.get_meta("entry", {})
		var search_text := str(card.get_meta("search_text", "")).to_lower()
		card.visible = needle.is_empty() or search_text.contains(needle)
		if card.visible:
			visible += 1
	if is_instance_valid(_empty) and is_instance_valid(_empty_label):
		var no_results := visible == 0
		_scroll.visible = not no_results
		_empty.visible = no_results
		if no_results:
			_empty_label.text = "没有找到“%s”这一页\n换个词试试。" % _query.strip_edges()
