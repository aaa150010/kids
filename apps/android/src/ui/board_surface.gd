class_name BoardSurface
extends Control

signal cell_pressed(position: int)
signal previewed

var game_id := "gomoku"
var state: Dictionary = {}
var legal: Array = []
var interactive := true
var face_to_face := false
var accent := Color("#d56c29")
var show_numbers := false
var focused := -1
var pressed := false
var motion := 1.0
var notice: Dictionary = {}
var _animation: Tween
var _move_numbers: Dictionary = {}

# --- 交互增强用的自绘动画状态（全部不依赖子节点，只在 _draw 里体现）---
var _clock := 0.0                 # 呼吸/脉冲动画时钟
var _shake_index := -1            # 正在左右抖动的格子/棋子
var _shake_elapsed := 0.0
var _flip_index := -1             # 正在做翻牌动画的军棋格子
var _touch_index := -1            # 当前跟踪的触点编号，-1 表示没有
var _touch_guard_msec := 0        # 触摸后短暂屏蔽模拟鼠标事件，避免一次点击触发两遍
var _long_press_index := -1       # 正在等待长按的格子
var _long_press_elapsed := 0.0
var _long_press_fired := false
var _tooltip_index := -1          # 长按气泡展示的格子
var _rules: BoardRules            # 仅用于绘制时查询河界/铁路/占位，避免逐帧新建
const SHAKE_TIME := 0.25
const LONG_PRESS_TIME := 0.45

func _ready() -> void:
	custom_minimum_size = Vector2(400,340)
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	resized.connect(queue_redraw)

func _notification(what: int) -> void:
	# 切后台/关窗时触摸可能收不到抬起事件，主动复位按压状态，避免下次点击错乱
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_CLOSE_REQUEST:
		_cancel_press()

func metrics() -> Dictionary:
	var columns := 15 if game_id == "gomoku" else 9 if game_id == "jungle" else 12
	var rows := 15 if game_id == "gomoku" else 7 if game_id == "jungle" else 5
	var padding := 24.0
	var horizontal_units := float(columns) + 0.2 if game_id != "gomoku" else 15.2
	var vertical_units := float(rows) + 0.2 if game_id != "gomoku" else 15.2
	var spacing := minf((size.x - padding) / horizontal_units, (size.y - padding) / vertical_units)
	var extent := Vector2(columns if game_id != "gomoku" else 14,rows if game_id != "gomoku" else 14)*spacing
	var origin := (size-extent)*0.5
	if game_id != "gomoku":
		origin += Vector2.ONE*spacing*0.5
	return {"spacing":spacing,"origin":origin,"columns":columns,"rows":rows}

func position_for(index: int) -> Vector2:
	var layout := metrics()
	var column := index%15 if game_id == "gomoku" else index%9 if game_id == "jungle" else int(index/5)
	var row := int(index/15) if game_id == "gomoku" else int(index/9) if game_id == "jungle" else index%5
	return layout.origin+Vector2(column,row)*float(layout.spacing)

func update_state(value: Dictionary, targets: Array = [], animate: bool = false) -> void:
	state = value.duplicate(true)
	legal = targets.duplicate()
	notice = state.get("interactionNote", {}).duplicate(true) if state.get("interactionNote", {}) is Dictionary else {}
	_move_numbers.clear()
	if game_id == "gomoku":
		# 相邻快照的差异才是这一手落点；旧实现取到的是最早的空盘。
		var history: Array = state.get("history",[])
		for step in history.size():
			var before: Array = history[step].get("before",{}).get("board",[])
			var after: Array = history[step+1].get("before",{}).get("board",[]) if step+1 < history.size() else state.get("board",[])
			if before.size() != 225 or after.size() != 225:
				continue
			for index in 225:
				if int(before[index]) < 0 and int(after[index]) >= 0:
					_move_numbers[index] = int(history[step].before.get("moveCount",step))+1
					break
	if _animation != null:
		_animation.kill()
	motion = 0.0 if animate else 1.0
	var last: Dictionary = state.get("lastMove",{})
	# 只看“本帧新增的翻牌”做翻转动画；普通走子不触发
	_flip_index = int(last.get("to",-1)) if animate and bool(last.get("flip",false)) else -1
	_shake_index = -1
	_shake_elapsed = 0.0
	if animate:
		_animation = create_tween()
		var screen := _screen()
		if screen != null:
			_animation.set_meta("screen_owner",screen.get_instance_id())
			MotionKit.adopt(screen, _animation)
		_animation.tween_property(self,"motion",1.0,0.32).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_animation.step_finished.connect(func(_index): queue_redraw())
	queue_redraw()
	# 有动画/选中态/抖动时保持逐帧重绘，其余时候让引擎休眠省电
	set_process(_needs_frames())

