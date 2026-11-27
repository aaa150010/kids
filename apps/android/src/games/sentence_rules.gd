class_name SentenceRules
extends GameSession

const VERSION := 1
const STATION_SENTENCE_COUNT := 5
const BANDS := ["easy", "normal", "challenge"]
const BAND_RANGES := {
	"easy": Vector2i(4, 6),
	"normal": Vector2i(7, 9),
	"challenge": Vector2i(10, 12),
}


func create_session(context: Dictionary) -> Dictionary:
	super.create_session(context)
	if not _players_match_mode():
		state = {}
		return state
	var incoming: Variant = context.get("station", {})
	if not incoming is Dictionary:
		state = {}
		return state
	var station_input: Dictionary = incoming
	if not _valid_station(station_input):
		state = {}
		return state
	var station: Dictionary = station_input.duplicate(true)
	var sentences: Array = station.sentences
	var first: Dictionary = sentences[0]
	state.merge({
		"sentenceTrainVersion": VERSION,
		"view": "play",
		"levelId": maxi(1, _integer(context.get("levelId", 1))),
		"station": station,
		"stationId": str(station.id),
		"stationTitle": str(station.title),
		"band": str(station.band),
		"minAge": int(station.minAge),
		"sentenceIndex": 0,
		"sentenceCount": STATION_SENTENCE_COUNT,
		"sentence": first.duplicate(true),
		"placedIds": [],
		"trayIds": _tray_order(first),
		"turn": 0,
		"correctCount": 0,
		"wrongCount": 0,
		"history": [],
		"judgement": {},
		"stars": 0,
		"reason": "",
		"phase": "playing",
		"reported": false,
	}, true)
	return state


func snapshot() -> Dictionary:
	state.sentenceTrainVersion = VERSION
	return super.snapshot()


func restore(value: Dictionary) -> bool:
	if not _number(value.get("sentenceTrainVersion", null)):
		return false
	if int(value.get("sentenceTrainVersion", -1)) != VERSION:
		return false
	if not super.restore(value):
		return false
	if not _players_match_mode():
		return false
	var station: Variant = state.get("station", {})
	if not station is Dictionary:
		return false
	var station_map: Dictionary = station
	if not _valid_station(station_map):
		return false
	if str(state.get("stationId", "")) != str(station_map.get("id", "")):
		return false
	if str(state.get("stationTitle", "")) != str(station_map.get("title", "")):
		return false
	if str(state.get("band", "")) != str(station_map.get("band", "")):
		return false
	if _integer(state.get("minAge", 0)) != int(station_map.get("minAge", 0)):
		return false
	var sentence_count := _integer(state.get("sentenceCount", 0))
	var sentences: Array = station_map.get("sentences", [])
	if sentence_count != STATION_SENTENCE_COUNT or sentences.size() != STATION_SENTENCE_COUNT:
		return false
	var sentence_index := _integer(state.get("sentenceIndex", -1))
	if sentence_index < 0 or sentence_index >= sentences.size():
		return false
	var sentence_value: Variant = state.get("sentence", {})
	if not sentence_value is Dictionary:
		return false
	var sentence: Dictionary = sentence_value
	if not _valid_sentence(sentence, str(station_map.band)):
		return false
	var source_sentence: Dictionary = sentences[sentence_index]
	if JSON.stringify(sentence) != JSON.stringify(source_sentence):
		return false
	if str(state.get("view", "play")) not in ["map", "play"]:
		return false
	var chunks: Array = sentence.get("chunks", [])
	var ids := {}
	for chunk in chunks:
		ids[str(chunk.id)] = true
	if not _valid_id_list(state.get("placedIds", null), ids):
		return false
	if not _valid_id_list(state.get("trayIds", null), ids):
		return false
	var placed_ids: Array = state.placedIds
	var tray_ids: Array = state.trayIds
	var placed_seen := {}
	for chunk_id in placed_ids:
		if placed_seen.has(chunk_id):
			return false
		placed_seen[chunk_id] = true
	var tray_seen := {}
	for chunk_id in tray_ids:
		if tray_seen.has(chunk_id):
			return false
		tray_seen[chunk_id] = true
	for chunk_id in ids:
		var in_placed := placed_seen.has(chunk_id)
		var in_tray := tray_seen.has(chunk_id)
		if in_placed == in_tray:
			return false
	var phase := str(state.get("phase", ""))
	if phase not in ["playing", "feedback", "station_result"]:
		return false
	if phase in ["feedback", "station_result"] and placed_ids.size() != chunks.size():
		return false
	var judgement: Variant = state.get("judgement", {})
	if not judgement is Dictionary:
		return false
	var judgement_map: Dictionary = judgement
	if phase == "playing":
		if not judgement_map.is_empty():
			return false
	else:
		if not _valid_judgement(judgement_map, sentence, placed_ids):
			return false
	var correct_count := _integer(state.get("correctCount", -1))
	var wrong_count := _integer(state.get("wrongCount", -1))
	if correct_count < 0 or correct_count > sentence_count:
		return false
	if wrong_count < 0 or correct_count + wrong_count > sentence_count:
		return false
	if phase == "station_result" and sentence_index != sentence_count - 1:
		return false
	if not state.get("history", null) is Array:
		return false
	var history: Array = state.get("history", [])
	if not _valid_history(history, sentences):
		return false
	if history.size() != correct_count + wrong_count:
		return false
	if phase == "playing" and history.size() != sentence_index:
		return false
	if phase in ["feedback", "station_result"] and history.size() != sentence_index + 1:
		return false
	var turn := _integer(state.get("turn", -1))
	if turn < 0 or turn > 1:
		return false
	if str(state.modeId) != "classic":
		turn = 0
	if not state.get("reported", null) is bool:
		return false
	if phase == "station_result":
		state.stars = stars()
	else:
		state.stars = 0
	if _integer(state.get("levelId", 0)) < 1:
		return false
	state.turn = turn
	state.sentenceTrainVersion = VERSION
	state.phase = phase
	return true


