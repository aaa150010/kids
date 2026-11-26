class_name GameSession
extends RefCounted

var state: Dictionary = {}
var random := SessionRng.new()

func create_session(context: Dictionary) -> Dictionary:
	var seed_value := int(context.get("seed", Time.get_ticks_usec()))
	random = SessionRng.new(seed_value)
	state = context.duplicate(true)
	state.merge({"snapshotVersion":2,"sessionId":"%s-%s" % [Time.get_unix_time_from_system(), seed_value],"seed":seed_value,"phase":"playing","reported":false,"history":[]}, true)
	state.gameId = str(context.get("gameId", state.get("gameId", "")))
	state.modeId = str(context.get("modeId", state.get("modeId", "classic")))
	return state

func handle_input(_action: Dictionary) -> Dictionary:
	return {"ok":false}


func apply_action(action: Dictionary) -> Dictionary:
	return handle_input(action)


func result() -> Dictionary:
	if str(state.get("phase", "")) not in ["finished", "result"]:
		return {}
	return {
		"winner": int(state.get("winner", -1)),
		"reason": str(state.get("reason", "")),
		"phase": str(state.get("phase", "")),
	}

func tick(_delta: float) -> bool:
	return false

func snapshot() -> Dictionary:
	state.rngState = str(random.generator.state)
	state.snapshotVersion = 2
	return state.duplicate(true)

func restore(value: Dictionary) -> bool:
	if int(value.get("snapshotVersion", 1)) not in [1, 2]:
		return false
	if not value.get("players") is Array or value.players.is_empty():
		return false
	var seen_ids := {}
	for player in value.players:
		if not player is Dictionary:
			return false
		var player_id := str(player.get("id", ""))
		if player_id.is_empty() or seen_ids.has(player_id) or str(player.get("name", "")).strip_edges().is_empty():
			return false
		seen_ids[player_id] = true
		var age_value: Variant = player.get("age", 0)
		if not (age_value is int or age_value is float) or int(age_value) not in range(4, 13):
			return false
	state = value.duplicate(true)
	state.snapshotVersion = 2
	random = SessionRng.new(int(state.get("seed",1)), int(str(state.get("rngState","0"))))
	return true
