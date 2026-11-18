class_name GardenArt
extends RefCounted

const ROOT := "res://assets/garden/runtime/"

var textures: Dictionary = {}
var definitions: Dictionary = {}
var missing: Dictionary = {}


func texture(path: String) -> Texture2D:
	if textures.has(path):
		return textures[path]
	var full_path := path if path.begins_with("res://") else ROOT + path
	if not ResourceLoader.exists(full_path):
		if not missing.has(path):
			missing[path] = true
			push_error("花园缺少素材：" + full_path)
		return null
	var loaded: Texture2D = load(full_path)
	textures[path] = loaded
	return loaded


func definition(path: String) -> Dictionary:
	if definitions.has(path):
		return definitions[path]
	var full_path := ROOT + path
	if not FileAccess.file_exists(full_path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(full_path))
	var result: Dictionary = parsed if parsed is Dictionary else {}
	definitions[path] = result
	return result


func draw_image(canvas: CanvasItem, path: String, rect: Rect2, tint: Color = Color.WHITE, keep_aspect: bool = false) -> void:
	var image := texture(path)
	if image == null:
		return
	var target := rect
	if keep_aspect:
		var factor := minf(rect.size.x / image.get_width(), rect.size.y / image.get_height())
		var dimensions := image.get_size() * factor
		target = Rect2(rect.position + (rect.size - dimensions) * .5, dimensions)
	canvas.draw_texture_rect(image, target, false, tint)


func has_clip(clip: String) -> bool:
	return ContentDB.garden_presentation.get("actors", {}).has(clip) or ContentDB.garden_presentation.get("plants", {}).has(clip) or ContentDB.garden_presentation.get("animations", {}).has(clip)


func draw_actor(canvas: CanvasItem, clip: String, clock: float, anchor: Vector2, root_transform: Transform2D, tint: Color = Color.WHITE, loop: bool = true, flags: Dictionary = {}, baked: bool = false) -> void:
	if (RuntimeQuality.quality_level <= 1 or baked) and bool(flags.get("hasArm", true)) and bool(flags.get("hasHead", true)) and ContentDB.garden_presentation.get("animations", {}).has(clip):
		_draw_clip(canvas, clip, clock, anchor, root_transform, tint, loop)
		return
	var actors: Dictionary = ContentDB.garden_presentation.get("actors", {})
	var plants: Dictionary = ContentDB.garden_presentation.get("plants", {})
	var model: Dictionary = {}
	var motion: Dictionary = {}
	var atlas: Texture2D
	if plants.has(clip):
		model = definition("plant-motion/" + clip + ".json")
		motion = model
		atlas = texture("plant-motion/" + clip + ".webp")
		var shooting: Dictionary = model.get("shooting", {})
		var attack_clock := float(flags.get("attackClock", 100))
		if not shooting.is_empty() and attack_clock >= 0 and attack_clock * 100 < float(shooting.get("duration", 0)):
			motion = shooting
			clock = attack_clock
			loop = false
	elif clip.begins_with("gargantuar-"):
		model = definition("giant-motion/gargantuar.json")
		var action := clip.get_slice("-", clip.get_slice_count("-") - 1)
		var giant_clip: Dictionary = model.get("clips", {}).get(action, {})
		motion = {"duration": giant_clip.get("duration", 100), "origin": model.get("origin", [0, 0]), "groups": [{"tracks": giant_clip.get("tracks", [])}]}
		atlas = texture("giant-motion/gargantuar.webp")
	elif actors.has(clip):
		var family := str(actors[clip])
		model = definition("actor-motion/" + family + ".json")
		motion = model.get("clips", {}).get(clip, {})
		atlas = texture("actor-motion/" + family + ".webp")
	if not motion.is_empty() and atlas != null:
		_draw_rig(canvas, model, motion, atlas, clock, anchor, root_transform, tint, loop, flags)
		return
	_draw_clip(canvas, clip, clock, anchor, root_transform, tint, loop)


