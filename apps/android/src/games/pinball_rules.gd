class_name PinballRules
extends GameSession

const VERSION := 1
const LOGIC_HZ := ArcadePhysics.STEP_HZ
const LOGIC_STEP := ArcadePhysics.STEP_DELTA
const MAX_FRAME_STEPS := 24
const MAX_EVENTS := 72
const MODES := ["adventure", "classic"]
const BANDS := ["easy", "normal", "challenge"]
const INVALID_INT := -2147483648
const EPSILON := 0.000001
const MAX_BALL_SPEED := 2.4

var _accumulator := 0.0


func create_session(context: Dictionary) -> Dictionary:
	super.create_session(context)
	var mode := str(context.get("modeId", "adventure"))
	if not mode in MODES:
		mode = "adventure"
	var level_id := maxi(1, _int_value(context.get("levelId", 1), 1))
	var table_value: Variant = context.get("level", {})
	var table: Dictionary = (table_value.duplicate(true) if table_value is Dictionary else {})
	var table_number := INVALID_INT
	var table_validation := {"ok": false, "issues": []}
	if not table.is_empty():
		table_number = _strict_int(table.get("levelNumber", null))
		table_validation = validate_table(table, level_id)
	if table_number != level_id or not bool(table_validation.get("ok", false)):
		table = {}
	if not table.is_empty() and str(table.get("mode", "")) != mode:
		table = {}
	var players_value: Variant = state.get("players", [])
	var player_count: int = players_value.size() if players_value is Array else 0
	var required_players := 2 if mode == "classic" else 1
	if table.is_empty() or player_count != required_players:
		state.merge({
			"pinballVersion": VERSION,
			"gameId": "pinball",
			"modeId": mode,
			"levelId": level_id,
			"levelNumber": level_id,
			"levelKey": "",
			"level": {},
			"view": "map",
			"phase": "empty",
			"reason": "这张弹珠台还没有准备好",
			"events": [],
			"reported": false,
			"winner": -1,
			"outcome": "",
			"stars": 0,
		}, true)
		_accumulator = 0.0
		return state
	var target_count := (table.get("targets", []) as Array).size()
	var target_lights: Array = []
	for _index in target_count:
		target_lights.append(false)
	var bumper_count := (table.get("bumpers", []) as Array).size()
	var bumper_hits: Array = []
	for _index in bumper_count:
		bumper_hits.append(0)
	var flippers: Dictionary = table.get("flippers", {})
	var left_flipper: Dictionary = flippers.get("left", {})
	var right_flipper: Dictionary = flippers.get("right", {})
	var launch: Dictionary = table.get("launch", {})
	state.merge({
		"pinballVersion": VERSION,
		"gameId": "pinball",
		"modeId": mode,
		"levelId": level_id,
		"levelNumber": level_id,
		"levelKey": str(table.get("id", "")),
		"levelTitle": str(table.get("title", "弹珠星轨")),
		"levelBand": str(table.get("band", "easy")),
		"level": table,
		"view": "board",
		"phase": "playing",
		"reason": "",
		"success": false,
		"score": 0,
		"targetsLit": target_lights,
		"bumperHits": bumper_hits,
		"pendingClear": false,
		"ballsLeft": int(table.get("balls", 3)),
		"ballNumber": 1,
		"savesRemaining": int(table.get("saves", 1)),
		"ballSavesUsed": 0,
		"ball": {
			"status": "ready",
			"x": _float_value(launch.get("x", 0.91), 0.91),
			"y": _float_value(launch.get("y", 0.88), 0.88),
			"vx": 0.0,
			"vy": 0.0,
			"age": 0.0,
			"slowTime": 0.0,
		},
		"flippersPressed": {"left": false, "right": false},
		"flipperAngles": {
			"left": deg_to_rad(_float_value(left_flipper.get("restAngle", 25.0), 25.0)),
			"right": deg_to_rad(_float_value(right_flipper.get("restAngle", 155.0), 155.0)),
		},
		"elapsed": 0.0,
		"hintsUsed": 0,
		"physicsAccumulator": 0.0,
		"events": [],
		"reported": false,
		"winner": -1,
		"outcome": "",
		"stars": 0,
		"difficulty": str(context.get("difficulty", "normal")),
	}, true)
	_accumulator = 0.0
	return state


func handle_input(action: Dictionary) -> Dictionary:
	match str(action.get("type", "")):
		"flipper":
			return set_flipper(
				str(action.get("side", "")),
				bool(action.get("pressed", false)),
				_int_value(action.get("seat", 0), 0)
			)
		"launch":
			return launch_ball(_int_value(action.get("seat", 0), 0))
		"release_all":
			release_all_flippers()
			return {"ok": true, "changed": true}
		"hint":
			return hint()
	return {"ok": false, "changed": false, "message": "这个操作现在不能用"}


func set_flipper(side: String, pressed: bool, seat: int) -> Dictionary:
	if str(state.get("phase", "")) != "playing":
		return {"ok": false, "changed": false, "message": "这张弹珠台已经结束啦"}
	if side not in ["left", "right"]:
		return {"ok": false, "changed": false, "message": "找不到这块弹板"}
	var mode := str(state.get("modeId", "adventure"))
	var expected_seat := 0 if side == "left" or mode == "adventure" else 1
	if seat != expected_seat:
		return {"ok": false, "changed": false, "message": "这块弹板由另一位小朋友操作"}
	var press_value: Variant = state.get("flippersPressed", {})
	var pressed_map: Dictionary = press_value.duplicate(true) if press_value is Dictionary else {"left": false, "right": false}
	var previous := bool(pressed_map.get(side, false))
	if previous == pressed:
		return {"ok": true, "changed": false}
	pressed_map[side] = pressed
	state.flippersPressed = pressed_map
	var flippers: Dictionary = _table().get("flippers", {})
	var definition: Dictionary = flippers.get(side, {})
	var pivot_value: Variant = definition.get("pivot", [0.5, 0.8])
	var pivot := Vector2(0.5, 0.8)
	if pivot_value is Array and pivot_value.size() >= 2:
		pivot = Vector2(_float_value(pivot_value[0], 0.5), _float_value(pivot_value[1], 0.8))
	_add_event({
		"type": "flipper",
		"side": side,
		"seat": seat,
		"pressed": pressed,
		"x": pivot.x,
		"y": pivot.y,
	})
	return {"ok": true, "changed": true, "side": side, "pressed": pressed}


