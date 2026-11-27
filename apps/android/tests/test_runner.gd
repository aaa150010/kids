extends Node

const BoardRulesResource = preload("res://src/games/board_rules.gd")
const QuizRulesResource = preload("res://src/games/quiz_rules.gd")
const MemoryRulesResource = preload("res://src/games/memory_rules.gd")
const StoryFixtures = preload("res://tests/story_fixtures.gd")

var failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)


func all_scripts(path: String) -> Array[String]:
	var result: Array[String] = []
	var directory := DirAccess.open(path)
	if directory == null:
		return result
	for file_name in directory.get_files():
		if file_name.ends_with(".gd"):
			result.append(path.path_join(file_name))
	for directory_name in directory.get_directories():
		result.append_array(all_scripts(path.path_join(directory_name)))
	return result


func _run() -> void:
	var content = get_tree().root.get_node_or_null("/root/ContentDB")
	check(content != null, "ContentDB autoload is available")
	if content == null:
		get_tree().quit(1)
		return
	for script_path in all_scripts("res://src"):
		var script: GDScript = load(script_path)
		check(script != null and script.can_instantiate(), "%s parses and can be instantiated" % script_path)
	check(content.games.size() == 34, "catalog contains 34 entries including the ten 3.0 games")
	check(int(content.content_version) == 25, "content package version is 25")
	var app_version_value: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://version.json"))
	check(
		app_version_value is Dictionary
		and int(app_version_value.get("versionCode", 0)) == 22
		and str(app_version_value.get("versionName", "")) == "3.0.0",
		"app version is 3.0.0 (22)"
	)
	check(content.tuning.get("games", {}).size() == content.games.size(), "tuning covers all catalog entries")
	for content_issue in content.content_issues():
		check(false, "content validation: %s" % str(content_issue))
	StoryFixtures.new().run(content, Callable(self, "check"))
	for icon_path in [
		"res://assets/branding/app-icon-192.png",
		"res://assets/branding/app-icon-512.png",
		"res://assets/branding/app-icon-1024.png",
		"res://assets/branding/app-icon-foreground-432.png",
		"res://assets/branding/app-icon-background-432.png",
	]:
		check(FileAccess.file_exists(icon_path), "%s is bundled" % icon_path)
	var runtime_quality := get_tree().root.get_node_or_null("/root/RuntimeQuality")
	check(runtime_quality != null and int(runtime_quality.target_fps) >= 60, "runtime quality targets high refresh")
	for game_id in content.game_map:
		check(not GameTuning.definition(str(game_id)).is_empty(), "%s has a tuning definition" % game_id)
	check(GameTuning.resolve("auto", [{"age": 5}]) == "easy", "young players resolve to easy")
	check(GameTuning.resolve("auto", [{"age": 8}]) == "normal", "middle players resolve to normal")
	check(GameTuning.resolve("auto", [{"age": 11}]) == "challenge", "older players resolve to challenge")
	check(GameTuning.resolve("auto", [{"age": 11}, {"age": 6}]) == "easy", "multiplayer auto uses the youngest player")
	check(GameTuning.resolve("challenge", [{"age": 5}]) == "challenge", "manual difficulty overrides age")
	check(GameTuning.stars("math", "easy", 3, 6) == 1, "easy quiz star threshold is applied")
	check(GameTuning.stars("math", "normal", 8, 8) == 3, "perfect quiz earns three stars")
	check(content.workbook_questions.size() >= 100, "workbook bank is loaded")
	check(content.poems.size() >= 300, "poetry bank is loaded")
	for game_id in ["math", "pinyin", "patterns", "animals"]:
		check(content.quizzes.get(game_id, []).size() > 0, "%s questions are loaded" % game_id)
	check(content.trivia_questions.size() >= 160, "trivia bank contains at least 160 questions")
	for game_id in ["jungle", "gomoku", "memory", "math", "pinyin", "patterns", "animals", "workbook"]:
		check(content.chapters.get(game_id, []).size() > 0, "%s adventure levels are loaded" % game_id)
	for game_id in ["jungle", "gomoku"]:
		check(content.puzzles.get(game_id, []).size() > 0, "%s puzzle fixtures are loaded" % game_id)
	check(content.chess_puzzles().size() == 12, "chess has twelve fixed one-move puzzles")
	check(content.sudoku_puzzles().size() == 32, "sudoku has 32 fixed puzzles")
	check(content.military_formations().size() == 3, "military has three preset formations")
	check(content.military_puzzles().size() == 24, "military has 24 fixed endgame puzzles")
	check(content.tangram_levels_data().size() == 24, "tangram has 24 playable outlines")
	check(content.spot_scene_data().size() == 24, "spot-the-difference has 24 scenes")
	check(content.shop_items().size() == 16, "little shop has 16 products")
	check(content.shop_orders().size() == 24, "little shop has 24 orders")
	check(content.fruit_types().size() == 12, "fruit slice has 12 original fruit types")
	check(content.robot_levels().size() == 24, "robot has 24 playable routes")
	check(content.sentence_stations().size() == 24, "sentence train has 24 stations")
	check(content.pipe_levels().size() == 36, "pipes has 36 playable gardens")
	check(content.tank_levels().size() == 30, "tank has 30 fixed mazes")
	check(content.sokoban_levels().size() == 48, "sokoban has 48 warehouse levels")
	check(content.circuit_levels().size() == 32, "circuit workshop has 32 low-voltage circuits")
	check(content.bubble_levels().size() == 24, "bubble has 24 levels")
	check(content.rhythm_charts().size() == 24, "rhythm has 24 charts")
	check(content.garbage_levels().size() == 30, "garbage sorting has 30 levels")
	check(content.kitchen_levels().size() == 24, "little kitchen has 24 orders")
	check(content.maze_levels().size() == 32, "maze has 32 levels")
	check(content.slide_levels().size() == 32, "slide puzzle has 32 boards")
	check(content.pixel_art_pages().size() == 30, "pixel art has 30 pictures")
	check(content.pinball_tables().size() == 24, "pinball has 24 tables")
	check(content.breakout_levels().size() == 24, "breakout has 24 levels")
	check(content.air_hockey_arenas().size() == 18, "air hockey has 18 arenas")
	for cover_path in [
		"res://assets/covers/tangram.svg",
		"res://assets/covers/spot.svg",
		"res://assets/covers/shop.svg",
		"res://assets/covers/fruit_slice.svg",
		"res://assets/covers/robot.svg",
		"res://assets/covers/sentence_train.svg",
		"res://assets/covers/pipes.svg",
		"res://assets/covers/tank.svg",
		"res://assets/covers/sokoban.svg",
		"res://assets/covers/circuit.svg",
		"res://assets/covers/bubble.svg",
		"res://assets/covers/rhythm.svg",
		"res://assets/covers/garbage_sort.svg",
		"res://assets/covers/kitchen.svg",
		"res://assets/covers/maze.svg",
		"res://assets/covers/slide_puzzle.svg",
		"res://assets/covers/pixel_art.svg",
		"res://assets/covers/pinball.svg",
		"res://assets/covers/breakout.svg",
		"res://assets/covers/air_hockey.svg",
	]:
		check(FileAccess.file_exists(cover_path), "%s is bundled" % cover_path)
	check(content.search_games("拼图").has("tangram"), "lobby search finds tangram by Chinese alias")
	check(content.search_games("水果").has("fruit_slice"), "lobby search finds fruit slice by category alias")
	check(content.search_games("数学").has("math") and content.search_games("数学").has("workbook"), "lobby search matches multiple math games")
	check(content.search_games("tangram").has("tangram"), "lobby search accepts English game ids")
	check(content.search_games("编程").has("robot"), "lobby search finds the robot by learning goal")
	check(content.search_games("组句").has("sentence_train"), "lobby search finds sentence train by alias")
	check(content.search_games("水管").has("pipes"), "lobby search finds pipes by alias")
	check(content.search_games("坦克大战").has("tank"), "lobby search finds tank by alias")
	check(content.search_games("推箱子").has("sokoban"), "lobby search finds sokoban by alias")
	check(content.search_games("灯泡").has("circuit"), "lobby search finds circuit by alias")
	check(content.search_games("弹珠").has("pinball"), "lobby search finds pinball by alias")
	check(content.search_games("打砖块").has("breakout"), "lobby search finds breakout by alias")
	check(content.search_games("冰球").has("air_hockey"), "lobby search finds air hockey by alias")
	check(content.search_games("节奏").has("rhythm"), "lobby search finds rhythm by alias")
	check(content.search_games("垃圾分类").has("garbage_sort"), "lobby search finds garbage sorting by alias")
	check(content.search_games("厨房").has("kitchen"), "lobby search finds kitchen by alias")
	check(content.search_games("华容道").has("maze") or content.search_games("华容道").has("slide_puzzle"), "lobby search finds maze and sliding puzzle aliases")
	check(content.search_games("像素画").has("pixel_art"), "lobby search finds pixel art by alias")
	check(content.search_games("泡泡").has("bubble"), "lobby search finds bubble by alias")
	check(content.search_games("完全不存在的小游戏").is_empty(), "lobby search returns an empty result for an unknown query")
	for quiz_game_id in ["math", "pinyin", "patterns", "animals", "trivia"]:
		for sample_age in [4, 7, 10, 12]:
			var rounds_needed := int(GameTuning.value(quiz_game_id, GameTuning.from_age(sample_age), "rounds", 10))
			check(content.questions(quiz_game_id, sample_age).size() >= rounds_needed, "%s has a full age-band pool for age %s" % [quiz_game_id, sample_age])

	var fake_player = {
		"id": "test-player",
		"name": "测试小朋友",
		"age": 7,
		"avatar": "🦊",
		"color": "#d56c29",
	}
	var fake_player_two: Dictionary = fake_player.duplicate(true)
	fake_player_two.id = "test-player-two"
	var board_rules = BoardRulesResource.new()
	var jungle_levels: Array = content.puzzles.get("jungle", [])
	var jungle_puzzle: Dictionary = jungle_levels[0]
	var jungle_state: Dictionary = board_rules.create_session({
		"gameId": "jungle",
		"modeId": "puzzle",
		"players": [fake_player],
		"seed": 42,
		"puzzle": jungle_puzzle,
	})
	var selected: Dictionary = board_rules.handle_input({"type":"select","to":24})
	check(bool(selected.ok), "jungle piece can be selected")
	var captured: Dictionary = board_rules.handle_input({"type":"move","to":25})
	check(bool(captured.ok) and jungle_state.phase == "finished", "jungle mouse catches elephant in a puzzle")
	var restored_jungle = BoardRulesResource.new()
	check(restored_jungle.restore(board_rules.snapshot()), "jungle snapshot restores")
	check(str(restored_jungle.state.modeId) == "puzzle", "jungle snapshot preserves the mode")

	var gomoku_levels: Array = content.puzzles.get("gomoku", [])
	var gomoku_puzzle: Dictionary = gomoku_levels[0]
	var gomoku_rules = BoardRulesResource.new()
	var gomoku_state: Dictionary = gomoku_rules.create_session({
		"gameId": "gomoku",
		"modeId": "puzzle",
		"players": [fake_player, fake_player_two],
		"seed": 43,
		"puzzle": gomoku_puzzle,
	})
	var gomoku_move: Dictionary = gomoku_rules.handle_input({"type":"move","to":gomoku_puzzle.line[0].to})
	check(bool(gomoku_move.ok) and gomoku_state.phase == "finished", "gomoku puzzle completes at the prepared line")
	check(gomoku_state.winningLine.size() >= 5, "gomoku puzzle exposes a winning line")

	var chess_puzzle: Dictionary = content.chess_puzzles()[0]
	var chess_rules = ChessRules.new()
	var chess_state: Dictionary = chess_rules.create_session({
		"gameId": "chess",
		"modeId": "puzzle",
		"players": [fake_player],
		"seed": 46,
		"puzzle": chess_puzzle,
	})
	var chess_line: Dictionary = chess_puzzle.line[0]
	check(bool(chess_rules.handle_input({"type":"select","position":int(chess_line.from)}).ok), "chess puzzle piece can be selected")
	check(bool(chess_rules.handle_input({"type":"move","to":int(chess_line.to)}).ok) and chess_state.phase == "finished", "chess puzzle completes a one-move capture")
	check(int(chess_state.winner) == 0, "chess puzzle awards the attacking player")
	var chess_classic = ChessRules.new()
	var chess_classic_state: Dictionary = chess_classic.create_session({
		"gameId": "chess",
		"modeId": "classic",
		"players": [fake_player, fake_player_two],
		"seed": 48,
	})
	check(chess_classic_state.phase == "playing" and chess_classic_state.pieces.size() == 32, "chess classic starts with 32 pieces")
	for side in 2:
		var faction: Array = chess_classic_state.pieces.filter(func(piece): return int(piece.side) == side)
		var soldiers: Array = faction.filter(func(piece): return str(piece.kind) == "soldier")
		check(faction.size() == 16 and soldiers.size() == 5, "chess side %s starts with sixteen pieces and five soldiers" % side)
		for soldier in soldiers:
			check(chess_classic.piece_name(soldier) == ("兵" if side == 0 else "卒"), "soldier names follow their faction")
	for cannon_position in [19, 25, 64, 70]:
		check(str(chess_classic.piece_at(cannon_position).get("kind", "")) == "cannon", "chess cannon starts on its standard position %s" % cannon_position)
	var restored_chess = ChessRules.new()
	check(restored_chess.restore(chess_classic.snapshot()), "chess snapshot restores")
	var chess_before_query: Dictionary = chess_classic.snapshot()
	var cannon_targets: Array = chess_classic.legal_targets(64)
	check(chess_classic.state == chess_before_query, "querying legal targets does not mutate the chess session")
	check(1 in cannon_targets, "red cannon can capture the black horse over one screen")
	check(bool(chess_classic.handle_input({"type":"select", "position":64}).ok), "red cannon can be selected")
	check(bool(chess_classic.handle_input({"type":"move", "to":1}).ok), "red cannon captures the black horse")
	check(int(chess_classic.piece_at(1).get("side", -1)) == 0, "capturing piece remains red across the board")
	var chess_after_capture: Dictionary = chess_classic.snapshot()
	var restored_capture = ChessRules.new()
	check(restored_capture.restore(chess_after_capture), "chess capture snapshot restores")
	check(restored_capture.state.pieces == chess_after_capture.pieces, "restoring a capture does not revive captured pieces")
	restored_capture.legal_targets(0)
	check(restored_capture.state.pieces == chess_after_capture.pieces, "querying a reply does not revive captured pieces")
	check(restored_capture.undo_last_move(), "a restored capture can be undone")
	check(restored_capture.state.pieces == chess_before_query.pieces, "undo restores the exact captured piece and initial board")

	var sudoku_puzzle: Dictionary = content.sudoku_puzzles()[0]
	var sudoku_rules = SudokuRules.new()
	var sudoku_state: Dictionary = sudoku_rules.create_session({
		"gameId": "sudoku",
		"modeId": "classic",
		"players": [fake_player],
		"seed": 49,
		"puzzle": sudoku_puzzle,
	})
	check(int(sudoku_rules.size()) == 4, "mini sudoku uses a 4x4 grid")
	check(bool(sudoku_rules.is_given(0)), "sudoku givens are protected")
	var first_empty := -1
	for index in str(sudoku_state.values).length():
		if str(sudoku_state.values)[index] == "0":
			first_empty = index
			break
	sudoku_state.selected = first_empty
	var sudoku_value := int(str(sudoku_state.solution)[first_empty])
	check(bool(sudoku_rules.set_number(sudoku_value).ok), "sudoku accepts a correct number")
	var restored_sudoku = SudokuRules.new()
	check(restored_sudoku.restore(sudoku_rules.snapshot()), "sudoku snapshot restores")

	var military_puzzle: Dictionary = content.military_puzzles()[0]
	var military_rules = MilitaryRules.new()
	var military_state: Dictionary = military_rules.create_session({
		"gameId": "military",
		"modeId": "puzzle",
		"players": [fake_player],
		"seed": 44,
		"puzzle": military_puzzle,
	})
	var military_from := int(military_puzzle.pieces[0].position)
	var military_flag := int(military_puzzle.pieces[1].position)
	check(bool(military_rules.handle_input({"type":"select","position":military_from}).ok), "military puzzle piece can be selected")
	check(bool(military_rules.handle_input({"type":"move","to":military_flag}).ok) and military_state.phase == "finished", "military puzzle captures the flag")
	check(int(military_state.winner) == 0, "military puzzle awards the attacking player")

	var military_classic = MilitaryRules.new()
	var military_classic_state: Dictionary = military_classic.create_session({
		"gameId": "military",
		"modeId": "classic",
		"players": [fake_player, fake_player_two],
		"seed": 47,
	})
	check(military_classic_state.phase == "playing" and military_classic_state.pieces.size() == 50, "military classic starts immediately with both formations")
	check(bool(military_classic_state.revealAll), "military classic reveals both sides from the start")
	check(not bool(military_classic_state.needsHandoff), "military classic skips the device handoff")
	var military_snapshot: Dictionary = military_classic.snapshot()
	var restored_military = MilitaryRules.new()
	check(restored_military.restore(military_snapshot), "military snapshot restores")
	var legacy_military = MilitaryRules.new()
	var legacy_save: Dictionary = military_snapshot.duplicate(true)
	legacy_save.militaryVersion = 2
	legacy_save.revealAll = false
	legacy_save.needsHandoff = true
	check(legacy_military.restore(legacy_save), "military v2 snapshot migrates")
	check(bool(legacy_military.state.revealAll) and not bool(legacy_military.state.needsHandoff), "military v2 hidden snapshot opens up")
	var old_military = MilitaryRules.new()
	var old_save: Dictionary = military_snapshot.duplicate(true)
	old_save.erase("militaryVersion")
	check(not old_military.restore(old_save), "legacy flipping chess snapshot is rejected safely")

	var quiz = QuizRulesResource.new()
	var quiz_pool: Array = content.questions("math", 5).slice(0, 2)
	var quiz_state: Dictionary = quiz.create_session({
		"gameId": "math",
		"modeId": "adventure",
		"players": [fake_player],
		"seed": 45,
		"pools": [quiz_pool],
		"rounds": 2,
	})
	var question: Dictionary = quiz.question()
	var answer: Dictionary = quiz.handle_input({"type":"answer","index":int(question.answer)})
	check(bool(answer.ok) and quiz_state.phase == "feedback", "quiz keeps the explanation after answering")
	check(question.get("explanation", "") != "", "quiz feedback has an explanation")
	check(bool(quiz.handle_input({"type":"next"}).ok), "quiz advances only after the next action")

	var memory = MemoryRulesResource.new()
	var memory_cards: Array = content.memory_cards().slice(0, 2)
	var memory_state: Dictionary = memory.create_session({
		"gameId": "memory",
		"modeId": "adventure",
		"players": [fake_player],
		"seed": 46,
		"cards": memory_cards,
		"pairs": 2,
	})
	var first_index := 0
	var second_index := 1
	for index in memory_state.deck.size():
		for other in range(index + 1, memory_state.deck.size()):
			if str(memory_state.deck[index]) == str(memory_state.deck[other]):
				first_index = index
				second_index = other
	var first_flip: Dictionary = memory.handle_input({"type":"flip","index":first_index})
	var second_flip: Dictionary = memory.handle_input({"type":"flip","index":second_index})
	check(bool(first_flip.ok) and bool(second_flip.ok) and bool(memory_state.pending), "memory waits for a pair before advancing")
	memory.tick(1.0)
	check(memory_state.matched.size() == 2, "memory resolves a matching pair")
	check(int(memory_state.get("attempts", [])[0]) == 1, "memory records the current player's attempt")
	var memory_two = MemoryRulesResource.new()
	var memory_two_state: Dictionary = memory_two.create_session({
		"gameId": "memory",
		"modeId": "classic",
		"players": [fake_player, fake_player_two],
		"seed": 48,
		"cards": content.memory_cards().slice(0, 4),
		"pairs": 4,
	})
	var match_a := -1
	var match_b := -1
	for index in memory_two_state.deck.size():
		for other in range(index + 1, memory_two_state.deck.size()):
			if str(memory_two_state.deck[index]) == str(memory_two_state.deck[other]):
				match_a = index
				match_b = other
				break
		if match_a >= 0:
			break
	memory_two.handle_input({"type":"flip","index":match_a})
	memory_two.handle_input({"type":"flip","index":match_b})
	memory_two.tick(1.0)
	check(int(memory_two_state.currentPlayer) == 0, "memory match keeps the current player's turn")
	var mismatch_a := -1
	var mismatch_b := -1
	for index in memory_two_state.deck.size():
		if index in memory_two_state.matched:
			continue
		for other in range(index + 1, memory_two_state.deck.size()):
			if other in memory_two_state.matched:
				continue
			if str(memory_two_state.deck[index]) != str(memory_two_state.deck[other]):
				mismatch_a = index
				mismatch_b = other
				break
		if mismatch_a >= 0:
			break
	memory_two.handle_input({"type":"flip","index":mismatch_a})
	memory_two.handle_input({"type":"flip","index":mismatch_b})
	memory_two.tick(1.0)
	memory_two.tick(1.0)
	check(int(memory_two_state.currentPlayer) == 1, "memory mismatch passes the turn")
	var poetry_screen = load("res://src/games/poetry_game.gd").new()
	var poetry_poem: Dictionary = content.poems[0]
	var poetry_snapshot := {
		"schemaVersion": 1,
		"player": fake_player,
		"currentPoemId": str(poetry_poem.id),
		"mode": "draw",
		"knownIds": [],
		"reviewIds": [],
		"usedIds": [str(poetry_poem.id)],
		"poemScrolls": {
			str(poetry_poem.id): {"line": 5, "ratio": 0.5},
			"missing-poem": {"line": 99, "ratio": 2.0},
		},
	}
	check(poetry_screen._restore_snapshot(poetry_snapshot, str(fake_player.id)), "poetry snapshot with semantic scroll anchor restores")
	check(int(poetry_screen.poem_scrolls.get(str(poetry_poem.id), {}).get("line", -1)) == 5, "poetry keeps the first visible line anchor")
	check(not poetry_screen.poem_scrolls.has("missing-poem"), "poetry drops scroll anchors for unknown poems")
	check(poetry_screen._new_attempt_id() != poetry_screen._new_attempt_id(), "poetry attempt ids are unique across draws")
	poetry_screen.free()

	_check_refactor_rules(content, fake_player, fake_player_two)
	_check_new_games(content, fake_player, fake_player_two)
	_check_action_games(content, fake_player, fake_player_two)

	var save_store := get_tree().root.get_node_or_null("/root/SaveStore")
	check(save_store != null, "SaveStore autoload is available")
	var difficulty_profile: Dictionary = save_store.add_profile("测试难度", 8, "🐼", "#2878c8") if save_store != null else {}
	check(not difficulty_profile.is_empty(), "temporary profile can be created for save tests")
	if not difficulty_profile.is_empty() and save_store != null:
		save_store.set_difficulty("math", str(difficulty_profile.id), "challenge")
		check(save_store.difficulty("math", str(difficulty_profile.id)) == "challenge", "difficulty preference persists")
		save_store.set_difficulty("math", str(difficulty_profile.id), "auto")
		check(save_store.difficulty("math", str(difficulty_profile.id)) == "auto", "auto difficulty removes stored override")
		save_store.delete_profile(str(difficulty_profile.id))

	var isolated := OS.get_environment("KIDS_PLAYGROUND_SAVE_PATH").begins_with("user://")
	check(isolated, "save tests run against an isolated save path")
	if isolated and save_store != null:
		_check_refactor_saves(save_store)

	if failures.is_empty():
		print("Native content, board, quiz and memory checks passed.")
		get_tree().quit(0)
	else:
		print("Native checks failed: %d" % failures.size())
		get_tree().quit(1)


