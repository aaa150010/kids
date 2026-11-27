class_name RhythmField
extends Control

signal action_requested(action: Dictionary)

const AUDIO_RATE := 44100
const APPROACH_SECONDS := 2.25
const LANE_COUNT := 4

var engine: RhythmRules
var accent := Color("#a77c16")
var soft := Color("#f5eccb")
var paused := false

var _lane_rects: Array[Rect2] = []
var _track_rect := Rect2()
var _hit_y := 0.0
var _pointer_lanes: Dictionary = {}
var _lane_held: Dictionary = {}
var _lane_glow: Dictionary = {}
var _clock := 0.0
var _beat_player: AudioStreamPlayer
var _beat_stream: AudioStreamWAV
var _beat_bpm := 0.0
var _last_touch_msec := -1000
var _notice := ""
var _notice_until := 0.0
var _notice_color := Color.WHITE
var _music_enabled := true


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	custom_minimum_size = Vector2(720, 640)
	set_process(true)
	_beat_player = AudioStreamPlayer.new()
	_beat_player.name = "NativeBeat"
	_beat_player.bus = "Music"
	_beat_player.volume_db = -10.0
	add_child(_beat_player)
	_music_enabled = bool(SaveStore.settings().get("musicOn", true))
	if not SaveStore.changed.is_connected(_on_store_changed):
		SaveStore.changed.connect(_on_store_changed)


func _exit_tree() -> void:
	stop_beat()
	if SaveStore.changed.is_connected(_on_store_changed):
		SaveStore.changed.disconnect(_on_store_changed)


func bind(rules: RhythmRules, tint: Color, soft_color: Color) -> void:
	engine = rules
	accent = tint
	soft = soft_color
	_lane_glow.clear()
	_pointer_lanes.clear()
	_lane_held.clear()
	_beat_bpm = 0.0
	_notice = ""
	queue_redraw()


func start_beat() -> void:
	if engine == null or engine.state.is_empty() or str(engine.state.get("phase", "")) != "playing" or not _music_enabled or float(engine.state.get("countdown", 0.0)) > 0.0:
		stop_beat()
		return
	if _beat_player.playing:
		return
	var chart: Dictionary = engine.state.get("chart", {})
	var bpm := float(chart.get("bpm", 90.0))
	if _beat_stream == null or not is_equal_approx(_beat_bpm, bpm):
		_beat_bpm = bpm
		_beat_stream = _build_beat_stream(bpm, int(chart.get("beatsPerBar", 4)))
	_beat_player.stream = _beat_stream
	AudioFX.stop_music()
	var stream_length := maxf(0.1, _beat_stream.get_length())
	var offset := fmod(maxf(0.0, float(engine.state.get("playhead", 0.0))), stream_length)
	_beat_player.play(offset)


func stop_beat() -> void:
	if _beat_player != null:
		_beat_player.stop()


func set_paused(value: bool) -> void:
	paused = value
	if paused:
		stop_beat()
		_pointer_lanes.clear()
		_lane_held.clear()


func resume_beat() -> void:
	if not paused:
		start_beat()


func show_judgement(lane: int, judgement: String, message: String = "") -> void:
	if lane >= 0:
		_lane_glow[lane] = _clock + 0.18
	if not message.strip_edges().is_empty():
		_notice = message
		_notice_until = _clock + 1.15
		_notice_color = {
			"perfect": Color("#4e8a68"),
			"good": Color("#7b6b38"),
			"miss": Color("#9b5c4d"),
			"stray": Color("#77685c"),
		}.get(judgement, PlaygroundUI.INK_SOFT)
	queue_redraw()


