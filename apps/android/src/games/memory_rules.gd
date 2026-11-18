class_name MemoryRules
extends GameSession

func create_session(context: Dictionary) -> Dictionary:
	super.create_session(context)
	var pairs := int(context.get("pairs",6))
	var preview_seconds := float(context.get("previewSeconds",0.8))
	var hints_max := int(context.get("hintsMax",2))
	var three_star_mistakes := int(context.get("threeStarMistakes",3))
	var unique_cards: Array = []
	var seen_ids := {}
	for card in context.get("cards",[]):
		if not card is Dictionary:
			continue
		var card_id := str(card.get("id", ""))
		if card_id.is_empty() or seen_ids.has(card_id):
			continue
		seen_ids[card_id] = true
		unique_cards.append(card)
	var cards: Array = random.shuffled(unique_cards).slice(0,pairs)
	if cards.is_empty():
		state.erase("cards")
		state.merge({"deck":[],"cardData":[],"pairs":0,"flipped":[],"matched":[],"scores":[],"currentPlayer":0,"pending":false,"remaining":0.0,"peekRemaining":0.0,"peekIndices":[],"hints":0,"mistakes":0,"moves":0,"previewSeconds":preview_seconds,"hintsMax":hints_max,"threeStarMistakes":three_star_mistakes,"phase":"empty"},true)
		return state
	var deck: Array = []
	for card in cards:
		deck.append(str(card.id))
		deck.append(str(card.id))
	state.erase("cards")
	state.merge({"deck":random.shuffled(deck),"cardData":cards,"pairs":cards.size(),"flipped":[],"matched":[],"scores":[],"currentPlayer":0,"pending":false,"remaining":0.0,"peekRemaining":0.0,"peekIndices":[],"hints":0,"mistakes":0,"moves":0,"previewSeconds":preview_seconds,"hintsMax":hints_max,"threeStarMistakes":three_star_mistakes},true)
	for player in state.players:
		state.scores.append(0)
	return state

func restore(value: Dictionary) -> bool:
	if not super.restore(value) or not state.get("deck") is Array or state.deck.size() < 2 or state.deck.size() > 24 or state.deck.size()%2 != 0:
		return false
	if not (str(state.get("phase", "")) in ["playing", "result"]):
		return false
	var counts := {}
	for identifier in state.deck:
		if not identifier is String or identifier.is_empty():
			return false
		counts[str(identifier)] = int(counts.get(str(identifier),0))+1
	if counts.values().any(func(count): return int(count) != 2):
		return false
	for key in ["flipped","matched","scores"]:
		if not state.get(key) is Array:
			return false
	if state.flipped.size() > 2 or state.scores.size() != state.players.size():
		return false
	var seen := {}
	for index in state.flipped+state.matched:
		if not _numeric(index):
			return false
		var clean_index := int(index)
		if clean_index < 0 or clean_index >= state.deck.size() or seen.has(clean_index):
			return false
		seen[clean_index] = true
	state.merge({"remaining":0.8 if state.flipped.size() == 2 else 0.0,"peekRemaining":0.0,"peekIndices":[],"hints":0,"mistakes":0,"moves":0,"previewSeconds":0.8,"hintsMax":2,"threeStarMistakes":3,"reported":false,"sessionId":"legacy-memory-"+str(state.deck.hash()),"cardData":[]},false)
	var clean_card_data: Array = []
	var card_data_ids := {}
	var saved_card_data: Variant = state.get("cardData", [])
	if saved_card_data is Array:
		for card in saved_card_data:
			if not card is Dictionary:
				continue
			var card_id := str(card.get("id", ""))
			if card_id in counts and not card_data_ids.has(card_id):
				clean_card_data.append(card)
				card_data_ids[card_id] = true
	state.cardData = clean_card_data
	var clean_peeks: Array = []
	var saved_peeks: Variant = state.get("peekIndices", [])
	if saved_peeks is Array:
		for index in saved_peeks:
			if not _numeric(index):
				continue
			var peek := int(index)
			if peek >= 0 and peek < state.deck.size() and not seen.has(peek) and not (peek in clean_peeks):
				clean_peeks.append(peek)
	if clean_peeks.size() != 2 or state.deck[int(clean_peeks[0])] != state.deck[int(clean_peeks[1])]:
		clean_peeks.clear()
	state.peekIndices = clean_peeks
	state.pending = state.flipped.size() == 2
	state.mismatchShowing = bool(state.get("mismatchShowing",false)) and bool(state.pending)
	state.remaining = clampf(_number(state.get("remaining", 0.8), 0.8),0.0,0.32 if bool(state.mismatchShowing) else 0.9)
	state.peekRemaining = clampf(_number(state.get("peekRemaining", 0.0), 0.0), 0.0, 5.0)
	state.hints = maxi(0, _integer(state.get("hints", 0)))
	state.mistakes = maxi(0, _integer(state.get("mistakes", 0)))
	state.moves = maxi(0, _integer(state.get("moves", 0)))
	state.previewSeconds = clampf(_number(state.get("previewSeconds", 0.8), 0.8), 0.2, 3.0)
	state.hintsMax = maxi(0, _integer(state.get("hintsMax", 2)))
	state.threeStarMistakes = maxi(0, _integer(state.get("threeStarMistakes", 3)))
	state.currentPlayer = clampi(_integer(state.get("currentPlayer",0)),0,state.players.size()-1)
	for index in state.scores.size():
		state.scores[index] = maxi(0, _integer(state.scores[index]))
	for index in range(0, state.matched.size(), 2):
		if index + 1 >= state.matched.size() or state.deck[int(state.matched[index])] != state.deck[int(state.matched[index + 1])]:
			return false
	var saved_phase := str(state.get("phase", ""))
	if saved_phase == "result" and state.matched.size() != state.deck.size():
		return false
	if saved_phase == "playing" and state.matched.size() == state.deck.size():
		return false
	return saved_phase in ["playing","result"]


