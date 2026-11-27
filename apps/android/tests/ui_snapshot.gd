extends SceneTree

const GAME_SCRIPTS := {
	"jungle": "res://src/games/board_game.gd",
	"poetry": "res://src/games/poetry_game.gd",
	"math": "res://src/games/quiz_game.gd",
	"pinyin": "res://src/games/quiz_game.gd",
	"memory": "res://src/games/memory_game.gd",
	"patterns": "res://src/games/quiz_game.gd",
	"animals": "res://src/games/quiz_game.gd",
	"tangram": "res://src/games/tangram_game.gd",
	"spot": "res://src/games/spot_game.gd",
	"shop": "res://src/games/shop_game.gd",
	"fruit_slice": "res://src/games/fruit_slice_game.gd",
	"robot": "res://src/games/robot_game.gd",
	"sentence_train": "res://src/games/sentence_train_game.gd",
	"pipes": "res://src/games/pipe_game.gd",
	"trivia": "res://src/games/quiz_game.gd",
	"gomoku": "res://src/games/board_game.gd",
	"chess": "res://src/games/chess_game.gd",
	"sudoku": "res://src/games/sudoku_game.gd",
	"military": "res://src/games/military_game.gd",
	"workbook": "res://src/games/quiz_game.gd",
	"stories": "res://src/games/story_game.gd",
}
const SIZES := [
	{"label":"3000x2120", "logical":Vector2i(1600, 1129), "physical":Vector2i(3000, 2120)},
]
const COMPACT_SIZE := {"label":"1180x800", "logical":Vector2i(1180, 800), "physical":Vector2i(1180, 800)}
const LARGE_SIZE := {"label":"3392x2400", "logical":Vector2i(1600, 1129), "physical":Vector2i(3392, 2400)}
const TABLETOP_GAMES := ["chess", "military", "jungle", "gomoku"]
const MIN_TOUCH_SIZE := 48.0

var output_dir := ""
var issues: Array[String] = []
var performance_lines: Array[String] = []
var save_store: Node
var content: Node
var fatal_failure := false
var dry_run := false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	dry_run = OS.get_environment("KIDS_UI_DRY_RUN") == "1"
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
	_seed_story_illustrations()
	var requested_size := OS.get_environment("KIDS_UI_SIZE")
	var capture_sizes: Array = SIZES.duplicate()
	if requested_size == str(COMPACT_SIZE.label):
		capture_sizes.append(COMPACT_SIZE)
	elif requested_size == str(LARGE_SIZE.label):
		capture_sizes.append(LARGE_SIZE)
	for dimensions in capture_sizes:
		if not requested_size.is_empty() and str(dimensions.label) != requested_size:
			continue
		await _capture_lobby(dimensions)
		if fatal_failure:
			break
		if OS.get_environment("KIDS_UI_LOBBY_ONLY") != "1":
			await _capture_games(dimensions)
		if fatal_failure:
			break
	var report := "\n".join(issues) if not issues.is_empty() else "No visible touch-target or board-mapping issues found."
	var file := FileAccess.open(output_dir.path_join("layout-report.txt"), FileAccess.WRITE)
	file.store_string(report)
	file.close()
	var performance_file := FileAccess.open(output_dir.path_join("performance-report.txt"), FileAccess.WRITE)
	performance_file.store_string("\n".join(performance_lines))
	performance_file.close()
	print("UI snapshots saved to: ", output_dir)
	print(report)
	quit(0 if issues.is_empty() else 1)


func _seed_story_illustrations() -> void:
	var stories: Array = content.stories
	if stories.is_empty():
		return
	var story: Dictionary = stories[0]
	var cache_dir := ProjectSettings.globalize_path("user://story-images/")
	DirAccess.make_dir_recursive_absolute(cache_dir)
	for illustration in story.get("illustrations", []):
		var source := str(illustration.get("remoteUrl", ""))
		var marker := "/story-images/"
		var split := source.find(marker)
		if split < 0:
			continue
		source = ProjectSettings.globalize_path("res://../../content-src/assets/stories/") + source.substr(split + marker.length())
		var destination := cache_dir + str(illustration.get("sha256", "")) + ".webp"
		if FileAccess.file_exists(source):
			DirAccess.copy_absolute(source, destination)
			illustration.asset = source


