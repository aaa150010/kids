class_name NativeMemoryGame
extends NativeGameScreen

## 结算撒花：自绘彩色纸屑从顶部飘落，2 秒后自动移除
class ConfettiFx:
	extends Control
	const DURATION := 2.0
	const COLORS := [Color("#f26d6d"), Color("#f2c94c"), Color("#6fcf97"), Color("#56ccf2"), Color("#bb6bd9"), Color("#f2994a")]
	var _pieces: Array = []
	var _elapsed := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		z_index = 95

	func _process(delta: float) -> void:
		if _pieces.is_empty():
			# 等拿到有效尺寸后再生成纸屑
			if size.x < 8.0 or size.y < 8.0:
				return
			for index in 26:
				_pieces.append({
					"x": randf() * size.x,
					"y": -20.0 - randf() * size.y * 0.4,
					"vy": 180.0 + randf() * 160.0,
					"sway": randf() * TAU,
					"rot": randf() * TAU,
					"vr": randf_range(-4.0, 4.0),
					"edge": 8.0 + randf() * 8.0,
					"tint": COLORS[index % COLORS.size()],
				})
		_elapsed += delta
		for piece in _pieces:
			piece.y += float(piece.vy) * delta
			piece.rot += float(piece.vr) * delta
			piece.x += sin(_elapsed * 3.0 + float(piece.sway)) * 36.0 * delta
		queue_redraw()
		if _elapsed >= DURATION:
			queue_free()

	func _draw() -> void:
		# 最后 0.5 秒整体淡出
		var fade := clampf((DURATION - _elapsed) / 0.5, 0.0, 1.0)
		for piece in _pieces:
			var tint: Color = piece.tint
			tint.a *= fade
			var half := float(piece.edge) * 0.5
			draw_set_transform(Vector2(piece.x, piece.y), float(piece.rot), Vector2.ONE)
			draw_rect(Rect2(-half, -half * 0.6, half * 2.0, half * 1.2), tint)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


var engine := MemoryRules.new()
var card_theme := "animals"
var view := "table"
var cards: Array[MemoryCard] = []
var player_labels: Array[Label] = []
var status: Label
var _save_clock := 0.0

func _ready() -> void:
	build_shell()
	var saved := SaveStore.load_state(game_id,players.map(func(player): return str(player.id)))
	if engine.restore(saved):
		players = engine.state.players.duplicate(true)
		difficulty = str(engine.state.get("difficulty",difficulty))
		card_theme = str(engine.state.get("theme","animals"))
		level_id = int(engine.state.get("levelId",1))
		view = str(engine.state.get("view","table"))
		if engine.state.phase == "result" and not bool(saved.get("resume",true)):
			engine.state = {}
			if mode_id == "adventure":
				_show_map()
				return
			_new_session()
	elif mode_id == "adventure":
		_show_map()
		return
	else:
		_new_session()
	if view == "map":
		_show_map()
	else:
		_build_table()
		_refresh(false)
		if engine.state.phase == "result":
			_finish()
	call_deferred("begin_lesson")

func _new_session() -> void:
	var cap := 5 if int(players[0].age) <= 5 else 8 if int(players[0].age) <= 7 else 10 if int(players[0].age) <= 9 else 12
	var pairs := clampi(cap+int(GameTuning.value(game_id,difficulty,"pairsDelta",0)),3,12)
	var chapter := ContentDB.level(game_id,level_id)
	if mode_id == "adventure":
		card_theme = str(chapter.get("theme","animals"))
		pairs = clampi(6+int((level_id-1)%12/2)+int(GameTuning.value(game_id,difficulty,"pairsDelta",0)),3,12)
	var pool := ContentDB.memory_cards().filter(func(card): return str(card.get("theme","")) == card_theme)
	if pool.is_empty():
		card_theme = "animals"
		pool = ContentDB.memory_cards().filter(func(card): return str(card.get("theme","")) == card_theme)
	engine.create_session({"gameId":game_id,"modeId":mode_id,"players":players.duplicate(true),"levelId":level_id,"difficulty":difficulty,"seed":int(chapter.get("seed",Time.get_ticks_usec())) if mode_id == "adventure" else Time.get_ticks_usec(),"cards":pool,"pairs":pairs,"previewSeconds":float(GameTuning.value(game_id,difficulty,"previewSeconds",0.8)),"hintsMax":int(GameTuning.value(game_id,difficulty,"hints",2)),"threeStarMistakes":int(GameTuning.value(game_id,difficulty,"threeStarMistakes",3)),"theme":card_theme,"view":"table"})
	view = "table"
	_save("开始翻牌")

