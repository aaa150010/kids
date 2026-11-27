class_name ArcadePhysics
extends RefCounted

const STEP_HZ := 120
const STEP_DELTA := 1.0 / float(STEP_HZ)
const EPSILON := 0.000001
const DEFAULT_MAX_STEPS := 12


static func consume_fixed_steps(accumulator: float, delta: float, max_steps: int = DEFAULT_MAX_STEPS) -> Dictionary:
	var carry := maxf(0.0, accumulator)
	var frame := clampf(delta, 0.0, 0.25)
	carry += frame
	var available := maxi(0, int(floor(carry / STEP_DELTA + EPSILON)))
	var steps := mini(available, maxi(1, max_steps))
	var dropped := available > steps
	if dropped:
		carry = fmod(carry, STEP_DELTA)
	else:
		carry = maxf(0.0, carry - float(steps) * STEP_DELTA)
	return {
		"steps": steps,
		"accumulator": carry,
		"alpha": clampf(carry / STEP_DELTA, 0.0, 1.0),
		"dropped": dropped,
	}


static func circle_circle_contact(center: Vector2, radius: float, other_center: Vector2, other_radius: float) -> Dictionary:
	var offset := center - other_center
	var combined := maxf(0.0, radius) + maxf(0.0, other_radius)
	var distance_squared := offset.length_squared()
	if distance_squared > combined * combined + EPSILON:
		return _miss()
	var distance := sqrt(distance_squared)
	var normal := offset / distance if distance > EPSILON else Vector2.UP
	return {
		"hit": true,
		"overlapping": true,
		"started_inside": distance <= combined + EPSILON,
		"t": 0.0,
		"point": center,
		"contact_point": center - normal * maxf(0.0, radius),
		"normal": normal,
		"penetration": maxf(0.0, combined - distance),
		"distance": distance,
	}


static func sweep_circle_circle(
	center: Vector2,
	velocity: Vector2,
	radius: float,
	other_center: Vector2,
	other_velocity: Vector2 = Vector2.ZERO,
	other_radius: float = 0.0,
	max_time: float = STEP_DELTA
) -> Dictionary:
	var combined := maxf(0.0, radius) + maxf(0.0, other_radius)
	var relative_center := center - other_center
	var relative_velocity := velocity - other_velocity
	var distance_squared := relative_center.length_squared()
	if distance_squared <= combined * combined + EPSILON:
		var distance := sqrt(maxf(0.0, distance_squared))
		var contact_normal := relative_center / distance if distance > EPSILON else Vector2.UP
		return {
			"hit": true,
			"overlapping": true,
			"started_inside": true,
			"t": 0.0,
			"point": center,
			"other_point": other_center,
			"contact_point": center - contact_normal * maxf(0.0, radius),
			"normal": contact_normal,
			"penetration": maxf(0.0, combined - distance),
			"kind": "circle",
		}
	var a := relative_velocity.length_squared()
	if a <= EPSILON * EPSILON:
		return _miss()
	var b := 2.0 * relative_center.dot(relative_velocity)
	var c := distance_squared - combined * combined
	var discriminant := b * b - 4.0 * a * c
	if discriminant < -EPSILON:
		return _miss()
	discriminant = maxf(0.0, discriminant)
	var root := sqrt(discriminant)
	var denominator := 2.0 * a
	var first := (-b - root) / denominator
	var second := (-b + root) / denominator
	var travel_time := first if first >= -EPSILON else second
	if travel_time < -EPSILON or travel_time > maxf(0.0, max_time) + EPSILON:
		return _miss()
	travel_time = clampf(travel_time, 0.0, maxf(0.0, max_time))
	var moving_point := center + velocity * travel_time
	var target_point := other_center + other_velocity * travel_time
	var hit_offset := moving_point - target_point
	var hit_distance := hit_offset.length()
	var hit_normal := hit_offset / hit_distance if hit_distance > EPSILON else Vector2.UP
	return {
		"hit": true,
		"overlapping": false,
		"started_inside": false,
		"t": travel_time,
		"point": moving_point,
		"other_point": target_point,
		"contact_point": moving_point - hit_normal * maxf(0.0, radius),
		"normal": hit_normal,
		"penetration": 0.0,
		"kind": "circle",
	}


