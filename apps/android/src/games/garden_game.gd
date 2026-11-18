class_name NativeGardenGame
extends NativeGameScreen

const ENGINE := preload("res://src/games/garden_engine.gd")
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
var engine: GardenBattleEngine
var field: GardenField
var speed := 1
var selected_level := 1
var selected_mode := "adventure"
var selected_seeds: Array = []
var plant_entries: Dictionary = {}
var zombie_entries: Dictionary = {}
var seed_buttons: Dictionary = {}
var seed_pick_buttons: Dictionary = {}
var seed_flight_lock := false
var seed_flight_generation := 0
var sun_label: Label
var wave_label: Label
var tutorial_label: Label
var hud_clock := 0.0
var save_clock := 0.0
var reported_battle := false
var use_speed_button: Button
var selected_difficulty := "auto"
var tick_accumulator := 0.0


func _ready() -> void:
	build_shell()
	engine = ENGINE.new()
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
	if profile_data.get("battle") is Dictionary and not profile_data.battle.is_empty():
		battle = engine.restore(profile_data.battle, players[0])
		paused = bool(profile_data.get("paused", false))
		if battle.is_empty():
			selected_level = clampi(_integer(profile_data.battle.get("levelId", 1)), 1, 50)
			var environment := str(ContentDB.garden_levels().get(str(selected_level), {}).get("environment", "day"))
			selected_seeds = ContentDB.garden_rules.get("decks", {}).get(environment, PLAYABLE_PLANTS.slice(0, 8)).duplicate()
			_begin_battle(false)
			return
		selected_level = clampi(_integer(battle.get("levelId", 1)), 1, 50)
		selected_mode = str(battle.mode)
		if battle.get("player") is Dictionary:
			players = [battle.player.duplicate(true)]
		speed = clampi(_integer(profile_data.get("speed", 1)), 1, 3)
		tick_accumulator = _number(battle.get("logicAccumulator", 0.0), 0.0)
		selected_difficulty = str(battle.get("difficulty", "auto"))
		view = "battle"
		_render_battle()
		if paused:
			call_deferred("toggle_pause", true)
	elif not bool(profile_data.get("tutorialSeen", false)):
		_begin_battle(true)
	elif str(profile_data.get("view", "home")) == "choose" and not selected_seeds.is_empty():
		_render_seed_picker()
	else:
		_render_home()
	pause_changed.connect(_on_pause_changed)
	call_deferred("_start_garden_music")


func _load_entries() -> void:
	for entry in ContentDB.garden.get("plantAlmanac", []):
		plant_entries[str(entry.id)] = entry
	for entry in ContentDB.garden.get("zombieAlmanac", []):
		zombie_entries[str(entry.id)] = entry


func _process(delta: float) -> void:
	if view != "battle" or battle.is_empty() or battle.get("phase") != "playing" or paused:
		return
	tick_accumulator += delta * speed
	var events: Array = []
	var steps := 0
	while tick_accumulator >= 1.0 / 30.0 and steps < 8:
		events.append_array(engine.tick(battle, 1.0 / 30.0))
		tick_accumulator -= 1.0 / 30.0
		steps += 1
	battle.logicAccumulator = tick_accumulator
	if is_instance_valid(field):
		field.set_battle(battle, clampf(tick_accumulator / (1.0 / 30.0), 0.0, 1.0))
	_process_events(events)
	hud_clock += delta
	save_clock += delta
	if hud_clock >= 0.18:
		hud_clock = 0.0
		_update_hud()
	if save_clock >= 2.0:
		save_clock = 0.0
		_save_profile("战斗中")
	if battle.get("phase") in ["won", "lost"]:
		_finish_battle()


func _notification(what: int) -> void:
	if OS.get_environment("KIDS_PLAYGROUND_AUDIT") == "1":
		return
	if not is_inside_tree() or engine == null:
		return
	if what in [NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_CLOSE_REQUEST]:
		if view == "battle" and not battle.is_empty():
			if not paused and is_instance_valid(overlay_root):
				toggle_pause(true)
			_save_profile("切到后台暂停")
			SaveStore.flush()
		AudioFX.stop_all()

