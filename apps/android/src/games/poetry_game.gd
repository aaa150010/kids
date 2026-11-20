class_name NativePoetryGame
extends NativeGameScreen


## 自绘撒花：不依赖纹理，1 秒后自动释放；只动自绘参数
class ConfettiBurst extends Control:
	const LIFE := 1.1
	const PALETTE := [
		Color("#e8b84a"),
		Color("#f2938c"),
		Color("#8fc77e"),
		Color("#8657a7"),
		Color("#f6e3b4"),
	]

	var _pieces: Array = []
	var _elapsed := 0.0

	func launch(origin: Vector2) -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		for index in 30:
			var angle := randf_range(-PI * 0.92, -PI * 0.08)
			var speed := randf_range(150.0, 420.0)
			_pieces.append({
				"pos": origin + Vector2(randf_range(-70.0, 70.0), randf_range(-24.0, 18.0)),
				"vel": Vector2(cos(angle), sin(angle)) * speed,
				"angle": randf() * TAU,
				"spin": randf_range(-8.0, 8.0),
				"radius": randf_range(4.5, 10.0),
				"color": PALETTE[index % PALETTE.size()],
				"star": index % 4 == 0,
			})

	func _process(delta: float) -> void:
		_elapsed += delta
		if _elapsed >= LIFE:
			queue_free()
			return
		for piece in _pieces:
			piece["vel"] = Vector2(piece.vel.x, piece.vel.y + 620.0 * delta) * 0.99
			piece["pos"] = piece.pos + piece.vel * delta
			piece["angle"] = piece.angle + piece.spin * delta
		queue_redraw()

	func _draw() -> void:
		var fade := clampf(1.0 - _elapsed / LIFE, 0.0, 1.0)
		for piece in _pieces:
			var tint: Color = piece.color
			tint.a *= fade
			draw_set_transform(piece.pos, piece.angle, Vector2.ONE)
			if piece.star:
				draw_colored_polygon(_star(piece.radius), tint)
			else:
				draw_rect(Rect2(Vector2(-piece.radius, -piece.radius * 0.32), Vector2(piece.radius * 2.0, piece.radius * 0.64)), tint)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	func _star(radius: float) -> PackedVector2Array:
		var points := PackedVector2Array()
		for index in 10:
			var r := radius if index % 2 == 0 else radius * 0.46
			var angle := -PI * 0.5 + PI * 0.2 * index
			points.append(Vector2(cos(angle), sin(angle)) * r)
		return points


var current_poem: Dictionary = {}
var evaluation := ""
var mode := "draw"
var query := ""
var poem_font_size := 30
var library_scroll_y := 0
var library_page := 0
const LIBRARY_PAGE_SIZE := 40
var library_scroll: ScrollContainer = null
var known_ids: Array = []
var review_ids: Array = []
var used_ids: Array = []
var hide_text := false
var reported_current := false
var main_box: VBoxContainer
var library_box: VBoxContainer
var route_section := 0
var library_filter := "all"
var _draw_sequence := 0
var poem_scrolls: Dictionary = {}
var poem_scroll: ScrollContainer = null
var profile_panel: Control
var poem_line_labels: Array[Control] = []
# 当前诗卡与待播放的入场动画（"flip" 抽诗翻面 / "pop" 换一首弹入 / "" 直接显示）
var _card: Control = null
var _pending_transition := ""
var _advancing := false
var _busy := false


func _ready() -> void:
	build_shell()
	var player: Dictionary = players[0]
	var stored := SaveStore.load_state(game_id, [str(player.id)])
	_restore_snapshot(stored, str(player.id))
	var saved_font := _integer(SaveStore.settings().get("poetryFontSize", 0))
	var responsive_font := 38 if get_viewport_rect().size.y >= 1000 else 32
	var resolved_font := saved_font
	if saved_font <= 0 or (saved_font == 30 and get_viewport_rect().size.y >= 760):
		resolved_font = responsive_font
	poem_font_size = clampi(resolved_font, 24, 46)
	_render()
	call_deferred("begin_lesson")