func _frame(clock: float, duration: float, length: int, loop: bool) -> Dictionary:
	var progress := fposmod(clock * 100.0, maxf(1, duration)) / maxf(1, duration) if loop else clampf(clock * 100.0 / maxf(1, duration), 0, 1)
	var position := progress * (length if loop else maxi(0, length - 1))
	var current := mini(length - 1, int(floor(position)))
	return {"current": maxi(0, current), "next": (current + 1) % maxi(1, length) if loop else mini(length - 1, current + 1), "blend": position - floor(position)}


func _pose(first: Array, second: Array, blend: float) -> Transform2D:
	var position := Vector2(lerpf(float(first[0]), float(second[0]), blend), lerpf(float(first[1]), float(second[1]), blend))
	var scale_x := lerpf(float(first[2]), float(second[2]), blend)
	var scale_y := lerpf(float(first[3]), float(second[3]), blend)
	var skew_x := deg_to_rad(lerpf(float(first[4]), float(second[4]), blend))
	var skew_y := deg_to_rad(lerpf(float(first[5]), float(second[5]), blend))
	return Transform2D(Vector2(cos(skew_x), sin(skew_x)) * scale_x, Vector2(-sin(skew_y), cos(skew_y)) * scale_y, position)


func _draw_rig(canvas: CanvasItem, model: Dictionary, motion: Dictionary, atlas: Texture2D, clock: float, anchor: Vector2, root_transform: Transform2D, tint: Color, loop: bool, flags: Dictionary) -> void:
	var origin: Array = motion.get("origin", model.get("origin", [0, 0]))
	var actor_scale := float(motion.get("scale", 1.0))
	var local := Transform2D.IDENTITY.scaled(Vector2.ONE * actor_scale)
	local.origin = anchor + Vector2(float(origin[0]), float(origin[1]))
	var root := root_transform * local
	var frames: Dictionary = model.get("frames", {})
	for group in motion.get("groups", []):
		var transform := root
		var samples: Dictionary = {}
		var attachment: Array = group.get("attachment", [])
		if not attachment.is_empty():
			var attachment_frame := _frame(clock, float(motion.get("duration", 100)), attachment.size(), loop)
			transform = root * _pose(attachment[int(attachment_frame.current)], attachment[int(attachment_frame.next)], float(attachment_frame.blend)) * _pose(attachment[0], attachment[0], 0).affine_inverse()
		for track in group.get("tracks", []):
			var poses: Array = track.get("poses", [])
			if poses.is_empty():
				continue
			if not samples.has(poses.size()):
				samples[poses.size()] = _frame(clock, float(motion.get("duration", 100)), poses.size(), loop)
			var sample: Dictionary = samples[poses.size()]
			var first: Array = poses[int(sample.current)]
			var second: Array = poses[int(sample.next)]
			var frame_key := str(first[8])
			var track_name := str(track.get("name", "")).to_lower()
			if frame_key.is_empty() or float(first[6]) < 0 or float(first[7]) <= 0 or not frames.has(frame_key):
				continue
			if flags.get("hasArm", true) == false and "outerarm" in track_name:
				if "upper" in frame_key.to_lower() and frames.has(frame_key + "2"):
					frame_key += "2"
				elif "lower" in frame_key.to_lower() or "hand" in frame_key.to_lower():
					continue
			if flags.get("hasHead", true) == false and ("head" in track_name or "jaw" in track_name or "hair" in track_name or "eye" in track_name or "tongue" in track_name):
				continue
			var part := transform * _pose(first, second, float(sample.blend))
			var attack_clock := float(flags.get("attackClock", 100))
			if attack_clock >= 0 and attack_clock < .2 and ("head" in track_name or "mouth" in track_name) and flags.has("attackClock"):
				part = part.scaled_local(Vector2(1 + sin(attack_clock / .2 * PI) * .08, 1))
			canvas.draw_set_transform_matrix(part)
			var rectangle: Array = frames[frame_key]
			var frame_rect := Rect2(float(rectangle[0]), float(rectangle[1]), float(rectangle[2]), float(rectangle[3]))
			var color := Color(tint, tint.a * lerpf(float(first[7]), float(second[7]), float(sample.blend)))
			canvas.draw_texture_rect_region(atlas, Rect2(Vector2.ZERO, frame_rect.size), Rect2(frame_rect.position * 2, frame_rect.size * 2), color)
			if flags.has("maxArmor") and float(flags.maxArmor) > 0 and ("CONE" in frame_key or "BUCKET" in frame_key or "HELMET" in frame_key):
				var ratio := float(flags.get("armor", 0)) / float(flags.maxArmor)
				if ratio > 0 and ratio < 2.0 / 3.0:
					var points := PackedVector2Array([Vector2(frame_rect.size.x * .3, 3), Vector2(frame_rect.size.x * .48, frame_rect.size.y * .25), Vector2(frame_rect.size.x * .37, frame_rect.size.y * .45), Vector2(frame_rect.size.x * .6, frame_rect.size.y * .65)])
					canvas.draw_polyline(points, Color("#4b3726"), 1.8, true)
					if ratio < 1.0 / 3.0:
						canvas.draw_line(Vector2(4, frame_rect.size.y * .6), Vector2(frame_rect.size.x * .65, frame_rect.size.y * .45), Color("#4b3726"), 2.4, true)
	canvas.draw_set_transform_matrix(root_transform)


