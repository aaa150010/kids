class_name NativeBoardGame
extends NativeGameScreen

var engine := BoardRules.new()
var surface: BoardSurface
var status: Label
var detail: Label
var player_labels: Array[Label] = []
var player_panels: Array[PanelContainer] = []
var view := "board"
var replay_index := 0
var replay_surface: BoardSurface
var replay_label: Label
var _idle_seconds := 0.0

func _ready() -> void:
	build_shell()
	var stored := SaveStore.load_state(game_id,players.map(func(player): return str(player.id)))
	stored.gameId = game_id
	stored.modeId = mode_id
	if stored.get("players") is Array and engine.restore(stored):
		players = engine.state.players.duplicate(true)
		difficulty = str(engine.state.get("difficulty",difficulty))
		level_id = int(engine.state.get("levelId",1))
		view = str(engine.state.get("view","board"))
		if engine.state.phase == "finished" and not bool(stored.get("resume",true)):
			engine.state = {}
			if mode_id == "puzzle":
				_show_map()
				return
			_create()
	elif mode_id == "puzzle":
		_show_map()
		return
	else:
		_create()
	if view == "map" and mode_id == "puzzle":
		_show_map()
	else:
		_build_board()
		_refresh()
		if engine.state.phase == "finished":
			_show_result()
	call_deferred("begin_lesson")

func _create(number: int = 1) -> void:
	level_id = number
	var chapter := ContentDB.level(game_id,number)
	var puzzle: Dictionary = {}
	if mode_id == "puzzle":
		var pool: Array = ContentDB.puzzles.get(game_id,[])
		if number < 1 or number > pool.size():
			return
		puzzle = pool[number-1].duplicate(true)
	engine.create_session({"gameId":game_id,"modeId":mode_id,"difficulty":difficulty,"hintsMax":int(GameTuning.value(game_id,difficulty,"hints",2)),"undosMax":int(GameTuning.value(game_id,difficulty,"undos",3)),"hintSeconds":int(GameTuning.value(game_id,difficulty,"hintSeconds",18)),"players":players.duplicate(true),"levelId":number,"seed":int(chapter.get("seed",Time.get_ticks_usec())) if mode_id == "puzzle" else Time.get_ticks_usec(),"puzzle":puzzle,"view":"board"})
	session_id = str(engine.state.sessionId)
	view = "board"
	_save("开始第 %s 关" % number if mode_id == "puzzle" else "新的棋局")

func _show_map() -> void:
	view = "map"
	PlaygroundUI.clear(content_root)
	content_root.add_child(PlaygroundUI.label("选择一个小挑战",30,accent,700))
	content_root.add_child(level_map(_choose_level))
	if not engine.state.is_empty():
		engine.state.view = "map"
		_save("正在选择关卡")

func _choose_level(number: int) -> void:
	if not SaveStore.level_unlocked(str(players[0].id),game_id,number,mode_id):
		return
	_create(number)
	_build_board()
	_refresh()
	begin_lesson()

func _build_board() -> void:
	PlaygroundUI.clear(content_root)
	player_labels.clear()
	player_panels.clear()
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation",16)
	row.add_child(_player_column(0))
	surface = BoardSurface.new()
	surface.game_id = game_id
	surface.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	surface.size_flags_vertical = Control.SIZE_EXPAND_FILL
	surface.cell_pressed.connect(_cell)
	surface.previewed.connect(func(): lesson_action("select"))
	row.add_child(surface)
	row.add_child(_player_column(1))
	content_root.add_child(row)
	status = PlaygroundUI.label("",22,accent,700,true)
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content_root.add_child(status)
	var tools := HFlowContainer.new()
	tools.alignment = FlowContainer.ALIGNMENT_CENTER
	tools.add_theme_constant_override("h_separation",12)
	if mode_id == "puzzle":
		tools.add_child(PlaygroundUI.button("关卡地图",accent,_show_map,"soft"))
		tools.add_child(PlaygroundUI.button("看提示",accent,_hint,"soft"))
	tools.add_child(PlaygroundUI.button("悔棋",accent,_request_undo,"soft"))
	tools.add_child(PlaygroundUI.button("棋谱回放",accent,_show_replay,"soft"))
	if game_id == "gomoku":
		tools.add_child(PlaygroundUI.button("显示手数",accent,func(): surface.show_numbers = not surface.show_numbers; surface.queue_redraw(),"soft"))
	tools.add_child(PlaygroundUI.button("重新开始",accent,_confirm_restart,"ghost"))
	content_root.add_child(tools)

