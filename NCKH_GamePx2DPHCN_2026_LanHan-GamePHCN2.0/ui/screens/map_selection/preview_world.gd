extends Node2D
## Isolated visual demo: no session, provider, physics, input or saved progress.
const Actor = preload("res://maps/shared/characters/player/gameplay_actor.gd")
const Stone = preload("res://maps/shared/world/stone_visual.gd")
const ROCK = preload("res://assets/map_1/obstacles/rock_base.png")
const GRASS = preload("res://assets/shared/environment/grass.png")
const DIRT = preload("res://assets/shared/environment/stone.png")
const TREE = preload("res://assets/map_4/goal/summit_tree.png")
var map_id := 1
var scenery_only := false
var clock := 0.0
var background: Node2D
var actor: Node2D
var props: Array[Node2D] = []

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	background = load("res://maps/map_%d/visuals/map_%d_background.tscn" % [map_id,map_id]).instantiate()
	add_child(background)
	background.set_scrolling(false)
	background.set_process(false)
	if not scenery_only:
		actor = Actor.new()
		actor.map_id = map_id
		actor.pose_id = [3,0,4,1,2][map_id-1]
		actor.outfit_enabled = true
		actor.joints_visible = false
		actor.scale = Vector2.ONE * 2.2
		actor.z_index = 10
		add_child(actor)
		match map_id:
			1:
				var rock := Sprite2D.new()
				rock.texture = ROCK
				rock.scale = Vector2.ONE * 1.7
				add_child(rock)
				props.append(rock)
			2: _stone("slab", Vector2(576,150))
			3:
				_stone("wall", Vector2(380,205))
				_stone("wall", Vector2(772,205))
				props[1].scale.x = -1
			4:
				for i in range(4):
					_stone("ledge", Vector2(330+i*155,320-i*52))
				var tree := Sprite2D.new()
				tree.texture = TREE
				tree.scale = Vector2.ONE * 1.6
				tree.position = Vector2(845,90)
				add_child(tree)
			5: _stone("pool",Vector2.ZERO)
	reset_demo()

func _stone(kind: String, at: Vector2) -> void:
	var prop := Stone.new()
	prop.kind = kind
	prop.position = at
	add_child(prop)
	props.append(prop)

func reset_demo() -> void:
	clock = 0.0
	set_process(false)
	_pose(0.0)

func _process(delta: float) -> void:
	clock += delta
	_pose(clock)

func _pose(time: float) -> void:
	background.far_layer.position.x = -fmod(time * 18.0,1152.0)
	background.near_layer.position.x = -fmod(time * 30.0,1152.0)
	if scenery_only: return
	var cycle := fmod(time,6.0) / 6.0
	var action := (1.0 - cos(cycle * TAU)) * 0.5
	actor.amount = action
	actor.animation_clock = time
	actor.visual_active = time > 0
	actor.running = map_id == 1 and cycle < 0.4
	actor.charging = map_id == 1 and cycle >= 0.4
	actor.burst = maxf(0,1-absf(cycle-0.6)*15) if map_id == 1 else 0.0
	actor.position = Vector2(576,320)
	match map_id:
		1:
			actor.position.x = 400
			props[0].position = Vector2(lerpf(820,485,minf(cycle*2.5,1.0)),260)
			props[0].modulate.a = 1.0 - smoothstep(0.55,0.72,cycle)
			actor.position.y -= absf(sin(time*6.0))*3.0
		2:
			props[0].position = Vector2(576,188-clampf((action-0.35)/0.65,0,1)*26.4)
		3:
			props[0].position.x = 390-action*120
			props[1].position.x = 762+action*120
		4:
			var step := mini(int(cycle*4.0),2)
			var jump := clampf(fmod(cycle*4.0,1.0)*2.0-0.5,0.0,1.0)
			actor.jump_progress = jump if jump > 0 and jump < 1 else -1.0
			actor.position = Vector2(330+155*(step+jump),320-52*(step+jump)-sin(jump*PI)*65)
		5:
			actor.position = Vector2(576,336.4)
			actor.mirrored = cycle > 0.5
	actor.refresh()

func _draw() -> void:
	if map_id == 4 and not scenery_only: return
	for x in range(0,1152,32):
		for y in range(320,672,32):
			draw_texture_rect(DIRT,Rect2(x,y,32,32),false)
		draw_texture_rect(GRASS,Rect2(x,312,32,16),false)
