class_name RhythmRules
extends GameSession

const RHYTHM_VERSION := 1
const LANE_COUNT := 4
const PERFECT_WINDOW := 0.095
const GOOD_WINDOW := 0.205
const COUNTDOWN_SECONDS := 2.4
const HOLD_RELEASE_RATIO := 0.80


func create_session(context: Dictionary) -> Dictionary:
	super.create_session(context)
	var chart: Dictionary = context.get("chart", {}).duplicate(true) if context.get("chart") is Dictionary else {}
	state.merge({
		"rhythmVersion": RHYTHM_VERSION,
		"phase": "playing",
		"levelId": int(context.get("levelId", chart.get("levelNumber", 1))),
		"levelNumber": int(context.get("levelNumber", chart.get("levelNumber", 1))),
		"chartId": str(chart.get("id", "")),
		"chart": chart,
		"notes": _new_note_states(chart),
		"playhead": 0.0,
		"countdown": COUNTDOWN_SECONDS,
		"combo": 0,
		"maxCombo": 0,
		"score": 0,
		"perfect": 0,
		"good": 0,
		"miss": 0,
		"judged": 0,
		"totalNotes": _chart_note_count(chart),
		"accuracy": 0.0,
		"stars": 0,
		"holdLanes": {},
		"feedback": {},
		"strayTaps": 0,
		"reported": false,
		"view": "play",
	}, true)
	var validation := validate_chart(chart, false)
	if not bool(validation.get("ok", false)):
		state.phase = "empty"
		state.reason = "这张节奏谱没有准备好。"
		return state
	if str(state.modeId) != str(chart.get("mode", state.modeId)):
		state.phase = "empty"
		state.reason = "节奏谱与当前玩法不一致。"
	return state


func restore(value: Dictionary) -> bool:
	if int(value.get("rhythmVersion", 0)) != RHYTHM_VERSION:
		return false
	if not super.restore(value):
		return false
	if not (str(state.get("phase", "")) in ["playing", "finished"]):
		return false
	if not state.get("chart") is Dictionary:
		return false
	var chart: Dictionary = state.chart
	var chart_check := validate_chart(chart, false)
	if not bool(chart_check.get("ok", false)):
		return false
	if str(state.get("gameId", "")) != "rhythm":
		return false
	if str(state.get("modeId", "")) != str(chart.get("mode", "")):
		return false
	if int(state.get("levelId", -1)) != int(chart.get("levelNumber", -2)):
		return false
	if int(state.get("levelNumber", -1)) != int(chart.get("levelNumber", -2)):
		return false
	if str(state.get("chartId", "")) != str(chart.get("id", "")):
		return false
	if int(state.get("rhythmVersion", 0)) != int(chart.get("schemaVersion", 0)):
		return false
	var expected_players := 2 if str(chart.get("mode", "")) == "classic" else 1
	if state.players.size() != expected_players:
		return false
	var notes: Variant = state.get("notes")
	if not notes is Array or notes.size() != _chart_note_count(chart):
		return false
	var chart_notes := _normalize_notes(chart)
	var active_lanes := {}
	var clean_holds := {}
	for index in notes.size():
		var note_value: Variant = notes[index]
		if not note_value is Dictionary:
			return false
		var note: Dictionary = note_value
		var source: Dictionary = chart_notes[index]
		if not _numeric(note.get("beat")) or not _numeric(note.get("lane")) or not _numeric(note.get("hold")):
			return false
		if not is_equal_approx(float(note.beat), float(source.beat)):
			return false
		if int(note.lane) != int(source.lane):
			return false
		if not is_equal_approx(float(note.hold), float(source.hold)):
			return false
		var status := str(note.get("status", ""))
		if not (status in ["pending", "holding", "hit", "missed"]):
			return false
		if status in ["hit", "missed"]:
			var judgement := str(note.get("judgement", ""))
			if judgement != "miss" and not (judgement in ["perfect", "good"]):
				return false
		if status == "holding":
			note.status = "pending"
			note.judgement = ""
			note.baseJudgement = ""
			note.holdStartedAt = 0.0
			note.hitAt = 0.0
		if not _numeric(note.get("startTime", -1.0)) or float(note.startTime) < -0.001:
			return false
		if not _numeric(note.get("holdStartedAt", 0.0)):
			return false
	if str(state.get("phase", "")) == "finished":
		if not active_lanes.is_empty():
			return false
		for note in notes:
			if str(note.get("status", "")) != "hit" and str(note.get("status", "")) != "missed":
				return false
	var playhead_value: Variant = state.get("playhead", 0.0)
	if not _numeric(playhead_value) or float(playhead_value) < 0.0 or float(playhead_value) > _duration(chart) + 2.0:
		return false
	state.holdLanes = clean_holds
	state.countdown = clampf(_number(state.get("countdown", 0.0), 0.0), 0.0, COUNTDOWN_SECONDS)
	state.playhead = float(playhead_value)
	state.combo = maxi(0, _integer(state.get("combo", 0)))
	state.maxCombo = maxi(state.combo, _integer(state.get("maxCombo", 0)))
	state.score = maxi(0, _integer(state.get("score", 0)))
	state.strayTaps = maxi(0, _integer(state.get("strayTaps", 0)))
	state.totalNotes = notes.size()
	_recount_judgements()
	if str(state.get("phase", "")) == "playing" and int(state.judged) >= int(state.totalNotes):
		return false
	var feedback_value: Variant = state.get("feedback", {})
	if feedback_value is Dictionary:
		state.feedback = _clean_feedback(feedback_value)
	else:
		state.feedback = {}
	state.reported = bool(state.get("reported", false))
	state.stars = _stars_for_accuracy(float(state.accuracy)) if str(state.phase) == "finished" else 0
	return true


