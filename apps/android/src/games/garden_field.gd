class_name GardenField
extends Control

signal cell_pressed(row: int, col: int)
signal sun_pressed(uid: int)
signal coin_pressed(uid: int)
signal seed_pressed(kind: String)
signal shovel_pressed
signal speed_pressed
signal blank_pressed

var state: Dictionary = {}
var art := GardenArt.new()
var backdrop := GardenBackdrop.new()
var render_blend := 1.0
var effects: Array = []
var paused := false
var speed := 1
var hover_cell := Vector2i(-1, -1)
var last_event := 0
var dense_mode := false

# ---- 触摸交互状态（W2：点选 + 拖拽双模式）----
const MOUSE_POINTER := -2
var _press_position := Vector2.ZERO
var _gesture_dragging := false
var _last_touch_msec := -1000
var _pointer_visible := false
var card_reasons: Dictionary = {}
var _card_error_kind := ""
var _card_error_time := 0.0
var _shovel_return := 0.0
var _shovel_return_from := Vector2.ZERO
var shovel_return_requested := false
var can_plant_check := Callable()        # 编排层注入的可种植校验，返回 "" 表示可种
var dialog_open := false                 # 弹窗打开期间战场输入静默
var press_target := ""                   # 按下命中的 HUD 目标："seed:i"/"shovel"/"speed"
var drag_kind := ""                      # 拖拽中的植物卡（空 = 未拖拽）
var drag_pos := Vector2.ZERO             # 拖拽手指位置（棋盘逻辑坐标）
var drag_active := false
var preview_cell := Vector2i(-1, -1)     # 种植预览格
var cell_flash := 0.0                    # 非法格红闪剩余时间
var cell_flash_at := Vector2i(-1, -1)
var ghost_back := 0.0                    # ghost 回弹进度（0 = 无回弹）
var ghost_back_from := Vector2.ZERO
var ghost_back_kind := ""
var _touch_index := -1                   # 当前跟踪的触点（战场为单指操作，多余手指忽略）
var _touch_consumed := false             # 本次按压已被阳光/金币消费，不再参与种植


func _ready() -> void:
	custom_minimum_size = Vector2(720, 430)
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	resized.connect(queue_redraw)
	mouse_exited.connect(func():
		if _touch_index == -1:
			_pointer_visible = false
			hover_cell = Vector2i(-1, -1)
			preview_cell = Vector2i(-1, -1)
			queue_redraw()
	)


func set_battle(next_state: Dictionary, blend: float = 1.0) -> void:
	state = next_state
	render_blend = clampf(blend, 0, 1)
	queue_redraw()


func _process(delta: float) -> void:
	if cell_flash > 0:
		cell_flash = maxf(0, cell_flash - delta)
	if ghost_back > 0:
		ghost_back += delta / .18
		if ghost_back >= 1:
			ghost_back = 0 # 回弹结束，销毁 ghost
	_card_error_time = maxf(0, _card_error_time - delta)
	if shovel_return_requested:
		shovel_return_requested = false
		_shovel_return_from = drag_pos
		_shovel_return = 0.001
	_shovel_return = maxf(0, _shovel_return - delta / .2)
	if not paused or cell_flash > 0 or ghost_back > 0 or _card_error_time > 0 or _shovel_return > 0 or bool(state.get("bannerVisible", false)):
		queue_redraw()


func add_effect(event: Dictionary) -> void:
	if int(event.get("uid", 0)) > 0 and int(event.uid) <= last_event:
		return
	last_event = maxi(last_event, int(event.get("uid", 0)))
	if str(event.get("type", "")) in ["hit", "explode", "plant", "freeze", "fume", "shovel", "vase", "smash", "flag"]:
		effects.append(event.duplicate(true))
	if effects.size() > 36:
		effects = effects.slice(-36)


func _transform() -> Transform2D:
	var layout := GardenLayout.metrics(size)
	var factor := float(layout.scale)
	return Transform2D(Vector2(factor, 0), Vector2(0, factor), layout.origin)


func _draw() -> void:
	if state.is_empty():
		return
	draw_set_transform_matrix(Transform2D.IDENTITY)
	var scenery := str(ContentDB.garden_presentation.get("scenes", {}).get(str(state.environment), "hd4/scenery/day.webp"))
	var transform := _transform()
	var backdrop_image := art.texture(scenery)
	if backdrop_image != null:
		var edge := maxf(0, transform.origin.x)
		draw_texture_rect_region(backdrop_image, Rect2(0, 0, edge + 1, size.y), Rect2(0, 0, 160, backdrop_image.get_height()))
		draw_texture_rect_region(backdrop_image, Rect2(size.x - edge - 1, 0, edge + 1, size.y), Rect2(backdrop_image.get_width() - 160, 0, 160, backdrop_image.get_height()))
	draw_set_transform_matrix(transform)
	backdrop.draw_scene(self, state, art)
	# 有种植预览时由 _draw_preview 接管格子高亮；铲子模式保留黄色悬停
	if _preview_kind().is_empty() and hover_cell.x >= 0 and hover_cell.x < 9 and hover_cell.y in state.get("activeRows", []):
		draw_colored_polygon(GardenLayout.cell_polygon(state, hover_cell.y, hover_cell.x), Color(1, .96, .65, .18))
	var actors: Array = []
	for layer in ["bases", "grid", "shells"]:
		for plant in state.get(layer, []):
			if not plant.is_empty():
				actors.append({"type": "plant", "layer": layer, "object": plant, "order": int(plant.row) * 100 + (5 if layer == "bases" else 18 if layer == "shells" else 10)})
	for zombie in state.get("zombies", []):
		actors.append({"type": "zombie", "object": zombie, "order": int(zombie.row) * 100 + 20})
	for corpse in state.get("deaths", []):
		actors.append({"type": "corpse", "object": corpse, "order": int(corpse.row) * 100 + 21})
	dense_mode = actors.size() > 40
	actors.sort_custom(func(left, right): return int(left.order) < int(right.order))
	for actor in actors:
		draw_set_transform_matrix(transform)
		match str(actor.type):
			"plant":
				_draw_plant(actor.object, str(actor.layer), transform)
			"zombie":
				_draw_zombie(actor.object, transform)
			"corpse":
				_draw_corpse(actor.object, transform)
	draw_set_transform_matrix(transform)
	_draw_mowers(transform)
	_draw_projectiles(transform)
	_draw_debris(transform)
	_draw_vases()
	_draw_collectibles(transform)
	_draw_effects(transform)
	_draw_boss(transform)
	_draw_fog()
	_draw_intro()
	_draw_preview(transform)
	_draw_battle_banner()
	_draw_hud()
	_draw_ghost(transform)
	draw_set_transform_matrix(Transform2D.IDENTITY)


