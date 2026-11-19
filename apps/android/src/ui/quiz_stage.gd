class_name QuizStage
extends Control

signal answered(index: int)
signal listen_requested

const OUT_TIME := 0.12 # 旧题滑出时长
const IN_TIME := 0.22 # 新题弹入时长
const STAR_LIFE := 0.62 # 答对星星粒子生命周期
const STAR_GOAL := 3 # 每答对几题点亮一颗里程碑星

var game_id := "math"
var accent := Color("#2878c8")
var question: Dictionary = {}
var selected := -1
var feedback := false
var scores: Array = []
var totals: Array = []
var prompt: Label
var listen: Button
var buttons: Array[Button] = []
var clock := 0.0
var gain := 1.0
var _tokens: Array = []
var _tween: Tween
var _question_id := ""
var _pending: Dictionary = {} # 滑出期间暂存的新题数据
var _pending_id := ""
var _feedback_played := false # 同一题的抖动/彩带只播放一次
var _sparks: Array = [] # 自绘答对星星粒子
var _position := 0
var _total := 0
var _correct := 0

func _ready() -> void:
	custom_minimum_size = Vector2(420,390)
	clip_contents = true
	prompt = PlaygroundUI.label("",30,PlaygroundUI.INK,700,true)
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(prompt)
	listen = PlaygroundUI.button("听题",accent,_request_listen,"soft")
	listen.custom_minimum_size = Vector2(84,52)
	PressFeedback.attach(listen,&"select")
	add_child(listen)
	for index in 3:
		var button := PlaygroundUI.button("",accent,Callable(),"soft")
		button.custom_minimum_size = Vector2(96,64)
		PressFeedback.attach(button)
		button.pressed.connect(_choose.bind(index))
		add_child(button)
		buttons.append(button)
	resized.connect(_layout)
	_layout()

func update_question(value: Dictionary, answer_index: int, is_feedback: bool, current_scores: Array, current_totals: Array) -> void:
	var incoming := str(value.get("id",""))
	var is_new := incoming != _question_id
	var data := {
		"question": value.duplicate(true),
		"selected": answer_index,
		"feedback": is_feedback,
		"scores": current_scores.duplicate(),
		"totals": current_totals.duplicate(),
	}
	if is_new and not _question_id.is_empty() and is_inside_tree():
		# 先让旧题滑出，动画结束后再用 _finish_transition 换上新题弹入
		_pending = data
		if _pending_id != incoming:
			_pending_id = incoming
			_play_out()
		return
	_pending = {}
	_pending_id = ""
	_tween_kill()
	_apply(data)
	if is_new and not feedback:
		_play_in()

## 顶部进度：当前第几题 / 共几题，以及每答对 3 题点亮的里程碑星
func set_progress(correct: int, position: int, total: int) -> void:
	_total = maxi(total,0)
	_correct = maxi(correct,0)
	_position = clampi(position,0,maxi(_total-1,0))
	queue_redraw()

func _choose(index: int) -> void:
	# 弹窗接管输入或已经进入讲解时，忽略选项点击
	if feedback or not _pending.is_empty() or _blocked_by_dialog():
		return
	answered.emit(index)


func _request_listen() -> void:
	if not _pending.is_empty() or _blocked_by_dialog():
		return
	listen_requested.emit()

func _blocked_by_dialog() -> bool:
	var tree := get_tree()
	if tree == null:
		return false
	var hub := tree.get_first_node_in_group("main_hub")
	if hub == null:
		return false
	var controller = hub.get("ipc")
	return controller != null and controller.is_blocked_by_dialog()