func handle_input(action: Dictionary) -> Dictionary:
	if str(state.get("phase", "")) != "playing":
		return {"ok": false, "message": "这张谱已经拍完啦。"}
	if float(state.get("countdown", 0.0)) > 0.0:
		return {"ok": false, "message": "准备好的拍子马上就来。"}
	var kind := str(action.get("type", ""))
	if kind == "press":
		return _press(int(action.get("lane", -1)))
	if kind == "release":
		return _release(int(action.get("lane", -1)))
	if kind == "tap":
		var pressed := _press(int(action.get("lane", -1)))
		if bool(pressed.get("ok", false)) and int(pressed.get("noteIndex", -1)) >= 0:
			var note: Dictionary = state.notes[int(pressed.noteIndex)]
			if float(note.get("hold", 0.0)) <= 0.0:
				return pressed
			return _release(int(action.get("lane", -1)))
		return pressed
	return {"ok": false}


func tick(delta: float) -> bool:
	if str(state.get("phase", "")) != "playing" or delta <= 0.0 or not is_finite(delta):
		return false
	var changed := false
	var remaining := delta
	var countdown_value := maxf(0.0, float(state.get("countdown", 0.0)))
	if countdown_value > 0.0:
		var used := minf(countdown_value, remaining)
		state.countdown = countdown_value - used
		remaining -= used
		changed = true
		if float(state.countdown) > 0.0:
			return changed
	if remaining <= 0.0:
		return changed
	state.playhead = float(state.get("playhead", 0.0)) + remaining
	changed = true
	var playhead := float(state.playhead)
	var notes: Array = state.notes
	var hold_lanes: Dictionary = state.get("holdLanes", {})
	for lane_key in hold_lanes.keys():
		var note_index := int(hold_lanes[lane_key])
		if note_index < 0 or note_index >= notes.size():
			hold_lanes.erase(lane_key)
			continue
		var held_note: Dictionary = notes[note_index]
		if str(held_note.get("status", "")) != "holding":
			hold_lanes.erase(lane_key)
			continue
		var required := float(held_note.get("holdSeconds", 0.0))
		if playhead >= float(held_note.get("startTime", 0.0)) + required:
			_complete_hold(held_note, str(held_note.get("baseJudgement", "good")))
			hold_lanes.erase(lane_key)
			state.feedback = {
				"judgement": str(held_note.get("judgement", "good")),
				"lane": int(held_note.lane),
				"hold": true,
			}
	state.holdLanes = hold_lanes
	for note_value in notes:
		var note: Dictionary = note_value
		if str(note.get("status", "")) != "pending":
			continue
		if playhead > float(note.get("startTime", 0.0)) + GOOD_WINDOW:
			_judge_note(note, "miss")
	if _all_judged():
		_finish()
		changed = true
	return changed


func snapshot() -> Dictionary:
	state.rhythmVersion = RHYTHM_VERSION
	return super.snapshot()


