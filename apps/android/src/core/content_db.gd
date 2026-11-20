extends Node

const CONTENT_ROOT := "res://content/"

var games: Array[Dictionary] = []
var game_map: Dictionary = {}
var quizzes: Dictionary = {}
var memory: Dictionary = {}
var poems: Array = []
var workbook_questions: Array = []
var content_version: int = 1
var chapters: Dictionary = {}
var puzzles: Dictionary = {}
var tuning: Dictionary = {}
var military: Dictionary = {}
var stories: Array = []
var story_map: Dictionary = {}
var story_audio: Dictionary = {}


func _ready() -> void:
	if OS.get_environment("KIDS_PLAYGROUND_AUDIT") != "1" and UpdateService.has_method("load_applied_content_pack"):
		UpdateService.load_applied_content_pack()
	_load_json_files()


func _load_json_files() -> void:
	games.assign(_json_array("games.json"))
	for item in games:
		game_map[str(item.get("id", ""))] = item
	quizzes = _json_dictionary("quizzes.json")
	memory = _json_dictionary("memory.json")
	poems = _json_array("poems.json")
	workbook_questions = _json_array("workbook.json")
	chapters = _json_dictionary("chapters.json")
	puzzles = _json_dictionary("puzzles.json")
	tuning = _json_dictionary("tuning.json")
	military = _json_dictionary("military.json")
	stories = _json_array("stories.json").filter(func(entry): return entry is Dictionary and not str(entry.get("id", "")).is_empty())
	story_map.clear()
	for entry in stories:
		if entry is Dictionary and not str(entry.get("id", "")).is_empty():
			story_map[str(entry.id)] = entry
	story_audio = _json_dictionary("story-audio.json")
	var version_data := _json_dictionary("version.json")
	content_version = int(version_data.get("version", 1))


func _read_text(filename: String) -> String:
	var path := CONTENT_ROOT + filename
	if not FileAccess.file_exists(path):
		push_error("缺少原生内容：" + path)
		return ""
	return FileAccess.get_file_as_string(path)


func _json(filename: String) -> Variant:
	var value: Variant = JSON.parse_string(_read_text(filename))
	return value


func _json_array(filename: String) -> Array:
	var value: Variant = _json(filename)
	if value is Array:
		return value
	return []


func _json_dictionary(filename: String) -> Dictionary:
	var value: Variant = _json(filename)
	if value is Dictionary:
		return value
	return {}


func game(game_id: String) -> Dictionary:
	return game_map.get(game_id, {})


func story(story_id: String) -> Dictionary:
	return story_map.get(story_id, {})


func story_audio_entry(story_id: String) -> Dictionary:
	var assets: Variant = story_audio.get("assets", {})
	if not assets is Dictionary:
		return {}
	var entry: Variant = assets.get(story_id, {})
	if not entry is Dictionary or str(entry.get("textSha256", "")) != str(story(story_id).get("narrationSha256", "")):
		return {}
	return entry


func default_order() -> Array[String]:
	var result: Array[String] = []
	for item in games:
		if item.get("group", "games") == "games":
			result.append(str(item.id))
	for item in games:
		if item.get("group", "games") == "practice":
			result.append(str(item.id))
	return result


func ordered_games(order: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var seen := {}
	for game_id in order:
		if game_map.has(game_id) and not seen.has(game_id):
			result.append(game_map[game_id])
			seen[game_id] = true
	for item in games:
		if not seen.has(item.id):
			var insertion := result.size()
			for index in result.size():
				if str(result[index].get("group", "games")) == str(item.get("group", "games")):
					insertion = index + 1
			result.insert(insertion, item)
			seen[item.id] = true
	return result


func questions(game_id: String, age: int) -> Array:
	var source: Array
	if game_id == "workbook":
		source = workbook_questions
	elif quizzes.get(game_id) is Array:
		source = quizzes[game_id]
	else:
		return []
	return source.filter(func(question):
		return int(question.get("age", 0)) == age
	)


func random_questions(game_id: String, age: int, count: int, exclude_ids: Array = []) -> Array:
	var pool := questions(game_id, age)
	pool = pool.filter(func(question): return not (str(question.get("id", "")) in exclude_ids))
	pool.shuffle()
	if pool.size() < count:
		var fallback := questions(game_id, age)
		fallback.shuffle()
		for question in fallback:
			if not pool.any(func(existing): return existing.id == question.id):
				pool.append(question)
			if pool.size() >= count:
				break
	return pool.slice(0, count)


func poem_for_age(age: int) -> Array:
	var allowed := ["启蒙"] if age <= 5 else ["启蒙", "进阶"] if age <= 7 else ["进阶", "挑战"] if age <= 10 else ["挑战"]
	return poems.filter(func(poem): return str(poem.get("level", "启蒙")) in allowed)


func random_poem(age: int, excluded_id: String = "") -> Dictionary:
	var pool := poem_for_age(age).filter(func(poem): return poem.id != excluded_id)
	if pool.is_empty():
		pool = poem_for_age(age)
	if pool.is_empty():
		return {}
	return pool.pick_random()


func memory_cards() -> Array:
	return memory.get("cards", [])


func memory_themes() -> Array:
	return memory.get("themes", [])


func guide(game_id: String) -> Array:
	return game(game_id).get("guide", [])


func modes(game_id: String) -> Array:
	var fallback := {"id":"classic","name":"开始游戏","player_range":game(game_id).get("player_range",[1,2])}
	return game(game_id).get("modes", [fallback])


func mode(game_id: String, mode_id: String) -> Dictionary:
	for entry in modes(game_id):
		if str(entry.id) == mode_id:
			return entry
	return modes(game_id)[0]


func level(game_id: String, level_id: int) -> Dictionary:
	var entries: Array = chapters.get(game_id, [])
	return entries[level_id-1].duplicate(true) if level_id > 0 and level_id <= entries.size() else {}


func military_formations() -> Array:
	return military.get("formations", [])


func military_puzzles() -> Array:
	return military.get("puzzles", [])


func chess_puzzles() -> Array:
	return puzzles.get("chess", [])


func sudoku_puzzles() -> Array:
	var value: Variant = _json_dictionary("sudoku.json").get("puzzles", [])
	return value if value is Array else []