func _shadow(anchor: Vector2, width: float = 30, opacity: float = .16) -> void:
	var polygon := PackedVector2Array()
	for index in 24:
		var angle := TAU * float(index) / 24
		polygon.append(anchor + Vector2(cos(angle) * width, sin(angle) * width * .22))
	draw_colored_polygon(polygon, Color(0, 0, 0, opacity))


func plant_clip(plant: Dictionary) -> String:
	var kind := str(plant.kind)
	var phase := str(plant.get("phase", "idle"))
	var ratio := float(plant.health) / maxf(1, float(plant.maxHealth))
	if kind in ["wallnut", "tallnut", "pumpkin", "garlic"] and ratio < 2.0 / 3.0:
		return kind + ("-cracked2" if ratio < 1.0 / 3.0 else "-cracked1")
	if kind == "potatomine" and phase == "unarmed":
		return "potatomine-unarmed"
	if kind == "chomper":
		return "chomper-digest" if phase == "digest" else "chomper-bite" if phase == "bite" else "chomper"
	if kind == "sunshroom" and float(plant.age) > 120:
		return "sunshroom-big"
	if kind == "scaredyshroom" and phase == "scared":
		return "scaredyshroom-scared"
	if kind == "cactus" and bool(plant.get("tall", false)):
		return "cactus-tall"
	if kind == "tanglekelp" and phase == "attack":
		return "tanglekelp-grab"
	if kind == "squash" and phase == "attack":
		return "squash-attack"
	if kind == "cobcannon" and float(plant.attackTimer) > 0:
		return "cobcannon-attack" if float(state.time) - float(plant.shotAt) < 3.5 else "cobcannon-charge" if float(plant.attackTimer) < 1.25 else "cobcannon-unarmed"
	if kind == "blover" and float(plant.age) > .5:
		return "blover-loop"
	if float(state.time) - float(plant.get("shotAt", -10)) < .65:
		var attack := kind + ("-block" if kind == "umbrella" else "-attack")
		if art.has_clip(attack):
			return attack
	return kind


func _draw_plant(plant: Dictionary, layer: String, transform: Transform2D) -> void:
	var kind := str(plant.kind)
	var anchor := GardenLayout.plant_anchor(state, plant)
	if layer == "grid":
		_shadow(GardenLayout.cell_foot(state, int(plant.row), int(plant.col)), 29 if kind != "cobcannon" else 62)
	var clock := float(plant.age) + float(plant.uid) * .31
	var tint := Color.WHITE
	var sleeping: bool = kind in ContentDB.garden_rules.get("mushrooms", []) and str(state.environment) in ["day", "pool", "roof"] and not bool(plant.awake)
	if sleeping:
		clock = 0
		tint = Color("#d6d7cd")
	if float(state.time) - float(plant.hitAt) < .12:
		tint = Color(1.5, 1.5, 1.5)
	if bool(state.get("shovel", false)) and _shovel_target().get("uid", -1) == plant.uid:
		tint = Color(1.6, 1.6, 1.3)
	elif not _preview_kind().is_empty() and ContentDB.garden_rules.get("upgrades", {}).has(_preview_kind()) and _can_check(Vector2i(int(plant.col), int(plant.row)), _preview_kind()).is_empty():
		var glow := 1.15 + .3 * sin(float(state.time) * 6)
		tint = Color(glow, glow, 1.0)
	var clip := plant_clip(plant)
	var once := clip.ends_with("-attack") or clip in ["chomper-bite", "umbrella-block", "tanglekelp-grab", "squash-attack"]
	if once:
		clock = float(plant.actionAge) if str(plant.phase) in ["attack", "bite"] else maxf(0, float(state.time) - float(plant.shotAt))
	art.draw_actor(self, clip, clock, anchor, transform, tint, not once, {"attackClock": float(state.time) - float(plant.shotAt)}, dense_mode)
	if sleeping:
		_text("z", anchor + Vector2(15, -48), 13, Color("#eff4ff"))


func swimming(zombie: Dictionary) -> bool:
	if str(state.environment) not in ["pool", "fog"] or int(zombie.get("row", -1)) not in [2, 3]:
		return false
	var x := float(zombie.get("x", 0))
	return x > .1 and x < 8.85 and not bool(zombie.get("flying", false))


func zombie_clip(zombie: Dictionary) -> String:
	var kind := str(zombie.kind)
	var phase := str(zombie.get("phase", "walk"))
	var action := "eat" if bool(zombie.get("eating", false)) else "walk"
	if kind not in ["snorkel", "dolphin", "balloon", "bungee", "digger", "imp"] and swimming(zombie) and kind in ["normal", "flag", "cone", "bucket", "newspaper", "door", "ducky"]:
		return ("ducky3" if kind == "bucket" and float(zombie.armor) > 0 else "ducky2" if kind == "cone" and float(zombie.armor) > 0 else "ducky1") + "-" + action
	if not bool(zombie.get("hasHead", true)):
		return kind + "-headless" if art.has_clip(kind + "-headless") else "zombie-headless"
	if kind == "ducky":
		return "zombie-" + action
	if kind == "normal":
		return "zombie-" + action
	if kind in ["cone", "bucket", "football"]:
		return (kind if float(zombie.armor) > 0 else "football-bare" if kind == "football" else "zombie") + "-" + action
	if kind == "door":
		return ("door" if float(zombie.shield) > 0 else "zombie") + "-" + action
	if kind == "newspaper":
		return "newspaper-gasp" if phase == "rage" else ("newspaper-mad" if float(zombie.shield) <= 0 else "newspaper") + "-" + action
	if kind == "pole":
		return "pole-jump" if phase == "jump" else "pole-" + ("run" if bool(zombie.hasPole) and action == "walk" else action)
	if kind == "digger":
		return "digger-" + ("dig" if bool(zombie.underground) else "rise" if phase == "rise" else action)
	if kind == "pogo":
		return "pogo-" + ("bounce" if bool(zombie.hasPogo) else action)
	if kind == "ladder":
		return "ladder-place" if phase == "place" else "ladder-bare" if float(zombie.shield) <= 0 else "ladder-" + action
	if kind == "bungee":
		return "bungee-drop" if phase == "down" else "bungee-idle"
	if kind == "balloon":
		return "balloon-fly" if bool(zombie.flying) else "balloon-pop" if phase == "land" else "balloon-" + action
	if kind == "dolphin":
		return "dolphin-jump" if phase == "jump" else "dolphin-eat" if action == "eat" else "dolphin-ride" if bool(zombie.hasDolphin) else "dolphin-swim"
	if kind == "snorkel":
		return "snorkel-eat" if action == "eat" else "snorkel-swim" if float(zombie.x) < 9 else "snorkel-walk"
	if kind == "dancer" and phase == "summon" and float(zombie.actionAge) < 2:
		return "dancer-summon"
	if kind == "catapult":
		return "catapult-shoot" if phase == "shoot" and float(zombie.actionAge) < 1.5 else "catapult-idle" if float(zombie.x) < 8.6 else "catapult-walk"
	if kind == "zomboni":
		return "zomboni-critical" if float(zombie.health) < float(zombie.maxHealth) / 3 else "zomboni-damaged" if float(zombie.health) < float(zombie.maxHealth) * 2 / 3 else "zomboni-walk"
	if kind == "gargantuar":
		return "gargantuar-" + (phase if phase in ["smash", "throw"] else "walk")
	if kind == "imp" and phase in ["thrown", "land"]:
		return "imp-" + phase
	if kind == "jack" and float(zombie.specialTimer) < 1.1:
		return "jack-open"
	return kind + "-" + action


