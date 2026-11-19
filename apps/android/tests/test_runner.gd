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
	check(content.games.size() == 11, "catalog contains 11 entries including the story library")
	check(content.tuning.get("games", {}).size() == 11, "tuning covers all catalog entries")
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
	for game_id in ["jungle", "gomoku", "memory", "math", "pinyin", "patterns", "animals", "workbook"]:
		check(content.chapters.get(game_id, []).size() > 0, "%s adventure levels are loaded" % game_id)
	for game_id in ["jungle", "gomoku"]:
		check(content.puzzles.get(game_id, []).size() > 0, "%s puzzle fixtures are loaded" % game_id)
	check(content.military_formations().size() == 3, "military has three preset formations")
	check(content.military_puzzles().size() == 24, "military has 24 fixed endgame puzzles")

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
	poetry_screen.free()

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

	if failures.is_empty():
		print("Native content, board, quiz and memory checks passed.")
		get_tree().quit(0)
	else:
		print("Native checks failed: %d" % failures.size())
		get_tree().quit(1)
