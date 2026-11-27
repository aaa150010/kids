extends Node

const CONTENT_ROOT := "res://content/"

var games: Array[Dictionary] = []
var game_map: Dictionary = {}
var quizzes: Dictionary = {}
var memory: Dictionary = {}
var poems: Array = []
var workbook_questions: Array = []
var trivia_questions: Array = []
var tangram_data: Dictionary = {}
var tangram_levels: Array = []
var spot_data: Dictionary = {}
var spot_scenes: Array = []
var shop_data: Dictionary = {}
var fruit_data: Dictionary = {}
var robot_data: Dictionary = {}
var sentence_train_data: Dictionary = {}
var pipe_data: Dictionary = {}
var tank_data: Dictionary = {}
var sokoban_data: Dictionary = {}
var circuit_data: Dictionary = {}
var pinball_data: Dictionary = {}
var breakout_data: Dictionary = {}
var air_hockey_data: Dictionary = {}
var rhythm_data: Dictionary = {}
var garbage_data: Dictionary = {}
var kitchen_data: Dictionary = {}
var maze_data: Dictionary = {}
var slide_data: Dictionary = {}
var bubble_data: Dictionary = {}
var pixel_art_data: Dictionary = {}
var content_version: int = 1
var chapters: Dictionary = {}
var puzzles: Dictionary = {}
var tuning: Dictionary = {}
var military: Dictionary = {}
var stories: Array = []
var story_map: Dictionary = {}
var _sudoku_puzzles_cache: Array = []
var _content_issues: Array[String] = []


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
	trivia_questions = _json_array("trivia.json")
	tangram_data = _json_dictionary("tangram.json")
	tangram_levels = _expand_tangram_levels(tangram_data)
	var spot_value: Variant = _json("spot.json")
	if spot_value is Dictionary:
		spot_data = spot_value
		spot_scenes = spot_data.get("scenes", []) if spot_data.get("scenes") is Array else []
	elif spot_value is Array:
		spot_data = {"version": 1, "scenes": spot_value}
		spot_scenes = spot_value
	else:
		spot_data = {}
		spot_scenes = []
	shop_data = _json_dictionary("shop.json")
	fruit_data = _json_dictionary("fruit_slice.json")
	robot_data = _json_dictionary("robot.json")
	sentence_train_data = _json_dictionary("sentence_train.json")
	pipe_data = _json_dictionary("pipes.json")
	tank_data = _json_dictionary("tank.json")
	sokoban_data = _json_dictionary("sokoban.json")
	circuit_data = _json_dictionary("circuit.json")
	pinball_data = _json_dictionary("pinball.json")
	breakout_data = _json_dictionary("breakout.json")
	air_hockey_data = _json_dictionary("air_hockey.json")
	rhythm_data = _json_dictionary("rhythm.json")
	garbage_data = _json_dictionary("garbage_sort.json")
	kitchen_data = _json_dictionary("kitchen.json")
	maze_data = _json_dictionary("maze.json")
	slide_data = _json_dictionary("slide_puzzle.json")
	bubble_data = _json_dictionary("bubble.json")
	pixel_art_data = _json_dictionary("pixel_art.json")
	chapters = _json_dictionary("chapters.json")
	puzzles = _json_dictionary("puzzles.json")
	tuning = _json_dictionary("tuning.json")
	military = _json_dictionary("military.json")
	stories = _json_array("stories.json").filter(func(entry): return entry is Dictionary and not str(entry.get("id", "")).is_empty())
	story_map.clear()
	for entry in stories:
		if entry is Dictionary and not str(entry.get("id", "")).is_empty():
			story_map[str(entry.id)] = entry
	var version_data := _json_dictionary("version.json")
	content_version = int(version_data.get("version", 1))
	_sudoku_puzzles_cache.clear()
	_validate_content()


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
	elif game_id == "trivia":
		source = trivia_questions
	elif quizzes.get(game_id) is Array:
		source = quizzes[game_id]
	else:
		return []
	var max_age := 6 if age <= 6 else 9 if age <= 9 else 12
	return source.filter(func(question):
		return int(question.get("age", 0)) >= 4 and int(question.get("age", 0)) <= max_age
	)


func search_games(query: String) -> Array[String]:
	var needle := query.strip_edges().to_lower()
	if needle.is_empty():
		return default_order()
	var tokens := needle.split(" ", false)
	var result: Array[String] = []
	for item in games:
		var game_id := str(item.get("id", ""))
		var haystack := _game_search_text(item).to_lower()
		var matched := true
		for token in tokens:
			if not haystack.contains(str(token)):
				matched = false
				break
		if matched:
			result.append(game_id)
	return result


