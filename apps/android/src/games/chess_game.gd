class_name NativeChessGame
extends NativeGameScreen

var engine := ChessRules.new()
var board: ChessBoard
var status: Label
var detail: Label
var player_labels: Array[Label] = []
var player_panels: Array[PanelContainer] = []
var game_header: Control
var game_tools: Control
var _last_immersive_turn := -1
var _recovery_snapshot: Dictionary = {}
var _result_visible := false
var _replay_board: ChessBoard
var _replay_label: Label
var _replay_index := 0


func _ready() -> void:
	build_shell()
	var stored := SaveStore.load_state(game_id, players.map(func(player): return str(player.id)))
	stored.modeId = mode_id
	if stored.get("recoverySnapshot") is Dictionary:
		_recovery_snapshot = stored.recoverySnapshot.duplicate(true)
	var restored := stored.get("players") is Array and engine.restore(stored)
	var recovered := false
	if restored:
		players = engine.state.players.duplicate(true)
		level_id = int(engine.state.get("levelId", 1))
		if engine.state.phase == "finished" and not bool(stored.get("resume", true)):
			var current_level := level_id
			engine.state = {}
			_create(current_level)
	else:
		var stored_fields: Array = stored.keys().filter(func(key): return str(key) != "modeId")
		if not stored_fields.is_empty():
			_recovery_snapshot = stored.duplicate(true)
			_recovery_snapshot.erase("recoverySnapshot")
			recovered = true
		_create()
	_build_board()
	_refresh()
	if restored:
		_save("象棋局面已恢复")
	if recovered:
		show_toast("原局面已保留备份，从本局开头继续", 3.0)
	call_deferred("begin_lesson")


func _create(number: int = 1) -> void:
	level_id = maxi(1, number)
	if mode_id == "puzzle":
		var puzzles := ContentDB.chess_puzzles()
		if puzzles.is_empty():
			engine.create_session({"gameId": game_id, "modeId": "puzzle", "players": players, "puzzle": {}})
		else:
			level_id = clampi(level_id, 1, puzzles.size())
			engine.create_session({
				"gameId": game_id, "modeId": "puzzle", "players": players,
				"levelId": level_id, "puzzle": puzzles[level_id - 1], "seed": Time.get_ticks_usec(),
				"hintsMax": int(GameTuning.value(game_id, difficulty, "hints", 2)),
				"undosMax": int(GameTuning.value(game_id, difficulty, "undos", 3)),
			})
	else:
		engine.create_session({
			"gameId": game_id, "modeId": "classic", "players": players, "seed": Time.get_ticks_usec(),
			"hintsMax": int(GameTuning.value(game_id, difficulty, "hints", 2)),
			"undosMax": int(GameTuning.value(game_id, difficulty, "undos", 3)),
		})
	if not _recovery_snapshot.is_empty():
		engine.state.recoverySnapshot = _recovery_snapshot.duplicate(true)
	session_id = str(engine.state.sessionId)
	_save("开始中国象棋")


func preview_ready() -> void:
	_refresh()


func _build_board() -> void:
	PlaygroundUI.clear(content_root)
	content_root.rotation = 0.0
	player_labels.clear()
	player_panels.clear()
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	header.add_child(_player_chip(0))
	var middle := CenterContainer.new()
	middle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	middle.add_child(PlaygroundUI.chip("楚河汉界 · 红先黑后", accent))
	header.add_child(middle)
	header.add_child(_player_chip(1))
	content_root.add_child(header)
	game_header = header
	board = ChessBoard.new()
	board.accent = accent
	board.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	board.size_flags_vertical = Control.SIZE_EXPAND_FILL
	board.cell_pressed.connect(_cell)
	content_root.add_child(board)
	status = PlaygroundUI.label("", 22, accent, 700, true)
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content_root.add_child(status)
	detail = PlaygroundUI.label("", 16, PlaygroundUI.INK_SOFT, 500, true)
	detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content_root.add_child(detail)
	var tools := HFlowContainer.new()
	tools.alignment = FlowContainer.ALIGNMENT_CENTER
	tools.add_theme_constant_override("h_separation", 12)
	if mode_id == "puzzle":
		tools.add_child(PlaygroundUI.button("关卡列表", accent, _show_puzzle_map, "soft"))
		tools.add_child(PlaygroundUI.button("看提示", accent, _hint, "soft"))
	tools.add_child(PlaygroundUI.button("悔棋", accent, _undo, "soft"))
	tools.add_child(PlaygroundUI.button("重新开始", accent, _confirm_restart, "ghost"))
	content_root.add_child(tools)
	game_tools = tools
	_on_immersive_changed(immersive)


