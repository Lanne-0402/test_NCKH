@tool
extends Node2D

@export_range(1, 5) var map_id := 1
const SKY = preload("res://assets/shared/environment/sky.png")
const STONE = preload("res://assets/shared/environment/stone.png")
const GRASS = preload("res://assets/shared/environment/grass.png")
const ROCKS = preload("res://assets/shared/environment/rocks.png")
const MOSS = preload("res://assets/shared/environment/moss_boulder.png")


func _draw() -> void:
	# Background is broad enough for Map 4's moving camera, in world coordinates.
	var tint := Color.WHITE
	if map_id == 2:
		tint = Color(0.58, 0.67, 0.64)
	elif map_id == 3:
		tint = Color(0.69, 0.66, 0.77)
	elif map_id == 5:
		tint = Color(0.85, 1.0, 0.92)
	draw_texture_rect(SKY, Rect2(-576, -384, 2304, 1296), false, tint)
	if map_id in [2, 3]:
		for x in [-128, 1088]:
			for y in range(120, 640, 32):
				for col in range(3):
					draw_texture_rect(STONE, Rect2(x + col * 32, y, 32, 32), false, tint)
	# Remove cropped, oversized cliff repetitions while awaiting dedicated BGs.
	if map_id == 5:
		for x in range(0, 1152, 32):
			for y in range(320, 672, 32):
				draw_texture_rect(STONE, Rect2(x, y, 32, 32), false)
			draw_texture_rect(GRASS, Rect2(x, 320, 32, 32), false)