func _draw_zombie(zombie: Dictionary, transform: Transform2D) -> void:
	var column := lerpf(float(zombie.get("previousX", zombie.x)), float(zombie.x), render_blend)
	var anchor := GardenLayout.foot(state, int(zombie.row), column)
	var scale_factor := .5 if bool(zombie.get("mini", false)) else 1.0
	if not swimming(zombie):
		_shadow(anchor, 25 * scale_factor, .14)
	if str(zombie.kind) == "bobsled" and bool(zombie.get("sledActive", false)) and int(zombie.get("sledUid", -1)) == int(zombie.uid):
		art.draw_image(self, "original/sled.webp", Rect2(anchor - Vector2(35, 25), Vector2(170, 40)), Color.WHITE, true)
	if str(zombie.phase) in ["jump", "thrown"]:
		anchor.y -= sin(clampf(float(zombie.actionAge) / (2.0 if str(zombie.phase) == "thrown" else 1.0), 0, 1) * PI) * 75
	if str(zombie.kind) == "bungee":
		anchor.y -= maxf(0, 1 - float(zombie.actionAge) / 2) * 400 if str(zombie.phase) == "down" else minf(1, float(zombie.actionAge) / 2) * 400 if str(zombie.phase) == "up" else 0
		var cord := Vector2(anchor.x, 0)
		draw_line(cord, anchor - Vector2(0, 100), Color("#ddd2b2"), 2)
	var tint := Color("#b7d8ff") if float(zombie.frozenTimer) > 0 or float(zombie.slowTimer) > 0 else Color("#d8a9ed") if bool(zombie.hypnotized) else Color.WHITE
	if float(state.time) - float(zombie.hitAt) < .1:
		tint = Color(1.45, 1.45, 1.45)
	var facing := -1.0 if bool(zombie.backwards) or bool(zombie.hypnotized) else 1.0
	var actor_transform := transform * Transform2D(Vector2(scale_factor * facing, 0), Vector2(0, scale_factor), anchor)
	var clock := float(zombie.actionAge) if str(zombie.phase) in ["jump", "rise", "thrown", "place", "smash", "throw", "rage", "down", "open"] else float(zombie.animationTime)
	art.draw_actor(self, zombie_clip(zombie), clock, Vector2.ZERO, actor_transform, tint, str(zombie.phase) not in ["jump", "rise", "thrown", "place", "smash", "throw", "rage", "open"], zombie, dense_mode)
	draw_set_transform_matrix(transform)
	if float(zombie.butterTimer) > 0:
		art.draw_image(self, "original/butter.webp", Rect2(anchor - Vector2(18, 125), Vector2(36, 28)), Color.WHITE, true)
	if swimming(zombie):
		draw_arc(anchor + Vector2(0, 2), 27, 0, PI, 18, Color(.72, .96, 1, .38), 2, true)
		draw_arc(anchor + Vector2(0, 5), 36, 0, PI, 18, Color(.72, .96, 1, .16), 1.5, true)


func _draw_corpse(corpse: Dictionary, transform: Transform2D) -> void:
	var reason := str(corpse.reason)
	var clip := str(corpse.kind) + "-die"
	if reason in ["burn", "fire", "explode"]:
		clip = str(corpse.kind) + "-burn" if art.has_clip(str(corpse.kind) + "-burn") else "zombie-burn"
	elif not art.has_clip(clip):
		clip = "zombie-die"
	var anchor := GardenLayout.foot(state, int(corpse.row), float(corpse.x))
	var opacity := clampf((2.2 - float(corpse.age)) / .5, 0, 1)
	art.draw_actor(self, clip, float(corpse.age), anchor, transform, Color(1, 1, 1, opacity), false, corpse)


func _draw_mowers(transform: Transform2D) -> void:
	for mower in state.get("mowers", []):
		if str(mower.state) == "spent":
			continue
		var position := GardenLayout.foot(state, int(mower.row), lerpf(float(mower.previousX), float(mower.x), render_blend))
		var moving := str(mower.state) == "moving"
		if moving:
			position.y += sin(float(mower.age) * 75) * 1.2
		var environment := str(state.environment)
		var pool_row := environment in ["pool", "fog"] and int(mower.row) in [2, 3]
		var path := "original/roof-cleaner.webp" if environment == "roof" else "original/pool-cleaner.webp" if pool_row else "original/mower.webp"
		var dimensions := Vector2(55, 41) if environment == "roof" else Vector2(44, 60) if pool_row else Vector2(50, 41)
		_shadow(position + Vector2(0, -2), dimensions.x * .48, .2)
		art.draw_image(self, path, Rect2(position + Vector2(-dimensions.x * .5, 4 - dimensions.y), dimensions), Color.WHITE, false)
		if moving:
			for wheel_offset in [Vector2(-dimensions.x * .21, 1), Vector2(dimensions.x * .31, 1)]:
				var wheel: Vector2 = position + wheel_offset
				var spoke := Vector2.from_angle(float(mower.age) * 24) * 3
				draw_line(wheel - spoke, wheel + spoke, Color("#aaa59b"), 1.3, true)
			for offset in 3:
				draw_line(position - Vector2(30 + offset * 5, 2 - offset * 3), position - Vector2(40 + offset * 6, -5 - offset * 3), Color(.4, .5, .2, .45), 2)
	draw_set_transform_matrix(transform)