func _restore_snapshot(value: Dictionary, profile_id: String) -> bool:
	if value.is_empty() or not _numeric(value.get("schemaVersion", 1)) or _integer(value.get("schemaVersion", 1)) != 1:
		return false
	var saved_player: Variant = value.get("player")
	if not saved_player is Dictionary:
		return false
	var saved_id := str(saved_player.get("id", ""))
	if saved_id != profile_id:
		return false
	if str(saved_player.get("name", "")).strip_edges().is_empty() or not _numeric(saved_player.get("age", 0)) or _integer(saved_player.get("age", 0)) not in range(4, 13):
		return false
	players = [saved_player.duplicate(true)]
	var valid_ids := {}
	for poem in ContentDB.poems:
		valid_ids[str(poem.id)] = true
	known_ids = _clean_poem_ids(value.get("knownIds", []), valid_ids)
	review_ids = _clean_poem_ids(value.get("reviewIds", []), valid_ids)
	used_ids = _clean_poem_ids(value.get("usedIds", []), valid_ids)
	var saved_evaluation := str(value.get("evaluation", ""))
	evaluation = saved_evaluation if saved_evaluation in ["known", "review"] else ""
	var saved_mode := str(value.get("mode", "draw"))
	mode = saved_mode if saved_mode in ["draw", "library", "route"] else "draw"
	current_poem = _find_poem(str(value.get("currentPoemId", "")))
	if current_poem.is_empty() or mode != "draw":
		evaluation = ""
	hide_text = bool(value.get("hideText", false))
	reported_current = bool(value.get("reportedCurrent", false)) and not evaluation.is_empty()
	query = str(value.get("query", "")).left(80)
	library_scroll_y = maxi(0, _integer(value.get("libraryScrollY", 0)))
	library_page = maxi(0, _integer(value.get("libraryPage", 0)))
	route_section = clampi(_integer(value.get("routeSection", 0)), 0, 5)
	var saved_filter := str(value.get("libraryFilter", "all"))
	library_filter = saved_filter if saved_filter in ["all", "age", "known", "review"] else "all"
	_draw_sequence = maxi(0, _integer(value.get("drawSequence", 0)))
	poem_scrolls = {}
	if value.get("poemScrolls") is Dictionary:
		for poem_id in value.poemScrolls:
			if not valid_ids.has(str(poem_id)) or not value.poemScrolls[poem_id] is Dictionary:
				continue
			var anchor: Dictionary = value.poemScrolls[poem_id]
			var ratio := clampf(float(anchor.get("ratio", 0.0)), 0.0, 1.0) if _numeric(anchor.get("ratio", 0.0)) else 0.0
			poem_scrolls[str(poem_id)] = {
				"line": maxi(0, _integer(anchor.get("line", 0))),
				"ratio": ratio,
			}
	return true


func _numeric(value: Variant) -> bool:
	if value is int or value is float:
		return is_finite(float(value))
	if value is String:
		return value.is_valid_float()
	return false


func _integer(value: Variant) -> int:
	if value is int:
		return int(value)
	if value is float and is_finite(value):
		return int(value)
	if value is String and value.is_valid_float():
		return int(float(value))
	return 0


func _clean_poem_ids(value: Variant, valid_ids: Dictionary) -> Array:
	var result: Array = []
	if not value is Array:
		return result
	for item in value:
		if item is String and valid_ids.has(item) and not (item in result):
			result.append(item)
	return result


func _render() -> void:
	# 整页重建会丢弃旧卡与其动画，这里同步解除翻面中的操作锁
	_busy = false
	_card = null
	# 只有抽诗页会播放卡片入场动画，其他页面的待播标记直接丢弃
	if mode != "draw":
		_pending_transition = ""
	# 诗卡自带入场动画时不再整页淡入，避免两段淡入之间出现空白
	var has_card_intro := not _pending_transition.is_empty()
	PlaygroundUI.clear(content_root)
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 14)
	profile_panel = _profile_panel()
	row.add_child(profile_panel)
	var main_panel := PlaygroundUI.panel(Color(1, 1, 1, 0.76), 28, PlaygroundUI.mix(accent, Color.WHITE, 0.55), 1)
	main_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_panel.modulate.a = 1.0 if has_card_intro else 0.0
	var backdrop := PoemBackdrop.new()
	backdrop.poem_text = str(current_poem.get("fullText",""))
	main_panel.add_child(backdrop)
	main_box = VBoxContainer.new()
	main_box.add_theme_constant_override("separation", 12)
	main_panel.add_child(main_box)
	main_box.add_child(_tabs())
	if mode == "route":
		main_box.add_child(_route_view())
	elif mode == "library":
		main_box.add_child(_library_view())
	else:
		main_box.add_child(_draw_view())
	row.add_child(main_panel)
	content_root.add_child(row)
	_on_immersive_changed(immersive)
	if not has_card_intro:
		MotionKit.tween(self).tween_property(main_panel,"modulate:a",1.0,0.18)


## 统一按钮入口：保留 PlaygroundUI 造型，并接入通用按压反馈
func _btn(text: String, tint: Color, on_pressed: Callable, kind: String = "primary") -> Button:
	var node := PlaygroundUI.button(text, tint, func():
		if not paused and not _busy:
			on_pressed.call()
	, kind)
	# 先补足触摸目标下限，避免按压反馈在布局前误判尺寸
	node.custom_minimum_size = Vector2(maxf(node.custom_minimum_size.x, 48.0), maxf(node.custom_minimum_size.y, 48.0))
	PressFeedback.attach(node, &"tap")
	return node


