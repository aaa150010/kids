extends MainGameSubManager
class_name BackgroundManager
## 背景管理器,管理背景和前景

@onready var background: Sprite2D = %Background
@onready var frontground: Node2D = %Frontground

@onready var home: MainGameHome = %Home
## 泳池
var pool:Pool
## 浓雾
var fog:Fog

## 雨
var rain:MainGameRain

## 雾
const FOG = preload("res://pvz/scenes/main_game_bg/fog.tscn")
const RAIN = preload("res://pvz/scenes/main_game_bg/rain.tscn")


func init_manager() -> void:
	init_background()
	init_frontground()

## 初始化背景
func init_background():
	var curr_bg_texture: Texture2D = ConstLevelData.GameBgTextureMap[game_para.game_BG]
	background.texture = curr_bg_texture
	# 本地花园素材按 2× 绘制尺寸保存，上游原版布局按 1400×600 的背景坐标。
	background.scale = Vector2(0.5, 0.5)
	home.init_home(game_para.game_BG)
	if not game_para.is_zombie_can_home:
		print("僵尸无法进房")
		home.disable_home()
	match game_para.game_BG:
		ConstLevelData.GameBg.Pool, ConstLevelData.GameBg.Fog:
			pool = background.get_node(^"Pool")
			pool.init_pool(game_para)

## 初始化前景
func init_frontground():
	if game_para.is_fog:
		fog = FOG.instantiate()
		frontground.add_child(fog)
	if game_para.is_rain:
		rain = RAIN.instantiate()
		frontground.add_child(rain)

## 展示下一轮僵尸前退雾；直接进入下一轮时保留当前三叶草效果和移动。
func start_next_game_background_manager_update():
	if game_para.look_show_zombie and is_instance_valid(fog):
		fog.fog_outside()