func _game_search_text(item: Dictionary) -> String:
	var parts: Array[String] = [
		str(item.get("id", "")),
		str(item.get("title", "")),
		str(item.get("subtitle", "")),
		str(item.get("category", "")),
		str(item.get("group", "")),
		str(item.get("players", "")),
	]
	for key in ["features", "guide", "searchTerms"]:
		if item.get(key) is Array:
			for value in item[key]:
				parts.append(str(value))
	for entry in item.get("modes", []):
		if entry is Dictionary:
			parts.append(str(entry.get("name", "")))
			parts.append(str(entry.get("description", "")))
	return " ".join(parts)


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
	if level_id <= 0 or level_id > entries.size():
		return {}
	var entry: Dictionary = entries[level_id-1].duplicate(true)
	_enrich_chapter(game_id, level_id, entry)
	return entry


func _enrich_chapter(game_id: String, level_id: int, entry: Dictionary) -> void:
	if not (game_id in ["math", "pinyin", "patterns", "animals"]):
		return
	if not str(entry.get("skill", "")).strip_edges().is_empty():
		return
	var source: Array = quizzes.get(game_id, []) if quizzes.get(game_id) is Array else []
	if source.is_empty():
		return
	var skill_info := {}
	for question in source:
		var skill := str(question.get("skill", "")).strip_edges()
		if skill.is_empty():
			continue
		if not skill_info.has(skill):
			skill_info[skill] = {"minAge": int(question.get("age", 99)), "count": 0}
		var info: Dictionary = skill_info[skill]
		info.minAge = mini(int(info.minAge), int(question.get("age", 99)))
		info.count = int(info.count) + 1
		skill_info[skill] = info
	if skill_info.is_empty():
		return
	var skills: Array = skill_info.keys()
	skills.sort_custom(func(first, second):
		var a: Dictionary = skill_info[first]
		var b: Dictionary = skill_info[second]
		if int(a.minAge) == int(b.minAge):
			return str(first) < str(second)
		return int(a.minAge) < int(b.minAge)
	)
	var skill := str(skills[(level_id - 1) % skills.size()])
	entry.skill = skill
	entry.title = "第 %s 关 · %s" % [level_id, skill]


func military_formations() -> Array:
	return military.get("formations", [])


func military_puzzles() -> Array:
	return military.get("puzzles", [])


func chess_puzzles() -> Array:
	return puzzles.get("chess", [])


func tangram_levels_data() -> Array:
	return tangram_levels


func _expand_tangram_levels(data: Dictionary) -> Array:
	var result: Array = []
	var templates: Dictionary = data.get("templates", {}) if data.get("templates") is Dictionary else {}
	for raw in data.get("levels", []):
		if not raw is Dictionary:
			continue
		var entry: Dictionary = raw.duplicate(true)
		var template: Array = templates.get(str(entry.get("template", "")), []) if templates.get(str(entry.get("template", ""))) is Array else []
		var turn := int(entry.get("turn", 0))
		var target: Array = []
		for piece in template:
			if not piece is Dictionary:
				continue
			var source := Vector2(float(piece.get("x", 0.5)), float(piece.get("y", 0.5))) - Vector2(0.5, 0.5)
			source = source.rotated(float(turn) * PI * 0.5) + Vector2(0.5, 0.5)
			target.append({
				"kind": str(piece.get("kind", "square")),
				"x": source.x, "y": source.y,
				"rotation": (int(piece.get("rotation", 0)) + turn) % 4,
				"mirror": bool(piece.get("mirror", false)),
			})
		entry.targetPieces = target
		result.append(entry)
	return result


func spot_scene_data() -> Array:
	return spot_scenes


func shop_items() -> Array:
	var value: Variant = shop_data.get("items", [])
	return value if value is Array else []


func shop_orders() -> Array:
	var value: Variant = shop_data.get("orders", [])
	return value if value is Array else []


func fruit_types() -> Array:
	var value: Variant = fruit_data.get("fruits", [])
	return value if value is Array else []


func robot_levels() -> Array:
	var value: Variant = robot_data.get("levels", [])
	return value if value is Array else []


func sentence_stations() -> Array:
	var value: Variant = sentence_train_data.get("stations", [])
	return value if value is Array else []


func pipe_levels() -> Array:
	var value: Variant = pipe_data.get("levels", [])
	return value if value is Array else []


