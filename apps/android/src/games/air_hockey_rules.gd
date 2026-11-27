class_name AirHockeyRules
extends GameSession

const VERSION := 1
const LOGIC_HZ := ArcadePhysics.STEP_HZ
const LOGIC_STEP := ArcadePhysics.STEP_DELTA
const MAX_FRAME_STEPS := 24
const MAX_EVENTS := 64
const MODES := ["practice", "classic"]
const BANDS := ["easy", "normal", "challenge"]
const LEFT := 0.038
const RIGHT := 0.962
const TOP := 0.055
const BOTTOM := 0.945
const PUCK_RADIUS := 0.022
const PADDLE_MAX_SPEED := 3.25
const MAX_PUCK_SPEED := 1.45
const MIN_PUCK_SPEED := 0.34
const SERVE_DELAY := 0.9
const PLAY_ASPECT := 1.62
const INVALID_INT := -2147483648

var _accumulator := 0.0


func create_session(context: Dictionary) -> Dictionary:
	super.create_session(context)
	var mode := str(context.get("modeId", "practice"))
	if not mode in MODES:
		mode = "practice"
	var arena_value: Variant = context.get("arena", context.get("level", {}))
	var arena := _normalize_arena(arena_value)
	var level_id := maxi(1, _int_value(context.get("levelId", 1), 1))
	var level_number := _int_value(arena.get("levelNumber", level_id), level_id)
	var required_players := 2 if mode == "classic" else 1
	var players_value: Variant = state.get("players", [])
	var player_count: int = players_value.size() if players_value is Array else 0
	if (
		arena.is_empty()
		or str(arena.get("mode", "")) != mode
		or level_id != level_number
		or player_count != required_players
		or not bool(validate_arena(arena).get("ok", false))
	):
		state.merge({
			"airHockeyVersion": VERSION,
			"gameId": "air_hockey",
			"modeId": mode,
			"levelId": level_id,
			"levelNumber": level_number,
			"levelKey": "",
			"level": {},
			"view": "map",
			"phase": "empty",
			"reason": "这一张冰球台还没有准备好",
			"events": [],
			"reported": false,
			"success": false,
			"winner": -1,
			"stars": 0,
		}, true)
		_accumulator = 0.0
		return state
	arena.levelNumber = level_id
	var targets := _build_targets(arena)
	var paddles := _build_paddles(mode, arena)
	var target_total := targets.size()
	state.merge({
		"airHockeyVersion": VERSION,
		"gameId": "air_hockey",
		"modeId": mode,
		"levelId": level_id,
		"levelNumber": level_id,
		"levelKey": str(arena.get("id", "")),
		"levelTitle": str(arena.get("title", "冰球碰碰台")),
		"levelBand": str(arena.get("band", "easy")),
		"level": arena,
		"view": "board",
		"phase": "playing",
		"reason": "",
		"success": false,
		"winner": -1,
		"outcome": "",
		"scores": [0, 0],
		"playerScores": [0, 0],
		"targets": targets,
		"targetTotal": target_total,
		"targetsHit": 0,
		"paddles": paddles,
		"puck": {},
		"timeLeft": float(arena.get("tableSeconds", 45.0)),
		"elapsed": 0.0,
		"serveTimer": SERVE_DELAY,
		"nextServeX": 0,
		"lastScorer": -1,
		"maxScore": target_total if mode == "practice" else int(arena.get("targetScore", 5)),
		"goals": [0, 0],
		"wallHits": 0,
		"paddleHits": 0,
		"hintsUsed": 0,
		"physicsAccumulator": 0.0,
		"events": [],
		"reported": false,
		"stars": 0,
		"difficulty": str(context.get("difficulty", "normal")),
	}, true)
	_accumulator = 0.0
	_add_event({"type": "serve_ready", "x": 0.5, "y": 0.5})
	return state


func handle_input(action: Dictionary) -> Dictionary:
	match str(action.get("type", "")):
		"drag", "move":
			return drag_mallet(
				_int_value(action.get("seat", 0), 0),
				_float_value(action.get("x", 0.5), 0.5),
				_float_value(action.get("y", 0.5), 0.5)
			)
		"serve":
			return serve_now()
		"hint":
			return hint()
	return {"ok": false, "changed": false, "message": "这个操作现在不能用"}


func drag_mallet(seat: int, x: float, y: float) -> Dictionary:
	if str(state.get("phase", "")) != "playing":
		return {"ok": false, "changed": false, "message": "这场比赛已经结束啦"}
	var index := _paddle_index(seat)
	if index < 0:
		return {"ok": false, "changed": false, "message": "找不到这只球拍"}
	var paddles_value: Variant = state.get("paddles", [])
	if not paddles_value is Array:
		return {"ok": false, "changed": false, "message": "球拍还没有准备好"}
	var paddles: Array = paddles_value
	var paddle: Dictionary = paddles[index]
	var radius := _float_value(paddle.get("radius", 0.055), 0.055)
	var low_x := LEFT + radius
	var high_x := RIGHT - radius
	if str(state.get("modeId", "")) == "classic":
		if seat == 0:
			high_x = 0.5 - radius * 0.18
		else:
			low_x = 0.5 + radius * 0.18
	var target_x := clampf(x, low_x, high_x)
	var target_y := clampf(y, TOP + radius, BOTTOM - radius)
	var changed := (
		absf(_float_value(paddle.get("targetX", target_x), target_x) - target_x) > 0.0001
		or absf(_float_value(paddle.get("targetY", target_y), target_y) - target_y) > 0.0001
	)
	paddle.targetX = target_x
	paddle.targetY = target_y
	paddles[index] = paddle
	state.paddles = paddles
	return {"ok": true, "changed": changed, "seat": seat, "x": target_x, "y": target_y}


