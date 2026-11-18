class_name NativeGardenGame
extends NativeGameScreen

const TUTORIAL_TEXT := [
	"点一下发光的阳光，把它收进口袋。",
	"选向日葵卡片，再点一块空草坪。",
	"种一株豌豆射手，守住中间的路。",
	"点铲子，再点向日葵，把它铲掉。",
	"种一株坚果墙，让僵尸先啃它。",
	"按下面的按钮，让割草机启动一次。",
	"点上方暂停按钮，试试让战斗停下来。",
	"点倍速按钮，把速度切换到 2×。",
	"花园小课堂完成啦，可以去闯关了！",
]
const PLAYABLE_PLANTS := [
	"peashooter", "sunflower", "cherrybomb", "wallnut", "potatomine", "snowpea",
	"chomper", "repeater", "puffshroom", "sunshroom", "fumeshroom", "gravebuster",
	"hypnoshroom", "scaredyshroom", "iceshroom", "doomshroom", "lilypad", "squash",
	"threepeater", "tanglekelp", "jalapeno", "spikeweed", "torchwood", "tallnut",
	"seashroom", "plantern", "cactus", "blover", "splitpea", "starfruit", "pumpkin",
	"magnetshroom", "cabbagepult", "flowerpot", "kernelpult", "coffeebean", "garlic",
	"umbrella", "marigold", "melonpult", "gatlingpea", "twinsunflower", "gloomshroom",
	"cattail", "wintermelon", "goldmagnet", "spikerock", "cobcannon",
]

var profile_data: Dictionary = {}
var view := "home"
var battle: Dictionary = {}
var battle_host: PvZBattleHost
var pending_pvz_resume: Dictionary = {}
var speed := 1
var selected_level := 1
var selected_mode := "adventure"
var selected_seeds: Array = []
var plant_entries: Dictionary = {}
var zombie_entries: Dictionary = {}
var seed_pick_buttons: Dictionary = {}
var seed_loadout_buttons: Array = []
var seed_flight_lock := false
var seed_flight_generation := 0
var tutorial_label: Label
var tutorial_banner: Control
var speed_button: Button
var _tutorial_event_callable: Callable
var reported_battle := false
var selected_difficulty := "auto"


func _ready() -> void:
	build_shell()
	_load_entries()
	profile_data = SaveStore.load_state(game_id, [str(players[0].id)])
	selected_level = clampi(_integer(profile_data.get("selectedLevel", 1)), 1, 50)
	selected_mode = str(profile_data.get("selectedMode", "adventure"))
	var saved_seeds: Variant = profile_data.get("selectedSeeds", [])
	selected_seeds = []
	if saved_seeds is Array:
		for kind in saved_seeds:
			if kind is String and ContentDB.garden_plants().has(kind) and not (kind in selected_seeds):
				selected_seeds.append(kind)
	if profile_data.is_empty():
		profile_data = {
			"schemaVersion": 1,
			"stars": {},
			"tutorialSeen": false,
			"bestEndless": 0,
			"battle": {},
			"difficulty": "auto",
			"autoCollectSun": int(players[0].age) <= 6,
			"reported": false,
		}
	selected_difficulty = difficulty_pref if GameTuning.supports(game_id) else "auto"
	pause_changed.connect(_on_pause_changed)
	var resume: Variant = profile_data.get("pvzBattle", {})
	if resume is Dictionary and not resume.is_empty():
		pending_pvz_resume = resume.duplicate(true)
		selected_level = clampi(_integer(pending_pvz_resume.get("levelId", selected_level)), 1, 50)
		selected_mode = str(pending_pvz_resume.get("mode", selected_mode))
		var restored_seeds: Variant = pending_pvz_resume.get("selectedSeeds", selected_seeds)
		if restored_seeds is Array:
			selected_seeds = restored_seeds.filter(func(kind): return kind is String and ContentDB.garden_plants().has(str(kind))).slice(0, 10)
		speed = clampi(_integer(pending_pvz_resume.get("speed", 1)), 1, 3)
		battle = {
			"levelId": selected_level,
			"mode": selected_mode,
			"phase": "playing",
			"reference": true,
		}
		view = "battle"
		_render_battle()
		return
	if profile_data.get("battle") is Dictionary and not profile_data.battle.is_empty():
		# 旧原生引擎的局内快照无法无损映射到上游角色实例；保留关卡与卡组并从本关开局继续。
		var legacy: Dictionary = profile_data.battle
		selected_level = clampi(_integer(legacy.get("levelId", 1)), 1, 50)
		selected_mode = str(legacy.get("mode", "adventure"))
		var legacy_seeds: Variant = legacy.get("seeds", selected_seeds)
		if legacy_seeds is Array:
			selected_seeds = legacy_seeds.filter(func(kind): return kind is String and ContentDB.garden_plants().has(str(kind))).slice(0, 10)
		profile_data.battle = {}
		_begin_battle(false)
	elif not bool(profile_data.get("tutorialSeen", false)):
		_begin_battle(true)
	elif str(profile_data.get("view", "home")) == "choose" and not selected_seeds.is_empty():
		_render_seed_picker()
	else:
		_render_home()
	call_deferred("_start_garden_music")


func _load_entries() -> void:
	for entry in ContentDB.garden.get("plantAlmanac", []):
		plant_entries[str(entry.id)] = entry
	for entry in ContentDB.garden.get("zombieAlmanac", []):
		zombie_entries[str(entry.id)] = entry


func _process(delta: float) -> void:
	if battle_host != null:
		return


func _notification(what: int) -> void:
	if OS.get_environment("KIDS_PLAYGROUND_AUDIT") == "1":
		return
	if not is_inside_tree():
		return
	if what in [NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_CLOSE_REQUEST]:
		if view == "battle" and not battle.is_empty():
			if not paused and is_instance_valid(overlay_root):
				toggle_pause(true)
			_save_profile("切到后台暂停")
			SaveStore.flush()
		AudioFX.stop_all()