func tank_levels() -> Array:
	var value: Variant = tank_data.get("levels", [])
	return value if value is Array else []


func sokoban_levels() -> Array:
	var value: Variant = sokoban_data.get("levels", [])
	return value if value is Array else []


func circuit_levels() -> Array:
	var value: Variant = circuit_data.get("levels", [])
	return value if value is Array else []


func pinball_tables() -> Array:
	var value: Variant = pinball_data.get("tables", [])
	return value if value is Array else []


func breakout_levels() -> Array:
	var value: Variant = breakout_data.get("levels", [])
	return value if value is Array else []


func air_hockey_arenas() -> Array:
	var value: Variant = air_hockey_data.get("arenas", [])
	return value if value is Array else []


func rhythm_charts() -> Array:
	var value: Variant = rhythm_data.get("charts", [])
	return value if value is Array else []


func garbage_levels() -> Array:
	var value: Variant = garbage_data.get("levels", [])
	return value if value is Array else []


func kitchen_levels() -> Array:
	var value: Variant = kitchen_data.get("levels", [])
	return value if value is Array else []


func maze_levels() -> Array:
	var value: Variant = maze_data.get("levels", [])
	return value if value is Array else []


func slide_levels() -> Array:
	var value: Variant = slide_data.get("levels", [])
	return value if value is Array else []


func bubble_levels() -> Array:
	var value: Variant = bubble_data.get("levels", [])
	return value if value is Array else []


func pixel_art_pages() -> Array:
	var value: Variant = pixel_art_data.get("levels", [])
	return value if value is Array else []


func sudoku_puzzles() -> Array:
	if _sudoku_puzzles_cache.is_empty():
		var value: Variant = _json_dictionary("sudoku.json").get("puzzles", [])
		if value is Array:
			_sudoku_puzzles_cache = value.duplicate(true)
	return _sudoku_puzzles_cache


func content_issues() -> Array[String]:
	return _content_issues.duplicate()


