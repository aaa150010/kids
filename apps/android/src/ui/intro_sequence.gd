class_name IntroSequence
extends Control

signal finished

var _done := false
var _emitted := false
var _pulse := 0.0
var _studio_group: VBoxContainer
var _title_group: VBoxContainer
var _skip_hint: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	_build()
	resized.connect(queue_redraw)
	_play()


func _build() -> void:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var stack := VBoxContainer.new()
	stack.alignment = BoxContainer.ALIGNMENT_CENTER
	stack.add_theme_constant_override("separation", 14)
	center.add_child(stack)

	_studio_group = VBoxContainer.new()
	_studio_group.alignment = BoxContainer.ALIGNMENT_CENTER
	_studio_group.add_theme_constant_override("separation", 10)
	_studio_group.modulate.a = 0.0
	var studio_mark := PlaygroundUI.label("LYNOTE", 64, Color("#f4c75c"), 700)
	studio_mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_studio_group.add_child(studio_mark)
	var studio_sub := PlaygroundUI.label("童 心 制 作", 17, Color("#dcebdc"), 500)
	studio_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_studio_group.add_child(studio_sub)
	var line := ColorRect.new()
	line.color = Color("#f4c75c")
	line.custom_minimum_size = Vector2(190, 2)
	line.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_studio_group.add_child(line)
	stack.add_child(_studio_group)

	_title_group = VBoxContainer.new()
	_title_group.alignment = BoxContainer.ALIGNMENT_CENTER
	_title_group.add_theme_constant_override("separation", 8)
	_title_group.modulate.a = 0.0
	_title_group.hide()
	var mark := TextureRect.new()
	mark.texture = load("res://assets/branding/app-icon-512.png")
	mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mark.custom_minimum_size = Vector2(92, 92)
	mark.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_group.add_child(mark)
	var title := PlaygroundUI.label("童心游乐场", 70, Color("#fff7e5"), 700)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_group.add_child(title)
	var subtitle := PlaygroundUI.label("一家人一起玩的本地益智游戏", 23, Color("#dcebdc"), 500)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_group.add_child(subtitle)
	var tagline := PlaygroundUI.label("无广告 · 实时保存 · 一家人一起玩", 16, Color("#a9c9b9"), 500)
	tagline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_group.add_child(tagline)
	stack.add_child(_title_group)

	_skip_hint = PlaygroundUI.label("轻触屏幕跳过", 15, Color(0.86, 0.93, 0.86, 0.62), 500)
	_skip_hint.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_skip_hint.position = Vector2(-156, -52)
	add_child(_skip_hint)


func _play() -> void:
	AudioFX.play("studio")
	var entrance := create_tween().set_parallel(true)
	entrance.tween_property(_studio_group, "modulate:a", 1.0, 0.4)
	await entrance.finished
	await _wait(0.55)
	if _done:
		return
	var exit := create_tween()
	exit.tween_property(_studio_group, "modulate:a", 0.0, 0.24)
	await exit.finished
	if _done:
		return
	_studio_group.hide()
	_title_group.show()
	AudioFX.play("title")
	var title_entrance := create_tween().set_parallel(true)
	title_entrance.tween_property(_title_group, "modulate:a", 1.0, 0.48)
	await title_entrance.finished
	await _wait(1.25)
	if _done:
		return
	await _finish()


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _finish() -> void:
	if _emitted:
		return
	_done = true
	set_process(false)
	var fade := create_tween()
	fade.tween_property(self, "modulate:a", 0.0, 0.32)
	await fade.finished
	if _emitted:
		return
	_emitted = true
	finished.emit()


func _skip() -> void:
	if _done:
		return
	AudioFX.play("tap")
	_finish()


func _process(delta: float) -> void:
	_pulse += delta
	queue_redraw()


func _draw() -> void:
	var dimensions := size
	if dimensions.x <= 0.0 or dimensions.y <= 0.0:
		return
	for index in 28:
		var amount := float(index) / 27.0
		var tint := Color("#091512").lerp(Color("#1c3a2e"), amount)
		draw_rect(Rect2(0.0, dimensions.y * amount, dimensions.x, dimensions.y / 27.0 + 1.0), tint)
	var center := dimensions * 0.5
	var glow := minf(dimensions.x, dimensions.y) * 0.27
	for index in 3:
		draw_circle(center, glow + index * 22.0 + sin(_pulse * 1.7) * 3.0, Color(0.96, 0.78, 0.36, 0.025))
	for index in 4:
		draw_arc(center, glow + index * 30.0, -2.4, 2.4, 64, Color(0.95, 0.75, 0.32, 0.1), 2.0, true)
	for point in [Vector2(0.18, 0.24), Vector2(0.83, 0.18), Vector2(0.76, 0.78), Vector2(0.12, 0.74), Vector2(0.9, 0.48)]:
		draw_circle(Vector2(dimensions.x * point.x, dimensions.y * point.y), 3.0 + sin(_pulse * 2.0 + point.x * 9.0) * 1.2, Color(1.0, 0.92, 0.66, 0.36))
	draw_line(Vector2(dimensions.x * 0.08, dimensions.y * 0.07), Vector2(dimensions.x * 0.27, dimensions.y * 0.07), Color(0.96, 0.78, 0.36, 0.28), 1.0, true)
	draw_line(Vector2(dimensions.x * 0.73, dimensions.y * 0.93), Vector2(dimensions.x * 0.92, dimensions.y * 0.93), Color(0.96, 0.78, 0.36, 0.28), 1.0, true)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_skip()
		accept_event()
	elif event is InputEventScreenTouch and event.pressed:
		_skip()
		accept_event()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_skip()
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenTouch and event.pressed:
		_skip()
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_ENTER, KEY_SPACE, KEY_ESCAPE]:
		_skip()
		get_viewport().set_input_as_handled()