func _fail(message: String) -> void:
	issues.append(message)
	fatal_failure = true
	push_error(message)


func _make_viewport(dimensions: Vector2i) -> SubViewport:
	var viewport := SubViewport.new()
	viewport.size = dimensions
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	root.add_child(viewport)
	return viewport


func _capture_lobby(capture: Dictionary) -> void:
	var viewport := _make_viewport(capture.logical)
	var packed: PackedScene = load("res://scenes/main.tscn")
	if packed == null or not packed.can_instantiate():
		_fail("lobby: main scene cannot be instantiated")
		viewport.queue_free()
		return
	var scene: Node = packed.instantiate()
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
	var search_edit: LineEdit = scene.get("_search_edit") as LineEdit
	var search_empty: Control = scene.get("_search_empty") as Control
	if grid != null and search_edit != null:
		var original_order: Array[String] = []
		for card in grid.get_children():
			if card is LobbyGameCard:
				original_order.append((card as LobbyGameCard).game_id)
		search_edit.text = "水果"
		scene.call("_on_lobby_search_changed", "水果")
		scene.call("_apply_lobby_search")
		await _frames(3)
		var visible_cards := grid.get_children().filter(
			func(card): return card is LobbyGameCard and (card as LobbyGameCard).visible
		)
		if visible_cards.size() != 1 or str((visible_cards[0] as LobbyGameCard).game_id) != "fruit_slice":
			_fail("lobby: searching 水果 must leave only the fruit slice card visible")
			viewport.queue_free()
			return
		var filtered_order: Array[String] = []
		for card in grid.get_children():
			if card is LobbyGameCard:
				filtered_order.append((card as LobbyGameCard).game_id)
		if filtered_order != original_order:
			_fail("lobby: search filtering must not rebuild or reorder cards")
			viewport.queue_free()
			return
		await _save(viewport, capture, "lobby-search")
		search_edit.text = "完全不存在的小游戏"
		scene.call("_on_lobby_search_changed", "完全不存在的小游戏")
		scene.call("_apply_lobby_search")
		await _frames(3)
		if search_empty == null or not search_empty.visible:
			_fail("lobby: unknown search must expose the empty state")
			viewport.queue_free()
			return
		await _save(viewport, capture, "lobby-search-empty")
		scene.call("_clear_lobby_search")
		await _frames(3)
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
		var selected_games := OS.get_environment("KIDS_UI_GAMES")
		if not selected_games.is_empty() and not (game_id in selected_games.split(",", false)):
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
		if script == null or not script.can_instantiate():
			_fail("%s: game script cannot be instantiated" % game_id)
			viewport.queue_free()
			return
		var screen: Control = script.new()
		if screen == null or not screen.has_method("setup"):
			_fail("%s: game screen is unavailable" % game_id)
			viewport.queue_free()
			return
		screen.call("setup", configured, selected)
		viewport.add_child(screen)
		await _frames(12)
		if screen.has_method("_finish_lesson"):
			screen.call("_finish_lesson")
			await _frames(3)
		if game_id == "military" and screen.has_method("preview_ready"):
			screen.call("preview_ready")
			await _frames(4)
		print("capturing ",game_id," ",capture.label)
		_audit(screen, game_id)
		if game_id in TABLETOP_GAMES:
			_audit_board(screen, game_id)
		if game_id == "chess":
			_audit_chess_factions(screen)
		if fatal_failure:
			viewport.queue_free()
			return
		await _sample_performance("%s-%s" % [game_id, capture.label])
		await _save(viewport, capture, game_id)
		if game_id in ["tangram", "spot", "shop"]:
			screen.call("_choose_level", 1)
			await _frames(14)
			_audit(screen, "%s-play" % game_id)
			await _save(viewport, capture, game_id + "-play")
			if fatal_failure:
				viewport.queue_free()
				return
		if game_id == "fruit_slice":
			await _capture_fruit_effects(viewport, capture, screen)
			if fatal_failure:
				viewport.queue_free()
				return
		if game_id in TABLETOP_GAMES:
			await _capture_board_play(viewport, capture, screen, game_id)
			if fatal_failure:
				viewport.queue_free()
				return
			await _capture_rules_views(viewport, capture, screen, game_id)
			if fatal_failure:
				viewport.queue_free()
				return
		if game_id == "poetry":
			screen.call("draw_poem", "")
			await _frames(16)
			_audit(screen, "poetry-drawn")
			await _save(viewport, capture, "poetry-drawn")
		if game_id == "stories" and not content.stories.is_empty():
			screen.call("_open_story", str(content.stories[0].id), false)
			await _frames(12)
			_audit(screen, "stories-reading")
			await _sample_performance("stories-reading-%s" % capture.label)
			await _save(viewport, capture, "stories-reading")
		screen.call("toggle_pause", true)
		await _frames(14)
		await _save(viewport, capture, game_id + "-pause")
		viewport.queue_free()
		await _frames(2)


