@tool
extends Node2D
## Decoration only, deliberately below actor/obstacle draw order.
const ROCKS = preload("res://assets/shared/environment/rocks.png")
func _draw() -> void:
	for x in [86,690,1080]:
		draw_texture_rect_region(ROCKS,Rect2(x,298,38,22),Rect2(152,0,38,22),Color("a5ae89"))