func _profile_panel() -> Control:
	var player: Dictionary = players[0]
	var tint := PlaygroundUI.color(str(player.get("color", "#8657a7")))
	var panel := PlaygroundUI.panel(PlaygroundUI.mix(tint, Color.WHITE, 0.9), 26, PlaygroundUI.mix(tint, Color.WHITE, 0.52), 2)
	panel.custom_minimum_size.x = 265
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	panel.add_child(column)
	column.add_child(PlaygroundUI.label("今天抽查谁？", 14, PlaygroundUI.INK_SOFT, 700))
	var player_card := HBoxContainer.new()
	player_card.add_theme_constant_override("separation", 12)
	player_card.add_child(ArtLibrary.picture(str(player.avatar),Vector2(68,78)))
	var info := VBoxContainer.new()
	info.add_child(PlaygroundUI.label(str(player.name), 24, PlaygroundUI.INK, 700))
	info.add_child(PlaygroundUI.label("%s 岁 · 家长抽诗，孩子背诵" % int(player.age), 13, PlaygroundUI.INK_SOFT, 500))
	player_card.add_child(info)
	column.add_child(player_card)
	var pool_size := maxi(1, ContentDB.poem_for_age(int(player.age)).size())
	var learned := _count_pool(known_ids)
	var reviewing := _count_pool(review_ids)
	var progress := PlaygroundUI.panel(PlaygroundUI.mix(tint, Color.WHITE, 0.82), 20, PlaygroundUI.mix(tint, Color.WHITE, 0.45), 1)
	var copy := VBoxContainer.new()
	copy.add_child(PlaygroundUI.label("适龄背诵进度", 13, PlaygroundUI.INK_SOFT, 700))
	copy.add_child(PlaygroundUI.label("%s / %s 首" % [learned, pool_size], 30, tint, 700))
	copy.add_child(PlaygroundUI.label("⭐ 已会 %s 首  ·  📖 待复习 %s 首" % [known_ids.size(), review_ids.size()], 14, PlaygroundUI.INK_SOFT, 500, true))
	progress.add_child(copy)
	column.add_child(progress)
	var note := PlaygroundUI.panel(Color("#fff8de"), 20, Color("#e4cc87"), 1)
	note.add_child(PlaygroundUI.label("💡 让孩子背对屏幕\n家长看诗句检查，点选结果后原诗仍会保留。", 15, PlaygroundUI.INK_SOFT, 500, true))
	column.add_child(note)
	column.add_child(_btn("🎲 随机抽背", tint, func(): mode = "draw"; draw_poem(), "soft"))
	column.add_child(_btn("📚 全库浏览", tint, func(): mode = "library"; _save("浏览诗库"); _render(), "ghost"))
	return panel


func _tabs() -> Control:
	var row := HFlowContainer.new()
	row.add_theme_constant_override("separation", 8)
	var draw_button := _btn("🎲 随机抽背", accent, func(): mode = "draw"; _save("随机抽背"); _render(), "primary" if mode == "draw" else "soft")
	var library_button := _btn("📚 全库浏览", accent, func(): mode = "library"; _save("浏览诗库"); _render(), "primary" if mode == "library" else "soft")
	draw_button.custom_minimum_size = Vector2(170, 48)
	library_button.custom_minimum_size = Vector2(170, 48)
	row.add_child(draw_button)
	row.add_child(library_button)
	row.add_child(_btn("背诵路线",accent,func(): mode = "route"; _save("背诵路线"); _render(),"primary" if mode == "route" else "soft"))
	var count := PlaygroundUI.label("四藤吟社本 · %s 首" % ContentDB.poems.size(), 13, PlaygroundUI.INK_SOFT, 500)
	count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(count)
	return row


func _on_immersive_changed(value: bool) -> void:
	if profile_panel != null and is_instance_valid(profile_panel):
		profile_panel.visible = not value