func release_all_flippers() -> void:
	var press_value: Variant = state.get("flippersPressed", {})
	var pressed_map: Dictionary = press_value.duplicate(true) if press_value is Dictionary else {}
	pressed_map["left"] = false
	pressed_map["right"] = false
	state.flippersPressed = pressed_map


func launch_ball(_seat: int = 0) -> Dictionary:
	if str(state.get("phase", "")) != "playing":
		return {"ok": false, "changed": false, "message": "这张弹珠台已经结束啦"}
	var ball_value: Variant = state.get("ball", {})
	if not ball_value is Dictionary:
		return {"ok": false, "changed": false, "message": "弹珠还没有准备好"}
	var ball: Dictionary = ball_value
	if str(ball.get("status", "")) != "ready":
		return {"ok": false, "changed": false, "message": "弹珠已经在轨道上啦"}
	var launch: Dictionary = _table().get("launch", {})
	var launch_degrees := clampf(_float_value(launch.get("angle", -12.0), -12.0), -42.0, -12.0)
	var angle := deg_to_rad(launch_degrees)
	var power := clampf(_float_value(launch.get("power", 1.0), 1.0), 0.4, 1.8)
	ball.status = "live"
	ball.vx = sin(angle) * power
	ball.vy = -cos(angle) * power
	ball.age = 0.0
	ball.slowTime = 0.0
	state.ball = ball
	_add_event({
		"type": "launch",
		"x": _float_value(ball.get("x", 0.5), 0.5),
		"y": _float_value(ball.get("y", 0.8), 0.8),
		"power": power,
	})
	return {"ok": true, "changed": true, "ballNumber": int(state.get("ballNumber", 1))}