func serve_now() -> Dictionary:
	if str(state.get("phase", "")) != "playing":
		return {"ok": false, "changed": false, "message": "这场比赛已经结束啦"}
	var puck_value: Variant = state.get("puck", {})
	if puck_value is Dictionary and not puck_value.is_empty():
		return {"ok": false, "changed": false, "message": "冰球已经在场上了"}
	state.serveTimer = 0.0
	return {"ok": true, "changed": true}


func hint() -> Dictionary:
	if str(state.get("phase", "")) != "playing":
		return {"ok": false, "message": "这场比赛已经结束啦"}
	state.hintsUsed = int(state.get("hintsUsed", 0)) + 1
	var arena := _arena()
	return {
		"ok": true,
		"changed": true,
		"hint": str(arena.get("hint", "把球拍放在冰球后方，再向球门方向滑过去。")),
		"hints": int(state.hintsUsed),
	}


func tick(delta: float) -> bool:
	if str(state.get("phase", "")) != "playing":
		return false
	var frame := ArcadePhysics.consume_fixed_steps(_accumulator, delta, MAX_FRAME_STEPS)
	_accumulator = float(frame.get("accumulator", 0.0))
	var steps := int(frame.get("steps", 0))
	var changed := false
	for _index in steps:
		if str(state.get("phase", "")) != "playing":
			break
		_step(LOGIC_STEP)
		changed = true
	if bool(frame.get("dropped", false)):
		_accumulator = minf(_accumulator, LOGIC_STEP * 0.5)
	return changed


func snapshot() -> Dictionary:
	var value := super.snapshot()
	value.events = []
	value.airHockeyVersion = VERSION
	value.physicsAccumulator = clampf(_accumulator, 0.0, LOGIC_STEP)
	value.stars = stars()
	return value


func restore(value: Dictionary) -> bool:
	if _strict_int(value.get("airHockeyVersion", null)) != VERSION:
		return false
	if not super.restore(value):
		return false
	var mode := str(state.get("modeId", ""))
	if not mode in MODES:
		return _reject_restore()
	var arena := _normalize_arena(state.get("level", {}))
	if arena.is_empty() or not bool(validate_arena(arena).get("ok", false)):
		return _reject_restore()
	var level_id := _strict_int(state.get("levelId", null))
	var level_number := _strict_int(state.get("levelNumber", null))
	var normalized_number := _strict_int(arena.get("levelNumber", null))
	if level_id < 1 or level_number != level_id or normalized_number != level_id:
		return _reject_restore()
	if str(arena.get("mode", "")) != mode or str(state.get("levelKey", "")) != str(arena.get("id", "")):
		return _reject_restore()
	arena.levelNumber = level_id
	var players_value: Variant = state.get("players", [])
	if not players_value is Array or players_value.size() != (2 if mode == "classic" else 1):
		return _reject_restore()
	var phase := str(state.get("phase", ""))
	if phase not in ["playing", "finished"]:
		return _reject_restore()
	var scores_value: Variant = state.get("scores", null)
	if not scores_value is Array or scores_value.size() != 2:
		return _reject_restore()
	var scores: Array = []
	for raw in scores_value:
		var score := _strict_int(raw)
		if score < 0 or score > 99:
			return _reject_restore()
		scores.append(score)
	state.scores = scores
	state.playerScores = scores.duplicate()
	var targets_source := _build_targets(arena)
	var targets_value: Variant = state.get("targets", null)
	if not targets_value is Array or targets_value.size() != targets_source.size():
		return _reject_restore()
	var targets: Array = []
	var lit_count := 0
	for index in targets_value.size():
		var raw: Variant = targets_value[index]
		if not raw is Dictionary:
			return _reject_restore()
		var source: Dictionary = targets_source[index]
		var lit_value: Variant = raw.get("lit", false)
		if not lit_value is bool:
			return _reject_restore()
		var lit := bool(lit_value)
		source.lit = lit
		if lit:
			lit_count += 1
		targets.append(source)
	state.targets = targets
	state.targetTotal = targets.size()
	var targets_hit := _strict_int(state.get("targetsHit", lit_count))
	if targets_hit != lit_count:
		return _reject_restore()
	state.targetsHit = targets_hit
	var paddles_source := _build_paddles(mode, arena)
	var paddles_value: Variant = state.get("paddles", null)
	if not paddles_value is Array or paddles_value.size() != paddles_source.size():
		return _reject_restore()
	var paddles: Array = []
	for index in paddles_value.size():
		var raw: Variant = paddles_value[index]
		if not raw is Dictionary:
			return _reject_restore()
		var paddle: Dictionary = raw
		var x := _finite_float(paddle.get("x", -1.0))
		var y := _finite_float(paddle.get("y", -1.0))
		var target_x := _finite_float(paddle.get("targetX", -1.0))
		var target_y := _finite_float(paddle.get("targetY", -1.0))
		var radius := _finite_float(paddle.get("radius", 0.0))
		var source: Dictionary = paddles_source[index]
		if radius < 0.025 or radius > 0.1:
			return _reject_restore()
		if x < LEFT or x > RIGHT or y < TOP or y > BOTTOM:
			return _reject_restore()
		if target_x < LEFT or target_x > RIGHT or target_y < TOP or target_y > BOTTOM:
			return _reject_restore()
		var clean := source.duplicate(true)
		clean.x = x
		clean.y = y
		clean.targetX = target_x
		clean.targetY = target_y
		clean.dx = clampf(_finite_float(paddle.get("dx", 0.0)), -PADDLE_MAX_SPEED, PADDLE_MAX_SPEED)
		clean.dy = clampf(_finite_float(paddle.get("dy", 0.0)), -PADDLE_MAX_SPEED, PADDLE_MAX_SPEED)
		paddles.append(clean)
	state.paddles = paddles
	var puck_value: Variant = state.get("puck", {})
	var puck: Dictionary = {}
	if puck_value is Dictionary and not puck_value.is_empty():
		var x := _finite_float(puck_value.get("x", -1.0))
		var y := _finite_float(puck_value.get("y", -1.0))
		var vx := _finite_float(puck_value.get("vx", 0.0))
		var vy := _finite_float(puck_value.get("vy", 0.0))
		var speed := _finite_float(puck_value.get("speed", 0.0))
		if x < LEFT - 0.12 or x > RIGHT + 0.12 or y < TOP - 0.12 or y > BOTTOM + 0.12:
			return _reject_restore()
		if Vector2(vx, vy).length_squared() <= 0.0000001:
			return _reject_restore()
		if speed < MIN_PUCK_SPEED or speed > MAX_PUCK_SPEED:
			return _reject_restore()
		puck = {
			"x": x,
			"y": y,
			"vx": vx,
			"vy": vy,
			"speed": speed,
			"radius": clampf(_finite_float(puck_value.get("radius", PUCK_RADIUS)), 0.012, 0.04),
		}
	elif puck_value != null and not puck_value is Dictionary:
		return _reject_restore()
	state.puck = puck
	var table_seconds := _float_value(arena.get("tableSeconds", 45.0), 45.0)
	var time_left := _finite_float(state.get("timeLeft", -1.0))
	var elapsed := _finite_float(state.get("elapsed", -1.0))
	if time_left < 0.0 or time_left > table_seconds + 0.1 or elapsed < 0.0 or elapsed > table_seconds + 1.0:
		return _reject_restore()
	state.timeLeft = time_left
	state.elapsed = elapsed
	var serve_timer := _finite_float(state.get("serveTimer", 0.0))
	if serve_timer < 0.0 or serve_timer > SERVE_DELAY + 0.2:
		return _reject_restore()
	state.serveTimer = serve_timer
	state.nextServeX = clampi(_strict_int(state.get("nextServeX", 0)), -1, 1)
	state.lastScorer = clampi(_strict_int(state.get("lastScorer", -1)), -1, 1)
	state.maxScore = _strict_int(state.get("maxScore", 1))
	if state.maxScore < 1 or state.maxScore > 12:
		return _reject_restore()
	var expected_max := targets.size() if mode == "practice" else int(arena.get("targetScore", 1))
	if state.maxScore != expected_max:
		return _reject_restore()
	state.goals = scores.duplicate()
	state.wallHits = maxi(0, _strict_int(state.get("wallHits", 0)))
	state.paddleHits = maxi(0, _strict_int(state.get("paddleHits", 0)))
	state.hintsUsed = maxi(0, _strict_int(state.get("hintsUsed", 0)))
	var success_value: Variant = state.get("success", false)
	if not success_value is bool:
		return _reject_restore()
	state.success = bool(success_value)
	var winner := _strict_int(state.get("winner", -1))
	if winner < -1 or winner > 1 or (winner >= 0 and not state.success):
		return _reject_restore()
	state.winner = winner
	var outcome := str(state.get("outcome", ""))
	if outcome not in ["", "win", "draw", "played"]:
		return _reject_restore()
	state.outcome = outcome
	if phase == "playing":
		if not puck.is_empty() and mode == "practice" and targets_hit >= targets.size():
			return _reject_restore()
		if mode == "practice" and int(scores[1]) != 0:
			return _reject_restore()
		if mode == "classic" and (int(scores[0]) >= state.maxScore or int(scores[1]) >= state.maxScore):
			return _reject_restore()
	elif not puck.is_empty():
		return _reject_restore()
	if mode == "practice" and int(scores[0]) != targets_hit:
		return _reject_restore()
	if phase == "finished" and mode == "practice" and not state.success and time_left > 0.01:
		return _reject_restore()
	var reported_value: Variant = state.get("reported", false)
	if not reported_value is bool:
		return _reject_restore()
	state.reported = bool(reported_value)
	state.level = arena
	state.levelId = level_id
	state.levelNumber = level_id
	state.levelKey = str(arena.get("id", ""))
	state.levelTitle = str(arena.get("title", "冰球碰碰台"))
	state.levelBand = str(arena.get("band", "easy"))
	state.view = "board"
	state.events = []
	state.physicsAccumulator = clampf(_finite_float(value.get("physicsAccumulator", 0.0)), 0.0, LOGIC_STEP)
	_accumulator = float(state.physicsAccumulator)
	return true