func _draw_view() -> Control:
	var transition := _pending_transition
	_pending_transition = ""
	if current_poem.is_empty():
		_card = null
		var empty := VBoxContainer.new()
		empty.alignment = BoxContainer.ALIGNMENT_CENTER
		empty.add_theme_constant_override("separation", 16)
		empty.size_flags_vertical = Control.SIZE_EXPAND_FILL
		empty.add_child(PlaygroundUI.label("📜", 96, accent, 700))
		var title := PlaygroundUI.label("准备好了吗？", 36, PlaygroundUI.INK, 700, true)
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.add_child(title)
		var subtitle := PlaygroundUI.label("请家长拿好平板，抽一首适合 %s 的短诗或名篇。" % players[0].name, 18, PlaygroundUI.INK_SOFT, 500, true)
		subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.add_child(subtitle)
		var button := _btn("🎲 抽一首，开始背诵", accent, draw_poem)
		button.custom_minimum_size = Vector2(320, 64)
		var center := CenterContainer.new()
		center.add_child(button)
		empty.add_child(center)
		return empty
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	poem_scroll = scroll
	poem_line_labels.clear()
	var front_style := PlaygroundUI.style(Color("#fffaf0"), 22, Color("#d6c29b"), 2)
	var back_style := PlaygroundUI.style(PlaygroundUI.mix(accent, Color.WHITE, 0.12), 22, PlaygroundUI.mix(accent, Color.WHITE, 0.5), 3)
	var poem_card := PanelContainer.new()
	# 抽诗时先显示藤紫卡背，翻面瞬间换成纸色正面
	poem_card.add_theme_stylebox_override("panel", back_style if transition == "flip" else front_style)
	poem_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	poem_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	if not transition.is_empty():
		poem_card.modulate.a = 0.0
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	# 背面阶段只隐藏视觉，不隐藏节点，保证卡片尺寸不塌陷
	column.modulate.a = 0.0 if transition == "flip" else 1.0
	poem_card.add_child(column)
	var meta := HBoxContainer.new()
	meta.add_theme_constant_override("separation", 8)
	meta.add_child(PlaygroundUI.chip(str(current_poem.get("type", "唐诗")), accent))
	meta.add_child(PlaygroundUI.chip(str(current_poem.get("level", "启蒙")), accent))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	meta.add_child(spacer)
	meta.add_child(PlaygroundUI.chip("适合 %s" % players[0].name, accent))
	column.add_child(meta)
	var title := PlaygroundUI.label(str(current_poem.get("title", "")), 44 if poem_font_size >= 36 else 38, PlaygroundUI.INK, 700, true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	var author := PlaygroundUI.label("唐 · %s" % str(current_poem.get("author", "")), 16, PlaygroundUI.INK_SOFT, 500)
	author.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(author)
	var text := VBoxContainer.new()
	text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	text.add_theme_constant_override("separation", 16 if poem_font_size >= 36 else 10)
	var reveal_blocks: Array = []
	var raw_lines: Array = current_poem.get("lines", [])
	var pinyin_lines: Array = current_poem.get("linesPinyin", []) if current_poem.get("linesPinyin") is Array else []
	for index in raw_lines.size():
		var line: Variant = raw_lines[index]
		var line_block := VBoxContainer.new()
		line_block.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var pinyin_text := str(pinyin_lines[index]) if index < pinyin_lines.size() else ""
		var ruby := PoemRubyText.new()
		ruby.configure(str(line), pinyin_text, poem_font_size, not hide_text, hide_text)
		line_block.add_child(ruby)
		if transition == "flip":
			line_block.modulate.a = 0.0
		reveal_blocks.append(line_block)
		poem_line_labels.append(ruby)
		text.add_child(line_block)
	column.add_child(text)
	# 卡背：藤紫 + 📜 印章，翻面前先给孩子一个"抽签"的期待
	if transition == "flip":
		var back_face := CenterContainer.new()
		back_face.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var back_stack := VBoxContainer.new()
		back_stack.alignment = BoxContainer.ALIGNMENT_CENTER
		back_stack.add_theme_constant_override("separation", 10)
		var seal := PlaygroundUI.label("📜", 96, Color("#fdf6e4"), 700)
		seal.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		back_stack.add_child(seal)
		var seal_text := PlaygroundUI.label("唐诗三百首", 26, Color(1, 1, 1, 0.88), 700)
		seal_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		back_stack.add_child(seal_text)
		back_face.add_child(back_stack)
		poem_card.add_child(back_face)
		poem_card.set_meta("face_back", back_face)
	poem_card.set_meta("face_front", column)
	poem_card.set_meta("face_style", front_style)
	poem_card.set_meta("face_lines", reveal_blocks)
	_card = poem_card
	scroll.add_child(poem_card)
	call_deferred("_restore_poem_scroll")
	if transition == "flip":
		_busy = true
		call_deferred("_play_card_flip", poem_card)
	elif transition == "pop":
		call_deferred("_pop_card_in", poem_card)
	var page := VBoxContainer.new()
	page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_theme_constant_override("separation", 10)
	page.add_child(scroll)
	page.add_child(_poem_tools())
	page.add_child(_evaluation_row())
	return page


func _poem_tools() -> Control:
	var tools := HBoxContainer.new()
	tools.alignment = BoxContainer.ALIGNMENT_CENTER
	tools.add_theme_constant_override("separation", 10)
	var read_button := _btn("🔊 朗读", accent, _read_poem, "soft")
	read_button.disabled = hide_text
	tools.add_child(read_button)
	tools.add_child(_btn("👀 显示正文" if hide_text else "🙈 遮住正文", accent, _toggle_text, "soft"))
	tools.add_child(_btn("🎲 换一首", accent, draw_poem, "soft"))
	var smaller := _btn("A−", accent, _adjust_poem_font.bind(-2), "ghost")
	var larger := _btn("A+", accent, _adjust_poem_font.bind(2), "ghost")
	smaller.custom_minimum_size = Vector2(58, 48)
	larger.custom_minimum_size = Vector2(58, 48)
	tools.add_child(smaller)
	tools.add_child(larger)
	return tools


func _evaluation_row() -> Control:
	if not evaluation.is_empty():
		var result_row := HBoxContainer.new()
		result_row.add_theme_constant_override("separation", 14)
		var message := PlaygroundUI.panel(PlaygroundUI.mix(accent, Color.WHITE, 0.86), 20, PlaygroundUI.mix(accent, Color.WHITE, 0.45), 2)
		message.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var message_copy := VBoxContainer.new()
		message_copy.add_child(PlaygroundUI.label("⭐ 已记作会背啦" if evaluation == "known" else "📖 已放进待复习", 22, accent, 700))
		message_copy.add_child(PlaygroundUI.label("可以再读一遍原诗，准备好再继续。", 15, PlaygroundUI.INK_SOFT, 500))
		message.add_child(message_copy)
		result_row.add_child(message)
		var next_button := _btn("下一首 →", accent, _next_poem)
		next_button.custom_minimum_size = Vector2(190, 60)
		next_button.add_theme_font_size_override("font_size", 22)
		result_row.add_child(next_button)
		return result_row
	var evaluate_row := HBoxContainer.new()
	evaluate_row.add_theme_constant_override("separation", 14)
	var review := _btn("📖 再复习", Color("#a36b24"), func(): evaluate_poem("review"), "soft")
	var known := _btn("⭐ 背对了", accent, func(): evaluate_poem("known"))
	for button in [review, known]:
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size = Vector2(0, 64)
		button.add_theme_font_size_override("font_size", 26)
	evaluate_row.add_child(review)
	evaluate_row.add_child(known)
	return evaluate_row


func _restore_poem_scroll() -> void:
	if not is_instance_valid(poem_scroll) or current_poem.is_empty() or poem_line_labels.is_empty():
		return
	var anchor: Dictionary = poem_scrolls.get(str(current_poem.id), {})
	if anchor.is_empty():
		return
	var index := clampi(int(anchor.get("line", 0)), 0, poem_line_labels.size() - 1)
	var label: Control = poem_line_labels[index]
	if not is_instance_valid(label):
		return
	var top := label.get_global_rect().position.y - poem_scroll.get_global_rect().position.y + float(poem_scroll.scroll_vertical)
	poem_scroll.scroll_vertical = maxi(0, roundi(top + float(anchor.get("ratio", 0.0)) * maxf(1.0, label.size.y)))


func _capture_poem_scroll() -> void:
	if not is_instance_valid(poem_scroll) or current_poem.is_empty() or poem_line_labels.is_empty():
		return
	var top := poem_scroll.get_global_rect().position.y
	var line_index := 0
	var ratio := 0.0
	for index in poem_line_labels.size():
		var label: Control = poem_line_labels[index]
		if not is_instance_valid(label):
			continue
		var rect := label.get_global_rect()
		if rect.end.y > top:
			line_index = index
			ratio = clampf((top - rect.position.y) / maxf(1.0, rect.size.y), 0.0, 1.0)
			break
	poem_scrolls[str(current_poem.id)] = {"line": line_index, "ratio": ratio}


func _library_view() -> Control:
	var column := VBoxContainer.new()
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 10)
	var search := PlaygroundUI.text_field("搜索题目、诗人或诗句", query, accent)
	search.custom_minimum_size.y = 50
	search.text_submitted.connect(func(value):
		query = value
		library_page = 0
		library_scroll_y = 0
		_save("搜索诗词")
		_render()
	)
	search.text_changed.connect(func(value):
		query = value
		library_page = 0
		library_scroll_y = 0
		_save("输入诗词搜索")
	)
	var search_row := HBoxContainer.new()
	search_row.add_theme_constant_override("separation", 8)
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search_row.add_child(search)
	search_row.add_child(_btn("搜索", accent, func():
		query = search.text
		library_page = 0
		library_scroll_y = 0
		_save("搜索诗词")
		_render()
	, "soft"))
	column.add_child(search_row)
	var filters := HFlowContainer.new()
	for entry in [["all","全库"],["age","适龄"],["known","已会"],["review","待复习"]]:
		var target := str(entry[0])
		filters.add_child(_btn(str(entry[1]),accent,func(): library_filter = target; library_page = 0; library_scroll_y = 0; _save("切换诗库筛选"); _render(),"primary" if library_filter == target else "soft"))
	column.add_child(filters)
	var results := ContentDB.poems.filter(func(poem):
		if library_filter == "known" and not (str(poem.id) in known_ids):
			return false
		if library_filter == "review" and not (str(poem.id) in review_ids):
			return false
		if library_filter == "age" and not ContentDB.poem_for_age(int(players[0].age)).any(func(item): return item.id == poem.id):
			return false
		if query.strip_edges().is_empty():
			return true
		var needle := query.strip_edges()
		return (
			str(poem.title).contains(needle)
			or str(poem.author).contains(needle)
			or str(poem.fullText).contains(needle)
		)
	)
	var page_count := maxi(1, ceili(float(results.size()) / LIBRARY_PAGE_SIZE))
	library_page = clampi(library_page, 0, page_count - 1)
	column.add_child(PlaygroundUI.label("找到 %s 首 · 第 %s / %s 页，每页 %s 首" % [results.size(), library_page + 1, page_count, LIBRARY_PAGE_SIZE], 13, PlaygroundUI.INK_SOFT, 500))
	var scroll := ScrollContainer.new()
	library_scroll = scroll
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	scroll.value_changed.connect(func(value: float): library_scroll_y = int(value))
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	var page_start := library_page * LIBRARY_PAGE_SIZE
	for poem in results.slice(page_start, mini(results.size(), page_start + LIBRARY_PAGE_SIZE)):
		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", 2)
		var click := _btn(
			"%s    唐 · %s · %s" % [poem.title, poem.author, poem.type],
			accent,
			choose_library_poem.bind(poem),
			"ghost"
		)
		click.custom_minimum_size.y = 62
		click.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.add_child(click)
		if not query.strip_edges().is_empty():
			row.add_child(PlaygroundUI.label(_poem_excerpt(poem, query), 14, PlaygroundUI.INK_SOFT, 500, true))
		list.add_child(row)
	scroll.add_child(list)
	column.add_child(scroll)
	var page_row := HBoxContainer.new()
	page_row.alignment = BoxContainer.ALIGNMENT_CENTER
	page_row.add_theme_constant_override("separation", 12)
	var previous_page := _btn("上一页", accent, _change_library_page.bind(-1), "soft")
	previous_page.disabled = library_page <= 0
	var next_page := _btn("下一页", accent, _change_library_page.bind(1), "soft")
	next_page.disabled = library_page >= page_count - 1
	page_row.add_child(previous_page)
	page_row.add_child(next_page)
	column.add_child(page_row)
	if library_scroll_y > 0:
		scroll.call_deferred("set", "scroll_vertical", library_scroll_y)
	return column


