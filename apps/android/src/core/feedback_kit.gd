class_name FeedbackKit
extends RefCounted

static var _last_haptic_ms := 0


static func tap(sound: String = "tap", strength: int = 8) -> void:
	AudioFX.play(sound)
	haptic(strength)


static func haptic(duration_ms: int = 8) -> void:
	if not bool(SaveStore.settings().get("hapticsOn", true)):
		return
	if not OS.has_feature("mobile"):
		return
	var now := Time.get_ticks_msec()
	if now - _last_haptic_ms < 80:
		return
	_last_haptic_ms = now
	Input.vibrate_handheld(clampi(duration_ms, 5, 20))


static func success() -> void:
	AudioFX.play("correct")
	haptic(14)


static func error() -> void:
	AudioFX.play("wrong")
	haptic(18)