func result() -> Dictionary:
	if str(state.get("phase", "")) != "finished":
		return {}
	var stars_by_seat: Array = []
	for seat in 2:
		stars_by_seat.append(stars_for_seat(seat))
	return {
		"phase": "finished",
		"success": bool(state.get("success", false)),
		"winner": int(state.get("winner", -1)),
		"outcome": str(state.get("outcome", "")),
		"reason": str(state.get("reason", "")),
		"scores": (state.get("scores", [0, 0]) as Array).duplicate(),
		"stars": stars(),
		"starsBySeat": stars_by_seat,
		"targetsHit": int(state.get("targetsHit", 0)),
		"targetTotal": int(state.get("targetTotal", 0)),
		"timeLeft": float(state.get("timeLeft", 0.0)),
		"modeId": str(state.get("modeId", "")),
	}


func stars() -> int:
	if str(state.get("phase", "")) != "finished":
		return 0
	if str(state.get("modeId", "")) == "classic":
		var highest := 0
		for seat in 2:
			highest = maxi(highest, stars_for_seat(seat))
		return highest
	if not bool(state.get("success", false)):
		return 0
	var arena := _arena()
	var table_seconds := maxf(1.0, _float_value(arena.get("tableSeconds", 45.0), 45.0))
	var time_ratio := clampf(_float_value(state.get("timeLeft", 0.0), 0.0) / table_seconds, 0.0, 1.0)
	var result_stars := 1
	if time_ratio >= 0.28:
		result_stars += 1
	if time_ratio >= 0.48:
		result_stars += 1
	return clampi(result_stars, 1, 3)


func stars_for_seat(seat: int) -> int:
	if seat < 0 or seat > 1 or str(state.get("phase", "")) != "finished":
		return 0
	if str(state.get("modeId", "")) != "classic":
		return stars()
	var scores: Array = state.get("scores", [0, 0])
	var own := int(scores[seat]) if seat < scores.size() else 0
	var other := int(scores[1 - seat]) if scores.size() > 1 else 0
	if own > other:
		return 3
	if own == other:
		return 2
	return 1


