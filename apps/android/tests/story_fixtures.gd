extends RefCounted

const Session = preload("res://src/games/story_session.gd")


func run(content: Node, check: Callable) -> void:
	check.call(content.stories.size() == 600, "stories contains 600 independent entries")
	var totals := {"idiom":0,"myth":0,"folk":0,"fable":0,"history":0,"fairy":0}
	var titles := {}
	for story in content.stories:
		check.call(not titles.has(str(story.title)), "story titles are unique: " + str(story.title))
		titles[str(story.title)] = true
		totals[str(story.category)] = int(totals.get(str(story.category), 0)) + 1
		check.call(story.paragraphs.size() >= 2, "story retains a complete segmented narrative: " + str(story.title))
		check.call(int(story.get("contentRevision", 0)) >= 2, "story content has a reviewed revision: " + str(story.title))
		var paragraph_ids := {}
		for paragraph in story.paragraphs:
			check.call(not str(paragraph.get("id", "")).is_empty(), "paragraph has a stable identifier: " + str(story.title))
			check.call(not paragraph_ids.has(str(paragraph.id)), "paragraph identifiers are unique: " + str(story.title))
			paragraph_ids[str(paragraph.id)] = true
			check.call(str(paragraph.text).length() == paragraph.pinyin.size(), "ruby aligns to every character: " + str(story.title))
		var illustrations: Array = story.get("illustrations", [])
		check.call(illustrations.size() in [2, 3], "story has two or three illustrations: " + str(story.title))
		for illustration in illustrations:
			check.call(paragraph_ids.has(str(illustration.get("paragraphId", ""))), "illustration anchor exists: " + str(story.title))
			check.call(str(illustration.get("side", "")) in ["left", "right"], "illustration float side is valid: " + str(story.title))
			check.call(str(illustration.get("asset", "")).is_empty(), "story illustration is not bundled in the APK: " + str(story.title))
			check.call(str(illustration.get("remoteUrl", "")).begins_with("https://lynote.xyz/play-app/story-images/"), "story illustration has a remote URL: " + str(story.title))
			check.call(str(illustration.get("sha256", "")).length() == 64, "story illustration has a content hash: " + str(story.title))
			check.call(int(illustration.get("size", 0)) > 0, "story illustration has an expected size: " + str(story.title))
	check.call(totals == {"idiom":200,"myth":80,"folk":80,"fable":80,"history":60,"fairy":100}, "story category counts match the agreed library")
	var order: Array = content.default_order()
	check.call(order.find("workbook") == order.find("poetry") + 1 and order.find("stories") == order.find("workbook") + 1, "default learning shelf preserves poetry/workbook adjacency")
	var catalog := {
		"one": {
			"contentRevision": 2,
			"paragraphs": [
				{"id":"opening","text":"第一段"},
				{"id":"ending","text":"第二段"},
			],
			"illustrations": [],
		},
		"two": {
			"contentRevision": 1,
			"paragraphs": [{"id":"only","text":"另一篇"}],
			"illustrations": [],
		},
	}
	var player := {"id":"story-fixture-a","name":"小禾","age":5,"avatar":"🐰","color":"#a72e40"}
	var first = Session.new()
	first.create_session(player, catalog)
	check.call(bool(first.state.pinyin), "young children start with pinyin")
	first.handle_input({"type":"open","id":"one"})
	first.handle_input({"type":"favorite"})
	first.handle_input({
		"type":"bookmark",
		"value":{
			"reading":{"paragraphId":"ending","characterIndex":1,"lineOffset":0.2},
			"listening":{"paragraphId":"opening"},
			"followReading":false,
		},
	})
	first.handle_input({"type":"complete"})
	first.handle_input({"type":"font"})
	var saved: Dictionary = first.snapshot()
	var updated_profile: Dictionary = player.duplicate(true)
	updated_profile.name = "大厅改过的名字"
	updated_profile.age = 8
	var restored = Session.new()
	restored.create_session(updated_profile, catalog)
	check.call(restored.restore(saved), "reading snapshot restores")
	check.call(restored.state.player.name == "小禾" and int(restored.state.player.age) == 5, "in-progress player remains the snapshot participant")
	check.call(
		str(restored.reading_anchor().paragraphId) == "ending"
		and int(restored.reading_anchor().characterIndex) == 1
		and str(restored.listening_paragraph_id()) == "opening"
		and restored.state.phase == "reading",
		"reading and listening anchors survive reopen"
	)
	check.call(int(restored.state.fontSize) == 40 and restored.state.completed == ["one"], "font and completion survive without duplicate scoring")
	var second_player: Dictionary = player.duplicate(true)
	second_player.id = "story-fixture-b"
	var second = Session.new()
	second.create_session(second_player, catalog)
	check.call(not second.restore(saved), "another child's snapshot cannot be loaded")
	check.call(second.state.favorites.is_empty() and second.state.bookmarks.is_empty(), "children's favorites and positions remain isolated")
	var legacy = Session.new()
	legacy.create_session(player, catalog, {"pinyin":false})
	check.call(not bool(legacy.state.pinyin), "learning preferences retain pinyin off")
	var legacy_snapshot: Dictionary = restored.snapshot()
	legacy_snapshot.schemaVersion = 2
	legacy_snapshot.bookmarks.one = {"paragraph":1,"offset":0.5}
	var migrated = Session.new()
	migrated.create_session(player, catalog)
	check.call(migrated.restore(legacy_snapshot), "schema 2 reading snapshot restores")
	check.call(
		str(migrated.reading_anchor().paragraphId) == "ending"
		and str(migrated.listening_paragraph_id()) == "ending",
		"legacy paragraph indexes migrate to stable identifiers"
	)
	var corrupt: Dictionary = saved.duplicate(true)
	corrupt.storyId = "removed-story"
	corrupt.fontSize = {"bad":true}
	corrupt.bookmarks.one = {
		"reading":{"paragraphId":"removed","characterIndex":[],"lineOffset":{}},
		"listening":{"paragraphId":"removed"},
		"followReading":"bad",
	}
	check.call(restored.restore(corrupt), "bad optional fields fall back safely")
	check.call(restored.state.phase == "library" and int(restored.state.fontSize) == 34, "missing story and invalid font fall back")
	check.call(
		str(restored.state.bookmarks.one.reading.paragraphId) == "opening"
		and int(restored.state.bookmarks.one.reading.characterIndex) == 0,
		"corrupt paragraph anchor falls back to the first paragraph"
	)
	restored.handle_input({"type":"open","id":"one"})
	restored.handle_input({"type":"restart"})
	check.call(restored.state.favorites == ["one"] and restored.state.completed == ["one"], "restarting this story retains favorites and footprints")
	var copied: Dictionary = first.learning_snapshot()
	copied.favorites.clear()
	check.call(first.state.favorites == ["one"], "learning snapshots do not alias the live session")
