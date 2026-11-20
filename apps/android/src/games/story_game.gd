class_name NativeStoryGame
extends NativeGameScreen

const PAGE_SIZE := 18
const CATEGORY_NAMES := {"all":"全部", "idiom":"成语故事", "myth":"神话故事", "folk":"民间故事", "fable":"寓言故事", "history":"历史典故", "fairy":"中外童话"}
const CATEGORY_ICONS := {"all":"故事书架", "idiom":"成语故事", "myth":"神话故事", "folk":"民间故事", "fable":"寓言故事", "history":"历史典故", "fairy":"中外童话"}
const FILTER_NAMES := ["全库故事", "适龄推荐", "我的收藏", "最近读过"]
var session := StorySession.new()
var _audio_active := false
var _cards_root: VBoxContainer
var _reader_scroll: ScrollContainer
var reader_tools: Control
var _paragraphs: Array[PanelContainer] = []
var _audio_label: Label
var _audio_icon: Control
var _play_button: Button
var _time_label: Label
var _search_timer: Timer
var _update_clock := 0.0
var _programmatic_scroll := false
var _follow_audio := true
var _highlighted := -1
var _restoring_reading := false
var _filtered: Array = []
var _reader_generation := 0
var _reading_dirty := false
var _reading_save_clock := 0.0
var _tts_mode := false
var _tts_paragraph := 0
var _tts_wait := 0.0


func _ready() -> void:
	build_shell()
	_search_timer = Timer.new()
	_search_timer.one_shot = true
	_search_timer.wait_time = 0.3
	add_child(_search_timer)
	_search_timer.timeout.connect(_on_search_settled)
	var profile_id := str(players[0].id)
	var learning_data: Dictionary = SaveStore.learning(profile_id, game_id)
	var shelf: Dictionary = learning_data.get("storyShelf", {}) if learning_data.get("storyShelf") is Dictionary else {}
	session.create_session(players[0], ContentDB.story_map, shelf)
	var stored := SaveStore.load_state(game_id, [profile_id])
	if not stored.is_empty(): session.restore(stored)
	players = [session.state.player.duplicate(true)]
	SaveStore.changed.connect(_on_settings_changed)
	pause_changed.connect(func(value: bool):
		if value: _pause_audio()
	)
	_render()
	_save("打开故事馆")
	call_deferred("begin_lesson")


func _render() -> void:
	_reader_generation += 1
	_programmatic_scroll = false
	_restoring_reading = false
	_search_timer.stop()
	_reader_scroll = null
	_cards_root = null
	_audio_label = null
	_audio_icon = null
	_play_button = null
	_time_label = null
	_paragraphs.clear()
	_highlighted = -1
	_tts_mode = false
	_tts_paragraph = 0
	_tts_wait = 0.0
	PlaygroundUI.clear(content_root)
	if session.state.phase == "reading" and not _story().is_empty():
		_render_reader()
	else:
		_render_library()


func _story() -> Dictionary:
	return ContentDB.story(str(session.state.get("storyId", "")))


func _pinyin_text(values: Variant) -> String:
	if not values is Array:
		return ""
	var parts := PackedStringArray()
	for value in values:
		var text := str(value).strip_edges()
		if not text.is_empty():
			parts.append(text)
	return " ".join(parts)


