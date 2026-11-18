extends Node

const RATE := 44100

var _players: Array[AudioStreamPlayer] = []
var _music_players: Array[AudioStreamPlayer] = []
var _active_music := 0
var _theme := ""
var _music_cache: Dictionary = {}
var _sfx_cache: Dictionary = {}
var _last_played: Dictionary = {}
var _music_tween: Tween
var _next_voice := 0
var _duck_reasons: Dictionary = {}
const MUSIC_DB := -18.0
const SILENT_DB := -48.0
const SFX_COOLDOWN := {
	"tap": 0.035,
	"select": 0.045,
	"shoot": 0.055,
	"hit": 0.045,
	"food": 0.12,
	"sun": 0.08,
	"flip": 0.04,
}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_configure_buses()
	for index in 12:
		var player := AudioStreamPlayer.new()
		player.bus = "SFX"
		player.volume_db = -7.0
		add_child(player)
		_players.append(player)
	for index in 2:
		var music := AudioStreamPlayer.new()
		music.bus = "Music"
		music.volume_db = SILENT_DB
		add_child(music)
		_music_players.append(music)
	_prewarm_sfx()
	_apply_volume_settings()
	SaveStore.changed.connect(_apply_volume_settings)
	get_tree().node_added.connect(_watch_dialog_manager)


func _watch_dialog_manager(node: Node) -> void:
	if node is DialogManager:
		node.dialog_opened.connect(func(layer: Control):
			var reason := StringName("dialog:%s" % layer.get_instance_id())
			set_music_duck(true, reason)
			layer.tree_exiting.connect(func(): set_music_duck(false, reason), CONNECT_ONE_SHOT)
		)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		set_music_duck(true, &"focus")
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		set_music_duck(false, &"focus")
	elif what == NOTIFICATION_APPLICATION_PAUSED:
		set_music_duck(true, &"background")
	elif what == NOTIFICATION_APPLICATION_RESUMED:
		set_music_duck(false, &"background")


func set_sfx_volume(value: float) -> void:
	_save_volume("sfxVolume", value)


func set_music_volume(value: float) -> void:
	_save_volume("musicVolume", value)


func set_speech_volume(value: float) -> void:
	_save_volume("speechVolume", value)


func _save_volume(key: String, value: float) -> void:
	if is_finite(value):
		SaveStore.set_setting(key, clampf(value, 0.0, 1.0))


func _apply_volume_settings() -> void:
	var settings := SaveStore.settings()
	for entry in [["SFX", "sfxVolume", "soundOn"], ["Music", "musicVolume", "musicOn"]]:
		var bus := AudioServer.get_bus_index(entry[0])
		if bus < 0:
			continue
		var volume := clampf(float(settings.get(entry[1], 1.0)), 0.0, 1.0)
		AudioServer.set_bus_mute(bus, volume <= 0.0 or not bool(settings.get(entry[2], true)))
		var duck_db := 5.0 if entry[0] == "Music" and not _duck_reasons.is_empty() else 0.0
		AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(volume, 0.0001)) - duck_db)
	if not bool(settings.get("soundOn", true)):
		for player in _players:
			player.stop()


func _configure_buses() -> void:
	for bus_name in ["SFX", "Music"]:
		if AudioServer.get_bus_index(bus_name) >= 0:
			continue
		AudioServer.add_bus()
		var index := AudioServer.bus_count - 1
		AudioServer.set_bus_name(index, bus_name)
		AudioServer.set_bus_send(index, "Master")
	var master := AudioServer.get_bus_index("Master")
	if master >= 0 and AudioServer.get_bus_effect_count(master) == 0:
		var compressor := AudioEffectCompressor.new()
		compressor.threshold = -6.0
		compressor.ratio = 3.0
		compressor.attack_us = 1500.0
		compressor.release_ms = 120.0
		AudioServer.add_bus_effect(master, compressor)


func _prewarm_sfx() -> void:
	for name in ["correct","wrong","turn","tap","select","back","pause","win","flip","pair","plant","sun","shoot","hit","food","mower","flag","boss","studio","title","whoosh","coin"]:
		_sfx_stream(name)


func _sfx_stream(name: String) -> AudioStreamWAV:
	if _sfx_cache.has(name):
		return _sfx_cache[name]
	var recipe := _recipe(name)
	var stream := _build_stream(
		recipe.get("notes", []),
		float(recipe.get("noteLength", 0.08)),
		false,
		recipe.get("durations", [])
	)
	_sfx_cache[name] = stream
	return stream


