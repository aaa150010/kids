class_name NativeBoardGame
extends NativeGameScreen

var engine := BoardRules.new()
var surface: BoardSurface
var status: Label
var detail: Label
var player_labels: Array[Label] = []
var player_panels: Array[PanelContainer] = []
var game_header: Control
var game_tools: Control
var view := "board"
var replay_index := 0
var replay_surface: BoardSurface
var replay_label: Label
var _idle_seconds := 0.0
var _last_immersive_turn := -1

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
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	header.add_child(_player_chip(0))
	var middle := CenterContainer.new()
	middle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	middle.add_child(PlaygroundUI.chip("自由五子 · 无禁手" if game_id == "gomoku" else "鼠吃象 · 狮虎跳河", accent))
	header.add_child(middle)
	header.add_child(_player_chip(1))
	content_root.add_child(header)
	game_header = header
	surface = BoardSurface.new()
	surface.game_id = game_id
	surface.accent = accent
	surface.face_to_face = TabletopLayout.enabled(game_id, players, mode_id)
	surface.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	surface.size_flags_vertical = Control.SIZE_EXPAND_FILL
	surface.cell_pressed.connect(_cell)
	surface.previewed.connect(func(): lesson_action("select"))
	content_root.add_child(surface)
	status = PlaygroundUI.label("",22,accent,700,true)
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content_root.add_child(status)
	detail = PlaygroundUI.label("",16,PlaygroundUI.INK_SOFT,500,true)
	detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content_root.add_child(detail)
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
	game_tools = tools
	_on_immersive_changed(immersive)

func _player_chip(side: int) -> Control:
	var panel := PlaygroundUI.panel(PlaygroundUI.mix(accent,Color.WHITE,0.88),18,PlaygroundUI.mix(accent,Color.WHITE,0.4),2)
	panel.custom_minimum_size = Vector2(230,60)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation",10)
	panel.add_child(row)
	if side < players.size():
		row.add_child(ArtLibrary.profile_picture(players[side], Vector2(46, 48)))
	else:
		row.add_child(ArtLibrary.semantic_picture("trophy", "ui", Vector2(46, 48)))
	var copy := VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.add_theme_constant_override("separation",1)
	var name := str(players[side].name) if side < players.size() else "本关目标"
	copy.add_child(PlaygroundUI.label(name,18,PlaygroundUI.INK,700,true))
	var text := PlaygroundUI.label("",14,PlaygroundUI.INK_SOFT,500,true)
	copy.add_child(text)
	row.add_child(copy)
	player_labels.append(text)
	player_panels.append(panel)
	return panel


func _extra_topbar_actions(row: HBoxContainer) -> void:
	var rules := PlaygroundUI.button("规则", accent, show_game_rules, "soft")
	rules.custom_minimum_size = Vector2(70,48)
	rules.add_theme_font_size_override("font_size", 17)
	row.add_child(rules)


func show_game_rules() -> void:
	_show_rules()


func _on_immersive_changed(value: bool) -> void:
	if game_header != null and is_instance_valid(game_header):
		game_header.visible = not value
	if status != null and is_instance_valid(status):
		status.visible = not value
	if detail != null and is_instance_valid(detail):
		detail.visible = not value
	if game_tools != null and is_instance_valid(game_tools):
		game_tools.visible = not value
	if value:
		_last_immersive_turn = int(engine.state.get("turn", 0)) if not engine.state.is_empty() else -1


func _extra_pause_actions() -> Array:
	var actions: Array = []
	if mode_id == "puzzle":
		actions.append({"text":"关卡地图", "icon":"back", "kind":"soft", "callback":func(): _close_pause_tools(); _show_map()})
		actions.append({"text":"看提示", "icon":"hint", "kind":"soft", "callback":func(): _close_pause_tools(); _hint()})
	elif game_id == "gomoku":
		actions.append({"text":"显示手数", "icon":"game", "kind":"soft", "callback":_toggle_numbers_from_pause})
	actions.append({"text":"悔棋", "icon":"undo", "kind":"soft", "callback":func(): _close_pause_tools(); _request_undo()})
	return actions