func _show_map() -> void:
	view = "map"
	PlaygroundUI.clear(content_root)
	content_root.add_child(PlaygroundUI.label("翻开四个小世界",30,accent,700))
	content_root.add_child(level_map(_choose_level))
	if not engine.state.is_empty():
		_save("正在选择翻牌关卡")

func _choose_level(number: int) -> void:
	if not SaveStore.level_unlocked(str(players[0].id),game_id,number,mode_id):
		return
	level_id = number
	_new_session()
	_build_table()
	_refresh(false)
	begin_lesson()

func _build_table() -> void:
	PlaygroundUI.clear(content_root)
	cards.clear()
	player_labels.clear()
	var tools := HFlowContainer.new()
	tools.add_theme_constant_override("h_separation",12)
	if mode_id == "adventure":
		tools.add_child(PlaygroundUI.button("关卡地图",accent,_show_map,"soft"))
		tools.add_child(PlaygroundUI.chip("第 %s 关" % level_id,accent))
	else:
		for entry in ContentDB.memory_themes():
			var identifier := str(entry.id)
			tools.add_child(PlaygroundUI.button(str(entry.name),accent,_choose_theme.bind(identifier),"primary" if identifier == card_theme else "soft"))
	if players.size() == 1:
		tools.add_child(PlaygroundUI.button("看一对提示",accent,_hint,"soft"))
	tools.add_child(PlaygroundUI.button("重新开始",accent,_confirm_restart,"ghost"))
	content_root.add_child(tools)
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation",16)
	row.add_child(_player_panel(0))
	var table := PlaygroundUI.panel(Color("#f7e6ee"),28,Color("#c992ad"),3)
	table.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	table.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var grid_scroll := ScrollContainer.new()
	grid_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	grid_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	grid_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	table.add_child(grid_scroll)
	var grid := GridContainer.new()
	grid.add_theme_constant_override("h_separation",12)
	grid.add_theme_constant_override("v_separation",12)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid_scroll.add_child(grid)
	grid_scroll.resized.connect(_layout_memory_grid.bind(grid_scroll, grid, engine.state.deck.size()))
	call_deferred("_layout_memory_grid", grid_scroll, grid, engine.state.deck.size())
	var card_data := {}
	for entry in ContentDB.memory_cards()+engine.state.get("cardData",[]):
		card_data[str(entry.id)] = entry
	for index in engine.state.deck.size():
		var card := MemoryCard.new()
		grid.add_child(card)
		card.configure(card_data.get(str(engine.state.deck[index]),{}))
		card.set_card_theme(card_theme)
		card.pressed.connect(_flip.bind(index))
		cards.append(card)
	row.add_child(table)
	row.add_child(_player_panel(1))
	content_root.add_child(row)
	status = PlaygroundUI.label("",22,accent,700,true)
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content_root.add_child(status)

