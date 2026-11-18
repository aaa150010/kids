class_name PvZBattleHost
extends Control

## 将 PVZ-Godot-Dream 的 1066×600 主战斗嵌进原生大厅。
## 上游仍拥有完整战斗架构；此节点只负责生命周期、速度、暂停、胜负和快照。

signal battle_ready
signal battle_finished(won: bool, summary: Dictionary)
signal autosave_due(note: String)

const VIEW_SIZE := Vector2i(1066, 600)
const CHECKPOINT_EVENTS := {
	"add_sun_value": true,
	"main_game_click_card": true,
	"main_game_click_shovel": true,
	"hm_character_clear_card": true,
	"create_tombstone": true,
	"main_game_progress_update": true,
	"create_trophy": true,
	"win_main_game": true,
	"zombie_go_home": true,
}

var level_id := 1
var mode := "adventure"
var environment := "day"
var selected_seeds: Array = []
var difficulty := "normal"
var speed := 1
var profile_id := ""
var battle: MainGameManager
var level: ResourceLevelData
var _viewport: SubViewport
var _display: TextureRect
var _view_scale := 1.0
var _view_offset := Vector2.ZERO
var _finished := false
var _loss_started := false
var _autosave_clock := 0.0
var _checkpoint_pending := false
var _event_callable: Callable
var _elapsed := 0.0
var _cleaned := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var backdrop := ColorRect.new()
	backdrop.color = Color("#172318")
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)
	_viewport = SubViewport.new()
	_viewport.size = VIEW_SIZE
	_viewport.disable_3d = true
	_viewport.transparent_bg = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.handle_input_locally = false
	_viewport.gui_disable_input = false
	add_child(_viewport)
	_display = TextureRect.new()
	_display.texture = _viewport.get_texture()
	_display.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_display.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_display.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_display.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_display)
	resized.connect(_update_view_metrics)
	_update_view_metrics()


func _update_view_metrics() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	_view_scale = minf(size.x / VIEW_SIZE.x, size.y / VIEW_SIZE.y)
	var draw_size := Vector2(VIEW_SIZE) * _view_scale
	_view_offset = (size - draw_size) * 0.5


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouse:
		var mouse_event := event as InputEventMouse
		var local := (mouse_event.position - _view_offset) / maxf(_view_scale, 0.001)
		if local.x < 0.0 or local.y < 0.0 or local.x > VIEW_SIZE.x or local.y > VIEW_SIZE.y:
			return
		var forwarded := mouse_event.duplicate() as InputEventMouse
		forwarded.position = local
		forwarded.global_position = local
		if forwarded is InputEventMouseButton and forwarded.pressed:
			# Android 轻触通常先到按下事件，补一次同坐标移动以触发布局格子的悬停判定。
			var hover := InputEventMouseMotion.new()
			hover.position = local
			hover.global_position = local
			hover.button_mask = MOUSE_BUTTON_MASK_LEFT
			_viewport.push_input(hover, true)
		_viewport.push_input(forwarded, true)
		accept_event()
	elif event is InputEventScreenTouch or event is InputEventScreenDrag:
		_viewport.push_input(event, false)
		accept_event()
	elif event is InputEventKey:
		_viewport.push_input(event, false)
		accept_event()


