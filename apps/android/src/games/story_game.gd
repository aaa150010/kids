class_name NativeStoryGame
extends NativeGameScreen

const PAGE_SIZE := 18
const CATEGORY_NAMES := {"all":"全部", "idiom":"成语故事", "myth":"神话故事", "folk":"民间故事", "fable":"寓言故事", "history":"历史典故", "fairy":"中外童话"}
const CATEGORY_ICONS := {"all":"📚", "idiom":"📜", "myth":"🐉", "folk":"🏮", "fable":"🦊", "history":"🏯", "fairy":"🏰"}
var session := StorySession.new()
var narrator: AudioStreamPlayer
var _position := 0.0
var _duration := 0.0
var _audio_active := false
var _stream_story_id := ""
var _pending_play := ""
var _cards_root: VBoxContainer
var _reader_scroll: ScrollContainer
var reader_tools: Control
var _paragraphs: Array[PanelContainer] = []
var _audio_label: Label
var _play_button: Button
var _timeline: HSlider
var _time_label: Label
var _search_timer: Timer
var _update_clock := 0.0
var _updating_slider := false
var _dragging_slider := false
var _programmatic_scroll := false
var _follow_audio := true
var _highlighted := -1
var _restoring_reading := false
var _downloads_label: Label
var _downloads_transfer: Label
var _transfers: Dictionary = {}
var _filtered: Array = []
var _reader_generation := 0
var _reading_dirty := false
var _reading_save_clock := 0.0
var _output_latency := -1.0


func _ready() -> void:
	build_shell()
	narrator = AudioStreamPlayer.new()
	narrator.max_polyphony = 1
	add_child(narrator)
	narrator.finished.connect(_on_audio_finished)
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
	_position = _resume_position(str(session.state.storyId))
	StoryAudio.audio_ready.connect(_on_audio_ready)
	StoryAudio.download_failed.connect(_on_download_failed)
	StoryAudio.download_progress.connect(_on_download_progress)
	StoryAudio.queue_changed.connect(_refresh_downloads)
	SaveStore.changed.connect(_on_settings_changed)
	pause_changed.connect(func(value: bool):
		if value: _pause_audio()
	)
	_render()
	_save("打开故事馆")
	call_deferred("begin_lesson")


func _render() -> void:
	_reader_generation += 1
	_dragging_slider = false
	_programmatic_scroll = false
	_restoring_reading = false
	_search_timer.stop()
	_reader_scroll = null
	_cards_root = null
	_timeline = null
	_audio_label = null
	_play_button = null
	_time_label = null
	_paragraphs.clear()
	_highlighted = -1
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


func _resume_position(story_id: String) -> float:
	var bookmark := session.bookmark()
	var entry := ContentDB.story_audio_entry(story_id)
	if entry.is_empty() or str(bookmark.get("audioHash", "")) != str(entry.get("sha256", "")):
		return 0.0
	var duration := float(entry.get("duration", 0.0))
	return clampf(float(bookmark.get("position", 0.0)), 0.0, duration)