func _render_home() -> void:
	view = "home"
	if is_instance_valid(speed_button):
		speed_button.visible = false
	PlaygroundUI.clear(content_root)
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 16)
	var hero := GardenSurfaces.panel(Color("#e5f2d8"), 30, Color("#8eb878"), 2)
	hero.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var hero_column := VBoxContainer.new()
	hero_column.add_theme_constant_override("separation", 12)
	hero.add_child(hero_column)
	var cover := TextureRect.new()
	cover.texture = load("res://assets/garden/runtime/original/menu.webp")
	cover.custom_minimum_size.y = 360
	cover.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	cover.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	hero_column.add_child(cover)
	hero_column.add_child(PlaygroundUI.label("🌻 植物大战僵尸 · 本地完整版", 34, PlaygroundUI.INK, 700))
	hero_column.add_child(PlaygroundUI.label("48 种植物从第一次进入起全部可用。收集阳光、选择卡片、种下防线，守住小房子。", 17, PlaygroundUI.INK_SOFT, 500, true))
	var tags := HFlowContainer.new()
	tags.add_theme_constant_override("h_separation", 7)
	for text in ["☀️ 阳光经济", "🌱 48 种植物", "🧟 28 种僵尸", "⏸ 暂停", "⏩ 1× / 2× / 3×", "💾 实时自动保存"]:
		tags.add_child(PlaygroundUI.chip(text, accent))
	hero_column.add_child(tags)
	var actions := HFlowContainer.new()
	actions.add_theme_constant_override("h_separation", 10)
	actions.add_theme_constant_override("v_separation", 10)
	actions.add_child(GardenSurfaces.button("🏡 冒险关卡", accent, func(): view = "levels"; _render_levels()))
	actions.add_child(GardenSurfaces.button("♾️ 无尽模式", Color("#6b5ca5"), _start_endless, "soft"))
	actions.add_child(GardenSurfaces.button("📖 植物与僵尸图鉴", Color("#8d6b24"), func(): view = "almanac"; _render_almanac("plants"), "soft"))
	actions.add_child(GardenSurfaces.button("🎓 花园小课堂", Color("#2878c8"), _start_tutorial, "soft"))
	if not battle.is_empty() and battle.get("phase") == "playing":
		actions.add_child(GardenSurfaces.button("▶ 继续上次战斗", Color("#d26d31"), func(): view = "battle"; _render_battle()))
	hero_column.add_child(actions)
	row.add_child(hero)
	var side := VBoxContainer.new()
	side.custom_minimum_size.x = 330
	side.add_theme_constant_override("separation", 12)
	side.add_child(_progress_card())
	side.add_child(_tutorial_card())
	side.add_child(_almanac_preview())
	row.add_child(side)
	content_root.add_child(row)


func _progress_card() -> Control:
	var stars_total := 0
	var stars_data: Dictionary = profile_data.get("stars", {})
	for value in stars_data.values():
		stars_total += int(value)
	var cleared: int = stars_data.size()
	var panel := GardenSurfaces.panel(Color(1, 1, 1, 0.78), 24, PlaygroundUI.mix(accent, Color.WHITE, 0.52), 1)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 7)
	panel.add_child(column)
	column.add_child(PlaygroundUI.label("🏡 花园进度", 23, accent, 700))
	column.add_child(PlaygroundUI.label("已通关 %s / 50 关" % cleared, 17, PlaygroundUI.INK, 700))
	column.add_child(PlaygroundUI.label("⭐ 累计 %s 颗星" % stars_total, 15, PlaygroundUI.INK_SOFT, 500))
	column.add_child(PlaygroundUI.label("无尽最好成绩：%s 面旗" % int(profile_data.get("bestEndless", 0)), 15, PlaygroundUI.INK_SOFT, 500))
	column.add_child(PlaygroundUI.separator())
	column.add_child(PlaygroundUI.label("✓ 所有植物已解锁\n✓ 不需要金币购买\n✓ 关卡按顺序开放", 14, PlaygroundUI.INK_SOFT, 500, true))
	column.add_child(PlaygroundUI.label("难度：%s" % _difficulty_name(selected_difficulty), 14, accent, 700))
	return panel


func _tutorial_card() -> Control:
	var panel := GardenSurfaces.panel(PlaygroundUI.mix(Color("#2878c8"), Color.WHITE, 0.88), 24, Color("#8fbce8"), 1)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)
	column.add_child(PlaygroundUI.label("🎓 第一次来花园？", 21, Color("#1d609b"), 700))
	column.add_child(PlaygroundUI.label("跟着小课堂收集阳光、种植物、铲除植物、触发割草机，并试一次暂停和倍速。", 14, PlaygroundUI.INK_SOFT, 500, true))
	column.add_child(PlaygroundUI.label("✓ 已经完成" if bool(profile_data.get("tutorialSeen", false)) else "还没有完成", 13, Color("#1d609b"), 700))
	return panel


func _almanac_preview() -> Control:
	var panel := GardenSurfaces.panel(Color("#fff8de"), 24, Color("#ddc674"), 1)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	for emoji in ["🌻", "🌱", "🍒", "🌰", "🌊", "🧟"]:
		row.add_child(PlaygroundUI.label(emoji, 27, PlaygroundUI.INK, 700))
	panel.add_child(row)
	return panel


