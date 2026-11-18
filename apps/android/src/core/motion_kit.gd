class_name MotionKit
extends RefCounted

const PRESS_DOWN := 0.07
const PRESS_UP := 0.13
const MODAL_IN := 0.18
const MODAL_OUT := 0.12
const PAGE_FADE := 0.20
const CARD_IN := 0.24
const FLIP := 0.26
const MOVE := 0.24

static var _owned: Dictionary = {}


static func tween(owner: Node) -> Tween:
	_connect_cleanup(owner)
	var animation := owner.create_tween()
	var key := owner.get_instance_id()
	var list: Array = _live_tweens(key)
	list.append(animation)
	_owned[key] = list
	animation.finished.connect(func(): _forget(key, animation))
	return animation


static func adopt(owner: Node, animation: Tween) -> Tween:
	_connect_cleanup(owner)
	var key := owner.get_instance_id()
	var list: Array = _live_tweens(key)
	if not animation in list:
		list.append(animation)
	_owned[key] = list
	animation.finished.connect(func(): _forget(key, animation))
	return animation


static func _connect_cleanup(owner: Node) -> void:
	if owner.has_meta("_motion_cleanup"):
		return
	owner.set_meta("_motion_cleanup", true)
	var key := owner.get_instance_id()
	owner.tree_exited.connect(func(): _owned.erase(key))


static func _forget(key: int, animation: Tween) -> void:
	if not _owned.has(key):
		return
	var list: Array = _owned[key]
	list.erase(animation)
	if list.is_empty():
		_owned.erase(key)
	else:
		_owned[key] = list


static func _live_tweens(key: int) -> Array:
	# kill() 不会发 finished；主动清理，避免每次按压积累已终止的Tween。
	var live: Array = []
	for animation in _owned.get(key, []):
		if is_instance_valid(animation) and animation.is_valid():
			live.append(animation)
	if live.is_empty():
		_owned.erase(key)
	else:
		_owned[key] = live
	return live


static func set_paused(owner: Node, paused: bool) -> void:
	for animation in _live_tweens(owner.get_instance_id()):
		if not is_instance_valid(animation):
			continue
		if paused:
			animation.pause()
		elif not animation.is_running():
			animation.play()


static func set_paused_tree(root: Node, paused: bool) -> void:
	for key in _owned.keys():
		if not is_instance_id_valid(int(key)):
			continue
		var owner: Node = instance_from_id(int(key))
		if owner == null or not (owner == root or root.is_ancestor_of(owner)):
			continue
		set_paused(owner, paused)


static func kill_owner(owner: Node) -> void:
	var key := owner.get_instance_id()
	for animation in _owned.get(key, []):
		if is_instance_valid(animation):
			animation.kill()
	_owned.erase(key)


static func fade_in(node: CanvasItem, owner: Node = null, duration: float = 0.22, from_y: float = 10.0) -> void:
	node.modulate.a = 0.0
	var animation := tween(owner if owner != null else node)
	animation.set_parallel(true)
	animation.tween_property(node, "modulate:a", 1.0, duration)
	# 容器负责子节点位置；共享入场方法也必须守住此约束。
	if not is_zero_approx(from_y) and not (node is Control and node.get_parent() is Container):
		node.position.y += from_y
		animation.tween_property(node, "position:y", node.position.y - from_y, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


static func press_pop(node: Control) -> void:
	kill_owner(node)
	node.pivot_offset = node.size * 0.5
	var animation := tween(node)
	animation.tween_property(node, "scale", Vector2.ONE * 0.97, PRESS_DOWN)
	animation.tween_property(node, "scale", Vector2.ONE, PRESS_UP).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


static func fade_out_and_free(node: CanvasItem, owner: Node = null, duration: float = MODAL_OUT) -> void:
	if not is_instance_valid(node):
		return
	var animation := tween(owner if owner != null else node)
	animation.tween_property(node, "modulate:a", 0.0, duration)
	animation.tween_callback(node.queue_free)
