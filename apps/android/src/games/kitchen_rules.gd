class_name KitchenRules
extends GameSession

const KITCHEN_VERSION := 1


func create_session(context: Dictionary) -> Dictionary:
	super.create_session(context)
	var level: Dictionary = context.get("level", {}).duplicate(true) if context.get("level") is Dictionary else {}
	var ingredients: Array = context.get("ingredientCatalog", []).duplicate(true) if context.get("ingredientCatalog") is Array else []
	var tools: Array = context.get("toolCatalog", []).duplicate(true) if context.get("toolCatalog") is Array else []
	var steps: Array = level.get("steps", []).duplicate(true) if level.get("steps") is Array else []
	state.merge({
		"kitchenVersion": KITCHEN_VERSION,
		"phase": "cooking",
		"levelId": int(context.get("levelId", level.get("levelNumber", 1))),
		"levelNumber": int(context.get("levelNumber", level.get("levelNumber", 1))),
		"levelData": level,
		"ingredientCatalog": ingredients,
		"toolCatalog": tools,
		"stepsData": steps,
		"currentStepIndex": 0,
		"doneSteps": [],
		"feedback": {},
		"currentPlayer": 0,
		"score": 0,
		"combo": 0,
		"maxCombo": 0,
		"mistakes": 0,
		"hints": 0,
		"stars": 0,
		"reported": false,
		"view": "kitchen",
	}, true)
	var validation := validate_level(level, ingredients, tools, context.get("templates", {}))
	if not bool(validation.get("ok", false)):
		state.phase = "empty"
		state.reason = "这张菜谱还没有准备好。"
		return state
	if str(state.modeId) != str(level.get("mode", state.modeId)):
		state.phase = "empty"
		state.reason = "菜谱与当前玩法不一致。"
		return state
	var expected_players := 2 if str(state.modeId) == "classic" else 1
	if state.players.size() != expected_players or steps.is_empty():
		state.phase = "empty"
		state.reason = "厨房人数或菜谱步骤不正确。"
	return state


func restore(value: Dictionary) -> bool:
	if int(value.get("kitchenVersion", 0)) != KITCHEN_VERSION:
		return false
	if not super.restore(value):
		return false
	if str(state.get("gameId", "")) != "kitchen":
		return false
	if not (str(state.get("phase", "")) in ["cooking", "feedback", "finished"]):
		return false
	if not state.get("levelData") is Dictionary or not state.get("stepsData") is Array:
		return false
	if not state.get("ingredientCatalog") is Array or not state.get("toolCatalog") is Array:
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
	var level_check := validate_level(level, state.ingredientCatalog, state.toolCatalog, {})
	if not bool(level_check.get("ok", false)):
		return false
	var steps: Array = state.stepsData
	if steps != level.get("steps", []):
		return false
	if steps.is_empty():
		return false
	var done_value: Variant = state.get("doneSteps", [])
	if not done_value is Array:
		return false
	var done_steps: Array = done_value
	if done_steps.size() > steps.size():
		return false
	for index in done_steps.size():
		var done_value_entry: Variant = done_steps[index]
		if not done_value_entry is Dictionary:
			return false
		var done: Dictionary = done_value_entry
		if not _numeric(done.get("stepIndex", -1)) or int(done.stepIndex) != index:
			return false
		var step: Dictionary = steps[index]
		if str(done.get("kind", "")) != str(step.get("kind", "")):
			return false
		if not _numeric(done.get("playerIndex", -1)) or int(done.playerIndex) < 0 or int(done.playerIndex) >= state.players.size():
			return false
		if not bool(done.get("correct", false)):
			return false
	var current_step := int(state.get("currentStepIndex", -1))
	if current_step < 0 or current_step > steps.size():
		return false
	var phase := str(state.phase)
	if phase == "cooking":
		if current_step != done_steps.size() or current_step >= steps.size():
			return false
	elif phase == "feedback":
		if done_steps.is_empty() or current_step != done_steps.size() - 1:
			return false
	elif phase == "finished":
		if done_steps.size() != steps.size() or current_step < steps.size():
			return false
	state.currentPlayer = clampi(_integer(state.get("currentPlayer", 0)), 0, state.players.size() - 1)
	state.currentStepIndex = current_step
	state.doneSteps = done_steps
	state.score = maxi(0, _integer(state.get("score", 0)))
	state.combo = maxi(0, _integer(state.get("combo", 0)))
	state.maxCombo = maxi(int(state.get("maxCombo", 0)), int(state.combo))
	state.mistakes = maxi(0, _integer(state.get("mistakes", 0)))
	state.hints = maxi(0, _integer(state.get("hints", 0)))
	state.feedback = _clean_feedback(state.get("feedback", {}), steps, state.ingredientCatalog, state.toolCatalog)
	if phase == "feedback" and state.feedback.is_empty():
		return false
	if phase != "feedback":
		state.feedback = {}
	state.stars = _stars(int(state.mistakes)) if phase == "finished" else 0
	state.reported = bool(state.get("reported", false))
	return true


