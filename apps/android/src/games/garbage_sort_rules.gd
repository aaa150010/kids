class_name GarbageSortRules
extends GameSession

const GARBAGE_VERSION := 1
const CATEGORY_IDS := ["recyclable", "hazardous", "kitchen", "other"]


func create_session(context: Dictionary) -> Dictionary:
	super.create_session(context)
	var level: Dictionary = context.get("level", {}).duplicate(true) if context.get("level") is Dictionary else {}
	var categories: Array = context.get("categories", []).duplicate(true) if context.get("categories") is Array else []
	var catalog: Dictionary = context.get("itemCatalog", {}).duplicate(true) if context.get("itemCatalog") is Dictionary else {}
	var queue: Array = level.get("items", []).duplicate(true) if level.get("items") is Array else []
	state.merge({
		"garbageVersion": GARBAGE_VERSION,
		"phase": "sorting",
		"levelId": int(context.get("levelId", level.get("levelNumber", 1))),
		"levelNumber": int(context.get("levelNumber", level.get("levelNumber", 1))),
		"levelData": level,
		"categories": categories,
		"itemCatalog": catalog,
		"queue": queue,
		"currentIndex": 0,
		"placed": [],
		"feedback": {},
		"currentPlayer": 0,
		"score": 0,
		"combo": 0,
		"maxCombo": 0,
		"mistakes": 0,
		"hints": 0,
		"stars": 0,
		"accuracy": 0.0,
		"reported": false,
		"view": "sort",
	}, true)
	var validation := validate_level(level, categories, catalog)
	if not bool(validation.get("ok", false)):
		state.phase = "empty"
		state.reason = "这一关垃圾分类内容不完整。"
		return state
	if str(state.modeId) != str(level.get("mode", state.modeId)):
		state.phase = "empty"
		state.reason = "关卡玩法和当前选择不一致。"
		return state
	if queue.is_empty() or (str(state.modeId) == "adventure" and state.players.size() != 1) or (str(state.modeId) == "classic" and state.players.size() != 2):
		state.phase = "empty"
		state.reason = "垃圾分类的人数或关卡顺序不正确。"
	return state


