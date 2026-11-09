@tool
extends Node2D

@export_enum("slab", "wall", "ledge", "pool") var kind := "slab"
const STONE = preload("res://assets/shared/environment/stone.png")
const GRASS = preload("res://assets/shared/environment/grass.png")
const WATER = preload("res://assets/shared/environment/water.png")
const SPIKES = preload("res://assets/shared/environment/spikes.png")
const MOSS = preload("res://assets/shared/environment/moss_boulder.png")
const LONG_ROCK = preload("res://assets/shared/environment/long_rock.png")

func _rock_border(rect: Rect2) -> void:
	# Full native rock silhouette, clipping only the final repeat.
	for x in range(int(rect.position.x),int(rect.end.x),64):
		var width := minf(64,rect.end.x-x)
		draw_texture_rect_region(LONG_ROCK,Rect2(x,rect.position.y,width,32),Rect2(0,0,width,32))


func _tiles(rect: Rect2, texture: Texture2D, tint := Color.WHITE) -> void:
	# Tile at 2x native size; crop boundary tiles instead of stretching pixels.
	for y in range(int(rect.position.y), int(rect.end.y), 32):
		for x in range(int(rect.position.x), int(rect.end.x), 32):
			var size := Vector2(minf(32, rect.end.x - x), minf(32, rect.end.y - y))
			draw_texture_rect_region(texture, Rect2(Vector2(x, y), size), Rect2(Vector2.ZERO, size / 2.0), tint)


func _draw() -> void:
	match kind:
		"slab":
			# One continuous silhouette, not a repeated rock mosaic.
			draw_texture_rect(LONG_ROCK,Rect2(-160,-160,320,160),false)
		"wall":
			_tiles(Rect2(-40, -120, 80, 240), STONE)
			for y in range(-120,120,64):
				draw_set_transform(Vector2(-20,y),PI/2)
				draw_texture_rect_region(LONG_ROCK,Rect2(0,0,48,24),Rect2(0,0,48,24))
			draw_set_transform(Vector2.ZERO)
			_rock_border(Rect2(-40,-120,80,32))
			_rock_border(Rect2(-40,88,80,32))
			for y in range(-112, 112, 32):
				draw_set_transform(Vector2(40, y), PI / 2)
				draw_texture_rect(SPIKES, Rect2(0, -32, 32, 32), false, Color(0.8, 0.85, 0.75))
			draw_set_transform(Vector2.ZERO)
		"ledge":
			_tiles(Rect2(-90, 0, 180, 48), STONE)
			_tiles(Rect2(-90, 0, 180, 16), GRASS)
			# Dress the underside without changing the 180x18 collider/foot plane.
			# Repeated boulders removed to keep step boundaries readable.
		"pool":
			_tiles(Rect2(288, 288, 576, 80), STONE)
			for x in range(320, 832, 64):
				draw_texture_rect(WATER, Rect2(x, 292, 64, 32), false, Color(0.7, 1, 0.95))
			_tiles(Rect2(288, 336, 576, 32), STONE)
			_rock_border(Rect2(288,336,576,32))
			draw_texture_rect(MOSS,Rect2(256,256,64,80),false)
			draw_texture_rect(MOSS,Rect2(832,256,64,80),false)