func place_chunk(chunk_id: String) -> Dictionary:
	if str(state.get("phase", "")) != "playing":
		return {"ok": false, "message": "先看完这一句，再继续接车厢。"}
	var sentence: Dictionary = state.get("sentence", {})
	var chunks: Array = sentence.get("chunks", [])
	if chunk_id.is_empty() or not _known_chunk(chunks, chunk_id):
		return {"ok": false, "message": "这张词卡找不到啦。"}
	var tray_ids: Array = state.get("trayIds", [])
	var tray_index := tray_ids.find(chunk_id)
	if tray_index < 0:
		return {"ok": false, "message": "这张词卡已经在火车上啦。"}
	var placed_ids: Array = state.get("placedIds", [])
	if placed_ids.size() >= chunks.size():
		return {"ok": false, "message": "车厢已经满了，检查一下再出发。"}
	tray_ids.remove_at(tray_index)
	placed_ids.append(chunk_id)
	state.judgement = {}
	if _is_coop():
		state.turn = 1 - clampi(_integer(state.get("turn", 0)), 0, 1)
	return {
		"ok": true,
		"complete": placed_ids.size() == chunks.size(),
		"turn": int(state.get("turn", 0)),
		"placedIndex": placed_ids.size() - 1,
	}


func remove_chunk(chunk_id: String) -> Dictionary:
	if str(state.get("phase", "")) != "playing":
		return {"ok": false, "message": "讲解时不能取回词卡。"}
	var placed_ids: Array = state.get("placedIds", [])
	var placed_index := placed_ids.find(chunk_id)
	if placed_index < 0:
		return {"ok": false, "message": "这节车厢里没有这张词卡。"}
	var tray_ids: Array = state.get("trayIds", [])
	placed_ids.remove_at(placed_index)
	if not tray_ids.has(chunk_id):
		tray_ids.append(chunk_id)
	state.judgement = {}
	return {"ok": true, "removedIndex": placed_index}