func _layout_memory_grid(scroll: ScrollContainer, grid: GridContainer, card_count: int) -> void:
	if not is_instance_valid(scroll) or not is_instance_valid(grid) or card_count <= 0:
		return
	var viewport_size := scroll.size
	if viewport_size.x < 1.0 or viewport_size.y < 1.0:
		return
	const MIN_CARD_WIDTH := 90.0
	const MIN_CARD_HEIGHT := 116.0
	const GAP := 12.0
	var max_columns := maxi(1, int(floor((viewport_size.x + GAP) / (MIN_CARD_WIDTH + GAP))))
	var visible_rows := maxi(1, int(floor((viewport_size.y + GAP) / (MIN_CARD_HEIGHT + GAP))))
	var columns_for_height := int(ceil(float(card_count) / float(visible_rows)))
	var balanced_columns := int(round(sqrt(float(card_count) * viewport_size.x / viewport_size.y)))
	grid.columns = clampi(maxi(columns_for_height, balanced_columns), 1, max_columns)


func _player_panel(index: int) -> Control:
	var panel := PlaygroundUI.panel(PlaygroundUI.mix(accent,Color.WHITE,0.9),24,PlaygroundUI.LINE)
	panel.custom_minimum_size.x = 150
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",16)
	panel.add_child(column)
	column.add_child(ArtLibrary.picture(str(players[index].get("avatar","🦊")) if index < players.size() else "💡",Vector2(90,100)))
	column.add_child(PlaygroundUI.label(str(players[index].name) if index < players.size() else "记住位置",22,PlaygroundUI.INK,700,true))
	var score := PlaygroundUI.label("",19,PlaygroundUI.INK_SOFT,500,true)
	column.add_child(score)
	player_labels.append(score)
	return panel

func _refresh(animate: bool = true, hold: Array = []) -> void:
	if cards.is_empty():
		return
	var matched: Array = engine.state.matched
	var flipped: Array = engine.state.flipped
	var peek_indices: Array = engine.state.peekIndices
	for index: int in cards.size():
		if index in hold:
			# 抖动演出中的卡片暂时不刷新，等抖动结束再统一扣回
			continue
		var paired: bool = index in matched
		var face_up: bool = paired or index in flipped or index in peek_indices
		cards[index].show_face(face_up,paired,paused or bool(engine.state.pending) or float(engine.state.peekRemaining)>0 or engine.state.phase != "playing",animate)
	for index: int in 2:
		if index < players.size():
			player_labels[index].text = "%s\n已找到 %s 对" % ["现在轮到你" if index == int(engine.state.currentPlayer) else "等一等，记位置",int(engine.state.scores[index])]
		else:
			player_labels[index].text = "没有倒计时\n提示 %s / %s 次\n已尝试 %s 次" % [int(engine.state.hints),int(engine.state.get("hintsMax",2)),int(engine.state.moves)]
	status.text = "全部配对完成啦！" if engine.state.phase == "result" else "看看这两张图案，记住位置" if bool(engine.state.pending) else "先翻开一张卡片" if engine.state.flipped.is_empty() else "再翻一张，找一找它的朋友"

func _flip(index: int) -> void:
	if paused:
		return
	var result := engine.handle_input({"type":"flip","index":index})
	if not bool(result.ok):
		return
	lesson_action("flip")
	if engine.state.flipped.size() == 2:
		lesson_action("pair")
	AudioFX.play("flip")
	FeedbackKit.haptic(7)
	_save("已翻开 %s 张卡" % engine.state.flipped.size())
	_refresh()
	for entry in ContentDB.memory_cards():
		if str(entry.id) == str(engine.state.deck[index]):
			Speech.speak(str(entry.name))
			break

func _hint() -> void:
	if paused:
		return
	var result := engine.handle_input({"type":"hint"})
	if bool(result.ok):
		_save("正在看一对提示")
		_refresh()
		Speech.speak("看看这两个位置，记住后自己找一找。")
	else:
		show_toast("提示次数已用完，或还有一对没看完。")