func _render_levels() -> void:
	view = "levels"
	if is_instance_valid(speed_button):
		speed_button.visible = false
	PlaygroundUI.clear(content_root)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 10)
	outer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_root.add_child(outer)
	var toolbar := HBoxContainer.new()
	toolbar.add_child(GardenSurfaces.button("← 花园首页", accent, func(): _render_home(), "ghost"))
	toolbar.add_child(PlaygroundUI.label("冒险关卡 · 五座花园", 26, PlaygroundUI.INK, 700))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar.add_child(spacer)
	toolbar.add_child(GardenSurfaces.button("🏡 目前全部植物都可使用", accent, func(): view = "almanac"; _render_almanac("plants"), "soft"))
	outer.add_child(toolbar)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 12)
	scroll.add_child(list)
	var worlds := [
		{"start": 1, "name": "白天花园", "icon": "🌞", "desc": "阳光充足，学习基础防线"},
		{"start": 11, "name": "夜晚花园", "icon": "🌙", "desc": "没有天降阳光，蘑菇登场"},
		{"start": 21, "name": "泳池", "icon": "🌊", "desc": "六条战线，中间是水路"},
		{"start": 31, "name": "浓雾", "icon": "🌫️", "desc": "雾里防矿工、气球和玩偶匣"},
		{"start": 41, "name": "屋顶", "icon": "🏠", "desc": "坡面弹道与屋顶清洁车"},
	]
	for world in worlds:
		var section := GardenSurfaces.panel(PlaygroundUI.mix(accent, Color.WHITE, 0.92), 22, PlaygroundUI.mix(accent, Color.WHITE, 0.55), 1)
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", 9)
		section.add_child(column)
		column.add_child(PlaygroundUI.label("%s %s · %s" % [world.icon, world.name, world.desc], 21, PlaygroundUI.INK, 700))
		var grid := HBoxContainer.new()
		grid.add_theme_constant_override("separation", 7)
		for offset in 10:
			var level_id := int(world.start) + offset
			var stars := int(profile_data.get("stars", {}).get(str(level_id), 0))
			var unlocked := level_id == 1 or int(profile_data.get("stars", {}).get(str(level_id - 1), 0)) > 0
			var label := "%s\n%s" % [level_id, "★".repeat(stars) if stars > 0 else ("预约" if unlocked else "🔒")]
			var button := GardenSurfaces.button(label, accent if unlocked else Color("#a9a294"), _choose_level.bind(level_id), "soft" if unlocked else "ghost")
			button.custom_minimum_size = Vector2(93, 72)
			button.add_theme_font_size_override("font_size", 16)
			button.disabled = not unlocked
			grid.add_child(button)
		column.add_child(grid)
		list.add_child(section)


func _choose_level(level_id: int) -> void:
	selected_level = level_id
	selected_mode = "adventure"
	var allowed: Array = ContentDB.garden_levels().get(str(level_id), {}).get("allowedPlants", PLAYABLE_PLANTS)
	var environment := str(ContentDB.garden_levels().get(str(level_id), {}).get("environment", "day"))
	selected_seeds = ContentDB.garden_rules.get("decks", {}).get(environment, PLAYABLE_PLANTS.slice(0, 8)).filter(func(kind): return kind in allowed)
	if str(ContentDB.garden_levels().get(str(level_id), {}).get("mode", "lawn")) != "lawn":
		_begin_battle(false)
	else:
		_render_seed_picker()
	_save_profile("选择关卡")


func _start_endless() -> void:
	selected_level = 1
	selected_mode = "endless"
	selected_seeds = ["peashooter", "sunflower", "wallnut", "cherrybomb", "potatomine", "snowpea", "repeater", "chomper", "threepeater", "tallnut"]
	_render_seed_picker()


func _render_seed_picker() -> void:
	view = "choose"
	if is_instance_valid(speed_button):
		speed_button.visible = false
	PlaygroundUI.clear(content_root)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 8)
	outer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_root.add_child(outer)
	var top := HBoxContainer.new()
	top.add_child(GardenSurfaces.button("← 关卡地图", accent, _render_levels, "ghost"))
	top.add_child(PlaygroundUI.label(
		"无尽模式 · 选择 6–10 张卡" if selected_mode == "endless" else "第 %s 关 · 选择 6–10 张卡" % selected_level,
		27,
		PlaygroundUI.INK,
		700
	))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(spacer)
	top.add_child(GardenSurfaces.button("全部 %s 种植物都已解锁" % PLAYABLE_PLANTS.size(), accent, func(): pass, "soft"))
	top.add_child(GardenSurfaces.button("难度：%s" % _difficulty_name(selected_difficulty), Color("#8d6b24"), _cycle_difficulty, "soft"))
	outer.add_child(top)
	seed_flight_lock = false
	var split := HBoxContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_theme_constant_override("separation", 12)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var grid := GridContainer.new()
	grid.columns = 7 if get_viewport_rect().size.x >= 1450 else 6
	grid.add_theme_constant_override("h_separation", 7)
	grid.add_theme_constant_override("v_separation", 7)
	scroll.add_child(grid)
	var allowed: Array = ContentDB.garden_levels().get(str(selected_level), {}).get("allowedPlants", PLAYABLE_PLANTS)
	seed_pick_buttons.clear()
	for kind in PLAYABLE_PLANTS:
		if kind in allowed:
			grid.add_child(_seed_pick_button(str(kind)))
	split.add_child(scroll)
	var info := VBoxContainer.new()
	info.custom_minimum_size.x = 300
	info.add_theme_constant_override("separation", 10)
	info.add_child(PlaygroundUI.label("🃏 已选 %s / 10" % selected_seeds.size(), 20, accent, 700))
	info.add_child(PlaygroundUI.label("点卡片加入或移除。开始后，左上角卡片会按顺序显示。", 14, PlaygroundUI.INK_SOFT, 500, true))
	var loadout := GridContainer.new()
	loadout.columns = 5
	loadout.add_theme_constant_override("h_separation", 4)
	loadout.add_theme_constant_override("v_separation", 4)
	seed_loadout_buttons.clear()
	for slot_index in 10:
		var slot := Button.new()
		slot.custom_minimum_size = Vector2(50, 62)
		slot.disabled = slot_index >= selected_seeds.size()
		slot.add_theme_stylebox_override("normal", PlaygroundUI.style(Color("#ead7aa"), 9, accent if not slot.disabled else Color("#b8ad95"), 3 if not slot.disabled else 1))
		slot.add_theme_stylebox_override("hover", PlaygroundUI.style(Color("#fff0bf"), 9, accent, 3))
		slot.add_theme_stylebox_override("pressed", PlaygroundUI.style(Color("#d8e6ad"), 9, accent, 3))
		slot.add_theme_stylebox_override("disabled", PlaygroundUI.style(Color("#f2ead9"), 9, Color("#c8bda7"), 1))
		if slot_index < selected_seeds.size():
			var portrait := TextureRect.new()
			portrait.texture = _plant_texture(str(selected_seeds[slot_index]))
			portrait.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			portrait.offset_left = 4
			portrait.offset_right = -4
			portrait.offset_top = 3
			portrait.offset_bottom = -3
			portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
			slot.add_child(portrait)
			slot.pressed.connect(_remove_seed_from_loadout.bind(slot_index))
		seed_loadout_buttons.append(slot)
		loadout.add_child(slot)
	info.add_child(loadout)
	var action := GardenSurfaces.button("开始守家 →", accent, _begin_battle)
	action.disabled = selected_seeds.size() < 6
	info.add_child(action)
	split.add_child(info)
	outer.add_child(split)
	_save_profile("选择本局卡组")
	call_deferred("_start_garden_music")


