class_name StorySession
extends RefCounted

const CATEGORIES := ["all", "idiom", "myth", "folk", "fable", "history", "fairy"]
const FILTERS := ["all", "age", "favorites", "recent"]
const SCHEMA_VERSION := 3
var state: Dictionary = {}
var library: Dictionary = {}


func _number(value: Variant, fallback: float = 0.0) -> float:
	if value is int or value is float:
		return float(value) if is_finite(float(value)) else fallback
	if value is String and value.is_valid_float():
		var parsed := float(value)
		return parsed if is_finite(parsed) else fallback
	return fallback


func _paragraphs(story_id: String) -> Array:
	var story: Dictionary = library.get(story_id, {})
	var values: Variant = story.get("paragraphs", [])
	return values if values is Array else []


func _paragraph_id(story_id: String, index: int) -> String:
	var paragraphs := _paragraphs(story_id)
	if paragraphs.is_empty():
		return ""
	var safe_index := clampi(index, 0, paragraphs.size() - 1)
	var paragraph: Variant = paragraphs[safe_index]
	if not paragraph is Dictionary:
		return "p%d" % safe_index
	return str(paragraph.get("id", "p%d" % safe_index))


func _valid_paragraph_id(story_id: String, value: Variant) -> String:
	var identifier := str(value)
	if identifier.is_empty():
		return ""
	for index in _paragraphs(story_id).size():
		if _paragraph_id(story_id, index) == identifier:
			return identifier
	return ""


func _content_revision(story_id: String) -> int:
	var story: Dictionary = library.get(story_id, {})
	return maxi(1, int(_number(story.get("contentRevision", 1), 1)))


func _blank_bookmark(story_id: String) -> Dictionary:
	return {
		"contentRevision": _content_revision(story_id),
		"reading": {"paragraphId": "", "characterIndex": 0, "lineOffset": 0.0},
		"listening": {"paragraphId": ""},
		"followReading": false,
	}


func _clean_anchor(story_id: String, value: Variant) -> Dictionary:
	if not value is Dictionary:
		return {"paragraphId": "", "characterIndex": 0, "lineOffset": 0.0}
	var requested_id := str(value.get("paragraphId", ""))
	var paragraph_id := _valid_paragraph_id(story_id, requested_id)
	var count := 0
	if not paragraph_id.is_empty():
		for paragraph in _paragraphs(story_id):
			if str(paragraph.get("id", "")) == paragraph_id and paragraph.get("text") is String:
				count = paragraph.text.length()
				break
	if paragraph_id.is_empty() and not requested_id.is_empty() and not _paragraphs(story_id).is_empty():
		paragraph_id = _paragraph_id(story_id, 0)
		var first: Variant = _paragraphs(story_id)[0]
		if first is Dictionary and first.get("text") is String:
			count = first.text.length()
	return {
		"paragraphId": paragraph_id,
		"characterIndex": clampi(int(_number(value.get("characterIndex", 0))), 0, maxi(0, count - 1)),
		"lineOffset": clampf(_number(value.get("lineOffset", 0.0)), 0.0, 1.0),
	}


func _clean_bookmark(story_id: String, value: Variant) -> Dictionary:
	var result := _blank_bookmark(story_id)
	if not value is Dictionary:
		return result
	if value.get("reading") is Dictionary:
		result.reading = _clean_anchor(story_id, value.reading)
	else:
		var paragraphs := _paragraphs(story_id)
		var index := clampi(int(_number(value.get("paragraph", 0))), 0, maxi(0, paragraphs.size() - 1))
		var legacy_map: Variant = library.get(story_id, {}).get("legacyParagraphMap", [])
		var paragraph_id := ""
		if legacy_map is Array and index < legacy_map.size():
			paragraph_id = _valid_paragraph_id(story_id, legacy_map[index])
		if paragraph_id.is_empty():
			paragraph_id = _paragraph_id(story_id, index)
		var length := 0
		if not paragraphs.is_empty() and paragraphs[index] is Dictionary:
			length = str(paragraphs[index].get("text", "")).length()
		var legacy_offset := clampf(_number(value.get("offset", 0.0)), 0.0, 1.0)
		result.reading = {
			"paragraphId": paragraph_id,
			"characterIndex": clampi(int(floor(legacy_offset * maxi(0, length - 1))), 0, maxi(0, length - 1)),
			"lineOffset": 0.0,
		}
		result.listening = {"paragraphId": paragraph_id}
	if value.get("listening") is Dictionary:
		result.listening = {
			"paragraphId": _valid_paragraph_id(story_id, value.listening.get("paragraphId", "")),
		}
	var follow_value: Variant = value.get("followReading", false)
	result.followReading = follow_value is bool and bool(follow_value)
	result.contentRevision = _content_revision(story_id)
	return result


func create_session(player: Dictionary, catalog: Dictionary, learning: Dictionary = {}) -> Dictionary:
	library = catalog
	state = {
		"schemaVersion": SCHEMA_VERSION, "gameId": "stories", "modeId": "classic",
		"player": player.duplicate(true), "phase": "library", "seed": randi(),
		"storyId": "", "category": "all", "filter": "age", "query": "", "page": 0,
		"pinyin": true, "fontSize": 34, "shelfScroll": 0.0,
		"favorites": [], "recent": [], "bookmarks": {}, "completed": [],
	}
	for key in ["pinyin", "fontSize", "favorites", "recent", "bookmarks", "completed"]:
		if learning.has(key):
			state[key] = learning[key].duplicate(true) if learning[key] is Array or learning[key] is Dictionary else learning[key]
	_sanitize()
	return snapshot()


