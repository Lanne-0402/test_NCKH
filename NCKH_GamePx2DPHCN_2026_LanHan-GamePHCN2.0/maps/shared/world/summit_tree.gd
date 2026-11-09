@tool
extends Node2D
const TREE = preload("res://assets/map_4/goal/summit_tree.png")
func _draw() -> void:
	draw_texture_rect(TREE,Rect2(0,-224,160,224),false)