func _process(delta: float) -> void:
	_clock += delta
	if _shake_index >= 0:
		_shake_elapsed += delta
		if _shake_elapsed >= SHAKE_TIME:
			_shake_index = -1
			_shake_elapsed = 0.0
	if not interactive or (pressed and _blocked_by_dialog()):
		_cancel_press()
	_update_long_press(delta)
	queue_redraw()
	if not _needs_frames():
		set_process(false)

# 是否还需要逐帧重绘：动画中、抖动中、长按计时、选中呼吸
func _needs_frames() -> bool:
	if motion < 0.999:
		return true
	if _shake_index >= 0 or _long_press_index >= 0 or _tooltip_index >= 0:
		return true
	if interactive and pressed:
		return true
	if interactive and not str(state.get("selected","")).is_empty():
		return true
	return false

# 弹窗（DialogManager）接管输入时，棋盘静默
func _blocked_by_dialog() -> bool:
	var tree := get_tree()
	if tree == null:
		return false
	var hub := tree.get_first_node_in_group("main_hub")
	if hub == null:
		return false
	var controller := hub.get("ipc") as InteractionController
	return controller != null and controller.is_blocked_by_dialog()

func _screen() -> NativeGameScreen:
	var parent := get_parent()
	while parent != null:
		if parent is NativeGameScreen:
			return parent
		parent = parent.get_parent()
	return null

func _draw() -> void:
	var layout := metrics()
	var gap := float(layout.spacing)
	if gap <= 0:
		return
	var background := Color("#ecd09a") if game_id == "gomoku" else Color("#d8eac1") if game_id == "jungle" else Color("#d9dfed")
	draw_style_box(PlaygroundUI.style(background,30,Color("#a87c52") if game_id == "gomoku" else Color("#93ad7c") if game_id == "jungle" else Color("#727fac"),3,8,Color(0,0,0,0.12)),Rect2(Vector2.ZERO,size))
	if game_id == "gomoku":
		_draw_gomoku(gap)
	else:
		_draw_grid(gap)
	if game_id == "jungle":
		_draw_move_hints(gap)
	if _tooltip_index >= 0:
		_draw_tooltip(gap)
	elif not str(notice.get("message", "")).is_empty():
		var cells: Array = notice.get("cells", [])
		var anchor := position_for(int(cells[0])) if not cells.is_empty() and int(cells[0]) in range(int(layout.columns) * int(layout.rows)) else size * 0.5
		TabletopLayout.draw_note(self, anchor, str(notice.message), TabletopLayout.facing_angle(int(notice.get("side", int(state.get("turn", 0)))), face_to_face), accent, "hint")
	if focused >= 0 and pressed and interactive and _tooltip_index < 0:
		var center := position_for(focused)
		draw_arc(center,gap*0.44,0,TAU,40,Color("#e1a52a"),4,true)
		var bubble := center+Vector2(0,-gap*1.6)
		bubble.x = clampf(bubble.x,gap,size.x-gap)
		bubble.y = maxf(gap,bubble.y)
		draw_circle(bubble,gap*0.62,Color("#fffaf0"))
		draw_circle(bubble,gap*0.48,Color("#33312d") if int(state.get("turn",0)) == 0 else Color.WHITE)