func _render_library() -> void:
	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation", 10)
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 8)
	title_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(ArtLibrary.semantic_picture("story", "ui", Vector2(34, 34)))
	var greeting := PlaygroundUI.label("%s的故事书架" % players[0].name, 26, accent, 700)
	greeting.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(greeting)
	heading.add_child(title_row)
	var recent_stories: Array = session.state.get("recent", [])
	if not recent_stories.is_empty():
		heading.add_child(PlaygroundUI.semantic_icon_button("continue", "接着读", accent, func(): _open_story(str(recent_stories[0])), "primary"))
	heading.add_child(PlaygroundUI.semantic_icon_button("speech", "系统朗读", accent, _show_system_tts_info))
	content_root.add_child(heading)
	var categories := HFlowContainer.new()
	categories.add_theme_constant_override("h_separation", 8)
	categories.add_theme_constant_override("v_separation", 8)
	for key in StorySession.CATEGORIES:
		var button := PlaygroundUI.semantic_icon_button(
			str(CATEGORY_ICONS[key]),
			str(CATEGORY_NAMES[key]),
			accent,
			_set_category.bind(str(key)),
			"primary" if session.state.category == key else "soft",
			18
		)
		button.custom_minimum_size.y = 48
		categories.add_child(button)
	content_root.add_child(categories)
	var search_row := HBoxContainer.new()
	search_row.add_theme_constant_override("separation", 8)
	var search := PlaygroundUI.text_field("找故事：输入故事名、人物或成语", str(session.state.query), accent)
	search.custom_minimum_size.y = 50
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search.text_changed.connect(func(value: String):
		session.handle_input({"type":"query", "value":value})
		_search_timer.start()
	)
	search.text_submitted.connect(func(_value: String): _search_timer.stop(); _on_search_settled())
	search_row.add_child(search)
	var filters := MenuButton.new()
	filters.custom_minimum_size = Vector2(184, 48)
	filters.text = _story_filter_label(str(session.state.filter))
	filters.alignment = HORIZONTAL_ALIGNMENT_CENTER
	filters.flat = false
	filters.add_theme_font_size_override("font_size", 19)
	var soft_filter := PlaygroundUI.mix(accent, Color.WHITE, 0.86)
	filters.add_theme_stylebox_override("normal", PlaygroundUI.style(soft_filter, 16, accent, 2))
	filters.add_theme_stylebox_override("hover", PlaygroundUI.style(PlaygroundUI.mix(accent, Color.WHITE, 0.76), 16, accent, 2))
	filters.add_theme_stylebox_override("pressed", PlaygroundUI.style(accent, 16, accent, 2))
	filters.add_theme_stylebox_override("focus", PlaygroundUI.style(soft_filter, 16, accent, 2))
	filters.add_theme_color_override("font_color", accent)
	filters.add_theme_color_override("font_hover_color", accent)
	filters.add_theme_color_override("font_pressed_color", Color.WHITE)
	var blank_image := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	blank_image.fill(Color(0, 0, 0, 0))
	filters.add_theme_icon_override("arrow", ImageTexture.create_from_image(blank_image))
	var popup := filters.get_popup()
	popup.add_theme_stylebox_override("panel", PlaygroundUI.style(PlaygroundUI.PAPER, 16, accent, 2, 5, Color(0, 0, 0, 0.16)))
	popup.add_theme_stylebox_override("hover", PlaygroundUI.style(accent, 10, accent, 0))
	popup.add_theme_font_size_override("font_size", 18)
	popup.add_theme_color_override("font_color", PlaygroundUI.INK)
	popup.add_theme_color_override("font_hover_color", Color.WHITE)
	popup.add_theme_constant_override("v_separation", 10)
	popup.add_theme_constant_override("item_start_padding", 14)
	popup.add_theme_constant_override("item_end_padding", 14)
	for index in StorySession.FILTERS.size():
		popup.add_item(FILTER_NAMES[index], index)
		popup.set_item_checked(index, str(session.state.filter) == str(StorySession.FILTERS[index]))
	popup.index_pressed.connect(func(index: int):
		var key := str(StorySession.FILTERS[index])
		filters.text = str(FILTER_NAMES[index])
		session.handle_input({"type":"filter", "value":key})
		session.state.shelfScroll = 0.0
		_save("切换故事筛选")
		_render_cards()
	)
	search_row.add_child(filters)
	content_root.add_child(search_row)
	_cards_root = VBoxContainer.new()
	_cards_root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_root.add_child(_cards_root)
	_render_cards()


func _set_category(category: String) -> void:
	session.handle_input({"type":"category", "value":category})
	session.state.shelfScroll = 0.0
	_save("切换故事分类")
	_render()


func _on_search_settled() -> void:
	session.state.shelfScroll = 0.0
	_save("查找故事")
	_render_cards()


func _story_filter_label(filter_key: String) -> String:
	var index := StorySession.FILTERS.find(filter_key)
	return FILTER_NAMES[index] if index >= 0 and index < FILTER_NAMES.size() else FILTER_NAMES[0]


func _select_stories() -> Array:
	var results: Array = []
	var query := str(session.state.query).strip_edges().to_lower()
	for story in ContentDB.stories:
		if session.state.category != "all" and str(story.category) != session.state.category: continue
		var story_id := str(story.id)
		match str(session.state.filter):
			"age":
				if int(players[0].age) < int(story.get("minAge", 4)): continue
			"favorites":
				if not (story_id in session.state.favorites): continue
			"recent":
				if not (story_id in session.state.recent): continue
		if not query.is_empty() and not (query in str(story.get("searchText", story.title)).to_lower()): continue
		results.append(story)
	if session.state.filter == "recent":
		results.sort_custom(func(a: Dictionary, b: Dictionary): return session.state.recent.find(str(a.id)) < session.state.recent.find(str(b.id)))
	return results