func _process_events(events: Array) -> void:
	for event in events:
		if is_instance_valid(field):
			field.add_effect(event)
		match str(event.get("type", "")):
			"mower":
				_play_garden_sound("lawnmower")
				show_toast("割草机启动了！")
			"eat":
				_play_garden_sound("chomp")
			"plant":
				_play_garden_sound("plant_water" if bool(event.get("water", false)) else "buttonclick")
			"sun", "coin":
				_play_garden_sound("points")
			"flag":
				_play_garden_sound("hugewave")
			"explode":
				_play_garden_sound("cherrybomb")
			"freeze":
				_play_garden_sound("frozen")
			"fume":
				_play_garden_sound("fume")
			"hypnotize":
				_play_garden_sound("mindcontrolled")
			"vase":
				_play_garden_sound("vase_breaking")
			"coffee":
				_play_garden_sound("coffee")
			"thunder":
				_play_garden_sound("thunder")
			"win":
				_play_garden_sound("winmusic")
			"lost":
				_play_garden_sound("losemusic")
			"shoot":
				AudioFX.play("shoot")
			"hit":
				_play_garden_sound("bonk")

func _render_home() -> void:
	view = "home"
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
	seed_flight_generation += 1
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
	if kind in selected_seeds:
		selected_seeds.erase(kind)
	elif selected_seeds.size() < 10:
		selected_seeds.append(kind)
	AudioFX.play("select")
	_render_seed_picker()
	_save_profile("选择植物卡组")


func _start_seed_flight(kind: String) -> void:
	var flight := Control.new()
	flight.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flight.z_index = 90
	var sprite_reference := TextureRect.new()
	var sprite := sprite_reference
	sprite.texture = _plant_texture(kind)
	sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	sprite.custom_minimum_size = Vector2(104, 124)
	sprite.size = Vector2(104, 124)
	sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flight.add_child(sprite)
	flight.set_meta("source_kind", kind)
	flight.set_meta("source_generation", seed_flight_generation)
	flight.modulate.a = 0.9
	add_child(flight)
	call_deferred("_play_seed_flight", flight)