func outcome_for_seat(seat: int) -> String:
	if str(state.get("phase", "")) != "finished":
		return ""
	if str(state.get("modeId", "")) != "classic":
		return "win" if bool(state.get("success", false)) else "played"
	var scores: Array = state.get("scores", [0, 0])
	var own := int(scores[seat]) if seat < scores.size() else 0
	var other := int(scores[1 - seat]) if scores.size() > 1 else 0
	if own > other:
		return "win"
	if own < other:
		return "loss"
	return "draw"


func drain_events() -> Array:
	var events_value: Variant = state.get("events", [])
	var events: Array = events_value.duplicate(true) if events_value is Array else []
	state.events = []
	return events


func target_progress() -> Array:
	var result: Array = []
	var targets_value: Variant = state.get("targets", [])
	if not targets_value is Array:
		return result
	for index in targets_value.size():
		if targets_value[index] is Dictionary:
			var target: Dictionary = targets_value[index]
			result.append({
				"index": index,
				"label": str(target.get("label", "目标")),
				"lit": bool(target.get("lit", false)),
			})
	return result


func _step(step: float) -> void:
	var time_left := maxf(0.0, _float_value(state.get("timeLeft", 0.0), 0.0) - step)
	state.timeLeft = time_left
	state.elapsed = _float_value(state.get("elapsed", 0.0), 0.0) + step
	_update_paddles(step)
	var serve_timer := maxf(0.0, _float_value(state.get("serveTimer", 0.0), 0.0) - step)
	state.serveTimer = serve_timer
	var puck_value: Variant = state.get("puck", {})
	if puck_value is Dictionary and puck_value.is_empty() and serve_timer <= 0.0:
		_serve_puck()
	puck_value = state.get("puck", {})
	if puck_value is Dictionary and not puck_value.is_empty():
		_advance_puck(puck_value, step)
	if str(state.get("phase", "")) == "playing" and time_left <= 0.00001:
		_finish_for_time()


func _update_paddles(step: float) -> void:
	var paddles_value: Variant = state.get("paddles", [])
	if not paddles_value is Array:
		return
	var paddles: Array = paddles_value
	for index in paddles.size():
		var paddle: Dictionary = paddles[index]
		var x := _float_value(paddle.get("x", 0.5), 0.5)
		var y := _float_value(paddle.get("y", 0.5), 0.5)
		var target_x := _float_value(paddle.get("targetX", x), x)
		var target_y := _float_value(paddle.get("targetY", y), y)
		var move := Vector2(target_x - x, target_y - y)
		var distance := move.length()
		var allowance := PADDLE_MAX_SPEED * step
		var delta := move if distance <= allowance else move.normalized() * allowance
		paddle.dx = delta.x / maxf(0.000001, step)
		paddle.dy = delta.y / maxf(0.000001, step)
		paddle.x = x + delta.x
		paddle.y = y + delta.y
		paddles[index] = paddle
	state.paddles = paddles


func _serve_puck() -> void:
	var arena := _arena()
	var mode := str(state.get("modeId", "practice"))
	var direction_x := 0.0
	if mode == "practice":
		direction_x = -1.0
	else:
		var next_value := int(state.get("nextServeX", 0))
		if next_value == 0:
			direction_x = -1.0 if random.generator.randf() < 0.5 else 1.0
		else:
			direction_x = 1.0 if next_value > 0 else -1.0
	var angle := random.generator.randf_range(-0.42, 0.42)
	var direction := Vector2(direction_x * cos(angle), sin(angle))
	if direction.length_squared() <= 0.000001:
		direction = Vector2.LEFT
	direction = direction.normalized()
	var speed := clampf(_float_value(arena.get("puckSpeed", 0.62), 0.62), MIN_PUCK_SPEED, MAX_PUCK_SPEED)
	var physical_velocity := direction * speed
	state.puck = {
		"x": 0.5,
		"y": 0.5,
		"vx": physical_velocity.x / PLAY_ASPECT,
		"vy": physical_velocity.y,
		"speed": speed,
		"radius": PUCK_RADIUS,
	}
	state.serveTimer = 0.0
	state.nextServeX = 0
	_add_event({"type": "serve", "x": 0.5, "y": 0.5, "speed": speed})


func _advance_puck(puck: Dictionary, step: float) -> void:
	var x := _float_value(puck.get("x", 0.5), 0.5)
	var y := _float_value(puck.get("y", 0.5), 0.5)
	var radius := clampf(_float_value(puck.get("radius", PUCK_RADIUS), PUCK_RADIUS), 0.012, 0.04)
	var speed := clampf(_float_value(puck.get("speed", 0.6), 0.6), MIN_PUCK_SPEED, MAX_PUCK_SPEED)
	var velocity := Vector2(
		_float_value(puck.get("vx", 0.0), 0.0) * PLAY_ASPECT,
		_float_value(puck.get("vy", 0.0), 0.0)
	)
	if velocity.length_squared() <= 0.0000001:
		velocity = Vector2.LEFT * speed
	velocity = velocity.normalized() * speed
	var remaining := step
	var collisions := 0
	while remaining > 0.0000001 and collisions < 8 and str(state.get("phase", "")) == "playing":
		var hit := _earliest_hit(Vector2(x * PLAY_ASPECT, y), velocity, remaining)
		if hit.is_empty():
			x += velocity.x * remaining / PLAY_ASPECT
			y += velocity.y * remaining
			remaining = 0.0
			break
		var travel := clampf(float(hit.get("t", 0.0)), 0.0, remaining)
		x += velocity.x * travel / PLAY_ASPECT
		y += velocity.y * travel
		remaining -= travel
		var resolved := _resolve_hit(hit, velocity, speed)
		velocity = resolved.get("velocity", velocity)
		speed = float(resolved.get("speed", speed))
		x = float(resolved.get("x", x * PLAY_ASPECT)) / PLAY_ASPECT
		y = float(resolved.get("y", y))
		if bool(resolved.get("stops", false)):
			state.puck = {}
			return
		collisions += 1
		velocity = velocity.normalized() * speed
	puck.x = x
	puck.y = y
	puck.vx = velocity.x / PLAY_ASPECT
	puck.vy = velocity.y
	puck.speed = speed
	state.puck = puck
	if str(state.get("modeId", "")) == "classic":
		var goal_height := _float_value(_arena().get("goalHeight", 0.24), 0.24)
		var goal_top := 0.5 - goal_height * 0.5
		var goal_bottom := 0.5 + goal_height * 0.5
		if x < LEFT and y >= goal_top and y <= goal_bottom:
			_score_goal(1)
			return
		if x > RIGHT and y >= goal_top and y <= goal_bottom:
			_score_goal(0)
			return
	if x < LEFT - radius or x > RIGHT + radius or y < TOP - radius or y > BOTTOM + radius:
		_reset_after_escape()