func restore(value: Dictionary) -> bool:
	if int(value.get("garbageVersion", 0)) != GARBAGE_VERSION:
		return false
	if not super.restore(value):
		return false
	if str(state.get("gameId", "")) != "garbage_sort":
		return false
	if not (str(state.get("phase", "")) in ["sorting", "feedback", "finished"]):
		return false
	if not state.get("levelData") is Dictionary or not state.get("categories") is Array or not state.get("itemCatalog") is Dictionary:
		return false
	var level: Dictionary = state.levelData
	if int(state.get("levelId", -1)) != int(level.get("levelNumber", -2)):
		return false
	if int(state.get("levelNumber", -1)) != int(level.get("levelNumber", -2)):
		return false
	if str(state.get("modeId", "")) != str(level.get("mode", "")):
		return false
	var expected_players := 2 if str(level.get("mode", "")) == "classic" else 1
	if state.players.size() != expected_players:
		return false
	var level_check := validate_level(level, state.categories, state.itemCatalog)
	if not bool(level_check.get("ok", false)):
		return false
	var queue_value: Variant = state.get("queue", [])
	if not queue_value is Array or queue_value != level.get("items", []):
		return false
	var queue: Array = queue_value
	if queue.is_empty():
		return false
	var seen := {}
	var catalogs: Dictionary = state.itemCatalog
	for item_id in queue:
		var key := str(item_id)
		if seen.has(key) or not catalogs.get(key) is Dictionary:
			return false
		seen[key] = true
	var placed_value: Variant = state.get("placed", [])
	if not placed_value is Array:
		return false
	var placed: Array = placed_value
	if placed.size() > queue.size():
		return false
	var mistakes := 0
	var correct_count := 0
	for index in placed.size():
		var entry_value: Variant = placed[index]
		if not entry_value is Dictionary:
			return false
		var entry: Dictionary = entry_value
		if str(entry.get("itemId", "")) != str(queue[index]):
			return false
		var bin_id := str(entry.get("binId", ""))
		var item: Dictionary = catalogs[str(queue[index])]
		if not _category_exists(state.categories, bin_id):
			return false
		if typeof(entry.get("correct", false)) != TYPE_BOOL:
			return false
		var correct := bool(entry.correct)
		if correct != (bin_id == str(item.get("bin", ""))):
			return false
		if correct:
			correct_count += 1
		else:
			mistakes += 1
		if not _numeric(entry.get("playerIndex", -1)) or int(entry.playerIndex) < 0 or int(entry.playerIndex) >= state.players.size():
			return false
	var current_index := int(state.get("currentIndex", -1))
	if current_index < 0 or current_index > queue.size():
		return false
	var phase := str(state.phase)
	if phase == "sorting":
		if current_index != placed.size() or current_index >= queue.size():
			return false
	elif phase == "feedback":
		if placed.is_empty() or current_index != placed.size() - 1:
			return false
	elif phase == "finished":
		if placed.size() != queue.size() or current_index < queue.size():
			return false
	state.mistakes = mistakes
	state.currentIndex = current_index
	state.placed = placed
	state.combo = maxi(0, _integer(state.get("combo", 0)))
	state.maxCombo = maxi(int(state.get("maxCombo", 0)), int(state.combo))
	state.score = maxi(0, _integer(state.get("score", 0)))
	state.hints = maxi(0, _integer(state.get("hints", 0)))
	state.accuracy = float(correct_count) / float(maxi(1, placed.size()))
	state.currentPlayer = clampi(_integer(state.get("currentPlayer", 0)), 0, state.players.size() - 1)
	state.feedback = _clean_feedback(state.get("feedback", {}), catalogs, state.categories)
	if phase == "feedback" and state.feedback.is_empty():
		return false
	if phase != "feedback":
		state.feedback = {}
	state.stars = _stars(mistakes) if phase == "finished" else 0
	state.reported = bool(state.get("reported", false))
	return true


func handle_input(action: Dictionary) -> Dictionary:
	var phase := str(state.get("phase", ""))
	if phase in ["empty", "finished"]:
		return {"ok": false, "message": "这一关已经完成啦。"}
	match str(action.get("type", "")):
		"sort":
			if phase != "sorting":
				return {"ok": false, "message": "先看看刚才的物品解释，再继续。"}
			return _sort(str(action.get("binId", "")))
		"next":
			if phase != "feedback":
				return {"ok": false}
			return _next()
		"hint":
			if phase != "sorting":
				return {"ok": false}
			state.hints = int(state.get("hints", 0)) + 1
			var category := _category(state.categories, str(current_item().get("bin", "")))
			return {
				"ok": true,
				"event": "hint",
				"hint": str(category.get("question", "先想想：它还能再利用吗？")),
			}
	return {"ok": false}


func current_item() -> Dictionary:
	var queue: Array = state.get("queue", [])
	var index := int(state.get("currentIndex", 0))
	if index < 0 or index >= queue.size():
		return {}
	var catalog: Dictionary = state.get("itemCatalog", {})
	var value: Variant = catalog.get(str(queue[index]), {})
	return value.duplicate(true) if value is Dictionary else {}


func category(category_id: String) -> Dictionary:
	return _category(state.get("categories", []), category_id).duplicate(true)


func category_for_item(item_id: String) -> Dictionary:
	var item_value: Variant = state.get("itemCatalog", {}).get(item_id, {})
	if not item_value is Dictionary:
		return {}
	return category(str(item_value.get("bin", "")))


func item_catalog() -> Dictionary:
	return state.get("itemCatalog", {}).duplicate(true)


