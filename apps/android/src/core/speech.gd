extends Node

var _voice_id := ""
var _last_text := ""
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


func speak(text: String) -> void:
	if text.strip_edges().is_empty():
		return
	if not bool(SaveStore.settings().get("speechOn", true)) or float(SaveStore.settings().get("speechVolume", 0.72)) <= 0.0:
		stop()
		return
	_last_text = text
	if _voice_id.is_empty() and not DisplayServer.tts_get_voices().is_empty():
		_voice_id = str(DisplayServer.tts_get_voices()[0].get("id", ""))
	if _voice_id.is_empty():
		return
	_speaking = true
	_speaking_grace = 0.35
	AudioFX.set_music_duck(true, &"tts")
	var volume := int(round(clampf(float(SaveStore.settings().get("speechVolume", 0.72)), 0.0, 1.0) * 100.0))
	DisplayServer.tts_speak(text, _voice_id, volume, 1.03, 0.92, 0, true)


func repeat() -> void:
	if not _last_text.is_empty():
		speak(_last_text)


func stop() -> void:
	DisplayServer.tts_stop()
	_speaking = false
	AudioFX.set_music_duck(false, &"tts")


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