func play(name: String) -> void:
	if not bool(SaveStore.settings().get("soundOn", true)):
		return
	var now := Time.get_ticks_msec() / 1000.0
	var cooldown := float(SFX_COOLDOWN.get(name, 0.0))
	if cooldown > 0.0 and now - float(_last_played.get(name, -999.0)) < cooldown:
		return
	_last_played[name] = now
	var player := _free_player()
	player.stream = _sfx_stream(name)
	player.pitch_scale = clampf(1.0 + randf_range(-0.018, 0.018), 0.96, 1.04)
	player.play()


func _free_player() -> AudioStreamPlayer:
	for player in _players:
		if not player.playing:
			return player
	var player: AudioStreamPlayer = _players[_next_voice % _players.size()]
	_next_voice = (_next_voice + 1) % _players.size()
	return player


func play_file(path: String) -> void:
	if not bool(SaveStore.settings().get("soundOn", true)) or not ResourceLoader.exists(path):
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(_last_played.get(path, -999)) < .08:
		return
	_last_played[path] = now
	if not _sfx_cache.has(path):
		_sfx_cache[path] = load(path)
	var player := _free_player()
	player.stream = _sfx_cache[path]
	player.pitch_scale = 1.0
	player.play()


func stop_all() -> void:
	stop_music()
	for player in _players:
		player.stop()


func _recipe(name: String) -> Dictionary:
	match name:
		"confirm":
			return _notes([659.25, 880.0], 0.06, [0.06, 0.12])
		"save":
			return _notes([523.25, 783.99], 0.065, [0.065, 0.14])
		"dialog_open":
			return _notes([392.0, 587.33], 0.05, [0.05, 0.1])
		"dialog_close":
			return _notes([587.33, 392.0], 0.045, [0.045, 0.08])
		"move":
			return _notes([220.0], 0.04, [0.055])
		"capture":
			return _notes([196.0, 392.0], 0.045, [0.045, 0.09])
		"drop":
			return _notes([293.66], 0.06, [0.08])
		"correct", "success":
			return _notes([523.25, 659.25, 783.99], 0.09, [0.18, 0.18, 0.3])
		"wrong":
			return _notes([349.23, 261.63], 0.16, [0.26, 0.38])
		"turn":
			return _notes([440.0, 587.33], 0.1, [0.14, 0.2])
		"tap":
			return _notes([700.0], 0.035, [0.06])
		"select":
			return _notes([587.33, 783.99], 0.055, [0.08, 0.12])
		"back":
			return _notes([392.0, 329.63], 0.07, [0.12, 0.18])
		"pause":
			return _notes([392.0, 523.25], 0.11, [0.14, 0.23])
		"win":
			return _notes([523.25, 659.25, 783.99, 1046.5], 0.12, [0.18, 0.18, 0.18, 0.42])
		"flip":
			return _notes([660.0, 880.0], 0.04, [0.06, 0.08])
		"pair":
			return _notes([783.99, 987.77, 1174.66], 0.07, [0.1, 0.1, 0.24])
		"plant":
			return _notes([196.0, 293.66, 392.0], 0.06, [0.09, 0.09, 0.16])
		"sun":
			return _notes([1046.5, 1318.51], 0.05, [0.07, 0.13])
		"shoot":
			return _notes([880.0], 0.025, [0.045])
		"hit":
			return _notes([150.0, 110.0], 0.04, [0.05, 0.08])
		"food":
			return _notes([110.0, 92.0], 0.08, [0.09, 0.1])
		"mower":
			return _notes([220.0, 330.0, 440.0], 0.055, [0.08, 0.08, 0.18])
		"flag":
			return _notes([392.0, 523.25, 659.25], 0.1, [0.15, 0.15, 0.28])
		"boss":
			return _notes([130.81, 146.83, 130.81, 98.0], 0.18, [0.25, 0.25, 0.25, 0.45])
		"studio":
			return _notes([261.63, 329.63, 392.0], 0.11, [0.16, 0.16, 0.34])
		"title":
			return _notes([523.25, 659.25, 783.99, 1046.5], 0.1, [0.16, 0.16, 0.16, 0.36])
		"whoosh":
			return _notes([196.0, 246.94, 329.63, 440.0], 0.06, [0.08, 0.08, 0.08, 0.18])
		"coin":
			return _notes([987.77, 1318.51], 0.045, [0.07, 0.16])
		_:
			return _notes([523.25], 0.05, [0.1])


func _notes(values: Array, note_length: float, durations: Array) -> Dictionary:
	return {"notes": values, "noteLength": note_length, "durations": durations}


