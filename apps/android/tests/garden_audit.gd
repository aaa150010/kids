extends SceneTree

var output_dir := ""
var screen: Variant
var viewport: SubViewport
var action_log: Array = []
var captures: Dictionary = {}
var frame_number := 0
var performance_lines: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var save_store := root.get_node("SaveStore")
	if OS.get_environment("KIDS_PLAYGROUND_AUDIT") != "1":
		push_error("Garden audit requires isolated saves")
		quit(1)
		return
	for key in ["speechOn", "musicOn", "soundOn"]:
		save_store.set_setting(key, false)
	var profile: Dictionary = save_store.add_profile("花园体验", 8, "🦊", "#3f7a46")
	if profile.is_empty():
		profile = save_store.profiles()[0]
	output_dir = ProjectSettings.globalize_path("res://").path_join("../../build/ui-audit")
	DirAccess.make_dir_recursive_absolute(output_dir.path_join("garden-frames"))
	viewport = SubViewport.new()
	viewport.size = Vector2i(1600, 1131)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var content := root.get_node("ContentDB")
	var meta: Dictionary = content.game("garden").duplicate(true)
	meta.modeId = "classic"
	meta.difficultyPreference = "normal"
	var script: GDScript = load("res://src/games/garden_game.gd")
	if script == null or not script.can_instantiate():
		quit(1)
		return
	screen = script.new()
	screen.setup(meta, [profile])
	print("Garden audit: creating native game")
	viewport.add_child(screen)
	screen.set_process(false)
	await _frames(5)
	if "--pool-only" in OS.get_cmdline_user_args():
		await _capture_worlds([21])
		await _finish_audit("garden-pool-replay.json")
		return
	print("Garden audit: tutorial")
	screen.call("_process", 1.0 / 30.0)
	_collect()
	_action("sunflower", 2, 0)
	_action("peashooter", 2, 1)
	screen.call("_toggle_shovel")
	screen.call("_battle_cell", 2, 0)
	for index in 210:
		screen.call("_process", 1.0 / 30.0)
	_collect()
	_action("wallnut", 2, 4)
	await _frames(4)
	screen.call("_tutorial_mower")
	await _frames(4)
	screen.toggle_pause(true)
	screen.call("_close_top_modal")
	screen.toggle_pause(false)
	screen.call("_cycle_speed")
	await _frames(30)
	print("Garden audit: adventure")
	while not screen._modal_stack.is_empty():
		screen.call("_close_top_modal")
	screen.toggle_pause(false)
	screen.call("_choose_level", 1)
	screen.call("_begin_battle", false)
	screen.speed = 1
	await _frames(8)
	_action("sunflower", 2, 0)
	_action("peashooter", 2, 1)
	for tick in 2100:
		_collect()
		var battle: Dictionary = screen.battle
		if int(battle.sun) >= 50 and battle.grid[23].is_empty() and float(battle.cooldowns.get("wallnut", 0)) <= 0:
			_action("wallnut", 2, 5)
		screen.call("_process", 1.0 / 30.0)
		if str(battle.phase) != "playing":
			break
		if tick % 4 == 0:
			await process_frame
			RenderingServer.force_draw(false)
			if tick >= 600 and tick <= 1440:
				var frame := viewport.get_texture().get_image()
				frame.resize(960, 679, Image.INTERPOLATE_LANCZOS)
				frame.save_png(output_dir.path_join("garden-frames/%05d.png" % frame_number))
				frame_number += 1
			if tick == 1000:
				await _capture("garden-runtime")
				await _capture_grid("garden-runtime")
		for zombie in battle.zombies:
			var visible := float(zombie.x) > .8 and float(zombie.x) < 8.2
			if visible and not bool(zombie.hasArm) and bool(zombie.hasHead) and not captures.has("arm"):
				captures.arm = true
				await _capture("garden-arm")
			if visible and not bool(zombie.hasHead) and not captures.has("head"):
				captures.head = true
				await _capture("garden-headless")
	await _capture("garden-end")
	await _capture_worlds()
	await _sample_performance("garden-boss")
	await _stress_performance()
	await _finish_audit()