static func circle_rect_contact(center: Vector2, radius: float, rect: Rect2) -> Dictionary:
	var rect_end := rect.position + rect.size
	var closest := Vector2(
		clampf(center.x, rect.position.x, rect_end.x),
		clampf(center.y, rect.position.y, rect_end.y)
	)
	var offset := center - closest
	var distance := offset.length()
	var inside := rect.has_point(center)
	var normal := Vector2.UP
	var penetration := 0.0
	if inside:
		var left := center.x - rect.position.x
		var right := rect_end.x - center.x
		var top := center.y - rect.position.y
		var bottom := rect_end.y - center.y
		var nearest := minf(minf(left, right), minf(top, bottom))
		if nearest == left:
			normal = Vector2.LEFT
		elif nearest == right:
			normal = Vector2.RIGHT
		elif nearest == top:
			normal = Vector2.UP
		else:
			normal = Vector2.DOWN
		penetration = maxf(0.0, radius) + nearest
	elif distance > EPSILON:
		normal = offset / distance
		penetration = maxf(0.0, maxf(0.0, radius) - distance)
	var overlapping := inside or distance <= maxf(0.0, radius) + EPSILON
	return {
		"hit": overlapping,
		"overlapping": overlapping,
		"started_inside": inside,
		"t": 0.0,
		"point": center,
		"contact_point": closest,
		"normal": normal,
		"penetration": penetration,
		"distance": distance,
		"inside": inside,
	}


static func sweep_circle_rect(
	center: Vector2,
	velocity: Vector2,
	radius: float,
	rect: Rect2,
	rect_velocity: Vector2 = Vector2.ZERO,
	max_time: float = STEP_DELTA
) -> Dictionary:
	var frame := maxf(0.0, max_time)
	var initial := circle_rect_contact(center, radius, rect)
	if bool(initial.get("overlapping", false)):
		initial.kind = "rect"
		return initial
	var relative_velocity := velocity - rect_velocity
	if relative_velocity.length_squared() <= EPSILON * EPSILON:
		return _miss()
	var candidates: Array = []
	var rect_end := rect.position + rect.size
	var corners := [
		rect.position,
		Vector2(rect_end.x, rect.position.y),
		rect_end,
		Vector2(rect.position.x, rect_end.y),
	]
	var edges := [
		[rect.position, Vector2(rect_end.x, rect.position.y), "top"],
		[Vector2(rect_end.x, rect.position.y), rect_end, "right"],
		[rect_end, Vector2(rect.position.x, rect_end.y), "bottom"],
		[Vector2(rect.position.x, rect_end.y), rect.position, "left"],
	]
	for index in edges.size():
		var edge: Array = edges[index]
		var edge_hit := sweep_circle_segment(center, relative_velocity, radius, edge[0], edge[1], 0.0, frame)
		if bool(edge_hit.get("hit", false)):
			edge_hit.kind = "rect_side"
			edge_hit.order = index
			candidates.append(edge_hit)
	for index in corners.size():
		var corner_hit := sweep_circle_circle(center, relative_velocity, radius, corners[index], Vector2.ZERO, 0.0, frame)
		if bool(corner_hit.get("hit", false)):
			corner_hit.kind = "rect_corner"
			corner_hit.order = 10 + index
			candidates.append(corner_hit)
	var earliest := earliest_hit(candidates)
	if earliest.is_empty():
		return _miss()
	var travel_time := clampf(float(earliest.get("t", 0.0)), 0.0, frame)
	var moved_rect := Rect2(rect.position + rect_velocity * travel_time, rect.size)
	var contact := circle_rect_contact(center + velocity * travel_time, radius, moved_rect)
	var normal_value: Vector2 = earliest.get("normal", Vector2.UP)
	if contact.get("normal", Vector2.ZERO) != Vector2.ZERO:
		normal_value = contact.get("normal", normal_value)
	return {
		"hit": true,
		"overlapping": false,
		"started_inside": false,
		"t": travel_time,
		"point": center + velocity * travel_time,
		"other_point": moved_rect.position,
		"contact_point": contact.get("contact_point", moved_rect.position),
		"normal": normal_value,
		"penetration": float(contact.get("penetration", 0.0)),
		"kind": "rect",
		"edge": str(earliest.get("kind", "")),
	}


