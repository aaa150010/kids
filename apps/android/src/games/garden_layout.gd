class_name GardenLayout
extends RefCounted

const BOARD_SIZE := Vector2(800, 600)
const GRID_ORIGIN := Vector2(40, 80)
const CELL_WIDTH := 80.0
const MOWER_START_COLUMN := -.25


static func metrics(bounds: Vector2) -> Dictionary:
	var scale_factor := minf(bounds.x / BOARD_SIZE.x, bounds.y / BOARD_SIZE.y)
	return {"scale": scale_factor, "origin": (bounds - BOARD_SIZE * scale_factor) * .5}


static func column_x(column: float) -> float:
	return GRID_ORIGIN.x + column * CELL_WIDTH


static func cell_height(state: Dictionary) -> float:
	var environment := str(state.get("environment", ""))
	return 85.0 if environment in ["pool", "fog", "roof"] else 100.0


static func slope(state: Dictionary, column: float) -> float:
	if str(state.get("environment", "day")) != "roof":
		return 0.0
	return maxf(0.0, 440.0 - column_x(column)) * .25


static func foot(state: Dictionary, row: int, column: float) -> Vector2:
	var height := cell_height(state)
	var environment := str(state.get("environment", "day"))
	var baseline := 68.0 if environment in ["pool", "fog"] else 58.0 if environment == "roof" else 78.0
	return Vector2(column_x(column), GRID_ORIGIN.y + row * height + baseline + slope(state, column))


static func cell_foot(state: Dictionary, row: int, column: int) -> Vector2:
	return foot(state, row, float(column) + .5)


static func plant_anchor(state: Dictionary, plant: Dictionary) -> Vector2:
	var anchor := cell_foot(state, int(plant.row), int(plant.col))
	if str(state.get("environment", "day")) == "roof" and str(plant.kind) != "flowerpot":
		anchor.y -= 12.0
	return anchor


static func point(state: Dictionary, column: float, row_position: float) -> Vector2:
	return Vector2(column_x(column), GRID_ORIGIN.y + row_position * cell_height(state) + slope(state, column))


static func cell_center(state: Dictionary, row: int, column: int) -> Vector2:
	return point(state, float(column) + .5, float(row) + .5) - Vector2(0, _roof_top_offset(state))


static func cell_polygon(state: Dictionary, row: int, column: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	for corner in [Vector2(column, row), Vector2(column + 1, row), Vector2(column + 1, row + 1), Vector2(column, row + 1)]:
		points.append(point(state, corner.x, corner.y) - Vector2(0, _roof_top_offset(state)))
	return points


static func _roof_top_offset(state: Dictionary) -> float:
	return 10.0 if str(state.get("environment", "day")) == "roof" else 0.0


static func cell_at(state: Dictionary, position: Vector2) -> Vector2i:
	var column_position := (position.x - GRID_ORIGIN.x) / CELL_WIDTH
	var column := int(floor(column_position))
	var row := int(floor((position.y - GRID_ORIGIN.y - slope(state, column_position) + _roof_top_offset(state)) / cell_height(state)))
	return Vector2i(column, row)


static func seed_rect(index: int) -> Rect2:
	return Rect2(85 + index * 52, 8, 49, 65)


static func seed_at(position: Vector2, count: int) -> int:
	for index in mini(count, 10):
		if seed_rect(index).has_point(position):
			return index
	return -1