func result() -> Dictionary:
	if str(state.get("phase", "")) != "finished":
		return {}
	var total := int(state.get("queue", []).size())
	var correct := int(state.get("placed", []).size()) - int(state.get("mistakes", 0))
	return {
		"score": int(state.get("score", 0)),
		"stars": int(state.get("stars", 0)),
		"correct": maxi(0, correct),
		"answered": total,
		"mistakes": int(state.get("mistakes", 0)),
		"hints": int(state.get("hints", 0)),
		"accuracy": float(state.get("accuracy", 0.0)),
		"completed": true,
	}


func progress_text() -> String:
	return "第 %s / %s 件" % [mini(int(state.get("currentIndex", 0)) + 1, int(state.get("queue", []).size())), int(state.get("queue", []).size())]


func _sort(bin_id: String) -> Dictionary:
	if not _category_exists(state.categories, bin_id):
		return {"ok": false, "message": "这四个桶里选一个。"}
	var item := current_item()
	if item.is_empty():
		return {"ok": false, "message": "这一件物品没有准备好。"}
	var correct_bin := str(item.get("bin", ""))
	var correct := bin_id == correct_bin
	var player_index := int(state.get("currentPlayer", 0))
	var entry := {
		"itemId": str(item.get("id", "")),
		"binId": bin_id,
		"correct": correct,
		"playerIndex": player_index,
	}
	var placed: Array = state.get("placed", [])
	placed.append(entry)
	state.placed = placed
	if correct:
		state.combo = int(state.get("combo", 0)) + 1
		state.maxCombo = maxi(int(state.get("maxCombo", 0)), int(state.combo))
		state.score = int(state.get("score", 0)) + 100 + mini(int(state.combo), 10) * 10
	else:
		state.mistakes = int(state.get("mistakes", 0)) + 1
		state.combo = 0
	state.accuracy = float(placed.filter(func(row): return bool(row.get("correct", false))).size()) / float(placed.size())
	state.feedback = {
		"itemId": str(item.get("id", "")),
		"itemName": str(item.get("name", "生活物品")),
		"itemArt": str(item.get("art", "object")),
		"chosenBin": bin_id,
		"correctBin": correct_bin,
		"correct": correct,
		"explanation": str(item.get("explanation", "")),
		"categoryName": str(category(correct_bin).get("name", "正确垃圾桶")),
	}
	state.phase = "feedback"
	return {
		"ok": true,
		"correct": correct,
		"event": "correct" if correct else "mistake",
		"feedback": state.feedback.duplicate(true),
	}


func _next() -> Dictionary:
	if str(state.get("phase", "")) != "feedback":
		return {"ok": false}
	var queue_size := int(state.get("queue", []).size())
	var next_index := int(state.get("currentIndex", 0)) + 1
	state.currentIndex = next_index
	state.feedback = {}
	if state.players.size() > 1:
		state.currentPlayer = (int(state.get("currentPlayer", 0)) + 1) % state.players.size()
	if next_index >= queue_size:
		state.phase = "finished"
		state.stars = _stars(int(state.get("mistakes", 0)))
		state.accuracy = float(int(state.get("placed", []).size()) - int(state.get("mistakes", 0))) / float(maxi(1, queue_size))
		return {"ok": true, "event": "finished", "finished": true}
	state.phase = "sorting"
	return {"ok": true, "event": "next", "finished": false}


func _finish() -> void:
	state.phase = "finished"
	state.stars = _stars(int(state.get("mistakes", 0)))
	state.accuracy = float(int(state.get("placed", []).size()) - int(state.get("mistakes", 0))) / float(maxi(1, int(state.get("queue", []).size())))


