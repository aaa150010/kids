class_name IslandBoard3D
extends Control

## 智慧岛 3D 棋盘（SubViewport 正交渲染）
## 交互：单指拖动旋转视角（yaw ±40° 阻尼）、双指/滚轮缩放（0.8~1.3）、点格子看信息卡
## 视觉：3D 骰子改用自绘骰面、路径呼吸环、金币/星星粒子、事件图标弹跳
## 省电：静止时 UPDATE_ONCE，动效期间临时 UPDATE_ALWAYS

signal tile_tapped(index: int)

const MAX_YAW := 0.698 # ±40°
const YAW_DRAG := 0.006
const ZOOM_MIN := 0.8
const ZOOM_MAX := 1.3
const BASE_CAMERA_SIZE := 23.0
const CAMERA_BASE := Vector3(0, 24, 19)
const CAMERA_PITCH := -0.9424778
const DRAG_SLOP := 14.0
const TAP_MAX_TIME := 0.35
const TAP_MAX_DISTANCE := 14.0
const TILE_TOUCH_RADIUS := 40.0
const IDLE_RECENTER := 2.0

const TYPE_LABEL := {
	"start": "起点",
	"property": "房产",
	"quiz": "答题",
	"bonus": "宝箱",
	"penalty": "淘气云朵",
	"move": "顺风车",
	"rest": "休息",
}
const TYPE_ICON := {
	"start": "🏁",
	"property": "🏠",
	"quiz": "📚",
	"bonus": "💰",
	"penalty": "🌧️",
	"move": "🚌",
	"rest": "🌿",
}

var viewport: SubViewport
var display: TextureRect
var world: Node3D
var camera: Camera3D
var tile_visuals: Dictionary = {}
var pawns: Array[Node3D] = []
var houses: Dictionary = {}
var tiles: Array = []
var movements: Dictionary = {}

# 视角与输入
var _yaw := 0.0
var _yaw_target := 0.0
var _zoom := 1.0
var _zoom_target := 1.0
var _smoothing := false
var _fingers: Dictionary = {}
var _pointer := -1
var _press_pos := Vector2.ZERO
var _press_ms := 0
var _dragging := false
var _pinch_base := 0.0
var _pinch_zoom := 1.0
var _last_touch_ms := 0
var _idle_timer: Timer
var _render_until := 0

# 选中与提示卡
var _selected := -1
var _highlight: Node3D
var _highlight_tween: Tween
var _tile_tweens: Dictionary = {}
var _tooltip: PanelContainer
var _tooltip_icon: Label
var _tooltip_title: Label
var _tooltip_meta: Label
var _tooltip_tween: Tween

# 骰子 / 粒子
var _dice # DiceView（内部类，声明在下方）
var _dice_tween: Tween
var _effects # BurstLayer（内部类，声明在下方）
var _path_rings: Array[Node3D] = []
var _path_tweens: Array[Tween] = []


## 自绘骰子：白底圆角方块 + 1~6 点阵
class DiceView extends Control:
	var face := 1
	var _style: StyleBoxFlat

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_style = StyleBoxFlat.new()
		_style.bg_color = Color("#fffaf0")
		_style.border_color = Color("#c98f5a")
		_style.set_border_width_all(4)
		_style.set_corner_radius_all(20)
		_style.shadow_size = 10
		_style.shadow_color = Color(0.15, 0.1, 0.05, 0.22)
		_style.shadow_offset = Vector2(0, 6)

	func _draw() -> void:
		draw_style_box(_style, Rect2(Vector2.ZERO, size))
		var radius := size.x * 0.085
		for point in _pip_layout():
			var center := Vector2(size.x * point.x, size.y * point.y)
			draw_circle(center, radius, Color("#8a4b2a"))
			draw_circle(center + Vector2(-radius * 0.22, -radius * 0.26), radius * 0.34, Color(1, 1, 1, 0.5))

	func _pip_layout() -> Array:
		match face:
			1:
				return [Vector2(0.5, 0.5)]
			2:
				return [Vector2(0.3, 0.3), Vector2(0.7, 0.7)]
			3:
				return [Vector2(0.28, 0.28), Vector2(0.5, 0.5), Vector2(0.72, 0.72)]
			4:
				return [Vector2(0.3, 0.3), Vector2(0.7, 0.3), Vector2(0.3, 0.7), Vector2(0.7, 0.7)]
			5:
				return [Vector2(0.28, 0.28), Vector2(0.72, 0.28), Vector2(0.5, 0.5), Vector2(0.28, 0.72), Vector2(0.72, 0.72)]
			_:
				return [Vector2(0.3, 0.26), Vector2(0.7, 0.26), Vector2(0.3, 0.5), Vector2(0.7, 0.5), Vector2(0.3, 0.74), Vector2(0.7, 0.74)]