func start(context: Dictionary, resume: Dictionary = {}) -> bool:
	level_id = int(context.get("levelId", 1))
	mode = str(context.get("mode", "adventure"))
	environment = str(context.get("environment", "day"))
	selected_seeds = context.get("seeds", []).duplicate()
	difficulty = str(context.get("difficulty", "normal"))
	speed = clampi(int(context.get("speed", 1)), 1, 3)
	profile_id = str(context.get("profileId", ""))
	# 上游在轮末仍会写自己的 .tres；用儿童 ID 隔离，主存档仍只走 SaveStore。
	Global.user_manager.curr_user_name = "kid_" + profile_id.validate_filename() if not profile_id.is_empty() else "local_kid"
	var built := PvZLevelFactory.build(level_id, mode, selected_seeds, difficulty)
	environment = str(built.get("environment", environment))
	level = built.get("level") as ResourceLevelData
	if level == null:
		push_error("PvZBattleHost：关卡资源创建失败")
		return false
	if not resume.is_empty():
		_apply_resume_data(level, resume)
	Global.game_para = level
	var allowed: Array[CharacterRegistry.PlantType] = []
	var configured: Array = ContentDB.garden_levels().get(str(level_id), {}).get("allowedPlants", [])
	if mode == "endless" or mode == "tutorial":
		configured = ContentDB.garden_rules.get("playable", [])
	for kind in configured:
		var id := PvZLevelFactory.plant_type(str(kind))
		if id != CharacterRegistry.PlantType.Null and not (id in allowed):
			allowed.append(id)
	Global.global_game_state.curr_plant = allowed
	var scene := load(str(built.get("scene", "res://pvz/scenes/main/MainGame01Front.tscn"))) as PackedScene
	if scene == null:
		push_error("PvZBattleHost：主战斗场景加载失败")
		return false
	var instance := scene.instantiate()
	battle = instance as MainGameManager
	if battle == null:
		instance.queue_free()
		push_error("PvZBattleHost：主战斗根节点类型不匹配")
		return false
	battle.set_meta("kids_battle_host", self)
	battle.process_mode = Node.PROCESS_MODE_INHERIT
	_viewport.add_child(battle)
	_event_callable = _on_event_pushed
	if not EventBus.event_pushed.is_connected(_event_callable):
		EventBus.event_pushed.connect(_event_callable)
	AudioFX.stop_music()
	AudioFX.stop_all()
	_set_speed_tree(speed)
	var menu_button := battle.get_node_or_null("%MainGameMenuButton") as CanvasItem
	if menu_button != null:
		menu_button.hide()
	var slot_root := battle.get_node_or_null("%CardSlotRoot") as Control
	if slot_root != null:
		# 上游场景的卡槽根控件依赖完整视口尺寸；嵌入 SubViewport 时显式铺满。
		slot_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		# 上游把阳光数字画在卡槽左侧 101px，根节点保留 150px 左边距才能落在种子槽内。
		slot_root.offset_left = 150.0
	var candidate := battle.card_manager.card_slot_norm.card_slot_candidate if battle.card_manager.card_slot_norm != null else null
	if candidate != null:
		# 关卡卡组已由原生选卡页确定，不再显示上游第二套候选卡槽。
		candidate.hide()
	call_deferred("_finish_ready", resume)
	return true


func _finish_ready(resume: Dictionary) -> void:
	if not is_instance_valid(battle) or battle.is_queued_for_deletion():
		return
	if not resume.is_empty():
		_restore_live_state(resume)
	AudioFX.stop_music()
	AudioFX.stop_all()
	battle_ready.emit()


func set_paused(value: bool) -> void:
	if not is_instance_valid(battle):
		return
	battle.process_mode = Node.PROCESS_MODE_DISABLED if value else Node.PROCESS_MODE_INHERIT
	if value:
		SoundManager.stop_all_audio()
		AudioFX.stop_all()
	else:
		SoundManager.resume_bgm()
		battle.refresh_battle_bgm()


func set_speed(value: int) -> void:
	speed = clampi(value, 1, 3)
	_set_speed_tree(speed)
	autosave_due.emit("切换倍速")


func trigger_tutorial_mower(lane: int = 2) -> void:
	if not is_instance_valid(battle) or not is_instance_valid(battle.game_item_manager):
		return
	var movers := battle.game_item_manager.gim_lawn_mover.all_lawn_movers
	if lane < 0 or lane >= movers.size():
		return
	var mover = movers[lane]
	if is_instance_valid(mover) and not mover.is_moving and not mover.is_destroyed:
		mover.call("_start_mower")


