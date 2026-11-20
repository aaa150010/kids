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