func _change_library_page(delta: int) -> void:
	library_page = maxi(0, library_page + delta)
	library_scroll_y = 0
	_save("浏览诗库分页")
	_render()


func _poem_excerpt(poem: Dictionary, needle: String) -> String:
	var full_text := str(poem.get("fullText", ""))
	if full_text.is_empty():
		return ""
	var position := full_text.find(needle.strip_edges())
	if position < 0:
		position = 0
	var start := maxi(0, position - 12)
	var finish := mini(full_text.length(), position + needle.strip_edges().length() + 28)
	return ("…" if start > 0 else "") + full_text.substr(start, finish - start) + ("…" if finish < full_text.length() else "")


func draw_poem(transition: String = "flip") -> void:
	if paused or _busy:
		return
	lesson_action("draw")
	var player: Dictionary = players[0]
	var pool: Array = ContentDB.poem_for_age(int(player.age))
	var candidates := pool.filter(func(poem):
		return not (str(poem.id) in used_ids) and str(poem.id) != str(current_poem.get("id", ""))
	)
	if candidates.is_empty():
		used_ids = []
		candidates = pool.filter(func(poem): return str(poem.id) != str(current_poem.get("id", "")))
	if candidates.is_empty():
		candidates = pool
	if candidates.is_empty():
		return
	var poem: Dictionary = candidates.pick_random()
	current_poem = poem
	_draw_sequence += 1
	used_ids.append(str(poem.id))
	evaluation = ""
	reported_current = false
	mode = "draw"
	_pending_transition = transition
	AudioFX.play("select")
	Speech.speak("%s，%s。请家长检查孩子背诵。" % [poem.title, poem.author])
	_save("抽到新诗")
	_render()