func _set_speed_tree(value: int) -> void:
	Global.time_scale = float(value)
	Engine.time_scale = float(value)


func _process(delta: float) -> void:
	if _finished or not is_instance_valid(battle):
		return
	_elapsed += delta
	_autosave_clock += delta
	if _autosave_clock >= 2.0:
		_autosave_clock = 0.0
		autosave_due.emit("战斗中")


func _on_event_pushed(event_name: String, payload: Array) -> void:
	if CHECKPOINT_EVENTS.has(event_name) and not _finished:
		_queue_checkpoint()
	if event_name == "win_main_game" and not _finished:
		call_deferred("_complete", true)
	elif event_name == "zombie_go_home" and not _loss_started:
		_loss_started = true
		call_deferred("_complete_loss_after_animation")


func _queue_checkpoint() -> void:
	if _checkpoint_pending:
		return
	_checkpoint_pending = true
	call_deferred("_emit_checkpoint")


func _emit_checkpoint() -> void:
	_checkpoint_pending = false
	if not _finished:
		autosave_due.emit("战斗操作")


func _complete_loss_after_animation() -> void:
	var timer := get_tree().create_timer(3.2, true, false, true)
	await timer.timeout
	if _finished:
		return
	TreePauseManager.end_tree_pause_clear_all_pause_factors()
	_complete(false)


func notify_main_game_won() -> void:
	_complete(true)


func _complete(won: bool) -> void:
	if _finished:
		return
	_finished = true
	var summary := _summary(won)
	TreePauseManager.end_tree_pause_clear_all_pause_factors()
	_set_speed_tree(1)
	battle_finished.emit(won, summary)


func _summary(won: bool) -> Dictionary:
	var wave := 0
	var total := 0
	if is_instance_valid(battle) and is_instance_valid(battle.zombie_manager):
		var manager := battle.zombie_manager.zombie_wave_manager
		if is_instance_valid(manager):
			wave = maxi(0, manager.curr_wave + 1)
			total = maxi(1, manager.max_wave)
	var flags := maxi(0, wave / 10)
	var stars := 3 if won and total <= 10 else 2 if won else 0
	if won and mode == "endless":
		stars = clampi(wave / 10, 1, 3)
	return {
		"levelId": level_id,
		"mode": mode,
		"environment": environment,
		"wave": wave,
		"waveCount": total,
		"flags": flags,
		"stars": stars,
		"elapsed": _elapsed,
	}


func snapshot_state() -> Dictionary:
	var result := {
		"schemaVersion": 1,
		"levelId": level_id,
		"mode": mode,
		"environment": environment,
		"selectedSeeds": selected_seeds.duplicate(),
		"difficulty": difficulty,
		"speed": speed,
		"savedAt": Time.get_unix_time_from_system(),
	}
	if not is_instance_valid(battle) or battle.is_queued_for_deletion():
		return result
	result["round"] = battle.curr_game_round
	result["progress"] = int(battle.main_game_progress)
	result["plants"] = _snapshot_plants()
	result["tombstones"] = _snapshot_tombstones()
	result["zombies"] = _snapshot_zombies()
	result["suns"] = _snapshot_suns()
	result["mowers"] = _snapshot_mowers()
	result["bosses"] = _snapshot_bosses()
	result["cards"] = _snapshot_cards()
	result["pots"] = _snapshot_pots()
	if is_instance_valid(battle.zombie_manager) and is_instance_valid(battle.zombie_manager.zombie_wave_manager):
		var waves := battle.zombie_manager.zombie_wave_manager
		result["wave"] = waves.curr_wave
		result["maxWave"] = waves.max_wave
		result["waveMax"] = waves.max_wave_one_round
	if is_instance_valid(battle.day_suns_manager):
		result["daySunSum"] = battle.day_suns_manager.curr_sun_sum_value
	return result