func _render_cards() -> void:
	if not is_instance_valid(_cards_root): return
	PlaygroundUI.clear(_cards_root)
	_filtered = _select_stories()
	var page_count := maxi(1, ceili(float(_filtered.size()) / PAGE_SIZE))
	session.state.page = clampi(int(session.state.page), 0, page_count - 1)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.get_v_scroll_bar().value_changed.connect(func(value: float): session.state.shelfScroll = maxf(0.0, value))
	var grid := GridContainer.new()
	grid.columns = 3 if get_viewport_rect().size.x >= 1450.0 else 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for story in _filtered.slice(int(session.state.page) * PAGE_SIZE, (int(session.state.page) + 1) * PAGE_SIZE):
		var card := PlaygroundUI.panel(PlaygroundUI.PAPER, 24, PlaygroundUI.mix(accent, Color.WHITE, 0.65), 2)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", 8)
		card.add_child(column)
		var title_box := VBoxContainer.new()
		title_box.add_theme_constant_override("separation", 1)
		var title_row := HBoxContainer.new()
		title_row.add_theme_constant_override("separation", 6)
		var category_icon := ArtLibrary.semantic_picture(str(CATEGORY_ICONS.get(str(story.category), "story")), "ui", Vector2(26, 26))
		category_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		title_row.add_child(category_icon)
		var title_text := StoryText.new()
		title_text.configure({"text":str(story.title), "pinyin":story.get("titlePinyin", [])}, bool(session.state.pinyin), 24)
		title_text.custom_minimum_size.y = 56
		title_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title_row.add_child(title_text)
		title_box.add_child(title_row)
		column.add_child(title_box)
		var opening := str(story.paragraphs[0].text) if not story.paragraphs.is_empty() else "翻开故事，一起听读。"
		column.add_child(PlaygroundUI.label(opening.left(48) + ("……" if opening.length() > 48 else ""), 18, PlaygroundUI.INK_SOFT, 500, true))
		var tools := HBoxContainer.new()
		tools.add_theme_constant_override("separation", 8)
		var note := "已读" if str(story.id) in session.state.completed else "已收藏" if str(story.id) in session.state.favorites else str(CATEGORY_NAMES.get(str(story.category), "故事"))
		var label := PlaygroundUI.label(note, 15, PlaygroundUI.INK_SOFT)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tools.add_child(label)
		var open_button := PlaygroundUI.semantic_icon_button("play", "打开", accent, _open_story.bind(str(story.id), false), "primary", 18)
		tools.add_child(open_button)
		column.add_child(tools)
		grid.add_child(card)
	if _filtered.is_empty():
		var empty := VBoxContainer.new()
		empty.add_theme_constant_override("separation", 8)
		var empty_icon := ArtLibrary.semantic_picture("story", "ui", Vector2(64, 64))
		empty_icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		empty.add_child(empty_icon)
		var empty_label := PlaygroundUI.label("这里还没有故事\n试试其他分类，或选择“全库故事”。", 25, PlaygroundUI.INK_SOFT, 500, true)
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.add_child(empty_label)
		grid.add_child(empty)
	scroll.add_child(grid)
	_cards_root.add_child(scroll)
	scroll.set_deferred("scroll_vertical", int(float(session.state.get("shelfScroll", 0.0))))
	var pagination := HBoxContainer.new()
	pagination.alignment = BoxContainer.ALIGNMENT_CENTER
	pagination.add_theme_constant_override("separation", 14)
	var previous := PlaygroundUI.semantic_icon_button("back", "上一页", accent, _change_page.bind(-1), "soft")
	previous.disabled = int(session.state.page) <= 0
	pagination.add_child(previous)
	pagination.add_child(PlaygroundUI.label("%s / %s 页 · %s 篇" % [int(session.state.page) + 1, page_count, _filtered.size()], 18, PlaygroundUI.INK_SOFT))
	var next := PlaygroundUI.semantic_icon_button("next", "下一页", accent, _change_page.bind(1), "soft")
	next.disabled = int(session.state.page) >= page_count - 1
	pagination.add_child(next)
	_cards_root.add_child(pagination)