func _numeric(value: Variant) -> bool:
	if value is int or value is float:
		return is_finite(float(value))
	if value is String:
		return value.is_valid_float()
	return false


func _number(value: Variant, fallback: float) -> float:
	if value is int or value is float:
		return float(value) if is_finite(float(value)) else fallback
	if value is String and value.is_valid_float():
		var parsed := float(value)
		return parsed if is_finite(parsed) else fallback
	return fallback


func _integer(value: Variant) -> int:
	return int(round(_number(value, 0.0)))

func handle_input(action: Dictionary) -> Dictionary:
	if state.phase != "playing" or bool(state.pending) or float(state.peekRemaining) > 0:
		return {"ok":false}
	if str(action.get("type","")) == "hint":
		if int(state.hints) >= int(state.get("hintsMax",2)) or not state.flipped.is_empty():
			return {"ok":false}
		for index in state.deck.size():
			if index in state.matched:
				continue
			for other in range(index+1,state.deck.size()):
				if not (other in state.matched) and state.deck[index] == state.deck[other]:
					state.peekIndices = [index,other]
					state.peekRemaining = float(state.get("previewSeconds",0.8)) + 0.6
					state.hints = int(state.hints)+1
					return {"ok":true,"event":"hint"}
		return {"ok":false}
	var index := int(action.get("index",-1))
	if index < 0 or index >= state.deck.size() or index in state.flipped or index in state.matched:
		return {"ok":false}
	state.flipped.append(index)
	if state.flipped.size() == 2:
		state.pending = true
		state.remaining = 0.9
		state.moves = int(state.moves)+1
	return {"ok":true,"event":"flip"}

func tick(delta: float) -> bool:
	if state.get("phase","") != "playing":
		return false
	var changed := false
	if float(state.peekRemaining) > 0:
		state.peekRemaining = maxf(0,float(state.peekRemaining)-delta)
		if float(state.peekRemaining) == 0:
			state.peekIndices = []
			changed = true
	if bool(state.pending):
		state.remaining = maxf(0,float(state.remaining)-delta)
		if float(state.remaining) == 0:
			var first := int(state.flipped[0])
			var second := int(state.flipped[1])
			state.lastMatched = state.deck[first] == state.deck[second]
			if not bool(state.lastMatched) and not bool(state.get("mismatchShowing",false)):
				# 抖动仍属于这一次判定，快照保留两张牌和输入锁。
				state.mismatchShowing = true
				state.remaining = 0.32
				return true
			state.mismatchShowing = false
			if bool(state.lastMatched):
				state.matched.append(first)
				state.matched.append(second)
				state.scores[int(state.currentPlayer)] = int(state.scores[int(state.currentPlayer)])+1
			else:
				state.mistakes = int(state.mistakes)+1
			state.flipped = []
			state.pending = false
			state.currentPlayer = (int(state.currentPlayer)+1)%state.players.size()
			if state.matched.size() == state.deck.size():
				state.phase = "result"
			changed = true
	return changed

func stars() -> int:
	if int(state.hints) == 0 and int(state.mistakes) <= int(state.get("threeStarMistakes",3)):
		return 3
	if int(state.mistakes) <= int(state.pairs):
		return 2
	return 1