func _draw_projectiles(transform: Transform2D) -> void:
	var paths := {"pea": "pea.webp", "ice": "original/snow-pea.webp", "fire": "original/fire-pea.webp", "puff": "original/puff.webp", "spike": "original/spike.webp", "homing": "original/spike.webp", "star": "original/star.webp", "cabbage": "original/cabbage.webp", "kernel": "original/kernel.webp", "butter": "original/butter.webp", "melon": "original/melon.webp", "wintermelon": "original/wintermelon-projectile.webp", "basketball": "original/basketball.webp", "cannon": "original/cannon-projectile.webp"}
	for projectile in state.get("projectiles", []):
		var position := GardenLayout.point(state, lerpf(float(projectile.previousX), float(projectile.x), render_blend), lerpf(float(projectile.previousY), float(projectile.y), render_blend))
		var kind := str(projectile.kind)
		var dimensions := Vector2(36, 36) if kind in ["melon", "wintermelon", "cannon"] else Vector2(25, 25) if bool(projectile.lob) else Vector2(18, 18)
		art.draw_image(self, str(paths.get(kind, "pea.webp")), Rect2(position - dimensions * .5, dimensions), Color.WHITE, true)
	for roller in state.get("rollers", []):
		var anchor := GardenLayout.foot(state, int(roller.row), float(roller.x))
		var local := transform * Transform2D(float(roller.age) * 5, anchor - Vector2(0, 28))
		art.draw_actor(self, "wallnut", float(roller.age), Vector2(0, 32), local, Color("#ff8c6a") if str(roller.kind) == "explodenut" else Color.WHITE)
	draw_set_transform_matrix(transform)


func _draw_debris(transform: Transform2D) -> void:
	for part in state.get("debris", []):
		var age := float(part.age)
		var position := GardenLayout.foot(state, int(part.row), float(part.x))
		position += Vector2(age * 24, -100 + age * -65 + age * age * 100)
		position.y = minf(position.y, GardenLayout.foot(state, int(part.row), float(part.x)).y)
		art.draw_part(self, "zombie-walk", str(part.part), position, transform, age * 3, Color(1, 1, 1, clampf((1.8 - age) * 2, 0, 1)))


func _draw_vases() -> void:
	for vase in state.get("vases", []):
		var position := GardenLayout.foot(state, int(vase.row), float(vase.col) + .5)
		var image := art.texture("original/vases.webp")
		if image != null:
			var region := Rect2(0, 0, image.get_width() / 4.0, image.get_height())
			draw_texture_rect_region(image, Rect2(position - Vector2(30, 70), Vector2(60, 75)), region, Color("#9ee39a") if bool(vase.green) else Color.WHITE)


func _draw_collectibles(transform: Transform2D) -> void:
	for sun in state.get("suns", []):
		var position := GardenLayout.point(state, float(sun.x) + .5, float(sun.y) + .2)
		var factor := .6 * clampf(float(sun.value) / 25.0, .6, 1.5)
		var opacity := clampf(float(sun.ttl), 0, 1)
		if bool(sun.collecting):
			var progress := clampf(float(sun.collectAge) / .35, 0, 1)
			var start := Vector2(float(sun.get("collectX", position.x)), float(sun.get("collectY", position.y)))
			position = start.lerp(Vector2(37, 38), 1 - pow(1 - progress, 2))
			factor *= 1 - progress * .4
			opacity = 1 - progress * progress
		var local := transform * Transform2D(Vector2(factor, 0), Vector2(0, factor), position)
		art.draw_actor(self, "sun", float(sun.age), Vector2.ZERO, local, Color(1, 1, 1, opacity))
	draw_set_transform_matrix(transform)
	for coin in state.get("coins", []):
		var position := GardenLayout.foot(state, int(coin.row), float(coin.x)) - Vector2(0, 8 + absf(sin(float(coin.age) * 4)) * 8)
		art.draw_image(self, "original/coin-gold.webp", Rect2(position - Vector2(13, 20), Vector2(26, 30)), Color.WHITE, true)
	draw_set_transform_matrix(transform)


func _draw_effects(transform: Transform2D) -> void:
	var current := float(state.time)
	for effect in effects:
		var age := current - float(effect.get("time", 0))
		if age < 0 or age > 1:
			continue
		var kind := str(effect.get("type", ""))
		var position := GardenLayout.foot(state, int(effect.get("row", 0)), float(effect.get("col", 0)) + (.5 if kind == "plant" else 0))
		if kind == "flag":
			continue
		elif kind == "plant" or kind == "shovel":
			for index in 5:
				var offset := Vector2(sin(index * 2.4) * age * 32, -sin(age * PI) * 18)
				draw_circle(position + offset, 2.8 * (1 - age), Color("#705132"))
		elif kind == "hit" and age < .18:
			position.y -= 65
			for index in 4:
				var angle := float(index) * TAU / 4
				draw_line(position + Vector2.from_angle(angle) * 3, position + Vector2.from_angle(angle) * (9 + age * 25), Color(1, 1, .7, 1 - age * 5), 2)
		elif kind == "explode" or kind == "smash":
			position.y -= 35
			var points := PackedVector2Array()
			for index in 24:
				var angle := float(index) * TAU / 24
				points.append(position + Vector2.from_angle(angle) * (75 if index % 2 == 0 else 42) * minf(1, age * 8 + .2))
			draw_colored_polygon(points, Color(1, .72, .18, maxf(0, 1 - age * 1.5)))
		elif kind == "fume":
			art.draw_actor(self, "fume-cloud", age, position + Vector2(70, -45), transform, Color(1, 1, 1, 1 - age), false)
		elif kind == "freeze" and age < .4:
			draw_rect(Rect2(40, 80, 720, 500), Color(.6, .8, 1, .15 * (1 - age / .4)))
	draw_set_transform_matrix(transform)


func _draw_boss(transform: Transform2D) -> void:
	var boss: Dictionary = state.get("boss", {})
	if boss.is_empty():
		return
	art.draw_boss(self, state, transform)
	draw_set_transform_matrix(transform)


