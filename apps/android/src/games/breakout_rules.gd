class_name BreakoutRules
extends GameSession

const VERSION := 1
const LOGIC_HZ := ArcadePhysics.STEP_HZ
const LOGIC_STEP := ArcadePhysics.STEP_DELTA
const MAX_FRAME_STEPS := 24
const MAX_EVENTS := 64
const MODES := ["adventure", "classic"]
const BANDS := ["easy", "normal", "challenge"]
const POWERUPS := ["wide", "slow", "heart"]
const FIELD_LEFT := 0.035
const FIELD_RIGHT := 0.965
const FIELD_TOP := 0.055
const FIELD_BOTTOM := 0.965
const BRICK_TOP := 0.105
const BRICK_GAP := 0.004
const PADDLE_Y := 0.905
const PADDLE_HEIGHT := 0.026
const BALL_RADIUS := 0.017
const PADDLE_SPEED := 1.85
const MAX_BALL_SPEED := 1.15
const MAX_POWERUPS := 10
const MAX_BRICKS := 120
const MAX_LIVES := 8
const INVALID_INT := -2147483648

var _accumulator := 0.0


func create_session(context: Dictionary) -> Dictionary:
	super.create_session(context)
	var mode := str(context.get("modeId", "adventure"))
	if not mode in MODES:
		mode = "adventure"
	var level := _normalize_level(context.get("level", {}))
	var level_id := maxi(1, _int_value(context.get("levelId", 1), 1))
	var level_number := _int_value(level.get("levelNumber", level_id), level_id)
	var required_players := 2 if mode == "classic" else 1
	var players_value: Variant = state.get("players", [])
	var player_count: int = players_value.size() if players_value is Array else 0
	if (
		level.is_empty()
		or str(level.get("mode", "")) != mode
		or level_id != level_number
		or player_count != required_players
		or not bool(validate_level(level).get("ok", false))
	):
		state.merge({
			"breakoutVersion": VERSION,
			"gameId": "breakout",
			"modeId": mode,
			"levelId": level_id,
			"levelNumber": level_number,
			"levelKey": "",
			"level": {},
			"view": "map",
			"phase": "empty",
			"reason": "这一座砖块城堡还没有准备好",
			"events": [],
			"reported": false,
			"success": false,
			"winner": -1,
			"stars": 0,
		}, true)
		_accumulator = 0.0
		return state
	level.levelNumber = level_id
	var bricks := _build_bricks(level)
	var paddles := _build_paddles(level, mode)
	state.merge({
		"breakoutVersion": VERSION,
		"gameId": "breakout",
		"modeId": mode,
		"levelId": level_id,
		"levelNumber": level_id,
		"levelKey": str(level.get("id", "")),
		"levelTitle": str(level.get("title", "砖块小城堡")),
		"levelBand": str(level.get("band", "easy")),
		"level": level,
		"view": "board",
		"phase": "playing",
		"reason": "",
		"success": false,
		"winner": -1,
		"score": 0,
		"lives": int(level.get("lives", 3)),
		"bricks": bricks,
		"bricksTotal": bricks.size(),
		"bricksBroken": 0,
		"bricksDamaged": 0,
		"paddles": paddles,
		"balls": [],
		"powerups": [],
		"nextBallId": 1,
		"nextPowerupId": 1,
		"serveTimer": 0.8,
		"slowTimer": 0.0,
		"combo": 0,
		"bestCombo": 0,
		"physicsAccumulator": 0.0,
		"events": [],
		"reported": false,
		"difficulty": str(context.get("difficulty", "normal")),
	}, true)
	_accumulator = 0.0
	return state


func handle_input(action: Dictionary) -> Dictionary:
	match str(action.get("type", "")):
		"move":
			return move_paddle(
				_int_value(action.get("seat", 0), 0),
				_float_value(action.get("x", 0.5), 0.5)
			)
		"serve":
			return serve()
		"hint":
			return hint()
	return {"ok": false, "changed": false, "message": "这个操作现在不能用"}


func move_paddle(seat: int, x: float) -> Dictionary:
	if str(state.get("phase", "")) != "playing":
		return {"ok": false, "changed": false, "message": "这一座城堡已经结束啦"}
	var index := _paddle_index(seat)
	if index < 0:
		return {"ok": false, "changed": false, "message": "找不到这块挡板"}
	var paddles_value: Array = state.get("paddles", [])
	var paddle: Dictionary = paddles_value[index]
	var width := _float_value(paddle.get("width", 0.15), 0.15)
	var left := FIELD_LEFT + width * 0.5
	var right := FIELD_RIGHT - width * 0.5
	if str(state.get("modeId", "")) == "classic":
		if seat == 0:
			right = minf(right, 0.5 - width * 0.5 - 0.008)
		else:
			left = maxf(left, 0.5 + width * 0.5 + 0.008)
	var target := clampf(x, left, right)
	var changed := absf(_float_value(paddle.get("targetX", target), target) - target) > 0.0001
	paddle.targetX = target
	paddles_value[index] = paddle
	state.paddles = paddles_value
	return {"ok": true, "changed": changed, "seat": seat, "x": target}


func serve() -> Dictionary:
	if str(state.get("phase", "")) != "playing":
		return {"ok": false, "changed": false, "message": "这一座城堡已经结束啦"}
	var balls_value: Variant = state.get("balls", [])
	if balls_value is Array and not balls_value.is_empty():
		return {"ok": false, "changed": false, "message": "小球已经在场上了"}
	state.serveTimer = 0.0
	_add_event({"type": "serve_ready", "x": 0.5, "y": PADDLE_Y - 0.08})
	return {"ok": true, "changed": true}