## 自绘粒子层：金币/星星/事件图标，全部按自绘参数逐帧重绘
class BurstLayer extends Control:
	var particles: Array[Dictionary] = []

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func burst(at: Vector2, kind: String, count: int) -> void:
		for index in count:
			particles.append({
				"kind": kind,
				"text": "",
				"pos": at + Vector2(randf_range(-16, 16), randf_range(-10, 10)),
				"vel": Vector2(randf_range(-110, 110), randf_range(-260, -130)),
				"life": 0.0,
				"max": randf_range(0.6, 1.0),
				"spin": randf_range(-4.0, 4.0),
				"angle": randf() * TAU,
				"scale": randf_range(0.7, 1.15),
			})

	func icon(at: Vector2, symbol: String) -> void:
		particles.append({
			"kind": "icon",
			"text": symbol,
			"pos": at,
			"vel": Vector2(0, -190),
			"life": 0.0,
			"max": 1.1,
			"spin": 0.0,
			"angle": 0.0,
			"scale": 1.0,
		})

	func _process(delta: float) -> void:
		if particles.is_empty():
			return
		for index in range(particles.size() - 1, -1, -1):
			var particle: Dictionary = particles[index]
			particle.life = float(particle.life) + delta
			if float(particle.life) >= float(particle.max):
				particles.remove_at(index)
				continue
			var velocity: Vector2 = particle.vel
			velocity.y += 520.0 * delta
			velocity.x *= 0.99
			particle.vel = velocity
			particle.pos = Vector2(particle.pos) + velocity * delta
			particle.angle = float(particle.angle) + float(particle.spin) * delta
		queue_redraw()

	func _draw() -> void:
		for particle in particles:
			var progress := float(particle.life) / float(particle.max)
			var alpha := clampf(1.0 - pow(progress, 2.2), 0.0, 1.0)
			var position: Vector2 = particle.pos
			var scale := float(particle.scale)
			match str(particle.kind):
				"coin":
					_draw_coin(position, 10.0 * scale, alpha)
				"star":
					_draw_star(position, 12.0 * scale, float(particle.angle), alpha)
				_:
					_draw_icon(position, str(particle.text), alpha, scale)

	func _draw_coin(center: Vector2, radius: float, alpha: float) -> void:
		draw_circle(center, radius, Color(0.87, 0.66, 0.25, alpha))
		draw_circle(center, radius * 0.72, Color(1.0, 0.82, 0.34, alpha))
		draw_circle(center + Vector2(-radius * 0.24, -radius * 0.28), radius * 0.22, Color(1, 1, 1, alpha * 0.7))

	func _draw_star(center: Vector2, radius: float, angle: float, alpha: float) -> void:
		var points := PackedVector2Array()
		for index in 10:
			var length := radius if index % 2 == 0 else radius * 0.46
			var direction := angle - PI / 2.0 + float(index) * PI / 5.0
			points.append(center + Vector2(cos(direction), sin(direction)) * length)
		draw_colored_polygon(points, Color(1.0, 0.78, 0.24, alpha))

	func _draw_icon(center: Vector2, symbol: String, alpha: float, scale: float) -> void:
		var font := PlaygroundUI.emoji_font()
		var font_size := int(44.0 * scale)
		var text_size := font.get_string_size(symbol, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		draw_string(
			font,
			center - text_size * 0.5 + Vector2(0, text_size.y * 0.35),
			symbol,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			font_size,
			Color(1, 1, 1, alpha)
		)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_CLICK
	viewport = SubViewport.new()
	viewport.msaa_3d = Viewport.MSAA_2X
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(viewport)
	display = TextureRect.new()
	display.texture = viewport.get_texture()
	display.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	display.stretch_mode = TextureRect.STRETCH_SCALE
	display.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	display.mouse_filter = Control.MOUSE_FILTER_IGNORE
	display.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(display)
	world = Node3D.new()
	viewport.add_child(world)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = BASE_CAMERA_SIZE
	camera.position = CAMERA_BASE
	camera.rotation_degrees = Vector3(-54, 0, 0)
	world.add_child(camera)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-58, -36, 0)
	light.light_energy = 1.15
	world.add_child(light)
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("#d9eee8")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("#fff1d5")
	settings.ambient_light_energy = 0.8
	environment.environment = settings
	world.add_child(environment)
	_build_island()
	_build_highlight()
	_build_dice()
	_idle_timer = Timer.new()
	_idle_timer.one_shot = true
	_idle_timer.wait_time = IDLE_RECENTER
	_idle_timer.timeout.connect(_recenter)
	add_child(_idle_timer)
	RuntimeQuality.changed.connect(_apply_quality)
	resized.connect(_resize_viewport)
	_apply_quality()
	_resize_viewport.call_deferred()


