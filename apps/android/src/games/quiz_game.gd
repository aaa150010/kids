class_name NativeQuizGame
extends NativeGameScreen

var engine := QuizRules.new()
var stage: QuizStage
var feedback_panel: PanelContainer
var feedback_title: Label
var feedback_text: Label
var next_button: Button
var player_labels: Array[Label] = []
var player_panels: Array[PanelContainer] = []
var game_controls: Control
var view := "question"
var family := "mixed"
var _last_question := ""
var _last_immersive_player := -1

func _ready() -> void:
	build_shell()
	var stored := SaveStore.load_state(game_id,players.map(func(player): return str(player.id)))
	if engine.restore(stored):
		players = engine.state.players.duplicate(true)
		level_id = int(engine.state.get("levelId",1))
		difficulty = str(engine.state.get("difficulty",difficulty))
		family = str(engine.state.get("family",engine.state.get("workbookPractice","mixed")))
		view = str(engine.state.get("view","question"))
		if engine.state.phase == "result" and not bool(stored.get("resume",true)):
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
	if view == "map" and mode_id == "adventure":
		_show_map()
	else:
		_build_session()
		_refresh()
	call_deferred("begin_lesson")

func _show_map() -> void:
	view = "map"
	PlaygroundUI.clear(content_root)
	content_root.add_child(PlaygroundUI.label("今天探索哪一关？",30,accent,700))
	content_root.add_child(PlaygroundUI.label("一颗星就能继续，喜欢的关卡可以反复练习。",18,PlaygroundUI.INK_SOFT,500,true))
	content_root.add_child(level_map(_choose_level))
	if not engine.state.is_empty():
		_save("正在看关卡地图")

func _choose_level(number: int) -> void:
	if not SaveStore.level_unlocked(str(players[0].id),game_id,number,mode_id):
		return
	level_id = number
	_new_session()
	_build_session()
	_refresh()
	begin_lesson()

func _new_session() -> void:
	var chapter := ContentDB.level(game_id,level_id)
	var count := int(GameTuning.value(game_id, difficulty, "rounds", 8))
	var pools: Array = []
	var family_id := str(chapter.get("family","mixed")) if mode_id == "adventure" else family
	for player in players:
		var pool := ContentDB.questions(game_id,int(player.age))
		var progress := SaveStore.learning(str(player.id),game_id,mode_id)
		if mode_id == "review":
			pool = pool.filter(func(question): return str(question.id) in progress.wrongIds)
		elif family_id not in ["mixed",""]:
			var family_pool := pool.filter(func(question): return str(question.get("family","")) == family_id)
			if not family_pool.is_empty():
				pool = family_pool
		if mode_id != "review":
			var fresh := pool.filter(func(question): return not (str(question.id) in progress.recentIds))
			if fresh.size() < mini(count,pool.size()):
				progress.recentIds = []
			else:
				pool = fresh
		pools.append(pool)
	engine.create_session({"gameId":game_id,"modeId":mode_id,"players":players.duplicate(true),"levelId":level_id,"difficulty":difficulty,"seed":int(chapter.get("seed",Time.get_ticks_usec())) if mode_id == "adventure" else Time.get_ticks_usec(),"pools":pools,"rounds":count,"family":family_id,"view":"question"})
	engine.state.erase("pools")
	view = "question"
	_last_question = ""
	_save("新的练习已开始")

func _build_session() -> void:
	PlaygroundUI.clear(content_root)
	player_labels.clear()
	player_panels.clear()
	var controls := HFlowContainer.new()
	controls.add_theme_constant_override("h_separation",12)
	if mode_id == "adventure":
		controls.add_child(PlaygroundUI.button("关卡地图",accent,_show_map,"soft"))
		controls.add_child(PlaygroundUI.chip("第 %s 关 · %s" % [level_id,ContentDB.level(game_id,level_id).get("title","")],accent))
	elif game_id == "workbook" and mode_id != "review":
		for entry in [["mixed","综合"],["foundation","基础"],["calculation","计算"],["application","应用"]]:
			var target := str(entry[0])
			controls.add_child(PlaygroundUI.button(str(entry[1]),accent,_change_family.bind(target),"primary" if family == target else "soft"))
	controls.add_child(PlaygroundUI.button("重新开始",accent,_confirm_restart,"ghost"))
	content_root.add_child(controls)
	game_controls = controls
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation",14)
	for side in 2:
		var panel := _player_panel(side)
		if side == 0:
			row.add_child(panel)
		else:
			stage = QuizStage.new()
			stage.game_id = game_id
			stage.accent = accent
			stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
			stage.answered.connect(_answer)
			stage.listen_requested.connect(_listen)
			row.add_child(stage)
			row.add_child(panel)
	content_root.add_child(row)
	feedback_panel = PlaygroundUI.panel(Color("#fff9e9"),22,PlaygroundUI.mix(accent,Color.WHITE,0.5),2)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",8)
	feedback_panel.add_child(column)
	feedback_title = PlaygroundUI.label("",22,accent,700,true)
	column.add_child(feedback_title)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = 72
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	feedback_text = PlaygroundUI.label("",20,PlaygroundUI.INK_SOFT,500,true)
	feedback_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(feedback_text)
	column.add_child(scroll)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation",12)
	var explain_button := PlaygroundUI.button("听讲解",accent,func(): Speech.speak(feedback_text.text),"soft")
	explain_button.custom_minimum_size = Vector2(148,64)
	actions.add_child(explain_button)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(spacer)
	next_button = PlaygroundUI.button("下一题 →",accent,_next)
	next_button.custom_minimum_size = Vector2(220,64)
	actions.add_child(next_button)
	column.add_child(actions)
	content_root.add_child(feedback_panel)
	_on_immersive_changed(immersive)