static func validate_catalog(data: Dictionary) -> Dictionary:
	var issues: Array[String] = []
	var categories_value: Variant = data.get("categories", [])
	if not categories_value is Array or categories_value.size() != 4:
		return {"ok": false, "issues": ["必须正好包含四类垃圾桶"]}
	var categories: Array = categories_value
	var category_ids := {}
	for raw in categories:
		if not raw is Dictionary:
			issues.append("垃圾桶条目不是对象")
			continue
		var category: Dictionary = raw
		var category_id := str(category.get("id", "")).strip_edges()
		if category_id.is_empty() or category_ids.has(category_id):
			issues.append("垃圾桶 ID 为空或重复")
		category_ids[category_id] = true
		for field in ["name", "color", "short", "question"]:
			if str(category.get(field, "")).strip_edges().is_empty():
				issues.append("%s 缺少 %s" % [category_id, field])
	if category_ids.size() != 4:
		issues.append("四类垃圾桶 ID 不完整")
	for required in CATEGORY_IDS:
		if not category_ids.has(required):
			issues.append("缺少垃圾桶：%s" % required)
	var items_value: Variant = data.get("items", [])
	if not items_value is Array:
		return {"ok": false, "issues": issues + ["items 必须是数组"]}
	var items: Array = items_value
	if items.size() != 80:
		issues.append("原创生活物品应为 80 件，实际 %s 件" % items.size())
	var item_map := {}
	var counts := {"recyclable": 0, "hazardous": 0, "kitchen": 0, "other": 0}
	for raw in items:
		if not raw is Dictionary:
			issues.append("物品条目不是对象")
			continue
		var item: Dictionary = raw
		var item_id := str(item.get("id", "")).strip_edges()
		if item_id.is_empty() or item_map.has(item_id):
			issues.append("物品 ID 为空或重复：%s" % item_id)
			continue
		item_map[item_id] = item
		var bin_id := str(item.get("bin", ""))
		if not category_ids.has(bin_id):
			issues.append("%s 的垃圾桶无效" % item_id)
		else:
			counts[bin_id] = int(counts[bin_id]) + 1
		if str(item.get("name", "")).strip_edges().is_empty():
			issues.append("%s 缺少名字" % item_id)
		if str(item.get("explanation", "")).strip_edges().is_empty():
			issues.append("%s 缺少解释" % item_id)
		if str(item.get("art", "")).strip_edges().is_empty():
			issues.append("%s 缺少原创造型提示" % item_id)
	for required in CATEGORY_IDS:
		if int(counts.get(required, 0)) < 16:
			issues.append("%s 类物品太少" % required)
	var templates_value: Variant = data.get("templates", {})
	if not templates_value is Dictionary or templates_value.is_empty():
		issues.append("缺少关卡模板定义")
	var templates: Dictionary = templates_value if templates_value is Dictionary else {}
	var levels_value: Variant = data.get("levels", [])
	if not levels_value is Array:
		return {"ok": false, "issues": issues + ["levels 必须是数组"]}
	var levels: Array = levels_value
	if levels.size() != 30:
		issues.append("垃圾分类应共有 30 关，实际 %s 关" % levels.size())
	var mode_counts := {"adventure": 0, "classic": 0}
	var band_counts := {
		"adventure": {"easy": 0, "normal": 0, "challenge": 0},
		"classic": {"easy": 0, "normal": 0, "challenge": 0},
	}
	var numbers := {"adventure": [], "classic": []}
	var referenced := {}
	for raw in levels:
		if not raw is Dictionary:
			issues.append("关卡条目不是对象")
			continue
		var level: Dictionary = raw
		var mode := str(level.get("mode", ""))
		var band := str(level.get("band", ""))
		if not mode_counts.has(mode):
			issues.append("关卡 mode 无效")
			continue
		if not band_counts[mode].has(band):
			issues.append("关卡 band 无效")
			continue
		mode_counts[mode] = int(mode_counts[mode]) + 1
		band_counts[mode][band] = int(band_counts[mode][band]) + 1
		numbers[mode].append(int(level.get("levelNumber", 0)))
		if not templates.has(str(level.get("template", ""))):
			issues.append("%s 缺少有效模板" % str(level.get("id", "")))
		for item_id in level.get("items", []) if level.get("items") is Array else []:
			referenced[str(item_id)] = true
		var validation := validate_level(level, categories, item_map)
		for issue in validation.get("issues", []):
			issues.append("%s：%s" % [str(level.get("id", "")), str(issue)])
		var replay := verify_level(level, categories, item_map)
		if not bool(replay.get("ok", false)):
			issues.append("%s：%s" % [str(level.get("id", "")), str(replay.get("message", "固定解失败"))])
	if mode_counts["adventure"] != 24:
		issues.append("单人垃圾分类应为 24 关，实际 %s 关" % mode_counts["adventure"])
	if mode_counts["classic"] != 6:
		issues.append("双人合作垃圾分类应为 6 关，实际 %s 关" % mode_counts["classic"])
	for mode in ["adventure", "classic"]:
		for band in ["easy", "normal", "challenge"]:
			var expected := 8 if mode == "adventure" else 2
			if int(band_counts[mode][band]) != expected:
				issues.append("%s %s 垃圾分类应为 %s 关，实际 %s 关" % [mode, band, expected, band_counts[mode][band]])
		var mode_numbers: Array = numbers[mode]
		mode_numbers.sort()
		for index in mode_numbers.size():
			if int(mode_numbers[index]) != index + 1:
				issues.append("%s 的 levelNumber 必须连续" % mode)
				break
	for item_id in item_map:
		if not referenced.has(item_id):
			issues.append("物品 %s 从未出现在关卡中" % item_id)
	return {"ok": issues.is_empty(), "issues": issues}