func _process(delta: float) -> void:
	if _smoothing:
		# 指数阻尼：拖动时视角略微跟手，松手后柔和落到目标
		var factor := 1.0 - pow(0.000002, delta)
		_yaw = lerpf(_yaw, _yaw_target, factor)
		_zoom = lerpf(_zoom, _zoom_target, factor)
		if absf(_yaw - _yaw_target) < 0.0015 and absf(_zoom - _zoom_target) < 0.0015:
			_yaw = _yaw_target
			_zoom = _zoom_target
			_smoothing = false
		_apply_view()
	if viewport != null and viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS and Time.get_ticks_msec() >= _render_until:
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


func _apply_quality() -> void:
	if viewport == null:
		return
	viewport.msaa_3d = Viewport.MSAA_2X if RuntimeQuality.quality_level >= 1 else Viewport.MSAA_DISABLED
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


func _resize_viewport() -> void:
	if viewport == null or size.x < 10.0 or size.y < 10.0:
		return
	var canvas_scale := get_viewport().get_final_transform().get_scale()
	var render_scale := maxf(1.0,maxf(canvas_scale.x,canvas_scale.y))
	var target := Vector2i(maxi(1,int(size.x*render_scale)),maxi(1,int(size.y*render_scale)))
	target.x = mini(target.x,4096)
	target.y = mini(target.y,2800)
	if viewport.size != target:
		viewport.size = target
		if _smoothing or Time.get_ticks_msec() < _render_until:
			_keep_awake(300)
		else:
			viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_layout_dice()
	if _tooltip != null:
		_tooltip.visible = false


func _mesh(shape: Mesh, tint: Color, parent: Node3D, position: Vector3) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = shape
	var material := StandardMaterial3D.new()
	material.albedo_color = tint
	material.roughness = 0.8
	node.material_override = material
	node.position = position
	parent.add_child(node)
	return node

func _box(dimensions: Vector3) -> BoxMesh:
	var shape := BoxMesh.new()
	shape.size = dimensions
	return shape

func _cylinder(radius: float, height: float) -> CylinderMesh:
	var shape := CylinderMesh.new()
	shape.top_radius = radius
	shape.bottom_radius = radius
	shape.height = height
	shape.radial_segments = 48
	return shape

func _build_island() -> void:
	_mesh(_cylinder(13.5,0.08),Color("#a4d7de"),world,Vector3(0,-0.95,0))
	_mesh(_cylinder(11.2,1.0),Color("#a88660"),world,Vector3(0,-0.55,0))
	_mesh(_cylinder(11.3,0.2),Color("#aacf91"),world,Vector3(0,0.02,0))
	_mesh(_cylinder(3.9,0.08),Color("#74c7cd"),world,Vector3(0,0.18,0))
	_mesh(_cylinder(1.7,0.4),Color("#edd9a6"),world,Vector3(0,0.35,0))
	var pavilion := Node3D.new()
	world.add_child(pavilion)
	for offset in [Vector3(-0.8,0.9,-0.8),Vector3(0.8,0.9,-0.8),Vector3(-0.8,0.9,0.8),Vector3(0.8,0.9,0.8)]:
		_mesh(_box(Vector3(0.14,1.2,0.14)),Color("#cf9866"),pavilion,offset)
	var roof := PrismMesh.new()
	roof.size = Vector3(2.7,1.1,2.7)
	_mesh(roof,Color("#3b8b79"),pavilion,Vector3(0,1.8,0))
	for index in 7:
		var angle := float(index)/7.0*TAU
		var root := Node3D.new()
		root.position = Vector3(cos(angle)*5.6,0.22,sin(angle)*5.6)
		world.add_child(root)
		_mesh(_cylinder(0.12,0.7),Color("#a5774d"),root,Vector3(0,0.35,0))
		var leaves := SphereMesh.new()
		leaves.radius = 0.65
		leaves.height = 1.1
		leaves.radial_segments = 12
		leaves.rings = 6
		_mesh(leaves,Color("#69a85d") if index%2 == 0 else Color("#88b562"),root,Vector3(0,1.0,0))
	var title := Label3D.new()
	title.text = "智慧岛心"
	title.font = PlaygroundUI.font()
	title.font_size = 54
	title.pixel_size = 0.009
	title.position = Vector3(0,3.2,0)
	title.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	title.modulate = Color("#3c6e62")
	world.add_child(title)
	for index in 32:
		var tile := Node3D.new()
		tile.position = _tile_position(index)
		world.add_child(tile)
		_mesh(_box(Vector3(1.55,0.26,1.55)),Color("#f8eccf") if index%2 == 0 else Color("#e9d6ac"),tile,Vector3.ZERO)
		var label := Label3D.new()
		label.name = "TileName"
		label.font = PlaygroundUI.font()
		label.font_size = 30
		label.pixel_size = 0.006
		label.position = Vector3(0,0.38,0.25)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.outline_size = 5
		label.outline_modulate = Color(1,1,1,0.82)
		label.modulate = Color("#5c513c")
		tile.add_child(label)
		tile_visuals[index] = tile