func _player_chip(side: int) -> Control:
	var panel := PlaygroundUI.panel(PlaygroundUI.mix(accent, Color.WHITE, 0.90), 18, PlaygroundUI.mix(accent, Color.WHITE, 0.45), 2)
	panel.custom_minimum_size = Vector2(230, 60)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	panel.add_child(row)
	var player: Dictionary = players[side] if side < players.size() else {}
	if player.is_empty():
		row.add_child(ArtLibrary.semantic_picture("trophy", "ui", Vector2(46, 48)))
	else:
		row.add_child(ArtLibrary.profile_picture(player, Vector2(46, 48)))
	var copy := VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.add_theme_constant_override("separation", 1)
	copy.add_child(PlaygroundUI.label(str(player.get("name", "本关目标")), 18, PlaygroundUI.INK, 700, true))
	var label := PlaygroundUI.label("", 14, PlaygroundUI.INK_SOFT, 500, true)
	copy.add_child(label)
	row.add_child(copy)
	player_labels.append(label)
	player_panels.append(panel)
	return panel


func _extra_topbar_actions(row: HBoxContainer) -> void:
	var rules := PlaygroundUI.button("规则", accent, show_game_rules, "soft")
	rules.custom_minimum_size = Vector2(70, 48)
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
	var actions: Array = [{"text":"悔棋", "icon":"undo", "kind":"soft", "callback":func(): _close_pause_tools(); _undo()}]
	if mode_id == "puzzle":
		actions.append({"text":"残局列表", "icon":"back", "kind":"soft", "callback":func(): _close_pause_tools(); _show_puzzle_map()})
		actions.append({"text":"看提示", "icon":"hint", "kind":"soft", "callback":func(): _close_pause_tools(); _hint()})
	return actions


func _refresh() -> void:
	if board == null or not is_instance_valid(board) or engine.state.is_empty():
		return
	if engine.state.phase == "finished" and not _result_visible:
		_show_result()
	board.interactive = not paused and engine.state.phase == "playing"
	var selected := int(engine.state.get("selected", -1))
	var targets := engine.legal_targets(selected) if selected >= 0 else []
	board.update_board(engine, int(engine.state.get("turn", 0)), selected, targets)
	var turn := int(engine.state.get("turn", 0))
	if immersive and engine.state.phase == "playing" and turn != _last_immersive_turn:
		_last_immersive_turn = turn
		show_toast("%s走棋" % engine.side_name(turn), 1.2)
	for side in 2:
		var current: bool = side == turn and str(engine.state.phase) == "playing"
		player_panels[side].add_theme_stylebox_override("panel", PlaygroundUI.style(
			PlaygroundUI.mix(accent, Color.WHITE, 0.84 if current else 0.94), 22,
			accent if current else PlaygroundUI.LINE, 3 if current else 1
		))
		player_labels[side].text = ("现在轮到你" if current else "等一等") + "\n" + engine.side_name(side)
	if engine.state.phase == "finished":
		status.text = str(engine.state.get("reason", "本局结束"))
		detail.text = "本局共走 %s 步，进度已经自动保存。" % int(engine.state.get("moveCount", 0))
	elif mode_id == "puzzle":
		status.text = "只走红方：一步将死或吃掉黑将"
		detail.text = "已尝试 %s 次 · 提示 %s / %s\n%s" % [
			int(engine.state.get("mistakes", 0)),
			int(engine.state.get("hints", 0)),
			int(engine.state.get("hintsMax", 2)),
			str(engine.state.get("lastPuzzleReply", engine.state.get("puzzle", {}).get("hint", "找一步直接吃掉黑将的走法。"))),
		]
	else:
		status.text = "红方走棋" if turn == 0 else "黑方走棋"
		if selected < 0:
			detail.text = "点自己的棋子，再点棋盘上的红点。"
		else:
			var selected_piece := engine.piece_at(selected)
			var captures := targets.filter(func(target): return not engine.piece_at(int(target)).is_empty()).size()
			detail.text = "%s：可走 %s 格 · 可吃 %s 枚" % [engine.piece_name(selected_piece), targets.size() - captures, captures]