func _seed_pick_button(kind: String) -> Button:
	var definition: Dictionary = ContentDB.garden_plants()[kind]
	var button := Button.new()
	button.custom_minimum_size = Vector2(112, 144)
	button.toggle_mode = true
	button.button_pressed = kind in selected_seeds
	button.add_theme_stylebox_override("normal", PlaygroundUI.style(Color("#f0d8a5"), 8, accent if kind in selected_seeds else Color("#7e5c37"), 3 if kind in selected_seeds else 1))
	button.add_theme_stylebox_override("hover", PlaygroundUI.style(Color("#fff1c2"), 8, accent, 3))
	button.add_theme_stylebox_override("pressed", PlaygroundUI.style(Color("#d6e8a9"), 8, accent, 3))
	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.offset_left = 6
	column.offset_right = -6
	column.offset_top = 5
	column.offset_bottom = -5
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 2)
	var portrait := TextureRect.new()
	portrait.texture = _plant_texture(kind)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.custom_minimum_size.y = 77
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(portrait)
	var name_label := PlaygroundUI.label(str(definition.name), 17, PlaygroundUI.INK, 700)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(name_label)
	var cost := PlaygroundUI.label("阳光 %s" % int(definition.cost), 14, Color("#5e4728"), 700)
	cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(cost)
	button.add_child(column)
	button.pressed.connect(_toggle_seed_pick.bind(kind))
	seed_pick_buttons[kind] = button
	return button


func _toggle_seed_pick(kind: String) -> void:
	if seed_flight_lock:
		return
	var start := Vector2(746, 38)
	var removing_slot := selected_seeds.find(kind)
	if removing_slot >= 0 and removing_slot < seed_loadout_buttons.size():
		var selected_slot: Control = seed_loadout_buttons[removing_slot]
		if is_instance_valid(selected_slot):
			start = selected_slot.get_global_rect().get_center()
	else:
		var candidate: Control = seed_pick_buttons.get(kind, null)
		if candidate != null and is_instance_valid(candidate):
			start = candidate.get_global_rect().get_center()
	if kind in selected_seeds:
		selected_seeds.erase(kind)
	elif selected_seeds.size() < 10:
		selected_seeds.append(kind)
	AudioFX.play("select")
	_render_seed_picker()
	if kind in selected_seeds:
		var slot_index := selected_seeds.find(kind)
		if slot_index >= 0 and slot_index < seed_loadout_buttons.size():
			var target: Control = seed_loadout_buttons[slot_index]
			if is_instance_valid(target):
				_start_picker_transfer(kind, start, target.get_global_rect().get_center())
	else:
		_return_seed_to_picker(kind, start)
	_save_profile("选择植物卡组")


func _remove_seed_from_loadout(slot_index: int) -> void:
	if slot_index < 0 or slot_index >= selected_seeds.size() or seed_flight_lock:
		return
	var kind := str(selected_seeds[slot_index])
	var start := Vector2(746, 38)
	if slot_index < seed_loadout_buttons.size():
		var slot: Control = seed_loadout_buttons[slot_index]
		if is_instance_valid(slot):
			start = slot.get_global_rect().get_center()
	selected_seeds.remove_at(slot_index)
	AudioFX.play("back")
	_render_seed_picker()
	_return_seed_to_picker(kind, start)
	_save_profile("移除植物卡")