func restore(value: Dictionary) -> bool:
	var schema := int(_number(value.get("schemaVersion", 0)))
	if schema not in [1, 2, SCHEMA_VERSION] or str(value.get("gameId", "")) != "stories":
		return false
	if not value.get("player") is Dictionary or str(value.player.get("id", "")) != str(state.player.id):
		return false
	var previous_player: Dictionary = value.player
	if str(previous_player.get("name", "")).is_empty() or int(_number(previous_player.get("age", 0))) not in range(4, 13):
		return false
	for key in state.keys():
		if value.has(key):
			state[key] = value[key].duplicate(true) if value[key] is Array or value[key] is Dictionary else value[key]
	state.schemaVersion = SCHEMA_VERSION
	if schema == 1:
		state.pinyin = true
	_sanitize()
	return true


func _sanitize() -> void:
	state.schemaVersion = SCHEMA_VERSION
	state.category = str(state.get("category", "all")) if state.get("category") in CATEGORIES else "all"
	state.filter = str(state.get("filter", "all")) if state.get("filter") in FILTERS else "all"
	state.phase = "reading" if state.get("phase") == "reading" else "library"
	state.storyId = str(state.get("storyId", ""))
	if not library.has(state.storyId):
		state.storyId = ""
		state.phase = "library"
	state.query = str(state.get("query", "")).left(80)
	state.page = clampi(int(_number(state.get("page", 0))), 0, 100)
	state.shelfScroll = clampf(_number(state.get("shelfScroll", 0.0)), 0.0, 1000000.0)
	state.fontSize = int(_number(state.get("fontSize", 34), 34)) if int(_number(state.get("fontSize", 34), 34)) in [28, 34, 40] else 34
	state.pinyin = bool(state.get("pinyin", true))
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
			if library.has(str(story_id)) and state.bookmarks[story_id] is Dictionary:
				clean_bookmarks[str(story_id)] = _clean_bookmark(str(story_id), state.bookmarks[story_id])
	state.bookmarks = clean_bookmarks


func handle_input(action: Dictionary) -> bool:
	match str(action.get("type", "")):
		"open":
			var story_id := str(action.get("id", ""))
			if not library.has(story_id):
				return false
			state.storyId = story_id
			state.phase = "reading"
			if not state.bookmarks.has(story_id):
				state.bookmarks[story_id] = _blank_bookmark(story_id)
			state.recent.erase(story_id)
			state.recent.push_front(story_id)
			state.recent = state.recent.slice(0, 40)
		"library": state.phase = "library"
		"category":
			if not (action.get("value") in CATEGORIES):
				return false
			state.category = action.value
			state.page = 0
		"filter":
			if not (action.get("value") in FILTERS):
				return false
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
			if not library.has(story_id):
				return false
			if story_id in state.favorites:
				state.favorites.erase(story_id)
			else:
				state.favorites.append(story_id)
		"bookmark":
			if str(state.storyId).is_empty():
				return false
			var current := bookmark()
			var data: Dictionary = action.get("value", {})
			if data.get("reading") is Dictionary:
				current.reading = data.reading.duplicate(true)
			elif data.has("paragraphId") or data.has("characterIndex") or data.has("lineOffset"):
				current.reading = data.duplicate(true)
			if data.get("listening") is Dictionary:
				current.listening = data.listening.duplicate(true)
			if data.has("followReading"):
				current.followReading = bool(data.followReading)
			state.bookmarks[state.storyId] = _clean_bookmark(state.storyId, current)
		"complete":
			if str(state.storyId).is_empty():
				return false
			if not (state.storyId in state.completed):
				state.completed.append(state.storyId)
		"restart":
			if str(state.storyId).is_empty():
				return false
			state.bookmarks[state.storyId] = _blank_bookmark(state.storyId)
		_: return false
	return true


func bookmark() -> Dictionary:
	if state.storyId.is_empty():
		return _blank_bookmark("")
	return _clean_bookmark(str(state.storyId), state.bookmarks.get(state.storyId, {}))


func reading_anchor() -> Dictionary:
	return bookmark().reading


func listening_paragraph_id() -> String:
	return str(bookmark().listening.get("paragraphId", ""))


func follow_reading() -> bool:
	return bool(bookmark().get("followReading", false))


func update_reading_anchor(paragraph_id: String, character_index: int, line_offset: float) -> void:
	if state.storyId.is_empty():
		return
	state.bookmarks[state.storyId] = _clean_bookmark(state.storyId, {
		"reading": {
			"paragraphId": paragraph_id,
			"characterIndex": character_index,
			"lineOffset": line_offset,
		},
		"listening": bookmark().listening,
		"followReading": follow_reading(),
	})


func update_listening_paragraph(paragraph_id: String) -> void:
	if state.storyId.is_empty():
		return
	var current := bookmark()
	state.bookmarks[state.storyId] = _clean_bookmark(state.storyId, {
		"reading": current.reading,
		"listening": {"paragraphId": paragraph_id},
		"followReading": current.followReading,
	})


func set_follow_reading(value: bool) -> void:
	if state.storyId.is_empty():
		return
	var current := bookmark()
	state.bookmarks[state.storyId] = _clean_bookmark(state.storyId, {
		"reading": current.reading,
		"listening": current.listening,
		"followReading": value,
	})


func tick(_delta: float) -> void:
	pass


func snapshot() -> Dictionary:
	return state.duplicate(true)


func learning_snapshot() -> Dictionary:
	var result := {}
	for key in ["pinyin", "fontSize", "favorites", "recent", "bookmarks", "completed"]:
		result[key] = state[key].duplicate(true) if state[key] is Array or state[key] is Dictionary else state[key]
	return result