func _check_refactor_rules(content: Node, player_one: Dictionary, player_two: Dictionary) -> void:
	var recent_pool: Array = content.questions("math", 5).slice(0, 12)
	var recent_ids: Array = recent_pool.slice(0, 10).map(func(item): return str(item.id))
	var recent_rules = QuizRulesResource.new()
	var recent_state: Dictionary = recent_rules.create_session({
		"gameId": "math",
		"modeId": "adventure",
		"players": [player_one],
		"seed": 71,
		"pools": [recent_pool],
		"recentIds": [recent_ids],
		"rounds": 6,
	})
	var fresh_in_queue := 0
	for queued_question in recent_state.queues[0]:
		if not (str(queued_question.id) in recent_ids):
			fresh_in_queue += 1
	check(fresh_in_queue == 2, "quiz uses every unseen question before recycling recent ones")

	var military_puzzle_rules = MilitaryRules.new()
	var military_puzzle_state: Dictionary = military_puzzle_rules.create_session({
		"gameId": "military",
		"modeId": "puzzle",
		"players": [player_one],
		"seed": 72,
		"puzzle": content.military_puzzles()[0],
		"hintsMax": 2,
		"undosMax": 3,
	})
	var military_start := int(military_puzzle_state.pieces[0].position)
	var military_goal := int(military_puzzle_state.pieces[1].position)
	var military_targets: Array = military_puzzle_rules.legal_targets(military_start)
	var military_wrong := -1
	for military_target in military_targets:
		if int(military_target) != military_goal:
			military_wrong = int(military_target)
			break
	check(military_wrong >= 0, "military puzzle exposes a non-winning legal move")
	check(bool(military_puzzle_rules.handle_input({"type":"select","position":military_start}).ok), "military puzzle piece can be selected")
	if military_wrong >= 0:
		check(bool(military_puzzle_rules.handle_input({"type":"move","to":military_wrong}).ok), "military puzzle accepts a wrong legal move without freezing")
		check(str(military_puzzle_state.phase) == "playing" and int(military_puzzle_state.winner) != 1, "military wrong move cannot award the opponent")
		check(bool(military_puzzle_state.get("puzzleMiss", false)), "military wrong move is reported as a retry")
		check(military_puzzle_rules.undo_last_move(), "military wrong move can be undone")
	check(bool(military_puzzle_rules.handle_input({"type":"select","position":military_start}).ok), "military puzzle reselects after undo")
	check(bool(military_puzzle_rules.handle_input({"type":"move","to":military_goal}).ok), "military puzzle captures the flag")
	check(str(military_puzzle_state.phase) == "finished" and int(military_puzzle_state.winner) == 0, "military flag capture is the only puzzle win")

	var military_classic_a = MilitaryRules.new()
	var military_state_a: Dictionary = military_classic_a.create_session({
		"gameId": "military", "modeId": "classic", "players": [player_one, player_two], "seed": 701,
	})
	var military_classic_b = MilitaryRules.new()
	var military_state_b: Dictionary = military_classic_b.create_session({
		"gameId": "military", "modeId": "classic", "players": [player_one, player_two], "seed": 702,
	})
	check(military_state_a.formations[0] != military_state_a.formations[1], "military classic uses two different preset formations")
	check(military_state_a.formations != military_state_b.formations, "military formations are seeded instead of fixed")

	var chess_puzzle_rules = ChessRules.new()
	var chess_puzzle_state: Dictionary = chess_puzzle_rules.create_session({
		"gameId": "chess", "modeId": "puzzle", "players": [player_one],
		"seed": 73, "puzzle": content.chess_puzzles()[0], "hintsMax": 2, "undosMax": 3,
	})
	var chess_solution: Dictionary = chess_puzzle_state.puzzle.line[0]
	var chess_start := int(chess_solution.from)
	var chess_goal := int(chess_solution.to)
	check(bool(chess_puzzle_rules.handle_input({"type":"select","position":chess_start}).ok), "chess puzzle can select the attacking piece")
	var chess_targets: Array = chess_puzzle_rules.legal_targets(chess_start)
	var chess_wrong := -1
	for chess_target in chess_targets:
		if int(chess_target) != chess_goal:
			chess_wrong = int(chess_target)
			break
	check(chess_wrong >= 0, "chess puzzle exposes an alternative legal move")
	if chess_wrong >= 0:
		var chess_miss: Dictionary = chess_puzzle_rules.handle_input({"type":"move","to":chess_wrong})
		check(not bool(chess_miss.get("ok", true)) and bool(chess_miss.get("puzzleMiss", false)), "chess wrong move is rejected as a retry")
		check(str(chess_puzzle_state.phase) == "playing" and int(chess_puzzle_state.turn) == 0, "chess wrong move never hands control to black")
	check(bool(chess_puzzle_rules.handle_input({"type":"select","position":chess_start}).ok), "chess puzzle reselects after a retry")
	check(bool(chess_puzzle_rules.handle_input({"type":"move","to":chess_goal}).ok), "chess puzzle accepts the mate move")
	check(str(chess_puzzle_state.phase) == "finished" and int(chess_puzzle_state.winner) == 0, "chess puzzle awards the solo player")

	var hint_chess = ChessRules.new()
	hint_chess.create_session({
		"gameId": "chess", "modeId": "puzzle", "players": [player_one],
		"seed": 74, "puzzle": content.chess_puzzles()[0], "hintsMax": 2, "undosMax": 3,
	})
	var chess_hint: Dictionary = hint_chess.handle_input({"type":"hint"})
	check(bool(chess_hint.get("ok", false)) and str(chess_hint.get("hint", "")) != "", "chess puzzle hint is available")

	var longest_poem: Dictionary = {}
	for poem in content.poems:
		if longest_poem.is_empty() or str(poem.get("fullText", "")).length() > str(longest_poem.get("fullText", "")).length():
			longest_poem = poem
	var ruby := PoemRubyText.new()
	ruby.configure(str(longest_poem.get("fullText", "")), "", 24, false, false)
	ruby.size = Vector2(560, 120)
	get_tree().root.add_child(ruby)
	ruby.call("_layout_line")
	var max_ruby_right := 0.0
	for cell in ruby._cells:
		max_ruby_right = maxf(max_ruby_right, float(cell.x) + float(cell.width))
	check(ruby._height > 120.0, "long poetry wraps onto additional lines")
	check(max_ruby_right <= 561.0, "wrapped poetry stays inside its width")
	ruby.queue_free()