func handle_input(action: Dictionary) -> Dictionary:
	var phase := str(state.get("phase", ""))
	if phase in ["empty", "finished"]:
		return {"ok": false, "message": "这张菜谱已经完成啦。"}
	if str(action.get("type", "")) == "next":
		return _next()
	if phase != "cooking":
		return {"ok": false, "message": "先看看刚才的菜谱解释，再继续。"}
	var step := current_step()
	if step.is_empty():
		return {"ok": false}
	var kind := str(action.get("type", ""))
	var target_ok := false
	var target_label := ""
	match str(step.get("kind", "")):
		"grab":
			if kind != "grab":
				return _wrong(step, "这一步先从食材架拿东西。")
			var ingredient_id := str(action.get("ingredientId", ""))
			target_ok = ingredient_id == str(step.get("ingredient", ""))
			target_label = _ingredient(ingredient_id).get("name", "食材")
			if not target_ok:
				return _wrong(step, "先看看菜谱上要点哪一种食材。")
		"process":
			if kind != "process":
				return _wrong(step, "这一步要加工，去加工台选一个动作。")
			var tool_id := str(action.get("toolId", ""))
			target_ok = tool_id == str(step.get("tool", ""))
			target_label = _tool(tool_id).get("name", "加工")
			if not target_ok:
				return _wrong(step, "加工方式和菜谱下一格不一样。")
		"plate":
			if kind != "plate":
				return _wrong(step, "菜已经做好了，先装进小盘子。")
			target_ok = true
			target_label = "装盘"
		_:
			return {"ok": false}
	if not target_ok:
		return _wrong(step, "再对照一下菜谱。")
	var player_index := int(state.get("currentPlayer", 0))
	var done: Array = state.get("doneSteps", [])
	done.append({
		"stepIndex": int(state.get("currentStepIndex", 0)),
		"kind": str(step.get("kind", "")),
		"target": target_label,
		"playerIndex": player_index,
		"correct": true,
	})
	state.doneSteps = done
	state.combo = int(state.get("combo", 0)) + 1
	state.maxCombo = maxi(int(state.get("maxCombo", 0)), int(state.combo))
	state.score = int(state.get("score", 0)) + 100 + mini(int(state.combo), 12) * 8
	state.feedback = {
		"stepIndex": int(state.get("currentStepIndex", 0)),
		"kind": str(step.get("kind", "")),
		"title": str(step.get("label", "做好一步")),
		"explanation": str(step.get("explanation", "")),
		"playerIndex": player_index,
		"target": target_label,
	}
	state.phase = "feedback"
	return {
		"ok": true,
		"correct": true,
		"event": "step",
		"feedback": state.feedback.duplicate(true),
	}


func current_step() -> Dictionary:
	var steps: Array = state.get("stepsData", [])
	var index := int(state.get("currentStepIndex", 0))
	if index < 0 or index >= steps.size():
		return {}
	var value: Variant = steps[index]
	return value.duplicate(true) if value is Dictionary else {}