func _player_column(side: int) -> Control:
	var panel := PlaygroundUI.panel(PlaygroundUI.mix(accent,Color.WHITE,0.88),22,PlaygroundUI.mix(accent,Color.WHITE,0.4),2)
	panel.custom_minimum_size.x = 176
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",14)
	panel.add_child(column)
	var token := str(players[side].get("avatar","🦊")) if side < players.size() else "🎯"
	column.add_child(ArtLibrary.picture(token,Vector2(105,105)))
	var name := str(players[side].name) if side < players.size() else "本关目标"
	column.add_child(PlaygroundUI.label(name,23,PlaygroundUI.INK,700,true))
	var text := PlaygroundUI.label("",18,PlaygroundUI.INK_SOFT,500,true)
	column.add_child(text)
	player_labels.append(text)
	player_panels.append(panel)
	if side == 1:
		detail = PlaygroundUI.label("",17,PlaygroundUI.INK_SOFT,500,true)
		column.add_child(detail)
	return panel

func _refresh(animate: bool = false) -> void:
	if surface == null or not is_instance_valid(surface):
		return
	var selected := engine.piece_by_id(str(engine.state.get("selected","")))
	var targets: Array = engine.legal_moves(selected) if not selected.is_empty() else []
	surface.interactive = not paused and view == "board" and engine.state.phase == "playing" and not (mode_id == "puzzle" and int(engine.state.turn) == 1)
	surface.update_state(engine.state,targets,animate)
	for side in 2:
		var current: bool = int(engine.state.turn) == side and str(engine.state.phase) == "playing"
		player_panels[side].add_theme_stylebox_override("panel",PlaygroundUI.style(PlaygroundUI.mix(accent,Color.WHITE,0.85 if current else 0.94),22,accent if current else PlaygroundUI.LINE,3 if current else 1))
		player_labels[side].text = ("现在轮到你" if current else "等一等，慢慢想") if side < players.size() else str(engine.state.get("puzzle",{}).get("title",""))
	if not selected.is_empty():
		detail.text = "%s\n%s个可走位置" % [BoardRules.NAMES[selected.kind],targets.size()]
	elif mode_id == "puzzle":
		detail.text = "第 %s 关\n目标 %s 步\n已走 %s 步" % [level_id,int(engine.state.puzzle.get("targetSteps",1)),int(engine.state.moveCount)]
	else:
		detail.text = "第 %s 手\n%s" % [int(engine.state.moveCount)+1,"空交叉点落子" if game_id == "gomoku" else "红蓝双方轮流行动"]
	status.text = str(engine.state.reason) if engine.state.phase == "finished" else "点空交叉点落子，按住可以预览" if game_id == "gomoku" else "点亮起的位置移动" if not selected.is_empty() else "先翻暗棋，或选自己的亮棋" if game_id == "military" else "先选自己的动物，再点发光格子"

func _cell(position: int) -> void:
	if paused or view != "board" or engine.state.phase != "playing" or (mode_id == "puzzle" and int(engine.state.turn) == 1):
		return
	var target := engine.piece_at(position)
	var action := {"type":"move","to":position}
	if game_id != "gomoku" and not target.is_empty() and bool(target.revealed) and int(target.side) == int(engine.state.turn):
		action.type = "select"
	var result := engine.handle_input(action)
	if not bool(result.ok):
		_shake_for_failed(position)
		SfxMap.play(&"error")
		FeedbackKit.haptic(15)
		show_toast(str(result.get("message","试试亮起的位置")))
		_save("正在思考")
		return
	var event := str(result.event)
	if event == "select":
		SfxMap.play(&"select")
	elif event == "flip":
		SfxMap.play(&"flip")
	elif not engine.state.get("lastMove",{}).get("captured",{}).is_empty():
		# 吃子：SfxMap 里没有 whoosh 语义事件，直接用合成音名
		AudioFX.play("whoosh")
	else:
		SfxMap.play(&"move")
	FeedbackKit.haptic(8 if event == "select" else 12)
	_idle_seconds = 0.0
	lesson_action("select" if event == "select" else "move")
	_save("已走 %s 手" % engine.state.moveCount)
	_refresh(event != "select")
	if engine.state.phase == "finished":
		_show_result()