func _draw_gomoku(gap: float) -> void:
	var origin: Vector2 = metrics().origin
	for index in 15:
		draw_line(origin+Vector2(0,index*gap),origin+Vector2(14*gap,index*gap),Color("#79563c"),1.4,true)
		draw_line(origin+Vector2(index*gap,0),origin+Vector2(index*gap,14*gap),Color("#79563c"),1.4,true)
	for index in [48,56,112,168,176]:
		draw_circle(position_for(index),maxf(3,gap*0.08),Color("#79563c"))
	var board: Array = state.get("board",[])
	var last_to := int(state.get("lastMove",{}).get("to",-1))
	for index in board.size():
		var center := position_for(index)
		center.x += _shake_offset(index,gap)
		if int(board[index]) < 0:
			# 点错空位（例如 puzzle 走错）时，在该交叉点画一个淡出的红叉
			if index == _shake_index:
				_draw_error_mark(center,gap)
			continue
		var radius := gap*0.43
		if index == last_to and motion < 1.0:
			# 落子回弹：0.6 起步 -> 冲过 1.0 一点 -> 落在 1.0
			radius *= 0.6+0.4*_back_out(motion)
		draw_circle(center+Vector2(2,4),radius,Color(0,0,0,0.18))
		draw_circle(center,radius,Color("#292826") if int(board[index]) == 0 else Color("#fffef8"))
		draw_circle(center-Vector2(radius*0.25,radius*0.3),radius*0.22,Color(1,1,1,0.22 if int(board[index]) == 0 else 0.85))
		if index == last_to:
			draw_arc(center,radius*0.6,0,TAU,30,Color("#e2ab34"),2.5,true)
		if show_numbers:
			var number := int(_move_numbers.get(index,0))
			if number > 0:
				_facing_text(str(number), center, gap * 0.28, Color.WHITE if int(board[index]) == 0 else Color("#37322a"), int(board[index]))
	var line: Array = state.get("winningLine",[])
	for order in line.size():
		var index := int(line[order])
		var reveal := clampf(motion*float(line.size())-float(order),0.0,1.0)
		draw_arc(position_for(int(index)),gap*(0.32+0.14*reveal),0,TAU,32,Color(0.9,0.67,0.18,reveal),4,true)
		if reveal > 0.7:
			draw_circle(position_for(int(index)),gap*0.08*(reveal-0.7)/0.3,Color(1.0,0.88,0.42,reveal))

