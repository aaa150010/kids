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
	check(content.games.size() == 13, "catalog contains 13 entries including the story library")
	check(content.tuning.get("games", {}).size() == 13, "tuning covers all catalog entries")
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
	check(content.garden_levels().size() == 50, "garden contains 50 levels")
	check(content.garden_plants().size() >= 48, "garden contains at least 48 plant definitions")
	check(content.garden.get("zombieAlmanac", []).size() >= 25, "garden zombie almanac is loaded")
	for game_id in ["math", "pinyin", "patterns", "animals"]:
		check(content.quizzes.get(game_id, []).size() > 0, "%s questions are loaded" % game_id)
	for game_id in ["island", "jungle", "gomoku", "military", "memory", "math", "pinyin", "patterns", "animals", "workbook"]:
		check(content.chapters.get(game_id, []).size() > 0, "%s adventure levels are loaded" % game_id)
	for game_id in ["jungle", "gomoku", "military"]:
		check(content.puzzles.get(game_id, []).size() > 0, "%s puzzle fixtures are loaded" % game_id)

	var fake_player = {
		"id": "test-player",
		"name": "测试小朋友",
		"age": 7,
		"avatar": "🦊",
		"color": "#d56c29",
	}
	for level_number in range(1, 51):
		var mapped: Dictionary = PvZLevelFactory.build(level_number, "adventure", [], "normal")
		var level: ResourceLevelData = mapped.get("level")
		check(level != null, "PvZ level %s maps into the upstream resource format" % level_number)
		check(level.max_wave >= 10 and level.max_wave % 10 == 0, "PvZ level %s keeps complete upstream flag blocks" % level_number)
		check(str(mapped.get("scene", "")).begins_with("res://pvz/scenes/main/MainGame"), "PvZ level %s selects an embedded upstream scene" % level_number)
	var easy_level: ResourceLevelData = PvZLevelFactory.build(1, "adventure", ["sunflower"], "easy").get("level")
	var challenge_level: ResourceLevelData = PvZLevelFactory.build(1, "adventure", ["sunflower"], "challenge").get("level")
	check(easy_level.start_sun > challenge_level.start_sun, "younger PvZ difficulty starts with more sun")
	check(PvZLevelFactory.plant_type("peashooter") == CharacterRegistry.PlantType.P001PeaShooterSingle, "peashooter maps to the upstream plant registry")
	check(PvZLevelFactory.zombie_type("digger") == CharacterRegistry.ZombieType.Z018Digger, "digger maps to the upstream zombie registry")

	var pack_data: Array = content.garden.get("plantAlmanac", [])
	for entry in pack_data:
		check(not str(entry.get("name", "")).is_empty(), "every almanac plant has a name")

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

	var military_levels: Array = content.puzzles.get("military", [])
	var military_puzzle: Dictionary = military_levels[0]
	var military_rules = BoardRulesResource.new()
	var military_state: Dictionary = military_rules.create_session({
		"gameId": "military",
		"modeId": "puzzle",
		"players": [fake_player],
		"seed": 44,
		"puzzle": military_puzzle,
	})
	check(bool(military_rules.handle_input({"type":"select","to":5}).ok), "military engineer can be selected")
	check(bool(military_rules.handle_input({"type":"move","to":6}).ok) and military_state.phase == "finished", "military engineer clears a mine in a puzzle")
	check(bool(military_state.get("factionAssigned", true)), "military puzzle starts with assigned factions")

	var military_classic = BoardRulesResource.new()
	var military_classic_state: Dictionary = military_classic.create_session({
		"gameId": "military",
		"modeId": "classic",
		"players": [fake_player, fake_player_two],
		"seed": 47,
	})
	check(not bool(military_classic_state.factionAssigned), "military classic waits for faction assignment")
	var hidden_by_side := {"0": [], "1": []}
	for piece in military_classic_state.pieces:
		if not bool(piece.revealed):
			hidden_by_side[str(int(piece.side))].append(int(piece.position))
	check(hidden_by_side["0"].size() >= 3 and hidden_by_side["1"].size() >= 2, "military classic has enough hidden pieces to assign factions")
	var flip_one: Dictionary = military_classic.handle_input({"type":"move","to":int(hidden_by_side["0"][0])})
	var flip_two: Dictionary = military_classic.handle_input({"type":"move","to":int(hidden_by_side["1"][0])})
	var flip_three: Dictionary = military_classic.handle_input({"type":"move","to":int(hidden_by_side["0"][1])})
	check(bool(flip_one.ok) and bool(flip_two.ok) and bool(flip_three.ok), "military flips alternate between players")
	check(bool(military_classic_state.factionAssigned) and bool(flip_three.get("factionAssigned", false)), "two same-side flips assign the player faction")
	check(int(military_classic_state.factionSides[0]) == 0 and int(military_classic_state.factionSides[1]) == 1, "assigned factions split both sides")
	check(int(military_classic.player_side(0)) == 0 and int(military_classic.player_for_side(1)) == 1, "military faction mapping is symmetric")

	var reset_game = BoardRulesResource.new()
	var reset_state: Dictionary = reset_game.create_session({
		"gameId": "military",
		"modeId": "classic",
		"players": [fake_player, fake_player_two],
		"seed": 47,
	})
	var reset_zero: Array = []
	var reset_one: Array = []
	for piece in reset_state.pieces:
		if not bool(piece.revealed):
			if int(piece.side) == 0:
				reset_zero.append(int(piece.position))
			else:
				reset_one.append(int(piece.position))
	reset_game.handle_input({"type":"move","to":int(reset_zero[0])})
	reset_game.handle_input({"type":"move","to":int(reset_one[0])})
	reset_game.handle_input({"type":"move","to":int(reset_one[1])})
	check(not bool(reset_state.factionAssigned) and int(reset_state.factionLastSides[0]) == 1, "an opposite flip resets that player's faction streak")

	var legacy_military = BoardRulesResource.new()
	var legacy_save: Dictionary = reset_game.snapshot()
	legacy_save.erase("factionSides")
	legacy_save.erase("factionAssigned")
	legacy_save.erase("factionLastSides")
	check(legacy_military.restore(legacy_save), "legacy military snapshot still restores")
	check(bool(legacy_military.state.factionAssigned) and int(legacy_military.state.factionSides[0]) == 0, "legacy military saves default to fixed factions")

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