func _cell(position: int) -> void:
	if paused or engine.state.phase != "playing":
		return
	var selected := int(engine.state.get("selected", -1))
	var piece := engine.piece_at(position)
	var action: Dictionary
	if selected >= 0 and position in engine.legal_targets(selected):
		action = {"type": "move", "to": position}
	elif selected >= 0:
		var explanation := engine.explain_move(selected, position)
		engine.state.interactionNote = {
			"message": str(explanation.get("message", engine.piece_hint(engine.piece_at(selected)))),
			"cells": explanation.get("cells", [position]),
			"side": int(engine.state.turn),
		}
		if position != selected and not piece.is_empty() and int(piece.side) == int(engine.state.turn) and not engine.legal_targets(position).is_empty():
			action = {"type": "select", "position": position}
		else:
			SfxMap.play(&"error")
			FeedbackKit.haptic(12)
			_save("正在查看走法原因")
			_refresh()
			return
	elif not piece.is_empty() and int(piece.side) == int(engine.state.turn):
		if engine.legal_targets(position).is_empty():
			var hint := engine.piece_hint(piece)
			engine.state.interactionNote = {"message": hint, "cells": [position], "side": int(engine.state.turn)}
			SfxMap.play(&"error")
			_refresh()
			return
		action = {"type": "select", "position": position}
	else:
		var hint := "先选自己这一方的棋子" if piece.is_empty() else "这是对方的棋子，先选自己的"
		engine.state.interactionNote = {"message": hint, "cells": [position] if position >= 0 else [], "side": int(engine.state.turn)}
		SfxMap.play(&"error")
		_refresh()
		return
	var result := engine.handle_input(action)
	if not bool(result.get("ok", false)):
		if state_is_puzzle_miss(result):
			engine.state.interactionNote = {
				"message": str(result.get("message", "这一步还不是一步杀")),
				"cells": result.get("cells", [position]),
				"side": 0,
			}
			_save("一步杀再试一次")
			_refresh()
		SfxMap.play(&"error")
		show_toast(str(result.get("message", "试试亮起的位置")))
		return
	if action.type == "select":
		SfxMap.play(&"select")
	else:
		SfxMap.play(&"move")
	engine.state.interactionNote = {}
	_save("中国象棋进行中")
	_refresh()
	if engine.state.phase == "finished":
		_show_result()


func state_is_puzzle_miss(result: Dictionary) -> bool:
	return bool(result.get("puzzleMiss", false))


func _undo() -> void:
	if paused or engine.state.phase != "playing" or engine.state.history.is_empty():
		show_toast("现在没有可以撤回的走法")
		return
	if int(engine.state.get("undos", 0)) >= int(engine.state.get("undosMax", 3)):
		show_toast("这一档难度的悔棋次数已经用完。")
		return
	if mode_id == "classic" and players.size() == 2:
		open_modal("悔棋确认", PlaygroundUI.label("请另一位小朋友确认，是否撤回最近一步？", 21, PlaygroundUI.INK, 500, true), [
			{"text": "继续下棋", "kind": "soft", "callback": func(): _close_top_modal()},
			{"text": "同意撤回", "kind": "primary", "callback": _perform_undo},
		], "双方棋局")
		return
	_perform_undo()