func hint() -> Dictionary:
	if str(state.get("phase", "")) != "playing":
		return {"ok": false, "message": "这一座城堡已经结束啦"}
	var level := _level()
	state.hintsUsed = int(state.get("hintsUsed", 0)) + 1
	return {
		"ok": true,
		"changed": true,
		"hint": str(level.get("hint", "先看准小球落点，再轻轻把挡板移到下面。")),
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
	value.breakoutVersion = VERSION
	value.physicsAccumulator = clampf(_accumulator, 0.0, LOGIC_STEP)
	value.stars = stars()
	return value


func restore(value: Dictionary) -> bool:
	if _strict_int(value.get("breakoutVersion", null)) != VERSION:
		return false
	if not super.restore(value):
		return false
	var mode := str(state.get("modeId", ""))
	if not mode in MODES:
		return _reject_restore()
	var level := _normalize_level(state.get("level", {}))
	if level.is_empty() or not bool(validate_level(level).get("ok", false)):
		return _reject_restore()
	var level_id := _strict_int(state.get("levelId", null))
	var level_number := _strict_int(state.get("levelNumber", null))
	var normalized_number := _strict_int(level.get("levelNumber", null))
	if level_id < 1 or level_number != level_id or normalized_number != level_id:
		return _reject_restore()
	if str(level.get("mode", "")) != mode or str(state.get("levelKey", "")) != str(level.get("id", "")):
		return _reject_restore()
	level.levelNumber = level_id
	var players_value: Variant = state.get("players", [])
	if not players_value is Array or players_value.size() != (2 if mode == "classic" else 1):
		return _reject_restore()
	var phase := str(state.get("phase", ""))
	if phase not in ["playing", "finished"]:
		return _reject_restore()
	var lives := _strict_int(state.get("lives", null))
	if lives < 0 or lives > MAX_LIVES:
		return _reject_restore()
	var score := _strict_int(state.get("score", null))
	var broken := _strict_int(state.get("bricksBroken", null))
	var damaged := _strict_int(state.get("bricksDamaged", null))
	if score < 0 or score > 1000000 or broken < 0 or broken > MAX_BRICKS or damaged < 0 or damaged > MAX_BRICKS * 2:
		return _reject_restore()
	var expected_bricks := _build_bricks(level)
	var bricks_value: Variant = state.get("bricks", null)
	if not bricks_value is Array or bricks_value.size() > expected_bricks.size():
		return _reject_restore()
	var expected_by_id := {}
	for brick in expected_bricks:
		expected_by_id[str(brick.get("id", ""))] = brick
	var seen_bricks := {}
	var bricks: Array = []
	for raw in bricks_value:
		if not raw is Dictionary:
			return _reject_restore()
		var brick: Dictionary = raw
		var identifier := str(brick.get("id", ""))
		if not expected_by_id.has(identifier) or seen_bricks.has(identifier):
			return _reject_restore()
		var source: Dictionary = expected_by_id[identifier]
		var hp := _strict_int(brick.get("hp", null))
		if hp < 1 or hp > _strict_int(source.get("maxHp", 1)):
			return _reject_restore()
		var normalized := source.duplicate(true)
		normalized.hp = hp
		seen_bricks[identifier] = true
		bricks.append(normalized)
	state.bricks = bricks
	var expected_total := expected_bricks.size()
	if int(state.get("bricksTotal", expected_total)) != expected_total:
		return _reject_restore()
	var paddles_value: Variant = state.get("paddles", null)
	if not paddles_value is Array or paddles_value.size() != (2 if mode == "classic" else 1):
		return _reject_restore()
	var paddles: Array = []
	for index in paddles_value.size():
		var raw: Variant = paddles_value[index]
		if not raw is Dictionary:
			return _reject_restore()
		var paddle: Dictionary = raw
		var width := _finite_float(paddle.get("width", 0.0))
		var base_width := _finite_float(paddle.get("baseWidth", 0.0))
		var x := _finite_float(paddle.get("x", -1.0))
		var target := _finite_float(paddle.get("targetX", -1.0))
		if width < 0.08 or width > 0.42 or base_width < 0.08 or base_width > 0.36:
			return _reject_restore()
		if x < FIELD_LEFT or x > FIELD_RIGHT or target < FIELD_LEFT or target > FIELD_RIGHT:
			return _reject_restore()
		paddles.append({
			"seat": index,
			"x": x,
			"targetX": target,
			"dx": clampf(_finite_float(paddle.get("dx", 0.0)), -1.0, 1.0),
			"width": width,
			"baseWidth": base_width,
			"height": PADDLE_HEIGHT,
			"y": PADDLE_Y,
		})
	state.paddles = paddles
	var balls_value: Variant = state.get("balls", null)
	if not balls_value is Array or balls_value.size() > 1:
		return _reject_restore()
	var balls: Array = []
	for raw in balls_value:
		if not raw is Dictionary:
			return _reject_restore()
		var ball: Dictionary = raw
		var identifier := _strict_int(ball.get("id", null))
		var x := _finite_float(ball.get("x", -1.0))
		var y := _finite_float(ball.get("y", -1.0))
		var vx := _finite_float(ball.get("vx", 0.0))
		var vy := _finite_float(ball.get("vy", 0.0))
		var speed := _finite_float(ball.get("speed", 0.0))
		if identifier < 1 or identifier > 1000000 or x < FIELD_LEFT - 0.1 or x > FIELD_RIGHT + 0.1:
			return _reject_restore()
		if y < FIELD_TOP - 0.1 or y > FIELD_BOTTOM + 0.18 or speed <= 0.0 or speed > MAX_BALL_SPEED:
			return _reject_restore()
		if Vector2(vx, vy).length_squared() <= 0.0000001:
			return _reject_restore()
		balls.append({
			"id": identifier,
			"x": x,
			"y": y,
			"vx": vx,
			"vy": vy,
			"speed": speed,
			"radius": BALL_RADIUS,
		})
	state.balls = balls
	var powerups_value: Variant = state.get("powerups", null)
	if not powerups_value is Array or powerups_value.size() > MAX_POWERUPS:
		return _reject_restore()
	var powerups: Array = []
	for raw in powerups_value:
		if not raw is Dictionary:
			return _reject_restore()
		var powerup: Dictionary = raw
		var kind := str(powerup.get("kind", ""))
		var identifier := _strict_int(powerup.get("id", null))
		var x := _finite_float(powerup.get("x", -1.0))
		var y := _finite_float(powerup.get("y", -1.0))
		if not kind in POWERUPS or identifier < 1 or x < FIELD_LEFT or x > FIELD_RIGHT or y < FIELD_TOP or y > FIELD_BOTTOM:
			return _reject_restore()
		powerups.append({"id": identifier, "kind": kind, "x": x, "y": y, "vy": 0.14})
	state.powerups = powerups
	var slow_timer := _finite_float(state.get("slowTimer", 0.0))
	var serve_timer := _finite_float(state.get("serveTimer", 0.0))
	if slow_timer < 0.0 or slow_timer > 15.0 or serve_timer < 0.0 or serve_timer > 3.0:
		return _reject_restore()
	state.slowTimer = slow_timer
	state.serveTimer = serve_timer
	state.bestCombo = maxi(0, _strict_int(state.get("bestCombo", 0)))
	state.combo = clampi(_strict_int(state.get("combo", 0)), 0, 200)
	state.hintsUsed = maxi(0, _strict_int(state.get("hintsUsed", 0)))
	state.nextBallId = maxi(1, _strict_int(state.get("nextBallId", 1)))
	state.nextPowerupId = maxi(1, _strict_int(state.get("nextPowerupId", 1)))
	state.lives = lives
	state.score = score
	state.bricksBroken = broken
	state.bricksDamaged = damaged
	state.success = bool(state.get("success", false))
	state.winner = -1 if mode == "classic" else (0 if state.success else -1)
	state.reported = bool(state.get("reported", false))
	state.level = level
	state.levelId = level_id
	state.levelNumber = level_id
	state.levelKey = str(level.get("id", ""))
	state.levelTitle = str(level.get("title", "砖块小城堡"))
	state.levelBand = str(level.get("band", "easy"))
	state.view = "board"
	state.events = []
	state.physicsAccumulator = clampf(_finite_float(value.get("physicsAccumulator", 0.0)), 0.0, LOGIC_STEP)
	_accumulator = float(state.physicsAccumulator)
	return true


func result() -> Dictionary:
	if str(state.get("phase", "")) != "finished":
		return {}
	return {
		"phase": "finished",
		"success": bool(state.get("success", false)),
		"winner": int(state.get("winner", -1)),
		"reason": str(state.get("reason", "")),
		"score": int(state.get("score", 0)),
		"stars": stars(),
		"lives": int(state.get("lives", 0)),
		"bricksBroken": int(state.get("bricksBroken", 0)),
		"bricksTotal": int(state.get("bricksTotal", 0)),
		"bestCombo": int(state.get("bestCombo", 0)),
		"modeId": str(state.get("modeId", "")),
	}


func stars() -> int:
	if str(state.get("phase", "")) != "finished" or not bool(state.get("success", false)):
		return 0
	var lives := int(state.get("lives", 0))
	var value := 1
	if lives >= 2:
		value += 1
	if lives >= 4:
		value += 1
	return clampi(value, 1, 3)


func powerup_locations() -> Array:
	return state.get("powerups", []).duplicate(true)


func drain_events() -> Array:
	var events_value: Variant = state.get("events", [])
	var events: Array = events_value.duplicate(true) if events_value is Array else []
	state.events = []
	return events


func _step(step: float) -> void:
	var slow_timer := maxf(0.0, _finite_float(state.get("slowTimer", 0.0)) - step)
	state.slowTimer = slow_timer
	_update_paddles(step)
	var serve_timer := maxf(0.0, _finite_float(state.get("serveTimer", 0.0)) - step)
	state.serveTimer = serve_timer
	var balls_value: Variant = state.get("balls", [])
	if balls_value is Array and balls_value.is_empty() and serve_timer <= 0.0:
		_serve_ball()
	_update_powerups(step)
	balls_value = state.get("balls", [])
	if not balls_value is Array or balls_value.is_empty():
		return
	var balls: Array = balls_value
	var kept: Array = []
	for raw in balls:
		if not raw is Dictionary or str(state.get("phase", "")) != "playing":
			continue
		var ball: Dictionary = raw
		var lost := _advance_ball(ball, step)
		if not lost and str(state.get("phase", "")) == "playing":
			kept.append(ball)
	state.balls = kept
	if str(state.get("phase", "")) != "playing":
		return
	if kept.is_empty():
		_lose_ball()


func _update_paddles(step: float) -> void:
	var paddles_value: Variant = state.get("paddles", [])
	if not paddles_value is Array:
		return
	var paddles: Array = paddles_value
	for index in paddles.size():
		var paddle: Dictionary = paddles[index]
		var x := _float_value(paddle.get("x", 0.5), 0.5)
		var target := _float_value(paddle.get("targetX", x), x)
		var delta := clampf(target - x, -PADDLE_SPEED * step, PADDLE_SPEED * step)
		paddle.dx = delta / maxf(0.000001, step)
		paddle.x = x + delta
		paddles[index] = paddle
	state.paddles = paddles


func _serve_ball() -> void:
	var level := _level()
	var speed := clampf(_float_value(level.get("ballSpeed", 0.55), 0.55), 0.3, MAX_BALL_SPEED)
	var angle := random.generator.randf_range(-0.48, 0.48)
	var direction := Vector2(sin(angle), -cos(angle)).normalized()
	var paddles_value: Variant = state.get("paddles", [])
	var x := 0.5
	var y := PADDLE_Y - PADDLE_HEIGHT * 0.5 - BALL_RADIUS - 0.022
	if str(state.get("modeId", "")) == "adventure" and paddles_value is Array and not paddles_value.is_empty():
		x = clampf(_float_value(paddles_value[0].get("x", 0.5), 0.5), FIELD_LEFT + BALL_RADIUS, FIELD_RIGHT - BALL_RADIUS)
	var ball_id := int(state.get("nextBallId", 1))
	state.nextBallId = ball_id + 1
	var balls_value: Variant = state.get("balls", [])
	var balls: Array = balls_value if balls_value is Array else []
	balls = [{
		"id": ball_id,
		"x": x,
		"y": y,
		"vx": direction.x * speed,
		"vy": direction.y * speed,
		"speed": speed,
		"radius": BALL_RADIUS,
	}]
	state.balls = balls
	_add_event({"type": "serve", "x": x, "y": y, "ballId": ball_id})
	_add_event({"type": "launch", "x": x, "y": y})


func _advance_ball(ball: Dictionary, step: float) -> bool:
	var x := _float_value(ball.get("x", 0.5), 0.5)
	var y := _float_value(ball.get("y", 0.5), 0.5)
	var vx := _float_value(ball.get("vx", 0.0), 0.0)
	var vy := _float_value(ball.get("vy", 0.0), 0.0)
	var base_speed := clampf(_float_value(ball.get("speed", 0.5), 0.5), 0.3, MAX_BALL_SPEED)
	var speed := base_speed
	if float(state.get("slowTimer", 0.0)) > 0.0:
		speed *= 0.72
	var direction := Vector2(vx, vy)
	if direction.length_squared() <= 0.0000001:
		direction = Vector2(0.0, -1.0)
	direction = direction.normalized()
	var velocity := direction * speed
	var remaining := step
	var collisions := 0
	while remaining > 0.0000001 and collisions < 7 and str(state.get("phase", "")) == "playing":
		var hit := _earliest_hit(Vector2(x, y), velocity, remaining)
		if hit.is_empty():
			x += velocity.x * remaining
			y += velocity.y * remaining
			remaining = 0.0
			break
		var travel := clampf(float(hit.get("t", 0.0)), 0.0, remaining)
		x += velocity.x * travel
		y += velocity.y * travel
		remaining -= travel
		velocity = _resolve_hit(hit, velocity, speed)
		collisions += 1
		if remaining <= 0.0000001:
			break
	ball.x = x
	ball.y = y
	ball.vx = velocity.x
	ball.vy = velocity.y
	ball.speed = base_speed
	if y - BALL_RADIUS > FIELD_BOTTOM:
		_add_event({"type": "ball_lost", "x": x, "y": minf(FIELD_BOTTOM, y), "ballId": int(ball.get("id", 0))})
		return true
	return false


func _earliest_hit(center: Vector2, velocity: Vector2, max_time: float) -> Dictionary:
	var hits: Array = []
	var top_hit := ArcadePhysics.sweep_circle_segment(
		center, velocity, BALL_RADIUS,
		Vector2(FIELD_LEFT, FIELD_TOP), Vector2(FIELD_RIGHT, FIELD_TOP),
		0.0, max_time
	)
	if bool(top_hit.get("hit", false)):
		top_hit.kind = "wall"
		top_hit.id = "top"
		hits.append(top_hit)
	var left_hit := ArcadePhysics.sweep_circle_segment(
		center, velocity, BALL_RADIUS,
		Vector2(FIELD_LEFT, FIELD_TOP), Vector2(FIELD_LEFT, FIELD_BOTTOM),
		0.0, max_time
	)
	if bool(left_hit.get("hit", false)):
		left_hit.kind = "wall"
		left_hit.id = "left"
		hits.append(left_hit)
	var right_hit := ArcadePhysics.sweep_circle_segment(
		center, velocity, BALL_RADIUS,
		Vector2(FIELD_RIGHT, FIELD_TOP), Vector2(FIELD_RIGHT, FIELD_BOTTOM),
		0.0, max_time
	)
	if bool(right_hit.get("hit", false)):
		right_hit.kind = "wall"
		right_hit.id = "right"
		hits.append(right_hit)
	var bricks_value: Variant = state.get("bricks", [])
	if bricks_value is Array:
		for raw in bricks_value:
			if not raw is Dictionary:
				continue
			var brick: Dictionary = raw
			var rect := Rect2(
				Vector2(_float_value(brick.get("x", 0.0)), _float_value(brick.get("y", 0.0))),
				Vector2(_float_value(brick.get("w", 0.0)), _float_value(brick.get("h", 0.0)))
			)
			var brick_hit := ArcadePhysics.sweep_circle_rect(center, velocity, BALL_RADIUS, rect, Vector2.ZERO, max_time)
			if bool(brick_hit.get("hit", false)):
				brick_hit.kind = "brick"
				brick_hit.id = str(brick.get("id", ""))
				brick_hit.brick = brick
				hits.append(brick_hit)
	var paddles_value: Variant = state.get("paddles", [])
	if paddles_value is Array:
		for raw in paddles_value:
			if not raw is Dictionary:
				continue
			var paddle: Dictionary = raw
			var width := _float_value(paddle.get("width", 0.15))
			var rect := Rect2(
				Vector2(_float_value(paddle.get("x", 0.5)) - width * 0.5, PADDLE_Y - PADDLE_HEIGHT * 0.5),
				Vector2(width, PADDLE_HEIGHT)
			)
			var paddle_hit := ArcadePhysics.sweep_circle_rect(
				center, velocity, BALL_RADIUS, rect,
				Vector2(_float_value(paddle.get("dx", 0.0)), 0.0),
				max_time
			)
			if bool(paddle_hit.get("hit", false)):
				paddle_hit.kind = "paddle"
				paddle_hit.id = "paddle:" + str(int(paddle.get("seat", 0)))
				paddle_hit.paddle = paddle
				hits.append(paddle_hit)
	var earliest := ArcadePhysics.earliest_hit(hits)
	return earliest


func _resolve_hit(hit: Dictionary, velocity: Vector2, speed: float) -> Vector2:
	var kind := str(hit.get("kind", ""))
	var normal := Vector2(hit.get("normal", Vector2.UP))
	var point := Vector2(hit.get("point", Vector2.ZERO))
	var new_velocity := velocity
	if kind == "paddle":
		var paddle_value: Variant = hit.get("paddle", {})
		var paddle: Dictionary = paddle_value if paddle_value is Dictionary else {}
		var paddle_x := _float_value(paddle.get("x", 0.5))
		var paddle_width := maxf(0.01, _float_value(paddle.get("width", 0.15)))
		var english := clampf((point.x - paddle_x) / (paddle_width * 0.5), -1.0, 1.0)
		new_velocity = ArcadePhysics.reflect_velocity(velocity, normal, 1.0, 0.0)
		new_velocity.y = -absf(new_velocity.y)
		new_velocity.x = clampf(new_velocity.x + english * speed * 0.42 + _float_value(paddle.get("dx", 0.0)) * 0.035, -speed * 0.9, speed * 0.9)
		new_velocity = new_velocity.normalized() * speed
		_add_event({
			"type": "paddle",
			"seat": int(paddle.get("seat", 0)),
			"x": point.x,
			"y": point.y,
			"color": "#f2d36b",
		})
		state.combo = 0
	elif kind == "brick":
		new_velocity = ArcadePhysics.reflect_velocity(velocity, normal, 0.995, 0.0)
		new_velocity = new_velocity.normalized() * speed
		_hit_brick(hit)
	elif kind == "wall":
		new_velocity = ArcadePhysics.reflect_velocity(velocity, normal, 0.998, 0.0)
		new_velocity = new_velocity.normalized() * speed
		_add_event({"type": "bounce", "x": point.x, "y": point.y, "color": "#bde5e4"})
	var post := Vector2(hit.get("point", Vector2.ZERO)) + normal.normalized() * 0.0008
	var balls_value: Variant = state.get("balls", [])
	if balls_value is Array:
		var balls: Array = balls_value
		if not balls.is_empty() and balls[0] is Dictionary:
			balls[0].x = post.x
			balls[0].y = post.y
			state.balls = balls
	if new_velocity.length_squared() > 0.0000001:
		new_velocity = new_velocity.normalized() * speed
	return new_velocity


func _hit_brick(hit: Dictionary) -> void:
	var brick_value: Variant = hit.get("brick", {})
	var brick: Dictionary = brick_value if brick_value is Dictionary else {}
	if brick.is_empty():
		return
	var identifier := str(brick.get("id", ""))
	var bricks_value: Variant = state.get("bricks", [])
	if not bricks_value is Array:
		return
	var bricks: Array = bricks_value
	var index := -1
	for cursor in bricks.size():
		if bricks[cursor] is Dictionary and str(bricks[cursor].get("id", "")) == identifier:
			index = cursor
			break
	if index < 0:
		return
	var target: Dictionary = bricks[index]
	var hp := maxi(1, _int_value(target.get("hp", 1), 1)) - 1
	var color := str(target.get("color", "#e7b73c"))
	var point := Vector2(hit.get("point", Vector2.ZERO))
	state.combo = mini(200, int(state.get("combo", 0)) + 1)
	state.bestCombo = maxi(int(state.get("bestCombo", 0)), int(state.combo))
	if hp > 0:
		target.hp = hp
		bricks[index] = target
		state.bricks = bricks
		state.bricksDamaged = int(state.get("bricksDamaged", 0)) + 1
		state.score = int(state.get("score", 0)) + 20 + int(state.combo) * 2
		_add_event({
			"type": "brick_hit",
			"id": identifier,
			"x": point.x,
			"y": point.y,
			"color": color,
			"hp": hp,
			"combo": int(state.combo),
		})
		return
	bricks.remove_at(index)
	state.bricks = bricks
	state.bricksBroken = int(state.get("bricksBroken", 0)) + 1
	state.score = int(state.get("score", 0)) + 80 + int(state.combo) * 5
	_add_event({
		"type": "brick",
		"id": identifier,
		"x": point.x,
		"y": point.y,
		"color": color,
		"combo": int(state.combo),
	})
	_maybe_drop_powerup(point, color)
	if bricks.is_empty():
		_finish(true)


func _maybe_drop_powerup(position: Vector2, color: String) -> void:
	var level := _level()
	var kinds: Array = level.get("powerups", POWERUPS)
	if kinds.is_empty():
		return
	var chance := clampf(_float_value(level.get("powerupChance", 0.16), 0.16), 0.0, 0.5)
	if random.generator.randf() > chance:
		return
	var powerups_value: Variant = state.get("powerups", [])
	if not powerups_value is Array:
		return
	var powerups: Array = powerups_value
	if powerups.size() >= MAX_POWERUPS:
		return
	var powerup_id := int(state.get("nextPowerupId", 1))
	state.nextPowerupId = powerup_id + 1
	var kind := str(kinds[random.generator.randi_range(0, kinds.size() - 1)])
	powerups.append({
		"id": powerup_id,
		"kind": kind,
		"x": clampf(position.x, FIELD_LEFT + 0.03, FIELD_RIGHT - 0.03),
		"y": clampf(position.y + 0.02, FIELD_TOP + 0.04, FIELD_BOTTOM - 0.08),
		"vy": 0.14,
	})
	state.powerups = powerups
	_add_event({
		"type": "powerup_drop",
		"id": powerup_id,
		"kind": kind,
		"x": position.x,
		"y": position.y,
		"color": color,
	})


func _update_powerups(step: float) -> void:
	var powerups_value: Variant = state.get("powerups", [])
	if not powerups_value is Array or powerups_value.is_empty():
		return
	var paddles_value: Variant = state.get("paddles", [])
	var paddles: Array = paddles_value if paddles_value is Array else []
	var remaining: Array = []
	for raw in powerups_value:
		if not raw is Dictionary:
			continue
		var powerup: Dictionary = raw
		powerup.y = _float_value(powerup.get("y", 0.0), 0.0) + _float_value(powerup.get("vy", 0.14), 0.14) * step
		var caught := false
		for paddle_value in paddles:
			if not paddle_value is Dictionary:
				continue
			var paddle: Dictionary = paddle_value
			var width := _float_value(paddle.get("width", 0.15), 0.15)
			var paddle_rect := Rect2(
				Vector2(_float_value(paddle.get("x", 0.5), 0.5) - width * 0.5, PADDLE_Y - PADDLE_HEIGHT * 0.5),
				Vector2(width, PADDLE_HEIGHT)
			)
			if paddle_rect.grow(0.03).has_point(Vector2(_float_value(powerup.get("x", 0.0)), _float_value(powerup.get("y", 0.0)))):
				_apply_powerup(str(powerup.get("kind", "")), paddle)
				_add_event({
					"type": "powerup_collect",
					"kind": str(powerup.get("kind", "")),
					"seat": int(paddle.get("seat", 0)),
					"x": _float_value(powerup.get("x", 0.0)),
					"y": _float_value(powerup.get("y", 0.0)),
					"color": "#f4cf69",
				})
				caught = true
				break
		if not caught and _float_value(powerup.get("y", 0.0), 0.0) <= FIELD_BOTTOM:
			remaining.append(powerup)
	state.powerups = remaining


func _apply_powerup(kind: String, paddle: Dictionary) -> void:
	match kind:
		"heart":
			state.lives = mini(MAX_LIVES, int(state.get("lives", 0)) + 1)
			_add_event({"type": "heart_bonus", "x": _float_value(paddle.get("x", 0.5)), "y": PADDLE_Y - 0.08})
		"slow":
			state.slowTimer = 8.0
			for ball in state.get("balls", []):
				if ball is Dictionary:
					ball.speed = clampf(_float_value(ball.get("speed", 0.5), 0.5), 0.3, MAX_BALL_SPEED)
		"wide":
			var width := minf(0.42, _float_value(paddle.get("width", 0.15), 0.15) + 0.055)
			paddle.width = width
			paddle.targetX = clampf(_float_value(paddle.get("targetX", paddle.x), 0.5), FIELD_LEFT + width * 0.5, FIELD_RIGHT - width * 0.5)
			var paddles_value: Array = state.get("paddles", [])
			var seat := int(paddle.get("seat", 0))
			if seat >= 0 and seat < paddles_value.size():
				paddles_value[seat] = paddle
				state.paddles = paddles_value


func _lose_ball() -> void:
	var lives := maxi(0, int(state.get("lives", 0)) - 1)
	state.lives = lives
	state.combo = 0
	_add_event({"type": "heart_lost", "x": 0.5, "y": PADDLE_Y, "lives": lives})
	if lives <= 0:
		_finish(false)
		return
	state.serveTimer = 0.9
	_add_event({"type": "serve_ready", "x": 0.5, "y": PADDLE_Y - 0.08})


func _finish(success: bool) -> void:
	if str(state.get("phase", "")) == "finished":
		return
	state.phase = "finished"
	state.success = success
	state.events = []
	state.serveTimer = 0.0
	state.powerups = []
	state.balls = []
	state.winner = 0 if success and str(state.get("modeId", "")) != "classic" else -1
	state.reason = "砖块全部敲下，城堡完成啦！" if success else "爱心用完啦，再看看小球落点。"
	state.stars = stars()
	_add_event({
		"type": "complete",
		"success": success,
		"x": 0.5,
		"y": PADDLE_Y - 0.18,
	})


func _level() -> Dictionary:
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


func _build_bricks(level: Dictionary) -> Array:
	var rows: Array = level.get("rows", [])
	var columns := maxi(1, _int_value(level.get("columns", 10), 10))
	var top := clampf(_float_value(level.get("brickTop", BRICK_TOP), BRICK_TOP), FIELD_TOP + 0.02, PADDLE_Y - 0.2)
	var height := clampf(_float_value(level.get("brickHeight", 0.034), 0.034), 0.024, 0.055)
	var width := (FIELD_RIGHT - FIELD_LEFT) / float(columns)
	var palette_value: Variant = level.get("palette", {})
	var palette: Dictionary = palette_value if palette_value is Dictionary else {}
	var armor: Array = level.get("armor", [])
	var result: Array = []
	for row in rows.size():
		if not rows[row] is String:
			continue
		var text := str(rows[row])
		var count := mini(columns, text.length())
		for column in count:
			var key := text.substr(column, 1)
			if key == "." or key.strip_edges().is_empty() or not palette.has(key):
				continue
			var color := str(palette[key])
			if not Color.html_is_valid(color):
				color = "#e7b73c"
			var max_hp := 2 if key in armor else 1
			result.append({
				"id": "%s:%s" % [row, column],
				"row": row,
				"col": column,
				"x": FIELD_LEFT + float(column) * width + BRICK_GAP * 0.5,
				"y": top + float(row) * (height + BRICK_GAP),
				"w": maxf(0.012, width - BRICK_GAP),
				"h": height,
				"hp": max_hp,
				"maxHp": max_hp,
				"color": color,
			})
	return result


func _build_paddles(level: Dictionary, mode: String) -> Array:
	var base_width := clampf(_float_value(level.get("paddleWidth", 0.18), 0.18), 0.1, 0.34)
	if mode == "classic":
		base_width = minf(base_width, 0.19)
		return [
			{"seat": 0, "x": 0.27, "targetX": 0.27, "dx": 0.0, "width": base_width, "baseWidth": base_width, "height": PADDLE_HEIGHT, "y": PADDLE_Y},
			{"seat": 1, "x": 0.73, "targetX": 0.73, "dx": 0.0, "width": base_width, "baseWidth": base_width, "height": PADDLE_HEIGHT, "y": PADDLE_Y},
		]
	return [
		{"seat": 0, "x": 0.5, "targetX": 0.5, "dx": 0.0, "width": base_width, "baseWidth": base_width, "height": PADDLE_HEIGHT, "y": PADDLE_Y},
	]


func _normalize_level(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return {}
	var source: Dictionary = value
	var rows_value: Variant = source.get("rows", [])
	if not rows_value is Array:
		return {}
	var rows: Array = []
	for row in rows_value:
		if not row is String:
			return {}
		rows.append(str(row))
	var palette_value: Variant = source.get("palette", {})
	if not palette_value is Dictionary:
		return {}
	var palette: Dictionary = {}
	for key in palette_value:
		if not Color.html_is_valid(str(palette_value[key])):
			return {}
		palette[str(key)] = str(palette_value[key])
	var armor_value: Variant = source.get("armor", [])
	var armor: Array = []
	if armor_value is Array:
		for key in armor_value:
			armor.append(str(key))
	var powerups_value: Variant = source.get("powerups", POWERUPS)
	var powerups: Array = []
	if powerups_value is Array:
		for type_value in powerups_value:
			if str(type_value) in POWERUPS:
				powerups.append(str(type_value))
	return {
		"id": str(source.get("id", "")),
		"levelNumber": _int_value(source.get("levelNumber", 0), 0),
		"mode": str(source.get("mode", "")),
		"band": str(source.get("band", "")),
		"minAge": _int_value(source.get("minAge", 0), 0),
		"title": str(source.get("title", "砖块小城堡")),
		"rows": rows,
		"columns": _int_value(source.get("columns", 10), 10),
		"palette": palette,
		"armor": armor,
		"lives": _int_value(source.get("lives", 3), 3),
		"ballSpeed": _finite_float(source.get("ballSpeed", 0.55)),
		"paddleWidth": _finite_float(source.get("paddleWidth", 0.18)),
		"powerups": powerups,
		"powerupChance": _finite_float(source.get("powerupChance", 0.16)),
		"brickTop": _finite_float(source.get("brickTop", BRICK_TOP)),
		"brickHeight": _finite_float(source.get("brickHeight", 0.034)),
		"hint": str(source.get("hint", "接住小球，再找砖块最薄的地方。")),
		"explanation": str(source.get("explanation", "每一次弹起都在给下一块砖块找角度。")),
	}


static func validate_catalog(value: Variant) -> Dictionary:
	var issues: Array[String] = []
	var valid_levels: Array = []
	if not value is Dictionary:
		return {"ok": false, "issues": ["breakout.json 顶层必须是对象"], "validLevels": []}
	var source: Dictionary = value
	if str(source.get("id", "")) != "breakout":
		issues.append("id 必须是 breakout")
	if _value_int(source.get("schemaVersion", 1), 1) < 1:
		issues.append("schemaVersion 无效")
	var levels_value: Variant = source.get("levels", [])
	if not levels_value is Array:
		issues.append("levels 必须是数组")
		return {"ok": false, "issues": issues, "validLevels": []}
	var levels: Array = levels_value
	if levels.size() != 24:
		issues.append("应有 24 个砖块关，实际 %s 个" % levels.size())
	var ids := {}
	var counters := {"adventure": {}, "classic": {}}
	for index in levels.size():
		var level_value: Variant = levels[index]
		var validation := validate_level(level_value)
		if not bool(validation.get("ok", false)):
			for issue in validation.get("issues", []):
				issues.append("第 %s 项：%s" % [index + 1, str(issue)])
			continue
		var level: Dictionary = level_value
		var identifier := str(level.get("id", ""))
		if ids.has(identifier):
			issues.append("重复关卡 id：%s" % identifier)
		ids[identifier] = true
		var mode := str(level.get("mode", ""))
		var band := str(level.get("band", ""))
		if counters.has(mode):
			counters[mode][band] = int(counters[mode].get(band, 0)) + 1
		valid_levels.append(level.duplicate(true))
	for mode in ["adventure", "classic"]:
		var expected_total := 18 if mode == "adventure" else 6
		var expected_band := 6 if mode == "adventure" else 2
		var total := 0
		for band in BANDS:
			var count := int(counters[mode].get(band, 0))
			total += count
			if count != expected_band:
				issues.append("%s 的 %s 关应为 %s 个，实际 %s 个" % [mode, band, expected_band, count])
		if total != expected_total:
			issues.append("%s 关应为 %s 个，实际 %s 个" % [mode, expected_total, total])
	valid_levels.sort_custom(func(first, second):
		var first_mode := str(first.get("mode", ""))
		var second_mode := str(second.get("mode", ""))
		if first_mode != second_mode:
			return first_mode == "adventure"
		return int(first.get("levelNumber", 0)) < int(second.get("levelNumber", 0))
	)
	var expected_numbers := {"adventure": 1, "classic": 1}
	for level in valid_levels:
		var mode := str(level.get("mode", ""))
		var number := int(level.get("levelNumber", 0))
		if number != int(expected_numbers.get(mode, 1)):
			issues.append("%s 的关卡编号应连续，发现 %s" % [mode, number])
		expected_numbers[mode] = int(expected_numbers.get(mode, 1)) + 1
	return {"ok": issues.is_empty(), "issues": issues, "validLevels": valid_levels}


static func validate_level(value: Variant) -> Dictionary:
	var issues: Array[String] = []
	if not value is Dictionary:
		return {"ok": false, "issues": ["关卡必须是对象"]}
	var level: Dictionary = value
	if str(level.get("id", "")).strip_edges().is_empty():
		issues.append("缺少 id")
	var mode := str(level.get("mode", ""))
	if not mode in MODES:
		issues.append("mode 必须是 adventure 或 classic")
	var band := str(level.get("band", ""))
	if not band in BANDS:
		issues.append("band 必须是 easy、normal 或 challenge")
	var min_age := _value_int(level.get("minAge", 0), 0)
	if min_age < 4 or min_age > 12:
		issues.append("minAge 必须在 4–12")
	var level_number := _value_int(level.get("levelNumber", 0), 0)
	if level_number < 1 or level_number > 18:
		issues.append("levelNumber 无效")
	var columns := _value_int(level.get("columns", 0), 0)
	if columns < 6 or columns > 12:
		issues.append("columns 必须在 6–12")
	var rows_value: Variant = level.get("rows", null)
	if not rows_value is Array:
		issues.append("rows 必须是数组")
		return {"ok": false, "issues": issues}
	var rows: Array = rows_value
	if rows.size() < 2 or rows.size() > 8:
		issues.append("rows 应有 2–8 排")
	var palette_value: Variant = level.get("palette", null)
	if not palette_value is Dictionary:
		issues.append("palette 必须是对象")
		return {"ok": false, "issues": issues}
	var palette: Dictionary = palette_value
	if palette.is_empty():
		issues.append("palette 不能为空")
	for key in palette:
		if str(key).length() != 1 or not Color.html_is_valid(str(palette[key])):
			issues.append("palette 含有无效颜色 %s" % key)
	var brick_count := 0
	for row_index in rows.size():
		if not rows[row_index] is String:
			issues.append("第 %s 排必须是字符串" % (row_index + 1))
			continue
		var row_text := str(rows[row_index])
		if row_text.length() != columns:
			issues.append("第 %s 排应有 %s 格" % [row_index + 1, columns])
		for character_index in row_text.length():
			var key := row_text.substr(character_index, 1)
			if key == ".":
				continue
			if not palette.has(key):
				issues.append("第 %s 排含有未定义砖块 %s" % [row_index + 1, key])
			else:
				brick_count += 1
	if brick_count < 6:
		issues.append("可破砖块太少")
	var lives := _value_int(level.get("lives", 0), 0)
	if lives < 1 or lives > 6:
		issues.append("lives 必须在 1–6")
	var ball_speed := _value_float(level.get("ballSpeed", 0.0))
	if ball_speed < 0.3 or ball_speed > MAX_BALL_SPEED:
		issues.append("ballSpeed 超出范围")
	var paddle_width := _value_float(level.get("paddleWidth", 0.0))
	if paddle_width < 0.1 or paddle_width > 0.34:
		issues.append("paddleWidth 超出范围")
	var powerups_value: Variant = level.get("powerups", [])
	if powerups_value is Array:
		for kind in powerups_value:
			if not str(kind) in POWERUPS:
				issues.append("未知道具 %s" % str(kind))
	var powerup_chance := _value_float(level.get("powerupChance", 0.16))
	if powerup_chance < 0.0 or powerup_chance > 0.5:
		issues.append("powerupChance 超出范围")
	var top := _value_float(level.get("brickTop", BRICK_TOP))
	var height := _value_float(level.get("brickHeight", 0.034))
	if top < FIELD_TOP or top + float(rows.size()) * (height + BRICK_GAP) > PADDLE_Y - 0.12:
		issues.append("砖块区域超出场地")
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
	var number := float(value)
	return number if is_finite(number) else 0.0


func _strict_int(value: Variant) -> int:
	if value is int:
		return int(value)
	if value is float and is_finite(float(value)) and is_equal_approx(float(value), float(int(value))):
		return int(value)
	return INVALID_INT