func _play_seed_flight(flight: Control) -> void:
	var kind := str(flight.get_meta("source_kind", ""))
	if int(flight.get_meta("source_generation", 0)) != seed_flight_generation:
		flight.queue_free()
		return
	var button: Button = seed_pick_buttons.get(kind, null)
	if button == null or not is_instance_valid(button):
		flight.queue_free()
		return
	var start := button.get_global_rect().get_center()
	var target := Vector2(746, 38)
	flight.global_position = start - Vector2(104, 124) * 0.5
	flight.modulate.a = 0.9
	var tween := MotionKit.tween(flight)
	tween.tween_property(flight, "global_position", target - Vector2(104, 124) * 0.5, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(sprite_reference, "modulate:a", 0.0, 0.07).set_delay(0.13)
	tween.tween_callback(flight.queue_free)


func _begin_battle(tutorial: bool = false) -> void:
	var special := str(ContentDB.garden_levels().get(str(selected_level), {}).get("mode", "lawn"))
	if selected_seeds.size() < 6 and not tutorial and special == "lawn":
		show_toast("至少选 6 张植物卡")
		return
	var seeds := ["sunflower", "peashooter", "wallnut", "cherrybomb", "potatomine"] if tutorial else selected_seeds
	battle = engine.create(players[0], selected_level, "tutorial" if tutorial else selected_mode, seeds, tutorial, selected_difficulty)
	battle["sessionId"] = "%s-%s-%s" % [game_id, Time.get_unix_time_from_system(), randi()]
	speed = 1
	tick_accumulator = 0.0
	reported_battle = false
	field = null
	seed_flight_lock = true
	seed_flight_generation += 1
	if not tutorial:
		for kind in selected_seeds.duplicate(true):
			_start_seed_flight(kind)
	_save_profile("战斗开始")
	_render_battle()
	var environment := str(battle.get("environment", "day"))
	call_deferred("_start_garden_music")


func _render_battle() -> void:
	view = "battle"
	PlaygroundUI.clear(content_root)
	seed_buttons.clear()
	sun_label = null
	wave_label = null
	tutorial_label = null
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 5)
	outer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_root.add_child(outer)
	field = GardenField.new()
	field.size_flags_vertical = Control.SIZE_EXPAND_FILL
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	field.cell_pressed.connect(_battle_cell)
	field.sun_pressed.connect(_collect_sun)
	field.coin_pressed.connect(func(uid: int):
		if engine.collect_coin(battle, uid):
			_save_profile("收集金币")
	)
	field.seed_pressed.connect(_select_battle_seed)
	field.shovel_pressed.connect(_toggle_shovel)
	field.speed_pressed.connect(_cycle_speed)
	field.blank_pressed.connect(_cancel_selection)
	# 注入可种植校验，战场用它做实时预览（绿/红格框）
	field.can_plant_check = func(row: int, col: int, kind: String) -> String:
		return engine.can_plant(battle, row, col, kind) if not battle.is_empty() else "战斗未开始"
	field.speed = speed
	field.paused = paused
	field.set_battle(battle)
	outer.add_child(field)
	if bool(battle.get("tutorial", false)):
		var step := int(battle.get("tutorialStep", 0))
		var tutorial_panel := GardenSurfaces.panel(Color("#fff5c9"), 12, Color("#a78b4c"), 1)
		var tutorial_row := HBoxContainer.new()
		tutorial_row.add_theme_constant_override("separation", 10)
		tutorial_label = PlaygroundUI.label("小课堂 %s / 8 · %s" % [mini(step + 1, 8), TUTORIAL_TEXT[mini(step, TUTORIAL_TEXT.size() - 1)]], 16, PlaygroundUI.INK, 700, true)
		tutorial_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tutorial_row.add_child(tutorial_label)
		if step >= 3 and step < 8:
			tutorial_row.add_child(GardenSurfaces.button("跳过教程", Color("#8f7550"), _skip_tutorial, "ghost"))
		if step == 5:
			tutorial_row.add_child(GardenSurfaces.button("启动割草机", Color("#d1842c"), _tutorial_mower))
		tutorial_panel.add_child(tutorial_row)
		outer.add_child(tutorial_panel)
	if battle.get("phase") in ["won", "lost"]:
		call_deferred("_finish_battle")

func _battle_seed_button(kind: String) -> Button:
	var definition: Dictionary = ContentDB.garden_plants()[kind]
	var button := Button.new()
	button.custom_minimum_size = Vector2(104, 106)
	button.add_theme_stylebox_override("normal",PlaygroundUI.style(PlaygroundUI.mix(accent,Color.WHITE,0.86),16,PlaygroundUI.mix(accent,Color.WHITE,0.28),2,3,Color(0,0,0,0.12)))
	button.add_theme_stylebox_override("hover",PlaygroundUI.style(PlaygroundUI.mix(accent,Color.WHITE,0.78),16,accent,3))
	button.add_theme_stylebox_override("pressed",PlaygroundUI.style(PlaygroundUI.mix(accent,Color.WHITE,0.7),16,accent,3))
	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.offset_left = 5
	column.offset_right = -5
	column.offset_top = 5
	column.offset_bottom = -5
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation",1)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icon := TextureRect.new()
	icon.texture = _plant_texture(kind)
	icon.custom_minimum_size = Vector2(0,52)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(icon)
	var name_label := PlaygroundUI.label(str(definition.name),12,PlaygroundUI.INK,700,true)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.max_lines_visible = 1
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	column.add_child(name_label)
	var cost_label := PlaygroundUI.label("☀ %s" % int(definition.cost),12,accent,700)
	cost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(cost_label)
	button.add_child(column)
	button.pressed.connect(_select_battle_seed.bind(kind))
	return button