func _apply(data: Dictionary) -> void:
	listen.disabled = false
	question = data.question
	_question_id = str(question.get("id",""))
	selected = int(data.selected)
	feedback = bool(data.feedback)
	scores = data.scores
	totals = data.totals
	if not feedback:
		_feedback_played = false
	_tokens = _visual_tokens(str(question.get("visual","")))
	prompt.text = str(question.get("prompt",""))
	prompt.modulate.a = 1.0
	prompt.scale = Vector2.ONE
	for index in 3:
		var button := buttons[index]
		button.modulate.a = 1.0
		button.scale = Vector2.ONE
		button.rotation = 0.0
		button.text = str(question.get("options",["","",""])[index])
		button.disabled = feedback
		var tint := accent
		if feedback:
			if index == int(question.get("answer",-1)):
				tint = Color("#4a9661")
			elif index == selected:
				tint = Color("#ce7654")
		button.add_theme_stylebox_override("disabled",PlaygroundUI.style(PlaygroundUI.mix(tint,Color.WHITE,0.8),20,tint,3))
		button.add_theme_color_override("font_disabled_color",PlaygroundUI.INK)
		for child in button.get_children():
			button.remove_child(child)
			child.queue_free()
		var symbols := ArtLibrary.symbols(button.text)
		if not symbols.is_empty() and button.text.length() <= symbols.size()*3:
			button.text = ""
			var row := HBoxContainer.new()
			row.alignment = BoxContainer.ALIGNMENT_CENTER
			row.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			for symbol in symbols:
				row.add_child(ArtLibrary.picture(str(symbol),Vector2(42,52)))
			button.add_child(row)
	_layout()
	if feedback:
		_play_feedback()
	queue_redraw()

## 答题反馈：答对保持绿色脉冲并撒星星，答错让错选项轻轻左右摇
func _play_feedback() -> void:
	if _feedback_played:
		return
	var answer := int(question.get("answer",-1))
	if answer < 0 or answer >= buttons.size():
		return
	_feedback_played = true
	# 正确选项始终绿色脉冲，答对时再撒一把星星
	_pulse(buttons[answer])
	if selected == answer:
		var button := buttons[answer]
		# 讲解面板出现会改变舞台高度，等一帧再按最新按钮位置撒星星
		var burst := MotionKit.tween(self)
		burst.tween_interval(0.04)
		burst.tween_callback(func():
			if feedback and selected == answer:
				_burst(button.position+button.size*0.5)
		)
	elif selected >= 0 and selected < buttons.size():
		MotionKit.kill_owner(buttons[selected]) # 结束按压回弹，避免和抖动抢变换
		buttons[selected].scale = Vector2.ONE
		_shake(buttons[selected])
	queue_redraw()