func _earliest_hit(center: Vector2, velocity: Vector2, max_time: float) -> Dictionary:
	var hits: Array = []
	var top_hit := ArcadePhysics.sweep_circle_segment(
		center, velocity, PUCK_RADIUS,
		Vector2(LEFT * PLAY_ASPECT, TOP), Vector2(RIGHT * PLAY_ASPECT, TOP),
		0.0, max_time
	)
	if bool(top_hit.get("hit", false)):
		top_hit.kind = "wall"
		top_hit.side = "top"
		hits.append(top_hit)
	var bottom_hit := ArcadePhysics.sweep_circle_segment(
		center, velocity, PUCK_RADIUS,
		Vector2(LEFT * PLAY_ASPECT, BOTTOM), Vector2(RIGHT * PLAY_ASPECT, BOTTOM),
		0.0, max_time
	)
	if bool(bottom_hit.get("hit", false)):
		bottom_hit.kind = "wall"
		bottom_hit.side = "bottom"
		hits.append(bottom_hit)
	var goal_height := _float_value(_arena().get("goalHeight", 0.24), 0.24)
	var goal_top := 0.5 - goal_height * 0.5
	var goal_bottom := 0.5 + goal_height * 0.5
	if str(state.get("modeId", "")) == "classic":
		_add_wall_segment(hits, center, velocity, max_time, Vector2(LEFT * PLAY_ASPECT, TOP), Vector2(LEFT * PLAY_ASPECT, goal_top), "left_top")
		_add_wall_segment(hits, center, velocity, max_time, Vector2(LEFT * PLAY_ASPECT, goal_bottom), Vector2(LEFT * PLAY_ASPECT, BOTTOM), "left_bottom")
		_add_wall_segment(hits, center, velocity, max_time, Vector2(RIGHT * PLAY_ASPECT, TOP), Vector2(RIGHT * PLAY_ASPECT, goal_top), "right_top")
		_add_wall_segment(hits, center, velocity, max_time, Vector2(RIGHT * PLAY_ASPECT, goal_bottom), Vector2(RIGHT * PLAY_ASPECT, BOTTOM), "right_bottom")
	else:
		_add_wall_segment(hits, center, velocity, max_time, Vector2(LEFT * PLAY_ASPECT, TOP), Vector2(LEFT * PLAY_ASPECT, BOTTOM), "left")
		_add_wall_segment(hits, center, velocity, max_time, Vector2(RIGHT * PLAY_ASPECT, TOP), Vector2(RIGHT * PLAY_ASPECT, BOTTOM), "right")
	var paddles_value: Variant = state.get("paddles", [])
	if paddles_value is Array:
		for raw in paddles_value:
			if not raw is Dictionary:
				continue
			var paddle: Dictionary = raw
			var paddle_center := Vector2(
				_float_value(paddle.get("x", 0.5)) * PLAY_ASPECT,
				_float_value(paddle.get("y", 0.5))
			)
			var paddle_velocity := Vector2(
				_float_value(paddle.get("dx", 0.0)) * PLAY_ASPECT,
				_float_value(paddle.get("dy", 0.0))
			)
			var paddle_radius := _float_value(paddle.get("radius", 0.055), 0.055)
			var paddle_hit := ArcadePhysics.sweep_circle_circle(
				center, velocity, PUCK_RADIUS,
				paddle_center, paddle_velocity, paddle_radius,
				max_time
			)
			if bool(paddle_hit.get("hit", false)):
				paddle_hit.kind = "paddle"
				paddle_hit.id = "paddle:" + str(int(paddle.get("seat", 0)))
				paddle_hit.paddle = paddle
				hits.append(paddle_hit)
	if str(state.get("modeId", "")) == "practice":
		var targets_value: Variant = state.get("targets", [])
		if targets_value is Array:
			for index in targets_value.size():
				if not targets_value[index] is Dictionary:
					continue
				var target: Dictionary = targets_value[index]
				if bool(target.get("lit", false)):
					continue
				var target_hit := ArcadePhysics.sweep_circle_circle(
					center, velocity, PUCK_RADIUS,
					Vector2(_float_value(target.get("x", 0.5)) * PLAY_ASPECT, _float_value(target.get("y", 0.5))),
					Vector2.ZERO,
					_float_value(target.get("radius", 0.06), 0.06),
					max_time
				)
				if bool(target_hit.get("hit", false)):
					target_hit.kind = "target"
					target_hit.id = str(index)
					target_hit.targetIndex = index
					target_hit.target = target
					hits.append(target_hit)
	return ArcadePhysics.earliest_hit(hits)


func _add_wall_segment(
	hits: Array,
	center: Vector2,
	velocity: Vector2,
	max_time: float,
	start: Vector2,
	finish: Vector2,
	side: String
) -> void:
	if start.distance_squared_to(finish) <= 0.0000001:
		return
	var hit := ArcadePhysics.sweep_circle_segment(center, velocity, PUCK_RADIUS, start, finish, 0.0, max_time)
	if not bool(hit.get("hit", false)):
		return
	hit.kind = "wall"
	hit.side = side
	hits.append(hit)