func _draw_grid(gap: float) -> void:
	var count := 63 if game_id == "jungle" else 60
	if _rules == null:
		_rules = BoardRules.new()
	_rules.state = state
	var rules := _rules
	var breath := _breath()
	if game_id == "military":
		for index in count:
			for neighbor in rules.road_neighbours(index):
				if int(neighbor) > index:
					var origin := position_for(index)
					var destination := position_for(int(neighbor))
					var rail := rules.rail_link(index,int(neighbor))
					draw_line(origin,destination,Color("#707ca3") if rail else Color("#aab1c5"),6 if rail else 2,true)
	for index in count:
		var center := position_for(index)
		var rectangle := Rect2(center-Vector2.ONE*gap*0.43,Vector2.ONE*gap*0.86)
		var background := Color("#edf4d8") if game_id == "jungle" else Color("#edf0f8")
		var border := Color("#bdd09b") if game_id == "jungle" else Color("#a4b0d1")
		if game_id == "jungle":
			if index in BoardRules.WATER:
				background = Color("#85c9df")
			if index in BoardRules.TRAPS[0] or index in BoardRules.TRAPS[1]:
				background = Color("#eccca3")
			if index in BoardRules.DENS:
				background = Color("#ffd77b")
		else:
			if index in BoardRules.CAMPS:
				background = Color("#fff8d5")
			if index in BoardRules.HEADQUARTERS:
				background = Color("#c8d3ef")
		draw_style_box(PlaygroundUI.style(background,13,border,1),rectangle)
		if game_id == "jungle" and index in BoardRules.WATER:
			for wave in 3:
				draw_line(center+Vector2(-gap*0.25,(wave-1)*gap*0.16),center+Vector2(gap*0.25,(wave-1)*gap*0.16),Color(1,1,1,0.35),2,true)
		var marker := ""
		if game_id == "jungle":
			marker = "兽穴" if index in BoardRules.DENS else "陷阱" if index in BoardRules.TRAPS[0] or index in BoardRules.TRAPS[1] else ""
		else:
			marker = "行营" if index in BoardRules.CAMPS else "大本营" if index in BoardRules.HEADQUARTERS else ""
		if not marker.is_empty():
			var marker_side := 0 if index % 9 < 4 else 1
			_facing_text(marker, center, gap * 0.2, Color("#827759"), marker_side)
		if game_id == "gomoku" and index in legal:
			# 合法落点：半透明主色圆片 + 中心实心点，轻微呼吸缩放
			draw_circle(center,gap*(0.30+0.035*breath),Color(0.88,0.67,0.20,0.35))
			draw_circle(center,gap*(0.10+0.012*breath),Color("#e1ac35"))
			if not rules.piece_at(index).is_empty():
				# 可吃目标：红圈同步呼吸
				draw_arc(center,gap*(0.42+0.03*breath),0,TAU,32,Color(0.84,0.36,0.26,0.65+0.35*breath),4,true)
		if index == _shake_index and rules.piece_at(index).is_empty():
			# 空格子出错时画一个淡出红叉（棋子出错则由棋子自身抖动）
			_draw_error_mark(center,gap)
	for piece in state.get("pieces",[]):
		var index := int(piece.position)
		var center := position_for(index)
		var last: Dictionary = state.get("lastMove",{})
		if int(last.get("to",-1)) == index and last.has("from"):
			var trail_start := position_for(int(last.from))
			var trail_end := position_for(int(last.to))
			draw_line(trail_start,trail_end,Color(0.95,0.7,0.2,(1.0-motion)*0.55),maxf(2.0,gap*0.06),true)
			center = trail_start.lerp(center,motion)
		center.x += _shake_offset(index,gap)
		var selected := str(state.get("selected","")) == str(piece.id)
		# 选中态：底部软阴影 + 呼吸光晕 + 棋子轻微上浮（只改绘制位置，不动布局）
		var lift := gap*0.05 if selected else 0.0
		if selected:
			draw_circle(center+Vector2(0,gap*0.06),gap*0.42,Color(0,0,0,0.13))
			draw_circle(center,gap*(0.56+0.03*breath),Color(0.95,0.73,0.25,0.10+0.10*breath))
			draw_arc(center,gap*(0.49+0.03*breath),0,TAU,48,Color(0.90,0.66,0.16,0.45+0.40*breath),3.0+2.0*breath,true)
		var draw_center := center-Vector2(0,lift)
		var tint := Color("#d96947") if int(piece.side) == 0 else Color("#4e81b2")
		# 军棋翻牌：前 0.5 显示背面并横向压缩，后 0.5 展开正面
		var flip_width := 1.0
		var show_back := not bool(piece.get("revealed",true))
		if index == _flip_index and motion < 1.0:
			var phase := clampf(motion,0.0,1.0)
			flip_width = maxf(0.05,absf(phase*2.0-1.0))
			show_back = phase < 0.5
		if show_back:
			var hidden := Rect2(draw_center-Vector2(gap*0.38*flip_width,gap*0.4),Vector2(gap*0.76*flip_width,gap*0.8))
			if index == focused and pressed and interactive:
				# 按住盖牌时放大 + 白圈，提示这张牌可以翻开
				hidden = hidden.grow(gap*0.05)
				draw_arc(draw_center,gap*0.52,0,TAU,32,Color(1,1,1,0.7),2.5,true)
			draw_style_box(PlaygroundUI.style(Color("#6974b2"),12,Color("#404d89"),3,3,Color(0,0,0,0.14)),hidden)
			if flip_width > 0.45:
				_text("?",draw_center,gap*0.4*flip_width,Color("#fff6d6"))
			continue
		if game_id == "jungle":
			var piece_angle := TabletopLayout.facing_angle(int(piece.side), face_to_face)
			var shadow_center := draw_center + Vector2(0, gap * 0.37)
			draw_circle(shadow_center, gap * 0.32, Color(0, 0, 0, 0.16))
			draw_circle(draw_center, gap * 0.43, Color(tint, 0.16))
			draw_arc(draw_center, gap * 0.43, 0, TAU, 40, tint, 3.5, true)
			draw_set_transform(draw_center, piece_angle, Vector2.ONE)
			var texture := ArtLibrary.jungle_piece(str(piece.kind))
			if texture != null:
				draw_texture_rect(texture, Rect2(Vector2(-gap * 0.39, -gap * 0.39), Vector2(gap * 0.78, gap * 0.78)), false)
			else:
				_draw_jungle_animal(str(piece.kind), gap * 0.34, tint)
			var badge_center := Vector2(gap * 0.30, gap * 0.28)
			draw_circle(badge_center, gap * 0.15, tint)
			_text(str(BoardRules.ANIMALS[piece.kind]), badge_center, gap * 0.13, Color.WHITE)
			_text(str(BoardRules.NAMES[piece.kind]), Vector2(0, gap * 0.40), gap * 0.16, tint)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		else:
			var rect := Rect2(draw_center-Vector2(gap*0.38*flip_width,gap*0.4),Vector2(gap*0.76*flip_width,gap*0.8))
			draw_style_box(PlaygroundUI.style(Color("#fff9ec"),12,tint,3,4,Color(0,0,0,0.15)),rect)
			if flip_width > 0.6:
				_text(str(BoardRules.NAMES[piece.kind]),draw_center,gap*0.25,tint)
		if selected:
			draw_arc(draw_center,gap*0.47,0,TAU,40,Color("#e6ae2e"),4,true)
		if game_id == "jungle" and index in BoardRules.TRAPS[1-int(piece.side)]:
			var marker_angle := TabletopLayout.facing_angle(int(piece.side), face_to_face)
			draw_set_transform(draw_center, marker_angle, Vector2.ONE)
			draw_colored_polygon(PackedVector2Array([
				Vector2(gap * 0.18, gap * 0.18),
				Vector2(gap * 0.42, gap * 0.18),
				Vector2(gap * 0.30, gap * 0.36),
			]), Color("#b43b2b"))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var last_capture: Dictionary = state.get("lastMove",{}).get("captured",{})
	if game_id != "gomoku" and not last_capture.is_empty() and motion < 1.0:
		var last_to := int(state.get("lastMove",{}).get("to",-1))
		if last_to >= 0:
			var center := position_for(last_to)
			var alpha := 1.0-motion
			if game_id == "jungle":
				var texture := ArtLibrary.jungle_piece(str(last_capture.get("kind","")))
				if texture != null:
					var capture_angle := TabletopLayout.facing_angle(int(last_capture.get("side", 0)), face_to_face)
					draw_set_transform(center, capture_angle, Vector2.ONE)
					draw_texture_rect(texture, Rect2(Vector2(-gap * 0.30, -gap * 0.34), Vector2(gap * 0.60, gap * 0.60)), false, Color(1, 1, 1, alpha * 0.75))
					draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
				else:
					_text(str(BoardRules.NAMES.get(str(last_capture.get("kind","")),"棋子")),center,gap*0.2,Color(0.55,0.28,0.24,alpha))
			else:
				_text(str(BoardRules.NAMES.get(str(last_capture.get("kind","")),"棋子")),center,gap*0.22,Color(0.55,0.28,0.24,alpha))
	if rules_safe_participants().size() > 0:
		TabletopLayout.draw_turn_marks(
			self,
			rules_safe_participants(),
			int(state.get("turn", 0)),
			face_to_face,
			[Color("#d96947"), Color("#4e81b2")],
			str(state.get("phase", "")) == "finished"
		)