func _validate_content() -> void:
	_content_issues.clear()
	if games.size() != 34:
		_content_issues.append("游戏目录应为 34 项，实际 %s 项" % games.size())
	for game_id in ["math", "pinyin", "patterns", "animals"]:
		if questions(game_id, 5).is_empty() and questions(game_id, 6).is_empty():
			_content_issues.append("%s 题库为空或年龄映射异常" % game_id)
	for game_id in ["math", "pinyin", "patterns", "animals", "workbook"]:
		for question in questions(game_id, 5).slice(0, 20):
			if not question.get("options") is Array or question.options.size() != 3:
				_content_issues.append("%s 题目 %s 的选项不是三项" % [game_id, str(question.get("id", ""))])
				break
			if int(question.get("answer", -1)) not in [0, 1, 2]:
				_content_issues.append("%s 题目 %s 的答案索引越界" % [game_id, str(question.get("id", ""))])
				break
	if sudoku_puzzles().size() < 32:
		_content_issues.append("数独题库不足 32 题")
	if trivia_questions.size() < 160:
		_content_issues.append("知识竞赛题库不足 160 题")
	for age in range(4, 13):
		if trivia_questions.filter(func(item): return int(item.get("age", 0)) == age).size() < 8:
			_content_issues.append("知识竞赛缺少 %s 岁题目" % age)
	if tangram_levels.size() < 24:
		_content_issues.append("七巧板关卡不足 24 关")
	if spot_scenes.size() < 24:
		_content_issues.append("找不同场景不足 24 个")
	if shop_items().size() < 16 or shop_orders().size() < 24:
		_content_issues.append("小小商店商品或订单不足")
	if fruit_types().size() < 8:
		_content_issues.append("水果切切乐水果种类不足")
	if robot_levels().size() < 24:
		_content_issues.append("路线小机器人关卡不足 24 关")
	if sentence_stations().size() < 24:
		_content_issues.append("句子小火车车站不足 24 站")
	if pipe_levels().size() < 36:
		_content_issues.append("水管工坊关卡不足 36 关")
	if tank_levels().size() != 30:
		_content_issues.append("坦克小卫士固定关卡应为 30 张，实际 %s 张" % tank_levels().size())
	if sokoban_levels().size() != 48:
		_content_issues.append("仓库推推乐关卡应为 48 关，实际 %s 关" % sokoban_levels().size())
	if circuit_levels().size() != 32:
		_content_issues.append("电路小工坊关卡应为 32 关，实际 %s 关" % circuit_levels().size())
	if bubble_levels().size() != 24:
		_content_issues.append("泡泡星星关卡应为 24 关，实际 %s 关" % bubble_levels().size())
	if rhythm_charts().size() != 24:
		_content_issues.append("节奏拍拍乐谱面应为 24 张，实际 %s 张" % rhythm_charts().size())
	if garbage_levels().size() != 30:
		_content_issues.append("垃圾分类站关卡应为 30 关，实际 %s 关" % garbage_levels().size())
	if kitchen_levels().size() != 24:
		_content_issues.append("小小厨房订单应为 24 个，实际 %s 个" % kitchen_levels().size())
	if maze_levels().size() != 32:
		_content_issues.append("迷宫小探险关卡应为 32 关，实际 %s 关" % maze_levels().size())
	if slide_levels().size() != 32:
		_content_issues.append("数字华容道关卡应为 32 关，实际 %s 关" % slide_levels().size())
	if pixel_art_pages().size() != 30:
		_content_issues.append("像素小画家画稿应为 30 张，实际 %s 张" % pixel_art_pages().size())
	if pinball_tables().size() != 24:
		_content_issues.append("弹珠星轨关卡应为 24 张，实际 %s 张" % pinball_tables().size())
	if breakout_levels().size() != 24:
		_content_issues.append("砖块小城堡关卡应为 24 关，实际 %s 关" % breakout_levels().size())
	if air_hockey_arenas().size() != 18:
		_content_issues.append("冰球碰碰台场地应为 18 个，实际 %s 个" % air_hockey_arenas().size())
	_append_rule_issues("坦克小卫士", TankRules.validate_catalog(tank_data))
	_append_rule_issues("仓库推推乐", SokobanRules.validate_catalog(sokoban_data))
	_append_rule_issues("电路小工坊", CircuitRules.validate_catalog(circuit_data))
	_append_rule_issues("泡泡星星", BubbleRules.validate_catalog(bubble_data))
	_append_rule_issues("节奏拍拍乐", RhythmRules.validate_catalog(rhythm_data))
	_append_rule_issues("垃圾分类站", GarbageSortRules.validate_catalog(garbage_data))
	_append_rule_issues("小小厨房", KitchenRules.validate_catalog(kitchen_data))
	_append_rule_issues("迷宫小探险", MazeRules.validate_catalog(maze_data))
	_append_rule_issues("数字华容道", SlidePuzzleRules.validate_catalog(slide_data))
	_append_rule_issues("像素小画家", PixelArtRules.validate_catalog(pixel_art_data))
	_append_rule_issues("弹珠星轨", PinballRules.validate_catalog(pinball_data))
	_append_rule_issues("砖块小城堡", BreakoutRules.validate_catalog(breakout_data))
	_append_rule_issues("冰球碰碰台", AirHockeyRules.validate_catalog(air_hockey_data))
	for level in tangram_levels:
		if not level is Dictionary or not level.get("targetPieces") is Array or level.targetPieces.size() != 7:
			_content_issues.append("七巧板关卡碎片配置异常")
			break
	for scene in spot_scenes:
		if not scene is Dictionary or not scene.get("differences") is Array or scene.differences.size() != 5:
			_content_issues.append("找不同场景差异配置异常")
			break
	for order in shop_orders():
		if not order is Dictionary or not order.get("items") is Array or order.get("items").is_empty():
			_content_issues.append("小小商店订单配置异常")
			break
	for level in robot_levels():
		if not level is Dictionary or not level.get("solution") is Array or level.solution.is_empty():
			_content_issues.append("路线小机器人关卡缺少固定解法")
			break
	for station in sentence_stations():
		if not station is Dictionary or not station.get("sentences") is Array or station.sentences.size() != 5:
			_content_issues.append("句子小火车车站应有 5 句")
			break
	for level in pipe_levels():
		if not level is Dictionary or not level.get("pieces") is Array or level.pieces.is_empty():
			_content_issues.append("水管工坊关卡管件配置异常")
			break
	if chess_puzzles().is_empty():
		_content_issues.append("中国象棋残局为空")
	if military_puzzles().size() < 24:
		_content_issues.append("军棋残局不足 24 题")
	for issue in _content_issues:
		push_warning("内容检查：" + issue)


func _append_rule_issues(label: String, report: Dictionary) -> void:
	var issues_value: Variant = report.get("issues", [])
	if not issues_value is Array:
		return
	for issue in issues_value:
		_content_issues.append("%s：%s" % [label, str(issue)])
