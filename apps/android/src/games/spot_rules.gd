class_name SpotRules
extends GameSession

const VERSION := 1
const DIFFERENCE_COUNT := 5


func create_session(context: Dictionary) -> Dictionary:
	super.create_session(context)
	var scene: Dictionary = context.get("scene", {}).duplicate(true)
	var differences: Array = scene.get("differences", []) if scene.get("differences") is Array else []
	var session_level := clampi(int(context.get("levelId", 1)), 1, 999)
	var session_view := str(context.get("view", "scene"))
	state.merge({
		"spotVersion": VERSION,
		"levelId": session_level,
		"view": session_view if session_view in ["map", "scene"] else "scene",
		"scene": scene,
		"sceneId": str(scene.get("id", "")),
		"foundIds": [],
		"wrongTaps": 0,
		"hints": 0,
		"hintsMax": maxi(0, int(context.get("hintsMax", 3))),
		"hintId": "",
		"phase": "playing" if differences.size() == DIFFERENCE_COUNT else "empty",
		"stars": 0,
		"reported": false,
	}, true)
	return state


func total() -> int:
	var differences: Variant = state.get("scene", {}).get("differences", [])
	return differences.size() if differences is Array else 0


func found_count() -> int:
	var found: Variant = state.get("foundIds", [])
	return found.size() if found is Array else 0


func difference(difference_id: String) -> Dictionary:
	var differences: Variant = state.get("scene", {}).get("differences", [])
	if differences is Array:
		for entry in differences:
			if entry is Dictionary and str(entry.get("id", "")) == difference_id:
				return entry
	return {}


func handle_input(action: Dictionary) -> Dictionary:
	if str(state.get("phase", "")) != "playing":
		return {"ok": false}
	match str(action.get("type", "")):
		"tap":
			var x_value: Variant = action.get("x", -1.0)
			var y_value: Variant = action.get("y", -1.0)
			if not _number(x_value) or not _number(y_value):
				return {"ok": false}
			var point := Vector2(float(x_value), float(y_value))
			if point.x < 0.0 or point.x > 1.0 or point.y < 0.0 or point.y > 1.0:
				return {"ok": false}
			var touch_radius := 0.0
			var touch_value: Variant = action.get("touchRadius", 0.0)
			if _number(touch_value):
				touch_radius = clampf(float(touch_value), 0.0, 0.2)
			var nearest := {}
			var nearest_found := {}
			var nearest_distance := INF
			var nearest_found_distance := INF
			for entry in state.get("scene", {}).get("differences", []):
				if not entry is Dictionary:
					continue
				var center := Vector2(float(entry.get("x", 0.0)), float(entry.get("y", 0.0)))
				var radius := maxf(0.045, maxf(float(entry.get("radius", 0.07)), touch_radius))
				var distance := point.distance_to(center)
				if distance > radius:
					continue
				if str(entry.get("id", "")) in state.foundIds:
					if distance < nearest_found_distance:
						nearest_found = entry
						nearest_found_distance = distance
				elif distance < nearest_distance:
					nearest = entry
					nearest_distance = distance
			if nearest.is_empty() and not nearest_found.is_empty():
				return {"ok": true, "already": true, "found": str(nearest_found.get("id", ""))}
			if nearest.is_empty():
				state.wrongTaps = int(state.get("wrongTaps", 0)) + 1
				return {"ok": true, "wrong": true}
			var difference_id := str(nearest.get("id", ""))
			state.foundIds.append(difference_id)
			state.hintId = ""
			var completed := found_count() >= total()
			if completed:
				state.phase = "result"
				state.stars = stars()
			return {
				"ok": true,
				"found": difference_id,
				"completed": completed,
				"foundCount": found_count(),
				"total": total(),
			}
		"hint":
			if int(state.get("hints", 0)) >= int(state.get("hintsMax", 3)):
				return {"ok": false, "message": "提示次数已经用完了"}
			for entry in state.get("scene", {}).get("differences", []):
				if not entry is Dictionary or str(entry.get("id", "")) in state.foundIds:
					continue
				state.hints = int(state.get("hints", 0)) + 1
				state.hintId = str(entry.get("id", ""))
				return {"ok": true, "hintId": state.hintId}
			return {"ok": false, "message": "已经找到全部不同"}
	return {"ok": false}


func stars() -> int:
	if str(state.get("phase", "")) != "result":
		return 0
	var hints := int(state.get("hints", 0))
	var mistakes := int(state.get("wrongTaps", 0))
	if hints == 0 and mistakes <= 1:
		return 3
	if hints <= 2 and mistakes <= 4:
		return 2
	return 1


