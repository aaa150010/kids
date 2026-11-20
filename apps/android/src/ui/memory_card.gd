class_name MemoryCard
extends Button

## 卡背自绘图案：按主题画爪印/圆点/条纹/方格，铺满卡背面板
class BackPattern:
	extends Control
	var pattern_theme := "animals"
	var ink := Color("#b2662f")

	func _ready() -> void:
		# 卡片随网格拉伸时图案按新尺寸重画
		resized.connect(queue_redraw)

	func _draw() -> void:
		match pattern_theme:
			"animals":
				# 爪印：一个大肉垫 + 三个小脚趾，两处错落
				_paw(size * Vector2(0.3, 0.3), 0.9)
				_paw(size * Vector2(0.7, 0.72), 1.15)
			"fruits":
				# 圆点阵：3x3 小圆
				for row in 3:
					for col in 3:
						var pos := size * Vector2(0.22 + 0.28 * col, 0.22 + 0.28 * row)
						draw_circle(pos, minf(size.x, size.y) * 0.05, ink)
			"vehicles":
				# 横纹：马路条纹感
				var y := size.y * 0.14
				while y < size.y * 0.9:
					draw_rect(Rect2(8.0, y, size.x - 16.0, 7.0), ink)
					y += 22.0
			"objects":
				# 方格：错排棋盘格
				var cell := (size.x - 16.0) / 4.0
				for row in 4:
					for col in 4:
						if (row + col) % 2 == 0:
							var origin := Vector2(8.0 + col * cell, size.y * 0.12 + row * cell * 0.85)
							draw_rect(Rect2(origin + Vector2(2, 2), Vector2(cell - 4, cell * 0.85 - 4)), ink)

	func _paw(center: Vector2, scale_factor: float) -> void:
		# 肉垫画成横向微扁的圆
		draw_set_transform(center, 0.0, Vector2(1.25, 1.0))
		draw_circle(Vector2.ZERO, 10.0 * scale_factor, ink)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		for toe in [-1, 0, 1]:
			draw_circle(center + Vector2(toe * 11.0 * scale_factor, -14.0 * scale_factor), 4.2 * scale_factor, ink)


## 配对成功金色星光：自绘小圆点 + 十字光芒向外扩散并淡出
class StarBurst:
	extends Control
	var progress := 0.0
	var _tween: Tween

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		# 画幅向外扩一圈，星光可以越过卡片边缘
		offset_left = -48
		offset_top = -48
		offset_right = 48
		offset_bottom = 48
		_tween = create_tween()
		MotionKit.adopt(self, _tween)
		_tween.tween_method(_advance, 0.0, 1.0, 0.5)
		_tween.tween_callback(queue_free)

	func _advance(value: float) -> void:
		progress = value
		queue_redraw()

	func _draw() -> void:
		var center := size * 0.5
		var alpha := 1.0 - progress
		for index in 8:
			var angle := TAU * float(index) / 8.0 + 0.4
			var pos := center + Vector2(cos(angle), sin(angle)) * (14.0 + progress * 52.0)
			var radius := 4.5 * (1.0 - progress * 0.6)
			draw_circle(pos, radius, Color("#ffd34d", alpha))
			var arm := radius * 1.8
			var shine := Color("#fff6d8", alpha)
			draw_line(pos + Vector2(-arm, 0), pos + Vector2(arm, 0), shine, 1.5)
			draw_line(pos + Vector2(0, -arm), pos + Vector2(0, arm), shine, 1.5)


# 四主题卡背配色：面板底色 / 描边 / 图案色
const BACK_STYLES := {
	"animals": {"bg": Color("#d98850"), "border": Color("#fff0dc"), "ink": Color("#b2662f")},
	"fruits": {"bg": Color("#d6657c"), "border": Color("#ffe3ea"), "ink": Color("#f2aebe")},
	"vehicles": {"bg": Color("#5b8dd6"), "border": Color("#e3efff"), "ink": Color("#a9c8ef")},
	"objects": {"bg": Color("#7a9e5f"), "border": Color("#eef7e3"), "ink": Color("#b9d0a2")},
}

var picture: TextureRect
var title: Label
var face: Control
var reverse: PanelContainer
var revealed := false
var paired := false
var transition: Tween
var pending_card: Dictionary = {}
var theme_id := "animals"
var _pattern: BackPattern
var _shake_tween: Tween
var _celebrate_tween: Tween