func _draw_fog() -> void:
	if str(state.environment) != "fog" or float(state.get("fogCleared", 0)) > 0:
		return
	for column in range(5, 10):
		for row in int(state.rows):
			var lit := false
			for plant in state.grid:
				if not plant.is_empty() and str(plant.kind) == "plantern" and absi(int(plant.row) - row) <= 1 and absi(int(plant.col) - column) <= 1:
					lit = true
			if not lit:
				var position := GardenLayout.foot(state, row, float(column) + .5) + Vector2(sin(float(state.time) * .3 + row) * 9, -40)
				var fog := art.texture("original/fog-cloud.webp")
				if fog != null:
					var frame := int(float(state.time) * 2 + row + column) % 8
					var region := Rect2(float(frame) * fog.get_width() / 8.0, 0, fog.get_width() / 8.0, fog.get_height())
					draw_texture_rect_region(fog, Rect2(position - Vector2(70, 65), Vector2(140, 140)), region, Color(1, 1, 1, .38))
	if int(state.levelId) == 40 and float(state.lightning) <= 0:
		draw_rect(Rect2(0, 75, 800, 525), Color(0, .02, .05, .35))


func _draw_hud() -> void:
	var cards: Array = state.seeds if str(state.special) == "lawn" or str(state.special) == "whack" else state.packets.map(func(packet): return str(packet.kind))
	var width := minf(690, 94 + maxi(6, cards.size()) * 52)
	var bank := art.texture("original/seedbank.webp")
	if bank != null:
		draw_texture_rect_region(bank, Rect2(5, 4, 60, 72), Rect2(0, 0, 145, 174))
		draw_texture_rect_region(bank, Rect2(65, 4, width - 70, 72), Rect2(145, 0, 720, 174))
		draw_texture_rect_region(bank, Rect2(width - 5, 4, 10, 72), Rect2(865, 0, 27, 174))
	_text(str(int(state.sun)), Vector2(15, 66), 21, Color("#352716"))
	for index in mini(cards.size(), 10):
		_draw_card(str(cards[index]), index)
	var shovel_rect := Rect2(718, 10, 56, 55)
	var speed_rect := Rect2(660, 12, 48, 48)
	if press_target == "shovel":
		shovel_rect.position += Vector2(0, 2) # 按压下沉 2px
	if press_target == "speed":
		speed_rect.position += Vector2(0, 2)
	draw_style_box(PlaygroundUI.style(Color("#b99c66") if not bool(state.shovel) else Color("#ffe7a0"), 5, Color("#5d431f"), 2), shovel_rect)
	if not bool(state.shovel) and _shovel_return <= 0:
		art.draw_image(self, "original/shovel.webp", shovel_rect.grow(-4), Color.WHITE, true)
	if press_target == "shovel":
		draw_rect(shovel_rect, Color(0, 0, 0, .1))
	draw_style_box(PlaygroundUI.style(Color("#e7d2a1"), 6, Color("#5e4726"), 2), speed_rect)
	_text(str(speed) + "×", speed_rect.position + Vector2(6, 32), 19, Color("#4d3421"))
	if press_target == "speed":
		draw_rect(speed_rect, Color(0, 0, 0, .1))
	art.draw_image(self, "original/meter-empty.webp", Rect2(570, 574, 205, 20))
	var progress := clampf(float(state.waveIndex) / maxf(1, float(state.waveCount)), 0, 1) if state.boss.is_empty() else clampf(1 - float(state.boss.health) / float(state.boss.maxHealth), 0, 1)
	if state.boss.is_empty() and state.has("waveProgressAt") and float(state.get("waveDuration", 0.0)) > 0.0:
		progress = clampf(float(state.waveProgressAt), 0.0, 1.0)
	if progress > 0:
		art.draw_image(self, "original/meter-full.webp", Rect2(570, 574, 205 * progress, 20))
	art.draw_image(self, "original/meter-head.webp", Rect2(565 + 195 * progress, 565, 25, 30), Color.WHITE, true)
	_text("第 %s 关" % int(state.levelId), Vector2(450, 590), 15, Color("#fff3cd"))
	if int(state.get("aimingCannon", -1)) >= 0:
		_text("点草坪选择炮击位置", Vector2(280, 96), 18, Color("#fff3b2"))


func start_shovel_return() -> void:
	shovel_return_requested = true


func _draw_card(kind: String, index: int) -> void:
	var rect := GardenLayout.seed_rect(index)
	if kind == _card_error_kind and _card_error_time > 0:
		rect.position.x += sin((.24 - _card_error_time) * TAU / .06) * 4
	var definition: Dictionary = ContentDB.garden_plants().get(kind, {})
	# 卡片四态：READY / NO_SUN / COOLING / SELECTED
	var status := _card_status(kind)
	var selected := status == "selected"
	if selected:
		# 选中卡浮起：放大 1.10 + 上浮 6px + 亮色描边与外发光
		rect = Rect2(rect.get_center() - rect.size * .55 + Vector2(0, -6), rect.size * 1.1)
	var pressed := press_target == "seed:%d" % index
	if pressed:
		rect.position += Vector2(0, 2) # 按压下沉 2px
	if selected:
		draw_rect(rect.grow(2.5), Color(.96, 1, .55, .4), false, 4)
	draw_style_box(PlaygroundUI.style(Color("#ead7aa"), 3, Color("#f6ff8c") if selected else Color("#59422b"), 3 if selected else 1), rect)
	var card_path := "original/card-" + kind + ".webp"
	var card_image: Texture2D = art.texture(card_path) if ResourceLoader.exists(GardenArt.ROOT + card_path) else null
	# Landscape card sheets contain the colored face above the disabled face.
	var state_sheet := card_image != null and card_image.get_width() > card_image.get_height() * .75
	if card_image != null and not state_sheet:
		art.draw_image(self, card_path, rect.grow(-2))
	else:
		var portrait_rect := Rect2(rect.position + Vector2(4, 2), Vector2(40, 40))
		if state_sheet:
			var region := Rect2(0, 0, card_image.get_width(), card_image.get_height() * .5)
			var dimensions := region.size * minf(portrait_rect.size.x / region.size.x, portrait_rect.size.y / region.size.y)
			draw_texture_rect_region(card_image, Rect2(portrait_rect.get_center() - dimensions * .5, dimensions), region)
		else:
			var portrait := ""
			for entry in ContentDB.garden.get("plantAlmanac", []):
				if str(entry.id) == kind:
					portrait = str(entry.image)
			if not portrait.is_empty():
				art.draw_image(self, portrait, portrait_rect, Color.WHITE, true)
		_text(str(definition.get("name", kind)), rect.position + Vector2(2, 48), 9, Color("#322414"))
		# 阳光不足时阳光数变红
		_text(str(int(definition.get("cost", 0))), rect.position + Vector2(13, 61), 11, Color("#c8342a") if status == "no_sun" else Color("#322414"))
	if status in ["no_sun", "disabled"]:
		draw_rect(rect, Color(0, 0, 0, .35))
	if status == "disabled":
		_text("先种前置", rect.position + Vector2(2, 31), 10, Color.WHITE)
	if selected:
		_text("已选", rect.position + Vector2(12, 16), 11, Color("#245a2e"))
	var cooldown := 0.0 if _free_cards() else float(state.cooldowns.get(kind, 0))
	var total := float(ContentDB.garden_rules.get("plants", {}).get(kind, {}).get("cooldownSeconds", 7.5))
	if cooldown > 0:
		draw_rect(Rect2(rect.position, Vector2(rect.size.x, rect.size.y * clampf(cooldown / maxf(.1, total), 0, 1))), Color(.06, .08, .07, .6))
		# 冷却剩余秒数
		var seconds := str(maxi(1, int(ceil(cooldown))))
		_text(seconds, rect.position + Vector2(rect.size.x * .5 - 5.0 * seconds.length(), rect.size.y * .5 + 7), 18, Color("#ffffff"))
	if pressed:
		draw_rect(rect, Color(0, 0, 0, .1))