func _select_battle_seed(kind: String) -> void:
	if battle.is_empty() or battle.get("phase") != "playing" or paused:
		return
	# 再点同一张卡 = 取消选中
	if str(battle.get("selectedSeed", "")) == kind and not bool(battle.get("shovel", false)):
		_cancel_selection()
		return
	# 不可用卡（阳光不足/冷却中）不进入选中态，直接提示原因
	var reason := _card_unavailable_reason(kind)
	if not reason.is_empty():
		AudioFX.play("wrong")
		show_toast(reason)
		return
	battle.selectedSeed = kind
	battle.shovel = false
	battle.aimingCannon = -1
	_play_garden_sound("buttonclick")
	_save_profile("选择植物卡")
	if is_instance_valid(field):
		field.set_battle(battle)


func _card_unavailable_reason(kind: String) -> String:
	if str(battle.get("special", "")) in ["conveyor", "bowling", "vase"]:
		return "" # 传送带/保龄球/砸罐模式的卡不耗阳光、无冷却
	var definition: Dictionary = ContentDB.garden_plants().get(kind, {})
	if int(battle.get("sun", 0)) < int(definition.get("cost", 0)):
		return "阳光不够"
	if float(battle.get("cooldowns", {}).get(kind, 0)) > 0:
		return "还在冷却"
	return ""


func _cancel_selection() -> void:
	# 三条取消路径共用：再点同卡 / 点空白 / 返回键
	if battle.is_empty():
		return
	if str(battle.get("selectedSeed", "")).is_empty() and not bool(battle.get("shovel", false)) and int(battle.get("aimingCannon", -1)) < 0:
		return
	battle.selectedSeed = ""
	battle.shovel = false
	battle.aimingCannon = -1
	AudioFX.play("back")
	if is_instance_valid(field):
		field.set_battle(battle)
	_save_profile("取消选择")

func _battle_cell(row: int, col: int) -> void:
	if battle.is_empty() or battle.get("phase") != "playing" or paused:
		return
	var digging := bool(battle.get("shovel", false))
	var kind := str(battle.get("selectedSeed", ""))
	var result: Dictionary = engine.shovel(battle, row, col) if digging else engine.handle_cell(battle, row, col)
	if bool(result.get("ok", false)):
		_tutorial_action("dig" if digging else "plant", kind)
		AudioFX.play("whoosh" if digging else "plant")
		_play_garden_sound("plant_water" if str(battle.environment) in ["pool", "fog"] and row in [2, 3] else "buttonclick")
	else:
		AudioFX.play("wrong")
		show_toast(str(result.get("reason", "这里不能操作")))
	_process_events(battle.get("events", []))
	battle.events = []
	field.set_battle(battle)
	_save_profile("铲除植物" if digging else "草坪操作")

func _collect_sun(uid: int) -> void:
	var result: Dictionary = engine.collect_sun(battle, uid)
	if bool(result.get("ok", false)):
		AudioFX.play("sun")
		_tutorial_action("sun")
		field.set_battle(battle)
		_update_hud()
		_save_profile("收集阳光")


func _toggle_shovel() -> void:
	battle.shovel = not bool(battle.get("shovel", false))
	battle.aimingCannon = -1
	if bool(battle.get("shovel", false)):
		battle.selectedSeed = ""
	_play_garden_sound("buttonclick")
	if is_instance_valid(field):
		field.set_battle(battle)
	_save_profile("选择铲子")

func _show_selected_plant() -> void:
	var kind := str(battle.get("selectedSeed", ""))
	if kind.is_empty() or not plant_entries.has(kind):
		return
	_show_almanac_detail(plant_entries[kind])


func _cycle_speed() -> void:
	speed = 2 if speed == 1 else 3 if speed == 2 else 1
	if bool(battle.get("tutorial", false)):
		_tutorial_action("speed")
	AudioFX.play("select")
	if is_instance_valid(field):
		field.speed = speed
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
	AudioFX.play("select")
	_save_profile("自动拾取阳光")
	_render_battle()


func _update_hud() -> void:
	if battle.is_empty():
		return
	if is_instance_valid(field):
		field.speed = speed
		field.paused = paused
		field.set_battle(battle)
	if not bool(battle.get("tutorial", false)) and bool(profile_data.get("autoCollectSun", false)):
		for sun in battle.suns.duplicate():
			if not bool(sun.get("collecting", false)):
				engine.collect_sun(battle, int(sun.uid))