func _resolve_hit(hit: Dictionary, velocity: Vector2, speed: float) -> Dictionary:
	var kind := str(hit.get("kind", ""))
	var normal := Vector2(hit.get("normal", Vector2.UP))
	var point := Vector2(hit.get("point", Vector2.ZERO))
	if kind == "wall":
		var reflected := ArcadePhysics.reflect_velocity(velocity, normal, 0.992, 0.01)
		if reflected.length_squared() <= 0.0000001:
			reflected = normal.normalized() * speed
		reflected = reflected.normalized() * speed
		state.wallHits = int(state.get("wallHits", 0)) + 1
		_add_event({
			"type": "wall",
			"x": point.x / PLAY_ASPECT,
			"y": point.y,
			"side": str(hit.get("side", "")),
			"color": "#9bcde0",
		})
		return {
			"velocity": reflected,
			"speed": speed,
			"x": point.x + normal.normalized().x * 0.001,
			"y": point.y + normal.normalized().y * 0.001,
			"stops": false,
		}
	if kind == "paddle":
		var paddle_value: Variant = hit.get("paddle", {})
		var paddle: Dictionary = paddle_value if paddle_value is Dictionary else {}
		var paddle_velocity := Vector2(
			_float_value(paddle.get("dx", 0.0)) * PLAY_ASPECT,
			_float_value(paddle.get("dy", 0.0))
		)
		var bounced := ArcadePhysics.bounce_relative(velocity, paddle_velocity, normal, 1.02, 0.02)
		if bounced.length_squared() <= 0.0000001:
			bounced = normal.normalized() * speed
		var new_speed := clampf(maxf(bounced.length(), speed * 0.92), MIN_PUCK_SPEED, MAX_PUCK_SPEED)
		bounced = bounced.normalized() * new_speed
		state.paddleHits = int(state.get("paddleHits", 0)) + 1
		_add_event({
			"type": "paddle",
			"seat": int(paddle.get("seat", 0)),
			"x": point.x / PLAY_ASPECT,
			"y": point.y,
			"color": "#f2d36b",
		})
		return {
			"velocity": bounced,
			"speed": new_speed,
			"x": point.x + normal.normalized().x * 0.0012,
			"y": point.y + normal.normalized().y * 0.0012,
			"stops": false,
		}
	if kind == "target":
		_hit_target(int(hit.get("targetIndex", -1)))
		return {"velocity": velocity, "speed": speed, "x": point.x, "y": point.y, "stops": true}
	return {
		"velocity": velocity,
		"speed": speed,
		"x": point.x,
		"y": point.y,
		"stops": false,
	}


func _hit_target(index: int) -> void:
	var targets_value: Variant = state.get("targets", [])
	if not targets_value is Array or index < 0 or index >= targets_value.size():
		return
	var targets: Array = targets_value
	if not targets[index] is Dictionary:
		return
	var target: Dictionary = targets[index]
	if bool(target.get("lit", false)):
		return
	target.lit = true
	targets[index] = target
	state.targets = targets
	state.targetsHit = int(state.get("targetsHit", 0)) + 1
	state.scores[0] = int(state.scores[0]) + 1
	state.playerScores = state.scores.duplicate()
	_add_event({
		"type": "target",
		"index": index,
		"x": _float_value(target.get("x", 0.5)),
		"y": _float_value(target.get("y", 0.5)),
		"label": str(target.get("label", "目标")),
		"lit": int(state.targetsHit),
		"total": int(state.targetTotal),
		"color": "#f2cf69",
	})
	state.puck = {}
	if int(state.targetsHit) >= int(state.targetTotal):
		_finish_practice()
	else:
		state.serveTimer = 0.8
		state.nextServeX = -1
		_add_event({"type": "serve_ready", "x": 0.5, "y": 0.5})


func _score_goal(scorer: int) -> void:
	if str(state.get("phase", "")) != "playing":
		return
	var scores: Array = state.scores
	scores[scorer] = int(scores[scorer]) + 1
	state.scores = scores
	state.playerScores = scores.duplicate()
	state.goals = scores.duplicate()
	state.lastScorer = scorer
	_add_event({
		"type": "goal",
		"seat": scorer,
		"x": LEFT if scorer == 0 else RIGHT,
		"y": 0.5,
		"score": int(scores[scorer]),
		"color": "#f1c95f" if scorer == 0 else "#e78070",
	})
	state.puck = {}
	var target_score := int(state.get("maxScore", 5))
	if int(scores[scorer]) >= target_score:
		_finish_classic(scorer)
		return
	state.serveTimer = SERVE_DELAY
	state.nextServeX = 1 if scorer == 0 else -1
	_add_event({"type": "serve_ready", "x": 0.5, "y": 0.5})


func _finish_practice() -> void:
	if str(state.get("phase", "")) == "finished":
		return
	state.phase = "finished"
	state.success = int(state.get("targetsHit", 0)) >= int(state.get("targetTotal", 1))
	state.winner = 0 if state.success else -1
	state.outcome = "win" if state.success else "played"
	state.puck = {}
	state.serveTimer = 0.0
	state.reason = "所有目标都亮起来啦！" if state.success else "时间到了，再试一次会更快。"
	state.stars = stars()
	_add_event({
		"type": "complete",
		"success": bool(state.success),
		"x": 0.5,
		"y": 0.5,
	})


func _finish_classic(winner: int) -> void:
	if str(state.get("phase", "")) == "finished":
		return
	state.phase = "finished"
	state.success = true
	state.winner = clampi(winner, -1, 1)
	state.outcome = "draw" if state.winner < 0 else "win"
	state.puck = {}
	state.serveTimer = 0.0
	state.reason = "比赛结束，看看两边的得分。" if state.winner < 0 else "比赛结束，%s先拿到目标分！" % ("左边" if state.winner == 0 else "右边")
	state.stars = stars()
	_add_event({"type": "complete", "success": true, "x": 0.5, "y": 0.5})