func release_all_holds() -> bool:
	var changed := false
	for note_value in state.get("notes", []):
		if not note_value is Dictionary:
			continue
		var note: Dictionary = note_value
		if str(note.get("status", "")) == "holding":
			note.status = "pending"
			note.judgement = ""
			note.baseJudgement = ""
			note.holdStartedAt = 0.0
			note.hitAt = 0.0
			changed = true
	state.holdLanes = {}
	state.feedback = {}
	return changed


func result() -> Dictionary:
	if str(state.get("phase", "")) != "finished":
		return {}
	return {
		"score": int(state.get("score", 0)),
		"stars": int(state.get("stars", 0)),
		"accuracy": float(state.get("accuracy", 0.0)),
		"perfect": int(state.get("perfect", 0)),
		"good": int(state.get("good", 0)),
		"miss": int(state.get("miss", 0)),
		"maxCombo": int(state.get("maxCombo", 0)),
		"totalNotes": int(state.get("totalNotes", 0)),
		"completed": int(state.get("score", 0)) > 0,
	}


func lane_holding(lane: int) -> bool:
	return state.get("holdLanes", {}).has(str(lane))


func note_start_seconds(note: Dictionary) -> float:
	var bpm := maxf(30.0, _number(state.get("chart", {}).get("bpm", 90.0), 90.0))
	return _number(note.get("beat", 0.0), 0.0) * 60.0 / bpm


func note_hold_seconds(note: Dictionary) -> float:
	var bpm := maxf(30.0, _number(state.get("chart", {}).get("bpm", 90.0), 90.0))
	return _number(note.get("hold", 0.0), 0.0) * 60.0 / bpm


func current_player_name() -> String:
	if state.players.size() > 1:
		return "两位小乐手一起拍"
	if state.players.is_empty():
		return "小乐手"
	return str(state.players[0].get("name", "小乐手"))


func bar_seconds() -> float:
	var chart: Dictionary = state.get("chart", {})
	var bpm := maxf(30.0, _number(chart.get("bpm", 90.0), 90.0))
	var beats := maxi(1, _integer(chart.get("beatsPerBar", 4)))
	return 60.0 / bpm * float(beats)


func _press(lane: int) -> Dictionary:
	if lane < 0 or lane >= LANE_COUNT:
		return {"ok": false}
	if state.get("holdLanes", {}).has(str(lane)):
		return {"ok": false, "message": "这一轨还在长按，等它亮完整。"}
	var playhead := float(state.get("playhead", 0.0))
	var notes: Array = state.notes
	var target_index := -1
	var best_distance := INF
	for index in notes.size():
		var note: Dictionary = notes[index]
		if str(note.get("status", "")) != "pending" or int(note.get("lane", -1)) != lane:
			continue
		var distance := absf(float(note.get("startTime", 0.0)) - playhead)
		if distance <= GOOD_WINDOW and distance < best_distance:
			best_distance = distance
			target_index = index
	if target_index < 0:
		state.combo = 0
		state.strayTaps = int(state.get("strayTaps", 0)) + 1
		state.feedback = {"judgement": "stray", "lane": lane}
		return {"ok": true, "event": "stray", "message": "听一听拍子，不着急。"}
	var note: Dictionary = notes[target_index]
	var judgement := "perfect" if best_distance <= PERFECT_WINDOW else "good"
	if float(note.get("hold", 0.0)) > 0.0:
		note.status = "holding"
		note.baseJudgement = judgement
		note.holdStartedAt = playhead
		note.offset = playhead - float(note.startTime)
		state.holdLanes[str(lane)] = target_index
		state.feedback = {"judgement": judgement, "lane": lane, "holdStart": true}
		return {"ok": true, "event": "hold_start", "noteIndex": target_index, "judgement": judgement}
	_judge_note(note, judgement)
	state.feedback = {"judgement": judgement, "lane": lane, "hold": false}
	if _all_judged():
		_finish()
	return {"ok": true, "event": judgement, "noteIndex": target_index, "judgement": judgement}


