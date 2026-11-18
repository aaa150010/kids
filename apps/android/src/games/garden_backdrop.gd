class_name GardenBackdrop
extends RefCounted


func draw_scene(canvas: CanvasItem, state: Dictionary, art: GardenArt) -> void:
	var environment := str(state.get("environment", "day"))
	var path := str(ContentDB.garden_presentation.get("scenes", {}).get(environment, "hd4/scenery/day.webp"))
	art.draw_image(canvas, path, Rect2(0, 0, 800, 600))
	if environment == "day":
		var lawn := art.texture("hd4/scenery/lawn.webp")
		if lawn != null:
			for row in int(state.get("rows", 5)):
				canvas.draw_texture_rect_region(lawn, Rect2(0, 80 + int(row) * 100, 800, 100), Rect2(0, (80 + int(row) * 100) * 4, 3200, 400))
	for grave in state.get("graves", []):
		var position := GardenLayout.foot(state, int(grave.row), float(grave.col) + .5)
		art.draw_image(canvas, "original/grave.webp", Rect2(position - Vector2(30, 65), Vector2(60, 73)), Color.WHITE, true)
	for crater in state.get("craters", []):
		var position := GardenLayout.foot(state, int(crater.row), float(crater.col) + .5)
		art.draw_image(canvas, "original/crater.webp", Rect2(position - Vector2(40, 25), Vector2(80, 40)), Color.WHITE, true)
	for trail in state.get("iceTrails", []):
		var position := GardenLayout.foot(state, int(trail.row), float(trail.x))
		art.draw_image(canvas, "original/ice-trail.webp", Rect2(position - Vector2(0, 35), Vector2(maxf(0, 800 - position.x), 55)))
	if str(state.get("special", "")) == "bowling":
		canvas.draw_line(Vector2(280, 80), Vector2(280, 580), Color("#bf3934"), 3)
	if environment in ["pool", "fog"]:
		for row in [2, 3]:
			var position := GardenLayout.foot(state, row, 4.5)
			for offset in 4:
				var center := Vector2(150 + offset * 160, position.y - 20 + sin(float(state.time) * 1.5 + offset) * 3)
				canvas.draw_arc(center, 12, .1, 2.6, 10, Color(1, 1, 1, .1), 1, true)