func _toggle_numbers_from_pause() -> void:
	_close_pause_tools()
	if is_instance_valid(surface):
		surface.show_numbers = not surface.show_numbers
		surface.queue_redraw()


func _refresh(animate: bool = false) -> void:
	if surface == null or not is_instance_valid(surface):
		return
	var selected := engine.piece_by_id(str(engine.state.get("selected","")))
	var targets: Array = engine.legal_moves(selected) if not selected.is_empty() else []
	surface.interactive = not paused and view == "board" and engine.state.phase == "playing" and not (mode_id == "puzzle" and int(engine.state.turn) == 1)
	surface.update_state(engine.state,targets,animate)
	if immersive and str(engine.state.phase) == "playing" and int(engine.state.turn) != _last_immersive_turn:
		_last_immersive_turn = int(engine.state.turn)
		var who := str(players[int(engine.state.turn)].get("name","")) if int(engine.state.turn) < players.size() else ""
		var hint := "轮到你"
		if not who.is_empty():
			hint = "%s · 轮到你" % who
		show_toast(hint, 1.1)
	for side in 2:
		var current: bool = int(engine.state.turn) == side and str(engine.state.phase) == "playing"
		player_panels[side].add_theme_stylebox_override("panel",PlaygroundUI.style(PlaygroundUI.mix(accent,Color.WHITE,0.85 if current else 0.94),22,accent if current else PlaygroundUI.LINE,3 if current else 1))
		if side < players.size():
			var prefix := "现在轮到你" if current else "等一等，慢慢想"
			if str(engine.state.phase) == "finished":
				prefix = "本局结束"
			player_labels[side].text = prefix
		else:
			player_labels[side].text = "本关目标"
	if not selected.is_empty():
		var captures := targets.filter(func(target): return not engine.piece_at(int(target)).is_empty()).size()
		detail.text = "%s\n可走 %s 格 · 可吃 %s 枚" % [BoardRules.NAMES[selected.kind],targets.size() - captures,captures]
	elif mode_id == "puzzle":
		detail.text = "第 %s 关\n目标 %s 步\n已走 %s 步" % [level_id,int(engine.state.puzzle.get("targetSteps",1)),int(engine.state.moveCount)]
	else:
		var military_hint := "先翻开暗棋；同一人连续翻出两次同色即可定阵营。" if game_id == "military" and not bool(engine.state.get("factionAssigned", false)) else "红蓝双方轮流行动"
		detail.text = "第 %s 手\n%s" % [int(engine.state.moveCount)+1,"空交叉点落子" if game_id == "gomoku" else military_hint]
	status.text = str(engine.state.reason) if engine.state.phase == "finished" else "点空交叉点落子，按住可以预览" if game_id == "gomoku" else "点亮起的位置移动" if not selected.is_empty() else "先翻两次同色定阵营，再选自己的亮棋" if game_id == "military" and not bool(engine.state.get("factionAssigned", false)) else "先翻暗棋，或选自己的亮棋" if game_id == "military" else "先选自己的动物，再点发光格子"

func _cell(position: int) -> void:
	if paused or view != "board" or engine.state.phase != "playing" or (mode_id == "puzzle" and int(engine.state.turn) == 1):
		return
	var target := engine.piece_at(position)
	var action := {"type":"move","to":position}
	if game_id != "gomoku" and engine.can_select(target):
		action.type = "select"
	var result := engine.handle_input(action)
	if not bool(result.ok):
		engine.state.interactionNote = {
			"message": str(result.get("message", "试试亮起的位置")),
			"cells": [position] if position >= 0 else [],
			"side": int(engine.state.get("turn", 0)),
		}
		_shake_for_failed(position)
		SfxMap.play(&"error")
		FeedbackKit.haptic(15)
		_save("正在查看落点原因")
		_refresh()
		return
	engine.state.interactionNote = {}
	var event := str(result.event)
	if event == "select":
		SfxMap.play(&"select")
	elif event == "flip":
		SfxMap.play(&"flip")
		if bool(result.get("factionAssigned", false)):
			show_toast("阵营确定：你执%s方！" % ("红" if int(result.get("factionSide", 0)) == 0 else "蓝"), 4)
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
	var line: Array = engine.state.puzzle.get("line", [])
	var cursor := int(engine.state.get("lineIndex", 0))
	var target := int(line[cursor].get("to", -1)) if cursor >= 0 and cursor < line.size() and line[cursor] is Dictionary else -1
	engine.state.interactionNote = {"message":text, "cells":[target] if target >= 0 else [], "side":int(engine.state.get("turn",0))}
	Speech.speak(text)
	_save("看过提示")
	_refresh()