func _start_picker_transfer(kind: String, start: Vector2, target: Vector2) -> void:
	var flight := Control.new()
	flight.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flight.z_index = 90
	var sprite := TextureRect.new()
	sprite.texture = _plant_texture(kind)
	sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	sprite.custom_minimum_size = Vector2(76, 92)
	sprite.size = Vector2(76, 92)
	sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flight.add_child(sprite)
	flight.global_position = start - Vector2(38, 46)
	flight.set_meta("source_generation", seed_flight_generation)
	add_child(flight)
	seed_flight_lock = true
	var tween := MotionKit.tween(flight)
	tween.tween_property(flight, "global_position", target - Vector2(38, 46), .2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(sprite, "modulate:a", .15, .08).set_delay(.12)
	tween.tween_callback(func():
		flight.queue_free()
		seed_flight_lock = false
	)


func _return_seed_to_picker(kind: String, start := Vector2(746, 38)) -> void:
	var flight := Control.new()
	flight.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flight.z_index = 90
	var sprite := TextureRect.new()
	sprite.texture = _plant_texture(kind)
	sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	sprite.custom_minimum_size = Vector2(104, 124)
	sprite.size = Vector2(104, 124)
	sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flight.add_child(sprite)
	flight.set_meta("target_kind", kind)
	flight.set_meta("target_generation", seed_flight_generation)
	flight.set_meta("start_global", start)
	flight.modulate.a = 0.9
	add_child(flight)
	call_deferred("_play_seed_return", flight)


func _play_seed_return(flight: Control) -> void:
	var kind := str(flight.get_meta("target_kind", ""))
	if int(flight.get_meta("target_generation", 0)) != seed_flight_generation:
		flight.queue_free()
		return
	var button: Button = seed_pick_buttons.get(kind, null)
	if button == null or not is_instance_valid(button):
		flight.queue_free()
		return
	var start := Vector2(746, 38)
	start = flight.get_meta("start_global", start)
	var target := button.get_global_rect().get_center()
	flight.global_position = start - Vector2(104, 124) * 0.5
	flight.modulate.a = 0.9
	seed_flight_lock = true
	var tween := MotionKit.tween(flight)
	tween.tween_property(flight, "global_position", target - Vector2(104, 124) * 0.5, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	var sprite := flight.get_child(0) as TextureRect
	tween.parallel().tween_property(sprite, "modulate:a", 0.0, 0.07).set_delay(0.13)
	tween.tween_callback(func():
		flight.queue_free()
		seed_flight_lock = false
	)


func _begin_battle(tutorial: bool = false) -> void:
	var special := str(ContentDB.garden_levels().get(str(selected_level), {}).get("mode", "lawn"))
	if selected_seeds.size() < 6 and not tutorial and special == "lawn":
		show_toast("至少选 6 张植物卡")
		return
	var seeds := ["sunflower", "peashooter", "wallnut", "cherrybomb", "potatomine"] if tutorial else selected_seeds
	if tutorial:
		selected_mode = "tutorial"
	battle = {
		"levelId": selected_level,
		"mode": "tutorial" if tutorial else selected_mode,
		"seeds": seeds.duplicate(),
		"tutorial": tutorial,
		"tutorialStep": 0,
		"phase": "playing",
		"sessionId": "%s-%s-%s" % [game_id, Time.get_unix_time_from_system(), randi()],
		"reference": true,
	}
	speed = 1
	reported_battle = false
	pending_pvz_resume = {}
	_save_profile("战斗开始")
	_render_battle()


func _render_battle() -> void:
	view = "battle"
	if is_instance_valid(speed_button):
		speed_button.visible = true
		speed_button.text = "⏩ %s×" % speed
	PlaygroundUI.clear(content_root)
	tutorial_label = null
	tutorial_banner = null
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 6)
	outer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_root.add_child(outer)
	var resume := pending_pvz_resume.duplicate(true)
	pending_pvz_resume = {}
	battle_host = PvZBattleHost.new()
	battle_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	battle_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	battle_host.autosave_due.connect(_save_profile)
	battle_host.battle_finished.connect(_on_reference_battle_finished)
	battle_host.battle_ready.connect(_on_reference_battle_ready)
	outer.add_child(battle_host)
	var context := {
		"levelId": selected_level,
		"mode": str(battle.get("mode", selected_mode)),
		"environment": str(ContentDB.garden_levels().get(str(selected_level), {}).get("environment", "day")),
		"seeds": battle.get("seeds", selected_seeds).duplicate(),
		"difficulty": _resolved_difficulty(),
		"speed": speed,
		"profileId": str(players[0].id),
	}
	if not battle_host.start(context, resume):
		battle_host.queue_free()
		battle_host = null
		show_toast("战斗场景没有加载成功，请重新进入这一关。")
		_render_home()
		return
	if bool(battle.get("tutorial", false)):
		_build_tutorial_banner(outer)


func _on_reference_battle_ready() -> void:
	if not is_instance_valid(battle_host) or not is_instance_valid(battle_host.battle):
		return
	_tutorial_event_callable = _on_tutorial_event
	EventBus.event_pushed.connect(_tutorial_event_callable)
	var slot := battle_host.battle.card_manager.card_slot_battle
	if slot != null:
		for card in slot.curr_cards:
			if is_instance_valid(card) and not card.signal_card_use_end.is_connected(_on_tutorial_card_used):
				card.signal_card_use_end.connect(_on_tutorial_card_used)
	if bool(battle.get("tutorial", false)):
		for row in battle_host.battle.plant_cell_manager.all_plant_cells:
			for cell in row:
				if cell is PlantCell and not cell.signal_plant_free.is_connected(_on_tutorial_plant_removed):
					cell.signal_plant_free.connect(_on_tutorial_plant_removed)
	if paused:
		battle_host.set_paused(true)
	if bool(battle.get("tutorial", false)):
		_refresh_tutorial_banner()
	_save_profile("战斗已就绪")


func _resolved_difficulty() -> String:
	if selected_difficulty != "auto":
		return selected_difficulty
	return GameTuning.resolve("auto", players)


func _cycle_speed() -> void:
	speed = 2 if speed == 1 else 3 if speed == 2 else 1
	if is_instance_valid(battle_host):
		battle_host.set_speed(speed)
	if is_instance_valid(speed_button):
		speed_button.text = "⏩ %s×" % speed
	if bool(battle.get("tutorial", false)):
		_tutorial_action("speed")
	AudioFX.play("select")
	_save_profile("切换倍速")


func _cycle_difficulty() -> void:
	selected_difficulty = "normal" if selected_difficulty == "auto" else "easy" if selected_difficulty == "normal" else "challenge" if selected_difficulty == "easy" else "auto"
	profile_data.difficulty = selected_difficulty
	SaveStore.set_difficulty(game_id, str(players[0].id), selected_difficulty)
	_save_profile("切换难度")
	_render_seed_picker()


func _difficulty_name(value: String) -> String:
	if value == "easy":
		return "轻松"
	if value == "challenge":
		return "挑战"
	if value == "normal":
		return "标准"
	return "按年龄"


func _toggle_auto_collect() -> void:
	profile_data.autoCollectSun = not bool(profile_data.get("autoCollectSun", false))
	Global.config_service.auto_collect_sun = bool(profile_data.autoCollectSun)
	AudioFX.play("select")
	_save_profile("自动拾取阳光")
	show_toast("阳光落地后会直接收进口袋" if bool(profile_data.autoCollectSun) else "阳光需要手动点击收集")


func _build_tutorial_banner(parent: VBoxContainer) -> void:
	tutorial_banner = GardenSurfaces.panel(Color("#fff5c9"), 12, Color("#a78b4c"), 1)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	tutorial_label = PlaygroundUI.label("", 16, PlaygroundUI.INK, 700, true)
	tutorial_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(tutorial_label)
	if int(battle.get("tutorialStep", 0)) >= 3:
		row.add_child(GardenSurfaces.button("跳过教程", Color("#8f7550"), _skip_tutorial, "ghost"))
	if int(battle.get("tutorialStep", 0)) == 5:
		row.add_child(GardenSurfaces.button("启动割草机", Color("#d1842c"), _tutorial_mower))
	tutorial_banner.add_child(row)
	parent.add_child(tutorial_banner)
	_refresh_tutorial_banner()


func _refresh_tutorial_banner() -> void:
	if not bool(battle.get("tutorial", false)) or not is_instance_valid(tutorial_label):
		return
	var step := clampi(int(battle.get("tutorialStep", 0)), 0, TUTORIAL_TEXT.size() - 1)
	tutorial_label.text = "🎓 小课堂 %s / 8 · %s" % [mini(step + 1, 8), TUTORIAL_TEXT[step]]


func _tutorial_action(action: String, kind: String = "") -> void:
	if not bool(battle.get("tutorial", false)):
		return
	var step := int(battle.get("tutorialStep", 0))
	var next := step
	if action == "sun" and step == 0:
		next = 1
	elif action == "plant" and step == 1 and kind == "sunflower":
		next = 2
	elif action == "plant" and step == 2 and kind == "peashooter":
		next = 3
	elif action == "dig" and step == 3:
		next = 4
	elif action == "plant" and step == 4 and kind == "wallnut":
		next = 5
	elif action == "mower" and step == 5:
		next = 6
	elif action == "pause" and step == 6:
		next = 7
	elif action == "speed" and step == 7:
		next = 8
	if next != step:
		battle.tutorialStep = next
		_refresh_tutorial_banner()
		Speech.speak(TUTORIAL_TEXT[mini(next, TUTORIAL_TEXT.size() - 1)])
		_save_profile("花园小课堂")
		if next >= 8:
			call_deferred("_finish_reference_tutorial")
		elif next in [5, 6]:
			call_deferred("_rebuild_tutorial_banner")


func _rebuild_tutorial_banner() -> void:
	if not bool(battle.get("tutorial", false)) or not is_instance_valid(tutorial_banner):
		return
	var parent := tutorial_banner.get_parent()
	tutorial_banner.queue_free()
	tutorial_banner = null
	if parent is VBoxContainer:
		_build_tutorial_banner(parent)


func _on_tutorial_event(event_name: String, payload: Array) -> void:
	if event_name == "add_sun_value" and int(battle.get("tutorialStep", 0)) == 0:
		_tutorial_action("sun")


func _on_tutorial_plant_removed(_cell: PlantCell, _plant_type: int) -> void:
	if int(battle.get("tutorialStep", 0)) == 3:
		_tutorial_action("dig")


func _on_tutorial_card_used(card: Card) -> void:
	if not bool(battle.get("tutorial", false)) or card == null or card.card_reference == null:
		return
	var kind := PvZLevelFactory.plant_kind(card.card_reference.content_id)
	_tutorial_action("plant", kind)
	call_deferred("_rebind_tutorial_cards")


func _rebind_tutorial_cards() -> void:
	if not is_instance_valid(battle_host) or not is_instance_valid(battle_host.battle):
		return
	var slot := battle_host.battle.card_manager.card_slot_battle
	if slot == null:
		return
	for card in slot.curr_cards:
		if is_instance_valid(card) and not card.signal_card_use_end.is_connected(_on_tutorial_card_used):
			card.signal_card_use_end.connect(_on_tutorial_card_used)


func _tutorial_mower() -> void:
	if not bool(battle.get("tutorial", false)) or int(battle.get("tutorialStep", 0)) != 5:
		return
	if is_instance_valid(battle_host):
		battle_host.trigger_tutorial_mower(2)
	AudioFX.play("mower")
	_tutorial_action("mower")


func _skip_tutorial() -> void:
	if int(battle.get("tutorialStep", 0)) < 3:
		return
	profile_data.tutorialSeen = true
	_dispose_reference_battle()
	_save_profile("跳过花园小课堂")
	_render_home()


func _finish_reference_tutorial() -> void:
	profile_data.tutorialSeen = true
	profile_data.pvzBattle = {}
	_dispose_reference_battle()
	_save_profile("花园小课堂完成", false)
	_render_home()
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	content.add_child(PlaygroundUI.label("🎓", 58, accent, 700))
	content.add_child(PlaygroundUI.label("收集阳光、种植、铲除、割草机、暂停和倍速都学会啦。现在可以挑战白天花园了。", 17, PlaygroundUI.INK_SOFT, 500, true))
	open_modal("花园小课堂完成！", content, [
		{"text": "去闯关", "kind": "primary", "callback": func(): _close_top_modal(); _render_levels()},
	], "小花园准备好了")
	AudioFX.play("win")


func _on_reference_battle_finished(won: bool, summary: Dictionary) -> void:
	_finish_battle(won, summary)


func _finish_battle(won: bool, summary: Dictionary) -> void:
	if battle.is_empty() or reported_battle:
		return
	reported_battle = true
	var stars := int(summary.get("stars", 0))
	var wave := int(summary.get("wave", 0))
	var total := int(summary.get("waveCount", 1))
	var flags := int(summary.get("flags", 0))
	if won:
		if battle.get("mode") == "endless":
			profile_data.bestEndless = maxi(int(profile_data.get("bestEndless", 0)), flags)
		else:
			var level_key := str(battle.get("levelId", 1))
			profile_data.stars[level_key] = maxi(int(profile_data.get("stars", {}).get(level_key, 0)), stars)
		SaveStore.record_outcome(
			str(players[0].id),
			game_id,
			"win",
			stars,
			wave,
			maxi(1, total),
			{"strategy": {"correct": wave, "answered": maxi(1, total)}},
			str(battle.get("sessionId", ""))
		)
	else:
		SaveStore.record_outcome(str(players[0].id), game_id, "loss", 0, 0, 0, {}, str(battle.get("sessionId", "")))
	battle["phase"] = "won" if won else "lost"
	profile_data.pvzBattle = {}
	_save_profile("战斗结束", false)
	AudioFX.play("win" if won else "wrong")
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	content.add_child(PlaygroundUI.label("🏆" if won else "🌱", 62, accent, 700))
	content.add_child(PlaygroundUI.label("守住了小房子！" if won else "这次没有守住，再来一次就好。", 26, PlaygroundUI.INK, 700, true))
	if won and battle.get("mode") != "endless":
		content.add_child(PlaygroundUI.label("获得 %s 颗星" % stars, 19, Color("#b6861c"), 700))
	if battle.get("mode") == "endless":
		content.add_child(PlaygroundUI.label("到达第 %s 波 · %s 面旗" % [wave, flags], 18, PlaygroundUI.INK_SOFT, 700))
	var tutorial := bool(battle.get("tutorial", false))
	var replay := func():
		_close_top_modal()
		_dispose_reference_battle()
		_begin_battle(tutorial)
	open_modal("战斗结束", content, [
		{"text": "花园首页", "kind": "soft", "callback": func(): _close_top_modal(); _dispose_reference_battle(); _render_home()},
		{"text": "再打一次", "kind": "primary", "callback": replay},
	], "进度已自动保存")


func _dispose_reference_battle() -> void:
	if _tutorial_event_callable.is_valid() and EventBus.event_pushed.is_connected(_tutorial_event_callable):
		EventBus.event_pushed.disconnect(_tutorial_event_callable)
	if is_instance_valid(battle_host):
		battle_host.cleanup()
		battle_host.queue_free()
	battle_host = null
	battle = {}
	paused = false


func _render_almanac(tab: String) -> void:
	view = "almanac"
	if is_instance_valid(speed_button):
		speed_button.visible = false
	PlaygroundUI.clear(content_root)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 9)
	outer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_root.add_child(outer)
	var top := HBoxContainer.new()
	top.add_child(GardenSurfaces.button("← 花园首页", accent, _render_home, "ghost"))
	top.add_child(GardenSurfaces.button("🌱 植物 %s 种" % PLAYABLE_PLANTS.size(), accent, func(): _render_almanac("plants"), "primary" if tab == "plants" else "soft"))
	top.add_child(GardenSurfaces.button("🧟 僵尸 %s 种" % zombie_entries.size(), Color("#5b5b68"), func(): _render_almanac("zombies"), "primary" if tab == "zombies" else "soft"))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(spacer)
	top.add_child(PlaygroundUI.label("全部植物的说明和战斗能力都可以在这里查看", 13, PlaygroundUI.INK_SOFT, 500))
	outer.add_child(top)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	scroll.add_child(grid)
	var entries := PLAYABLE_PLANTS.map(func(kind): return plant_entries.get(kind, {})).filter(func(entry): return not entry.is_empty()) if tab == "plants" else zombie_entries.values()
	for entry in entries:
		grid.add_child(_almanac_card(entry, tab))