func evaluate_poem(result: String) -> void:
	if paused or _busy or current_poem.is_empty() or not evaluation.is_empty():
		return
	evaluation = result
	var poem_id := str(current_poem.id)
	known_ids = known_ids.filter(func(id): return id != poem_id)
	review_ids = review_ids.filter(func(id): return id != poem_id)
	if result == "known":
		known_ids.append(poem_id)
	else:
		review_ids.append(poem_id)
	lesson_action("evaluate")
	if not reported_current:
		reported_current = true
		SaveStore.record_outcome(
			str(players[0].id),
			game_id,
			"win" if result == "known" else "loss",
			1 if result == "known" else 0,
			1 if result == "known" else 0,
			1,
			{"language": {"correct": 1 if result == "known" else 0, "answered": 1}},
			"poetry-" + str(current_poem.id) + "-" + str(_draw_sequence)
		)
	_save("记录背诵结果")
	# 先提交讲解页，再播放装饰；暂停、离开和重建都不依赖计时器回调。
	_render()
	if result == "known":
		AudioFX.play("win")
		FeedbackKit.haptic(14)
		_flash_card(_card)
		_spawn_confetti(_card)
	else:
		AudioFX.play("turn")
		FeedbackKit.haptic(7)
		_shake_card(_card)


func choose_library_poem(poem: Dictionary) -> void:
	current_poem = poem
	_draw_sequence += 1
	evaluation = ""
	reported_current = false
	mode = "draw"
	_pending_transition = "flip"
	_save("从诗库选诗")
	AudioFX.play("select")
	_render()