func step_at(index: int) -> Dictionary:
	var steps: Array = state.get("stepsData", [])
	if index < 0 or index >= steps.size() or not steps[index] is Dictionary:
		return {}
	return steps[index].duplicate(true)


func ingredient(ingredient_id: String) -> Dictionary:
	return _ingredient(ingredient_id).duplicate(true)


func tool(tool_id: String) -> Dictionary:
	return _tool(tool_id).duplicate(true)


func recipe_lines() -> Array:
	var result: Array = []
	var steps: Array = state.get("stepsData", [])
	for index in steps.size():
		if steps[index] is Dictionary:
			result.append({
				"index": index,
				"label": str(steps[index].get("label", "做一步")),
				"done": index < int(state.get("doneSteps", []).size()),
			})
	return result


func progress_text() -> String:
	var total := int(state.get("stepsData", []).size())
	var position := mini(int(state.get("doneSteps", []).size()) + 1, total)
	return "第 %s / %s 步" % [position, total]


func result() -> Dictionary:
	if str(state.get("phase", "")) != "finished":
		return {}
	var total := int(state.get("stepsData", []).size())
	return {
		"score": int(state.get("score", 0)),
		"stars": int(state.get("stars", 0)),
		"correct": total,
		"answered": total,
		"mistakes": int(state.get("mistakes", 0)),
		"hints": int(state.get("hints", 0)),
		"maxCombo": int(state.get("maxCombo", 0)),
		"completed": true,
	}


func _wrong(step: Dictionary, message: String) -> Dictionary:
	state.mistakes = int(state.get("mistakes", 0)) + 1
	state.combo = 0
	return {
		"ok": true,
		"correct": false,
		"event": "wrong",
		"message": message,
		"stepLabel": str(step.get("label", "看看菜谱下一格")),
	}


func _next() -> Dictionary:
	if str(state.get("phase", "")) != "feedback":
		return {"ok": false}
	var steps: Array = state.get("stepsData", [])
	var next_index := int(state.get("currentStepIndex", 0)) + 1
	state.currentStepIndex = next_index
	state.feedback = {}
	if state.players.size() > 1:
		state.currentPlayer = (int(state.get("currentPlayer", 0)) + 1) % state.players.size()
	if next_index >= steps.size():
		state.phase = "finished"
		state.stars = _stars(int(state.get("mistakes", 0)))
		return {"ok": true, "finished": true}
	state.phase = "cooking"
	return {"ok": true, "finished": false}


func hint_for_current() -> Dictionary:
	if str(state.get("phase", "")) != "cooking":
		return {}
	state.hints = int(state.get("hints", 0)) + 1
	var step := current_step()
	return {
		"ok": true,
		"hint": str(step.get("hint", "看菜谱发亮的那一步，再选正确的位置。")),
		"stepLabel": str(step.get("label", "按照菜谱下一格")),
	}


func _ingredient(ingredient_id: String) -> Dictionary:
	for value in state.get("ingredientCatalog", []):
		if value is Dictionary and str(value.get("id", "")) == ingredient_id:
			return value
	return {}


func _tool(tool_id: String) -> Dictionary:
	for value in state.get("toolCatalog", []):
		if value is Dictionary and str(value.get("id", "")) == tool_id:
			return value
	return {}