func _almanac_card(entry: Dictionary, tab: String) -> Control:
	var panel := GardenSurfaces.panel(Color(1, 1, 1, 0.78), 18, PlaygroundUI.mix(accent, Color.WHITE, 0.55), 1)
	panel.custom_minimum_size = Vector2(210, 220)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	panel.add_child(column)
	var path := "res://assets/garden/runtime/" + str(entry.get("image", ""))
	var portrait := TextureRect.new()
	portrait.texture = load(path) if ResourceLoader.exists(path) else null
	portrait.custom_minimum_size.y = 110
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	column.add_child(portrait)
	var name := PlaygroundUI.label(str(entry.get("name", "")), 19, PlaygroundUI.INK, 700)
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(name)
	column.add_child(PlaygroundUI.chip(str(entry.get("group", "")), accent if tab == "plants" else Color("#6b5b72")))
	var button := GardenSurfaces.button("听说明", accent if tab == "plants" else Color("#66556d"), _show_almanac_detail.bind(entry), "soft")
	button.custom_minimum_size.y = 38
	column.add_child(button)
	return panel


func _show_almanac_detail(entry: Dictionary) -> void:
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	var path := "res://assets/garden/runtime/" + str(entry.get("image", ""))
	if ResourceLoader.exists(path):
		var portrait := TextureRect.new()
		portrait.texture = load(path)
		portrait.custom_minimum_size = Vector2(220, 180)
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		content.add_child(portrait)
	for pair in entry.get("stats", []):
		content.add_child(PlaygroundUI.chip("%s：%s" % [pair[0], pair[1]], accent))
	content.add_child(PlaygroundUI.label(str(entry.get("description", "")), 17, PlaygroundUI.INK_SOFT, 500, true))
	content.add_child(PlaygroundUI.label("%s：%s" % [entry.get("noteTitle", "提示"), entry.get("note", "")], 14, PlaygroundUI.INK_SOFT, 500, true))
	Speech.speak("%s。%s。%s" % [entry.get("name", ""), entry.get("description", ""), entry.get("note", "")])
	open_modal(str(entry.get("name", "")), content, [
		{"text": "再读一遍", "kind": "soft", "callback": func(): Speech.speak("%s。%s" % [entry.get("description", ""), entry.get("note", "")])},
		{"text": "关闭", "kind": "primary", "callback": func(): _close_top_modal()},
	], str(entry.get("group", "")))