func _show_rules() -> void:
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	var lines: Array = []
	if game_id == "jungle":
		lines = [
			"棋盘：9 列 × 7 行，横向摆放；左右两端各有一座兽穴。",
			"等级：象 8、狮 7、虎 6、豹 5、狼 4、狗 3、猫 2、鼠 1；同级可以互吃。",
			"鼠能吃象，象不能吃鼠；只有鼠能进入蓝色河流，水中棋子只能吃水中的鼠。",
			"狮和虎可以横竖跳过河流，但河的路径上只要有鼠就会挡住跳跃。",
			"进入对方陷阱的棋子战力归零，任何己方棋子都可以吃掉它；不能进入自己的兽穴。",
			"进入对方兽穴、吃光对方棋子或让对方没有合法动作即可获胜。",
		]
	elif game_id == "gomoku":
		lines = [
			"双方轮流在空交叉点落子，先连成五颗或更多同色棋子的一方获胜。",
			"本地采用自由五子规则：不禁手，长连也算胜。",
			"按住空交叉点可以预览落点，松手后确认；最后落子会用金色圆环标出。",
			"残局中悔棋会同时撤回玩家这一步和固定自动应手。",
		]
	else:
		lines = [
			"开局所有棋子背面朝上，两位玩家轮流翻开一枚暗棋。",
			"同一位玩家连续翻出两次同色棋子后确定阵营；之后只能移动自己颜色的亮棋。",
			"每回合只能选择翻棋或走棋一次；行营内的棋子不能被攻击。",
			"地雷不能移动，工兵可以排雷；炸弹与目标同归于尽，夺取军旗即可获胜。",
			"铁路可以让普通棋子沿直线快速移动，工兵可以沿铁路转弯。",
		]
	for index in lines.size():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.add_child(PlaygroundUI.chip(str(index + 1), accent))
		var text := PlaygroundUI.label(str(lines[index]), 19, PlaygroundUI.INK_SOFT, 500, true)
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(text)
		body.add_child(row)
	open_modal("规则小书", body, [
		{"text": "读给我听", "kind": "soft", "callback": func(): Speech.speak(" ".join(PackedStringArray(lines)))},
		{"text": "知道了", "kind": "primary", "callback": func(): _close_top_modal()},
	], "先看规则再开局")

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
		var winner_player := engine.player_for_side(int(state.winner))
		for side in players.size():
			var outcome := "draw" if int(state.winner) < 0 else "win" if side == winner_player else "loss"
			SaveStore.record_outcome(str(players[side].id),game_id,outcome,stars if mode_id == "puzzle" else 1 if outcome == "win" else 0,0,0,{"strategy":{"correct":1 if outcome == "win" else 0,"answered":1}},str(state.get("sessionId","legacy-"+game_id+str(state.moveCount))))
		_save("本局完成",false)
	var content := VBoxContainer.new()
	var trophy := ArtLibrary.semantic_picture("trophy", "ui", Vector2(100, 100))
	trophy.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	content.add_child(trophy)
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

func _show_replay() -> void:
	if engine.state.is_empty():
		return
	replay_index = 0
	var content := VBoxContainer.new()
	replay_surface = BoardSurface.new()
	replay_surface.game_id = game_id
	replay_surface.face_to_face = TabletopLayout.enabled(game_id, players, mode_id)
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