func _build_highlight() -> void:
	_highlight = _make_ring(Color("#ffd45e"))
	for index in 6:
		_path_rings.append(_make_ring(Color("#9be7b8")))


func _make_ring(tint: Color) -> Node3D:
	var root := Node3D.new()
	root.visible = false
	world.add_child(root)
	var torus := TorusMesh.new()
	torus.inner_radius = 0.62
	torus.outer_radius = 0.94
	torus.rings = 16
	torus.ring_segments = 32
	var mesh := _mesh(torus, tint, root, Vector3.ZERO)
	var material := mesh.material_override as StandardMaterial3D
	material.albedo_color = Color(tint, 0.9)
	material.emission_enabled = true
	material.emission = tint
	material.emission_energy_multiplier = 0.7
	return root


func _build_dice() -> void:
	if _dice != null:
		return
	_dice = DiceView.new()
	_dice.z_index = 30
	_dice.visible = false
	add_child(_dice)
	_layout_dice()


func _layout_dice() -> void:
	if _dice == null:
		return
	var side := clampf(minf(size.x, size.y) * 0.2, 72.0, 104.0)
	_dice.size = Vector2(side, side)
	_dice.position = Vector2((size.x - side) * 0.5, maxf(10.0, size.y * 0.1))
	_dice.pivot_offset = _dice.size * 0.5


func _ensure_effects() -> void:
	if _effects != null:
		return
	_effects = BurstLayer.new()
	_effects.z_index = 25
	add_child(_effects)
	_effects.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _tile_position(index: int) -> Vector3:
	var angle := float(index%32)/32.0*TAU-PI/2
	return Vector3(cos(angle)*9.2,0.28,sin(angle)*9.2)

func set_tiles(values: Array) -> void:
	tiles = values
	for index in values.size():
		if not tile_visuals.has(index):
			continue
		var tile: Node3D = tile_visuals[index]
		var label := tile.get_node("TileName") as Label3D
		label.text = str(values[index].get("name",""))
		var icon := Sprite3D.new()
		icon.texture = ArtLibrary.texture(str(values[index].get("icon","")))
		icon.pixel_size = 0.004
		icon.position = Vector3(0,0.2,-0.2)
		icon.rotation_degrees.x = -90
		tile.add_child(icon)
	_keep_awake(300)

func reset_presentation() -> void:
	MotionKit.kill_owner(self)
	for animation in movements.values():
		if animation != null and animation.is_valid():
			animation.kill()
	movements.clear()
	for pawn in pawns:
		pawn.queue_free()
	pawns.clear()
	for ring in _path_rings:
		ring.visible = false
	if _dice != null:
		_dice.hide()
	if _effects != null:
		_effects.particles.clear()
		_effects.queue_redraw()
	_reset_gesture()


func set_players(players: Array) -> void:
	if pawns.size() != players.size():
		for pawn in pawns:
			pawn.queue_free()
		pawns.clear()
		for index in players.size():
			var pawn := Node3D.new()
			world.add_child(pawn)
			var tint := PlaygroundUI.color(str(players[index].get("color","#d56c29")))
			_mesh(_cylinder(0.35,0.15),tint,pawn,Vector3(0,0.12,0))
			var body := CapsuleMesh.new()
			body.radius = 0.27
			body.height = 0.75
			_mesh(body,tint,pawn,Vector3(0,0.55,0))
			var face := Sprite3D.new()
			face.texture = ArtLibrary.texture(str(players[index].get("avatar","🦊")))
			face.pixel_size = 0.007
			face.position = Vector3(0,1.15,0)
			face.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			pawn.add_child(face)
			pawn.position = _tile_position(int(players[index].position))+_offset_for_player(index,players.size())
			pawn.set_meta("tile",int(players[index].position))
			pawns.append(pawn)
	else:
		for index in players.size():
			if int(pawns[index].get_meta("tile",0)) != int(players[index].position):
				move_player(index,int(players[index].position),players.size())
	_keep_awake(300)