func _pulse(button: Button) -> void:
	MotionKit.kill_owner(button) # 结束按压回弹，避免和脉冲抢 scale
	button.scale = Vector2.ONE
	button.pivot_offset = button.size*0.5
	var pulse := MotionKit.tween(button)
	pulse.tween_property(button,"scale",Vector2(1.035,1.035),0.1)
	pulse.tween_property(button,"scale",Vector2.ONE,0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _shake(button: Button) -> void:
	button.pivot_offset = button.size*0.5
	var shake := MotionKit.tween(button)
	shake.tween_property(button,"rotation",deg_to_rad(-2.0),0.06)
	shake.tween_property(button,"rotation",deg_to_rad(2.0),0.08)
	shake.tween_property(button,"rotation",deg_to_rad(-1.2),0.07)
	shake.tween_property(button,"rotation",deg_to_rad(0.8),0.06)
	shake.tween_property(button,"rotation",0.0,0.05)

func _burst(center: Vector2) -> void:
	for index in 10:
		var angle := -PI*0.85+randf()*PI*0.7
		var speed := 90.0+randf()*150.0
		_sparks.append({
			"pos":center,
			"vel":Vector2(cos(angle),sin(angle))*speed,
			"life":STAR_LIFE*(0.75+randf()*0.35),
			"age":0.0,
			"size":5.0+randf()*6.5,
			"color":[Color("#f2b21e"),Color("#e8863c"),Color("#67a94f")][index%3],
			"spin":randf_range(-3.0,3.0),
			"angle":randf()*TAU,
		})

func _play_out() -> void:
	_tween_kill()
	for button in buttons:
		button.disabled = true
	listen.disabled = true
	_sparks.clear()
	SfxMap.play(&"move")
	var items := _content_items()
	for entry in items:
		var control: Control = entry
		control.pivot_offset = control.size*0.5
	var animation := MotionKit.tween(self)
	animation.set_parallel(true)
	for entry in items:
		var control: Control = entry
		animation.tween_property(control,"modulate:a",0.0,OUT_TIME)
		animation.tween_property(control,"scale",Vector2(0.98,0.98),OUT_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	animation.chain().tween_callback(_finish_transition)
	_tween = animation

func _finish_transition() -> void:
	if _pending.is_empty():
		return
	var data := _pending
	_pending = {}
	_pending_id = ""
	_tween = null # 滑出动画已经结束，避免在自己的回调里再次 kill
	_apply(data)
	_play_in()

func _play_in() -> void:
	_tween_kill()
	var items := _content_items()
	for entry in items:
		var control: Control = entry
		control.pivot_offset = control.size*0.5
		control.modulate.a = 0.0
		control.scale = Vector2(0.96,0.96)
	var animation := MotionKit.tween(self)
	animation.set_parallel(true)
	for entry in items:
		var control: Control = entry
		animation.tween_property(control,"modulate:a",1.0,IN_TIME)
		animation.tween_property(control,"scale",Vector2.ONE,IN_TIME).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween = animation

func _content_items() -> Array:
	var items: Array = [prompt]
	items.append_array(buttons)
	return items


func _visual_tokens(text: String) -> Array:
	var value := text.strip_edges()
	if value.is_empty():
		return []
	var tokens := ArtLibrary.symbols(value)
	if tokens.is_empty():
		return []
	var stripped := value
	for character in [" ", "\t", "\n", "、", "，", "。", "？", "?", "！", "!", ",", "."]:
		stripped = stripped.replace(character, "")
	var joined := "".join(PackedStringArray(tokens))
	return tokens if stripped.length() <= joined.length() + 2 else []


func _tween_kill() -> void:
	if _tween != null and is_instance_valid(_tween):
		_tween.kill()
	_tween = null

## 友好布局：题卡在上、视觉居中、三个答案卡整齐排在底部
func _layout() -> void:
	if prompt == null:
		return
	var pad := clampf(size.x*0.04,16.0,36.0)
	listen.size = Vector2(clampf(size.x*0.13,84.0,120.0),clampf(size.y*0.06,48.0,64.0))
	listen.position = Vector2(size.x-listen.size.x-16,12)
	var prompt_top := maxf(size.y*0.115,listen.size.y+18)
	var options_top := size.y*0.77
	var prompt_height := clampf(size.y*0.23,56.0,maxf(56.0,options_top-prompt_top-8.0))
	prompt.position = Vector2(pad,prompt_top)
	prompt.size = Vector2(size.x-pad*2,prompt_height)
	prompt.pivot_offset = prompt.size*0.5
	var gap := clampf(size.x*0.012,6.0,14.0)
	var width := (size.x-pad*2-gap*2)/3.0
	var height := clampf(size.y*0.17,88.0,164.0)
	var answer_font := clampi(int(size.y*0.026),20,30)
	for index in buttons.size():
		buttons[index].position = Vector2(pad+index*(width+gap),options_top)
		buttons[index].size = Vector2(width,height)
		buttons[index].pivot_offset = buttons[index].size*0.5
		buttons[index].add_theme_font_size_override("font_size",answer_font)
	_fit_prompt()

## 题面文字超宽或超高时自动缩字号，保证短窗口也完整显示
func _fit_prompt() -> void:
	var text := str(question.get("prompt",""))
	if text.is_empty():
		return
	var fitted := clampi(int(size.y*0.038),26,46)
	if size.x < 560 or size.y < 470:
		fitted = mini(fitted,26)
	if size.x < 460 or size.y < 400:
		fitted = mini(fitted,22)
	var available := maxf(40.0,prompt.size.x)
	var font := PlaygroundUI.font()
	while fitted > 16:
		var width := font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,fitted).x
		var lines := maxi(1,ceili(width/available))
		if float(lines)*float(fitted)*1.32 <= prompt.size.y:
			break
		fitted -= 2
	if prompt.get_theme_font_size("font_size") != fitted:
		prompt.add_theme_font_size_override("font_size",fitted)

func _process(delta: float) -> void:
	var parent := get_parent()
	while parent != null and not parent is NativeGameScreen:
		parent = parent.get_parent()
	if parent != null and parent.paused:
		return
	clock += delta
	_update_sparks(delta)
	queue_redraw()

func _update_sparks(delta: float) -> void:
	if _sparks.is_empty():
		return
	var alive: Array = []
	for entry in _sparks:
		var spark: Dictionary = entry
		spark["age"] = float(spark["age"])+delta
		if float(spark["age"]) >= float(spark["life"]):
			continue
		var velocity: Vector2 = spark["vel"]
		velocity.y += 320.0*delta
		var spot: Vector2 = spark["pos"]
		spot += velocity*delta
		spark["vel"] = velocity
		spark["pos"] = spot
		spark["angle"] = float(spark["angle"])+float(spark["spin"])*delta
		alive.append(spark)
	_sparks = alive

func _draw() -> void:
	var rectangle := Rect2(Vector2.ZERO,size)
	var background := Color("#cbeafa") if game_id == "math" else Color("#fff7ea") if game_id in ["pinyin","workbook"] else Color("#f8e7b1") if game_id == "patterns" else Color("#dfedc1")
	draw_style_box(PlaygroundUI.style(background,28,PlaygroundUI.mix(accent,Color.WHITE,0.4),2),rectangle)
	match game_id:
		"math": _draw_water()
		"pinyin": _draw_letters()
		"patterns": _draw_patterns()
		"animals": _draw_animals()
		"workbook": _draw_workbook()
	var prompt_card := Rect2(prompt.position-Vector2(14,10),prompt.size+Vector2(28,20))
	draw_style_box(PlaygroundUI.style(Color(1,1,1,0.76),24,PlaygroundUI.mix(accent,Color.WHITE,0.5),2,4,Color(0,0,0,0.08)),prompt_card)
	var visual_card := Rect2(size.x*0.16,size.y*0.37,size.x*0.68,size.y*0.24)
	draw_style_box(PlaygroundUI.style(Color(1,1,1,0.36),24,PlaygroundUI.mix(accent,Color.WHITE,0.65),1),visual_card)
	_draw_progress()
	_draw_sparks()

## 顶部小标签 + 里程碑星（每答对 3 题点亮一颗，最多 3 颗）
func _draw_progress() -> void:
	if _total <= 0:
		return
	var font := PlaygroundUI.font()
	var font_size := 17 if size.x >= 520 else 15
	var text := "第 %s / %s 题" % [mini(_position+1,_total),_total]
	var width := font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x+26
	draw_style_box(PlaygroundUI.style(PlaygroundUI.mix(accent,Color.WHITE,0.78),17,PlaygroundUI.mix(accent,Color.WHITE,0.4),2),Rect2(16,12,width,34))
	draw_string(font,Vector2(16+13,12+17+font_size*0.36),text,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,PlaygroundUI.mix(accent,PlaygroundUI.INK,0.4))
	# 星级槽位按本局题量算，8 题一局显示两颗，避免出现永远点不亮的空星
	var slots := clampi(floori(float(_total)/float(STAR_GOAL)),1,3)
	var lit := mini(floori(float(_correct)/float(STAR_GOAL)),slots)
	for index in slots:
		var glyph := "★" if index < lit else "☆"
		var tint := Color("#d9a52c") if index < lit else Color("#c9bda9")
		draw_string(font,Vector2(16+width+10+index*26,12+17+10),glyph,HORIZONTAL_ALIGNMENT_LEFT,-1,24,tint)


func _draw_sparks() -> void:
	for entry in _sparks:
		var spark: Dictionary = entry
		var life := maxf(0.01,float(spark["life"]))
		var alpha := clampf(1.0-float(spark["age"])/life,0.0,1.0)
		var tint: Color = spark["color"]
		tint.a = alpha
		var center: Vector2 = spark["pos"]
		_draw_star(center,float(spark["size"])*(0.55+0.45*alpha),tint,float(spark["angle"]))

func _draw_star(center: Vector2, radius: float, tint: Color, angle: float) -> void:
	var points := PackedVector2Array()
	for index in 10:
		var length := radius if index%2 == 0 else radius*0.45
		var theta := angle-PI*0.5+index*PI/5.0
		points.append(center+Vector2(cos(theta),sin(theta))*length)
	draw_colored_polygon(points,tint)

func _draw_water() -> void:
	var unit := clampf(size.y/500.0,0.7,1.5)
	for row in 2:
		var top := size.y*0.55+row*size.y*0.12
		var bar := 48.0*unit
		draw_style_box(PlaygroundUI.style(Color("#74bfdc") if row == 0 else Color("#94d6e5"),24),Rect2(24,top,size.x-48,bar))
		for index in 10:
			var point := Vector2(46+index*(size.x-80)/10.0,top+bar*0.5+sin(clock*1.6+index)*3)
			draw_arc(point,7*unit,0,PI,10,Color(1,1,1,0.35),2,true)
		var progress := float(scores[row])/maxf(1,float(totals[row])) if row < scores.size() and row < totals.size() else 0.0
		_icon("⛵",Vector2(65+(size.x-160)*progress,top+bar*0.45+sin(clock*2.2+row)*3),Vector2(60,56)*unit)
		_icon("🚩",Vector2(size.x-56,top+bar*0.38),Vector2(30,38)*unit)
	_draw_visual(Vector2(size.x*0.5,size.y*0.42),46*unit)

func _draw_letters() -> void:
	var top := size.y*0.40
	var height := clampf(size.y*0.22,64.0,140.0)
	draw_style_box(PlaygroundUI.style(Color("#fffcf5"),24,Color("#e6b0a0"),2),Rect2(size.x*0.21,top,size.x*0.58,height))
	for index in 4:
		var origin := Vector2(size.x*0.21+index*size.x*0.145,top)
		draw_line(origin,origin+Vector2(0,height),Color("#efd8ce"),1.5,true)
	_draw_visual(Vector2(size.x*0.5,top+height*0.5),clampf(height*0.62,40.0,80.0))
	if feedback and not question.is_empty():
		draw_line(Vector2(size.x*0.5,top+height),buttons[int(question.answer)].position+Vector2(buttons[0].size.x*0.5,-5),Color("#77a476"),4,true)

func _draw_patterns() -> void:
	for index in 7:
		var y := size.y*0.10+index*size.y*0.12
		draw_line(Vector2(0,y),Vector2(size.x,y),Color(0.7,0.48,0.2,0.07),2,true)
	_icon("🔍",Vector2(66,size.y*0.45),Vector2(72,72))
	_draw_visual(Vector2(size.x*0.52,size.y*0.45),clampf(size.y*0.12,44.0,72.0))
	if feedback and not question.is_empty():
		var index := int(question.answer)
		draw_arc(buttons[index].position+buttons[index].size*0.5,40,0,TAU,40,Color("#d3a122"),4,true)

func _draw_animals() -> void:
	var ground := size.y*0.70
	draw_circle(Vector2(size.x-100,size.y*0.18),40,Color("#ffe499"))
	draw_colored_polygon(PackedVector2Array([Vector2(0,ground),Vector2(size.x*0.25,ground-size.y*0.10),Vector2(size.x*0.6,ground-size.y*0.03),Vector2(size.x,ground-size.y*0.12),Vector2(size.x,size.y),Vector2(0,size.y)]),Color("#b4d28f"))
	_icon("🌳",Vector2(80,ground-size.y*0.10),Vector2(86,120))
	_icon("🌲",Vector2(size.x-70,ground-size.y*0.10),Vector2(82,112))
	_draw_visual(Vector2(size.x*0.5,size.y*0.45),clampf(size.y*0.16,60.0,110.0))

func _draw_workbook() -> void:
	var unit := clampf(size.y/500.0,0.7,1.4)
	var step := 36.0*unit
	var line := size.y*0.24
	while line < size.y*0.90:
		draw_line(Vector2(25,line),Vector2(size.x-25,line),Color("#cddae4"),1,true)
		line += step
	draw_line(Vector2(72,0),Vector2(72,size.y),Color("#e7b9b2"),2,true)
	for index in 7:
		draw_arc(Vector2(27,50+index*52*unit),9*unit,PI*0.2,PI*1.8,20,Color("#7e858d"),3,true)
	_draw_visual(Vector2(size.x*0.54,size.y*0.45),clampf(size.y*0.13,44.0,68.0))
	_icon("✏️",Vector2(size.x-52,size.y*0.45),Vector2(52,74)*unit)

func _draw_visual(center: Vector2, extent: float) -> void:
	center.y += sin(clock * 1.35) * 2.2
	if _tokens.is_empty():
		var text := str(question.get("visual",""))
		if text.is_empty():
			return
		var pixels := int(extent*0.7)
		var width := PlaygroundUI.font().get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,pixels).x
		if width > size.x*0.8:
			pixels = int(pixels*size.x*0.8/width)
			width = PlaygroundUI.font().get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,pixels).x
		draw_string(PlaygroundUI.font(),center+Vector2(-width*0.5,pixels*0.35),text,HORIZONTAL_ALIGNMENT_LEFT,-1,pixels,PlaygroundUI.INK)
		return
	var side := minf(extent,(size.x-180)/maxf(1,_tokens.size()))
	for index in _tokens.size():
		_icon(str(_tokens[index]),center+Vector2((index-(_tokens.size()-1)*0.5)*side,0),Vector2.ONE*side*0.9)

func _icon(token: String, center: Vector2, dimensions: Vector2) -> void:
	var image := ArtLibrary.texture(token)
	if image != null:
		draw_texture_rect(image,Rect2(center-dimensions*0.5,dimensions),false)
