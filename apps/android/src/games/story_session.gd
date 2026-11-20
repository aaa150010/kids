class_name StorySession
extends RefCounted

const CATEGORIES := ["all", "idiom", "myth", "folk", "fable", "history", "fairy"]
const FILTERS := ["all", "age", "favorites", "recent"]
var state: Dictionary = {}
var library: Dictionary = {}


func _number(value: Variant, fallback: float = 0.0) -> float:
	if value is int or value is float:
		return float(value) if is_finite(float(value)) else fallback
	if value is String and value.is_valid_float():
		var parsed := float(value)
		return parsed if is_finite(parsed) else fallback
	return fallback


func create_session(player: Dictionary, catalog: Dictionary, learning: Dictionary = {}) -> Dictionary:
	library = catalog
	state = {
		"schemaVersion": 2, "gameId": "stories", "modeId": "classic",
		"player": player.duplicate(true), "phase": "library", "seed": randi(),
		"storyId": "", "category": "all", "filter": "age", "query": "", "page": 0,
		"pinyin": true, "fontSize": 28,
		"favorites": [], "recent": [], "bookmarks": {}, "completed": [],
	}
	for key in ["fontSize", "favorites", "recent", "bookmarks", "completed"]:
		if learning.has(key):
			state[key] = learning[key].duplicate(true) if learning[key] is Array or learning[key] is Dictionary else learning[key]
	_sanitize()
	return snapshot()


func restore(value: Dictionary) -> bool:
	var schema := int(_number(value.get("schemaVersion", 0)))
	if schema not in [1, 2] or str(value.get("gameId", "")) != "stories":
		return false
	if not value.get("player") is Dictionary or str(value.player.get("id", "")) != str(state.player.id):
		return false
	var previous_player: Dictionary = value.player
	if str(previous_player.get("name", "")).is_empty() or int(_number(previous_player.get("age", 0))) not in range(4, 13):
		return false
	for key in state.keys():
		if value.has(key):
			state[key] = value[key].duplicate(true) if value[key] is Array or value[key] is Dictionary else value[key]
	state.schemaVersion = 2
	if schema == 1:
		state.pinyin = true
	_sanitize()
	return true


func _sanitize() -> void:
	state.category = str(state.get("category", "all")) if state.get("category") in CATEGORIES else "all"
	state.filter = str(state.get("filter", "all")) if state.get("filter") in FILTERS else "all"
	state.phase = "reading" if state.get("phase") == "reading" else "library"
	state.storyId = str(state.get("storyId", ""))
	if not library.has(state.storyId):
		state.storyId = ""
		state.phase = "library"
	state.query = str(state.get("query", "")).left(80)
	state.page = clampi(int(_number(state.get("page", 0))), 0, 100)
	state.fontSize = int(_number(state.get("fontSize", 28), 28)) if int(_number(state.get("fontSize", 28), 28)) in [28, 34, 40] else 28
	state.pinyin = bool(state.get("pinyin", false))
	for key in ["favorites", "recent", "completed"]:
		var cleaned: Array = []
		if state.get(key) is Array:
			for story_id in state[key]:
				if story_id is String and library.has(story_id) and not (story_id in cleaned):
					cleaned.append(story_id)
		state[key] = cleaned.slice(0, 40) if key == "recent" else cleaned
	var clean_bookmarks: Dictionary = {}
	if state.get("bookmarks") is Dictionary:
		for story_id in state.bookmarks:
			if library.has(story_id) and state.bookmarks[story_id] is Dictionary:
				var bookmark: Dictionary = state.bookmarks[story_id]
				var position := _number(bookmark.get("position", 0.0))
				var paragraph := int(_number(bookmark.get("paragraph", 0)))
				var count := maxi(1, library[story_id].get("paragraphs", []).size())
				clean_bookmarks[story_id] = {
					"position": clampf(position, 0.0, 7200.0) if is_finite(position) else 0.0,
					"paragraph": clampi(paragraph, 0, count - 1),
					"offset": clampf(_number(bookmark.get("offset", 0.0)), 0.0, 1.0),
					"audioHash": str(bookmark.get("audioHash", "")),
				}
	state.bookmarks = clean_bookmarks


func handle_input(action: Dictionary) -> bool:
	match str(action.get("type", "")):
		"open":
			var story_id := str(action.get("id", ""))
			if not library.has(story_id):
				return false
			state.storyId = story_id
			state.phase = "reading"
			state.recent.erase(story_id)
			state.recent.push_front(story_id)
			state.recent = state.recent.slice(0, 40)
		"library": state.phase = "library"
		"category":
			if not (action.get("value") in CATEGORIES): return false
			state.category = action.value
			state.page = 0
		"filter":
			if not (action.get("value") in FILTERS): return false
			state.filter = action.value
			state.page = 0
		"query":
			state.query = str(action.get("value", "")).left(80)
			state.page = 0
		"page": state.page = maxi(0, int(action.get("value", 0)))
		"pinyin": state.pinyin = not bool(state.pinyin)
		"font": state.fontSize = [28, 34, 40][([28, 34, 40].find(int(state.fontSize)) + 1) % 3]
		"favorite":
			var story_id := str(action.get("id", state.storyId))
			if not library.has(story_id): return false
			if story_id in state.favorites: state.favorites.erase(story_id)
			else: state.favorites.append(story_id)
		"bookmark":
			if str(state.storyId).is_empty(): return false
			var data: Dictionary = action.get("value", {})
			var previous := bookmark()
			previous.merge(data, true)
			state.bookmarks[state.storyId] = previous
		"complete":
			if str(state.storyId).is_empty(): return false
			if not (state.storyId in state.completed): state.completed.append(state.storyId)
		"restart":
			if str(state.storyId).is_empty(): return false
			state.bookmarks[state.storyId] = {"position": 0.0, "paragraph": 0, "offset": 0.0, "audioHash": ""}
		_: return false
	return true


func bookmark() -> Dictionary:
	return state.bookmarks.get(state.storyId, {"position": 0.0, "paragraph": 0, "offset": 0.0, "audioHash": ""}).duplicate(true)


func tick(_delta: float) -> void:
	pass


func snapshot() -> Dictionary:
	return state.duplicate(true)


func learning_snapshot() -> Dictionary:
	var result := {}
	for key in ["pinyin", "fontSize", "favorites", "recent", "bookmarks", "completed"]:
		result[key] = state[key].duplicate(true) if state[key] is Array or state[key] is Dictionary else state[key]
	return result