func set_owners(properties: Dictionary, player_colors: Array) -> void:
	for index in houses.keys():
		if properties.get(int(index),properties.get(str(index),{})).is_empty():
			houses[index].queue_free()
			houses.erase(index)
	for index in tile_visuals:
		var property: Dictionary = properties.get(int(index),properties.get(str(index),{}))
		if property.is_empty():
			continue
		var owner := int(property.get("ownerId",-1))
		if owner < 0 or owner >= player_colors.size():
			continue
		var level := int(property.get("level",0))
		if houses.has(index) and int(houses[index].get_meta("level",-1)) == level and int(houses[index].get_meta("owner",-1)) == owner:
			continue
		if houses.has(index):
			houses[index].queue_free()
		var house := Node3D.new()
		house.position = _tile_position(int(index))*0.78
		var tint := PlaygroundUI.color(str(player_colors[owner]))
		_mesh(_box(Vector3(0.64,0.55+level*0.22,0.65)),PlaygroundUI.mix(tint,Color.WHITE,0.35),house,Vector3(0,0.5+level*0.11,0))
		var roof := PrismMesh.new()
		roof.size = Vector3(0.9,0.4,0.9)
		_mesh(roof,tint,house,Vector3(0,1.0+level*0.22,0))
		house.set_meta("level",level)
		house.set_meta("owner",owner)
		# 新房子/升级时从地面“长出来”，避免突然出现
		house.scale = Vector3(0.25,0.25,0.25)
		world.add_child(house)
		houses[index] = house
		var tween := MotionKit.tween(self)
		tween.tween_property(house, "scale", Vector3.ONE, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_keep_awake(600)

func _offset_for_player(index: int, count: int) -> Vector3:
	var angle := float(index)/maxf(1,count)*TAU
	return Vector3(cos(angle)*0.36,0,sin(angle)*0.36)

func move_player(index: int, position: int, count: int) -> void:
	if index < 0 or index >= pawns.size():
		return
	var pawn := pawns[index]
	var origin := int(pawn.get_meta("tile",position))
	pawn.set_meta("tile",position)
	if movements.has(index):
		movements[index].kill()
	var tween := create_tween()
	var parent := get_parent()
	var screen: NativeGameScreen = null
	while parent != null and not parent is NativeGameScreen:
		parent = parent.get_parent()
	if parent != null:
		screen = parent
		tween.set_meta("screen_owner",parent.get_instance_id())
		MotionKit.adopt(screen, tween)
	var steps := (position-origin+32)%32
	_keep_awake(steps * 160 + 300)
	for step in range(1,steps+1):
		var destination := _tile_position((origin+step)%32)+_offset_for_player(index,count)
		tween.tween_property(pawn,"position",destination+Vector3(0,0.22,0),0.09)
		tween.tween_property(pawn,"position",destination,0.07).set_trans(Tween.TRANS_QUAD)
	# 跳跃结束后交给统一计时器恢复 UPDATE_ONCE，避免打断其它动效
	tween.finished.connect(func(): _keep_awake(120))
	movements[index] = tween


# ---------------- 视角与手势 ----------------

func _reset_gesture() -> void:
	_fingers.clear()
	_pointer = -1
	_dragging = false
	_pinch_base = 0.0
	if _idle_timer != null:
		_idle_timer.stop()


func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT,NOTIFICATION_APPLICATION_PAUSED]:
		_reset_gesture()


func _gui_input(event: InputEvent) -> void:
	var parent := get_parent()
	while parent != null and not parent is NativeGameScreen:
		parent = parent.get_parent()
	if parent is NativeGameScreen and (parent.paused or parent._modal_stack.size() > 0):
		_reset_gesture()
		return
	if event is InputEventScreenTouch:
		_last_touch_ms = Time.get_ticks_msec()
		if event.pressed:
			_track_press(event.index, event.position)
		else:
			if event.canceled:
				_reset_gesture()
			else:
				_track_release(event.index, event.position)
		accept_event()
	elif event is InputEventScreenDrag:
		_last_touch_ms = Time.get_ticks_msec()
		_track_move(event.index, event.position)
		accept_event()
	elif event is InputEventMouseButton:
		if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			_zoom_to(_zoom_target + (0.08 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -0.08))
			accept_event()
		elif event.button_index == MOUSE_BUTTON_LEFT and Time.get_ticks_msec() - _last_touch_ms > 300:
			# 兜底：未开启鼠标转触摸时，鼠标同样可以拖动/点选
			if event.pressed:
				_track_press(0, event.position)
			else:
				_track_release(0, event.position)
			accept_event()
	elif event is InputEventMouseMotion:
		if not _fingers.is_empty() and Time.get_ticks_msec() - _last_touch_ms > 300:
			_track_move(0, event.position)


