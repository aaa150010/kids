extends SceneTree

const GAME_SCRIPTS := {
	"island": "res://src/games/island_game.gd",
	"jungle": "res://src/games/board_game.gd",
	"poetry": "res://src/games/poetry_game.gd",
	"math": "res://src/games/quiz_game.gd",
	"pinyin": "res://src/games/quiz_game.gd",
	"memory": "res://src/games/memory_game.gd",
	"patterns": "res://src/games/quiz_game.gd",
	"animals": "res://src/games/quiz_game.gd",
	"gomoku": "res://src/games/board_game.gd",
	"military": "res://src/games/board_game.gd",
	"garden": "res://src/games/garden_game.gd",
	"workbook": "res://src/games/quiz_game.gd",
	"stories": "res://src/games/story_game.gd",
}
const SIZES := [
	{"label":"3000x2120", "logical":Vector2i(1600, 1129), "physical":Vector2i(3000, 2120)},
	{"label":"3392x2400", "logical":Vector2i(1600, 1129), "physical":Vector2i(3392, 2400)},
	{"label":"1180x800", "logical":Vector2i(1180, 800), "physical":Vector2i(1180, 800)},
]
const MIN_TOUCH_SIZE := 48.0

var output_dir := ""
var issues: Array[String] = []
var performance_lines: Array[String] = []
var save_store: Node
var content: Node


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	save_store = root.get_node_or_null("SaveStore")
	content = root.get_node_or_null("ContentDB")
	if save_store == null or content == null:
		quit(1)
		return
	save_store.set_setting("speechOn", false)
	save_store.set_setting("musicOn", false)
	var update_service := root.get_node_or_null("UpdateService")
	if update_service != null:
		update_service.checking = true
	if save_store.profiles().size() < 2:
		save_store.add_profile("小探险家", 7, "🦊", "#d56c29")
		save_store.add_profile("小搭档", 9, "🐼", "#2878c8")
	output_dir = ProjectSettings.globalize_path("res://").path_join("../../build/ui-audit")
	DirAccess.make_dir_recursive_absolute(output_dir)
	for dimensions in SIZES:
		await _capture_lobby(dimensions)
		if OS.get_environment("KIDS_UI_LOBBY_ONLY") != "1":
			await _capture_games(dimensions)
	var report := "\n".join(issues) if not issues.is_empty() else "No visible touch-target issues found."
	var file := FileAccess.open(output_dir.path_join("layout-report.txt"), FileAccess.WRITE)
	file.store_string(report)
	file.close()
	var performance_file := FileAccess.open(output_dir.path_join("performance-report.txt"), FileAccess.WRITE)
	performance_file.store_string("\n".join(performance_lines))
	performance_file.close()
	print("UI snapshots saved to: ", output_dir)
	print(report)
	quit(0)


func _make_viewport(dimensions: Vector2i) -> SubViewport:
	var viewport := SubViewport.new()
	viewport.size = dimensions
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	root.add_child(viewport)
	return viewport


func _capture_lobby(capture: Dictionary) -> void:
	var viewport := _make_viewport(capture.logical)
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	viewport.add_child(scene)
	await _frames(8)
	if scene.has_method("_on_intro_finished"):
		scene.call("_on_intro_finished")
	await _frames(6)
	var grid := scene.get("card_grid") as GridContainer
	if grid != null:
		print("lobby cards=", grid.get_child_count(), " grid=", grid.size, " viewport=", capture.logical)
	_audit(scene, "lobby")
	await _sample_performance("lobby-%s" % capture.label)
	await _save(viewport, capture, "lobby")
	scene.call("_show_profile_form", {})
	await _frames(8)
	_audit(scene, "profile-form")
	await _save(viewport, capture, "profile-form")
	viewport.queue_free()
	await _frames(2)