func hint() -> Dictionary:
	if str(state.get("phase", "")) != "playing":
		return {"ok": false, "message": "这张弹珠台已经结束啦"}
	state.hintsUsed = int(state.get("hintsUsed", 0)) + 1
	var labels := target_progress()
	var next_label := ""
	var next_index := -1
	for entry in labels:
		if not bool(entry.get("lit", false)):
			next_label = str(entry.get("label", "目标灯"))
			next_index = int(entry.get("index", -1))
			break
	var message := str(_table().get("hint", "用左右弹板把弹珠送回上方，点亮全部目标灯。"))
	if next_index >= 0:
		message = "%s 先试着点亮「%s」。" % [message, next_label]
	return {
		"ok": true,
		"changed": true,
		"hint": message,
		"targetIndex": next_index,
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


func _step(delta: float) -> void:
	_update_flippers(delta)
	var ball_value: Variant = state.get("ball", {})
	if not ball_value is Dictionary:
		return
	var ball: Dictionary = ball_value
	if str(ball.get("status", "")) != "live":
		return
	state.elapsed = float(state.get("elapsed", 0.0)) + delta
	ball.age = _float_value(ball.get("age", 0.0), 0.0) + delta
	var table := _table()
	var gravity := clampf(_float_value(table.get("gravity", 0.42), 0.42), 0.08, 1.2)
	var max_speed := clampf(_float_value(table.get("maxSpeed", 1.8), 1.8), 0.5, MAX_BALL_SPEED)
	var velocity := Vector2(_float_value(ball.get("vx", 0.0), 0.0), _float_value(ball.get("vy", 0.0), 0.0))
	velocity.y += gravity * delta
	velocity = velocity.limit_length(max_speed)
	ball.vx = velocity.x
	ball.vy = velocity.y
	_advance_ball(ball, delta, max_speed)
	var center := Vector2(_float_value(ball.get("x", 0.5), 0.5), _float_value(ball.get("y", 0.8), 0.8))
	var speed := Vector2(_float_value(ball.get("vx", 0.0), 0.0), _float_value(ball.get("vy", 0.0), 0.0)).length()
	if speed < 0.035 and str(ball.get("status", "")) == "live":
		ball.slowTime = _float_value(ball.get("slowTime", 0.0), 0.0) + delta
	else:
		ball.slowTime = 0.0
	state.ball = ball
	var drain: Dictionary = table.get("drain", {})
	var drain_y := _float_value(drain.get("y", 0.962), 0.962)
	var drain_left := _float_value(drain.get("left", 0.40), 0.40)
	var drain_right := _float_value(drain.get("right", 0.60), 0.60)
	if str(ball.get("status", "")) == "live" and center.y >= drain_y and center.x >= drain_left and center.x <= drain_right:
		_drain_ball(center)
		return
	if str(ball.get("status", "")) != "live":
		return
	if center.x < -0.08 or center.x > 1.08 or center.y < -0.08 or center.y > 1.08:
		_drain_ball(Vector2(clampf(center.x, 0.0, 1.0), drain_y))
		return
	if _float_value(ball.get("slowTime", 0.0), 0.0) > 2.3:
		ball.vx = random.generator.randf_range(-0.20, 0.20)
		ball.vy = -0.46
		ball.slowTime = 0.0
		state.ball = ball
		_add_event({"type": "nudge", "x": center.x, "y": center.y})
	if _float_value(ball.get("age", 0.0), 0.0) > 45.0:
		_drain_ball(center)


func _update_flippers(delta: float) -> void:
	var flippers: Dictionary = _table().get("flippers", {})
	var pressed_value: Variant = state.get("flippersPressed", {})
	var pressed: Dictionary = pressed_value if pressed_value is Dictionary else {}
	var angles_value: Variant = state.get("flipperAngles", {})
	var angles: Dictionary = angles_value.duplicate(true) if angles_value is Dictionary else {}
	for side in ["left", "right"]:
		var definition: Dictionary = flippers.get(side, {})
		var default_rest := 25.0 if side == "left" else 155.0
		var default_active := -20.0 if side == "left" else 200.0
		var rest := deg_to_rad(_float_value(definition.get("restAngle", default_rest), default_rest))
		var active := deg_to_rad(_float_value(definition.get("flipAngle", default_active), default_active))
		var target := active if bool(pressed.get(side, false)) else rest
		var current := _float_value(angles.get(side, rest), rest)
		var pressure := 18.0 if bool(pressed.get(side, false)) else 10.5
		current = move_toward(current, target, pressure * delta)
		angles[side] = current
	state.flipperAngles = angles


func _advance_ball(ball: Dictionary, delta: float, max_speed: float) -> void:
	var center := Vector2(_float_value(ball.get("x", 0.5), 0.5), _float_value(ball.get("y", 0.8), 0.8))
	var velocity := Vector2(_float_value(ball.get("vx", 0.0), 0.0), _float_value(ball.get("vy", 0.0), 0.0))
	var radius := _ball_radius()
	var remaining := delta
	for _iteration in 8:
		var hit: Dictionary = _earliest_collision(center, velocity, radius, remaining)
		if hit.is_empty():
			center += velocity * remaining
			remaining = 0.0
			break
		var travel := clampf(_float_value(hit.get("t", 0.0), 0.0), 0.0, remaining)
		center += velocity * travel
		remaining = maxf(0.0, remaining - travel)
		var normal: Vector2 = hit.get("normal", Vector2.UP)
		if normal.length_squared() <= EPSILON:
			normal = Vector2.UP
		else:
			normal = normal.normalized()
		var restitution := 0.78
		var friction := 0.012
		var kick := 0.0
		match str(hit.get("type", "")):
			"bumper":
				var bumper_index := _int_value(hit.get("index", -1), -1)
				var bumpers: Array = _table().get("bumpers", [])
				if bumper_index >= 0 and bumper_index < bumpers.size():
					var bumper: Dictionary = bumpers[bumper_index]
					var hits_value: Variant = state.get("bumperHits", [])
					var hits: Array = hits_value.duplicate() if hits_value is Array else []
					if bumper_index < hits.size():
						hits[bumper_index] = int(hits[bumper_index]) + 1
						state.bumperHits = hits
					state.score = int(state.get("score", 0)) + maxi(0, _int_value(bumper.get("points", 40), 40))
					_add_event({
						"type": "bumper",
						"index": bumper_index,
						"x": center.x,
						"y": center.y,
						"points": maxi(0, _int_value(bumper.get("points", 40), 40)),
					})
				kick = 0.20
				restitution = 0.96
			"target":
				var target_index := _int_value(hit.get("index", -1), -1)
				var targets: Array = _table().get("targets", [])
				if target_index >= 0 and target_index < targets.size():
					var target: Dictionary = targets[target_index]
					var lights_value: Variant = state.get("targetsLit", [])
					var lights: Array = lights_value.duplicate() if lights_value is Array else []
					var newly_lit := false
					if target_index < lights.size() and not bool(lights[target_index]):
						lights[target_index] = true
						state.targetsLit = lights
						newly_lit = true
						var points := maxi(0, _int_value(target.get("points", 120), 120))
						state.score = int(state.get("score", 0)) + points
						_add_event({
							"type": "target",
							"index": target_index,
							"x": center.x,
							"y": center.y,
							"points": points,
							"label": str(target.get("label", "目标灯")),
						})
						if _targets_complete():
							state.pendingClear = true
							state.score = int(state.get("score", 0)) + 250
							_add_event({
								"type": "all_targets",
								"x": center.x,
								"y": center.y,
								"bonus": 250,
							})
					elif not newly_lit:
						state.score = int(state.get("score", 0)) + 10
				kick = 0.06
				restitution = 0.86
			"flipper":
				var side := str(hit.get("side", ""))
				var pressed_value: Variant = state.get("flippersPressed", {})
				var pressed: Dictionary = pressed_value if pressed_value is Dictionary else {}
				if bool(pressed.get(side, false)):
					kick = 0.27
				restitution = 0.90
				_add_event({
					"type": "flipper_hit",
					"side": side,
					"x": center.x,
					"y": center.y,
				})
			"wall":
				restitution = 0.76
			"boundary":
				restitution = 0.80
		var previous_speed := velocity.length()
		velocity = ArcadePhysics.reflect_velocity(velocity, normal, restitution, friction)
		velocity += normal * kick
		velocity = velocity.limit_length(max_speed)
		center += normal * maxf(0.0008, _float_value(hit.get("penetration", 0.0), 0.0) + 0.0008)
		if previous_speed > 0.18 and str(hit.get("type", "")) in ["wall", "boundary"]:
			_add_event({
				"type": "bounce",
				"x": center.x,
				"y": center.y,
				"normalX": normal.x,
				"normalY": normal.y,
			})
		if travel <= 0.000001:
			continue
		if remaining <= 0.000001:
			break
	ball.x = center.x
	ball.y = center.y
	ball.vx = velocity.x
	ball.vy = velocity.y
	state.ball = ball


func _earliest_collision(center: Vector2, velocity: Vector2, radius: float, max_time: float) -> Dictionary:
	var hits: Array = []
	var table := _table()
	var drain: Dictionary = table.get("drain", {})
	var drain_left := clampf(_float_value(drain.get("left", 0.40), 0.40), 0.04, 0.96)
	var drain_right := clampf(_float_value(drain.get("right", 0.60), 0.60), drain_left + 0.04, 0.96)
	var boundary_lines := [
		[Vector2(0.012, 0.020), Vector2(0.012, 0.975)],
		[Vector2(0.988, 0.020), Vector2(0.988, 0.975)],
		[Vector2(0.020, 0.020), Vector2(0.980, 0.020)],
		[Vector2(0.012, 0.975), Vector2(drain_left, 0.975)],
		[Vector2(drain_right, 0.975), Vector2(0.988, 0.975)],
	]
	for index in boundary_lines.size():
		var line: Array = boundary_lines[index]
		var boundary_hit := ArcadePhysics.sweep_circle_segment(
			center, velocity, radius, line[0], line[1], 0.004, max_time
		)
		if bool(boundary_hit.get("hit", false)):
			boundary_hit.type = "boundary"
			boundary_hit.order = index
			hits.append(boundary_hit)
	var walls_value: Variant = table.get("walls", [])
	var walls: Array = walls_value if walls_value is Array else []
	for index in walls.size():
		var raw: Variant = walls[index]
		if not raw is Dictionary:
			continue
		var wall: Dictionary = raw
		var start := Vector2(_float_value(wall.get("x1", 0.0), 0.0), _float_value(wall.get("y1", 0.0), 0.0))
		var finish := Vector2(_float_value(wall.get("x2", 0.0), 0.0), _float_value(wall.get("y2", 0.0), 0.0))
		var wall_hit := ArcadePhysics.sweep_circle_segment(
			center, velocity, radius, start, finish,
			maxf(0.002, _float_value(wall.get("radius", 0.006), 0.006)), max_time
		)
		if bool(wall_hit.get("hit", false)):
			wall_hit.type = "wall"
			wall_hit.index = index
			wall_hit.order = 20 + index
			hits.append(wall_hit)
	var bumpers_value: Variant = table.get("bumpers", [])
	var bumpers: Array = bumpers_value if bumpers_value is Array else []
	for index in bumpers.size():
		var raw: Variant = bumpers[index]
		if not raw is Dictionary:
			continue
		var bumper: Dictionary = raw
		var bumper_center := Vector2(_float_value(bumper.get("x", 0.5), 0.5), _float_value(bumper.get("y", 0.4), 0.4))
		var bumper_hit := ArcadePhysics.sweep_circle_circle(
			center, velocity, radius,
			bumper_center, Vector2.ZERO,
			maxf(0.008, _float_value(bumper.get("radius", 0.035), 0.035)),
			max_time
		)
		if bool(bumper_hit.get("hit", false)):
			bumper_hit.type = "bumper"
			bumper_hit.index = index
			bumper_hit.order = 80 + index
			hits.append(bumper_hit)
	var targets_value: Variant = table.get("targets", [])
	var targets: Array = targets_value if targets_value is Array else []
	for index in targets.size():
		var raw: Variant = targets[index]
		if not raw is Dictionary:
			continue
		var target: Dictionary = raw
		var target_center := Vector2(_float_value(target.get("x", 0.5), 0.5), _float_value(target.get("y", 0.2), 0.2))
		var target_hit := ArcadePhysics.sweep_circle_circle(
			center, velocity, radius,
			target_center, Vector2.ZERO,
			maxf(0.006, _float_value(target.get("radius", 0.018), 0.018)),
			max_time
		)
		if bool(target_hit.get("hit", false)):
			target_hit.type = "target"
			target_hit.index = index
			target_hit.order = 110 + index
			hits.append(target_hit)
	var flippers_value: Variant = table.get("flippers", {})
	var flippers: Dictionary = flippers_value if flippers_value is Dictionary else {}
	for side in ["left", "right"]:
		var segment := _flipper_segment(side, flippers)
		var flipper_hit := ArcadePhysics.sweep_circle_segment(
			center, velocity, radius, segment[0], segment[1], 0.010, max_time
		)
		if bool(flipper_hit.get("hit", false)):
			flipper_hit.type = "flipper"
			flipper_hit.side = side
			flipper_hit.order = 150 if side == "left" else 151
			hits.append(flipper_hit)
	return ArcadePhysics.earliest_hit(hits)


func _flipper_segment(side: String, flippers: Dictionary = {}) -> Array:
	var definition_value: Variant = flippers.get(side, {})
	var definition: Dictionary = definition_value if definition_value is Dictionary else {}
	var default_pivot := [0.30, 0.80] if side == "left" else [0.70, 0.80]
	var pivot_value: Variant = definition.get("pivot", default_pivot)
	var pivot := Vector2(0.30, 0.80) if side == "left" else Vector2(0.70, 0.80)
	if pivot_value is Array and pivot_value.size() >= 2:
		pivot = Vector2(_float_value(pivot_value[0], pivot.x), _float_value(pivot_value[1], pivot.y))
	var length := clampf(_float_value(definition.get("length", 0.17), 0.17), 0.06, 0.28)
	var angles_value: Variant = state.get("flipperAngles", {})
	var angles: Dictionary = angles_value if angles_value is Dictionary else {}
	var default_rest := 25.0 if side == "left" else 155.0
	var rest := deg_to_rad(_float_value(definition.get("restAngle", default_rest), default_rest))
	var angle := _float_value(angles.get(side, rest), rest)
	var tip := pivot + Vector2(cos(angle), sin(angle)) * length
	return [pivot, tip]


func _drain_ball(point: Vector2) -> void:
	var ball_value: Variant = state.get("ball", {})
	var ball: Dictionary = ball_value if ball_value is Dictionary else {}
	_add_event({"type": "drain", "x": point.x, "y": point.y})
	if _targets_complete():
		_finish(true, "目标灯全部点亮，星轨完成啦")
		return
	var saves := int(state.get("savesRemaining", 0))
	if saves > 0:
		state.savesRemaining = saves - 1
		state.ballSavesUsed = int(state.get("ballSavesUsed", 0)) + 1
		_ready_ball()
		_add_event({"type": "ball_save", "x": point.x, "y": point.y, "remaining": saves - 1})
		return
	var balls_left := int(state.get("ballsLeft", 1)) - 1
	state.ballsLeft = maxi(0, balls_left)
	if balls_left <= 0:
		ball.status = "settled"
		state.ball = ball
		_finish(false, "弹珠都用完了，再看看目标灯的位置")
		return
	state.ballNumber = int(state.get("ballNumber", 1)) + 1
	_ready_ball()
	_add_event({
		"type": "ball_lost",
		"x": point.x,
		"y": point.y,
		"ballsLeft": balls_left,
		"ballNumber": int(state.get("ballNumber", 2)),
	})


func _ready_ball() -> void:
	var launch: Dictionary = _table().get("launch", {})
	state.ball = {
		"status": "ready",
		"x": _float_value(launch.get("x", 0.91), 0.91),
		"y": _float_value(launch.get("y", 0.88), 0.88),
		"vx": 0.0,
		"vy": 0.0,
		"age": 0.0,
		"slowTime": 0.0,
	}


func _finish(success: bool, reason: String) -> void:
	state.phase = "finished"
	state.success = success
	state.reason = reason
	state.outcome = ("played" if str(state.get("modeId", "")) == "classic" else "win") if success else "retry"
	state.winner = -1 if not success or str(state.get("modeId", "")) == "classic" else 0
	state.pendingClear = success
	state.stars = stars()
	var ball_value: Variant = state.get("ball", {})
	if ball_value is Dictionary:
		var ball: Dictionary = ball_value
		ball.status = "settled"
		ball.vx = 0.0
		ball.vy = 0.0
		state.ball = ball
	_add_event({
		"type": "complete",
		"success": success,
		"x": 0.5,
		"y": 0.45,
		"reason": reason,
	})


func targets_complete() -> bool:
	return _targets_complete()


func _targets_complete() -> bool:
	var lights_value: Variant = state.get("targetsLit", [])
	if not lights_value is Array:
		return false
	var lights: Array = lights_value
	if lights.is_empty():
		return false
	for value in lights:
		if not bool(value):
			return false
	return true


func target_progress() -> Array:
	var result: Array = []
	var targets_value: Variant = _table().get("targets", [])
	var targets: Array = targets_value if targets_value is Array else []
	var lights_value: Variant = state.get("targetsLit", [])
	var lights: Array = lights_value if lights_value is Array else []
	for index in targets.size():
		var raw: Variant = targets[index]
		var target: Dictionary = raw if raw is Dictionary else {}
		result.append({
			"index": index,
			"label": str(target.get("label", "目标灯")),
			"lit": bool(lights[index]) if index < lights.size() else false,
			"x": _float_value(target.get("x", 0.5), 0.5),
			"y": _float_value(target.get("y", 0.2), 0.2),
		})
	return result


func ball_snapshot() -> Dictionary:
	var value: Variant = state.get("ball", {})
	return value.duplicate(true) if value is Dictionary else {}


func flipper_angle(side: String) -> float:
	var angles_value: Variant = state.get("flipperAngles", {})
	var angles: Dictionary = angles_value if angles_value is Dictionary else {}
	return _float_value(angles.get(side, 0.0), 0.0)


func flipper_pressed(side: String) -> bool:
	var pressed_value: Variant = state.get("flippersPressed", {})
	var pressed: Dictionary = pressed_value if pressed_value is Dictionary else {}
	return bool(pressed.get(side, false))


func ball_ready() -> bool:
	var value: Variant = state.get("ball", {})
	return value is Dictionary and str(value.get("status", "")) == "ready"


func is_cooperative() -> bool:
	return str(state.get("modeId", "adventure")) == "classic"


func level_title() -> String:
	return str(state.get("levelTitle", _table().get("title", "弹珠星轨")))


func stars() -> int:
	if str(state.get("phase", "")) != "finished" or not bool(state.get("success", false)):
		return 0
	var table := _table()
	var par := maxi(1, _int_value(table.get("parScore", 700), 700))
	var score := int(state.get("score", 0))
	var balls_left := int(state.get("ballsLeft", 0))
	var saves_used := int(state.get("ballSavesUsed", 0))
	if score >= par and balls_left >= 1 and saves_used <= 1:
		return 3
	if score >= int(round(float(par) * 0.65)) or balls_left >= 1:
		return 2
	return 1


func result() -> Dictionary:
	if str(state.get("phase", "")) != "finished":
		return {}
	var targets := target_progress()
	var lit := 0
	for target in targets:
		if bool(target.get("lit", false)):
			lit += 1
	var bumps := 0
	var bumper_hits_value: Variant = state.get("bumperHits", [])
	var bumper_hits: Array = bumper_hits_value if bumper_hits_value is Array else []
	for value in bumper_hits:
		bumps += maxi(0, int(value))
	return {
		"phase": "finished",
		"success": bool(state.get("success", false)),
		"reason": str(state.get("reason", "")),
		"outcome": str(state.get("outcome", "retry")),
		"winner": int(state.get("winner", -1)),
		"score": int(state.get("score", 0)),
		"stars": stars(),
		"targetsLit": lit,
		"targetTotal": targets.size(),
		"bumperHits": bumps,
		"ballsLeft": int(state.get("ballsLeft", 0)),
		"ballNumber": int(state.get("ballNumber", 1)),
		"ballSavesUsed": int(state.get("ballSavesUsed", 0)),
		"elapsed": float(state.get("elapsed", 0.0)),
	}


func snapshot() -> Dictionary:
	var value := super.snapshot()
	value.events = []
	value.pinballVersion = VERSION
	value.physicsAccumulator = clampf(_accumulator, 0.0, LOGIC_STEP)
	value.stars = stars()
	return value


func drain_events() -> Array:
	var value: Variant = state.get("events", [])
	var events: Array = value.duplicate(true) if value is Array else []
	state.events = []
	return events


func restore(value: Dictionary) -> bool:
	if _strict_int(value.get("pinballVersion", null)) != VERSION:
		return false
	if not super.restore(value):
		return false
	var mode := str(state.get("modeId", ""))
	if not mode in MODES:
		return _reject_restore()
	var table_value: Variant = state.get("level", {})
	if not table_value is Dictionary:
		return _reject_restore()
	var table: Dictionary = table_value
	var table_validation := validate_table(table)
	if not bool(table_validation.get("ok", false)):
		return _reject_restore()
	var level_id := _strict_int(state.get("levelId", null))
	var level_number := _strict_int(state.get("levelNumber", null))
	var table_number := _strict_int(table.get("levelNumber", null))
	if level_id < 1 or level_number != level_id or table_number != level_id:
		return _reject_restore()
	if str(table.get("mode", "")) != mode or str(state.get("levelKey", "")) != str(table.get("id", "")):
		return _reject_restore()
	var players_value: Variant = state.get("players", [])
	var expected_players := 2 if mode == "classic" else 1
	if not players_value is Array or players_value.size() != expected_players:
		return _reject_restore()
	var phase := str(state.get("phase", ""))
	if phase not in ["playing", "finished"]:
		return _reject_restore()
	var targets_value: Variant = table.get("targets", [])
	var target_lights: Variant = state.get("targetsLit", null)
	if not targets_value is Array or not target_lights is Array or target_lights.size() != targets_value.size():
		return _reject_restore()
	var clean_lights: Array = []
	for raw in target_lights:
		if not raw is bool:
			return _reject_restore()
		clean_lights.append(raw)
	state.targetsLit = clean_lights
	var bumpers_value: Variant = table.get("bumpers", [])
	var bumper_hits: Variant = state.get("bumperHits", null)
	if not bumpers_value is Array or not bumper_hits is Array or bumper_hits.size() != bumpers_value.size():
		return _reject_restore()
	var clean_hits: Array = []
	for raw in bumper_hits:
		var count := _strict_int(raw)
		if count < 0 or count > 100000:
			return _reject_restore()
		clean_hits.append(count)
	state.bumperHits = clean_hits
	var balls := _strict_int(table.get("balls", null))
	var saves := _strict_int(table.get("saves", null))
	var balls_left := _strict_int(state.get("ballsLeft", null))
	var ball_number := _strict_int(state.get("ballNumber", null))
	var saves_remaining := _strict_int(state.get("savesRemaining", null))
	var saves_used := _strict_int(state.get("ballSavesUsed", null))
	if balls < 1 or saves < 0 or balls_left < 0 or balls_left > balls:
		return _reject_restore()
	if ball_number < 1 or ball_number > balls or saves_remaining < 0 or saves_remaining > saves:
		return _reject_restore()
	if saves_used < 0 or saves_used > saves:
		return _reject_restore()
	var score := _strict_int(state.get("score", null))
	var elapsed := _finite_float(state.get("elapsed", 0.0))
	var hints := _strict_int(state.get("hintsUsed", 0))
	if score < 0 or score > 10000000 or elapsed < 0.0 or elapsed > 3600.0 or hints < 0 or hints > 1000:
		return _reject_restore()
	var ball_value: Variant = state.get("ball", null)
	if not ball_value is Dictionary:
		return _reject_restore()
	var raw_ball: Dictionary = ball_value
	var status := str(raw_ball.get("status", ""))
	if status not in ["ready", "live", "settled"]:
		return _reject_restore()
	if phase == "playing" and status not in ["ready", "live"]:
		return _reject_restore()
	if phase == "finished" and status != "settled":
		return _reject_restore()
	var ball_x := _finite_float(raw_ball.get("x", 0.0))
	var ball_y := _finite_float(raw_ball.get("y", 0.0))
	var ball_vx := _finite_float(raw_ball.get("vx", 0.0))
	var ball_vy := _finite_float(raw_ball.get("vy", 0.0))
	var ball_age := _finite_float(raw_ball.get("age", 0.0))
	var slow_time := _finite_float(raw_ball.get("slowTime", 0.0))
	if ball_x < -0.10 or ball_x > 1.10 or ball_y < -0.10 or ball_y > 1.10:
		return _reject_restore()
	if Vector2(ball_vx, ball_vy).length() > MAX_BALL_SPEED + 0.1:
		return _reject_restore()
	if ball_age < 0.0 or ball_age > 90.0 or slow_time < 0.0 or slow_time > 10.0:
		return _reject_restore()
	var pressed_value: Variant = state.get("flippersPressed", null)
	if not pressed_value is Dictionary:
		return _reject_restore()
	var pressed: Dictionary = pressed_value
	if not (pressed.get("left", null) is bool) or not (pressed.get("right", null) is bool):
		return _reject_restore()
	var angles_value: Variant = state.get("flipperAngles", null)
	if not angles_value is Dictionary:
		return _reject_restore()
	var angles: Dictionary = angles_value
	for side in ["left", "right"]:
		var angle := _finite_float(angles.get(side, 0.0))
		if angle < -TAU or angle > TAU:
			return _reject_restore()
	var pending_value: Variant = state.get("pendingClear", false)
	if not pending_value is bool:
		return _reject_restore()
	var success_value: Variant = state.get("success", false)
	var reported_value: Variant = state.get("reported", false)
	if not success_value is bool or not reported_value is bool:
		return _reject_restore()
	state.phase = phase
	state.success = bool(success_value)
	state.ball = {
		"status": status,
		"x": ball_x,
		"y": ball_y,
		"vx": ball_vx,
		"vy": ball_vy,
		"age": ball_age,
		"slowTime": slow_time,
	}
	state.view = "board"
	state.events = []
	state.physicsAccumulator = clampf(_finite_float(value.get("physicsAccumulator", 0.0)), 0.0, LOGIC_STEP)
	_accumulator = float(state.physicsAccumulator)
	state.pinballVersion = VERSION
	return true


func _reject_restore() -> bool:
	state = {}
	_accumulator = 0.0
	return false


static func validate_catalog(value: Variant) -> Dictionary:
	var issues: Array = []
	if not value is Dictionary:
		return {"ok": false, "issues": ["pinball.json 顶层必须是对象"], "validTables": []}
	var data: Dictionary = value
	var schema := _strict_int(data.get("schemaVersion", data.get("version", null)))
	if schema != VERSION:
		issues.append("pinball.json 的 schemaVersion 必须是 %s" % VERSION)
	var tables_value: Variant = data.get("tables", null)
	if not tables_value is Array:
		issues.append("pinball.json 缺少 tables 数组")
		return {"ok": false, "issues": issues, "validTables": []}
	var tables: Array = tables_value
	var valid_tables: Array = []
	var ids := {}
	var numbers_by_mode := {"adventure": {}, "classic": {}}
	var band_counts := {
		"adventure": {"easy": 0, "normal": 0, "challenge": 0},
		"classic": {"easy": 0, "normal": 0, "challenge": 0},
	}
	for index in tables.size():
		var raw: Variant = tables[index]
		var validation := validate_table(raw)
		if bool(validation.get("ok", false)):
			var table: Dictionary = raw
			var identifier := str(table.get("id", ""))
			var mode := str(table.get("mode", ""))
			var band := str(table.get("band", ""))
			var number := _int_value(table.get("levelNumber", 0), 0)
			if ids.has(identifier):
				issues.append("第 %s 项 id 重复：%s" % [index + 1, identifier])
				continue
			if numbers_by_mode[mode].has(number):
				issues.append("%s 的 levelNumber %s 重复" % [mode, number])
				continue
			ids[identifier] = true
			numbers_by_mode[mode][number] = true
			band_counts[mode][band] += 1
			valid_tables.append(table.duplicate(true))
		else:
			var details: Array = validation.get("issues", [])
			var first := str(details[0]) if not details.is_empty() else "未知错误"
			issues.append("第 %s 张弹珠台：%s" % [index + 1, first])
	for mode in MODES:
		var expected_total := 18 if mode == "adventure" else 6
		var expected_band := 6 if mode == "adventure" else 2
		var total := 0
		for band in BANDS:
			total += int(band_counts[mode][band])
			if int(band_counts[mode][band]) != expected_band:
				issues.append("%s 的 %s 档应有 %s 张，实际 %s 张" % [mode, band, expected_band, int(band_counts[mode][band])])
		if total != expected_total:
			issues.append("%s 应有 %s 张弹珠台，实际 %s 张" % [mode, expected_total, total])
		var mode_numbers: Dictionary = numbers_by_mode[mode]
		for number in range(1, expected_total + 1):
			if not mode_numbers.has(number):
				issues.append("%s 缺少 levelNumber %s" % [mode, number])
	return {
		"ok": issues.is_empty(),
		"issues": issues,
		"validTables": valid_tables,
	}


static func validate_table(value: Variant, expected_level: int = -1) -> Dictionary:
	var issues: Array = []
	if not value is Dictionary:
		return {"ok": false, "issues": ["弹珠台必须是对象"]}
	var table: Dictionary = value
	var mode := str(table.get("mode", ""))
	var band := str(table.get("band", ""))
	if not mode in MODES:
		issues.append("mode 必须是 adventure 或 classic")
	var level_number := _strict_int(table.get("levelNumber", null))
	if level_number < 1:
		issues.append("levelNumber 必须是正整数")
	elif expected_level > 0 and level_number != expected_level:
		issues.append("levelNumber 与关卡编号不一致")
	if not band in BANDS:
		issues.append("band 必须是 easy、normal 或 challenge")
	var min_age := _strict_int(table.get("minAge", null))
	if min_age < 4 or min_age > 12:
		issues.append("minAge 必须在 4–12 之间")
	if str(table.get("id", "")).strip_edges().is_empty():
		issues.append("缺少 id")
	if str(table.get("title", "")).strip_edges().is_empty():
		issues.append("缺少 title")
	if str(table.get("hint", "")).strip_edges().is_empty():
		issues.append("缺少 hint")
	if str(table.get("explanation", "")).strip_edges().is_empty():
		issues.append("缺少 explanation")
	var radius := _positive_number(table.get("ballRadius", null), 0.010, 0.045)
	if radius <= 0.0:
		issues.append("ballRadius 超出范围")
	var gravity := _positive_number(table.get("gravity", null), 0.08, 1.20)
	if gravity <= 0.0:
		issues.append("gravity 超出范围")
	var max_speed := _positive_number(table.get("maxSpeed", 1.8), 0.50, MAX_BALL_SPEED)
	if max_speed <= 0.0:
		issues.append("maxSpeed 超出范围")
	var balls := _strict_int(table.get("balls", null))
	if balls < 1 or balls > 5:
		issues.append("balls 必须是 1–5")
	var saves := _strict_int(table.get("saves", null))
	if saves < 0 or saves > 3:
		issues.append("saves 必须是 0–3")
	if _strict_int(table.get("parScore", null)) < 1:
		issues.append("parScore 必须是正整数")
	var launch_value: Variant = table.get("launch", null)
	if not launch_value is Dictionary:
		issues.append("缺少 launch")
	else:
		var launch: Dictionary = launch_value
		if not _inside_unit(launch.get("x", null), launch.get("y", null)):
			issues.append("launch 坐标超出台面")
		if _positive_number(launch.get("power", null), 0.4, 1.8) <= 0.0:
			issues.append("launch.power 超出范围")
		if not _number_value(launch.get("angle", null)):
			issues.append("launch.angle 必须是数字")
	var drain_value: Variant = table.get("drain", null)
	if not drain_value is Dictionary:
		issues.append("缺少 drain")
	else:
		var drain: Dictionary = drain_value
		var drain_y := _finite_float(drain.get("y", 0.0)) if _number_value(drain.get("y", null)) else -1.0
		var drain_left := _finite_float(drain.get("left", 0.0)) if _number_value(drain.get("left", null)) else -1.0
		var drain_right := _finite_float(drain.get("right", 0.0)) if _number_value(drain.get("right", null)) else -1.0
		if drain_y < 0.86 or drain_y > 0.995:
			issues.append("drain.y 超出范围")
		if drain_left < 0.05 or drain_right > 0.95 or drain_right - drain_left < 0.08:
			issues.append("drain 开口不合理")
	var flippers_value: Variant = table.get("flippers", null)
	if not flippers_value is Dictionary:
		issues.append("缺少 flippers")
	else:
		var flippers: Dictionary = flippers_value
		for side in ["left", "right"]:
			var raw_flipper: Variant = flippers.get(side, null)
			if not raw_flipper is Dictionary:
				issues.append("缺少 %s 弹板" % side)
				continue
			var flipper: Dictionary = raw_flipper
			var pivot_value: Variant = flipper.get("pivot", null)
			if not pivot_value is Array or pivot_value.size() != 2 or not _inside_unit(pivot_value[0], pivot_value[1]):
				issues.append("%s 弹板 pivot 不合理" % side)
			var length := _positive_number(flipper.get("length", null), 0.06, 0.28)
			if length <= 0.0:
				issues.append("%s 弹板长度不合理" % side)
			if not _number_value(flipper.get("restAngle", null)) or not _number_value(flipper.get("flipAngle", null)):
				issues.append("%s 弹板角度必须是数字" % side)
	var walls_value: Variant = table.get("walls", null)
	if not walls_value is Array or walls_value.size() < 4:
		issues.append("walls 至少需要四段")
	else:
		for index in walls_value.size():
			var raw_wall: Variant = walls_value[index]
			if not raw_wall is Dictionary:
				issues.append("第 %s 段墙不是对象" % (index + 1))
				continue
			var wall: Dictionary = raw_wall
			var x1v: Variant = wall.get("x1", null)
			var y1v: Variant = wall.get("y1", null)
			var x2v: Variant = wall.get("x2", null)
			var y2v: Variant = wall.get("y2", null)
			if not _inside_unit(x1v, y1v) or not _inside_unit(x2v, y2v):
				issues.append("第 %s 段墙坐标超出台面" % (index + 1))
			elif Vector2(_finite_float(x2v), _finite_float(y2v)).distance_to(Vector2(_finite_float(x1v), _finite_float(y1v))) < 0.01:
				issues.append("第 %s 段墙太短" % (index + 1))
			if _positive_number(wall.get("radius", 0.006), 0.001, 0.03) <= 0.0:
				issues.append("第 %s 段墙半径不合理" % (index + 1))
	var bumpers_value: Variant = table.get("bumpers", null)
	if not bumpers_value is Array or bumpers_value.size() < 2:
		issues.append("bumpers 至少需要两个")
	else:
		for index in bumpers_value.size():
			var raw_bumper: Variant = bumpers_value[index]
			if not raw_bumper is Dictionary:
				issues.append("第 %s 个缓冲柱不是对象" % (index + 1))
				continue
			var bumper: Dictionary = raw_bumper
			if not _inside_unit(bumper.get("x", null), bumper.get("y", null)):
				issues.append("第 %s 个缓冲柱超出台面" % (index + 1))
			if _positive_number(bumper.get("radius", null), 0.012, 0.075) <= 0.0:
				issues.append("第 %s 个缓冲柱半径不合理" % (index + 1))
			if _strict_int(bumper.get("points", null)) < 1:
				issues.append("第 %s 个缓冲柱分数不合理" % (index + 1))
	var targets_value: Variant = table.get("targets", null)
	if not targets_value is Array or targets_value.size() < 3:
		issues.append("targets 至少需要三盏目标灯")
	else:
		var target_keys := {}
		for index in targets_value.size():
			var raw_target: Variant = targets_value[index]
			if not raw_target is Dictionary:
				issues.append("第 %s 盏目标灯不是对象" % (index + 1))
				continue
			var target: Dictionary = raw_target
			if not _inside_unit(target.get("x", null), target.get("y", null)):
				issues.append("第 %s 盏目标灯超出台面" % (index + 1))
			if _positive_number(target.get("radius", null), 0.009, 0.045) <= 0.0:
				issues.append("第 %s 盏目标灯半径不合理" % (index + 1))
			if _strict_int(target.get("points", null)) < 1:
				issues.append("第 %s 盏目标灯分数不合理" % (index + 1))
			var label := str(target.get("label", "")).strip_edges()
			if label.is_empty():
				issues.append("第 %s 盏目标灯缺少 label" % (index + 1))
			elif target_keys.has(label):
				issues.append("目标灯 label 重复：%s" % label)
			else:
				target_keys[label] = true
	if band == "easy" and min_age > 6:
		issues.append("easy 的 minAge 不应高于 6")
	if band == "normal" and (min_age < 7 or min_age > 9):
		issues.append("normal 的 minAge 应在 7–9")
	if band == "challenge" and min_age < 10:
		issues.append("challenge 的 minAge 不应低于 10")
	return {"ok": issues.is_empty(), "issues": issues}


func _add_event(event: Dictionary) -> void:
	var events_value: Variant = state.get("events", [])
	var events: Array = events_value if events_value is Array else []
	events.append(event.duplicate(true))
	if events.size() > MAX_EVENTS:
		events = events.slice(events.size() - MAX_EVENTS)
	state.events = events


func _table() -> Dictionary:
	var value: Variant = state.get("level", {})
	return value if value is Dictionary else {}


func _ball_radius() -> float:
	return clampf(_float_value(_table().get("ballRadius", 0.021), 0.021), 0.008, 0.045)


static func _inside_unit(x_value: Variant, y_value: Variant) -> bool:
	if not _number_value(x_value) or not _number_value(y_value):
		return false
	var x := _finite_float(x_value)
	var y := _finite_float(y_value)
	return x >= 0.0 and x <= 1.0 and y >= 0.0 and y <= 1.0


static func _positive_number(value: Variant, minimum: float, maximum: float) -> float:
	if not _number_value(value):
		return 0.0
	var parsed := _finite_float(value)
	return parsed if parsed >= minimum and parsed <= maximum else 0.0


static func _number_value(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


static func _strict_int(value: Variant) -> int:
	if value is int:
		return int(value)
	if value is float and is_finite(float(value)) and is_equal_approx(float(value), float(int(value))):
		return int(value)
	return INVALID_INT


static func _int_value(value: Variant, fallback: int) -> int:
	var parsed := _strict_int(value)
	return fallback if parsed == INVALID_INT else parsed


static func _finite_float(value: Variant) -> float:
	if (value is int or value is float) and is_finite(float(value)):
		return float(value)
	return 0.0


static func _float_value(value: Variant, fallback: float) -> float:
	return float(value) if (value is int or value is float) and is_finite(float(value)) else fallback