func _track_press(index: int, position: Vector2) -> void:
	_idle_timer.stop()
	_fingers[index] = position
	if _fingers.size() == 1:
		_pointer = index
		_press_pos = position
		_press_ms = Time.get_ticks_msec()
		_dragging = false
	elif _fingers.size() == 2:
		_dragging = false
		var keys := _fingers.keys()
		var first: Vector2 = _fingers[keys[0]]
		var second: Vector2 = _fingers[keys[1]]
		_pinch_base = maxf(1.0, first.distance_to(second))
		_pinch_zoom = _zoom_target


func _track_move(index: int, position: Vector2) -> void:
	if not _fingers.has(index):
		return
	var previous: Vector2 = _fingers[index]
	_fingers[index] = position
	if _fingers.size() >= 2:
		# 双指捏合：按当前两指距离相对基准距离缩放
		var keys := _fingers.keys()
		var first: Vector2 = _fingers[keys[0]]
		var second: Vector2 = _fingers[keys[1]]
		if _pinch_base > 1.0:
			_zoom_to(_pinch_zoom * first.distance_to(second) / _pinch_base)
		return
	if index != _pointer:
		return
	if not _dragging and position.distance_to(_press_pos) > DRAG_SLOP:
		_dragging = true
		_hide_tooltip()
	if _dragging:
		_yaw_target = clampf(_yaw_target - (position.x - previous.x) * YAW_DRAG, -MAX_YAW, MAX_YAW)
		_smoothing = true
		_keep_awake(500)


func _track_release(index: int, position: Vector2) -> void:
	if not _fingers.has(index):
		return
	var lifted: Vector2 = _fingers[index]
	_fingers.erase(index)
	if _fingers.is_empty():
		if index == _pointer:
			var elapsed := (Time.get_ticks_msec() - _press_ms) / 1000.0
			if not _dragging and elapsed <= TAP_MAX_TIME and lifted.distance_to(_press_pos) <= TAP_MAX_DISTANCE:
				_handle_tap(position)
			elif _dragging:
				_idle_timer.start()
		_pointer = -1
		_dragging = false
		_pinch_base = 0.0
	elif _fingers.size() == 1:
		# 双指松一指：剩下那只继续拖动，不误触发 tap
		_pointer = int(_fingers.keys()[0])
		_press_pos = _fingers[_pointer]
		_dragging = true
		_pinch_base = 0.0
		_idle_timer.start()


func _handle_tap(local: Vector2) -> void:
	var index := _tile_at(local)
	if index >= 0:
		_select_tile(index, local)
		tile_tapped.emit(index)
	else:
		_clear_selection()


func _tile_at(local: Vector2) -> int:
	if tiles.is_empty() or viewport == null or viewport.size.x <= 0 or size.x <= 0.0:
		return -1
	var best := -1
	var best_distance := TILE_TOUCH_RADIUS
	for key in tile_visuals:
		var node: Node3D = tile_visuals[key]
		var projected := camera.unproject_position(node.global_position + Vector3(0, 0.4, 0))
		var screen := Vector2(
			projected.x / float(viewport.size.x) * size.x,
			projected.y / float(viewport.size.y) * size.y
		)
		var distance := screen.distance_to(local)
		if distance < best_distance:
			best = int(key)
			best_distance = distance
	return best


func _zoom_to(value: float) -> void:
	_zoom_target = clampf(value, ZOOM_MIN, ZOOM_MAX)
	_smoothing = true
	_keep_awake(600)
	_hide_tooltip()


func _recenter() -> void:
	# 2 秒无操作后柔和回正
	if not _fingers.is_empty() or absf(_yaw_target) < 0.01:
		return
	_yaw_target = 0.0
	_smoothing = true
	_keep_awake(900)


func _apply_view() -> void:
	if camera == null:
		return
	camera.size = BASE_CAMERA_SIZE / _zoom
	camera.position = CAMERA_BASE.rotated(Vector3.UP, _yaw)
	camera.rotation = Vector3(CAMERA_PITCH, _yaw, 0)
	_keep_awake(200)


func _keep_awake(milliseconds: int) -> void:
	_render_until = maxi(_render_until, Time.get_ticks_msec() + milliseconds)
	if viewport != null:
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS


# ---------------- 格子选中与信息卡 ----------------