static func circle_segment_contact(
	center: Vector2,
	radius: float,
	start: Vector2,
	finish: Vector2,
	segment_radius: float = 0.0
) -> Dictionary:
	var closest := closest_point_on_segment(center, start, finish)
	var offset := center - closest
	var distance := offset.length()
	var combined := maxf(0.0, radius) + maxf(0.0, segment_radius)
	var overlapping := distance <= combined + EPSILON
	var normal := offset / distance if distance > EPSILON else segment_normal(start, finish)
	if normal == Vector2.ZERO:
		normal = Vector2.UP
	return {
		"hit": overlapping,
		"overlapping": overlapping,
		"started_inside": overlapping,
		"t": 0.0,
		"point": center,
		"contact_point": closest,
		"normal": normal,
		"penetration": maxf(0.0, combined - distance),
		"distance": distance,
	}


static func sweep_circle_segment(
	center: Vector2,
	velocity: Vector2,
	radius: float,
	start: Vector2,
	finish: Vector2,
	segment_radius: float = 0.0,
	max_time: float = STEP_DELTA
) -> Dictionary:
	var frame := maxf(0.0, max_time)
	var initial := circle_segment_contact(center, radius, start, finish, segment_radius)
	if bool(initial.get("overlapping", false)):
		initial.kind = "segment"
		return initial
	var combined := maxf(0.0, radius) + maxf(0.0, segment_radius)
	var segment := finish - start
	var length := segment.length()
	if combined <= EPSILON:
		return _sweep_point_crosses_segment(center, velocity, start, finish, frame)
	var direction := segment / length if length > EPSILON else Vector2.RIGHT
	var candidates: Array = []
	var endpoint_a := sweep_circle_circle(center, velocity, radius, start, Vector2.ZERO, segment_radius, frame)
	if bool(endpoint_a.get("hit", false)):
		endpoint_a.kind = "segment_end"
		endpoint_a.order = 0
		candidates.append(endpoint_a)
	var endpoint_b := sweep_circle_circle(center, velocity, radius, finish, Vector2.ZERO, segment_radius, frame)
	if bool(endpoint_b.get("hit", false)):
		endpoint_b.kind = "segment_end"
		endpoint_b.order = 1
		candidates.append(endpoint_b)
	if length > EPSILON:
		var normal_axis := Vector2(-direction.y, direction.x)
		var relative := center - start
		for side_index in 2:
			var side := -1.0 if side_index == 0 else 1.0
			var plane_offset := relative.dot(normal_axis) - side * combined
			var normal_speed := velocity.dot(normal_axis)
			if absf(normal_speed) <= EPSILON:
				continue
			var travel_time := -plane_offset / normal_speed
			if travel_time < -EPSILON or travel_time > frame + EPSILON:
				continue
			var travel := clampf(travel_time, 0.0, frame)
			var along := (center + velocity * travel - start).dot(direction)
			if along < -EPSILON or along > length + EPSILON:
				continue
			var hit_point := center + velocity * travel
			var hit_closest := closest_point_on_segment(hit_point, start, finish)
			var hit_normal := hit_point - hit_closest
			if hit_normal.length_squared() <= EPSILON * EPSILON:
				hit_normal = normal_axis * side
			else:
				hit_normal = hit_normal.normalized()
			candidates.append({
				"hit": true,
				"overlapping": false,
				"started_inside": false,
				"t": travel,
				"point": hit_point,
				"contact_point": hit_closest,
				"normal": hit_normal,
				"penetration": 0.0,
				"kind": "segment_side",
				"order": 10 + side_index,
			})
	var earliest := earliest_hit(candidates)
	if earliest.is_empty():
		return _miss()
	var travel_time := clampf(float(earliest.get("t", 0.0)), 0.0, frame)
	var hit_point := center + velocity * travel_time
	var closest := closest_point_on_segment(hit_point, start, finish)
	var hit_normal: Vector2 = earliest.get("normal", Vector2.UP)
	var outward := hit_point - closest
	if outward.length_squared() > EPSILON * EPSILON:
		hit_normal = outward.normalized()
	return {
		"hit": true,
		"overlapping": false,
		"started_inside": false,
		"t": travel_time,
		"point": hit_point,
		"contact_point": closest,
		"normal": hit_normal,
		"penetration": 0.0,
		"kind": "segment",
	}


static func reflect_velocity(
	velocity: Vector2,
	normal: Vector2,
	restitution: float = 1.0,
	friction: float = 0.0
) -> Vector2:
	var hit_normal := normal.normalized()
	if hit_normal == Vector2.ZERO:
		return velocity
	var normal_speed := velocity.dot(hit_normal)
	if normal_speed >= -EPSILON:
		return velocity
	var tangent := velocity - hit_normal * normal_speed
	var tangent_keep := 1.0 - clampf(friction, 0.0, 1.0)
	var bounce := -normal_speed * clampf(restitution, 0.0, 1.0)
	return tangent * tangent_keep + hit_normal * bounce