static func validate_catalog(data: Dictionary) -> Dictionary:
	var issues: Array[String] = []
	var ingredients_value: Variant = data.get("ingredients", [])
	if not ingredients_value is Array or ingredients_value.size() < 18:
		return {"ok": false, "issues": ["至少需要 18 种原创食材"]}
	var ingredients: Array = ingredients_value
	var ingredient_map := {}
	for raw in ingredients:
		if not raw is Dictionary:
			issues.append("食材条目不是对象")
			continue
		var ingredient: Dictionary = raw
		var ingredient_id := str(ingredient.get("id", "")).strip_edges()
		if ingredient_id.is_empty() or ingredient_map.has(ingredient_id):
			issues.append("食材 ID 为空或重复")
			continue
		ingredient_map[ingredient_id] = ingredient
		for field in ["name", "art", "color"]:
			if str(ingredient.get(field, "")).strip_edges().is_empty():
				issues.append("%s 缺少 %s" % [ingredient_id, field])
	var tools_value: Variant = data.get("tools", [])
	if not tools_value is Array or tools_value.size() < 5:
		return {"ok": false, "issues": issues + ["至少需要五种加工工具"]}
	var tools: Array = tools_value
	var tool_map := {}
	for raw in tools:
		if not raw is Dictionary:
			issues.append("工具条目不是对象")
			continue
		var tool: Dictionary = raw
		var tool_id := str(tool.get("id", "")).strip_edges()
		if tool_id.is_empty() or tool_map.has(tool_id):
			issues.append("工具 ID 为空或重复")
			continue
		tool_map[tool_id] = tool
		for field in ["name", "verb", "color"]:
			if str(tool.get(field, "")).strip_edges().is_empty():
				issues.append("%s 缺少 %s" % [tool_id, field])
	var templates_value: Variant = data.get("templates", {})
	if not templates_value is Dictionary or templates_value.is_empty():
		return {"ok": false, "issues": issues + ["缺少菜谱模板"]}
	var templates: Dictionary = templates_value
	var levels_value: Variant = data.get("levels", [])
	if not levels_value is Array:
		return {"ok": false, "issues": issues + ["levels 必须是数组"]}
	var levels: Array = levels_value
	if levels.size() != 24:
		issues.append("小小厨房应共有 24 张订单，实际 %s 张" % levels.size())
	var mode_counts := {"adventure": 0, "classic": 0}
	var band_counts := {
		"adventure": {"easy": 0, "normal": 0, "challenge": 0},
		"classic": {"easy": 0, "normal": 0, "challenge": 0},
	}
	var numbers := {"adventure": [], "classic": []}
	var referenced := {}
	for raw in levels:
		if not raw is Dictionary:
			issues.append("订单条目不是对象")
			continue
		var level: Dictionary = raw
		var mode := str(level.get("mode", ""))
		var band := str(level.get("band", ""))
		if not mode_counts.has(mode):
			issues.append("订单 mode 无效")
			continue
		if not band_counts[mode].has(band):
			issues.append("订单 band 无效")
			continue
		mode_counts[mode] = int(mode_counts[mode]) + 1
		band_counts[mode][band] = int(band_counts[mode][band]) + 1
		numbers[mode].append(int(level.get("levelNumber", 0)))
		if not templates.has(str(level.get("template", ""))):
			issues.append("%s 引用了不存在的菜谱模板" % str(level.get("id", "")))
		for ingredient_id in level.get("ingredients", []) if level.get("ingredients") is Array else []:
			referenced[str(ingredient_id)] = true
		var check := validate_level(level, ingredients, tools, templates)
		for issue in check.get("issues", []):
			issues.append("%s：%s" % [str(level.get("id", "")), str(issue)])
		var replay := verify_level(level, ingredients, tools)
		if not bool(replay.get("ok", false)):
			issues.append("%s：%s" % [str(level.get("id", "")), str(replay.get("message", "固定菜谱失败"))])
	if mode_counts["adventure"] != 18:
		issues.append("单人订单应为 18 张，实际 %s 张" % mode_counts["adventure"])
	if mode_counts["classic"] != 6:
		issues.append("双人合作订单应为 6 张，实际 %s 张" % mode_counts["classic"])
	for mode in ["adventure", "classic"]:
		for band in ["easy", "normal", "challenge"]:
			var expected := 6 if mode == "adventure" else 2
			if int(band_counts[mode][band]) != expected:
				issues.append("%s %s 订单应为 %s 张，实际 %s 张" % [mode, band, expected, band_counts[mode][band]])
		var mode_numbers: Array = numbers[mode]
		mode_numbers.sort()
		for index in mode_numbers.size():
			if int(mode_numbers[index]) != index + 1:
				issues.append("%s 的 levelNumber 必须连续" % mode)
				break
	for ingredient_id in ingredient_map:
		if not referenced.has(ingredient_id):
			issues.append("食材 %s 从未出现在订单中" % ingredient_id)
	return {"ok": issues.is_empty(), "issues": issues}