func _build_stream(values: Array, note_length: float, looped: bool, durations: Array = []) -> AudioStreamWAV:
	var frames := 0
	for index in values.size():
		frames += maxi(1, int(float(durations[index] if index < durations.size() else note_length) * RATE))
	frames = maxi(1, frames)
	var bytes := PackedByteArray()
	bytes.resize(frames * 2)
	var cursor := 0
	for index in values.size():
		var frequency := float(values[index])
		var note_duration := float(durations[index]) if index < durations.size() else note_length
		var note_frames := maxi(1, int(note_duration * RATE))
		for frame in note_frames:
			if cursor >= frames:
				break
			var progress := float(frame) / float(note_frames)
			var attack := minf(1.0, progress / 0.05)
			var release := minf(1.0, (1.0 - progress) / 0.16)
			var envelope := attack * release
			var tone := sin(TAU * frequency * float(frame) / RATE)
			var overtone := sin(TAU * frequency * 2.0 * float(frame) / RATE) * 0.15
			var sample := clampf((tone + overtone) * envelope * 0.32, -1.0, 1.0)
			var encoded := int(sample * 32767.0)
			bytes[cursor * 2] = encoded & 0xff
			bytes[cursor * 2 + 1] = (encoded >> 8) & 0xff
			cursor += 1
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = bytes
	if looped:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = frames
	return wav


func start_music(theme: String) -> void:
	if not bool(SaveStore.settings().get("musicOn", true)):
		stop_music()
		return
	if _theme == theme and _music_players[_active_music].playing:
		return
	_theme = theme
	if not _music_cache.has(theme):
		if theme.begins_with("garden:"):
			var path := "res://assets/garden/music/" + theme.trim_prefix("garden:") + ".mp3"
			if ResourceLoader.exists(path):
				var stream: AudioStreamMP3 = load(path).duplicate()
				stream.loop = true
				_music_cache[theme] = stream
			else:
				_music_cache[theme] = _build_music("garden")
		else:
			_music_cache[theme] = _build_music(theme)
	var old_index := _active_music
	var next_index := 1 - _active_music
	var old_player := _music_players[old_index]
	var next_player := _music_players[next_index]
	next_player.stop()
	next_player.stream = _music_cache[theme]
	next_player.volume_db = SILENT_DB
	next_player.play()
	if _music_tween != null:
		_music_tween.kill()
	_music_tween = MotionKit.tween(self)
	_music_tween.set_parallel(true)
	if old_player.playing:
		_music_tween.tween_property(old_player, "volume_db", SILENT_DB, 0.28)
	_music_tween.tween_property(next_player, "volume_db", MUSIC_DB, 0.28).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_music_tween.chain().tween_callback(func():
		if old_player != next_player:
			old_player.stop()
	)
	_active_music = next_index


func stop_music() -> void:
	_theme = ""
	if _music_tween != null:
		_music_tween.kill()
	for player in _music_players:
		player.stop()
		player.volume_db = SILENT_DB


func refresh_settings() -> void:
	if not bool(SaveStore.settings().get("musicOn", true)):
		stop_music()
	elif not _music_players[_active_music].playing:
		start_music("lobby" if _theme.is_empty() else _theme)


func set_music_duck(active: bool, reason: StringName = &"story") -> void:
	if active:
		_duck_reasons[reason] = true
	else:
		_duck_reasons.erase(reason)
	var bus := AudioServer.get_bus_index("Music")
	if bus < 0:
		return
	# 压低总线音量，避免与两路播放器的切曲渐变争用。
	_apply_volume_settings()


func _build_music(theme: String) -> AudioStreamWAV:
	var roots := {
		"lobby": 261.63,
		"garden": 293.66,
		"night": 196.0,
		"pool": 329.63,
		"fog": 174.61,
		"roof": 220.0,
		"poetry": 246.94,
		"math": 261.63,
		"water": 261.63,
		"forest": 293.66,
		"rainbow": 349.23,
	}
	var root := float(roots.get(theme, 261.63))
	var pattern := [1.0, 1.25, 1.5, 2.0, 1.5, 1.25, 1.125, 1.5]
	var values: Array = []
	for index in 16:
		values.append(0.38 if index % 4 == 3 else 0.24)
	var duration := 0.0
	for value in values:
		duration += float(value)
	var frames := int(duration * RATE)
	var bytes := PackedByteArray()
	bytes.resize(frames * 2)
	var cursor := 0
	for step in 16:
		var frequency := root * float(pattern[step % pattern.size()])
		var note_frames := int(float(values[step]) * RATE)
		for frame in note_frames:
			if cursor >= frames:
				break
			var progress := float(frame) / float(note_frames)
			var envelope := sin(PI * progress) * 0.14
			var sample := sin(TAU * frequency * float(frame) / RATE) * envelope
			sample += sin(TAU * frequency * 0.5 * float(frame) / RATE) * envelope * 0.45
			var encoded := int(clampf(sample, -1.0, 1.0) * 32767.0)
			bytes[cursor * 2] = encoded & 0xff
			bytes[cursor * 2 + 1] = (encoded >> 8) & 0xff
			cursor += 1
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = bytes
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = frames
	return wav