func _release(lane: int) -> Dictionary:
	if lane < 0 or lane >= LANE_COUNT:
		return {"ok": false}
	var hold_lanes: Dictionary = state.get("holdLanes", {})
	if not hold_lanes.has(str(lane)):
		return {"ok": false}
	var note_index := int(hold_lanes[str(lane)])
	if note_index < 0 or note_index >= state.notes.size():
		hold_lanes.erase(str(lane))
		return {"ok": false}
	var note: Dictionary = state.notes[note_index]
	var held := maxf(0.0, float(state.get("playhead", 0.0)) - float(note.get("holdStartedAt", 0.0)))
	var required := maxf(0.0, float(note.get("holdSeconds", 0.0)))
	hold_lanes.erase(str(lane))
	state.holdLanes = hold_lanes
	if required > 0.0 and held + 0.001 >= required * HOLD_RELEASE_RATIO:
		_complete_hold(note, str(note.get("baseJudgement", "good")))
		state.feedback = {
			"judgement": str(note.get("judgement", "good")),
			"lane": lane,
			"hold": true,
		}
		if _all_judged():
			_finish()
		return {"ok": true, "event": "hold_done", "noteIndex": note_index, "judgement": str(note.get("judgement", "good"))}
	_judge_note(note, "miss")
	state.feedback = {"judgement": "miss", "lane": lane, "hold": true}
	if _all_judged():
		_finish()
	return {"ok": true, "event": "miss", "noteIndex": note_index, "judgement": "miss", "message": "长按提早松手了，再听一拍。"}


func _complete_hold(note: Dictionary, judgement: String) -> void:
	note.status = "hit"
	note.judgement = judgement
	note.hitAt = float(state.get("playhead", 0.0))
	_register_judgement(judgement, maxi(1, int(round(float(note.get("holdSeconds", 0.0)) * 220.0))))


func _judge_note(note: Dictionary, judgement: String) -> void:
	if str(note.get("status", "")) in ["hit", "missed"]:
		return
	note.status = "hit" if judgement != "miss" else "missed"
	note.judgement = judgement
	note.hitAt = float(state.get("playhead", 0.0))
	_register_judgement(judgement, 0)
	if judgement == "miss":
		state.feedback = {"judgement": "miss", "lane": int(note.get("lane", 0)), "hold": false}


func _register_judgement(judgement: String, bonus: int = 0) -> void:
	state.judged = int(state.get("judged", 0)) + 1
	if judgement == "perfect":
		state.perfect = int(state.get("perfect", 0)) + 1
		state.combo = int(state.get("combo", 0)) + 1
		var combo_bonus := mini(int(state.combo), 60) * 10
		state.score = int(state.get("score", 0)) + 1000 + combo_bonus + bonus
	elif judgement == "good":
		state.good = int(state.get("good", 0)) + 1
		state.combo = int(state.get("combo", 0)) + 1
		var combo_bonus := mini(int(state.combo), 60) * 6
		state.score = int(state.get("score", 0)) + 620 + combo_bonus + bonus
	else:
		state.miss = int(state.get("miss", 0)) + 1
		state.combo = 0
	state.maxCombo = maxi(int(state.get("maxCombo", 0)), int(state.combo))
	state.accuracy = _accuracy()


func _all_judged() -> bool:
	for note_value in state.get("notes", []):
		var note: Dictionary = note_value
		if not (str(note.get("status", "")) in ["hit", "missed"]):
			return false
	return true


func _finish() -> void:
	state.phase = "finished"
	state.combo = 0
	state.accuracy = _accuracy()
	state.stars = _stars_for_accuracy(float(state.accuracy))
	state.score = int(state.get("score", 0))
	state.feedback = {}
	state.holdLanes = {}


func _accuracy() -> float:
	var total := maxi(1, int(state.get("totalNotes", 0)))
	return clampf((float(state.get("perfect", 0)) + float(state.get("good", 0)) * 0.65) / float(total), 0.0, 1.0)


func _recount_judgements() -> void:
	var perfect := 0
	var good := 0
	var miss := 0
	for note_value in state.get("notes", []):
		var note: Dictionary = note_value
		var judgement := str(note.get("judgement", ""))
		if judgement == "perfect":
			perfect += 1
		elif judgement == "good":
			good += 1
		elif judgement == "miss":
			miss += 1
	state.perfect = perfect
	state.good = good
	state.miss = miss
	state.judged = perfect + good + miss
	state.accuracy = _accuracy()


func _clean_feedback(source: Dictionary) -> Dictionary:
	var judgement := str(source.get("judgement", ""))
	if not (judgement in ["perfect", "good", "miss", "stray"]):
		return {}
	var result := {"judgement": judgement}
	if _numeric(source.get("lane", -1)):
		result.lane = clampi(int(source.lane), 0, LANE_COUNT - 1)
	if source.has("hold") and typeof(source.get("hold")) == TYPE_BOOL:
		result.hold = bool(source.hold)
	return result