static func validate_level(level: Dictionary, ingredients: Array, tools: Array, templates: Variant = null) -> Dictionary:
	var issues: Array[String] = []
	var level_id := str(level.get("id", "")).strip_edges()
	if level_id.is_empty():
		issues.append("缺少订单 ID")
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
	for field in ["title", "dish", "narration", "hint", "explanation"]:
		if str(level.get(field, "")).strip_edges().is_empty():
			issues.append("缺少 %s" % field)
	if (
		not str(level.get("template", "")).strip_edges().is_empty()
		and templates is Dictionary
		and not templates.is_empty()
		and not templates.has(str(level.template))
	):
		issues.append("引用了不存在的模板")
	var ingredient_map := {}
	for ingredient in ingredients:
		if ingredient is Dictionary:
			ingredient_map[str(ingredient.get("id", ""))] = ingredient
	var tool_map := {}
	for tool in tools:
		if tool is Dictionary:
			tool_map[str(tool.get("id", ""))] = tool
	var used_value: Variant = level.get("ingredients", [])
	if not used_value is Array or used_value.is_empty():
		issues.append("订单食材不能为空")
		return {"ok": false, "issues": issues}
	var used := {}
	for ingredient_id in used_value:
		var key := str(ingredient_id)
		if used.has(key) or not ingredient_map.has(key):
			issues.append("订单食材重复或不存在：%s" % key)
		used[key] = true
	var steps_value: Variant = level.get("steps", [])
	var solution_value: Variant = level.get("solution", [])
	if not steps_value is Array or steps_value.is_empty():
		issues.append("菜谱步骤不能为空")
		return {"ok": false, "issues": issues}
	if not solution_value is Array or solution_value.size() != steps_value.size():
		issues.append("固定解必须覆盖全部菜谱步骤")
		return {"ok": false, "issues": issues}
	var allowed_tools := {}
	var template_value: Variant = null
	if templates is Dictionary:
		template_value = templates.get(str(level.get("template", "")))
	if template_value is Dictionary and template_value.get("allowedTools") is Array:
		for tool_id in template_value.allowedTools:
			allowed_tools[str(tool_id)] = true
	var grabbed := {}
	for index in steps_value.size():
		var step: Dictionary = steps_value[index]
		var kind := str(step.get("kind", ""))
		if kind not in ["grab", "process", "plate"]:
			issues.append("第 %s 步 kind 无效" % (index + 1))
			continue
		if index == 0 and kind != "grab":
			issues.append("第一步必须先拿食材")
		if kind == "grab":
			var ingredient_id := str(step.get("ingredient", ""))
			if not ingredient_map.has(ingredient_id) or not used.has(ingredient_id):
				issues.append("第 %s 步食材无效" % (index + 1))
			grabbed[ingredient_id] = true
		elif kind == "process":
			var tool_id := str(step.get("tool", ""))
			if not tool_map.has(tool_id):
				issues.append("第 %s 步工具无效" % (index + 1))
			elif not allowed_tools.is_empty() and not allowed_tools.has(tool_id):
				issues.append("第 %s 步工具不在模板里" % (index + 1))
			var process_ingredient := str(step.get("ingredient", ""))
			if not process_ingredient.is_empty() and (not used.has(process_ingredient) or not grabbed.has(process_ingredient)):
				issues.append("第 %s 步加工了还没拿取的食材" % (index + 1))
		elif kind == "plate":
			if index != steps_value.size() - 1:
				issues.append("装盘必须是最后一步")
		if str(step.get("label", "")).strip_edges().is_empty():
			issues.append("第 %s 步缺少标签" % (index + 1))
		if str(step.get("explanation", "")).strip_edges().is_empty():
			issues.append("第 %s 步缺少解释" % (index + 1))
		var token := str(solution_value[index])
		var expected_token := "plate"
		if kind == "grab":
			expected_token = "grab:%s" % str(step.get("ingredient", ""))
		elif kind == "process":
			expected_token = "process:%s" % str(step.get("tool", ""))
		if token != expected_token:
			issues.append("第 %s 步固定解不一致" % (index + 1))
	if steps_value.size() > 0 and str((steps_value[-1] as Dictionary).get("kind", "")) != "plate":
		issues.append("最后一步必须装盘")
	var recipe_value: Variant = level.get("recipe", [])
	if not recipe_value is Array or recipe_value.size() != steps_value.size():
		issues.append("recipe 说明必须逐步对应")
	return {"ok": issues.is_empty(), "issues": issues}