## 遮住/显示正文：翻页 whoosh + 立即保存
func _read_poem() -> void:
	if paused or _busy or hide_text or current_poem.is_empty():
		return
	Speech.speak("%s，%s。%s" % [current_poem.title,current_poem.author,current_poem.fullText])


func _adjust_poem_font(delta: int) -> void:
	poem_font_size = clampi(poem_font_size + delta, 24, 46)
	SaveStore.set_setting("poetryFontSize", poem_font_size)
	_save("调整诗文字号")
	_render()


func _toggle_text() -> void:
	if paused or _busy:
		return
	hide_text = not hide_text
	Speech.stop()
	SfxMap.play(&"drag_start")
	_save("切换正文")
	_render()


func _find_poem(poem_id: String) -> Dictionary:
	for poem in ContentDB.poems:
		if str(poem.id) == poem_id:
			return poem
	return {}


func _count_pool(ids: Array) -> int:
	var pool := ContentDB.poem_for_age(int(players[0].age))
	var pool_ids := pool.map(func(poem): return str(poem.id))
	return ids.filter(func(id): return id in pool_ids).size()


func _save(note: String) -> void:
	_capture_poem_scroll()
	var data := {
		"schemaVersion": 1,
		"player": players[0].duplicate(true),
		"currentPoemId": str(current_poem.get("id", "")),
		"evaluation": evaluation,
		"mode": mode,
		"knownIds": known_ids,
		"reviewIds": review_ids,
		"usedIds": used_ids,
		"hideText": hide_text,
		"reportedCurrent": reported_current,
		"query":query,
		"libraryScrollY": library_scroll.scroll_vertical if is_instance_valid(library_scroll) else library_scroll_y,
		"libraryPage": library_page,
		"routeSection":route_section,
		"libraryFilter":library_filter,
		"drawSequence":_draw_sequence,
		"poemScrolls":poem_scrolls,
	}
	SaveStore.save_state(game_id, str(players[0].id), data, note, not current_poem.is_empty())


## 下一首：旧卡滑出淡出，再抽新诗并弹入
func _next_poem() -> void:
	if paused or _advancing or _busy:
		return
	if evaluation.is_empty():
		return
	lesson_action("next")
	draw_poem("pop")


# ---------- 诗卡动效：翻面 / 弹入 / 摇一摇 / 金边一闪 / 撒花 ----------

