class_name SfxMap
extends RefCounted

## 语义事件 → AudioFX 合成音效名 的统一映射
## AudioFX.play 内部已读取 soundOn 设置，这里只做事件名转译
## 未映射事件回退 "tap"

const MAP := {
	&"tap": "tap",
	&"select": "select",
	&"deselect": "back",
	&"drag_start": "whoosh",
	&"drop": "drop",
	&"cancel": "back",
	&"error": "wrong",
	&"success": "correct",
	&"flip": "flip",
	&"match": "pair",
	&"mismatch": "wrong",
	&"move": "move",
	&"capture": "capture",
	&"confirm": "confirm",
	&"save": "save",
	&"win": "win",
	&"lose": "wrong",
	&"dialog_open": "dialog_open",
	&"dialog_close": "dialog_close",
}
const FALLBACK := "tap"


static func play(event: StringName) -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var audio := tree.root.get_node_or_null("AudioFX")
	if audio != null:
		audio.call("play", str(MAP.get(event, FALLBACK)))


static func sound_name(event: StringName) -> String:
	return str(MAP.get(event, FALLBACK))