func _capture_fruit_effects(viewport: SubViewport, capture: Dictionary, screen: Control) -> void:
	var field: Control = screen.get("field") as Control
	var engine: RefCounted = screen.get("engine") as RefCounted
	if field == null or engine == null:
		_fail("fruit_slice: effect capture has no field or session")
		return
	field.call("_start_game")
	await _frames(3)
	for _index in 3:
		engine.call("_spawn_one")
	var state: Dictionary = engine.get("state")
	var fruits: Array = state.get("fruits", [])
	if fruits.size() < 3:
		_fail("fruit_slice: effect capture could not spawn three fruits")
		return
	for index in 3:
		var fruit: Dictionary = fruits[index]
		fruit.x = 0.28 + float(index) * 0.22
		fruit.y = 0.46 + float(index % 2) * 0.08
		fruit.vx = 0.0
		fruit.vy = -0.08
		fruit.spin = 0.0
		fruit.special = ""
	state.fruits = fruits
	field.queue_redraw()
	await _frames(5)
	var field_size: Vector2 = field.size
	for point_index in 5:
		var trail_point := Vector2(
			field_size.x * (0.18 + float(point_index) * 0.11),
			field_size.y * (0.62 - float(point_index) * 0.035)
		)
		field.call("_add_trail", 0, trail_point)
	_audit(screen, "fruit_slice-active")
	await _save(viewport, capture, "fruit_slice-active")
	for index in 3:
		var fruit: Dictionary = fruits[index]
		var point := Vector2(float(fruit.x) * field_size.x, float(fruit.y) * field_size.y)
		field.call("_slice", point, point + Vector2(8.0, 0.0))
	await _frames(2)
	_audit(screen, "fruit_slice-combo")
	await _save(viewport, capture, "fruit_slice-combo")
	await _frames(12)
	_audit(screen, "fruit_slice-halves")
	await _save(viewport, capture, "fruit_slice-halves")
	field.call("_apply_events", [{
		"type": "bomb",
		"x": 0.72,
		"y": 0.5,
		"radius": 0.06,
		"delta": -5,
		"penalty": 5,
	}])
	await _frames(4)
	_audit(screen, "fruit_slice-bomb")
	await _save(viewport, capture, "fruit_slice-bomb")


func _screenshot_mode(game_id: String) -> Dictionary:
	var modes: Array = content.modes(game_id)
	var preferred: String = str({
		"math":"practice", "pinyin":"practice", "patterns":"practice", "animals":"practice", "trivia":"practice",
		"tangram":"adventure", "spot":"adventure", "shop":"adventure", "fruit_slice":"practice",
		"robot":"adventure", "sentence_train":"adventure", "pipes":"adventure",
		"workbook":"classic", "memory":"classic", "jungle":"classic", "gomoku":"classic",
		"chess":"classic", "sudoku":"classic", "military":"classic", "poetry":"classic",
	}.get(game_id,"classic"))
	for mode in modes:
		if str(mode.id) == str(preferred):
			return mode
	for mode in modes:
		if int(mode.get("player_range", [2, 2])[0]) <= 1:
			return mode
	return modes[0]


