extends Node

signal changed

const HIGH_REFRESH := 120
const STANDARD_REFRESH := 60

var display_refresh := STANDARD_REFRESH
var target_fps := HIGH_REFRESH
var effects_scale := 1.0
var quality_level := 2
var _warmup := 5.0
var _sample_time := 0.0
var _sample_frames := 0
var _slow_windows := 0
var _stable_windows := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	display_refresh = _detect_refresh()
	target_fps = display_refresh
	Engine.max_fps = target_fps
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)


func _detect_refresh() -> int:
	var refresh := 0.0
	if DisplayServer.has_method("screen_get_refresh_rate"):
		refresh = float(DisplayServer.call("screen_get_refresh_rate", DisplayServer.window_get_current_screen()))
	if refresh <= 1.0:
		refresh = STANDARD_REFRESH
	return clampi(roundi(refresh), STANDARD_REFRESH, 144)


func _process(delta: float) -> void:
	if _warmup > 0.0:
		_warmup -= delta
		return
	_sample_time += delta
	_sample_frames += 1
	if _sample_time < 2.0:
		return
	var fps := float(_sample_frames) / _sample_time
	_sample_time = 0.0
	_sample_frames = 0
	var target := float(target_fps)
	if fps < target * 0.72:
		_slow_windows += 1
		_stable_windows = 0
	else:
		_slow_windows = 0
		if fps > target * 0.95:
			_stable_windows += 1
	if _slow_windows >= 3:
		_degrade_effects()
	elif _stable_windows >= 6:
		_restore()


func _degrade_effects() -> void:
	if effects_scale <= 0.56:
		return
	effects_scale = maxf(0.5, effects_scale - 0.22)
	quality_level = 1
	emit_signal("changed")

func _restore() -> void:
	_stable_windows = 0
	if effects_scale < 0.999:
		effects_scale = minf(1.0, effects_scale + 0.22)
		quality_level = 2 if effects_scale >= 0.999 else 1
		emit_signal("changed")