func _snapshot_plants() -> Array:
	var result: Array = []
	if not is_instance_valid(battle) or not is_instance_valid(battle.plant_cell_manager):
		return result
	var data := battle.plant_cell_manager.get_save_game_data_plant_cell_manager()
	for cell in data.all_plant_cells_datas:
		var plants: Array = []
		for place in cell.plant_type_in_cell:
			var plant_data: Dictionary = cell.plant_type_in_cell[place]
			plants.append({
				"place": int(place),
				"data": _plain_value(plant_data),
			})
		result.append({
			"row": cell.row_col.x,
			"col": cell.row_col.y,
			"ladder": cell.is_ladder,
			"plants": plants,
		})
	return result


func _snapshot_tombstones() -> Dictionary:
	if not is_instance_valid(battle) or not is_instance_valid(battle.plant_cell_manager):
		return {}
	return battle.plant_cell_manager.tomb_stone_manager.get_save_game_data_tomb_stone_manager()


func _snapshot_mowers() -> Dictionary:
	if not is_instance_valid(battle) or not is_instance_valid(battle.game_item_manager):
		return {}
	return battle.game_item_manager.gim_lawn_mover.get_save_game_data_lawn_mover_manager()


func _snapshot_bosses() -> Dictionary:
	if not is_instance_valid(battle) or not is_instance_valid(battle.zombie_manager):
		return {}
	return battle.zombie_manager.get_save_game_data_bosses()


func _snapshot_cards() -> Dictionary:
	var result := {"cards": []}
	if not is_instance_valid(battle) or not is_instance_valid(battle.card_manager):
		return result
	var slot := battle.card_manager.card_slot_battle
	if slot == null or not is_instance_valid(slot):
		return result
	result["sun"] = slot.sun_value
	for card in slot.curr_cards:
		if not is_instance_valid(card):
			continue
		result["cards"].append({
			"contentId": card.card_reference.content_id if card.card_reference != null else 0,
			"cooling": card._is_cooling,
			"remaining": card._cool_timer,
		})
	return result


func _snapshot_zombies() -> Array:
	var result: Array = []
	if not is_instance_valid(battle) or not is_instance_valid(battle.zombie_manager):
		return result
	for zombie in battle.zombie_manager.all_zombies_1d:
		if not is_instance_valid(zombie) or zombie.is_queued_for_deletion() or zombie.is_death:
			continue
		var hp := zombie.hp_component
		result.append({
			"type": int(zombie.zombie_type),
			"lane": zombie.lane,
			"x": zombie.global_position.x,
			"y": zombie.global_position.y,
			"hp": hp.curr_hp,
			"armor1": hp.curr_hp_armor1 if hp is HpComponentZombie else 0,
			"armor2": hp.curr_hp_armor2 if hp is HpComponentZombie else 0,
			"hypno": zombie.is_hypno,
			"wave": zombie.curr_wave,
			"mini": zombie.is_mini_zombie,
		})
	return result


func _snapshot_pots() -> Array:
	var result: Array = []
	if not is_instance_valid(battle) or not is_instance_valid(battle.plant_cell_manager):
		return result
	for row in battle.plant_cell_manager.all_plant_cells:
		for cell in row:
			if not cell is PlantCell or not is_instance_valid(cell.pot) or cell.pot.is_open:
				continue
			result.append({
				"row": cell.row_col.x,
				"col": cell.row_col.y,
				"type": int(cell.pot.pot_type),
				"fixed": cell.pot.is_fixed_res,
				"plant": int(cell.pot.curr_plant_type),
				"zombie": int(cell.pot.curr_zombie_type),
			})
	return result


func _snapshot_suns() -> Array:
	var result: Array = []
	if not is_instance_valid(battle) or not is_instance_valid(battle.suns):
		return result
	for node in battle.suns.get_children():
		if node is Sun and is_instance_valid(node) and not node.collected:
			result.append({
				"value": node.sun_value,
				"x": node.global_position.x,
				"y": node.global_position.y,
			})
	return result


