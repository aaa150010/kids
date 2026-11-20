extends SceneTree

var service: Node
var started_at := 0.0
var story: Dictionary = {}


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var content := root.get_node_or_null("ContentDB")
	service = root.get_node_or_null("StoryImages")
	if content == null or service == null or content.stories.is_empty():
		push_error("story image probe prerequisites missing")
		quit(1)
		return
	story = content.stories[0]
	service.story_ready.connect(_on_ready)
	service.story_failed.connect(_on_failed)
	started_at = Time.get_ticks_msec()
	service.prepare_story(story)


func _process(_delta: float) -> bool:
	var state: Dictionary = service.story_state(story)
	if bool(state.get("ready", false)):
		print("story image probe ready: %s cached=%s/%s" % [story.id, state.cached, state.total])
		quit(0)
		return true
	if Time.get_ticks_msec() - started_at > 45000:
		push_error("story image probe timeout")
		quit(1)
		return true
	return false


func _on_ready(story_id: String) -> void:
	if story_id != str(story.id):
		return
	var state: Dictionary = service.story_state(story)
	print("story image probe ready: %s cached=%s/%s" % [story_id, state.cached, state.total])
	quit(0)


func _on_failed(story_id: String, message: String) -> void:
	if story_id != str(story.id):
		return
	push_error("story image probe failed: " + message)
	quit(1)