func _board_for(screen: Control, game_id: String) -> Control:
	return screen.get("surface") as Control if game_id in ["jungle", "gomoku"] else screen.get("board") as Control


func _audit_chess_factions(screen: Control) -> void:
	var engine: RefCounted = screen.get("engine")
	if engine == null:
		_fail("chess: faction audit has no session")
		return
	var state: Dictionary = engine.get("state")
	var pieces: Array = state.get("pieces", [])
	for side in 2:
		var faction: Array = pieces.filter(func(piece): return int(piece.get("side", -1)) == side)
		var soldiers: Array = faction.filter(func(piece): return str(piece.get("kind", "")) == "soldier")
		if faction.size() != 16 or soldiers.size() != 5:
			_fail("chess: side %s must start with sixteen pieces and five soldiers" % side)
			return
		for soldier in soldiers:
			var actual_name := str(engine.call("piece_name", soldier))
			if actual_name != ("兵" if side == 0 else "卒"):
				_fail("chess: a soldier has the wrong faction name")
				return


func _audit_board(screen: Control, game_id: String) -> void:
	var board := _board_for(screen, game_id)
	if board == null or not board.has_method("position_for"):
		_fail("%s: board did not initialize" % game_id)
		return
	var engine: RefCounted = screen.get("engine")
	if engine == null or not engine.get("state") is Dictionary or (engine.get("state") as Dictionary).is_empty():
		_fail("%s: game session did not initialize" % game_id)
		return
	var cells := 90 if game_id == "chess" else 65 if game_id == "military" else 225 if game_id == "gomoku" else 63
	var metrics: Dictionary = board.call("metrics")
	var extent := Vector2.ONE * float(metrics.get("gap", metrics.get("spacing", 1.0))) * 0.49
	if game_id == "military":
		extent = Vector2(float(metrics.get("gap_x", 1.0)), float(metrics.get("gap_y", 1.0))) * 0.44
	var board_rect := Rect2(Vector2.ZERO, board.size)
	if board.has_method("audit_bounds"):
		var visible_bounds: Rect2 = board.call("audit_bounds")
		if not board_rect.encloses(visible_bounds):
			_fail("%s: visible board bounds exceed its allocated safe area" % game_id)
			return
	for index in cells:
		if game_id == "military" and int(index / 5) == 6:
			continue
		var point: Vector2 = board.call("position_for", index)
		var actual := int(board.call("_index_at" if game_id in ["jungle", "gomoku"] else "cell_at", point))
		if actual != index:
			_fail("%s: board point %s maps to %s" % [game_id, index, actual])
			return
		if not board_rect.encloses(Rect2(point - extent, extent * 2.0)):
			_fail("%s: edge piece at %s is clipped" % [game_id, index])
			return
	var viewport_rect := screen.get_viewport_rect()
	if not viewport_rect.encloses(board.get_global_rect()):
		_fail("%s: board extends beyond the viewport" % game_id)


func _next_board_move(engine: RefCounted, game_id: String) -> Dictionary:
	var state: Dictionary = engine.get("state")
	if str(state.get("phase", "")) != "playing":
		return {}
	if game_id == "chess":
		for piece in state.get("pieces", []):
			if int(piece.get("side", -1)) != int(state.get("turn", 0)) or str(piece.get("kind", "")) != "horse":
				continue
			var horse_targets: Array = engine.call("legal_targets", int(piece.get("position", -1)))
			if not horse_targets.is_empty():
				return {"from": int(piece.position), "to": int(horse_targets[0])}
	if game_id == "gomoku":
		var positions := [112, 113, 97, 98]
		for target in positions:
			if int(state.board[int(target)]) < 0:
				return {"to": int(target)}
		return {}
	var turn := int(state.get("turn", 0))
	for piece in state.get("pieces", []):
		if int(piece.get("side", -1)) != turn or int(piece.get("position", -1)) < 0:
			continue
		var from := int(piece.position)
		var before: Dictionary = state.duplicate(true)
		var targets: Array = engine.call("legal_moves", piece) if game_id == "jungle" else engine.call("legal_targets", from)
		if state != before:
			_fail("%s: querying legal moves changed the game state" % game_id)
			return {}
		for target in targets:
			var occupant: Dictionary = engine.call("piece_at", int(target))
			if occupant.is_empty():
				return {"from": from, "to": int(target)}
		if not targets.is_empty():
			return {"from": from, "to": int(targets[0])}
	return {}