func _capture_games(capture: Dictionary) -> void:
	for meta in content.games:
		var game_id := str(meta.id)
		if not GAME_SCRIPTS.has(game_id):
			continue
		var mode := _screenshot_mode(game_id)
		var minimum := int(mode.get("player_range", [1, 2])[0])
		var selected: Array = save_store.profiles().slice(0, maxi(1, minimum))
		var viewport := _make_viewport(capture.logical)
		var configured: Dictionary = meta.duplicate(true)
		configured.modeId = str(mode.id)
		configured.difficultyPreference = "normal"
		# 每个尺寸使用干净的一局，避免上一个视口退出时保存的暂停态串到下一次截图。
		save_store.data.gameSaves.erase(game_id)
		save_store.data.sessionSaves.erase(game_id)
		var script: GDScript = load(GAME_SCRIPTS[game_id])
		var screen = script.new()
		screen.setup(configured, selected)
		viewport.add_child(screen)
		await _frames(12)
		print("capturing ",game_id," ",capture.label)
		_audit(screen, game_id)
		await _sample_performance("%s-%s" % [game_id, capture.label])
		await _save(viewport, capture, game_id)
		if game_id == "stories" and not content.stories.is_empty():
			screen.call("_open_story", str(content.stories[0].id), false)
			await _frames(12)
			_audit(screen, "stories-reading")
			await _sample_performance("stories-reading-%s" % capture.label)
			await _save(viewport, capture, "stories-reading")
		screen.toggle_pause(true)
		await _frames(5)
		await _save(viewport, capture, game_id + "-pause")
		viewport.queue_free()
		await _frames(2)


func _screenshot_mode(game_id: String) -> Dictionary:
	var modes: Array = content.modes(game_id)
	var preferred: String = str({
		"math":"practice", "pinyin":"practice", "patterns":"practice", "animals":"practice",
		"workbook":"classic", "memory":"classic", "jungle":"classic", "gomoku":"classic",
		"military":"classic", "island":"classic", "poetry":"classic", "garden":"classic",
	}.get(game_id,"classic"))
	for mode in modes:
		if str(mode.id) == str(preferred):
			return mode
	for mode in modes:
		if int(mode.get("player_range", [2, 2])[0]) <= 1:
			return mode
	return modes[0]


func _audit(node: Node, label: String) -> void:
	for child in node.find_children("*", "Button", true, false):
		var button := child as Button
		if button == null:
			continue
		if not button.is_visible_in_tree():
			continue
		if button.size.y > 0.0 and button.size.y < MIN_TOUCH_SIZE:
			issues.append("%s: button '%s' height %.1f < %.1f" % [label, button.text, button.size.y, MIN_TOUCH_SIZE])
		if button.size.x > 0.0 and button.size.x < MIN_TOUCH_SIZE:
			issues.append("%s: button '%s' width %.1f < %.1f" % [label, button.text, button.size.x, MIN_TOUCH_SIZE])


func _save(viewport: SubViewport, capture: Dictionary, name: String) -> void:
	await _frames(2)
	RenderingServer.force_draw(false)
	var image := viewport.get_texture().get_image()
	var physical: Vector2i = capture.physical
	if image.get_size() != physical:
		image.resize(physical.x, physical.y, Image.INTERPOLATE_LANCZOS)
	var folder := output_dir.path_join(str(capture.label))
	DirAccess.make_dir_recursive_absolute(folder)
	image.save_png(folder.path_join(name + ".png"))


func _frames(count: int) -> void:
	for index in count:
		await process_frame


func _sample_performance(label: String) -> void:
	var samples: Array[float] = []
	var previous := Time.get_ticks_usec()
	for index in 40:
		await process_frame
		var now := Time.get_ticks_usec()
		samples.append(float(now-previous)/1000.0)
		previous = now
	samples.sort()
	var total := 0.0
	for value in samples:
		total += value
	var average := total / maxf(1.0,float(samples.size()))
	var p95 := samples[mini(samples.size()-1,int(samples.size()*0.95))]
	performance_lines.append("%s avg=%.2fms p95=%.2fms fps=%.1f" % [label,average,p95,1000.0/maxf(0.01,average)])