func _text(value: String, position: Vector2, font_size: int, tint: Color) -> void:
	draw_string(PlaygroundUI.font(), position, value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, tint)


# ---- 种植预览与拖拽 ghost（自绘，与战场同一套变换）----

func _draw_preview(transform: Transform2D) -> void:
	var kind := _preview_kind()
	if not kind.is_empty() and _cell_valid(preview_cell):
		var polygon := GardenLayout.cell_polygon(state, preview_cell.y, preview_cell.x)
		var outline := polygon + PackedVector2Array([polygon[0]])
		if _can_check(preview_cell, kind).is_empty():
			# 可种：绿色亮格框 + 半透明植物投影
			draw_colored_polygon(polygon, Color(.35, 1, .45, .16))
			draw_polyline(outline, Color(.45, 1, .5, .85), 2.5, true)
			var anchor := GardenLayout.plant_anchor(state, {"row": preview_cell.y, "col": preview_cell.x, "kind": kind})
			art.draw_actor(self, _preview_clip(kind), 0, anchor, transform, Color(1, 1, 1, .45), true, {}, dense_mode)
			draw_set_transform_matrix(transform)
		else:
			# 不可种：红色暗格框，不画投影
			draw_colored_polygon(polygon, Color(1, .18, .12, .25))
			draw_polyline(outline, Color(1, .32, .22, .75), 2.5, true)
	if int(state.get("aimingCannon", -1)) >= 0 and _cell_valid(preview_cell):
		var target := GardenLayout.cell_center(state, preview_cell.y, preview_cell.x)
		draw_arc(target, 25, 0, TAU, 40, Color("#ff6651"), 3, true)
		draw_line(target - Vector2(35, 0), target + Vector2(35, 0), Color("#ffefb5"), 2)
		draw_line(target - Vector2(0, 35), target + Vector2(0, 35), Color("#ffefb5"), 2)
	var shovel_plant := _shovel_target()
	if not shovel_plant.is_empty():
		var target_cell := GardenLayout.cell_polygon(state, int(shovel_plant.row), int(shovel_plant.col))
		draw_polyline(target_cell + PackedVector2Array([target_cell[0]]), Color("#fff4a8"), 3, true)
	# 非法操作红闪反馈（不取消选中，防误触）
	if cell_flash > 0 and _cell_valid(cell_flash_at):
		var flash := GardenLayout.cell_polygon(state, cell_flash_at.y, cell_flash_at.x)
		draw_polyline(flash + PackedVector2Array([flash[0]]), Color(1, .25, .15, .4 + .6 * absf(sin(cell_flash * 22))), 3.5, true)


func _draw_battle_banner() -> void:
	if not bool(state.get("bannerVisible", false)):
		return
	var banner: Dictionary = state.get("banner", {})
	var age := clampf(float(banner.get("age", 0.0)), 0.0, 1.0)
	var alpha := 1.0 if age < 0.8 else clampf((1.0 - age) / 0.2, 0.0, 1.0)
	var text := str(banner.get("text", ""))
	var font := PlaygroundUI.font()
	var font_size := 30
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string(font, (size.x - width) * 0.5, size.y * 0.44, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color("#c73425", alpha))


func _draw_intro() -> void:
	if int(state.get("introStep", -1)) < 0:
		return
	var texts := ["准备", "放置", "开始"]
	var step := clampi(int(state.introStep), 0, 2)
	var age := clampf(float(state.introAge), 0.0, 1.0)
	var font := PlaygroundUI.font()
	var text := str(texts[step])
	var font_size := 44
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string(font, (size.x - width) * 0.5, size.y * 0.38, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color("#fff3b2", 1.0 - age * 0.4))


func _draw_ghost(transform: Transform2D) -> void:
	if dialog_open or paused:
		return
	var kind := _preview_kind()
	if bool(state.get("shovel", false)) and _pointer_visible:
		art.draw_image(self, "original/shovel.webp", Rect2(drag_pos - Vector2(18, 60), Vector2(52, 64)), Color.WHITE, true)
	elif _shovel_return > 0:
		var target := _shovel_return_from.lerp(Vector2(746, 38), 1 - _shovel_return * _shovel_return)
		art.draw_image(self, "original/shovel.webp", Rect2(target - Vector2(26, 32), Vector2(52, 64)), Color.WHITE, true)
	elif _pointer_visible and not kind.is_empty():
		var anchor := drag_pos + Vector2(0, -12)
		var local := transform * Transform2D(Vector2(1.1, 0), Vector2(0, 1.1), anchor)
		art.draw_actor(self, _preview_clip(kind), 0, Vector2.ZERO, local, Color(1, 1, 1, .85), true, {}, dense_mode)
		draw_set_transform_matrix(transform)
	elif ghost_back > 0 and ghost_back < 1:
		# 取消种植：ghost 回弹到卡槽后销毁
		var t := 1.0 - pow(1.0 - ghost_back, 2.0)
		var anchor := ghost_back_from.lerp(_card_home(ghost_back_kind), t) + Vector2(0, -30)
		var local := transform * Transform2D(Vector2(1.1, 0), Vector2(0, 1.1), anchor)
		art.draw_actor(self, _preview_clip(ghost_back_kind), 0, Vector2.ZERO, local, Color(1, 1, 1, .55 * (1 - ghost_back)), true, {}, dense_mode)
		draw_set_transform_matrix(transform)