func _finish_for_time() -> void:
	if str(state.get("modeId", "")) == "practice":
		_finish_practice()
		return
	var scores: Array = state.get("scores", [0, 0])
	var winner := -1
	if int(scores[0]) > int(scores[1]):
		winner = 0
	elif int(scores[1]) > int(scores[0]):
		winner = 1
	_finish_classic(winner)
	if winner < 0:
		state.outcome = "draw"
		state.reason = "时间到，两边得分一样，是平局。"
	else:
		state.outcome = "win"
		state.reason = "时间到，%s得分更多。" % ("左边" if winner == 0 else "右边")


func _reset_after_escape() -> void:
	state.puck = {}
	state.serveTimer = 0.65
	state.nextServeX = 0
	_add_event({"type": "escape", "x": 0.5, "y": 0.5})
	_add_event({"type": "serve_ready", "x": 0.5, "y": 0.5})


func _arena() -> Dictionary:
	var value: Variant = state.get("level", {})
	return value if value is Dictionary else {}


func _paddle_index(seat: int) -> int:
	var paddles_value: Variant = state.get("paddles", [])
	if not paddles_value is Array:
		return -1
	for index in paddles_value.size():
		if paddles_value[index] is Dictionary and int(paddles_value[index].get("seat", -1)) == seat:
			return index
	return -1


func _add_event(event: Dictionary) -> void:
	var events_value: Variant = state.get("events", [])
	var events: Array = events_value if events_value is Array else []
	events.append(event)
	while events.size() > MAX_EVENTS:
		events.pop_front()
	state.events = events


func _reject_restore() -> bool:
	state = {}
	_accumulator = 0.0
	return false


func _build_targets(arena: Dictionary) -> Array:
	var source: Variant = arena.get("targets", [])
	var result: Array = []
	if not source is Array:
		return result
	for index in source.size():
		if not source[index] is Dictionary:
			continue
		var target: Dictionary = source[index]
		result.append({
			"id": int(target.get("id", index + 1)),
			"label": str(target.get("label", "星门 %s" % (index + 1))),
			"x": _float_value(target.get("x", 0.65), 0.65),
			"y": _float_value(target.get("y", 0.5), 0.5),
			"radius": _float_value(target.get("radius", 0.06), 0.06),
			"lit": false,
		})
	return result


func _build_paddles(mode: String, arena: Dictionary) -> Array:
	var radius := clampf(_float_value(arena.get("paddleRadius", 0.052), 0.052), 0.03, 0.09)
	if mode == "classic":
		return [
			{"seat": 0, "x": 0.22, "y": 0.5, "targetX": 0.22, "targetY": 0.5, "dx": 0.0, "dy": 0.0, "radius": radius},
			{"seat": 1, "x": 0.78, "y": 0.5, "targetX": 0.78, "targetY": 0.5, "dx": 0.0, "dy": 0.0, "radius": radius},
		]
	return [
		{"seat": 0, "x": 0.22, "y": 0.5, "targetX": 0.22, "targetY": 0.5, "dx": 0.0, "dy": 0.0, "radius": radius},
	]