func _new_note_states(chart: Dictionary) -> Array:
	var result: Array = []
	var bpm := maxf(30.0, _number(chart.get("bpm", 90.0), 90.0))
	for raw in chart.get("notes", []) if chart.get("notes") is Array else []:
		if not raw is Array or raw.size() != 3:
			continue
		var beat := float(raw[0])
		var lane := int(raw[1])
		var hold_beats := float(raw[2])
		result.append({
			"beat": beat,
			"lane": lane,
			"hold": hold_beats,
			"startTime": beat * 60.0 / bpm,
			"holdSeconds": hold_beats * 60.0 / bpm,
			"status": "pending",
			"judgement": "",
			"baseJudgement": "",
			"startedAt": 0.0,
			"holdStartedAt": 0.0,
			"hitAt": 0.0,
			"offset": 0.0,
		})
	return result


static func validate_catalog(data: Dictionary) -> Dictionary:
	var issues: Array[String] = []
	var charts_value: Variant = data.get("charts", [])
	if not charts_value is Array:
		return {"ok": false, "issues": ["rhythm.json 的 charts 必须是数组"]}
	var charts: Array = charts_value
	var template_value: Variant = data.get("templates", {})
	var templates: Dictionary = template_value if template_value is Dictionary else {}
	var ids := {}
	var mode_counts := {"adventure": 0, "classic": 0}
	var band_counts := {
		"adventure": {"easy": 0, "normal": 0, "challenge": 0},
		"classic": {"easy": 0, "normal": 0, "challenge": 0},
	}
	var number_sets := {"adventure": [], "classic": []}
	for raw in charts:
		if not raw is Dictionary:
			issues.append("存在不是对象的节奏谱")
			continue
		var chart: Dictionary = raw
		var id := str(chart.get("id", "")).strip_edges()
		if id.is_empty() or ids.has(id):
			issues.append("节奏谱 ID 为空或重复：%s" % id)
		ids[id] = true
		var mode := str(chart.get("mode", ""))
		var band := str(chart.get("band", ""))
		if not mode_counts.has(mode):
			issues.append("%s 的 mode 无效" % id)
			continue
		if not band_counts[mode].has(band):
			issues.append("%s 的 band 无效" % id)
			continue
		mode_counts[mode] = int(mode_counts[mode]) + 1
		band_counts[mode][band] = int(band_counts[mode][band]) + 1
		number_sets[mode].append(int(chart.get("levelNumber", 0)))
		if not templates.is_empty() and not templates.has(str(chart.get("template", ""))):
			issues.append("%s 引用了不存在的模板" % id)
		var check := validate_chart(chart)
		for issue in check.get("issues", []):
			issues.append("%s：%s" % [id, str(issue)])
	if mode_counts["adventure"] != 18:
		issues.append("单人节奏谱应为 18 张，实际 %s 张" % mode_counts["adventure"])
	if mode_counts["classic"] != 6:
		issues.append("双人合拍谱应为 6 张，实际 %s 张" % mode_counts["classic"])
	for mode in ["adventure", "classic"]:
		for band in ["easy", "normal", "challenge"]:
			var expected := 6 if mode == "adventure" else 2
			if int(band_counts[mode][band]) != expected:
				issues.append("%s %s 谱应为 %s 张，实际 %s 张" % [mode, band, expected, band_counts[mode][band]])
		var numbers: Array = number_sets[mode]
		numbers.sort()
		for index in numbers.size():
			if int(numbers[index]) != index + 1:
				issues.append("%s 的 levelNumber 必须从 1 连续编号" % mode)
				break
	return {"ok": issues.is_empty(), "issues": issues}