# 非法选择/非法走法：让该棋子左右抖一下，给出即时视觉反馈
func _shake_for_failed(position: int) -> void:
	if surface == null or not is_instance_valid(surface):
		return
	var selected := engine.piece_by_id(str(engine.state.get("selected","")))
	var index := int(selected.get("position",-1))
	if index < 0:
		var tapped := engine.piece_at(position)
		index = position if tapped.is_empty() else int(tapped.position)
	surface.shake(index)

func _fixed_reply() -> void:
	var line: Array = engine.state.puzzle.get("line",[])
	var cursor := int(engine.state.lineIndex)
	if cursor >= line.size():
		return
	var action: Dictionary = line[cursor].duplicate(true)
	if action.has("from"):
		var piece := engine.piece_at(int(action.from))
		engine.state.selected = str(piece.get("id",""))
	action.type = "move"
	var result := engine.handle_input(action)
	if bool(result.ok):
		_save("练习局面已保存")
		_refresh(true)
		if engine.state.phase == "finished":
			_show_result()

func _hint() -> void:
	if paused or engine.state.phase != "playing":
		return
	if int(engine.state.hints) >= int(engine.state.get("hintsMax",2)):
		show_toast("这一档难度的提示次数已经用完。")
		return
	engine.state.hints = int(engine.state.hints)+1
	FeedbackKit.haptic(7)
	var text := str(engine.state.puzzle.get("hint","先看看可走的位置。"))
	show_toast(text,5)
	Speech.speak(text)
	_save("看过提示")

func _request_undo() -> void:
	if paused or engine.state.phase != "playing" or engine.state.history.is_empty():
		show_toast("现在没有可以撤回的走法")
		return
	if int(engine.state.undos) >= int(engine.state.get("undosMax",3)):
		show_toast("这一档难度的悔棋次数已经用完。")
		return
	if str(engine.state.history.back().type) == "flip":
		show_toast("暗棋已经翻开，这次不能撤回哦")
		return
	var message := "撤回刚才这一步和自动应手，再想一想。" if mode_id == "puzzle" else "撤回最近的一步，再想一想。" if players.size() == 1 else "请另一位小朋友确认，是否同意撤回最近一步？"
	open_modal("悔棋确认",PlaygroundUI.label(message,21,PlaygroundUI.INK,500,true),[
		{"text":"继续下棋","kind":"soft","callback":func(): _close_top_modal()},
		{"text":"同意撤回","kind":"primary","callback":_confirm_undo},
	])

func _confirm_undo() -> void:
	_close_top_modal()
	var undone := engine.undo_player_turn() if mode_id == "puzzle" else engine.undo()
	if undone:
		FeedbackKit.haptic(9)
		_save("撤回了一步")
		_refresh()