func _process(delta: float) -> void:
	super._process(delta)
	if paused or view != "table" or engine.state.is_empty():
		return
	# 判定前先记下正在等待的两张卡，tick 之后 flipped 会被清空
	var resolving: Array = engine.state.flipped.duplicate() if bool(engine.state.get("pending",false)) else []
	if engine.tick(delta):
		if bool(engine.state.get("mismatchShowing",false)):
			_refresh()
			for index in resolving:
				if int(index) >= 0 and int(index) < cards.size():
					cards[int(index)].shake()
		elif not resolving.is_empty():
			var matched_now := bool(engine.state.get("lastMatched",false))
			AudioFX.play("pair" if matched_now else "turn")
			FeedbackKit.haptic(12 if matched_now else 7)
			if matched_now:
				# 配对成功：两张卡跳起 + 金色星光
				for index in resolving:
					if int(index) >= 0 and int(index) < cards.size():
						cards[int(index)].celebrate()
				_refresh()
			else:
				_refresh()
		else:
			_refresh()
		_save("配对状态已保存")
		if engine.state.phase == "result":
			_finish()

func _finish() -> void:
	if not bool(engine.state.reported):
		for index in players.size():
			var outcome := "win" if players.size() == 1 or int(engine.state.scores[index]) > int(engine.state.scores[1-index]) else "draw" if engine.state.scores[0] == engine.state.scores[1] else "loss"
			SaveStore.record_outcome(str(players[index].id),game_id,outcome,int(engine.state.scores[index]),int(engine.state.scores[index]),int(engine.state.pairs),{"memory":{"correct":engine.state.scores[index],"answered":engine.state.pairs}},str(engine.state.sessionId))
		if mode_id == "adventure":
			SaveStore.complete_level(str(players[0].id),game_id,level_id,engine.stars(),mode_id)
		engine.state.reported = true
		_save("翻牌完成",false)
	var content := VBoxContainer.new()
	content.add_child(ArtLibrary.picture("🏆",Vector2(100,100)))
	for index in players.size():
		content.add_child(PlaygroundUI.label("%s 找到 %s 对" % [players[index].name,int(engine.state.scores[index])],25,accent,700,true))
	if mode_id == "adventure":
		content.add_child(PlaygroundUI.label("★".repeat(engine.stars())+"☆".repeat(3-engine.stars()),36,Color("#cc9a28"),700))
	var actions := [{"text":"再翻一局","kind":"soft","callback":func(): _close_top_modal(); _new_session(); _build_table(); _refresh(false)}]
	if mode_id == "adventure":
		actions.append({"text":"关卡地图","kind":"primary","callback":func(): _close_top_modal(); _show_map()})
	else:
		actions.append({"text":"回大厅","kind":"primary","callback":func(): _close_top_modal(); back_requested.emit()})
	var layer := open_modal("全部找到啦！",content,actions)
	_spawn_confetti(layer)
	FeedbackKit.success()

## 在结算面板所在层撒花：全屏自绘纸屑，不拦截点击
func _spawn_confetti(parent: Control) -> void:
	if parent == null:
		return
	var confetti := ConfettiFx.new()
	parent.add_child(confetti)
	confetti.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _choose_theme(target: String) -> void:
	if target == card_theme:
		return
	open_modal("换一个主题？",PlaygroundUI.label("换主题会重新发牌，已完成成绩会保留。",20,PlaygroundUI.INK_SOFT,500,true),[
		{"text":"继续这局","kind":"soft","callback":func(): _close_top_modal()},
		{"text":"换个主题","kind":"primary","callback":func(): _close_top_modal(); card_theme = target; _new_session(); _build_table(); _refresh(false)},
	])

func _confirm_restart() -> void:
	_close_top_modal()
	open_modal("重新翻这一局？",PlaygroundUI.label("已经通过的关卡和其他游戏会保留。",20,PlaygroundUI.INK_SOFT,500,true),[
		{"text":"继续这局","kind":"soft","callback":func(): _close_top_modal()},
		{"text":"重新开始","kind":"primary","callback":func(): _close_top_modal(); toggle_pause(false); _new_session(); _build_table(); _refresh(false)},
	])

func _save(note: String, resume: bool = true) -> void:
	if engine.state.is_empty():
		return
	engine.state.view = view
	SaveStore.save_state(game_id,str(players[0].id),engine.snapshot(),note,resume and (engine.state.phase == "playing" or view == "map"))