static func bounce_relative(
	velocity: Vector2,
	other_velocity: Vector2,
	normal: Vector2,
	restitution: float = 1.0,
	friction: float = 0.0
) -> Vector2:
	return other_velocity + reflect_velocity(velocity - other_velocity, normal, restitution, friction)


static func sort_hits(hits: Array) -> Array:
	var ordered := hits.duplicate()
	ordered.sort_custom(func(first: Dictionary, second: Dictionary) -> bool:
		var first_time := float(first.get("t", INF))
		var second_time := float(second.get("t", INF))
		if first_time < second_time - EPSILON:
			return true
		if second_time < first_time - EPSILON:
			return false
		var first_order := int(first.get("order", 0))
		var second_order := int(second.get("order", 0))
		if first_order != second_order:
			return first_order < second_order
		var first_key := str(first.get("id", first.get("kind", "")))
		var second_key := str(second.get("id", second.get("kind", "")))
		if first_key != second_key:
			return first_key < second_key
		var first_normal: Vector2 = first.get("normal", Vector2.ZERO)
		var second_normal: Vector2 = second.get("normal", Vector2.ZERO)
		if not is_equal_approx(first_normal.x, second_normal.x):
			return first_normal.x < second_normal.x
		return first_normal.y < second_normal.y
	)
	return ordered


static func earliest_hit(hits: Array) -> Dictionary:
	var ordered := sort_hits(hits)
	return ordered[0].duplicate(true) if not ordered.is_empty() else {}


static func closest_point_on_segment(point: Vector2, start: Vector2, finish: Vector2) -> Vector2:
	var segment := finish - start
	var length_squared := segment.length_squared()
	if length_squared <= EPSILON * EPSILON:
		return start
	var amount := clampf((point - start).dot(segment) / length_squared, 0.0, 1.0)
	return start + segment * amount


static func segment_normal(start: Vector2, finish: Vector2) -> Vector2:
	var segment := finish - start
	if segment.length_squared() <= EPSILON * EPSILON:
		return Vector2.ZERO
	return Vector2(-segment.y, segment.x).normalized()


static func closest_point_on_rect(point: Vector2, rect: Rect2) -> Vector2:
	var rect_end := rect.position + rect.size
	return Vector2(
		clampf(point.x, rect.position.x, rect_end.x),
		clampf(point.y, rect.position.y, rect_end.y)
	)


static func integral(value: Variant, fallback: int = 0) -> int:
	return int(value) if value is int or value is float else fallback


static func number(value: Variant, fallback: float = 0.0) -> float:
	return float(value) if value is int or value is float else fallback


static func _miss() -> Dictionary:
	return {
		"hit": false,
		"overlapping": false,
		"started_inside": false,
		"t": INF,
		"point": Vector2.ZERO,
		"contact_point": Vector2.ZERO,
		"normal": Vector2.ZERO,
		"penetration": 0.0,
	}


static func _sweep_point_crosses_segment(
	center: Vector2,
	velocity: Vector2,
	start: Vector2,
	finish: Vector2,
	max_time: float
) -> Dictionary:
	var segment := finish - start
	var denominator := velocity.cross(segment)
	if absf(denominator) <= EPSILON:
		return _miss()
	var difference := start - center
	var travel_time := difference.cross(segment) / denominator
	var along := difference.cross(velocity) / denominator
	if travel_time < -EPSILON or travel_time > max_time + EPSILON or along < -EPSILON or along > 1.0 + EPSILON:
		return _miss()
	travel_time = clampf(travel_time, 0.0, max_time)
	var axis := segment_normal(start, finish)
	var before := center + velocity * maxf(0.0, travel_time - 0.0001) - start
	var side := 1.0 if axis.cross(before) >= 0.0 else -1.0
	var normal := axis * side
	if normal.dot(velocity) >= 0.0:
		normal = -normal
	return {
		"hit": true,
		"overlapping": false,
		"started_inside": false,
		"t": travel_time,
		"point": center + velocity * travel_time,
		"contact_point": center + velocity * travel_time,
		"normal": normal,
		"penetration": 0.0,
		"kind": "segment_line",
	}
