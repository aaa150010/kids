class_name GameTuning
extends RefCounted

const LEVELS := ["easy", "normal", "challenge"]

const FALLBACK := {
	"math": {"kind":"quiz","rounds":{"easy":6,"normal":8,"challenge":10},"starThresholds":{"easy":[0.5,0.75,1.0],"normal":[0.6,0.8,1.0],"challenge":[0.75,0.9,1.0]}},
	"pinyin": {"kind":"quiz","rounds":{"easy":6,"normal":8,"challenge":10},"starThresholds":{"easy":[0.5,0.75,1.0],"normal":[0.6,0.8,1.0],"challenge":[0.75,0.9,1.0]}},
	"patterns": {"kind":"quiz","rounds":{"easy":6,"normal":8,"challenge":10},"starThresholds":{"easy":[0.5,0.75,1.0],"normal":[0.6,0.8,1.0],"challenge":[0.75,0.9,1.0]}},
	"animals": {"kind":"quiz","rounds":{"easy":6,"normal":8,"challenge":10},"starThresholds":{"easy":[0.5,0.75,1.0],"normal":[0.6,0.8,1.0],"challenge":[0.75,0.9,1.0]}},
	"workbook": {"kind":"quiz","rounds":{"easy":8,"normal":10,"challenge":12},"starThresholds":{"easy":[0.5,0.75,1.0],"normal":[0.6,0.8,1.0],"challenge":[0.75,0.9,1.0]}},
	"memory": {"kind":"memory","pairsDelta":{"easy":-2,"normal":0,"challenge":2},"previewSeconds":{"easy":1.2,"normal":0.8,"challenge":0.55},"hints":{"easy":3,"normal":2,"challenge":1},"threeStarMistakes":{"easy":4,"normal":3,"challenge":2}},
	"jungle": {"kind":"board","hintSeconds":{"easy":10,"normal":18,"challenge":0},"hints":{"easy":3,"normal":2,"challenge":1},"undos":{"easy":99,"normal":3,"challenge":1}},
	"gomoku": {"kind":"board","hintSeconds":{"easy":10,"normal":18,"challenge":0},"hints":{"easy":3,"normal":2,"challenge":1},"undos":{"easy":99,"normal":3,"challenge":1}},
	"sudoku": {"kind":"quiz","hintSeconds":{"easy":0,"normal":0,"challenge":0},"hints":{"easy":5,"normal":3,"challenge":1},"undos":{"easy":99,"normal":9,"challenge":3}},
	"chess": {"kind":"board","hintSeconds":{"easy":10,"normal":18,"challenge":0},"hints":{"easy":3,"normal":2,"challenge":1},"undos":{"easy":99,"normal":3,"challenge":1}},
	"military": {"kind":"board","hintSeconds":{"easy":10,"normal":18,"challenge":0},"hints":{"easy":3,"normal":2,"challenge":1},"undos":{"easy":99,"normal":3,"challenge":1}},
	"poetry": {"kind":"poetry","difficultyEnabled":false},
	"stories": {"kind":"stories","difficultyEnabled":false},
}


static func normalize(value: Variant) -> String:
	var key := str(value)
	return key if key in LEVELS else "auto"


static func from_age(age: int) -> String:
	return "easy" if age <= 6 else "challenge" if age >= 10 else "normal"


static func resolve(preference: Variant, players: Array) -> String:
	var normalized := normalize(preference)
	if normalized != "auto":
		return normalized
	if players.is_empty():
		return "normal"
	var youngest := 12
	for player in players:
		youngest = mini(youngest, int(player.get("age", 12)))
	return from_age(youngest)


static func label(level: String) -> String:
	return {"easy":"轻松", "normal":"标准", "challenge":"挑战", "auto":"自动"}.get(level, "自动")


static func definition(game_id: String) -> Dictionary:
	var value: Variant = {}
	var loop := Engine.get_main_loop() as SceneTree
	if loop != null:
		var content := loop.root.get_node_or_null("ContentDB")
		if content != null:
			value = content.tuning.get("games", {}).get(game_id)
	if value is Dictionary:
		return value
	return FALLBACK.get(game_id, {})


static func value(game_id: String, level: String, key: String, fallback: Variant = null) -> Variant:
	var data := definition(game_id)
	var table: Variant = data.get(key)
	if table is Dictionary:
		return table.get(level, table.get("normal", fallback))
	return data.get(key, fallback)


static func supports(game_id: String) -> bool:
	return bool(definition(game_id).get("difficultyEnabled", true))


static func stars(game_id: String, level: String, correct: int, total: int) -> int:
	if total <= 0:
		return 0
	var thresholds: Array = value(game_id, level, "starThresholds", [0.6, 0.8, 1.0])
	var ratio := float(correct) / float(total)
	if ratio >= float(thresholds[2]):
		return 3
	if ratio >= float(thresholds[1]):
		return 2
	if ratio >= float(thresholds[0]):
		return 1
	return 0