static func validate_level(level: Dictionary, categories: Array, item_map: Dictionary) -> Dictionary:
	var issues: Array[String] = []
	var level_id := str(level.get("id", "")).strip_edges()
	if level_id.is_empty():
		issues.append("缺少关卡 ID")
	if str(level.get("mode", "")) not in ["adventure", "classic"]:
		issues.append("mode 必须是 adventure 或 classic")
	var band := str(level.get("band", ""))
	if band not in ["easy", "normal", "challenge"]:
		issues.append("band 无效")
	var age := int(level.get("minAge", 0))
	if age < 4 or age > 12:
		issues.append("minAge 必须在 4–12 岁")
	elif band == "easy" and age > 6:
		issues.append("easy 的 minAge 应为 4–6")
	elif band == "normal" and (age < 7 or age > 9):
		issues.append("normal 的 minAge 应为 7–9")
	elif band == "challenge" and age < 10:
		issues.append("challenge 的 minAge 应为 10–12")
	if int(level.get("levelNumber", 0)) <= 0:
		issues.append("levelNumber 必须大于 0")
	if str(level.get("title", "")).strip_edges().is_empty():
		issues.append("缺少标题")
	if str(level.get("hint", "")).strip_edges().is_empty():
		issues.append("缺少提示")
	if str(level.get("narration", "")).strip_edges().is_empty():
		issues.append("缺少朗读文本")
	var category_ids := {}
	for category in categories:
		if category is Dictionary:
			category_ids[str(category.get("id", ""))] = true
	var items_value: Variant = level.get("items", [])
	var solution_value: Variant = level.get("solution", [])
	if not items_value is Array or items_value.size() < 4 or items_value.size() > 12:
		issues.append("每关应有 4–12 件物品")
		return {"ok": false, "issues": issues}
	if not solution_value is Array or solution_value.size() != items_value.size():
		issues.append("固定解必须与物品数量一致")
		return {"ok": false, "issues": issues}
	var seen := {}
	for index in items_value.size():
		var item_id := str(items_value[index])
		if seen.has(item_id):
			issues.append("同一关物品不能重复：%s" % item_id)
		seen[item_id] = true
		var item_value: Variant = item_map.get(item_id)
		if not item_value is Dictionary:
			issues.append("关卡引用了不存在的物品：%s" % item_id)
			continue
		var item: Dictionary = item_value
		var bin_id := str(solution_value[index])
		if not category_ids.has(bin_id):
			issues.append("%s 的固定解垃圾桶无效" % item_id)
		if str(item.get("bin", "")) != bin_id:
			issues.append("%s 的固定解与物品类别不一致" % item_id)
	return {"ok": issues.is_empty(), "issues": issues}