func submit() -> Dictionary:
	if str(state.get("phase", "")) != "playing":
		return {"ok": false, "message": "这一句已经排好了。"}
	var sentence: Dictionary = state.get("sentence", {})
	var chunks: Array = sentence.get("chunks", [])
	var placed_ids: Array = state.get("placedIds", [])
	if placed_ids.size() != chunks.size():
		return {"ok": false, "message": "把词卡都接上车，再点完成句子。"}
	var attempt_text := _sentence_text(sentence, placed_ids)
	var correct := _matches_accepted(sentence, placed_ids)
	var judgement := {
		"correct": correct,
		"attemptOrder": placed_ids.duplicate(),
		"attemptText": attempt_text,
		"fullSentence": str(sentence.get("fullSentence", "")),
		"explanation": str(sentence.get("explanation", "")),
	}
	state.judgement = judgement
	state.phase = "feedback"
	if correct:
		state.correctCount = _integer(state.get("correctCount", 0)) + 1
	else:
		state.wrongCount = _integer(state.get("wrongCount", 0)) + 1
	var history: Array = state.get("history", [])
	history.append({
		"sentenceId": str(sentence.get("id", "")),
		"correct": correct,
		"attemptOrder": placed_ids.duplicate(),
		"attemptText": attempt_text,
	})
	state.history = history
	return {
		"ok": true,
		"correct": correct,
		"fullSentence": str(sentence.get("fullSentence", "")),
		"explanation": str(sentence.get("explanation", "")),
		"attemptText": attempt_text,
		"correctCount": int(state.correctCount),
		"wrongCount": int(state.wrongCount),
		"last": int(state.get("sentenceIndex", 0)) >= int(state.get("sentenceCount", 0)) - 1,
	}


func next_sentence() -> Dictionary:
	if str(state.get("phase", "")) != "feedback":
		return {"ok": false, "message": "先完成这一句，再继续。"}
	var next_index := _integer(state.get("sentenceIndex", 0)) + 1
	var total := _integer(state.get("sentenceCount", STATION_SENTENCE_COUNT))
	if next_index >= total:
		state.phase = "station_result"
		state.stars = stars()
		state.reason = "第 %s 站到站啦" % _integer(state.get("levelId", 1))
		return {
			"ok": true,
			"finished": true,
			"stars": int(state.stars),
			"correctCount": int(state.get("correctCount", 0)),
			"wrongCount": int(state.get("wrongCount", 0)),
		}
	var station: Dictionary = state.get("station", {})
	var sentences: Array = station.get("sentences", [])
	if next_index < 0 or next_index >= sentences.size():
		return {"ok": false, "message": "下一句还没有准备好。"}
	var next_sentence_value: Dictionary = sentences[next_index]
	state.sentenceIndex = next_index
	state.sentence = next_sentence_value.duplicate(true)
	state.placedIds = []
	state.trayIds = _tray_order(next_sentence_value)
	state.judgement = {}
	state.phase = "playing"
	state.reason = ""
	return {
		"ok": true,
		"finished": false,
		"sentenceIndex": next_index,
	}


func handle_input(action: Dictionary) -> Dictionary:
	match str(action.get("type", "")):
		"place_chunk":
			return place_chunk(str(action.get("chunkId", "")))
		"remove_chunk":
			return remove_chunk(str(action.get("chunkId", "")))
		"submit":
			return submit()
		"next":
			return next_sentence()
	return {"ok": false, "message": "这一步现在还做不了。"}


func tick(_delta: float) -> bool:
	return false


func stars() -> int:
	var total := _integer(state.get("sentenceCount", STATION_SENTENCE_COUNT))
	var correct := _integer(state.get("correctCount", 0))
	if total <= 0 or correct <= 0:
		return 0
	if correct >= total:
		return 3
	if correct >= int(ceil(float(total) * 0.75)):
		return 2
	return 1


func result() -> Dictionary:
	if str(state.get("phase", "")) != "station_result":
		return {}
	return {
		"winner": -1,
		"phase": "station_result",
		"reason": str(state.get("reason", "")),
		"stars": stars(),
		"correct": _integer(state.get("correctCount", 0)),
		"answered": _integer(state.get("sentenceCount", STATION_SENTENCE_COUNT)),
	}


func current_chunks() -> Array:
	var sentence: Dictionary = state.get("sentence", {})
	var chunks: Variant = sentence.get("chunks", [])
	return chunks if chunks is Array else []