func _wave_text() -> String:
	if battle.get("tutorial", false):
		return "花园小课堂 · 跟着下方提示操作"
	var current := int(battle.get("waveIndex", 0))
	var total := int(battle.get("waveCount", 0))
	var flags := int(battle.get("flags", 0))
	if battle.get("mode") == "endless":
		return "无尽模式 · 第 %s 波 · 旗 %s · 最高 %s" % [int(current), int(flags), int(profile_data.get("bestEndless", 0))]
	if int(battle.get("levelId", 0)) == 50:
		return "屋顶决战 · 僵尸博士首领战"
	return "第 %s 关 · 波次 %s / %s · 旗 %s" % [int(battle.get("levelId", 1)), int(current), int(total), int(flags)]


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
		if is_instance_valid(tutorial_label):
			tutorial_label.text = "🎓 小课堂 %s / 8  ·  %s" % [mini(next + 1, 8), TUTORIAL_TEXT[mini(next, TUTORIAL_TEXT.size() - 1)]]
		Speech.speak(TUTORIAL_TEXT[mini(next, TUTORIAL_TEXT.size() - 1)])
		_save_profile("花园小课堂")
		if next >= 8:
			profile_data.tutorialSeen = true
			battle = {}
			_save_profile("花园小课堂完成", false)
			call_deferred("_complete_tutorial")
		elif next in [5, 6]:
			call_deferred("_render_battle")


func _tutorial_mower() -> void:
	if not bool(battle.get("tutorial", false)) or int(battle.get("tutorialStep", 0)) != 5:
		return
	engine.trigger_mower(battle, 2)
	AudioFX.play("mower")
	_tutorial_action("mower")
	field.set_battle(battle)


func _skip_tutorial() -> void:
	if int(battle.get("tutorialStep", 0)) < 3:
		return
	profile_data.tutorialSeen = true
	battle = {}
	_save_profile("跳过花园小课堂")
	_render_home()


func _complete_tutorial() -> void:
	_render_home()
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	content.add_child(PlaygroundUI.label("🎓", 58, accent, 700))
	content.add_child(PlaygroundUI.label("收集阳光、种植、铲除、割草机、暂停和倍速都学会啦。现在可以挑战白天花园了。", 17, PlaygroundUI.INK_SOFT, 500, true))
	open_modal("花园小课堂完成！", content, [
		{"text": "去闯关", "kind": "primary", "callback": func(): _close_top_modal(); _render_levels()},
	], "小花园准备好了")
	AudioFX.play("win")


func _finish_battle() -> void:
	if battle.is_empty() or reported_battle:
		return
	reported_battle = true
	var won: bool = str(battle.get("phase", "")) == "won"
	var stars := int(battle.get("resultStars", 0))
	if won:
		if battle.get("mode") == "endless":
			profile_data.bestEndless = maxi(int(profile_data.get("bestEndless", 0)), int(battle.get("flags", 0)))
		else:
			var level_key := str(battle.get("levelId", 1))
			profile_data.stars[level_key] = maxi(int(profile_data.get("stars", {}).get(level_key, 0)), stars)
		var outcome := "win"
		SaveStore.record_outcome(
			str(players[0].id),
			game_id,
			outcome,
			stars,
			int(battle.get("waveIndex", 0)),
			maxi(1, int(battle.get("waveCount", 1))),
			{"strategy": {"correct": int(battle.get("waveIndex", 0)), "answered": maxi(1, int(battle.get("waveCount", 1)))}},
			str(battle.get("sessionId", ""))
		)
	else:
		SaveStore.record_outcome(str(players[0].id), game_id, "loss", 0, 0, 0, {}, str(battle.get("sessionId", "")))
	profile_data.battle = {}
	_save_profile("战斗结束", false)
	AudioFX.play("win" if won else "wrong")
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	content.add_child(PlaygroundUI.label("🏆" if won else "🌱", 62, accent, 700))
	content.add_child(PlaygroundUI.label("守住了小房子！" if won else "这次没有守住，再来一次就好。", 26, PlaygroundUI.INK, 700, true))
	if won and battle.get("mode") != "endless":
		content.add_child(PlaygroundUI.label("获得 %s 颗星" % stars, 19, Color("#b6861c"), 700))
	if battle.get("mode") == "endless":
		content.add_child(PlaygroundUI.label("到达第 %s 波 · %s 面旗" % [battle.get("waveIndex", 0), battle.get("flags", 0)], 18, PlaygroundUI.INK_SOFT, 700))
	open_modal("战斗结束", content, [
		{"text": "花园首页", "kind": "soft", "callback": func(): _close_top_modal(); battle = {}; _render_home()},
		{"text": "再打一次", "kind": "primary", "callback": func(): _close_top_modal(); _begin_battle(bool(battle.get("tutorial", false)))},
	], "进度已自动保存")