func _render_library() -> void:
	var heading := HBoxContainer.new()
	var greeting := PlaygroundUI.label("📚 %s的故事书架" % players[0].name, 26, accent, 700)
	greeting.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(greeting)
	heading.add_child(PlaygroundUI.button("↓ 下载管理", accent, _show_downloads, "soft"))
	content_root.add_child(heading)
	var categories := HFlowContainer.new()
	categories.add_theme_constant_override("h_separation", 8)
	categories.add_theme_constant_override("v_separation", 8)
	for key in StorySession.CATEGORIES:
		var button := PlaygroundUI.button(str(CATEGORY_ICONS[key]) + " " + str(CATEGORY_NAMES[key]), accent, _set_category.bind(str(key)), "primary" if session.state.category == key else "soft")
		button.custom_minimum_size.y = 48
		button.add_theme_font_size_override("font_size", 18)
		categories.add_child(button)
	content_root.add_child(categories)
	var search_row := HBoxContainer.new()
	search_row.add_theme_constant_override("separation", 8)
	var search := LineEdit.new()
	search.placeholder_text = "找故事：输入故事名、人物或成语"
	search.text = str(session.state.query)
	search.custom_minimum_size.y = 48
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search.add_theme_font_size_override("font_size", 20)
	search.add_theme_stylebox_override("normal", PlaygroundUI.style(Color.WHITE, 16, accent, 1))
	search.text_changed.connect(func(value: String):
		session.handle_input({"type":"query", "value":value})
		_search_timer.start()
	)
	search.text_submitted.connect(func(_value: String): _search_timer.stop(); _on_search_settled())
	search_row.add_child(search)
	var filters := OptionButton.new()
	filters.custom_minimum_size = Vector2(175, 48)
	filters.add_theme_font_size_override("font_size", 20)
	for name in ["全库故事", "适龄推荐", "我的收藏", "最近读过", "已下载音频"]: filters.add_item(name)
	filters.select(StorySession.FILTERS.find(str(session.state.filter)))
	filters.item_selected.connect(func(index: int):
		session.handle_input({"type":"filter", "value":StorySession.FILTERS[index]})
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
	_save("切换故事分类")
	_render()


func _on_search_settled() -> void:
	_save("查找故事")
	_render_cards()


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
			"downloaded":
				if not StoryAudio.is_cached(story_id): continue
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
		var title_pinyin := _pinyin_text(story.get("titlePinyin", []))
		if not title_pinyin.is_empty():
			var pinyin_label := PlaygroundUI.label(title_pinyin, 14, PlaygroundUI.INK_SOFT, 500, true)
			pinyin_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			title_box.add_child(pinyin_label)
		title_box.add_child(PlaygroundUI.label(str(CATEGORY_ICONS.get(str(story.category), "📖")) + " " + str(story.title), 24, accent, 700, true))
		column.add_child(title_box)
		var opening := str(story.paragraphs[0].text) if not story.paragraphs.is_empty() else "翻开故事，一起听读。"
		column.add_child(PlaygroundUI.label(opening.left(48) + ("……" if opening.length() > 48 else ""), 18, PlaygroundUI.INK_SOFT, 500, true))
		var tools := HBoxContainer.new()
		tools.add_theme_constant_override("separation", 8)
		var note := "✓ 已读" if str(story.id) in session.state.completed else "♥ 收藏" if str(story.id) in session.state.favorites else str(CATEGORY_NAMES.get(str(story.category), "故事"))
		var label := PlaygroundUI.label(note, 15, PlaygroundUI.INK_SOFT)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tools.add_child(label)
		tools.add_child(PlaygroundUI.button("看故事", accent, _open_story.bind(str(story.id), false), "soft"))
		var audio_available := StoryAudio.available(str(story.id))
		var listen := PlaygroundUI.button(
			"听故事" if StoryAudio.is_cached(str(story.id)) else "下载听" if audio_available else "音频准备中",
			accent,
			_open_story.bind(str(story.id), true)
		)
		listen.disabled = not audio_available
		tools.add_child(listen)
		column.add_child(tools)
		grid.add_child(card)
	if _filtered.is_empty():
		grid.add_child(PlaygroundUI.label("📖 这里还没有故事\n试试其他分类，或选择“全库故事”。", 25, PlaygroundUI.INK_SOFT, 500, true))
	scroll.add_child(grid)
	_cards_root.add_child(scroll)
	var pagination := HBoxContainer.new()
	pagination.alignment = BoxContainer.ALIGNMENT_CENTER
	pagination.add_theme_constant_override("separation", 14)
	var previous := PlaygroundUI.button("← 上一页", accent, _change_page.bind(-1), "soft")
	previous.disabled = int(session.state.page) <= 0
	pagination.add_child(previous)
	pagination.add_child(PlaygroundUI.label("%s / %s 页 · %s 篇" % [int(session.state.page) + 1, page_count, _filtered.size()], 18, PlaygroundUI.INK_SOFT))
	var next := PlaygroundUI.button("下一页 →", accent, _change_page.bind(1), "soft")
	next.disabled = int(session.state.page) >= page_count - 1
	pagination.add_child(next)
	_cards_root.add_child(pagination)


func _change_page(direction: int) -> void:
	session.handle_input({"type":"page", "value":int(session.state.page) + direction})
	_save("翻故事书架")
	_render_cards()


func _open_story(story_id: String, listen: bool = false) -> void:
	Speech.stop()
	_pause_audio()
	_save("切换故事前保存")
	if not session.handle_input({"type":"open", "id":story_id}): return
	_reader_scroll = null
	_position = _resume_position(story_id)
	_duration = float(ContentDB.story_audio_entry(story_id).get("duration", 0.0))
	_follow_audio = true
	_stream_story_id = ""
	_output_latency = -1.0
	narrator.stream = null
	lesson_action("open_story")
	_save("阅读《%s》" % _story().title)
	_render()
	if listen: call_deferred("_request_play")


func _render_reader() -> void:
	_restoring_reading = true
	var story := _story()
	var tools := HFlowContainer.new()
	tools.add_theme_constant_override("h_separation", 8)
	tools.add_theme_constant_override("v_separation", 8)
	tools.add_child(PlaygroundUI.button("← 回书架", accent, _back_to_shelf, "soft"))
	tools.add_child(PlaygroundUI.button("♥ 已收藏" if str(story.id) in session.state.favorites else "♡ 收藏", accent, func(): session.handle_input({"type":"favorite"}); _save("收藏故事"); _render(), "soft"))
	tools.add_child(PlaygroundUI.button("拼音：开" if session.state.pinyin else "拼音：关", accent, func(): _capture_reading(); session.handle_input({"type":"pinyin"}); _save("切换拼音"); _render(), "soft"))
	tools.add_child(PlaygroundUI.button("字号：%s" % {28:"大",34:"更大",40:"最大"}[int(session.state.fontSize)], accent, func(): _capture_reading(); session.handle_input({"type":"font"}); _save("调整字号"); _render(), "soft"))
	tools.add_child(PlaygroundUI.button("跟随朗读", accent, func(): _follow_audio = true; _update_highlight(true), "soft"))
	content_root.add_child(tools)
	reader_tools = tools
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
	var finish := HBoxContainer.new()
	finish.add_theme_constant_override("separation", 12)
	finish.add_child(PlaygroundUI.button("✓ 读完啦", accent, func(): _mark_complete(); show_toast("这篇读过啦，故事还会留在这里。"), "soft"))
	finish.add_child(PlaygroundUI.button("下一篇 →", accent, _next_story))
	paper.add_child(finish)
	paper.add_child(PlaygroundUI.label("故事出处：%s\n%s" % [str(story.get("sourceLabel", "经典故事")), str(story.get("editorialNote", "传统故事的儿童中文改写。"))], 14, PlaygroundUI.INK_SOFT, 500, true))
	_reader_scroll.add_child(paper)
	_reader_scroll.get_v_scroll_bar().value_changed.connect(func(_value: float):
		if not _programmatic_scroll and not _restoring_reading:
			_follow_audio = false
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


func _on_immersive_changed(value: bool) -> void:
	if reader_tools != null and is_instance_valid(reader_tools):
		reader_tools.visible = not value


func _build_player() -> Control:
	var panel := PlaygroundUI.panel(PlaygroundUI.mix(accent, Color.WHITE, 0.91), 24, PlaygroundUI.mix(accent, Color.WHITE, 0.55), 2)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	panel.add_child(column)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_play_button = PlaygroundUI.button("Ⅱ 暂停" if _audio_active else "▶ 接着听" if _position > 0.0 else "▶ 听故事", accent, _toggle_audio)
	row.add_child(_play_button)
	row.add_child(PlaygroundUI.button("↶ 10秒", accent, _jump.bind(-10.0), "soft"))
	row.add_child(PlaygroundUI.button("10秒 ↷", accent, _jump.bind(10.0), "soft"))
	row.add_child(PlaygroundUI.button("↺ 重听", accent, _restart_story, "soft"))
	_time_label = PlaygroundUI.label("", 17, PlaygroundUI.INK_SOFT)
	_time_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(_time_label)
	row.add_child(PlaygroundUI.button("↓ 下载", accent, _show_downloads, "soft"))
	column.add_child(row)
	_timeline = HSlider.new()
	_timeline.custom_minimum_size.y = 48
	_timeline.min_value = 0.0
	_duration = float(ContentDB.story_audio_entry(str(session.state.storyId)).get("duration", _duration))
	_timeline.max_value = maxf(1.0, _duration)
	_timeline.step = 0.1
	_timeline.editable = _duration > 0.0
	_timeline.drag_started.connect(func(): _dragging_slider = true)
	_timeline.drag_ended.connect(func(changed_value: bool):
		_dragging_slider = false
		if changed_value: _seek(_timeline.value)
	)
	_timeline.value_changed.connect(func(value: float):
		if not _updating_slider and not _dragging_slider: _seek(value)
	)
	column.add_child(_timeline)
	_audio_label = PlaygroundUI.label(_audio_status(), 15, PlaygroundUI.INK_SOFT, 500, true)
	column.add_child(_audio_label)
	_refresh_player()
	return panel


func _audio_status() -> String:
	var story_id := str(session.state.storyId)
	if not _pending_play.is_empty(): return "↓ 正在准备音频，文字可以先看。"
	if not bool(SaveStore.settings().get("speechOn", true)): return "🗣 中文朗读已关闭，可在暂停面板的声音设置中开启。"
	if StoryAudio.is_cached(story_id): return "✓ 音频已下载，可以离线听 · 切后台会暂停并自动保存"
	if StoryAudio.available(story_id): return "↓ 首次听这篇需要联网下载，以后可以离线听。"
	return "📖 文字已就绪，这篇音频暂未准备好。"


func _toggle_audio() -> void:
	if _audio_active or not _pending_play.is_empty(): _pause_audio(); _save("暂停听故事")
	else: _request_play()


func _request_play() -> void:
	if paused or _story().is_empty(): return
	if not bool(SaveStore.settings().get("speechOn", true)):
		show_toast("先在声音设置中打开中文朗读，再来听故事。")
		return
	_pending_play = str(session.state.storyId)
	_refresh_player()
	lesson_action("listen")
	StoryAudio.enqueue([_pending_play], true)


func _on_audio_ready(story_id: String, path: String) -> void:
	if story_id != _pending_play or story_id != str(session.state.storyId) or not is_inside_tree() or paused:
		if session.state.phase == "library":
			call_deferred("_render_cards")
		return
	_pending_play = ""
	if not bool(SaveStore.settings().get("speechOn", true)): return
	var stream := AudioStreamMP3.load_from_file(path)
	if stream == null:
		show_toast("这篇音频暂时打不开，可以重新下载。")
		return
	var entry := ContentDB.story_audio_entry(story_id)
	if str(session.bookmark().get("audioHash", "")) != str(entry.sha256): _position = 0.0
	narrator.stream = stream
	_stream_story_id = story_id
	_output_latency = maxf(0.0, AudioServer.get_output_latency())
	_duration = stream.get_length()
	if _position >= _duration - 0.1: _position = 0.0
	Speech.stop()
	AudioFX.set_music_duck(true)
	_audio_active = true
	narrator.stream_paused = false
	narrator.play(clampf(_position, 0.0, maxf(0.0, _duration - 0.05)))
	_save("听《%s》" % _story().title)
	_refresh_player()


func _pause_audio() -> void:
	_pending_play = ""
	var seeking := _dragging_slider and is_instance_valid(_timeline)
	if _audio_active:
		_position = _current_position()
		narrator.stream_paused = true
	if seeking:
		_position = clampf(_timeline.value,0.0,maxf(0.0,_duration-0.05))
	_dragging_slider = false
	_audio_active = false
	AudioFX.set_music_duck(false)
	_refresh_player()


func _seek(value: float) -> void:
	if paused or _duration <= 0.0: return
	_position = clampf(value, 0.0, maxf(0.0, _duration - 0.05))
	if _audio_active: narrator.seek(_position)
	_follow_audio = true
	_update_highlight(true)
	_save("调整故事播放位置")
	_refresh_player()


func _jump(seconds: float) -> void:
	_seek((_current_position()) + seconds)


func _current_position() -> float:
	if not _audio_active or _stream_story_id != str(session.state.storyId):
		return _position
	var mixed := narrator.get_playback_position() + AudioServer.get_time_since_last_mix()
	return clampf(mixed - maxf(0.0, _output_latency), 0.0, maxf(0.0, _duration))


func _on_audio_finished() -> void:
	_audio_active = false
	_position = _duration
	AudioFX.set_music_duck(false)
	_mark_complete()
	AudioFX.play("win")
	_refresh_player()
	if is_instance_valid(_audio_label): _audio_label.text = "✓ 故事讲完啦，可以再看一遍，准备好再点下一篇。"


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
		_play_button.text = "Ⅱ 暂停" if _audio_active else "取消播放" if not _pending_play.is_empty() else "▶ 接着听" if _position > 0.0 else "▶ 听故事"
	if is_instance_valid(_time_label): _time_label.text = _format_time(_current_position()) + " / " + _format_time(_duration)
	if is_instance_valid(_timeline) and not _dragging_slider:
		_updating_slider = true
		_timeline.max_value = maxf(1.0, _duration)
		_timeline.value = _current_position()
		_timeline.editable = _duration > 0.0
		_updating_slider = false
	if is_instance_valid(_audio_label): _audio_label.text = _audio_status()


func _format_time(seconds: float) -> String:
	var whole := maxi(0, int(seconds))
	return "%02d:%02d" % [int(whole / 60), whole % 60]


func _on_download_progress(story_id: String, received: int, total: int) -> void:
	_transfers[story_id] = "%s %s%%" % [str(ContentDB.story(story_id).get("title", "音频")), int(100.0 * received / maxi(1, total))]
	if is_instance_valid(_downloads_transfer): _downloads_transfer.text = "↓ " + "  ·  ".join(_transfers.values())
	if story_id == _pending_play and is_instance_valid(_audio_label):
		_audio_label.text = "↓ 正在下载 %s%% · 文字可以先看" % int(100.0 * received / maxi(1, total))


func _on_download_failed(story_id: String, message: String) -> void:
	if is_instance_valid(_downloads_transfer): _downloads_transfer.text = message
	if story_id == _pending_play:
		_pending_play = ""
		_refresh_player()
		if is_instance_valid(_audio_label): _audio_label.text = message
		show_toast(message)
		AudioFX.play("wrong")
		Speech.speak("音频暂时没准备好，可以先看文字。")


func _refresh_downloads() -> void:
	var pending: Array = StoryAudio.pending_ids()
	for story_id in _transfers.keys():
		if not (story_id in pending): _transfers.erase(story_id)
	if is_instance_valid(_downloads_label):
		_downloads_label.text = "待完成 %s 篇%s" % [pending.size(), " · 已暂停，可继续" if StoryAudio.suspended else " · 下载中" if not pending.is_empty() else " · 任务已完成"]
	if is_instance_valid(_downloads_transfer) and pending.is_empty(): _downloads_transfer.text = "✓ 已下载的音频可以离线播放。"


func _update_highlight(force: bool = false) -> void:
	if _paragraphs.is_empty(): return
	var entry := ContentDB.story_audio_entry(str(session.state.storyId))
	var position := _current_position()
	var target := -1
	for index in entry.get("paragraphs", []).size():
		var segment: Dictionary = entry.paragraphs[index]
		if position >= float(segment.get("start", 0.0)) and position < float(segment.get("end", 0.0)):
			target = index
			break
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
	_position = 0.0
	_save("本篇重新开始")
	_render()
	_request_play()


func _show_downloads() -> void:
	_pause_audio()
	_save("管理故事音频")
	var current_ids: Array = []
	for story in ContentDB.stories:
		if session.state.category == "all" or str(story.category) == session.state.category: current_ids.append(str(story.id))
	var all_ids: Array = ContentDB.stories.map(func(story: Dictionary): return str(story.id))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	var free := StoryAudio.free_bytes()
	box.add_child(PlaygroundUI.label(
		"音频已用 %s MB · 剩余空间 %s" % [
			snappedf(StoryAudio.storage_bytes() / 1000000.0, 0.1),
			("%s MB" % int(free / 1000000.0)) if free > 0 else "由系统管理",
		],
		19,
		PlaygroundUI.INK,
		500,
		true
	))
	box.add_child(PlaygroundUI.label("文字一直保存在平板里。提前下载音频后，没有网络也可以听。", 18, PlaygroundUI.INK_SOFT, 500, true))
	if not _story().is_empty():
		box.add_child(PlaygroundUI.button("↓ 下载本篇", accent, func(): StoryAudio.enqueue([str(session.state.storyId)], true); show_toast("已加入下载任务"), "soft"))
	box.add_child(PlaygroundUI.button("↓ 下载当前分类 · %s MB" % int(ceil(StoryAudio.total_bytes(current_ids) / 1000000.0)), accent, _confirm_download.bind(current_ids, "当前分类"), "soft"))
	box.add_child(PlaygroundUI.button("↓ 下载全部 · %s MB" % int(ceil(StoryAudio.total_bytes(all_ids) / 1000000.0)), accent, _confirm_download.bind(all_ids, "全部故事"), "soft"))
	_downloads_label = PlaygroundUI.label("", 18, PlaygroundUI.INK_SOFT, 500, true)
	box.add_child(_downloads_label)
	_downloads_transfer = PlaygroundUI.label("下载时可以继续读故事；切后台会暂停，回来后自动继续。", 16, PlaygroundUI.INK_SOFT, 500, true)
	box.add_child(_downloads_transfer)
	_refresh_downloads()
	box.add_child(PlaygroundUI.button("继续下载", accent, func(): StoryAudio.resume_downloads(); show_toast("正在继续下载"), "soft"))
	box.add_child(PlaygroundUI.button("暂停下载", accent, func(): StoryAudio.pause_downloads(); show_toast("下载已暂停，已完成的音频会保留"), "soft"))
	box.add_child(PlaygroundUI.button("取消下载任务", accent, func(): StoryAudio.cancel_downloads(); show_toast("已取消，已下载的音频会保留"), "soft"))
	box.add_child(PlaygroundUI.button("清理音频…", accent, _confirm_clear_audio.bind(current_ids), "ghost"))
	if not _story().is_empty():
		box.add_child(PlaygroundUI.button("只清理本篇音频…", accent, _confirm_clear_audio.bind([str(session.state.storyId)]), "ghost"))
	open_modal("故事音频", box, [{"text":"关掉窗口", "kind":"primary", "callback":func(): _close_top_modal()}], "离线听故事")


func _confirm_download(ids: Array, label: String) -> void:
	var missing: Array = []
	var unavailable := 0
	for story_id in ids:
		if not StoryAudio.available(str(story_id)): unavailable += 1
		elif not StoryAudio.is_cached(str(story_id)): missing.append(str(story_id))
	var needed := StoryAudio.total_bytes(missing)
	var text := "需要下载 %s 篇，共 %s MB。下载时可以继续看文字。" % [missing.size(), snappedf(needed / 1000000.0, 0.1)]
	if unavailable > 0: text += "\n另有 %s 篇音频尚未准备好，文字可以正常阅读。" % unavailable
	if missing.is_empty():
		show_toast("这个范围暂时没有待下载的音频。")
		return
	var free := StoryAudio.free_bytes()
	if free > 0 and needed + 8 * 1024 * 1024 > free:
		show_toast("空间不够下载这些音频，请先清理部分已下载音频。")
		return
	open_modal("下载%s？" % label, PlaygroundUI.label(text, 20, PlaygroundUI.INK, 500, true), [
		{"text":"先不下载", "kind":"soft", "callback":func(): _close_top_modal()},
		{"text":"开始下载", "kind":"primary", "callback":func(): _close_top_modal(); StoryAudio.enqueue(missing); show_toast("已加入下载任务")},
	], "按需下载")


func _confirm_clear_audio(ids: Array) -> void:
	open_modal("清理这些故事的音频？", PlaygroundUI.label("所有孩子共享的这些音频会从平板删除。正文、收藏和各自的听读进度会保留，需要时可以重新下载。", 20, PlaygroundUI.INK, 500, true), [
		{"text":"保留音频", "kind":"soft", "callback":func(): _close_top_modal()},
		{"text":"清理音频", "kind":"primary", "callback":func(): _close_top_modal(); StoryAudio.clear_cached(ids); show_toast("已清理音频，听读进度仍然保留")},
	], "请家长操作")


func _save(note: String = "自动保存听读进度") -> void:
	if session.state.is_empty(): return
	_capture_reading()
	if not _story().is_empty():
		_position = _current_position()
		var entry := ContentDB.story_audio_entry(str(session.state.storyId))
		session.handle_input({"type":"bookmark", "value":{"position":_position, "audioHash":str(entry.get("sha256", ""))}})
	var learning_data := SaveStore.learning(str(players[0].id), game_id)
	learning_data.storyShelf = session.learning_snapshot()
	SaveStore.save_state(game_id, str(players[0].id), session.snapshot(), note)
	_reading_dirty = false
	_reading_save_clock = 0.0


func _on_settings_changed() -> void:
	if not bool(SaveStore.settings().get("speechOn", true)) and (_audio_active or not _pending_play.is_empty()):
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
	_close_top_modal()
	open_modal("本篇从头开始？", PlaygroundUI.label("只重新开始当前故事，收藏和其他故事的进度会保留。", 20, PlaygroundUI.INK, 500, true), [
		{"text":"接着听", "kind":"soft", "callback":func(): _close_top_modal()},
		{"text":"从头开始", "kind":"primary", "callback":func(): _close_top_modal(); toggle_pause(false); _restart_story()},
	], "这一本故事")


func _process(delta: float) -> void:
	super._process(delta)
	if _reading_dirty and not _restoring_reading:
		_reading_save_clock += delta
		if _reading_save_clock >= 0.35:
			_save("保存阅读位置")
	_update_clock += delta
	if _update_clock < 0.15: return
	_update_clock = 0.0
	if _audio_active:
		_position = _current_position()
		_refresh_player()
		_update_highlight()


func _notification(what: int) -> void:
	if narrator != null and what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_WM_CLOSE_REQUEST]:
		_pause_audio()
		_save("切后台保存听读位置")
	super._notification(what)


func _exit_tree() -> void:
	_pending_play = ""
	if narrator != null: narrator.stop()
	AudioFX.set_music_duck(false)