func _change_page(direction: int) -> void:
	session.handle_input({"type":"page", "value":int(session.state.page) + direction})
	session.state.shelfScroll = 0.0
	_save("翻故事书架")
	_render_cards()


func _open_story(story_id: String, _listen: bool = false) -> void:
	Speech.stop()
	_pause_audio()
	_save("切换故事前保存")
	if not session.handle_input({"type":"open", "id":story_id}): return
	_reader_scroll = null
	_tts_mode = true
	var story_paragraphs: Array = _story().get("paragraphs", [])
	_tts_paragraph = clampi(int(session.bookmark().get("paragraph", 0)), 0, maxi(0, story_paragraphs.size() - 1))
	_tts_wait = 0.0
	_follow_audio = true
	lesson_action("open_story")
	_save("阅读《%s》" % _story().title)
	_render()


func _render_reader() -> void:
	_restoring_reading = true
	var story := _story()
	_tts_mode = true
	var story_paragraphs: Array = story.get("paragraphs", [])
	_tts_paragraph = clampi(int(session.bookmark().get("paragraph", 0)), 0, maxi(0, story_paragraphs.size() - 1))
	_tts_wait = 0.0
	_reader_scroll = ScrollContainer.new()
	_reader_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_reader_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_reader_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var paper := VBoxContainer.new()
	paper.add_theme_constant_override("separation", 12)
	paper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var title := StoryText.new()
	title.configure({"text":str(story.title), "pinyin":story.get("titlePinyin", [])}, bool(session.state.pinyin), 34)
	paper.add_child(title)
	paper.add_child(PlaygroundUI.label("%s · %s" % [CATEGORY_NAMES.get(str(story.category), "故事"), story.get("origin", "经典故事·儿童改写")], 16, PlaygroundUI.INK_SOFT, 500, true))
	for paragraph in story.get("paragraphs", []):
		var panel := PlaygroundUI.panel(PlaygroundUI.PAPER, 20, PlaygroundUI.mix(accent, Color.WHITE, 0.85), 1)
		var body := StoryText.new()
		body.configure(paragraph, bool(session.state.pinyin), int(session.state.fontSize))
		panel.add_child(body)
		paper.add_child(panel)
		_paragraphs.append(panel)
	paper.add_child(PlaygroundUI.label("故事出处：%s\n%s" % [str(story.get("sourceLabel", "经典故事")), str(story.get("editorialNote", "传统故事的儿童中文改写。"))], 14, PlaygroundUI.INK_SOFT, 500, true))
	_reader_scroll.add_child(paper)
	_reader_scroll.get_v_scroll_bar().value_changed.connect(func(_value: float):
		if not _programmatic_scroll and not _restoring_reading:
			_follow_audio = false
			if not (_tts_mode and _audio_active):
				_capture_reading()
			_reading_dirty = true
			_reading_save_clock = 0.0
	)
	_reader_scroll.gui_input.connect(func(event: InputEvent):
		if event is InputEventScreenTouch and not event.pressed: _save("保存阅读位置")
		elif event is InputEventMouseButton and not event.pressed: _save("保存阅读位置")
	)
	content_root.add_child(_reader_scroll)
	content_root.add_child(_build_player())
	_on_immersive_changed(immersive)
	_restore_reading.call_deferred()


func _on_immersive_changed(_value: bool) -> void:
	reader_tools = null


func _build_player() -> Control:
	var panel := PlaygroundUI.panel(PlaygroundUI.mix(accent, Color.WHITE, 0.91), 24, PlaygroundUI.mix(accent, Color.WHITE, 0.55), 2)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.add_child(PlaygroundUI.semantic_icon_button("back", "书架", accent, _back_to_shelf, "soft"))
	_play_button = PlaygroundUI.semantic_icon_button("listen", "系统朗读", accent, _toggle_audio, "primary")
	row.add_child(_play_button)
	row.add_child(PlaygroundUI.semantic_icon_button("settings", "阅读设置", accent, _show_reading_settings, "soft"))
	var finish := PlaygroundUI.semantic_icon_button("check", "读完啦", accent, func(): _mark_complete(); show_toast("这篇读过啦，故事还会留在这里。"), "soft")
	finish.custom_minimum_size = Vector2(108, 48)
	finish.add_theme_font_size_override("font_size", 17)
	row.add_child(finish)
	var next_story := PlaygroundUI.semantic_icon_button("next", "下一篇", accent, _next_story, "soft")
	next_story.custom_minimum_size = Vector2(104, 48)
	next_story.add_theme_font_size_override("font_size", 17)
	row.add_child(next_story)
	_time_label = PlaygroundUI.label("", 17, PlaygroundUI.INK_SOFT)
	_time_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(_time_label)
	column.add_child(row)
	var status_row := HBoxContainer.new()
	status_row.add_theme_constant_override("separation", 6)
	_audio_icon = ArtLibrary.semantic_picture("speech", "ui", Vector2(20, 20))
	_audio_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	status_row.add_child(_audio_icon)
	_audio_label = PlaygroundUI.label(_audio_status(), 15, PlaygroundUI.INK_SOFT, 500, true)
	_audio_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_row.add_child(_audio_label)
	column.add_child(status_row)
	_refresh_player()
	return panel