func _player_panel(index: int) -> Control:
	var panel := PlaygroundUI.panel(PlaygroundUI.mix(accent,Color.WHITE,0.9),24,PlaygroundUI.LINE)
	panel.custom_minimum_size.x = 156
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",16)
	panel.add_child(column)
	var player: Dictionary = players[index] if index < players.size() else {}
	column.add_child(ArtLibrary.picture(str(player.get("avatar","💡")),Vector2(100,108)))
	column.add_child(PlaygroundUI.label(str(player.get("name","慢慢想")),22,PlaygroundUI.INK,700,true))
	var label := PlaygroundUI.label("",18,PlaygroundUI.INK_SOFT,500,true)
	column.add_child(label)
	player_labels.append(label)
	player_panels.append(panel)
	return panel


func _on_immersive_changed(value: bool) -> void:
	if game_controls != null and is_instance_valid(game_controls):
		game_controls.visible = not value
	for panel in player_panels:
		if panel != null and is_instance_valid(panel):
			panel.visible = not value
	if value:
		_last_immersive_player = int(engine.state.get("currentPlayer", 0)) if not engine.state.is_empty() else -1


func _refresh() -> void:
	if engine.state.get("phase","") == "empty":
		feedback_panel.hide()
		stage.hide()
		player_labels[0].text = "这里还没有需要复习的题目。\n可以先玩自由练习。"
		return
	if engine.state.phase == "result":
		_finish()
		return
	var question := engine.question()
	var current := int(engine.state.currentPlayer)
	if immersive and current != _last_immersive_player:
		_last_immersive_player = current
		var who := str(players[current].get("name","")) if current < players.size() else ""
		var hint := "轮到你"
		if not who.is_empty():
			hint = "%s · 轮到你" % who
		show_toast(hint, 1.1)
	var progress := SaveStore.learning(str(players[current].id),game_id,mode_id)
	if not (str(question.id) in progress.recentIds):
		progress.recentIds.append(str(question.id))
	var totals: Array = engine.state.queues.map(func(queue): return queue.size())
	stage.set_progress(int(engine.state.scores[current]),int(engine.state.positions[current]),int(totals[current]))
	stage.update_question(question,int(engine.state.selected),engine.state.phase == "feedback",engine.state.scores,totals)
	for index in 2:
		if index < players.size():
			player_labels[index].text = "%s\n第 %s / %s 题\n★ %s" % ["现在轮到你" if index == current else "等待下一轮",mini(int(engine.state.positions[index])+1,int(totals[index])),int(totals[index]),int(engine.state.scores[index])]
			player_panels[index].add_theme_stylebox_override("panel",PlaygroundUI.style(PlaygroundUI.mix(accent,Color.WHITE,0.86 if index == current else 0.95),24,accent if index == current else PlaygroundUI.LINE,3 if index == current else 1))
		else:
			player_labels[index].text = "没有倒计时\n可以反复听题\n答后还有小讲解"
	feedback_panel.visible = engine.state.phase == "feedback"
	if feedback_panel.visible:
		feedback_panel.modulate.a = 0.0
		MotionKit.tween(self).tween_property(feedback_panel, "modulate:a", 1.0, 0.16)
		var correct := int(engine.state.selected) == int(question.answer)
		feedback_title.text = "答对啦！" if correct else "一起看一看，学会就好"
		feedback_text.text = "正确答案：%s\n%s" % [question.options[int(question.answer)],question.get("explanation","")]
		next_button.text = "查看成绩" if engine.final_question() else "下一题 →"
	elif _last_question != str(question.id):
		_last_question = str(question.id)
		Speech.speak(str(question.get("narration",question.get("prompt",""))))
	_save("正在看讲解" if engine.state.phase == "feedback" else "正在答题")

func _listen() -> void:
	if paused:
		return
	var question := engine.question()
	Speech.speak(str(question.get("narration",question.get("prompt",""))))
	lesson_action("listen")

func _answer(index: int) -> void:
	if paused:
		return
	var result := engine.handle_input({"type":"answer","index":index})
	if not bool(result.ok):
		return
	var current := int(engine.state.currentPlayer)
	var learning := SaveStore.learning(str(players[current].id),game_id,mode_id)
	var question: Dictionary = result.question
	if bool(result.correct):
		learning.wrongIds.erase(str(question.id))
	elif not (str(question.id) in learning.wrongIds):
		learning.wrongIds.append(str(question.id))
	SfxMap.play(&"success" if bool(result.correct) else &"error")
	FeedbackKit.haptic(10 if bool(result.correct) else 16)
	lesson_action("answer")
	_save("答案与讲解已保存")
	_refresh()
	Speech.speak("正确答案是%s。%s" % [question.options[int(question.answer)],question.get("explanation","")])