func _finish_audit(replay_name: String = "garden-replay.json") -> void:
	var art_missing: Dictionary = screen.field.art.missing
	print("Garden audit replay actions=", action_log.size(), " frames=", frame_number, " captures=", captures, " missing=", art_missing)
	var file := FileAccess.open(output_dir.path_join(replay_name), FileAccess.WRITE)
	file.store_string(JSON.stringify({"schemaVersion": 1, "actions": action_log, "captures": captures, "frames": frame_number, "missing": art_missing}, "\t"))
	file.close()
	if not performance_lines.is_empty():
		var performance := FileAccess.open(output_dir.path_join("garden-performance-report.txt"), FileAccess.WRITE)
		performance.store_string("Desktop logical viewport 1600x1131; 30Hz rules, target 120 FPS.\n" + "\n".join(performance_lines))
		performance.close()
	screen.queue_free()
	viewport.queue_free()
	await _frames(3)
	quit(0 if art_missing.is_empty() and bool(captures.get("poolSupportedPeashooter", false)) else 1)


func _action(kind: String, row: int, column: int) -> void:
	var battle: Dictionary = screen.battle
	if not screen.engine.can_plant(battle, row, column, kind).is_empty():
		return
	screen.call("_select_battle_seed", kind)
	screen.call("_battle_cell", row, column)
	action_log.append({"level": int(battle.levelId), "time": float(battle.time), "action": "plant", "kind": kind, "row": row, "column": column})


func _collect() -> void:
	for sun in screen.battle.get("suns", []).duplicate():
		if not bool(sun.get("collecting", false)):
			screen.call("_collect_sun", int(sun.uid))
			action_log.append({"time": float(screen.battle.time), "action": "sun", "uid": int(sun.uid)})


func _capture(name: String) -> void:
	await process_frame
	RenderingServer.force_draw(false)
	var image := viewport.get_texture().get_image()
	for dimensions in [Vector2i(3000, 2120), Vector2i(3392, 2400), Vector2i(1180, 800)]:
		viewport.size = Vector2i(1180, 800) if dimensions.x == 1180 else Vector2i(1600, 1132 if dimensions.x == 3392 else 1131)
		await _frames(3)
		RenderingServer.force_draw(false)
		image = viewport.get_texture().get_image()
		var folder := output_dir.path_join("%sx%s" % [dimensions.x, dimensions.y])
		DirAccess.make_dir_recursive_absolute(folder)
		var result := image.duplicate()
		result.resize(dimensions.x, dimensions.y, Image.INTERPOLATE_LANCZOS)
		result.save_png(folder.path_join(name + ".png"))
	viewport.size = Vector2i(1600, 1131)
	await _frames(3)


func _capture_grid(name: String) -> void:
	var field: Control = screen.field
	var guides := Control.new()
	guides.mouse_filter = Control.MOUSE_FILTER_IGNORE
	field.add_child(guides)
	field.resized.connect(guides.queue_redraw)
	guides.draw.connect(func():
		guides.draw_set_transform_matrix(field.call("_transform"))
		for row in screen.battle.activeRows:
			for column in 9:
				var polygon := GardenLayout.cell_polygon(screen.battle, int(row), column)
				polygon.append(polygon[0])
				guides.draw_polyline(polygon, Color(1, .96, .68, .55), .8, true)
				guides.draw_circle(GardenLayout.cell_center(screen.battle, int(row), column), 2.2, Color("#84d5ff"))
		for layer in ["bases", "grid"]:
			for plant in screen.battle[layer]:
				if plant.is_empty():
					continue
				var anchor := GardenLayout.plant_anchor(screen.battle, plant)
				guides.draw_line(anchor - Vector2(6, 0), anchor + Vector2(6, 0), Color("#ffdd79"), 1.5)
	)
	guides.queue_redraw()
	await _capture(name + "-grid")
	guides.queue_free()
	await _frames(2)


func _frames(count: int) -> void:
	for index in count:
		await process_frame