func _select_tile(index: int, local: Vector2) -> void:
	if not tile_visuals.has(index):
		return
	if _selected >= 0 and _selected != index and tile_visuals.has(_selected):
		_scale_tile(_selected, Vector3.ONE, 0.16)
	_selected = index
	_scale_tile(index, Vector3.ONE * 1.12, 0.18)
	_place_highlight(index)
	_show_tooltip(index, local)
	AudioFX.play("tap")


func _scale_tile(index: int, target: Vector3, duration: float) -> void:
	if not tile_visuals.has(index):
		return
	if _tile_tweens.has(index) and _tile_tweens[index] != null and _tile_tweens[index].is_valid():
		_tile_tweens[index].kill()
	var tile: Node3D = tile_visuals[index]
	var tween := MotionKit.tween(self)
	tween.tween_property(tile, "scale", target, duration).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tile_tweens[index] = tween
	_keep_awake(int(duration * 1000.0) + 200)


func _place_highlight(index: int) -> void:
	if _highlight == null or not tile_visuals.has(index):
		return
	var tile: Node3D = tile_visuals[index]
	_highlight.visible = true
	_highlight.position = tile.position + Vector3(0, 0.2, 0)
	_highlight.scale = Vector3.ONE * 0.9
	if _highlight_tween != null and _highlight_tween.is_valid():
		_highlight_tween.kill()
	_highlight_tween = MotionKit.tween(self)
	_highlight_tween.set_loops(3)
	_highlight_tween.tween_property(_highlight, "scale", Vector3.ONE * 1.08, 0.55).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_highlight_tween.tween_property(_highlight, "scale", Vector3.ONE * 0.92, 0.55).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_highlight_tween.finished.connect(func():
		if is_instance_valid(_highlight):
			_highlight.scale = Vector3.ONE
	)
	_keep_awake(3600)


func _clear_selection() -> void:
	if _selected >= 0:
		_scale_tile(_selected, Vector3.ONE, 0.16)
	_selected = -1
	if _highlight_tween != null and _highlight_tween.is_valid():
		_highlight_tween.kill()
	if _highlight != null:
		_highlight.visible = false
	_hide_tooltip()


func _ensure_tooltip() -> void:
	if _tooltip != null:
		return
	_tooltip = PlaygroundUI.panel(Color(1, 1, 1, 0.96), 16, Color(0.18, 0.14, 0.11, 0.16), 1)
	_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip.z_index = 20
	_tooltip.visible = false
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 10)
	_tooltip_icon = PlaygroundUI.label("", 26, PlaygroundUI.INK, 700)
	row.add_child(_tooltip_icon)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 0)
	_tooltip_title = PlaygroundUI.label("", 16, PlaygroundUI.INK, 700)
	_tooltip_meta = PlaygroundUI.label("", 12, PlaygroundUI.INK_SOFT, 500)
	column.add_child(_tooltip_title)
	column.add_child(_tooltip_meta)
	row.add_child(column)
	_tooltip.add_child(row)
	for node in _tooltip.find_children("*", "Control", true, false):
		(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_tooltip)