func draw_boss(canvas: CanvasItem, state: Dictionary, root_transform: Transform2D) -> void:
	var tracks := definition("boss/tracks.json")
	var boss: Dictionary = state.get("boss", {})
	if tracks.is_empty() or boss.is_empty():
		return
	var clock := float(boss.get("actionAge", 0))
	var clip := "anim_idle"
	var loop := true
	if str(boss.phase) == "head":
		clip = "anim_head_enter" if clock < 3.15 else "anim_head_idle" if float(boss.timer) > 2.5 else "anim_head_leave"
		clock = clock if clip == "anim_head_enter" else maxf(0, 2.5 - float(boss.timer)) if clip == "anim_head_leave" else clock - 3.15
		loop = clip == "anim_head_idle"
	elif str(boss.phase) == "stomp" and clock < 2:
		clip = "anim_RV_1" if int(boss.get("attack", 0)) % 8 == 2 else "anim_stomp_" + str(clampi(int(boss.row) + 1, 1, 4))
		loop = false
	elif str(boss.phase) == "idle" and clock < 1.4:
		clip = "anim_spawn_" + str(5 - clampi(int(boss.row), 0, 4))
		loop = false
	var tint := Color("#a8d7ff") if float(boss.get("frozenTimer", 0)) > 0 else Color.WHITE
	var attachment := _draw_boss_tracks(canvas, tracks.get("body", {}), clip, clock, 18, root_transform, tint, loop)
	if not attachment.is_empty() and float(attachment[6]) >= 0:
		var driver := root_transform * Transform2D(Vector2(1.2, 0), Vector2(0, 1.2), Vector2(float(attachment[0]) + 28, float(attachment[1]) - 84))
		_draw_boss_tracks(canvas, tracks.get("driver", {}), "anim_idle", float(boss.age), 18, driver, tint, true)
	if not boss.get("ball", {}).is_empty():
		var ball: Dictionary = boss.ball
		var origin := GardenLayout.foot(state, int(ball.row), float(ball.x)) - Vector2(75, 120)
		var ball_transform := root_transform * Transform2D(0, origin)
		var age := float(ball.get("age", 0))
		_draw_boss_tracks(canvas, tracks.get(str(ball.kind), {}), "anim_form" if age < 1 else "anim_role", age if age < 1 else age - 1, 16 if age < 1 else 2, ball_transform, Color.WHITE, age >= 1)
	canvas.draw_set_transform_matrix(root_transform)