func _check_new_games(content: Node, player_one: Dictionary, player_two: Dictionary) -> void:
	var tangram_levels: Array = content.tangram_levels_data()
	check(not tangram_levels.is_empty(), "tangram levels are available to the rules test")
	if not tangram_levels.is_empty():
		var tangram = TangramRules.new()
		var tangram_state: Dictionary = tangram.create_session({
			"gameId": "tangram",
			"modeId": "adventure",
			"players": [player_one],
			"levelId": 1,
			"level": tangram_levels[0],
			"difficulty": "normal",
			"hintsMax": 2,
			"seed": 801,
		})
		check(str(tangram_state.phase) == "playing" and tangram_state.targetPieces.size() == 7, "tangram starts with seven target pieces")
		for slot_index in tangram_state.targetPieces.size():
			var target_piece: Dictionary = tangram_state.targetPieces[slot_index]
			var piece_index := -1
			for candidate_index in tangram_state.pieces.size():
				var candidate: Dictionary = tangram_state.pieces[candidate_index]
				if not bool(candidate.get("placed", false)) and str(candidate.get("kind", "")) == str(target_piece.get("kind", "")):
					piece_index = candidate_index
					break
			check(piece_index >= 0, "tangram exposes a piece for target slot %s" % slot_index)
			if piece_index < 0:
				continue
			while int(tangram_state.pieces[piece_index].get("rotation", 0)) != int(target_piece.get("rotation", 0)):
				tangram.handle_input({"type": "rotate", "index": piece_index})
			if bool(target_piece.get("mirror", false)):
				tangram.handle_input({"type": "mirror", "index": piece_index})
			var placement: Dictionary = tangram.handle_input({
				"type": "place",
				"index": piece_index,
				"x": float(target_piece.get("x", 0.5)),
				"y": float(target_piece.get("y", 0.5)),
			})
			check(bool(placement.get("ok", false)) and bool(placement.get("snapped", false)), "tangram piece snaps to its matching outline")
		check(str(tangram_state.phase) == "finished" and int(tangram_state.stars) in [1, 2, 3], "tangram completes with a valid star result")
		var tangram_restored = TangramRules.new()
		check(tangram_restored.restore(tangram.snapshot()), "tangram completion snapshot restores")
		check(str(tangram_restored.state.phase) == "finished", "restored tangram keeps its completed state")

	var spot_scenes: Array = content.spot_scene_data()
	check(spot_scenes.size() >= 17, "spot-the-difference scene 17 exists")
	if spot_scenes.size() >= 17:
		var scene: Dictionary = spot_scenes[16]
		var spot = SpotRules.new()
		var spot_state: Dictionary = spot.create_session({
			"gameId": "spot",
			"modeId": "adventure",
			"players": [player_one],
			"levelId": 17,
			"view": "scene",
			"scene": scene,
			"hintsMax": 2,
			"seed": 802,
		})
		check(int(spot_state.levelId) == 17 and str(spot_state.view) == "scene", "spot session keeps its non-first level identity")
		var wrong_point := Vector2(0.5, 0.5)
		var best_clearance := 0.0
		for y_index in 11:
			for x_index in 11:
				var candidate_point := Vector2(float(x_index) / 10.0, float(y_index) / 10.0)
				var clearance := INF
				for difference_entry in scene.differences:
					clearance = minf(clearance, candidate_point.distance_to(Vector2(float(difference_entry.x), float(difference_entry.y))))
				if clearance > best_clearance:
					best_clearance = clearance
					wrong_point = candidate_point
		var wrong_result: Dictionary = spot.handle_input({"type": "tap", "x": wrong_point.x, "y": wrong_point.y})
		check(bool(wrong_result.get("wrong", false)) and int(spot_state.wrongTaps) == 1, "spot wrong tap is recorded without completing the scene")
		var first_difference: Dictionary = scene.differences[0]
		var second_difference: Dictionary = scene.differences[1]
		check(bool(spot.handle_input({"type": "tap", "x": first_difference.x, "y": first_difference.y}).get("ok", false)), "spot accepts the first difference")
		check(bool(spot.handle_input({"type": "tap", "x": second_difference.x, "y": second_difference.y}).get("ok", false)), "spot accepts the second difference")
		var hint_result: Dictionary = spot.handle_input({"type": "hint"})
		check(bool(hint_result.get("ok", false)) and int(spot_state.hints) == 1, "spot hint is available once")
		var spot_restored = SpotRules.new()
		check(spot_restored.restore(spot.snapshot()), "spot mid-scene snapshot restores")
		check(int(spot_restored.state.levelId) == 17 and int(spot_restored.found_count()) == 2, "spot restore keeps the level, found differences and hint state")
		for difference_entry in scene.differences:
			if str(difference_entry.id) in spot_restored.state.foundIds:
				continue
			spot_restored.handle_input({"type": "tap", "x": difference_entry.x, "y": difference_entry.y})
		check(str(spot_restored.state.phase) == "result" and spot_restored.found_count() == 5, "spot completes after all five differences")
		var corrupt_spot: Dictionary = spot_restored.snapshot()
		var broken_object_id := str(corrupt_spot.scene.differences[0].objectId)
		for object_entry in corrupt_spot.scene.objects:
			if str(object_entry.get("id", "")) == broken_object_id:
				object_entry.erase("right")
				break
		var rejected_spot = SpotRules.new()
		check(not rejected_spot.restore(corrupt_spot), "spot rejects a scene with a missing difference override")

	var catalog := {}
	for item in content.shop_items():
		catalog[str(item.id)] = item
	var shop_orders: Array = content.shop_orders()
	check(not shop_orders.is_empty(), "shop orders are available to the rules test")
	if not shop_orders.is_empty():
		var order: Dictionary = shop_orders[0]
		var shop = ShopRules.new()
		var shop_state: Dictionary = shop.create_session({
			"gameId": "shop",
			"modeId": "adventure",
			"players": [player_one],
			"levelId": 1,
			"difficulty": "normal",
			"catalog": catalog,
			"order": order,
			"hintsMax": 2,
			"seed": 803,
		})
		for requirement in order.items:
			for _quantity_index in int(requirement.qty):
				shop.handle_input({"type": "add_item", "item_id": str(requirement.item)})
		check(shop.basket_count() > 0, "shop basket accepts ordered products")
		var checkout: Dictionary = shop.handle_input({"type": "checkout"})
		check(bool(checkout.get("ok", false)) and str(shop_state.phase) == "pay", "shop advances to payment with a matching basket")
		var total := int(shop_state.total)
		for coin in [50, 20, 10, 5, 2, 1]:
			while int(shop_state.paid) + int(coin) <= total:
				shop.handle_input({"type": "pay", "value": int(coin)})
		check(int(shop_state.paid) == total, "shop coins can pay the exact order total")
		var payment: Dictionary = shop.handle_input({"type": "confirm_payment"})
		check(bool(payment.get("ok", false)) and str(shop_state.phase) == "finished", "shop completes after enough payment")
		check(int(shop_state.change) == 0 and int(shop_state.stars) == 3, "shop keeps exact change and a clean three-star result")
		var shop_restored = ShopRules.new()
		check(shop_restored.restore(shop.snapshot()), "shop completed snapshot restores")
		check(str(shop_restored.state.phase) == "finished" and int(shop_restored.result().stars) == 3, "restored shop keeps its paid order result")

	var robot_level: Dictionary = content.robot_levels()[0]
	var robot = RobotRules.new()
	var robot_state: Dictionary = robot.create_session({
		"gameId": "robot",
		"modeId": "adventure",
		"players": [player_one],
		"levelId": 1,
		"level": robot_level,
		"difficulty": "normal",
		"seed": 906,
	})
	for command in robot_level.solution:
		check(bool(robot.handle_input({"type": "add_command", "command": str(command)}).get("ok", false)), "robot accepts a direction command")
	var robot_steps := 0
	while str(robot_state.phase) != "result" and robot_steps < 20:
		robot.handle_input({"type": "step"})
		robot_steps += 1
	check(str(robot_state.phase) == "result" and int(robot_state.stars) == 3, "robot solution reaches the flag with three stars")
	var robot_restored = RobotRules.new()
	check(robot_restored.restore(robot.snapshot()), "robot completed snapshot restores")
	check(str(robot_restored.state.phase) == "result" and int(robot_restored.result().stars) == 3, "restored robot keeps the completed route result")

	var sentence_station: Dictionary = content.sentence_stations()[0]
	var sentences = SentenceRules.new()
	var sentence_state: Dictionary = sentences.create_session({
		"gameId": "sentence_train",
		"modeId": "adventure",
		"players": [player_one],
		"levelId": 1,
		"station": sentence_station,
		"seed": 907,
	})
	for sentence_index in 5:
		var current_sentence: Dictionary = sentence_state.sentence
		for chunk_id in current_sentence.answerOrder:
			check(bool(sentences.handle_input({"type": "place_chunk", "chunkId": str(chunk_id)}).get("ok", false)), "sentence train accepts a word carriage")
		var sentence_submit: Dictionary = sentences.handle_input({"type": "submit"})
		check(bool(sentence_submit.get("correct", false)), "sentence train accepts the authored word order")
		sentences.handle_input({"type": "next"})
	check(str(sentence_state.phase) == "station_result" and int(sentence_state.stars) == 3, "sentence train completes a station with three stars")
	var sentence_restored = SentenceRules.new()
	check(sentence_restored.restore(sentences.snapshot()), "sentence train station snapshot restores")

	var pipe_level: Dictionary = content.pipe_levels()[0]
	var pipes = PipeRules.new()
	var pipe_state: Dictionary = pipes.create_session({
		"gameId": "pipes",
		"modeId": "adventure",
		"players": [player_one],
		"levelId": 1,
		"level": pipe_level,
		"seed": 908,
	})
	for index in pipe_state.pieces.size():
		var piece: Dictionary = pipe_state.pieces[index]
		if bool(piece.get("locked", false)) or str(piece.get("type", "")) == "cross":
			continue
		var guard := 0
		while int(piece.get("rotation", 0)) != int(piece.get("solutionRotation", 0)) and guard < 5:
			pipes.handle_input({"type": "rotate", "index": index})
			guard += 1
	check(str(pipe_state.phase) == "finished" and int(pipes.result().stars) == 3, "pipes solution waters every goal with three stars")
	var pipe_restored = PipeRules.new()
	check(pipe_restored.restore(pipes.snapshot()), "pipes completed snapshot restores")
	check(int(pipe_restored.result().wetGoals) == int(pipe_restored.result().goalCount), "restored pipes keep every goal watered")

	var fruit_config := {
		"practiceWaves": 1,
		"practiceFruits": 1,
		"challengeSeconds": 60.0,
		"spawnDelay": 0.05,
		"maxFruits": 4,
		"bombChance": 0.0,
		"bonusChance": 0.0,
		"comboWindow": 1.0,
		"bombPenalty": 5,
		"bonusPoints": 50,
		"bombRadius": 0.06,
		"bonusRadius": 0.055,
	}
	var practice_fruit = FruitRules.new()
	var practice_state: Dictionary = practice_fruit.create_session({
		"gameId": "fruit_slice",
		"modeId": "practice",
		"players": [player_one],
		"difficulty": "normal",
		"seed": 901,
		"fruitTypes": content.fruit_types(),
		"config": fruit_config,
	})
	check(str(practice_state.phase) == "ready" and int(practice_state.spawnQueue.size()) > 0, "fruit practice starts ready with a deterministic spawn queue")
	check(bool(practice_fruit.handle_input({"type": "start"}).get("started", false)), "fruit practice starts on the child's tap")
	for _spawn_tick in 3:
		practice_fruit.tick(0.12)
	check(practice_state.fruits.size() == 1, "fruit practice spawns its first fruit")
	if practice_state.fruits.size() == 1:
		var practice_target: Dictionary = practice_state.fruits[0]
		var practice_hit: Dictionary = practice_fruit.handle_input({
			"type": "slice",
			"from": {"x": practice_target.x, "y": practice_target.y},
			"to": {"x": practice_target.x, "y": practice_target.y},
			"tap": true,
		})
		check(bool(practice_hit.get("ok", false)) and int(practice_state.sliced) == 1, "fruit practice accepts a light tap in addition to a swipe")
		var practice_events: Array = practice_fruit.drain_events()
		check(practice_events.any(func(event): return str(event.get("type", "")) == "slice"), "fruit slice emits a visual event")
		check(practice_fruit.drain_events().is_empty(), "fruit visual events drain exactly once")
	practice_fruit.tick(0.12)
	check(str(practice_state.phase) == "result" and str(practice_state.reason).contains("三波"), "fruit practice finishes after its final wave")
	var practice_restored = FruitRules.new()
	check(practice_restored.restore(practice_fruit.snapshot()), "fruit practice result snapshot restores")
	check(str(practice_restored.state.phase) == "result" and int(practice_restored.state.sliced) == 1, "restored fruit practice keeps the completed score and slice count")

	var combo_config := fruit_config.duplicate(true)
	combo_config.bombChance = 0.0
	combo_config.bonusChance = 0.0
	combo_config.comboWindow = 2.0
	var combo_fruit = FruitRules.new()
	var combo_state: Dictionary = combo_fruit.create_session({
		"gameId": "fruit_slice", "modeId": "challenge", "players": [player_one],
		"difficulty": "normal", "seed": 902, "fruitTypes": content.fruit_types(), "config": combo_config,
	})
	combo_fruit.handle_input({"type": "start"})
	combo_fruit.call("_spawn_one")
	combo_fruit.call("_spawn_one")
	check(combo_state.fruits.size() == 2, "fruit combo fixture has two active fruits")
	if combo_state.fruits.size() == 2:
		for fruit_entry in combo_state.fruits.duplicate(true):
			combo_fruit.handle_input({
				"type": "slice",
				"from": {"x": fruit_entry.x, "y": fruit_entry.y},
				"to": {"x": fruit_entry.x, "y": fruit_entry.y},
				"tap": true,
			})
	check(int(combo_state.combo) == 2 and int(combo_state.maxCombo) == 2, "fruit combo increments within the configured window")
	check(int(combo_state.score) == 22 and int(combo_state.sliced) == 2, "fruit combo awards increasing points for a quick pair")
	var combo_snapshot: Dictionary = combo_fruit.snapshot()
	check(combo_snapshot.events.is_empty(), "fruit snapshots never persist transient visual events")
	var combo_restored = FruitRules.new()
	check(combo_restored.restore(combo_snapshot), "fruit mid-challenge snapshot restores")
	check(str(combo_restored.state.rngState) == str(combo_snapshot.rngState), "fruit restore keeps the deterministic RNG state")
	check(combo_restored.state.spawnQueue == combo_snapshot.spawnQueue, "fruit restore keeps the pre-generated spawn queue")
	var broken_fruit: Dictionary = combo_snapshot.duplicate(true)
	broken_fruit.erase("rngState")
	var rejected_fruit = FruitRules.new()
	check(not rejected_fruit.restore(broken_fruit), "fruit rejects a snapshot without its RNG state")

	var bonus_config := fruit_config.duplicate(true)
	bonus_config.bombChance = 0.0
	bonus_config.bonusChance = 1.0
	var bonus_fruit = FruitRules.new()
	var bonus_state: Dictionary = bonus_fruit.create_session({
		"gameId": "fruit_slice", "modeId": "challenge", "players": [player_one],
		"difficulty": "normal", "seed": 903, "fruitTypes": content.fruit_types(), "config": bonus_config,
	})
	bonus_fruit.handle_input({"type": "start"})
	bonus_fruit.call("_spawn_one")
	if not bonus_state.fruits.is_empty():
		var bonus_target: Dictionary = bonus_state.fruits[0]
		check(str(bonus_target.get("special", "")) == "bonus", "fruit bonus fixture spawns a golden fruit")
		var bonus_hit: Dictionary = bonus_fruit.handle_input({
			"type": "slice",
			"from": {"x": bonus_target.x, "y": bonus_target.y},
			"to": {"x": bonus_target.x, "y": bonus_target.y},
			"tap": true,
		})
		check(bool(bonus_hit.get("ok", false)), "fruit bonus target can be sliced")
	check(int(bonus_state.score) == 60, "fruit bonus adds fifty points to the normal slice score")

	var bomb_config := fruit_config.duplicate(true)
	bomb_config.bombChance = 1.0
	bomb_config.bonusChance = 0.0
	var bomb_fruit = FruitRules.new()
	var bomb_state: Dictionary = bomb_fruit.create_session({
		"gameId": "fruit_slice", "modeId": "challenge", "players": [player_one],
		"difficulty": "normal", "seed": 904, "fruitTypes": content.fruit_types(), "config": bomb_config,
	})
	bomb_fruit.handle_input({"type": "start"})
	bomb_fruit.call("_spawn_one")
	bomb_state.score = 20
	if not bomb_state.fruits.is_empty():
		var bomb_target: Dictionary = bomb_state.fruits[0]
		var bomb_hit: Dictionary = bomb_fruit.handle_input({
			"type": "slice",
			"from": {"x": bomb_target.x, "y": bomb_target.y},
			"to": {"x": bomb_target.x, "y": bomb_target.y},
			"tap": true,
		})
		check(bool(bomb_hit.get("ok", false)), "fruit bomb can be sliced without ending the run")
	check(int(bomb_state.bombs) == 1 and int(bomb_state.score) == 15, "fruit bomb deducts five points without a life system")
	check(str(bomb_state.phase) == "playing", "fruit bomb keeps the challenge running")

	var timeout_config := fruit_config.duplicate(true)
	timeout_config.challengeSeconds = 0.5
	timeout_config.bombChance = 0.0
	timeout_config.bonusChance = 0.0
	var timeout_fruit = FruitRules.new()
	var timeout_state: Dictionary = timeout_fruit.create_session({
		"gameId": "fruit_slice", "modeId": "challenge", "players": [player_one],
		"difficulty": "normal", "seed": 905, "fruitTypes": content.fruit_types(), "config": timeout_config,
	})
	timeout_fruit.handle_input({"type": "start"})
	for _timer_tick in 5:
		timeout_fruit.tick(0.12)
	check(str(timeout_state.phase) == "result" and str(timeout_state.reason).contains("时间到"), "fruit challenge finishes when its rule timer expires")