static func verify_level(level: Dictionary, ingredients: Array, tools: Array) -> Dictionary:
	var steps_value: Variant = level.get("steps", [])
	if not steps_value is Array or steps_value.is_empty():
		return {"ok": false, "message": "没有菜谱步骤"}
	var players := [{
		"id": "kitchen-check",
		"name": "小厨师",
		"age": 8,
		"avatar": "🦊",
		"color": "#a35a2d",
	}]
	if str(level.get("mode", "")) == "classic":
		players.append({
			"id": "kitchen-check-two",
			"name": "厨房伙伴",
			"age": 9,
			"avatar": "🐼",
			"color": "#5f806e",
		})
	var sim = KitchenRules.new()
	sim.create_session({
		"gameId": "kitchen",
		"modeId": str(level.get("mode", "adventure")),
		"players": players,
		"levelId": int(level.get("levelNumber", 1)),
		"levelNumber": int(level.get("levelNumber", 1)),
		"level": level,
		"ingredientCatalog": ingredients,
		"toolCatalog": tools,
		"seed": 11,
	})
	if str(sim.state.get("phase", "")) != "cooking":
		return {"ok": false, "message": str(sim.state.get("reason", "固定解无法开始"))}
	for step_value in steps_value:
		var step: Dictionary = step_value
		var action := {"type": str(step.get("kind", ""))}
		if str(step.get("kind", "")) == "grab":
			action.ingredientId = str(step.get("ingredient", ""))
		elif str(step.get("kind", "")) == "process":
			action.toolId = str(step.get("tool", ""))
		var acted: Dictionary = sim.handle_input(action)
		if not bool(acted.get("ok", false)) or not bool(acted.get("correct", false)):
			return {"ok": false, "message": "固定菜谱中有一  步没有按顺序完成"}
		var next: Dictionary = sim.handle_input({"type": "next"})
		if not bool(next.get("ok", false)):
			return {"ok": false, "message": "固定菜谱无法继续"}
	if str(sim.state.get("phase", "")) != "finished":
		return {"ok": false, "message": "固定菜谱完成后仍未结束"}
	var summary: Dictionary = sim.result()
	if int(summary.get("mistakes", 0)) != 0 or int(summary.get("stars", 0)) != 3:
		return {"ok": false, "message": "固定菜谱没有拿到三星"}
	return {"ok": true, "result": summary}


static func _clean_feedback(source: Variant, steps: Array, ingredients: Array, tools: Array) -> Dictionary:
	if not source is Dictionary:
		return {}
	var feedback: Dictionary = source
	var index := _integer(feedback.get("stepIndex", -1), -1)
	if index < 0 or index >= steps.size() or not steps[index] is Dictionary:
		return {}
	var step: Dictionary = steps[index]
	var kind := str(feedback.get("kind", ""))
	if kind != str(step.get("kind", "")):
		return {}
	var result := {
		"stepIndex": index,
		"kind": str(step.get("kind", "")),
		"title": str(step.get("label", "做好一步")),
		"explanation": str(step.get("explanation", "")),
		"playerIndex": maxi(0, _integer(feedback.get("playerIndex", 0))),
		"target": str(feedback.get("target", "")),
	}
	return result


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