func _process(delta: float) -> void:
	_clock += delta
	if engine != null and _notice_until > 0.0 and _clock > _notice_until:
		_notice = ""
		_notice_until = 0.0
	if paused:
		return
	if not paused and engine != null and _music_enabled and str(engine.state.get("phase", "")) == "playing" and float(engine.state.get("countdown", 0.0)) <= 0.0 and not _beat_player.playing:
		start_beat()
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if paused or engine == null or str(engine.state.get("phase", "")) != "playing":
		return
	get_viewport().set_input_as_handled()
	if event is InputEventScreenTouch:
		if event.device == InputEvent.DEVICE_ID_EMULATION:
			return
		_last_touch_msec = Time.get_ticks_msec()
		_handle_pointer(event.index, event.position, event.pressed, true)
	elif event is InputEventScreenDrag:
		_last_touch_msec = Time.get_ticks_msec()
		_handle_drag(event.index, event.position)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if Time.get_ticks_msec() - _last_touch_msec < 500:
			return
		_handle_pointer(0, event.position, event.pressed, false)
	elif event is InputEventMouseMotion and _pointer_lanes.has(0):
		_handle_drag(0, event.position)
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode in [KEY_1, KEY_KP_1]:
			_trigger_lane_key(0)
		elif event.keycode in [KEY_2, KEY_KP_2]:
			_trigger_lane_key(1)
		elif event.keycode in [KEY_3, KEY_KP_3]:
			_trigger_lane_key(2)
		elif event.keycode in [KEY_4, KEY_KP_4]:
			_trigger_lane_key(3)


func _trigger_lane_key(lane: int) -> void:
	action_requested.emit({"type": "tap", "lane": lane})


func _handle_pointer(index: int, position: Vector2, pressed: bool, touch: bool) -> void:
	var lane := _lane_at(position)
	if pressed:
		if lane < 0:
			return
		_pointer_lanes[index] = lane
		_lane_held[lane] = true
		action_requested.emit({"type": "press", "lane": lane, "touch": touch})
	else:
		if not _pointer_lanes.has(index):
			return
		var held_lane := int(_pointer_lanes[index])
		_pointer_lanes.erase(index)
		_lane_held.erase(held_lane)
		action_requested.emit({"type": "release", "lane": held_lane, "touch": touch})


func _handle_drag(index: int, position: Vector2) -> void:
	# 手指滑到另一轨时不偷偷换音，仍由最初按下的轨道负责这次长按。
	if not _pointer_lanes.has(index):
		return
	var lane := int(_pointer_lanes[index])
	if not _lane_rects.is_empty() and not _lane_rects[lane].grow(28.0).has_point(position):
		_pointer_lanes.erase(index)
		_lane_held.erase(lane)
		action_requested.emit({"type": "release", "lane": lane, "cancelled": true})


func _lane_at(position: Vector2) -> int:
	for index in _lane_rects.size():
		if _lane_rects[index].has_point(position):
			return index
	return -1


func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_WM_CLOSE_REQUEST]:
		stop_beat()
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN and not paused:
		start_beat()


func _on_store_changed() -> void:
	var enabled := bool(SaveStore.settings().get("musicOn", true))
	if enabled == _music_enabled:
		return
	_music_enabled = enabled
	if not enabled:
		stop_beat()
	elif not paused and engine != null and str(engine.state.get("phase", "")) == "playing":
		start_beat()


func _draw() -> void:
	var width := maxf(640.0, size.x)
	var height := maxf(480.0, size.y)
	draw_style_box(
		PlaygroundUI.style(PlaygroundUI.mix(accent, Color.WHITE, 0.94), 28, PlaygroundUI.mix(accent, Color.WHITE, 0.50), 2, 8, Color(0, 0, 0, 0.10)),
		Rect2(Vector2.ZERO, Vector2(width, height))
	)
	_layout_track(Vector2(width, height))
	_draw_header(width)
	_draw_track()
	_draw_notes()
	_draw_hit_pads()
	_draw_feedback(width, height)
	_draw_countdown(width, height)


func _layout_track(area: Vector2) -> void:
	var track_width := clampf(area.x * 0.54, 430.0, 690.0)
	var track_height := clampf(area.y - 168.0, 390.0, area.y - 92.0)
	_track_rect = Rect2(Vector2((area.x - track_width) * 0.5, 78.0), Vector2(track_width, track_height))
	_hit_y = _track_rect.position.y + _track_rect.size.y - 118.0
	_lane_rects.clear()
	var lane_width := _track_rect.size.x / float(LANE_COUNT)
	for index in LANE_COUNT:
		_lane_rects.append(Rect2(
			Vector2(_track_rect.position.x + lane_width * float(index), _track_rect.position.y),
			Vector2(lane_width, _track_rect.size.y)
		))