func rules_safe_participants() -> Array:
	var participants: Variant = state.get("players", [])
	if participants is Array:
		return (participants as Array).duplicate()
	return []


func _draw_jungle_animal(kind: String, radius: float, tint: Color) -> void:
	var fur := Color("#f0ba67") if kind in ["lion","leopard"] else Color("#e8d3b0")
	var dark := tint.darkened(0.35)
	var center := Vector2(0, -radius * 0.1)
	if kind == "elephant":
		draw_circle(center + Vector2(-radius * 0.45, -radius * 0.1), radius * 0.55, Color("#a7b4c8"))
		draw_circle(center + Vector2(radius * 0.45, -radius * 0.1), radius * 0.55, Color("#a7b4c8"))
		draw_circle(center, radius * 0.62, Color("#8796ad"))
		draw_line(center + Vector2(0, radius * 0.35), center + Vector2(radius * 0.08, radius * 1.15), Color("#8796ad"), radius * 0.22, true)
	elif kind == "lion":
		for index in 14:
			var angle := float(index) * TAU / 14.0
			draw_line(center + Vector2(cos(angle), sin(angle)) * radius * 0.58, center + Vector2(cos(angle), sin(angle)) * radius * 0.95, dark, radius * 0.18, true)
		draw_circle(center, radius * 0.62, fur)
	elif kind == "tiger":
		draw_circle(center, radius * 0.64, Color("#e69b45"))
		for x in [-0.36, -0.08, 0.20]:
			draw_line(center + Vector2(radius * x, -radius * 0.58), center + Vector2(radius * (x + 0.10), -radius * 0.22), dark, radius * 0.10, true)
	elif kind == "leopard":
		draw_circle(center, radius * 0.62, Color("#e8ad55"))
		for index in 7:
			var angle := float(index) * TAU / 7.0
			draw_circle(center + Vector2(cos(angle), sin(angle)) * radius * 0.38, radius * 0.07, dark)
	else:
		var ear_height := radius * (0.88 if kind in ["cat","rat","wolf"] else 0.58)
		draw_colored_polygon(PackedVector2Array([
			center + Vector2(-radius * 0.48, -radius * 0.28),
			center + Vector2(-radius * 0.70, -radius * 0.28 - ear_height),
			center + Vector2(-radius * 0.12, -radius * 0.60),
		]), fur)
		draw_colored_polygon(PackedVector2Array([
			center + Vector2(radius * 0.48, -radius * 0.28),
			center + Vector2(radius * 0.70, -radius * 0.28 - ear_height),
			center + Vector2(radius * 0.12, -radius * 0.60),
		]), fur)
		draw_circle(center, radius * 0.62, fur)
		if kind in ["rat","cat"]:
			draw_line(center + Vector2(-radius * 0.2, radius * 0.2), center + Vector2(-radius * 0.95, radius * 0.02), dark, radius * 0.05, true)
			draw_line(center + Vector2(radius * 0.2, radius * 0.2), center + Vector2(radius * 0.95, radius * 0.02), dark, radius * 0.05, true)
	draw_circle(center + Vector2(-radius * 0.24, -radius * 0.06), radius * 0.08, Color("#342c27"))
	draw_circle(center + Vector2(radius * 0.24, -radius * 0.06), radius * 0.08, Color("#342c27"))
	draw_circle(center + Vector2(0, radius * 0.22), radius * 0.11, Color("#5d4135"))