func _draw_boss_tracks(canvas: CanvasItem, rig: Dictionary, clip: String, clock: float, fps: float, root_transform: Transform2D, tint: Color, loop: bool) -> Array:
	var bounds: Array = rig.get("clips", {}).get(clip, [0, 1])
	var length := int(bounds[1])
	var position := fposmod(clock * fps, maxf(1, length)) if loop else clampf(clock * fps, 0, maxi(0, length - 1))
	var frame := int(floor(position))
	var next := (frame + 1) % maxi(1, length) if loop else mini(length - 1, frame + 1)
	var attachment: Array = []
	for track in rig.get("tracks", []):
		var poses: Array = track.get("poses", [])
		if poses.is_empty():
			continue
		var first: Array = poses[mini(poses.size() - 1, int(bounds[0]) + frame)]
		var second: Array = poses[mini(poses.size() - 1, int(bounds[0]) + next)]
		if str(track.get("name", "")) == "Boss_head2":
			attachment = first.duplicate()
			attachment[0] = lerpf(float(first[0]), float(second[0]), position - frame)
			attachment[1] = lerpf(float(first[1]), float(second[1]), position - frame)
		if str(first[8]).is_empty() or float(first[6]) < 0 or float(first[7]) <= 0:
			continue
		var image := texture("boss/" + str(first[8]) + ".webp")
		if image == null:
			continue
		canvas.draw_set_transform_matrix(root_transform * _pose(first, second, position - frame))
		canvas.draw_texture_rect(image, Rect2(Vector2.ZERO, image.get_size() * .5), false, Color(tint, tint.a * float(first[7])))
	canvas.draw_set_transform_matrix(root_transform)
	return attachment


func _draw_clip(canvas: CanvasItem, name: String, clock: float, anchor: Vector2, root_transform: Transform2D, tint: Color, loop: bool) -> void:
	var clip: Dictionary = ContentDB.garden_presentation.get("animations", {}).get(name, {})
	if clip.is_empty():
		if not missing.has(name):
			missing[name] = true
			push_error("花园缺少动作：" + name)
		return
	var durations: Array = clip.get("durations", [])
	var total := 0.0
	for duration in durations:
		total += float(duration)
	var time := fposmod(clock * 100.0, maxf(1, total)) if loop else minf(total - .001, clock * 100.0)
	var frame_index := 0
	for duration in durations:
		if time < float(duration):
			break
		time -= float(duration)
		frame_index += 1
	var frames: Array = clip.get("frames", [])
	if frames.is_empty():
		return
	var frame: Array = frames[mini(frames.size() - 1, frame_index)]
	var atlas := texture(str(clip.pages[int(frame[0])]))
	if atlas == null:
		return
	var origin: Array = clip.get("anchor", [0, 0])
	var position := anchor + Vector2(float(frame[5]) - float(origin[0]), float(frame[6]) - float(origin[1]))
	canvas.draw_set_transform_matrix(root_transform)
	canvas.draw_texture_rect_region(atlas, Rect2(position, Vector2(float(frame[3]), float(frame[4]))), Rect2(float(frame[1]) * 2, float(frame[2]) * 2, float(frame[3]) * 2, float(frame[4]) * 2), tint)


func draw_part(canvas: CanvasItem, family_clip: String, part: String, anchor: Vector2, root_transform: Transform2D, rotation: float, tint: Color) -> void:
	var family := str(ContentDB.garden_presentation.get("actors", {}).get(family_clip, "zombie"))
	var model := definition("actor-motion/" + family + ".json")
	var atlas := texture("actor-motion/" + family + ".webp")
	if atlas == null:
		return
	var frames: Dictionary = model.get("frames", {})
	var candidates := ["ZOMBIE_HEAD"] if part == "head" else ["ZOMBIE_OUTERARM_LOWER", "ZOMBIE_OUTERARM_HAND"] if part == "arm" else ["ZOMBIE_CONE1", "ZOMBIE_BUCKET1", "ZOMBIE_FOOTBALL_HELMET"]
	for key in candidates:
		if not frames.has(key):
			continue
		var frame: Array = frames[key]
		var region := Rect2(float(frame[0]), float(frame[1]), float(frame[2]), float(frame[3]))
		var local := Transform2D(rotation, anchor)
		canvas.draw_set_transform_matrix(root_transform * local)
		canvas.draw_texture_rect_region(atlas, Rect2(-region.size * .5, region.size), Rect2(region.position * 2, region.size * 2), tint)
		break
	canvas.draw_set_transform_matrix(root_transform)
