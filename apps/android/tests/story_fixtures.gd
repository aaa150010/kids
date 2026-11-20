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
		for paragraph in story.paragraphs:
			check.call(str(paragraph.text).length() == paragraph.pinyin.size(), "ruby aligns to every character: " + str(story.title))
	check.call(totals == {"idiom":200,"myth":80,"folk":80,"fable":80,"history":60,"fairy":100}, "story category counts match the agreed library")
	var order: Array = content.default_order()
	check.call(order.find("workbook") == order.find("poetry") + 1 and order.find("stories") == order.find("workbook") + 1, "default learning shelf preserves poetry/workbook adjacency")
	var catalog := {"one":{"paragraphs":[{"text":"第一段"},{"text":"第二段"}]},"two":{"paragraphs":[{"text":"另一篇"}]}}
	var player := {"id":"story-fixture-a","name":"小禾","age":5,"avatar":"🐰","color":"#a72e40"}
	var first = Session.new()
	first.create_session(player, catalog)
	check.call(bool(first.state.pinyin), "young children start with pinyin")
	first.handle_input({"type":"open","id":"one"})
	first.handle_input({"type":"favorite"})
	first.handle_input({"type":"bookmark","value":{"position":12.4,"paragraph":1,"offset":0.3}})
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
	check.call(is_equal_approx(float(restored.bookmark().position), 12.4) and restored.state.phase == "reading", "audio position and reading phase survive reopen")
	check.call(int(restored.state.fontSize) == 34 and restored.state.completed == ["one"], "font and completion survive without duplicate scoring")
	var second_player: Dictionary = player.duplicate(true)
	second_player.id = "story-fixture-b"
	var second = Session.new()
	second.create_session(second_player, catalog)
	check.call(not second.restore(saved), "another child's snapshot cannot be loaded")
	check.call(second.state.favorites.is_empty() and second.state.bookmarks.is_empty(), "children's favorites and positions remain isolated")
	var corrupt: Dictionary = saved.duplicate(true)
	corrupt.storyId = "removed-story"
	corrupt.fontSize = {"bad":true}
	corrupt.bookmarks.one = {"position":[],"paragraph":999,"offset":{}}
	check.call(restored.restore(corrupt), "bad optional fields fall back safely")
	check.call(restored.state.phase == "library" and int(restored.state.fontSize) == 28, "missing story and invalid font fall back")
	check.call(is_zero_approx(float(restored.state.bookmarks.one.position)) and int(restored.state.bookmarks.one.paragraph) == 1, "corrupt bookmark is clamped without removing other progress")
	restored.handle_input({"type":"open","id":"one"})
	restored.handle_input({"type":"restart"})
	check.call(restored.state.favorites == ["one"] and restored.state.completed == ["one"], "restarting this story retains favorites and footprints")
	var copied: Dictionary = first.learning_snapshot()
	copied.favorites.clear()
	check.call(first.state.favorites == ["one"], "learning snapshots do not alias the live session")