func result() -> Dictionary:
	if str(state.get("phase", "")) != "result":
		return {}
	return {
		"winner": -1,
		"phase": "result",
		"reason": "找到全部不同",
		"found": found_count(),
		"total": total(),
		"wrongTaps": int(state.get("wrongTaps", 0)),
		"hints": int(state.get("hints", 0)),
		"stars": stars(),
	}


func snapshot() -> Dictionary:
	state.spotVersion = VERSION
	return super.snapshot()


func restore(value: Dictionary) -> bool:
	var version_value: Variant = value.get("spotVersion", null)
	if not _number(version_value) or int(version_value) != VERSION:
		return false
	if not super.restore(value):
		return false
	var level_value: Variant = state.get("levelId", null)
	if not _number(level_value) or int(level_value) < 1 or int(level_value) > 999:
		return false
	if str(state.get("view", "scene")) not in ["map", "scene"]:
		return false
	var scene: Variant = state.get("scene", {})
	if not scene is Dictionary:
		return false
	var objects: Variant = scene.get("objects", [])
	var differences: Variant = scene.get("differences", [])
	var scene_valid := not str(scene.get("id", "")).strip_edges().is_empty()
	scene_valid = scene_valid and not str(scene.get("title", "")).strip_edges().is_empty()
	scene_valid = scene_valid and objects is Array and differences is Array
	scene_valid = scene_valid and differences.size() == DIFFERENCE_COUNT
	if not scene_valid:
		return false
	if str(state.get("sceneId", "")) != str(scene.get("id", "")):
		return false
	var object_map := {}
	for entry in objects:
		if not entry is Dictionary:
			return false
		var object_id := str(entry.get("id", "")).strip_edges()
		if object_id.is_empty() or object_map.has(object_id):
			return false
		if not _number(entry.get("x", null)) or not _number(entry.get("y", null)):
			return false
		if not _number(entry.get("size", null)) or str(entry.get("kind", "")).is_empty():
			return false
		var object_x := float(entry.x)
		var object_y := float(entry.y)
		if object_x < 0.0 or object_x > 1.0 or object_y < 0.0 or object_y > 1.0:
			return false
		object_map[object_id] = entry
	if not state.get("foundIds") is Array:
		return false
	if not state.get("reported", null) is bool:
		return false
	for key in ["hints", "hintsMax", "wrongTaps"]:
		if not _number(state.get(key, null)):
			return false
	var valid_ids := {}
	var used_objects := {}
	for entry in differences:
		if not entry is Dictionary:
			return false
		var identifier := str(entry.get("id", ""))
		if identifier.is_empty() or valid_ids.has(identifier):
			return false
		valid_ids[identifier] = true
		var object_id := str(entry.get("objectId", ""))
		if not object_map.has(object_id) or used_objects.has(object_id):
			return false
		used_objects[object_id] = true
		var object: Dictionary = object_map[object_id]
		var right: Variant = object.get("right", {})
		if not right is Dictionary:
			return false
		var right_values: Dictionary = right
		if right_values.is_empty():
			return false
		if not _number(entry.get("x", null)) or not _number(entry.get("y", null)):
			return false
		var x := float(entry.x)
		var y := float(entry.y)
		var radius := float(entry.get("radius", 0.07))
		if x < 0.0 or x > 1.0 or y < 0.0 or y > 1.0 or radius < 0.03 or radius > 0.3:
			return false
		if absf(x - float(object.x)) > 0.02 or absf(y - float(object.y)) > 0.02:
			return false
	var seen_found := {}
	for identifier in state.foundIds:
		if not identifier is String or not valid_ids.has(identifier) or seen_found.has(identifier):
			return false
		seen_found[identifier] = true
	var phase := str(state.get("phase", ""))
	if phase not in ["playing", "result"]:
		return false
	if phase == "result" and state.foundIds.size() != differences.size():
		return false
	if phase == "playing" and state.foundIds.size() >= differences.size():
		return false
	state.spotVersion = VERSION
	state.sceneId = str(scene.get("id", ""))
	state.hintsMax = clampi(int(state.get("hintsMax", 3)), 0, 10)
	state.hints = clampi(int(state.get("hints", 0)), 0, state.hintsMax)
	state.wrongTaps = maxi(0, int(state.get("wrongTaps", 0)))
	state.stars = stars() if phase == "result" else 0
	var hint_id := str(state.get("hintId", ""))
	state.hintId = hint_id if valid_ids.has(hint_id) and not (hint_id in state.foundIds) else ""
	state.reported = bool(state.get("reported", false))
	return true


func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))