func _check_action_games(content: Node, player_one: Dictionary, player_two: Dictionary) -> void:
	_check_tank_rules(content, player_one, player_two)
	_check_sokoban_rules(content, player_one, player_two)
	_check_circuit_rules(content, player_one, player_two)


func _check_tank_rules(content: Node, player_one: Dictionary, player_two: Dictionary) -> void:
	var levels: Array = content.tank_levels()
	var validation: Dictionary = TankRules.validate_catalog({"schemaVersion": 1, "levels": levels})
	check(bool(validation.get("ok", false)), "tank catalog validates every authored maze and fixed solution")
	check(levels.filter(func(level): return str(level.get("mode", "")) == "adventure").size() == 24, "tank has 24 solo mazes")
	check(levels.filter(func(level): return str(level.get("mode", "")) == "classic").size() == 6, "tank has 6 cooperative mazes")
	check(not levels.is_empty(), "tank levels are available to the rules test")
	if levels.is_empty():
		return
	var wall_rules = TankRules.new()
	wall_rules.create_session({
		"gameId": "tank", "modeId": "adventure", "players": [player_one],
		"levelId": 1, "level": levels[0], "seed": 1001,
	})
	var before_wall: Dictionary = wall_rules.tank_at(0)
	var blocked: Dictionary = wall_rules.move_tank(0, "left")
	check(bool(blocked.get("ok", false)) and not bool(blocked.get("moved", true)), "tank reports a wall without rejecting the turn")
	check(int(wall_rules.tank_at(0).get("x", -1)) == int(before_wall.get("x", -2)) and int(wall_rules.tank_at(0).get("y", -1)) == int(before_wall.get("y", -2)), "tank wall collision keeps the tank in place")

	var fixture: Dictionary = {}
	for level in levels:
		if str(level.get("mode", "")) != "adventure":
			continue
		if not (level.get("targets", []) as Array).is_empty() and not (level.get("gates", []) as Array).is_empty():
			fixture = level
			break
	check(not fixture.is_empty(), "tank exposes a target-and-gate fixture")
	if not fixture.is_empty():
		var tank = TankRules.new()
		tank.create_session({
			"gameId": "tank", "modeId": "adventure", "players": [player_one],
			"levelId": 2, "level": fixture, "seed": 1002,
		})
		var fired: Dictionary = tank.fire(0)
		check(bool(fired.get("ok", false)) and (tank.state.bullets as Array).size() == 1, "tank creates a foam shot in the rules state")
		var flight_snapshot: Dictionary = tank.snapshot()
		var flight_restore = TankRules.new()
		check(flight_restore.restore(flight_snapshot), "tank mid-flight shot snapshot restores")
		check(flight_restore.state.bullets == flight_snapshot.bullets, "tank restore keeps foam shots and their trajectory")
		var wrong_tank_level: Dictionary = flight_snapshot.duplicate(true)
		wrong_tank_level.levelId = int(wrong_tank_level.levelId) + 1
		check(not TankRules.new().restore(wrong_tank_level), "tank rejects a snapshot whose level id does not match its level")
		var corrupt_flight: Dictionary = flight_snapshot.duplicate(true)
		corrupt_flight.gatesOpen = {}
		corrupt_flight.events = {}
		var corrupt_restore = TankRules.new()
		check(corrupt_restore.restore(corrupt_flight), "tank repair-restores malformed gate and event containers")
		check(corrupt_restore.state.get("gatesOpen") is Array and corrupt_restore.state.get("events") is Array, "tank rebuilds safe collections after a malformed snapshot")
		for _hit_index in 3:
			tank.state.tanks[0].invuln = 0.0
			tank._damage_tank(0, "fixture")
		check(int(tank.state.tanks[0].shield) == 3 and int(tank.state.shieldBreaks) == 1, "tank bubble shield refills at its checkpoint after three hits")
		var replayed = _replay_tank_level(fixture, [player_one], 2)
		check(str(replayed.state.get("phase", "")) == "finished", "tank target-and-gate fixed solution reaches its goal")
		check(not (replayed.state.get("targetsActive", []) as Array).is_empty(), "tank fixed solution activates its signal target")
		check(not (replayed.state.get("gatesOpen", []) as Array).is_empty(), "tank signal target opens its linked gate")
		check(not (replayed.state.get("pickupsCollected", []) as Array).is_empty(), "tank fixed solution collects its star badges")
		var finished_snapshot: Dictionary = replayed.snapshot()
		var finished_restore = TankRules.new()
		check(finished_restore.restore(finished_snapshot), "tank completed snapshot restores")
		check(str(finished_restore.state.get("phase", "")) == "finished", "restored tank keeps every endpoint lit")

	var coop_level: Dictionary = {}
	for level in levels:
		if str(level.get("mode", "")) == "classic":
			coop_level = level
			break
	check(not coop_level.is_empty(), "tank exposes a cooperative fixture")
	if not coop_level.is_empty():
		var coop = _replay_tank_level(coop_level, [player_one, player_two], 25)
		check(coop.tank_count() == 2, "tank cooperative maze starts two independent tanks")
		check(str(coop.state.get("phase", "")) == "finished", "tank cooperative fixed solution lights both endpoints")
		check(str(coop.result().get("outcome", "")) == "played", "tank cooperative completion is recorded as played instead of a winner")
		var wrong_mode = TankRules.new()
		wrong_mode.create_session({
			"gameId": "tank", "modeId": "adventure", "players": [player_one],
			"levelId": 1, "level": coop_level, "seed": 1011,
		})
		check(str(wrong_mode.state.get("phase", "")) == "empty", "tank rejects a cooperative maze in solo mode")
	var patrol_level: Dictionary = {}
	for level in levels:
		if str(level.get("mode", "")) == "adventure" and not (level.get("movers", []) as Array).is_empty():
			patrol_level = level
			break
	if not patrol_level.is_empty():
		var patrol_a = TankRules.new()
		var patrol_b = TankRules.new()
		for rules in [patrol_a, patrol_b]:
			rules.create_session({
				"gameId": "tank", "modeId": "adventure", "players": [player_one],
				"levelId": 1, "level": patrol_level, "seed": 1019,
			})
		patrol_a.move_tank(0, "right")
		for _step_index in 15:
			patrol_a.tick(0.05)
			patrol_b.tick(0.05)
		var patrol_path_a: Array = []
		var patrol_path_b: Array = []
		for mover_value in patrol_level.get("movers", []):
			var mover: Dictionary = mover_value
			patrol_path_a.append(patrol_a.mover_cell(mover))
			patrol_path_b.append(patrol_b.mover_cell(mover))
		check(patrol_path_a == patrol_path_b, "tank patrol paths follow the same fixed timeline regardless of player movement")
		check(patrol_a.state.get("emitterTimers", []) == patrol_b.state.get("emitterTimers", []), "tank fixed emitters do not depend on player position")