func _perform_undo() -> void:
	if not _modal_stack.is_empty():
		var top: Control = _modal_stack.back()
		if is_instance_valid(top):
			_close_top_modal()
	if not engine.undo_last_move():
		show_toast("现在没有可以撤回的走法")
		return
	_save("撤回了一步")
	_refresh()


func _hint() -> void:
	if paused or engine.state.phase != "playing" or mode_id != "puzzle":
		return
	var result := engine.handle_input({"type": "hint"})
	if not bool(result.get("ok", false)):
		show_toast(str(result.get("message", "现在没有可用提示。")))
		return
	var text := str(result.get("hint", "找一步直接吃掉黑将的走法。"))
	var target := int(result.get("cell", -1))
	engine.state.interactionNote = {"message": text, "cells": [target] if target >= 0 else [], "side": 0}
	Speech.speak(text)
	_save("看过一步杀提示")
	_refresh()


func _confirm_restart() -> void:
	open_modal("重新开始？", PlaygroundUI.label("当前局面会保存为上一局，确认后重新开局。", 19, PlaygroundUI.INK, 500, true), [
		{"text": "继续下棋", "kind": "soft", "callback": func(): _close_top_modal()},
		{"text": "重新开始", "kind": "primary", "callback": func(): _restart_game()},
	], "中国象棋")


func _restart_game() -> void:
	_close_top_modal()
	if paused:
		toggle_pause(false)
	_result_visible = false
	_create(level_id)
	_build_board()
	_refresh()


func _show_puzzle_map() -> void:
	if mode_id != "puzzle":
		return
	var puzzles := ContentDB.chess_puzzles()
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	for index in puzzles.size():
		var puzzle: Dictionary = puzzles[index]
		var number := index + 1
		var unlocked := SaveStore.level_unlocked(str(players[0].id), game_id, number, mode_id)
		var button := PlaygroundUI.button(
			"%s\n%s" % [str(puzzle.get("title", "一步杀")), "一步杀" if unlocked else "尚未解锁"],
			accent,
			_open_puzzle.bind(index),
			"primary" if number == level_id else "soft"
		)
		button.custom_minimum_size = Vector2(0, 76)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.disabled = not unlocked
		grid.add_child(button)
	body.add_child(grid)
	open_modal("中国象棋残局", body, [{"text": "关闭", "kind": "soft", "callback": func(): _close_top_modal()}], "一步杀练习")


func _open_puzzle(index: int) -> void:
	if not SaveStore.level_unlocked(str(players[0].id), game_id, index + 1, mode_id):
		show_toast("先完成前一关，再来挑战这一关。")
		return
	_close_top_modal()
	_result_visible = false
	_create(index + 1)
	_build_board()
	_refresh()


func _show_rules() -> void:
	var lines: Array = []
	if mode_id == "puzzle":
		lines = [
			"这是单人一步杀练习：只走红方，目标是一步将死或吃掉黑将。",
			"先点红方棋子，再点亮起的交叉点；不是一步杀的走法不会改变棋盘。",
			"可以看提示，也可以重开；尝试次数和提示次数都会影响星级。",
			"经典双人模式仍然是红方先走，双方轮流走棋。",
		]
	else:
		lines = [
			"红方先走，双方轮流走一步；点自己的棋子，再点亮起的交叉点。",
			"车走直线，炮吃子要隔一个棋子；马走日字，象走田字且不能塞象眼。",
			"士和将只在九宫里走；兵卒没过河只能向前，过河后也能横着走。",
			"不能让将帅直接照面，也不能走出让自己被将军的棋。",
			"将死对方、让对方无棋可走，或吃掉对方的将帅就获胜；所有进度都会自动保存。",
		]
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	for index in lines.size():
		var row := HBoxContainer.new()
		row.add_child(PlaygroundUI.chip(str(index + 1), accent))
		var label := PlaygroundUI.label(lines[index], 18, PlaygroundUI.INK_SOFT, 500, true)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		body.add_child(row)
	open_modal("中国象棋规则", body, [
		{"text": "读给我听", "kind": "soft", "callback": func(): Speech.speak(" ".join(PackedStringArray(lines)))},
		{"text": "知道了", "kind": "primary", "callback": func(): _close_top_modal()},
	], "楚河汉界")


