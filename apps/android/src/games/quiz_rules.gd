class_name QuizRules
extends GameSession

func create_session(context: Dictionary) -> Dictionary:
	super.create_session(context)
	state.merge({"queues":[],"positions":[],"scores":[],"answers":[],"currentPlayer":0,"phase":"question","selected":-1},true)
	var pools: Array = context.get("pools",[])
	var rounds := int(context.get("rounds",8))
	for pool in pools:
		var shuffled := random.shuffled(pool)
		state.queues.append(shuffled.slice(0,mini(rounds,shuffled.size())))
		state.positions.append(0)
		state.scores.append(0)
	if pools.is_empty() or pools.any(func(pool): return pool.is_empty()):
		state.phase = "empty"
	return state

func restore(value: Dictionary) -> bool:
	if not super.restore(value):
		return false
	if not state.get("queues") is Array or state.queues.size() != state.players.size() or not state.get("positions") is Array or not state.get("scores") is Array:
		return false
	if state.positions.size() != state.players.size() or state.scores.size() != state.players.size():
		return false
	if not (str(state.get("phase","")) in ["question","feedback","result","empty"]):
		return false
	var saved_phase := str(state.get("phase", ""))
	for index in state.queues.size():
		if not state.queues[index] is Array:
			return false
		if state.queues[index].is_empty():
			if saved_phase != "empty":
				return false
			continue
		if not _whole(state.positions[index]) or not _whole(state.scores[index]):
			return false
		if int(state.positions[index]) < 0 or int(state.positions[index]) > state.queues[index].size():
			return false
		for question in state.queues[index]:
			if not _valid_question(question):
				return false
	state.merge({"answers":[],"selected":-1,"reported":false,"sessionId":"legacy-quiz-"+str(state.get("questionId",""))+str(state.get("updatedAt",0))},false)
	if not state.get("answers") is Array:
		state.answers = []
	else:
		var clean_answers: Array = []
		for answer in state.answers:
			if answer is Dictionary and _valid_question(answer.get("question", {})) and _numeric(answer.get("selected", -1)) and int(answer.selected) in [0,1,2]:
				clean_answers.append(answer)
		state.answers = clean_answers
	if not _whole(state.get("selected", -1)):
		state.selected = -1
	state.selected = clampi(int(state.selected), -1, 2)
	state.currentPlayer = clampi(_integer(state.get("currentPlayer",0)),0,state.players.size()-1)
	state.scores = state.scores.map(func(score): return maxi(0, _integer(score)))
	if saved_phase == "feedback" and int(state.selected) not in [0,1,2]:
		return false
	if state.phase in ["question","feedback"] and int(state.positions[int(state.currentPlayer)]) >= state.queues[int(state.currentPlayer)].size():
		return false
	return true


func _valid_question(value: Variant) -> bool:
	if not value is Dictionary or not (value.get("options") is Array) or value.options.size() != 3:
		return false
	return _whole(value.get("answer", -1)) and int(value.answer) in [0,1,2]


func _whole(value: Variant) -> bool:
	return _numeric(value) and is_equal_approx(float(value), float(int(value)))


func _numeric(value: Variant) -> bool:
	if value is int or value is float:
		return is_finite(float(value))
	if value is String:
		return value.is_valid_float()
	return false


func _integer(value: Variant) -> int:
	if value is int:
		return int(value)
	if value is float and is_finite(value):
		return int(value)
	if value is String and value.is_valid_float():
		return int(float(value))
	return 0

func question() -> Dictionary:
	if state.get("phase","") in ["empty","result"]:
		return {}
	var player := int(state.currentPlayer)
	var queue: Array = state.queues[player]
	var position := int(state.positions[player])
	return queue[position] if position < queue.size() else {}

func handle_input(action: Dictionary) -> Dictionary:
	var player := int(state.get("currentPlayer",0))
	if action.get("type") == "answer" and state.phase == "question":
		var selected := int(action.get("index",-1))
		if selected < 0 or selected >= 3:
			return {"ok":false}
		var current := question()
		if current.is_empty():
			return {"ok":false}
		var correct := selected == int(current.answer)
		state.selected = selected
		state.scores[player] = int(state.scores[player])+(1 if correct else 0)
		state.answers.append({"questionId":str(current.id),"question":current.duplicate(true),"playerIndex":player,"selected":selected,"correct":correct})
		state.phase = "feedback"
		return {"ok":true,"correct":correct,"question":current}
	if action.get("type") == "next" and state.phase == "feedback":
		state.positions[player] = int(state.positions[player])+1
		state.selected = -1
		var player_count: int = int(state.players.size())
		for offset: int in player_count:
			var target: int = (player+offset+1)%player_count
			if int(state.positions[target]) < state.queues[target].size():
				state.currentPlayer = target
				state.phase = "question"
				return {"ok":true}
		state.phase = "result"
		return {"ok":true,"finished":true}
	return {"ok":false}

func final_question() -> bool:
	for index in state.players.size():
		if int(state.positions[index])+(1 if index == int(state.currentPlayer) else 0) < state.queues[index].size():
			return false
	return true

static func stars(correct: int, total: int) -> int:
	if total <= 0:
		return 0
	var ratio := float(correct)/float(total)
	return 3 if correct == total else 2 if ratio >= 0.8 else 1 if ratio >= 0.6 else 0