func _show_reading_settings() -> void:
	_pause_audio()
	_capture_reading()
	_save("打开阅读设置")
	if not paused:
		_open_pause_tools()
	var story_id := str(session.state.storyId)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	box.add_child(PlaygroundUI.semantic_icon_button(
		"favorite",
		"已收藏" if story_id in session.state.favorites else "收藏故事",
		accent,
		func(): session.handle_input({"type":"favorite"}); _save("收藏故事"); _close_top_modal(); _render(),
		"soft"
	))
	box.add_child(PlaygroundUI.semantic_icon_button(
		"practice",
		"拼音：开" if session.state.pinyin else "拼音：关",
		accent,
		func(): _capture_reading(); session.handle_input({"type":"pinyin"}); _save("切换拼音"); _close_top_modal(); _render(),
		"soft"
	))
	box.add_child(PlaygroundUI.semantic_icon_button(
		"next",
		"字号：%s" % {28:"大",34:"更大",40:"最大"}[int(session.state.fontSize)],
		accent,
		func(): _capture_reading(); session.handle_input({"type":"font"}); _save("调整字号"); _close_top_modal(); _render(),
		"soft"
	))
	box.add_child(PlaygroundUI.semantic_icon_button(
		"search",
		"跟随朗读位置",
		accent,
		func(): _follow_audio = true; _update_highlight(true); _close_top_modal(),
		"soft"
	))
	open_modal("阅读设置", box, [{"text":"回到暂停","icon":"back","kind":"primary","callback":func(): _close_top_modal()}], "设置只影响当前儿童")


func _set_audio_status(text: String) -> void:
	if is_instance_valid(_audio_label): _audio_label.text = text


func _audio_status() -> String:
	if not bool(SaveStore.settings().get("speechOn", true)):
		return "中文朗读已关闭，可在暂停面板的声音设置中开启。"
	if not Speech.has_chinese_voice():
		return "平板没有检测到中文系统语音，请先在系统设置中安装中文 TTS。"
	if _audio_active:
		return "正在使用平板自带中文语音朗读 · 音色由系统决定 · 切后台会暂停并自动保存"
	return "使用平板自带中文语音，无需下载或联网 · 音色由系统设置决定"


func _toggle_audio() -> void:
	if _audio_active:
		_pause_audio()
		_save("暂停系统朗读")
	else:
		_request_play()


func _request_play() -> void:
	if paused or _story().is_empty(): return
	if not bool(SaveStore.settings().get("speechOn", true)):
		show_toast("先在声音设置中打开中文朗读，再来听故事。")
		return
	if not Speech.has_chinese_voice():
		show_toast("平板没有检测到中文系统语音，请先在系统设置中安装中文 TTS。")
		return
	var count := _story_paragraph_count()
	if count <= 0: return
	if _tts_paragraph >= count:
		_tts_paragraph = 0
	lesson_action("listen")
	_start_system_tts(_tts_paragraph)


func _story_paragraph_count() -> int:
	var paragraphs: Variant = _story().get("paragraphs", [])
	return paragraphs.size() if paragraphs is Array else 0


