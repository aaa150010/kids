extends Node

var failures: Array[String] = []
var checks := 0


func _ready() -> void:
	call_deferred("_run")


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)


func _run() -> void:
	var content = get_tree().root.get_node_or_null("ContentDB")
	check(content != null, "ContentDB autoload is available")
	if content == null:
		get_tree().quit(1)
		return
	var extracted_audio = load("res://assets/garden/pvz-audio/SFX/plant/cherrybomb.ogg.res")
	check(extracted_audio is AudioStream, "upstream imported OGG resource loads as AudioStream")
	var audio_map_file := FileAccess.open("res://pvz/data/kids_audio_map.json", FileAccess.READ)
	var audio_map: Dictionary = JSON.parse_string(audio_map_file.get_as_text()) if audio_map_file != null else {}
	if audio_map_file != null:
		audio_map_file.close()
	var mapped_audio_count := 0
	for group in audio_map:
		for key in audio_map[group]:
			for audio_path in audio_map[group][key]:
				mapped_audio_count += 1
				check(ResourceLoader.exists(str(audio_path)), "mapped PvZ audio exists: %s" % audio_path)
	check(mapped_audio_count >= 60, "upstream PCK audio map covers core music, plants, zombies and buttons")
	var built: Dictionary = PvZLevelFactory.build(1, "adventure", ["peashooter", "sunflower", "wallnut", "cherrybomb", "potatomine", "snowpea"], "normal")
	var level: ResourceLevelData = built.get("level")
	check(level != null, "level 1 resource is created")
	check(level.max_wave == 10, "short content levels are rounded to an upstream ten-wave flag block")
	check(level.game_BG == ConstLevelData.GameBg.FrontDay, "level 1 uses the day background")
	check(level.prechosen_cards.size() == 6, "selected seeds become upstream prechosen cards")
	var conveyor: ResourceLevelData = PvZLevelFactory.build(10, "adventure", [], "normal").get("level")
	check(conveyor.card_mode == ConstLevelData.E_CardMode.ConveyorBelt, "level 10 uses the upstream conveyor slot")
	check(not conveyor.conveyor_weights.is_empty(), "level 10 has upstream card weights")
	var vase: ResourceLevelData = PvZLevelFactory.build(35, "adventure", [], "normal").get("level")
	check(vase.is_pot_mode and vase.pot_mode == ConstLevelData.E_PotMode.Weight, "level 35 uses upstream weight pots")
	var boss: ResourceLevelData = PvZLevelFactory.build(50, "adventure", [], "normal").get("level")
	check(boss.has_boss() and boss.win_on_boss_death, "level 50 configures the upstream doctor boss")
	check(boss.game_sences == MainSceneRegistry.MainScenes.MainGameRoof, "level 50 embeds the rooftop scene")
	for level_number in range(1, 51):
		var mapped: Dictionary = PvZLevelFactory.build(level_number, "adventure", [], "normal")
		var mapped_level: ResourceLevelData = mapped.get("level")
		check(mapped_level != null, "level %s maps to an upstream resource" % level_number)
		check(mapped_level.max_wave >= 10 and mapped_level.max_wave % 10 == 0, "level %s uses complete upstream flag blocks" % level_number)
		check(not mapped_level.zombie_refresh_types.is_empty() or mapped_level.monster_mode != ConstLevelData.E_MonsterMode.Norm, "level %s has an upstream zombie pool" % level_number)
		check(str(mapped.get("scene", "")).begins_with("res://pvz/scenes/main/MainGame"), "level %s selects an upstream main scene" % level_number)
	for kind in PvZLevelFactory.PLANT_MAP:
		check(PvZLevelFactory.plant_type(str(kind)) != CharacterRegistry.PlantType.Null, "plant %s maps into the upstream registry" % kind)
	for kind in PvZLevelFactory.ZOMBIE_MAP:
		check(PvZLevelFactory.zombie_type(str(kind)) != CharacterRegistry.ZombieType.Null, "zombie %s maps into the upstream registry" % kind)

	var host := PvZBattleHost.new()
	add_child(host)
	var started := host.start({
		"levelId": 1,
		"mode": "adventure",
		"environment": "day",
		"seeds": ["peashooter", "sunflower", "wallnut", "cherrybomb", "potatomine", "snowpea"],
		"difficulty": "normal",
		"speed": 1,
	}, {})
	check(started, "embedded host accepts level 1")
	for index in 90:
		await get_tree().process_frame
	await get_tree().create_timer(3.4, true, false, true).timeout
	check(is_instance_valid(host.battle), "upstream main game root remains alive")
	if is_instance_valid(host.battle):
		check(host.battle.game_para == level or host.battle.game_para != null, "upstream main game receives its level resource")
		check(host.battle.main_game_progress != MainGameManager.E_MainGameProgress.NONE, "upstream progresses beyond its initial state")
		check(host.battle.card_manager.card_slot_battle != null, "upstream battle card slot is embedded")
		var slot_root: Control = host.battle.card_manager.card_slot_root
		var slot_battle: CardSlotBattle = host.battle.card_manager.card_slot_battle
		var candidate: CardSlotCandidate = host.battle.card_manager.card_slot_norm.card_slot_candidate
		print(
			"PVZ_LAYOUT root=", slot_root.get_global_rect(),
			" battle=", slot_battle.get_global_rect(),
			" battle_visible=", slot_battle.is_visible_in_tree(),
			" progress=", host.battle.main_game_progress,
			" battle_parent=", slot_battle.get_parent().get_path(),
			" container=", host.battle.card_manager.card_slot_container.get_global_rect(),
			" candidate=", candidate.get_global_rect(),
			" candidate_visible=", candidate.is_visible_in_tree(),
			" cards=", slot_battle.curr_cards.size(),
			" placeholders=", slot_battle.cards_placeholder.size()
		)
		check(slot_battle.size.x >= 500.0, "ten upstream card placeholders restore the seed bank width")
		check(candidate.is_visible_in_tree() == false, "native seed picker suppresses the second upstream chooser")
		var sunflower_card: Card = null
		for card in slot_battle.curr_cards:
			if card.card_reference != null and card.card_reference.content_id == CharacterRegistry.PlantType.P002SunFlower:
				sunflower_card = card
				break
		check(sunflower_card != null, "tutorial loadout contains the sunflower seed packet")
		var start_sun: int = slot_battle.sun_value
		if sunflower_card != null:
			EventBus.push_event("main_game_click_card", [sunflower_card])
			var target_cell: PlantCell = host.battle.plant_cell_manager.all_plant_cells[2][1]
			host.battle.hand_manager._on_cell_mouse_enter(target_cell)
			target_cell.click_cell.emit(target_cell)
			await get_tree().process_frame
			check(target_cell.get_curr_plant_num() == 1, "seed packet plants through the upstream hand manager")
			check(slot_battle.sun_value == start_sun - 50, "successful planting spends fifty sun")
		var live_zombie = host.battle.zombie_manager.zombie_wave_manager.zombie_wave_create_manager.wave_create_zombie(CharacterRegistry.ZombieType.Z001Norm, 2, 0)
		check(is_instance_valid(live_zombie), "upstream wave factory creates a live zombie")
		var preview_sun: Sun = SceneRegistry.SUN.instantiate()
		preview_sun.init_sun(25, Vector2(500, 120))
		host.battle.suns.add_child(preview_sun)
		await get_tree().process_frame
	var snapshot: Dictionary = host.snapshot_state()
	check(int(snapshot.get("levelId", 0)) == 1, "snapshot records the level")
	check(snapshot.has("plants") and snapshot.has("zombies") and snapshot.has("cards"), "snapshot captures live battle systems")
	host.cleanup()
	host.queue_free()
	await get_tree().process_frame
	var restored_host := PvZBattleHost.new()
	add_child(restored_host)
	restored_host.start({
		"levelId": 1,
		"mode": "tutorial",
		"environment": "day",
		"seeds": ["sunflower", "peashooter", "wallnut", "cherrybomb", "potatomine"],
		"difficulty": "normal",
		"speed": 1,
	}, snapshot)
	await get_tree().create_timer(2.4, true, false, true).timeout
	if is_instance_valid(restored_host.battle):
		var restored_cell: PlantCell = restored_host.battle.plant_cell_manager.all_plant_cells[2][1]
		check(restored_cell.get_curr_plant_num() == 1, "mid-battle plant survives a new host and snapshot restore")
		check(restored_host.battle.card_manager.card_slot_battle.sun_value == int(snapshot.get("cards", {}).get("sun", -1)), "mid-battle sun survives restore")
		check(restored_host.battle.zombie_manager.all_zombies_1d.size() >= 1, "mid-battle zombie survives restore")
		check(restored_host.battle.suns.get_child_count() >= 1, "uncollected sun survives restore")
	else:
		check(false, "restored host keeps the upstream main game alive")
	restored_host.cleanup()
	restored_host.queue_free()
	await get_tree().process_frame
	for special_level in [5, 10, 15, 35, 50]:
		var special_host := PvZBattleHost.new()
		add_child(special_host)
		var special_started := special_host.start({
			"levelId": special_level,
			"mode": "adventure",
			"seeds": ["peashooter", "sunflower", "wallnut", "cherrybomb", "potatomine", "snowpea"],
			"difficulty": "normal",
			"speed": 1,
		}, {})
		check(special_started, "special level %s boots in the embedded host" % special_level)
		await get_tree().create_timer(0.5, true, false, true).timeout
		check(is_instance_valid(special_host.battle), "special level %s keeps its main game root" % special_level)
		var special_snapshot: Dictionary = special_host.snapshot_state()
		if special_level == 35:
			check(special_host.battle.plant_cell_manager.curr_pot_num > 0, "vase level creates its upstream pot layout")
			check(not special_snapshot.get("pots", []).is_empty(), "vase snapshot captures unopened upstream pots")
		if special_level == 50:
			check(special_host.battle.game_para.has_boss(), "boss level exposes the upstream doctor to the main game")
		special_host.cleanup()
		special_host.queue_free()
		await get_tree().process_frame
		if special_level == 35:
			var vase_host := PvZBattleHost.new()
			add_child(vase_host)
			vase_host.start({
				"levelId": 35,
				"mode": "adventure",
				"seeds": [],
				"difficulty": "normal",
				"speed": 1,
			}, special_snapshot)
			await get_tree().create_timer(0.7, true, false, true).timeout
			check(is_instance_valid(vase_host.battle) and vase_host.battle.plant_cell_manager.curr_pot_num > 0, "vase pots survive snapshot restore")
			vase_host.cleanup()
			vase_host.queue_free()
			await get_tree().process_frame
	if failures.is_empty():
		print("PVZ_SMOKE_OK checks=%s" % checks)
		get_tree().quit(0)
	else:
		print("PVZ_SMOKE_FAILED checks=%s failures=%s" % [checks, failures])
		get_tree().quit(1)
