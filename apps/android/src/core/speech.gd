extends Node

signal unavailable(message: String)

var _voice_id := ""
var _last_text := ""
var _last_owner := ""
var _current_owner := ""
var _speaking := false
var _speaking_grace := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var voices := DisplayServer.tts_get_voices()
	for voice in voices:
		var language := str(voice.get("language", "")).to_lower()
		var name := str(voice.get("name", "")).to_lower()
		if language.begins_with("zh") or "chinese" in name or "中文" in name:
			_voice_id = str(voice.get("id", ""))
			break


func speak(text: String, owner: String = "") -> bool:
	return begin(text, 0.92, owner)


func begin(text: String, rate: float = 0.92, owner: String = "") -> bool:
	if text.strip_edges().is_empty():
		return false
	if not bool(SaveStore.settings().get("speechOn", true)) or float(SaveStore.settings().get("speechVolume", 0.72)) <= 0.0:
		stop()
		return false
	_last_text = text
	_last_owner = owner
	if not _ensure_chinese_voice():
		unavailable.emit("平板没有检测到中文语音，请先在系统设置中安装中文 TTS。")
		return false
	DisplayServer.tts_stop()
	_current_owner = owner
	_speaking = true
	_speaking_grace = 0.35
	AudioFX.set_music_duck(true, &"tts")
	var volume := int(round(clampf(float(SaveStore.settings().get("speechVolume", 0.72)), 0.0, 1.0) * 100.0))
	DisplayServer.tts_speak(text, _voice_id, volume, 1.03, rate, 0, true)
	return true


func has_chinese_voice() -> bool:
	return _ensure_chinese_voice()


func is_speaking() -> bool:
	return _speaking


func _ensure_chinese_voice() -> bool:
	if not _voice_id.is_empty():
		return true
	for voice in DisplayServer.tts_get_voices():
		var language := str(voice.get("language", "")).to_lower()
		var name := str(voice.get("name", "")).to_lower()
		if language.begins_with("zh") or "chinese" in name or "中文" in name:
			_voice_id = str(voice.get("id", ""))
			return true
	return false


func repeat() -> void:
	if not _last_text.is_empty():
		speak(_last_text, _last_owner)


func stop() -> void:
	DisplayServer.tts_stop()
	_speaking = false
	_current_owner = ""
	AudioFX.set_music_duck(false, &"tts")


func stop_owner(owner: String) -> void:
	if owner.is_empty() or _current_owner == owner:
		stop()


func is_owned_by(owner: String) -> bool:
	return not owner.is_empty() and _current_owner == owner


func _process(delta: float) -> void:
	if not _speaking:
		return
	if not bool(SaveStore.settings().get("speechOn", true)) or float(SaveStore.settings().get("speechVolume", 0.72)) <= 0.0:
		stop()
		return
	_speaking_grace = maxf(0.0,_speaking_grace-delta)
	if _speaking_grace > 0.0:
		return
	if not DisplayServer.tts_is_speaking():
		_speaking = false
		AudioFX.set_music_duck(false, &"tts")