func _capture_worlds(level_ids: Array = [4, 11, 21, 31, 41, 50]) -> void:
	var decks := {
		4: ["peashooter", "sunflower", "wallnut", "cherrybomb", "potatomine", "snowpea", "repeater", "chomper", "threepeater", "tallnut"],
		11: ["puffshroom", "sunshroom", "wallnut", "gravebuster", "fumeshroom", "hypnoshroom", "scaredyshroom", "cherrybomb"],
		21: ["lilypad", "peashooter", "sunflower", "wallnut", "tanglekelp", "seashroom", "snowpea", "cherrybomb"],
		31: ["lilypad", "puffshroom", "sunshroom", "seashroom", "plantern", "blover", "cactus", "wallnut"],
		41: ["flowerpot", "sunflower", "cabbagepult", "kernelpult", "melonpult", "wallnut", "umbrella", "cherrybomb"],
	}
	for level_id in level_ids:
		while not screen._modal_stack.is_empty():
			screen.call("_close_top_modal")
		screen.toggle_pause(false)
		screen.call("_choose_level", level_id)
		if level_id != 50:
			screen.selected_seeds = decks[level_id].duplicate()
			screen.call("_begin_battle", false)
		screen.speed = 1
		await _frames(5)
		for tick in 960:
			_collect()
			var battle: Dictionary = screen.battle
			var environment := str(battle.environment)
			if environment in ["day", "pool"]:
				_action("sunflower", 0, 0)
				if environment == "day":
					_action("peashooter", 2, 1)
			elif environment in ["night", "fog"]:
				_action("sunshroom", 0, 0)
				_action("puffshroom", 1, 1)
				_action("puffshroom", 4, 2)
			if environment in ["pool", "fog"]:
				_action("lilypad", 2, 1)
				if environment == "pool":
					_action("peashooter", 2, 1)
				_action("seashroom", 3, 2)
				_action("plantern", 1, 4)
			if environment == "roof":
				_action("sunflower", 0, 0)
				_action("cabbagepult", 2, 1)
				if level_id == 50:
					for packet in battle.packets.duplicate():
						for column in range(0, 7):
							for row in battle.activeRows:
								_action(str(packet.kind), int(row), column)
			if environment not in ["pool", "fog"]:
				_action("wallnut", 2, 5)
			screen.call("_process", 1.0 / 30.0)
			if tick % 30 == 0:
				await process_frame
			if str(battle.phase) != "playing":
				break
		if int(level_id) == 21:
			var restored: Dictionary = screen.engine.restore(screen.engine.snapshot(screen.battle))
			var supported := not restored.is_empty() and str(restored.bases[19].get("kind", "")) == "lilypad" and str(restored.grid[19].get("kind", "")) == "peashooter"
			captures.poolSupportedPeashooter = supported
			if not supported:
				push_error("Pool audit must show a peashooter on its lily pad and preserve both in the snapshot")
		await _capture("garden-" + str(screen.battle.environment) + ("-boss" if level_id == 50 else ""))
		if level_id in [4, 21, 41]:
			await _capture_grid("garden-" + str(screen.battle.environment))
		print("Garden audit: captured world ", level_id)


func _sample_performance(label: String) -> void:
	var samples: Array[float] = []
	var previous := Time.get_ticks_usec()
	for warmup in 30:
		await process_frame
		previous = Time.get_ticks_usec()
	for index in 120:
		await process_frame
		var now := Time.get_ticks_usec()
		var elapsed := float(now - previous) / 1000000.0
		screen.call("_process", minf(.05, elapsed))
		samples.append(elapsed * 1000)
		previous = now
	samples.sort()
	var total := 0.0
	for sample in samples:
		total += sample
	var average := total / samples.size()
	var result := "%s avg=%.2fms p95=%.2fms fps=%.1f plants=%s zombies=%s" % [label, average, samples[int(samples.size() * .95)], 1000.0 / maxf(.01, average), screen.battle.grid.filter(func(plant): return not plant.is_empty()).size(), screen.battle.zombies.size()]
	performance_lines.append(result)
	print(result)


func _stress_performance() -> void:
	var state: Dictionary = screen.engine.create(screen.players[0], 4, "adventure", ["peashooter", "sunflower", "wallnut", "repeater", "snowpea", "chomper"], false, "normal")
	for row in 5:
		for column in range(0, 5):
			state.grid[row * 9 + column] = screen.engine._new_plant(state, "peashooter" if column > 0 else "sunflower", row, column)
	for index in 80:
		var zombie: Dictionary = screen.engine._spawn_zombie(state, "bucket" if index % 3 == 0 else "normal", index % 5)
		zombie.x = 5.5 + float(index / 5) * .2
	screen.battle = state
	screen.call("_render_battle")
	for frame in 480:
		await process_frame
		screen.call("_process", 1.0 / 120.0)
	await _sample_performance("garden-stress-controlled-fixture")
