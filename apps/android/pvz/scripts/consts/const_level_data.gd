extends RefCounted
class_name ConstLevelData

#region 游戏背景
## 游戏场景
enum GameBg {
	FrontDay,
	FrontNight,
	Pool,
	Fog,
	Roof,
	RoofNight
}

## 背景图
const GameBgTextureMap: Dictionary = {
	GameBg.FrontDay: preload("res://assets/garden/runtime/lawn.webp"),
	GameBg.FrontNight: preload("res://assets/garden/runtime/original/night.webp"),
	GameBg.Pool: preload("res://assets/garden/runtime/original/pool.webp"),
	GameBg.Fog: preload("res://assets/garden/runtime/original/fog.webp"),
	GameBg.Roof: preload("res://assets/garden/runtime/original/roof.webp"),
	GameBg.RoofNight: preload("res://assets/garden/runtime/original/roof.webp"),

}
#endregion

#region 音乐
enum GameBGM {
	FrontDay,
	FrontNight,
	Pool,
	Fog,
	Roof,
	MiniGame,
	Boss,
	Puzzle,
}

## BGM 资源路径
const GameBGMMap: Dictionary[GameBGM, String] = {
	GameBGM.FrontDay: "res://assets/garden/pvz-audio/BGM/front_day.mp3.res",
	GameBGM.FrontNight: "res://assets/garden/pvz-audio/BGM/front_night.mp3.res",
	GameBGM.Pool: "res://assets/garden/pvz-audio/BGM/pool.mp3.res",
	GameBGM.Fog: "res://assets/garden/music/fog.mp3",
	GameBGM.Roof: "res://assets/garden/music/roof.mp3",
	GameBGM.MiniGame: "res://assets/garden/pvz-audio/BGM/mini_game.mp3.res",
	GameBGM.Boss: "res://assets/garden/music/boss.mp3",
	GameBGM.Puzzle: "res://assets/garden/music/puzzle.mp3",
}
#endregion

#region 出怪
## 出怪模式。新增模式追加在末尾，保留关卡资源中已保存的枚举编号。
enum E_MonsterMode {
	Null = 0, ## 不启动自然波次，仍可配置开战时生成的僵王
	Norm = 1, ## 正常出怪模式
	HammerZombie = 2, ## 锤僵尸出怪模式
}
#endregion

#region 卡槽
## 卡槽模式
enum E_CardMode {
	Null,
	Norm,
	ConveyorBelt,
	Coin, ## 金币卡槽(雪人du狗小游戏)
}
#endregion

#region 罐子
## 罐子的生成模式
enum E_PotMode {
	Null, ## 无
	Weight, ## 根据权重随机生成罐子
	Fixd, ## 固定生成，随机位置
}
#endregion