func _capture_board_play(viewport: SubViewport, capture: Dictionary, screen: Control, game_id: String) -> void:
	var engine: RefCounted = screen.get("engine")
	if screen.has_method("_finish_lesson"):
		screen.call("_finish_lesson")
	if game_id in ["chess", "military"]:
		_audit_touch_mouse_dedup(_board_for(screen, game_id), game_id)
		if fatal_failure:
			return
	var first := _next_board_move(engine, game_id)
	if first.is_empty():
		_fail("%s: no opening move available" % game_id)
		return
	if first.has("from"):
		var select_action := {"type": "select", "position": int(first.from)}
		if game_id == "jungle":
			select_action["to"] = int(first.from)
		var select_result: Dictionary = engine.call("handle_input", select_action)
		if not bool(select_result.get("ok", false)):
			_fail("%s: the opening piece could not be selected" % game_id)
			return
		screen.call("_refresh")
		await _frames(4)
		_audit_board(screen, game_id)
		await _save(viewport, capture, game_id + "-selected")
	var move_action := {"type": "move", "to": int(first.to)}
	var move_result: Dictionary = engine.call("handle_input", move_action)
	if not bool(move_result.get("ok", false)):
		_fail("%s: the opening move was rejected" % game_id)
		return
	if game_id in ["jungle", "gomoku"]:
		screen.call("_refresh", true)
	else:
		screen.call("_refresh")
	await _frames(48)
	if int((engine.get("state") as Dictionary).get("turn", -1)) != 1:
		_fail("%s: the first move did not hand over to player 2" % game_id)
		return
	_audit_board(screen, game_id)
	await _save(viewport, capture, game_id + "-player2")
	var second := _next_board_move(engine, game_id)
	if second.is_empty():
		_fail("%s: player 2 has no reply" % game_id)
		return
	if second.has("from"):
		screen.call("_cell", int(second.from))
	screen.call("_cell", int(second.to))
	await _frames(48)
	_audit_board(screen, game_id)
	await _save(viewport, capture, game_id + "-both-moved")
	var snapshot: Dictionary = engine.call("snapshot")
	if not bool(engine.call("restore", snapshot)):
		_fail("%s: the played board cannot restore its snapshot" % game_id)
		return
	var restored: Dictionary = engine.get("state")
	for field in ["pieces", "board", "turn", "moveCount", "lastMove", "selected"]:
		if restored.get(field) != snapshot.get(field):
			_fail("%s: snapshot restoration changed %s" % [game_id, field])
			return
	screen.call("_refresh")
	await _frames(4)
	_audit_board(screen, game_id)
	await _save(viewport, capture, game_id + "-restored")
	if game_id != "gomoku":
		await _capture_prepared_capture(viewport, capture, screen, engine, game_id, snapshot)
	if game_id == "chess" and not fatal_failure:
		await _capture_chess_legacy_and_capture(viewport, capture, screen, engine, snapshot)


func _audit_touch_mouse_dedup(board: Control, game_id: String) -> void:
	var previous_connections := board.get_signal_connection_list("cell_pressed")
	for connection in previous_connections:
		board.disconnect("cell_pressed", connection.callable)
	var counts := [0]
	var listener := func(_position: int): counts[0] += 1
	board.connect("cell_pressed", listener)
	var old_touch := int(board.get("_touch_index"))
	var old_guard := int(board.get("_touch_guard_msec"))
	var point: Vector2 = board.call("position_for", 0)
	var touch := InputEventScreenTouch.new()
	touch.index = 0
	touch.position = point
	touch.pressed = true
	board.call("_gui_input", touch)
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.position = point
	mouse.pressed = true
	board.call("_gui_input", mouse)
	touch.pressed = false
	board.call("_gui_input", touch)
	mouse.pressed = false
	board.call("_gui_input", mouse)
	board.disconnect("cell_pressed", listener)
	for connection in previous_connections:
		board.connect("cell_pressed", connection.callable, int(connection.flags))
	board.set("_touch_index", old_touch)
	board.set("_touch_guard_msec", old_guard)
	if int(counts[0]) != 1:
		_fail("%s: one touch plus its emulated mouse event emitted %s cell presses" % [game_id, counts[0]])