func chunk_lookup() -> Dictionary:
	var result := {}
	for chunk in current_chunks():
		if chunk is Dictionary:
			result[str(chunk.get("id", ""))] = str(chunk.get("text", ""))
	return result


func prompt_text() -> String:
	return str(state.get("sentence", {}).get("prompt", ""))


func narration_text() -> String:
	return str(state.get("sentence", {}).get("narration", ""))


func full_sentence() -> String:
	return str(state.get("sentence", {}).get("fullSentence", ""))


func explanation() -> String:
	return str(state.get("sentence", {}).get("explanation", ""))


func validate_station(station: Dictionary) -> bool:
	return _valid_station(station)


func _tray_order(sentence: Dictionary) -> Array:
	var ordered := []
	for chunk in sentence.get("chunks", []):
		if chunk is Dictionary:
			ordered.append(str(chunk.get("id", "")))
	var shuffled: Array = random.shuffled(ordered)
	if shuffled.size() > 1 and JSON.stringify(shuffled) == JSON.stringify(sentence.get("answerOrder", [])):
		var first: Variant = shuffled.pop_front()
		shuffled.append(first)
	return shuffled


func _is_coop() -> bool:
	var player_values: Variant = state.get("players", [])
	return str(state.get("modeId", "classic")) == "classic" and player_values is Array and player_values.size() == 2


func _players_match_mode() -> bool:
	var player_values: Variant = state.get("players", [])
	if not player_values is Array:
		return false
	match str(state.get("modeId", "classic")):
		"classic":
			return player_values.size() == 2
		"adventure":
			return player_values.size() == 1
	return false


func _known_chunk(chunks: Array, chunk_id: String) -> bool:
	for chunk in chunks:
		if chunk is Dictionary and str(chunk.get("id", "")) == chunk_id:
			return true
	return false


func _matches_accepted(sentence: Dictionary, order: Array) -> bool:
	var signature := JSON.stringify(order)
	if signature == JSON.stringify(sentence.get("answerOrder", [])):
		return true
	var accepted: Variant = sentence.get("acceptedOrders", [])
	if accepted is Array and not accepted.is_empty():
		for candidate in accepted:
			if candidate is Array and JSON.stringify(candidate) == signature:
				return true
	return false


func _sentence_text(sentence: Dictionary, order: Array) -> String:
	var lookup := {}
	for chunk in sentence.get("chunks", []):
		if chunk is Dictionary:
			lookup[str(chunk.get("id", ""))] = str(chunk.get("text", ""))
	var pieces := PackedStringArray()
	for chunk_id in order:
		if not lookup.has(str(chunk_id)):
			return ""
		pieces.append(str(lookup[str(chunk_id)]))
	return "".join(pieces)


func _valid_station(station: Dictionary) -> bool:
	if str(station.get("id", "")).strip_edges().is_empty():
		return false
	if str(station.get("title", "")).strip_edges().is_empty():
		return false
	var band := str(station.get("band", ""))
	if band not in BANDS:
		return false
	var age := _integer(station.get("minAge", 0))
	if not _age_matches_band(age, band):
		return false
	var sentences: Variant = station.get("sentences", [])
	if not sentences is Array or sentences.size() != STATION_SENTENCE_COUNT:
		return false
	var sentence_ids := {}
	for sentence in sentences:
		if not sentence is Dictionary:
			return false
		var sentence_map: Dictionary = sentence
		if not _valid_sentence(sentence_map, band):
			return false
		var sentence_id := str(sentence_map.get("id", ""))
		if sentence_ids.has(sentence_id):
			return false
		sentence_ids[sentence_id] = true
	return true