static func validate_chart(chart: Dictionary, check_fixed_solution: bool = true) -> Dictionary:
	var issues: Array[String] = []
	var id := str(chart.get("id", "")).strip_edges()
	if id.is_empty():
		issues.append("缺少谱面 ID")
	if int(chart.get("schemaVersion", 0)) != RHYTHM_VERSION:
		issues.append("谱面 schemaVersion 不是 %s" % RHYTHM_VERSION)
	if not (str(chart.get("mode", "")) in ["adventure", "classic"]):
		issues.append("mode 必须是 adventure 或 classic")
	var band := str(chart.get("band", ""))
	if not (band in ["easy", "normal", "challenge"]):
		issues.append("band 无效")
	var age := int(chart.get("minAge", 0))
	if age < 4 or age > 12:
		issues.append("minAge 必须在 4–12 岁之间")
	elif band == "easy" and age > 6:
		issues.append("easy 谱的 minAge 应为 4–6")
	elif band == "normal" and (age < 7 or age > 9):
		issues.append("normal 谱的 minAge 应为 7–9")
	elif band == "challenge" and age < 10:
		issues.append("challenge 谱的 minAge 应为 10–12")
	if int(chart.get("lanes", 0)) != LANE_COUNT:
		issues.append("必须正好是四轨")
	var bpm := _number(chart.get("bpm", 0.0), 0.0)
	if bpm < 45.0 or bpm > 190.0:
		issues.append("BPM 超出儿童节奏练习范围")
	var beats := _number(chart.get("totalBeats", 0.0), 0.0)
	if beats <= 0.0:
		issues.append("totalBeats 必须大于 0")
	var title := str(chart.get("title", "")).strip_edges()
	if title.is_empty():
		issues.append("缺少标题")
	if str(chart.get("hint", "")).strip_edges().is_empty():
		issues.append("缺少 hint")
	if str(chart.get("narration", "")).strip_edges().is_empty():
		issues.append("缺少 narration")
	var notes_value: Variant = chart.get("notes", [])
	if not notes_value is Array or notes_value.is_empty():
		issues.append("notes 不能为空")
		return {"ok": false, "issues": issues}
	var notes: Array = notes_value
	var normalized: Array = []
	var lane_end := {0: -999.0, 1: -999.0, 2: -999.0, 3: -999.0}
	var last_beat := -999.0
	var last_lane := -1
	for index in notes.size():
		var raw: Variant = notes[index]
		if not raw is Array or raw.size() != 3:
			issues.append("第 %s 个音符不是 [beat,lane,hold]" % (index + 1))
			continue
		var beat := _number(raw[0], -1.0)
		var lane := _integer(raw[1], -1)
		var hold := _number(raw[2], -1.0)
		if beat < 0.0 or beat >= beats:
			issues.append("第 %s 个音符的拍点越界" % (index + 1))
		if lane < 0 or lane >= LANE_COUNT:
			issues.append("第 %s 个音符的轨道越界" % (index + 1))
		if hold < 0.0 or hold > 4.0:
			issues.append("第 %s 个音符的长按拍数越界" % (index + 1))
		if beat < last_beat - 0.0001 or (is_equal_approx(beat, last_beat) and lane < last_lane):
			issues.append("notes 必须按拍点和轨道排序")
		last_beat = beat
		last_lane = lane
		var start := beat * 60.0 / maxf(45.0, bpm)
		var end := start + hold * 60.0 / maxf(45.0, bpm)
		if start < float(lane_end.get(lane, -999.0)) + 0.03:
			issues.append("第 %s 个音符与前一个长按重叠" % (index + 1))
		lane_end[lane] = end
		normalized.append({"beat": beat, "lane": lane, "hold": hold})
	var solution_value: Variant = chart.get("solution", [])
	if not solution_value is Array or solution_value.size() != notes.size():
		issues.append("solution 必须覆盖全部音符")
	else:
		var seen := {}
		for value in solution_value:
			var note_index := _integer(value, -1)
			if note_index < 0 or note_index >= notes.size() or seen.has(note_index):
				issues.append("solution 含有越界或重复的音符序号")
				break
			seen[note_index] = true
		if seen.size() == notes.size():
			var previous_beat := -INF
			for value in solution_value:
				var note: Dictionary = normalized[int(value)]
				if float(note.beat) < previous_beat - 0.0001:
					issues.append("solution 必须按时间先后排列")
					break
				previous_beat = float(note.beat)
	if check_fixed_solution:
		var replay := verify_solution(chart)
		if not bool(replay.get("ok", false)):
			issues.append("固定完美解未完成谱面：%s" % str(replay.get("message", "")))
	return {"ok": issues.is_empty(), "issues": issues}