func _show_result() -> void:
	var state := engine.state
	if not bool(state.get("reported", false)):
		state.reported = true
		if mode_id == "puzzle" and int(state.winner) == 0:
			var stars := 1
			if int(state.get("hints", 0)) == 0 and int(state.get("mistakes", 0)) == 0:
				stars = 3
			elif int(state.get("hints", 0)) == 0:
				stars = 2
			SaveStore.complete_level(str(players[0].id), game_id, level_id, stars, mode_id)
			SaveStore.record_outcome(str(players[0].id), game_id, "win", stars, 1, 1, {"strategy": {"correct": 1, "answered": 1}}, str(state.get("sessionId", "chess")))
		elif mode_id == "classic":
			for side in players.size():
				var outcome := "draw" if int(state.winner) < 0 else "win" if side == int(state.winner) else "loss"
				SaveStore.record_outcome(str(players[side].id), game_id, outcome, 1 if outcome == "win" else 0, 0, 0, {"strategy": {"correct": 1 if outcome == "win" else 0, "answered": 1}}, str(state.get("sessionId", "chess")))
		_save("中国象棋完成", false)
	if _result_visible:
		return
	_result_visible = true
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	var trophy := ArtLibrary.semantic_picture("trophy", "ui", Vector2(88, 88))
	trophy.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	body.add_child(trophy)
	body.add_child(PlaygroundUI.label(str(state.get("reason", "本局结束")), 24, accent, 700, true))
	open_modal("中国象棋结束", body, [
		{"text": "棋谱回放", "icon": "repeat", "kind": "soft", "callback": func(): _result_visible = false; _close_top_modal(); _show_replay()},
		{"text": "再看棋盘", "kind": "soft", "callback": func(): _result_visible = false; _close_top_modal()},
		{"text": "再来一局", "kind": "primary", "callback": func(): _result_visible = false; _restart_game()},
	], "本局已自动保存")


func _show_replay() -> void:
	if engine.state.is_empty() or engine.state.get("history", []).is_empty():
		show_toast("这一局还没有可以回放的步骤")
		return
	_replay_index = 0
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	_replay_board = ChessBoard.new()
	_replay_board.accent = accent
	_replay_board.interactive = false
	_replay_board.custom_minimum_size = Vector2(760, 520)
	body.add_child(_replay_board)
	_replay_label = PlaygroundUI.label("", 18, accent, 700)
	_replay_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(_replay_label)
	open_modal("棋谱回放", body, [
		{"text": "上一步", "icon": "back", "kind": "soft", "callback": _replay_step.bind(-1)},
		{"text": "下一步", "icon": "next", "kind": "soft", "callback": _replay_step.bind(1)},
		{"text": "关闭回放", "icon": "close", "kind": "primary", "callback": func(): _close_top_modal()},
	], "回放不会改变当前棋局")
	_refresh_replay()


func _replay_step(direction: int) -> void:
	var count := int(engine.state.get("history", []).size())
	_replay_index = clampi(_replay_index + direction, 0, count)
	_refresh_replay()


func _refresh_replay() -> void:
	if not is_instance_valid(_replay_board):
		return
	var history: Array = engine.state.get("history", [])
	var replay_state := engine.state.duplicate(true)
	if _replay_index < history.size() and history[_replay_index] is Dictionary and history[_replay_index].get("before") is Dictionary:
		replay_state.merge(history[_replay_index].before.duplicate(true), true)
	var replay_rules := ChessRules.new()
	replay_rules.state = replay_state
	var side := int(replay_state.get("turn", 0))
	_replay_board.update_board(replay_rules, side, -1, [])
	_replay_label.text = "第 %s / %s 步 · 只查看，不改变当前局面" % [_replay_index, history.size()]


func _save(note: String, resume: bool = true) -> void:
	if engine.state.is_empty():
		return
	SaveStore.save_state(game_id, str(players[0].id), engine.snapshot(), note, resume and str(engine.state.get("phase", "")) == "playing")