func _next() -> void:
	if paused:
		return
	var result := engine.handle_input({"type":"next"})
	if not bool(result.ok):
		return
	lesson_action("next")
	# 翻题的 whoosh 由答题舞台在滑出旧题时播放，这里不重复叠加
	_save("继续下一题")
	_refresh()

func _finish() -> void:
	if not bool(engine.state.get("reported",false)):
		for index in players.size():
			var score := int(engine.state.scores[index])
			var total: int = int(engine.state.queues[index].size())
			var outcome := "win" if players.size() == 1 or score > int(engine.state.scores[1-index]) else "draw" if score == int(engine.state.scores[1-index]) else "loss"
			var axis := str({"math":"math","workbook":"math","pinyin":"language","animals":"science"}.get(game_id,"logic"))
			SaveStore.record_outcome(str(players[index].id),game_id,outcome,score,score,total,{axis:{"correct":score,"answered":total}},str(engine.state.sessionId))
			if mode_id == "adventure":
				SaveStore.complete_level(str(players[index].id),game_id,level_id,GameTuning.stars(game_id,difficulty,score,total),mode_id)
		engine.state.reported = true
		_save("练习完成",false)
	PlaygroundUI.clear(content_root)
	var panel := PlaygroundUI.panel(PlaygroundUI.mix(accent,Color.WHITE,0.9),28,accent,2)
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation",20)
	panel.add_child(column)
	column.add_child(ArtLibrary.picture("🏆",Vector2(120,120)))
	column.add_child(PlaygroundUI.label("又学会了新本领！",36,accent,700))
	for index in players.size():
		column.add_child(PlaygroundUI.label("%s · 答对 %s / %s 题" % [players[index].name,int(engine.state.scores[index]),engine.state.queues[index].size()],26,PlaygroundUI.INK,700,true))
	if mode_id == "adventure":
		var stars := GameTuning.stars(game_id,difficulty,int(engine.state.scores[0]),engine.state.queues[0].size())
		column.add_child(PlaygroundUI.label("★".repeat(stars)+"☆".repeat(3-stars),42,Color("#c99520"),700))
		column.add_child(PlaygroundUI.label("获得一颗星就可以去下一关，也可以再练一遍。",19,PlaygroundUI.INK_SOFT,500,true))
	var actions := HFlowContainer.new()
	actions.add_theme_constant_override("h_separation",14)
	actions.add_child(PlaygroundUI.button("逐题复习",accent,_review_answers,"soft"))
	actions.add_child(PlaygroundUI.button("再练一次",accent,func(): _new_session(); _build_session(); _refresh(),"soft"))
	if mode_id == "adventure":
		actions.add_child(PlaygroundUI.button("关卡地图",accent,_show_map))
	column.add_child(actions)
	content_root.add_child(panel)
	SfxMap.play(&"win")
	FeedbackKit.haptic(14)

func _review_answers() -> void:
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation",18)
	for entry in engine.state.answers:
		var question: Dictionary = entry.get("question",{})
		if question.is_empty():
			continue
		var panel := PlaygroundUI.panel(PlaygroundUI.CREAM,18,PlaygroundUI.LINE)
		var column := VBoxContainer.new()
		column.add_child(PlaygroundUI.label(str(question.prompt),22,PlaygroundUI.INK,700,true))
		column.add_child(PlaygroundUI.label("正确答案：%s\n%s" % [question.options[int(question.answer)],question.get("explanation","")],19,PlaygroundUI.INK_SOFT,500,true))
		panel.add_child(column)
		list.add_child(panel)
	open_modal("逐题看一看",list,[{"text":"看完啦","kind":"primary","callback":func(): _close_top_modal()}])

func _change_family(target: String) -> void:
	if target == family:
		return
	open_modal("换一页练习？",PlaygroundUI.label("这一页会重新开始，已记录的错题和成长成绩会保留。",20,PlaygroundUI.INK_SOFT,500,true),[
		{"text":"继续这页","kind":"soft","callback":func(): _close_top_modal()},
		{"text":"换一页","kind":"primary","callback":func(): _close_top_modal(); family = target; _new_session(); _build_session(); _refresh()},
	])

func _confirm_restart() -> void:
	_close_top_modal()
	open_modal("重新开始这一页？",PlaygroundUI.label("已完成的关卡和自己的错题会保留。",20,PlaygroundUI.INK_SOFT,500,true),[
		{"text":"继续这页","kind":"soft","callback":func(): _close_top_modal()},
		{"text":"重新开始","kind":"primary","callback":func(): _close_top_modal(); toggle_pause(false); _new_session(); _build_session(); _refresh()},
	])

func _save(note: String, resume: bool = true) -> void:
	if engine.state.is_empty():
		return
	engine.state.view = view
	SaveStore.save_state(game_id,str(players[0].id),engine.snapshot(),note,resume and (engine.state.phase in ["question","feedback"] or view == "map"))