func _show_tooltip(index: int, local: Vector2) -> void:
	_ensure_tooltip()
	var tile: Dictionary = tiles[index] if index < tiles.size() else {}
	var kind := str(tile.get("type", "rest"))
	_tooltip_icon.text = str(TYPE_ICON.get(kind, "✨"))
	_tooltip_title.text = "%s %s" % [str(tile.get("icon", "")), str(tile.get("name", "智慧岛"))]
	var meta := "%s · 第 %s 格" % [str(TYPE_LABEL.get(kind, "事件")), index + 1]
	if kind == "property":
		meta += " · %s 金币" % int(tile.get("price", 0))
	_tooltip_meta.text = meta
	_tooltip.visible = true
	_tooltip.reset_size()
	var target := local + Vector2(16, -_tooltip.size.y - 12)
	target.x = clampf(target.x, 8.0, maxf(8.0, size.x - _tooltip.size.x - 8.0))
	target.y = clampf(target.y, 8.0, maxf(8.0, size.y - _tooltip.size.y - 8.0))
	_tooltip.position = target
	_tooltip.pivot_offset = Vector2(0, _tooltip.size.y)
	_tooltip.modulate.a = 0.0
	_tooltip.scale = Vector2(0.92, 0.92)
	if _tooltip_tween != null and _tooltip_tween.is_valid():
		_tooltip_tween.kill()
	_tooltip_tween = MotionKit.tween(self)
	_tooltip_tween.set_parallel(true)
	_tooltip_tween.tween_property(_tooltip, "modulate:a", 1.0, 0.14)
	_tooltip_tween.tween_property(_tooltip, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _hide_tooltip() -> void:
	if _tooltip == null or not _tooltip.visible:
		return
	if _tooltip_tween != null and _tooltip_tween.is_valid():
		_tooltip_tween.kill()
	_tooltip_tween = MotionKit.tween(self)
	_tooltip_tween.tween_property(_tooltip, "modulate:a", 0.0, 0.12)
	_tooltip_tween.tween_callback(func():
		if is_instance_valid(_tooltip):
			_tooltip.visible = false
	)


# ---------------- 骰子 / 路径 / 事件反馈 ----------------

func play_dice_roll(value: int) -> void:
	_build_dice()
	_layout_dice()
	_dice.visible = true
	_dice.modulate.a = 1.0
	_dice.face = 1 + randi() % 6
	_dice.rotation = 0.0
	_dice.scale = Vector2.ONE * 0.55
	_dice.queue_redraw()
	AudioFX.play("whoosh")
	_keep_awake(1600)
	if _dice_tween != null and _dice_tween.is_valid():
		_dice_tween.kill()
	var tween := MotionKit.tween(self)
	_dice_tween = tween
	tween.tween_property(_dice, "scale", Vector2.ONE, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	for index in 9:
		tween.tween_callback(func():
			if not is_instance_valid(_dice):
				return
			_dice.face = 1 + randi() % 6
			_dice.rotation = randf_range(-0.09, 0.09)
			_dice.scale = Vector2.ONE * randf_range(0.94, 1.06)
			_dice.queue_redraw()
		)
		tween.tween_interval(0.065)
	tween.tween_callback(func():
		if not is_instance_valid(_dice):
			return
		_dice.face = clampi(value, 1, 6)
		_dice.rotation = 0.0
		_dice.scale = Vector2.ONE * 1.22
		_dice.queue_redraw()
		AudioFX.play("select")
	)
	tween.tween_property(_dice, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_interval(0.34)
	tween.tween_property(_dice, "modulate:a", 0.0, 0.18)
	tween.tween_callback(func():
		if is_instance_valid(_dice):
			_dice.visible = false
	)


func show_path(from_index: int, steps: int) -> void:
	if steps <= 0 or tile_visuals.is_empty():
		return
	for tween in _path_tweens:
		if tween != null and tween.is_valid():
			tween.kill()
	_path_tweens.clear()
	for ring in _path_rings:
		ring.visible = false
	var total := mini(steps, _path_rings.size())
	for step in range(1, total + 1):
		var index := (from_index + step) % 32
		if not tile_visuals.has(index):
			continue
		var ring: Node3D = _path_rings[step - 1]
		var tile: Node3D = tile_visuals[index]
		ring.visible = true
		ring.position = tile.position + Vector3(0, 0.2, 0)
		ring.scale = Vector3.ONE * 0.4
		var tween := MotionKit.tween(self)
		tween.tween_interval(0.16 + float(step - 1) * 0.18)
		tween.tween_property(ring, "scale", Vector3.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.tween_property(ring, "scale", Vector3.ONE * 1.06, 0.36).set_trans(Tween.TRANS_SINE)
		tween.tween_property(ring, "scale", Vector3.ONE * 0.96, 0.36).set_trans(Tween.TRANS_SINE)
		tween.tween_interval(1.1)
		tween.tween_property(ring, "scale", Vector3.ONE * 0.05, 0.22)
		tween.tween_callback(func():
			if is_instance_valid(ring):
				ring.visible = false
		)
		_path_tweens.append(tween)
	_keep_awake(2600 + total * 180)


func celebrate(tile_index: int, kind: String = "coin", count: int = 10) -> void:
	if not tile_visuals.has(tile_index):
		return
	_ensure_effects()
	_effects.burst(_screen_of(tile_index) + Vector2(0, -6), kind, count)
	_keep_awake(1500)


func bounce_icon(tile_index: int, symbol: String) -> void:
	if not tile_visuals.has(tile_index):
		return
	_ensure_effects()
	_effects.icon(_screen_of(tile_index) + Vector2(0, -26), symbol)
	_keep_awake(1500)


func _screen_of(index: int) -> Vector2:
	if not tile_visuals.has(index) or viewport == null or viewport.size.x <= 0:
		return size * 0.5
	var node: Node3D = tile_visuals[index]
	var projected := camera.unproject_position(node.global_position + Vector3(0, 0.6, 0))
	return Vector2(
		projected.x / float(viewport.size.x) * size.x,
		projected.y / float(viewport.size.y) * size.y
	)