func _valid_sentence(sentence: Dictionary, station_band: String) -> bool:
	if str(sentence.get("id", "")).strip_edges().is_empty():
		return false
	var band := str(sentence.get("band", ""))
	if band not in BANDS or band != station_band:
		return false
	var age := _integer(sentence.get("minAge", 0))
	if not _age_matches_band(age, band):
		return false
	for key in ["prompt", "fullSentence", "explanation", "narration", "skill"]:
		if str(sentence.get(key, "")).strip_edges().is_empty():
			return false
	var chunks: Variant = sentence.get("chunks", [])
	if not chunks is Array or chunks.size() < 3 or chunks.size() > 8:
		return false
	var chunk_ids := {}
	for chunk in chunks:
		if not chunk is Dictionary:
			return false
		var chunk_id := str(chunk.get("id", ""))
		var chunk_text := str(chunk.get("text", ""))
		if chunk_id.is_empty() or chunk_text.is_empty() or chunk_ids.has(chunk_id):
			return false
		chunk_ids[chunk_id] = true
	var answer_order_value: Variant = sentence.get("answerOrder", [])
	if not _valid_order(answer_order_value, chunk_ids):
		return false
	var answer_order: Array = answer_order_value
	var full_sentence := str(sentence.get("fullSentence", ""))
	if _sentence_text(sentence, answer_order) != full_sentence:
		return false
	var accepted_value: Variant = sentence.get("acceptedOrders", null)
	if accepted_value == null:
		return true
	if not accepted_value is Array or accepted_value.is_empty():
		return false
	var seen_orders := {}
	for candidate in accepted_value:
		if not _valid_order(candidate, chunk_ids):
			return false
		var signature := JSON.stringify(candidate)
		if seen_orders.has(signature):
			return false
		seen_orders[signature] = true
	return true


func _valid_order(order_value: Variant, chunk_ids: Dictionary) -> bool:
	if not order_value is Array or order_value.size() != chunk_ids.size():
		return false
	var seen := {}
	for chunk_id in order_value:
		if not chunk_id is String or not chunk_ids.has(chunk_id) or seen.has(chunk_id):
			return false
		seen[chunk_id] = true
	return seen.size() == chunk_ids.size()


func _valid_id_list(value: Variant, ids: Dictionary) -> bool:
	if not value is Array:
		return false
	for chunk_id in value:
		if not chunk_id is String or not ids.has(chunk_id):
			return false
	return true


func _valid_judgement(judgement: Dictionary, sentence: Dictionary, placed_ids: Array) -> bool:
	if not judgement.get("correct", null) is bool:
		return false
	if not judgement.get("attemptOrder", null) is Array:
		return false
	if judgement.attemptOrder != placed_ids:
		return false
	if str(judgement.get("attemptText", "")) != _sentence_text(sentence, placed_ids):
		return false
	if str(judgement.get("fullSentence", "")) != str(sentence.get("fullSentence", "")):
		return false
	if str(judgement.get("explanation", "")) != str(sentence.get("explanation", "")):
		return false
	return bool(judgement.correct) == _matches_accepted(sentence, placed_ids)


func _valid_history(history: Array, sentences: Array) -> bool:
	if history.size() > sentences.size():
		return false
	var sentence_map := {}
	for sentence in sentences:
		sentence_map[str(sentence.get("id", ""))] = sentence
	var seen := {}
	for entry in history:
		if not entry is Dictionary:
			return false
		var sentence_id := str(entry.get("sentenceId", ""))
		if sentence_id.is_empty() or not sentence_map.has(sentence_id) or seen.has(sentence_id):
			return false
		seen[sentence_id] = true
		if not entry.get("correct", null) is bool:
			return false
		if not entry.get("attemptOrder", null) is Array:
			return false
		if not entry.get("attemptText", null) is String:
			return false
		var sentence: Dictionary = sentence_map[sentence_id]
		var order: Array = entry.attemptOrder
		var chunk_ids := {}
		for chunk in sentence.get("chunks", []):
			if chunk is Dictionary:
				chunk_ids[str(chunk.get("id", ""))] = true
		if not _valid_order(order, chunk_ids):
			return false
		if str(entry.attemptText) != _sentence_text(sentence, order):
			return false
		if bool(entry.correct) != _matches_accepted(sentence, order):
			return false
	return true


func _age_matches_band(age: int, band: String) -> bool:
	if not BAND_RANGES.has(band):
		return false
	var limits: Vector2i = BAND_RANGES[band]
	return age >= limits.x and age <= limits.y


func _integer(value: Variant) -> int:
	return int(value) if _number(value) else 0


func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))