func _plain_value(value: Variant) -> Variant:
	if value is Dictionary:
		var result := {}
		for key in value:
			result[str(key)] = _plain_value(value[key])
		return result
	if value is Array:
		var result: Array = []
		for entry in value:
			result.append(_plain_value(entry))
		return result
	if value is Vector2i:
		return {"x": value.x, "y": value.y}
	if value is Vector2:
		return {"x": value.x, "y": value.y}
	return value


func _apply_resume_data(target_level: ResourceLevelData, resume: Dictionary) -> void:
	var saved := ResourceSaveGameMainGame.new()
	saved.curr_game_round = clampi(int(resume.get("round", 1)), 1, 999)
	saved.curr_wave = int(resume.get("wave", -1))
	saved.curr_max_wave = int(resume.get("maxWave", target_level.max_wave))
	saved.day_sun_curr_sun_sum_value = int(resume.get("daySunSum", 0))
	saved.card_manager_data = {"curr_sun_value": int(resume.get("cards", {}).get("sun", target_level.start_sun))}
	saved.lawn_mover_manager_data = resume.get("mowers", {})
	saved.boss_manager_data = resume.get("bosses", {})
	var plant_manager := ResourceSaveGamePlantCellManager.new()
	var cells: Array[ResourceSaveGamePlantCell] = []
	for entry in resume.get("plants", []):
		if not entry is Dictionary:
			continue
		var cell := ResourceSaveGamePlantCell.new()
		cell.row_col = Vector2i(int(entry.get("row", 0)), int(entry.get("col", 0)))
		cell.is_ladder = bool(entry.get("ladder", false))
		for plant in entry.get("plants", []):
			if not plant is Dictionary:
				continue
			var plant_data: Dictionary = plant.get("data", {})
			cell.plant_type_in_cell[int(plant.get("place", 0))] = plant_data
		cells.append(cell)
	plant_manager.all_plant_cells_datas = cells
	plant_manager.tomb_stone_manager_data = resume.get("tombstones", {})
	saved.plant_cell_manager_data = plant_manager
	target_level.save_game_data_main_game = saved
	target_level.ori_data_on_save_data_update = {"kids_mid_battle": true}


func _restore_live_state(resume: Dictionary) -> void:
	# 波次、卡槽、植物、墓碑、小推车和僵王已由上游读档恢复；这里补齐场上单位与冷却。
	_restore_cards(resume.get("cards", {}))
	_restore_pots(resume.get("pots", []))
	_restore_suns(resume.get("suns", []))
	_restore_zombies(resume.get("zombies", []))


func _restore_cards(data: Dictionary) -> void:
	if not is_instance_valid(battle) or battle.card_manager.card_slot_battle == null:
		return
	var slot := battle.card_manager.card_slot_battle
	var saved_cards: Array = data.get("cards", [])
	for index in mini(saved_cards.size(), slot.curr_cards.size()):
		var card := slot.curr_cards[index]
		var entry: Dictionary = saved_cards[index]
		if bool(entry.get("cooling", false)):
			card.card_change_cool_time(float(entry.get("remaining", 0.0)))
			card.card_cool()


func _restore_pots(data: Array) -> void:
	if not is_instance_valid(battle) or not is_instance_valid(battle.plant_cell_manager):
		return
	var rows: Array = battle.plant_cell_manager.all_plant_cells
	for entry in data:
		if not entry is Dictionary:
			continue
		var row := int(entry.get("row", -1))
		var col := int(entry.get("col", -1))
		if row < 0 or col < 0 or row >= rows.size() or col >= rows[row].size():
			continue
		var cell: PlantCell = rows[row][col]
		var plant_id := int(entry.get("plant", CharacterRegistry.PlantType.Null))
		var zombie_id := int(entry.get("zombie", CharacterRegistry.ZombieType.Null))
		if plant_id == CharacterRegistry.PlantType.Null and zombie_id == CharacterRegistry.ZombieType.Null:
			continue
		var pot_para := {
			ScaryPot.E_PotInitParaAttr.PotType: int(entry.get("type", ScaryPot.E_PotType.Random)),
			ScaryPot.E_PotInitParaAttr.IsFixedRes: bool(entry.get("fixed", false)),
			ScaryPot.E_PotInitParaAttr.PlantCell: cell,
			ScaryPot.E_PotInitParaAttr.IsCanLookRandom: false,
		}
		if plant_id != CharacterRegistry.PlantType.Null:
			pot_para[ScaryPot.E_PotInitParaAttr.PlantType] = plant_id
		if zombie_id != CharacterRegistry.ZombieType.Null:
			pot_para[ScaryPot.E_PotInitParaAttr.ZombieType] = zombie_id
		battle.plant_cell_manager.plant_cell_creat_pot(cell, pot_para)