func _replay_tank_level(level: Dictionary, players: Array, level_id: int = 1):
	var rules = TankRules.new()
	rules.create_session({
		"gameId": "tank",
		"modeId": str(level.get("mode", "adventure")),
		"players": players,
		"levelId": level_id,
		"level": level,
		"seed": 1010 + level_id,
	})
	for token_value in level.get("solution", []):
		var token := str(token_value)
		if token.begins_with("wait:"):
			_tick_tank_seconds(rules, float(token.substr(5)))
			continue
		var parts := token.split(":")
		if parts.size() < 2:
			continue
		var seat := int(parts[0])
		match str(parts[1]):
			"move":
				rules.move_tank(seat, str(parts[2]))
			"face":
				rules.face_tank(seat, str(parts[2]))
			"fire":
				rules.fire(seat)
	return rules


func _tick_tank_seconds(rules, seconds: float) -> void:
	var remaining := maxf(0.0, seconds)
	var guard := 0
	while remaining > 0.0001 and guard < 6000:
		rules.tick(minf(0.05, remaining))
		remaining -= 0.05
		guard += 1


func _check_sokoban_rules(content: Node, player_one: Dictionary, player_two: Dictionary) -> void:
	var levels: Array = content.sokoban_levels()
	var validation: Dictionary = SokobanRules.validate_catalog({"version": 1, "levels": levels})
	check(bool(validation.get("ok", false)), "sokoban catalog validates all 48 authored solutions")
	check(levels.filter(func(level): return not bool(level.get("coop", false))).size() == 36, "sokoban has 36 solo warehouses")
	check(levels.filter(func(level): return bool(level.get("coop", false))).size() == 12, "sokoban has 12 cooperative warehouses")
	check(not levels.is_empty(), "sokoban levels are available to the rules test")
	if levels.is_empty():
		return
	var first_level: Dictionary = levels[0]
	var rules = SokobanRules.new()
	rules.create_session({
		"gameId": "sokoban", "modeId": "adventure", "players": [player_one],
		"levelId": 1, "level": first_level, "seed": 1020,
	})
	var deadlock: Dictionary = rules.move("down")
	check(bool(deadlock.get("ok", false)), "sokoban accepts the first push toward a dead end")
	deadlock = rules.move("down")
	check(bool(deadlock.get("ok", false)) and bool(deadlock.get("deadlocked", false)), "sokoban reports a box trapped in a corner without deleting the session")
	check(bool(rules.undo().get("ok", false)), "sokoban can undo a dead-end push")
	check(bool(rules.restart().get("ok", false)), "sokoban can restart after a failed plan")
	for direction in first_level.get("solution", []):
		check(bool(rules.move(str(direction)).get("ok", false)), "sokoban accepts every authored direction")
	check(str(rules.state.get("phase", "")) == "finished" and int(rules.state.get("stars", 0)) == 3, "sokoban authored solution completes with three stars")
	var completed_snapshot: Dictionary = rules.snapshot()
	var restored = SokobanRules.new()
	check(restored.restore(completed_snapshot), "sokoban completed snapshot restores")
	check(str(restored.state.get("phase", "")) == "finished" and restored.boxes_on_goals() == restored.goal_count(), "restored sokoban keeps every box on a goal")
	var wrong_sokoban_level: Dictionary = completed_snapshot.duplicate(true)
	wrong_sokoban_level.levelId = int(wrong_sokoban_level.levelId) + 1
	check(not SokobanRules.new().restore(wrong_sokoban_level), "sokoban rejects a snapshot whose level id does not match its level")
	var duplicate_boxes: Dictionary = completed_snapshot.duplicate(true)
	duplicate_boxes.boxes = (duplicate_boxes.boxes as Array).duplicate(true)
	duplicate_boxes.boxes.append((duplicate_boxes.boxes as Array)[0].duplicate(true))
	check(not SokobanRules.new().restore(duplicate_boxes), "sokoban rejects duplicate or extra boxes in a snapshot")
	var wrong_sokoban_mode = SokobanRules.new()
	wrong_sokoban_mode.create_session({
		"gameId": "sokoban", "modeId": "classic", "players": [player_one, player_two],
		"levelId": 1, "level": first_level, "seed": 1022,
	})
	check(str(wrong_sokoban_mode.state.get("phase", "")) == "empty", "sokoban rejects a solo warehouse in cooperative mode")

	var coop_level: Dictionary = {}
	for level in levels:
		if bool(level.get("coop", false)):
			coop_level = level
			break
	check(not coop_level.is_empty(), "sokoban exposes a cooperative warehouse")
	if not coop_level.is_empty():
		var coop = SokobanRules.new()
		coop.create_session({
			"gameId": "sokoban", "modeId": "classic", "players": [player_one, player_two],
			"levelId": 1, "level": coop_level, "seed": 1021,
		})
		var opening := str((coop_level.get("solution", []) as Array)[0])
		check(bool(coop.move(opening).get("ok", false)), "sokoban cooperative warehouse accepts its opening move")
		check(coop.is_cooperative() and int(coop.state.get("turn", -1)) == 1, "sokoban cooperative move hands the shared turn to the second child")
		var coop_snapshot: Dictionary = coop.snapshot()
		var coop_restored = SokobanRules.new()
		check(coop_restored.restore(coop_snapshot), "sokoban cooperative snapshot restores")
		check(int(coop_restored.state.get("turn", -1)) == 1, "restored sokoban keeps the cooperative turn order")