func _start_system_tts(index: int) -> void:
	var story := _story()
	var paragraphs: Variant = story.get("paragraphs", [])
	if not paragraphs is Array or paragraphs.is_empty():
		return
	_tts_paragraph = clampi(index, 0, paragraphs.size() - 1)
	var text := str(paragraphs[_tts_paragraph].get("text", "")).strip_edges()
	if _tts_paragraph == 0:
		text = str(story.get("title", "")) + "。" + text
	if not Speech.begin(text, 0.9):
		_audio_active = false
		_refresh_player()
		show_toast("系统中文语音暂时不可用，请检查平板的中文 TTS 设置。")
		return
	_audio_active = true
	_tts_wait = 0.0
	_follow_audio = true
	AudioFX.set_music_duck(true)
	_update_highlight(true)
	_save("系统朗读第 %s 段" % (_tts_paragraph + 1))
	_refresh_player()


func _advance_system_tts(delta: float) -> void:
	if not _tts_mode or not _audio_active:
		return
	if Speech.is_speaking():
		_tts_wait = 0.0
		return
	_tts_wait += delta
	if _tts_wait < 0.35:
		return
	_tts_wait = 0.0
	_tts_paragraph += 1
	if _tts_paragraph >= _story_paragraph_count():
		_finish_system_tts()
	else:
		_start_system_tts(_tts_paragraph)


func _finish_system_tts() -> void:
	_audio_active = false
	_tts_wait = 0.0
	Speech.stop()
	AudioFX.set_music_duck(false)
	_mark_complete()
	AudioFX.play("win")
	_refresh_player()
	_set_audio_status("故事讲完啦，可以再看一遍，准备好再点下一篇。")


func _show_system_tts_info() -> void:
	_pause_audio()
	if not paused:
		_open_pause_tools()
	var voice_hint := "已检测到中文系统语音。" if Speech.has_chinese_voice() else "当前未检测到中文系统语音，请在平板系统设置里安装中文 TTS。"
	var text := "故事使用安卓平板自带的中文语音朗读，不下载音频，也不需要联网。\n\n音色、语速和停顿由平板系统决定；暂停后从当前段落继续。%s" % voice_hint
	open_modal("系统朗读", PlaygroundUI.label(text, 20, PlaygroundUI.INK, 500, true), [
		{"text": "试听系统语音", "kind": "soft", "callback": func(): Speech.speak("你好，我是平板自带的中文语音。")},
		{"text": "知道啦", "kind": "primary", "callback": func(): _close_top_modal()},
	], "无需下载")


func _pause_audio() -> void:
	if _audio_active:
		_save("暂停系统朗读")
		Speech.stop()
	_audio_active = false
	_tts_wait = 0.0
	AudioFX.set_music_duck(false)
	_refresh_player()


func _mark_complete() -> void:
	if _story().is_empty(): return
	_pause_audio()
	var first_time: bool = not (str(session.state.storyId) in session.state.completed)
	session.handle_input({"type":"complete"})
	_save("读过《%s》" % _story().title)
	if first_time:
		SaveStore.record_outcome(str(players[0].id), game_id, "played", 0, 0, 0, {}, "story:" + str(players[0].id) + ":" + str(session.state.storyId))


func _refresh_player() -> void:
	if is_instance_valid(_play_button):
		_play_button.text = "暂停朗读" if _audio_active else "再读一遍" if _tts_paragraph >= maxi(1, _story_paragraph_count()) else "继续朗读" if _tts_paragraph > 0 else "系统朗读"
	if is_instance_valid(_time_label):
		var count := maxi(1, _story_paragraph_count())
		_time_label.text = "共 %s 段" % count if _tts_paragraph >= count else "第 %s / %s 段" % [mini(_tts_paragraph + 1, count), count]
	_set_audio_status(_audio_status())


func _update_highlight(force: bool = false) -> void:
	if _paragraphs.is_empty(): return
	var count := _paragraphs.size()
	var target := clampi(_tts_paragraph, 0, count - 1)
	if not _audio_active and _tts_paragraph >= count:
		target = count - 1
	if target == _highlighted and not force: return
	_highlighted = target
	for index in _paragraphs.size():
		_paragraphs[index].add_theme_stylebox_override("panel", PlaygroundUI.style(PlaygroundUI.mix(accent, Color.WHITE, 0.9) if index == target else PlaygroundUI.PAPER, 20, accent if index == target else PlaygroundUI.mix(accent, Color.WHITE, 0.85), 2 if index == target else 1))
	if _follow_audio and target >= 0 and target < _paragraphs.size() and is_instance_valid(_reader_scroll):
		_programmatic_scroll = true
		_reader_scroll.ensure_control_visible(_paragraphs[target])
		call_deferred("_end_programmatic_scroll")