static func verify_solution(chart: Dictionary) -> Dictionary:
	if not chart.get("notes") is Array or not chart.get("solution") is Array:
		return {"ok": false, "message": "谱面缺少 notes 或 solution"}
	var players := [{
		"id": "rhythm-check",
		"name": "小乐手",
		"age": 8,
		"avatar": "🦊",
		"color": "#c65d45",
	}]
	if str(chart.get("mode", "")) == "classic":
		players.append({
			"id": "rhythm-check-two",
			"name": "合拍伙伴",
			"age": 9,
			"avatar": "🐼",
			"color": "#4c7a72",
		})
	var sim = RhythmRules.new()
	sim.create_session({
		"gameId": "rhythm",
		"modeId": str(chart.get("mode", "adventure")),
		"players": players,
		"levelId": int(chart.get("levelNumber", 1)),
		"levelNumber": int(chart.get("levelNumber", 1)),
		"chart": chart,
		"seed": 7,
	})
	if str(sim.state.get("phase", "")) != "playing":
		return {"ok": false, "message": str(sim.state.get("reason", "无法开始固定解"))}
	sim.tick(COUNTDOWN_SECONDS)
	var normalized := _normalize_notes(chart)
	for value in chart.solution:
		var index := int(value)
		if index < 0 or index >= normalized.size():
			return {"ok": false, "message": "固定解音符越界"}
		var note: Dictionary = normalized[index]
		var target := float(note.beat) * 60.0 / maxf(45.0, float(chart.get("bpm", 90.0)))
		var ahead := target - float(sim.state.playhead)
		if ahead > 0.0:
			sim.tick(ahead)
		var press_result := sim.handle_input({"type": "press", "lane": int(note.lane)})
		if not bool(press_result.get("ok", false)):
			return {"ok": false, "message": "固定解按键被拒绝：%s" % str(press_result.get("message", ""))}
		if float(note.hold) > 0.0:
			var hold_seconds := float(note.hold) * 60.0 / maxf(45.0, float(chart.get("bpm", 90.0)))
			sim.tick(hold_seconds + 0.02)
			sim.handle_input({"type": "release", "lane": int(note.lane)})
	if str(sim.state.get("phase", "")) != "finished":
		sim.tick(3.0)
	var summary: Dictionary = sim.result()
	if str(sim.state.get("phase", "")) != "finished":
		return {"ok": false, "message": "固定解结束后仍未完成"}
	if int(summary.get("miss", 0)) != 0 or int(summary.get("perfect", 0)) + int(summary.get("good", 0)) != normalized.size():
		return {"ok": false, "message": "固定解产生了漏拍"}
	return {"ok": true, "result": summary}


static func _normalize_notes(chart: Dictionary) -> Array:
	var result: Array = []
	var bpm := maxf(45.0, _number(chart.get("bpm", 90.0), 90.0))
	for raw in chart.get("notes", []) if chart.get("notes") is Array else []:
		if not raw is Array or raw.size() != 3:
			continue
		var beat := _number(raw[0], 0.0)
		var hold := _number(raw[2], 0.0)
		result.append({
			"beat": beat,
			"lane": _integer(raw[1], 0),
			"hold": hold,
			"start": beat * 60.0 / bpm,
			"holdSeconds": hold * 60.0 / bpm,
		})
	return result


static func _duration(chart: Dictionary) -> float:
	var bpm := maxf(45.0, _number(chart.get("bpm", 90.0), 90.0))
	var result := 0.0
	for raw in chart.get("notes", []) if chart.get("notes") is Array else []:
		if raw is Array and raw.size() == 3:
			result = maxf(result, (_number(raw[0], 0.0) + _number(raw[2], 0.0)) * 60.0 / bpm)
	return result


static func _chart_note_count(chart: Dictionary) -> int:
	return chart.get("notes", []).size() if chart.get("notes") is Array else 0


static func _stars_for_accuracy(accuracy: float) -> int:
	if accuracy >= 0.95:
		return 3
	if accuracy >= 0.82:
		return 2
	if accuracy >= 0.62:
		return 1
	return 0


static func _numeric(value: Variant) -> bool:
	if value is int or value is float:
		return is_finite(float(value))
	if value is String:
		return value.is_valid_float()
	return false


static func _number(value: Variant, fallback: float = 0.0) -> float:
	if value is int or value is float:
		return float(value)
	if value is String and value.is_valid_float():
		return value.to_float()
	return fallback


static func _integer(value: Variant, fallback: int = 0) -> int:
	if value is int:
		return int(value)
	if value is float and is_finite(value):
		return int(value)
	if value is String and value.is_valid_float():
		return int(value.to_float())
	return fallback