## 抽诗翻面：卡背停留一瞬 → X 轴压扁 → 换正面 → 展开 → 诗句逐行淡入
func _play_card_flip(card: Control) -> void:
	if not is_instance_valid(card) or not card.is_inside_tree():
		return
	_busy = true
	await get_tree().process_frame
	if not is_instance_valid(card) or card != _card:
		return
	card.pivot_offset = card.size * 0.5
	card.modulate.a = 0.0
	var lines: Array = card.get_meta("face_lines", [])
	var animation := MotionKit.tween(card)
	animation.tween_property(card, "modulate:a", 1.0, 0.12)
	animation.tween_interval(0.08)
	animation.tween_property(card, "scale:x", 0.06, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	animation.tween_callback(_swap_card_face.bind(card))
	animation.tween_property(card, "scale:x", 1.0, 0.21).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	animation.tween_callback(func():
		if card == _card:
			_busy = false
			_reveal_lines(lines)
	)


func _swap_card_face(card: Control) -> void:
	if not is_instance_valid(card) or card != _card:
		return
	# 展开结束前保持输入锁，透明正面不接收评判操作。
	var front: Control = card.get_meta("face_front", null)
	var back: Control = card.get_meta("face_back", null)
	var style: StyleBoxFlat = card.get_meta("face_style", null)
	if back != null:
		back.hide()
	if front != null:
		front.modulate.a = 1.0
	if style != null:
		card.add_theme_stylebox_override("panel", style)
	SfxMap.play(&"flip")


## 诗句逐行淡入，每行错开 0.12 秒
func _reveal_lines(lines: Array) -> void:
	var alive: Array = lines.filter(func(label): return is_instance_valid(label))
	if alive.is_empty():
		return
	var animation := MotionKit.tween(alive[0])
	animation.set_parallel(true)
	for index in alive.size():
		animation.tween_property(alive[index], "modulate:a", 1.0, 0.16).set_delay(index * 0.12)


## 换一首：新卡从 0.96 弹性弹入
func _pop_card_in(card: Control) -> void:
	if not is_instance_valid(card) or not card.is_inside_tree():
		return
	await get_tree().process_frame
	if not is_instance_valid(card):
		return
	card.pivot_offset = card.size * 0.5
	card.scale = Vector2(0.96, 0.96)
	var animation := MotionKit.tween(card)
	animation.set_parallel(true)
	animation.tween_property(card, "scale", Vector2.ONE, 0.24).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	animation.tween_property(card, "modulate:a", 1.0, 0.2)


## 再复习：诗卡轻摇
func _shake_card(card: Control) -> void:
	if card == null or not is_instance_valid(card):
		return
	card.pivot_offset = card.size * 0.5
	var animation := MotionKit.tween(card)
	animation.tween_property(card, "rotation", deg_to_rad(-1.4), 0.055)
	animation.tween_property(card, "rotation", deg_to_rad(1.4), 0.09)
	animation.tween_property(card, "rotation", deg_to_rad(-0.8), 0.08)
	animation.tween_property(card, "rotation", 0.0, 0.07)


## 背对了：诗卡金色描边一闪
func _flash_card(card: Control) -> void:
	if card == null or not is_instance_valid(card):
		return
	var ring := PanelContainer.new()
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ring.add_theme_stylebox_override("panel", PlaygroundUI.style(Color(1, 1, 1, 0), 26, Color("#e6b64c"), 5))
	ring.modulate.a = 0.0
	card.add_child(ring)
	var animation := MotionKit.tween(ring)
	animation.tween_property(ring, "modulate:a", 1.0, 0.12)
	animation.tween_property(ring, "modulate:a", 0.0, 0.32).set_delay(0.08).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	animation.tween_callback(ring.queue_free)


## 背对了：自绘星星/纸屑撒花 1 秒
func _spawn_confetti(card: Control) -> void:
	if card == null or not is_instance_valid(card):
		return
	var burst := ConfettiBurst.new()
	add_child(burst)
	burst.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	burst.z_index = 90
	burst.launch(card.get_global_rect().get_center() - get_global_rect().position)


func _route_view() -> Control:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation",10)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var pool := ContentDB.poems
	for section in ceili(pool.size()/10.0):
		var group := pool.slice(section*10,mini(pool.size(),section*10+10))
		var learned := group.filter(func(poem): return str(poem.id) in known_ids).size()
		var button := _btn("第 %s 组 · 已会 %s / %s 首  →" % [section+1,learned,group.size()],accent,_open_route_group.bind(section),"soft")
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size.y = 68
		list.add_child(button)
	scroll.add_child(list)
	return scroll


func _open_route_group(section: int) -> void:
	route_section = section
	var group := ContentDB.poems.slice(section*10,mini(ContentDB.poems.size(),section*10+10))
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation",10)
	for poem in group:
		var marker := "已会" if str(poem.id) in known_ids else "待复习" if str(poem.id) in review_ids else "试着背一背"
		list.add_child(_btn("%s · %s" % [poem.title,marker],accent,func(): _close_top_modal(); choose_library_poem(poem),"soft"))
	_save("查看背诵分组")
	open_modal("第 %s 组" % [section+1],list,[{"text":"回到路线","kind":"primary","callback":func(): _close_top_modal()}],"由家长判断背诵，不自动评分")


func _confirm_restart() -> void:
	_close_top_modal()
	var content := VBoxContainer.new()
	content.add_child(PlaygroundUI.label("重新抽一首当前小朋友的适龄诗，已会和待复习记录都会保留。", 17, PlaygroundUI.INK_SOFT, 500, true))
	var redraw := func():
		_close_top_modal()
		toggle_pause(false)
		_busy = false
		current_poem = {}
		evaluation = ""
		reported_current = false
		draw_poem()
	open_modal("重新抽一首？", content, [
		{"text": "继续这首", "kind": "soft", "callback": func(): _close_top_modal()},
		{"text": "重新抽", "kind": "primary", "callback": redraw},
	])