func _capture_reading() -> void:
	if _restoring_reading or not is_instance_valid(_reader_scroll) or _paragraphs.is_empty(): return
	var top := float(_reader_scroll.scroll_vertical)
	var paragraph := 0
	for index in _paragraphs.size():
		if _paragraphs[index].position.y <= top + 20.0: paragraph = index
	var panel := _paragraphs[paragraph]
	var offset := clampf((top - panel.position.y) / maxf(1.0, panel.size.y), 0.0, 1.0)
	session.handle_input({"type":"bookmark", "value":{"paragraph":paragraph, "offset":offset}})


func _restore_reading() -> void:
	var generation := _reader_generation
	await get_tree().process_frame
	await get_tree().process_frame
	if generation != _reader_generation or not is_inside_tree():
		return
	if not is_instance_valid(_reader_scroll) or _paragraphs.is_empty():
		_restoring_reading = false
		return
	var bookmark := session.bookmark()
	var index := clampi(int(bookmark.get("paragraph", 0)), 0, _paragraphs.size() - 1)
	_programmatic_scroll = true
	_reader_scroll.scroll_vertical = maxi(0, int(_paragraphs[index].position.y + float(bookmark.get("offset", 0.0)) * _paragraphs[index].size.y))
	_restoring_reading = false
	call_deferred("_end_programmatic_scroll")


func _end_programmatic_scroll() -> void:
	_programmatic_scroll = false


func _back_to_shelf() -> void:
	Speech.stop()
	_pause_audio()
	_capture_reading()
	session.handle_input({"type":"library"})
	_save("返回故事书架")
	_render()


func _next_story() -> void:
	var candidates := _select_stories()
	if candidates.is_empty(): candidates = ContentDB.stories
	var current := -1
	for index in candidates.size():
		if str(candidates[index].id) == str(session.state.storyId): current = index; break
	if candidates.is_empty(): return
	_open_story(str(candidates[(current + 1) % candidates.size()].id))


func _restart_story() -> void:
	_pause_audio()
	session.handle_input({"type":"restart"})
	_reader_scroll = null
	_tts_paragraph = 0
	_tts_wait = 0.0
	_save("本篇重新开始")
	_render()
	_tts_paragraph = 0
	_tts_wait = 0.0


func _save(note: String = "自动保存听读进度") -> void:
	if session.state.is_empty(): return
	if _tts_mode and _audio_active:
		session.handle_input({"type":"bookmark", "value":{"paragraph":_tts_paragraph, "offset":0.0}})
	else:
		_capture_reading()
	var learning_data := SaveStore.learning(str(players[0].id), game_id)
	learning_data.storyShelf = session.learning_snapshot()
	SaveStore.save_state(game_id, str(players[0].id), session.snapshot(), note)
	_reading_dirty = false
	_reading_save_clock = 0.0


func _on_settings_changed() -> void:
	if not bool(SaveStore.settings().get("speechOn", true)) and _audio_active:
		_pause_audio()
		_save("关闭故事朗读")


func show_help() -> void:
	_pause_audio()
	_save("查看故事馆玩法")
	super.show_help()


func _show_settings() -> void:
	_pause_audio()
	_save("调整故事声音")
	super._show_settings()


func _confirm_restart() -> void:
	open_modal("本篇从头开始？", PlaygroundUI.label("只重新开始当前故事，收藏和其他故事的进度会保留。", 20, PlaygroundUI.INK, 500, true), [
		{"text":"接着听", "kind":"soft", "callback":func(): _close_top_modal()},
		{"text":"从头开始", "kind":"primary", "callback":func(): _close_top_modal(); toggle_pause(false); _restart_story()},
	], "这一本故事")


func _process(delta: float) -> void:
	super._process(delta)
	if _tts_mode:
		_advance_system_tts(delta)
	if _reading_dirty and not _restoring_reading:
		_reading_save_clock += delta
		if _reading_save_clock >= 0.35:
			_save("保存阅读位置")
	_update_clock += delta
	if _update_clock < 0.15: return
	_update_clock = 0.0
	if _audio_active:
		_refresh_player()
		_update_highlight()


func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_WM_CLOSE_REQUEST]:
		_pause_audio()
		_save("切后台保存听读位置")
	super._notification(what)


func _exit_tree() -> void:
	if _audio_active: Speech.stop()
	AudioFX.set_music_duck(false)