func _render_almanac(tab: String) -> void:
	view = "almanac"
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
	if is_instance_valid(field):
		field.paused = is_paused
		if is_paused:
			field.cancel_interaction() # 暂停时清理悬停与拖拽残留
	_save_profile("暂停" if is_paused else "继续战斗")
	if not is_paused:
		call_deferred("_start_garden_music")

func _confirm_restart() -> void:
	_close_top_modal()
	var tutorial := bool(battle.get("tutorial", false))
	var content := VBoxContainer.new()
	content.add_child(PlaygroundUI.label("当前战斗进度会被本轮替换，儿童档案、星级和植物解锁不会丢失。", 17, PlaygroundUI.INK_SOFT, 500, true))
	var restart := func():
		_close_top_modal()
		paused = false
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
		if not str(battle.get("selectedSeed", "")).is_empty() or bool(battle.get("shovel", false)) or int(battle.get("aimingCannon", -1)) >= 0:
			# 返回键先取消选中/铲子/瞄准，而不是直接弹暂停
			_cancel_selection()
			return
		_save_profile("暂停")
		_confirm_exit()
		return
	_confirm_exit()


func _save_profile(note: String, resume: bool = true) -> void:
	if engine == null or players.is_empty():
		return
	profile_data.battle = engine.snapshot(battle) if not battle.is_empty() and battle.get("phase") == "playing" else {}
	profile_data.speed = speed
	profile_data.view = view
	profile_data.selectedLevel = selected_level
	profile_data.selectedMode = selected_mode
	profile_data.selectedSeeds = selected_seeds.duplicate()
	profile_data.paused = paused
	profile_data.updatedAt = Time.get_unix_time_from_system()
	var note_text := note
	if view == "battle" and not battle.is_empty():
		note_text = "第 %s 关 · 第 %s 波" % [battle.get("levelId", 1), battle.get("waveIndex", 0)] if battle.get("mode") != "endless" else "无尽 · 第 %s 波" % battle.get("waveIndex", 0)
	SaveStore.save_state(game_id, str(players[0].id), profile_data, note_text, resume and not battle.is_empty() and battle.get("phase") == "playing")


func _integer(value: Variant) -> int:
	if value is int:
		return int(value)
	if value is float and is_finite(value):
		return int(value)
	if value is String and value.is_valid_float():
		return int(float(value))
	return 0


func _number(value: Variant, fallback: float) -> float:
	if value is int or value is float:
		return float(value) if is_finite(float(value)) else fallback
	if value is String and value.is_valid_float():
		var parsed := float(value)
		return parsed if is_finite(parsed) else fallback
	return fallback


func _play_garden_sound(name: String) -> void:
	AudioFX.play_file("res://assets/garden/original/" + name + ".mp3")


func _start_garden_music() -> void:
	if paused:
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
	var pause := GardenSurfaces.button("Ⅱ 暂停", accent, toggle_pause, "soft")
	pause.custom_minimum_size = Vector2(108, 48)
	row.add_child(pause)
	bar.add_child(row)
	return bar


func open_modal(title: String, content: Control, actions: Array, eyebrow: String = "", dismissible: bool = true) -> Control:
	if is_instance_valid(field):
		field.set_dialog_open(true) # 弹窗打开期间战场输入静默
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
	if is_instance_valid(field) and _modal_stack.is_empty():
		field.set_dialog_open(false)