func _show_result() -> void:
	var state := engine.state
	if not bool(state.get("reported",false)):
		state.reported = true
		var stars := 1
		if int(state.hints) == 0:
			stars = 2
			if int(state.undos) == 0 and int(state.moveCount) <= int(state.get("puzzle",{}).get("targetSteps",9999)):
				stars = 3
		if mode_id == "puzzle" and int(state.winner) == 0:
			SaveStore.complete_level(str(players[0].id),game_id,level_id,stars,mode_id)
		for side in players.size():
			var outcome := "draw" if int(state.winner) < 0 else "win" if side == int(state.winner) else "loss"
			SaveStore.record_outcome(str(players[side].id),game_id,outcome,stars if mode_id == "puzzle" else 1 if outcome == "win" else 0,0,0,{"strategy":{"correct":1 if outcome == "win" else 0,"answered":1}},str(state.get("sessionId","legacy-"+game_id+str(state.moveCount))))
		_save("本局完成",false)
	var content := VBoxContainer.new()
	content.add_child(ArtLibrary.picture("🏆",Vector2(100,100)))
	content.add_child(PlaygroundUI.label(str(state.reason),25,accent,700,true))
	content.add_child(PlaygroundUI.label("共走 %s 手，可以回放刚才的棋局。" % state.moveCount,18,PlaygroundUI.INK_SOFT,500,true))
	var actions: Array = [{"text":"棋谱回放","kind":"soft","callback":func(): _close_top_modal(); _show_replay()}]
	if mode_id == "puzzle":
		actions.append({"text":"关卡地图","kind":"primary","callback":func(): _close_top_modal(); _show_map()})
	else:
		actions.append({"text":"再来一局","kind":"primary","callback":func(): _close_top_modal(); _create(); _refresh()})
	open_modal("这一局完成啦",content,actions)
	if mode_id == "puzzle" and int(state.winner) != 0:
		SfxMap.play(&"lose")
	else:
		SfxMap.play(&"win")
	FeedbackKit.haptic(14)
	Speech.speak(str(state.reason))

func _show_replay() -> void:
	if engine.state.is_empty():
		return
	replay_index = 0
	var content := VBoxContainer.new()
	replay_surface = BoardSurface.new()
	replay_surface.game_id = game_id
	replay_surface.interactive = false
	replay_surface.custom_minimum_size = Vector2(580,380)
	content.add_child(replay_surface)
	replay_label = PlaygroundUI.label("",18,accent,700)
	content.add_child(replay_label)
	open_modal("棋谱回放",content,[
		{"text":"上一步","kind":"soft","callback":func(): replay_index = maxi(0,replay_index-1); _replay_refresh()},
		{"text":"下一步","kind":"soft","callback":func(): replay_index = mini(engine.state.history.size(),replay_index+1); _replay_refresh()},
		{"text":"返回棋局","kind":"primary","callback":func(): _close_top_modal()},
	])
	_replay_refresh()

func _replay_refresh() -> void:
	var value: Dictionary = engine.state if replay_index == engine.state.history.size() else engine.state.history[replay_index].before
	replay_surface.update_state(value)
	replay_label.text = "第 %s / %s 手 · 只看回放，不改变当前局面" % [replay_index,engine.state.history.size()]

func _save(note: String, resume: bool = true) -> void:
	if engine.state.is_empty():
		return
	engine.state.view = view
	SaveStore.save_state(game_id,str(players[0].id),engine.snapshot(),note,resume and (engine.state.phase == "playing" or view == "map"))

func _confirm_restart() -> void:
	_close_top_modal()
	open_modal("重新开始？",PlaygroundUI.label("当前棋局重新开始，已经完成的关卡和其他游戏会保留。",20,PlaygroundUI.INK_SOFT,500,true),[
		{"text":"继续这局","kind":"soft","callback":func(): _close_top_modal()},
		{"text":"重新开始","kind":"primary","callback":func(): _close_top_modal(); toggle_pause(false); _create(level_id); _refresh()},
	])

func _process(delta: float) -> void:
	super._process(delta)
	if is_instance_valid(surface):
		surface.interactive = not paused and view == "board" and engine.state.get("phase","") == "playing" and not (mode_id == "puzzle" and int(engine.state.turn) == 1)
	if paused or view != "board" or engine.state.is_empty() or engine.state.phase != "playing":
		return
	if mode_id == "puzzle" and int(engine.state.turn) == 1:
		if is_instance_valid(surface) and surface.motion >= 0.999:
			_fixed_reply()
		return
	_idle_seconds += delta
	var hint_seconds := int(GameTuning.value(game_id,difficulty,"hintSeconds",18))
	if hint_seconds > 0 and not bool(engine.state.get("autoHintShown",false)) and mode_id == "puzzle" and _idle_seconds >= hint_seconds:
		engine.state.autoHintShown = true
		var text := str(engine.state.get("puzzle",{}).get("hint","再看看目标，试试另一处。"))
		show_toast(text,4)
		Speech.speak(text)
		_save("自动提示")