func _ready() -> void:
	custom_minimum_size = Vector2(90,116)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_stylebox_override("normal",PlaygroundUI.style(Color("#fff9ee"),20,Color("#ca8dad"),2,4,Color(0,0,0,0.12)))
	add_theme_stylebox_override("hover",PlaygroundUI.style(Color("#fffdf7"),20,Color("#c05b8f"),3))
	add_theme_stylebox_override("pressed",PlaygroundUI.style(Color("#f5dfeb"),20,Color("#c05b8f"),3))
	add_theme_stylebox_override("disabled",PlaygroundUI.style(Color("#eaf2df"),20,Color("#9bb67b"),2))
	face = VBoxContainer.new()
	face.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	face.offset_left = 10
	face.offset_right = -10
	face.offset_top = 8
	face.offset_bottom = -8
	picture = TextureRect.new()
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.custom_minimum_size = Vector2(60,70)
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	picture.size_flags_vertical = Control.SIZE_EXPAND_FILL
	face.add_child(picture)
	title = PlaygroundUI.label("",19,PlaygroundUI.INK,700,true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	face.add_child(title)
	add_child(face)
	reverse = PanelContainer.new()
	reverse.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 图案裁剪在面板矩形内，避免条纹/方格溢出圆角
	reverse.clip_contents = true
	reverse.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	reverse.offset_left = 8
	reverse.offset_top = 4
	reverse.offset_right = -8
	reverse.offset_bottom = -4
	# 卡背图案垫在文字下面，随主题换色换图案
	_pattern = BackPattern.new()
	_pattern.mouse_filter = Control.MOUSE_FILTER_IGNORE
	reverse.add_child(_pattern)
	var back_center := CenterContainer.new()
	back_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	reverse.add_child(back_center)
	var back_copy := VBoxContainer.new()
	back_copy.alignment = BoxContainer.ALIGNMENT_CENTER
	back_copy.add_theme_constant_override("separation",4)
	var mark := ArtLibrary.semantic_picture("game","ui",Vector2(42,42))
	mark.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back_copy.add_child(mark)
	var hint := PlaygroundUI.label("翻一翻",16,Color("#fff5f8"),700)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	back_copy.add_child(hint)
	back_center.add_child(back_copy)
	add_child(reverse)
	resized.connect(func(): pivot_offset = size*0.5)
	face.hide()
	_apply_theme()
	# 按压反馈：按下 0.95 + 轻提示音，翻开时仍走 _flip 的 flip 音
	PressFeedback.attach(self, &"tap")
	if not pending_card.is_empty():
		_apply_card()

## 切换卡背主题（动物/水果/交通/物品），可在 _ready 前调用
func set_card_theme(value: String) -> void:
	theme_id = value if BACK_STYLES.has(value) else "animals"
	_apply_theme()

func _apply_theme() -> void:
	if reverse == null:
		return
	var palette: Dictionary = BACK_STYLES.get(theme_id, BACK_STYLES["animals"])
	reverse.add_theme_stylebox_override("panel",PlaygroundUI.style(palette.bg,22,palette.border,3,5,Color(0,0,0,0.16)))
	if _pattern != null:
		_pattern.pattern_theme = theme_id
		_pattern.ink = palette.ink
		_pattern.queue_redraw()

func configure(card: Dictionary) -> void:
	pending_card = card.duplicate(true)
	if title != null and picture != null:
		_apply_card()


func _apply_card() -> void:
	title.text = str(pending_card.get("name",""))
	picture.texture = ArtLibrary.semantic_texture(str(pending_card.get("name",pending_card.get("id",""))),"memory")

func show_face(value: bool, is_paired: bool, locked: bool, animate: bool = true) -> void:
	disabled = locked or value or is_paired
	paired = is_paired
	if revealed == value:
		if not value and reverse != null:
			face.hide()
			reverse.show()
		return
	revealed = value
	if transition != null:
		transition.kill()
	# 翻牌动画接管 transform：清掉按压/抖动/庆祝 tween，避免缩放互相打架
	MotionKit.kill_owner(self)
	scale = Vector2.ONE
	rotation = 0.0
	if not animate:
		face.visible = value
		reverse.visible = not value
		scale = Vector2.ONE
		return
	transition = create_tween()
	var parent := get_parent()
	var screen: NativeGameScreen = null
	while parent != null and not parent is NativeGameScreen:
		parent = parent.get_parent()
	if parent != null:
		screen = parent
		transition.set_meta("screen_owner",parent.get_instance_id())
		MotionKit.adopt(screen, transition)
	transition.tween_property(self,"scale:x",0.04,0.11)
	transition.tween_callback(func(): face.visible = revealed; reverse.visible = not revealed)
	transition.tween_property(self,"scale:x",1.0,MotionKit.FLIP-0.11).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if is_paired:
		transition.tween_property(self,"modulate",Color("#fff0a8"),0.08)
		transition.tween_property(self,"modulate",Color.WHITE,0.15)

## 不匹配：左右抖动 0.3 秒（±3° 正弦衰减），结束后回调由游戏层翻回
func shake(on_done: Callable = Callable()) -> void:
	if _shake_tween != null:
		_shake_tween.kill()
	pivot_offset = size * 0.5
	_shake_tween = MotionKit.tween(self)
	_shake_tween.tween_method(_apply_shake, 0.0, 1.0, 0.3)
	_shake_tween.tween_callback(func():
		rotation = 0.0
		if on_done.is_valid():
			on_done.call()
	)

func _apply_shake(progress: float) -> void:
	# 三个来回、幅度线性衰减
	rotation = sin(progress * TAU * 3.0) * deg_to_rad(3.0) * (1.0 - progress)

## 配对成功：向上跳起（1.0→1.12→1.0 回弹）+ 金色星光 + 淡金闪光
func celebrate() -> void:
	if _celebrate_tween != null:
		_celebrate_tween.kill()
	pivot_offset = size * 0.5
	_celebrate_tween = MotionKit.tween(self)
	_celebrate_tween.tween_property(self,"scale",Vector2.ONE * 1.12,0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_celebrate_tween.tween_property(self,"scale",Vector2.ONE,0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var flash := MotionKit.tween(self)
	flash.tween_property(self,"modulate",Color("#ffe9a0"),0.08)
	flash.tween_property(self,"modulate",Color.WHITE,0.3)
	add_child(StarBurst.new())