func _draw_header(width: float) -> void:
	var chart: Dictionary = engine.state.get("chart", {}) if engine != null else {}
	var title := str(chart.get("title", "节奏拍拍乐"))
	var font := PlaygroundUI.font()
	draw_string(font, Vector2(28, 46), title, HORIZONTAL_ALIGNMENT_LEFT, width - 360.0, 25, PlaygroundUI.INK)
	var bpm := int(chart.get("bpm", 90))
	draw_string(font, Vector2(28, 68), "四轨节拍 · %s BPM · %s" % [bpm, engine.current_player_name() if engine != null else "小乐手"], HORIZONTAL_ALIGNMENT_LEFT, width - 380.0, 15, PlaygroundUI.INK_SOFT)
	_draw_stat(width - 328.0, 20.0, "节拍分", str(int(engine.state.get("score", 0))) if engine != null else "0")
	_draw_stat(width - 226.0, 20.0, "连击", str(int(engine.state.get("combo", 0))) if engine != null else "0")
	var accuracy := int(round(float(engine.state.get("accuracy", 0.0)) * 100.0)) if engine != null else 0
	_draw_stat(width - 124.0, 20.0, "准确度", "%s%%" % accuracy)


func _draw_stat(x: float, y: float, caption: String, value: String) -> void:
	var font := PlaygroundUI.font()
	draw_string(font, Vector2(x, y + 15), caption, HORIZONTAL_ALIGNMENT_LEFT, 90.0, 12, PlaygroundUI.INK_SOFT)
	draw_string(font, Vector2(x, y + 43), value, HORIZONTAL_ALIGNMENT_LEFT, 96.0, 22, accent)