func _start_tutorial() -> void:
	if bool(profile_data.get("tutorialSeen", false)):
		var content := VBoxContainer.new()
		content.add_child(PlaygroundUI.label("已经完成过花园小课堂，也可以随时重新练习。", 17, PlaygroundUI.INK_SOFT, 500, true))
		open_modal("再上一次小课堂？", content, [
			{"text": "先不用", "kind": "soft", "callback": func(): _close_top_modal()},
			{"text": "重新开始", "kind": "primary", "callback": func(): _close_top_modal(); _begin_battle(true)},
		])
		return
	_begin_battle(true)


func _plant_texture(kind: String) -> Texture2D:
	var entry: Dictionary = plant_entries.get(kind, {})
	var path := "res://assets/garden/runtime/" + str(entry.get("image", ""))
	return load(path) if ResourceLoader.exists(path) else null


func toggle_pause(force: Variant = null) -> void:
	super.toggle_pause(force)
	if paused and int(battle.get("tutorialStep", -1)) == 6:
		_tutorial_action("pause")


func _on_pause_changed(is_paused: bool) -> void:
	if is_instance_valid(battle_host):
		battle_host.set_paused(is_paused)
	if is_paused:
		AudioFX.stop_music()
	_save_profile("暂停" if is_paused else "继续战斗")
	SaveStore.flush()
	if not is_paused and not is_instance_valid(battle_host):
		call_deferred("_start_garden_music")

func _confirm_restart() -> void:
	_close_top_modal()
	var tutorial := bool(battle.get("tutorial", false))
	var content := VBoxContainer.new()
	content.add_child(PlaygroundUI.label("当前战斗进度会被本轮替换，儿童档案、星级和植物解锁不会丢失。", 17, PlaygroundUI.INK_SOFT, 500, true))
	var restart := func():
		_close_top_modal()
		paused = false
		_dispose_reference_battle()
		_begin_battle(tutorial)
	open_modal("重开这次战斗？", content, [
		{"text": "继续战斗", "kind": "soft", "callback": func(): _close_top_modal()},
		{"text": "重新开始", "kind": "primary", "callback": restart},
	], "花园进度")


func _handle_back() -> void:
	if not _modal_stack.is_empty():
		_close_top_modal()
		return
	if view in ["levels", "choose", "almanac"]:
		_render_home()
		return
	if view == "battle" and not battle.is_empty() and battle.get("phase") == "playing":
		_save_profile("暂停")
		_confirm_exit()
		return
	_confirm_exit()