func _normalize_arena(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return {}
	var source: Dictionary = value
	var targets_value: Variant = source.get("targets", [])
	if not targets_value is Array:
		return {}
	var targets: Array = []
	for index in targets_value.size():
		if not targets_value[index] is Dictionary:
			return {}
		var target: Dictionary = targets_value[index]
		targets.append({
			"id": _int_value(target.get("id", index + 1), index + 1),
			"label": str(target.get("label", "星门 %s" % (index + 1))),
			"x": _finite_float(target.get("x", 0.65)),
			"y": _finite_float(target.get("y", 0.5)),
			"radius": _finite_float(target.get("radius", 0.06)),
		})
	return {
		"id": str(source.get("id", "")),
		"levelNumber": _int_value(source.get("levelNumber", 0), 0),
		"mode": str(source.get("mode", "")),
		"band": str(source.get("band", "")),
		"minAge": _int_value(source.get("minAge", 0), 0),
		"title": str(source.get("title", "冰球碰碰台")),
		"tableSeconds": _finite_float(source.get("tableSeconds", 45.0)),
		"targetScore": _int_value(source.get("targetScore", 5), 5),
		"puckSpeed": _finite_float(source.get("puckSpeed", 0.62)),
		"goalHeight": _finite_float(source.get("goalHeight", 0.24)),
		"paddleRadius": _finite_float(source.get("paddleRadius", 0.052)),
		"targets": targets,
		"hint": str(source.get("hint", "把球拍放在冰球后方，再向球门方向滑过去。")),
		"explanation": str(source.get("explanation", "轻推球拍控制方向，快速滑过冰球可以让它跑得更快。")),
	}


static func validate_catalog(value: Variant) -> Dictionary:
	var issues: Array[String] = []
	var valid_arenas: Array = []
	if not value is Dictionary:
		return {"ok": false, "issues": ["air_hockey.json 顶层必须是对象"], "validArenas": []}
	var source: Dictionary = value
	if str(source.get("id", "")) != "air_hockey":
		issues.append("id 必须是 air_hockey")
	if _value_int(source.get("schemaVersion", 1), 1) < 1:
		issues.append("schemaVersion 无效")
	var arenas_value: Variant = source.get("arenas", [])
	if not arenas_value is Array:
		issues.append("arenas 必须是数组")
		return {"ok": false, "issues": issues, "validArenas": []}
	var arenas: Array = arenas_value
	if arenas.size() != 18:
		issues.append("应有 18 张冰球台，实际 %s 张" % arenas.size())
	var ids := {}
	var counters := {"practice": {}, "classic": {}}
	for index in arenas.size():
		var arena_value: Variant = arenas[index]
		var validation := validate_arena(arena_value)
		if not bool(validation.get("ok", false)):
			for issue in validation.get("issues", []):
				issues.append("第 %s 项：%s" % [index + 1, str(issue)])
			continue
		var arena: Dictionary = arena_value
		var identifier := str(arena.get("id", ""))
		if ids.has(identifier):
			issues.append("重复冰球台 id：%s" % identifier)
		ids[identifier] = true
		var mode := str(arena.get("mode", ""))
		var band := str(arena.get("band", ""))
		if counters.has(mode):
			counters[mode][band] = int(counters[mode].get(band, 0)) + 1
		valid_arenas.append(arena.duplicate(true))
	for mode in ["practice", "classic"]:
		var expected_total := 12 if mode == "practice" else 6
		var expected_band := 4 if mode == "practice" else 2
		var total := 0
		for band in BANDS:
			var count := int(counters[mode].get(band, 0))
			total += count
			if count != expected_band:
				issues.append("%s 的 %s 台应为 %s 张，实际 %s 张" % [mode, band, expected_band, count])
		if total != expected_total:
			issues.append("%s 台应为 %s 张，实际 %s 张" % [mode, expected_total, total])
	valid_arenas.sort_custom(func(first, second):
		var first_mode := str(first.get("mode", ""))
		var second_mode := str(second.get("mode", ""))
		if first_mode != second_mode:
			return first_mode == "practice"
		return int(first.get("levelNumber", 0)) < int(second.get("levelNumber", 0))
	)
	var expected_numbers := {"practice": 1, "classic": 1}
	for arena in valid_arenas:
		var mode := str(arena.get("mode", ""))
		var number := int(arena.get("levelNumber", 0))
		if number != int(expected_numbers.get(mode, 1)):
			issues.append("%s 的场地编号应连续，发现 %s" % [mode, number])
		expected_numbers[mode] = int(expected_numbers.get(mode, 1)) + 1
	return {"ok": issues.is_empty(), "issues": issues, "validArenas": valid_arenas}


static func validate_arena(value: Variant) -> Dictionary:
	var issues: Array[String] = []
	if not value is Dictionary:
		return {"ok": false, "issues": ["冰球台必须是对象"]}
	var arena: Dictionary = value
	if str(arena.get("id", "")).strip_edges().is_empty():
		issues.append("缺少 id")
	var mode := str(arena.get("mode", ""))
	if not mode in MODES:
		issues.append("mode 必须是 practice 或 classic")
	var band := str(arena.get("band", ""))
	if not band in BANDS:
		issues.append("band 必须是 easy、normal 或 challenge")
	var min_age := _value_int(arena.get("minAge", 0), 0)
	if min_age < 4 or min_age > 12:
		issues.append("minAge 必须在 4–12")
	var number := _value_int(arena.get("levelNumber", 0), 0)
	if number < 1 or number > 12:
		issues.append("levelNumber 无效")
	var seconds := _value_float(arena.get("tableSeconds", 0.0))
	if seconds < 20.0 or seconds > 150.0:
		issues.append("tableSeconds 超出范围")
	var puck_speed := _value_float(arena.get("puckSpeed", 0.0))
	if puck_speed < MIN_PUCK_SPEED or puck_speed > MAX_PUCK_SPEED:
		issues.append("puckSpeed 超出范围")
	var goal_height := _value_float(arena.get("goalHeight", 0.0))
	if goal_height < 0.12 or goal_height > 0.4:
		issues.append("goalHeight 超出范围")
	var paddle_radius := _value_float(arena.get("paddleRadius", 0.0))
	if paddle_radius < 0.03 or paddle_radius > 0.09:
		issues.append("paddleRadius 超出范围")
	var target_score := _value_int(arena.get("targetScore", 0), 0)
	var targets_value: Variant = arena.get("targets", [])
	if not targets_value is Array:
		issues.append("targets 必须是数组")
		return {"ok": false, "issues": issues}
	var targets: Array = targets_value
	if mode == "classic":
		if target_score < 1 or target_score > 9:
			issues.append("targetScore 必须在 1–9")
		if not targets.is_empty():
			issues.append("双人冰球台不应有练习目标")
	else:
		if targets.size() < 2 or targets.size() > 6:
			issues.append("练习目标应有 2–6 个")
		if target_score != targets.size():
			issues.append("练习 targetScore 必须等于目标数量")
	var target_ids := {}
	for index in targets.size():
		if not targets[index] is Dictionary:
			issues.append("目标必须是对象")
			continue
		var target: Dictionary = targets[index]
		var identifier := _value_int(target.get("id", index + 1), index + 1)
		if target_ids.has(identifier):
			issues.append("重复目标 id %s" % identifier)
		target_ids[identifier] = true
		var x := _value_float(target.get("x", -1.0))
		var y := _value_float(target.get("y", -1.0))
		var radius := _value_float(target.get("radius", 0.0))
		if x < LEFT + radius or x > RIGHT - radius or y < TOP + radius or y > BOTTOM - radius:
			issues.append("目标 %s 超出场地" % identifier)
		if radius < 0.035 or radius > 0.08:
			issues.append("目标 %s 半径超出范围" % identifier)
	return {"ok": issues.is_empty(), "issues": issues}


static func _value_int(value: Variant, fallback: int = 0) -> int:
	return int(value) if value is int or value is float else fallback


static func _value_float(value: Variant, fallback: float = 0.0) -> float:
	return float(value) if value is int or value is float else fallback


func _int_value(value: Variant, fallback: int = 0) -> int:
	return int(value) if value is int or value is float else fallback


func _float_value(value: Variant, fallback: float = 0.0) -> float:
	return float(value) if value is int or value is float else fallback


func _finite_float(value: Variant) -> float:
	if not (value is int or value is float):
		return 0.0
	var result := float(value)
	return result if is_finite(result) else 0.0


func _strict_int(value: Variant) -> int:
	if value is int:
		return int(value)
	if value is float and is_finite(float(value)) and is_equal_approx(float(value), float(int(value))):
		return int(value)
	return INVALID_INT