func _capture_rules_views(viewport: SubViewport, capture: Dictionary, screen: Control, game_id: String) -> void:
	var previous_seat := int(screen.get("_interaction_seat"))
	for side in 2:
		screen.set("_interaction_seat", side)
		screen.call("show_game_rules")
		await _frames(32)
		var layers: Array = screen.get("_modal_stack")
		if layers.is_empty():
			_fail("%s: rules did not open for seat %s" % [game_id, side])
			return
		var layer: Control = layers.back()
		var seat_name := "left" if side == 0 else "right"
		_audit(layer, "%s-rules-%s" % [game_id, seat_name])
		_audit_modal_buttons(layer, screen.get_viewport_rect(), "%s-rules-%s" % [game_id, seat_name])
		await _save(viewport, capture, "%s-rules-%s" % [game_id, seat_name])
		screen.call("_close_top_modal")
		await _frames(32)
	screen.set("_interaction_seat", previous_seat)


func _audit_modal_buttons(layer: Control, viewport_rect: Rect2, label: String) -> void:
	for child in layer.find_children("*", "Button", true, false):
		var button := child as Button
		if button == null or not button.is_visible_in_tree():
			continue
		var transform := button.get_global_transform_with_canvas()
		var corners := [Vector2.ZERO, Vector2(button.size.x, 0.0), button.size, Vector2(0.0, button.size.y)]
		for corner in corners:
			var point: Vector2 = transform * Vector2(corner)
			if not viewport_rect.grow(1.0).has_point(point):
				_fail("%s: rotated action button '%s' extends beyond the viewport" % [label, button.text])
				return


func _capture_chess_legacy_and_capture(viewport: SubViewport, capture: Dictionary, screen: Control, engine: RefCounted, original: Dictionary) -> void:
	engine.call("create_session", {
		"gameId": "chess", "modeId": "classic", "players": original.players.duplicate(true), "seed": 12346,
	})
	var fresh: Dictionary = engine.call("snapshot")
	var legacy: Dictionary = fresh.duplicate(true)
	legacy.chessVersion = 1
	for piece in legacy.pieces:
		if int(piece.side) == 0 and str(piece.kind) == "soldier":
			var position := int(piece.position)
			piece.id = "1-soldier-6-%s" % (position % 9)
			piece.side = 1
	if not bool(engine.call("restore", legacy)):
		_fail("chess: the legacy wrong-faction red soldiers could not be recovered")
		return
	_audit_chess_factions(screen)
	if fatal_failure:
		return
	screen.call("_refresh")
	await _frames(4)
	await _save(viewport, capture, "chess-legacy-restored")
	if not bool(engine.call("restore", fresh)):
		_fail("chess: the clean classic opening could not be restored")
		return
	var before_query: Dictionary = (engine.get("state") as Dictionary).duplicate(true)
	var targets: Array = engine.call("legal_targets", 64)
	if (engine.get("state") as Dictionary) != before_query or not (1 in targets):
		_fail("chess: classic cannon capture query is invalid or changes the board")
		return
	var selected: Dictionary = engine.call("handle_input", {"type": "select", "position": 64})
	var moved: Dictionary = engine.call("handle_input", {"type": "move", "to": 1}) if bool(selected.get("ok", false)) else {"ok": false}
	if not bool(moved.get("ok", false)):
		_fail("chess: the classic cannon-over-screen capture failed")
		return
	var after_capture: Dictionary = engine.call("snapshot")
	if after_capture.pieces.size() != 31 or not bool(engine.call("restore", after_capture)):
		_fail("chess: a classic capture snapshot cannot restore all 31 surviving pieces")
		return
	var capture_state: Dictionary = engine.get("state")
	if capture_state.pieces != after_capture.pieces:
		_fail("chess: restoring a capture changed the surviving pieces")
		return
	engine.call("legal_targets", 0)
	if (engine.get("state") as Dictionary).pieces != after_capture.pieces:
		_fail("chess: querying a reply revived a captured piece")
		return
	screen.call("_refresh")
	await _frames(4)
	_audit_board(screen, "chess")
	await _save(viewport, capture, "chess-classic-capture-restored")
	if not bool(engine.call("undo_last_move")):
		_fail("chess: the restored classic capture could not be undone")
		return
	if (engine.get("state") as Dictionary).pieces != fresh.pieces:
		_fail("chess: undo did not restore the exact captured horse and opening")
		return
	screen.call("_refresh")
	await _frames(4)
	await _save(viewport, capture, "chess-capture-undone")
	if not bool(engine.call("restore", original)):
		_fail("chess: the original session could not restore after migration and capture screenshots")
		return
	screen.call("_refresh")