func _text(value: String, center: Vector2, font_size: float, tint: Color) -> void:
	var pixels := maxi(12,int(font_size))
	var font := PlaygroundUI.font()
	var width := font.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,pixels).x
	draw_string(font,center+Vector2(-width*0.5,pixels*0.35),value,HORIZONTAL_ALIGNMENT_LEFT,-1,pixels,tint)

func _facing_text(value: String, center: Vector2, font_size: float, tint: Color, side: int) -> void:
	draw_set_transform(center, TabletopLayout.facing_angle(side, face_to_face), Vector2.ONE)
	_text(value, Vector2.ZERO, font_size, tint)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _gui_input(event: InputEvent) -> void:
	if _blocked_by_dialog():
		_cancel_press()
		return
	if not interactive:
		if pressed:
			_cancel_press()
		return
	if event is InputEventScreenTouch:
		# 显式处理触摸；触摸后短时间屏蔽模拟出来的鼠标事件，避免一次点击触发两遍
		_touch_guard_msec = Time.get_ticks_msec()+140
		if event.pressed:
			if _touch_index >= 0 and _touch_index != event.index:
				return
			_touch_index = event.index
			if not pressed:
				_begin(event.position)
		else:
			if _touch_index < 0 or event.index != _touch_index:
				return
			_touch_index = -1
			if event.canceled:
				_cancel_press()
			else:
				_finish(event.position)
		accept_event()
	elif event is InputEventScreenDrag:
		_touch_guard_msec = Time.get_ticks_msec()+140
		if event.index == _touch_index:
			_drag(event.position)
		accept_event()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		# 桌面调试路径：没有触摸时仍然可用；触摸模拟出的鼠标事件直接吞掉
		if Time.get_ticks_msec() < _touch_guard_msec:
			accept_event()
			return
		if event.pressed:
			_begin(event.position)
		else:
			_finish(event.position)
		accept_event()
	elif event is InputEventMouseMotion and pressed:
		_drag(event.position)

# 供外部（board_game 的非法走法）调用：让某枚棋子左右抖一下
func shake(index: int) -> void:
	if index < 0:
		return
	_shake_index = index
	_shake_elapsed = 0.0
	set_process(true)
	queue_redraw()