func _save_profile(note: String, resume: bool = true) -> void:
	if players.is_empty():
		return
	profile_data.battle = {}
	if is_instance_valid(battle_host) and not battle.is_empty() and battle.get("phase") == "playing":
		profile_data.pvzBattle = battle_host.snapshot_state()
	else:
		profile_data.pvzBattle = {}
	profile_data.speed = speed
	profile_data.view = view
	profile_data.selectedLevel = selected_level
	profile_data.selectedMode = selected_mode
	profile_data.selectedSeeds = selected_seeds.duplicate()
	profile_data.paused = paused
	profile_data.updatedAt = Time.get_unix_time_from_system()
	var note_text := note
	if view == "battle" and not battle.is_empty():
		var snapshot: Dictionary = profile_data.get("pvzBattle", {})
		note_text = "第 %s 关 · 第 %s 波" % [battle.get("levelId", 1), int(snapshot.get("wave", 0)) + 1] if battle.get("mode") != "endless" else "无尽 · 第 %s 波" % (int(snapshot.get("wave", 0)) + 1)
	var resumable: bool = resume and not profile_data.get("pvzBattle", {}).is_empty() and str(battle.get("phase", "")) == "playing"
	SaveStore.save_state(game_id, str(players[0].id), profile_data, note_text, resumable)


func _integer(value: Variant) -> int:
	if value is int:
		return int(value)
	if value is float and is_finite(value):
		return int(value)
	if value is String and value.is_valid_float():
		return int(float(value))
	return 0


func _start_garden_music() -> void:
	if paused:
		return
	if is_instance_valid(battle_host):
		return
	var theme := "menu"
	if view == "battle" and not battle.is_empty():
		theme = "boss" if not battle.get("boss", {}).is_empty() else "conveyor" if str(battle.get("special", "")) == "conveyor" else str(battle.get("environment", "day"))
	elif view == "choose":
		theme = "choose"
	AudioFX.start_music("garden:" + theme)


func _build_topbar() -> Control:
	var bar := GardenSurfaces.panel()
	var box := bar.get_theme_stylebox("panel").duplicate() as StyleBoxTexture
	box.content_margin_top = 5
	box.content_margin_bottom = 5
	bar.add_theme_stylebox_override("panel", box)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var back := GardenSurfaces.button("←", accent, _handle_back, "soft")
	back.custom_minimum_size = Vector2(52, 48)
	row.add_child(back)
	var title := PlaygroundUI.label("植物大战僵尸", 23, PlaygroundUI.INK, 700)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)
	speed_button = GardenSurfaces.button("⏩ %s×" % speed, accent, _cycle_speed, "soft")
	speed_button.custom_minimum_size = Vector2(94, 48)
	speed_button.visible = view == "battle"
	row.add_child(speed_button)
	var pause := GardenSurfaces.button("Ⅱ 暂停", accent, toggle_pause, "soft")
	pause.custom_minimum_size = Vector2(108, 48)
	row.add_child(pause)
	bar.add_child(row)
	return bar


func open_modal(title: String, content: Control, actions: Array, eyebrow: String = "", dismissible: bool = true) -> Control:
	var layer := Control.new()
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.z_index = 60
	layer.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.set_meta("dismissible", dismissible)
	var dim := ColorRect.new()
	dim.color = Color(0.08, 0.11, 0.08, 0.68)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(center)
	var stone := PanelContainer.new()
	stone.add_theme_stylebox_override("panel", GardenSurfaces.surface("ui/stone-panel.webp", 16, 16))
	stone.custom_minimum_size = Vector2(minf(930.0, maxf(560.0, get_viewport_rect().size.x - 84.0)), 0)
	stone.modulate.a = 0.0
	stone.scale = Vector2(0.97, 0.97)
	stone.pivot_offset = Vector2(stone.size.x * .5, 0)
	center.add_child(stone)
	var paper := PanelContainer.new()
	paper.add_theme_stylebox_override("panel", GardenSurfaces.surface("ui/parchment-button.webp", 7, 25))
	paper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	paper.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stone.add_child(paper)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	paper.add_child(column)
	if not eyebrow.is_empty():
		column.add_child(PlaygroundUI.label(eyebrow, 14, Color("#73552e"), 700))
	var title_label := PlaygroundUI.label(title, 32, Color("#35271b"), 700, true)
	title_label.add_theme_constant_override("outline_size", 2)
	title_label.add_theme_color_override("font_outline_color", Color("#fff4d0"))
	column.add_child(title_label)
	var divider := ColorRect.new()
	divider.color = Color("#b89b68")
	divider.custom_minimum_size.y = 2
	divider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(divider)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if content.get_combined_minimum_size().y > 430.0:
		var scroll := ScrollContainer.new()
		scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		scroll.custom_minimum_size.y = minf(430.0, get_viewport_rect().size.y * .54)
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.add_child(content)
		column.add_child(scroll)
	else:
		column.add_child(content)
	var actions_row := HBoxContainer.new()
	actions_row.alignment = BoxContainer.ALIGNMENT_END
	actions_row.add_theme_constant_override("separation", 8)
	actions_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for action in actions:
		var button := GardenSurfaces.button(
			str(action.get("text", "好")),
			accent,
			action.get("callback", Callable()),
			str(action.get("kind", "primary"))
		)
		button.custom_minimum_size = Vector2(0, 52)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", 18)
		actions_row.add_child(button)
	column.add_child(actions_row)
	overlay_root.add_child(layer)
	_modal_stack.append(layer)
	stone.resized.connect(func(): stone.pivot_offset = Vector2(stone.size.x * .5, 0))
	var animation := MotionKit.tween(self)
	animation.set_parallel(true)
	animation.tween_property(stone, "modulate:a", 1.0, MotionKit.MODAL_IN)
	animation.tween_property(stone, "scale", Vector2.ONE, MotionKit.MODAL_IN).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var controls := paper.find_children("*", "Button", true, false)
	if not controls.is_empty():
		controls[0].call_deferred("grab_focus")
	return layer


func _close_top_modal() -> void:
	# 本游戏的弹窗全部是上面的自绘层（不走 DialogManager），按基类 fallback 路径关闭
	if _modal_stack.is_empty():
		return
	var layer: Control = _modal_stack.pop_back()
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	MotionKit.fade_out_and_free(layer, self, MotionKit.MODAL_OUT)
