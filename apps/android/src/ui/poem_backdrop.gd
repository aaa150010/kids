class_name PoemBackdrop
extends Control

var poem_text := ""

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func _draw() -> void:
	for index in range(30,int(size.y),38):
		draw_line(Vector2(24,index),Vector2(size.x-24,index),Color(0.65,0.5,0.37,0.055),1,true)
	var content_name := "月亮" if poem_text.contains("月") else "树林" if poem_text.contains("树") or poem_text.contains("林") else "山景"
	var image := ArtLibrary.semantic_texture(content_name, "content")
	if image != null:
		draw_texture_rect(image,Rect2(size.x-185,18,160,160),false,Color(0.7,0.58,0.78,0.18))
	var hills := PackedVector2Array([Vector2(0,size.y),Vector2(0,size.y-60),Vector2(size.x*0.25,size.y-130),Vector2(size.x*0.45,size.y-50),Vector2(size.x*0.7,size.y-100),Vector2(size.x,size.y-30),Vector2(size.x,size.y)])
	draw_colored_polygon(hills,Color(0.48,0.37,0.61,0.06))