func _begin(point: Vector2) -> void:
	if motion < 0.999:
		return # 走子/翻牌动画还没结束，先不接受新输入，防止连点
	pressed = true
	focused = _index_at(point)
	_tooltip_index = -1
	_long_press_elapsed = 0.0
	_long_press_fired = false
	_long_press_index = -1
	if game_id == "jungle" and focused >= 0 and not _piece_at(focused).is_empty():
		_long_press_index = focused
	previewed.emit()
	FeedbackKit.haptic(5)
	set_process(true)
	queue_redraw()

func _finish(point: Vector2) -> void:
	if not pressed:
		return
	pressed = false
	var target := _index_at(point)
	var fired := _long_press_fired
	_long_press_index = -1
	_tooltip_index = -1
	_long_press_fired = false
	if target >= 0 and not fired and motion >= 0.999:
		cell_pressed.emit(target)
	set_process(_needs_frames())
	queue_redraw()

func _drag(point: Vector2) -> void:
	var next := _index_at(point)
	if next != focused:
		# 手指移出原格：取消长按等待与气泡（长按已触发过则继续抑制松手点击）
		_long_press_index = -1
		_tooltip_index = -1
	focused = next
	queue_redraw()

func _cancel_press() -> void:
	if not pressed and _touch_index < 0 and _tooltip_index < 0 and _long_press_index < 0:
		return
	pressed = false
	_touch_index = -1
	_long_press_index = -1
	_tooltip_index = -1
	_long_press_fired = false
	focused = -1
	queue_redraw()

func _update_long_press(delta: float) -> void:
	if _long_press_index < 0:
		return
	if not pressed:
		_long_press_index = -1
		return
	if _tooltip_index >= 0:
		return
	_long_press_elapsed += delta
	if _long_press_elapsed >= LONG_PRESS_TIME:
		_tooltip_index = _long_press_index
		_long_press_fired = true
		FeedbackKit.haptic(10)

func _index_at(point: Vector2) -> int:
	var layout := metrics()
	var offset := (point-Vector2(layout.origin))/float(layout.spacing)
	var col := roundi(offset.x)
	var row := roundi(offset.y)
	if col < 0 or col >= int(layout.columns) or row < 0 or row >= int(layout.rows):
		return -1
	# 五子棋落点更密，放宽命中半径并保底 22 物理像素；斗兽棋/军棋保持格判定
	var limit := float(layout.spacing)*0.7
	if game_id == "gomoku":
		limit = maxf(float(layout.spacing)*0.85,22.0)
	var visual_point := Vector2(layout.origin) + Vector2(col, row) * float(layout.spacing)
	if point.distance_to(visual_point) > limit:
		return -1
	return row*15+col if game_id == "gomoku" else row*9+col if game_id == "jungle" else col*5+row

func is_blank_at(point: Vector2) -> bool:
	return _index_at(point) < 0

# --- 自绘动画辅助 ---

func _breath() -> float:
	return 0.5+0.5*sin(_clock*3.2)

func _back_out(t: float) -> float:
	var u := clampf(t,0.0,1.0)-1.0
	return 1.0+2.70158*u*u*u+1.70158*u*u

func _shake_offset(index: int, gap: float) -> float:
	if index != _shake_index or _shake_elapsed >= SHAKE_TIME:
		return 0.0
	var t := clampf(_shake_elapsed/SHAKE_TIME,0.0,1.0)
	return sin(t*TAU*3.1)*gap*0.12*(1.0-t)

func _draw_error_mark(center: Vector2, gap: float) -> void:
	var alpha := 1.0-clampf(_shake_elapsed/SHAKE_TIME,0.0,1.0)
	var arm := gap*0.2
	draw_line(center-Vector2(arm,arm),center+Vector2(arm,arm),Color(0.86,0.31,0.24,alpha),3,true)
	draw_line(center-Vector2(arm,-arm),center+Vector2(arm,-arm),Color(0.86,0.31,0.24,alpha),3,true)