func _capture_prepared_capture(viewport: SubViewport, capture: Dictionary, screen: Control, engine: RefCounted, game_id: String, original: Dictionary) -> void:
	var puzzles: Array = content.chess_puzzles() if game_id == "chess" else content.military_puzzles() if game_id == "military" else content.puzzles.get("jungle", [])
	if puzzles.is_empty():
		_fail("%s: capture screenshot fixture is missing" % game_id)
		return
	var puzzle: Dictionary = puzzles[0]
	var context := {
		"gameId": game_id, "modeId": "puzzle", "players": original.players.duplicate(true),
		"puzzle": puzzle.duplicate(true), "seed": 12345,
	}
	engine.call("create_session", context)
	var pieces: Array = puzzle.get("pieces", [])
	var from := -1
	var to := -1
	if puzzle.get("line") is Array and not puzzle.line.is_empty():
		from = int(puzzle.line[0].get("from", -1))
		to = int(puzzle.line[0].get("to", -1))
	elif pieces.size() >= 2:
		from = int(pieces[0].position)
		to = int(pieces[1].position)
	if from < 0 or to < 0:
		_fail("%s: capture screenshot fixture has no prepared move" % game_id)
		return
	var select_action := {"type": "select", "position": from, "to": from}
	var selected: Dictionary = engine.call("handle_input", select_action)
	var result: Dictionary = engine.call("handle_input", {"type": "move", "to": to}) if bool(selected.get("ok", false)) else {"ok": false}
	if not bool(result.get("ok", false)):
		_fail("%s: capture screenshot fixture move was rejected" % game_id)
		return
	var captured_state: Dictionary = engine.get("state")
	captured_state.reported = true
	screen.call("_refresh")
	await _frames(48)
	_audit_board(screen, game_id)
	await _save(viewport, capture, game_id + "-capture")
	if not bool(engine.call("restore", original)):
		_fail("%s: initial session could not be restored after capture screenshot" % game_id)
		return
	screen.call("_refresh")


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
	if dry_run:
		return
	await _frames(2)
	RenderingServer.force_draw(false)
	var image := viewport.get_texture().get_image()
	var physical: Vector2i = capture.physical
	if image.get_size() != physical:
		image.resize(physical.x, physical.y, Image.INTERPOLATE_LANCZOS)
	var folder := output_dir.path_join(str(capture.label))
	DirAccess.make_dir_recursive_absolute(folder)
	if image.save_png(folder.path_join(name + ".png")) != OK:
		_fail("%s: screenshot could not be saved" % name)
		return
	if name in TABLETOP_GAMES:
		var left_view: Image = image.duplicate()
		left_view.rotate_90(COUNTERCLOCKWISE)
		left_view.save_png(folder.path_join(name + "-left-seat.png"))
		var right_view: Image = image.duplicate()
		right_view.rotate_90(CLOCKWISE)
		right_view.save_png(folder.path_join(name + "-right-seat.png"))


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