func _restore_suns(data: Array) -> void:
	if not is_instance_valid(battle) or not is_instance_valid(battle.suns):
		return
	for entry in data:
		if not entry is Dictionary:
			continue
		var sun: Sun = SceneRegistry.SUN.instantiate()
		sun.init_sun(int(entry.get("value", 25)), Vector2(float(entry.get("x", 0)), float(entry.get("y", 0))))
		battle.suns.add_child(sun)


func _restore_zombies(data: Array) -> void:
	if not is_instance_valid(battle) or not is_instance_valid(battle.zombie_manager):
		return
	for entry in data:
		if not entry is Dictionary:
			continue
		var lane := int(entry.get("lane", -1))
		var zombie_type := int(entry.get("type", CharacterRegistry.ZombieType.Null)) as CharacterRegistry.ZombieType
		if lane < 0 or lane >= battle.zombie_manager.all_zombie_rows.size() or zombie_type == CharacterRegistry.ZombieType.Null:
			continue
		var init_para := {
			Zombie000Base.E_ZInitAttr.CharacterInitType: Character000Base.E_CharacterInitType.IsNorm,
			Zombie000Base.E_ZInitAttr.Lane: lane,
			Zombie000Base.E_ZInitAttr.CurrWave: int(entry.get("wave", -1)),
			Zombie000Base.E_ZInitAttr.IsMiniZombie: bool(entry.get("mini", false)),
		}
		var zombie := battle.zombie_manager.create_norm_zombie(
			zombie_type,
			battle.zombie_manager.all_zombie_rows[lane],
			init_para,
			Vector2(float(entry.get("x", 0)), float(entry.get("y", 0)))
		)
		if not is_instance_valid(zombie):
			continue
		if zombie.hp_component is HpComponentZombie:
			var hp := zombie.hp_component as HpComponentZombie
			hp.curr_hp = int(entry.get("hp", hp.curr_hp))
			hp.curr_hp_armor1 = int(entry.get("armor1", hp.curr_hp_armor1))
			hp.curr_hp_armor2 = int(entry.get("armor2", hp.curr_hp_armor2))
		else:
			zombie.hp_component.curr_hp = int(entry.get("hp", zombie.hp_component.curr_hp))
		if bool(entry.get("hypno", false)) and not zombie.is_hypno:
			zombie.signal_character_be_hypno.emit()


func cleanup() -> void:
	if _cleaned:
		return
	_cleaned = true
	if _event_callable.is_valid() and EventBus.event_pushed.is_connected(_event_callable):
		EventBus.event_pushed.disconnect(_event_callable)
	TreePauseManager.end_tree_pause_clear_all_pause_factors()
	_set_speed_tree(1)
	Global.game_para = null
	Global.main_game = null
	Global.user_manager.curr_user_name = ""
	if is_instance_valid(SoundManager) and SoundManager.has_method("stop_all_audio"):
		SoundManager.call("stop_all_audio")
	if is_instance_valid(battle):
		battle.queue_free()
	if is_instance_valid(_viewport):
		_viewport.queue_free()


func _exit_tree() -> void:
	cleanup()