func _draw_move_hints(gap: float) -> void:
	if legal.is_empty():
		return
	var selected_id := str(state.get("selected", ""))
	if selected_id.is_empty():
		return
	var selected_piece: Dictionary = {}
	for piece in state.get("pieces", []):
		if str(piece.get("id", "")) == selected_id:
			selected_piece = piece
			break
	if selected_piece.is_empty():
		return
	var start := position_for(int(selected_piece.position))
	var kind := str(selected_piece.get("kind", ""))
	var pulse := _breath()
	var route := Color("#d56c29")
	route.a = 0.32
	var selected_row := int(int(selected_piece.position) / 9)
	for value in legal:
		var target := int(value)
		var finish := position_for(target)
		if kind in ["lion", "tiger"] and absi(int(target / 9) - selected_row) > 1:
			_draw_dashed(start, finish, route, maxf(2.0, gap * 0.045), gap * 0.20)
		else:
			draw_line(start, finish, route, maxf(2.0, gap * 0.045), true)
		var captured := not _piece_at(target).is_empty()
		if captured:
			var radius := gap * (0.51 + 0.025 * pulse)
			draw_circle(finish, radius, Color(0.88, 0.28, 0.22, 0.10))
			draw_arc(finish, radius, 0, TAU, 38, Color("#e04b3f"), maxf(3.0, gap * 0.045), true)
			draw_circle(finish + Vector2(0, -radius), gap * 0.07, Color("#e04b3f"))
		else:
			draw_circle(finish, gap * (0.24 + 0.025 * pulse), Color(0.88, 0.28, 0.22, 0.16))
			draw_circle(finish, gap * (0.115 + 0.01 * pulse), Color("#e04b3f"))
			draw_circle(finish, gap * 0.04, Color("#fff7df"))


func _draw_dashed(start: Vector2, finish: Vector2, tint: Color, width: float, dash: float) -> void:
	var delta := finish - start
	var length := delta.length()
	if length < 1.0:
		return
	var direction := delta / length
	var cursor := 0.0
	while cursor < length:
		var end := minf(cursor + dash * 0.62, length)
		draw_line(start + direction * cursor, start + direction * end, tint, width, true)
		cursor += dash

func _piece_at(index: int) -> Dictionary:
	for piece in state.get("pieces",[]):
		if int(piece.get("position",-1)) == index:
			return piece
	return {}

# 斗兽棋长按气泡：名称 + 等级 + 一句“能吃谁”的关系提示
func _draw_tooltip(gap: float) -> void:
	if game_id != "jungle":
		return
	var piece := _piece_at(_tooltip_index)
	if piece.is_empty():
		return
	var kind := str(piece.get("kind",""))
	var level := int(BoardRules.ANIMALS.get(kind,0))
	var title := "%s · %s 级" % [str(BoardRules.NAMES.get(kind,kind)),str(level)]
	var caption := _jungle_caption(kind)
	var width := maxf(gap*4.2,180.0)
	var height := maxf(gap*1.3,46.0)
	var center := position_for(_tooltip_index)
	var angle := TabletopLayout.facing_angle(int(state.get("turn", 0)), face_to_face)
	var box_center := center + Vector2(0, -gap * 1.55).rotated(angle)
	var visual_extent := Vector2(height, width) if face_to_face else Vector2(width, height)
	box_center.x = clampf(box_center.x, visual_extent.x * 0.5 + 6.0, size.x - visual_extent.x * 0.5 - 6.0)
	box_center.y = clampf(box_center.y, visual_extent.y * 0.5 + 6.0, size.y - visual_extent.y * 0.5 - 6.0)
	draw_set_transform(box_center, angle, Vector2.ONE)
	var rect := Rect2(Vector2(-width * 0.5, -height * 0.5), Vector2(width, height))
	draw_style_box(PlaygroundUI.style(Color("#fffdf4"),16,Color("#b98a3e"),2,6,Color(0,0,0,0.2)),rect)
	_text(title, Vector2(0, -height * 0.16), gap * 0.22, Color("#4a3a22"))
	_text(caption, Vector2(0, height * 0.2), gap * 0.18, Color("#7a6644"))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _jungle_caption(kind: String) -> String:
	if kind == "rat":
		return "能下水，还能吃大象"
	var animals := ["elephant","lion","tiger","leopard","wolf","dog","cat","rat"]
	var rank := int(BoardRules.ANIMALS.get(kind,0))
	var prey: Array = []
	for other in animals:
		if int(BoardRules.ANIMALS[other]) < rank:
			prey.append(str(BoardRules.NAMES[other]))
	if prey.is_empty():
		return "个子最小，要靠陷阱取胜"
	var text := "能吃 "+"、".join(PackedStringArray(prey.slice(0,3)))
	if kind in ["lion","tiger"]:
		text += "，能跳河"
	return text