# ---- 输入层：_input 全程跟踪触点（拖拽移出控件也能收到），_gui_input 只留桌面悬停 ----

func _input(event: InputEvent) -> void:
	# Godot 的鼠标模拟触摸、触摸模拟鼠标均标记为 -1；只处理原始设备事件。
	if event.device == -1:
		return
	if not is_visible_in_tree() or is_queued_for_deletion() or _input_silenced():
		if _touch_index != -1:
			cancel_interaction()
		return
	if event is InputEventScreenTouch:
		_last_touch_msec = Time.get_ticks_msec()
		if event.canceled:
			if event.index == _touch_index:
				cancel_interaction()
		elif event.pressed:
			if _touch_index == -1 and _contains_screen(event.position):
				_touch_down(event.index, event.position)
		elif event.index == _touch_index:
			_release_pointer(event.position, event.index)
		if _contains_screen(event.position) or event.index == _touch_index:
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		_last_touch_msec = Time.get_ticks_msec()
		if event.index == _touch_index:
			_move_pointer(event.position, event.index)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		if Time.get_ticks_msec() - _last_touch_msec < 250:
			return
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			cancel_interaction()
			blank_pressed.emit()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed and _touch_index == -1 and _contains_screen(event.position):
				_touch_down(MOUSE_POINTER, event.position)
				get_viewport().set_input_as_handled()
			elif not event.pressed and _touch_index == MOUSE_POINTER:
				_release_pointer(event.position, MOUSE_POINTER)
				get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _touch_index == MOUSE_POINTER:
		_move_pointer(event.position, MOUSE_POINTER)
		get_viewport().set_input_as_handled()


func _gui_input(event: InputEvent) -> void:
	if _input_silenced() or event.device == -1:
		return
	if event is InputEventMouseMotion and _touch_index == -1 and Time.get_ticks_msec() - _last_touch_msec >= 250:
		drag_pos = _transform().affine_inverse() * event.position
		_pointer_visible = true
		var cell := GardenLayout.cell_at(state, drag_pos)
		hover_cell = cell
		preview_cell = cell if _cell_valid(cell) else Vector2i(-1, -1)
		queue_redraw()


func _contains_screen(screen_pos: Vector2) -> bool:
	return Rect2(Vector2.ZERO, size).has_point(get_global_transform_with_canvas().affine_inverse() * screen_pos)


func _move_pointer(screen_pos: Vector2, index: int) -> void:
	if not _gesture_dragging and _board_from_screen(screen_pos).distance_to(_board_from_screen(_press_position)) >= 24:
		_gesture_dragging = true
		_on_drag_start(_press_position, index)
	_on_drag_move(screen_pos, Vector2.ZERO, index)


func _release_pointer(screen_pos: Vector2, index: int) -> void:
	_move_pointer(screen_pos, index)
	if not _contains_screen(screen_pos):
		if drag_active:
			_start_ghost_return(drag_kind, _board_from_screen(screen_pos))
		blank_pressed.emit()
	elif _gesture_dragging:
		_on_drag_end(screen_pos, index)
	else:
		_on_tap(screen_pos, index)
	_touch_up(index)
	_gesture_dragging = false
	drag_active = false
	drag_kind = ""


func _touch_down(index: int, screen_pos: Vector2) -> void:
	_touch_index = index
	_touch_consumed = false
	_press_position = screen_pos
	_gesture_dragging = false
	_pointer_visible = true
	ghost_back = 0
	press_target = ""
	var board := _board_from_screen(screen_pos)
	drag_pos = board
	var cell := GardenLayout.cell_at(state, board)
	hover_cell = cell
	preview_cell = cell if _cell_valid(cell) else Vector2i(-1, -1)
	# 阳光/金币按下即收，贴近原版手感；命中后本次按压不再参与种植
	for sun in state.get("suns", []):
		var center := GardenLayout.point(state, float(sun.x) + .5, float(sun.y) + .2)
		if not bool(sun.collecting) and board.distance_to(center) <= 44:
			sun_pressed.emit(int(sun.uid))
			_touch_consumed = true
			return
	for coin in state.get("coins", []):
		if board.distance_to(GardenLayout.foot(state, int(coin.row), float(coin.x)) - Vector2(0, 15)) < 26:
			coin_pressed.emit(int(coin.uid))
			_touch_consumed = true
			return
	if Rect2(718, 10, 56, 55).has_point(board):
		press_target = "shovel"
		AudioFX.play("tap")
	elif Rect2(660, 12, 48, 48).has_point(board):
		press_target = "speed"
		AudioFX.play("tap")
	elif board.y < 76:
		var cards := _hud_cards()
		var hit := GardenLayout.seed_at(board, cards.size())
		if hit >= 0:
			press_target = "seed:%d" % hit
			AudioFX.play("tap")


func _touch_up(index: int) -> void:
	if index != _touch_index:
		return
	press_target = ""
	_touch_index = -1
	_touch_consumed = false
	_pointer_visible = index == MOUSE_POINTER
	if index != MOUSE_POINTER:
		hover_cell = Vector2i(-1, -1)
		preview_cell = Vector2i(-1, -1)
	queue_redraw()


func _on_tap(screen_pos: Vector2, index: int) -> void:
	if index != _touch_index or _touch_consumed or _input_silenced():
		return
	var board := _board_from_screen(screen_pos)
	if Rect2(718, 10, 56, 55).has_point(board):
		shovel_pressed.emit()
		return
	if Rect2(660, 12, 48, 48).has_point(board):
		speed_pressed.emit()
		return
	if board.y < 76:
		var cards := _hud_cards()
		var hit := GardenLayout.seed_at(board, cards.size())
		if hit >= 0:
			seed_pressed.emit(str(cards[hit]))
		else:
			blank_pressed.emit() # 卡槽空白处点按 = 取消选中
		return
	# 阳光/金币兜底（正常情况下按下时已收集）
	for sun in state.get("suns", []):
		var center := GardenLayout.point(state, float(sun.x) + .5, float(sun.y) + .2)
		if not bool(sun.collecting) and board.distance_to(center) <= 44:
			sun_pressed.emit(int(sun.uid))
			return
	for coin in state.get("coins", []):
		if board.distance_to(GardenLayout.foot(state, int(coin.row), float(coin.x)) - Vector2(0, 15)) < 26:
			coin_pressed.emit(int(coin.uid))
			return
	var cell := GardenLayout.cell_at(state, board)
	if _cell_valid(cell):
		_attempt_cell(cell)
	else:
		blank_pressed.emit() # 点空白（非格非卡非阳光）= 取消选中


