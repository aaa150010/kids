extends SceneTree

var failures: Array[String] = []
var checks := 0
var engine: Variant
var content: Node
var player := {"id": "garden-fixture", "name": "花园测试", "age": 8, "avatar": "🦊", "color": "#3f7a46"}


func _init() -> void:
	call_deferred("_run")


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)


func session(level_id: int = 4) -> Dictionary:
	return engine.create(player, level_id, "adventure", content.garden_rules.playable.duplicate(), false, "normal")


func step(state: Dictionary, seconds: float) -> void:
	for index in int(ceil(seconds * 30)):
		engine.tick(state, 1.0 / 30.0)


func _run() -> void:
	content = root.get_node("ContentDB")
	var engine_script: GDScript = load("res://src/games/garden_engine.gd")
	if engine_script == null or not engine_script.can_instantiate():
		quit(1)
		return
	engine = engine_script.new()
	check(engine != null, "garden engine loads")
	if engine == null:
		quit(1)
		return
	check(content.garden_rules.playable.size() == 48, "48 playable plant definitions")
	check(content.garden_presentation.actors.size() >= 170, "full actor animation catalog")
	for script_path in ["res://src/games/garden_art.gd", "res://src/games/garden_field.gd", "res://src/games/garden_game.gd"]:
		var script: GDScript = load(script_path)
		check(script != null and script.can_instantiate(), script_path + " compiles")
	var state := session()
	for level_id in [4, 11, 21, 31, 41]:
		var layout_state := session(level_id)
		var roof := str(layout_state.environment) == "roof"
		var height := 85.0 if str(layout_state.environment) in ["pool", "fog", "roof"] else 100.0
		for row in layout_state.rows:
			for column in 9:
				var x := 80.0 + column * 80.0
				var rise := maxf(0, 440.0 - x) * .25 if roof else 0.0
				var center := Vector2(x, 80.0 + row * height + height * .5 + rise - (10.0 if roof else 0.0))
				check(GardenLayout.cell_at(layout_state, center) == Vector2i(column, row), "level %s row %s column %s visible center selects its cell" % [level_id, row, column])
				var baseline := 58.0 if roof else 68.0 if height == 85.0 else 78.0
				var expected_foot := Vector2(x, 80.0 + row * height + baseline + rise)
				check(GardenLayout.cell_foot(layout_state, row, column).is_equal_approx(expected_foot), "level %s row %s column %s foot follows visible grid" % [level_id, row, column])
	var roof_state := session(41)
	for column in 9:
		for x_offset in [1.0, 79.0]:
			var x: float = 40.0 + column * 80.0 + float(x_offset)
			var edge := 70.0 + 85.0 + maxf(0, 440.0 - x) * .25
			check(GardenLayout.cell_at(roof_state, Vector2(x, edge - 1)) == Vector2i(column, 0), "roof upper edge stays in the row above across the tile")
			check(GardenLayout.cell_at(roof_state, Vector2(x, edge + 1)) == Vector2i(column, 1), "roof lower edge stays in the row below across the tile")
	var pot := {"kind": "flowerpot", "row": 0, "col": 0}
	var potted_plant := {"kind": "sunflower", "row": 0, "col": 0}
	check(is_equal_approx(GardenLayout.plant_anchor(roof_state, pot).y - GardenLayout.plant_anchor(roof_state, potted_plant).y, 12.0), "roof plant stands above the pot rim")
	for index in 10:
		var rect := GardenLayout.seed_rect(index)
		check(GardenLayout.seed_at(rect.get_center(), 10) == index, "seed %s selects the card drawn there" % index)
		check(GardenLayout.seed_at(Vector2(rect.end.x + 1, rect.get_center().y), 10) == -1, "seed %s gap does not select an adjacent card" % index)
		if index < 9:
			check(not rect.intersects(GardenLayout.seed_rect(index + 1)), "seed %s does not overlap its neighbor" % index)
	check(GardenLayout.seed_at(GardenLayout.seed_rect(6).get_center(), 6) == -1, "empty seed slots do not select a card")
	check(GardenLayout.seed_at(Vector2(85, 0), 10) == -1, "seed top border does not select a card")
	check(is_equal_approx(GardenLayout.point(state, 0, 0).x, 40.0), "day lawn starts at the first visible cell edge")
	check(state.mowers.all(func(mower): return is_equal_approx(GardenLayout.column_x(float(mower.x)), 20.0)), "mowers park in the path before the first plant")
	var old_parking: Dictionary = engine.snapshot(state)
	old_parking.mowers[0].x = 0.0
	old_parking.mowers[0].previousX = 0.0
	old_parking.mowers[1].state = "moving"
	old_parking.mowers[1].x = 3.0
	old_parking.mowers[1].previousX = 2.9
	var parking_restored: Dictionary = engine.restore(old_parking)
	check(not parking_restored.is_empty() and is_equal_approx(float(parking_restored.mowers[0].x), -.25), "ready mower restores to the path")
	check(not parking_restored.is_empty() and is_equal_approx(float(parking_restored.mowers[1].x), 3.0), "moving mower keeps its saved progress")
	var zombie: Dictionary = engine._spawn_zombie(state, "normal", 2)
	zombie.x = 6.0
	engine._damage_zombie(state, zombie, 100)
	check(not bool(zombie.hasArm) and bool(zombie.hasHead), "body below two thirds loses arm first")
	check(state.debris.size() == 1, "arm detaches once")
	engine._damage_zombie(state, zombie, 90)
	check(not bool(zombie.hasHead), "body below one third loses head")
	check(state.debris.size() == 2, "head detaches once")
	var restored: Dictionary = engine.restore(JSON.parse_string(JSON.stringify(engine.snapshot(state))))
	check(not restored.is_empty() and not bool(restored.zombies[0].hasHead), "headless state survives JSON snapshot")
	step(restored, .1)
	check(restored.debris.size() == 2, "restore does not duplicate detached parts")
	step(restored, 4)
	check(restored.zombies.is_empty(), "headless zombie falls without another hit")
	state = session()
	zombie = engine._spawn_zombie(state, "bucket", 2)
	engine._damage_zombie(state, zombie, 1000)
	check(float(zombie.armor) > 0 and is_equal_approx(float(zombie.health), float(zombie.maxHealth)), "helmet absorbs damage before body")
	engine._damage_zombie(state, zombie, 120)
	check(float(zombie.armor) <= 0 and bool(zombie.hasHead), "helmet detaches before head")
	state = session()
	state.sun = 1000
	check(bool(engine.plant(state, 2, 1, "peashooter").ok), "shooter plants normally")
	zombie = engine._spawn_zombie(state, "normal", 2)
	zombie.x = 5.0
	engine._fire(state, state.grid[19], "pea", 2)
	check(is_equal_approx(float(zombie.health), 270), "firing does not apply immediate damage")
	step(state, .1)
	check(is_equal_approx(float(zombie.health), 270), "projectile must travel to target")
	step(state, 1.0)
	check(float(zombie.health) < 270, "projectile collision applies damage")
	state = session(21)
	state.sun = 2000
	check(not bool(engine.plant(state, 2, 0, "peashooter").ok), "water rejects unsupported plant")
	check(bool(engine.plant(state, 2, 0, "lilypad").ok), "water accepts lily pad")
	check(bool(engine.plant(state, 2, 0, "peashooter").ok), "main plant stacks on lily pad")
	check(bool(engine.plant(state, 2, 0, "pumpkin").ok), "pumpkin stacks around main plant")
	check(str(state.bases[18].kind) == "lilypad" and str(state.grid[18].kind) == "peashooter" and str(state.shells[18].kind) == "pumpkin", "three independent plant layers retained")
	engine.shovel(state, 2, 0)
	check(state.shells[18].is_empty() and not state.grid[18].is_empty(), "shovel removes shell first")
	state = session()
	zombie = engine._spawn_zombie(state, "normal", 2)
	zombie.x = .1
	var distant: Dictionary = engine._spawn_zombie(state, "normal", 2)
	distant.x = 7
	step(state, .1)
	check(str(state.mowers[2].state) == "moving", "mower activates on invasion")
	check(float(distant.health) > 0, "mower does not instantly erase whole lane")
	step(state, 1.3)
	check(float(distant.health) <= 0, "moving mower sweeps distant zombie")
	check(int(state.usedMowers) == 1, "mower consumption is counted once")
	state = session(50)
	step(state, 1)
	check(str(state.phase) == "playing" and not state.boss.is_empty(), "boss level does not instantly win at zero regular waves")
	for level_id in range(1, 51):
		state = session(level_id)
		check(not state.activeRows.is_empty(), "level %s has playable lanes" % level_id)
		check(str(state.special) == str(content.garden.levels[str(level_id)].mode), "level %s preserves special mode" % level_id)
		step(state, .2)
		check(not engine.restore(engine.snapshot(state)).is_empty(), "level %s snapshot round trip" % level_id)
	for kind in content.garden_rules.playable:
		state = session(21 if kind in ["lilypad", "tanglekelp", "seashroom", "cattail"] else 11)
		state.sun = 10000
		var plant: Dictionary = engine._new_plant(state, str(kind), 2, 1)
		plant.awake = true
		state.grid[19] = plant
		var enemy: Dictionary = engine._spawn_zombie(state, "normal", 2)
		enemy.x = 5
		step(state, 2)
		check(not engine.restore(engine.snapshot(state)).is_empty(), "%s action state serializes" % kind)
	for kind in content.garden_rules.zombies:
		if kind == "boss":
			continue
		state = session(21 if kind in ["ducky", "dolphin", "snorkel"] else 4)
		state.sun = 1000
		engine.plant(state, 2, 3, "wallnut")
		var enemy: Dictionary = engine._spawn_zombie(state, str(kind), 2)
		enemy.x = 4
		step(state, 3)
		check(not engine.restore(engine.snapshot(state)).is_empty(), "%s action state serializes" % kind)
	check(engine.restore({"version": 2}).is_empty(), "corrupt snapshot falls back safely")
	state = session()
	state.projectiles = [{"bad": true}]
	check(engine.restore(state).is_empty(), "malformed projectile falls back safely")
	state = session()
	state.sun = 10000
	engine.plant(state, 2, 1, "hypnoshroom")
	state.grid[19].awake = true
	zombie = engine._spawn_zombie(state, "normal", 2)
	zombie.x = 1.7
	step(state, .4)
	check(bool(zombie.hypnotized), "eating awake hypno mushroom changes allegiance")
	state = session(31)
	state.sun = 10000
	engine.plant(state, 0, 0, "blover")
	zombie = engine._spawn_zombie(state, "balloon", 1)
	step(state, 1)
	check(float(zombie.health) <= 0 and float(state.fogCleared) > 0, "blover removes flying enemies and fog")
	state = session()
	state.sun = 10000
	engine.plant(state, 2, 1, "peashooter")
	engine.plant(state, 2, 1, "pumpkin")
	zombie = engine._spawn_zombie(state, "normal", 2)
	zombie.x = 1.7
	step(state, .4)
	check(float(state.shells[19].health) < float(state.shells[19].maxHealth) and is_equal_approx(float(state.grid[19].health), float(state.grid[19].maxHealth)), "pumpkin takes bites before protected plant")
	state = session()
	state.sun = 10000
	engine.plant(state, 2, 1, "umbrella")
	zombie = engine._spawn_zombie(state, "bungee", 2)
	zombie.x = 1.5
	step(state, .1)
	check(float(zombie.health) <= 0 and not state.grid[19].is_empty(), "umbrella blocks nearby bungee")
	state = session()
	zombie = engine._spawn_zombie(state, "gargantuar", 2)
	zombie.x = 7
	engine._damage_zombie(state, zombie, float(zombie.maxHealth) * .51, "test", true)
	step(state, 1.2)
	check(bool(zombie.thrown) and state.zombies.any(func(enemy): return str(enemy.kind) == "imp"), "damaged giant throws an actual imp")
	state = session(35)
	check(state.vases.size() == 15, "first vase stage uses the reference layout")
	check(state.vases.filter(func(vase): return str(vase.content.type) == "zombie").size() == 5, "vases preserve reference content counts")
	state = session()
	state.rngState = 42
	var duplicate: Dictionary = engine.snapshot(state)
	for index in 90:
		engine.tick(state, 1.0 / 30.0)
	for frame in 30:
		for fast_step in 3:
			engine.tick(duplicate, 1.0 / 30.0)
	check(JSON.stringify(engine.snapshot(state)) == JSON.stringify(engine.snapshot(duplicate)), "three times speed preserves the fixed-step result")
	state = session(1)
	check(state.mowers.all(func(mower): return str(mower.state) == "ready"), "all five mowers are visible on a one-lane level")
	state = session(5)
	step(state, 1.0)
	check(not state.packets.is_empty(), "bowling level supplies a packet")
	if not state.packets.is_empty():
		var bowling_kind := str(state.packets[0].kind)
		var bowling_result: Dictionary = engine.plant(state, 0, 1, bowling_kind)
		check(bool(bowling_result.ok) and state.rollers.size() == 1, "bowling places a rolling nut")
		zombie = engine._spawn_zombie(state, "normal", 0)
		zombie.x = 3.2
		step(state, 1.0)
		check(float(zombie.health) <= 0 or state.rollers.is_empty(), "rolling nut travels into a zombie")
	state = session(10)
	step(state, 6.0)
	check(not state.packets.is_empty(), "conveyor level supplies cards without sun")
	if not state.packets.is_empty():
		var before_sun := int(state.sun)
		var conveyor_result: Dictionary = engine.plant(state, 2, 1, str(state.packets[0].kind))
		check(bool(conveyor_result.ok) and int(state.sun) == before_sun, "conveyor planting is free")
	state = session(15)
	step(state, .1)
	check(str(state.special) == "whack", "whack level preserves its special mode")
	state = session(35)
	var vase_count: int = state.vases.size()
	if not state.vases.is_empty():
		var vase: Dictionary = state.vases[0]
		engine.handle_cell(state, int(vase.row), int(vase.col))
		check(state.vases.size() == vase_count - 1, "vase click consumes a vase")
	state = session(50)
	check(str(state.special) == "conveyor" and not state.boss.is_empty(), "boss level preserves conveyor and boss")
	check(float(state.boss.health) > 0, "boss starts with health")
	print("Garden fixtures: %s checks, %s failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