func _check_circuit_rules(content: Node, player_one: Dictionary, player_two: Dictionary) -> void:
	var levels: Array = content.circuit_levels()
	var validation: Dictionary = CircuitRules.validate_catalog({"version": 1, "levels": levels})
	check(bool(validation.get("ok", false)), "circuit catalog validates all 32 solved low-voltage boards")
	check(levels.filter(func(level): return str(level.get("mode", "adventure")) == "adventure").size() == 24, "circuit workshop has 24 solo boards")
	check(levels.filter(func(level): return str(level.get("mode", "")) == "classic").size() == 8, "circuit workshop has 8 cooperative boards")
	check(not levels.is_empty(), "circuit levels are available to the rules test")
	if levels.is_empty():
		return
	var first_level: Dictionary = levels[0]
	var rules = CircuitRules.new()
	rules.create_session({
		"gameId": "circuit", "modeId": "adventure", "players": [player_one],
		"levelId": 1, "level": first_level, "seed": 1030,
	})
	check(rules.fault_index() >= 0 and not rules.last_fault().is_empty(), "circuit explains an open connection before the child starts")
	check(rules.powered_goal_count() == 0 and str(rules.state.get("phase", "")) == "playing", "circuit starts incomplete instead of pre-lit")
	var playing_snapshot: Dictionary = rules.snapshot()
	var restored = CircuitRules.new()
	check(restored.restore(playing_snapshot), "circuit mid-board snapshot restores")
	check(restored.piece_count() == rules.piece_count() and restored.fault_index() == rules.fault_index(), "restored circuit keeps its components and fault hint")
	var solved = _solve_circuit(first_level, [player_one], "adventure", 1)
	check(str(solved.state.get("phase", "")) == "finished" and solved.goals_completed(), "circuit authored solution powers every goal")
	check(int(solved.state.get("stars", 0)) == 3, "circuit clean authored solution earns three stars")
	var completed_snapshot: Dictionary = solved.snapshot()
	var completed_restore = CircuitRules.new()
	check(completed_restore.restore(completed_snapshot), "circuit completed snapshot restores")
	check(str(completed_restore.state.get("phase", "")) == "finished" and completed_restore.goals_completed(), "restored circuit keeps every target powered")
	var wrong_circuit_level: Dictionary = playing_snapshot.duplicate(true)
	wrong_circuit_level.levelId = int(wrong_circuit_level.levelId) + 1
	check(not CircuitRules.new().restore(wrong_circuit_level), "circuit rejects a snapshot whose level id does not match its board")

	var coop_level: Dictionary = {}
	for level in levels:
		if str(level.get("mode", "")) == "classic" and (level.get("solution", []) as Array).size() >= 2:
			coop_level = level
			break
	check(not coop_level.is_empty(), "circuit workshop exposes a cooperative board")
	if not coop_level.is_empty():
		var coop = CircuitRules.new()
		coop.create_session({
			"gameId": "circuit", "modeId": "classic", "players": [player_one, player_two],
			"levelId": 1, "level": coop_level, "seed": 1031,
		})
		var first_step: Dictionary = coop_level.solution[0]
		var index := int(first_step.get("index", -1))
		if first_step.has("rotation"):
			coop.rotate_part(index)
		elif first_step.has("closed"):
			coop.toggle_switch(index)
		check(coop.is_cooperative(), "circuit cooperative board recognizes both children")
		check(str(coop.state.get("phase", "")) == "finished" or int(coop.state.get("turn", -1)) == 1, "circuit cooperative action hands the shared turn to the second child")
		var coop_snapshot: Dictionary = coop.snapshot()
		var coop_restored = CircuitRules.new()
		check(coop_restored.restore(coop_snapshot), "circuit cooperative snapshot restores")
		check(int(coop_restored.state.get("turn", -1)) == int(coop_snapshot.get("turn", -2)), "restored circuit keeps its cooperative turn")
		var one_player_coop = CircuitRules.new()
		one_player_coop.create_session({
			"gameId": "circuit", "modeId": "classic", "players": [player_one],
			"levelId": 1, "level": coop_level, "seed": 1032,
		})
		check(str(one_player_coop.state.get("phase", "")) == "empty", "circuit rejects a cooperative board without two children")