func _on_drag_start(screen_pos: Vector2, index: int) -> void:
	if index != _touch_index or _touch_consumed:
		return
	# 从可用卡片拖出 = 拖拽种植模式（不可用卡不生成 ghost，松手走 tap 提示原因）
	if press_target.begins_with("seed:"):
		var hit := int(press_target.get_slice(":", 1))
		var cards := _hud_cards()
		if hit >= 0 and hit < cards.size():
			var kind := str(cards[hit])
			if _card_status(kind) in ["ready", "selected"]:
				drag_active = true
				drag_kind = kind
				drag_pos = _board_from_screen(screen_pos)
				if str(state.get("selectedSeed", "")) != kind or bool(state.get("shovel", false)):
					seed_pressed.emit(kind)
				if str(state.get("selectedSeed", "")) != kind:
					drag_active = false
					drag_kind = ""
					_touch_consumed = true
			else:
				_touch_consumed = true
				seed_pressed.emit(kind)
	elif press_target == "shovel":
		if not bool(state.get("shovel", false)):
			shovel_pressed.emit()
	elif not press_target.is_empty():
		_touch_consumed = true


func _on_drag_move(screen_pos: Vector2, _delta: Vector2, index: int) -> void:
	if index != _touch_index:
		return
	var board := _board_from_screen(screen_pos)
	if drag_active:
		drag_pos = board
	if not _touch_consumed:
		# 按住滑动实时刷新预览
		var cell := GardenLayout.cell_at(state, board)
		hover_cell = cell
		preview_cell = cell if _cell_valid(cell) else Vector2i(-1, -1)


func _on_drag_end(screen_pos: Vector2, index: int) -> void:
	if index != _touch_index:
		return
	var board := _board_from_screen(screen_pos)
	hover_cell = Vector2i(-1, -1)
	preview_cell = Vector2i(-1, -1)
	if drag_active:
		var kind := drag_kind
		drag_active = false
		drag_kind = ""
		var cell := GardenLayout.cell_at(state, board)
		if _cell_valid(cell) and not _touch_consumed:
			_attempt_cell(cell) # 松手落格种植
		else:
			_start_ghost_return(kind, board) # 拖回卡槽/出界松手 = 取消，回弹销毁
	elif not _touch_consumed and not _preview_kind().is_empty():
		var cell := GardenLayout.cell_at(state, board)
		if _cell_valid(cell):
			_attempt_cell(cell) # 选中卡后按住滑动，松手落格种植


func _attempt_cell(cell: Vector2i) -> void:
	var kind := _preview_kind()
	if not kind.is_empty() and not _can_check(cell, kind).is_empty():
		_flash_cell(cell) # 非法格不取消选中：红闪反馈，wrong 音与提示由编排层处理
	cell_pressed.emit(cell.y, cell.x)


func _flash_cell(cell: Vector2i) -> void:
	cell_flash = .5
	cell_flash_at = cell


func _start_ghost_return(kind: String, board: Vector2) -> void:
	ghost_back_kind = kind
	ghost_back_from = board
	ghost_back = .001


func set_dialog_open(open: bool) -> void:
	dialog_open = open
	if open:
		cancel_interaction()


func cancel_interaction() -> void:
	# 手势取消/暂停/弹窗打开时统一清理：无悬停与拖拽残留
	_gesture_dragging = false
	_pointer_visible = false
	_shovel_return = 0.0
	_touch_index = -1
	_touch_consumed = false
	press_target = ""
	drag_active = false
	drag_kind = ""
	ghost_back = 0.0
	hover_cell = Vector2i(-1, -1)
	preview_cell = Vector2i(-1, -1)
	queue_redraw()


# ---- 交互辅助 ----

func _board_from_screen(screen_pos: Vector2) -> Vector2:
	return _transform().affine_inverse() * (get_global_transform_with_canvas().affine_inverse() * screen_pos)


func _input_silenced() -> bool:
	if state.is_empty() or paused or dialog_open:
		return true
	var hub := get_tree().get_first_node_in_group("main_hub")
	if hub != null:
		var ipc = hub.get("ipc")
		if ipc != null and ipc.is_blocked_by_dialog():
			return true
	return false


func _cell_valid(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.x < 9 and cell.y in state.get("activeRows", [])


func _hud_cards() -> Array:
	return state.get("seeds", []) if str(state.get("special", "")) in ["lawn", "whack"] else state.get("packets", []).map(func(packet): return str(packet.kind))


func _free_cards() -> bool:
	return str(state.get("special", "")) in ["conveyor", "bowling", "vase"]


func _preview_kind() -> String:
	if not drag_kind.is_empty():
		return drag_kind
	if bool(state.get("shovel", false)):
		return ""
	return str(state.get("selectedSeed", ""))


func _can_check(cell: Vector2i, kind: String) -> String:
	if can_plant_check.is_valid():
		return str(can_plant_check.call(cell.y, cell.x, kind))
	return ""


func _card_status(kind: String) -> String:
	if str(state.get("selectedSeed", "")) == kind and not bool(state.get("shovel", false)):
		return "selected"
	if not _free_cards():
		if float(state.get("cooldowns", {}).get(kind, 0)) > 0:
			return "cooling"
		if int(state.get("sun", 0)) < int(ContentDB.garden_plants().get(kind, {}).get("cost", 0)):
			return "no_sun"
	return "ready"


func _card_home(kind: String) -> Vector2:
	var hit := _hud_cards().find(kind)
	return GardenLayout.seed_rect(hit).get_center() if hit >= 0 else Vector2(110, 40)


func _preview_clip(kind: String) -> String:
	return kind if art.has_clip(kind) else "peashooter"


func _shovel_target() -> Dictionary:
	if not bool(state.get("shovel", false)) or not _pointer_visible:
		return {}
	var cell := GardenLayout.cell_at(state, drag_pos)
	if not _cell_valid(cell):
		return {}
	var index := cell.y * 9 + cell.x
	if state.grid[index].is_empty() and cell.x > 0 and str(state.grid[index - 1].get("kind", "")) == "cobcannon":
		index -= 1
	for layer in ["bases", "shells", "grid"]:
		var plant: Dictionary = state[layer][index]
		if not plant.is_empty():
			return plant
	return {}
