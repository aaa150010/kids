class_name TabletopLayout
extends RefCounted

const BOARD_GAMES := ["chess", "military", "jungle", "gomoku"]


static func enabled(game_id: String, players: Array, mode_id: String) -> bool:
	return game_id in BOARD_GAMES and players.size() == 2 and mode_id == "classic"


static func facing_angle(side: int, tabletop: bool = true) -> float:
	if not tabletop:
		return 0.0
	return PI * 0.5 if side == 0 else -PI * 0.5


static func canvas_size(available: Vector2, angle: float) -> Vector2:
	return Vector2(available.y, available.x) if not is_zero_approx(angle) else available


static func layout_canvas(canvas: Control, available: Vector2, angle: float) -> void:
	canvas.set_anchors_preset(Control.PRESET_TOP_LEFT)
	canvas.pivot_offset = Vector2.ZERO
	canvas.size = canvas_size(available, angle)
	canvas.rotation = angle
	canvas.position = Vector2(available.x, 0.0) if angle > 0.0 else Vector2(0.0, available.y) if angle < 0.0 else Vector2.ZERO


static func input_blocked(surface: Control) -> bool:
	var owner := surface.get_parent()
	while owner != null:
		if owner is NativeGameScreen:
			if owner.paused or not owner._modal_stack.is_empty():
				return true
			break
		owner = owner.get_parent()
	var tree := surface.get_tree()
	var hub := tree.get_first_node_in_group("main_hub") if tree != null else null
	var controller := hub.get("ipc") as InteractionController if hub != null else null
	return controller != null and controller.is_blocked_by_dialog()


static func remember_seat(surface: Control, side: int) -> void:
	var owner := surface.get_parent()
	while owner != null:
		if owner is NativeGameScreen:
			owner._interaction_seat = side
			owner._last_actor_seat = side
			return
		owner = owner.get_parent()


# Seat marks belong to the edge of the toy board, so the turn remains visible
# while the surrounding application controls are hidden.
static func draw_turn_marks(canvas: Control, participants: Array, turn: int, tabletop: bool, colors: Array, finished: bool = false) -> void:
	var font := PlaygroundUI.font()
	for side in (2 if tabletop else 1):
		var player_side: int = side if tabletop else turn
		var name := str(participants[player_side].get("name", "")) if player_side < participants.size() else ""
		var text := "本局完成" if finished else (name + "走棋" if not name.is_empty() else "轮到红方" if player_side == 0 else "轮到另一方")
		if tabletop and not finished and player_side != turn:
			text = name if not name.is_empty() else "左边的小伙伴" if side == 0 else "右边的小伙伴"
		var tint: Color = colors[player_side % colors.size()]
		var center := Vector2(19.0 if side == 0 else canvas.size.x - 19.0, canvas.size.y * 0.5) if tabletop else Vector2(canvas.size.x * 0.5, 19.0)
		canvas.draw_set_transform(center, facing_angle(player_side, tabletop), Vector2.ONE)
		var width := minf(230.0, font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x + 44.0)
		var active := player_side == turn and not finished
		canvas.draw_style_box(PlaygroundUI.style(PlaygroundUI.mix(tint, Color.WHITE, 0.86 if active else 0.96), 14, tint if active else PlaygroundUI.mix(tint, Color.WHITE, 0.65), 2 if active else 1), Rect2(-width * 0.5, -14.0, width, 28.0))
		canvas.draw_circle(Vector2(-width * 0.5 + 14.0, 0), 5.0, tint if active else PlaygroundUI.mix(tint, Color.WHITE, 0.70))
		canvas.draw_string(font, Vector2(-width * 0.5 + 27.0, 6.0), text, HORIZONTAL_ALIGNMENT_LEFT, width - 34.0, 17, tint)
		canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


static func draw_note(canvas: Control, anchor: Vector2, message: String, angle: float, tint: Color, icon: String = "hint") -> void:
	if message.is_empty():
		return
	var font := PlaygroundUI.font()
	var max_width := minf(380.0, (canvas.size.y if not is_zero_approx(angle) else canvas.size.x) - 36.0)
	var lines: Array[String] = [""]
	for index in message.length():
		var letter := message.substr(index, 1)
		if font.get_string_size(lines[-1] + letter, HORIZONTAL_ALIGNMENT_LEFT, -1, 19).x > max_width - 64.0:
			lines.append("")
		lines[-1] += letter
	var width := 100.0
	for line in lines:
		width = maxf(width, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, 19).x + 64.0)
	var height := float(lines.size()) * 27.0 + 20.0
	var extent := Vector2(height, width) if not is_zero_approx(angle) else Vector2(width, height)
	var center := anchor + Vector2(0.0, -height * 0.5 - 42.0).rotated(angle)
	center.x = clampf(center.x, extent.x * 0.5 + 8.0, canvas.size.x - extent.x * 0.5 - 8.0)
	center.y = clampf(center.y, extent.y * 0.5 + 8.0, canvas.size.y - extent.y * 0.5 - 8.0)
	canvas.draw_set_transform(center, angle, Vector2.ONE)
	canvas.draw_style_box(PlaygroundUI.style(Color("#fffdf4"), 18, tint, 2, 6, Color(0, 0, 0, 0.14)), Rect2(-Vector2(width, height) * 0.5, Vector2(width, height)))
	var texture := ArtLibrary.semantic_texture(icon)
	if texture != null:
		canvas.draw_texture_rect(texture, Rect2(-width * 0.5 + 12.0, -14.0, 28.0, 28.0), false)
	for index in lines.size():
		canvas.draw_string(font, Vector2(-width * 0.5 + 50.0, -height * 0.5 + 29.0 + float(index) * 27.0), lines[index], HORIZONTAL_ALIGNMENT_LEFT, width - 60.0, 19, tint)
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