static func verify_level(level: Dictionary, categories: Array, item_map: Dictionary) -> Dictionary:
	if not level.get("items") is Array or not level.get("solution") is Array:
		return {"ok": false, "message": "关卡缺少 items 或 solution"}
	var players := [{
		"id": "garbage-check",
		"name": "分类小助手",
		"age": 8,
		"avatar": "🦊",
		"color": "#4f7f71",
	}]
	if str(level.get("mode", "")) == "classic":
		players.append({
			"id": "garbage-check-two",
			"name": "环保伙伴",
			"age": 9,
			"avatar": "🐼",
			"color": "#c17845",
		})
	var sim = GarbageSortRules.new()
	sim.create_session({
		"gameId": "garbage_sort",
		"modeId": str(level.get("mode", "adventure")),
		"players": players,
		"levelId": int(level.get("levelNumber", 1)),
		"levelNumber": int(level.get("levelNumber", 1)),
		"level": level,
		"categories": categories,
		"itemCatalog": item_map,
		"seed": 9,
	})
	if str(sim.state.get("phase", "")) != "sorting":
		return {"ok": false, "message": str(sim.state.get("reason", "固定解无法开始"))}
	for value in level.solution:
		var sorted: Dictionary = sim.handle_input({"type": "sort", "binId": str(value)})
		if not bool(sorted.get("ok", false)) or not bool(sorted.get("correct", false)):
			return {"ok": false, "message": "固定解有一次分类不正确"}
		var next: Dictionary = sim.handle_input({"type": "next"})
		if not bool(next.get("ok", false)):
			return {"ok": false, "message": "固定解无法继续下一件"}
	if str(sim.state.get("phase", "")) != "finished":
		return {"ok": false, "message": "固定解结束后仍未完成"}
	var summary: Dictionary = sim.result()
	if int(summary.get("mistakes", 0)) != 0 or int(summary.get("stars", 0)) != 3:
		return {"ok": false, "message": "固定解没有拿到三星"}
	return {"ok": true, "result": summary}


static func _category(categories: Array, category_id: String) -> Dictionary:
	for value in categories:
		if value is Dictionary and str(value.get("id", "")) == category_id:
			return value.duplicate(true)
	return {}


static func _category_exists(categories: Array, category_id: String) -> bool:
	for value in categories:
		if value is Dictionary and str(value.get("id", "")) == category_id:
			return true
	return false


static func _clean_feedback(source: Variant, catalog: Dictionary, categories: Array) -> Dictionary:
	if not source is Dictionary:
		return {}
	var feedback: Dictionary = source
	var item_id := str(feedback.get("itemId", ""))
	var item_value: Variant = catalog.get(item_id)
	if not item_value is Dictionary:
		return {}
	var item: Dictionary = item_value
	var chosen := str(feedback.get("chosenBin", ""))
	var correct_bin := str(feedback.get("correctBin", ""))
	if not _category_exists(categories, chosen) or not _category_exists(categories, correct_bin):
		return {}
	if correct_bin != str(item.get("bin", "")) or bool(feedback.get("correct", false)) != (chosen == correct_bin):
		return {}
	return {
		"itemId": item_id,
		"itemName": str(item.get("name", "")),
		"itemArt": str(item.get("art", "object")),
		"chosenBin": chosen,
		"correctBin": correct_bin,
		"correct": chosen == correct_bin,
		"explanation": str(item.get("explanation", "")),
		"categoryName": str(_category(categories, correct_bin).get("name", "正确垃圾桶")),
	}


static func _stars(mistakes: int) -> int:
	return 3 if mistakes == 0 else 2 if mistakes <= 1 else 1


static func _numeric(value: Variant) -> bool:
	if value is int or value is float:
		return is_finite(float(value))
	if value is String:
		return value.is_valid_float()
	return false


static func _integer(value: Variant, fallback: int = 0) -> int:
	if value is int:
		return int(value)
	if value is float and is_finite(value):
		return int(value)
	if value is String and value.is_valid_float():
		return int(value.to_float())
	return fallback