func _draw_track() -> void:
	draw_style_box(
		PlaygroundUI.style(PlaygroundUI.mix(soft, Color.WHITE, 0.30), 24, PlaygroundUI.mix(accent, Color.WHITE, 0.62), 2),
		_track_rect
	)
	var lane_colors := [
		PlaygroundUI.mix(accent, Color.WHITE, 0.63),
		PlaygroundUI.mix(accent, Color.WHITE, 0.73),
		PlaygroundUI.mix(accent, Color.WHITE, 0.73),
		PlaygroundUI.mix(accent, Color.WHITE, 0.63),
	]
	for index in LANE_COUNT:
		var rect := _lane_rects[index]
		var lane_fill: Color = lane_colors[index]
		if _lane_held.has(index):
			lane_fill = PlaygroundUI.mix(lane_fill, accent, 0.22)
		draw_rect(rect, lane_fill)
		if index > 0:
			draw_line(Vector2(rect.position.x, rect.position.y + 18.0), Vector2(rect.position.x, rect.end.y - 18.0), Color(accent, 0.20), 1.5, true)
		var font := PlaygroundUI.font()
		draw_string(font, Vector2(rect.position.x + rect.size.x * 0.5 - 5.0, rect.position.y + 26.0), str(index + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(accent, 0.60))
	var beat_seconds := 60.0 / maxf(45.0, float(engine.state.get("chart", {}).get("bpm", 90.0))) if engine != null else 0.66
	var bar_beats := maxi(1, int(engine.state.get("chart", {}).get("beatsPerBar", 4))) if engine != null else 4
	var playhead := float(engine.state.get("playhead", 0.0)) if engine != null else 0.0
	var first_beat := int(floor(playhead / beat_seconds)) - 2
	for beat_index in range(maxi(0, first_beat), first_beat + 16):
		var beat_time := float(beat_index) * beat_seconds
		var delta := beat_time - playhead
		if delta < -0.3 or delta > APPROACH_SECONDS:
			continue
		var y := _hit_y - delta / APPROACH_SECONDS * (_hit_y - _track_rect.position.y - 18.0)
		if y < _track_rect.position.y or y > _track_rect.end.y:
			continue
		var strong := beat_index % bar_beats == 0
		draw_line(Vector2(_track_rect.position.x + 10.0, y), Vector2(_track_rect.end.x - 10.0, y), Color(accent, 0.11 if not strong else 0.18), 1.0 if not strong else 1.6, true)
	draw_line(Vector2(_track_rect.position.x + 9.0, _hit_y), Vector2(_track_rect.end.x - 9.0, _hit_y), Color(accent, 0.60), 3.0, true)
	for index in LANE_COUNT:
		var rect := _lane_rects[index]
		var center := Vector2(rect.position.x + rect.size.x * 0.5, _hit_y)
		var glow := 1.0 if _clock < float(_lane_glow.get(index, -1.0)) else 0.0
		draw_circle(center, 23.0 + glow * 8.0, Color(accent, 0.10 + glow * 0.16))
		draw_arc(center, 17.0, 0.0, TAU, 28, Color(accent, 0.36 + glow * 0.34), 2.0 + glow * 2.0, true)


func _draw_notes() -> void:
	if engine == null or str(engine.state.get("phase", "")) != "playing":
		return
	var playhead := float(engine.state.get("playhead", 0.0))
	for note_value in engine.state.get("notes", []):
		var note: Dictionary = note_value
		var status := str(note.get("status", ""))
		if status in ["hit", "missed"]:
			continue
		var lane := clampi(int(note.get("lane", 0)), 0, LANE_COUNT - 1)
		var lane_rect := _lane_rects[lane]
		var start := engine.note_start_seconds(note)
		var hold := engine.note_hold_seconds(note)
		var start_delta := start - playhead
		var end_delta := start + hold - playhead
		if start_delta > APPROACH_SECONDS + 0.5 or end_delta < -0.4:
			continue
		var head_y := _hit_y - start_delta / APPROACH_SECONDS * (_hit_y - _track_rect.position.y - 22.0)
		var tail_y := _hit_y - end_delta / APPROACH_SECONDS * (_hit_y - _track_rect.position.y - 22.0)
		if hold > 0.0:
			var hold_top := minf(head_y, tail_y)
			var hold_bottom := maxf(head_y, tail_y)
			var body_width := minf(42.0, lane_rect.size.x * 0.34)
			draw_style_box(
				PlaygroundUI.style(Color(accent, 0.26), 14, Color(accent, 0.42), 1),
				Rect2(Vector2(lane_rect.position.x + (lane_rect.size.x - body_width) * 0.5, hold_top), Vector2(body_width, maxf(8.0, hold_bottom - hold_top)))
			)
		var card_width := minf(64.0, lane_rect.size.x * 0.54)
		var head_y_clamped := clampf(head_y, _track_rect.position.y + 9.0, _track_rect.end.y - 22.0)
		var card := Rect2(Vector2(lane_rect.position.x + (lane_rect.size.x - card_width) * 0.5, head_y_clamped - 13.0), Vector2(card_width, 26.0))
		if status == "holding":
			card = Rect2(Vector2(lane_rect.position.x + (lane_rect.size.x - card_width) * 0.5, _hit_y - 16.0), Vector2(card_width, 32.0))
		draw_style_box(
			PlaygroundUI.style(PlaygroundUI.mix(accent, Color.WHITE, 0.18 if hold > 0.0 else 0.06), 11, accent, 2, 3, Color(0, 0, 0, 0.14)),
			card
		)
		draw_circle(card.get_center(), minf(5.0, card.size.y * 0.16), Color(1, 1, 1, 0.88))


func _draw_hit_pads() -> void:
	var pad_height := 74.0
	var pad_y := minf(_track_rect.end.y - 8.0, _hit_y + 38.0)
	for index in LANE_COUNT:
		var lane_rect := _lane_rects[index]
		var pad := Rect2(Vector2(lane_rect.position.x + 12.0, pad_y), Vector2(lane_rect.size.x - 24.0, pad_height))
		var active := _lane_held.has(index)
		var fill := PlaygroundUI.mix(accent, Color.WHITE, 0.84 if not active else 0.46)
		draw_style_box(
			PlaygroundUI.style(fill, 18, PlaygroundUI.mix(accent, Color.WHITE, 0.16 if active else 0.50), 2, 4, Color(0, 0, 0, 0.10)),
			pad
		)
		draw_string(PlaygroundUI.font(), Vector2(pad.position.x + 12.0, pad.position.y + 45.0), str(index + 1), HORIZONTAL_ALIGNMENT_CENTER, pad.size.x - 24.0, 21, PlaygroundUI.INK)


func _draw_feedback(width: float, height: float) -> void:
	if engine == null:
		return
	var feedback: Dictionary = engine.state.get("feedback", {})
	if feedback.is_empty() and _notice.is_empty():
		return
	var judgement := str(feedback.get("judgement", "")) if not feedback.is_empty() else ""
	var copy: String = {
		"perfect": "刚刚好！",
		"good": "跟上拍子啦",
		"miss": "下一拍再对准",
		"stray": "听一听再拍",
	}.get(judgement, _notice)
	if not _notice.is_empty():
		copy = _notice
	if copy.is_empty():
		return
	var tint: Color = {
		"perfect": Color("#4e8a68"),
		"good": Color("#7b6b38"),
		"miss": Color("#9b5c4d"),
		"stray": Color("#77685c"),
	}.get(judgement, _notice_color)
	var font := PlaygroundUI.font()
	var text_width := font.get_string_size(copy, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
	var rect := Rect2(Vector2((width - text_width - 40.0) * 0.5, height - 54.0), Vector2(text_width + 40.0, 36.0))
	draw_style_box(PlaygroundUI.style(PlaygroundUI.mix(tint, Color.WHITE, 0.84), 18, Color(tint, 0.35), 1), rect)
	draw_string(font, rect.position + Vector2(20.0, 24.0), copy, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, tint)


func _draw_countdown(width: float, height: float) -> void:
	if engine == null or str(engine.state.get("phase", "")) != "playing":
		return
	var countdown := float(engine.state.get("countdown", 0.0))
	if countdown <= 0.0:
		return
	var center := Vector2(width * 0.5, height * 0.48)
	draw_circle(center, 82.0, Color(0.96, 0.88, 0.75, 0.92))
	draw_circle(center, 70.0, Color(accent, 0.16))
	var text := "准备"
	var size := 28
	if countdown < 2.0:
		text = "3"
		size = 46
	if countdown < 1.35:
		text = "2"
	if countdown < 0.70:
		text = "1"
	draw_string(PlaygroundUI.font(), center + Vector2(-70.0, 13.0), text, HORIZONTAL_ALIGNMENT_CENTER, 140.0, size, PlaygroundUI.INK)


func _build_beat_stream(bpm: float, beats_per_bar: int) -> AudioStreamWAV:
	var beat_seconds := 60.0 / maxf(45.0, bpm)
	var bar_seconds := beat_seconds * float(maxi(1, beats_per_bar))
	var total_seconds := bar_seconds * 4.0
	var frames := maxi(1, int(total_seconds * AUDIO_RATE))
	var bytes := PackedByteArray()
	bytes.resize(frames * 2)
	var scale := [261.63, 329.63, 392.0, 440.0, 523.25]
	for frame in frames:
		var time := float(frame) / AUDIO_RATE
		var beat_pos := time / beat_seconds
		var pulse: float = beat_pos - float(floor(beat_pos))
		var beat_in_bar := int(floor(beat_pos)) % maxi(1, beats_per_bar)
		var bar_index := int(floor(time / bar_seconds)) % 4
		var kick_env := exp(-pulse * 18.0)
		var kick := sin(TAU * (72.0 - pulse * 18.0) * time) * kick_env * 0.22
		var tick_env := exp(-pulse * 44.0)
		var tick_frequency := 1320.0 if beat_in_bar == 0 or beat_in_bar == 2 else 980.0
		var tick := sin(TAU * tick_frequency * time) * tick_env * 0.08
		var half_pulse := fmod(beat_pos * 2.0, 1.0)
		var shaker := sin(TAU * 5700.0 * time) * exp(-half_pulse * 38.0) * 0.027
		var melody_note := int((beat_in_bar + bar_index * 2) % scale.size())
		var melody_env := exp(-pulse * 2.8)
		var melody := sin(TAU * float(scale[melody_note]) * time) * melody_env * 0.105
		var sample := clampf(kick + tick + shaker + melody, -1.0, 1.0)
		var encoded := int(sample * 32767.0)
		bytes[frame * 2] = encoded & 0xff
		bytes[frame * 2 + 1] = (encoded >> 8) & 0xff
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = AUDIO_RATE
	stream.stereo = false
	stream.data = bytes
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = frames
	return stream