func _solve_circuit(level: Dictionary, players: Array, mode_id: String, level_id: int):
	var rules = CircuitRules.new()
	rules.create_session({
		"gameId": "circuit", "modeId": mode_id, "players": players,
		"levelId": level_id, "level": level, "seed": 1040 + level_id,
	})
	for step_value in level.get("solution", []):
		if not step_value is Dictionary:
			continue
		var step: Dictionary = step_value
		var index := int(step.get("index", -1))
		if step.has("rotation"):
			var guard := 0
			while index >= 0 and int(rules.piece_at(index).get("rotation", -1)) != int(step.get("rotation", 0)) and guard < 4:
				rules.rotate_part(index)
				guard += 1
		if step.has("closed"):
			if index >= 0 and bool(rules.piece_at(index).get("closed", false)) != bool(step.get("closed", false)):
				rules.toggle_switch(index)
	return rules


func _check_refactor_saves(save_store: Node) -> void:
	var save_a: Dictionary = save_store.add_profile("存档甲", 7, "🦊", "#d56c29")
	var save_b: Dictionary = save_store.add_profile("存档乙", 9, "🐼", "#2878c8")
	check(not save_a.is_empty() and not save_b.is_empty(), "save fixture profiles are created")
	var lobby_defaults := ["tangram", "spot", "shop", "fruit_slice", "math", "workbook"]
	save_store.set_lobby_order(["shop", "math"])
	var restored_order: Array = save_store.lobby_order(lobby_defaults)
	check(
		restored_order.size() == lobby_defaults.size()
		and str(restored_order[0]) == "shop"
		and str(restored_order[1]) == "math"
		and "tangram" in restored_order
		and "fruit_slice" in restored_order,
		"saved lobby order is preserved while new games are filled by group"
	)
	save_store.set_context("chess", "classic", [str(save_a.id), str(save_b.id)])
	save_store.save_state("chess", str(save_a.id), {
		"gameId": "chess", "modeId": "classic", "phase": "playing",
		"players": [save_a, save_b], "levelId": 2,
	}, "共享测试局", true)
	check(save_store.shared_sessions_for(str(save_a.id)).size() == 1, "shared session is discoverable")
	save_store.delete_profile(str(save_a.id))
	check(save_store.profile(str(save_a.id)).is_empty(), "profile deletion removes the profile")
	check(not save_store.profile(str(save_b.id)).is_empty(), "profile deletion preserves the other child")
	var shared_values: Array = save_store.data.sessionSaves.get("chess", {}).values()
	check(not shared_values.is_empty(), "profile deletion archives rather than deletes a shared session")
	if not shared_values.is_empty():
		var shared_entry: Dictionary = shared_values[0]
		check(str(save_a.id) in shared_entry.get("archivedProfileIds", []), "shared session records the archived child")
	save_store.set_setting("sfxVolume", 0.51)
	check(save_store.flush(), "valid save flush succeeds")
	check(save_store.flush(), "a second valid flush can rotate the primary safely")
	var save_paths: Dictionary = save_store.storage_paths()
	check(FileAccess.file_exists(str(save_paths.backup)), "valid flush rotates a backup")
	var corrupt_file := FileAccess.open(str(save_paths.save), FileAccess.WRITE)
	corrupt_file.store_string("{broken")
	corrupt_file.close()
	save_store._primary_was_valid = false
	var recovered: Dictionary = save_store._load()
	check(recovered.get("profiles", []).any(func(item): return str(item.id) == str(save_b.id)), "corrupt main save recovers the last valid backup")
	var legacy: Dictionary = recovered.duplicate(true)
	legacy.schemaVersion = 1
	var legacy_file := FileAccess.open(str(save_paths.save), FileAccess.WRITE)
	legacy_file.store_string(JSON.stringify(legacy, "\t"))
	legacy_file.close()
	if FileAccess.file_exists(str(save_paths.backup)):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(str(save_paths.backup)))
	var migrated: Dictionary = save_store._load()
	check(int(migrated.get("schemaVersion", 0)) == 2, "legacy save envelope migrates to the current schema")
	var malformed: Dictionary = save_store.data.duplicate(true)
	malformed.schemaVersion = 2
	malformed.selections = {"math": "oops"}
	malformed.sessionSaves = "oops"
	malformed.learning = {str(save_b.id): "oops"}
	var malformed_file := FileAccess.open(str(save_paths.save), FileAccess.WRITE)
	malformed_file.store_string(JSON.stringify(malformed, "\t"))
	malformed_file.close()
	var normalized_bad: Dictionary = save_store._load()
	check(normalized_bad.get("profiles", []).any(func(item): return str(item.id) == str(save_b.id)), "nested corrupt save sections keep valid profiles")
	check(normalized_bad.get("selections") is Dictionary and normalized_bad.selections.is_empty(), "corrupt selection section falls back to an empty map")
	check(normalized_bad.get("sessionSaves") is Dictionary and normalized_bad.sessionSaves.is_empty(), "corrupt session section falls back without crashing")
	var old_save_path: String = str(save_paths.save)
	var old_backup_path: String = str(save_paths.backup)
	save_store._save_path = "user://missing-save-dir/failure.json"
	save_store._backup_path = "user://missing-save-dir/failure.backup.json"
	check(not save_store.flush() and not save_store.last_save_ok, "save failure returns an error instead of claiming success")
	var failed_outcome: bool = save_store.record_outcome(str(save_b.id), "save-retry-test", "win", 12, 1, 1, {}, "retry-outcome-fixture")
	check(not failed_outcome, "failed record flush reports failure")
	check(not save_store.data.recordedSessions.get(str(save_b.id), {}).has("retry-outcome-fixture"), "failed record does not commit the session dedupe marker")
	check(int(save_store.records_for(str(save_b.id)).games.get("save-retry-test", {}).get("plays", 0)) == 0, "failed record is rolled back in memory")
	save_store._save_path = old_save_path
	save_store._backup_path = old_backup_path
	var retried_outcome: bool = save_store.record_outcome(str(save_b.id), "save-retry-test", "win", 12, 1, 1, {}, "retry-outcome-fixture")
	check(retried_outcome, "record retry succeeds after storage recovers")
	check(int(save_store.records_for(str(save_b.id)).games.get("save-retry-test", {}).get("plays", 0)) == 1, "record retry commits exactly once")
	save_store.data = save_store._default_data()
	check(save_store.flush(), "save store can be reset after failure tests")
